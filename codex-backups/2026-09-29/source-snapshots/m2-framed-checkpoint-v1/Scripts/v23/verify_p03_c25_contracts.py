#!/usr/bin/env python3
"""Verify the V23-P03-C25 static fence, corpus, and evidence artifacts."""

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

import p03_c25_contracts as contracts


class DuplicateKey(ValueError):
    """Raised when a supposedly canonical JSON object repeats a key."""


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
    row: dict[str, Any], relative: str, rendered: dict[str, bytes], failures: list[str],
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
    path = ROOT / "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift"
    if not path.is_file():
        return
    names = tuple(re.findall(
        r"\bfunc\s+(testV23P03C25[A-Z]\w*)\s*\(",
        path.read_text(encoding="utf-8"),
    ))
    _assert(names == contracts._observed_selectors(ROOT), "test selector observation", failures)
    _assert(names == tuple(contracts.TEST_METHODS) or len(names) == 5, "five test selectors", failures)


def _source_text(relative: str, failures: list[str]) -> str:
    path = ROOT / relative
    if not path.is_file():
        failures.append(f"source regression file missing:{relative}")
        return ""
    return path.read_text(encoding="utf-8")


def _require_source_tokens(
    relative: str, source: str, tokens: tuple[str, ...], failures: list[str]
) -> None:
    for token in tokens:
        _assert(token in source, f"source regression:{relative}:{token}", failures)


