#!/usr/bin/env python3
"""Verify Card 50's static C13 corpus, exact fence, and sealed evidence."""

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

import p03_c13_contracts as contracts


class DuplicateKey(ValueError):
    pass


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def _load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_keys)


def _candidate_changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths: list[str] = []
    for line in status.splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))
    committed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths.extend(path.replace("\\", "/") for path in committed.splitlines() if path)
    return sorted(set(paths))


def _base_path_exists(relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], failures: list[str], label: str) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_manifest_row(row: dict[str, Any], relative: str, failures: list[str]) -> None:
    _assert(row.get("path") == relative, f"manifest row path:{relative}", failures)
    path = ROOT / relative
    if path.is_file():
        raw = path.read_bytes()
        _assert(row.get("state") in ("WORKTREE", "GENERATED"), f"manifest row state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"manifest row bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"manifest row digest:{relative}", failures)
        return
    if relative in contracts.EXISTING_PATHS:
        raw = contracts._git_blob(ROOT, relative)
        _assert(row.get("state") == "BASE_HEAD", f"manifest base state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"manifest base bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"manifest base digest:{relative}", failures)
        return
    _assert(relative in contracts.NEW_PATHS, f"manifest row outside fence:{relative}", failures)
    _assert(row.get("state") == "MISSING_NEW_PATH", f"manifest missing state:{relative}", failures)
    _assert(row.get("bytes") == 0 and row.get("sha256") == contracts.sha256_bytes(b""), f"manifest missing digest:{relative}", failures)


