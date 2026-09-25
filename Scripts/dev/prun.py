"""Run one unittest script's tests across parallel worker processes.

Usage (from the checkout root, Windows or macOS):
  python Scripts/dev/prun.py <tests.py> [-j N] [-c chunk] [-k substring ...] [-t seconds]
-t is the per-worker timeout (default 3600 s); a worker that exceeds it is killed
and its tests count as errors. Worker output is decoded as UTF-8 (errors replaced).
Workers are separate interpreters, so class fixtures and cwd are isolated per
worker; every test id is run exactly once and all results are aggregated.
Exit status is nonzero when any test fails, errors, or is not run.
"""
import importlib.util
import json
import os
import subprocess
import sys
import time
import unittest
from concurrent.futures import ThreadPoolExecutor

DEFAULT_WORKER_TIMEOUT = 3600.0


def load(path):
    spec = importlib.util.spec_from_file_location("prun_target", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["prun_target"] = module
    spec.loader.exec_module(module)
    return module


def ids(path):
    module = load(path)
    suite = unittest.defaultTestLoader.loadTestsFromModule(module)
    out = []

    def walk(s):
        for t in s:
            if isinstance(t, unittest.TestSuite):
                walk(t)
            else:
                out.append(t.id().split(".", 1)[1])
    walk(suite)
    return out


def worker(path, names):
    module = load(path)
    suite = unittest.TestSuite()
    for name in names:
        suite.addTest(unittest.defaultTestLoader.loadTestsFromName(name, module))
    result = unittest.TextTestRunner(verbosity=0, stream=sys.stderr).run(suite)
    print("PRUN_RESULT " + json.dumps({
        "run": result.testsRun,
        "failures": [t.id() for t, _ in result.failures],
        "errors": [t.id() for t, _ in result.errors],
        "skipped": len(result.skipped),
    }))
    return 0 if result.wasSuccessful() else 1


def main(argv):
    if argv[:1] == ["--worker"]:
        return worker(argv[1], argv[2:])
    path = argv[0]
    jobs = min(16, os.cpu_count() or 4)
    filters = []
    chunk = 2
    timeout = DEFAULT_WORKER_TIMEOUT
    rest = argv[1:]
    while rest:
        flag = rest.pop(0)
        if flag == "-j":
            jobs = int(rest.pop(0))
        elif flag == "-c":
            chunk = int(rest.pop(0))
        elif flag == "-k":
            filters.append(rest.pop(0))
        elif flag == "-t":
            timeout = float(rest.pop(0))
            if timeout <= 0:
                raise SystemExit("-t needs a positive number of seconds")
        else:
            raise SystemExit("unknown argument " + flag)
    names = ids(path)
    if filters:
        names = [n for n in names if any(f in n for f in filters)]
    # Small consecutive chunks (class locality) drained from a shared queue,
    # so one slow test cannot hold a whole precomputed share hostage.
    size = max(1, chunk)
    buckets = [names[i:i + size] for i in range(0, len(names), size)]
    started = time.time()

    def run(bucket):
        try:
            proc = subprocess.run([sys.executable, __file__, "--worker", path, *bucket],
                                  capture_output=True, text=True, encoding="utf-8", errors="replace",
                                  timeout=timeout)
        except subprocess.TimeoutExpired as expired:
            return bucket, expired
        return bucket, proc

    def text(value):
        if isinstance(value, bytes):
            return value.decode("utf-8", errors="replace")
        return value or ""

    total = {"run": 0, "failures": [], "errors": [], "skipped": 0}
    logs = []
    with ThreadPoolExecutor(min(jobs, len(buckets))) as pool:
        for bucket, proc in pool.map(run, buckets):
            if isinstance(proc, subprocess.TimeoutExpired):
                total["errors"].append("worker timed out after %.0f s: %s" % (timeout, ",".join(bucket)))
                logs.append(text(proc.stdout) + text(proc.stderr))
                continue
            summary = None
            for line in proc.stdout.splitlines():
                if line.startswith("PRUN_RESULT "):
                    summary = json.loads(line[len("PRUN_RESULT "):])
            if summary is None:
                total["errors"].append("worker crashed: " + ",".join(bucket))
                logs.append(proc.stdout + proc.stderr)
                continue
            for key in ("failures", "errors"):
                total[key] += summary[key]
            total["run"] += summary["run"]
            total["skipped"] += summary["skipped"]
            if summary["failures"] or summary["errors"]:
                logs.append(proc.stderr)
    for log in logs:
        sys.stderr.write(log)
    ok = not total["failures"] and not total["errors"] and total["run"] == len(names)
    print("PRUN_TOTAL expected=%d run=%d failures=%d errors=%d skipped=%d seconds=%.0f %s" % (
        len(names), total["run"], len(total["failures"]), len(total["errors"]),
        total["skipped"], time.time() - started, "OK" if ok else "FAILED"))
    for name in total["failures"] + total["errors"]:
        print("  " + name)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
