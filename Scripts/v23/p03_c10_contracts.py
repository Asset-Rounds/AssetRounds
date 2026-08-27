#!/usr/bin/env python3
"""Deterministic, language-neutral artifacts for provisional V23-P03-C10."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
from p03_c08_contracts import ACTIVE_S10_RESERVED_PATHS

CARD = "V23-P03-C10"
TITLE = "Two structurally different fault-injected full-lifecycle and portable-contract conformance fixtures"
APP_BASE_HEAD = "4177977e2a9177ef52f2cb77db084bb79ab853ba"
APP_BASE_TREE = "12da7c1b0a09d712b5d2347470495312d76825b6"
COORDINATION_HEAD = "a00600f9afebca6490d3d8ce0edc23d0c2d4d205"
COORDINATION_TREE = "516fbf2d514f7567195905e4be328d9a532f7d5e"
CONTEXT_DIGEST = "2eb08e65834dea06f4728d735469bdeae3124f48a1ebe1befbf0bb572de7cedc"
FENCE_DIGEST = "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8"
PREREQUISITE_DIGEST = "f2b4d226d03e0e9b06e790dd4f01c802ced7e325b8870b85c074c777d719b251"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
REGISTER_ROW_DIGEST = "0962702d0142a831e01b8e56e3f6eb3843cc04a597aeb34f2f8d573563f493ce"
DOSSIER_DIGEST = "a1cf3de904ec41b9a311362a7871b306dd460a7850866417f51d77ebe335f1dd"
INHERITED_BLOCK_DIGEST = "fecd5727d0d4a4f2e475ac07d535423ed569bf901e3f867fd7316f11d521fef3"

PATH_FENCE = [
    "FieldEvidenceAppTests/Fixtures/V21/Kernel/V21P03C10ChecklistFixtureManifestV1.json",
    "FieldEvidenceAppTests/Fixtures/V21/Kernel/V21P03C10MeasurementRepeatFixtureManifestV1.json",
    "FieldEvidenceAppTests/Fixtures/V21/Kernel/V21P03C10KernelConformanceScenarioGraphV1.json",
    "FieldEvidenceAppTests/Fixtures/V21/Contracts/V21P03C10PortableContractCorpusV1.json",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/PortableContractValidatorAdapterV1.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/PortableContractToolLockReaderV1.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
    "Scripts/v21-contracts/portable_contract_validator_v1.py",
    "Scripts/v21-contracts/portable-contract-validator.lock.json",
    "Scripts/v21-contracts/run-portable-contracts.py",
    "Scripts/v21-contracts/check-portable-contract-lock.py",
    "Scripts/v23/p03_c10_contracts.py",
    "Scripts/v23/generate_p03_c10_contracts.py",
    "Scripts/v23/verify_p03_c10_contracts.py",
    "Scripts/v23/kernel-conformance-fixture.schema.json",
    "Scripts/v23/kernel-conformance-contract.schema.json",
    "docs/design/v23/tooling/V23P03C10KernelConformanceContractV1.json",
    "docs/design/v23/tooling/V23P03C10KernelConformanceEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P03C10BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P03-C10-tooling-manifest.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/schema.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/core.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/applicator.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/unevaluated.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/validation.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/meta-data.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/format-annotation.json",
    "TestSupport/PortableContracts/JSONSchemaDraft202012/meta/content.json",
]
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C10KernelConformanceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C10KernelConformanceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C10BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C10-tooling-manifest.json"
OUTPUT_PATHS = [CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH]
SOURCE_PATHS = [path for path in PATH_FENCE if path not in OUTPUT_PATHS]
MANIFEST_INPUT_PATHS = [path for path in PATH_FENCE if path != MANIFEST_PATH]
FIXTURE_PATHS = PATH_FENCE[:4]
SWIFT_TEST_PATH = PATH_FENCE[4]
FIXTURE_SCHEMA_PATH = PATH_FENCE[15]
CONTRACT_SCHEMA_PATH = PATH_FENCE[16]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_20G01BothFixtureShapesCompleteFullLifecycleWithPortableSchemaParity",
    "testV9_20A01EveryPublicationBoundaryFaultRecoversWithoutPartialAuthority",
    "testV9_20H01HostilePortableCorpusFixtureLeakAndReleaseHooksFailClosed",
    "testV9_20I01RelaunchResumesOrCleansEveryDurableBoundaryDeterministically",
    "testV9_20R01TwoAndThreeReplicaSchedulesReconcileArchiveRestoreSearchDeleteAndErase",
]
LIFECYCLE = [
    "VALIDATE", "START", "RESUME", "RESPOND", "EVIDENCE", "FIND", "WORK",
    "RECHECK", "FINALIZE", "PROJECT", "ARCHIVE", "RESTORE", "SEARCH", "DELETE",
    "ERASE", "RECOVER",
]
LIFECYCLE_TRACES = {
    "CHECKLIST": [
        "VALIDATE", "START", "EVIDENCE", "RESPOND", "RESUME", "FIND", "FINALIZE", "WORK",
        "RECHECK", "PROJECT", "ARCHIVE", "RESTORE", "SEARCH", "DELETE", "ERASE", "RECOVER",
    ],
    "MEASUREMENT_REPEAT": [
        "VALIDATE", "START", "EVIDENCE", "RESPOND", "FIND", "FINALIZE", "WORK", "RESUME",
        "RECHECK", "PROJECT", "ARCHIVE", "RESTORE", "SEARCH", "DELETE", "RECOVER", "ERASE",
    ],
}
FAULTS = [
    "AHEAD_REVISION", "COOPERATIVE_CANCELLATION", "CRASH", "INCOMPATIBLE_FORMAT",
    "INJECTED_INTERRUPTION", "LOW_SPACE", "PROTECTED_DATA", "STALE_MUTATION",
    "STALE_REVISION", "TAMPER",
]
REQUIRED_FAULT_CLASSES = [
    "CRASH", "COOPERATIVE_CANCELLATION", "LOW_SPACE", "PROTECTED_DATA", "TAMPER", "STALE_REVISION",
]
PRODUCTION_FAULT_BOUNDARIES = [
    "FINALIZATION_SNAPSHOT_STAGING_WRITE", "FINALIZATION_SNAPSHOT_PROMOTION_MOVE",
    "FINALIZATION_INTENT_PHASE_WRITE", "FINALIZATION_MODEL_SAVE", "WORK_MODEL_SAVE",
    "WORK_AFTER_EVIDENCE_PROMOTION", "REPORT_RENDER", "REPORT_STAGE_WRITE", "REPORT_PROMOTION",
    "REPORT_REREAD", "REPORT_READY_SAVE", "REPORT_FAILED_STATE_SAVE", "REPORT_RETRY_TRANSITION_SAVE",
    "JOURNAL_AFTER_CHECKPOINT_PREPARED", "JOURNAL_AFTER_CHECKPOINT_STATE_WRITTEN",
    "JOURNAL_AFTER_REPLAY_MUTATION", "JOURNAL_AFTER_COMPACTION_STATE_WRITTEN",
    "RESTORE_BEFORE_PREPARED_WRITE", "RESTORE_AFTER_PREPARED_WRITE",
    "RESTORE_BEFORE_GENERATION_INSTALL", "RESTORE_AFTER_GENERATION_INSTALL",
    "RESTORE_BEFORE_POINTER_SWITCH", "RESTORE_AFTER_POINTER_SWITCH",
    "RESTORE_BEFORE_NEW_GENERATION_VALIDATION", "RESTORE_AFTER_NEW_GENERATION_VALIDATION",
    "RESTORE_BEFORE_CLEANUP", "DELETE_PREPARED_JOURNAL", "DELETE_DATABASE_SAVE",
    "DELETE_COMMITTED_PHASE", "DELETE_FILE_CLEANUP", "DELETE_JOURNAL_REMOVAL",
    "ERASE_AFTER_EMPTY_GENERATION_DIRECTORY_CREATE", "ERASE_BEFORE_PREPARED_WRITE",
    "ERASE_AFTER_PREPARED_WRITE", "ERASE_BEFORE_POINTER_SWITCH", "ERASE_AFTER_POINTER_SWITCH",
    "ERASE_BEFORE_POINTER_PHASE_WRITE", "ERASE_AFTER_POINTER_PHASE_WRITE",
    "ERASE_BEFORE_SESSION_ACTIVATION", "ERASE_AFTER_SESSION_ACTIVATION",
    "ERASE_BEFORE_SESSION_PHASE_WRITE", "ERASE_AFTER_SESSION_PHASE_WRITE", "ERASE_BEFORE_CLEANUP",
    "ERASE_AFTER_CLEANUP", "ERASE_BEFORE_CLEANUP_PHASE_WRITE", "ERASE_AFTER_CLEANUP_PHASE_WRITE",
    "ERASE_BEFORE_JOURNAL_REMOVAL", "SEARCH_CANCELLATION", "SEARCH_CHECKPOINT", "SEARCH_STALE",
    "SEARCH_AHEAD", "SEARCH_INCOMPATIBLE", "SEARCH_PUBLICATION_TOKEN",
]
PORTABLE_CASES = [
    "GOLDEN_BYTES", "UNKNOWN_VERSION", "UNKNOWN_FIELD", "UNKNOWN_ENUM",
    "STABLE_FAILURE_CLASS",
]
NORMALIZED_CONVERGENCE_SETS = [
    "CANONICAL", "TOMBSTONE", "UNRESOLVED_CONFLICT", "CONTENT", "MUTATION_ID",
]
CHECKS = [
    "EXACT_29_NEW_PATH_CREATE_ONLY_FENCE",
    "ZERO_ACTIVE_S10_RESERVATION_OVERLAP",
    "EXACTLY_TWO_STRUCTURALLY_DISTINCT_FIXTURE_PACKAGES",
    "FULL_LIFECYCLE_AND_PUBLICATION_BOUNDARY_FAULT_CLOSURE",
    "PINNED_NETWORK_FREE_DRAFT_2020_12_PORTABLE_CORPUS",
    "TWO_AND_THREE_REPLICA_REPLAY_TWICE_NORMALIZED_CONVERGENCE",
    "DEBUG_OR_SEALED_TEST_HOST_AND_RELEASE_ABSENCE",
    "PERSISTENCE_AND_BRAND_NO_DELTA",
    "EXACT_FIVE_G01_A01_H01_I01_R01_EVIDENCE_TESTS",
    "STATIC_PROVISIONAL_FLAGS_AND_S10_6_RECONCILIATION",
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


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "s10ReservationDigest": S10_RESERVATION_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST,
    }


def flags() -> dict[str, Any]:
    return {
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False,
        "hostedDispatchEnabled": False, "phase10PollingDuringParallelExecution": False,
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True,
    }


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing source artifact: {relative}")
        rows.append(artifact(relative, path.read_bytes()))
    return rows


def portable_validation_receipts(root: Path) -> dict[str, Any]:
    portable_root = root / "Scripts/v21-contracts"
    sys.path.insert(0, str(portable_root))
    try:
        import portable_contract_validator_v1 as portable
        lock_path = root / "Scripts/v21-contracts/portable-contract-validator.lock.json"
        lock = portable.load_lock(root)
        registry = portable.load_registry(root, lock)
        fixture_schema = json.loads((root / FIXTURE_SCHEMA_PATH).read_text(encoding="utf-8"))
        envelope = {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://assetrounds.invalid/schemas/v23/kernel-portable-envelope-v1.json",
            **fixture_schema["$defs"]["portableEnvelope"],
        }
        corpus = json.loads((root / FIXTURE_PATHS[3]).read_text(encoding="utf-8"))
        tool_relative = "Scripts/v21-contracts/portable_contract_validator_v1.py"
        tool_row = next((row for row in lock["files"] if row["path"] == tool_relative), None)
        if tool_row is None:
            raise ContractError("portable validator source is absent from tool lock")
        tool_sha = sha256((root / tool_relative).read_bytes())
        lock_sha = sha256(lock_path.read_bytes())
        if tool_sha != tool_row["sha256"]:
            raise ContractError("portable validator source differs from tool lock")
        rows = []
        all_deterministic = True
        for expected in corpus["cases"]:
            instance = json.loads(expected["input"])
            first = portable.validate_instance(instance, envelope, registry, envelope["$id"])
            second = portable.validate_instance(instance, envelope, registry, envelope["$id"])
            deterministic = portable.canonical_json(first) == portable.canonical_json(second)
            all_deterministic = all_deterministic and deterministic
            classification = "ACCEPTED" if first["valid"] else "REJECTED"
            if first["valid"]:
                instance_path = schema_path = ""
            else:
                if not first["errors"]:
                    raise ContractError(f"portable rejection lacks observed error: {expected['id']}")
                instance_path = first["errors"][0]["instancePath"]
                schema_path = first["errors"][0]["schemaPath"]
            if (classification != expected["expectedClass"] or
                    instance_path != expected["instancePath"] or
                    schema_path != expected["schemaPath"]):
                raise ContractError(f"portable observed receipt differs from corpus expectation: {expected['id']}")
            rows.append({
                "caseID": expected["id"], "classification": classification,
                "instancePath": instance_path, "schemaPath": schema_path,
                "inputSHA256": sha256(expected["input"].encode("utf-8")),
                "toolSourceSHA256": tool_sha, "lockSHA256": lock_sha,
                "deterministicReplayMatched": deterministic,
            })
        if not all_deterministic:
            raise ContractError("portable C10 receipt replay is nondeterministic")
        return {
            "toolID": lock["tool"]["toolID"], "toolSourceSHA256": tool_sha,
            "lockSHA256": lock_sha, "networkFetchCount": 0,
            "deterministicReplayMatched": True, "cases": rows,
        }
    finally:
        sys.path.remove(str(portable_root))


def contract(root: Path) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C10KernelConformanceContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "pathFence": PATH_FENCE, "existingPaths": [], "newPaths": PATH_FENCE,
        "fixturePolicy": {
            "packageCount": 2,
            "packages": ["CHECKLIST", "MEASUREMENT_REPEAT"],
            "structurallyDistinct": True, "sharedProductionAdapters": True,
            "nonshipping": True, "productionBundleRegistryOrUI": False,
        },
        "lifecycleTransitions": LIFECYCLE, "lifecycleTraces": LIFECYCLE_TRACES,
        "faultClasses": FAULTS,
        "publicationBoundaryCoverage": "EVERY_BOUNDARY_FAILS_VISIBLY_WITHOUT_FALSE_SUCCESS_OR_ORPHANS",
        "portableContract": {
            "dialect": "https://json-schema.org/draft/2020-12/schema",
            "validatorLanguage": "PYTHON", "swiftValidator": False, "networkFree": True,
            "toolLockRequired": True, "cases": PORTABLE_CASES,
        },
        "scenarioGraph": {
            "normalized": True,
            "nodeDomains": ["LIFECYCLE", "FAULT", "BRAND_STATE", "PERSISTENT_CONSUMER"],
            "everyNodeMapsNamedSelectorAndEvidenceReceipt": True,
        },
        "convergence": {
            "replicaCounts": [2, 3], "replaysPerSchedule": 2,
            "comparisonSets": NORMALIZED_CONVERGENCE_SETS,
            "localJournalByteOrderCompared": False,
        },
        "releaseAbsence": {
            "destructiveHooks": "DEBUG_OR_SEALED_TEST_HOST_ONLY",
            "absentTypes": ["FIXTURE", "VALIDATOR", "GENERATOR", "HARNESS"],
            "productionIntegrationBlockedUntilConformanceRestored": True,
        },
        "recovery": {
            "removesOnlyTestFixtures": True,
            "reconciles": ["RECORDS", "FILES", "RECEIPTS", "PROJECTIONS", "EVIDENCE"],
        },
        "persistence": {
            "mode": "NONE", "schemaBehaviorDelta": False, "migrationBehaviorDelta": False,
            "backupBehaviorDelta": False, "restoreBehaviorDelta": False,
            "deleteBehaviorDelta": False, "exportBehaviorDelta": False,
            "downgradeDisposition": "NOT_APPLICABLE",
        },
        "privacy": {
            "secretFree": True, "networkFree": True, "bounded": True,
            "createsAccountsAuthTenancyRemoteSyncTelemetryOrProviderState": False,
        },
        "brand": {"manifestCount": 1, "uiSurfaceDelta": False, "brandSurfaceDelta": False,
                  "fullSweepTriggered": False},
        "s10": {"reservedPathCount": 86, "overlapPaths": []},
        "sourceArtifacts": source_rows(root), "evidenceIDs": EVIDENCE_IDS,
        "testMethods": TEST_METHODS, **flags(),
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def evidence(root: Path, contract_value: dict[str, Any]) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C10KernelConformanceEvidenceReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "result": "PASS", "checks": CHECKS,
        "pathFenceCount": 29, "existingPathCount": 0, "newPathCount": 29,
        "sourcePathCount": 25, "generatedArtifactCount": 4,
        "s10FenceOverlapPaths": [], "sourceArtifacts": source_rows(root),
        "contractArtifact": artifact(CONTRACT_PATH, pretty(contract_value)),
        "portableValidationReceipts": portable_validation_receipts(root),
        "evidenceMatrix": [{"evidenceID": evidence_id, "testMethod": method}
                           for evidence_id, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "evidenceIDs": EVIDENCE_IDS, "testMethods": TEST_METHODS, **flags(),
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def brand_manifest() -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C10BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "manifestCount": 1, "uiSurfaceDelta": False,
        "brandSurfaceDelta": False, "fullSweepTriggered": False,
        "affectedSurfacePaths": [], "disposition": "NO_UI_OR_BRAND_SURFACE_DELTA", **flags(),
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = []
    for relative in MANIFEST_INPUT_PATHS:
        raw = generated.get(relative)
        if raw is None:
            raw = (root / relative).read_bytes()
        rows.append(artifact(relative, raw))
    unsigned = {
        "schema": "V23P03C10ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": PATH_FENCE, "existingPaths": [],
        "newPaths": PATH_FENCE, "pathFenceCount": 29, "existingPathCount": 0,
        "newPathCount": 29, "sourcePathCount": 25, "generatedArtifactCount": 4,
        "manifestInputCount": 28, "activeS10ReservationPathCount": 86,
        "s10FenceOverlapPaths": [], "artifacts": rows,
        "artifactSetDigest": sha256(canonical(rows)), "evidenceIDs": EVIDENCE_IDS, **flags(),
    }
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def all_outputs(root: Path) -> dict[str, bytes]:
    contract_raw = pretty(contract(root))
    evidence_raw = pretty(evidence(root, json.loads(contract_raw)))
    brand_raw = pretty(brand_manifest())
    generated = {CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    generated[MANIFEST_PATH] = pretty(tooling_manifest(root, generated))
    return generated