def _source_region(source: str, start_marker: str, end_marker: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        return ""
    end = source.find(end_marker, start + len(start_marker))
    return source[start:] if end < 0 else source[start:end]


def _check_source_regressions(failures: list[str]) -> None:
    # These checks bind the verifier to the production closure helper and its
    # concrete call sites, rather than relying on artifact prose alone.
    validator_path = "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift"
    decoder_path = "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift"
    grammar_path = "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift"
    tests_path = "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift"
    validator = _source_text(validator_path, failures)
    decoder = _source_text(decoder_path, failures)
    grammar = _source_text(grammar_path, failures)
    tests = _source_text(tests_path, failures)

    closure = _source_region(
        decoder,
        "enum SurveyDefinitionBackupGraphClosureV1 {",
        "\nstruct BackupCanonicalDecoderV1",
    )
    _require_source_tokens(
        decoder_path,
        closure,
        (
            "enum SurveyDefinitionBackupGraphClosureV1 {",
            "static func validate(",
            "history: MutationHistorySnapshotV1",
            "expectedWorkspaceID: WorkspaceID?",
            "MutationEnvelopeV1.decodeCanonical",
            "case let .applySurveyDefinition",
            "mutation.validate()",
            "eventByID",
            "mutationByEventID",
            "releaseChildCount",
            "eventChildCount",
            "release.validateSuccessor(of: predecessor)",
            "event.validateSuccessor(of: predecessor, release: release)",
            "roots",
            "heads",
            "visitedEvents",
            "visitedReleases",
            "identity.latestLifecycleEventID",
            "identity.latestLifecycleEventSHA256",
            "expectedRevisions",
            "actualRevisions",
            "history.entityRevisions",
        ),
        failures,
    )
    _require_source_tokens(
        decoder_path,
        decoder,
        ("try Self.validateSurveyDefinitions(value)",),
        failures,
    )

    validation = _source_region(
        validator,
        "func validateSurveyDefinitions(",
        "\n    func validateInspectionReview(",
    )
    _require_source_tokens(
        validator_path,
        validation,
        (
            "records.mutationHistory",
            "manifest.source.persistentSchemaVersion == 24",
            "try SurveyDefinitionBackupGraphClosureV1.validate(",
            "identities: Array(identities.values)",
            "releases: Array(releases.values)",
            "history: history",
            "expectedWorkspaceID: workspaceID",
        ),
        failures,
    )
    _assert(
        validator.count("SurveyDefinitionBackupGraphClosureV1.validate(") == 1,
        "backup closure validator call site count",
        failures,
    )

    _require_source_tokens(
        grammar_path,
        grammar,
        (
            "expressionCanBeTrue",
            "VisibilityAlternativeV1",
            "private static func alternatives",
            "private static func union",
            "private static func intersection",
            "case .not(let child):return try alternatives",
            "case .all(let children):if negated",
            "case .any(let children):if negated",
            "func merged(with other",
            "expressionIsWellTyped",
            "maximumAggregateExpressionNodes",
        ),
        failures,
    )
    nested_any = len(re.findall(r"(?:\.any|SurveyVisibilityExpressionV1\.any)\s*\(\s*\[", tests))
    _assert(nested_any >= 2, "nested-any regression cases", failures)
    _assert("XCTAssertNoThrow" in tests, "nested-any satisfiable case", failures)
    _assert("XCTAssertThrowsError" in tests, "nested-any contradictory case", failures)
    _require_source_tokens(
        tests_path,
        tests,
        (
            "V24BackupSurveyDefinitionRecordV1",
            "predecessorEventID",
            "predecessorEventSHA256",
            "latestLifecycleEventID",
            "latestLifecycleEventSHA256",
        ),
        failures,
    )

def _check_semantics(contract: dict[str, Any], evidence: dict[str, Any], failures: list[str]) -> None:
    _check_source_regressions(failures)
    required = contract.get("requiredSemantics", {})
    boundary = contract.get("persistenceBoundary", {})
    scope = contract.get("semanticScope", {})
    expected_lists = {
        "contractNames": contracts.CONTRACT_NAMES,
        "activityKinds": contracts.ACTIVITY_KINDS,
        "lifecycleStates": contracts.LIFECYCLE_STATES,
        "fieldKinds": contracts.FIELD_KINDS,
        "sensitivities": contracts.SENSITIVITY_VALUES,
        "releaseDispositions": contracts.RELEASE_DISPOSITIONS,
        "failureCases": contracts.FAILURE_VALUES,
        "subjectKinds": contracts.SUBJECT_KINDS,
        "subjectStates": contracts.SUBJECT_STATES,
        "availabilityStates": contracts.AVAILABILITY_STATES,
        "interruptionPoints": contracts.INTERRUPTION_POINTS,
    }
    for key, expected in expected_lists.items():
        _assert(required.get(key) == list(expected), f"required:{key}", failures)
    for key, expected in {
        "runtimeActivityKindEnum": "ActivityKindV1",
        "runtimeLifecycleStateEnum": "SurveyDefinitionLifecycleStateV1",
        "runtimeIdentityType": "SurveyDefinitionIdentityV1",
        "runtimeReleaseType": "SurveyDefinitionReleaseV1",
        "runtimeLifecycleEventType": "SurveyDefinitionLifecycleEventV1",
    }.items():
        _assert(required.get(key) == expected, f"runtime:{key}", failures)

    _assert(
        required.get("persistentSchemaVersion") == 24
        and required.get("recordsSchemaVersion") == 23
        and required.get("persistentKindLifecycleModelCount") == 87
        and required.get("durableFamilyCount") == 2,
        "V24/records23/87/two families", failures,
    )
    _assert(
        required.get("persistentFamilies") == ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"],
        "durable families", failures,
    )
    _assert(
        required.get("nonPersistentFamilies") == [
            "SurveyDefinitionSemanticTreeV1", "SurveyDefinitionImportPreviewV1", "SurveyDefinitionDraftScratchV1",
        ],
        "derived families", failures,
    )
    for key in (
        "derivedSemanticTree", "immutablePublishedRelease", "importAlwaysDraft",
        "publishedEditCreatesSuccessor",
    ):
        _assert(required.get(key) is True, f"required:{key}", failures)
    for key in ("liveWorkspaceMutation", "sourceBytesInProjections", "runtimeFetching", "remoteIdentity"):
        _assert(required.get(key) is False, f"closed boundary:{key}", failures)
    _assert(required.get("lifecycleEventStorage") == "EXISTING_MUTATION_ENVELOPE_AND_JOURNAL", "event journal", failures)
    _assert(required.get("genericMutationReceiptKind") == "MutationReceiptV1", "generic receipt", failures)
    _assert(required.get("fiveActivityKinds") == list(contracts.ACTIVITY_KINDS), "five activity kinds", failures)
    _assert(tuple(required.get("fiveSelectors", [])) == contracts._observed_selectors(ROOT), "five selectors", failures)
    _assert(
        required.get("templateLimits") == {
            "maxArchiveBytes": 16777216, "maxEntries": 128, "maxEntryBytes": 8388608,
            "maxPathUTF8Bytes": 240, "maxDepth": 8, "maxCompressionRatio": 20,
        },
        "arsurveytemplate limits", failures,
    )

    for key, expected in {
        "schemaVersion": 24,
        "recordsSchemaVersion": 23,
        "persistedFamilies": ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"],
        "nonPersistentFamilies": [
            "SurveyDefinitionSemanticTreeV1", "SurveyDefinitionImportPreviewV1", "SurveyDefinitionDraftScratchV1",
        ],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
    }.items():
        _assert(boundary.get(key) == expected, f"persistence boundary:{key}", failures)
    _assert(boundary.get("secondStore") is False and boundary.get("secondWriter") is False, "single store/writer", failures)
    for key in (
        "migrationRequired", "backupRestoreRequired", "deleteEraseRequired", "exportReportRequired",
        "searchRebuildRequired", "replayRequired", "classificationRequired", "interruptionRecoveryRequired",
    ):
        _assert(boundary.get(key) is True, f"lifecycle:{key}", failures)

    for token, field in {
        "IMMUTABLE_IDENTITY_AND_RELEASE": "atomicAuthorityPolicy",
        "SOLE_CANONICAL_WRITER": "atomicAuthorityPolicy",
        "ARSURVEYTemplate_HOSTILE_VALIDATION": "templatePolicy",
        "CLOSED_FIRST_GENERATION_FIELD_SET": "grammarPolicy",
        "PUBLISHED_RELEASES_IMMUTABLE": "releasePolicy",
        "DROP_UNACCEPTED_DERIVED_PREVIEWS": "replayPolicy",
        "V24_EIGHTY_SEVEN_MODELS_RECORDS23": "lifecyclePolicy",
        "EXACT_ONE_HUNDRED_TWENTY_EIGHT_PATH_RESERVATION": "s10Policy",
    }.items():
        _assert(token in str(scope.get(field, "")), f"scope:{field}:{token}", failures)

    forbidden_text = (
        " ".join(str(item) for item in required.get("forbiddenClaims", []))
        + " " + str(scope.get("forbiddenPolicy", ""))
    ).upper()
    for token in (
        "AUTOMATIC", "GENERIC_EAV", "RUNTIME_CODE", "PACKAGE_CREATED_STORAGE_TABLES",
        "SILENT", "SECOND_WRITER", "SECOND_STORE", "NETWORK", "CLOUD", "ACCOUNT",
        "PROVIDER", "ANDROID", "LEGAL", "NONREPUDIATION",
    ):
        _assert(token in forbidden_text, f"forbidden:{token}", failures)
    _assert(evidence.get("requiredSemanticsDigest") == contracts.sha256_value(required), "semantics digest", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require all C25 fence paths to be changed")
    parser.add_argument("--json", action="store_true", help="emit machine-readable evidence")
    args = parser.parse_args()

    failures: list[str] = []
    coordination_identity: dict[str, str] = {}
    try:
        coordination_identity = contracts.assert_coordination_identity(ROOT)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        failures.append(f"coordination identity:{error}")
    changed = _candidate_changed_paths()
    unowned = sorted(set(changed) - set(contracts.PATH_FENCE))
    missing = sorted(set(contracts.PATH_FENCE) - set(changed))
    rendered: dict[str, bytes] = {}
    try:
        rendered = contracts.all_outputs(ROOT)
    except (OSError, subprocess.CalledProcessError, ValueError, TypeError) as error:
        failures.append(f"render:{error}")

    _assert(not unowned, "changed path outside full C25 fence", failures)
    if args.complete:
        _assert(not missing, "required implementation path missing from C25 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 128, "path fence count", failures)
    _assert(len(contracts.EXISTING_PATHS) == 114 and len(contracts.NEW_PATHS) == 14, "path split 114+14", failures)
    _assert(len(set(contracts.PATH_FENCE)) == 128, "duplicate path fence", failures)
    _assert(
        contracts.PRIOR_FENCE_PROOF.get("fenceCount") == 62
        and contracts.PRIOR_FENCE_PROOF.get("priorOwnedPathCount") == 1032
        and contracts.PRIOR_FENCE_PROOF.get("overlapCount") == 1308
        and contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapCount") == 1308
        and contracts.PRIOR_FENCE_PROOF.get("unauthorizedOverlapCount") == 0
        and len(contracts.PRIOR_FENCE_OVERLAPS) == 1308
        and contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapEdges") == list(contracts.PRIOR_FENCE_OVERLAPS)
        and all(
            isinstance(row, dict) and isinstance(row.get("path"), str)
            and isinstance(row.get("priorCardID"), str) and isinstance(row.get("priorFenceDigest"), str)
            and isinstance(row.get("disposition"), str) and isinstance(row.get("boundEvidence"), dict)
            for row in contracts.PRIOR_FENCE_OVERLAPS
        ),
        "prior overlap proof", failures,
    )
    _assert(
        not set(contracts.PATH_FENCE) & {".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml"},
        "workflow overlap", failures,
    )
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
    _assert(schema.get("$id") == "https://assetrounds.invalid/v23/survey-definition.schema.json", "schema id", failures)
    _assert(schema.get("type") == "object" and schema.get("additionalProperties") is False, "strict schema root", failures)

    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, label, failures)
        _assert(document.get("statusFlags") == contracts._flags(), f"{label}:status flags", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:S10 reconciliation", failures)

    authority = contract.get("authority", {})
    _assert(contract.get("artifact") == "V23P03C25SurveyDefinitionContractV1", "contract artifact", failures)
    _assert(
        contract.get("cardID") == contracts.CARD
        and contract.get("status") == "PASS_STATIC_PROVISIONAL"
        and contract.get("verificationMode") == "STATIC_ONLY",
        "contract status", failures,
    )
    _assert(authority.get("appBaseHead") == contracts.BASE_HEAD and authority.get("appBaseTree") == contracts.BASE_TREE, "app base", failures)
    _assert(
        authority.get("coordinationHead") == contracts.COORDINATION_HEAD
        and authority.get("coordinationOriginMainHead") == contracts.COORDINATION_ORIGIN_MAIN_HEAD
        and authority.get("coordinationTree") == contracts.COORDINATION_TREE,
        "coordination base", failures,
    )
    _assert(
        not coordination_identity
        or (
            coordination_identity.get("head") == contracts.COORDINATION_HEAD
            and coordination_identity.get("originMain") == contracts.COORDINATION_ORIGIN_MAIN_HEAD
            and coordination_identity.get("tree") == contracts.COORDINATION_TREE
        ),
        "coordination checkout identity", failures,
    )
    _assert(
        authority.get("contextDigest") == contracts.CONTEXT_DIGEST
        and authority.get("pathFenceDigest") == contracts.FENCE_DIGEST
        and authority.get("provisionalPrerequisiteDigest") == contracts.PREREQUISITE_DIGEST,
        "authority digests", failures,
    )
    _assert(
        authority.get("coordinationLedgerDigest") == contracts.COORDINATION_LEDGER_DIGEST
        and authority.get("coordinationProjectionDigest") == contracts.COORDINATION_PROJECTION_DIGEST
        and authority.get("coordinationCASSequence") == contracts.COORDINATION_CAS_SEQUENCE
        and authority.get("hydrationTransitionSequence") == contracts.HYDRATION_TRANSITION_SEQUENCE
        and authority.get("hydrationTransitionDigest") == contracts.HYDRATION_TRANSITION_DIGEST,
        "coordination ledger/projection/transition", failures,
    )
    _assert(
        authority.get("hydrationRevision") == contracts.HYDRATION_REVISION
        and authority.get("hydrationCorrectionReceiptDigest") == contracts.HYDRATION_CORRECTION_RECEIPT_DIGEST,
        "hydration correction authority", failures,
    )
    _assert(
        authority.get("allowedPathCount") == 128
        and authority.get("existingPathCount") == 114
        and authority.get("newPathCount") == 14
        and authority.get("directPrerequisiteCards") == ["V23-P03-C24"]
        and authority.get("nextCard") == "V23-P03-C26",
        "authority path/order", failures,
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

    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _assert(document.get("priorFenceProof") == contracts.PRIOR_FENCE_PROOF, f"{label}:prior proof", failures)
        _assert(document.get("priorFenceOverlaps") == list(contracts.PRIOR_FENCE_OVERLAPS), f"{label}:prior rows", failures)
    _assert(contracts.sha256_value(contract.get("priorFenceProof")) == contracts.PRIOR_FENCE_PROOF_CANONICAL_SHA256, "prior proof digest", failures)

    _assert(evidence.get("artifact") == "V23P03C25SurveyDefinitionEvidenceReceiptV1" and evidence.get("result") == "PASS_STATIC_PROVISIONAL", "evidence result", failures)
    _assert(brand.get("artifact") == "V23P03C25BrandImpactManifestV1" and brand.get("s10FenceOverlapPaths") == [], "brand boundary", failures)
    _assert(manifest.get("artifact") == "V23P03C25ToolingManifestV1" and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence", failures)
    _assert(
        manifest.get("pathFenceCount") == 128
        and manifest.get("existingPathCount") == 114
        and manifest.get("newPathCount") == 14
        and manifest.get("sourceReferenceCount") == 114
        and manifest.get("s10FenceOverlapPaths") == [],
        "manifest counts/boundary", failures,
    )
    rows = manifest.get("artifacts", [])
    _assert(
        len(rows) == 127 and {row.get("path") for row in rows} == set(contracts.MANIFEST_INPUT_PATHS),
        "manifest rows", failures,
    )
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(rows), "manifest closure digest", failures)
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("path"), str):
            _check_row(row, row["path"], rendered, failures)
    _check_test_methods(failures)
    _assert(not list(ROOT.rglob("__pycache__")), "python cache present", failures)

    result = "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL"
    payload: dict[str, Any] = {
        "acceptance": False, "adoption": False, "cardID": contracts.CARD,
        "contextDigest": contracts.CONTEXT_DIGEST,
        "coordinationCASSequence": contracts.COORDINATION_CAS_SEQUENCE,
        "coordinationHead": contracts.COORDINATION_HEAD,
        "coordinationOriginMainHead": contracts.COORDINATION_ORIGIN_MAIN_HEAD,
        "coordinationLedgerDigest": contracts.COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": contracts.COORDINATION_PROJECTION_DIGEST,
        "coordinationTree": contracts.COORDINATION_TREE,
        "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS),
        "pathFenceCount": len(contracts.PATH_FENCE), "fenceDigest": contracts.FENCE_DIGEST,
        "missingRequiredChangedPathCount": len(missing), "missingAllowedPathCount": len(missing),
        "unownedChangedPathCount": len(unowned), "priorOwnedPathCount": contracts.PRIOR_FENCE_PROOF["priorOwnedPathCount"],
        "priorOverlapCount": contracts.PRIOR_FENCE_OVERLAP_COUNT,
        "authorizedOverlapEdgeCount": contracts.PRIOR_FENCE_PROOF["authorizedOverlapCount"],
        "hydrationTransitionSequence": contracts.HYDRATION_TRANSITION_SEQUENCE,
        "hydrationTransitionDigest": contracts.HYDRATION_TRANSITION_DIGEST,
        "native": False, "hosted": False, "release": False,
        "result": result, "s10FenceOverlapPaths": [],
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "verificationModes": 0, "persistentSchemaVersion": 24,
        "recordsSchemaVersion": 23, "modelCount": 87, "durableFamilyCount": 2,
        "activityKinds": list(contracts.ACTIVITY_KINDS),
        "testSelectors": list(contracts._observed_selectors(ROOT)),
        "selectorCount": len(contracts._observed_selectors(ROOT)),
        "statusFlags": contracts._flags(),
    }
    if failures:
        payload["failures"] = failures
    if args.json:
        print(json.dumps(payload, sort_keys=True))
    else:
        print(result)
        if failures:
            print(json.dumps(payload, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
