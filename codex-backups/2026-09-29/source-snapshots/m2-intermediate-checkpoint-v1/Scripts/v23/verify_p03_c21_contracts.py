#!/usr/bin/env python3
"""Verify the V23-P03-C21 static corpus, fence, and evidence artifacts."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c21_contracts as contracts


class DuplicateKey(ValueError):
    pass


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def _load(relative: str) -> dict[str, Any]:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_keys)


def _candidate_changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths: list[str] = []
    for line in status.splitlines():
        if line:
            value = line[3:]
            if " -> " in value:
                value = value.split(" -> ", 1)[1]
            paths.append(value.replace("\\", "/"))
    committed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths.extend(item.replace("\\", "/") for item in committed.splitlines() if item)
    return sorted(set(paths))


def _base_path_exists(relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], label: str, failures: list[str]) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_row(row: dict[str, Any], relative: str, rendered: dict[str, bytes], failures: list[str]) -> None:
    path = ROOT / relative
    _assert(row.get("path") == relative, f"row path:{relative}", failures)
    if relative in rendered:
        raw = rendered[relative]
        _assert(row.get("state") == "GENERATED", f"row generated state:{relative}", failures)
    elif path.is_file():
        raw = path.read_bytes()
        _assert(row.get("state") == "WORKTREE", f"row worktree state:{relative}", failures)
    elif relative in contracts.EXISTING_PATHS:
        raw = contracts._git_blob(ROOT, relative)
        _assert(row.get("state") == "BASE_HEAD", f"row base state:{relative}", failures)
    else:
        raw = b""
        _assert(row.get("state") == "MISSING_NEW_PATH", f"row missing state:{relative}", failures)
    _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row digest:{relative}", failures)


def _check_test_methods(failures: list[str]) -> None:
    path = ROOT / "FieldEvidenceAppTests/V9_35ClientCapabilityPackageLifecycleTests.swift"
    if not path.is_file():
        return
    names = re.findall(r"\bfunc\s+(testV23P03C21[A-Z]\w*)\s*\(", path.read_text(encoding="utf-8"))
    _assert(tuple(names) == contracts.TEST_METHODS, f"test method selector mismatch: {names}", failures)


def _check_semantics(contract: dict[str, Any], evidence: dict[str, Any], failures: list[str]) -> None:
    required = contract.get("requiredSemantics", {})
    boundary = contract.get("persistenceBoundary", {})
    scope = contract.get("semanticScope", {})
    _assert(required.get("contractNames") == list(contracts.CONTRACT_NAMES), "contract names", failures)
    _assert(required.get("capabilityRanges") == list(contracts.CAPABILITY_RANGES), "capability ranges", failures)
    _assert(required.get("admissions") == list(contracts.ADMISSIONS) and len(required.get("admissions", [])) == 5, "five admissions", failures)
    _assert(required.get("operations") == list(contracts.OPERATIONS) and len(required.get("operations", [])) == 9, "nine operations", failures)
    _assert(required.get("lifecycleStates") == list(contracts.LIFECYCLE_STATES) and len(required.get("lifecycleStates", [])) == 5, "canonical lifecycle states", failures)
    _assert(not set(required.get("lifecycleStates", [])) & {"DRAFT", "FINALIZED"}, "removed noncanonical lifecycle states", failures)
    _assert(required.get("persistentSchemaVersion") == 20 and required.get("recordsSchemaVersion") == 19, "V20 records19", failures)
    _assert(required.get("persistentKindLifecycleModelCount") == 81 and required.get("durableFamilyCount") == 4, "81 lifecycle models/four families", failures)
    _assert(required.get("immutableVersionedReleases") is True and required.get("withdrawalPreservesHistory") is True, "immutable withdrawal history", failures)
    _assert(len(required.get("fiveSelectors", [])) == 5 and tuple(required.get("fiveSelectors", [])) == contracts.TEST_METHODS, "five selectors", failures)
    _assert(boundary.get("schemaVersion") == 20 and boundary.get("recordsSchemaVersion") == 19, "persistence boundary versions", failures)
    _assert(boundary.get("persistedFamilies") == list(contracts.CONTRACT_NAMES), "persisted family set", failures)
    for key in ("migrationRequired", "backupRestoreRequired", "deleteEraseRequired", "exportReportRequired", "searchRebuildRequired", "replayRequired", "classificationRequired", "interruptionRecoveryRequired"):
        _assert(boundary.get(key) is True, f"lifecycle:{key}", failures)
    _assert(boundary.get("secondStore") is False and boundary.get("secondWriter") is False, "single store/writer", failures)
    _assert("PLATFORM_NEUTRAL" in scope.get("capabilityPolicy", ""), "platform-neutral capabilities", failures)
    _assert("CLOSED_ADMISSION_MATRIX" in scope.get("admissionPolicy", "") or "READ_WRITE" in scope.get("admissionPolicy", ""), "closed admissions", failures)
    _assert("CLOSED_OPERATION_MATRIX" in scope.get("operationPolicy", "") or "UPGRADE_DRAFT" in scope.get("operationPolicy", ""), "closed operations", failures)
    _assert("IMMUTABLE_VERSIONED_PACKAGE_RELEASES" in scope.get("packagePolicy", ""), "immutable releases", failures)
    _assert("FINALIZED_HISTORY_REMAINS_READABLE" in scope.get("historyPolicy", ""), "withdrawal history", failures)
    _assert("V20_EIGHTY_ONE_MODELS" in scope.get("lifecyclePolicy", ""), "V20 lifecycle", failures)
    forbidden_text = " ".join(str(item) for item in required.get("forbiddenClaims", [])) + " " + scope.get("forbiddenPolicy", "")
    for token in ("REMOTE_CLIENT_REGISTRY", "ACCOUNT_USER_TENANT_ENDPOINT", "PROVIDER_CREDENTIAL", "MUTABLE_RELEASE", "ANDROID_WEB_BACKEND_SAAS_CLOUD", "SECOND_WRITER"):
        _assert(token in forbidden_text.upper(), f"forbidden:{token}", failures)
    _assert(evidence.get("requiredSemanticsDigest") == contracts.sha256_value(required), "evidence semantics digest", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C21 fence path to be changed")
    parser.add_argument("--json", action="store_true", help="emit machine-readable evidence")
    args = parser.parse_args()

    failures: list[str] = []
    changed = _candidate_changed_paths()
    unowned = sorted(set(changed) - set(contracts.PATH_FENCE))
    missing = sorted(set(contracts.PATH_FENCE) - set(changed))
    rendered: dict[str, bytes] = {}
    try:
        rendered = contracts.all_outputs(ROOT)
    except (OSError, subprocess.CalledProcessError, ValueError, TypeError) as error:
        failures.append(f"render:{error}")

    _assert(not unowned, "changed path outside full C21 fence", failures)
    if args.complete:
        _assert(not missing, "required implementation path missing from C21 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 121, "path fence count", failures)
    _assert(len(contracts.EXISTING_PATHS) == 107 and len(contracts.NEW_PATHS) == 14, "path split 107+14", failures)
    _assert(len(set(contracts.PATH_FENCE)) == 121, "duplicate path fence", failures)
    _assert(contracts.PRIOR_FENCE_PROOF["overlapCount"] == 1135 and contracts.PRIOR_FENCE_PROOF["unauthorizedOverlapCount"] == 0, "prior overlap proof", failures)
    _assert(not set(contracts.PATH_FENCE) & {".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml"}, "S10 workflow overlap", failures)
    _assert(not any("s10" in path.lower() or "phase10" in path.lower() for path in contracts.PATH_FENCE), "S10 path overlap", failures)
    for relative in contracts.EXISTING_PATHS:
        _assert(_base_path_exists(relative), f"existing path absent at BASE_HEAD:{relative}", failures)
    for relative in contracts.NEW_PATHS:
        _assert(not _base_path_exists(relative), f"new path existed at BASE_HEAD:{relative}", failures)

    try:
        schema = _load(contracts.SCHEMA_PATH)
        contract = _load(contracts.CONTRACT_PATH)
        evidence = _load(contracts.EVIDENCE_PATH)
        brand = _load(contracts.BRAND_PATH)
        manifest = _load(contracts.MANIFEST_PATH)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")
        schema = contract = evidence = brand = manifest = {}

    for relative, raw in rendered.items():
        path = ROOT / relative
        _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    if rendered:
        _assert(schema == contracts.schema_document(), "schema does not equal generated corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect", failures)
    _assert(schema.get("type") == "object" and schema.get("additionalProperties") is False, "schema strict root", failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, label, failures)
        _assert(all(value is False for value in document.get("statusFlags", {}).values()), f"{label}: status flag overclaim", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}: reconciliation flag", failures)

    authority = contract.get("authority", {})
    _assert(contract.get("artifact") == "V23P03C21ClientCapabilityPackageLifecycleContractV1", "contract artifact", failures)
    _assert(contract.get("cardID") == contracts.CARD and contract.get("status") == "PASS_STATIC_PROVISIONAL" and contract.get("verificationMode") == "STATIC_ONLY", "contract status", failures)
    _assert(authority.get("coordinationHead") == contracts.COORDINATION_HEAD and authority.get("coordinationTree") == contracts.COORDINATION_TREE, "coordination identity", failures)
    _assert(authority.get("contextDigest") == contracts.CONTEXT_DIGEST and authority.get("pathFenceDigest") == contracts.FENCE_DIGEST, "authority digests", failures)
    _assert(authority.get("coordinationCASSequence") == 246 and authority.get("hydrationTransitionSequence") == 246, "hydration sequence", failures)
    _assert(authority.get("hydrationTransitionDigest") == contracts.HYDRATION_TRANSITION_DIGEST, "hydration transition digest", failures)
    _assert(authority.get("allowedPathCount") == 121 and authority.get("existingPathCount") == 107 and authority.get("newPathCount") == 14, "authority path counts", failures)
    _assert(authority.get("directPrerequisiteCards") == ["V23-P03-C18", "V23-P03-C19", "V23-P03-C20"] and authority.get("nextCard") == "V23-P03-C22", "prerequisite/successor", failures)
    _check_semantics(contract, evidence, failures)
    _assert(evidence.get("artifact") == "V23P03C21ClientCapabilityPackageLifecycleEvidenceReceiptV1" and evidence.get("result") == "PASS_STATIC_PROVISIONAL", "evidence result", failures)
    _assert(brand.get("artifact") == "V23P03C21ClientCapabilityPackageLifecycleBrandImpactManifestV1" and brand.get("s10FenceOverlapPaths") == [], "brand boundary", failures)
    _assert(manifest.get("artifact") == "V23P03C21ToolingManifestV1" and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 121 and manifest.get("existingPathCount") == 107 and manifest.get("newPathCount") == 14 and manifest.get("sourceReferenceCount") == 107, "manifest counts", failures)
    _assert(manifest.get("s10FenceOverlapPaths") == [] and manifest.get("artifactSetDigest") == contracts.sha256_value(manifest.get("artifacts", [])), "manifest closure digest", failures)
    rows = manifest.get("artifacts", [])
    _assert(len(rows) == 120 and {row.get("path") for row in rows} == set(contracts.MANIFEST_INPUT_PATHS), "manifest rows", failures)
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("path"), str):
            _check_row(row, row["path"], rendered, failures)
    _check_test_methods(failures)

    result = "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL"
    payload = {
        "acceptance": False, "adoption": False, "cardID": contracts.CARD,
        "contextDigest": contracts.CONTEXT_DIGEST, "coordinationCASSequence": contracts.COORDINATION_CAS_SEQUENCE,
        "coordinationHead": contracts.COORDINATION_HEAD, "coordinationLedgerDigest": contracts.COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": contracts.COORDINATION_PROJECTION_DIGEST, "coordinationTree": contracts.COORDINATION_TREE,
        "existingPathCount": 107, "fenceDigest": contracts.FENCE_DIGEST, "hosted": False,
        "hydrationTransitionDigest": contracts.HYDRATION_TRANSITION_DIGEST, "hydrationTransitionSequence": 246,
        "missingRequiredChangedPathCount": len(missing), "native": False, "newPathCount": 14,
        "missingAllowedPathCount": len(missing), "pathFenceCount": 121, "priorOverlapCount": 1135,
        "release": False, "result": result, "s10FenceOverlapPaths": [], "sourceReferenceCount": 107,
        "unownedChangedPathCount": len(unowned), "admissions": 5, "operations": 9, "modelCount": 81,
    }
    if failures:
        payload["failures"] = failures
    print(json.dumps(payload, sort_keys=True) if args.json else result)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
