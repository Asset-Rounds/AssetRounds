#!/usr/bin/env python3
"""Deterministic activity-contract-family tooling model for V23-P03-C47."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
_BASE = Path(__file__).with_name("p03_c46_contracts.py")
_BASE_SHA256 = "53d75bddf01a4d256d5b3cbc1c278592515301cc1925c7d217aa3cfef58ea43b"
if hashlib.sha256(_BASE.read_bytes()).hexdigest() != _BASE_SHA256:
    raise ValueError("sealed C46 tooling model differs")
exec(compile(_BASE.read_text(encoding="utf-8"), str(_BASE), "exec"), globals())

CARD = "V23-P03-C47"
TITLE = "Shared activity envelope with independent installation and standalone punch contracts, readiness, variation, and closeout truth"
REGISTER_ORDINAL = 77
BASE_HEAD = "1277773b210cb9abc83564897e799951ca82b911"
BASE_TREE = "cc6484cad20d5cbaf5b575a8dd0bc31533bb77a7"
COORDINATION_HEAD = "050ebc4848dcf3d146508613e30293a2047192bd"
COORDINATION_TREE = "11fbe750fd9c267b5d99ef5fe9473d617d8671c9"
COORDINATION_CAS_SEQUENCE = 326
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "c1f51f31dc12bb02b3d4ec626273b425a564582bc411d6f1810c854c95392266"
CONTEXT_DIGEST = "8605e88d350858e6aea3362aa379e3bdb3a1d4956b694045d3e78b726e922be4"
FENCE_DIGEST = "3f4132bbfa489157b19ab52e68d800e34ea0ed7781b9e27d870e6f929db7b59b"
HYDRATION_TRANSITION_DIGEST = "5ddc09535ad5e7faec88ea4e48c399f35fc88f105d2497ba07f66be927b37f6b"
COORDINATION_LEDGER_DIGEST = "58ff2d4b22a3a3900ef8f22dd4f49e16dbee39f1390abde8ff40fa200d3a024c"
COORDINATION_PROJECTION_DIGEST = "10b70b91b31980e639a4a25a769758bdd9d17619bc3b8862ac4f88ad6ed6a3ec"
AUTHORIZED_OVERLAP_COUNT = 2521
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/activity-contract-families.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C47ActivityContractFamiliesV2.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C47ActivityContractEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C47BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C47-tooling-manifest.json"
SCRIPT_PATHS = ("Scripts/v23/p03_c47_contracts.py", "Scripts/v23/generate_p03_c47_contracts.py", "Scripts/v23/verify_p03_c47_contracts.py")
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Activities/ActivityContractFamiliesV2.swift",
    "FieldEvidenceApp/Domain/Models/ActivityContractPersistenceModelsV2.swift",
    "FieldEvidenceApp/Application/Activities/ActivityContractCoordinatorV2.swift",
    "FieldEvidenceApp/Infrastructure/Activities/ActivityContractLifecycleAdapterV2.swift",
    "FieldEvidenceAppTests/V9_54ActivityContractFamiliesTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Activities/V22P03C47ActivityContractCorpusV2.json",
)
EXISTING_PATHS: tuple[str, ...] = (
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowDefinitionV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGraphValidatorV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ResponseFieldDefinitionV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ResponseValueV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Domain/Packs/PackageEvolutionContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/WorkflowContracts.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkflowModels.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
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
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift",
    "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
    "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Settings/FeaturePolicyLoaderV1.swift",
    "FieldEvidenceApp/Application/Packs/PackageEvolutionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/PackageEvolutionLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
    "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
    "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
    "FieldEvidenceAppTests/S4_4HistoryComparisonTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_1SecondPackZeroForkTests.swift",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift",
    "FieldEvidenceAppTests/V9_11PackRegistryTests.swift",
    "FieldEvidenceAppTests/V9_12WorkflowGraphTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_13TypedResponseTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_17KernelPersistenceTests.swift",
    "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/V9_32PackageEvolutionTests.swift",
    "FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/SurveyDefinitionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/SurveyDefinitions/V22P03C25SurveyDefinitionCorpusV1.json",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = ("SharedActivityEnvelopeReceiptV1", "InstallationActivityContractReceiptV1", "PunchActivityContractReceiptV1", "NoPlanFallbackV1")
TEST_METHODS = (
    "testV23P03C47G01SharedEnvelopeInstallationAndPunchAcceptAsThreeIsolatedReceipts",
    "testV23P03C47A01NoPlanFallbackReadinessDeferredUnableAndCancellationRemainExact",
    "testV23P03C47H01CrossFamilyClaimsInvalidTransitionsAndStaleInputsFailClosed",
    "testV23P03C47I01ThreeReceiptWriterInterruptionRecoversWithoutCrossFamilyMutation",
    "testV23P03C47R01BackupRestoreReplayDeleteEraseSearchReportAndForwardFixRemainExact",
)
CONFORMANCE_RECEIPTS = ("SharedActivityEnvelopeReceiptV1", "InstallationActivityContractReceiptV1", "PunchActivityContractReceiptV1")
DURABLE_FAMILIES = ("ActivitySessionEnvelopeV2", "ActivityStateTransitionV2", "CompletedActivitySnapshotV2", "InstallationTaskResultV1", "InstallationAsBuiltSnapshotV1", "PunchReviewBasisSnapshotV1")
NEW_DURABLE_ROW_CLASSES = ("ActivitySessionEnvelopeV2", "ActivityStateTransitionV2", "InstallationTaskResultV1", "InstallationAsBuiltSnapshotV1", "PunchReviewBasisSnapshotV1")
RELEASED_DURABLE_COMPATIBILITY_REFERENCES = {"CompletedActivitySnapshotV2": {"referenceType": "CompletedActivitySnapshotV2CompatibilityReferenceV1", "member": "completedSnapshotReference", "parallelRowForbidden": True}}
C47_PERSISTENT_ROW_CLASSES = (
    "ActivitySessionEnvelopeRow", "ActivityStateTransitionRow",
    "InstallationTaskResultRow", "InstallationAsBuiltSnapshotRow",
    "PunchReviewBasisSnapshotRow",
)
C47_SCHEMA_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"
C47_MIGRATION_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift"
C47_IMPORT_SOURCE_PATH = "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift"
C47_BACKUP_SOURCE_PATH = "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift"
C47_RESTORE_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift"
C47_REPLACEMENT_SOURCE_PATH = "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift"
C47_DELETION_LEDGER_SOURCE_PATH = "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift"
C47_DELETION_INTENT_SOURCE_PATH = "FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift"
C47_WHOLE_SIGN_RULE_SOURCE_PATH = "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift"
C47_DELETION_STORE_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift"
C47_WRITER_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift"
C47_WRITER_PORT_SOURCE_PATH = "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift"
C47_MUTATION_SOURCE_PATH = "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift"
C47_RECEIPT_SOURCE_PATH = "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift"
C47_WORKFLOW_LIFECYCLE_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Packs/PackageEvolutionLifecycleAdapterV1.swift"
ACTIVITY_KINDS = ("INSPECTION", "SURVEY", "PREVENTIVE_MAINTENANCE", "REPAIR", "OPERATIONAL_RECHECK", "INSTALLATION", "PUNCH_REVIEW")
HOSTILE_CASES = ("INSPECTION_PASS_COMPLIANT_CERTIFIED_APPROVED_VOCABULARY_LEAKAGE", "STALE_OR_TAMPERED_BASIS", "MISSING_SUBJECT_OR_REFERENCE", "UNSAFE_ACCESS_SITE_MATERIAL_WEATHER_OR_EQUIPMENT_BLOCKER", "DUPLICATE_FINDING_TRUTH", "PLAN_REBASE_OR_PHYSICAL_MOVE_DURING_WORK", "PACKAGE_UPDATE_OR_RETIREMENT", "PARTIAL_FINALIZATION_RACE")
INTERRUPTION_BOUNDARIES = ("EVERY_LIFECYCLE_TRANSITION", "TASK_OR_ITEM_SAVE", "EVIDENCE_PROMOTION", "PLACEMENT_OR_FINDING_MUTATION", "FINALIZATION", "REPORT_BOUNDARY")
FLAGS = {key: False for key in ("native", "hosted", "physical", "adoption", "acceptance", "release", "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution")}
COMPATIBILITY_KEY = "c47ActivityContractCompatibility"
COMPATIBILITY = {
    "compatibilityCardID": CARD,
    "sharedEnvelopeDoesNotCollapseFamilyTruth": True,
    "installationAndPunchReceiptsRemainIndependent": True,
    "noPlanFallbackIsExplicit": True,
    "surveyDefinitionOwnershipIsPreserved": True,
    "legacyInspectionTruthIsNotRewritten": True,
    "threeReceiptIsolationIsRequired": True,
}
EXISTING_TEST_PATHS = tuple(path for path in EXISTING_PATHS if path.startswith("FieldEvidenceAppTests/"))
EXISTING_SWIFT_TEST_PATHS = tuple(path for path in EXISTING_TEST_PATHS if path.endswith(".swift"))
COMPATIBILITY_CORPORA = tuple(path for path in EXISTING_TEST_PATHS if path.endswith(".json"))


def compatibility_marker(path: str) -> str:
    return "C47ActivityContractCompatibility_" + re.sub(r"[^A-Za-z0-9]", "_", path)


def _compatibility_tests(root: Path) -> None:
    if (len(EXISTING_TEST_PATHS), len(EXISTING_SWIFT_TEST_PATHS), len(COMPATIBILITY_CORPORA)) != (33, 32, 1):
        raise ValueError("C47 existing test compatibility inventory differs")
    tokens = tuple(COMPATIBILITY.keys())
    for path in EXISTING_SWIFT_TEST_PATHS:
        text = _text(root, path)
        if compatibility_marker(path) not in text or any(token not in text for token in tokens):
            raise ValueError("C47 existing Swift compatibility closure differs:" + path)
    for path in COMPATIBILITY_CORPORA:
        if json.loads(_text(root, path)).get(COMPATIBILITY_KEY) != COMPATIBILITY:
            raise ValueError("C47 existing corpus compatibility closure differs:" + path)


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file(): return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C47(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def _closed_corpus(root: Path) -> dict[str, Any]:
    value = json.loads(_text(root, IMPLEMENTATION_PATHS[5]))
    keys = {"schema", "schemaVersion", "cardID", "classification", "persistentSchemaVersion", "recordsSchemaVersion", "durableFamilies", "contractNames", "activityKinds", "sharedEnvelopeCases", "installationCases", "punchCases", "readinessCases", "variationCases", "hostileCases", "interruptionBoundaries", "lifecycle", "invariants", "evidenceIDs", "statusFlags"}
    if set(value) != keys: raise ValueError("C47 closed corpus top-level differs")
    return value


def _require_tokens(text: str, tokens: tuple[str, ...], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"{label} missing:" + ",".join(missing))


def _require_patterns(text: str, patterns: tuple[str, ...], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.S) is None]
    if missing:
        raise ValueError(f"{label} missing:" + ",".join(missing))


def _require_any_pattern(text: str, patterns: tuple[str, ...], label: str) -> None:
    if not any(re.search(pattern, text, re.S) is not None for pattern in patterns):
        raise ValueError(f"{label} missing:" + " OR ".join(patterns))


def _swift_decl_block(text: str, declaration: str) -> str:
    start = text.find(declaration)
    if start < 0:
        raise ValueError("Swift declaration absent:" + declaration)
    opening = text.find("{", start)
    if opening < 0:
        raise ValueError("Swift declaration body absent:" + declaration)
    depth = 0
    for offset in range(opening, len(text)):
        if text[offset] == "{":
            depth += 1
        elif text[offset] == "}":
            depth -= 1
            if depth == 0:
                return text[start:offset + 1]
    raise ValueError("Swift declaration body unterminated:" + declaration)


def _source_slice(text: str, start_marker: str, end_marker: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise ValueError("source marker absent:" + start_marker)
    end = text.find(end_marker, start + len(start_marker))
    if end < 0:
        raise ValueError("source marker absent:" + end_marker)
    return text[start:end]


def _require_order(text: str, first: str, second: str, label: str) -> None:
    first_offset = text.find(first)
    second_offset = text.find(second)
    if first_offset < 0 or second_offset < 0 or first_offset >= second_offset:
        raise ValueError(f"{label} order differs:{first}->{second}")


def _assert_typed_conformance_authority(
    contracts: str, coordinator: str
) -> None:
    authority = _swift_decl_block(
        coordinator, "struct ActivityContractConformanceAuthorityV2"
    )
    _require_patterns(
        authority,
        (
            r"struct\s+ActivityContractConformanceAuthorityV2\s*:\s*Equatable\s*,\s*Sendable",
            r"let\s+sharedReceipt\s*:\s*SharedActivityEnvelopeReceiptV1",
            r"let\s+installationContractSHA256\s*:\s*String",
            r"let\s+punchContractSHA256\s*:\s*String",
            r"let\s+noPlanFallback\s*:\s*NoPlanFallbackV1",
            r"func\s+validate\(\s*_\s+payload\s*:\s*ActivityContractAcceptancePayloadV2\s*\)",
            r"func\s+receipt\(for\s+family\s*:\s*ActivityContractAcceptanceFamilyV2\s*\)",
        ),
        "C47 immutable typed conformance authority",
    )
    for instance_field in ("activityID", "workspaceID", "revision"):
        if re.search(rf"\b{instance_field}\b", authority):
            raise ValueError(
                "C47 conformance authority must be independent of activity instance:"
                + instance_field
            )
    _require_patterns(
        coordinator,
        (
            r"private\s+let\s+conformanceAuthority\s*:\s*ActivityContractConformanceAuthorityV2",
            r"try\s+conformanceAuthority\.validate\(request\.payload\)",
            r"case\s+shared\(",
            r"case\s+installation\(",
            r"case\s+punch\(",
        ),
        "C47 typed acceptance authority wiring",
    )
    _require_tokens(
        contracts,
        (
            "ActivityContractConformancePersistenceV1",
            "SharedActivityEnvelopeReceiptV1",
            "InstallationActivityContractReceiptV1",
            "PunchActivityContractReceiptV1",
        ),
        "C47 typed conformance receipt declarations",
    )


def _assert_mutation_image_identities(root: Path, tests: str) -> None:
    mutation_support = _text(root, C47_MUTATION_SOURCE_PATH)
    mutation_extension = _source_slice(
        mutation_support,
        "extension ActivityContractMutationV2",
        "enum WorkspaceCommandV1",
    )
    _require_patterns(
        mutation_extension,
        (
            r"var\s+affectedIdentities\s*:\s*\[WorkspaceEntityIdentityV1\]",
            r"Set\(ordered\)\.count\s*==\s*ordered\.count",
            r"var\s+concurrencyIdentities\s*:\s*\[WorkspaceEntityIdentityV1\]",
            r"try\s+affectedIdentities",
            r"expectedByIdentity\.count\s*==\s*expectedRevision\.entityRevisions\.count",
            r"expectedByIdentity\[activityIdentity\]\s*==\s*\(predecessorEnvelope\?\.revision\s*\?\?\s*0\)",
        ),
        "C47 unique mutation image identities",
    )

    receipt_support = _text(root, C47_RECEIPT_SOURCE_PATH)
    image_extensions: list[tuple[str, str]] = []
    for path, source in (
        (C47_MUTATION_SOURCE_PATH, mutation_support),
        (C47_RECEIPT_SOURCE_PATH, receipt_support),
    ):
        for match in re.finditer(
            r"extension\s+ActivityContractMutationV2\b", source
        ):
            block = _swift_decl_block(source[match.start():], match.group(0))
            if re.search(r"var\s+mutationPostImages", block):
                image_extensions.append((path, block))
    if len(image_extensions) != 1:
        raise ValueError(
            "C47 mutationPostImages must have exactly one canonical implementation"
        )
    image_extension = image_extensions[0][1]
    _require_patterns(
        image_extension,
        (
            r"var\s+mutationPostImages\s*:\s*\[MutationPostImageV1\]",
            r"let\s+ordered\s*=\s*try\s+values\.sorted",
            r"Set\(try\s+ordered\.map\s*\{\s*try\s+\$0\.identity\s*\}\)\.count\s*==\s*ordered\.count",
            r"Set\(try\s+ordered\.map\s*\{\s*try\s+\$0\.concurrencyIdentity\s*\}\)\.count\s*==\s*ordered\.count",
            r"ordered\.allSatisfy\(\{\s*try\s+\$0\.identity\s*==\s*\$0\.concurrencyIdentity",
        ),
        "C47 canonical post-image identity guard",
    )
    _require_patterns(
        tests,
        (
            r"postImages",
            r"mutationPostImages",
            r"Set\(.*?(?:postImages|mutationPostImages).*?(?:identity|Identity)",
        ),
        "C47 mutation post-image identity regression test",
    )


def _assert_retired_release_and_unknown_kind(
    root: Path, contracts: str, tests: str
) -> None:
    availability_disposition = _swift_decl_block(
        contracts, "enum ActivityWorkflowFamilyAvailabilityDispositionV2"
    )
    _require_patterns(
        availability_disposition,
        (r"case\s+availableForStart", r"case\s+historicReadExportOnly"),
        "C47 historic workflow availability dispositions",
    )
    availability = _swift_decl_block(
        contracts, "struct ActivityWorkflowFamilyAvailabilityV2"
    )
    _require_patterns(
        availability,
        (
            r"func\s+validate\(reference\s*:\s*ActivityWorkflowReleaseReferenceV2,\s*forStart\s*:\s*Bool\)",
            r"!forStart\s*\|\|\s*disposition\s*==\s*\.availableForStart",
            r"workflowReleaseReferenceSHA256\s*==\s*reference\.referenceSHA256",
        ),
        "C47 retired release read/export versus start gate",
    )
    resolution = _swift_decl_block(
        contracts, "enum ActivityWorkflowReleaseResolutionContextV2"
    )
    _require_patterns(
        resolution,
        (
            r"availability\.validate\(reference\s*:\s*reference,\s*forStart\s*:\s*false\)",
            r"func\s+validate\(expectedReference\s*:\s*ActivityWorkflowReleaseReferenceV2,\s*forStart\s*:\s*Bool\)",
            r"availability\.validate\(reference\s*:\s*reference,\s*forStart\s*:\s*forStart\)",
        ),
        "C47 released workflow read/export resolution",
    )
    lifecycle = _text(root, C47_WORKFLOW_LIFECYCLE_SOURCE_PATH)
    _require_patterns(
        lifecycle,
        (
            r"resolveActivityWorkflowRelease\(",
            r"forStart\s*:\s*Bool",
            r"var\s+disposition\s*:\s*ActivityWorkflowFamilyAvailabilityDispositionV2\s*=\s*\.historicReadExportOnly",
            r"if\s+forStart\s*,\s*disposition\s*!=\s*\.availableForStart",
            r"ActivityWorkflowFamilyAvailabilityV2\(",
        ),
        "C47 retired release lifecycle resolution",
    )

    kind = _swift_decl_block(contracts, "enum ActivityKindV2") + _swift_decl_block(
        contracts, "extension ActivityKindV2: Codable"
    )
    _require_patterns(
        kind,
        (
            r"case\s+unknown\(String\)",
            r"var\s+rawValue\s*:\s*String",
            r"case\s+let\s+\.unknown\(value\)\s*:\s*return\s+value",
            r"init\(preservingRawValue\s+value\s*:\s*String\)",
            r"default\s*:\s*self\s*=\s*\.unknown\(value\)",
            r"init\(from\s+decoder\s*:\s*Decoder\)",
            r"encode\(to\s+encoder\s*:\s*Encoder\)",
            r"func\s+requireKnownForMutation\(\)\s*throws",
            r"ActivityContractFailureV2\.unknownKindMutation",
        ),
        "C47 unknown-kind lossless read/export boundary",
    )
    compatibility = _swift_decl_block(
        contracts, "enum ActivityKindCompatibilityDispositionV2"
    )
    _require_patterns(
        compatibility,
        (r"case\s+unknownReadExportOnly\s*=\s*\"UNKNOWN_READ_EXPORT_ONLY\"",),
        "C47 unknown-kind compatibility disposition",
    )
    _require_patterns(
        contracts,
        (
            r"if\s+case\s+\.unknown\s*=\s+value\s*\{\s*return\s+\.unknownReadExportOnly",
            r"requireNewC47RowMutationAuthority\(.*?requireKnownForMutation\(\)",
        ),
        "C47 unknown-kind mutation rejection wiring",
    )
    _require_patterns(
        tests,
        (
            r"unknownBytes",
            r"JSONDecoder\(\)\.decode\(ActivityKindV2\.self",
            r"JSONEncoder\(\)\.encode\(unknown\)",
            r"\.unknownReadExportOnly",
            r"unknown\.requireKnownForMutation\(\)",
            r"\.unknownKindMutation",
            r"historicAvailability",
            r"\.historicReadExportOnly",
            r"forStart\s*:\s*false",
            r"forStart\s*:\s*true",
            r"retired",
        ),
        "C47 unknown-kind and retired-release regression tests",
    )


def _assert_task_coverage_and_as_built_freshness(
    root: Path, contracts: str, tests: str
) -> None:
    task_definition = _swift_decl_block(
        contracts, "struct InstallationTaskDefinitionV1"
    )
    _require_patterns(
        task_definition,
        (
            r"let\s+taskID\s*:\s*String",
            r"ActivityContractValidationV2\.token\(taskID\)",
            r"evidencePurposes",
        ),
        "C47 installation task identity definition",
    )
    workflow = _swift_decl_block(
        contracts, "struct InstallationWorkflowDefinitionReleaseV1"
    )
    _require_patterns(
        workflow,
        (
            r"let\s+tasks\s*:\s*\[InstallationTaskDefinitionV1\]",
            r"ActivityContractValidationV2\.sortedUnique\(tasks\.map\(\\\.taskID\)\)",
        ),
        "C47 required workflow task identity coverage",
    )
    lineage = _swift_decl_block(
        contracts, "enum InstallationTaskResultLineageV1"
    )
    _require_patterns(
        lineage,
        (
            r"validateAndCurrentHeads",
            r"Set\(values\.map\(\\\.taskID\)\)|heads\[value\.taskID\]",
            r"value\.validateSuccessor\(of\s*:\s*predecessor\)",
        ),
        "C47 task result lineage and current heads",
    )
    resolved = _swift_decl_block(contracts, "func validateResolved(")
    _require_patterns(
        resolved,
        (
            r"installationTaskHeads\s*:\s*InstallationTaskCurrentHeadContextV1",
            r"try\s+installationTaskHeads\.validate\(successors\s*:\s*installationTaskResults\)",
            r"(?:let|var)\s+resolvedTaskHeads\s*=\s*installationTaskHeads\.headsByTaskID",
            r"Set\(installationAsBuiltSnapshot\.taskResultSHA256s\)",
            r"Set\(resolvedTaskHeads\.values\.map\(\\\.resultSHA256\)\)",
            r"(?:requiredTaskIDs|requiredTasks|workflowReleaseContext.*?tasks|release\.tasks).*?taskID",
        ),
        "C47 required-task and as-built freshness validation",
    )
    _require_any_pattern(
        resolved,
        (
            r"Set\(.*?taskID.*?\)\s*==\s*Set\(.*?(?:required|tasks).*?\)",
            r"taskID.*?sorted\(\).*?(?:required|tasks)",
            r"(?:requiredTaskIDs|requiredTasks).*?(?:contains|allSatisfy|isSubset|==).*?taskID",
        ),
        "C47 required-task set coverage",
    )
    writer = _text(root, C47_WRITER_SOURCE_PATH)
    _require_patterns(
        writer,
        (
            r"InstallationTaskResultLineageV1\s*\.\s*validateAndCurrentHeads",
            r"currentHeads\s*:\s*Array\(currentTaskHeads\.values\)",
            r"currentInstallationBasis\(in:\s*installationValues\)",
            r"try\s+mutation\.validateResolved\(",
        ),
        "C47 persisted task-head and basis freshness",
    )
    _require_order(
        writer,
        "try mutation.validateResolved(",
        "if let predecessor = mutation.predecessorEnvelope",
        "C47 semantic resolution before restore insert",
    )
    _require_patterns(
        tests,
        (
            r"taskID",
            r"currentHeads",
            r"taskResultSHA256s",
            r"requiredTaskIDs|requiredTasks|missingRequiredTask|missingTerminalTaskHeads|unknownTask|undeclaredTask",
            r"resolvedAsBuilt",
            r"staleRevision|stale.*head|current.*head",
        ),
        "C47 required-task and as-built freshness tests",
    )


def _assert_decoded_nested_basis_sources(
    root: Path, contracts: str, persistence: str, tests: str
) -> None:
    source = _swift_decl_block(contracts, "enum ActivityBasisSourceV1")
    _require_patterns(
        source,
        (
            r"case\s+noPlan\(NoPlanFallbackV1\)",
            r"case\s+optionalPlan\(ActivityExternalReferenceV1\)",
            r"case\s+externalLocal\(ActivityExternalReferenceV1\)",
            r"func\s+validate\(\)\s*throws",
            r"switch\s+self",
            r"(?:noPlan|optionalPlan|externalLocal).*?validate",
        ),
        "C47 typed basis-source validation",
    )
    external = _swift_decl_block(contracts, "struct ActivityExternalReferenceV1")
    _require_patterns(
        external,
        (
            r"func\s+validate\(\)\s*throws",
            r"ActivityContractValidationV2\.token\(referenceID\)",
            r"revision\s*>\s*0",
            r"ActivityContractValidationV2\.digest\(sha256\)",
        ),
        "C47 decoded external basis-source validation",
    )
    for declaration, label in (
        ("struct InstallationBasisSnapshotV1", "C47 decoded installation basis source"),
        ("struct PunchReviewBasisSnapshotV1", "C47 decoded punch basis source"),
    ):
        basis = _swift_decl_block(contracts, declaration)
        _require_patterns(
            basis,
            (
                r"let\s+source\s*:\s*ActivityBasisSourceV1",
                r"try\s+source\.validate\(\)",
                r"source\s*:\s*source",
            ),
            label,
        )
    for declaration, label in (
        ("ActivitySessionEnvelopeRow", "C47 decoded envelope row"),
        ("ActivityStateTransitionRow", "C47 decoded transition row"),
        ("InstallationTaskResultRow", "C47 decoded task row"),
        ("InstallationAsBuiltSnapshotRow", "C47 decoded as-built row"),
        ("PunchReviewBasisSnapshotRow", "C47 decoded punch-basis row"),
    ):
        row = _swift_decl_block(persistence, f"@Model final class {declaration}")
        validation_pattern = (
            r"try\s+value\.validateForRead\(\)"
            if declaration == "ActivitySessionEnvelopeRow"
            else r"try\s+value\.validate\(\)"
        )
        _require_patterns(
            row,
            (
                r"ActivityContractPersistenceCodecV2\.decode\(",
                validation_pattern,
                r"canonicalData\s*==\s*\(try\s+ActivityContractPersistenceCodecV2\.encode\(value\)\)",
            ),
            label,
        )
    _require_patterns(
        tests,
        (
            r"JSONDecoder\(\)",
            r"ActivityBasisSourceV1",
            r"source",
            r"validate\(\)",
            r"(?:nested|decoded|corrupt|tampered)",
        ),
        "C47 decoded nested basis-source tests",
    )


def _assert_no_plan_fallback(
    contracts: str, persistence: str, lifecycle: str
) -> None:
    fallback = _swift_decl_block(contracts, "struct NoPlanFallbackV1")
    _require_patterns(
        fallback,
        (
            r"manualSubjectSelectionRequired\s*=\s*true",
            r"planRequired\s*=\s*false",
            r"scanRequired\s*=\s*false",
            r"!planRequired",
            r"!scanRequired",
        ),
        "C47 explicit NoPlanFallbackV1",
    )
    for name in CONFORMANCE_RECEIPTS:
        receipt = _swift_decl_block(contracts, f"struct {name}")
        _require_patterns(
            receipt,
            (
                r"persistence\s*=\s*\.nonpersistent",
                r"persistence\s*==\s*\.nonpersistent",
            ),
            "C47 nonpersistent receipt " + name,
        )
    enrollment = _swift_decl_block(
        contracts, "enum ActivityContractPersistenceEnrollmentV2"
    )
    match = re.search(r"nonpersistentFamilies\s*=\s*\[(.*?)\]", enrollment, re.S)
    if match is None:
        raise ValueError("C47 nonpersistent family enrollment absent")
    enrolled = tuple(re.findall(r'"([^"\\]+)"', match.group(1)))
    if enrolled != CONTRACT_NAMES:
        raise ValueError("C47 nonpersistent family enrollment differs")
    _require_patterns(
        persistence,
        (
            r"nonpersistentConformanceReceipts\s*=\s*ActivityContractPersistenceEnrollmentV2\.nonpersistentFamilies",
            r"noPlanFallbackPersistent\s*=\s*false",
        ),
        "C47 nonpersistent persistence boundary",
    )
    model_names = tuple(
        re.findall(r"@Model\s+final\s+class\s+([A-Za-z0-9_]+)", persistence)
    )
    if any(
        name in model_names
        for name in (*CONFORMANCE_RECEIPTS, "NoPlanFallbackV1")
    ):
        raise ValueError("C47 NoPlanFallback or receipt gained a durable model")
    _require_patterns(
        lifecycle,
        (
            r"conformanceReceiptsAreNeverBackedUp\s*=\s*true",
            r"backupPreparationLeavesLiveDerivedStateIntact\s*=\s*true",
        ),
        "C47 nonpersistent backup boundary",
    )


def _assert_basis_closeout_resolution(
    root: Path, contracts: str, coordinator: str, tests: str
) -> None:
    as_built = _swift_decl_block(contracts, "struct InstallationAsBuiltSnapshotV1")
    _require_patterns(
        as_built,
        (
            r"basisReference\s*:\s*InstallationBasisReferenceV1",
            r"basisSHA256",
            r"func\s+validateBasis\(\s*_\s+basis\s*:\s*InstallationBasisSnapshotV1\s*\)",
            r"taskResultSHA256s",
        ),
        "C47 as-built basis binding",
    )
    heads = _swift_decl_block(contracts, "struct InstallationTaskCurrentHeadContextV1")
    _require_patterns(
        heads,
        (
            r"headsByTaskID\s*:\s*\[String\s*:\s*InstallationTaskResultV1\]",
            r"currentHeads\s*:\s*\[InstallationTaskResultV1\]",
            r"func\s+validate\(\s*successors\s*:\s*\[InstallationTaskResultV1\]\s*\)",
            r"successor\.validateSuccessor\(of:\s*predecessor\)",
        ),
        "C47 current installation task heads",
    )
    resolved = _swift_decl_block(contracts, "func validateResolved(")
    _require_patterns(
        resolved,
        (
            r"installationTaskHeads\s*:\s*InstallationTaskCurrentHeadContextV1",
            r"currentInstallationBasis\s*:\s*InstallationBasisSnapshotV1\?\s*=\s*nil",
            r"let\s+resolvedBasis\s*=\s*installationBasisSnapshot\s*\?\?\s*currentInstallationBasis",
            r"installationBasisSnapshot.*?validateSuccessor\(of:\s*currentInstallationBasis\)",
            r"try\s+installationTaskHeads\.validate\(successors:\s*installationTaskResults\)",
            r"resolvedTaskHeads\.values\.map\(\\\.resultSHA256\)",
            r"Set\(installationAsBuiltSnapshot\.taskResultSHA256s\)",
        ),
        "C47 current-basis as-built resolution",
    )
    reference = _swift_decl_block(
        contracts, "struct CompletedActivitySnapshotV2CompatibilityReferenceV1"
    )
    _require_patterns(
        reference,
        (
            r"sourceWorkspaceID\s*:\s*WorkspaceID",
            r"targetCloseoutSHA256\s*:\s*String",
            r"sourceCloseoutSHA256\s*:\s*String",
            r"func\s+rebound\(",
            r"targetCloseoutSHA256\s*:\s*String",
            r"func\s+validate\(snapshot\s*:\s*CompletedActivitySnapshotV2\)",
        ),
        "C47 dual closeout provenance",
    )
    _require_patterns(
        resolved,
        (
            r"completedSnapshotReference\.sourceCloseoutSHA256",
            r"completedSnapshotReference\.targetCloseoutSHA256",
            r"expectedCloseoutSHA",
            r"sourceWorkspaceID\s*==\s*workspaceID",
        ),
        "C47 resolved source/target closeout proof",
    )
    _require_patterns(
        tests,
        (
            r"currentHeads",
            r"validateResolved\(",
            r"mappedInstallationCloseout",
            r"sourceCloseoutSHA256",
            r"targetCloseoutSHA256",
            r"reboundCompletedReference",
        ),
        "C47 basis and closeout test evidence",
    )
    writer = _text(root, C47_WRITER_SOURCE_PATH)
    _require_patterns(
        writer,
        (
            r"resolveActivityBasisHeads\(mutation\)",
            r"InstallationTaskResultLineageV1\s*\.\s*validateAndCurrentHeads",
            r"currentInstallationBasis\(\s*in:\s*installationValues\s*\)",
            r"func\s+currentInstallationBasis\(",
            r"value\.validateSuccessor\(of:\s*ordered\[index\s*-\s*1\]\)",
        ),
        "C47 persistent current-head resolution",
    )


def _assert_backup_history_and_deletion(root: Path, tests: str) -> None:
    backup = _text(root, C47_BACKUP_SOURCE_PATH)
    ordering = _source_slice(
        backup, "enum C47ActivityContractMutationOrderingV2", "extension V4BackupRecordsV1"
    )
    _require_patterns(
        ordering,
        (
            r"orderedIndices",
            r"indexByEnvelopeSHA256",
            r"mutation\.predecessorEnvelope",
            r"successorEnvelope\.amendment",
            r"indegree",
            r"dependents",
            r"comesBefore",
            r"ready",
            r"ordered\.count\s*==\s*mutations\.count",
            r"guard\s+let\s+dependencyIndex\s*=\s*indexByEnvelopeSHA256\[dependencySHA256\].*?throw\s+ActivityContractFailureV2\.missingReference",
        ),
        "C47 causal/topological mutation history",
    )
    _require_patterns(
        backup,
        (
            r"C47ActivityContractMutationOrderingV2\s*\n?\s*\.orderedIndices",
            r"let\s+retainedActivityKeys",
            r"case\s+\.finalized\s*,\s*\.superseded\s*,\s*\.cancelled\s*,\s*\.unableToComplete\s*:\s*return\s+key",
            r"deletedSubjectAssetIDs",
            r"deletedSubjectAssetIDs\.contains\(envelope\.subjectID\).*?!immutableActivityKeys\.contains\(key\)\s*\?\s*nil\s*:\s*key",
            r"try\s+deletionLedger\?\.validate\(\)",
        ),
        "C47 finalized-history and deletion-ledger closure",
    )
    restore = _text(root, C47_RESTORE_SOURCE_PATH)
    _require_patterns(
        restore,
        (
            r"sourceReplicaByHistoric",
            r"historicReplicaID",
            r"orderedActivityReceiptIndices",
            r"replacingMutationHistoryForCurrentWriter",
            r"MutationJournalStoreV1\.validateImportedSnapshot",
            r"CompletedActivitySnapshotCanonicalCodecV2\.decode",
            r"mappedInstallationCloseout",
            r"mappedPunchCloseout",
            r"successorEnvelope\.rebound\(",
        ),
        "C47 restore history replica and provenance",
    )
    replacement = _text(root, C47_REPLACEMENT_SOURCE_PATH)
    _require_patterns(
        replacement,
        (
            r"DeletionWinningRestorePlanV2",
            r"deletionLedger",
            r"recordsAfter",
            r"mutationHistory",
            r"try\s+ledger\.validate\(\)",
        ),
        "C47 deletion-ledger-qualified restore filtering",
    )
    for path, patterns, label in (
        (
            C47_DELETION_LEDGER_SOURCE_PATH,
            (
                r"finalizedAndSupersededActivityHistoryIsRetained\s*=\s*true",
                r"unfinalizedMatchingSubjectGraphMayBeDeleted\s*=\s*true",
                r"workspaceEraseOwnsAllCanonicalRowsAndReleasedSnapshotFiles\s*=\s*true",
            ),
            "C47 deletion ledger policy",
        ),
        (
            C47_DELETION_INTENT_SOURCE_PATH,
            (
                r"matchingUnfinalizedSubjectGraphIsClosed\s*=\s*true",
                r"finalizedAndSupersededHistoryIsRetained\s*=\s*true",
                r"nonpersistentReceiptsCreateNoCleanupIntent\s*=\s*true",
            ),
            "C47 deletion intent policy",
        ),
        (
            C47_WHOLE_SIGN_RULE_SOURCE_PATH,
            (
                r"unfinalizedMatchingSubjectGraphCanBeRemoved\s*=\s*true",
                r"finalizedAndSupersededHistoryCannotCascade\s*=\s*true",
                r"unrelatedActivitiesRemain\s*=\s*true",
            ),
            "C47 whole-sign deletion policy",
        ),
        (
            C47_DELETION_STORE_SOURCE_PATH,
            (
                r"finalizedHistoryIsPreserved\s*=\s*true",
                r"ordinaryDeletionRemovesOnlyUnfinalizedMatchingSubjectRows\s*=\s*true",
                r"journalHistoryRemainsAppendOnly\s*=\s*true",
            ),
            "C47 deletion ledger store policy",
        ),
    ):
        _require_patterns(_text(root, path), patterns, label)
    _require_patterns(
        tests,
        (
            r"sourceSequences.*?sourceSequences\.sorted\(\)",
            r"sourceCausalRevisions.*?sourceCausalRevisions\.sorted\(\)",
            r"restoredSequences.*?restoredSequences\.sorted\(\)",
            r"restoredCausalRevisions.*?restoredCausalRevisions\.sorted\(\)",
            r"BackupRestoreMode\.emptyInstall\s*,\s*\.clone\s*,\s*\.fork",
            r"Array\(1\.\.\.UInt64\(sourceMutations\.count\)\)",
            r"try\s+successor\.validateSuccessor\(of:\s*predecessor\)",
            r"completedSnapshotBytes",
            r"restoredSnapshotBytes",
            r"CompletedActivitySnapshotCanonicalCodecV2\.decode",
            r"retainedFinalized",
        ),
        "C47 backup/replay/delete evidence",
    )


def _assert_persistence_enrollment(root: Path, persistence: str) -> None:
    model_names = tuple(
        re.findall(r"@Model\s+final\s+class\s+([A-Za-z0-9_]+)", persistence)
    )
    if model_names != C47_PERSISTENT_ROW_CLASSES:
        raise ValueError(
            "C47 persistence must contain exactly five new rows:"
            + ",".join(model_names)
        )
    if any(
        forbidden in model_names
        for forbidden in ("CompletedActivitySnapshotV2Row", "CompletedActivitySnapshotRowV2")
    ):
        raise ValueError("C47 released CompletedActivitySnapshotV2 gained a parallel row")
    boundary = _swift_decl_block(
        persistence, "enum C47ActivityContractPersistenceBoundaryV2"
    )
    _require_patterns(
        boundary,
        (
            r"persistentSchemaVersion\s*=\s*36",
            r"recordsSchemaVersion\s*=\s*35",
            r"durableModelCount\s*=\s*6",
            r"reusedDurableFamily\s*=\s*\"CompletedActivitySnapshotV2\"",
            r"noPlanFallbackPersistent\s*=\s*false",
        ),
        "C47 six-family V36 persistence boundary",
    )
    rows = re.search(r"newlyEnrolledRows\s*=\s*\[(.*?)\]", boundary, re.S)
    if rows is None:
        raise ValueError("C47 newly enrolled row list absent")
    enrolled_rows = tuple(re.findall(r'"([^"\\]+)"', rows.group(1)))
    if enrolled_rows != C47_PERSISTENT_ROW_CLASSES:
        raise ValueError("C47 newly enrolled row list differs")
    schema = _text(root, C47_SCHEMA_SOURCE_PATH)
    schema36 = _source_slice(schema, "enum PersistentSchemaV36", "enum PersistentSchemaMigrationStageV1")
    _require_patterns(
        schema36,
        (
            r"PersistentSchemaV35\.models",
            r"ActivitySessionEnvelopeRow\.self",
            r"ActivityStateTransitionRow\.self",
            r"InstallationTaskResultRow\.self",
            r"InstallationAsBuiltSnapshotRow\.self",
            r"PunchReviewBasisSnapshotRow\.self",
        ),
        "C47 PersistentSchemaV36 enrollment",
    )
    _require_patterns(
        _text(root, C47_MIGRATION_SOURCE_PATH),
        (
            r"C47ActivityContractMigrationBoundaryV2",
            r"sourceVersion\s*=\s*35",
            r"targetVersion\s*=\s*36",
            r"recordsVersion\s*=\s*35",
            r"backfillCreatesActivityTruth\s*=\s*false",
        ),
        "C47 records35-to-V36 migration",
    )
    _require_patterns(
        _text(root, C47_IMPORT_SOURCE_PATH),
        (
            r"C47ActivityContractImportBoundaryV2",
            r"persistentSchemaVersion\s*=\s*36",
            r"recordsSchemaVersion\s*=\s*35",
            r"canonicalFiveRowRecordsImportable\s*=\s*true",
            r"conformanceReceiptsImportable\s*=\s*false",
        ),
        "C47 records35 import boundary",
    )


def _assert_effect_before_receipt(root: Path) -> None:
    writer = _text(root, C47_WRITER_PORT_SOURCE_PATH)
    port = _swift_decl_block(writer, "protocol WorkspaceWriterAdapterPortV1")
    _require_patterns(
        port,
        (
            r"func\s+persistedActivityContractEffectMatches\s*\(\s*_\s*mutation\s*:\s*ActivityContractMutationV2\s*\)\s*throws\s*->\s*Bool",
        ),
        "C47 writer adapter preflight port",
    )

    activity_writer = _swift_decl_block(
        writer,
        "extension WorkspaceWriterV1: ActivityContractCanonicalWorkspaceWritingV2",
    )
    commit = _swift_decl_block(activity_writer, "func commitActivityContract")
    _require_patterns(
        commit,
        (
            r"if\s+let\s+recovered\s*=\s*try\s+reconcileActivityContractEffectBeforeReceipt",
            r"_\s*=\s*try\s+execute\s*\(\s*request\s*\)",
        ),
        "C47 writer effect preflight call",
    )
    _require_order(
        commit,
        "reconcileActivityContractEffectBeforeReceipt",
        "execute(request)",
        "C47 effect preflight before command execution",
    )
    reconcile = _swift_decl_block(
        activity_writer,
        "private func reconcileActivityContractEffectBeforeReceipt",
    )
    _require_patterns(
        reconcile,
        (
            r"guard\s+try\s+adapter\.persistedActivityContractEffectMatches\s*\(\s*mutation\s*\)\s*else\s*\{\s*return\s+nil\s*\}",
            r"let\s+receipt\s*=\s*try\s+journalStore\.commit\s*\(",
        ),
        "C47 effect-before-receipt reconciliation",
    )
    _require_order(
        reconcile,
        "adapter.persistedActivityContractEffectMatches",
        "journalStore.commit",
        "C47 effect preflight before journal commit",
    )

    execute_internal = _swift_decl_block(writer, "private func executeInternal")
    c47_effect_case = _swift_decl_block(
        execute_internal, "if case let .applyActivityContract"
    )
    _require_patterns(
        c47_effect_case,
        (
            r"guard\s+journalStore\s*!=\s*nil\s*else\s*\{\s*throw\s+WorkspaceMutationFailureV1\.persistenceFailed\s*\}",
            r"try\s+adapter\.persistAppliedActivityContractEffect\s*\(\s*mutation\s*\)",
        ),
        "C47 effect persistence branch",
    )
    if len(
        re.findall(
            r"\badapter\.persistAppliedActivityContractEffect\s*\(",
            execute_internal,
        )
    ) != 1:
        raise ValueError(
            "C47 effect persistence must not be forced through non-C47 commands"
        )
    _require_order(
        execute_internal,
        "adapter.apply(",
        "if case let .applyActivityContract",
        "C47 adapter apply before effect persistence branch",
    )
    _require_order(
        execute_internal,
        "adapter.apply(",
        "adapter.persistAppliedActivityContractEffect",
        "C47 adapter apply before effect persistence",
    )
    _require_order(
        execute_internal,
        "adapter.persistAppliedActivityContractEffect",
        "journalStore.reach(.afterEffectBeforeReceipt)",
        "C47 effect persistence before receipt boundary",
    )

    adapter = _text(root, C47_WRITER_SOURCE_PATH)
    adapter_persist = _swift_decl_block(
        adapter, "func persistAppliedActivityContractEffect"
    )
    _require_patterns(
        adapter_persist,
        (
            r"guard\s+modelContext\.hasChanges\s*,\s*try\s+persistedActivityContractEffectMatches\s*\(\s*mutation\s*\)\s*else\s*\{\s*throw\s+WorkspaceMutationFailureV1\.receiptHistoryCorrupt\s*\}",
            r"try\s+modelContext\.save\s*\(\s*\)",
            r"modelContext\.rollback\s*\(\s*\)",
            r"throw\s+WorkspaceMutationFailureV1\.persistenceFailed",
        ),
        "C47 persisted effect exact preflight and save",
    )
    _require_order(
        adapter_persist,
        "modelContext.hasChanges",
        "persistedActivityContractEffectMatches",
        "C47 hasChanges before exact effect preflight",
    )
    _require_order(
        adapter_persist,
        "persistedActivityContractEffectMatches",
        "modelContext.save()",
        "C47 exact effect preflight before save",
    )
    if len(re.findall(r"modelContext\.save\s*\(\s*\)", adapter_persist)) != 1:
        raise ValueError("C47 effect persistence must save exactly once")
    _require_order(
        adapter_persist,
        "modelContext.save()",
        "modelContext.rollback()",
        "C47 effect save failure rollback",
    )
    _require_patterns(
        adapter_persist,
        (
            r"catch\s*\{\s*modelContext\.rollback\s*\(\s*\)\s*throw\s+WorkspaceMutationFailureV1\.persistenceFailed\s*\}",
        ),
        "C47 effect save failure mapping",
    )

    effect = _swift_decl_block(adapter, "func persistedActivityContractEffectMatches")
    rows = (
        ("envelopeRows", "ActivitySessionEnvelopeRow"),
        ("transitionRows", "ActivityStateTransitionRow"),
        ("resultRows", "InstallationTaskResultRow"),
        ("snapshotRows", "InstallationAsBuiltSnapshotRow"),
        ("basisRows", "PunchReviewBasisSnapshotRow"),
    )
    for variable, row in rows:
        fetch_pattern = rf"FetchDescriptor\s*<\s*{row}\s*>\s*\(\s*predicate\s*:\s*#Predicate\s*\{{\s*\$0\.mutationID\s*==\s*mutationID\s*\}}\s*\)"
        if len(re.findall(fetch_pattern, effect, re.S)) != 1:
            raise ValueError(
                "C47 effect preflight must query exactly one mutationID-scoped row set:"
                + row
            )
        _require_patterns(
            effect,
            (rf"\b{variable}\b",),
            "C47 effect preflight row binding:" + row,
        )

    row_count = re.search(
        r"\blet\s+rowCount\s*=\s*(.*?)\bguard\b", effect, re.S
    )
    if row_count is None or any(
        f"{variable}.count" not in row_count.group(1) for variable, _ in rows
    ):
        raise ValueError("C47 effect preflight total row count omits a C47 row kind")
    if len(re.findall(r"\breturn\s+false\b", effect)) != 1:
        raise ValueError("C47 effect preflight may return false only for total zero")
    _require_patterns(
        effect,
        (
            r"guard\s+rowCount\s*>\s*0\s*else\s*\{\s*return\s+false\s*\}",
            r"envelopeRows\.count\s*==\s*1",
            r"transitionRows\.count\s*==\s*\(?\s*mutation\.transition\s*==\s*nil\s*\?\s*0\s*:\s*1\s*\)?",
            r"resultRows\.count\s*==\s*mutation\.installationTaskResults\.count",
            r"snapshotRows\.count\s*==\s*\(?\s*mutation\.installationAsBuiltSnapshot\s*==\s*nil\s*\?\s*0\s*:\s*1\s*\)?",
            r"basisRows\.count\s*==\s*\(?\s*mutation\.punchReviewBasisSnapshot\s*==\s*nil\s*\?\s*0\s*:\s*1\s*\)?",
        ),
        "C47 effect preflight exact per-kind row counts",
    )
    for variable, _ in rows:
        _require_patterns(
            effect,
            (
                rf"{variable}\.allSatisfy\s*\(\s*\{{\s*\$0\.workspaceID\s*==\s*workspace\s*\}}\s*\)",
            ),
            "C47 effect preflight workspace scope:" + variable,
        )
    _require_patterns(
        effect,
        (
            r"try\s+envelopeRow\.value\(\)\s*==\s*mutation\.successorEnvelope",
            r"let\s+transition\s*=\s*try\s+transitionRows\.first\.map\s*\{\s*try\s+\$0\.value\(\)\s*\}",
            r"let\s+results\s*=\s*try\s+resultRows\.map\s*\{\s*try\s+\$0\.value\(\)\s*\}",
            r"let\s+snapshot\s*=\s*try\s+snapshotRows\.first\.map\s*\{\s*try\s+\$0\.value\(\)\s*\}",
            r"let\s+basis\s*=\s*try\s+basisRows\.first\.map\s*\{\s*try\s+\$0\.value\(\)\s*\}",
            r"transition\s*==\s*mutation\.transition",
            r"results\s*==\s*mutation\.installationTaskResults",
            r"snapshot\s*==\s*mutation\.installationAsBuiltSnapshot",
            r"basis\s*==\s*mutation\.punchReviewBasisSnapshot",
            r"persisted\.mutationSHA256\s*==\s*mutation\.mutationSHA256",
            r"persisted\.mutationPostImages\s*==\s*mutation\.mutationPostImages",
        ),
        "C47 effect preflight decoded-value and post-image equality",
    )
    if len(
        re.findall(
            r"throw\s+WorkspaceMutationFailureV1\.receiptHistoryCorrupt", effect
        )
    ) < 2:
        raise ValueError(
            "C47 effect preflight must throw on partial or mismatched persisted rows"
        )


def _persistence(root: Path) -> dict[str, Any]:
    c = _closed_corpus(root)
    values = c.get("durableFamilies")
    if values != list(DURABLE_FAMILIES): raise ValueError("C47 six durable families differ")
    if (c.get("persistentSchemaVersion"), c.get("recordsSchemaVersion")) != (36, 35): raise ValueError("C47 persistence must be V36/records35")
    return {"persistentSchemaVersion": 36, "recordsSchemaVersion": 35, "durableFamilies": values, "newDurableRowClasses": list(NEW_DURABLE_ROW_CLASSES), "releasedDurableCompatibilityReferences": RELEASED_DURABLE_COMPATIBILITY_REFERENCES}


def assert_source_regressions(root: Path) -> None:
    for path in IMPLEMENTATION_PATHS:
        if not (root / path).is_file(): raise ValueError("C47 implementation path absent:" + path)
    contracts = _tokens(root, IMPLEMENTATION_PATHS[0], *CONTRACT_NAMES)
    persistence = _tokens(root, IMPLEMENTATION_PATHS[1], "Row")
    coordinator = _tokens(root, IMPLEMENTATION_PATHS[2], "expectedRevision", "MutationID", "receipt")
    lifecycle = _tokens(root, IMPLEMENTATION_PATHS[3], "backup", "restore", "delete", "Erase", "search", "replay")
    combined = "\n".join((contracts, persistence, coordinator, lifecycle))
    for token in ("installation", "punch", "readiness", "variation", "closeout", "NoPlanFallback"):
        if token.lower() not in combined.lower(): raise ValueError("C47 family semantics regressed:" + token)
    for name in CONTRACT_NAMES[:3]:
        if combined.count(name) < 1: raise ValueError("C47 receipt family absent:" + name)
    for name in (*CONFORMANCE_RECEIPTS, "NoPlanFallbackV1"):
        if re.search(r"(?:@Model|final\s+class|struct\s+\w*Row)[^\n]*" + re.escape(name), persistence):
            raise ValueError("C47 nonpersistent conformance receipt/fallback gained durable row:" + name)
    for name in NEW_DURABLE_ROW_CLASSES:
        if name not in persistence: raise ValueError("C47 new durable row class absent:" + name)
    if "CompletedActivitySnapshotV2CompatibilityReferenceV1" not in contracts or "completedSnapshotReference" not in contracts:
        raise ValueError("C47 released completed-snapshot compatibility reference regressed")
    if re.search(r"(?:@Model|final\s+class|struct)\s+(?:CompletedActivitySnapshotV2Row|CompletedActivitySnapshotRowV2)\b", persistence):
        raise ValueError("C47 parallel CompletedActivitySnapshotV2 row is forbidden")
    for forbidden in ("receipt alias", "shared receipt family", "installation is punch", "punch is installation"):
        if forbidden.lower() in combined.lower(): raise ValueError("C47 three-receipt isolation regressed:" + forbidden)
    tests = _tokens(root, IMPLEMENTATION_PATHS[4], *TEST_METHODS)
    for token in ("installation", "punch", "fallback", "stale", "interrupt", "backup", "restore", "delete", "Erase"):
        if token.lower() not in tests.lower(): raise ValueError("C47 test coverage regressed:" + token)
    _assert_typed_conformance_authority(contracts, coordinator)
    _assert_no_plan_fallback(contracts, persistence, lifecycle)
    _assert_mutation_image_identities(root, tests)
    _assert_retired_release_and_unknown_kind(root, contracts, tests)
    _assert_task_coverage_and_as_built_freshness(root, contracts, tests)
    _assert_decoded_nested_basis_sources(root, contracts, persistence, tests)
    _assert_basis_closeout_resolution(root, contracts, coordinator, tests)
    _assert_backup_history_and_deletion(root, tests)
    _assert_effect_before_receipt(root)
    _assert_persistence_enrollment(root, persistence)
    corpus = _closed_corpus(root)
    if corpus.get("schema") != "V22P03C47ActivityContractCorpusV2" or corpus.get("schemaVersion") != 2 or corpus.get("cardID") != CARD or corpus.get("classification") != "IMPLEMENT_NOW" or corpus.get("contractNames") != list(CONTRACT_NAMES) or corpus.get("activityKinds") != list(ACTIVITY_KINDS) or corpus.get("hostileCases") != list(HOSTILE_CASES) or corpus.get("interruptionBoundaries") != list(INTERRUPTION_BOUNDARIES): raise ValueError("C47 corpus authority differs")
    _persistence(root)
    _compatibility_tests(root)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (120, 14, 134) or len(set(PATH_FENCE)) != 134: raise ValueError("C47 fence must be unique 134=120+14")
    if tuple(PATH_FENCE[126:]) != (*SCRIPT_PATHS, *GENERATED_PATHS): raise ValueError("C47 tooling rows 127-134 differ")
    if any("phase10" in p.lower() or "/s10" in p.lower() for p in PATH_FENCE): raise ValueError("C47 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE: raise ValueError("C47 base tree differs")
    for p in EXISTING_PATHS:
        if not _base_exists(root, p): raise ValueError("C47 existing path absent at base:" + p)
    for p in NEW_PATHS:
        if _base_exists(root, p): raise ValueError("C47 new path existed at base:" + p)
    if AUTHORIZED_OVERLAP_COUNT != 2521 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()): raise ValueError("C47 authority/status proof differs")


def authority() -> dict[str, Any]:
    return {"cardID": CARD, "attemptID": 1, "registerOrdinal": 77, "title": TITLE, "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED", "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE, "coordinationCASSequence": 326, "hydrationRevision": 1, "prerequisiteDigest": PREREQUISITE_DIGEST, "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "allowedPathCount": 134, "existingPathCount": 120, "newPathCount": 14, "authorizedOverlapCount": 2521, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0, "directPrerequisiteCards": ["V23-P03-C25"], "nextCard": "V23-P03-C48", "nextRegisterOrdinal": 78}


def schema_document(root: Path | None = None) -> dict[str, Any]:
    text={"type":"string","minLength":1}; strings=lambda n=1:{"type":"array","minItems":n,"uniqueItems":True,"items":text}; case=_closed_object({"caseID":text,"input":text,"expectedDisposition":text},["caseID","input","expectedDisposition"])
    lifecycle=["migration","backupRestoreCloneFork","journalReplay","searchRebuild","reportExport","deleteEraseRetention","interruptionRecovery","compatibilityForwardFix"]
    invariants=["threeReceiptFamiliesAreIndependent","sharedEnvelopeCannotWriteFamilyTruth","installationCannotWritePunchTruth","punchCannotWriteInstallationTruth","noPlanFallbackIsExplicit","readinessIsTyped","variationIsAppendOnly","closeoutNeverClaimsApprovalCertificationOrAuthorization","oneCanonicalWriterPerReceipt","noSecondRendererStoreOrStatusDatabase"]
    props={"schema":{"const":"V22P03C47ActivityContractCorpusV2"},"schemaVersion":{"const":2},"cardID":{"const":CARD},"classification":{"const":"IMPLEMENT_NOW"},"persistentSchemaVersion":{"type":"integer","minimum":1},"recordsSchemaVersion":{"type":"integer","minimum":1},"durableFamilies":{"const":list(DURABLE_FAMILIES)},"contractNames":{"const":list(CONTRACT_NAMES)},"activityKinds":{"const":list(ACTIVITY_KINDS)}}
    for k in ("sharedEnvelopeCases","installationCases","punchCases","readinessCases","variationCases"):props[k]={"type":"array","minItems":3,"items":case}
    props.update({"hostileCases":{"const":list(HOSTILE_CASES)},"interruptionBoundaries":{"const":list(INTERRUPTION_BOUNDARIES)},"lifecycle":_closed_object({k:text for k in lifecycle},lifecycle),"invariants":_closed_object({k:{"const":True} for k in invariants},invariants),"evidenceIDs":{"const":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")]},"statusFlags":_closed_object({k:{"const":False} for k in ("native","hosted","physical","adoption","acceptance","release")},["native","hosted","physical","adoption","acceptance","release"] )})
    return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/activity-contract-families.schema.json","title":"V23 P03 C47 Activity Contract Corpus V2","type":"object","additionalProperties":False,"properties":props,"required":list(props)}


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    semantics={"contractNames":list(CONTRACT_NAMES),"fiveSelectors":list(observed_selectors(root)),"sixSemanticDurableFamilies":list(DURABLE_FAMILIES),"fiveNewDurableRowClasses":list(NEW_DURABLE_ROW_CLASSES),"completedActivitySnapshotUsesReleasedCompatibilityReference":RELEASED_DURABLE_COMPATIBILITY_REFERENCES["CompletedActivitySnapshotV2"],"sharedEnvelopeInstallationAndPunchUseThreeIndependentConformanceReceipts":True,"threeConformanceReceiptsAndNoPlanFallbackAreNonpersistent":True,"noPlanFallbackIsExplicitAndNoninventing":True,"readinessVariationDeferredUnableAndCloseoutTruthRemainTyped":True,"threeReceiptWriterRecoveryCannotCrossFamilyMutation":True,"lifecycleCoversMigrationBackupRestoreCloneForkDeleteEraseSearchReplayReportRetentionAndForwardFix":True,"noSecondWriterRendererStoreStatusDatabaseOrApprovalClaim":True}
    return _sealed({"schema":"V23P03C47ActivityContractFamiliesV2","schemaVersion":2,"authority":authority(),"persistence":_persistence(root),"requiredSemantics":semantics})


def evidence_document(root: Path) -> dict[str, Any]:
    c=contract_document(root);return _sealed({"schema":"V23P03C47ActivityContractEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"classification":"IMPLEMENT_NOW","evidenceIDs":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")],"testSelectors":list(observed_selectors(root)),"persistence":_persistence(root),"requiredSemanticsDigest":sha256_value(c["requiredSemantics"]),"nativeEvidenceState":"PENDING_NOT_ACCEPTING","physicalEvidenceState":"REQUIRED_PENDING_OWNER","adoptionState":"PENDING_NOT_ACCEPTING","acceptanceState":"PENDING_NOT_ACCEPTING","releaseState":"PENDING_NOT_ACCEPTING","statusFlags":FLAGS})


def brand_document() -> dict[str, Any]:
    return _sealed({"schema":"V23P03C47BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"uiSurfaceDelta":True,"brandSurfaceDelta":True,"publicClaimDelta":False,"nativeIPadSurface":False,"dynamicTypeThroughAX5":True,"voiceOverVoiceControlAndErrorFocusRequired":True,"installationAndPunchWordingRemainIndependent":True,"approvalCertificationAuthorizationClaims":False,"physicalLockedState":"REQUIRED_PENDING_OWNER","statusFlags":FLAGS})


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root);rendered={SCHEMA_PATH:pretty(schema_document(root)),CONTRACT_PATH:pretty(contract_document(root)),EVIDENCE_PATH:pretty(evidence_document(root)),BRAND_PATH:pretty(brand_document())};rows=[_row(root,p,rendered) for p in MANIFEST_INPUT_PATHS];rendered[MANIFEST_PATH]=pretty(_sealed({"schema":"V23P03C47ToolingManifestV1","schemaVersion":1,"authority":authority(),"pathFence":list(PATH_FENCE),"pathFenceCount":134,"existingPathCount":120,"newPathCount":14,"authorizedOverlapCount":2521,"unauthorizedOverlapCount":0,"s10ReservationOverlapCount":0,"artifacts":rows,"artifactSetDigest":sha256_value(rows),"physicalLockedState":"REQUIRED_PENDING_OWNER","statusFlags":FLAGS}));return rendered
