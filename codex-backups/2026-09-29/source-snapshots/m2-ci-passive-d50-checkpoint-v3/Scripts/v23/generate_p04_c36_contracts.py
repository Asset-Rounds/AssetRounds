"""Generate the five deterministic V23-P04-C36 tooling artifacts."""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c36_contracts as contracts


def _write_atomically(documents: dict[str, object]) -> None:
    staged: list[tuple[Path, Path]] = []
    try:
        for relative_path in (contracts.SCHEMA, contracts.CONTRACT, contracts.EVIDENCE, contracts.BRAND, contracts.MANIFEST):
            target = contracts.ROOT / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=target.parent)
            temporary = Path(temporary_name)
            with os.fdopen(descriptor, "wb") as handle:
                handle.write(contracts.pretty(documents[relative_path]))
            staged.append((target, temporary))
        for target, temporary in staged:
            os.replace(temporary, target)
    finally:
        for _, temporary in staged:
            if temporary.exists():
                temporary.unlink()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apply", action="store_true", help="write all five artifacts")
    group.add_argument("--check", action="store_true", help="check all five artifacts")
    args = parser.parse_args()
    documents = contracts.documents()
    drift = [path for path, value in documents.items() if not (contracts.ROOT / path).is_file() or (contracts.ROOT / path).read_bytes() != contracts.pretty(value)]
    if args.check:
        if drift:
            raise SystemExit("C36 artifact drift: " + ",".join(drift))
        print("C36 generator check PASS_STATIC_PROVISIONAL generated=5")
        return
    _write_atomically(documents)
    print("C36 generator apply PASS_STATIC_PROVISIONAL generated=5")


if __name__ == "__main__":
    main()