def _check_corpus(fixture: dict[str, Any], failures: list[str]) -> None:
    _assert(fixture == contracts.CORPUS, "fixture equals deterministic C13 corpus", failures)
    _assert(fixture.get("schema") == "V21P03C13EvidenceAssuranceCorpusV1", "corpus schema", failures)
    _assert(fixture.get("schemaVersion") == 1 and fixture.get("cardID") == contracts.CARD, "corpus identity", failures)
    _assert(fixture.get("synthetic") is True and fixture.get("containsCustomerData") is False and fixture.get("containsSecrets") is False, "corpus synthetic boundary", failures)
    _assert(fixture.get("requiredContractNames") == list(contracts.CONTRACT_NAMES), "corpus contract names", failures)
    persistence = fixture.get("persistence", {})
    _assert(persistence.get("schemaRelease") == "PERSISTENT_SCHEMA_V13_EVIDENCE_ASSURANCE", "persistence schema release", failures)
    _assert(persistence.get("recordSchemaVersion") == 12 and persistence.get("predecessorSchemaVersion") == 12 and persistence.get("predecessorRecordSchemaVersion") == 11 and persistence.get("recordsSchemaVersion") == 12, "persistence records 12", failures)
    _assert(persistence.get("migration") == "EXACT_V12_TO_V13_COPY_ON_WRITE", "persistence migration", failures)
    _assert(persistence.get("canonicalWriter") == "V23-P02-C01" and persistence.get("lifecycleOwner") == contracts.CARD, "persistence writer/owner", failures)
    _assert(persistence.get("persistedFamilies") == list(contracts.CONTRACT_NAMES) and persistence.get("currentProjectionRows") == 0 and persistence.get("currentProjectionRowCount") == 0, "persistence families/projection", failures)
    _assert(persistence.get("secondStore") is False and persistence.get("secondWriter") is False and persistence.get("accountStore") is False and persistence.get("cloudStore") is False and persistence.get("deliveryOutbox") is False, "persistence forbidden stores", failures)
    _assert(fixture.get("currentProjectionRows") == [] and fixture.get("currentProjectionPersistence") == "NONPERSISTENT_REBUILD_ONLY", "no current projection row", failures)
    _assert(fixture.get("purposeBindingRequired") is True and fixture.get("snapshotBindingRequired") is True and fixture.get("denyByDefault") is True, "purpose/snapshot/deny binding", failures)
    _assert(fixture.get("supersessionImmutable") is True and fixture.get("voidImmutable") is True, "immutable supersession/void", failures)
    _assert(len(fixture.get("visibilityRecords", [])) >= 3 and len(fixture.get("claimEvidenceLinks", [])) >= 2 and len(fixture.get("assuranceManifests", [])) >= 1 and len(fixture.get("attestations", [])) >= 2, "assurance corpus families", failures)
    _assert(all(row.get("defaultDisposition") == "DENY_UNLESS_EXPLICIT" for row in fixture.get("visibilityRecords", [])), "visibility deny default", failures)
    _assert(all(row.get("frozen") is True for row in fixture.get("claimEvidenceLinks", [])), "links frozen", failures)
    _assert(all(row.get("writes") == 0 for row in fixture.get("assuranceProjectionPreviews", [])), "previews zero write", failures)
    _assert(all(row.get("immutable") is True for row in fixture.get("assuranceManifests", [])), "manifests immutable", failures)
    _assert(all(row.get("localOnly") is True and row.get("legalOrNonrepudiationClaim") is False for row in fixture.get("attestations", [])), "attestation local boundary", failures)
    forbidden = fixture.get("forbiddenCapabilities", {})
    _assert(all(forbidden.get(key) is False for key in ("accounts", "authentication", "cloud", "delivery", "legalClaims", "nonrepudiation", "finalizationProducer", "signing", "upload", "submission", "secondStore", "secondWriter")), "forbidden capability boundary", failures)
    _assert(fixture.get("claims") and all(value is False for value in fixture["claims"].values()), "claims false", failures)
    hostile_ids = {str(row.get("id")) for row in fixture.get("hostileCases", [])}
    for fragment in ("cross-workspace", "undeclared-audience", "sensitivity-widening", "missing-purpose", "missing-snapshot", "snapshot-digest-mismatch", "duplicate-link", "supersession-rewrite", "void-rewrite", "stale-preview-publication", "account-producer", "cloud-producer", "delivery-outbox", "legal-signature", "nonrepudiation", "finalization-producer", "second-store", "second-writer"):
        _assert(any(fragment in case_id for case_id in hostile_ids), f"hostile case:{fragment}", failures)
    interruption_ids = {str(row.get("id")) for row in fixture.get("interruptionCases", [])}
    for fragment in ("migration", "visibility", "link", "preview", "manifest", "attestation", "snapshot", "backup", "restore", "journal", "search", "report"):
        _assert(any(fragment in case_id for case_id in interruption_ids), f"interruption case:{fragment}", failures)
    recovery_ids = {str(row.get("id")) for row in fixture.get("recoveryCases", [])}
    for fragment in ("backup", "restore", "clone", "fork", "delete", "erase", "compatibility", "journal", "search", "report", "export", "released"):
        _assert(any(fragment in case_id for case_id in recovery_ids), f"recovery case:{fragment}", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C13 fence path to be changed")
    parser.add_argument("--json", action="store_true", help="emit machine-readable result")
    args = parser.parse_args()

    failures: list[str] = []
    candidate_paths = _candidate_changed_paths()
    unowned_changed = sorted(set(candidate_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(candidate_paths))
    pycache_paths = sorted(path for path in candidate_paths if "__pycache__" in path or path.endswith(".pyc"))
    _assert(not unowned_changed, "changed path outside full C13 fence", failures)
    _assert(not pycache_paths, "python cache artifact present", failures)
    if args.complete:
        _assert(not missing_required_changed, "required changed path missing from full C13 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 91 and len(set(contracts.PATH_FENCE)) == 91, "exact 91-path fence", failures)
    _assert(len(contracts.EXISTING_PATHS) == 77 and len(contracts.NEW_PATHS) == 14, "path classification counts", failures)
    _assert(contracts.PATH_FENCE == contracts.EXISTING_PATHS + contracts.NEW_PATHS, "path classification/order", failures)
    _assert(contracts.BASE_HEAD == "458a19d2ed16826ec93b1ce688ffa4e1e8e57b59" and contracts.BASE_TREE == "74c59c691c72c3d37c08b0c9a5d318d635844a82", "base authority", failures)
    _assert(contracts.FENCE_DIGEST == "3a8af6eccec4a8842fde87c41ba665400ec2d20a8c80796c9945559b6c4c49ef", "fence digest authority", failures)
    _assert(contracts.PREREQUISITE_DIGEST == "f9925484fe0549823b164fbcefaa0b7faeceb13c183cd02a8c8afdc0e9c8e3d8", "prerequisite digest authority", failures)
    _assert(not set(contracts.PATH_FENCE) & {path for path in contracts.PATH_FENCE if "s10" in path.lower() or "phase10" in path.lower()}, "S10 named path", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(sum(row.get("overlapCount", 0) for row in contracts.PRIOR_FENCE_OVERLAPS) == 536, "prior overlap total", failures)
    _assert(len(contracts.PRIOR_FENCE_OVERLAPS) == 31 and contracts.PRIOR_FENCE_PROOF.get("fenceCount") == 50 and contracts.PRIOR_FENCE_PROOF.get("priorOwnedPathCount") == 837, "prior fence proof counts", failures)
    _assert(contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapCount") == 536 and contracts.PRIOR_FENCE_PROOF.get("unauthorizedOverlapCount") == 0, "prior fence authorization", failures)
    for relative in contracts.PATH_FENCE:
        _assert(_base_path_exists(relative) is (relative in contracts.EXISTING_PATHS), f"BASE_HEAD existence:{relative}", failures)

    source_rows = contracts.source_artifacts(ROOT)
    _assert(len(source_rows) == 77, "source reference count", failures)
    for row in source_rows:
        raw = contracts._git_blob(ROOT, row["path"])
        _assert(row["bytes"] == len(raw) and row["sha256"] == contracts.sha256_bytes(raw), f"source digest:{row['path']}", failures)
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

    try:
        expected = contracts.all_outputs(ROOT)
        for relative, raw in expected.items():
            path = ROOT / relative
            _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as error:
        failures.append(f"deterministic generation:{error}")
        expected = {}

    _check_corpus(contracts.CORPUS, failures)
    _assert(schema == contracts.schema_document(), "schema does not equal generated C13 corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema" and schema.get("additionalProperties") is False, "schema strict root", failures)

    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, failures, label)
        _assert(document.get("verificationMode") == "STATIC_ONLY", f"{label}:mode", failures)
        _assert(document.get("authority") == contracts._authority(), f"{label}:authority", failures)
        _assert(document.get("statusFlags") == contracts._flags(), f"{label}:statusFlags", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation", failures)
        _assert(document.get("s10FenceOverlapPaths") == [] or document.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], f"{label}:S10 overlap", failures)

    _assert(contract.get("artifact") == "V23P03C13EvidenceAssuranceContractV1" and contract.get("status") == "PASS_STATIC_PROVISIONAL", "contract identity/status", failures)
    _assert(contract.get("sourceProjection") == contracts.SOURCE_PROJECTION, "contract source projection", failures)
    _assert(contract.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and contract.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "contract prerequisite/order", failures)
    _assert(contract.get("sourceContract", {}).get("sourceArtifacts") == source_rows and contract.get("sourceContract", {}).get("authorityArtifacts") == authority_rows, "contract source rows", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "contract lifecycle", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS) and contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract path classes", failures)
    _assert(contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract path S10 overlap", failures)
    _assert(contract.get("persistenceBoundary") == contracts.CORPUS["persistence"], "contract persistence boundary", failures)

    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL" and evidence.get("sourceProjection") == contracts.SOURCE_PROJECTION, "evidence result/projection", failures)
    _assert(evidence.get("pathEvidence") == contract.get("pathEvidence"), "evidence path evidence", failures)
    _assert(evidence.get("sourceContractDigest") == contracts.sha256_value(source_rows), "evidence source digest", failures)
    _assert(evidence.get("authorityArtifactDigest") == contracts.sha256_value(authority_rows), "evidence authority digest", failures)
    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL" and brand.get("affectedSurfacePaths") == [], "brand static boundary", failures)

    manifest_rows = manifest.get("artifacts", [])
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE) and manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST, "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 91 and manifest.get("existingPathCount") == 77 and manifest.get("newPathCount") == 14, "manifest path counts", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE) and manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest allowed paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows and manifest.get("authorityArtifacts") == authority_rows, "manifest source rows", failures)
    _assert([row.get("path") for row in manifest_rows] == list(contracts.MANIFEST_INPUT_PATHS), "manifest artifact paths", failures)
    for row in manifest_rows:
        _check_manifest_row(row, row.get("path", ""), failures)
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(manifest_rows), "manifest artifact set digest", failures)

    source_text = b"\n".join(contracts._git_blob(ROOT, path) for path in contracts.AUTHORITY_REFERENCE_PATHS).decode("utf-8")
    for token in contracts.SOURCE_CONTRACT_TOKENS:
        _assert(token in source_text, f"source contract token:{token}", failures)

    result: dict[str, Any] = {
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL",
        "cardID": contracts.CARD, "pathFenceCount": len(contracts.PATH_FENCE), "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS), "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "fenceDigest": contracts.FENCE_DIGEST, "baseHead": contracts.BASE_HEAD, "baseTree": contracts.BASE_TREE, "unownedChangedPathCount": len(unowned_changed), "missingRequiredChangedPathCount": len(missing_required_changed), "pycachePathCount": len(pycache_paths), "priorAuthorizedOverlapCount": 536, "s10FenceOverlapPaths": [],
        "native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False,
    }
    if failures:
        result["failures"] = failures
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
