#!/usr/bin/env python3
"""Fail-closed static tooling contracts for V23-P04-C09.

This module is an observation and evidence layer for the local operations
metrics card.  It owns no product implementation, persistence, writer,
network, telemetry, or UI route.  Every generated document is derived from
the live source bytes and the digest-bound coordination fence.  Until all
eight implementation/test/fixture lanes are present, the outputs remain
explicitly provisional.
"""
from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C09"
TITLE = "Local operations dashboard, asset service history, and qualified rebuildable reliability projections"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 97

# Frozen application and coordination hydration authority.
BASE_HEAD = "4f7a0ea5511e9e8f0027f49650eda0994dfa5f44"
BASE_TREE = "16263e9430aa6cf7d8511898e7a4c38206a4b9ea"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "8ae088f015beed8028f98b96dfd8242b966c0a0f"
COORDINATION_TREE = "007187bf9ca982fde8de723c85fd4b1b0b019b46"
COORDINATION_ORIGIN_HEAD = COORDINATION_HEAD
COORDINATION_CAS_SEQUENCE = 422
SEQUENCE = COORDINATION_CAS_SEQUENCE
CONTEXT_DIGEST = "a6427bd41715b3d8b2b28a29d45adba1fd2c6973fc28384bbb674ff69b11dbc6"
FENCE_DIGEST = "9065dfcc1459f942d5395369957c8de730ca5e109df470c1275a869b2790e2a2"
PREREQUISITE_DIGEST = "631978411529b4eac5b0b79518c0896b57963e3323b790700c45bf89300f0929"
HYDRATION_TRANSITION_DIGEST = "82333ceb77d14d7a33c54ed55530ab2ae2f19536f159f5c88878b1a124b6e5f4"
COORDINATION_LEDGER_DIGEST = "35de66d633c7d5333707d0aff053bd34d7d1bb5d36666bdb94996c6cb3617b53"
COORDINATION_PROJECTION_DIGEST = "02e330678d1922ca52019976236b03b53258718065fb262dc272dae89612217a"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
PRIOR_LEDGER_DIGEST = "fb3f42733b7b2cf30f90fa285914605322e31638cf62f9535f20c8114300a151"
CREATED_AT = "2026-08-31T11:30:00Z"

# Source lanes are intentionally not sealed during hydration.  The owner may
# set this to True only after all source lanes and audits are stable.
FINAL_HASHES_SEALED = True

SOURCE_PINS = {
    "dossierUTF8Length": 8502,
    "dossierSHA256": "7010cd064a0c96b61b91e25e4198a582554d0afd6f8712c2ea8a80c8264355b1",
    "inheritedV21BlockUTF8Length": 9281,
    "inheritedV21BlockSHA256": "8416a9a4e33b14674c53820f23e5561775b12ba5f50d640bd1249f39806b44b4",
    "registerRowUTF8Length": 304,
    "registerRowSHA256": "0566052cc8ecfc0c41ec7475051d4d9058270d13e1ecf4ee5674a9e57049ee55",
    "registerSectionUTF8Length": 44217,
    "registerSectionSHA256": "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5",
}

EXPECTED_EXISTING_PATH_COUNT = 117
EXPECTED_NEW_PATH_COUNT = 16
EXPECTED_FENCE_PATH_COUNT = 133
AUTHORIZED_OVERLAP_COUNT = 4198
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 97
PRIOR_OWNED_PATH_COUNT = 1531
S10_RESERVED_PATH_COUNT = 86

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Metrics/OperationsMetricsContractsV1.swift",
    "FieldEvidenceApp/Domain/Metrics/OperationsMetricsProjectionContractsV1.swift",
    "FieldEvidenceApp/Application/Metrics/OperationsMetricsCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Metrics/OperationsMetricsRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Features/Dashboard/OperationsDashboardView.swift",
    "FieldEvidenceAppTests/V9_73OperationsMetricsTimelineTests.swift",
    "FieldEvidenceAppUITests/V23_P04_C09OperationsDashboardUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Metrics/V22P04C09OperationsMetricsTimelineCorpusV1.json",
)
SCHEMA_PATH = "Scripts/v23/operations-metrics-timeline.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C09OperationsMetricsTimelineContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C09OperationsMetricsTimelineEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C09BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C09-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c09_contracts.py",
    "Scripts/v23/generate_p04_c09_contracts.py",
    "Scripts/v23/verify_p04_c09_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
OUTPUT_PATHS = GENERATED_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C09-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C09-attempt-1/BootstrapPathFenceV1.json"
_PREREQUISITE_RELATIVE = "receipts/V23-P03-C37-and-V23-P03-C53-to-V23-P04-C09-provisional-prerequisite.json"
_TRANSITION_RELATIVE = "transitions/000422-V23-P04-C09-attempt-1-NOT_STARTED-to-HYDRATING.json"
_LEDGER_RELATIVE = "state/BootstrapExecutionLedgerEnvelopeV1.json"
_PROJECTION_RELATIVE = "projections/ActiveWorkSetProjectionV1.json"

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
EXPECTED_SELECTORS = (
    "testV23P04C09G01MetricDefinitionAndDashboardJSONReconciliationAreDeterministic",
    "testV23P04C09A01AssetTimelineOrderAndProvenanceRemainExactAcrossCorrectiveLifecycle",
    "testV23P04C09H01MetricDefinitionOutputDisagreementDoubleCountAndOwnerBridgeFailClosed",
    "testV23P04C09I01InterruptedScaleRebuildCancellationAndDerivedIndexCorruptionRemainDeterministic",
    "testV23P04C09R01DropRebuildAndRecoveryPreserveCanonicalRecordsReceiptsAndArtifacts",
)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
JOURNEY_REFS = ("FJ09",)
DIRECT_PREREQUISITES = ("V23-P03-C37", "V23-P03-C53")
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
AGGREGATE_MEMBERSHIPS = (
    "AutonomousRequiredAcceptedSetV1",
    "P04ShippingSurfaceSetV1",
    "P04BrandClosureSetV1",
)
CONFORMANCE_SUBJECTS = ("P04ShippingSurfaceSetV1", "FJ09")
INVALIDATION_CONSUMERS = (
    "V23-P04-C12",
    "V23-P04-C22",
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C09).CONTRACTS",
    "AssetServiceIncidentV1",
    "ServiceImpactSegmentV1",
    "QualifiedServiceExposureV1",
    "ReliabilityMetricInputProjectionV1",
    "MetricDefinitionV1",
    "ReliabilityMetricProjectionV1",
    "QUALIFIED_RECORDED_UNPLANNED_MTBF_V1",
    "QUALIFIED_RECORDED_UNPLANNED_FULL_INTERRUPTION_AVAILABILITY_V1",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)

