"""Verify Card 48's static corpus, exact fence, source evidence, and receipts."""

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

import p03_c40_contracts as contracts


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
    status = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"], check=True, capture_output=True, text=True).stdout
    paths: list[str] = []
    for line in status.splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))
    committed = subprocess.run(["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"], check=True, capture_output=True, text=True).stdout
    paths.extend(path.replace("\\", "/") for path in committed.splitlines() if path)
    return sorted(set(paths))


def _base_path_exists(relative: str) -> bool:
    return subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"], capture_output=True).returncode == 0


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
    _assert(fixture == contracts.CORPUS, "fixture equals deterministic corpus", failures)
    _assert(fixture.get("schema") == "V21P03C40AuthorityCriterionCorpusV1", "fixture schema", failures)
    _assert(fixture.get("cardID") == contracts.CARD and fixture.get("schemaVersion") == 1, "fixture identity", failures)
    _assert(fixture.get("persistence", {}).get("schemaRelease") == "PERSISTENT_SCHEMA_V11_AUTHORITY_CRITERION_DERIVATION", "fixture schema release", failures)
    _assert(fixture.get("persistence", {}).get("predecessorSchemaVersion") == 10, "fixture predecessor schema", failures)
    expected_enums = {
        "sourceTypes": contracts.SOURCE_TYPES,
        "licenseStorageDispositions": contracts.LICENSE_STORAGE_DISPOSITIONS,
        "applicabilityDispositions": contracts.APPLICABILITY_DISPOSITIONS,
        "criterionResults": contracts.CRITERION_RESULTS,
        "severityScaleStates": contracts.SEVERITY_SCALE_STATES,
        "measurementDispositions": contracts.MEASUREMENT_DISPOSITIONS,
        "derivationDispositions": contracts.DERIVATION_DISPOSITIONS,
        "lifecycleDimensions": contracts.LIFECYCLE_DIMENSIONS,
    }
    for key, values in expected_enums.items():
        _assert(fixture.get(key) == list(values), f"fixture enum:{key}", failures)
    _assert({row.get("disposition") for row in fixture.get("applicabilityContexts", [])} == set(contracts.APPLICABILITY_DISPOSITIONS), "fixture applicability closure", failures)
    _assert({row.get("criterionResult") for row in fixture.get("classificationBindings", [])} == set(contracts.CRITERION_RESULTS), "fixture criterion closure", failures)
    _assert(all(row.get("licensedBytesStored") is False and row.get("copiedSourceTextStored") is False for row in fixture.get("authoritySourceReleases", [])), "fixture source bytes absent", failures)
    _assert(all(value is False for value in fixture.get("claims", {}).values()), "fixture claims false", failures)
    hostile_ids = {str(row.get("id")) for row in fixture.get("hostileCases", [])}
    for fragment in ("adoption", "jurisdiction", "copyrighted", "digest", "duplicate", "denominator", "overflow", "dimension", "evaluator", "safe-compliant"):
        _assert(any(fragment in case_id for case_id in hostile_ids), f"fixture hostile:{fragment}", failures)
    interruption_ids = {str(row.get("id")) for row in fixture.get("interruptionCases", [])}
    for fragment in ("release", "binding", "derivation", "report", "archive", "restore", "replay"):
        _assert(any(fragment in case_id for case_id in interruption_ids), f"fixture interruption:{fragment}", failures)
    recovery_ids = {str(row.get("id")) for row in fixture.get("recoveryCases", [])}
    for fragment in ("backup", "journal", "compatibility", "search", "delete", "released"):
        _assert(any(fragment in case_id for case_id in recovery_ids), f"fixture recovery:{fragment}", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every hydrated path to be changed; default permits the nine-path static lane")
    parser.add_argument("--json", action="store_true", help="retain machine-readable output")
    args = parser.parse_args()

    failures: list[str] = []
    candidate_paths = _candidate_changed_paths()
    unowned_changed = sorted(set(candidate_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(candidate_paths))
    _assert(not unowned_changed, "changed path outside full C40 fence", failures)
    if args.complete:
        _assert(not missing_required_changed, "required changed path missing from full C40 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 86 and len(set(contracts.PATH_FENCE)) == 86, "exact 86-path fence", failures)
    _assert(len(contracts.EXISTING_PATHS) == 71, "existing path count", failures)
    _assert(len(contracts.NEW_PATHS) == 15, "new path count", failures)
    _assert(contracts.PATH_FENCE == contracts.EXISTING_PATHS + contracts.NEW_PATHS, "path classification/order", failures)
    _assert(contracts.FENCE_DIGEST == "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397", "fence digest authority", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(not set(contracts.PATH_FENCE) & {path for path in contracts.PATH_FENCE if "s10" in path.lower() or "phase10" in path.lower()}, "S10 named path", failures)
    _assert(sum(row.get("overlapCount", 0) for row in contracts.PRIOR_FENCE_OVERLAPS) == 382, "prior overlap total", failures)
    _assert(contracts.PRIOR_FENCE_PROOF.get("fenceCount") == 48 and contracts.PRIOR_FENCE_PROOF.get("priorOwnedPathCount") == 806, "prior fence proof counts", failures)
    _assert(contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapCount") == 382 and contracts.PRIOR_FENCE_PROOF.get("unauthorizedOverlapCount") == 0, "prior fence authorization", failures)
    for relative in contracts.PATH_FENCE:
        _assert(_base_path_exists(relative) is (relative in contracts.EXISTING_PATHS), f"BASE_HEAD existence:{relative}", failures)

    source_rows = contracts.source_artifacts(ROOT)
    _assert(len(source_rows) == 71, "source reference count", failures)
    for row in source_rows:
        raw = contracts._git_blob(ROOT, row["path"])
        _assert(row["bytes"] == len(raw) and row["sha256"] == contracts.sha256_bytes(raw), f"source digest:{row['path']}", failures)
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
    _assert(schema == contracts.schema_document(), "schema does not equal generated corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema" and schema.get("additionalProperties") is False, "schema strict root", failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, failures, label)
        _assert(document.get("verificationMode") == "STATIC_ONLY", f"{label}:mode", failures)
        _assert(document.get("authority") == contracts._authority(), f"{label}:authority", failures)
        _assert(document.get("statusFlags") == contracts._flags(), f"{label}:statusFlags", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation", failures)
        _assert(document.get("s10FenceOverlapPaths") == [] or document.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], f"{label}:S10 overlap", failures)

    _assert(contract.get("artifact") == "V23P03C40AuthorityCriterionContractV1" and contract.get("status") == "PASS_STATIC_PROVISIONAL", "contract identity/status", failures)
    _assert(contract.get("sourceProjection") == contracts._SOURCE_PROJECTION, "contract source projection", failures)
    _assert(contract.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE, "contract prerequisite", failures)
    _assert(contract.get("sourceContract", {}).get("sourceArtifacts") == source_rows, "contract source rows", failures)
    _assert(contract.get("sourceContract", {}).get("authorityArtifacts") == authority_rows, "contract authority rows", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "contract lifecycle", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS), "contract existing paths", failures)
    _assert(contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract new paths", failures)
    _assert(contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract path S10 overlap", failures)
    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL" and evidence.get("sourceProjection") == contracts._SOURCE_PROJECTION, "evidence result/projection", failures)
    _assert(evidence.get("pathEvidence") == contract.get("pathEvidence"), "evidence path evidence", failures)
    _assert(evidence.get("sourceContractDigest") == contracts.sha256_value(source_rows), "evidence source digest", failures)
    _assert(evidence.get("authorityArtifactDigest") == contracts.sha256_value(authority_rows), "evidence authority digest", failures)
    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL" and brand.get("affectedSurfacePaths") == [], "brand static boundary", failures)

    manifest_rows = manifest.get("artifacts", [])
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE) and manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST, "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 86 and manifest.get("existingPathCount") == 71 and manifest.get("newPathCount") == 15, "manifest path counts", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE) and manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest allowed paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows and manifest.get("authorityArtifacts") == authority_rows, "manifest source rows", failures)
    _assert([row.get("path") for row in manifest_rows] == list(contracts.MANIFEST_INPUT_PATHS), "manifest artifact paths", failures)
    for row in manifest_rows:
        _check_row(row, row.get("path", ""), failures)
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(manifest_rows), "manifest artifact set digest", failures)

    source_text = b"\n".join(contracts._git_blob(ROOT, path) for path in contracts.AUTHORITY_REFERENCE_PATHS).decode("utf-8")
    for token in contracts.SOURCE_CONTRACT_TOKENS:
        _assert(token in source_text, f"source contract token:{token}", failures)
    result: dict[str, Any] = {"result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL", "cardID": contracts.CARD, "pathFenceCount": len(contracts.PATH_FENCE), "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS), "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS), "fenceDigest": contracts.FENCE_DIGEST, "baseHead": contracts.BASE_HEAD, "baseTree": contracts.BASE_TREE, "unownedChangedPathCount": len(unowned_changed), "missingRequiredChangedPathCount": len(missing_required_changed), "s10FenceOverlapPaths": [], "native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False}
    if failures:
        result["failures"] = failures
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
