#!/usr/bin/env python3
"""Deterministic static contract, corpus, and evidence builders for V23-P03-C22.

The C22 tooling lane records the sealed recovery-verification authority for an
isolated dry restore and deterministic replay.  It is deliberately static:
native compilation, hosted dispatch, adoption, acceptance, release, provider,
network, cloud, and Phase 10 claims all remain false.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import base64
import zlib
from pathlib import Path
from typing import Any


CARD = "V23-P03-C22"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 59
TITLE = "Recovery-point frontier/freshness truth with isolated dry restore and replay receipts"
BASE_HEAD = "4c766c0c35a9519828dc08c5e864e1c8a3490ff9"
BASE_TREE = "cd72c09b15b7e8a84610b9a080ccf598360b4f25"
COORDINATION_HEAD = "55d25b8ffdc4034284a0bd36bc15018f9cd3fc5d"
COORDINATION_TREE = "2a14cecfc48da23cebde20b6f04d87b4ea224f5f"
COORDINATION_LEDGER_DIGEST = "02c89502863681f168dc5dfcdcbac3ababd796b388c70d73fc304b56efbd2202"
COORDINATION_PROJECTION_DIGEST = "903207f5c1b59b2661910cb32670795c2bb74c0e6c7ddcfad1b24227e24ed763"
COORDINATION_CAS_SEQUENCE = 250
HYDRATION_TRANSITION_SEQUENCE = 250
HYDRATION_TRANSITION_DIGEST = "e4a5fccd7c704a24dafd4ef2252d4fe1f73584f87eef387f2ed45fab209888a4"
CONTEXT_DIGEST = "4e2d0c1f46926387a8e15a798d551744fa23448c4790f466a4d5d3903d026dc4"
FENCE_DIGEST = "c34e0f79176c9213abc467ff20e6f70282ded318b919768dbfd4506883fc2f40"
PREREQUISITE_DIGEST = "30acd280a136690d9f99d51b851313db62bee409f6b83d53b2adc0ee4294b279"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "9e05fcb44c63528e6085ec2c685d4322b838331727ccebb9c096a519a5d9f27b"
REGISTER_ROW_UTF8_LENGTH = 282
DOSSIER_SHA256 = "6f4817ca4e5d32be7bd07e4f9a1aa81e69dcbdd796f0422f6ad271c5316dc285"
DOSSIER_UTF8_LENGTH = 7222
INHERITED_V21_BLOCK_SHA256 = "116f16c8bef0d37fd98f93f5381362e69a24fc0240ad4d789c9de1d9666d0176"
INHERITED_V21_BLOCK_UTF8_LENGTH = 8972

SCHEMA_PATH = "Scripts/v23/recoverability-verification.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C22RecoverabilityVerificationContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C22RecoverabilityVerificationEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C22RecoverabilityVerificationBrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C22-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c22_contracts.py",
    "Scripts/v23/generate_p03_c22_contracts.py",
    "Scripts/v23/verify_p03_c22_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS


# Exact hydration order: 42 concrete existing archive/backup/persistence,
# protection/journal/diagnostic/test owners followed by C22's fourteen new
# contract, persistence, test, fixture, and tooling paths.
EXISTING_PATHS = (
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Backup/RecoverabilityVerificationContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/RecoverabilityVerificationPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Backup/RecoverabilityVerificationCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/RecoverabilityVerificationLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_36RecoverabilityVerificationTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Recoverability/V21P03C22RecoverabilityVerificationCorpusV1.json",
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

PRIOR_FENCE_OVERLAP_COUNT = 647
PRIOR_FENCE_PRIOR_OWNED_PATH_COUNT = 984
PRIOR_FENCE_PROOF_CANONICAL_SHA256 = "c4017152aacdda3d799e5c95b29985b3f75e987d282ae08fff8cd6a091e9c146"
PRIOR_FENCE_PROOF_CANONICAL_RAW_BYTES = 566606

# This is the exact canonical priorFenceProof from the sealed C22
# BootstrapPathFenceV1.  It is compressed only in the Python source so the
# generated contract/evidence/manifest artifacts expand every path-level edge
# and its boundEvidence without consulting the coordination checkout.
_PRIOR_FENCE_PROOF_ZLIB_BASE64 = (
    "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"
    "sT/l9pKvXtgHkaR5JDt3vCJRJJ8qkptJpPJrnuaTmyeCT356xUpFqSiVe1T+lEXrEW+ZqxJVsjYlL/ztF48vOqhKVMlalRy9np43UStqRa18mE++qxgVM76Y"
    "f/dJ30N6c/lGjv3VE66X7VH1bRWNolE0N2g2bxSNolE0+8+5ol7Uy7q93K7+1Yt6US+P8fJc/qSXfPeZlEu9KFM0imbPib4UjIJZK5jbp4//xOaEX17I6355"
    "4VWOylE5e06Zp2bUzOrMfIgUegpJISmk3VLqqSE1tGpDe0qxp47U0aod/X41dyox8Jr0uU4lo2T+LZmbueVrfnOXP+YrqvKNX9SNulE3D7r57uKuDrF+kEDh"
    "KJxHwfnX5dV/vXtLlf91dXHNVweN3l7rY54qR+X8XQnFFZJCGh7SLgnGFYgCWQ+QhQnHFYkiWQ8Sf3B9+fqi3j2cpkJUiArZPUW/ClEhKxHywsA5mL/c/FIl"
    "qkSV/DnpMpgX093iyzfcbt/E/zXvn2JRLIrlL1jcb29B6pWXMlEm72ESDy9fy4suysUrmUkOL6/e/vTuSM7RnR01o2bUzL818/zy1UXVyUWhKJQPVolP3aib"
    "FbnZT2U+RaNo1oNmcaU+ZaJM1sNkD5X7PiEw1I3zXINsJEIqTU5IwZCgosOAJqPNU61HnAFjbCk5NhtstckW6GCqNyY7DsYFU5JBDJx5HkyeBwM2R4yyGcIq"
    "/eAYrSGfDWZE6tnWJDpyc8UxF9dMEVccW6k5J+QWZsC0lm33zYHzKbUWIgi/6tMEzFkrXV2RMiDF6Bx7YAnWxGxclsEAUp8F44vLvYLh0JGkDVXE9ojeZOuC"
    "BLurKAZk/JBxR46gTQOQNMQVqK3KqPQAGAY0LYWYfaoppeByBB+rjAsorOUwUihoZM9WWBtfmjcROKPLSYao7h4H5o+lLY+enW2+FjI/3Di5o/Q7nr+vYl+e"
    "x7FzhysOxfGp4VhYqU+JKJH1ENm2Qp/qUB1r0bF9ZT7VoTrWpmPbinxqRI0Mb2QvlfhUikoZV8qeK/ApFsWyciyPr7ynWBTLOrFsV3FPnaiTdTrZrtKeOlEn"
    "63SyoMKeYlEs68SyZWU9haJQ1gZlt4p6KkbFrEbMjpX01IpaWY2VD1FBTwEpoDUD2qVyntpRO6u0s6eKeepH/azSz/aV8pSKUlkllYUV8tSLelmvlwWV8RSM"
    "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"
    "AWK2Wm4="
)


def _load_prior_fence_proof() -> dict[str, Any]:
    encoded = "".join(_PRIOR_FENCE_PROOF_ZLIB_BASE64).encode("ascii")
    raw = zlib.decompress(base64.b64decode(encoded))
    proof = json.loads(raw.decode("utf-8"))
    canonical_raw = json.dumps(
        proof,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    if hashlib.sha256(canonical_raw).hexdigest() != PRIOR_FENCE_PROOF_CANONICAL_SHA256:
        raise ValueError("C22 prior-fence proof digest differs")
    if len(raw) != PRIOR_FENCE_PROOF_CANONICAL_RAW_BYTES:
        raise ValueError("C22 prior-fence proof byte count differs")
    return proof


PRIOR_FENCE_PROOF = _load_prior_fence_proof()
PRIOR_FENCE_OVERLAPS: tuple[dict[str, Any], ...] = tuple(
    PRIOR_FENCE_PROOF["authorizedOverlapEdges"]
)


CONTRACT_NAMES = (
    "RecoverabilityVerificationStagingV1",
    "RecoverabilityVerificationReceiptV1",
)
VERIFICATION_MODES = ("STRUCTURE_ONLY", "ISOLATED_DRY_RESTORE", "FULL_CONTENT_RECONCILIATION")
FINDING_DISPOSITIONS = ("PASSED", "FAILED", "UNSUPPORTED", "QUARANTINED", "CANCELLED")
FRESHNESS_DISPOSITIONS = ("CURRENT_AT_VERIFICATION", "HISTORIC_AT_VERIFICATION", "HISTORIC_NONCURRENT")
STAGING_STATES = ("PREPARED", "STRUCTURE_VALIDATED", "DRY_RESTORED", "CONTENT_RECONCILED", "REPLAYED", "CLEANUP_REQUIRED")
FINDING_CODES = (
    "CORRUPT_ARCHIVE", "TRUNCATED_ARCHIVE", "CORRUPT_RECORD", "CORRUPT_CONTENT", "MISSING_CONTENT",
    "CORRUPT_CHECKPOINT", "UNSUPPORTED_SCHEMA", "UNSUPPORTED_CLIENT_CAPABILITY", "WRONG_ARCHIVE",
    "STALE_FRONTIER", "REPLAY_DIVERGENCE", "CLEANUP_INCOMPLETE", "LIVE_WORKSPACE_CHANGED",
    "SOURCE_ARCHIVE_CHANGED", "PROTECTED_DATA_UNAVAILABLE", "STORAGE_UNAVAILABLE", "CANCELLED",
)
PERSISTENT_SCHEMA_VERSION = 21
RECORDS_SCHEMA_VERSION = 20
PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT = 82
DURABLE_FAMILY_COUNT = 1
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C22G01ValidArchiveDryRestoreReplayProducesExactReceipt",
    "testV23P03C22A01CorruptTruncatedUnsupportedAndStaleArchivesFailClosed",
    "testV23P03C22H01WrongBindingReplayDivergenceCancellationAndStorageFailClosed",
    "testV23P03C22I01InterruptionAtEveryBoundaryLeavesNoPartialCanonicalSuccess",
    "testV23P03C22R01RecoveryDropsStagingAndPreservesAcceptedReceipt",
)
FORBIDDEN_CLAIMS = (
    "DESTRUCTIVE_LIVE_RESTORE",
    "SOURCE_ARCHIVE_REPAIR",
    "RECEIPT_INSIDE_VERIFIED_ARCHIVE",
    "PROVIDER_AVAILABILITY_OR_SLA",
    "CLOUD_DURABILITY",
    "NETWORK_STORAGE_PROVIDER",
    "ACCOUNT_OR_CREDENTIAL",
    "EXTERNAL_COPY_AVAILABLE",
    "FUTURE_RECOVERABILITY",
    "SECOND_WRITER_OR_STORE",
    "ANDROID_WEB_BACKEND_SAAS",
)

REQUIRED_BEHAVIORS = (
    {
        "id": "EXACT_ARCHIVE_BINDING",
        "contract": "RecoverabilityVerificationReceiptV1",
        "requirement": "One immutable receipt binds exact archive bytes, schema, source workspace revision, checkpoint, client capability, verifier build, and exact result.",
        "evidence": "C22-S01",
    },
    {
        "id": "ISOLATED_MODES",
        "contract": "RecoverabilityVerificationStagingV1",
        "requirement": "STRUCTURE_ONLY, ISOLATED_DRY_RESTORE, and FULL_CONTENT_RECONCILIATION run in disposable isolated staging and never mutate the live workspace or source archive.",
        "evidence": "C22-S02",
    },
    {
        "id": "DIGEST_RECONCILIATION",
        "contract": "RecoverabilityVerificationReceiptV1",
        "requirement": "Content, canonical-state, and ordered replay digests reconcile deterministically; changed bytes invalidate stale proof.",
        "evidence": "C22-S03",
    },
    {
        "id": "EXPLICIT_FINDINGS",
        "contract": "RecoverabilityVerificationReceiptV1",
        "requirement": "Unsupported, quarantined, stale, corrupt, truncated, missing-content, and wrong-digest findings remain explicit and fail closed.",
        "evidence": "C22-S04",
    },
    {
        "id": "IMMUTABLE_RECEIPT_LIFECYCLE",
        "contract": "RecoverabilityVerificationReceiptV1",
        "requirement": "Accepted receipts remain immutable outside the verified archive, are eligible only in subsequent backups, and corrections append successor receipts.",
        "evidence": "C22-S05",
    },
    {
        "id": "STAGING_RECOVERY",
        "contract": "RecoverabilityVerificationStagingV1",
        "requirement": "Cancellation, cleanup, interruption, workspace deletion, and Erase drop disposable staging and unaccepted projections without deleting canonical data.",
        "evidence": "C22-S06",
    },
    {
        "id": "STATIC_BOUNDARY",
        "contract": CARD,
        "requirement": "The tooling result is PASS_STATIC_PROVISIONAL; native, hosted, adoption, acceptance, release, provider, network, cloud, and Phase 10 claims remain false.",
        "evidence": "C22-B01",
    },
)

EVIDENCE_CASES = (
    {"id": "C22-S01", "kind": "GOLDEN", "assertion": "A valid archive dry-restores in isolation, reconciles content and canonical state, replays deterministically, cleans staging, and emits one exact receipt."},
    {"id": "C22-S02", "kind": "ALTERNATE", "assertion": "Structure-only, isolated dry-restore, and full-content-reconciliation modes preserve the same live-workspace bytes and explicit result semantics."},
    {"id": "C22-S03", "kind": "DIGESTS", "assertion": "Archive, canonical-state, and replay digests are ordered, deterministic, and stale when bound bytes change."},
    {"id": "C22-S04", "kind": "FINDINGS", "assertion": "Corrupt, truncated, missing-content, unsupported, quarantined, stale, wrong-digest, and wrong-binding inputs never become PASS."},
    {"id": "C22-S05", "kind": "IMMUTABILITY", "assertion": "Accepted receipts remain outside the verified archive and immutable across backup, restore, clone, fork, retention, and correction paths."},
    {"id": "C22-S06", "kind": "RECOVERY", "assertion": "Cancellation and interruption drop staging or leave one complete receipt-bound state; accepted receipts are never rewritten."},
    {"id": "C22-H01", "kind": "HOSTILE", "assertion": "Wrong archive binding, replay divergence, low storage, cancellation, source repair, external-copy overclaim, and second-store attempts fail closed."},
    {"id": "C22-I01", "kind": "INTERRUPTION", "assertion": "Every durable boundary exposes either zero accepted partial state or one complete retryable receipt-bound result."},
    {"id": "C22-R01", "kind": "RECOVERY", "assertion": "Recovery drops isolated staging and unaccepted projections while preserving accepted immutable receipts and appending successors for corrections."},
    {"id": "C22-F01", "kind": "PATH_FENCE", "assertion": "The hydrated fence is exactly 56 paths: 42 existing and 14 new, with zero S10 overlap and 647 authorized prior-fence overlaps."},
    {"id": "C22-B01", "kind": "STATIC_BOUNDARY", "assertion": "All activation, native, hosted, adoption, acceptance, release, provider, network, cloud, and Phase 10 flags remain false pending accepted S10.6 reconciliation."},
)

SOURCE_PROJECTION = {
    "registerRows": [
        "| 59 | <a id=\"v23-p03-c22-register\"></a>[`V23-P03-C22`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c22) | Recovery-point frontier/freshness truth with isolated dry restore and replay receipts | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C21` | `EXACT_WITH_GENERATION_REBIND` |\n",
    ],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "registerRowUTF8Length": REGISTER_ROW_UTF8_LENGTH,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "facetRowCount": 1,
    "canonicalRecordWriterOwnershipRowCount": 4,
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C22).CONTRACTS", *CONTRACT_NAMES, "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C23", "V23-P03-C27", "V23-P04-C01", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    "optionalCapabilityProviders": ["NONE"],
    "reservedLegacyOwnerReconciliationDebtCount": 0,
    "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0,
    "reservedLegacyRawWriteViolationPaths": [],
    "provisionalZeroViolationClosureClaimed": False,
    "directGraphDigest": "DERIVED_FROM_C22_PREREQUISITE_SET",
    "selectorManifestDigest": "DERIVED_FROM_C22_TEST_METHODS",
    "relationManifestDigest": "DERIVED_FROM_C22_RECOVERABILITY_RELATIONS",
    "dependencyDispositionDigest": "DERIVED_FROM_C22_RECOVERY_FINDINGS",
    "impactManifestDigest": "DERIVED_FROM_C22_BRAND_IMPACT_MANIFEST",
}

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 1,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [
        {
            "cardID": "V23-P03-C21",
            "attemptID": 1,
            "candidateHead": BASE_HEAD,
            "candidateTree": BASE_TREE,
            "checkpointDigest": "220e5829928407e7e67ab09337a384f9e0d265762fe11817d17804d04345df70",
            "verificationReceiptDigest": "5facf99213065103aca3f15f15be5b4ef569577f3d8305d410543ff2a19115d1",
            "contextDigest": "033924c121880600a986352b8da1360c058a1e546c4efd987c0aaf85b0123a89",
            "pathFenceDigest": "a961c346c2aa4a68fb18ed9af92497ded130e37e22bded16a99bf2bedf5e8a73",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C21_HEAD",
        },
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

SEMANTIC_SCOPE = {
    "durableOwner": ["RecoverabilityVerificationReceiptV1", "PersistentSchemaV21"],
    "nonPersistentOwner": ["RecoverabilityVerificationStagingV1"],
    "atomicAuthorityPolicy": "ARCHIVE_BOUND_DRY_RESTORE_CONTENT_RECONCILIATION_AND_DETERMINISTIC_REPLAY_RECEIPT_EFFECT_COMMIT_IN_ONE_SWIFTDATA_TRANSACTION_USING_THE_SOLE_CANONICAL_WRITER",
    "archiveBindingPolicy": "BIND_EXACT_ARCHIVE_BYTES_SCHEMA_SOURCE_WORKSPACE_REVISION_CHECKPOINT_CLIENT_CAPABILITY_AND_VERIFIER_BUILD_WITH_RECEIPT_OUTSIDE_THE_VERIFIED_ARCHIVE",
    "modePolicy": "CLOSED_MODES_STRUCTURE_ONLY_ISOLATED_DRY_RESTORE_FULL_CONTENT_RECONCILIATION_WITH_STAGING_NEVER_MUTATING_LIVE_WORKSPACE_OR_SOURCE_ARCHIVE",
    "digestPolicy": "CONTENT_CANONICAL_STATE_AND_ORDERED_REPLAY_DIGESTS_RECONCILE_EXACTLY_AND_CHANGED_BYTES_INVALIDATE_STALE_PROOF",
    "findingPolicy": "PASSED_FAILED_UNSUPPORTED_QUARANTINED_AND_CANCELLED_DISPOSITIONS_REMAIN_EXPLICIT_WITH_STALE_FRONTIER_CORRUPT_TRUNCATED_MISSING_WRONG_DIGEST_AND_DIVERGENT_INPUTS_FAIL_CLOSED",
    "receiptPolicy": "IMMUTABLE_EVIDENCE_OUTSIDE_THE_VERIFIED_ARCHIVE_INCLUDED_ONLY_IN_SUBSEQUENT_BACKUPS_WITH_ORIGINAL_BINDING_PRESERVED_ON_RESTORE_AND_HISTORIC_NONCURRENT_CLONE_OR_FORK",
    "lifecyclePolicy": "V21_EIGHTY_TWO_MODELS_RECORDS20_ONE_DURABLE_RECOVERABILITY_RECEIPT_FAMILY_AND_DISPOSABLE_STAGING_FROM_V20_ARCHIVE_BACKUP_RESTORE_IMPORT_EXPORT_JOURNAL_REPLAY_DELETE_ERASE_RETENTION_COMPATIBILITY_AND_FORWARD_FIX_CLOSED",
    "forbiddenPolicy": "NO_DESTRUCTIVE_LIVE_RESTORE_SOURCE_ARCHIVE_REPAIR_RECEIPT_INSIDE_ARCHIVE_PROVIDER_AVAILABILITY_SLA_CLOUD_DURABILITY_NETWORK_STORAGE_ACCOUNT_CREDENTIAL_EXTERNAL_COPY_OR_FUTURE_RECOVERABILITY_CLAIM_OR_SECOND_WRITER",
    "s10Policy": "EXACT_FIFTY_SIX_PATH_RESERVATION_WITH_ZERO_OVERLAP_AND_ALL_VISIBLE_UI_DEFERRED",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

CORPUS: dict[str, Any] = {
    "schema": "V21P03C22RecoverabilityVerificationCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION,
    "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
    "persistentRecoverabilityKindCount": DURABLE_FAMILY_COUNT,
    "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT,
    "durableFamilyCount": DURABLE_FAMILY_COUNT,
    "requiredContractNames": list(CONTRACT_NAMES),
    "verificationModes": list(VERIFICATION_MODES),
    "findingDispositions": list(FINDING_DISPOSITIONS),
    "freshnessDispositions": list(FRESHNESS_DISPOSITIONS),
    "stagingStates": list(STAGING_STATES),
    "findingCodes": list(FINDING_CODES),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "evidenceCases": list(EVIDENCE_CASES),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "persistence": {
        "schemaRelease": "RECOVERABILITY_VERIFICATION_V1",
        "schemaVersion": PERSISTENT_SCHEMA_VERSION,
        "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
        "mode": "NEW_SCHEMA_VERSION",
        "migrationRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportReportRequired": True,
        "searchRebuildRequired": True,
        "replayRequired": True,
        "classificationRequired": True,
        "interruptionRecoveryRequired": True,
        "canonicalWriter": "V23-P02-C01",
        "canonicalSourceOfTruth": ["RecoverabilityVerificationReceiptV1"],
        "persistedFamilies": ["RecoverabilityVerificationReceiptV1"],
        "nonPersistentFamilies": ["RecoverabilityVerificationStagingV1"],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
        "secondStore": False,
        "secondWriter": False,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V21_WRITE",
        "forwardFix": "DROP_STAGING_PRESERVE_ACCEPTED_RECEIPTS_DENY_UNSAFE_REPLAY_AND_APPEND_SUCCESSOR_RECEIPT_NEVER_REWRITE_ARCHIVE_OR_HISTORY",
    },
    "goldenCases": [
        {"id": "valid-archive-isolated-dry-restore-replay", "mode": "FULL_CONTENT_RECONCILIATION", "finding": "PASSED", "liveWorkspaceMutated": False, "receiptImmutable": True},
    ],
    "alternateCases": [
        {"id": "structure-only", "mode": "STRUCTURE_ONLY", "finding": "PASSED", "liveWorkspaceMutated": False},
        {"id": "corrupt-or-truncated", "mode": "ISOLATED_DRY_RESTORE", "finding": "FAILED", "findingCode": "CORRUPT_ARCHIVE", "liveWorkspaceMutated": False},
        {"id": "unsupported-or-quarantined", "mode": "ISOLATED_DRY_RESTORE", "finding": "UNSUPPORTED", "findingCode": "UNSUPPORTED_SCHEMA", "liveWorkspaceMutated": False},
        {"id": "stale-or-wrong-digest", "mode": "FULL_CONTENT_RECONCILIATION", "finding": "FAILED", "findingCode": "STALE_FRONTIER", "liveWorkspaceMutated": False},
    ],
    "hostileCases": [
        {"id": case_id, "expectedDisposition": "FAILED", "expectedBoundary": "FAIL_CLOSED_NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "wrong-archive-bound-to-receipt", "replay-state-divergence", "changed-bytes-after-proof",
            "source-archive-repair-request", "low-storage", "cancellation-leaks-staging",
            "provider-or-cloud-availability", "external-copy-overclaim", "receipt-inside-archive",
            "second-store-or-writer", "unknown-mode-or-finding",
        )
    ],
    "interruptionCases": [
        {"id": case_id, "expectedDisposition": "CANCELLED", "expectedBoundary": "RETRY_IDEMPOTENT_NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "crash-before-staging", "crash-after-staging", "crash-after-structure-check",
            "crash-after-dry-restore", "crash-after-content-reconciliation", "crash-after-replay",
            "crash-before-receipt", "crash-after-receipt-before-cleanup", "cleanup-interruption",
        )
    ],
    "recoveryCases": [
        {"id": case_id, "expectedDisposition": "DROP_STAGING_OR_PRESERVE_ONE_IMMUTABLE_ACCEPTED_RECEIPT"}
        for case_id in (
            "cancel-and-cleanup", "relaunch-after-interruption", "replay-retry",
            "replace-restore-preserves-original-binding", "clone-fork-historic-noncurrent",
            "retention-expiry-delete-erase", "correction-appends-successor",
        )
    ],
    "claims": {
        claim: False
        for claim in (
            "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit",
            "providerAvailability", "cloudDurability", "network", "account", "externalCopyAvailable",
            "futureRecoverability", "destructiveLiveRestore", "sourceArchiveRepair", "receiptInsideArchive",
            "secondStore", "secondWriter", "android", "web", "backend", "phase10PollingDuringParallelExecution",
        )
    },
}


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


def source_artifacts(root: Path) -> list[dict[str, Any]]:
    return [
        {"path": path, "source": "BASE_HEAD_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)}
        for path in SOURCE_REFERENCE_PATHS
    ]


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    return [
        {"path": path, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)}
        for path in AUTHORITY_REFERENCE_PATHS
    ]


def _schema_for_value(value: Any) -> dict[str, Any]:
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer"}
    if isinstance(value, float):
        return {"type": "number"}
    if isinstance(value, str):
        return {"type": "string"}
    if isinstance(value, list):
        result: dict[str, Any] = {"type": "array", "minItems": len(value), "maxItems": len(value)}
        if value:
            shapes = {json.dumps(_schema_for_value(item), sort_keys=True): _schema_for_value(item) for item in value}
            result["items"] = next(iter(shapes.values())) if len(shapes) == 1 else {"anyOf": [shapes[key] for key in sorted(shapes)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/recoverability-verification.schema.json",
        "title": "V23 P03 C22 Recoverability Verification Corpus",
    })
    return document


def _flags() -> dict[str, bool]:
    return {
        "native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False,
        "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False,
        "acceptanceCredit": False, "releaseReadiness": False, "phase10PollingDuringParallelExecution": False,
    }


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(PATH_FENCE), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "directPrerequisiteCards": ["V23-P03-C21"], "nextCard": "V23-P03-C23",
        "sourceDossierSHA256": DOSSIER_SHA256, "sourceDossierUTF8Length": DOSSIER_UTF8_LENGTH,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    }


def _sealed(body: dict[str, Any], field: str = "artifactDigest") -> dict[str, Any]:
    result = dict(body)
    result[field] = sha256_bytes(pretty(body))
    return result


def contract_document(schema_row: dict[str, Any]) -> dict[str, Any]:
    required = {
        "contractNames": list(CONTRACT_NAMES), "verificationModes": list(VERIFICATION_MODES),
        "findingDispositions": list(FINDING_DISPOSITIONS),
        "runtimeVerificationDispositionEnum": "RecoverabilityVerificationDispositionV1",
        "runtimeFreshnessDispositionEnum": "RecoveryPointFreshnessDispositionV1",
        "runtimeStagingStateEnum": "RecoverabilityStagingStateV1",
        "runtimeFindingCodeEnum": "RecoverabilityFindingCodeV1",
        "freshnessDispositions": list(FRESHNESS_DISPOSITIONS),
        "stagingStates": list(STAGING_STATES),
        "findingCodes": list(FINDING_CODES),
        "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION,
        "recordsSchemaVersion": RECORDS_SCHEMA_VERSION, "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT,
        "durableFamilyCount": DURABLE_FAMILY_COUNT, "persistentReceiptKind": "RecoverabilityVerificationReceiptV1",
        "disposableStagingKind": "RecoverabilityVerificationStagingV1", "immutableArchiveBinding": True,
        "isolatedDryRestore": True, "liveWorkspaceMutation": False, "sourceArchiveMutation": False,
        "fiveSelectors": list(TEST_METHODS), "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    }
    body = {
        "artifact": "V23P03C22RecoverabilityVerificationContractV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "title": TITLE, "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "requiredSemantics": required, "semanticScope": SEMANTIC_SCOPE,
        "persistenceBoundary": CORPUS["persistence"], "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "evidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(TEST_METHODS), "schemaArtifact": schema_row,
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    required = contract["requiredSemantics"]
    body = {
        "artifact": "V23P03C22RecoverabilityVerificationEvidenceReceiptV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "authority": _authority(), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows,
        "requiredSemanticsDigest": sha256_value(required), "requiredSemantics": required,
        "evidenceCases": list(EVIDENCE_CASES), "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(TEST_METHODS), "schemaArtifact": schema_row,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "staticBoundary": "NO_NATIVE_HOSTED_ADOPTION_ACCEPTANCE_RELEASE_PROVIDER_NETWORK_CLOUD_OR_PHASE10_CLAIM",
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def brand_document(contract: dict[str, Any]) -> dict[str, Any]:
    body = {
        "artifact": "V23P03C22RecoverabilityVerificationBrandImpactManifestV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "brandSurfaceDelta": True, "uiSurfaceDelta": False,
        "impact": "RECOVERY_FRESHNESS_AND_VERIFICATION_STATES_REMAIN_LOCAL_MANUAL_AND_ACCESSIBLE_WITH_NO_NEW_S10_UI_SURFACE",
        "preserved": ["live-workspace-bytes", "source-archive-bytes", "immutable-accepted-receipts", "existing-design-tokens", "existing-accessibility-contracts", "S10-reserved-brand-assets"],
        "deferred": ["native-build", "hosted-CI", "adoption", "acceptance", "release", "provider", "network", "cloud", "Phase10"],
        "pathFenceCount": len(PATH_FENCE), "s10FenceOverlapPaths": [],
        "authorityContextDigest": CONTEXT_DIGEST, "authorityFenceDigest": FENCE_DIGEST,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
        "contractDigest": contract["artifactDigest"],
    }
    return _sealed(body)


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    path = root / relative
    if relative in rendered:
        raw = rendered[relative]
        return {"path": relative, "state": "GENERATED", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if path.is_file():
        raw = path.read_bytes()
        return {"path": relative, "state": "WORKTREE", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if relative in EXISTING_PATHS:
        raw = _git_blob(root, relative)
        return {"path": relative, "state": "BASE_HEAD", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    return {"path": relative, "state": "MISSING_NEW_PATH", "bytes": 0, "sha256": sha256_bytes(b"")}


def all_outputs(root: Path) -> dict[str, bytes]:
    if len(EXISTING_PATHS) != 42 or len(NEW_PATHS) != 14 or len(PATH_FENCE) != 56 or len(set(PATH_FENCE)) != 56:
        raise ValueError("C22 path fence constants are not 56=42+14 unique paths")
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract = contract_document(schema_row)
    contract_raw = pretty(contract)
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract))
    evidence = json.loads(evidence_raw)
    brand_raw = pretty(brand_document(contract))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "artifact": "V23P03C22ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(),
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS),
        "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows,
        "artifacts": rows, "artifactSetDigest": sha256_value(rows), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "persistenceBoundary": CORPUS["persistence"],
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [],
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
        "evidenceDigest": evidence["artifactDigest"], "testSelectors": list(TEST_METHODS),
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def assert_corpus() -> None:
    if len(EXISTING_PATHS) != 42 or len(NEW_PATHS) != 14 or len(PATH_FENCE) != 56:
        raise ValueError("C22 path fence count differs")
    if CORPUS["requiredContractNames"] != list(CONTRACT_NAMES):
        raise ValueError("C22 contract family set differs")
    if CORPUS["verificationModes"] != list(VERIFICATION_MODES) or len(VERIFICATION_MODES) != 3:
        raise ValueError("C22 verification mode set differs")
    if CORPUS["findingDispositions"] != list(FINDING_DISPOSITIONS) or len(FINDING_DISPOSITIONS) != 5:
        raise ValueError("C22 finding disposition set differs")
    if CORPUS["persistentSchemaVersion"] != 21 or CORPUS["recordsSchemaVersion"] != 20:
        raise ValueError("C22 persistence versions differ")
    if CORPUS["persistentKindLifecycleModelCount"] != 82 or CORPUS["durableFamilyCount"] != 1:
        raise ValueError("C22 model/family counts differ")
    if CORPUS["persistence"]["secondStore"] or CORPUS["persistence"]["secondWriter"]:
        raise ValueError("C22 second store/writer is prohibited")
    if (
        PRIOR_FENCE_PROOF["priorOwnedPathCount"] != PRIOR_FENCE_PRIOR_OWNED_PATH_COUNT
        or PRIOR_FENCE_PROOF["overlapCount"] != PRIOR_FENCE_OVERLAP_COUNT
        or PRIOR_FENCE_PROOF["authorizedOverlapCount"] != PRIOR_FENCE_OVERLAP_COUNT
        or PRIOR_FENCE_PROOF["unauthorizedOverlapCount"] != 0
        or PRIOR_FENCE_PROOF["fenceCount"] != 59
        or len(PRIOR_FENCE_PROOF["authorizedOverlapEdges"]) != PRIOR_FENCE_OVERLAP_COUNT
        or len(PRIOR_FENCE_OVERLAPS) != PRIOR_FENCE_OVERLAP_COUNT
        or PRIOR_FENCE_PROOF["authorizedOverlapEdges"] != list(PRIOR_FENCE_OVERLAPS)
    ):
        raise ValueError("C22 prior-fence proof differs")


assert_corpus()
