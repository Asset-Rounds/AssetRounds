#!/usr/bin/env python3
"""Deterministic static evidence projection for V23-P03-C35."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C35"
BASE_HEAD = "884773401c32956c75fa425d36c60733e40a8fe1"
BASE_TREE = "d136ccab1a393d2f52f52a4132634135c1eda563"
CONTEXT_DIGEST = "e47b3a46ba3297c81f0ce5f4a5de9a8d5b1210646cdcdeb5da4fe2459359412c"
FENCE_DIGEST = "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe"
PREREQUISITE_DIGEST = "c0d85f7f9f6da3da50423ebd9d0e0a1942b257b8df3a6421c978dd7f76711e07"
S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
LEDGER_DIGEST = "e2df2856fd07592b70922568dae7a6e55ec89c786b99d8bffb05af054a06ef3d"
PROJECTION_DIGEST = "edada017c87aaad449b843d7705129349a7415e2b64a38411c7f58fdb5da5797"
CORRECTION_RECEIPT_DIGEST = "f7d5fe412fff3bc19b3c296a18ad54925263b39c2a12b87b7aacbe42c6800748"

BASE_SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Models/Site.swift", "FieldEvidenceApp/Domain/Models/Asset.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift", "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift", "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift", "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift", "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift", "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift", "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift", "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift", "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift", "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift", "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift", "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift", "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift", "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift", "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift", "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift", "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceApp/Domain/Models/LocationPersistenceModelsV1.swift", "FieldEvidenceApp/Domain/Location/LocationHierarchyContractsV1.swift",
    "FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift", "FieldEvidenceApp/Domain/Location/AssetCompositionContractsV1.swift",
    "FieldEvidenceApp/Domain/Location/CompletedLocationCompositionSnapshotV1.swift", "FieldEvidenceApp/Application/Location/AssetPlacementChangeCoordinatorV1.swift",
    "FieldEvidenceAppTests/V9_LocationHierarchyPlacementCompositionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Location/V21P03C35LocationPlacementCompositionCorpusV1.json",
]
ADDED_SOURCE_PATHS = [
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_08GenerationLeaseTests.swift",
    "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift",
]
SOURCE_PATHS = BASE_SOURCE_PATHS + ADDED_SOURCE_PATHS
SCRIPT_PATHS = ["Scripts/v23/p03_c35_contracts.py", "Scripts/v23/generate_p03_c35_contracts.py", "Scripts/v23/verify_p03_c35_contracts.py"]
SCHEMA_PATH = "Scripts/v23/location-placement-composition.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C35LocationPlacementCompositionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C35LocationPlacementCompositionEvidenceReceiptV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C35-tooling-manifest.json"
GENERATED_PATHS = [SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, MANIFEST_PATH]
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS
PATH_FENCE = BASE_SOURCE_PATHS + TOOL_PATHS + ADDED_SOURCE_PATHS
MANIFEST_INPUT_PATHS = [path for path in PATH_FENCE if path != MANIFEST_PATH]
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/Location/V21P03C35LocationPlacementCompositionCorpusV1.json"
TEST_PATH = "FieldEvidenceAppTests/V9_LocationHierarchyPlacementCompositionTests.swift"
EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_LocationHierarchyPlacementCompositionG01FlatMigrationAndHierarchyRemainStable",
    "testV9_LocationHierarchyPlacementCompositionA01DeletionIsExplicitAndNeverCascadesHistory",
    "testV9_LocationHierarchyPlacementCompositionH01HostileGraphsFailClosed",
    "testV9_LocationHierarchyPlacementCompositionI01InterruptionMatrixPreservesRestartAuthority",
    "testV9_LocationHierarchyPlacementCompositionR01FrozenHistorySurvivesRestoreAndEraseIsGenerationScoped",
]

def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()

def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()

def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()

def authority() -> dict[str, Any]:
    return {"cardID": CARD, "attemptID": 1, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
            "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST,
            "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
            "frozenS10ReservationDigest": S10_DIGEST, "coordinationLedgerDigest": LEDGER_DIGEST,
            "coordinationProjectionDigest": PROJECTION_DIGEST,
            "hydrationCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
            "coordinationCASSequence": 175, "hydrationRevision": 4,
            "allowedPathCount": 58, "existingPathCount": 43, "newPathCount": 15,
            "persistentChangeMode": "SCHEMA_AND_CONTENT",
            "persistentContractSchema": "PERSISTENT_SCHEMA_V6_LOCATION_PLACEMENT_COMPOSITION",
            "schemaBehaviorDelta": True, "migrationBehaviorDelta": True,
            "backupBehaviorDelta": True, "restoreBehaviorDelta": True,
            "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
            "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True,
            "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True,
            "downgradeDisposition": "FORWARD_FIX_ONLY_AFTER_FIRST_V6_WRITE",
            "nativeCompileRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False,
            "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
            "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
            "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True,
            "deferredAdoptionObligations": [
                "FINALIZATION_SERVICE_CURRENT_LOCATION_COMPOSITION_SNAPSHOT_ADOPTION_AFTER_ACCEPTED_S10_6_RECONCILIATION"
            ]}

def semantic_node(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return {"type":"object","additionalProperties":False,
                "required":sorted(value),
                "properties":{key:semantic_node(item) for key,item in sorted(value.items())}}
    if isinstance(value, list):
        variants=[]
        for item in value:
            candidate=semantic_node(item)
            if canonical(candidate) not in {canonical(row) for row in variants}: variants.append(candidate)
        result={"type":"array","minItems":len(value),"maxItems":len(value)}
        if variants: result["items"]=variants[0] if len(variants)==1 else {"anyOf":variants}
        if all(isinstance(item,str) for item in value): result["uniqueItems"]=True
        return result
    if value is None: return {"type":"null"}
    if isinstance(value,bool): return {"type":"boolean"}
    if isinstance(value,int): return {"type":"integer"}
    if isinstance(value,str):
        if len(value)==36 and value.count("-")==4: return {"type":"string","format":"uuid"}
        if len(value)==64 and all(char in "0123456789abcdef" for char in value):
            return {"type":"string","pattern":"^[0-9a-f]{64}$"}
        return {"type":"string","minLength":1}
    raise ContractError(f"unsupported schema value: {type(value)!r}")

def schema(fixture: dict[str, Any]) -> dict[str, Any]:
    value=semantic_node(fixture)
    value.update({"$schema":"https://json-schema.org/draft/2020-12/schema",
                  "$id":"https://assetrounds.invalid/schemas/v23/location-placement-composition.schema.json",
                  "title":"V23-P03-C35 semantic location placement composition corpus"})
    return value

def artifacts(root: Path, paths: list[str]) -> list[dict[str, Any]]:
    rows=[]
    for relative in paths:
        raw=(root/relative).read_bytes()
        rows.append({"path":relative,"bytes":len(raw),"sha256":sha256(raw)})
    return rows

def sealed(value: dict[str, Any]) -> dict[str, Any]:
    result=dict(value); result["artifactDigest"]=sha256(pretty(value)); return result

def all_outputs(root: Path) -> dict[str, bytes]:
    fixture=json.loads((root/FIXTURE_PATH).read_text(encoding="utf-8"))
    schema_raw=pretty(schema(fixture))
    source_rows=artifacts(root, SOURCE_PATHS)
    contract=sealed({"schema":"V23P03C35LocationPlacementCompositionContractV1","schemaVersion":1,
        "authority":authority(),"pathFence":PATH_FENCE,"sourceArtifacts":source_rows,"evidenceIDs":EVIDENCE_IDS,
        "testMethods":TEST_METHODS,"policies":["BOUNDED_DEPTH_EIGHT","APPEND_ONLY_SINGLE_TIP_PLACEMENT","ONE_STRUCTURAL_PARENT","NO_CASCADE_DELETE","ERASE_IS_GENERATION_SCOPED"]})
    contract_raw=pretty(contract)
    evidence=sealed({"schema":"V23P03C35LocationPlacementCompositionEvidenceReceiptV1","schemaVersion":1,
        "authority":authority(),"result":"PASS","verificationMode":"STATIC_ONLY","evidenceIDs":EVIDENCE_IDS,
        "testMethods":TEST_METHODS,"sourceArtifacts":source_rows,
        "schemaArtifact":{"path":SCHEMA_PATH,"bytes":len(schema_raw),"sha256":sha256(schema_raw)},
        "contractArtifact":{"path":CONTRACT_PATH,"bytes":len(contract_raw),"sha256":sha256(contract_raw)},
        "checks":["EXACT_58_PATH_FENCE","STRICT_FIXED_CORPUS","EXACT_FIVE_TESTS","DOMAIN_WRITER_INTEGRATION_GUARDS","ATOMIC_FIRST_SIGN_PLACEMENT","DELETION_ERASE_NO_CASCADE","S10_ZERO_OVERLAP","DETERMINISTIC_GENERATION"]})
    evidence_raw=pretty(evidence)
    partial={SCHEMA_PATH:schema_raw,CONTRACT_PATH:contract_raw,EVIDENCE_PATH:evidence_raw}
    manifest_rows=[]
    for relative in MANIFEST_INPUT_PATHS:
        raw=partial.get(relative) or (root/relative).read_bytes()
        manifest_rows.append({"path":relative,"bytes":len(raw),"sha256":sha256(raw)})
    manifest=sealed({"schema":"V23P03C35ToolingManifestV1","schemaVersion":1,"authority":authority(),
        "pathFence":PATH_FENCE,"pathFenceCount":len(PATH_FENCE),"sourcePathCount":len(SOURCE_PATHS),
        "toolPathCount":len(TOOL_PATHS),"artifacts":manifest_rows,"artifactSetDigest":sha256(canonical(manifest_rows)),
        "evidenceIDs":EVIDENCE_IDS,"s10FenceOverlapPaths":[]})
    partial[MANIFEST_PATH]=pretty(manifest)
    return partial
