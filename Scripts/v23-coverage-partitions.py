#!/usr/bin/env python3
"""Regenerate Scripts/v23-coverage-partitions.json deterministically for one checkout.

  python3 Scripts/v23-coverage-partitions.py --source SOURCE.json [--timings TIMINGS.json]
      [--checkout ROOT] --output Scripts/v23-coverage-partitions.json

SOURCE is either the coverage census (schema v23-coverage-partitions-shared.v1) or a
previous checked-in partitions file (schema v23-coverage-partitions.v1). TIMINGS is
optional: {"schema": "v23-coverage-timings.v1", "defaultSeconds": N,
"seconds": {"FieldEvidenceAppTests/Class/testMethod": N}}.

The output records sourceCensusHead (the commit whose census seeded the
assignments and estimates, carried over from SOURCE) and generatedAtHead (the
checkout's HEAD commit when this regeneration ran). For one checkout HEAD and
working tree the output is deterministic.

Existing assignments are kept. Methods no longer present at the checkout are
dropped (and empty partitions removed). A new method joins the partition that
already owns its class; a new class joins the least-loaded partition that stays
within the packing target, otherwise it opens a new partition. The result is
validated by the same admission code the workflow runs (disjoint, at most 60
partitions, union equal to every runnable method) before it is written.
No network, dispatch or Git mutation.
"""
import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys

TARGET_SECONDS = 2400.0
DEFAULT_SECONDS = 60.0
CENSUS_SCHEMA = "v23-coverage-partitions-shared.v1"
TIMINGS_SCHEMA = "v23-coverage-timings.v1"


def fail(message):
    raise SystemExit("v23 coverage partitions: " + message)


