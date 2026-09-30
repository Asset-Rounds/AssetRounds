#!/usr/bin/env python3
"""Deterministic static contract/evidence model for V23-P03-C27.

Generated artifacts remain provisional until the C27 Swift contracts and test
corpus exist.  This module is self-contained and never reads coordination.
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

CARD = "V23-P03-C27"
TITLE = "Opaque asset locators, external keys, safe resolution, rebinding, and retirement"
REGISTER_ORDINAL = 64
BASE_HEAD = "91ba659489b3a42707631d3a6117cab865f8fea5"
BASE_TREE = "6c3aaf8dee102c444aec7a7912f48b52863bc7bc"
COORDINATION_HEAD = "d141db7328861af29543264ea8624cf6148d6295"
COORDINATION_TREE = "e4ab5d54dff9b8461277825ce78ed19bba23db11"
COORDINATION_CAS_SEQUENCE = 273
HYDRATION_REVISION = 2
CONTEXT_DIGEST = "54bfcdcddddbdd66ffcfc3c0c98d56bc404b9ffd0d6cae6b716e533d0e105851"
FENCE_DIGEST = "9864db2f420a45c4497326da79d41f27cbfb187c0fb62c3fca96c051694adc0a"
PREREQUISITE_DIGEST = "849dd47256c86198df9fc3bb90ba10f822bf7398aafc08208fd724fac02482a1"
FENCE_CORRECTION_RECEIPT_DIGEST = "02820519bd539539fe2a1b3804e0a570c77c547390336d4024e3ded92e1e8d1b"
HYDRATION_TRANSITION_DIGEST = "81ceffdbd5a14f1a44a26d076cb4b1ab5a2a70ad4d2886482b32fcdb7f31a2a9"
COORDINATION_LEDGER_DIGEST = "bc0c14eaf91d78fcd59cb82f17f54391f87cdeb9c3f49071709307d0dc0545d1"
COORDINATION_PROJECTION_DIGEST = "c6142df78fe58e73abde700cfe5641cb62187cc6e78163f6426c130cea711927"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
AUTHORIZED_OVERLAP_COUNT = 1577
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/asset-locator.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C27AssetLocatorContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C27AssetLocatorEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C27BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C27-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c27_contracts.py",
    "Scripts/v23/generate_p03_c27_contracts.py",
    "Scripts/v23/verify_p03_c27_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)

EXISTING_PATHS = tuple("""FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift
FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift
FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift
FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift
FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift
FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift
FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift
FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift
FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift
FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift
FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift
FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift
FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift
FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift
FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift
FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift
FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift
FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift
FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift
FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift
FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift
FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift
FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift
FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift
FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift
FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift
FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift
FieldEvidenceAppTests/V9_06DeletionRightsTests.swift
FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift
FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift
FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift
FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift
FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift
FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift
FieldEvidenceAppTests/S6_2BackupExportTests.swift
FieldEvidenceAppTests/S6_3BackupValidationTests.swift
FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift
FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift
FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift
FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift
FieldEvidenceAppTests/V9_20KernelConformanceTests.swift
FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift
FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift
FieldEvidenceApp/Domain/Models/AssetSemanticPersistenceModelsV1.swift
FieldEvidenceApp/Domain/Models/Asset.swift
FieldEvidenceApp/Application/AssetSemantics/AssetSemanticsCoordinatorV1.swift
FieldEvidenceApp/Infrastructure/AssetSemantics/AssetSemanticLifecycleAdapterV1.swift
FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift
FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift
FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift
FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift
FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift
FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift
FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift
FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift
FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift
FieldEvidenceApp/Domain/Workflow/WorkflowContracts.swift
FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift
FieldEvidenceApp/Domain/Models/WorkflowModels.swift
FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift
FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift
FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift
FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift
FieldEvidenceApp/Domain/Search/SearchContractsV1.swift
FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift
FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift
FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift
FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift
FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift
FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift
FieldEvidenceApp/Resources/Localizable.xcstrings
FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift
FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift
FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift
FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift
FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift
FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift
FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift
FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift
FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift
FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift
FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift
FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift
FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift
FieldEvidenceAppTests/S3_6CameraRecoveryTests.swift
FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift
FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift
FieldEvidenceAppTests/S4_4HistoryComparisonTests.swift
FieldEvidenceAppTests/S6_1DeletionGraphTests.swift
FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift
FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift
FieldEvidenceAppTests/V9_19LocalSearchTests.swift
FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift
FieldEvidenceAppTests/V9_24AssetSemanticLifecycleTests.swift""".splitlines()) + (
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift",
    "FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift",
    "FieldEvidenceAppTests/V9_17KernelPersistenceTests.swift",
    "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift",
)

NEW_PATHS = (
    "FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetLocatorPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetLocatorLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_41AssetLocatorTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/AssetLocators/V22P03C27AssetLocatorCorpusV1.json",
    *SCRIPT_PATHS,
    *GENERATED_PATHS,
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = ("AssetLocatorV1", "ExternalKeyV1", "LocatorResolutionV1", "LocatorBindingReceiptV1")
PERSISTED_FAMILIES = ("AssetLocatorV1", "LocatorBindingReceiptV1")
NONPERSISTENT_FAMILIES = ("LocatorResolutionInputV1", "LocatorResolutionV1", "LocatorBindingPreviewV1", "FrozenAssetLocatorInterpretationV1")
RESOLUTION_OUTCOMES = ("MATCHED", "NO_MATCH", "FOREIGN_WORKSPACE", "AMBIGUOUS", "DAMAGED_OR_INCOMPLETE", "RETIRED", "REVOKED", "REPLACED")
TEST_METHODS = (
    "testV23P03C27G01StableLocatorResolutionHasEightClosedOutcomesAndSourceParity",
    "testV23P03C27A01CanonicalKeysSignaturesBindingsAndRowsRemainImmutable",
    "testV23P03C27H01ForeignRevokedPartialOversizedCollisionAndStaleInputsFailClosed",
    "testV23P03C27I01CanonicalRowsRetryFromOnlyOldOrNewStateAndReplayDeterministically",
    "testV23P03C27R01RetirementReplacementAndFrozenHistorySurviveOfflineRecovery",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
FLAGS = {key: False for key in (
    "native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance",
    "hostedAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness",
    "phase10PollingDuringParallelExecution",
)}

PERSISTENCE = {
    "schemaRelease": "ASSET_LOCATOR_V1", "persistentSchemaVersion": 26,
    "recordsSchemaVersion": 25, "persistentKindLifecycleModelCount": 94,
    "durableFamilyCount": 2, "persistedFamilies": list(PERSISTED_FAMILIES),
    "nonPersistentFamilies": list(NONPERSISTENT_FAMILIES), "mode": "NEW_SCHEMA_VERSION",
    "migrationRequired": True, "backupRestoreRequired": True, "cloneForkRequired": True,
    "deleteEraseRequired": True, "exportReportRequired": True, "searchRebuildRequired": True,
    "replayRequired": True, "interruptionRecoveryRequired": True,
    "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V26_WRITE",
}

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1", "schemaVersion": 1,
    "successorCardID": CARD, "successorAttemptID": 1, "ordinaryDirectEdgeCount": 1,
    "predecessors": [{"cardID": "V23-P03-C22", "attemptID": 1,
        "candidateHead": "d0485977644a71e49b8d4b898bb527e0353bd81e",
        "candidateTree": "2fc990ee64f9da6e84b07fddc2abed036f679630",
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C22_HEAD"}],
    "canonicalRelationPreserved": True, "nonreleaseSpecialEdgeApplied": False,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "nativeCompileRan": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
    "acceptanceCredit": False, "releaseCredit": False, "prerequisiteDigest": PREREQUISITE_DIGEST,
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _base_path_exists(root: Path, relative: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{relative}"], capture_output=True).returncode == 0


def _observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / "FieldEvidenceAppTests/V9_41AssetLocatorTests.swift"
    if not path.is_file():
        return TEST_METHODS
    values = tuple(re.findall(r"\bfunc\s+(testV23P03C27(?:G|A|H|I|R)\w*)\s*\(", path.read_text(encoding="utf-8")))
    return values


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def assert_corpus(root: Path) -> dict[str, Any]:
    relative = "FieldEvidenceAppTests/Fixtures/V22/AssetLocators/V22P03C27AssetLocatorCorpusV1.json"
    corpus = json.loads((root / relative).read_text(encoding="utf-8"), object_pairs_hook=_strict_object)
    expected = {
        "schema": "V22P03C27AssetLocatorCorpusV1", "schemaVersion": 1, "cardID": CARD,
        "ordinal": REGISTER_ORDINAL, "records": 25, "recordsSchemaVersion": 25,
        "persistentSchemaVersion": 26, "persistentModelCount": 94,
        "currentSyncPersistentModelCount": 94, "resolutionOutcomes": list(RESOLUTION_OUTCOMES),
        "evidenceIDs": ["G01", "A01", "H01", "I01", "R01"],
    }
    for key, value in expected.items():
        if corpus.get(key) != value:
            raise ValueError(f"corpus mismatch: {key}")
    selectors = corpus.get("evidenceSelectors")
    if not isinstance(selectors, list) or [row.get("id") for row in selectors] != list(EVIDENCE_IDS):
        raise ValueError("corpus evidence selectors")
    persistence = corpus.get("persistence", {})
    if not isinstance(persistence, dict) or any(persistence.get(key) != value for key, value in (
        ("persistentSchemaVersion", 26), ("recordsSchemaVersion", 25),
        ("persistentKindLifecycleModelCount", 94), ("durableFamilyCount", 2),
    )):
        raise ValueError("corpus persistence")
    return corpus


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "title": TITLE, "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "fenceCorrectionReceiptDigest": FENCE_CORRECTION_RECEIPT_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS), "directPrerequisiteCards": ["V23-P03-C22"],
        "nextCard": "V23-P03-C28", "digestPinsPending": False,
    }


def schema_document() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/asset-locator.schema.json",
        "title": "V23 P03 C27 Asset Locator Corpus", "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C27AssetLocatorCorpusV1"},
            "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
            "persistentSchemaVersion": {"const": 26}, "recordsSchemaVersion": {"const": 25},
            "persistentKindLifecycleModelCount": {"const": 94}, "durableFamilyCount": {"const": 2},
            "durableFamilies": {"type": "array", "const": list(PERSISTED_FAMILIES)},
            "resolutionOutcomes": {"type": "array", "const": list(RESOLUTION_OUTCOMES)},
            "requiredContractNames": {"type": "array", "const": list(CONTRACT_NAMES)},
            "statusFlags": {"type": "object", "additionalProperties": {"const": False}},
        },
        "required": ["schema", "schemaVersion", "cardID", "persistentSchemaVersion", "recordsSchemaVersion",
                     "persistentKindLifecycleModelCount", "durableFamilyCount", "durableFamilies",
                     "resolutionOutcomes", "requiredContractNames", "statusFlags"],
    }


def _sealed(body: dict[str, Any]) -> dict[str, Any]:
    return {**body, "artifactDigest": sha256_bytes(pretty(body))}


def contract_document(root: Path) -> dict[str, Any]:
    required = {
        "contractNames": list(CONTRACT_NAMES), "resolutionOutcomes": list(RESOLUTION_OUTCOMES),
        "persistentFamilies": list(PERSISTED_FAMILIES), "nonPersistentFamilies": list(NONPERSISTENT_FAMILIES),
        "fiveSelectors": list(_observed_selectors(root)), "opaquePayloadContainsSecrets": False,
        "scanMutates": False, "scanStartsSession": False, "codeGrantsPermission": False,
        "networkOnlyResolver": False, "silentDuplicateMerge": False,
        "manualAndCameraShareResolver": True, "rebindPreviewAndReceiptRequired": True,
        "historicInterpretationFrozen": True,
    }
    return _sealed({"schema": "V23P03C27AssetLocatorContractV1", "schemaVersion": 1,
                    "authority": authority(), "persistence": PERSISTENCE,
                    "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
                    "requiredSemantics": required})


def evidence_document(root: Path) -> dict[str, Any]:
    required = contract_document(root)["requiredSemantics"]
    return _sealed({"schema": "V23P03C27AssetLocatorEvidenceReceiptV1", "schemaVersion": 1,
                    "cardID": CARD, "evidenceIDs": list(EVIDENCE_IDS),
                    "testSelectors": list(_observed_selectors(root)),
                    "requiredSemanticsDigest": sha256_value(required), "statusFlags": FLAGS})


def brand_document() -> dict[str, Any]:
    return _sealed({"schema": "V23P03C27BrandImpactManifestV1", "schemaVersion": 1,
                    "cardID": CARD, "uiSurfaceDelta": False, "brandSurfaceDelta": True,
                    "changedStates": ["MATCHED", "NO_MATCH", "FOREIGN_WORKSPACE", "AMBIGUOUS",
                                      "DAMAGED_OR_INCOMPLETE", "RETIRED", "REVOKED", "REPLACED"],
                    "nativeIPadSurface": False, "telemetry": False, "statusFlags": FLAGS})


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    raw = rendered[relative] if relative in rendered else (root / relative).read_bytes()
    return {"path": relative, "sha256": sha256_bytes(raw), "byteCount": len(raw)}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_corpus(root)
    rendered = {SCHEMA_PATH: pretty(schema_document()), CONTRACT_PATH: pretty(contract_document(root)),
                EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document())}
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({"schema": "V23P03C27ToolingManifestV1", "schemaVersion": 1,
                        "authority": authority(), "pathFence": list(PATH_FENCE),
                        "pathFenceCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS),
                        "newPathCount": len(NEW_PATHS), "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
                        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
                        "artifacts": rows, "artifactSetDigest": sha256_value(rows), "statusFlags": FLAGS})
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (116, 14, 130):
        raise ValueError("C27 corrected fence must be 130=116+14")
    if len(set(PATH_FENCE)) != 130:
        raise ValueError("C27 fence contains duplicates")
    if any("s10" in path.lower() or "phase10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C27 fence overlaps S10/Phase10")
    for path in EXISTING_PATHS:
        if not _base_path_exists(root, path):
            raise ValueError(f"existing path absent at base: {path}")
    for path in NEW_PATHS:
        if _base_path_exists(root, path):
            raise ValueError(f"new path existed at base: {path}")
    if _observed_selectors(root) != TEST_METHODS:
        raise ValueError("C27 source must expose exactly the five sealed selectors")
    assert_corpus(root)
