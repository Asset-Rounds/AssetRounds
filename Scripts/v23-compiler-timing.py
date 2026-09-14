#!/usr/bin/env python3
"""Observe one source-pinned hosted build. Instrumented results are diagnostic only.

The existing shell watchdog owns timeouts and process-group termination. This
helper does not dispatch, retry, cache, select tests, or claim native acceptance.
"""
import datetime
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import queue
import re
import signal
import subprocess
import sys
import threading
import time


CONTRACT = "v23.integration.current-native.v1"
SOURCE_HEAD = "f6f99acec0c6ab5b5defb80b21607bde0ef5caaf"
SOURCE_PATHS = ("FieldEvidenceApp", "FieldEvidenceAppTests", "FieldEvidenceAppUITests",
                "FieldEvidenceApp.xcodeproj")
SOURCE_TREES = {
    "FieldEvidenceApp": "3e93cb3c625cc268a045fe8320e703cc798b53b7",
    "FieldEvidenceAppTests": "f90f0b7e6c5719816e5487d54eee32edbc5a4bbc",
    "FieldEvidenceAppUITests": "978eced2587c6ed6cb280aa6cea7d4e3fa6e4190",
    "FieldEvidenceApp.xcodeproj": "4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0",
}
SOURCE_SELECTION_HASHES = {
    "selectionSHA256": "E1704C9587E7C9661D4E032BD380AC44A2CC79E2BF066DF2162428D08D8C0B7A",
    "selectionMapSHA256": "09208F042EBAD8B82E09FB90973D9626DAE54FAB026E411632FE91D9B54726E8",
    "resolvedSelectionSHA256": "428CF8C679E28D87B3CB7BD2DC42B191F02A9DB4322D9882E3DF72521179F9B1",
}
SWIFT_FLAGS = ("OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -warn-long-function-bodies=500"
               " -Xfrontend -warn-long-expression-type-checking=200")
COMPILERS = {"xcodebuild", "swiftc", "swift-frontend", "clang", "clang++", "ld",
             "actool", "ibtool", "assetcatalogcompiler"}
PS_FIELDS = "pid=,ppid=,pcpu=,time=,etime=,rss=,state=,lstart=,comm="
DEVELOPER_DIR = "/Applications/Xcode_26.6.app/Contents/Developer"
CAPABILITY_TIMEOUT_SECONDS = 10
CAPABILITY_FLAGS = (b"-warn-long-function-bodies", b"-warn-long-expression-type-checking")


def require(condition, message):
    if not condition:
        raise ValueError("compiler timing admission: " + message)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def read_configuration(path):
    require(path.is_file() and not path.is_symlink(), "configuration file")
    config = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)
    return validate_configuration(config)


def validate_configuration(config):
    require(isinstance(config, dict), "configuration object")
    require(set(config) == {"schemaVersion", "mode", "sourceHead", "sourceTrees",
                            "selectionSHA256", "selectionMapSHA256", "resolvedSelectionSHA256",
                            "sampleIntervalSeconds"}, "configuration keys")
    require(type(config["schemaVersion"]) is int and config["schemaVersion"] == 1, "schema")
    require(config["mode"] == "timing-f6-source-v1", "diagnostic mode")
    require(config["sourceHead"] == SOURCE_HEAD, "source provenance")
    require(isinstance(config["sourceTrees"], dict)
            and set(config["sourceTrees"]) == set(SOURCE_PATHS), "source tree roles")
    require(all(isinstance(v, str) and re.fullmatch(r"[a-f0-9]{40}", v)
                for v in config["sourceTrees"].values()), "source tree identities")
    for key in ("selectionSHA256", "selectionMapSHA256", "resolvedSelectionSHA256"):
        require(isinstance(config[key], str)
                and re.fullmatch(r"[A-F0-9]{64}", config[key]), "selection hash")
    require(type(config["sampleIntervalSeconds"]) is int
            and config["sampleIntervalSeconds"] == 5, "sample interval")
    # Configuration is a receipt of these reviewed f6 values, not an authority
    # that can rebind the experiment to different product or selector bytes.
    require(config["sourceTrees"] == SOURCE_TREES, "fixed f6 source trees")
    require(all(config[key] == value for key, value in SOURCE_SELECTION_HASHES.items()),
            "fixed f6 selector hashes")
    return config


