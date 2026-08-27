"""Verify Card 47's static corpus, exact fence, source digests, and receipts."""

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

import p03_c39_contracts as contracts


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
        check=True,
        capture_output=True,
        text=True,
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
        check=True,
        capture_output=True,
        text=True,
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


def _check_row(row: dict[str, Any], relative: str, failures: list[str]) -> None:
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


def _check_fixture(fixture: dict[str, Any], failures: list[str]) -> None:
    _assert(fixture.get("schema") == "V21P03C39AssetSemanticCorpusV1", "fixture schema", failures)
    _assert(fixture.get("schemaVersion") == 1, "fixture schema version", failures)
    _assert(fixture.get("cardID") == contracts.CARD, "fixture card", failures)
    _assert(fixture.get("synthetic") is True, "fixture synthetic", failures)
    _assert(fixture.get("containsCustomerData") is False, "fixture customer data", failures)
    _assert(fixture.get("containsSecrets") is False, "fixture secrets", failures)
    persistence = fixture.get("persistence", {})
    _assert(persistence.get("schemaRelease") == "PERSISTENT_SCHEMA_V10_ASSET_SEMANTICS", "fixture schema release", failures)
    _assert(persistence.get("predecessorSchemaVersion") == 9, "fixture predecessor schema", failures)
    _assert(persistence.get("migration") == "EXACT_V9_TO_V10_COPY_ON_WRITE", "fixture migration", failures)
    _assert(persistence.get("canonicalWriter") == "V23-P02-C01", "fixture writer", failures)
    _assert(persistence.get("lifecycleOwner") == contracts.CARD, "fixture lifecycle owner", failures)
    enums = fixture.get("enumContracts", {})
    expected_enums = {
        "catalogStates": list(contracts.CATALOG_STATES),
        "lifecycleStates": list(contracts.LIFECYCLE_STATES),
        "identifierReviewStates": list(contracts.IDENTIFIER_REVIEW_STATES),
        "provenanceKinds": list(contracts.PROVENANCE_KINDS),
        "subjectKinds": list(contracts.SUBJECT_KINDS),
        "capabilityTags": list(contracts.CAPABILITY_TAGS),
    }
    for key, value in expected_enums.items():
        _assert(enums.get(key) == value, f"fixture enum:{key}", failures)
    _assert(len(fixture.get("catalogReleases", [])) >= 2, "fixture catalog releases", failures)
    _assert(len(fixture.get("kindDefinitions", [])) >= 1, "fixture kind definitions", failures)
    _assert(len(fixture.get("bindingEvents", [])) >= 2, "fixture kind bindings", failures)
    _assert(len(fixture.get("workflowCapabilityBindings", [])) >= 2, "fixture workflow bindings", failures)
    _assert(len(fixture.get("productIdentities", [])) >= 3, "fixture product identities", failures)
    _assert(len(fixture.get("lifecycleEvents", [])) >= 5, "fixture lifecycle events", failures)
    _assert(len(fixture.get("successorLinks", [])) >= 1, "fixture successor links", failures)
    _assert({row.get("subjectKind") for row in fixture.get("subjectScopes", [])} == set(contracts.SUBJECT_KINDS), "fixture subject scopes", failures)
    migration = fixture.get("legacyMigration", {})
    for key in ("preservedAssetID", "preservedBackupBytes", "preservedReportBytes", "preservedPlacement", "preservedExternalKeys", "preservedHistoricPackBindings"):
        _assert(migration.get(key) is True, f"fixture migration preservation:{key}", failures)
    for key in ("inventedManufacturer", "inventedModel", "inventedSerial", "inventedInstallation", "inventedLifecycle"):
        _assert(migration.get(key) is False, f"fixture migration invention:{key}", failures)
    claim_values = fixture.get("claims", {})
    _assert(claim_values and all(value is False for value in claim_values.values()), "fixture unsupported claims", failures)
    hostile_ids = {row.get("id") for row in fixture.get("hostileCases", [])}
    required_hostile_fragments = ("package-retired", "binding-change", "same-serial", "model-treated", "cyclic", "relationship-endpoint", "unknown-semantic", "cross-workspace", "identifier-spoof", "recall-presented")
    for fragment in required_hostile_fragments:
        _assert(any(fragment in str(case_id) for case_id in hostile_ids), f"fixture hostile:{fragment}", failures)
    interruption_ids = {row.get("id") for row in fixture.get("interruptionCases", [])}
    for fragment in ("migration-boundary", "binding-boundary", "lifecycle-boundary", "scope-boundary", "backup-boundary"):
        _assert(any(fragment in str(case_id) for case_id in interruption_ids), f"fixture interruption:{fragment}", failures)
    recovery_ids = {row.get("id") for row in fixture.get("recoveryCases", [])}
    for fragment in ("backup-clone-fork", "search-report", "delete-erase", "released-v1"):
        _assert(any(fragment in str(case_id) for case_id in recovery_ids), f"fixture recovery:{fragment}", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every hydrated path to be changed; default permits the nine-path static lane")
    parser.add_argument("--json", action="store_true", help="retain machine-readable output")
    args = parser.parse_args()

    failures: list[str] = []
    candidate_paths = _candidate_changed_paths()
    unowned_changed = sorted(set(candidate_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(candidate_paths))
    _assert(not unowned_changed, "changed path outside full C39 fence", failures)
    if args.complete:
        _assert(not missing_required_changed, "required changed path missing from full C39 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 73 and len(set(contracts.PATH_FENCE)) == 73, "exact 73-path fence", failures)
    _assert(len(contracts.EXISTING_PATHS) == 58, "existing path count", failures)
    _assert(len(contracts.NEW_PATHS) == 15, "new path count", failures)
    _assert(contracts.PATH_FENCE == contracts.EXISTING_PATHS + contracts.NEW_PATHS, "path classification/order", failures)
    _assert(contracts.FENCE_DIGEST == "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", "fence digest authority", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(not set(contracts.PATH_FENCE) & {path for path in contracts.PATH_FENCE if "s10" in path.lower() or "phase10" in path.lower()}, "S10 named path", failures)
    for relative in contracts.PATH_FENCE:
        expected_at_base = relative in contracts.EXISTING_PATHS
        _assert(_base_path_exists(relative) is expected_at_base, f"BASE_HEAD existence:{relative}", failures)

    source_rows = contracts.source_artifacts(ROOT)
    _assert(len(source_rows) == 58, "source reference count", failures)
    for row in source_rows:
        _assert(_base_path_exists(row["path"]), f"missing source:{row['path']}", failures)
        base_raw = contracts._git_blob(ROOT, row["path"])
        _assert(row["bytes"] == len(base_raw), f"source bytes:{row['path']}", failures)
        _assert(row["sha256"] == contracts.sha256_bytes(base_raw), f"source digest:{row['path']}", failures)
    authority_rows = contracts.authority_artifacts(ROOT)

    try:
        fixture = _load(contracts.FIXTURE_PATH)
        schema = _load(contracts.SCHEMA_PATH)
        contract = _load(contracts.CONTRACT_PATH)
        evidence = _load(contracts.EVIDENCE_PATH)
        brand = _load(contracts.BRAND_PATH)
        manifest = _load(contracts.MANIFEST_PATH)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")
        fixture = schema = contract = evidence = brand = manifest = {}

    try:
        expected = contracts.all_outputs(ROOT)
        for relative, raw in expected.items():
            path = ROOT / relative
            _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    except (OSError, json.JSONDecodeError, TypeError, ValueError) as error:
        failures.append(f"deterministic generation:{error}")
        expected = {}

    _check_fixture(fixture, failures)
    _assert(schema == contracts.schema_document(ROOT), "schema does not equal generated fixture schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect", failures)
    _assert(schema.get("type") == "object" and schema.get("additionalProperties") is False, "schema strict root", failures)
    _check_sealed(contract, failures, "contract")
    _check_sealed(evidence, failures, "evidence")
    _check_sealed(brand, failures, "brand")
    _check_sealed(manifest, failures, "manifest")

    _assert(contract.get("artifact") == "V23P03C39AssetSemanticsContractV1", "contract artifact", failures)
    _assert(contract.get("status") == "PASS_STATIC_PROVISIONAL", "contract status", failures)
    _assert(contract.get("verificationMode") == "STATIC_ONLY", "contract mode", failures)
    _assert(contract.get("authority") == contracts._authority(), "contract authority", failures)
    _assert(contract.get("sourceProjection") == contracts._source_projection(), "contract source projection", failures)
    _assert(contract.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE, "direct prerequisite evidence", failures)
    _assert(contract.get("sourceContract", {}).get("sourceArtifacts") == source_rows, "contract source rows", failures)
    _assert(contract.get("sourceContract", {}).get("authorityArtifacts") == authority_rows, "contract authority rows", failures)
    _assert(contract.get("authority", {}).get("pathFenceDigest") == contracts.FENCE_DIGEST, "contract authority fence", failures)
    _assert(contract.get("authority", {}).get("allowedPathCount") == 73, "contract authority path count", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "lifecycle coverage", failures)
    required = contract.get("requiredSemantics", {})
    for key, value in {
        "contractNames": contracts.CONTRACT_NAMES,
        "catalogStates": contracts.CATALOG_STATES,
        "lifecycleStates": contracts.LIFECYCLE_STATES,
        "identifierReviewStates": contracts.IDENTIFIER_REVIEW_STATES,
        "provenanceKinds": contracts.PROVENANCE_KINDS,
        "subjectKinds": contracts.SUBJECT_KINDS,
        "capabilityTags": contracts.CAPABILITY_TAGS,
    }.items():
        _assert(required.get(key) == list(value), f"required semantic:{key}", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS), "contract existing paths", failures)
    _assert(contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract new paths", failures)
    _assert(contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract S10 overlap", failures)

    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL", "evidence result", failures)
    _assert(evidence.get("verificationMode") == "STATIC_ONLY", "evidence mode", failures)
    _assert(evidence.get("authority") == contracts._authority(), "evidence authority", failures)
    _assert(evidence.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE, "evidence prerequisite", failures)
    _assert(evidence.get("pathEvidence") == contract.get("pathEvidence"), "evidence path evidence", failures)
    _assert(evidence.get("pathEvidence", {}).get("sourceArtifacts") == source_rows, "evidence source rows", failures)
    _assert(evidence.get("pathEvidence", {}).get("authorityArtifacts") == authority_rows, "evidence authority rows", failures)

    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL", "brand status", failures)
    _assert(brand.get("verificationMode") == "STATIC_ONLY", "brand mode", failures)
    _assert(brand.get("affectedSurfacePaths") == [], "brand shipping surfaces", failures)
    _assert(brand.get("s10FenceOverlapPaths") == [], "brand S10 overlap", failures)

    manifest_rows = manifest.get("artifacts", [])
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("authority") == contracts._authority(), "manifest authority", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest path fence", failures)
    _assert(manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST, "manifest path fence digest", failures)
    _assert(manifest.get("pathFenceCount") == 73, "manifest fence count", failures)
    _assert(manifest.get("existingPathCount") == 58 and manifest.get("newPathCount") == 15, "manifest classification", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE), "manifest allowed paths", failures)
    _assert(manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest delete/rename paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows, "manifest source rows", failures)
    _assert(manifest.get("authorityArtifacts") == authority_rows, "manifest authority rows", failures)
    _assert([row.get("path") for row in manifest_rows] == list(contracts.MANIFEST_INPUT_PATHS), "manifest artifact paths", failures)
    for row in manifest_rows:
        _check_row(row, row.get("path", ""), failures)
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(manifest_rows), "manifest artifact set digest", failures)

    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        flags = document.get("statusFlags")
        _assert(isinstance(flags, dict), f"{label}:statusFlags", failures)
        for key in ("native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance", "hostedAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness"):
            _assert(flags.get(key) is False, f"{label}:{key} flag", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation gate", failures)

    source_text = b"\n".join(contracts._git_blob(ROOT, path) for path in contracts.AUTHORITY_REFERENCE_PATHS).decode("utf-8")
    for token in contracts.SOURCE_CONTRACT_TOKENS:
        _assert(token in source_text, f"source contract token:{token}", failures)

    result: dict[str, Any] = {
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL",
        "cardID": contracts.CARD,
        "pathFenceCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "fenceDigest": contracts.FENCE_DIGEST,
        "baseHead": contracts.BASE_HEAD,
        "baseTree": contracts.BASE_TREE,
        "unownedChangedPathCount": len(unowned_changed),
        "missingRequiredChangedPathCount": len(missing_required_changed),
        "s10FenceOverlapPaths": [],
        "native": False,
        "hosted": False,
        "adoption": False,
        "acceptance": False,
        "release": False,
    }
    if failures:
        result["failures"] = failures
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
