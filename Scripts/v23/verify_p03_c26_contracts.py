#!/usr/bin/env python3
"""Fail-closed verifier for the V23-P03-C26 static fence and artifacts."""
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
import p03_c26_contracts as contracts


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


def _changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths: set[str] = set()
    for line in status.splitlines():
        if line:
            value = line[3:]
            paths.add((value.split(" -> ", 1)[-1]).replace("\\", "/"))
    committed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths.update(item.replace("\\", "/") for item in committed.splitlines() if item)
    return sorted(paths)


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], label: str, failures: list[str]) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_source_tokens(failures: list[str]) -> None:
    test_path = ROOT / "FieldEvidenceAppTests/V9_40SurveySessionTests.swift"
    if test_path.is_file():
        text = test_path.read_text(encoding="utf-8")
        observed = tuple(re.findall(r"\bfunc\s+(testV23P03C26(?:G|A|H|I|R)\w*)\s*\(", text))
        _assert(len(observed) == 5, "five C26 test selectors", failures)
        _assert(observed == tuple(contracts.TEST_METHODS), "C26 selector names", failures)
        for token in ("SurveySession", "FactCapture", "ProvisionalSubject", "Promotion", "Publication", "XCTAssert"):
            _assert(token in text, f"C26 test token:{token}", failures)

    authority_path = ROOT / "FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift"
    if not authority_path.is_file():
        return
    authority_source = authority_path.read_text(encoding="utf-8")
    reference_start = authority_source.find("struct SurveyPackageReleaseReferenceV1")
    authority_start = authority_source.find("struct SurveySessionAuthorityV1")
    authority_end = authority_source.find("struct ProvisionalSubjectReferenceV1", authority_start)
    _assert(reference_start >= 0 and authority_start > reference_start, "immutable package-release reference declaration", failures)
    if reference_start >= 0 and authority_start > reference_start:
        reference_body = authority_source[reference_start:authority_start]
        for field in contracts.PACKAGE_RELEASE_REFERENCE_FIELDS:
            _assert(re.search(rf"\b{re.escape(field)}\b", reference_body) is not None, f"package-release pin field:{field}", failures)
            expected_type = contracts.PACKAGE_RELEASE_REFERENCE_FIELD_TYPES[field]
            _assert(re.search(rf"\b{re.escape(field)}\s*:\s*{re.escape(expected_type)}\b", reference_body) is not None, f"package-release pin type:{field}", failures)
        _assert(re.search(r"init\s*\(\s*_\s*release\s*:\s*InspectionPackageReleaseV1", reference_body) is not None, "package-release reference initializer", failures)
        _assert(re.search(r"validate\s*\(\s*against\s+release\s*:\s*InspectionPackageReleaseV1", reference_body) is not None, "package-release reference validation", failures)
        _assert("release.state == .published" in reference_body, "package-release published admission", failures)
    if authority_start >= 0:
        authority_body = authority_source[authority_start:authority_end if authority_end > authority_start else len(authority_source)]
        _assert(re.search(r"let\s+packageRelease\s*:\s*SurveyPackageReleaseReferenceV1", authority_body) is not None, "session authority package-release reference type", failures)
        for forbidden in (r"\bData\b", r"rawPackage", r"packageBytes", r"sourceBytes"):
            _assert(re.search(forbidden, authority_body, flags=re.IGNORECASE) is None, f"session authority raw package bytes:{forbidden}", failures)


