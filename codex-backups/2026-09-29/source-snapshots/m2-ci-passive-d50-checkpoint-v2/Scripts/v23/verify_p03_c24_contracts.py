#!/usr/bin/env python3
"""Verify the V23-P03-C24 static fence, corpus, and evidence artifacts."""

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

import p03_c24_contracts as contracts


class DuplicateKey(ValueError):
    """Raised when a canonical JSON object repeats a key."""


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def _load(relative: str) -> Any:
    return json.loads(
        (ROOT / relative).read_text(encoding="utf-8"),
        object_pairs_hook=_no_duplicate_keys,
    )


def _candidate_changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths: list[str] = []
    for line in status.splitlines():
        if not line:
            continue
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
    _assert(
        isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)),
        f"{label}:artifactDigest", failures,
    )


def _check_row(
    row: dict[str, Any],
    relative: str,
    rendered: dict[str, bytes],
    failures: list[str],
) -> None:
    path = ROOT / relative
    _assert(row.get("path") == relative, f"row path:{relative}", failures)
    if relative in rendered:
        raw, state = rendered[relative], "GENERATED"
    elif path.is_file():
        raw, state = path.read_bytes(), "WORKTREE"
    elif relative in contracts.EXISTING_PATHS:
        raw, state = contracts._git_blob(ROOT, relative), "BASE_HEAD"
    else:
        raw, state = b"", "MISSING_NEW_PATH"
    _assert(row.get("state") == state, f"row state:{relative}", failures)
    _assert(
        row.get("bytes") == len(raw)
        and row.get("sha256") == contracts.sha256_bytes(raw),
        f"row digest:{relative}", failures,
    )


def _check_test_methods(failures: list[str]) -> None:
    path = ROOT / "FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift"
    if not path.is_file():
        return
    names = re.findall(
        r"\bfunc\s+(testV23P03C24[A-Z]\w*)\s*\(",
        path.read_text(encoding="utf-8"),
    )
    _assert(tuple(names) == contracts.TEST_METHODS, f"test method selector mismatch: {names}", failures)


