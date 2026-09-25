#!/usr/bin/env python3
"""Build a v23-coverage-timings.v1 file from shared-coverage consumer logs.

  python3 Scripts/dev/v23-coverage-timings.py --run-id ID --head SHA \
      --partitions Scripts/v23-coverage-partitions.json --output Scripts/v23-coverage-timings.json LOG...

Each LOG is one consumer job log (GitHub timestamped lines). A method's seconds is
the largest single attempt reported by "Test Case '-[FieldEvidenceAppTests.C m]'
passed|failed|skipped (N seconds)". A method that started but never finished
(the partition hit its test timeout, or the runner restarted after a crash) gets
the elapsed time from its start to the interruption as a lower bound. Methods
that never started are left out, so the partition generator keeps its previous
estimate for them. Only methods listed in PARTITIONS are recorded. Development
evidence only; no network, dispatch or Git mutation.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import sys

LINE = re.compile(r"^\ufeff?(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d+))?Z (.*)$")
CASE = re.compile(r"^Test Case '-\[FieldEvidenceAppTests\.([A-Za-z_][A-Za-z0-9_]*) (test[A-Za-z0-9_]*)\]' "
                  r"(?:(started)\.|(?:passed|failed|skipped) \(([0-9]+(?:\.[0-9]+)?) seconds\)\.)$")
INTERRUPTIONS = ("Restarting after unexpected exit, crash, or test timeout", "** BUILD INTERRUPTED **",
                 "##[error]Process completed with exit code 124.")
DEFAULT_SECONDS = 60.0


def timestamp(match):
    fraction = (match.group(2) or "0")[:6].ljust(6, "0")
    return datetime.datetime.fromisoformat(match.group(1)).timestamp() + int(fraction) / 1e6


def parse(path, seconds, lower_bounds):
    running = None
    for raw in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        line = LINE.match(raw)
        if line is None:
            continue
        text = line.group(3)
        case = CASE.match(text)
        if case is not None:
            key = "FieldEvidenceAppTests/%s/%s" % (case.group(1), case.group(2))
            if case.group(3):
                running = (key, timestamp(line))
            else:
                seconds[key] = max(seconds.get(key, 0.0), float(case.group(4)))
                running = None
        elif running is not None and text.startswith(INTERRUPTIONS):
            key, started = running
            elapsed = max(timestamp(line) - started, 0.0)
            lower_bounds[key] = max(lower_bounds.get(key, 0.0), elapsed)
            running = None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--partitions", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args(argv)
    if re.fullmatch(r"[0-9a-f]{40}", args.head) is None or re.fullmatch(r"[0-9]+", args.run_id) is None:
        raise SystemExit("v23 coverage timings: --head must be a full commit and --run-id numeric")
    known = {selector for partition in json.loads(Path(args.partitions).read_text(encoding="utf-8"))["partitions"]
             for selector in partition["selectors"]}
    seconds, lower_bounds = {}, {}
    for path in sorted(args.logs):
        parse(path, seconds, lower_bounds)
    merged = dict(seconds)
    for key, value in lower_bounds.items():
        merged[key] = max(merged.get(key, 0.0), value)
    unknown = sorted(set(merged) - known)
    recorded = {key: round(merged[key], 3) for key in sorted(merged) if key in known}
    value = {
        "schema": "v23-coverage-timings.v1",
        "defaultSeconds": DEFAULT_SECONDS,
        "seconds": recorded,
        "provenance": {
            "runID": args.run_id, "head": args.head, "developmentOnly": True,
            "logs": sorted(Path(path).name for path in args.logs),
            "rule": "largest single attempt per method; unfinished (timeout or crash restart) methods "
                    "record elapsed-to-interruption as a lower bound; never-started methods are omitted",
            "measuredMethods": len(recorded),
            "lowerBoundMethods": sorted(key for key in lower_bounds if key in known),
            "unknownMethodsDropped": len(unknown),
        },
    }
    raw = (json.dumps(value, indent=2, ensure_ascii=True) + "\n").encode("ascii")
    output = Path(args.output)
    temporary = output.with_name(output.name + ".partial")
    temporary.write_bytes(raw)
    os.replace(temporary, output)
    print("%s %d methods (%d lower bounds, %d unknown dropped)" % (
        output, len(recorded), len(value["provenance"]["lowerBoundMethods"]), len(unknown)))


if __name__ == "__main__":
    sys.exit(main())