def _check_semantics(schema: dict[str, Any], contract: dict[str, Any], evidence: dict[str, Any], failures: list[str]) -> None:
    required = contract.get("requiredSemantics", {})
    expected = {
        "contractNames": list(contracts.CONTRACT_NAMES),
        "persistentSchemaVersion": 25,
        "recordsSchemaVersion": 24,
        "persistentKindLifecycleModelCount": 92,
        "durableFamilyCount": 5,
        "persistentFamilies": list(contracts.PERSISTED_FAMILIES),
        "nonPersistentFamilies": list(contracts.NONPERSISTENT_FAMILIES),
        "sessionStates": list(contracts.SESSION_STATES),
        "sessionTransitions": list(contracts.SESSION_TRANSITIONS),
        "factActions": list(contracts.FACT_ACTIONS),
        "promotionActions": list(contracts.PROMOTION_ACTIONS),
        "subjectStates": list(contracts.SUBJECT_STATES),
        "availabilityStates": list(contracts.AVAILABILITY_STATES),
        "interruptionPoints": list(contracts.INTERRUPTION_POINTS),
        "packageReleaseReferenceType": contracts.PACKAGE_RELEASE_REFERENCE_TYPE,
        "packageReleaseReferenceFields": list(contracts.PACKAGE_RELEASE_REFERENCE_FIELDS),
        "packageReleaseReferenceFieldTypes": dict(contracts.PACKAGE_RELEASE_REFERENCE_FIELD_TYPES),
        "packageReleaseReferenceAdmission": contracts.PACKAGE_RELEASE_REFERENCE_ADMISSION,
        "packageReleaseReferenceContainsRawBytes": contracts.PACKAGE_RELEASE_REFERENCE_RAW_BYTES,
    }
    for key, value in expected.items():
        _assert(required.get(key) == value, f"required:{key}", failures)
    for key in ("immutableDefinitionAndPackageBinding", "typedFactsOnly", "unknownAndNotObservedAllowed", "derivedSemanticTree", "explicitPromotionAndReversal", "immutablePublication", "effectBeforeReceipt", "idempotentRetry"):
        _assert(required.get(key) is True, f"required:{key}", failures)
    for key in ("liveWorkspaceMutation", "automaticCompliance", "runtimeFetching", "remoteIdentity", "sourceBytesInProjections", "packageReleaseReferenceContainsRawBytes"):
        _assert(required.get(key) is False, f"closed boundary:{key}", failures)
    _assert(required.get("lifecycleEventStorage") == "EXISTING_MUTATION_ENVELOPE_AND_JOURNAL", "event journal", failures)
    _assert(required.get("genericMutationReceiptKind") == "MutationReceiptV1", "generic receipt", failures)
    _assert(tuple(required.get("fiveSelectors", [])) == contracts._observed_selectors(ROOT), "five selectors", failures)
    _assert(schema == contracts.schema_document(), "schema document mismatch", failures)
    _assert(evidence.get("requiredSemanticsDigest") == contracts.sha256_value(required), "required semantics digest", failures)
    _assert(contract.get("directPrerequisiteEvidence", {}).get("successorCardID") == contracts.CARD, "prerequisite successor", failures)
    _assert(contract.get("directPrerequisiteEvidence", {}).get("ordinaryDirectEdgeCount") == 1, "one direct prerequisite", failures)
    _assert(contract.get("directPrerequisiteEvidence", {}).get("predecessors", [{}])[0].get("cardID") == "V23-P03-C25", "C25 prerequisite", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every fenced path to be changed")
    parser.add_argument("--json", action="store_true", help="emit machine-readable result")
    args = parser.parse_args()

    failures: list[str] = []
    try:
        contracts.assert_corpus()
        rendered = contracts.all_outputs(ROOT)
    except (OSError, subprocess.CalledProcessError, TypeError, ValueError) as error:
        rendered = {}
        failures.append(f"render:{error}")

    changed = _changed_paths()
    unowned = sorted(set(changed) - set(contracts.PATH_FENCE))
    missing = sorted(set(contracts.PATH_FENCE) - set(changed))
    _assert(not unowned, "changed path outside C26 fence:" + ",".join(unowned), failures)
    if args.complete:
        _assert(not missing, "required C26 path missing:" + ",".join(missing), failures)
    _assert(len(contracts.EXISTING_PATHS) == 123 and len(contracts.NEW_PATHS) == 14 and len(contracts.PATH_FENCE) == 137, "137=123+14 path split", failures)
    _assert(len(set(contracts.PATH_FENCE)) == 137, "unique C26 fence", failures)
    _assert(contracts.AUTHORIZED_OVERLAP_COUNT == 1466 and contracts.UNAUTHORIZED_OVERLAP_COUNT == 0, "1466 authorized/0 unauthorized overlaps", failures)
    _assert(not any("s10" in path.lower() or "phase10" in path.lower() for path in contracts.PATH_FENCE), "S10/Phase10 fence overlap", failures)
    _assert(all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (contracts.BASE_HEAD, contracts.COORDINATION_HEAD)), "authority commit pins", failures)
    _assert(all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (contracts.BASE_TREE, contracts.COORDINATION_TREE)), "authority tree pins", failures)
    _assert(all(re.fullmatch(r"[0-9a-f]{64}", value) for value in (
        contracts.CONTEXT_DIGEST, contracts.FENCE_DIGEST, contracts.PREREQUISITE_DIGEST,
        contracts.HYDRATION_TRANSITION_DIGEST,
        contracts.COORDINATION_LEDGER_DIGEST, contracts.COORDINATION_PROJECTION_DIGEST,
        contracts.FROZEN_S10_RESERVATION_DIGEST,
    )), "authority digest formats", failures)
    _assert(not any(value == contracts._UNSET_DIGEST for value in (
        contracts.CONTEXT_DIGEST, contracts.FENCE_DIGEST, contracts.PREREQUISITE_DIGEST,
        contracts.HYDRATION_TRANSITION_DIGEST,
        contracts.COORDINATION_LEDGER_DIGEST, contracts.COORDINATION_PROJECTION_DIGEST,
        contracts.FROZEN_S10_RESERVATION_DIGEST,
    )), "C26 hydration digest pins are not yet bound", failures)
    for relative in contracts.EXISTING_PATHS:
        _assert(contracts._base_path_exists(ROOT, relative), f"existing absent at BASE_HEAD:{relative}", failures)
    for relative in contracts.NEW_PATHS:
        _assert(not contracts._base_path_exists(ROOT, relative), f"new existed at BASE_HEAD:{relative}", failures)

    documents: dict[str, Any] = {}
    try:
        for relative in (contracts.SCHEMA_PATH, contracts.CONTRACT_PATH, contracts.EVIDENCE_PATH, contracts.BRAND_PATH, contracts.MANIFEST_PATH):
            documents[relative] = _load(relative)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")

    for relative, raw in rendered.items():
        path = ROOT / relative
        _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    for relative in (contracts.CONTRACT_PATH, contracts.EVIDENCE_PATH, contracts.BRAND_PATH, contracts.MANIFEST_PATH):
        if isinstance(documents.get(relative), dict):
            _check_sealed(documents[relative], relative, failures)
    schema = documents.get(contracts.SCHEMA_PATH, {})
    contract = documents.get(contracts.CONTRACT_PATH, {})
    evidence = documents.get(contracts.EVIDENCE_PATH, {})
    manifest = documents.get(contracts.MANIFEST_PATH, {})
    if isinstance(schema, dict) and isinstance(contract, dict) and isinstance(evidence, dict):
        _check_semantics(schema, contract, evidence, failures)
    if isinstance(manifest, dict):
        _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest path fence", failures)
        _assert(manifest.get("fullFencePaths") == list(contracts.FULL_FENCE_PATHS), "manifest full fence", failures)
        _assert(manifest.get("pathFenceCount") == 137, "manifest fence count", failures)
        _assert(manifest.get("existingPathCount") == 123 and manifest.get("newPathCount") == 14, "manifest path split", failures)
        _assert(manifest.get("manifestInputCount") == len(contracts.MANIFEST_INPUT_PATHS), "manifest input count", failures)
        rows = manifest.get("artifacts")
        _assert(isinstance(rows, list) and len(rows) == len(contracts.MANIFEST_INPUT_PATHS), "manifest rows", failures)
        if isinstance(rows, list):
            _assert([row.get("path") for row in rows] == list(contracts.MANIFEST_INPUT_PATHS), "manifest row order", failures)
            _assert(len({row.get("path") for row in rows}) == len(rows), "manifest row uniqueness", failures)
            expected_rows = [contracts._manifest_row(ROOT, path, rendered) for path in contracts.MANIFEST_INPUT_PATHS]
            _assert(rows == expected_rows, "manifest row digests", failures)
            _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(rows), "manifest artifact set digest", failures)
        _assert(manifest.get("statusFlags") == contracts.FLAGS, "manifest flags", failures)
        _assert(manifest.get("priorFenceProof", {}).get("authorizedOverlapCount") == 1466 and manifest.get("priorFenceProof", {}).get("unauthorizedOverlapCount") == 0, "manifest overlap proof", failures)
    _check_source_tokens(failures)

    payload = {
        "cardID": contracts.CARD,
        "result": "PASS" if not failures else "FAIL",
        "complete": args.complete,
        "changedPathCount": len(changed),
        "fencePathCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "missingPathCount": len(missing),
        "unownedPathCount": len(unowned),
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "digestPinsPending": contracts._authority()["digestPinsPending"],
        "failures": failures,
    }
    if args.json:
        print(json.dumps(payload, sort_keys=True, indent=2))
    else:
        print(f"C26 verifier {payload['result']}: {len(failures)} failure(s)")
        for failure in failures:
            print(f"- {failure}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
