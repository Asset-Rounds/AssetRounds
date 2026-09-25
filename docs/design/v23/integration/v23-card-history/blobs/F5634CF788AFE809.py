#!/usr/bin/env python3
"""Fail-closed CLI for the provisional V23 controller."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from controller_contracts import (
    CapacityEvidence,
    ControllerSelection,
    canonical_bytes,
    canonical_digest,
    evaluate_admission,
    parse_timestamp,
)


def read_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected JSON object: {path}")
    return value


def atomic_write(path: Path, value: Any) -> None:
    payload = json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--selection", type=Path, required=True)
    validate.add_argument("--capacity", type=Path, required=True)

    evaluate = subparsers.add_parser("evaluate")
    evaluate.add_argument("--selection", type=Path, required=True)
    evaluate.add_argument("--capacity", type=Path, required=True)
    evaluate.add_argument("--observed-at", required=True)
    evaluate.add_argument("--output", type=Path, required=True)

    digest = subparsers.add_parser("digest")
    digest.add_argument("--input", type=Path, required=True)

    args = parser.parse_args()
    if args.command == "digest":
        value = read_object(args.input)
        print(canonical_digest(value))
        return 0

    selection_value = read_object(args.selection)
    capacity_value = read_object(args.capacity)
    selection = ControllerSelection.parse(selection_value)
    capacity = CapacityEvidence.parse(capacity_value)
    if args.command == "validate":
        print(
            json.dumps(
                {
                    "result": "PASS",
                    "selectionDigest": canonical_digest(selection_value),
                    "capacityDigest": canonical_digest(capacity_value),
                    "acceptanceCredit": False,
                    "releaseCredit": False,
                },
                indent=2,
            )
        )
        return 0

    observed_at = parse_timestamp(args.observed_at, "observed-at")
    decision = evaluate_admission(selection, capacity, now=observed_at)
    atomic_write(args.output, decision)
    print(canonical_bytes(decision).decode("utf-8"), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