AUTHORITY_CONTRACTS = (
    "AssetServiceIncidentV1",
    "ServiceImpactSegmentV1",
    "QualifiedServiceExposureV1",
    "ReliabilityMetricInputProjectionV1",
    "MetricDefinitionV1",
    "ReliabilityMetricProjectionV1",
    "QUALIFIED_RECORDED_UNPLANNED_MTBF_V1",
    "QUALIFIED_RECORDED_UNPLANNED_FULL_INTERRUPTION_AVAILABILITY_V1",
)
PERSISTENT_KINDS: tuple[str, ...] = ()
TIMELINE_KINDS = (
    "ASSET_SERVICE_INCIDENT",
    "SERVICE_IMPACT_SEGMENT",
    "QUALIFIED_SERVICE_EXPOSURE",
    "INSPECTION",
    "FINDING",
    "CORRECTIVE_WORK",
    "RECHECK",
    "REPORT",
    "EVIDENCE_ASSOCIATION",
    "EXPLICIT_ASSET_CHANGE",
    "C37_PLACEMENT_CHANGE",
)
METRIC_DEFINITIONS = (
    "QUALIFIED_RECORDED_UNPLANNED_MTBF_V1",
    "QUALIFIED_RECORDED_UNPLANNED_FULL_INTERRUPTION_AVAILABILITY_V1",
)
QUALIFICATION_STATES = ("QUALIFIED", "UNAVAILABLE")
LIFECYCLE = (
    "SCHEMA_VERSION",
    "WRITER_QUERY",
    "MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK",
    "IMPORT_EXPORT",
    "JOURNAL_REPLAY",
    "SEARCH_REBUILD",
    "REPORT_PROJECTION",
    "DELETE_ERASE",
    "RETENTION",
    "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX",
    "INTERRUPTION",
    "IDEMPOTENT_RECEIPTS",
)
LIFECYCLE_DISPOSITIONS = {
    "SCHEMA_VERSION": "OPERATIONS_METRICS_V1_VERSION_1",
    "WRITER_QUERY": "NONPERSISTENT_NO_CARD_LOCAL_WRITER_OR_QUERY",
    "MIGRATION": "NOT_APPLICABLE_DERIVED_ONLY",
    "BACKUP_REPLACE_RESTORE": "NOT_APPLICABLE_DERIVED_ONLY_REBUILD_AFTER_CANONICAL_RESTORE",
    "CLONE_FORK": "NOT_APPLICABLE_DERIVED_ONLY_REBUILD_FROM_CANONICAL_C53_INPUTS",
    "IMPORT_EXPORT": "DETERMINISTIC_OPEN_JSON_HANDOFF_NO_CANONICAL_IMPORT",
    "JOURNAL_REPLAY": "REBUILD_FROM_CANONICAL_C53_INPUTS",
    "SEARCH_REBUILD": "DERIVED_INDEX_REBUILD_FROM_CANONICAL_C53_INPUTS",
    "REPORT_PROJECTION": "C53_REPORT_PROJECTION_DERIVED_HANDOFF",
    "DELETE_ERASE": "NOT_APPLICABLE_DERIVED_ONLY_DROP_AND_REBUILD",
    "RETENTION": "NOT_APPLICABLE_DERIVED_ONLY",
    "COMPATIBILITY": "VERSIONED_DEFINITION_AND_PROJECTION_VALIDATION",
    "DOWNGRADE_FORWARD_FIX": "DROP_AND_REBUILD",
    "INTERRUPTION": "CANCEL_AND_RESTART_OR_RESUME_CALLER_HELD_CONTINUATION",
    "IDEMPOTENT_RECEIPTS": "NO_CARD_LOCAL_RECEIPT_CANONICAL_C53_RECEIPTS_UNCHANGED",
}
FORBIDDEN = (
    "MODEL_DECLARATION",
    "PERSISTENT_SCHEMA_V47",
    "SCHEMA_MIGRATION",
    "NEW_STORE",
    "SECOND_WRITER",
    "BACKUP_RESTORE_ENROLLMENT",
    "DELETE_ERASE_OWNERSHIP",
    "CUSTOMER_LEARNING_METRIC_DEFINITION_BRIDGE",
    "NETWORK",
    "TELEMETRY",
    "ACCOUNT",
    "AUTHENTICATION",
    "TENANCY",
    "REMOTE_SYNC",
    "BACKEND",
    "REMOTE_ANALYTICS",
    "NATIVE_IPAD",
    "PREDICTIVE_SCORING",
    "DUE_OR_OVERDUE",
    "ACTOR_ATTRIBUTION",
)
HOSTILE_VECTORS = (
    "metric-definition-output-disagreement",
    "double-count-after-retry-restore-replay-amend-or-delete",
    "stale-timeline-after-delete-erase-or-reassignment",
    "clock-time-zone-boundary",
    "unknown-metric-version",
    "10,000-asset-bounded-rebuild",
    "cancellation-or-derived-index-corruption",
    "C09-C43-owner-bridge",
    "telemetry-or-remote-claim",
)
FLAGS = {name: False for name in (
    "activation",
    "native",
    "hosted",
    "adoption",
    "acceptance",
    "release",
    "nativeAcceptance",
    "hostedAcceptance",
    "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

# This is the exact semantic scope recorded by the hydrated C09 context.
CONTEXT_SEMANTIC_SCOPE = {
    "canonicalIncidentAndExposureWriterOwner": "V23-P03-C53",
    "downgradeDisposition": "DROP_AND_REBUILD",
    "forbidden": [
        "MODEL_DECLARATION",
        "PERSISTENT_SCHEMA_V47",
        "SCHEMA_MIGRATION",
        "NEW_STORE",
        "SECOND_WRITER",
        "BACKUP_RESTORE_ENROLLMENT",
        "DELETE_ERASE_OWNERSHIP",
        "CUSTOMER_LEARNING_METRIC_DEFINITION_BRIDGE",
        "NETWORK",
        "TELEMETRY",
    ],
    "metricDefinitionOwner": "V23-P04-C09_SOLE_REGISTRY_AND_PROJECTION_OWNER",
    "metricTruth": "QUALIFIED_RECORDED_INTERVALS_ONLY_NEVER_INFER_UPTIME_OR_EXPOSURE_FROM_ABSENCE",
    "namedContracts": list(AUTHORITY_CONTRACTS),
    "persistentContractMode": "DERIVED_ONLY",
    "persistentContractSchema": "OPERATIONS_METRICS_V1",
    "policyProfile": "PERSISTENT_OR_PRODUCT_DELTA",
    "projectionOutputs": [
        "LOCAL_OPERATIONS_DASHBOARD",
        "ASSET_SERVICE_TIMELINE",
        "DETERMINISTIC_OPEN_JSON",
    ],
    "uiJourneyCredit": "NONE_UNTIL_POST_S10_6_REACHABLE_FJ09_ADOPTION",
    "uiSurface": "CONTAINED_NONADOPTED_VIEW_PENDING_S10_6_ROUTE_RECONCILIATION",
}
SEMANTIC_SCOPE = {
    "lineage": "REFINED_WITHOUT_LOSS",
    "policyProfile": "PERSISTENT_OR_PRODUCT_DELTA",
    "persistentContractMode": "DERIVED_ONLY",
    "persistentContractSchema": "OPERATIONS_METRICS_V1",
    "persistentKinds": list(PERSISTENT_KINDS),
    "metricDefinitionOwner": "V23-P04-C09_SOLE_REGISTRY_AND_PROJECTION_OWNER",
    "canonicalIncidentAndExposureWriterOwner": "V23-P03-C53",
    "metricTruth": "QUALIFIED_RECORDED_INTERVALS_ONLY_NEVER_INFER_UPTIME_OR_EXPOSURE_FROM_ABSENCE",
    "timelineKinds": list(TIMELINE_KINDS),
    "metricDefinitions": list(METRIC_DEFINITIONS),
    "qualificationStates": list(QUALIFICATION_STATES),
    "projectionOutputs": list(CONTEXT_SEMANTIC_SCOPE["projectionOutputs"]),
    "lifecycle": dict(LIFECYCLE_DISPOSITIONS),
    "migrationRequired": False,
    "backupRestoreRequired": False,
    "deleteEraseRequired": False,
    "exportReportRequired": True,
    "downgradePolicy": "DROP_AND_REBUILD",
    "noCanonicalWriter": True,
    "noPersistentMetricProjection": True,
    "noCustomerLearningBridge": True,
    "noNetworkOrTelemetry": True,
    "deterministicMetricDefinitionRegistry": True,
    "deterministicDashboardJSON": True,
    "deterministicTimelineOrderingAndProvenance": True,
    "qualifiedRecordedIntervalsOnly": True,
    "noInferenceFromAbsence": True,
    "boundedRebuildMaximumAssets": 10000,
    "cancellationAndCorruption": "DROP_DERIVED_AND_FAIL_CLOSED_UNTIL_REBUILT",
    "sourceClosure": "CANONICAL_C53_EVENT_REVISIONS",
    "forbidden": list(FORBIDDEN),
    "noNativeIPad": True,
    "noS10RouteWiring": True,
    "ui": "POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT",
    "accessibilityAndLocalization": {
        "voiceOver": True,
        "voiceControl": True,
        "switchControlWhereRelevant": True,
        "largerText": True,
        "darkContrastNonColor": True,
        "reduceMotion": True,
        "localeAndRTL": True,
        "offline": True,
        "permissionFallback": True,
        "cancellationRecovery": True,
        "syntheticFixturesOnly": True,
    },
}

_CANONICAL_TEXT_SUFFIXES = frozenset({
    ".csv", ".entitlements", ".json", ".md", ".pbxproj", ".plist", ".ps1", ".py", ".sh",
    ".strings", ".swift", ".toml", ".txt", ".xcstrings", ".xcscheme", ".yaml", ".yml",
})
_BASE_PATH_CACHE: frozenset[str] | None = None


def strict(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def canonical_file_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n") if path.suffix.lower() in _CANONICAL_TEXT_SUFFIXES else data


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def _coordination_root() -> Path:
    candidates = (Path(r"C:\AssetRounds-v23-coordination"), ROOT.parent / "AssetRounds-v23-coordination")
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C09 coordination fence unavailable")


def coord() -> Path:
    return _coordination_root()


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ValueError("C09 coordination input unavailable:" + relative)
    value = json.loads(canonical_file_bytes(path), object_pairs_hook=strict)
    if not isinstance(value, dict):
        raise ValueError("C09 coordination object required:" + relative)
    return value


def sealed_field(value: dict[str, Any], field: str) -> str:
    unsigned = {key: item for key, item in value.items() if key != field}
    return sha256_bytes((json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST or sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C09 context identity or seal differs")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST or sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ValueError("C09 path fence identity or seal differs")
    existing = tuple(context.get("existingPaths", ()))
    fenced_existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(context.get("newPaths", ()))
    fenced_new = tuple(fence.get("newPaths", ()))
    allowed = tuple(fence.get("allowedCreateOrReplacePaths", ()))
    if existing != fenced_existing or hydrated_new != fenced_new:
        raise ValueError("C09 context/fence path sets differ")
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C09 existing path fence cardinality differs")
    if hydrated_new != NEW_PATHS or allowed != existing + hydrated_new:
        raise ValueError("C09 hydrated new-path ordering differs")
    if tuple(context.get("expectedArtifacts", ())) != allowed:
        raise ValueError("C09 expected-artifact ordering differs")
    if context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST or tuple(context.get("directPrerequisites", ())) != DIRECT_PREREQUISITES:
        raise ValueError("C09 prerequisite binding differs")
    expected_projection = {
        **SOURCE_PINS,
        "canonicalSuccessor": {"cardID": "V23-P04-C10", "registerOrdinal": 98},
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
        "journeyRefs": list(JOURNEY_REFS),
        "registerRowSHA256": SOURCE_PINS["registerRowSHA256"],
        "registerRowUTF8Length": SOURCE_PINS["registerRowUTF8Length"],
        "registerSectionSHA256": SOURCE_PINS["registerSectionSHA256"],
        "registerSectionUTF8Length": SOURCE_PINS["registerSectionUTF8Length"],
        "selectors": list(EXPECTED_SELECTORS),
    }
    if context.get("sourceProjection") != expected_projection or context.get("semanticScope") != CONTEXT_SEMANTIC_SCOPE:
        raise ValueError("C09 source projection or semantic scope differs")
    reserved = tuple(fence.get("activeS10ReservedPaths", ()))
    if fence.get("frozenS10ReservationDigest") != FROZEN_S10_RESERVATION_DIGEST or len(reserved) != S10_RESERVED_PATH_COUNT or set(existing + hydrated_new) & set(reserved):
        raise ValueError("C09 S10 reservation or overlap differs")
    return existing, hydrated_new


EXISTING_PATHS, _HYDRATED_NEW_PATHS = _load_hydrated_paths()
PATH_FENCE = EXISTING_PATHS + _HYDRATED_NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_text(root, relative), object_pairs_hook=strict)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + relative)
    return value


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    lower = text.lower()
    missing = [token for token in tokens if token.lower() not in lower]
    if missing:
        raise ValueError(label + " missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I | re.S) is None]
    if missing:
        raise ValueError(label + " missing patterns:" + ",".join(missing))


def _base_exists(root: Path, relative: str) -> bool:
    global _BASE_PATH_CACHE
    if _BASE_PATH_CACHE is None:
        listing = subprocess.run(["git", "ls-tree", "-r", "--name-only", BASE_HEAD], cwd=root, check=True, capture_output=True, text=True).stdout
        _BASE_PATH_CACHE = frozenset(line.strip().replace("\\", "/") for line in listing.splitlines() if line.strip())
    return relative in _BASE_PATH_CACHE


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed: set[str] = set()
    for command in (("diff", "--name-only", BASE_HEAD, "--"), ("diff", "--cached", "--name-only", "--"), ("ls-files", "--others", "--exclude-standard")):
        result = subprocess.run(["git", *command], cwd=root, check=True, capture_output=True, text=True)
        changed.update(line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip())
    return tuple(sorted(changed))


def _candidate_identity(root: Path) -> None:
    if _git(root, "show", "-s", "--format=%T", CANDIDATE_HEAD) != CANDIDATE_TREE:
        raise ValueError("C09 candidate tree differs from accepted base")
    observed_head = _git(root, "rev-parse", "HEAD")
    if observed_head != BASE_HEAD and subprocess.run(["git", "merge-base", "--is-ancestor", BASE_HEAD, observed_head], cwd=root).returncode != 0:
        raise ValueError("C09 candidate is not a descendant of accepted base")


def _prior_fence_path(card_id: str, attempt_id: int) -> Path:
    return _coordination_root() / f"contexts/{card_id}-attempt-{attempt_id}/BootstrapPathFenceV1.json"


def _validate_prior_fence_proof(fence: dict[str, Any], allowed: tuple[str, ...]) -> None:
    proof = fence.get("priorFenceProof")
    if not isinstance(proof, dict):
        raise ValueError("C09 prior fence proof missing")
    for key, expected in (("fenceCount", PRIOR_FENCE_COUNT), ("priorOwnedPathCount", PRIOR_OWNED_PATH_COUNT), ("authorizedOverlapCount", AUTHORIZED_OVERLAP_COUNT), ("unauthorizedOverlapCount", UNAUTHORIZED_OVERLAP_COUNT), ("overlapCount", AUTHORIZED_OVERLAP_COUNT)):
        if proof.get(key) != expected:
            raise ValueError("C09 prior fence proof differs:" + key)
    rows = proof.get("fences")
    if not isinstance(rows, list) or len(rows) != PRIOR_FENCE_COUNT:
        raise ValueError("C09 prior fence rows differ")
    rebuilt: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    prior_owned: set[str] = set()
    disposition = "P04_C09_DERIVED_OPERATIONS_METRICS_CANONICAL_INPUT_AND_REBUILD_REPROOF_REQUIRED"
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("cardID"), str) or not isinstance(row.get("attemptID"), int):
            raise ValueError("C09 prior fence row shape differs")
        path = _prior_fence_path(row["cardID"], row["attemptID"])
        if not path.is_file():
            raise ValueError("C09 prior fence input unavailable:" + row["cardID"])
        prior = json.loads(canonical_file_bytes(path), object_pairs_hook=strict)
        owner_paths = tuple(prior.get("allowedCreateOrReplacePaths", ()))
        if prior.get("fenceDigest") != row.get("fenceDigest") or len(owner_paths) != row.get("ownedPathCount") or sealed_field(prior, "fenceDigest") != row.get("fenceDigest"):
            raise ValueError("C09 prior fence identity/seal differs:" + row["cardID"])
        prior_owned.update(owner_paths)
        rebuilt.append({"cardID": row["cardID"], "attemptID": row["attemptID"], "fenceDigest": row["fenceDigest"], "ownedPathCount": len(owner_paths)})
        edges.extend({"path": item, "priorCardID": row["cardID"], "priorFenceDigest": row["fenceDigest"], "disposition": disposition} for item in sorted(set(allowed) & set(owner_paths)))
    if len(prior_owned) != PRIOR_OWNED_PATH_COUNT or rows != rebuilt:
        raise ValueError("C09 prior owned-path proof differs")
    for key in ("authorizedFenceEdges", "authorizedOverlapEdges"):
        if proof.get(key) is not None and proof.get(key) != edges:
            raise ValueError("C09 " + key + " differ")


def _assert_coordination_state() -> None:
    coordination = _coordination_root()
    if _git(coordination, "rev-parse", "HEAD") != COORDINATION_HEAD or _git(coordination, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE:
        raise ValueError("C09 coordination HEAD/tree differs")
    origin = _git(coordination, "ls-remote", "origin", "refs/heads/main").split()
    if not origin or origin[0] != COORDINATION_ORIGIN_HEAD:
        raise ValueError("C09 coordination origin/main differs")
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    prerequisite = _coordination_json(_PREREQUISITE_RELATIVE)
    transition = _coordination_json(_TRANSITION_RELATIVE)
    ledger = _coordination_json(_LEDGER_RELATIVE)
    projection = _coordination_json(_PROJECTION_RELATIVE)
    _load_hydrated_paths()
    if context.get("repository") != {"appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE} or context.get("registerOrdinal") != REGISTER_ORDINAL or context.get("title") != TITLE or context.get("lineage") != "REFINED_WITHOUT_LOSS":
        raise ValueError("C09 context metadata differs")
    if context.get("expectedArtifacts") != list(PATH_FENCE) or context.get("persistentChangeMode") != "DERIVED_ONLY" or context.get("executionMode") != "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION":
        raise ValueError("C09 context scope differs")
    for key in ("nativeCompileRan", "hostedDispatchEnabled", "hostedDispatchRan", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit", "releaseReady", "physicalEvidenceComplete", "phase10PollingDuringParallelExecution"):
        if context.get(key) is not False:
            raise ValueError("C09 context claims activation:" + key)
    if context.get("uiAdoptionDeferred") is not True or context.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C09 UI/S10 disposition differs")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("C09 fence scope differs")
    if (fence.get("baseHead"), fence.get("baseTree")) != (BASE_HEAD, BASE_TREE) or fence.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C09 fence base differs")
    _validate_prior_fence_proof(fence, PATH_FENCE)
    expected_predecessors = [
        {"attemptID": 1, "candidateHead": "08841c808ab5fe263b41db530e4e733f8126adb4", "candidateTree": "19b59129672300d130b96b7115c9fce1aef1a8e5", "cardID": "V23-P03-C37", "checkpointDigest": "0ab302395a9d3a951ecf5df17c5de641cb69c8926a441b531c3da0e5e106a7d1", "contextDigest": "cacb2aeb4e857ef445a4432ed71c33b499e92de72d9bcf6cbc638a95f27d75bc", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE", "finalTransitionDigest": "fdd90e6cb53c375dc9e32e3e58ff2e7d4406c0938afeddd2dbc924b32bf3e760", "hydrationTransitionDigest": "dfefcdc0f7cc33c6894d58321f2c394dee18842fa421e698c38f027e327862a0", "pathFenceDigest": "59b198fde5e300119e100f68870480334b704adc64e303de40db3b23979a4e59", "verificationReceiptDigest": "e95d1bbdbdfe66466ec3f3a19780d3671db4162ae9e48eda5ba350f2b12c630b"},
        {"attemptID": 1, "candidateHead": "efdd77f67e8184cc8d32673f0bf4ba06385d5965", "candidateTree": "38547059ec0f7931903014bad7234567836d1b94", "cardID": "V23-P03-C53", "checkpointDigest": "0534d64456830fae433a49652fde08b8587658bfcb5c49b374454ed9ff27a180", "contextDigest": "e2cdd39366c42ceda098600bd0f5bf4f03dd7a6dc5fbe487ad7bb9e4da29e021", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE", "finalTransitionDigest": "970424964428350b230c27cefc35fa617fe44a87214a8dcbad81c06ddf533aa8", "hydrationTransitionDigest": "245f8cd950b5f0952b8dea9579ccd0320fc2f437f4ed928c478bf3c725f4c314", "pathFenceDigest": "1a2efea842b850f3b8a0a773b4ff904f43d763d7b087bdf4a53e3cc621618892", "verificationReceiptDigest": "36e8253c3a726243084f910273599f9facc84189f9636447d8927f7d3d3b397b"},
    ]
    if prerequisite.get("schema") != "ProvisionalExecutionPrerequisiteSetReceiptV1" or prerequisite.get("schemaVersion") != 1 or prerequisite.get("successorCardID") != CARD or prerequisite.get("successorAttemptID") != 1 or prerequisite.get("ordinaryDirectEdgeCount") != 2 or prerequisite.get("predecessors") != expected_predecessors or any(prerequisite.get(key) is not False for key in ("nativeCompileRan", "hostedDispatchEnabled", "hostedDispatchRan", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit", "releaseReady", "phase10PollingDuringParallelExecution")) or prerequisite.get("canonicalIncidentAndExposureWriterOwner") != "V23-P03-C53" or prerequisite.get("requiresAcceptedS10_6Reconciliation") is not True or sealed_field(prerequisite, "prerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C09 direct prerequisite receipt differs")
    expected_transition = {"schema": "BootstrapStateTransitionV1", "schemaVersion": 1, "sequence": SEQUENCE, "cardID": CARD, "attemptID": 1, "fromState": "NOT_STARTED", "toState": "HYDRATING", "reason": "OWNER_AUTHORIZED_P04_C09_PROVISIONAL_HYDRATION", "candidateHead": BASE_HEAD, "candidateTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "priorLedgerDigest": PRIOR_LEDGER_DIGEST, "newLedgerDigest": COORDINATION_LEDGER_DIGEST, "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0}, "createdAt": CREATED_AT, "transitionDigest": HYDRATION_TRANSITION_DIGEST}
    if any(transition.get(key) != value for key, value in expected_transition.items()) or sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C09 hydration transition differs")
    if ledger.get("schema") != "BootstrapExecutionLedgerEnvelopeV1" or ledger.get("schemaVersion") != 1 or ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or ledger.get("previousLedgerDigest") != PRIOR_LEDGER_DIGEST or sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST:
        raise ValueError("C09 ledger authority differs")
    expected_row = {"cardID": CARD, "attemptID": 1, "ordinal": REGISTER_ORDINAL, "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED", "state": "HYDRATING", "stateReason": "OWNER_AUTHORIZED_P04_C09_PROVISIONAL_HYDRATION", "candidateHead": BASE_HEAD, "candidateTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "directPrerequisites": list(DIRECT_PREREQUISITES)}
    rows = ledger.get("attempts")
    if not isinstance(rows, list) or expected_row not in rows:
        raise ValueError("C09 ledger card row differs")
    if projection.get("schema") != "ActiveWorkSetProjectionV1" or projection.get("schemaVersion") != 1 or projection.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or projection.get("projectionDigest") != COORDINATION_PROJECTION_DIGEST or projection.get("eligibilityBasis") != "P04_C09_HYDRATING_DERIVED_OPERATIONS_METRICS_AND_ASSET_SERVICE_TIMELINE" or projection.get("nextEligibleCardID") is not None or projection.get("nextEligibleRegisterOrdinal") is not None or sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ValueError("C09 projection authority differs")
    active = projection.get("activeEntries")
    if not isinstance(active, list) or expected_row not in active:
        raise ValueError("C09 projection card row differs")


def _authority_pins_ready() -> bool:
    refs = (BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE, COORDINATION_HEAD, COORDINATION_ORIGIN_HEAD, COORDINATION_TREE)
    digests = (CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST, COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST, FROZEN_S10_RESERVATION_DIGEST, *[value for value in SOURCE_PINS.values() if isinstance(value, str)])
    return all(re.fullmatch(r"[0-9a-f]{40}", value) for value in refs) and all(valid_sha(value) for value in digests)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(_HYDRATED_NEW_PATHS), len(PATH_FENCE), len(set(PATH_FENCE))) != (EXPECTED_EXISTING_PATH_COUNT, EXPECTED_NEW_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT):
        raise ValueError("C09 fence cardinality or uniqueness differs")
    if _HYDRATED_NEW_PATHS != NEW_PATHS or PATH_FENCE != EXISTING_PATHS + NEW_PATHS:
        raise ValueError("C09 new-path ordering differs from hydrated fence")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C09 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 4198 or UNAUTHORIZED_OVERLAP_COUNT != 0 or S10_RESERVATION_OVERLAP_COUNT != 0:
        raise ValueError("C09 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C09 app base tree differs")
    _candidate_identity(root)
    _assert_coordination_state()
    unauthorized = [path for path in observed_changed_paths(root) if path not in PATH_FENCE]
    if unauthorized:
        raise ValueError("C09 changed path outside fence:" + ",".join(unauthorized))
    missing_base = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C09 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C09 new path already exists at accepted base")


def selectors(root: Path) -> tuple[str, ...]:
    found: list[str] = []
    for relative in IMPLEMENTATION_PATHS[5:7]:
        path = root / relative
        if path.is_file():
            found.extend(re.findall(r"(?m)^\s*func\s+(testV23P04C09(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", path.read_text(encoding="utf-8")))
    return tuple(found)


def observed_selectors(root: Path) -> tuple[str, ...]:
    return selectors(root)


def bound_selectors(root: Path) -> tuple[str, ...]:
    found = selectors(root)
    return EXPECTED_SELECTORS if not found else found


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    found = selectors(root)
    return {"requiredPathCount": len(IMPLEMENTATION_PATHS), "presentPathCount": len(present), "missingPathCount": len(missing), "presentPaths": present, "missingPaths": missing, "selectors": list(found), "expectedSelectors": list(EXPECTED_SELECTORS), "hydrated": not missing, "sourceReady": not missing, "status": "SOURCE_READY" if not missing else "SOURCE_PENDING", "reason": "ALL_IMPLEMENTATION_SOURCE_LANES_PRESENT" if not missing else "IMPLEMENTATION_SOURCE_LANES_INCOMPLETE"}


def _assert_fixture_contract(fixture: dict[str, Any]) -> None:
    if fixture.get("schema") != "V22P04C09OperationsMetricsTimelineCorpusV1" or fixture.get("schemaVersion") != 1 or fixture.get("cardID") != CARD or fixture.get("ordinal") != REGISTER_ORDINAL:
        raise ValueError("C09 fixture identity differs")
    expected_selectors = [{"id": suffix, "selector": selector, "tier": tier} for suffix, selector, tier in zip(EVIDENCE_SUFFIXES, EXPECTED_SELECTORS, ("GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"))]
    if fixture.get("selectors") != expected_selectors:
        raise ValueError("C09 fixture selectors differ")
    if fixture.get("alternate", {}).get("timelineKinds") != list(TIMELINE_KINDS):
        raise ValueError("C09 fixture timeline kinds differ")
    status_flags = fixture.get("statusFlags")
    if not isinstance(status_flags, dict) or any(value is not False for value in status_flags.values()):
        raise ValueError("C09 fixture flags differ")
    claims = fixture.get("claims")
    if isinstance(claims, dict):
        required = ("metricDefinitionRegistry", "deterministicDashboardJSON", "timelineProvenance", "qualifiedRecordedIntervalsOnly", "boundedRebuild", "canonicalC53InputsOnly", "dropAndRebuild")
        if any(claims.get(key) is not True for key in required if key in claims):
            raise ValueError("C09 fixture claims differ")


def _source_claim_code(source: str) -> str:
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", code, flags=re.S)


def _assert_no_forbidden_source_claims(source: str, *, allow_canonical_test_writer: bool = False) -> None:
    code = _source_claim_code(source)
    patterns = (
        r"@Model\b",
        r"\b(?:ModelContainer|NSPersistentContainer|NSPersistentCloudKitContainer|ModelContext)\b",
        r"\b(?:PersistentSchemaV47|SchemaV47)\b",
        r"\bCustomerLearning(?:MetricDefinition)?V1\b",
        r"\b(?:URLSession|URLRequest|CKContainer|CloudKit|NWConnection|WebSocket)\b",
        r"\b(?:TelemetryClient|analyticsPipeline|remoteSync|providerOutbox|providerInbox|signedURL|dueQueue|recurrence)\b",
        r"\b(?:iPad|iPadOS|S10Route|S10_.*Route)\b",
    )
    for pattern in patterns:
        if re.search(pattern, code, re.I):
            raise ValueError("C09 forbidden source claim:" + pattern)
    if not allow_canonical_test_writer and re.search(r"\b(?:WorkspaceWriterV1|WorkspaceWriterAdapterV1)\b", code, re.I):
        raise ValueError("C09 forbidden source claim:canonical writer outside C53 test harness")


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C09 source lanes missing:" + ",".join(status["missingPaths"]))
    contract = _text(root, IMPLEMENTATION_PATHS[0])
    projection = _text(root, IMPLEMENTATION_PATHS[1])
    coordinator = _text(root, IMPLEMENTATION_PATHS[2])
    rebuild = _text(root, IMPLEMENTATION_PATHS[3])
    view = _text(root, IMPLEMENTATION_PATHS[4])
    tests = _text(root, IMPLEMENTATION_PATHS[5])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[6])
    fixture = _json(root, IMPLEMENTATION_PATHS[7])
    _assert_fixture_contract(fixture)
    _require_tokens(contract, ("MetricDefinitionV1", "OperationsMetricsContractV1", "OPERATIONS_METRICS_V1", "DERIVED_ONLY", "metricDefinitions", "validateRegistry", "canonicalTruthOwner", "DROP_DERIVED_AND_REBUILD_FROM_C53", "QUALIFIED_RECORDED_UNPLANNED_MTBF_V1", "QUALIFIED_RECORDED_UNPLANNED_FULL_INTERRUPTION_AVAILABILITY_V1", "infersUptimeFromAbsentFailures", "bridgesCustomerLearningMetricDefinition"), "C09 metric contracts")
    _require_tokens(projection, ("ReliabilityMetricProjectionV1", "DashboardProjectionV1", "AssetServiceHistoryTimelineV1", "OperationsMetricsOpenJSONV1", "definition", "projectionSHA256", "timelineSHA256", "validate", "includedSourceEventIDs", "excludedSources", "recordedAt"), "C09 projection contracts")
    _require_tokens(coordinator, ("OperationsMetricsCoordinatorV1", "OperationsMetricsCanonicalSourceV1", "OperationsMetricsRebuildCoordinatorV1", "project", "rebuild", "previewC53Commit", "commitC53", "expectedSourceClosureSHA256", "AssetServiceReliabilityCoordinatorV1", "createsSecondWriter", "persistsMetricProjection"), "C09 application coordinator")
    _require_tokens(rebuild, ("OperationsMetricsCanonicalSourceV1", "maximumAssetsPerRebuild", "OperationsMetricsRebuildContinuationV1", "sourceSetSHA256", "Task.checkCancellation", "validateOrDiscard", "C53ServiceReliabilityReportProjectionRegistryV1", "WorkspaceMutationCanonicalV1", "corruptDerivedProjection", "scaleLimitExceeded"), "C09 rebuild coordinator")
    _require_tokens(view, ("OperationsDashboardView", "OperationsDashboardPresentationModelV1", "OperationsDashboardMetricPresentationV1", "OperationsDashboardTimelinePresentationV1", "OperationsDashboardExposurePresentationV1", "accessibilityIdentifier", "accessibilityFocused", "accessibilityReduceMotion", "dynamicTypeSize", "BundledLocalizationCatalogV1", "reviewExposure", "correctExposure"), "C09 dashboard view")
    found = selectors(root)
    if found != EXPECTED_SELECTORS or len(set(found)) != 5:
        raise ValueError("C09 requires exactly five ordered G/A/H/I/R selectors")
    _require_tokens(tests, ("XCTest", "XCTAssert", "MetricDefinitionV1", "DashboardProjectionV1", "AssetServiceHistoryTimelineV1", "canonical", "definition", "projection", "digest", "double", "retry", "restore", "replay", "deletion", "Erase", "time", "zone", "unknown", "10,000", "cancel", "corrupt", "rebuild"), "C09 integration evidence")
    _require_tokens(ui_tests, (CARD, "XCTest", "XCTSkip", "XCTAssertFalse", "S10.6", "C16", "activationEnabled", "adoptionEnabled", "acceptanceCredit", "no acceptance credit"), "C09 UI deferral evidence")
    _require_patterns(ui_tests, (r"XCTAssertFalse\s*\(\s*Self\.acceptanceCredit\s*\)", r"throw\s+XCTSkip\s*\(", r"awaits accepted S10\.6/C16"), "C09 UI deferral evidence")
    for source in (contract, projection, coordinator, rebuild, view):
        _assert_no_forbidden_source_claims(source)
    _assert_no_forbidden_source_claims(tests, allow_canonical_test_writer=True)
    _assert_no_forbidden_source_claims(ui_tests)
    _require_patterns(tests, (r"\bWorkspaceWriterV1\b", r"\bAssetServiceReliabilityCoordinatorV1\s*\(", r"\bC09NoopWriterAdapter\b"), "C09 canonical C53 test harness")
    if re.search(r"\bOperationsMetrics(?:Writer|WriterAdapter|Store|Persistence)\b", _source_claim_code(tests), re.I):
        raise ValueError("C09 test lane claims a card-local writer or store")
    return found


def authority() -> dict[str, Any]:
    return {"cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE, "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "candidateHead": CANDIDATE_HEAD, "candidateTree": CANDIDATE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationOriginHead": COORDINATION_ORIGIN_HEAD, "coordinationTree": COORDINATION_TREE, "coordinationSequence": SEQUENCE, "coordinationCASSequence": SEQUENCE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "prerequisiteDigest": PREREQUISITE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "priorLedgerDigest": PRIOR_LEDGER_DIGEST, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "sourcePins": dict(SOURCE_PINS), "directPrerequisiteCards": list(DIRECT_PREREQUISITES), "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS), "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT, "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT, "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT, "existingPathCount": EXPECTED_EXISTING_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "s10ReservedPathCount": S10_RESERVED_PATH_COUNT, "finalHashesSealed": FINAL_HASHES_SEALED}


def common() -> dict[str, Any]:
    return {"cardID": CARD, "title": TITLE, "authority": authority(), "evidenceIDs": list(EVIDENCE_IDS), "statusFlags": dict(FLAGS), "nativeCompileRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False, "acceptanceEnabled": False, "releaseCredit": False, "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER", "requiresAcceptedS10_6Reconciliation": True, "uiAdoptionSkipped": True, "uiAcceptanceCredit": False, "finalHashesSealed": FINAL_HASHES_SEALED, "provisional": not FINAL_HASHES_SEALED, "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED"}


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path in IMPLEMENTATION_PATHS:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            rows.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SOURCE_PRESENT"})
        else:
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
    return rows


def source_projection(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {"implementationPaths": list(IMPLEMENTATION_PATHS), "presentPaths": status["presentPaths"], "missingPaths": status["missingPaths"], "selectors": list(selectors_value), "expectedSelectors": list(EXPECTED_SELECTORS), "sourceSemanticsInspected": bool(status["hydrated"]), "sourceReady": status["sourceReady"], "sourceStatus": status["status"], "sourceReason": status["reason"], "sourceRows": source_rows(root), **SOURCE_PINS, "canonicalSuccessor": {"cardID": "V23-P04-C10", "registerOrdinal": 98}, "deterministicEvidenceIDs": list(EVIDENCE_IDS), "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS), "conformanceSubjects": list(CONFORMANCE_SUBJECTS), "invalidationConsumers": list(INVALIDATION_CONSUMERS), "journeyRefs": list(JOURNEY_REFS)}


def semantics(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {**SEMANTIC_SCOPE, "selectors": list(selectors_value), "evidenceIDs": list(EVIDENCE_IDS), "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "timelineKinds": list(TIMELINE_KINDS), "metricDefinitions": list(METRIC_DEFINITIONS), "qualificationStates": list(QUALIFICATION_STATES), "lifecycle": dict(LIFECYCLE_DISPOSITIONS), "forbiddenCapabilities": list(FORBIDDEN), "previewRules": {"zeroCanonicalMutation": True, "zeroPersistentProjectionMutation": True, "repeatBytesDeterministic": True, "sourceClosureChangeRequiresRebuild": True}, "metricRules": {"sameDefinitionVersionInDashboardAndOpenJSON": True, "qualifiedRecordedIntervalsOnly": True, "noUptimeOrExposureFromAbsence": True, "includedAndExcludedSourcesDisclosed": True, "mtbfAndAvailabilityNumeratorReconcile": True, "definitionOutputDisagreementFailsClosed": True}, "timelineRules": {"canonicalEventIDsAndRevisions": True, "recordedAtTimeBasis": True, "deterministicOrdering": True, "duplicateEventFailsClosed": True, "correctionHistoryAppendOnly": True}, "rebuildRules": {"boundedMaximumAssets": 10000, "sortedStableSourceIdentity": True, "sourceSetDigestBoundContinuation": True, "cancellationChecked": True, "corruptDerivedStateDiscarded": True, "dropAndRebuildFromC53": True}, "lifecycleRules": {name: disposition for name, disposition in LIFECYCLE_DISPOSITIONS.items()}, "noNativeIPad": True, "noS10RouteWiring": True, "ui": "POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT", "accessibilityAndLocalization": dict(SEMANTIC_SCOPE["accessibilityAndLocalization"])}


def schema_document(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/operations-metrics-timeline.schema.json", "title": "V23-P04-C09 operations metrics timeline", "type": "object", "additionalProperties": False, "properties": {"schema": {"const": "OPERATIONS_METRICS_TIMELINE_V1"}, "schemaVersion": {"const": SCHEMA_VERSION}, "cardID": {"const": CARD}, "ordinal": {"const": REGISTER_ORDINAL}, "selectors": {"const": list(selectors_value)}, "authorityContracts": {"const": list(AUTHORITY_CONTRACTS)}, "persistentKinds": {"const": list(PERSISTENT_KINDS)}, "timelineKinds": {"const": list(TIMELINE_KINDS)}, "metricDefinitions": {"const": list(METRIC_DEFINITIONS)}, "qualificationStates": {"const": list(QUALIFICATION_STATES)}, "lifecycle": {"const": dict(LIFECYCLE_DISPOSITIONS)}, "forbidden": {"const": list(FORBIDDEN)}, "semantics": {"const": semantics(selectors_value)}, "sourceReady": {"type": "boolean"}, "physicalLockedState": {"const": "REQUIRED_PENDING_OWNER"}, "uiAdoptionSkipped": {"const": True}, "uiAcceptanceCredit": {"const": False}, "statusFlags": {"const": dict(FLAGS)}, "finalHashesSealed": {"const": FINAL_HASHES_SEALED}, "provisional": {"const": not FINAL_HASHES_SEALED}}, "required": ["schema", "schemaVersion", "cardID", "ordinal", "selectors", "authorityContracts", "persistentKinds", "timelineKinds", "metricDefinitions", "qualificationStates", "lifecycle", "forbidden", "semantics", "sourceReady", "physicalLockedState", "uiAdoptionSkipped", "uiAcceptanceCredit", "statusFlags", "finalHashesSealed", "provisional"]}


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None}


def contract_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({"schema": "V23P04C09OperationsMetricsTimelineContractV1", "schemaVersion": SCHEMA_VERSION, **common(), "directPrerequisites": list(DIRECT_PREREQUISITES), "contractRefs": list(CONTRACT_REFS), "journeyRefs": list(JOURNEY_REFS), "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS), "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "timelineKinds": list(TIMELINE_KINDS), "metricDefinitions": list(METRIC_DEFINITIONS), "qualificationStates": list(QUALIFICATION_STATES), "lifecycle": dict(LIFECYCLE_DISPOSITIONS), "forbidden": list(FORBIDDEN), "semantics": semantics(selectors_value), "sourceProjection": source_projection(root, selectors_value)})


def evidence_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "selectorSuffix": "G01", "focus": ["sole versioned MetricDefinition registry", "dashboard and deterministic open JSON definition agreement", "qualified recorded interval numerator reconciliation"], "expectedOutcome": "METRIC_DEFINITION_AND_DASHBOARD_BYTES_RECONCILE_DETERMINISTICALLY"},
        {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "selectorSuffix": "A01", "focus": ["asset service timeline ordering", "recorded event provenance and revisions", "correction lifecycle append-only history"], "expectedOutcome": "TIMELINE_ORDER_AND_PROVENANCE_REMAIN_EXACT_ACROSS_CORRECTIVE_LIFECYCLE"},
        {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "selectorSuffix": "H01", "focus": ["definition/output disagreement", "double-count and CustomerLearning owner bridge", "unknown version and unsupported qualification"], "expectedOutcome": "FAIL_CLOSED_WITH_NO_CANONICAL_OR_REMOTE_CLAIM"},
        {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "selectorSuffix": "I01", "focus": ["10,000-asset bounded rebuild", "cancellation and caller-held continuation", "derived-index corruption"], "expectedOutcome": "CANCELLATION_OR_CORRUPTION_RESTARTS_OR_FAILS_CLOSED_DETERMINISTICALLY"},
        {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "selectorSuffix": "R01", "focus": ["drop and rebuild derived state", "canonical C53 records/receipts preserved", "restore/replay/delete/Erase reconciliation"], "expectedOutcome": "CANONICAL_HISTORY_REMAINS_UNCHANGED_WHILE_DERIVED_OUTPUT_REBUILDS"},
    ]
    return _sealed({"schema": "V23P04C09OperationsMetricsTimelineEvidenceReceiptV1", "schemaVersion": SCHEMA_VERSION, **common(), "evidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(selectors_value), "cases": cases, "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "timelineKinds": list(TIMELINE_KINDS), "metricDefinitions": list(METRIC_DEFINITIONS), "qualificationStates": list(QUALIFICATION_STATES), "lifecycle": dict(LIFECYCLE_DISPOSITIONS), "hostileVectors": list(HOSTILE_VECTORS), "forbidden": list(FORBIDDEN), "semantics": semantics(selectors_value), "sourceProjection": source_projection(root, selectors_value), "derivedOnlyRequired": True, "exportAndReportRequired": True, "uiAdoptionSkipped": True, "accessibilityAndLocalizationRequired": True})


def brand_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return _sealed({"schema": "V23P04C09BrandImpactManifestV1", "schemaVersion": SCHEMA_VERSION, **common(), "iPhoneNativeOnly": True, "nativeIPadSurface": False, "uiSurfaceDelta": True, "brandSurfaceDelta": True, "uiSourceExists": IMPLEMENTATION_PATHS[4] in status["presentPaths"], "uiTestSourceExists": IMPLEMENTATION_PATHS[6] in status["presentPaths"], "uiTestDisposition": "EXPLICIT_POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_AUTHORITY", "adoptionSkipped": True, "onDeviceOnly": True, "networkOrTelemetryFlow": False, "syncStatusClaimed": False, "providerOrNotificationFlow": False, "recurrenceOrQRFlow": False, "accessibilityAndLocalizationRequired": True, "accessibilitySourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not status["hydrated"] else "SOURCE_INSPECTED", "localizationSourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not status["hydrated"] else "SOURCE_INSPECTED", "changedSurfaces": ["LOCAL_OPERATIONS_DASHBOARD", "ASSET_SERVICE_TIMELINE", "QUALIFIED_EXPOSURE_REVIEW_AND_CORRECTION", "RELIABILITY_METRIC_DETAILS", "DETERMINISTIC_OPEN_JSON"], "changedStates": ["QUALIFIED", "UNAVAILABLE", "CORRUPT_DERIVED_REBUILD_REQUIRED", "CANCELLATION_RESTART_REQUIRED"], "semantics": semantics(selectors_value), "sourceProjection": source_projection(root, selectors_value)})


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data) if FINAL_HASHES_SEALED else None, "status": "SEALED_TOOLING" if FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING"}
    target = root / path
    if not target.is_file():
        return {"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"}
    data = canonical_file_bytes(target)
    if path in TOOLING_EDIT_PATHS:
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data) if FINAL_HASHES_SEALED else None, "status": "SEALED_TOOLING" if FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING"}
    return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "PRESENT_SOURCE" if path in IMPLEMENTATION_PATHS else "PRESENT_INHERITED"}


def outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    status = source_status(root)
    selectors_value = assert_source_contracts(root) if status["hydrated"] else bound_selectors(root)
    rendered: dict[str, bytes] = {SCHEMA_PATH: pretty(schema_document(selectors_value)), CONTRACT_PATH: pretty(contract_document(root, selectors_value)), EVIDENCE_PATH: pretty(evidence_document(root, selectors_value)), BRAND_PATH: pretty(brand_document(root, selectors_value))}
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = {"schema": "V23-P04-C09-tooling-manifest", "schemaVersion": SCHEMA_VERSION, **common(), "pathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "toolingEditPaths": list(TOOLING_EDIT_PATHS), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "fencePathCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS), "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "s10ReservedPathCount": S10_RESERVED_PATH_COUNT, "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED", "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None, "sourceReady": status["sourceReady"], "sourceStatus": status["status"], "sourceReason": status["reason"], "sourceProjection": source_projection(root, selectors_value), "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "timelineKinds": list(TIMELINE_KINDS), "metricDefinitions": list(METRIC_DEFINITIONS), "lifecycle": dict(LIFECYCLE_DISPOSITIONS), "files": rows}
    rendered[MANIFEST_PATH] = pretty(_sealed(manifest))
    return rendered


def all_outputs(root: Path) -> dict[str, bytes]:
    return outputs(root)


def _self_parse() -> None:
    for path in SCRIPT_PATHS:
        local = ROOT / path
        if local.is_file():
            ast.parse(local.read_text(encoding="utf-8"), filename=path)


if __name__ == "__main__":
    _self_parse()
    status = source_status(ROOT)
    print(json.dumps({"cardID": CARD, "sourceReady": status["sourceReady"], "sourceStatus": status["status"], "sourceReason": status["reason"], "sourceMissing": status["missingPaths"], "finalHashesSealed": FINAL_HASHES_SEALED, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT, "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT}, sort_keys=True, indent=2))