def expected_command(environment):
    e = environment
    for key in ("PROJECT_PATH", "SCHEME", "CONFIGURATION", "CI_SIMULATOR_UDID",
                "CI_DESTINATION", "RUNNER_TEMP", "CI_ARTIFACT_DIR"):
        require(e.get(key) and not any(c in e[key] for c in ("\n", "\r", "\0")), key)
    require(e["PROJECT_PATH"] == "FieldEvidenceApp.xcodeproj"
            and e["SCHEME"] == "FieldEvidenceApp" and e["CONFIGURATION"] == "Debug", "project")
    require(re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}",
                         e["CI_SIMULATOR_UDID"]), "Simulator identity")
    require(e["CI_DESTINATION"] == "platform=iOS Simulator,id=" + e["CI_SIMULATOR_UDID"],
            "destination")
    return ["xcodebuild", "-project", e["PROJECT_PATH"], "-scheme", e["SCHEME"],
            "-configuration", e["CONFIGURATION"], "-destination", e["CI_DESTINATION"],
            "-derivedDataPath", e["RUNNER_TEMP"] + "/FieldEvidenceDerivedData",
            "-resultBundlePath", e["CI_ARTIFACT_DIR"] + "/Build.xcresult",
            "CODE_SIGNING_ALLOWED=NO", "build-for-testing"]


def admit(config, environment, command, root, git_output, platform=sys.platform):
    validate_configuration(config)
    required = {
        "CI_NATIVE_ACCEPTANCE_CONTRACT": CONTRACT,
        "GITHUB_REPOSITORY": "Asset-Rounds/AssetRounds",
        "GITHUB_REF": "refs/heads/codex/v23-s10-integration-20260910",
        "CI_RUNNER_PROVIDER": "github", "CI_RUNNER_LABEL": "macos-26",
        "NATIVE_SELECTION_ID": "catalog-file-authority",
        "CI_TASK_ID": "V23-INTEGRATION-20260910", "CI_TIER": "N8",
        "CI_SETUP_ARTIFACT_TIMEOUT_SECONDS": "300",
        "CI_BUILD_TIMEOUT_SECONDS": "1200", "CI_TEST_TIMEOUT_SECONDS": "900",
        "CI_UI_TIMEOUT_SECONDS": "0", "CI_TOTAL_BUDGET_SECONDS": "2400",
        "CI_RUN_UI_SMOKE": "false", "CI_SELECTOR_RUN_UI_SMOKE": "false",
        "CODE_SIGNING_ALLOWED": "NO", "RUNNER_ARCH": "ARM64",
        "DEVELOPER_DIR": DEVELOPER_DIR,
    }
    require(platform == "darwin", "host platform")
    for key, value in required.items():
        require(environment.get(key) == value, key)
    require(command == expected_command(environment), "exact base build argv")
    head = git_output("rev-parse", "HEAD").decode().strip()
    require(re.fullmatch(r"[a-f0-9]{40}", head)
            and head == environment.get("GITHUB_SHA"), "actual checkout head")
    for path, tree in config["sourceTrees"].items():
        require(git_output("rev-parse", "HEAD:" + path).decode().strip() == tree, path + " tree")
    # Synchronized groups would also compile untracked files. Check both tracked
    # changes and additional files in every pinned source root before building.
    require(not git_output("diff", "HEAD", "--", *SOURCE_PATHS).strip(), "dirty tracked source")
    require(not git_output("ls-files", "--others", "--exclude-standard", "--",
                           *SOURCE_PATHS).strip(), "untracked source")
    selected = (root / "Scripts/ci-selection.json").read_bytes()
    require(hashlib.sha256(selected).hexdigest().upper() == config["selectionSHA256"],
            "selector source bytes")
    mapping = (root / "Scripts/ci-selection-map.json").read_bytes()
    require(hashlib.sha256(mapping).hexdigest().upper() == config["selectionMapSHA256"],
            "selector map source bytes")
    resolved_path = Path(environment["CI_ARTIFACT_DIR"]) / "ci-selection.selected.json"
    require(environment.get("CI_SELECTION_PATH") == str(resolved_path), "resolved selection path")
    require(hashlib.sha256(resolved_path.read_bytes()).hexdigest().upper()
            == config["resolvedSelectionSHA256"]
            == environment.get("DISPATCH_NATIVE_SELECTION_SHA256"), "resolved selection bytes")
    require(not (Path(environment["RUNNER_TEMP"]) / "FieldEvidenceDerivedData/Build").exists(),
            "fresh DerivedData")
    return head


