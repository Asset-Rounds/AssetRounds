#!/usr/bin/env python3
"""Deterministic language-neutral contracts for provisional V23-P03-C09."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
from p03_c08_contracts import ACTIVE_S10_RESERVED_PATHS

CARD = "V23-P03-C09"
TITLE = "Bounded local search, revision-bound rebuild, and durable smart views"
APP_BASE_HEAD = "23e85119f222d20ccd20d906f600cc4d81f93876"
APP_BASE_TREE = "2f722a58146ed0c76bef32b95808c3399dde011d"
COORDINATION_HEAD = "c520b182691794893a08b3c486634bd9eccef1cd"
COORDINATION_TREE = "e8b96faa4ca2a7f1fd3279fcfadbb2d51009d0af"
CONTEXT_DIGEST = "d16169a1bf3c1bfe8dc614e7a5cd1a2b3061ebdb16a6319150546cfd96c28b55"
FENCE_DIGEST = "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed"
PREREQUISITE_DIGEST = "603f40097b381bebb9e26b7afb8b7c4b58911cb19f9eebd3ff7bdac60e8200bc"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
DOSSIER_DIGEST = "68b7b535fdf6a14e29f13882a24bf5a9d6f65c918e223240e50e257b1c9b18b7"
INHERITED_BLOCK_DIGEST = "fdb3799ff3c8596fa128602894d4fa507115e781b03e9800fab73a11a12cbd02"
REGISTER_ROW_DIGEST = "a487a02d9f2914c93dad095292771413b5fed5a5ac249b1af0d2554b03c53691"

EXISTING_PATHS = [
    "FieldEvidenceApp/Domain/Models/Site.swift",
    "FieldEvidenceApp/Domain/Models/Asset.swift",
    "FieldEvidenceApp/Domain/Models/LocationPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
    "FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift",
    "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V9_02FileAuthorityTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_08GenerationLeaseTests.swift",
]
NEW_PRODUCT_PATHS = [
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
]
TEST_PATH = "FieldEvidenceAppTests/V9_19LocalSearchTests.swift"
FIXTURE = "FieldEvidenceAppTests/Fixtures/V21/Search/V21P03C09LocalSearchCorpusV1.json"
SCRIPT_PATHS = [
    "Scripts/v23/p03_c09_contracts.py",
    "Scripts/v23/generate_p03_c09_contracts.py",
    "Scripts/v23/verify_p03_c09_contracts.py",
]
SCHEMA_PATH = "Scripts/v23/local-search-smart-view.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C09LocalSearchSmartViewContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C09LocalSearchEvidenceReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C09-tooling-manifest.json"
SOURCE_PATHS = EXISTING_PATHS + NEW_PRODUCT_PATHS + [TEST_PATH, FIXTURE]
GENERATED_PATHS = [CONTRACT_PATH, EVIDENCE_PATH, MANIFEST]
TOOL_PATHS = SCRIPT_PATHS + [SCHEMA_PATH] + GENERATED_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
NEW_PATHS = NEW_PRODUCT_PATHS + [TEST_PATH, FIXTURE] + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]

EVIDENCE_IDS = [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_19G01MutationDeleteSynchronization",
    "testV9_19A01CrashThenRevisionBoundRebuild",
    "testV9_19H01SortingFilteringUnicodeAndPrivacyBoundary",
    "testV9_19I01TenThousandRecordBudgetsFailClosed",
    "testV9_19R01DropRebuildRetainsCanonicalRecordsAndSavedViews",
]
SCOPES = ["ALL", "ASSETS", "LOCATIONS", "WORK", "REPORTS"]
SMART_VIEWS = ["RECENT", "INCOMPLETE", "RECHECK_DUE", "REPORT_FAILED", "BACKUP_STALE"]
RANKING = [
    "EXACT_STABLE_OR_DISPLAY_IDENTITY", "NORMALIZED_EXACT_TOKEN", "PREFIX",
    "TOKEN_PREFIX", "SUBSTRING", "TYPO_SUGGESTION_ONLY", "STABLE_ID_THEN_TIMESTAMP_TIE",
]
INDEXED_FIELDS = [
    "asset_identifier", "asset_label", "location_identifier", "location_label",
    "location_breadcrumb", "work_identifier", "work_summary", "report_identifier",
    "report_summary", "status",
]
SOURCE_KIND_MAPPINGS = [
    {"fieldID": "asset_identifier", "sourceKind": "ASSET"},
    {"fieldID": "asset_label", "sourceKind": "ASSET"},
    {"fieldID": "location_breadcrumb", "sourceKind": "LOCATION"},
    {"fieldID": "location_identifier", "sourceKind": "LOCATION"},
    {"fieldID": "location_label", "sourceKind": "LOCATION"},
    {"fieldID": "report_identifier", "sourceKind": "REPORT"},
    {"fieldID": "report_summary", "sourceKind": "REPORT"},
    {"fieldID": "status", "sourceKind": "ASSET"},
    {"fieldID": "status", "sourceKind": "LOCATION"},
    {"fieldID": "status", "sourceKind": "REPORT"},
    {"fieldID": "status", "sourceKind": "WORK"},
    {"fieldID": "work_identifier", "sourceKind": "WORK"},
    {"fieldID": "work_summary", "sourceKind": "WORK"},
]
EXCLUDED_FIELDS = [
    "media_bytes", "raw_ocr", "hidden_metadata", "support_draft", "feedback_draft",
    "uncommitted_c36",
]
CHECKS = [
    "EXACT_CORRECTED_60_PATH_FENCE_AND_BASE_EXISTENCE_PARTITION",
    "ZERO_ACTIVE_S10_RESERVATION_OVERLAP",
    "FROZEN_DOSSIER_INHERITED_AND_PREREQUISITE_AUTHORITY",
    "STRICT_DRAFT_2020_12_SCHEMA_POSITIVE_AND_HOSTILE_CORPUS",
    "MUTATION_DELETE_REVISION_AND_REBUILD_SYNCHRONIZATION",
    "DETERMINISTIC_SORT_FILTER_UNICODE_TYPO_AND_PRIVACY_MATRIX",
    "TEN_THOUSAND_RECORD_QUERY_REBUILD_AND_SIZE_BUDGETS",
    "SAVED_VIEW_V7_AND_DERIVED_INDEX_LIFECYCLE_RECOVERY",
    "EXACT_FIVE_NAMED_G01_A01_H01_I01_R01_SWIFT_TESTS",
    "INDEPENDENT_GENERATION_AND_BYTE_DIGEST_CLOSURE",
]


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "s10ReservationDigest": S10_RESERVATION_DIGEST,
        "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "dossierDigest": DOSSIER_DIGEST, "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST,
    }


def artifact(path: str, raw: bytes) -> dict[str, Any]:
    return {"path": path, "bytes": len(raw), "sha256": sha256(raw)}


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing source artifact: {relative}")
        rows.append(artifact(relative, path.read_bytes()))
    return rows


def changed_existing_paths(root: Path) -> list[str]:
    changed = []
    for relative in EXISTING_PATHS:
        base = subprocess.run(
            ["git", "-C", str(root), "show", f"{APP_BASE_HEAD}:{relative}"],
            check=True, capture_output=True,
        ).stdout
        if (root / relative).read_bytes() != base:
            changed.append(relative)
    return changed


def contract(root: Path) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C09LocalSearchSmartViewContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "pathFence": PATH_FENCE, "sourcePaths": SOURCE_PATHS, "toolPaths": TOOL_PATHS,
        "scopes": SCOPES, "smartViewKinds": SMART_VIEWS, "rankingPrecedence": RANKING,
        "searchableFieldRegistry": [
            {**mapping, "privacyClass": "WORKSPACE_USER_VISIBLE", "snippetAllowed": True,
             "normalization": "NFC_CASE_DIACRITIC_FOLD_CONTROL_STRIP", "purgeOwner": "SEARCH_INDEX"}
            for mapping in SOURCE_KIND_MAPPINGS
        ],
        "excludedFieldIDs": EXCLUDED_FIELDS,
        "typoPolicy": {"belowFour": 0, "fourThroughSeven": 1, "eightOrMore": 2,
                       "maximumSuggestions": 5, "silentSubstitutionAllowed": False},
        "sessionState": {"survivesDetailBack": ["query", "scope", "filter", "selectedStableID", "scrollAnchor"],
                         "survivesColdRestore": ["scope", "filter", "selectedStableID", "scrollAnchor"],
                         "coldRestoreClearsQuery": True, "routeStoresUserText": False},
        "lifecycle": {
            "SavedSmartViewDescriptorV1": {"mode": "NEW_SCHEMA_VERSION", "schema": "PERSISTENT_SCHEMA_V7_SAVED_SMART_VIEW_DESCRIPTOR", "downgrade": "FAIL_CLOSED_READ_COMPATIBLE_FORWARD_FIX", "backupRestoreDeleteEraseReplayExport": True},
            "SearchIndexProjectionV1": {"mode": "DERIVED_ONLY", "canonicalTruth": False, "backupExport": False, "downgrade": "DROP_AND_REBUILD", "revisionBound": True},
            "lastSelectedSmartViewID": {"mode": "DEVICE_LOCAL_SCALAR_PREFERENCE", "canonicalSavedView": False},
            "rawRecentQueryPersistence": "NOT_IMPLEMENTED",
        },
        "budgets": {"recordCount": 10000, "maximumProjectionRows": 100000,
                    "maximumProjectionRowsPerPage": 2500, "maximumResults": 100,
                    "maximumRebuildMilliseconds": 5000, "maximumQueryMilliseconds": 250,
                    "maximumIndexBytes": 16777216},
        "productionClosure": {
            "swiftDataProjectionSource": "SwiftDataSearchCanonicalProjectionSourceV1",
            "serviceSeam": "ProductionSearchServicesV1", "sourceKindRegistrationCount": 13,
            "writerInvalidationSynchronous": True, "startupInvalidationSynchronous": True,
            "assetSiteCrashRetryMarkerOrdered": True, "orphanCleanupPurgesDerivedIndex": True,
            "typedCanonicalStableKeys": True, "sameSearchKindTypedIdentityCollisionSafe": True,
            "truthfulIncompleteStatusSemantics": True,
            "backupStaleRequiresOperationalProvider": True,
            "rebuildPublicationTokenRequired": True,
            "sameRevisionDeletionRaceCovered": True,
        },
        "sourceArtifacts": source_rows(root), "fixtureArtifact": artifact(FIXTURE, (root / FIXTURE).read_bytes()),
        "evidenceIDs": EVIDENCE_IDS, "testMethods": TEST_METHODS,
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "phase10PollingDuringParallelExecution": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def evidence(root: Path, contract_value: dict[str, Any]) -> dict[str, Any]:
    schema_raw = (root / SCHEMA_PATH).read_bytes()
    changed_existing = changed_existing_paths(root)
    unsigned = {
        "schema": "V23P03C09LocalSearchEvidenceReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "result": "PASS", "verificationMode": "STATIC_ONLY",
        "checks": CHECKS, "evidenceIDs": EVIDENCE_IDS, "testMethods": TEST_METHODS,
        "pathFenceCount": 60, "existingPathCount": 46, "newPathCount": 14,
        "changedExistingAuthorityPaths": changed_existing,
        "unchangedAuthorityPathCount": 46 - len(changed_existing),
        "sourcePathCount": 53, "toolPathCount": 7, "s10FenceOverlapPaths": [],
        "activeS10ReservationPathCount": len(ACTIVE_S10_RESERVED_PATHS),
        "sourceArtifacts": source_rows(root), "fixtureArtifact": artifact(FIXTURE, (root / FIXTURE).read_bytes()),
        "schemaArtifact": artifact(SCHEMA_PATH, schema_raw),
        "contractArtifact": artifact(CONTRACT_PATH, pretty(contract_value)),
        "evidenceMatrix": [{"evidenceID": evidence_id, "testMethod": method}
                           for evidence_id, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "phase10PollingDuringParallelExecution": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def manifest(root: Path, contract_raw: bytes, evidence_raw: bytes) -> dict[str, Any]:
    generated = {CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw}
    rows = []
    for relative in MANIFEST_INPUT_PATHS:
        raw = generated.get(relative)
        if raw is None:
            raw = (root / relative).read_bytes()
        rows.append(artifact(relative, raw))
    changed_existing = changed_existing_paths(root)
    unsigned = {
        "schema": "V23P03C09ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": PATH_FENCE, "existingPaths": EXISTING_PATHS,
        "newPaths": NEW_PATHS, "pathFenceCount": 60, "existingPathCount": 46, "newPathCount": 14,
        "changedExistingAuthorityPaths": changed_existing,
        "unchangedAuthorityPathCount": 46 - len(changed_existing),
        "sourcePathCount": 53, "toolPathCount": 7, "generatedArtifactCount": 3,
        "manifestInputCount": 59, "activeS10ReservationPathCount": len(ACTIVE_S10_RESERVED_PATHS),
        "s10FenceOverlapPaths": [], "artifacts": rows, "artifactSetDigest": sha256(canonical(rows)),
        "evidenceIDs": EVIDENCE_IDS, "verificationMode": "STATIC_ONLY",
        "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "phase10PollingDuringParallelExecution": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def all_outputs(root: Path) -> dict[str, bytes]:
    contract_raw = pretty(contract(root))
    evidence_raw = pretty(evidence(root, json.loads(contract_raw)))
    manifest_raw = pretty(manifest(root, contract_raw, evidence_raw))
    return {CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, MANIFEST: manifest_raw}
