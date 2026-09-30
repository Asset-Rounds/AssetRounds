#!/usr/bin/env python3
"""Deterministic static contract, corpus, and evidence builders for V23-P03-C25.

The card owns the closed activity-kind vocabulary and immutable guided-survey
identity/release records. Import previews and semantic projections remain
derived-only; lifecycle event bytes stay in the existing mutation envelope and
journal. All activation and acceptance claims are intentionally provisional.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
import subprocess
import zlib
from pathlib import Path
from typing import Any


CARD = "V23-P03-C25"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 62
TITLE = "Distinct inspection, survey, preventive-maintenance, repair, and operational-recheck activity kinds with immutable guided-survey definitions"
BASE_HEAD = "d0c7c8a48e235e783627495ccba6b0e168e9b34e"
BASE_TREE = "9f759030a7154c38ade62ce9a3273f4b33ebf18d"
COORDINATION_HEAD = "e24b3f0c993d4120478902ba11f017de3001696c"
COORDINATION_ORIGIN_MAIN_HEAD = COORDINATION_HEAD
COORDINATION_TREE = "5a36a754c527ec7d1fc1ecc6991e4e76bac8e7c6"
COORDINATION_LEDGER_DIGEST = "a9bfbb1a9e7f632841bc3157ddd987b8ef9747ce9ba36b3db76b57cd7d33ea82"
COORDINATION_PROJECTION_DIGEST = "e132ba4efb0215635e9aa8f3beab70bf60ecbec1191b74e1c90694d8e738adac"
COORDINATION_CAS_SEQUENCE = 263
HYDRATION_TRANSITION_SEQUENCE = 263
HYDRATION_TRANSITION_DIGEST = "109bdcbfe09aa97b0a3af79121eba56f5b518cafe572b6442802b7e12782eeb9"
HYDRATION_REVISION = 2
HYDRATION_CORRECTION_RECEIPT_DIGEST = "81108e542ab819aae4b95ea0ad2dcbb3d6f7dcd0dd1341adaa3eb693c08f4750"
CONTEXT_DIGEST = "5f8a552d9c31a2f281f2987bf2b68d7249e688cc6dd74495580ed6ba35c06c37"
FENCE_DIGEST = "ad2f0a817100aee220391965bdbb3da3d7ab5aa518941232e07a4deea6005fdb"
PREREQUISITE_DIGEST = "dae2fda4456fc1e9e6bb8098614308afe624e1127205cee97babf6df7611bbb3"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "4ac43661699b7e6a1b8efc87a3e490af0356033cc7cda78f32a5b580d1b23cc5"
REGISTER_ROW_UTF8_LENGTH = 299
DOSSIER_SHA256 = "fdb4593ab7466dd8fff8a4db613625f849cd291367f0a165c8b7adc032b885ac"
DOSSIER_UTF8_LENGTH = 7554
INHERITED_V21_BLOCK_SHA256 = "23bd9ee57858b77b718e05113687d3cc3bc1f673a0948956f721ac382f665a7b"
INHERITED_V21_BLOCK_UTF8_LENGTH = 7269

SCHEMA_PATH = "Scripts/v23/survey-definition.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C25SurveyDefinitionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C25SurveyDefinitionEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C25BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C25-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c25_contracts.py",
    "Scripts/v23/generate_p03_c25_contracts.py",
    "Scripts/v23/verify_p03_c25_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

EXISTING_PATHS = tuple(json.loads(r'''["FieldEvidenceApp/Domain/InspectionKernel/WorkflowDefinitionV1.swift","FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift","FieldEvidenceApp/Domain/InspectionKernel/WorkflowGraphValidatorV1.swift","FieldEvidenceApp/Domain/InspectionKernel/ResponseFieldDefinitionV1.swift","FieldEvidenceApp/Domain/InspectionKernel/ResponseValueV1.swift","FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift","FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift","FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift","FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift","FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift","FieldEvidenceApp/Domain/Packs/PackageEvolutionContractsV1.swift","FieldEvidenceApp/Domain/Workflow/WorkflowContracts.swift","FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift","FieldEvidenceApp/Domain/Models/WorkflowModels.swift","FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift","FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift","FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift","FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift","FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift","FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift","FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift","FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift","FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift","FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift","FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift","FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift","FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift","FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift","FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift","FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift","FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift","FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift","FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift","FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift","FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift","FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift","FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift","FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift","FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift","FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift","FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift","FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift","FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift","FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift","FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift","FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift","FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift","FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift","FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift","FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift","FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift","FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift","FieldEvidenceApp/Domain/Search/SearchContractsV1.swift","FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift","FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift","FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift","FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift","FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift","FieldEvidenceApp/Resources/Localizable.xcstrings","FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift","FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift","FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift","FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift","FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift","FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift","FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift","FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift","FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift","FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift","FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift","FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift","FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift","FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift","FieldEvidenceApp/Infrastructure/Settings/FeaturePolicyLoaderV1.swift","FieldEvidenceApp/Application/Packs/PackageEvolutionCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Packs/PackageEvolutionLifecycleAdapterV1.swift","FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift","FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift","FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift","FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift","FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift","FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift","FieldEvidenceAppTests/S4_4HistoryComparisonTests.swift","FieldEvidenceAppTests/S6_2BackupExportTests.swift","FieldEvidenceAppTests/S6_3BackupValidationTests.swift","FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift","FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift","FieldEvidenceAppTests/S8_1SecondPackZeroForkTests.swift","FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift","FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift","FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift","FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift","FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift","FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift","FieldEvidenceAppTests/V9_06DeletionRightsTests.swift","FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift","FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift","FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift","FieldEvidenceAppTests/V9_11PackRegistryTests.swift","FieldEvidenceAppTests/V9_12WorkflowGraphTests.swift","FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift","FieldEvidenceAppTests/V9_13TypedResponseTests.swift","FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift","FieldEvidenceAppTests/V9_17KernelPersistenceTests.swift","FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift","FieldEvidenceAppTests/V9_19LocalSearchTests.swift","FieldEvidenceAppTests/V9_20KernelConformanceTests.swift","FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift","FieldEvidenceAppTests/V9_32PackageEvolutionTests.swift","FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift","FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift"]'''))
NEW_PATHS = tuple(json.loads(r'''["FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift","FieldEvidenceApp/Domain/Models/SurveyDefinitionPersistenceModelsV1.swift","FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift","FieldEvidenceAppTests/Fixtures/V22/SurveyDefinitions/V22P03C25SurveyDefinitionCorpusV1.json","Scripts/v23/p03_c25_contracts.py","Scripts/v23/generate_p03_c25_contracts.py","Scripts/v23/verify_p03_c25_contracts.py","Scripts/v23/survey-definition.schema.json","docs/design/v23/tooling/V23P03C25SurveyDefinitionContractV1.json","docs/design/v23/tooling/V23P03C25SurveyDefinitionEvidenceReceiptV1.json","docs/design/v23/tooling/V23P03C25BrandImpactManifestV1.json","docs/design/v23/tooling/V23-P03-C25-tooling-manifest.json"]'''))
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_REFERENCE_PATHS = EXISTING_PATHS
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

PRIOR_FENCE_OVERLAP_COUNT = 1308
PRIOR_FENCE_PRIOR_OWNED_PATH_COUNT = 1032
PRIOR_FENCE_PROOF_CANONICAL_SHA256 = "295cf9404f88da80e735ede7c8cf333d6fa75f05bfebac7b22c4ee0c5c78bddc"
PRIOR_FENCE_PROOF_CANONICAL_RAW_BYTES = 1139454
_PRIOR_FENCE_PROOF_ZLIB_BASE64 = (
    "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",
)


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def assert_coordination_identity(root: Path) -> dict[str, str]:
    """Fail closed unless the sibling coordination checkout is at the pinned tip."""
    coordination_root = root.parent / "AssetRounds-v23-coordination"
    if not coordination_root.is_dir():
        raise ValueError("C25 coordination checkout is missing")

    def git(*args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(coordination_root), *args],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

    head = git("rev-parse", "HEAD")
    origin_main = git("rev-parse", "origin/main")
    tree = git("rev-parse", "HEAD^{tree}")
    if head != COORDINATION_HEAD:
        raise ValueError(f"C25 coordination HEAD differs: {head}")
    if origin_main != COORDINATION_ORIGIN_MAIN_HEAD:
        raise ValueError(f"C25 coordination origin/main differs: {origin_main}")
    if tree != COORDINATION_TREE:
        raise ValueError(f"C25 coordination tree differs: {tree}")
    return {"head": head, "originMain": origin_main, "tree": tree}


def _load_prior_fence_proof() -> dict[str, Any]:
    raw = zlib.decompress(base64.b64decode("".join(_PRIOR_FENCE_PROOF_ZLIB_BASE64)))
    proof = json.loads(raw.decode("utf-8"))
    if sha256_bytes(canonical(proof)) != PRIOR_FENCE_PROOF_CANONICAL_SHA256:
        raise ValueError("C25 prior-fence proof digest differs")
    if len(canonical(proof)) != PRIOR_FENCE_PROOF_CANONICAL_RAW_BYTES:
        raise ValueError("C25 prior-fence proof byte count differs")
    return proof


PRIOR_FENCE_PROOF = _load_prior_fence_proof()
PRIOR_FENCE_OVERLAPS = tuple(PRIOR_FENCE_PROOF["authorizedOverlapEdges"])

CONTRACT_NAMES = (
    "ActivityKindV1",
    "SurveyDefinitionIdentityV1",
    "SurveyDefinitionReleaseV1",
    "SurveyDefinitionLifecycleEventV1",
    "SurveyDefinitionCoordinatorV1",
)
ACTIVITY_KINDS = (
    "INSPECTION",
    "SURVEY",
    "PREVENTIVE_MAINTENANCE",
    "REPAIR",
    "OPERATIONAL_RECHECK",
)
LIFECYCLE_STATES = ("DRAFT", "PUBLISHED", "RETIRED", "QUARANTINED")
FIELD_KINDS = (
    "INSTRUCTION", "SHORT_TEXT", "LONG_TEXT", "INTEGER", "DECIMAL",
    "TYPED_MEASUREMENT", "BOOLEAN", "SINGLE_CHOICE", "MULTIPLE_CHOICE",
    "DATE", "TIME", "ENTITY_REFERENCE", "PROVISIONAL_SUBJECT_REFERENCE",
    "LOCATOR", "NORMALIZED_PLAN_PLACEMENT", "EVIDENCE_REQUEST",
    "REPEATABLE_TYPED_GROUP",
)
SENSITIVITY_VALUES = ("CUSTOMER_SAFE", "INTERNAL_ONLY")
RELEASE_DISPOSITIONS = LIFECYCLE_STATES
FAILURE_VALUES = (
    "unknownActivityKind", "unsupportedActivityKind", "duplicateStableIdentity",
    "missingRelease", "missingRequiredField", "hiddenRequiredField",
    "unreachableRequiredField", "invalidConditionalVisibility",
    "semanticDiffConflict", "staleRevision", "importNotDraft",
    "activeSessionRetirement", "immutableReleaseMutation", "duplicateDefinitionID",
    "runtimeCodeExecution", "genericEAV", "scriptOrMacro", "claimsLeak",
    "inventedCompletion", "crossWorkspaceReference", "forgedDigest",
)
INTERRUPTION_POINTS = (
    "AFTER_IDENTITY_BEFORE_RECEIPT",
    "AFTER_IMPORT_QUARANTINE_BEFORE_DRAFT",
    "AFTER_DRAFT_BEFORE_RELEASE",
    "AFTER_PUBLISH_BEFORE_RECEIPT",
    "AFTER_RETIRE_BEFORE_RECEIPT",
)
SUBJECT_KINDS = (
    "ACTIVITY_KIND", "SURVEY_DEFINITION", "SURVEY_DEFINITION_RELEASE",
    "SURVEY_SECTION", "FACT_DEFINITION", "COMPLETION_RULE",
)
SUBJECT_STATES = ("DRAFT", "PUBLISHED", "RETIRED", "QUARANTINED")
AVAILABILITY_STATES = (
    "AVAILABLE", "MISSING_RELEASE", "STALE_REVISION", "QUARANTINED",
    "INCOMPATIBLE", "REQUIRES_EXPLICIT_ADOPTION",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C25G01StableActivityKindsAndImmutableSurveyDefinitionRelease",
    "testV23P03C25A01AlternateDefinitionAndDraftOnlyExchangeRemainBounded",
    "testV23P03C25H01UnknownKindsHiddenRequiredClaimsAndArchiveConflictsFailClosed",
    "testV23P03C25I01InterruptedImportPublishAndReleaseWritesRemainRetryable",
    "testV23P03C25R01CanonicalRebuildAndSuccessorReleasePreserveHistory",
)
FORBIDDEN_CLAIMS = (
    "AUTOMATIC_ASSET_CREATION_FROM_OCR_OR_SCAN",
    "ARBITRARY_JSON_OR_GENERIC_EAV_FORM_DATA",
    "RUNTIME_CODE_EXECUTION",
    "PACKAGE_CREATED_STORAGE_TABLES",
    "PACKAGE_CREATED_RENDERERS",
    "SURVEY_ANSWERS_AS_INSPECTION_PASS_FAIL",
    "SILENT_IN_PROGRESS_SESSION_UPGRADE",
    "LAST_WRITE_WINS_FACT_MERGING",
    "UNAUTHORIZED_ACTIVITY_KIND_RELABELING",
    "INVENTED_SIGNATURE_TRAINING_OR_COMPLIANCE_PROOF",
    "UNLICENSED_CONTENT_OR_MARKETPLACE",
    "NETWORK_CLOUD_ACCOUNT_OR_PROVIDER",
    "SECOND_WRITER_OR_SECOND_STORE",
    "NATIVE_IPAD_OR_ANDROID_SURFACE",
    "LEGAL_OR_NONREPUDIATION_CLAIM",
)

REQUIRED_BEHAVIORS = (
    {
        "id": "CLOSED_ACTIVITY_KIND_VOCABULARY",
        "contract": "ActivityKindV1",
        "requirement": "Expose exactly five activity kinds; distinguish inspection, survey, preventive maintenance, repair, and operational recheck without relabeling after start.",
        "evidence": "C25-S01",
    },
    {
        "id": "IMMUTABLE_DEFINITION_IDENTITY_AND_RELEASE",
        "contract": "SurveyDefinitionIdentityV1",
        "requirement": "Use stable definition identity and immutable published releases; editing creates a successor draft and retirement is non-destructive.",
        "evidence": "C25-S02",
    },
    {
        "id": "CLOSED_GUIDED_SURVEY_GRAMMAR",
        "contract": "SurveyDefinitionReleaseV1",
        "requirement": "Keep the first-generation typed field set closed, validate reachability and conditional visibility, and reject hidden-required traps.",
        "evidence": "C25-S03",
    },
    {
        "id": "BOUNDED_DRAFT_ONLY_EXCHANGE",
        "contract": "SurveyDefinitionLifecycleEventV1",
        "requirement": "Hostile-validate .arsurveytemplate archives; quarantine and import as draft only, with explicit bind-as-update or import-as-new for conflicts.",
        "evidence": "C25-S04",
    },
    {
        "id": "SOLE_WRITER_EVENT_JOURNAL",
        "contract": "SurveyDefinitionCoordinatorV1",
        "requirement": "Route canonical identity/release writes through the existing sole writer; lifecycle event bytes remain in the existing mutation envelope and journal.",
        "evidence": "C25-S05",
    },
    {
        "id": "ORDERED_V24_LIFECYCLE",
        "contract": "PERSISTENT_SCHEMA_V24",
        "requirement": "Close migration, backup/restore, import/export, journal replay, search/rebuild, delete/Erase, retention, compatibility, interruption, and forward-fix for 87 models and two durable families.",
        "evidence": "C25-S06",
    },
    {
        "id": "STATIC_PROVISIONAL_BOUNDARY",
        "contract": CARD,
        "requirement": "Remain PASS_STATIC_PROVISIONAL; native, hosted, adoption, acceptance, release, provider, network, account, cloud, and Phase 10 claims stay false pending accepted S10.6 reconciliation.",
        "evidence": "C25-B01",
    },
)

EVIDENCE_CASES = (
    {"id": "C25-S01", "kind": "GOLDEN", "assertion": "A stable package produces the exact five activity kinds and a deterministic immutable definition identity/release pair."},
    {"id": "C25-S02", "kind": "GOLDEN", "assertion": "Published releases are immutable; changes append a successor draft and active work remains pinned to its selected release."},
    {"id": "C25-S03", "kind": "ALTERNATE", "assertion": "Two structurally different definitions preserve typed defaults, explicit unknowns, conditional visibility, and bounded localization/report labels."},
    {"id": "C25-S04", "kind": "HOSTILE", "assertion": "Unknown kinds, duplicate IDs, hidden-required fields, invalid cycles, archive conflicts, runtime code, and forged claims fail closed."},
    {"id": "C25-S05", "kind": "INTERRUPTION", "assertion": "Interrupted import, draft, publish, retire, and receipt boundaries retry idempotently with zero or one canonical effect."},
    {"id": "C25-S06", "kind": "RECOVERY", "assertion": "Replay, backup/restore, delete/Erase, and rebuild preserve immutable releases and append only valid successors."},
    {"id": "C25-F01", "kind": "PATH_FENCE", "assertion": "The sealed C25 fence contains exactly 128 paths: 114 existing and 14 new, with zero S10 overlap and 1,308 authorized prior-fence edges."},
    {"id": "C25-B01", "kind": "STATIC_BOUNDARY", "assertion": "All activation/native/hosted/adoption/acceptance/release/provider/network/account/cloud/Phase 10 flags remain false."},
)

REGISTER_ROW = (
    "| 62 | <a id=" + chr(34) + "v23-p03-c25-register" + chr(34) + "></a>["
    + chr(96) + "V23-P03-C25" + chr(96)
    + "](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c25) | "
    + "Distinct inspection, survey, preventive-maintenance, repair, and operational-recheck activity kinds with immutable guided-survey definitions | "
    + chr(96) + "IMPLEMENT_NOW" + chr(96) + " | " + chr(96) + "NOT_STARTED" + chr(96)
    + " | V23-P03-C24 | " + chr(96) + "REFINED_WITHOUT_LOSS" + chr(96) + " |"
    + "\n"
)

SOURCE_PROJECTION = {
    "registerRows": [REGISTER_ROW],
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
    "canonicalRegisterDigest": REGISTER_SECTION_SHA256,
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001", "V23-POL-HIG-001", "V23-POL-A11Y-001", "V23-POL-L10N-001"],
    "contractRefs": [
        "V21ToV23RequirementRebindingV1(V21-P03-C25).CONTRACTS",
        "ActivityKindV1", "SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1",
        "SurveyDefinitionLifecycleEventV1", "DirectPrerequisiteEvidenceSetV1",
        "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1",
        "CandidateAcceptanceCompatibilityReceiptV1",
    ],
    "journeyRefs": ["FJ16"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1", "P03ShippingSurfaceSetV1", "P04BrandClosureSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1", "FJ16"],
    "invalidationConsumers": [
        "V23-P03-C26", "V23-P03-C28", "V23-P03-C33", "V23-P03-C47", "V23-P03-C49",
        "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR",
    ],
    "optionalCapabilityProviders": ["NONE"],
    "reservedLegacyOwnerReconciliationDebtCount": 0,
    "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0,
    "reservedLegacyRawWriteViolationPaths": [],
    "provisionalZeroViolationClosureClaimed": False,
    "sourceBoundary": "V23-P03-C25 dossier plus V21-P03-C25 inherited semantic payload; execution metadata is controlled by current V23 authority",
}

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 1,
    "predecessors": [{
        "cardID": "V23-P03-C24",
        "attemptID": 1,
        "candidateHead": "d0c7c8a48e235e783627495ccba6b0e168e9b34e",
        "candidateTree": "9f759030a7154c38ade62ce9a3273f4b33ebf18d",
        "contextDigest": "496ad67ebdeac22bd55a7675048ae54a1a297a3f83f401a5971eccc8e12d33ba",
        "pathFenceDigest": "08bd1b6091d22d234eaa18beac3d99d29540a3bdf00c4f91e01f5265f1d9346a",
        "verificationReceiptDigest": "b0903dfa37fefa29f61cb304d5119d41805e19f4b4c741a164c8e7834ab00b5f",
        "checkpointDigest": "df8810b379eb79164d7ee67c00044951a2552cf46643c333063cdba159f0325e",
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C24_HEAD",
    }],
    "canonicalRelationPreserved": True,
    "nonreleaseSpecialEdgeApplied": False,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "nativeCompileRan": False,
    "physicalLockedState": "REQUIRED_PENDING_OWNER",
    "acceptanceCredit": False,
    "releaseCredit": False,
    "createdAt": "2026-08-28T23:00:00Z",
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

SEMANTIC_SCOPE = {
    "durableOwner": ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1", "PersistentSchemaV24"],
    "durableFamilies": ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"],
    "stagingDisposition": "SURVEY_DEFINITION_IMPORT_PREVIEW_AND_DRAFT_SCRATCH_NONPERSISTENT_UNTIL_EXPLICIT_IDENTITY_OR_RELEASE_WRITE",
    "atomicAuthorityPolicy": "IMMUTABLE_IDENTITY_AND_RELEASE_EVENTS_COMMITTED_THROUGH_THE_SOLE_CANONICAL_WRITER_WITH_COMPLETE_LIFECYCLE_BYTES_IN_EXISTING_MUTATION_ENVELOPE_AND_JOURNAL",
    "templatePolicy": "ARSURVEYTemplate_HOSTILE_VALIDATION_TOTAL_BYTES_16777216_MAX_ENTRIES_128_MAX_ENTRY_BYTES_8388608_MAX_PATH_UTF8_BYTES_240_MAX_DEPTH_8_MAX_COMPRESSION_RATIO_20_IMPORTS_AS_DRAFT_ONLY",
    "grammarPolicy": "CLOSED_FIRST_GENERATION_FIELD_SET_WITH_TYPED_DEFAULTS_CONDITIONAL_VISIBILITY_REACHABILITY_SEMANTIC_DIFF_MIGRATION_PREVIEW_LOCALIZATION_AND_ACCESSIBLE_REPORT_LABELS_NO_RUNTIME_CODE_OR_GENERIC_EAV",
    "releasePolicy": "PUBLISHED_RELEASES_IMMUTABLE_EDITING_CREATES_SUCCESSOR_DRAFT_NEW_WORK_PINS_SELECTED_RELEASE_EXISTING_WORK_NEVER_SILENTLY_UPGRADES_RETIREMENT_NONDESTRUCTIVE",
    "replayPolicy": "DROP_UNACCEPTED_DERIVED_PREVIEWS_AND_REBUILD_FROM_IMMUTABLE_IDENTITY_RELEASE_AND_MUTATION_JOURNAL_FACTS_ACCEPTED_RELEASES_CORRECT_ONLY_BY_SUCCESSORS_WITH_EXACT_RECEIPTS",
    "lifecyclePolicy": "V24_EIGHTY_SEVEN_MODELS_RECORDS23_TWO_NEW_DURABLE_FAMILIES_SURVEY_DEFINITION_IDENTITY_AND_SURVEY_DEFINITION_RELEASE_LIFECYCLE_EVENT_BYTES_REMAIN_IN_EXISTING_MUTATION_ENVELOPE_AND_JOURNAL_ZERO_THIRD_ROW_ZERO_INVENTION_FROM_V23_ACCESSIBLE_DOCUMENTS_BACKUP_RESTORE_IMPORT_EXPORT_SEARCH_REPLAY_DELETE_ERASE_RETENTION_COMPATIBILITY_AND_FORWARD_FIX_CLOSED",
    "forbiddenPolicy": "NO_AUTOMATIC_ASSET_CREATION_NO_PACKAGE_CREATED_STORAGE_TABLES_NO_RUNTIME_CODE_EXECUTION_NO_ARBITRARY_JSON_EAV_NO_SCRIPTS_MACROS_NO_MARKETPLACE_OR_UNLICENSED_CONTENT_NO_SURVEY_ANSWERS_AS_INSPECTION_PASS_FAIL_NO_SILENT_SESSION_UPGRADE_NO_SECOND_WRITER_OR_STORE_NO_NETWORK_ACCOUNT_PROVIDER_OR_CLOUD",
    "s10Policy": "EXACT_ONE_HUNDRED_TWENTY_EIGHT_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP_AND_VISIBLE_UI_DEFERRED",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

CORPUS: dict[str, Any] = {
    "schema": "V22P03C25SurveyDefinitionCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "persistentSchemaVersion": 24,
    "recordsSchemaVersion": 23,
    "persistentKindLifecycleModelCount": 87,
    "durableFamilyCount": 2,
    "requiredContractNames": list(CONTRACT_NAMES),
    "activityKinds": list(ACTIVITY_KINDS),
    "lifecycleStates": list(LIFECYCLE_STATES),
    "fieldKinds": list(FIELD_KINDS),
    "sensitivities": list(SENSITIVITY_VALUES),
    "releaseDispositions": list(RELEASE_DISPOSITIONS),
    "failureCases": list(FAILURE_VALUES),
    "subjectKinds": list(SUBJECT_KINDS),
    "subjectStates": list(SUBJECT_STATES),
    "availabilityStates": list(AVAILABILITY_STATES),
    "interruptionPoints": list(INTERRUPTION_POINTS),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "evidenceCases": list(EVIDENCE_CASES),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "persistence": {
        "schemaRelease": "SURVEY_DEFINITION_IDENTITY_AND_RELEASE_V1",
        "schemaVersion": 24,
        "recordsSchemaVersion": 23,
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
        "canonicalSourceOfTruth": ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"],
        "persistedFamilies": ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"],
        "nonPersistentFamilies": ["SurveyDefinitionSemanticTreeV1", "SurveyDefinitionImportPreviewV1", "SurveyDefinitionDraftScratchV1"],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
        "secondStore": False,
        "secondWriter": False,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V24_WRITE",
        "forwardFix": "DROP_UNACCEPTED_DERIVED_PREVIEW_REBUILD_FROM_IMMUTABLE_IDENTITY_AND_RELEASE_FACTS_APPEND_SUCCESSOR_NEVER_REWRITE_RELEASE_HISTORY",
    },
    "goldenCases": [
        {"id": "five-activity-kinds", "activityKinds": list(ACTIVITY_KINDS), "exactlyFive": True, "relabelAfterStart": False},
        {"id": "immutable-published-release", "publishedImmutable": True, "successorDraftOnEdit": True, "historicReadableAfterRetirement": True},
    ],
    "alternateCases": [
        {"id": "draft-only-template-import", "quarantined": True, "importsAs": "DRAFT", "privateOriginalProjected": False},
        {"id": "explicit-bind-or-import-new", "sameDigestIdempotent": True, "identityDigestConflictRequiresExplicitChoice": True},
        {"id": "semantic-diff-preview", "previewOnly": True, "adoptionExplicit": True, "liveWorkspaceMutated": False},
    ],
    "hostileCases": [
        {"id": case_id, "expectedDisposition": "FAIL_CLOSED", "expectedBoundary": "NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "unknown-activity-kind", "duplicate-stable-identity", "duplicate-definition-id",
            "missing-release", "hidden-required-field", "unreachable-required-field",
            "invalid-conditional-visibility", "cycle-in-definition", "retire-active-session",
            "mutate-published-release", "archive-path-traversal", "archive-size-overflow",
            "runtime-code", "generic-eav", "forged-claims", "survey-as-inspection",
        )
    ],
    "interruptionCases": [
        {"id": point.lower(), "point": point, "expectedBoundary": "RETRY_IDEMPOTENT_ZERO_OR_ONE_CANONICAL_EFFECT"}
        for point in INTERRUPTION_POINTS
    ],
    "recoveryCases": [
        {"id": case_id, "expectedBoundary": "PRESERVE_IMMUTABLE_HISTORY_APPEND_VALID_SUCCESSOR"}
        for case_id in (
            "replay-from-journal", "backup-restore", "delete-erase", "import-retry",
            "publish-retry", "retirement-retry", "migration-forward-fix",
        )
    ],
    "claims": {
        claim: False
        for claim in (
            "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit",
            "releaseCredit", "providerAvailability", "cloudDurability", "network", "account",
            "externalDurability", "automaticCompletion", "automaticCompliance",
            "runtimeWebFetching", "inventedAlternateText", "hiddenEvidence",
            "secondStore", "secondWriter", "android", "web", "backend",
            "phase10PollingDuringParallelExecution",
        )
    },
}


def _git_blob(root: Path, relative: str) -> bytes:
    return subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"],
        check=True, capture_output=True,
    ).stdout


def source_artifacts(root: Path) -> list[dict[str, Any]]:
    return [
        {"path": relative, "source": "BASE_HEAD_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)}
        for relative in SOURCE_REFERENCE_PATHS
        for raw in (_git_blob(root, relative),)
    ]


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    return [
        {"path": relative, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)}
        for relative in AUTHORITY_REFERENCE_PATHS
        for raw in (_git_blob(root, relative),)
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
        return {
            "type": "object", "additionalProperties": False,
            "properties": {key: _schema_for_value(value[key]) for key in sorted(value)},
            "required": sorted(value),
        }
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    result = _schema_for_value(CORPUS)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/survey-definition.schema.json",
        "title": "V23 P03 C25 Survey Definition Corpus",
    })
    return result


def _flags() -> dict[str, bool]:
    return {
        "native": False, "hosted": False, "adoption": False, "acceptance": False,
        "release": False, "nativeAcceptance": False, "hostedAcceptance": False,
        "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False,
        "phase10PollingDuringParallelExecution": False,
    }


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationOriginMainHead": COORDINATION_ORIGIN_MAIN_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(PATH_FENCE), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "hydrationRevision": HYDRATION_REVISION,
        "hydrationCorrectionReceiptDigest": HYDRATION_CORRECTION_RECEIPT_DIGEST,
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "directPrerequisiteCards": ["V23-P03-C24"], "nextCard": "V23-P03-C26",
        "sourceDossierSHA256": DOSSIER_SHA256, "sourceDossierUTF8Length": DOSSIER_UTF8_LENGTH,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    }


def _sealed(body: dict[str, Any], field: str = "artifactDigest") -> dict[str, Any]:
    result = dict(body)
    result[field] = sha256_bytes(pretty(body))
    return result


def _observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift"
    if path.is_file():
        values = tuple(re.findall(r"\bfunc\s+(testV23P03C25[A-Z]\w*)\s*\(", path.read_text(encoding="utf-8")))
        if len(values) == 5:
            return values
    return TEST_METHODS


def contract_document(schema_row: dict[str, Any], selectors: tuple[str, ...]) -> dict[str, Any]:
    required = {
        "contractNames": list(CONTRACT_NAMES), "activityKinds": list(ACTIVITY_KINDS),
        "lifecycleStates": list(LIFECYCLE_STATES), "fieldKinds": list(FIELD_KINDS),
        "sensitivities": list(SENSITIVITY_VALUES), "releaseDispositions": list(RELEASE_DISPOSITIONS),
        "failureCases": list(FAILURE_VALUES), "subjectKinds": list(SUBJECT_KINDS),
        "subjectStates": list(SUBJECT_STATES), "availabilityStates": list(AVAILABILITY_STATES),
        "interruptionPoints": list(INTERRUPTION_POINTS),
        "runtimeActivityKindEnum": "ActivityKindV1",
        "runtimeLifecycleStateEnum": "SurveyDefinitionLifecycleStateV1",
        "runtimeIdentityType": "SurveyDefinitionIdentityV1",
        "runtimeReleaseType": "SurveyDefinitionReleaseV1",
        "runtimeLifecycleEventType": "SurveyDefinitionLifecycleEventV1",
        "persistentSchemaVersion": 24, "recordsSchemaVersion": 23,
        "persistentKindLifecycleModelCount": 87, "durableFamilyCount": 2,
        "persistentFamilies": ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"],
        "nonPersistentFamilies": ["SurveyDefinitionSemanticTreeV1", "SurveyDefinitionImportPreviewV1", "SurveyDefinitionDraftScratchV1"],
        "lifecycleEventStorage": "EXISTING_MUTATION_ENVELOPE_AND_JOURNAL",
        "genericMutationReceiptKind": "MutationReceiptV1",
        "derivedSemanticTree": True, "immutablePublishedRelease": True,
        "importAlwaysDraft": True, "publishedEditCreatesSuccessor": True,
        "liveWorkspaceMutation": False, "sourceBytesInProjections": False,
        "runtimeFetching": False, "remoteIdentity": False,
        "fiveActivityKinds": list(ACTIVITY_KINDS), "fiveSelectors": list(selectors),
        "templateLimits": {
            "maxArchiveBytes": 16777216, "maxEntries": 128, "maxEntryBytes": 8388608,
            "maxPathUTF8Bytes": 240, "maxDepth": 8, "maxCompressionRatio": 20,
        },
        "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    }
    body = {
        "artifact": "V23P03C25SurveyDefinitionContractV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY", "title": TITLE, "authority": _authority(),
        "sourceProjection": SOURCE_PROJECTION, "requiredSemantics": required,
        "semanticScope": SEMANTIC_SCOPE, "persistenceBoundary": CORPUS["persistence"],
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "evidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(selectors),
        "schemaArtifact": schema_row, "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def evidence_document(
    source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]],
    schema_row: dict[str, Any], contract: dict[str, Any], selectors: tuple[str, ...],
) -> dict[str, Any]:
    required = contract["requiredSemantics"]
    body = {
        "artifact": "V23P03C25SurveyDefinitionEvidenceReceiptV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY", "authority": _authority(),
        "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows,
        "requiredSemanticsDigest": sha256_value(required), "requiredSemantics": required,
        "evidenceCases": list(EVIDENCE_CASES), "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(selectors), "schemaArtifact": schema_row,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "staticBoundary": "NO_NATIVE_HOSTED_ADOPTION_ACCEPTANCE_RELEASE_PROVIDER_NETWORK_ACCOUNT_CLOUD_OR_PHASE10_CLAIM",
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def brand_document(contract: dict[str, Any]) -> dict[str, Any]:
    body = {
        "artifact": "V23P03C25BrandImpactManifestV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY", "brandSurfaceDelta": True, "uiSurfaceDelta": False,
        "impact": "CLOSED_ACTIVITY_KINDS_AND_IMMUTABLE_GUIDED_SURVEY_RELEASES_REMAIN_LOCAL_MANUAL_PRIVACY_SAFE_WITH_NO_NEW_S10_UI_SURFACE",
        "preserved": ["immutable-release-history", "draft-only-exchange", "existing-writer-and-journal", "existing-report-search-backup-restore-delete-erase", "S10-reserved-brand-assets"],
        "deferred": ["native-build", "hosted-CI", "adoption", "acceptance", "release", "provider", "network", "account", "cloud", "Phase10"],
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
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    selectors = _observed_selectors(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract = contract_document(schema_row, selectors)
    evidence = evidence_document(source_rows, authority_rows, schema_row, contract, selectors)
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: schema_raw, CONTRACT_PATH: pretty(contract),
        EVIDENCE_PATH: pretty(evidence), BRAND_PATH: pretty(brand_document(contract)),
    }
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "artifact": "V23P03C25ToolingManifestV1", "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY", "authority": _authority(),
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS),
        "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows, "artifacts": rows, "artifactSetDigest": sha256_value(rows),
        "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "persistenceBoundary": CORPUS["persistence"], "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
        "evidenceDigest": evidence["artifactDigest"], "testSelectors": list(selectors),
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def assert_corpus() -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (114, 14, 128):
        raise ValueError("C25 path fence must be exactly 128=114+14")
    if len(set(PATH_FENCE)) != 128:
        raise ValueError("C25 path fence contains duplicates")
    if CORPUS["persistentSchemaVersion"] != 24 or CORPUS["recordsSchemaVersion"] != 23:
        raise ValueError("C25 persistence versions differ")
    if CORPUS["persistentKindLifecycleModelCount"] != 87 or CORPUS["durableFamilyCount"] != 2:
        raise ValueError("C25 model/family counts differ")
    if CORPUS["requiredContractNames"] != list(CONTRACT_NAMES):
        raise ValueError("C25 contract family set differs")
    if CORPUS["persistence"]["persistedFamilies"] != ["SurveyDefinitionIdentityV1", "SurveyDefinitionReleaseV1"]:
        raise ValueError("C25 durable family set differs")
    if CORPUS["persistence"]["secondStore"] or CORPUS["persistence"]["secondWriter"]:
        raise ValueError("C25 second store/writer is prohibited")
    if tuple(PRIOR_FENCE_PROOF.get(key) for key in ("fenceCount", "priorOwnedPathCount", "overlapCount", "authorizedOverlapCount", "unauthorizedOverlapCount")) != (62, 1032, 1308, 1308, 0):
        raise ValueError("C25 prior-fence proof counts differ")
    if len(PRIOR_FENCE_OVERLAPS) != 1308 or not all(
        isinstance(row, dict) and isinstance(row.get("path"), str)
        and isinstance(row.get("priorCardID"), str) and isinstance(row.get("priorFenceDigest"), str)
        and isinstance(row.get("disposition"), str) and isinstance(row.get("boundEvidence"), dict)
        for row in PRIOR_FENCE_OVERLAPS
    ):
        raise ValueError("C25 prior-fence proof edges differ")


assert_corpus()