def diagnostic_command(command):
    require(command[-1] == "build-for-testing", "build action")
    return command[:-1] + ["-showBuildTimingSummary", SWIFT_FLAGS, command[-1]]


def parse_processes(raw):
    """Keep only compiler metadata; never retain unrelated process arguments.

    lstart is a stable PID-reuse discriminator. CPU time is the original ps text;
    pcpu is a decaying average, not an instantaneous core-occupancy measurement.
    """
    result, malformed = [], 0
    for line in raw.splitlines():
        if not line.strip():
            continue
        fields = line.split(None, 12)
        if len(fields) != 13:
            malformed += 1
            continue
        if PurePosixPath(fields[12]).name not in COMPILERS:
            continue
        try:
            pid, ppid, cpu, rss = int(fields[0]), int(fields[1]), float(fields[2]), int(fields[5])
            require(pid > 0 and ppid >= 0 and math.isfinite(cpu) and cpu >= 0 and rss >= 0,
                    "process values")
            require(re.fullmatch(r"\d+(?::\d+){1,2}(?:\.\d+)?", fields[3]), "CPU time")
            require(re.fullmatch(r"(?:\d+-)?\d+:\d+(?::\d+)?", fields[4]), "elapsed time")
            require(re.fullmatch(r"\d{4}", fields[11]), "process start year")
        except ValueError:
            malformed += 1
            continue
        started = " ".join(fields[7:12])
        result.append({"key": str(pid) + "@" + started, "pid": pid, "parentPID": ppid,
                       "executable": fields[12], "startedLocal": started,
                       "cpuPercentDecayingAverage": cpu, "cpuTime": fields[3],
                       "elapsedTime": fields[4], "residentKiB": rss, "state": fields[6]})
    require(len({p["key"] for p in result}) == len(result), "duplicate sampled process")
    return result, malformed


def sample_host():
    env = dict(os.environ, LC_ALL="C")
    raw = subprocess.check_output(["/bin/ps", "-axo", PS_FIELDS], env=env,
                                  timeout=2, stderr=subprocess.STDOUT).decode("utf-8", "replace")
    processes, malformed = parse_processes(raw)
    return {"logicalCPUCount": os.cpu_count(), "loadAverages": list(os.getloadavg()),
            "processes": processes, "malformedMetadataRows": malformed}