def load_native(root):
    spec = importlib.util.spec_from_file_location("v23_native_ci", root / "Scripts/v23-native-ci.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_json(native, path):
    try:
        return json.loads(Path(path).read_bytes().decode("utf-8"), object_pairs_hook=native.unique_pairs)
    except (OSError, UnicodeDecodeError, ValueError) as error:
        fail("unreadable JSON %s: %s" % (path, error))


def number(value, label):
    if type(value) not in (int, float) or not math.isfinite(value) or value < 0:
        fail("invalid seconds for " + label)
    return float(value)


def source_partitions(native, value):
    """Return (source census head, [(id, selectors, estimate)], sweep order)."""
    if not isinstance(value, dict):
        fail("source must be an object")
    if value.get("schema") == CENSUS_SCHEMA:
        head = value.get("head")
        partitions = [(item["id"], list(item["selectors"]), number(item["estimatedSeconds"], item["id"]))
                      for item in value["partitions"]]
        order = [item["id"] for item in sorted(value["sweepOrder"], key=lambda row: row["rank"])]
    elif value.get("schema") == native.SHARED_PARTITIONS_SCHEMA:
        head = value.get("sourceCensusHead")
        partitions = [(item["id"], list(item["selectors"]), number(item["estimatedSeconds"], item["id"]))
                      for item in value["partitions"]]
        order = list(value["sweepOrder"])
    else:
        fail("unknown source schema")
    ids = [item[0] for item in partitions]
    if len(ids) != len(set(ids)) or sorted(order) != sorted(ids):
        fail("source partition IDs and sweep order disagree")
    return head, partitions, order


def method_key(selector):
    _, class_name, method = selector.split("/")
    return class_name, method


def checkout_head(root):
    """The checkout's HEAD commit, which the regenerated file records as generatedAtHead."""
    try:
        head = subprocess.check_output(["git", "rev-parse", "--verify", "HEAD^{commit}"], cwd=root,
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        fail("cannot read the checkout HEAD: %s" % error)
    if re.fullmatch(r"[0-9a-f]{40}", head) is None:
        fail("unexpected checkout HEAD: " + head)
    return head


def regenerate(native, root, source, generated_at_head, timings=None):
    head, partitions, order = source_partitions(native, source)
    discovered = native.discover_unit_test_methods(root)
    present = set(discovered)
    known = {}
    default = DEFAULT_SECONDS
    if timings is not None:
        if not isinstance(timings, dict) or set(timings) != {"schema", "defaultSeconds", "seconds"} \
                or timings["schema"] != TIMINGS_SCHEMA or not isinstance(timings["seconds"], dict):
            fail("invalid timings JSON")
        default = number(timings["defaultSeconds"], "defaultSeconds")
        known = {key: number(value, key) for key, value in timings["seconds"].items()}
    estimate = {}
    for _, selectors, seconds in partitions:
        for selector in selectors:
            estimate[selector] = known.get(selector, seconds / len(selectors))
    rows = []
    owner_by_class = {}
    for identifier, selectors, _ in partitions:
        kept = [selector for selector in selectors if selector in present]
        if kept:
            rows.append({"id": identifier, "selectors": kept})
            for selector in kept:
                owner_by_class.setdefault(method_key(selector)[0], identifier)
    order = [identifier for identifier in order if any(row["id"] == identifier for row in rows)]
    assigned = {selector for row in rows for selector in row["selectors"]}
    new = sorted((selector for selector in discovered if selector not in assigned), key=method_key)
    by_id = {row["id"]: row for row in rows}

    def load(row):
        return sum(estimate.get(selector, known.get(selector, default)) for selector in row["selectors"])

    new_classes = {}
    for selector in new:
        new_classes.setdefault(method_key(selector)[0], []).append(selector)
    for class_name in sorted(new_classes):
        members = new_classes[class_name]
        cost = sum(known.get(selector, default) for selector in members)
        for selector in members:
            estimate[selector] = known.get(selector, default)
        target = owner_by_class.get(class_name)
        if target is None:
            candidates = sorted((load(row), row["id"]) for row in rows
                                if load(row) + cost <= TARGET_SECONDS
                                and len(row["selectors"]) + len(members) <= native.SHARED_MAX_PARTITION_METHODS)
            if candidates:
                target = candidates[0][1]
            else:
                used = {row["id"] for row in rows}
                free = [("S%02d" % index) for index in range(1, 100) if "S%02d" % index not in used]
                if not free:
                    fail("no free partition ID")
                target = free[0]
                by_id[target] = {"id": target, "selectors": []}
                rows.append(by_id[target])
                order.append(target)
            owner_by_class[class_name] = target
        by_id[target]["selectors"].extend(members)
    partitions_out = []
    for row in sorted(rows, key=lambda item: item["id"]):
        selectors = sorted(row["selectors"], key=method_key)
        seconds = round(max(sum(estimate[selector] for selector in selectors), 0.1), 1)
        partitions_out.append({"id": row["id"], "estimatedSeconds": seconds, "selectors": selectors})
    value = {"schema": native.SHARED_PARTITIONS_SCHEMA, "sourceCensusHead": head,
             "generatedAtHead": generated_at_head, "sweepOrder": order, "partitions": partitions_out}
    try:
        native.validate_coverage_partitions(value, discovered)
    except ValueError as error:
        fail(str(error))
    return value


def encode(value):
    return (json.dumps(value, indent=2, ensure_ascii=True) + "\n").encode("ascii")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", required=True)
    parser.add_argument("--timings")
    parser.add_argument("--checkout", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)
    root = Path(args.checkout).resolve()
    native = load_native(root)
    source = read_json(native, args.source)
    timings = read_json(native, args.timings) if args.timings else None
    raw = encode(regenerate(native, root, source, checkout_head(root), timings))
    output = Path(args.output)
    temporary = output.with_name(output.name + ".partial")
    if temporary.exists():
        fail("temporary output exists: " + str(temporary))
    temporary.write_bytes(raw)
    os.replace(temporary, output)
    print("%s %d bytes" % (output, len(raw)))


if __name__ == "__main__":
    sys.exit(main())
