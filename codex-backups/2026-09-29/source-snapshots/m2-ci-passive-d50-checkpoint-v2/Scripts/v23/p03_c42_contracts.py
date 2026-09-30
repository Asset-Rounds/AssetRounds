#!/usr/bin/env python3
"""Deterministic nonshipping TestSupport tooling model for V23-P03-C42."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C42"
TITLE = "Deterministic cross-market archetype, model-based state, codec, interruption, and Release-exclusion conformance corpus"
REGISTER_ORDINAL = 70
BASE_HEAD = "0ef5a09d9255a3f633bf7506de49ba9d564619f1"
BASE_TREE = "3e7970fbde803e7d485b2eb8d789c0d032aa5f1f"
COORDINATION_HEAD = "bc21e4f468dca4ba2ef32430a897270fbe4ed72d"
COORDINATION_TREE = "de17cc0002ea6b41c98c910f86781b06c1012289"
COORDINATION_CAS_SEQUENCE = 298
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "cb2720d424ec94999332fd6df38ebd0a0fbf6b94f0fdca98fa12ab34faa5057d"
CONTEXT_DIGEST = "33147aa41417cdb6adeba7aa2be91f50b4346d9b15546cba96b8ac03ce6e1770"
FENCE_DIGEST = "0d3fd318d75b5dc512ee7d9d2152118b3a2fb5cbc83cd666029126fa519271dd"
HYDRATION_TRANSITION_DIGEST = "402d18960a017697808c032257a00e768c0bd95fae17f5ab087631e27a9c8eb8"
COORDINATION_LEDGER_DIGEST = "9124ffb600d58ee77f8ea4eb2fc83e6ce32e918b1fe80ebc1a95f8ab7b1598f2"
COORDINATION_PROJECTION_DIGEST = "8833695ad009cc2a6db4bee4511f4dac8eb086178096fc48c9ece36d93bcf3d4"
AUTHORIZED_OVERLAP_COUNT = 306
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/cross-market-conformance.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C42CrossMarketConformanceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C42CrossMarketConformanceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C42BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C42-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c42_contracts.py",
    "Scripts/v23/generate_p03_c42_contracts.py",
    "Scripts/v23/verify_p03_c42_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
EXISTING_PATHS = (
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/PortableContractValidatorAdapterV1.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/PortableContractToolLockReaderV1.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/CompatibilityCorpusSupportV1.swift",
    "FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
    "FieldEvidenceAppTests/S4_4HistoryComparisonTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift",
    "FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift",
)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/CompositeAreaSafetyArchetypeV1.swift",
    "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/ControllerZoneDistributionArchetypeV1.swift",
    "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/ModelBasedConformanceContractsV1.swift",
    "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/ReleaseExclusionReceiptV1.swift",
    "FieldEvidenceAppTests/V9_47CrossMarketConformanceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/CrossMarketConformance/V22P03C42CrossMarketConformanceCorpusV1.json",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "CompositeAreaSafetyArchetypeV1",
    "ControllerZoneDistributionArchetypeV1",
    "ModelOperationV1",
    "ModelRunReceiptV1",
    "DeterministicRegressionPromotionReceiptV1",
    "ReleaseExclusionReceiptV1",
)
TEST_METHODS = (
    "testV23P03C42G01BothArchetypesCompleteOfflineSharedKernelJourney",
    "testV23P03C42A01FixedSeedModelRunsAreByteIdenticalAndBounded",
    "testV23P03C42H01HostileCorpusAndReleaseLeakageFailClosed",
    "testV23P03C42I01EveryStagedBoundaryConvergesAfterInterruption",
    "testV23P03C42R01PromotedCounterexamplesReplayAndReleaseExclusionRemainsExact",
)
FLAGS = {key: False for key in (
    "native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance",
    "hostedAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness",
    "phase10PollingDuringParallelExecution",
)}
PERSISTENCE: dict[str, Any] = {
    "mode": "NONPERSISTENT_TESTSUPPORT_ONLY",
    "persistentSchemaVersion": None,
    "recordsSchemaVersion": None,
    "persistentKindLifecycleModelCount": 0,
    "durableFamilyCount": 0,
    "persistedFamilies": [],
    "productSchemaBehaviorDelta": False,
    "productBackupRecordDelta": False,
    "generatedScratchDisposition": "BOUNDED_AND_REMOVED_AFTER_RUN",
    "fixtureDisposition": "IMMUTABLE_VERSIONED_TEST_INPUT_APPEND_ONLY",
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_paths(root: Path, *args: str) -> set[str]:
    output = subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout
    return {path.replace("\\", "/") for path in output.splitlines() if path}


def observed_changed_paths(root: Path) -> set[str]:
    changed = _git_paths(root, "diff", "--name-only", f"{BASE_HEAD}..HEAD", "--")
    changed |= _git_paths(root, "diff", "--name-only", "--")
    changed |= _git_paths(root, "diff", "--cached", "--name-only", "--")
    changed |= _git_paths(root, "ls-files", "--others", "--exclude-standard")
    return changed


def _base_exists(root: Path, path: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{path}"], capture_output=True).returncode == 0


def _tokens(root: Path, path: str, *tokens: str) -> str:
    target = root / path
    if not target.is_file():
        raise ValueError(f"C42 source absent:{path}")
    text = target.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"C42 source regression:{path}:" + ",".join(missing))
    return text


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / "FieldEvidenceAppTests/V9_47CrossMarketConformanceTests.swift"
    if not path.is_file():
        return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C42(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def require_source_ready(root: Path) -> None:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    if missing:
        raise ValueError("C42 stable TestSupport source absent:" + ",".join(missing))
    selectors = observed_selectors(root)
    if selectors != TEST_METHODS:
        raise ValueError("C42 exact ordered G/A/H/I/R selectors differ")


def assert_source_regressions(root: Path) -> None:
    require_source_ready(root)
    composite = _tokens(
        root, IMPLEMENTATION_PATHS[0], "CompositeAreaSafetyArchetypeV1", ".site", ".locationNode",
        ".assetCompositionEvent", ".requirementBasisBinding", ".findingClassificationBinding",
        ".correctiveActionEvent", ".signoffSnapshot", ".report", ".siteLocationCompositionArea",
        ".criterionConflict", ".findingCorrectiveRecheck", ".attributionSignoff", ".reportProjection",
    )
    controller = _tokens(
        root, IMPLEMENTATION_PATHS[1], "ControllerZoneDistributionArchetypeV1",
        ".functionalRelationshipTypeDescriptor", ".assetFunctionalRelationshipEvent",
        ".scheduleDefinitionRelease", ".occurrenceHistoryEvent", ".lightingMeasurementPlan",
        ".measurementCapture", ".measurementQualityAssessment", ".lightingClaimState",
        ".controllerZoneTopology", ".preventiveMaintenance", ".exactMeasurement",
        ".sharedComponent", ".boundedCardinality",
    )
    forbidden_market = re.compile(r"\b(playground|park|irrigation|water[- ]?management)\b", re.IGNORECASE)
    if forbidden_market.search(composite) or forbidden_market.search(controller):
        raise ValueError("C42 forbidden future-market wording leaked")
    model = _tokens(
        root, IMPLEMENTATION_PATHS[2], *CONTRACT_NAMES[2:5], "seed", "generatorVersion", "operations",
        "preconditionRejectionCount", "minimizedCounterexample", "expectedInvariant",
        "maximumScratchBytes", "maximumDurationMilliseconds", "maximumCases", "maximumShrinkSteps",
        "validate", "canonical",
    )
    if "while true" in model or "Int.random" in model or "UUID()" in model or "Date()" in model:
        raise ValueError("C42 nondeterministic or unbounded model generator surfaced")
    _tokens(
        root, IMPLEMENTATION_PATHS[3], "ReleaseExclusionReceiptV1", "sourceMembership", "targetDependencyGraph",
        "compiledArchive", "bundleResources", "localization", "packageRegistry", "routeRegistry",
        "settingsRegistry", "publicSymbols", "publicStrings", "screenshots", "appStoreDrafts",
        "runtimeSurface", "TestSupport", "validate",
    )
    tests = _tokens(root, IMPLEMENTATION_PATHS[4], *TEST_METHODS)
    for token in (
        "Unicode", "RTL", "DST", "timeZone", "UNKNOWN", "stale", "cycle", "cardinality", "qualification",
        "productIdentity", "clone", "fork", "lowStorage", "symlink", "decompression", "tamper", "relaunch",
        "recovery", "historic", "Release",
    ):
        if token.lower() not in tests.lower():
            raise ValueError("C42 hostile/interruption coverage regressed:" + token)
    corpus = json.loads((root / IMPLEMENTATION_PATHS[5]).read_text(encoding="utf-8"))
    if corpus.get("schema") != "V22P03C42CrossMarketConformanceCorpusV1":
        raise ValueError("C42 corpus schema differs")
    if corpus.get("archetypes") != ["CompositeAreaSafetyArchetypeV1", "ControllerZoneDistributionArchetypeV1"]:
        raise ValueError("C42 exact two-archetype corpus differs")
    if not corpus.get("promotedCounterexamples") or not corpus.get("hostileCases"):
        raise ValueError("C42 deterministic hostile/promoted corpus absent")
    for path in EXISTING_PATHS:
        if not (root / path).is_file():
            raise ValueError(f"C42 existing TestSupport owner absent:{path}")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (21, 14, 35) or len(set(PATH_FENCE)) != 35:
        raise ValueError("C42 fence must be unique 35=21+14")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C42 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C42 base tree differs")
    for path in EXISTING_PATHS:
        if not _base_exists(root, path):
            raise ValueError(f"C42 existing path absent at base:{path}")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"C42 new path existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 306 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C42 authority/status proof differs")
    if PERSISTENCE["durableFamilyCount"] != 0 or PERSISTENCE["persistentKindLifecycleModelCount"] != 0:
        raise ValueError("C42 must remain nonpersistent")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE,
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION, "prerequisiteDigest": PREREQUISITE_DIGEST,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": 35, "existingPathCount": 21, "newPathCount": 14,
        "authorizedOverlapCount": 306, "unauthorizedOverlapCount": 0,
        "directPrerequisiteCards": ["V23-P03-C10"], "nextCard": "V23-P03-C32",
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value))}


def schema_document() -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/cross-market-conformance.schema.json",
        "title": "V23 P03 C42 Cross-Market Conformance Corpus",
        "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C42CrossMarketConformanceCorpusV1"},
            "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
            "archetypes": {"const": ["CompositeAreaSafetyArchetypeV1", "ControllerZoneDistributionArchetypeV1"]},
            "modelBounds": {"type": "object"}, "hostileCases": {"type": "array", "minItems": 1},
            "promotedCounterexamples": {"type": "array", "minItems": 1},
        },
        "required": ["schema", "schemaVersion", "cardID", "archetypes", "modelBounds", "hostileCases", "promotedCounterexamples"],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    semantics = {
        "contractNames": list(CONTRACT_NAMES), "fiveSelectors": list(observed_selectors(root)),
        "exactTwoSyntheticNonshippingArchetypes": True, "acceptedSharedKernelOnly": True,
        "fixedSeedByteIdenticalOperationSequence": True, "boundedModelAndShrink": True,
        "randomOnlySuccessCannotAccept": True, "counterexamplePromotionIsImmutable": True,
        "isolatedCodecMigrationAndLifecycleCopies": True, "noProductStoreMutation": True,
        "releaseExclusionSurfaceEnumerationExact": True, "customerAndLicensedDataForbidden": True,
        "futureMarketVocabularyForbidden": True, "productionDependencyForbidden": True,
    }
    return _sealed({"schema": "V23P03C42CrossMarketConformanceContractV1", "schemaVersion": 1,
                    "authority": authority(), "persistence": PERSISTENCE, "requiredSemantics": semantics})


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    return _sealed({
        "schema": "V23P03C42CrossMarketConformanceEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "evidenceIDs": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")],
        "testSelectors": list(observed_selectors(root)),
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
        "releaseExclusion": {"sourceMembership": "STATIC_REQUIRED", "targetDependencyGraph": "STATIC_REQUIRED",
                             "compiledArchive": "NOT_RUN", "runtimeEnumeration": "NOT_RUN"},
        "statusFlags": FLAGS,
    })


def brand_document() -> dict[str, Any]:
    return _sealed({"schema": "V23P03C42BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
                    "uiSurfaceDelta": False, "brandSurfaceDelta": False, "publicScreenshots": False,
                    "nativeIPadSurface": False, "telemetry": False, "statusFlags": FLAGS})


def _row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    raw = rendered[path] if path in rendered else (root / path).read_bytes()
    return {"path": path, "sha256": sha256_bytes(raw), "byteCount": len(raw)}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    rendered = {
        SCHEMA_PATH: pretty(schema_document()), CONTRACT_PATH: pretty(contract_document(root)),
        EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document()),
    }
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "schema": "V23P03C42ToolingManifestV1", "schemaVersion": 1, "authority": authority(),
        "pathFence": list(PATH_FENCE), "pathFenceCount": 35, "existingPathCount": 21, "newPathCount": 14,
        "authorizedOverlapCount": 306, "unauthorizedOverlapCount": 0, "artifacts": rows,
        "artifactSetDigest": sha256_value(rows), "statusFlags": FLAGS,
    }))
    return rendered