def process_commands(processes):
    if not processes:
        return {}
    expected = {p["pid"]: p for p in processes}
    result = subprocess.run(["/bin/ps", "-ww", "-p", ",".join(str(p) for p in sorted(expected)),
                             "-o", "pid=,lstart=,comm=,command="], env=dict(os.environ, LC_ALL="C"),
                            timeout=2, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # A short-lived process may disappear between the two observations. Missing
    # argv stays absent, not an empty command or a successful completion claim.
    require(result.returncode in (0, 1), "process argument observation failed")
    commands = {}
    for row in result.stdout.decode("utf-8", "replace").splitlines():
        fields = row.strip().split(None, 6)
        if len(fields) != 7 or not fields[0].isdigit() or int(fields[0]) not in expected:
            continue
        process = expected[int(fields[0])]
        if " ".join(fields[1:6]) != process["startedLocal"]:
            continue  # PID was reused between observations.
        remainder, executable = fields[6], process["executable"]
        if remainder.startswith(executable) and remainder[len(executable):].startswith((" ", "\t")):
            commands[process["key"]] = remainder[len(executable):].strip()
    return commands


class Events:
    def __init__(self, path):
        self.stream = path.open("x", encoding="utf-8", newline="\n")
        self.started = time.monotonic()

    def append(self, event, **fields):
        row = {"event": event, "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
               "elapsedSeconds": round(time.monotonic() - self.started, 6), **fields}
        self.stream.write(json.dumps(row, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n")
        self.stream.flush()
        os.fsync(self.stream.fileno())

    def close(self):
        self.stream.close()


class ProcessObservations:
    def __init__(self):
        self.active = {}

    def observe(self, sample, elapsed, commands):
        current = {p["key"]: p for p in sample["processes"]}
        first, disappeared = [], []
        for key, process in current.items():
            if key not in self.active:
                first.append({**process, "firstObservedSeconds": elapsed,
                              "psRenderedCommand": commands.get(process["key"]),
                              "commandIsExactArgv": False, "exitStatus": None})
                self.active[key] = {"firstObservedSeconds": elapsed}
            self.active[key]["lastObservedSeconds"] = elapsed
        for key in sorted(set(self.active) - set(current)):
            disappeared.append({"key": key, **self.active.pop(key),
                                "firstAbsentSeconds": elapsed, "exitStatus": None,
                                "completionProven": False})
        return first, disappeared


def capability_command(environment):
    require(environment.get("DEVELOPER_DIR") == DEVELOPER_DIR, "pinned developer directory")
    return [DEVELOPER_DIR + "/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend",
            "-help-hidden"]


def run_observed_capability(command, output, metadata, interval=5,
                            sampler=sample_host, commands_reader=process_commands,
                            timeout_seconds=CAPABILITY_TIMEOUT_SECONDS):
    """Observe one query; its deadline is independent of slow process sampling.

    Only main supplies native argv and the fixed deadline. Test callers use
    Python children. The sampler thread cannot write events or affect the child.
    """
    events = Events(output / "capability-events.jsonl")
    observations, received_signal, previous_handlers = ProcessObservations(), [], {}
    child, observer = None, None
    stopped, pending = threading.Event(), queue.Queue()
    status, code, timed_out, flags_admitted = "error", None, False, False
    launched = None

    def relay(signum, _frame):
        received_signal.append(signum)
        if child is not None and child.poll() is None:
            child.send_signal(signum)

    def observe():
        while not stopped.is_set():
            start = time.monotonic()
            try:
                sample = sampler()
                commands = commands_reader(sample["processes"])
                pending.put((start, time.monotonic(), sample, commands, None))
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                pending.put((start, time.monotonic(), None, None,
                             {"errorType": type(error).__name__, "error": str(error)}))
            stopped.wait(max(0, interval - (time.monotonic() - start)))

    def drain():
        while True:
            try:
                start, end, sample, commands, error = pending.get_nowait()
            except queue.Empty:
                return
            fields = {"sampleStartElapsedSeconds": round(start - events.started, 6),
                      "samplerSeconds": round(end - start, 6)}
            if error is not None:
                events.append("capability-observation-error", **fields, **error)
            else:
                first, disappeared = observations.observe(sample, end - events.started, commands)
                events.append("capability-sample", **fields, **sample,
                              newlyObserved=first, disappeared=disappeared)

    try:
        events.append("capability-query-request", command=command,
                      timeoutSeconds=timeout_seconds, **metadata)
        executable = Path(command[0])
        require(executable.is_file() and os.access(executable, os.X_OK),
                "frontend is not an executable file")
        identity = executable.stat()
        events.append("capability-executable", requestedPath=str(executable),
                      resolvedPath=str(executable.resolve()), bytes=identity.st_size,
                      modifiedNanoseconds=identity.st_mtime_ns)
        for name in ("SIGTERM", "SIGINT", "SIGHUP"):
            signum = getattr(signal, name, None)
            if signum is not None:
                previous_handlers[signum] = signal.signal(signum, relay)
        with (output / "swift-frontend-help.txt").open("xb") as stdout, \
                (output / "swift-frontend-help.stderr.txt").open("xb") as stderr:
            try:
                child = subprocess.Popen(command, stdout=stdout, stderr=stderr)
                launched = time.monotonic()
                deadline = launched + timeout_seconds
                events.append("capability-process", pid=child.pid,
                              launchElapsedSeconds=round(launched - events.started, 6),
                              deadlineElapsedSeconds=round(deadline - events.started, 6))
                observer = threading.Thread(target=observe, daemon=True)
                observer.start()
                while not received_signal:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        timed_out = True
                        break
                    if child.poll() is not None:
                        break
                    drain()
                    try:
                        child.wait(timeout=max(0, min(.1, deadline - time.monotonic())))
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                # Kill/reap only this owned query. Never start a retry. Sampling
                # cannot delay deadline enforcement or add a grace period.
                if child is not None:
                    if child.poll() is None:
                        child.kill()
                    code = child.wait()
                stopped.set()
                for stream in (stdout, stderr):
                    stream.flush()
                    os.fsync(stream.fileno())
        if received_signal:
            status = "interrupted"
        elif timed_out:
            status = "timeout"
        elif code != 0:
            status = "nonzero-exit"
        else:
            help_bytes = (output / "swift-frontend-help.txt").read_bytes()
            flags_admitted = all(re.search(rb"(?m)^\s*" + re.escape(flag) + rb"(?:[=\s<]|$)",
                                           help_bytes) for flag in CAPABILITY_FLAGS)
            status = "supported" if flags_admitted else "missing-required-flag"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        events.append("capability-error", errorType=type(error).__name__, error=str(error))
    finally:
        stopped.set()
        drain()
        for signum, previous in previous_handlers.items():
            signal.signal(signum, previous)
        events.append("capability-terminal-observation", status=status,
                      capabilityReturnCode=code, timedOut=timed_out,
                      queryElapsedSeconds=None if launched is None else round(time.monotonic() - launched, 6),
                      receivedSignals=received_signal, flagsAdmitted=flags_admitted,
                      samplerStillActive=observer is not None and observer.is_alive(),
                      processesWithUnobservedTerminal=observations.active,
                      nativeAcceptance=False, providerQualification=False)
        events.close()
    return 0 if status == "supported" else 65


def run_observed_build(command, output, metadata, interval=5,
                       sampler=sample_host, commands_reader=process_commands):
    events = Events(output / "events.jsonl")
    observations, child, received_signal = ProcessObservations(), None, []
    previous_handlers = {}

    def relay(signum, _frame):
        received_signal.append(signum)
        if child is not None and child.poll() is None:
            child.send_signal(signum)

    try:
        events.append("build-request", command=command, **metadata)
        for name in ("SIGTERM", "SIGINT", "SIGHUP"):
            signum = getattr(signal, name, None)
            if signum is not None:
                previous_handlers[signum] = signal.signal(signum, relay)
        child = subprocess.Popen(command)  # Original stdout/stderr and process group are inherited.
        events.append("build-process", pid=child.pid)
        while child.poll() is None and not received_signal:
            start = time.monotonic()
            next_sample_deadline = start + interval
            try:
                sample = sampler()
                elapsed = round(time.monotonic() - events.started, 6)
                new_processes = [p for p in sample["processes"] if p["key"] not in observations.active]
                commands = commands_reader(new_processes)
                first, disappeared = observations.observe(sample, elapsed, commands)
                events.append("sample", **sample, newlyObserved=first, disappeared=disappeared,
                              sampleStartElapsedSeconds=round(start - events.started, 6),
                              samplerSeconds=round(time.monotonic() - start, 6))
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                # Preserve failure without replacing the original xcodebuild result.
                events.append("observation-error", errorType=type(error).__name__, error=str(error))
            if not received_signal:
                remaining = next_sample_deadline - time.monotonic()
                if remaining < 0:
                    events.append("sampling-deadline-missed", overrunSeconds=round(-remaining, 6))
                try:
                    child.wait(timeout=max(0, next_sample_deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    pass
        if received_signal and child.poll() is None:
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass  # The existing group watchdog remains the sole hard timeout owner.
        code = child.poll()
        events.append("build-terminal-observation", buildReturnCode=code,
                      receivedSignals=received_signal,
                      processesWithUnobservedTerminal=observations.active,
                      nativeAcceptance=False, providerQualification=False)
        return (128 + received_signal[0]) if code is None else (code if code >= 0 else 128 - code)
    finally:
        for signum, previous in previous_handlers.items():
            signal.signal(signum, previous)
        events.close()


def main():
    require(len(sys.argv) > 2 and sys.argv[1] == "--", "usage: -- <original build argv>")
    root = Path.cwd()
    config_path = root / "Scripts/v23-compiler-timing.json"
    config = read_configuration(config_path)
    command = sys.argv[2:]
    git = lambda *args: subprocess.check_output(["git", *args], cwd=root)
    head = admit(config, os.environ, command, root, git)
    output = Path(os.environ["CI_ARTIFACT_DIR"]) / "v23-compiler-timing"
    output.mkdir(exist_ok=False)
    metadata = {"schemaVersion": 1, "purpose": "compiler-timing-diagnostic",
                "head": head, "productSourceHead": SOURCE_HEAD,
                "configuration": config,
                "configurationSHA256": hashlib.sha256(config_path.read_bytes()).hexdigest().upper(),
                "baseCommand": command, "nativeAcceptance": False,
                "providerQualification": False, "buildWatchdogSeconds": 1200,
                "limits": "Sampling gives first/last sightings, not per-process exit codes. CPU percent is a decaying average. Host compilers can be unrelated; bind rendered source/primary paths before attribution. Instrumentation may affect duration."}
    # This single capability query must succeed before xcodebuild. Its durable
    # request and stream files precede launch, including every failure path.
    if run_observed_capability(capability_command(os.environ), output, metadata) != 0:
        return 65
    return run_observed_build(diagnostic_command(command), output, metadata)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(65)
