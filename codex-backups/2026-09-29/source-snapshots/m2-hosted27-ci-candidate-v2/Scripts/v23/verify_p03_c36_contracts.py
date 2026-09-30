#!/usr/bin/env python3
"""Verify C36's static corpus, full path fence, and evidence artifacts."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c36_contracts as contracts

C34_REPROOF_CARD = "V23-P03-C34"


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
    status_output = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"], check=True, capture_output=True, text=True).stdout
    paths: list[str] = []
    for line in status_output.splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))

    committed_output = subprocess.run(["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"], check=True, capture_output=True, text=True).stdout
    paths.extend(path.replace("\\", "/") for path in committed_output.splitlines() if path)
    return sorted(set(paths))


def _base_path_exists(relative: str) -> bool:
    probe = subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"], capture_output=True)
    return probe.returncode == 0


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], failures: list[str], label: str) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_row(row: dict[str, Any], relative: str, rendered: dict[str, bytes], failures: list[str]) -> None:
    if not relative:
        failures.append("row path is empty")
        return
    path = ROOT / relative
    _assert(row.get("path") == relative, f"row path:{relative}", failures)
    if relative in rendered:
        raw = rendered[relative]
        _assert(row.get("state") == "GENERATED", f"row generated state:{relative}", failures)
        _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row generated digest:{relative}", failures)
        return
    if path.is_file():
        raw = path.read_bytes()
        _assert(row.get("state") == "WORKTREE", f"row worktree state:{relative}", failures)
        _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row worktree digest:{relative}", failures)
        return
    if relative in contracts.EXISTING_PATHS:
        raw = contracts._git_blob(ROOT, relative)
        _assert(row.get("state") == "BASE_HEAD", f"row base state:{relative}", failures)
        _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row base digest:{relative}", failures)
        return
    _assert(relative in contracts.NEW_PATHS, f"row outside fence:{relative}", failures)
    _assert(row.get("state") == "MISSING_NEW_PATH", f"row missing state:{relative}", failures)
    _assert(row.get("bytes") == 0 and row.get("sha256") == contracts.sha256_bytes(b""), f"row missing digest:{relative}", failures)


def main() -> int:
    assert contracts.C34_NAVIGATION_REPROOF["consumerCardID"] == C34_REPROOF_CARD
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every hydrated fence path to be changed")
    parser.add_argument("--json", action="store_true", help="retain machine-readable output")
    args = parser.parse_args()

    failures: list[str] = []
    candidate_paths = _candidate_changed_paths()
    unowned_changed = sorted(set(candidate_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(candidate_paths))
    rendered = contracts.all_outputs(ROOT)

    _assert(not unowned_changed, "changed path outside full C36 fence", failures)
    if args.complete:
        _assert(not missing_required_changed, "required changed path missing from full C36 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 105, "path fence count", failures)
    _assert(len(contracts.EXISTING_PATHS) == 87, "existing path count", failures)
    _assert(len(contracts.NEW_PATHS) == 18, "new path count", failures)
    _assert(tuple(contracts.EXISTING_PATHS + contracts.NEW_PATHS) == tuple(contracts.PATH_FENCE), "path classification", failures)
    _assert(contracts.FENCE_DIGEST == "205df5643f4f73344eb052a36a8271500eceeb131bef4fdb1084f6efc56aa629", "fence digest authority", failures)
    _assert(contracts.PRIOR_FENCE_PROOF["overlapCount"] == 665, "prior overlap count", failures)
    _assert(sum(row["overlapCount"] for row in contracts.PRIOR_FENCE_OVERLAPS) == 665, "prior overlap row total", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(not set(contracts.PATH_FENCE) & {".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml"}, "S10 workflow overlap", failures)
    _assert(not any("s10" in path.lower() or "phase10" in path.lower() for path in contracts.PATH_FENCE), "S10 path overlap", failures)
    for relative in contracts.PATH_FENCE:
        if relative in contracts.EXISTING_PATHS:
            _assert(_base_path_exists(relative), f"existing path absent at BASE_HEAD:{relative}", failures)
        else:
            _assert(not _base_path_exists(relative), f"new path existed at BASE_HEAD:{relative}", failures)

    source_rows = contracts.source_artifacts(ROOT)
    for row in source_rows:
        _assert(_base_path_exists(row["path"]), f"missing source at BASE_HEAD:{row['path']}", failures)
        base_raw = contracts._git_blob(ROOT, row["path"])
        _assert(row["bytes"] == len(base_raw) and row["sha256"] == contracts.sha256_bytes(base_raw), f"source digest:{row['path']}", failures)
    authority_rows = contracts.authority_artifacts(ROOT)

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

    _assert(schema == contracts.schema_document(), "schema does not equal generated corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect", failures)
    _assert(schema.get("type") == "object" and schema.get("additionalProperties") is False, "schema strict root", failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, failures, label)

    _assert(contract.get("artifact") == "V23P03C36FieldDraftResilienceContractV1", "contract artifact", failures)
    _assert(contract.get("status") == "PASS_STATIC_PROVISIONAL" and contract.get("verificationMode") == "STATIC_ONLY", "contract status/mode", failures)
    _assert(contract.get("authority", {}).get("contextDigest") == contracts.CONTEXT_DIGEST, "contract context digest", failures)
    _assert(contract.get("authority", {}).get("pathFenceDigest") == contracts.FENCE_DIGEST, "contract authority fence digest", failures)
    _assert(contract.get("authority", {}).get("coordinationProjectionDigest") == contracts.COORDINATION_PROJECTION_DIGEST, "contract projection digest", failures)
    _assert(contract.get("authority", {}).get("hydrationTransitionDigest") == contracts.HYDRATION_TRANSITION_DIGEST, "contract transition digest", failures)
    _assert(contract.get("authority", {}).get("allowedPathCount") == 105, "contract authority path count", failures)
    _assert(contract.get("authority", {}).get("recordSchemaVersion") == 15, "contract record schema version", failures)
    _assert(contract.get("authority", {}).get("persistentModelCount") == 64 and contract.get("authority", {}).get("persistentModelFamilyCount") == 6, "contract model inventory", failures)
    _assert(contract.get("sourceContract", {}).get("sourceProjection") == contracts.SOURCE_PROJECTION, "contract source projection", failures)
    _assert(contract.get("sourceContract", {}).get("requiredContractNames") == list(contracts.CONTRACT_NAMES), "contract names", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "lifecycle coverage", failures)
    _assert(contract.get("requiredSemantics", {}).get("requiredBehaviors") == list(contracts.REQUIRED_BEHAVIORS), "required behaviors", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS), "contract existing paths", failures)
    _assert(contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract new paths", failures)
    _assert(contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract S10 overlap", failures)

    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL" and evidence.get("verificationMode") == "STATIC_ONLY", "evidence status/mode", failures)
    _assert(evidence.get("sourceProjection") == contracts.SOURCE_PROJECTION, "evidence source projection", failures)
    _assert(evidence.get("requiredSemanticsDigest") == contracts.sha256_value({"contractNames": list(contracts.CONTRACT_NAMES), "persistentModelFamilies": [dict(value) for value in contracts.PERSISTENT_MODEL_FAMILIES], "checkpointStates": contracts.CORPUS["checkpointStates"], "presentationStates": contracts.CORPUS["presentationStates"], "attachmentStates": contracts.CORPUS["attachmentStates"], "sagaStates": contracts.CORPUS["sagaStates"], "conflictPlans": contracts.CORPUS["conflictPlans"], "recoveryStatuses": contracts.CORPUS["recoveryStatuses"], "requiredBehaviors": list(contracts.REQUIRED_BEHAVIORS), "requiredLifecycle": list(contracts.LIFECYCLE_DIMENSIONS)}), "evidence semantics digest", failures)
    _assert(evidence.get("pathEvidence", {}).get("pathFenceDigest") == contracts.FENCE_DIGEST, "evidence path fence digest", failures)
    _assert(evidence.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "evidence S10 overlap", failures)
    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL" and brand.get("verificationMode") == "STATIC_ONLY", "brand status/mode", failures)
    _assert(brand.get("affectedSurfacePaths") == [] and brand.get("s10FenceOverlapPaths") == [], "brand shipping/S10 surface", failures)

    manifest_rows = manifest.get("artifacts", [])
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE) and manifest.get("fullFencePaths") == list(contracts.FULL_FENCE_PATHS), "manifest path fence", failures)
    _assert(manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST and manifest.get("pathFenceCount") == 105, "manifest fence identity", failures)
    _assert(manifest.get("existingPathCount") == 87 and manifest.get("newPathCount") == 18, "manifest classification counts", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE), "manifest allowed paths", failures)
    _assert(manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest delete/rename paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows and manifest.get("authorityArtifacts") == authority_rows, "manifest source rows", failures)
    _assert([row.get("path") for row in manifest_rows] == list(contracts.MANIFEST_INPUT_PATHS), "manifest artifact paths", failures)
    for row in manifest_rows:
        _check_row(row, row.get("path", ""), rendered, failures)
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(manifest_rows), "manifest artifact set digest", failures)

    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        flags = document.get("statusFlags")
        _assert(isinstance(flags, dict), f"{label}:statusFlags", failures)
        for key in ("native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance", "hostedAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness"):
            _assert(flags.get(key) is False, f"{label}:{key} flag", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation gate", failures)

    source_text = "\n".join(contracts._git_blob(ROOT, path).decode("utf-8") for path in contracts.AUTHORITY_REFERENCE_PATHS)
    for token in contracts.SOURCE_CONTRACT_TOKENS:
        _assert(token in source_text, f"source contract token:{token}", failures)

    result: dict[str, Any] = {
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL",
        "cardID": contracts.CARD, "pathFenceCount": len(contracts.PATH_FENCE), "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS),
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS), "fenceDigest": contracts.FENCE_DIGEST, "contextDigest": contracts.CONTEXT_DIGEST,
        "coordinationCASSequence": contracts.COORDINATION_CAS_SEQUENCE, "coordinationLedgerDigest": contracts.COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": contracts.COORDINATION_PROJECTION_DIGEST,
        "hydrationTransitionDigest": contracts.HYDRATION_TRANSITION_DIGEST, "priorOverlapCount": contracts.PRIOR_FENCE_PROOF["overlapCount"], "unownedChangedPathCount": len(unowned_changed),
        "missingRequiredChangedPathCount": len(missing_required_changed), "s10FenceOverlapPaths": [], "native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False,
    }
    if failures:
        result["failures"] = failures
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
