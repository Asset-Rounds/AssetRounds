#!/usr/bin/env python3
"""Deterministic provisional artifacts for V23-P03-C12."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C12"
TITLE = "RequirementEvaluationV1, explainable completion/site-exit gate, and deterministic integrity findings"
APP_BASE_HEAD = "3777bfc1b7800f808871337ddec533f171a6dc39"
APP_BASE_TREE = "d3b22a2116f16c693c57d590ed9361dc93fe5e78"
CONTEXT_DIGEST = "6f225b50a731e06f6dbd16622d86e6ebe145e3f53bec11ad654d4425f4a0619d"
FENCE_DIGEST = "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806"
PREREQUISITE_DIGEST = "445ad57928d6fd8b767757f0b071cf3e2ca23071216174fad36a0510f890be07"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
REGISTER_ROW_DIGEST = "ccec2b3a7fddcaa1746c237554b2ede58d0d2c66d8e1edc1e8edd78fc70cfa33"
DOSSIER_DIGEST = "fdb4ff81d6cfd6a5f506bb6d0283c52853dc8d0d51039a9d6df840ace6d742e1"
INHERITED_BLOCK_DIGEST = "63680446745dde0a41148beb68bf972c210aeda1a898d67bf93965bbd3119b4a"

PATH_FENCE = [
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationEngineV1.swift",
    "FieldEvidenceApp/Domain/Models/RequirementAssurancePersistenceModelsV1.swift",
    "FieldEvidenceAppTests/V9_21RequirementAssuranceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Requirements/V21P03C12RequirementAssuranceCorpusV1.json",
    "Scripts/v23/p03_c12_contracts.py",
    "Scripts/v23/generate_p03_c12_contracts.py",
    "Scripts/v23/verify_p03_c12_contracts.py",
    "Scripts/v23/requirement-assurance.schema.json",
    "docs/design/v23/tooling/V23P03C12RequirementAssuranceContractV1.json",
    "docs/design/v23/tooling/V23P03C12RequirementAssuranceEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P03C12BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P03-C12-tooling-manifest.json",
    "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportCorrectionRule.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_08GenerationLeaseTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
]
NEW_PATHS = PATH_FENCE[:13]
EXISTING_PATHS = PATH_FENCE[13:]
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C12RequirementAssuranceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C12RequirementAssuranceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C12BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C12-tooling-manifest.json"
OUTPUT_PATHS = [CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH]
SOURCE_PATHS = [path for path in PATH_FENCE if path not in OUTPUT_PATHS]
MANIFEST_INPUT_PATHS = [path for path in PATH_FENCE if path != MANIFEST_PATH]
SWIFT_TEST_PATH = "FieldEvidenceAppTests/V9_21RequirementAssuranceTests.swift"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/Requirements/V21P03C12RequirementAssuranceCorpusV1.json"
SCHEMA_PATH = "Scripts/v23/requirement-assurance.schema.json"

# Isolated until the Swift test source is frozen. The verifier requires these
# exact five methods once populated and rejects any sixth G/A/H/I/R selector.
TEST_METHODS = [
    "testV9_21G01RequirementEvaluationGoldenMatrixAndSiteExitDecision",
    "testV9_21A01WarningNotApplicableAndReasonedWaiverRemainExplainable",
    "testV9_21H01StaleOrphanDuplicateContradictoryAndBypassInputsFailClosed",
    "testV9_21I01InterruptedRebuildPreservesPriorAcceptedRevisionOrNoProjection",
    "testV9_21R01CanonicalRebuildAndLifecycleRoundTripAreDeterministic",
]
EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
RESULTS = ["SATISFIED", "NOT_SATISFIED", "NOT_APPLICABLE", "UNKNOWN", "WAIVED"]
REASON_CODES = [
    "REQUIREMENT_SATISFIED", "RESPONSE_NOT_SATISFIED", "NOT_APPLICABLE_ACCEPTED",
    "NOT_APPLICABLE_NOT_ALLOWED", "UNKNOWN_RESPONSE", "UNANSWERED_REQUIREMENT",
    "REQUIRED_EVIDENCE_MISSING", "EVIDENCE_INVALID", "EVIDENCE_DUPLICATED",
    "EVIDENCE_CONTRADICTORY", "WAIVER_ACCEPTED", "WAIVER_NOT_ALLOWED",
    "WAIVER_REASON_NOT_ALLOWED", "WAIVER_REVISION_MISMATCH", "WAIVER_SCOPE_MISMATCH",
]
CHECKS = [
    "EXACT_50_PATH_FENCE_AND_ZERO_S10_OVERLAP",
    "REQUIREMENT_ASSURANCE_V8_RECORDS7_SCHEMA_MIGRATION_AND_LIFECYCLE_CLOSURE",
    "ONE_CANONICAL_WRITER_MUTATION_RECEIPT_AND_C11_REPLAY_CLOSURE",
    "BACKUP_RESTORE_DELETE_ERASE_REPORT_AND_PROVISIONAL_CODEC_CLOSURE",
    "EXACT_FIVE_G01_A01_H01_I01_R01_STATIC_TEST_SELECTORS",
    "NO_FIFTH_SEARCH_ROOT_OPAQUE_SCORE_OR_WAIVER_BYPASS",
    "NO_UNREACHABLE_UI_ARTIFACT_AND_RELEASE_TEST_HOOK_ABSENCE",
    "STATIC_ONLY_NO_CREDIT_FLAGS_AND_S10_6_RECONCILIATION",
]


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def artifact(path: str, raw: bytes) -> dict[str, Any]:
    return {"path": path, "bytes": len(raw), "sha256": sha256(raw)}


def seal(unsigned: dict[str, Any]) -> dict[str, Any]:
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "s10ReservationDigest": S10_RESERVATION_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST,
    }


def flags() -> dict[str, Any]:
    return {
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False,
        "hostedDispatchEnabled": False, "hostedDispatchRan": False,
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing source artifact: {relative}")
        rows.append(artifact(relative, path.read_bytes()))
    return rows


def contract(root: Path) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C12RequirementAssuranceContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "pathFence": PATH_FENCE, "existingPaths": EXISTING_PATHS, "newPaths": NEW_PATHS,
        "persistentContract": {
            "schemaID": "RequirementAssuranceSchemaV1", "activeStoreSchemaVersion": 8,
            "releasedRecordSchemaVersion": 7, "mode": "NEW_SCHEMA_VERSION",
            "migrationRequired": True, "oneCanonicalWriterRequired": True,
            "mutationReceiptRequired": True, "c11ReplayRequired": True,
            "backupRestoreRequired": True, "deleteEraseRequired": True,
            "exportReportRequired": True,
            "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
        },
        "evaluation": {
            "results": RESULTS, "stableReasonCodes": REASON_CODES,
            "binds": ["REQUIREMENT_ID", "REQUIREMENT_VERSION", "POLICY_VERSION",
                      "EVALUATED_CANONICAL_REVISION", "EVIDENCE_REFERENCES"],
            "deterministic": True, "sideEffectFree": True, "languageIndependent": True,
            "opaqueAggregateScoreAllowed": False, "automaticRepairAllowed": False,
        },
        "siteExit": {
            "classes": ["HARD_BLOCKER", "WARNING", "NOT_APPLICABLE", "UNKNOWN", "WAIVER"],
            "waiverRequires": ["ALLOWED_REASON", "ACTOR_REFERENCE", "SCOPE", "EXACT_REVISION"],
            "bypassAllowed": False,
        },
        "integrityFindings": ["UNANSWERED_REQUIREMENT", "REQUIRED_EVIDENCE", "ORPHAN_REFERENCE",
                              "DUPLICATE_REFERENCE", "CONTRADICTORY_EVIDENCE", "INVALID_STATE",
                              "SNAPSHOT_REPORT_DIVERGENCE"],
        "recovery": {
            "interruptedRebuildPublishesPartial": False,
            "permittedPostInterruptionState": "PRIOR_ACCEPTED_REVISION_OR_NO_PROJECTION",
            "canonicalRebuildInputs": ["RESPONSES", "EVIDENCE", "POLICY", "REVISION"],
            "byteIdenticalRepeatRequired": True,
        },
        "lifecycleClosure": ["MIGRATION", "CANONICAL_WRITE", "MUTATION_RECEIPT", "C11_REPLAY",
                             "BACKUP", "RESTORE", "DELETE", "ERASE", "EXPORT", "REPORT_CODEC"],
        "search": {"newSearchRootCount": 0, "fifthSearchRootAllowed": False},
        "provisionalReachability": {
            "siteExitUIReachability": "NOT_RUN_NO_CREDIT_S10_RESERVED",
            "accessibility": "NOT_RUN_NO_CREDIT_S10_RESERVED",
            "universalFinalizationReachability": "NOT_PROVEN_S10_RESERVED",
            "completedSnapshotReachability": "NOT_PROVEN_S10_RESERVED",
            "codec": "PROVISIONAL_NONRELEASE_ONLY",
        },
        "releaseAbsence": {"testHooksInReleaseAllowed": False, "unreachableUIArtifactAllowed": False},
        "brand": {"manifestCount": 1, "uiSurfaceDelta": False, "brandSurfaceDelta": False,
                  "disposition": "NO_CURRENT_SHIPPING_UI_OR_BRAND_DELTA"},
        "s10": {"reservedPathCount": 86, "overlapPaths": []},
        "evidenceIDs": EVIDENCE_IDS, "testMethods": TEST_METHODS,
        "sourceArtifacts": source_rows(root), **flags(),
    }
    return seal(unsigned)


def evidence(root: Path, contract_value: dict[str, Any]) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C12RequirementAssuranceEvidenceReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "result": "PASS_STATIC_PROVISIONAL",
        "checks": CHECKS, "pathFenceCount": 50, "existingPathCount": 37, "newPathCount": 13,
        "sourcePathCount": 46, "generatedArtifactCount": 4, "s10FenceOverlapPaths": [],
        "sourceArtifacts": source_rows(root), "contractArtifact": artifact(CONTRACT_PATH, pretty(contract_value)),
        "evidenceMatrix": [{"evidenceID": evidence_id, "testMethod": method}
                           for evidence_id, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "siteExitUIReachability": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        "accessibility": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        "universalFinalizationReachability": "NOT_PROVEN_S10_RESERVED",
        "completedSnapshotReachability": "NOT_PROVEN_S10_RESERVED",
        "codec": "PROVISIONAL_NONRELEASE_ONLY",
        "evidenceIDs": EVIDENCE_IDS, "testMethods": TEST_METHODS, **flags(),
    }
    return seal(unsigned)


def brand_manifest() -> dict[str, Any]:
    return seal({
        "schema": "V23P03C12BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "manifestCount": 1, "uiSurfaceDelta": False,
        "brandSurfaceDelta": False, "fullSweepTriggered": False, "affectedSurfacePaths": [],
        "disposition": "NO_CURRENT_SHIPPING_UI_OR_BRAND_DELTA",
        "siteExitUIReachability": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        "accessibility": "NOT_RUN_NO_CREDIT_S10_RESERVED", **flags(),
    })


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = []
    for relative in MANIFEST_INPUT_PATHS:
        raw = generated.get(relative)
        if raw is None:
            raw = (root / relative).read_bytes()
        rows.append(artifact(relative, raw))
    return seal({
        "schema": "V23P03C12ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": PATH_FENCE, "existingPaths": EXISTING_PATHS,
        "newPaths": NEW_PATHS, "pathFenceCount": 50, "existingPathCount": 37,
        "newPathCount": 13, "sourcePathCount": 46, "generatedArtifactCount": 4,
        "manifestInputCount": 49, "activeS10ReservationPathCount": 86,
        "s10FenceOverlapPaths": [], "artifacts": rows,
        "artifactSetDigest": sha256(canonical(rows)), "evidenceIDs": EVIDENCE_IDS, **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    contract_raw = pretty(contract(root))
    evidence_raw = pretty(evidence(root, json.loads(contract_raw)))
    brand_raw = pretty(brand_manifest())
    generated = {CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    generated[MANIFEST_PATH] = pretty(tooling_manifest(root, generated))
    return generated
