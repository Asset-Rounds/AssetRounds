#!/usr/bin/env python3
"""Deterministic operational-contact tooling model for V23-P03-C46."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

_BASE = Path(__file__).with_name("p03_c45_contracts.py")
_BASE_SHA256 = "d2b8aa7a4f59db30dbfbd01d5cc796fdc8cc943cbccf286e470ba6cfa3702dc2"
if hashlib.sha256(_BASE.read_bytes()).hexdigest() != _BASE_SHA256:
    raise ValueError("sealed C45 tooling model differs")
exec(compile(_BASE.read_text(encoding="utf-8"), str(_BASE), "exec"), globals())

CARD = "V23-P03-C46"
TITLE = "Operational contact points, system-handoff intents, and privacy-separated contact import semantics"
REGISTER_ORDINAL = 76
BASE_HEAD = "32533a14d2e72ee8ebc46b25473c80fc3f721424"
BASE_TREE = "92fc18e03142c1eaae60a1f71deeb4fea2b71606"
COORDINATION_HEAD = "55ba73a9cf6dd6ad7186079fa6273bc353f4f94a"
COORDINATION_TREE = "37490d7473b271fcd50f9125f2a6ec17cf77b5ab"
COORDINATION_CAS_SEQUENCE = 322
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "25a1ad5ad00aa8bd98674ba7b5ec94e3d7cb6c0b1ecc8786330783860c049988"
CONTEXT_DIGEST = "c6ba76edfe0a71b6d77ea9c1855c625318b0d039e7d8e8707a3360b0c2a85ebf"
FENCE_DIGEST = "466e730797b35fa438c4ab60cbf9c347372680bf504d0257db4b7e952577235b"
HYDRATION_TRANSITION_DIGEST = "1967a15150bbc04b77a8c5bd8237250c4e5b91b70f43d46bb3b58a8bdd0f69e3"
COORDINATION_LEDGER_DIGEST = "4d3437d14a1e8bb96337b879b4f257510e83845ec72b2429f1dc7d4629b695f3"
COORDINATION_PROJECTION_DIGEST = "587e1c606e2ae475d7be14ff2ed1a357b080255c917bf8b4927cac1b0ff51852"
AUTHORIZED_OVERLAP_COUNT = 3389
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/operational-contact.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C46OperationalContactContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C46OperationalContactEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C46BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C46-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c46_contracts.py",
    "Scripts/v23/generate_p03_c46_contracts.py",
    "Scripts/v23/verify_p03_c46_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Contacts/OperationalContactContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/OperationalContactPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Contacts/OperationalContactCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Platform/SystemHandoffAdapterV1.swift",
    "FieldEvidenceAppTests/V9_53OperationalContactTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Contacts/V22P03C46OperationalContactCorpusV1.json",
)
EXISTING_PATHS = tuple(EXISTING_PATHS) + tuple(IMPLEMENTATION_PATHS[:0])
# C46 carries the complete C45 fence, including C45's six implementation rows.
_C45_IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetLabelPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Labels/AssetLabelCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_52AssetLabelTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Labels/V22P03C45AssetLabelCorpusV1.json",
)
EXISTING_PATHS = tuple(EXISTING_PATHS) + _C45_IMPLEMENTATION_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "ServicePartyReferenceV1", "ServiceContactPointV1", "SystemHandoffIntentV1",
    "PartyContactCSVRowV1", "PARTY_CONTACTS_V1",
)
TEST_METHODS = (
    "testV23P03C46G01CanonicalOperationalContactAndExplicitHandoffUseOneWorkspaceMutation",
    "testV23P03C46A01CSVImportPreviewPurposeSeparationAndCancelRemainBounded",
    "testV23P03C46H01StaleMalformedDuplicateAndMarketingIdentityInputsFailClosed",
    "testV23P03C46I01InterruptedContactWriteAndHandoffRecoverIdempotently",
    "testV23P03C46R01BackupRestoreCloneForkDeleteEraseExportSearchAndReplayRemainExact",
)
HOSTILE_CASES = (
    "MALFORMED_ADDRESS", "UNSUPPORTED_CHANNEL", "STALE_EXPECTED_REVISION",
    "DUPLICATE_CONTACT_POINT", "MIXED_PURPOSE_IMPORT", "SITE_ROLE_OWNERSHIP_ATTEMPT",
    "SUBSCRIBER_OR_CONSENT_PROMOTION_ATTEMPT", "CAMPAIGN_AUDIENCE_ATTEMPT",
    "MEASUREMENT_IDENTITY_ATTEMPT", "AUTOMATIC_HANDOFF_ATTEMPT", "PROTECTED_DATA",
    "LOW_STORAGE", "CANCELLATION",
)
INTERRUPTION_BOUNDARIES = (
    "BEFORE_CANONICAL_CONTACT_WRITE", "AFTER_EFFECT_BEFORE_RECEIPT",
    "DURING_IMPORT_PREVIEW", "BEFORE_EXPLICIT_SYSTEM_HANDOFF",
)
FLAGS = {key: False for key in (
    "native", "hosted", "physical", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "adoptionEvidence",
    "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution",
)}
COMPATIBILITY_KEY = "c46OperationalContactCompatibility"
COMPATIBILITY = {
    "compatibilityCardID": CARD,
    "operationalContactsArePurposeSeparated": True,
    "siteRoleOwnershipForbidden": True,
    "subscriberConsentCampaignAndMeasurementProjectionForbidden": True,
    "systemHandoffsAreExplicitEphemeralAndNoncanonical": True,
    "contactExportIsExcludedByDefault": True,
    "importedSourceBytesRemainLeasedScratch": True,
}
COMPATIBILITY_CORPORA = tuple(
    path for path in EXISTING_PATHS
    if path.startswith("FieldEvidenceAppTests/Fixtures/") and path.endswith(".json")
)
REQUIRED_MECHANICAL_PATHS = (
    "FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift",
    "FieldEvidenceApp/Application/AssetSemantics/AssetSemanticsCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Assistance/AssistanceCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Content/TemporalEvidenceCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift",
    "FieldEvidenceApp/Application/EvidenceContext/EvidenceContextCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Labels/AssetLabelCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Lighting/LightingCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Packs/FieldReferencePackCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Plans/PlanRebaseCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift",
    "FieldEvidenceApp/Application/Pose/PlacementPoseCoordinatorV1.swift",
    "FieldEvidenceApp/Application/WorkPacket/WorkPacketManifestCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Workflow/SurveySessionCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift",
    "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift",
    "FieldEvidenceApp/Domain/Assistance/AssistanceContractsV1.swift",
    "FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/TemporalEvidenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
    "FieldEvidenceApp/Domain/EvidenceContext/EvidenceContextContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift",
    "FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift",
    "FieldEvidenceApp/Domain/Lighting/LightingContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/Asset.swift",
    "FieldEvidenceApp/Domain/Models/AssetLabelPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetLocatorPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetSemanticPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssistancePersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/EvidenceContextPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/FieldReferencePackPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/LightingPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/ObservationAndTimeModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/PlacementPosePersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/PlanPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/SurveyDefinitionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/SurveySessionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/TemporalEvidencePersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkPacketManifestPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkflowModels.swift",
    "FieldEvidenceApp/Domain/Packs/FieldReferencePackContractsV1.swift",
    "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift",
    "FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift",
    "FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/TimeContextRule.swift",
    "FieldEvidenceApp/Domain/Workflow/WorkRule.swift",
    "FieldEvidenceApp/Domain/Workflow/WorkflowContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetLocatorLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetSemanticLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Assistance/AssistanceLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftAutosaveSchedulerV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftCommitSagaRecoveryV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/EvidenceContext/EvidenceContextLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift",
    "FieldEvidenceApp/Infrastructure/Lighting/LightingLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift",
    "FieldEvidenceApp/Infrastructure/Media/TemporalEvidenceLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/OfflineReadiness/FieldReferencePackLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Plans/PlanLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Pose/PlacementPoseLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/System/DeviceTimeSemanticsV1.swift",
    "FieldEvidenceApp/Infrastructure/WorkPacket/WorkPacketManifestLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Workflow/SurveySessionLifecycleAdapterV1.swift",
)


def mechanical_marker(path: str) -> str:
    return "C46OperationalContactConformance_" + re.sub(r"[^A-Za-z0-9]", "_", path)


def mechanical_classification(path: str) -> str:
    if "/Domain/" in path:
        return "DOMAIN_MODEL_AND_CONTRACT_PRIVACY_SEPARATION"
    if "/Application/" in path or "/Features/" in path:
        return "APPLICATION_COORDINATION_NO_SECOND_WRITER_OR_AUTOMATIC_HANDOFF"
    return "INFRASTRUCTURE_LIFECYCLE_NO_CONTACT_PROJECTION_OR_NETWORK_DELIVERY"


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C46(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def _closed_corpus(root: Path) -> dict[str, Any]:
    corpus = json.loads(_text(root, IMPLEMENTATION_PATHS[5]))
    keys = {
        "schema", "schemaVersion", "cardID", "classification", "persistentSchemaVersion",
        "recordsSchemaVersion", "durableFamilies", "contractNames", "contactPointCases",
        "handoffCases", "csvImportCases", "hostileCases", "interruptionBoundaries",
        "lifecycle", "invariants", "evidenceIDs", "statusFlags",
    }
    if set(corpus) != keys:
        raise ValueError("C46 closed corpus top-level differs")
    return corpus


def _persistence(root: Path) -> dict[str, Any]:
    corpus = _closed_corpus(root)
    versions = (corpus.get("persistentSchemaVersion"), corpus.get("recordsSchemaVersion"))
    families = corpus.get("durableFamilies")
    if versions != (35, 34):
        raise ValueError("C46 persistence versions differ")
    if families != ["ServiceContactPointRow", "SystemHandoffIntentRow"]:
        raise ValueError("C46 durable families differ")
    schemas = _tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift", "PersistentSchemaV35", "models.count==115", "ServiceContactPointRow.self", "SystemHandoffIntentRow.self")
    if "PersistentSchemaV34.models+[ServiceContactPointRow.self,SystemHandoffIntentRow.self]" not in schemas.replace(" ", ""):
        raise ValueError("C46 V35 model append differs")
    return {"persistentSchemaVersion": 35, "recordsSchemaVersion": 34, "durableFamilies": families, "persistentModelCount": 115}


def _compatibility_corpora(root: Path) -> None:
    if len(COMPATIBILITY_CORPORA) != 8:
        raise ValueError("C46 compatibility corpus inventory differs")
    for path in COMPATIBILITY_CORPORA:
        value = json.loads(_text(root, path))
        if value.get(COMPATIBILITY_KEY) != COMPATIBILITY:
            raise ValueError("C46 compatibility closure differs:" + path)


def _mechanical_enrollment_sources(root: Path) -> None:
    if len(REQUIRED_MECHANICAL_PATHS) != 88 or tuple(sorted(REQUIRED_MECHANICAL_PATHS)) != REQUIRED_MECHANICAL_PATHS:
        raise ValueError("C46 mechanical enrollment inventory differs")
    common = (
        "operationalContactsRemainPurposeSeparated",
        "systemHandoffsRemainExplicitEphemeralAndNoncanonical",
        "subscriberConsentCampaignAndMeasurementProjectionForbidden",
        "contactExportExcludedByDefault",
    )
    class_token = {
        "DOMAIN_MODEL_AND_CONTRACT_PRIVACY_SEPARATION": "siteRoleOwnershipForbidden",
        "APPLICATION_COORDINATION_NO_SECOND_WRITER_OR_AUTOMATIC_HANDOFF": "noSecondWriterOrAutomaticHandoff",
        "INFRASTRUCTURE_LIFECYCLE_NO_CONTACT_PROJECTION_OR_NETWORK_DELIVERY": "noContactProjectionOrNetworkDelivery",
    }
    for path in REQUIRED_MECHANICAL_PATHS:
        text = _text(root, path)
        required = (mechanical_marker(path), *common, class_token[mechanical_classification(path)])
        if any(token not in text for token in required):
            raise ValueError("C46 mechanical enrollment regressed:" + path)


def _audit_driven_source_closure(root: Path) -> None:
    contracts = _text(root, IMPLEMENTATION_PATHS[0])
    for token in (
        "maximumDisplayValueBytes = 1_024", "maximumSourceFiles = 16",
        "maximumImportFileBytes:Int64 = 4 * 1_024 * 1_024",
        "maximumImportSourceSetBytes:Int64 = 16 * 1_024 * 1_024",
        "maximumMutationContacts = 64", "Set(predecessors.map(\\.contactPointID)).count==predecessors.count",
        "Set(successors.map(\\.contactPointID)).count==successors.count",
        "Set(handoffIntents.map(\\.intentID)).count==handoffIntents.count",
        "concurrency.allSatisfy", "expectedRevision(for:identity)",
    ):
        if token not in contracts:
            raise ValueError("C46 core bound/duplicate/concurrency guard regressed:" + token)

    coordinator = _text(root, IMPLEMENTATION_PATHS[2])
    preview_start = coordinator.index("func previewPartyContacts(")
    accept_start = coordinator.index("func acceptPartyContactsImport(")
    handoff_start = coordinator.index("func handOff(", accept_start)
    preview = coordinator[preview_start:accept_start]
    acceptance = coordinator[accept_start:handoff_start]
    for token in (
        "fileBytesByName.count == sourceSet.files.count", "Int64(data.count) == file.byteCount",
        "KernelCanonicalHashV1.sha256(data) == file.sha256",
        "rows.count <= OperationalContactLimitsV1.maximumMutationContacts",
        "return .cancelledNoMutation",
    ):
        if token not in preview:
            raise ValueError("C46 bounded preview/cancel regressed:" + token)
    if acceptance.count("writer.commitOperationalContact(") != 1:
        raise ValueError("C46 import acceptance must invoke one canonical writer exactly once")
    for token in (
        "preview.validate()", "currentImportState(", "expectedRevision: expectedRevision",
        "mutationID: mutationID", "writerReceiptMismatch",
    ):
        if token not in acceptance:
            raise ValueError("C46 atomic import acceptance regressed:" + token)

    adapter = _text(root, IMPLEMENTATION_PATHS[3])
    for token in (
        "percentEncodedMailtoRecipient", "for byte in value.utf8", "output.append(0x25)",
        "return String(decoding: output, as: UTF8.self)", 'url.scheme == "mailto"',
    ):
        if token not in adapter:
            raise ValueError("C46 Unicode mailto closure regressed:" + token)

    restore = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift")
    restore_compact = re.sub(r"\s+", "", restore)
    for token in (
        "identityDecision.mode == .replaceExisting",
        "identityDecision.source.workspaceID\n            == identityDecision.targetPointer.workspaceID",
        "normalized.operationalContacts == records.operationalContacts",
        "normalized.validateC46OperationalContacts()",
    ):
        if token not in restore:
            raise ValueError("C46 same-workspace replace restore regressed:" + token)
    for token in (
        "func rebindingCrossWorkspaceReplacementOperationalContacts(",
        "destinationOperationalContactMutationID(for:",
        "var sourceReceipts: [OperationalContactRestoreSourceReceiptV1]", "sourceReceipts.sort",
        "retainedTargetReceipts", "let retainedTargetBytes = retainedTargetReceipts",
        "var transformedReceipts: [MutationHistoryReceiptRecordV1]", "sourceKind: .importedHistory",
        "transformedReceipts.count == sourceReceipts.count",
        "targetCurrentContacts.count == sourceCurrentContacts.count",
        "targetCurrentIntents.count == sourceCurrentIntents.count",
        "receipts: retainedReceipts + transformedReceipts",
        "MutationJournalStoreV1.validateImportedSnapshot(history)",
        "finalTargetReceiptCount", "retainedTargetReceipts.count + sourceReceipts.count",
        "finalRetainedTargetBytes == retainedTargetBytes",
        "history.receipts.count == sourceHistory.receipts.count",
        "validateC46OperationalContacts()",
    ):
        if token not in restore:
            raise ValueError("C46 cross-workspace replacement journal rebuild regressed:" + token)
    for token in (
        "letsourceWorkspaceUUID=identity.source.workspaceID",
        "sourceWorkspaceUUID!=identity.targetPointer.workspaceID",
        "letsourceWorkspaceID=WorkspaceID(rawValue:sourceWorkspaceUUID)",
    ):
        if token not in restore_compact:
            raise ValueError("C46 cross-workspace source UUID binding regressed:" + token)

    writer_adapter = _text(root, "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift")
    apply_start = writer_adapter.index("private func applyOperationalContact(")
    apply_end = writer_adapter.index("private func", apply_start + 20)
    apply_contact = writer_adapter[apply_start:apply_end]
    for token in ("mutation.validate()", "sequenceCollision", "staleEntityRevision", "modelContext.rollback()"):
        if token not in apply_contact:
            raise ValueError("C46 writer duplicate/concurrency guard regressed:" + token)
    writer = _text(root, "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift")
    commit_start = writer.index("func commitOperationalContact(")
    commit_contact = writer[commit_start:]
    for token in ("operationalContactReceipt(mutationID: mutation.mutationID)", "existing.mutationSHA256", "currentRevision()"):
        if token not in commit_contact:
            raise ValueError("C46 mutation-id recovery guard regressed:" + token)
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    for token in (
        '"replace-distinct-target"',
        "XCTAssertNotEqual(distinctTargetWorkspaceID, source.workspaceID)",
        "retainedTargetRow.envelopeData, targetOriginalEnvelopeBytes",
        "retainedTargetRow.receiptData, targetOriginalReceiptBytes",
        "importedDecodedRows.count, sourceOperationalMutations.count",
        "importedCreate.handoffIntents.count, 1",
        "importedRevisionTwo.revision, 2",
        "importedRevisionTwo.supersedes", "importedRevisionOne.revisionReference",
        "Set(importedMutations.map(\\.mutationID)).count",
        "try distinctJournal.validateAll()",
        "retainedDurableReceipt, targetOriginalReceipt",
        "importedDurableReceipts.count, sourceOperationalMutations.count",
        "durableOperationalContactReceipt(",
    ):
        if token not in tests:
            raise ValueError("C46 distinct-workspace replacement regression absent:" + token)


def assert_source_regressions(root: Path) -> None:
    for path in IMPLEMENTATION_PATHS:
        if not (root / path).is_file():
            raise ValueError(f"C46 implementation path absent:{path}")
    contracts = _tokens(root, IMPLEMENTATION_PATHS[0], *CONTRACT_NAMES)
    persistence = _tokens(root, IMPLEMENTATION_PATHS[1], "ServiceContactPoint")
    coordinator = _tokens(root, IMPLEMENTATION_PATHS[2], "expectedRevision", "MutationID", "receipt")
    handoff = _tokens(root, IMPLEMENTATION_PATHS[3], "SystemHandoffIntent", "explicit")
    combined = "\n".join((contracts, persistence, coordinator, handoff))
    for token in ("purpose", "backup", "restore", "clone", "fork", "delete", "Erase", "export", "search", "replay"):
        if token.lower() not in combined.lower():
            raise ValueError("C46 source lifecycle regressed:" + token)
    forbidden = (r"URLSession", r"NWConnection", r"subscriber repository", r"campaign audience", r"measurement identity")
    if any(re.search(pattern, combined, re.I) for pattern in forbidden):
        raise ValueError("C46 gained forbidden hosted/marketing identity surface")
    tests = _tokens(root, IMPLEMENTATION_PATHS[4], *TEST_METHODS)
    for token in ("CSV", "purpose", "stale", "duplicate", "interrupt", "backup", "restore", "delete", "Erase", "replay"):
        if token.lower() not in tests.lower():
            raise ValueError("C46 test coverage regressed:" + token)
    corpus = _closed_corpus(root)
    if (corpus.get("schema") != "V22P03C46OperationalContactCorpusV1" or corpus.get("schemaVersion") != 1
            or corpus.get("cardID") != CARD or corpus.get("classification") != "IMPLEMENT_NOW"
            or corpus.get("contractNames") != list(CONTRACT_NAMES)
            or corpus.get("hostileCases") != list(HOSTILE_CASES)
            or corpus.get("interruptionBoundaries") != list(INTERRUPTION_BOUNDARIES)
            or corpus.get("evidenceIDs") != [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
            or corpus.get("statusFlags") != {key: False for key in ("native", "hosted", "physical", "adoption", "acceptance", "release")}):
        raise ValueError("C46 corpus authority differs")
    _persistence(root)
    _compatibility_corpora(root)
    _mechanical_enrollment_sources(root)
    _audit_driven_source_closure(root)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (218, 14, 232) or len(set(PATH_FENCE)) != 232:
        raise ValueError("C46 fence must be unique 232=218+14")
    if tuple(PATH_FENCE[224:]) != (*SCRIPT_PATHS, *GENERATED_PATHS):
        raise ValueError("C46 tooling rows 225-232 differ")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C46 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C46 base tree differs")
    for path in EXISTING_PATHS:
        if not _base_exists(root, path):
            raise ValueError(f"C46 existing path absent at base:{path}")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"C46 new path existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 3389 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C46 authority/status proof differs")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE,
        "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST, "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": 232, "existingPathCount": 218, "newPathCount": 14,
        "authorizedOverlapCount": 3389, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
        "directPrerequisiteCards": ["V23-P03-C20"], "nextCard": "V23-P03-C47", "nextRegisterOrdinal": 77,
    }


def schema_document(root: Path | None = None) -> dict[str, Any]:
    text = {"type": "string", "minLength": 1}
    strings = lambda minimum=1: {"type": "array", "minItems": minimum, "uniqueItems": True, "items": text}
    case = _closed_object({"caseID": text, "input": text, "expectedDisposition": text}, ["caseID", "input", "expectedDisposition"])
    lifecycle_keys = ["migration", "backup", "restore", "cloneFork", "importExport", "journalReplay", "searchRebuild", "deleteErase", "retention", "compatibilityForwardFix"]
    invariant_keys = [
        "operationalContactsNeverBecomeSubscribers", "operationalContactsNeverBecomeConsentReceipts",
        "operationalContactsNeverBecomeCampaignAudience", "operationalContactsNeverBecomeMeasurementIdentity",
        "siteRoleOwnershipForbidden", "purposeSeparationRequired", "explicitSystemHandoffRequired",
        "oneCanonicalWriterTransaction", "effectBeforeReceiptRecovery", "importPreviewIsNoncanonical",
        "noNetworkDeliveryClaim", "noSecondWriter",
    ]
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/operational-contact.schema.json",
        "title": "V23 P03 C46 Operational Contact Corpus", "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C46OperationalContactCorpusV1"}, "schemaVersion": {"const": 1},
            "cardID": {"const": CARD}, "classification": {"const": "IMPLEMENT_NOW"},
            "persistentSchemaVersion": {"type": "integer", "minimum": 1}, "recordsSchemaVersion": {"type": "integer", "minimum": 1},
            "durableFamilies": strings(), "contractNames": {"const": list(CONTRACT_NAMES)},
            "contactPointCases": {"type": "array", "minItems": 3, "items": case},
            "handoffCases": {"type": "array", "minItems": 3, "items": case},
            "csvImportCases": {"type": "array", "minItems": 3, "items": case},
            "hostileCases": {"const": list(HOSTILE_CASES)}, "interruptionBoundaries": {"const": list(INTERRUPTION_BOUNDARIES)},
            "lifecycle": _closed_object({key: text for key in lifecycle_keys}, lifecycle_keys),
            "invariants": _closed_object({key: {"const": True} for key in invariant_keys}, invariant_keys),
            "evidenceIDs": {"const": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]},
            "statusFlags": _closed_object({key: {"const": False} for key in ("native", "hosted", "physical", "adoption", "acceptance", "release")}, ["native", "hosted", "physical", "adoption", "acceptance", "release"]),
        },
        "required": ["schema", "schemaVersion", "cardID", "classification", "persistentSchemaVersion", "recordsSchemaVersion", "durableFamilies", "contractNames", "contactPointCases", "handoffCases", "csvImportCases", "hostileCases", "interruptionBoundaries", "lifecycle", "invariants", "evidenceIDs", "statusFlags"],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    semantics = {
        "contractNames": list(CONTRACT_NAMES), "fiveSelectors": list(observed_selectors(root)),
        "contactPointsArePurposeBoundAndIndependentFromSiteRoleOwnership": True,
        "operationalContactsNeverBecomeSubscriberConsentCampaignOrMeasurementIdentity": True,
        "csvImportRequiresDeterministicPreviewValidationAndExplicitAcceptance": True,
        "systemHandoffIntentRequiresExplicitUserStartAndClaimsNoDelivery": True,
        "canonicalMutationsUseExpectedRevisionMutationIDOneWriterAndDurableReceipt": True,
        "effectBeforeReceiptRecoveryIsIdempotent": True,
        "durableLifecycleCoversMigrationBackupRestoreCloneForkImportExportReplaySearchDeleteEraseRetentionAndForwardFix": True,
        "noNetworkProviderSecondWriterDormantMarketingOrCustomerLearningDependency": True,
        "importPreviewIsBoundedCancelableNoncanonicalAndAcceptanceIsOneAtomicWriterCall": True,
        "unicodeMailtoRecipientEncodingRejectsQueryAndHeaderInjection": True,
        "sameWorkspaceReplaceRestorePreservesExactOperationalContactBytesAndJournalClosure": True,
        "duplicateMutationIDAndConcurrencyGuardsFailClosed": True,
        "crossWorkspaceReplaceRebuildsDestinationJournalReceiptAndProjectionWithDistinctWorkspaceRegression": True,
    }
    enrollment = [{"path": path, "marker": mechanical_marker(path), "classification": mechanical_classification(path)} for path in REQUIRED_MECHANICAL_PATHS]
    return _sealed({"schema": "V23P03C46OperationalContactContractV1", "schemaVersion": 1, "authority": authority(), "persistence": _persistence(root), "requiredSemantics": semantics, "mechanicalEnrollment": enrollment, "mechanicalEnrollmentDigest": sha256_value(enrollment)})


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    return _sealed({
        "schema": "V23P03C46OperationalContactEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "classification": "IMPLEMENT_NOW", "evidenceIDs": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")],
        "testSelectors": list(observed_selectors(root)), "persistence": _persistence(root),
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
        "nativeEvidenceState": "PENDING_NOT_ACCEPTING", "physicalEvidenceState": "REQUIRED_PENDING_OWNER",
        "adoptionState": "PENDING_NOT_ACCEPTING", "acceptanceState": "PENDING_NOT_ACCEPTING", "releaseState": "PENDING_NOT_ACCEPTING", "statusFlags": FLAGS,
    })


def brand_document() -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C46BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "publicClaimDelta": False, "nativeIPadSurface": False,
        "dynamicTypeThroughAX5": True, "voiceOverAndErrorFocusRequired": True, "stateNeverReliesOnlyOnColor": True,
        "operationalContactPrivacySeparationRequired": True, "networkDeliveryMarketingMeasurementFlow": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    rendered = {SCHEMA_PATH: pretty(schema_document(root)), CONTRACT_PATH: pretty(contract_document(root)), EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document())}
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "schema": "V23P03C46ToolingManifestV1", "schemaVersion": 1, "authority": authority(),
        "pathFence": list(PATH_FENCE), "pathFenceCount": 232, "existingPathCount": 218, "newPathCount": 14,
        "authorizedOverlapCount": 3389, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
        "mechanicalEnrollmentPaths": list(REQUIRED_MECHANICAL_PATHS), "mechanicalEnrollmentDigest": sha256_value(list(REQUIRED_MECHANICAL_PATHS)),
        "artifacts": rows, "artifactSetDigest": sha256_value(rows), "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    }))
    return rendered
