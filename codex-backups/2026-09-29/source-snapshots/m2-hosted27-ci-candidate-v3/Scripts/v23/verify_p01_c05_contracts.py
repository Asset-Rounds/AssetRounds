#!/usr/bin/env python3
"""Hostile static verifier for V23-P01-C05 restore identity contracts."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from p01_c05_contracts import (
    ACTIVATION_PHASES, CARD, CONTRACT_ARTIFACT, CONTRACT_SCHEMA,
    CRASH_RECOVERY_MATRIX, FAILURE_CASES,
    FIXTURE_SCHEMA, FULL_FENCE, IDENTITY_TABLE, MANIFEST, SOURCE_SPECS,
    TOOL_PATHS, TRANSFORMATION_ARTIFACT, ContractError, all_outputs, flags,
    pretty, sha,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_canonical(root: Path, path: str) -> dict[str, Any]:
    data = (root / path).read_bytes()
    value = json.loads(data)
    require(isinstance(value, dict), f"{path}: root must be object")
    require(data == pretty(value), f"{path}: noncanonical JSON")
    return value


def verify_seal(value: dict[str, Any], path: str) -> None:
    payload = dict(value)
    observed = payload.pop("artifactDigest", None)
    require(observed == sha(pretty(payload)), f"{path}: artifactDigest mismatch")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        expected = all_outputs(root)
        for path, data in expected.items():
            require((root / path).is_file() and (root / path).read_bytes() == data, f"stale generated artifact: {path}")
        contract = load_canonical(root, CONTRACT_ARTIFACT)
        transformations = load_canonical(root, TRANSFORMATION_ARTIFACT)
        manifest = load_canonical(root, MANIFEST)
        contract_schema = load_canonical(root, CONTRACT_SCHEMA)
        fixture_schema = load_canonical(root, FIXTURE_SCHEMA)
        for value, path in ((contract, CONTRACT_ARTIFACT), (transformations, TRANSFORMATION_ARTIFACT), (manifest, MANIFEST)):
            verify_seal(value, path)
            require(value.get("cardID") == CARD, f"{path}: wrong card")
            for key, expected_flag in flags().items():
                require(value.get(key) is expected_flag, f"{path}: unsafe {key}")

        require(len(FULL_FENCE) == len(set(FULL_FENCE)) == 25, "exact 25-path fence")
        require(FULL_FENCE == [path for path, _ in SOURCE_SPECS] + TOOL_PATHS, "25-path fence ordering")
        require(contract["fullCardFence"] == manifest["fullCardFence"] == FULL_FENCE, "fence drift")
        require(manifest["pathFence"] == TOOL_PATHS and manifest["toolingPathCount"] == 8, "tool fence drift")
        require(contract["identityTable"] == transformations["identityTable"] == IDENTITY_TABLE, "identity table drift")
        require([row["mode"] for row in IDENTITY_TABLE] == ["EMPTY", "REPLACE", "CLONE", "FORK"], "restore mode order drift")
        require(all(row["sourceReplicaID"] == "PROVENANCE_ONLY_NEVER_ACTIVE" for row in IDENTITY_TABLE), "source replica reuse permitted")
        require(all("PRESERVE" in row["recordIDs"] for row in IDENTITY_TABLE), "raw record UUID preservation weakened")
        require(IDENTITY_TABLE[-1]["sourceWorkspaceLineage"] == "REQUIRED_EXPLICIT_SOURCE_WORKSPACE_LINEAGE", "fork lineage omitted")
        require(contract["protocolVersions"] == {"currentGenerationPointerWriter": 3, "currentGenerationPointerReaders": [2, 3], "restoreIntentWriter": 2, "restoreIntentReaders": [1, 2], "backupManifestWriter": 2, "backupManifestReaders": [1, 2], "legacyManifestV1Retained": True, "unknownVersionDisposition": "FAIL_CLOSED"}, "protocol versions weakened")
        require(contract["activationPhases"] == ACTIVATION_PHASES, "activation phase drift")
        require(contract["crashRecoveryMatrix"] == CRASH_RECOVERY_MATRIX and len(CRASH_RECOVERY_MATRIX) == len(ACTIVATION_PHASES), "crash recovery phase coverage drift")
        require(contract["reconciliation"] == {"relaunch": "INTENT_POINTER_AND_GENERATION_IDENTITY_EXACT", "secondLaunch": "NO_PENDING_INTENT_ACTIVE_POINTER_V3_IDENTICAL", "export": "MANIFEST_V2_SOURCE_IDENTITY_MATCHES_ACTIVE_POINTER_V3", "mismatchDisposition": "FAIL_CLOSED_FORWARD_FIX_REQUIRED_NO_SUCCESS_RECEIPT"}, "relaunch/export reconciliation weakened")
        require([row["failure"] for row in contract["failureRecovery"]] == [row[0] for row in FAILURE_CASES], "failure matrix drift")
        collision = contract["collisionPolicy"]
        require(collision["identityPlanFrozenBeforeCanonicalWrite"] is True and collision["retryReusesFrozenIdentityPlan"] is True and collision["rawRecordUUIDRemapping"] is False and collision["immutableEmbeddedRecordIDsPreserved"] is True and collision["silentRewrite"] is False, "collision policy weakened")
        require(contract["lifecycle"]["downgradePolicy"] == "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION", "downgrade weakened")

        bindings = contract["sourceBindings"]
        require([row["path"] for row in bindings] == [path for path, _ in SOURCE_SPECS], "source binding order drift")
        for row, (path, symbols) in zip(bindings, SOURCE_SPECS):
            data = (root / path).read_bytes()
            text = data.decode("utf-8")
            require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"{path}: source digest drift")
            require(row["requiredSymbols"] == symbols and all(symbol in text for symbol in symbols), f"{path}: required symbols drift")
        identity_source = (root / SOURCE_SPECS[0][0]).read_text(encoding="utf-8")
        require(identity_source.count("recordDisposition = .preserve") == 4, "every mode must preserve raw record UUIDs")
        require("forkRecordIDMap" not in identity_source and "recordIdentityDisposition: .rebind" not in identity_source, "raw fork UUID remapping reintroduced")
        intent_source = (root / SOURCE_SPECS[1][0]).read_text(encoding="utf-8")
        require("Set(value.targetPointer.knownReplicaIDs).isSuperset" in intent_source, "common V2 history superset validation omitted")
        for source_index in (5, 6):
            archive_source = (root / SOURCE_SPECS[source_index][0]).read_text(encoding="utf-8")
            require("workspaceID != zero" in archive_source and "replicaID != zero" in archive_source, f"{SOURCE_SPECS[source_index][0]}: nonzero archive identity validation omitted")
        restore_source = (root / SOURCE_SPECS[7][0]).read_text(encoding="utf-8")
        ordered_cleanup = restore_source.find("removePreparedRestoreManifestBeforeDiscard")
        staged_removal = restore_source.find("removeRestoreStagingGeneration", ordered_cleanup)
        require(ordered_cleanup >= 0 and staged_removal > ordered_cleanup and "removePreparedRestoreGenerationManifestBeforeDiscard" in restore_source, "manifest-first discard ordering omitted")
        require("requireInstalledRestoreGenerationSnapshot" in restore_source, "installed generation snapshot reproof omitted")
        require(".prepareStreaming()" in restore_source, "postpublication schema-V2 export reconciliation omitted")
        require(all(symbol in restore_source for symbol in ("unavailableWorkspaces.formUnion", "unavailableReplicas.formUnion", "destinationWorkspaceID", "destinationOwnedForRestore", "for _ in 0..<16")), "bounded cross-role identity retry omitted")

        fixture_path = SOURCE_SPECS[-1][0]
        fixture_data = (root / fixture_path).read_bytes()
        fixture = json.loads(fixture_data)
        require(transformations["fixtureBinding"] == {"path": fixture_path, "bytes": len(fixture_data), "sha256": sha(fixture_data)}, "fixture binding drift")
        require(isinstance(fixture, dict) and fixture.get("schemaVersion") in {1, 2}, "fixture schema version drift")
        fixture_cases = fixture.get("cases")
        require(isinstance(fixture_cases, list) and fixture_cases, "fixture cases absent")
        require(len({row.get("id") for row in fixture_cases}) == len(fixture_cases), "fixture case IDs duplicate")
        fixture_text = fixture_data.decode("utf-8")
        require(all(mode.lower() in fixture_text.lower() for mode in ("EMPTY", "REPLACE", "CLONE", "FORK")), "fixture mode coverage incomplete")

        cases = transformations["cases"]
        require(transformations["coverage"]["caseCount"] == len(cases), "manifest case count drift")
        require({row["family"] for row in cases} == {"G01", "A01", "H01", "I01", "R01"}, "evidence families incomplete")
        require(sum(row["id"].endswith("SOURCE_REPLICA_REUSE") for row in cases) == 4, "source replica rejection not covered in every mode")
        require(all(transformations["coverage"][key] is True for key in ("pointerV3", "intentV2", "manifestV1Read", "manifestV2ReadWrite", "collision", "crashEveryPhase", "secondLaunch", "exportReconciliation")), "coverage weakened")

        rows = manifest["artifacts"]
        require([row["path"] for row in rows] == TOOL_PATHS[:-1], "manifest artifact order drift")
        for row in rows:
            data = (root / row["path"]).read_bytes()
            require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"{row['path']}: artifact digest drift")
        require(manifest["artifactSetDigest"] == sha(pretty(rows)), "artifact-set digest drift")
        require(manifest["artifactCount"] == 7 and manifest["sourceBindingCount"] == 17 and manifest["sourceBindingComplete"] is True, "manifest counts drift")
        require(contract_schema["properties"]["fullCardFence"]["minItems"] == 25, "contract schema fence weakened")
        require(fixture_schema["properties"]["identityTable"]["const"] == IDENTITY_TABLE, "fixture schema table drift")
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print(f"V23-P01-C05 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P01-C05 static contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
