#!/usr/bin/env python3
"""Verify C06 static platform scope and hostile mutations."""

from __future__ import annotations
import copy
import json
import os
import subprocess
import sys
from pathlib import Path
from c07_contracts import sha256_bytes
from c06_contracts import (ARTIFACT_PATH, CARD_ID, FENCED_PATHS, INFO_PATH, INFO_STRINGS_PATH,
    INHERITED_CONTRACTS, MANIFEST_PATH, SCHEMA_PATH, ContractError, build_manifest,
    build_outputs, pretty_bytes, validate_semantics)
from verify_c07_contracts import validate_schema, verify_digest

def load(path: Path): return json.loads(path.read_text(encoding="utf-8"))

def reject(fn) -> None:
    try: fn()
    except (ContractError, ValueError): return
    raise ContractError("hostile C06 mutation did not fail")

def main() -> int:
    root = Path(__file__).resolve().parents[2]
    checks = 0
    for relative, expected in build_outputs(root).items():
        if not (root / relative).is_file() or (root / relative).read_bytes() != pretty_bytes(expected):
            raise ContractError(f"generated C06 output differs: {relative}")
        checks += 1
    schema, artifact = load(root / SCHEMA_PATH), load(root / ARTIFACT_PATH)
    validate_schema(artifact, schema); verify_digest(artifact); validate_semantics(artifact); checks += 3
    if (len(artifact["targetConfigurationMatrix"]) != 6
            or len(artifact["inheritedContractClosure"]) != 25
            or len(artifact["deferredEvidence"]) != 25):
        raise ContractError("C06 matrix, contract, or deferred-evidence cardinality differs")
    if [r["contract"] for r in artifact["inheritedContractClosure"]] != INHERITED_CONTRACTS:
        raise ContractError("C06 inherited contract order differs")
    checks += 2
    for mutation in ("family", "orientation", "contract", "privacy", "overclaim"):
        hostile = copy.deepcopy(artifact)
        if mutation == "family": hostile["requiredArchiveUIDeviceFamily"] = [1, 2]
        elif mutation == "orientation": hostile["selectedOrientations"].append("PORTRAIT_UPSIDE_DOWN")
        elif mutation == "contract": hostile["inheritedContractClosure"].pop()
        elif mutation == "privacy": hostile["sourceInventory"]["privacyManifestCount"] = 2
        else: hostile["releaseReady"] = True
        reject(lambda value=hostile: validate_semantics(value))
        checks += 1
    hostile_mutations = []
    supported = copy.deepcopy(artifact)
    supported["targetConfigurationMatrix"][0]["supportedPlatforms"].append("macosx")
    hostile_mutations.append(supported)
    privacy_reason = copy.deepcopy(artifact)
    privacy_reason["sourceInventory"]["privacyFacts"]["requiredReasonAPIs"][0]["reasons"] = ["UNKNOWN.1"]
    hostile_mutations.append(privacy_reason)
    dependency = copy.deepcopy(artifact)
    dependency["sourceInventory"]["dependencyInventory"]["nonAppleImportedModules"] = ["UnknownSDK"]
    hostile_mutations.append(dependency)
    duplicate_sync = copy.deepcopy(artifact)
    duplicate_sync["sourceInventory"]["commerceInventory"]["appStoreSyncCalls"][0]["count"] = 2
    hostile_mutations.append(duplicate_sync)
    owner_fact = copy.deepcopy(artifact)
    owner_fact["platformFacts"]["macAvailability"] = "AVAILABLE"
    hostile_mutations.append(owner_fact)
    false_pass = copy.deepcopy(artifact)
    false_pass["deferredEvidence"][0]["status"] = "PASS"
    hostile_mutations.append(false_pass)
    release_hook = copy.deepcopy(artifact)
    release_hook["releaseTestSupportBlocker"]["releaseAbsenceSatisfied"] = True
    hostile_mutations.append(release_hook)
    stale_prerequisite = copy.deepcopy(artifact)
    stale_prerequisite["prerequisiteBindings"]["C12ToolingManifestDigest"] = "0" * 64
    hostile_mutations.append(stale_prerequisite)
    ipad_claim = copy.deepcopy(artifact)
    ipad_claim["sourceInventory"]["nativeIPadSourceClaimPaths"] = ["FieldEvidenceApp/Fake.swift"]
    hostile_mutations.append(ipad_claim)
    placeholder_promoted = copy.deepcopy(artifact)
    placeholder_promoted["sourceInventory"]["networkInventory"]["placeholderReleaseLinksBlockRelease"] = False
    hostile_mutations.append(placeholder_promoted)
    for hostile in hostile_mutations:
        reject(lambda value=hostile: validate_semantics(value))
        checks += 1
    unknown = copy.deepcopy(artifact); unknown["unknown"] = True
    reject(lambda: validate_schema(unknown, schema)); checks += 1
    stale_authority = copy.deepcopy(artifact); stale_authority["authority"]["baseHead"] = "0" * 40
    reject(lambda: validate_schema(stale_authority, schema)); checks += 1
    manifest = load(root / MANIFEST_PATH)
    if manifest != build_manifest(root): raise ContractError("C06 manifest differs")
    verify_digest(manifest)
    if manifest["pathFence"] != FENCED_PATHS or manifest["artifactCount"] != 7:
        raise ContractError("C06 manifest fence differs")
    expected_fence = [
        "Scripts/v23/c06_contracts.py", "Scripts/v23/generate_c06_contracts.py",
        "Scripts/v23/verify_c06_contracts.py", "Scripts/v23/platform-scope-manifest.schema.json",
        "docs/design/v23/tooling/V23PlatformScopeManifestV1.json",
        "docs/design/v23/tooling/V23-P00-C06-tooling-manifest.json",
        "FieldEvidenceApp/Info.plist", "FieldEvidenceApp/InfoPlist.xcstrings",
    ]
    if manifest["pathFence"] != expected_fence:
        raise ContractError("C06 manifest differs from the hydrated bootstrap fence")
    if [row["path"] for row in manifest["artifacts"]] != [path for path in expected_fence if path != MANIFEST_PATH]:
        raise ContractError("C06 manifest artifact order or set differs")
    for row in manifest["artifacts"]:
        if sha256_bytes((root / row["path"]).read_bytes()) != row["sha256"]:
            raise ContractError(f"C06 manifest hash differs: {row['path']}")
    checks += 3
    completed = subprocess.run([sys.executable, "-B", str(root / "Scripts/v23/generate_c06_contracts.py"),
        "--check", "--root", str(root)], check=True, capture_output=True, text=True,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    if "PASS V23-P00-C06" not in completed.stdout: raise ContractError("generator check failed")
    checks += 1
    if (root / "Scripts/v23/__pycache__").exists():
        raise ContractError("C06 verification created forbidden Python cache artifacts")
    checks += 1
    print(json.dumps({"result": "PASS", "cardID": CARD_ID, "checks": checks,
        "targetConfigurationCount": 6, "inheritedContractCount": 25,
        "deferredEvidenceCount": 25, "releaseTestSupportAbsent": False,
        "nativeCompileRan": False, "acceptanceEnabled": False,
        "acceptanceCredit": False, "releaseReady": False,
        "phase10PollingDuringParallelExecution": False, "releaseCredit": False}, sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
