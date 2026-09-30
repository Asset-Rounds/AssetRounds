#!/usr/bin/env python3
"""Generate or check the three deterministic V23-P03-C09 JSON artifacts."""
from __future__ import annotations

import argparse
import base64
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
import p03_c09_contracts as contracts


def require_behavioral_swift_evidence(root: Path) -> None:
    source = (root / contracts.TEST_PATH).read_text(encoding="utf-8")
    if ".Type = SwiftDataSearchCanonicalProjectionSourceV1.self" in source:
        raise contracts.ContractError("type-reference-only SwiftData evidence is forbidden")
    required = (
        r"let productionSource = try SwiftDataSearchCanonicalProjectionSourceV1\(",
        r"let productionServices = try ProductionSearchServicesV1\(",
        r"productionSource\.searchProjectionPage\(",
        r"for index in 0\.\.<10_000 \{\s*productionContext\.insert\(Asset\(",
        r"XCTAssertEqual\(canonicalOffset, 10_000\)",
        r"XCTAssertEqual\(projectedRows, 30_000\)",
        r"productionRevisionBox\.value = try source\(revision: 8\)",
        r"collisionContext\.insert\(workflowRecord\(id: collisionID\)\)",
        r"collisionContext\.insert\(Issue\(",
        r"WorkspaceEntityIdentityV1\(kind: \.workflowRecord, id: collisionID\)\.stableKey",
        r"WorkspaceEntityIdentityV1\(kind: \.issue, id: collisionID\)\.stableKey",
        r"FixedOperationalStatusProvider\(identities:",
        r"operationalStatusProvider: staleProvider",
        r"XCTAssertEqual\(error, \.invalidContext\)",
        r"let stalePublicationToken = await reloaded\.publicationToken\(\)",
        r"publicationToken: stalePublicationToken",
        r"XCTAssertEqual\(error, \.staleMutation\)",
        r"SameRevisionDeletionRaceSource\(",
        r"try await invalidatingStore\.dropProjection\(workspaceID: revision\.workspaceID\)",
        r"let raceDiscardCount = await raceSource\.discardCount\(\)",
        r"XCTAssertEqual\(raceDiscardCount, 1\)",
        r"postDeleteProjection\.records\.map\(\\\.sourceStableID\), \[\"post-delete-survivor\"\]",
        r"rebuildStaging\(publicationToken: guardedToken\)",
        r"saveRebuildStaging\(.*publicationToken: guardedToken",
        r"clearRebuildStaging\(publicationToken: guardedToken\)",
        r"state-draft.*state-open.*state-pending.*state-incomplete.*state-recheck.*state-progress",
    )
    for pattern in required:
        if re.search(pattern, source, re.S) is None:
            raise contracts.ContractError(f"behavioral SwiftData evidence missing: {pattern}")


def main() -> int:
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--apply", action="store_true")
    modes.add_argument("--check", action="store_true")
    modes.add_argument("--dump-json", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--root", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    root = args.root.resolve() if args.root else Path(__file__).resolve().parents[2]
    try:
        require_behavioral_swift_evidence(root)
        outputs = contracts.all_outputs(root)
        if set(outputs) != set(contracts.GENERATED_PATHS) or len(outputs) != 3:
            raise contracts.ContractError("exact three-output inventory differs")
        if args.dump_json:
            print(json.dumps({path: base64.b64encode(raw).decode("ascii")
                              for path, raw in sorted(outputs.items())},
                             sort_keys=True, separators=(",", ":")))
            return 0
        stale = []
        for relative, expected in outputs.items():
            target = root / relative
            if args.apply:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(expected)
            elif not target.is_file() or target.read_bytes() != expected:
                stale.append(relative)
        if stale:
            raise contracts.ContractError(f"stale generated artifacts: {stale}")
    except (contracts.ContractError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P03-C09 generation failed: {error}", file=sys.stderr)
        return 1
    print(f"V23-P03-C09 {'generated' if args.apply else 'verified'} 3 deterministic artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
