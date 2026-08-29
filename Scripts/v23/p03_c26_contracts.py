#!/usr/bin/env python3
"""Deterministic static contract and evidence tooling for V23-P03-C26.

The C26 lane is deliberately a static/provisional contract lane.  It seals the
guided-survey session boundary and records the exact source/fence/lifecycle
claims without adding a writer, store, renderer, transport, or provider.  The
coordination checkout is authority for the hydration pins; this module never
opens that checkout (the expansion tooling is intentionally self-contained).
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C26"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 63
TITLE = "Guided-survey sessions, typed facts, provisional subjects, publication, and lifecycle"

# Immutable app base supplied by the C26 authority task.
BASE_HEAD = "885cb7478fef5a5ee66041bcccc6e85bda8b5745"
BASE_TREE = "288762ba89bb198f492562b993e4ee401d5d4e47"

# Immutable coordination tip supplied by the C26 hydration/checkpoint.
COORDINATION_HEAD = "55db2fac6ae88856a07a909184874b7949289aba"
COORDINATION_ORIGIN_MAIN_HEAD = COORDINATION_HEAD
COORDINATION_TREE = "e36979bd9a93f8ea5ed0dfc9c0801f867593db51"
COORDINATION_CAS_SEQUENCE = 268
HYDRATION_TRANSITION_SEQUENCE = 268

# The hydration receipt supplies these values.  They are intentionally
# centralized so an authority refresh changes one small, reviewable block; no
# derived digest is silently substituted for a coordination authority pin.
_UNSET_DIGEST = "0" * 64
CONTEXT_DIGEST = "94711c712cecbf4639124e11f12d3ce43faaf2a3e7ea1133ad2d7924a64b3d09"
FENCE_DIGEST = "e4262e0f0631682dfb1196e769dda7aeab644004d35487ed7a7b3b4d99a8bf7e"
PREREQUISITE_DIGEST = "f74bafdc7120fd76e26bd2543851d2ae1981c658c655afc3638bade94c82d7c0"
HYDRATION_TRANSITION_DIGEST = "6178ba30a0e48586c4c36a5cafca69c5441a270f9469369ab08ba6e52bbddc0d"
HYDRATION_REVISION = 1
COORDINATION_LEDGER_DIGEST = "ab5b61377dd908ae25f2c5d9203fc09b697dde8e46e234e15bd1cdf7549eaf14"
COORDINATION_PROJECTION_DIGEST = "b629617ff17f03710ed6b96af601ef9fa553cbc24103ffb700359c012f26e9f5"
# The frozen reservation is inherited from prior cards and is not a C26
# hydration receipt field.
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

# C26's dossier and inherited block are immutable source slices in the pinned
# blueprint.  The exact hydration digest is separate and remains above.
DOSSIER_LINE_RANGE = (4088, 4147)
INHERITED_V21_LINE_RANGE = (14878, 14921)
DOSSIER_SHA256 = "47f14dc1c6863ffbf56a9315f93d27937ff4caf21ecbfaedbfa8d78072a9e21d"
DOSSIER_UTF8_LENGTH = 7129
INHERITED_V21_BLOCK_SHA256 = "e131548caa72172cf2c6bce51cf60a95832ab0c6f302c9560098a4185e984187"
INHERITED_V21_BLOCK_UTF8_LENGTH = 5413
REGISTER_ROW_SHA256 = "088b88845978a229355706c0a906aa6e2c06d459a80b1c34d1105a0a46ba48d4"
REGISTER_ROW_UTF8_LENGTH = 283

SCHEMA_PATH = "Scripts/v23/survey-session.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C26SurveySessionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C26SurveySessionEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C26BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C26-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c26_contracts.py",
    "Scripts/v23/generate_p03_c26_contracts.py",
    "Scripts/v23/verify_p03_c26_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

# C25's six product/test/fixture paths are existing at the C26 base.  The C25
# tooling files themselves remain source artifacts and are not silently claimed
# by this card.  Importing the prior contract only reads the expansion checkout.
try:
    _script_dir = Path(__file__).resolve().parent
    if str(_script_dir) not in sys.path:
        sys.path.insert(0, str(_script_dir))
    import p03_c25_contracts as _c25

    _C25_EXISTING = tuple(_c25.EXISTING_PATHS)
    _C25_PRODUCT = tuple(_c25.NEW_PATHS[:6])
except (ImportError, AttributeError, ValueError) as exc:  # pragma: no cover - fail closed at use
    _C25_EXISTING = ()
    _C25_PRODUCT = ()
    _C25_IMPORT_ERROR = str(exc)
else:
    _C25_IMPORT_ERROR = ""

_C26_EXISTING_ADDITIONS = (
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
)
EXISTING_PATHS = _C25_EXISTING + _C25_PRODUCT + _C26_EXISTING_ADDITIONS

NEW_PATHS = (
    "FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/SurveySessionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Workflow/SurveySessionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Workflow/SurveySessionLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_40SurveySessionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/SurveySessions/V22P03C26SurveySessionCorpusV1.json",
    *SCRIPT_PATHS,
    SCHEMA_PATH,
    CONTRACT_PATH,
    EVIDENCE_PATH,
    BRAND_PATH,
    MANIFEST_PATH,
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_REFERENCE_PATHS = EXISTING_PATHS
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

AUTHORIZED_OVERLAP_COUNT = 1466
UNAUTHORIZED_OVERLAP_COUNT = 0

CONTRACT_NAMES = (
    "SurveySessionV1",
    "FactCaptureV1",
    "ProvisionalSubjectV1",
    "SubjectPromotionReceiptV1",
    "SurveyPublicationSnapshotV1",
)
PERSISTED_FAMILIES = CONTRACT_NAMES
PACKAGE_RELEASE_REFERENCE_TYPE = "SurveyPackageReleaseReferenceV1"
PACKAGE_RELEASE_REFERENCE_FIELDS = (
    "packageReleaseID",
    "packageID",
    "packageContentVersion",
    "packageSHA256",
    "workflowSHA256",
    "releaseState",
)
PACKAGE_RELEASE_REFERENCE_FIELD_TYPES = {
    "packageReleaseID": "String",
    "packageID": "String",
    "packageContentVersion": "Int",
    "packageSHA256": "String",
    "workflowSHA256": "String",
    "releaseState": "InspectionPackageReleaseStateV1",
}
PACKAGE_RELEASE_REFERENCE_ADMISSION = "PUBLISHED_ONLY_EXACT_RELEASE_ID_PACKAGE_ID_CONTENT_VERSION_AND_PACKAGE_WORKFLOW_SHA256"
PACKAGE_RELEASE_REFERENCE_RAW_BYTES = False
NONPERSISTENT_FAMILIES = (
    "SurveySemanticTreeV1",
    "SurveyImportPreviewV1",
    "SurveyDraftScratchV1",
)
SESSION_STATES = (
    "DRAFT", "PAUSED", "REVIEW_REQUIRED", "COMPLETED", "AMENDED", "SUPERSEDED", "ARCHIVED", "DELETED",
)
SESSION_TRANSITIONS = (
    "CREATE", "PAUSE", "RESUME", "SUBMIT_FOR_REVIEW", "RETURN_FOR_AMENDMENT",
    "COMPLETE", "REOPEN_AMENDMENT", "SUPERSEDE", "ARCHIVE", "DELETE",
)
FACT_ACTIONS = ("RECORD", "CORRECT", "RETRACT", "RESOLVE_CONFLICT")
PROMOTION_ACTIONS = ("PROMOTE_TO_ASSET", "RECONCILE_AS_ALIAS", "REVERSE")
SUBJECT_STATES = ("ACTIVE", "PROMOTED", "RECONCILED_ALIAS", "PROMOTION_REVERSED", "ARCHIVED")
AVAILABILITY_STATES = ("AVAILABLE", "MISSING", "STALE", "QUARANTINED", "INCOMPATIBLE")
FAILURE_CASES = (
    "UNKNOWN_ACTIVITY_KIND", "WRONG_WORKSPACE", "WRONG_DEFINITION_RELEASE", "WRONG_PACKAGE_RELEASE", "TARGET_REVISION_CHANGED",
    "DUPLICATE_CAPTURE_ID", "CONCURRENT_FACT_CONFLICT_NO_LWW", "DIVERGENT_SAME_ID", "FORGED_SESSION_DIGEST", "FORGED_CAPTURE_DIGEST",
    "ILLEGAL_SESSION_TRANSITION", "INCOMPLETE_REQUIRED_FACT", "PASS_FAIL_CLAIM_FORBIDDEN", "DUPLICATE_PROVISIONAL_SUBJECT",
    "PROMOTION_WITHOUT_PREVIEW", "FORGED_PROMOTION_PREDECESSOR", "ALIAS_FORK", "ALIAS_CYCLE", "ARCHIVE_ORPHAN_EVENT",
    "ARCHIVE_FOREIGN_EVENT", "ARCHIVE_DISCONNECTED_EVENT", "BACKUP_MANIFEST_MISMATCH", "REPLAY_DUPLICATE_EFFECT", "REPLAY_EFFECT_BEFORE_CHECKPOINT",
    "MALFORMED_LOCAL_RECENT_PAYLOAD", "REMOTE_PROVIDER_OR_ACCOUNT_FIELD",
)
INTERRUPTION_POINTS = (
    "BEFORE_SESSION_ROW", "AFTER_SESSION_BEFORE_TRANSITION_RECEIPT", "AFTER_FACT_BEFORE_RECEIPT",
    "AFTER_PUBLICATION_BEFORE_RECEIPT", "AFTER_PROMOTION_BEFORE_RECEIPT", "RESTORE_BEFORE_RENAME",
    "SEARCH_AFTER_DROP_BEFORE_REBUILD", "ERASE_AFTER_MARKER_BEFORE_CLEANUP", "REPLAY_AFTER_EFFECT_BEFORE_CHECKPOINT",
)
TEST_METHODS = (
    "testV23P03C26G01GoldenSurveySessionCreatePauseResumeReviewPublishLifecycle",
    "testV23P03C26A01ConcurrentFactConflictHasNoLastWriteWins",
    "testV23P03C26H01HostileSessionDefinitionWorkspaceDigestAndClaimInputsFailClosed",
    "testV23P03C26I01PublicationAndPersistenceInterruptionIsOldOrNew",
    "testV23P03C26R01RecoveryPreservesImmutableSnapshotAndPromotionAliasHistory",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))

FORBIDDEN_CLAIMS = (
    "AUTOMATIC_ASSET_CREATION_OR_OCR",
    "AUTOMATIC_SUBJECT_MERGE",
    "SURVEY_AS_INSPECTION_PASS_FAIL_OR_COMPLIANCE",
    "LAST_WRITE_WINS_FACT_MERGING",
    "RUNTIME_CODE_OR_GENERIC_EAV",
    "SECOND_WRITER_OR_SECOND_STORE",
    "NETWORK_CLOUD_ACCOUNT_PROVIDER_OR_REMOTE_IDENTITY",
    "LICENSED_BYTES_OR_EXTERNAL_DURABILITY",
    "LEGAL_DIAGNOSIS_OR_NONREPUDIATION",
    "NATIVE_HOSTED_ADOPTION_ACCEPTANCE_OR_RELEASE",
    "PHASE10_OR_UI_SURFACE",
)

FLAGS = {
    "native": False,
    "hosted": False,
    "adoption": False,
    "acceptance": False,
    "release": False,
    "nativeAcceptance": False,
    "hostedAcceptance": False,
    "adoptionEvidence": False,
    "acceptanceCredit": False,
    "releaseReadiness": False,
    "phase10PollingDuringParallelExecution": False,
}

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 1,
    "predecessors": [{
        "cardID": "V23-P03-C25",
        "attemptID": 1,
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "contextDigest": _UNSET_DIGEST,
        "pathFenceDigest": _UNSET_DIGEST,
        "verificationReceiptDigest": _UNSET_DIGEST,
        "checkpointDigest": _UNSET_DIGEST,
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C25_HEAD",
    }],
    "canonicalRelationPreserved": True,
    "nonreleaseSpecialEdgeApplied": False,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "nativeCompileRan": False,
    "physicalLockedState": "REQUIRED_PENDING_OWNER",
    "acceptanceCredit": False,
    "releaseCredit": False,
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

SEMANTIC_SCOPE = {
    "sessionBoundary": "GUIDED_SURVEY_ONLY_TYPED_FACTS_PROVISIONAL_SUBJECTS_AND_IMMUTABLE_PUBLICATION",
    "activityKind": "SURVEY_ONLY_NO_INSPECTION_PASS_FAIL_RELABELLING",
    "durableOwner": list(PERSISTED_FAMILIES),
    "durableFamilies": list(PERSISTED_FAMILIES),
    "nonPersistentFamilies": list(NONPERSISTENT_FAMILIES),
    "stagingDisposition": "UNIVERSAL_DRAFT_AND_CHECKPOINT_SCRATCH_DERIVED_UNTIL_EXPLICIT_CANONICAL_RECEIPT",
    "atomicAuthorityPolicy": "SOLE_WORKSPACE_WRITER_EFFECT_BEFORE_GENERIC_DURABLE_RECEIPT_EXACT_REVISION_AND_MUTATION_ID",
    "packageReleaseAuthority": PACKAGE_RELEASE_REFERENCE_TYPE,
    "packageReleaseAuthorityFields": list(PACKAGE_RELEASE_REFERENCE_FIELDS),
    "packageReleaseAuthorityAdmission": PACKAGE_RELEASE_REFERENCE_ADMISSION,
    "packageReleaseAuthorityContainsRawBytes": PACKAGE_RELEASE_REFERENCE_RAW_BYTES,
    "publicationPolicy": "IMMUTABLE_SNAPSHOT_REPORT_BYTES_UNKNOWN_NOT_OBSERVED_ALLOWED_NO_AUTOMATIC_COMPLETION",
    "promotionPolicy": "EXPLICIT_PREVIEW_PROMOTE_OR_REVERSE_RECEIPT_NO_AUTO_MERGE_NO_DESTINATION_TRUTH_FROM_SOURCE",
    "replayPolicy": "DROP_UNACCEPTED_DERIVED_PREVIEWS_REBUILD_FROM_FIVE_IMMUTABLE_FAMILIES_AND_MUTATION_JOURNAL",
    "lifecyclePolicy": "V25_RECORDS24_NINETY_TWO_MODELS_FIVE_DURABLE_FAMILIES_BACKUP_RESTORE_CLONE_FORK_DELETE_ERASE_SEARCH_REPLAY_REPORT_RETENTION_COMPATIBILITY",
    "forbiddenPolicy": "NO_OCR_ASSET_CREATION_NO_REMOTE_FETCH_NO_RUNTIME_CODE_NO_GENERIC_EAV_NO_SECOND_STORE_OR_WRITER_NO_LEGAL_OR_COMPLIANCE_INFERENCE",
    "s10Policy": "FROZEN_S10_RESERVATION_ZERO_OVERLAP",
    "activationPolicy": "PASS_STATIC_PROVISIONAL_PRE_S10_6",
}

PERSISTENCE = {
    "schemaRelease": "SURVEY_SESSION_V1",
    "persistentSchemaVersion": 25,
    "recordsSchemaVersion": 24,
    "persistentKindLifecycleModelCount": 92,
    "durableFamilyCount": 5,
    "mode": "NEW_SCHEMA_VERSION",
    "migrationRequired": True,
    "backupRestoreRequired": True,
    "cloneForkRequired": True,
    "deleteEraseRequired": True,
    "exportReportRequired": True,
    "searchRebuildRequired": True,
    "replayRequired": True,
    "interruptionRecoveryRequired": True,
    "canonicalWriter": "V23-P02-C01",
    "canonicalSourceOfTruth": list(PERSISTED_FAMILIES),
    "persistedFamilies": list(PERSISTED_FAMILIES),
    "nonPersistentFamilies": list(NONPERSISTENT_FAMILIES),
    "currentProjectionRowCount": 0,
    "providerRows": 0,
    "secondStore": False,
    "secondWriter": False,
    "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V25_WRITE",
    "forwardFix": "DROP_DERIVED_PREVIEWS_REBUILD_FROM_IMMUTABLE_FACTS_APPEND_SUCCESSOR_NEVER_REWRITE_HISTORY",
}

REQUIRED_BEHAVIORS = (
    {
        "id": "CLOSED_TYPED_SESSION_BOUNDARY",
        "contract": "SurveySessionV1",
        "requirement": "Bind every session to workspace, survey definition release, immutable SurveyPackageReleaseReferenceV1 (release ID, package ID/content version, package SHA-256, workflow SHA-256, published state), actor, subject, revision, and exact mutation receipt; no silent rebind or raw package bytes.",
    },
    {
        "id": "TYPED_FACT_CAPTURE_AND_CONFLICT",
        "contract": "FactCaptureV1",
        "requirement": "Keep a closed typed fact vocabulary, deterministic repeat coordinates, explicit unknown/retract/conflict states, and exact predecessor references.",
    },
    {
        "id": "EXPLICIT_PROVISIONAL_SUBJECT_PROMOTION",
        "contract": "ProvisionalSubjectV1",
        "requirement": "Create no asset automatically; promotion, reversal, and alias history are explicit receipt-backed operations.",
    },
    {
        "id": "IMMUTABLE_PUBLICATION",
        "contract": "SurveyPublicationSnapshotV1",
        "requirement": "Publish immutable facts and report projections with unknown/not-observed values, and amend by successor snapshots only.",
    },
    {
        "id": "EXISTING_WRITER_AND_JOURNAL",
        "contract": "SurveySessionCoordinatorV1",
        "requirement": "Route all canonical effects through the existing WorkspaceWriter and mutation journal with effect-before-receipt and idempotent retry.",
    },
    {
        "id": "ORDERED_V25_LIFECYCLE",
        "contract": "PERSISTENT_SCHEMA_V25",
        "requirement": "Close migration, backup/restore/clone/fork, deletion/Erase, report/search/replay, retention, compatibility, interruption, and forward-fix for 92 models and five families.",
    },
)

EVIDENCE_CASES = (
    {"id": "C26-S01", "kind": "GOLDEN", "assertion": "Create, pause, resume, review, publish, amend retains exact session and definition authority."},
    {"id": "C26-S02", "kind": "ALTERNATE", "assertion": "Typed facts and repeat groups distinguish unknown, missing, outlier, and conflict without inventing inspection outcomes."},
    {"id": "C26-S03", "kind": "HOSTILE", "assertion": "Foreign, stale, duplicate, partial, forged, unavailable, and revoked inputs fail closed before canonical mutation."},
    {"id": "C26-S04", "kind": "INTERRUPTION", "assertion": "Interrupted capture, promotion, publication, amendment, and receipts retry idempotently with zero or one effect."},
    {"id": "C26-S05", "kind": "RECOVERY", "assertion": "Backup/restore/clone/fork/delete/Erase/search/replay preserve history and immutable report bytes."},
    {"id": "C26-F01", "kind": "PATH_FENCE", "assertion": "The sealed C26 fence contains exactly 137 paths: 123 existing and 14 new, with 1,466 authorized overlaps and zero unauthorized overlaps."},
    {"id": "C26-B01", "kind": "STATIC_BOUNDARY", "assertion": "Native, hosted, adoption, acceptance, release, provider, network, account, cloud, and Phase 10 flags remain false."},
)


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_blob(root: Path, relative: str) -> bytes:
    return subprocess.run(["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"], check=True, capture_output=True).stdout


def _base_path_exists(root: Path, relative: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{relative}"], capture_output=True).returncode == 0


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationOriginMainHead": COORDINATION_ORIGIN_MAIN_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "hydrationRevision": HYDRATION_REVISION,
        "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "allowedPathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "directPrerequisiteCards": ["V23-P03-C25"],
        "nextCard": "V23-P03-C27",
        "sourceDossierSHA256": DOSSIER_SHA256,
        "sourceDossierUTF8Length": DOSSIER_UTF8_LENGTH,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
        "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
        "digestPinsPending": any(value == _UNSET_DIGEST for value in (
            CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST,
            HYDRATION_TRANSITION_DIGEST,
            COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST,
            FROZEN_S10_RESERVATION_DIGEST, DOSSIER_SHA256, INHERITED_V21_BLOCK_SHA256,
        )),
    }


def _sealed(body: dict[str, Any], field: str = "artifactDigest") -> dict[str, Any]:
    result = dict(body)
    result[field] = sha256_bytes(pretty(body))
    return result


def _observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / "FieldEvidenceAppTests/V9_40SurveySessionTests.swift"
    if path.is_file():
        values = tuple(re.findall(r"\bfunc\s+(testV23P03C26(?:G|A|H|I|R)\w*)\s*\(", path.read_text(encoding="utf-8")))
        if len(values) == 5:
            return values
    return TEST_METHODS


def _source_rows(root: Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for relative in SOURCE_REFERENCE_PATHS:
        raw = _git_blob(root, relative)
        result.append({"path": relative, "source": "BASE_HEAD_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return result


def _authority_rows(root: Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for relative in AUTHORITY_REFERENCE_PATHS:
        raw = _git_blob(root, relative)
        result.append({"path": relative, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return result


def schema_document() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/survey-session.schema.json",
        "title": "V23 P03 C26 Survey Session Corpus",
        "type": "object",
        "additionalProperties": False,
        "required": ["schema", "schemaVersion", "cardID", "persistentSchemaVersion", "recordsSchemaVersion", "persistentKindLifecycleModelCount", "durableFamilyCount", "durableFamilies", "nonPersistentFamilies", "sessionStates", "sessionTransitions", "factActions", "promotionActions", "subjectStates", "availabilityStates", "failureCases", "interruptionPoints", "requiredContractNames", "statusFlags"],
        "properties": {
            "schema": {"const": "V22P03C26SurveySessionCorpusV1"},
            "schemaVersion": {"const": SCHEMA_VERSION},
            "cardID": {"const": CARD},
            "persistentSchemaVersion": {"const": 25},
            "recordsSchemaVersion": {"const": 24},
            "persistentKindLifecycleModelCount": {"const": 92},
            "durableFamilyCount": {"const": 5},
            "durableFamilies": {"type": "array", "const": list(PERSISTED_FAMILIES)},
            "nonPersistentFamilies": {"type": "array", "const": list(NONPERSISTENT_FAMILIES)},
            "sessionStates": {"type": "array", "const": list(SESSION_STATES)},
            "sessionTransitions": {"type": "array", "const": list(SESSION_TRANSITIONS)},
            "factActions": {"type": "array", "const": list(FACT_ACTIONS)},
            "promotionActions": {"type": "array", "const": list(PROMOTION_ACTIONS)},
            "subjectStates": {"type": "array", "const": list(SUBJECT_STATES)},
            "availabilityStates": {"type": "array", "const": list(AVAILABILITY_STATES)},
            "failureCases": {"type": "array", "const": list(FAILURE_CASES)},
            "interruptionPoints": {"type": "array", "const": list(INTERRUPTION_POINTS)},
            "requiredContractNames": {"type": "array", "const": list(CONTRACT_NAMES)},
            "statusFlags": {"type": "object", "additionalProperties": {"const": False}},
        },
    }


def corpus_document() -> dict[str, Any]:
    return {
        "schema": "V22P03C26SurveySessionCorpusV1",
        "schemaVersion": SCHEMA_VERSION,
        "cardID": CARD,
        "synthetic": True,
        "containsCustomerData": False,
        "containsSecrets": False,
        "persistentSchemaVersion": 25,
        "recordsSchemaVersion": 24,
        "persistentKindLifecycleModelCount": 92,
        "durableFamilyCount": 5,
        "durableFamilies": list(PERSISTED_FAMILIES),
        "nonPersistentFamilies": list(NONPERSISTENT_FAMILIES),
        "requiredContractNames": list(CONTRACT_NAMES),
        "sessionStates": list(SESSION_STATES),
        "sessionTransitions": list(SESSION_TRANSITIONS),
        "factActions": list(FACT_ACTIONS),
        "promotionActions": list(PROMOTION_ACTIONS),
        "subjectStates": list(SUBJECT_STATES),
        "availabilityStates": list(AVAILABILITY_STATES),
        "failureCases": list(FAILURE_CASES),
        "interruptionPoints": list(INTERRUPTION_POINTS),
        "requiredBehaviors": list(REQUIRED_BEHAVIORS),
        "evidenceCases": list(EVIDENCE_CASES),
        "forbiddenClaims": list(FORBIDDEN_CLAIMS),
        "persistence": PERSISTENCE,
        "statusFlags": dict(FLAGS),
    }


def _required_semantics(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "contractNames": list(CONTRACT_NAMES),
        "persistentSchemaVersion": 25,
        "recordsSchemaVersion": 24,
        "persistentKindLifecycleModelCount": 92,
        "durableFamilyCount": 5,
        "persistentFamilies": list(PERSISTED_FAMILIES),
        "nonPersistentFamilies": list(NONPERSISTENT_FAMILIES),
        "sessionStates": list(SESSION_STATES),
        "sessionTransitions": list(SESSION_TRANSITIONS),
        "factActions": list(FACT_ACTIONS),
        "promotionActions": list(PROMOTION_ACTIONS),
        "subjectStates": list(SUBJECT_STATES),
        "availabilityStates": list(AVAILABILITY_STATES),
        "interruptionPoints": list(INTERRUPTION_POINTS),
        "fiveSelectors": list(selectors),
        "immutableDefinitionAndPackageBinding": True,
        "packageReleaseReferenceType": PACKAGE_RELEASE_REFERENCE_TYPE,
        "packageReleaseReferenceFields": list(PACKAGE_RELEASE_REFERENCE_FIELDS),
        "packageReleaseReferenceFieldTypes": dict(PACKAGE_RELEASE_REFERENCE_FIELD_TYPES),
        "packageReleaseReferenceAdmission": PACKAGE_RELEASE_REFERENCE_ADMISSION,
        "packageReleaseReferenceContainsRawBytes": PACKAGE_RELEASE_REFERENCE_RAW_BYTES,
        "typedFactsOnly": True,
        "unknownAndNotObservedAllowed": True,
        "derivedSemanticTree": True,
        "explicitPromotionAndReversal": True,
        "immutablePublication": True,
        "effectBeforeReceipt": True,
        "idempotentRetry": True,
        "liveWorkspaceMutation": False,
        "automaticCompliance": False,
        "runtimeFetching": False,
        "remoteIdentity": False,
        "sourceBytesInProjections": False,
        "lifecycleEventStorage": "EXISTING_MUTATION_ENVELOPE_AND_JOURNAL",
        "genericMutationReceiptKind": "MutationReceiptV1",
        "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    }


def contract_document(schema_row: dict[str, Any], selectors: tuple[str, ...]) -> dict[str, Any]:
    required = _required_semantics(selectors)
    register_row = "| 63 | <a id=\"v23-p03-c26-register\"></a>[`V23-P03-C26`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c26) | Guided-survey sessions, typed facts, provisional subjects, publication, and lifecycle | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C25` | `EXACT_WITH_GENERATION_REBIND` |\n"
    body = {
        "artifact": "V23P03C26SurveySessionContractV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "title": TITLE,
        "authority": _authority(),
        "sourceProjection": {
            "dossierLineRange": list(DOSSIER_LINE_RANGE),
            "inheritedV21BlockLineRange": list(INHERITED_V21_LINE_RANGE),
            "dossierSHA256": DOSSIER_SHA256,
            "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
            "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
            "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
            "registerRow": register_row,
            "registerRowSHA256": REGISTER_ROW_SHA256,
            "registerRowUTF8Length": REGISTER_ROW_UTF8_LENGTH,
            "directPrerequisiteCard": "V23-P03-C25",
            "deterministicEvidenceIDs": list(EVIDENCE_IDS),
            "priorFenceOverlapCount": AUTHORIZED_OVERLAP_COUNT,
            "priorFenceUnauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        },
        "requiredSemantics": required,
        "semanticScope": SEMANTIC_SCOPE,
        "persistenceBoundary": PERSISTENCE,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "priorFenceProof": {
            "overlapCount": AUTHORIZED_OVERLAP_COUNT,
            "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
            "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
            "edgeMaterialization": "COORDINATION_RECEIPT_BOUND_AT_HYDRATION",
        },
        "evidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(selectors),
        "schemaArtifact": schema_row,
        "statusFlags": dict(FLAGS),
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract: dict[str, Any], selectors: tuple[str, ...]) -> dict[str, Any]:
    required = contract["requiredSemantics"]
    body = {
        "artifact": "V23P03C26SurveySessionEvidenceReceiptV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
        "requiredSemanticsDigest": sha256_value(required),
        "requiredSemantics": required,
        "evidenceCases": list(EVIDENCE_CASES),
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(selectors),
        "schemaArtifact": schema_row,
        "priorFenceProof": {
            "overlapCount": AUTHORIZED_OVERLAP_COUNT,
            "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
            "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        },
        "staticBoundary": "NO_NATIVE_HOSTED_ADOPTION_ACCEPTANCE_RELEASE_PROVIDER_NETWORK_ACCOUNT_CLOUD_OR_PHASE10_CLAIM",
        "statusFlags": dict(FLAGS),
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def brand_document(contract: dict[str, Any]) -> dict[str, Any]:
    body = {
        "artifact": "V23P03C26BrandImpactManifestV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "brandSurfaceDelta": True,
        "uiSurfaceDelta": False,
        "impact": "GUIDED_SURVEY_SESSIONS_TYPED_FACTS_PROVISIONAL_SUBJECTS_AND_IMMUTABLE_PUBLICATION_WITHOUT_NEW_UI_OR_S10_ASSETS",
        "preserved": ["sole-workspace-writer", "generic-mutation-receipt", "existing-journal", "immutable-report-bytes", "local-only-privacy-boundary"],
        "deferred": ["native-build", "hosted-CI", "adoption", "acceptance", "release", "provider", "network", "account", "cloud", "Phase10"],
        "pathFenceCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "s10FenceOverlapPaths": [],
        "authorityContextDigest": CONTEXT_DIGEST,
        "authorityFenceDigest": FENCE_DIGEST,
        "priorFenceOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "priorFenceUnauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "statusFlags": dict(FLAGS),
        "requiresAcceptedS10_6Reconciliation": True,
        "contractDigest": contract["artifactDigest"],
    }
    return _sealed(body)


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    path = root / relative
    if relative in rendered:
        raw, state = rendered[relative], "GENERATED"
    elif path.is_file():
        raw, state = path.read_bytes(), "WORKTREE"
    elif relative in EXISTING_PATHS:
        raw, state = _git_blob(root, relative), "BASE_HEAD"
    else:
        raw, state = b"", "MISSING_NEW_PATH"
    return {"path": relative, "state": state, "bytes": len(raw), "sha256": sha256_bytes(raw)}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_corpus()
    source_rows = _source_rows(root)
    authority_rows = _authority_rows(root)
    selectors = _observed_selectors(root)
    corpus = corpus_document()
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract = contract_document(schema_row, selectors)
    evidence = evidence_document(source_rows, authority_rows, schema_row, contract, selectors)
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: schema_raw,
        CONTRACT_PATH: pretty(contract),
        EVIDENCE_PATH: pretty(evidence),
        BRAND_PATH: pretty(brand_document(contract)),
    }
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "artifact": "V23P03C26ToolingManifestV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "pathFence": list(PATH_FENCE),
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "pathFenceCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS),
        "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "artifacts": rows,
        "artifactSetDigest": sha256_value(rows),
        "sourceProjection": contract["sourceProjection"],
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "persistenceBoundary": PERSISTENCE,
        "priorFenceProof": {
            "overlapCount": AUTHORIZED_OVERLAP_COUNT,
            "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
            "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        },
        "s10FenceOverlapPaths": [],
        "statusFlags": dict(FLAGS),
        "requiresAcceptedS10_6Reconciliation": True,
        "evidenceDigest": evidence["artifactDigest"],
        "testSelectors": list(selectors),
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def assert_corpus() -> None:
    if _C25_IMPORT_ERROR:
        raise ValueError(f"C25 source contract unavailable: {_C25_IMPORT_ERROR}")
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (123, 14, 137):
        raise ValueError(f"C26 path fence must be exactly 137=123+14, got {len(EXISTING_PATHS)}+{len(NEW_PATHS)}")
    if len(set(PATH_FENCE)) != 137:
        raise ValueError("C26 path fence contains duplicates")
    if PERSISTENCE["persistentSchemaVersion"] != 25 or PERSISTENCE["recordsSchemaVersion"] != 24:
        raise ValueError("C26 persistence versions differ")
    if PERSISTENCE["persistentKindLifecycleModelCount"] != 92 or PERSISTENCE["durableFamilyCount"] != 5:
        raise ValueError("C26 model/family counts differ")
    if tuple(PERSISTENCE["persistedFamilies"]) != PERSISTED_FAMILIES:
        raise ValueError("C26 durable family set differs")
    if PERSISTENCE["secondStore"] or PERSISTENCE["secondWriter"]:
        raise ValueError("C26 second store/writer is prohibited")
    if AUTHORIZED_OVERLAP_COUNT != 1466 or UNAUTHORIZED_OVERLAP_COUNT != 0:
        raise ValueError("C26 prior overlap counts differ")
    if any("s10" in path.lower() or "phase10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C26 path fence overlaps S10/Phase10")


assert_corpus()