def _check_semantics(
    contract: dict[str, Any],
    evidence: dict[str, Any],
    failures: list[str],
) -> None:
    required = contract.get("requiredSemantics", {})
    boundary = contract.get("persistenceBoundary", {})
    scope = contract.get("semanticScope", {})

    for key, expected in (
        ("contractNames", contracts.CONTRACT_NAMES),
        ("roles", contracts.ROLE_VALUES),
        ("sensitivities", contracts.SENSITIVITY_VALUES),
        ("alternateTextProvenance", contracts.ALTERNATE_TEXT_PROVENANCE_VALUES),
        ("tableHeaderScopes", contracts.TABLE_HEADER_SCOPE_VALUES),
        ("assessmentStates", contracts.ASSESSMENT_STATE_VALUES),
        ("assessmentScopes", contracts.ASSESSMENT_SCOPE_VALUES),
        ("failureCases", contracts.FAILURE_VALUES),
        ("referenceKinds", contracts.REFERENCE_KINDS),
        ("provenanceKinds", contracts.PROVENANCE_KINDS),
        ("licenseScopes", contracts.LICENSE_SCOPES),
        ("releaseDispositions", contracts.RELEASE_DISPOSITIONS),
        ("subjectKinds", contracts.SUBJECT_KINDS),
        ("subjectStates", contracts.SUBJECT_STATES),
        ("availabilityStates", contracts.AVAILABILITY_STATES),
        ("interruptionPoints", contracts.INTERRUPTION_POINTS),
    ):
        _assert(required.get(key) == list(expected), f"required:{key}", failures)

    for key, expected in (
        ("runtimeRoleEnum", "AccessibleDocumentRoleV1"),
        ("runtimeSensitivityEnum", "AccessibleDocumentSensitivityV1"),
        ("runtimeAlternateTextProvenanceEnum", "AccessibleAlternateTextProvenanceV1"),
        ("runtimeTableHeaderScopeEnum", "AccessibleTableHeaderScopeV1"),
        ("runtimeAssessmentStateEnum", "AccessibleDocumentAssessmentStateV1"),
    ):
        _assert(required.get(key) == expected, f"required:{key}", failures)

    _assert(
        required.get("persistentSchemaVersion") == 23
        and required.get("recordsSchemaVersion") == 22,
        "V23 records22", failures,
    )
    _assert(
        required.get("persistentKindLifecycleModelCount") == 85
        and required.get("durableFamilyCount") == 1,
        "85 lifecycle models/one durable family", failures,
    )
    _assert(
        required.get("persistentFamilies") == ["AccessibleDocumentAssessmentReceiptV1"],
        "durable family", failures,
    )
    _assert(
        required.get("nonPersistentFamilies") == ["AccessibleDocumentSemanticTreeV1"],
        "derived family", failures,
    )
    _assert(required.get("genericMutationReceiptKind") == "MutationReceiptV1", "generic receipt", failures)
    _assert(required.get("derivedSemanticTree") is True, "derived tree", failures)
    _assert(required.get("immutableAssessmentReceipt") is True, "immutable receipt", failures)
    _assert(required.get("unsupportedClaimsFailClosed") is True, "closed claims", failures)
    _assert(
        required.get("liveWorkspaceMutation") is False
        and required.get("sourceBytesInProjections") is False
        and required.get("runtimeFetching") is False
        and required.get("remoteIdentity") is False,
        "runtime boundary", failures,
    )
    _assert(tuple(required.get("fiveSelectors", [])) == contracts.TEST_METHODS, "five selectors", failures)

    _assert(
        boundary.get("schemaVersion") == 23
        and boundary.get("recordsSchemaVersion") == 22
        and boundary.get("persistedFamilies") == ["AccessibleDocumentAssessmentReceiptV1"]
        and boundary.get("nonPersistentFamilies") == ["AccessibleDocumentSemanticTreeV1"],
        "persistence boundary", failures,
    )
    _assert(
        boundary.get("currentProjectionRowCount") == 0
        and boundary.get("providerRows") == 0
        and boundary.get("secondStore") is False
        and boundary.get("secondWriter") is False,
        "single derived/current boundary", failures,
    )
    for key in (
        "migrationRequired", "backupRestoreRequired", "deleteEraseRequired",
        "exportReportRequired", "searchRebuildRequired", "replayRequired",
        "classificationRequired", "interruptionRecoveryRequired",
    ):
        _assert(boundary.get(key) is True, f"lifecycle:{key}", failures)

    for token, field in (
        ("DERIVED_SEMANTIC_TREE", "atomicAuthorityPolicy"),
        ("IMMUTABLE_SUCCESSOR_ONLY", "atomicAuthorityPolicy"),
        ("ASSESSMENT_BINDS_EXACT_OUTPUT_BYTES", "assessmentPolicy"),
        ("STABLE_ROLE_PARENT_ORDER", "accessibilityPolicy"),
        ("DROP_UNACCEPTED_DERIVED_TREES", "replayPolicy"),
        ("V23_EIGHTY_FIVE_MODELS_RECORDS22", "lifecyclePolicy"),
        ("NO_AUTOMATIC_PDF_UA_WCAG", "forbiddenPolicy"),
        ("EXACT_ONE_HUNDRED_NINETEEN_PATH_RESERVATION", "s10Policy"),
    ):
        _assert(token in str(scope.get(field, "")), f"scope:{field}:{token}", failures)

    forbidden_text = (
        " ".join(str(item) for item in required.get("forbiddenClaims", []))
        + " " + str(scope.get("forbiddenPolicy", ""))
    ).upper()
    for token in (
        "AUTOMATIC_PDF_UA", "WCAG", "LEGAL", "INVENTED_ALTERNATE_TEXT",
        "HIDDEN_EVIDENCE", "REMOTE_DOCUMENT_SERVICE", "SNAPSHOT_MUTATION",
        "SECOND_WRITER", "CLOUD", "NETWORK", "ACCOUNT",
    ):
        _assert(token in forbidden_text, f"forbidden:{token}", failures)

    _assert(
        evidence.get("requiredSemanticsDigest") == contracts.sha256_value(required),
        "evidence semantics digest", failures,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all C24 fence paths to be changed")
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

    _assert(not unowned, "changed path outside full C24 fence", failures)
    if args.complete:
        _assert(not missing, "required implementation path missing from C24 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 119, "path fence count", failures)
    _assert(
        len(contracts.EXISTING_PATHS) == 105 and len(contracts.NEW_PATHS) == 14,
        "path split 105+14", failures,
    )
    _assert(len(set(contracts.PATH_FENCE)) == 119, "duplicate path fence", failures)
    _assert(
        contracts.PRIOR_FENCE_PROOF.get("fenceCount") == 61
        and contracts.PRIOR_FENCE_PROOF.get("priorOwnedPathCount") == 1014
        and contracts.PRIOR_FENCE_PROOF.get("overlapCount") == 1216
        and contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapCount") == 1216
        and contracts.PRIOR_FENCE_PROOF.get("unauthorizedOverlapCount") == 0
        and len(contracts.PRIOR_FENCE_OVERLAPS) == 1216
        and contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapEdges") == list(contracts.PRIOR_FENCE_OVERLAPS)
        and all(
            isinstance(row, dict)
            and isinstance(row.get("path"), str)
            and isinstance(row.get("priorCardID"), str)
            and isinstance(row.get("priorFenceDigest"), str)
            and isinstance(row.get("disposition"), str)
            and isinstance(row.get("boundEvidence"), dict)
            for row in contracts.PRIOR_FENCE_OVERLAPS
        ),
        "prior overlap proof", failures,
    )
    _assert(
        not set(contracts.PATH_FENCE)
        & {".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml"},
        "S10 workflow overlap", failures,
    )
    _assert(
        not any("s10" in path.lower() or "phase10" in path.lower() for path in contracts.PATH_FENCE),
        "S10 path overlap", failures,
    )
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
        _assert(document.get("statusFlags") == contracts._flags(), f"{label}:status flags", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation flag", failures)

    authority = contract.get("authority", {})
    _assert(contract.get("artifact") == "V23P03C24AccessibleDocumentContractV1", "contract artifact", failures)
    _assert(
        contract.get("cardID") == contracts.CARD
        and contract.get("status") == "PASS_STATIC_PROVISIONAL"
        and contract.get("verificationMode") == "STATIC_ONLY",
        "contract status", failures,
    )
    _assert(
        authority.get("appBaseHead") == contracts.BASE_HEAD
        and authority.get("appBaseTree") == contracts.BASE_TREE,
        "app base identity", failures,
    )
    _assert(
        authority.get("coordinationHead") == contracts.COORDINATION_HEAD
        and authority.get("coordinationTree") == contracts.COORDINATION_TREE,
        "coordination identity", failures,
    )
    _assert(
        authority.get("contextDigest") == contracts.CONTEXT_DIGEST
        and authority.get("pathFenceDigest") == contracts.FENCE_DIGEST
        and authority.get("provisionalPrerequisiteDigest") == contracts.PREREQUISITE_DIGEST,
        "authority digests", failures,
    )
    _assert(
        authority.get("coordinationLedgerDigest") == contracts.COORDINATION_LEDGER_DIGEST
        and authority.get("coordinationProjectionDigest") == contracts.COORDINATION_PROJECTION_DIGEST,
        "coordination ledger/projection", failures,
    )
    _assert(
        authority.get("coordinationCASSequence") == 258
        and authority.get("hydrationTransitionSequence") == 258
        and authority.get("hydrationTransitionDigest") == contracts.HYDRATION_TRANSITION_DIGEST,
        "hydration sequence/digest", failures,
    )
    _assert(
        authority.get("allowedPathCount") == 119
        and authority.get("existingPathCount") == 105
        and authority.get("newPathCount") == 14,
        "authority path counts", failures,
    )
    _assert(
        authority.get("directPrerequisiteCards") == ["V23-P03-C23"]
        and authority.get("nextCard") == "V23-P03-C25",
        "prerequisite/successor", failures,
    )
    _assert(
        authority.get("sourceDossierSHA256") == contracts.DOSSIER_SHA256
        and authority.get("sourceDossierUTF8Length") == contracts.DOSSIER_UTF8_LENGTH
        and authority.get("inheritedV21BlockSHA256") == contracts.INHERITED_V21_BLOCK_SHA256
        and authority.get("inheritedV21BlockUTF8Length") == contracts.INHERITED_V21_BLOCK_UTF8_LENGTH,
        "authority source pins", failures,
    )
    _assert(contract.get("sourceProjection") == contracts.SOURCE_PROJECTION, "source projection", failures)
    _assert(contract.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE, "direct prerequisite", failures)
    _check_semantics(contract, evidence, failures)

    for label, document in (("contract", contract), ("evidence", evidence,)):
        _assert(document.get("priorFenceProof") == contracts.PRIOR_FENCE_PROOF, f"{label}:prior proof", failures)
        _assert(document.get("priorFenceOverlaps") == list(contracts.PRIOR_FENCE_OVERLAPS), f"{label}:prior rows", failures)
    for label, document in (("brand", brand), ("manifest", manifest)):
        _assert(document.get("priorFenceProof") == contracts.PRIOR_FENCE_PROOF, f"{label}:prior proof", failures)
        _assert(document.get("priorFenceOverlaps") == list(contracts.PRIOR_FENCE_OVERLAPS), f"{label}:prior rows", failures)
    _assert(
        contracts.sha256_value(contract.get("priorFenceProof")) == contracts.PRIOR_FENCE_PROOF_CANONICAL_SHA256,
        "contract prior proof digest", failures,
    )

    _assert(
        evidence.get("artifact") == "V23P03C24AccessibleDocumentEvidenceReceiptV1"
        and evidence.get("result") == "PASS_STATIC_PROVISIONAL",
        "evidence result", failures,
    )
    _assert(
        brand.get("artifact") == "V23P03C24BrandImpactManifestV1"
        and brand.get("s10FenceOverlapPaths") == [],
        "brand boundary", failures,
    )
    _assert(
        manifest.get("artifact") == "V23P03C24ToolingManifestV1"
        and manifest.get("pathFence") == list(contracts.PATH_FENCE),
        "manifest fence", failures,
    )
    _assert(
        manifest.get("pathFenceCount") == 119
        and manifest.get("existingPathCount") == 105
        and manifest.get("newPathCount") == 14
        and manifest.get("sourceReferenceCount") == 105
        and manifest.get("s10FenceOverlapPaths") == [],
        "manifest counts/boundary", failures,
    )
    _assert(
        manifest.get("artifactSetDigest") == contracts.sha256_value(manifest.get("artifacts", [])),
        "manifest closure digest", failures,
    )
    rows = manifest.get("artifacts", [])
    _assert(
        len(rows) == 118
        and {row.get("path") for row in rows} == set(contracts.MANIFEST_INPUT_PATHS),
        "manifest rows", failures,
    )
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("path"), str):
            _check_row(row, row["path"], rendered, failures)
    _check_test_methods(failures)

    result = "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL"
    payload: dict[str, Any] = {
        "acceptance": False,
        "adoption": False,
        "cardID": contracts.CARD,
        "contextDigest": contracts.CONTEXT_DIGEST,
        "coordinationCASSequence": contracts.COORDINATION_CAS_SEQUENCE,
        "coordinationHead": contracts.COORDINATION_HEAD,
        "coordinationLedgerDigest": contracts.COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": contracts.COORDINATION_PROJECTION_DIGEST,
        "coordinationTree": contracts.COORDINATION_TREE,
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "fenceDigest": contracts.FENCE_DIGEST,
        "hosted": False,
        "hydrationTransitionDigest": contracts.HYDRATION_TRANSITION_DIGEST,
        "hydrationTransitionSequence": contracts.HYDRATION_TRANSITION_SEQUENCE,
        "missingRequiredChangedPathCount": len(missing),
        "missingAllowedPathCount": len(missing),
        "native": False,
        "newPathCount": len(contracts.NEW_PATHS),
        "pathFenceCount": len(contracts.PATH_FENCE),
        "priorOwnedPathCount": contracts.PRIOR_FENCE_PROOF["priorOwnedPathCount"],
        "priorOverlapCount": contracts.PRIOR_FENCE_OVERLAP_COUNT,
        "authorizedOverlapEdgeCount": contracts.PRIOR_FENCE_PROOF["authorizedOverlapCount"],
        "release": False,
        "result": result,
        "s10FenceOverlapPaths": [],
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "unownedChangedPathCount": len(unowned),
        "verificationModes": 0,
        "durableFamilyCount": 1,
        "persistentSchemaVersion": 23,
        "recordsSchemaVersion": 22,
        "modelCount": 85,
        "selectorCount": len(contracts.TEST_METHODS),
    }
    if failures:
        payload["failures"] = failures
    print(json.dumps(payload, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
