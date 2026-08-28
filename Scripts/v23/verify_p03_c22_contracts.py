#!/usr/bin/env python3
"""Verify the V23-P03-C22 static corpus, fence, and evidence artifacts."""

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

import p03_c22_contracts as contracts


class DuplicateKey(ValueError):
    """Raised when a supposedly canonical JSON object repeats a key."""


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
        check=True,
        capture_output=True,
        text=True,
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
        check=True,
        capture_output=True,
        text=True,
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
    _assert(
        isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)),
        f"{label}:artifactDigest",
        failures,
    )


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
    _assert(
        row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw),
        f"row digest:{relative}",
        failures,
    )


def _check_test_methods(failures: list[str]) -> None:
    path = ROOT / "FieldEvidenceAppTests/V9_36RecoverabilityVerificationTests.swift"
    if not path.is_file():
        return
    names = re.findall(r"\bfunc\s+(testV23P03C22[A-Z]\w*)\s*\(", path.read_text(encoding="utf-8"))
    _assert(tuple(names) == contracts.TEST_METHODS, f"test method selector mismatch: {names}", failures)


def _check_semantics(contract: dict[str, Any], evidence: dict[str, Any], failures: list[str]) -> None:
    required = contract.get("requiredSemantics", {})
    boundary = contract.get("persistenceBoundary", {})
    scope = contract.get("semanticScope", {})
    _assert(required.get("contractNames") == list(contracts.CONTRACT_NAMES), "contract names", failures)
    _assert(required.get("verificationModes") == list(contracts.VERIFICATION_MODES), "verification modes", failures)
    _assert(required.get("findingDispositions") == list(contracts.FINDING_DISPOSITIONS), "finding dispositions", failures)
    _assert(required.get("runtimeVerificationDispositionEnum") == "RecoverabilityVerificationDispositionV1", "runtime disposition enum", failures)
    _assert(required.get("runtimeFreshnessDispositionEnum") == "RecoveryPointFreshnessDispositionV1", "runtime freshness enum", failures)
    _assert(required.get("runtimeStagingStateEnum") == "RecoverabilityStagingStateV1", "runtime staging enum", failures)
    _assert(required.get("runtimeFindingCodeEnum") == "RecoverabilityFindingCodeV1", "runtime finding enum", failures)
    _assert(required.get("freshnessDispositions") == list(contracts.FRESHNESS_DISPOSITIONS), "freshness dispositions", failures)
    _assert(required.get("stagingStates") == list(contracts.STAGING_STATES), "staging states", failures)
    _assert(required.get("findingCodes") == list(contracts.FINDING_CODES), "finding codes", failures)
    _assert(required.get("persistentSchemaVersion") == 21 and required.get("recordsSchemaVersion") == 20, "V21 records20", failures)
    _assert(required.get("persistentKindLifecycleModelCount") == 82 and required.get("durableFamilyCount") == 1, "82 lifecycle models/one durable family", failures)
    _assert(required.get("persistentReceiptKind") == "RecoverabilityVerificationReceiptV1", "durable receipt kind", failures)
    _assert(required.get("disposableStagingKind") == "RecoverabilityVerificationStagingV1", "disposable staging kind", failures)
    for key in ("immutableArchiveBinding", "isolatedDryRestore"):
        _assert(required.get(key) is True, f"required:{key}", failures)
    for key in ("liveWorkspaceMutation", "sourceArchiveMutation"):
        _assert(required.get(key) is False, f"required:{key}", failures)
    _assert(
        len(required.get("fiveSelectors", [])) == 5 and tuple(required.get("fiveSelectors", [])) == contracts.TEST_METHODS,
        "five selectors",
        failures,
    )
    _assert(boundary.get("schemaVersion") == 21 and boundary.get("recordsSchemaVersion") == 20, "persistence boundary versions", failures)
    _assert(boundary.get("persistedFamilies") == ["RecoverabilityVerificationReceiptV1"], "durable family set", failures)
    _assert(boundary.get("nonPersistentFamilies") == ["RecoverabilityVerificationStagingV1"], "disposable staging family set", failures)
    _assert(boundary.get("currentProjectionRowCount") == 0, "no persistent current projection", failures)
    _assert(boundary.get("providerRows") == 0, "no provider rows", failures)
    for key in (
        "migrationRequired", "backupRestoreRequired", "deleteEraseRequired", "exportReportRequired",
        "searchRebuildRequired", "replayRequired", "classificationRequired", "interruptionRecoveryRequired",
    ):
        _assert(boundary.get(key) is True, f"lifecycle:{key}", failures)
    _assert(boundary.get("secondStore") is False and boundary.get("secondWriter") is False, "single store/writer", failures)
    for token, field in (
        ("ARCHIVE_BOUND_DRY_RESTORE", "atomicAuthorityPolicy"),
        ("BIND_EXACT_ARCHIVE_BYTES", "archiveBindingPolicy"),
        ("CLOSED_MODES", "modePolicy"),
        ("CHANGED_BYTES_INVALIDATE_STALE_PROOF", "digestPolicy"),
        ("PASSED_FAILED_UNSUPPORTED_QUARANTINED_AND_CANCELLED", "findingPolicy"),
        ("IMMUTABLE_EVIDENCE_OUTSIDE", "receiptPolicy"),
        ("V21_EIGHTY_TWO_MODELS", "lifecyclePolicy"),
        ("NO_DESTRUCTIVE_LIVE_RESTORE", "forbiddenPolicy"),
    ):
        _assert(token in str(scope.get(field, "")), f"scope:{field}", failures)
    forbidden_text = " ".join(str(item) for item in required.get("forbiddenClaims", [])) + " " + str(scope.get("forbiddenPolicy", ""))
    for token in (
        "DESTRUCTIVE_LIVE_RESTORE", "SOURCE_ARCHIVE_REPAIR", "PROVIDER_AVAILABILITY_OR_SLA", "CLOUD_DURABILITY",
        "NETWORK_STORAGE_PROVIDER", "ACCOUNT_OR_CREDENTIAL", "EXTERNAL_COPY_AVAILABLE", "FUTURE_RECOVERABILITY",
        "SECOND_WRITER_OR_STORE",
    ):
        _assert(token in forbidden_text.upper(), f"forbidden:{token}", failures)
    _assert(evidence.get("requiredSemanticsDigest") == contracts.sha256_value(required), "evidence semantics digest", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C22 fence path to be changed")
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

    _assert(not unowned, "changed path outside full C22 fence", failures)
    if args.complete:
        _assert(not missing, "required implementation path missing from C22 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 56, "path fence count", failures)
    _assert(len(contracts.EXISTING_PATHS) == 42 and len(contracts.NEW_PATHS) == 14, "path split 42+14", failures)
    _assert(len(set(contracts.PATH_FENCE)) == 56, "duplicate path fence", failures)
    _assert(
        contracts.PRIOR_FENCE_PROOF["priorOwnedPathCount"] == 984
        and contracts.PRIOR_FENCE_PROOF["overlapCount"] == 647
        and contracts.PRIOR_FENCE_PROOF["authorizedOverlapCount"] == 647
        and contracts.PRIOR_FENCE_PROOF["unauthorizedOverlapCount"] == 0
        and contracts.PRIOR_FENCE_PROOF["fenceCount"] == 59
        and len(contracts.PRIOR_FENCE_OVERLAPS) == 647
        and contracts.PRIOR_FENCE_PROOF["authorizedOverlapEdges"] == list(contracts.PRIOR_FENCE_OVERLAPS)
        and all(
            isinstance(row, dict)
            and isinstance(row.get("path"), str)
            and isinstance(row.get("priorCardID"), str)
            and isinstance(row.get("priorFenceDigest"), str)
            and isinstance(row.get("disposition"), str)
            and isinstance(row.get("boundEvidence"), dict)
            for row in contracts.PRIOR_FENCE_OVERLAPS
        ),
        "prior overlap proof",
        failures,
    )
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
    _assert(contract.get("artifact") == "V23P03C22RecoverabilityVerificationContractV1", "contract artifact", failures)
    _assert(contract.get("cardID") == contracts.CARD and contract.get("status") == "PASS_STATIC_PROVISIONAL" and contract.get("verificationMode") == "STATIC_ONLY", "contract status", failures)
    _assert(authority.get("appBaseHead") == contracts.BASE_HEAD and authority.get("appBaseTree") == contracts.BASE_TREE, "app base identity", failures)
    _assert(authority.get("coordinationHead") == contracts.COORDINATION_HEAD and authority.get("coordinationTree") == contracts.COORDINATION_TREE, "coordination identity", failures)
    _assert(authority.get("contextDigest") == contracts.CONTEXT_DIGEST and authority.get("pathFenceDigest") == contracts.FENCE_DIGEST, "authority digests", failures)
    _assert(authority.get("coordinationCASSequence") == 250 and authority.get("hydrationTransitionSequence") == 250, "hydration sequence", failures)
    _assert(authority.get("hydrationTransitionDigest") == contracts.HYDRATION_TRANSITION_DIGEST, "hydration transition digest", failures)
    _assert(authority.get("allowedPathCount") == 56 and authority.get("existingPathCount") == 42 and authority.get("newPathCount") == 14, "authority path counts", failures)
    _assert(authority.get("directPrerequisiteCards") == ["V23-P03-C21"] and authority.get("nextCard") == "V23-P03-C23", "prerequisite/successor", failures)
    _assert(authority.get("sourceDossierSHA256") == contracts.DOSSIER_SHA256 and authority.get("inheritedV21BlockSHA256") == contracts.INHERITED_V21_BLOCK_SHA256, "authority source pins", failures)
    _check_semantics(contract, evidence, failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _assert(document.get("priorFenceProof") == contracts.PRIOR_FENCE_PROOF, f"{label}: prior fence proof", failures)
        _assert(document.get("priorFenceOverlaps") == list(contracts.PRIOR_FENCE_OVERLAPS), f"{label}: prior fence rows", failures)
        _assert(
            contracts.sha256_value(document.get("priorFenceProof")) == contracts.PRIOR_FENCE_PROOF_CANONICAL_SHA256,
            f"{label}: prior fence proof digest",
            failures,
        )
    _assert(evidence.get("artifact") == "V23P03C22RecoverabilityVerificationEvidenceReceiptV1" and evidence.get("result") == "PASS_STATIC_PROVISIONAL", "evidence result", failures)
    _assert(brand.get("artifact") == "V23P03C22RecoverabilityVerificationBrandImpactManifestV1" and brand.get("s10FenceOverlapPaths") == [], "brand boundary", failures)
    _assert(manifest.get("artifact") == "V23P03C22ToolingManifestV1" and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 56 and manifest.get("existingPathCount") == 42 and manifest.get("newPathCount") == 14 and manifest.get("sourceReferenceCount") == 42, "manifest counts", failures)
    _assert(manifest.get("s10FenceOverlapPaths") == [] and manifest.get("artifactSetDigest") == contracts.sha256_value(manifest.get("artifacts", [])), "manifest closure digest", failures)
    rows = manifest.get("artifacts", [])
    _assert(len(rows) == 55 and {row.get("path") for row in rows} == set(contracts.MANIFEST_INPUT_PATHS), "manifest rows", failures)
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("path"), str):
            _check_row(row, row["path"], rendered, failures)
    _check_test_methods(failures)

    result = "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL"
    payload = {
        "acceptance": False,
        "adoption": False,
        "cardID": contracts.CARD,
        "contextDigest": contracts.CONTEXT_DIGEST,
        "coordinationCASSequence": contracts.COORDINATION_CAS_SEQUENCE,
        "coordinationHead": contracts.COORDINATION_HEAD,
        "coordinationLedgerDigest": contracts.COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": contracts.COORDINATION_PROJECTION_DIGEST,
        "coordinationTree": contracts.COORDINATION_TREE,
        "existingPathCount": 42,
        "fenceDigest": contracts.FENCE_DIGEST,
        "hosted": False,
        "hydrationTransitionDigest": contracts.HYDRATION_TRANSITION_DIGEST,
        "hydrationTransitionSequence": contracts.HYDRATION_TRANSITION_SEQUENCE,
        "missingRequiredChangedPathCount": len(missing),
        "native": False,
        "newPathCount": 14,
        "missingAllowedPathCount": len(missing),
        "pathFenceCount": 56,
        "priorOwnedPathCount": contracts.PRIOR_FENCE_PROOF["priorOwnedPathCount"],
        "priorOverlapCount": contracts.PRIOR_FENCE_OVERLAP_COUNT,
        "authorizedOverlapEdgeCount": contracts.PRIOR_FENCE_PROOF["authorizedOverlapCount"],
        "release": False,
        "result": result,
        "s10FenceOverlapPaths": [],
        "sourceReferenceCount": 42,
        "unownedChangedPathCount": len(unowned),
        "verificationModes": 3,
        "findingDispositions": 5,
        "modelCount": 82,
        "durableFamilyCount": 1,
    }
    if failures:
        payload["failures"] = failures
    print(json.dumps(payload, sort_keys=True) if args.json else result)
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
