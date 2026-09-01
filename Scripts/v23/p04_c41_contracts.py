#!/usr/bin/env python3
"""Deterministic tooling authority for V23-P04-C41 My Day.

This lane records the bounded My Day workflow contract and its evidence
without becoming another plan store, scheduler, route engine, writer, or
source of due/readiness truth.  The generated artifacts are deliberately
static and unsealed until the card's source, test, and UI lanes have their
own acceptance evidence.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C41"
ORDINAL = 129
TITLE = "My Day local planning, manual ordering, readiness/duration cues, resume, carryover, and due-work reconciliation"
BASE = "4614507edcf811e9e6ac344b2a8b24aa8fd615ba"
BASE_TREE = "3ba84fa4c78c28a05713edf1e722da66f78b8512"
COORDINATION_HEAD = "faff7da3f861319d97c6c5d340e31b6f71671027"
COORDINATION_TREE = "56040236d7b4a3e46c632532a825d654ae4a7336"
SEQUENCE = 564
ALLOCATION_DIGEST = "403254f93c8278d271623e978ee745050f14e0fa10d5b69e9c3c883249772703"
PREREQUISITE_DIGEST = "191c39534f95436ba49d941d7fbacabcfda8262f31a05f04ae308e9cef98c1fb"
CONTEXT_DIGEST = "d3beeb077fbae5b2c3f89aae1b0a9bba0607cf33505faefd017f7bcce9b0f4b2"
FENCE_DIGEST = "0fd62083ef3757e5d27f4e843b7f76560bfb101c5b10a7a355abb0237a3f3250"
TRANSITION_DIGEST = "37041917308eb3aca0cd0bbe285ceb53c1272d641ae62b26ebab976b49a5ae62"
LEDGER_DIGEST = "71976ecf16483441a1f233e4cdcb0a89b93d15fd816150cd0b4c50e23e55135f"
PROJECTION_DIGEST = "f89e10337eea5cc59c27c9d6f93a13096c433f06277f1bd83e66fbc8b04958f9"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
TRANSITION_PATH = "transitions/000564-V23-P04-C41-attempt-1-NOT_STARTED-to-HYDRATING.json"
FINAL_HASHES_SEALED = False

# Generic aliases retained for callers that consume all v23 tooling modules.
HEAD = COORDINATION_HEAD
CTREE = COORDINATION_TREE
SEQ = SEQUENCE
ALLOCATION = ALLOCATION_DIGEST
PREREQ = PREREQUISITE_DIGEST
CONTEXT = CONTEXT_DIGEST
FENCE = FENCE_DIGEST
TRANSITION = TRANSITION_DIGEST
LEDGER = LEDGER_DIGEST
PROJECTION = PROJECTION_DIGEST
S10 = FROZEN_S10_DIGEST

EXISTING_PATHS = (
    "FieldEvidenceApp/Application/MyDay/MyDayCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/WorkspaceExperience/WorkspaceExperienceContractsV1.swift",
    "FieldEvidenceApp/Application/WorkspaceExperience/WorkspaceExperienceCoordinatorV1.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
)
NEW_PRODUCT_PATHS = (
    "FieldEvidenceApp/Domain/MyDay/MyDayWorkflowContractsV1.swift",
    "FieldEvidenceApp/Application/MyDay/MyDayWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/MyDay/MyDayWorkflowView.swift",
    "FieldEvidenceAppTests/V9_104MyDayWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/MyDay/V23P04C41MyDayWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C41MyDayWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c41_contracts.py",
    "Scripts/v23/generate_p04_c41_contracts.py",
    "Scripts/v23/verify_p04_c41_contracts.py",
)
SCHEMA = "Scripts/v23/my-day-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C41MyDayWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C41MyDayWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C41BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C41-tooling-manifest.json"
TOOLING_PATHS = (*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
NEW = (*NEW_PRODUCT_PATHS, *TOOLING_PATHS)
PATH_FENCE = (*EXISTING_PATHS, *NEW)
OWNED = frozenset(TOOLING_PATHS)
PRODUCT = (*EXISTING_PATHS, *NEW_PRODUCT_PATHS)
SOURCE_PATHS = PRODUCT
NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT = 7
NEW_TOOLING_DOCUMENTATION_PATH_COUNT = 8

DIRECT_PREREQUISITES = ["V23-P03-C57", "V23-P04-C12", "V23-P04-C22"]
AGGREGATE_MEMBERSHIPS = [
    "AutonomousRequiredAcceptedSetV1",
    "P04ShippingSurfaceSetV1",
    "P04BrandClosureSetV1",
]
INVALIDATION_CONSUMERS = [
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
]
CONTRACT_REFS = [
    "MyDaySummaryProjectionV1",
    "MyDayRestoreDispositionV1",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
]

SELECTOR_ROWS = (
    ("G01", "V23-P04-C41-G01", "GOLDEN"),
    ("A01", "V23-P04-C41-A01", "ALTERNATE"),
    ("H01", "V23-P04-C41-H01", "HOSTILE"),
    ("I01", "V23-P04-C41-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C41-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)
SHORT_SELECTORS = tuple(row[0] for row in SELECTOR_ROWS)

ELIGIBLE_REFERENCE_KINDS = [
    "WORK_PACKET",
    "ROUND_SESSION",
    "SCHEDULE_OCCURRENCE",
    "RESUMABLE_DRAFT",
]
SOURCE_STATES = ["ACTIVE", "COMPLETED", "CANCELLED", "RETIRED", "MISSING", "STALE", "REOPENED"]
READINESS_STATES = ["READY", "NOT_READY", "BLOCKED", "UNAVAILABLE"]
SUMMARY_FIELDS = [
    "SELECTED_COUNT",
    "READY_COUNT",
    "BLOCKED_COUNT",
    "UNAVAILABLE_COUNT",
    "DUE_COUNT",
    "ESTIMATED_MINUTES",
]
CARRYOVER = {
    "explicitOnly": True,
    "eligibleStates": ["ACTIVE", "REOPENED"],
    "excludedStates": ["COMPLETED", "CANCELLED", "RETIRED", "MISSING", "STALE"],
    "preservesMembershipIdentity": True,
    "preservesManualOrder": True,
    "preservesOptionalEstimate": True,
}
HOSTILE_CASES = [
    "STALE_PLAN_FRONTIER",
    "WRONG_WORKSPACE_REFERENCE",
    "DUPLICATE_REFERENCE",
    "DUPLICATE_MEMBERSHIP_ID",
    "NONCONTIGUOUS_MANUAL_ORDER",
    "AUTOMATIC_SORT_ATTEMPT",
    "SOURCE_SCHEDULE_MUTATION_ATTEMPT",
    "DIVERGENT_SAME_MUTATION_ID",
    "FORGED_SOURCE_DIGEST",
    "CROSS_DATE_NATURAL_KEY_COLLISION",
]
INTERRUPTION_BOUNDARIES = [
    "BEFORE_EFFECT",
    "AFTER_EFFECT_BEFORE_RECEIPT",
    "AFTER_RECEIPT_BEFORE_RETURN",
]
LIFECYCLE = {
    "replaceRestorePreservesExactPlans": True,
    "configurationCloneOmitsPlans": True,
    "workspaceForkRetainsNonactiveHistoryOnly": True,
    "erasePurgesMyDayTruth": True,
    "sourceNamespacesRemainIndependent": True,
    "sourceHistoryIsNeverRewritten": True,
}
CLAIMS = {
    "automaticCarryover": False,
    "automaticSorting": False,
    "automaticScheduling": False,
    "sourceMutation": False,
    "storedReadinessProjection": False,
    "storedSummaryProjection": False,
    "estimatedDurationIsActualDuration": False,
    "hostedDependency": False,
}

CORPUS_SCHEMA = "V23P04C41MyDayWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema",
        "schemaVersion",
        "cardID",
        "testOnly",
        "synthetic",
        "evidenceIDs",
        "selectors",
        "eligibleReferenceKinds",
        "sourceStates",
        "readinessStates",
        "summaryFields",
        "carryover",
        "hostileCases",
        "interruptionBoundaries",
        "lifecycle",
        "claims",
    )
)

SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "evidenceID": "V23-P04-C41-G01",
        "focus": "MANUAL_ORDER_ZERO_WRITE_PREVIEW_DERIVED_SUMMARY_DUE_READINESS_DURATION_AND_TYPED_START_RESUME",
        "expectedEffects": {
            "draftIsZeroWrite": True,
            "manualOrderIsSoleOrderAuthority": True,
            "automaticPrioritization": False,
            "summaryProjection": "DERIVED_NONPERSISTENT_REBUILDABLE",
            "routeIntent": "TYPED_START_OR_RESUME_WITHOUT_ROUTE_SIDE_EFFECT",
        },
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "evidenceID": "V23-P04-C41-A01",
        "focus": "EXPLICIT_CARRYOVER_AND_RECONCILIATION_PRESERVING_MEMBERSHIP_ORDER_ESTIMATE_AND_SOURCE_NAMESPACE",
        "expectedEffects": {
            "carryover": "EXPLICIT_ONLY",
            "eligibleStates": ["ACTIVE", "REOPENED"],
            "preserves": ["MEMBERSHIP_IDENTITY", "MANUAL_ORDER", "OPTIONAL_ESTIMATE"],
            "sourceTruthMutation": False,
            "reconcile": "INCUMBENT_C57_REPLAY_AND_RECEIPT_SEAM",
        },
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "evidenceID": "V23-P04-C41-H01",
        "focus": "STALE_SCOPE_DUPLICATE_ORDER_DIGEST_MUTATION_AND_NATURAL_KEY_FAILURES_WITHOUT_PARTIAL_CANONICAL_SUCCESS",
        "expectedEffects": {
            "invalidInput": "FAIL_CLOSED",
            "automaticSort": "REJECT",
            "sourceMutation": "REJECT",
            "divergentMutation": "REJECT",
            "claims": "ALL_FALSE",
        },
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "evidenceID": "V23-P04-C41-I01",
        "focus": "ZERO_WRITE_PREVIEW_EFFECT_BEFORE_RECEIPT_IDEMPOTENT_RETRY_AND_EXPLICIT_RECONCILIATION",
        "expectedEffects": {
            "preview": "ZERO_WRITE",
            "retry": "SAME_EFFECT_OR_NO_EFFECT",
            "effectBeforeReceipt": "RECOVER_WITH_INCUMBENT_WRITER",
            "afterReceipt": "RETURN_EXISTING_RECEIPT",
        },
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "evidenceID": "V23-P04-C41-R01",
        "focus": "REBUILDABLE_SUMMARY_RESTORE_CLONE_FORK_ERASE_SOURCE_NAMESPACE_AND_HISTORY_TRUTH",
        "expectedEffects": {
            "summary": "REBUILD_FROM_C57_C22_C12_SOURCES",
            "restore": "PRESERVE_EXACT_PLANS",
            "clone": "OMIT_PLANS",
            "fork": "RETAIN_NONACTIVE_HISTORY_ONLY",
            "erase": "PURGE_MY_DAY_TRUTH",
            "sourceHistory": "NEVER_REWRITE",
        },
    },
)

FLAGS = {
    name: False
    for name in (
        "native",
        "hosted",
        "physicalDevice",
        "adoption",
        "acceptance",
        "release",
        "nativeAcceptance",
        "hostedAcceptance",
        "physicalEvidence",
        "adoptionEvidence",
        "acceptanceCredit",
        "releaseReadiness",
        "phase10PollingDuringParallelExecution",
    )
}

SOURCE_PINS = {
    "V23-P04-C41": (6916, "f47b86204b1bc08c9dfecad534787d50dd927479f021251427aba2b99b8ba634"),
    "V23-P04-C41-register": (320, "3424fddd0018c1074502c726574498f027614a8ffe8413b4766c2bdd03357b35"),
    "V23-P04-C41-acceptance-rows": (3061, "c0657188037c448e302d339c8a1f315824d1de9d01d3d59f3e70ea8d626b8551"),
    "V23-P04-C41-lineage": (94, "539e9980753e30fa2acf0acde392e5e57f71b17af6de8ca52cc416c14103a6b8"),
}
SOURCE_PROJECTION = {
    "acceptedExpansionHead": BASE,
    "acceptedExpansionTree": BASE_TREE,
    "canonicalSuccessor": {"cardID": "V23-P04-C42", "registerOrdinal": 130},
    "dossierSlices": [
        {
            "byteCount": 6916,
            "startLine": 8480,
            "endLine": 8539,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
            "sha256": SOURCE_PINS["V23-P04-C41"][1],
        },
        {
            "byteCount": 320,
            "startLine": 310,
            "endLine": 310,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": SOURCE_PINS["V23-P04-C41-register"][1],
        },
        {
            "byteCount": 3061,
            "startLine": 1614,
            "endLine": 1623,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": SOURCE_PINS["V23-P04-C41-acceptance-rows"][1],
        },
        {
            "byteCount": 94,
            "startLine": 3134,
            "endLine": 3134,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": SOURCE_PINS["V23-P04-C41-lineage"][1],
        },
    ],
    "outcome": "MY_DAY_LOCAL_PLANNING_MANUAL_ORDER_READINESS_DURATION_CUES_RESUME_CARRYOVER_AND_DUE_WORK_RECONCILIATION_WITHOUT_DASHBOARD_ROOT_ROUTE_ENGINE_AUTOMATIC_PRIORITIZATION_OR_HIDDEN_SCHEDULE_MUTATION",
    "sourceAuthorityMode": "PINNED_BLUEPRINT_FOUNDATION_AND_READ_ONLY_ACCEPTED_APP_OWNER_INVENTORY",
}


def pretty(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def _git_bytes(*args: str, cwd: Path = ROOT) -> bytes:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True).stdout


def _duplicate_reject(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path: str | Path) -> Any:
    target = Path(path)
    if not target.is_absolute():
        target = ROOT / target
    try:
        return json.loads(target.read_bytes().decode("utf-8"), object_pairs_hook=_duplicate_reject)
    except FileNotFoundError as error:
        raise ValueError(f"missing JSON: {target.as_posix()}") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"malformed JSON: {target.as_posix()}") from error


def _coordination_root() -> Path | None:
    value = os.environ.get("V23_P04_C41_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _line_slice(raw: bytes, start: int, end: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    return b"".join(lines[start - 1 : end])


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C41 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    values = (
        ("V23-P04-C41", _line_slice(blueprint, 8480, 8539)),
        ("V23-P04-C41-register", _line_slice(foundation, 310, 310)),
        ("V23-P04-C41-acceptance-rows", _line_slice(foundation, 1614, 1623)),
        ("V23-P04-C41-lineage", _line_slice(foundation, 3134, 3134)),
    )
    result: list[dict[str, Any]] = []
    for anchor, value in values:
        expected_length, expected_sha = SOURCE_PINS[anchor]
        measured = (len(value), sha(value))
        if measured != (expected_length, expected_sha):
            raise ValueError(f"source pin drift: {anchor} expected={(expected_length, expected_sha)} actual={measured}")
        result.append({"anchor": anchor, "utf8Length": measured[0], "sha256": measured[1]})
    return result


def _require(value: Any, expected: Any, label: str) -> None:
    if value != expected:
        raise ValueError(f"{label} drift")


def _false_keys(document: dict[str, Any]) -> None:
    for key in (
        "acceptanceCredit",
        "acceptanceEnabled",
        "adoptionEnabled",
        "hostedDispatchEnabled",
        "hostedDispatchRan",
        "nativeCompileRan",
        "physicalDeviceEnabled",
        "publicationEnabled",
        "releaseCredit",
        "releaseReady",
        "phase10PollingDuringParallelExecution",
    ):
        _require(document.get(key), False, key)


def _coordination_evidence(root: Path) -> None:
    _require(git("rev-parse", "HEAD", cwd=root), COORDINATION_HEAD, "coordination HEAD")
    _require(git("rev-parse", "HEAD^{tree}", cwd=root), COORDINATION_TREE, "coordination tree")
    context = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json")
    fence = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    transition = read_json(root / TRANSITION_PATH)
    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    projection = read_json(root / "projections/ActiveWorkSetProjectionV1.json")

    blockers = [
        "DIRECT_RECEIPTS_PROVISIONAL_ZERO_ACCEPTANCE_CREDIT",
        "ACCEPTED_S10_6_RECONCILIATION_PENDING",
        "NATIVE_COMPILE_UNIT_UI_RECOVERY_AND_HOSTED_RUNS_NOT_RUN",
    ]
    _require((context.get("cardID"), context.get("attemptID"), context.get("registerOrdinal")), (CARD, 1, ORDINAL), "context identity")
    _require(context.get("title"), TITLE, "context title")
    _require(context.get("classification"), "IMPLEMENT_NOW", "context classification")
    _require(context.get("contextDigest"), CONTEXT_DIGEST, "context digest")
    _require(context.get("ownerAuthorizedPathAllocationDigest"), ALLOCATION_DIGEST, "context allocation")
    _require(context.get("provisionalPrerequisiteDigest"), PREREQUISITE_DIGEST, "context prerequisite")
    _require(context.get("repository"), {"appBaseHead": BASE, "appBaseTree": BASE_TREE}, "context repository")
    _require(context.get("acceptanceBlockers"), blockers, "context blockers")
    _false_keys(context)
    _require(context.get("planningStatus"), "NOT_STARTED", "context planning status")
    _require(context.get("lineage"), {"disposition": "ADDED_V23"}, "context lineage")
    _require(context.get("directPrerequisites"), DIRECT_PREREQUISITES, "context prerequisites")
    proof = {
        "allAcceptanceCreditFalse": True,
        "duplicateCount": 0,
        "expectedDirectEdgeCount": 3,
        "failedIntermediateAcceptanceCount": 0,
        "incompatibleCount": 0,
        "missingCount": 0,
        "observedDirectEdgeCount": 3,
        "orphanCount": 0,
        "staleCount": 0,
        "uniqueCardCount": 3,
    }
    _require(context.get("directPrerequisiteProof"), proof, "context prerequisite proof")
    _require(context.get("existingPaths"), list(EXISTING_PATHS), "context existing paths")
    _require(context.get("newPaths"), list(NEW), "context new paths")
    _require(context.get("expectedArtifacts"), list(PATH_FENCE), "context artifact fence")
    _require(context.get("persistenceDecision"), {
        "automaticPrioritization": False,
        "existingFixtureHarnessOwner": EXISTING_PATHS[3],
        "existingMyDayCoordinatorOwner": EXISTING_PATHS[0],
        "existingTodayCompositionContractOwner": EXISTING_PATHS[1],
        "existingTodayCompositionCoordinatorOwner": EXISTING_PATHS[2],
        "hiddenScheduleMutation": False,
        "newDurableFamilyCount": 0,
        "newMigrationCount": 0,
        "newModelCount": 0,
        "newRouteEngineCount": 0,
        "newSchemaCount": 0,
        "newSummaryProjectionIsDerivedNonpersistent": True,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "persistedExceptionMembership": False,
    }, "context persistence")
    _require(context.get("sourceProjection"), SOURCE_PROJECTION, "context source projection")
    _require(context.get("requiresAcceptedS10_6Reconciliation"), True, "context S10 reconciliation")

    for key, expected in {
        "cardID": CARD,
        "attemptID": 1,
        "baseHead": BASE,
        "baseTree": BASE_TREE,
        "fenceDigest": FENCE_DIGEST,
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "frozenS10ReservationDigest": FROZEN_S10_DIGEST,
    }.items():
        _require(fence.get(key), expected, f"fence {key}")
    _false_keys(fence)
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C41 path overlaps S10 reservation")
    prior = fence.get("priorFenceProof", {})
    for key, expected in {
        "authorizationBasis": "C57_MYDAY_CANONICAL_SEAM_WORKSPACE_EXPERIENCE_TODAY_COMPOSITION_AND_SHARED_TEST_SUPPORT_OWNER_AUTHORIZATION",
        "authorizedOverlapEdgeCount": 5,
        "fenceCount": 131,
        "inheritedExistingPathEnvelopeOverlapCount": 29,
        "overlapEdgeCount": 34,
        "priorFenceSetDigest": "5b2fd8e0a85788d8995b5de2c42e821ab9e06c1527efcec18d5e49f9c14400b5",
        "priorOwnedPathCount": 4,
        "s10ReservedOverlapCount": 0,
        "unauthorizedOverlapCount": 0,
    }.items():
        _require(prior.get(key), expected, f"prior fence {key}")

    _require(allocation.get("cardID"), CARD, "allocation card")
    _require(allocation.get("allocationDigest"), ALLOCATION_DIGEST, "allocation digest")
    _require(allocation.get("exactOrderedPaths"), list(PATH_FENCE), "allocation paths")
    _require(allocation.get("existingPaths"), list(EXISTING_PATHS), "allocation existing")
    _require(allocation.get("newPaths"), list(NEW), "allocation new")
    # The receipt counts only the six newly-created product/test/UI/fixture
    # files; the corrected fence/manifest count reports the shared harness as
    # the seventh product/test/UI/fixture path.
    _require(allocation.get("newProductTestUIFixturePathCount"), 6, "allocation product count")
    _require(allocation.get("newToolingDocumentationPathCount"), 8, "allocation tooling count")
    _require(allocation.get("s10ReservedOverlapCount"), 0, "allocation S10 overlap")
    _false_keys(allocation)
    _require(allocation.get("persistenceDecision"), context["persistenceDecision"], "allocation persistence")
    _require(allocation.get("sourceProjection"), SOURCE_PROJECTION, "allocation source projection")

    _require(prerequisite.get("prerequisiteDigest"), PREREQUISITE_DIGEST, "prerequisite digest")
    _require(prerequisite.get("successorCardID"), CARD, "prerequisite successor")
    _require(prerequisite.get("canonicalDirectPrerequisiteCardIDs"), DIRECT_PREREQUISITES, "prerequisite cards")
    _require(prerequisite.get("ordinaryDirectEdgeCount"), 3, "prerequisite edge count")
    _require(prerequisite.get("directPrerequisiteProof"), proof, "prerequisite proof")
    _require(prerequisite.get("acceptanceCredit"), False, "prerequisite acceptance")
    _require(prerequisite.get("immediateSequentialPredecessor"), {
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": "V23-P04-C40",
        "checkpointDigest": "6187c8227df154f0ad4155f5ec2a95b9dc54cb5a738889b445b674061204b38c",
        "verificationReceiptDigest": "654da2777b64b1fd536c1cdfa60467424d0855cd8a2da37a76261fba1adc1498",
    }, "immediate predecessor")

    _require(transition.get("schema"), "BootstrapStateTransitionV1", "transition schema")
    for key, expected in {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "fromState": "NOT_STARTED",
        "toState": "HYDRATING",
        "newLedgerDigest": LEDGER_DIGEST,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "sequence": SEQUENCE,
        "transitionDigest": TRANSITION_DIGEST,
    }.items():
        _require(transition.get(key), expected, f"transition {key}")
    _require(transition.get("directPrerequisiteCheckpointDigests"), [
        "876b8d3f0c358efa28c188ad88e5bd0f579845c17fa54febe8692a3c63419824",
        "640d2ad9ded5b1118f33b985db245ed1798beeb3281c71211b2c94653eef7932",
        "09a12729c1c567372fb0b4f5d055f7af6f62e99993cf54b7b9c63f85553b4bd0",
    ], "transition prerequisite checkpoints")

    _require(ledger.get("casSequence"), SEQUENCE, "ledger sequence")
    _require(ledger.get("ledgerDigest"), LEDGER_DIGEST, "ledger digest")
    active = next((entry for entry in ledger.get("attempts", []) if entry.get("cardID") == CARD), None)
    _require(bool(active), True, "ledger C41 attempt")
    if active:
        for key, expected in {
            "attemptID": 1,
            "cardID": CARD,
            "ordinal": ORDINAL,
            "classification": "IMPLEMENT_NOW",
            "candidateHead": BASE,
            "candidateTree": BASE_TREE,
            "contextDigest": CONTEXT_DIGEST,
            "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
            "pathFenceDigest": FENCE_DIGEST,
            "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
            "directPrerequisites": DIRECT_PREREQUISITES,
            "planningStatus": "NOT_STARTED",
            "state": "HYDRATING",
            "automaticPrioritization": False,
            "hiddenScheduleMutation": False,
            "newDurableFamilyCount": 0,
        }.items():
            _require(active.get(key), expected, f"ledger {key}")
    _require(projection.get("ledgerDigest"), LEDGER_DIGEST, "projection ledger")
    _require(projection.get("projectionDigest"), PROJECTION_DIGEST, "projection digest")
    _require((projection.get("nextEligibleCardID"), projection.get("nextEligibleRegisterOrdinal")), (None, None), "projection next eligible")
    projected = next((entry for entry in projection.get("activeEntries", []) if entry.get("cardID") == CARD), None)
    _require(bool(projected), True, "projection C41 attempt")
    if projected:
        for key, expected in {
            "attemptID": 1,
            "cardID": CARD,
            "ordinal": ORDINAL,
            "candidateHead": BASE,
            "candidateTree": BASE_TREE,
            "contextDigest": CONTEXT_DIGEST,
            "pathFenceDigest": FENCE_DIGEST,
            "state": "HYDRATING",
            "stateReason": "P04_C41_MY_DAY_LOCAL_PLANNING_MANUAL_ORDER_READINESS_RESUME_CARRYOVER_DUE_WORK_RECONCILIATION_HYDRATING",
        }.items():
            _require(projected.get(key), expected, f"projection {key}")


def authority() -> dict[str, Any]:
    source_pins = _source_slices()
    result = {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": ORDINAL,
        "title": TITLE,
        "appBaseHead": BASE,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "sequence": SEQUENCE,
        "allocationDigest": ALLOCATION_DIGEST,
        "prerequisiteDigest": PREREQUISITE_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "transitionDigest": TRANSITION_DIGEST,
        "ledgerDigest": LEDGER_DIGEST,
        "projectionDigest": PROJECTION_DIGEST,
        "fencePathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW),
        "productTestUIFixturePathCount": NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
        "toolingPathCount": NEW_TOOLING_DOCUMENTATION_PATH_COUNT,
        "authorizedOverlapCount": 5,
        "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0,
        "frozenS10ReservationDigest": FROZEN_S10_DIGEST,
        "orderedPathFence": list(PATH_FENCE),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW),
        "sourcePins": source_pins,
        "finalHashesSealed": FINAL_HASHES_SEALED,
    }
    coordination = _coordination_root()
    if coordination is None or not coordination.is_dir():
        if not (ROOT / MANIFEST).is_file():
            raise ValueError("coordination authority unavailable and no portable manifest")
        portable = read_json(ROOT / MANIFEST)
        _require(portable.get("authority"), result, "portable authority")
    else:
        _coordination_evidence(coordination)
    return result


def rows() -> tuple[list[dict[str, Any]], bool]:
    result: list[dict[str, Any]] = []
    for path in SOURCE_PATHS:
        target = ROOT / path
        present = target.is_file()
        result.append({
            "path": path,
            "status": "SOURCE_PRESENT" if present else "SOURCE_MISSING",
            "sha256": sha(target.read_bytes()) if present else None,
        })
    return result, all(row["status"] == "SOURCE_PRESENT" for row in result)


def counts() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in git(*args).splitlines() if line}

    changed = (
        names("diff", "--name-only", BASE, "HEAD")
        | names("diff", "--name-only", "HEAD")
        | names("diff", "--cached", "--name-only")
        | names("ls-files", "--others", "--exclude-standard")
    )
    allowed = set(PATH_FENCE)
    return {
        "changedPathCount": len(changed & allowed),
        "unownedChangedPathCount": len(changed - allowed),
        "missingPathCount": sum(not (ROOT / path).is_file() for path in PATH_FENCE),
        "fencePathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW),
        "productTestUIFixturePathCount": NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
        "toolingPathCount": NEW_TOOLING_DOCUMENTATION_PATH_COUNT,
        "s10ReservationOverlapCount": 0,
        "durableFamilyCount": 0,
        "modelDeltaCount": 0,
        "schemaDeltaCount": 0,
        "migrationCount": 0,
        "storeDeltaCount": 0,
        "writerDeltaCount": 0,
        "rendererDeltaCount": 0,
        "backendDeltaCount": 0,
    }


def _base_document() -> dict[str, Any]:
    auth = authority()
    source_rows, source_ready = rows()
    lifecycle = {
        "status": "IMPLEMENT_NOW",
        "policyProfile": "PERSISTENT_OR_PRODUCT_DELTA",
        "persistence": "NONPERSISTENT_DERIVED_REBUILDABLE_SUMMARY",
        "persistentSchemaVersion": "UNCHANGED_EXISTING_C57_OWNER",
        "recordsSchemaVersion": "UNCHANGED_EXISTING_C57_OWNER",
        "durableFamily": "NONE",
        "summaryProjection": "MyDaySummaryProjectionV1",
        "projectionPersistence": "NONPERSISTENT",
        "projectionDerived": True,
        "projectionRebuildable": True,
        "manualOrderOnly": True,
        "automaticPrioritization": False,
        "sourceTruthMutation": False,
        "canonicalWriterOwner": EXISTING_PATHS[0],
        "canonicalReplayOwner": EXISTING_PATHS[0],
        "todayCompositionOwner": EXISTING_PATHS[2],
        "todayCompositionContractOwner": EXISTING_PATHS[1],
        "fixtureHarnessOwner": EXISTING_PATHS[3],
        "carryoverDisposition": "EXPLICIT_ONLY",
        "reconciliationDisposition": "INCUMBENT_SOURCE_RECONCILIATION",
        "newDurableFamilyCount": 0,
        "newModelCount": 0,
        "newSchemaCount": 0,
        "newMigrationCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "newRouteEngineCount": 0,
        "newRendererCount": 0,
        "newBackendCount": 0,
        "resetDisposition": "EXISTING_LIFECYCLE_CONTRACT",
        "eraseDisposition": "EXISTING_MY_DAY_TRUTH_PURGE_CONTRACT",
        "backupRestoreDisposition": "PRESERVE_EXACT_PLANS",
        "cloneDisposition": "OMIT_PLANS",
        "forkDisposition": "RETAIN_NONACTIVE_HISTORY_ONLY",
        "sourceHistoryDisposition": "NEVER_REWRITE",
    }
    independence = {
        "entitlementIndependent": True,
        "manualOrderIsSoleAuthority": True,
        "summaryIsDerivedNonpersistent": True,
        "dueAndReadinessAreReadOnlyInputs": True,
        "c57WriterAndReplayReused": True,
        "c22AndC12ReadOnly": True,
        "typedStartResumeIntent": True,
        "explicitCarryoverAndReconcile": True,
        "newModel": False,
        "newSchema": False,
        "newStore": False,
        "newWriter": False,
        "newMigration": False,
        "newRouteEngine": False,
        "newRoot": False,
        "newRenderer": False,
        "newBackend": False,
        "newNetwork": False,
        "newTelemetry": False,
        "automaticPrioritization": False,
        "hiddenScheduleMutation": False,
        "sourceMutation": False,
        "claimsFabricated": False,
        "customerDataInTooling": False,
        "secretsInTooling": False,
    }
    return {
        "schema": "V23P04C41MyDayWorkflowToolingV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "sourceRows": source_rows,
        "sourceReady": source_ready,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "lifecycle": lifecycle,
        "independence": independence,
    }


def _requirements() -> dict[str, Any]:
    return {
        "manualOrderOnly": True,
        "automaticPrioritization": False,
        "manualMoveActions": ["UP", "DOWN", "TO_INDEX"],
        "draftPreviewZeroWrite": True,
        "summaryProjection": "MyDaySummaryProjectionV1",
        "summaryProjectionDerived": True,
        "summaryProjectionNonpersistent": True,
        "summaryProjectionRebuildable": True,
        "dueReadinessDurationCuesReadOnly": True,
        "typedExistingStartResumeIntent": True,
        "routeRequestDoesNotClaimStarted": True,
        "explicitCarryover": True,
        "carryoverEligibleStates": ["ACTIVE", "REOPENED"],
        "carryoverExcludedStates": ["COMPLETED", "CANCELLED", "RETIRED", "MISSING", "STALE"],
        "carryoverPreservesMembershipIdentity": True,
        "carryoverPreservesManualOrder": True,
        "carryoverPreservesOptionalEstimate": True,
        "explicitReconciliation": True,
        "c57CanonicalWriterAndReplayReused": True,
        "c22DueTruthReadOnly": True,
        "c12ReadinessAndResumeReadOnly": True,
        "todayCompositionOwner": EXISTING_PATHS[2],
        "todayCompositionContractOwner": EXISTING_PATHS[1],
        "canonicalWriterOwner": EXISTING_PATHS[0],
        "fixtureHarnessOwner": EXISTING_PATHS[3],
        "noNewModel": True,
        "noNewSchemaFamily": True,
        "noNewStore": True,
        "noNewWriter": True,
        "noNewMigration": True,
        "noNewRouteEngine": True,
        "noNewRoot": True,
        "noNewRenderer": True,
        "noBackend": True,
        "noNetwork": True,
        "noTelemetry": True,
        "fiveEvidenceScenarios": True,
        "scenarioSelectors": list(SELECTORS),
        "finalHashesUnsealed": True,
        "automaticCarryover": False,
        "automaticSorting": False,
        "automaticScheduling": False,
        "sourceMutation": False,
        "storedReadinessProjection": False,
        "storedSummaryProjection": False,
        "estimatedDurationIsActualDuration": False,
        "hostedDependency": False,
    }


def _corpus_expectations() -> dict[str, Any]:
    return {
        "schema": CORPUS_SCHEMA,
        "schemaVersion": 1,
        "cardID": CARD,
        "testOnly": True,
        "synthetic": True,
        "evidenceIDs": list(SELECTORS),
        "selectors": list(SHORT_SELECTORS),
        "eligibleReferenceKinds": list(ELIGIBLE_REFERENCE_KINDS),
        "sourceStates": list(SOURCE_STATES),
        "readinessStates": list(READINESS_STATES),
        "summaryFields": list(SUMMARY_FIELDS),
        "carryover": dict(CARRYOVER),
        "hostileCases": list(HOSTILE_CASES),
        "interruptionBoundaries": list(INTERRUPTION_BOUNDARIES),
        "lifecycle": dict(LIFECYCLE),
        "claims": dict(CLAIMS),
    }


def documents() -> dict[str, Any]:
    base = _base_document()
    corpus = _corpus_expectations()
    contract = {
        **base,
        "contract": "MyDayWorkflowContractV1",
        "journeyRefs": ["FJ12"],
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "aggregateMemberships": list(AGGREGATE_MEMBERSHIPS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
        "optionalCapabilityProviders": [],
        "contractRefs": list(CONTRACT_REFS),
        "requirements": _requirements(),
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusExpectations": corpus,
        "eligibleReferenceKinds": list(ELIGIBLE_REFERENCE_KINDS),
        "sourceStates": list(SOURCE_STATES),
        "readinessStates": list(READINESS_STATES),
        "summaryFields": list(SUMMARY_FIELDS),
        "carryover": dict(CARRYOVER),
        "lifecycleClaims": dict(LIFECYCLE),
        "claims": dict(CLAIMS),
        "outcome": SOURCE_PROJECTION["outcome"],
    }
    evidence = {
        **base,
        "receipt": "MyDayWorkflowEvidenceReceiptV1",
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusSchema": CORPUS_SCHEMA,
        "corpusExpectations": corpus,
        "claims": dict(CLAIMS),
        "prohibitedClaims": [
            "automatic prioritization",
            "automatic sorting",
            "automatic scheduling",
            "source schedule mutation",
            "stored due/readiness/summary projection",
            "work started merely by route intent",
            "hosted dependency",
            "native, hosted, physical-device, adoption, acceptance, or release evidence",
        ],
        "lifecycle": dict(LIFECYCLE),
        "sourceSlices": list(SOURCE_PROJECTION["dossierSlices"]),
        "canonicalWriterOwner": EXISTING_PATHS[0],
        "canonicalReplayOwner": EXISTING_PATHS[0],
        "todayCompositionOwner": EXISTING_PATHS[2],
        "zeroWritePreview": True,
        "finalHashesSealed": False,
    }
    brand = {
        "schema": "BrandImpactManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "requiresAcceptedS10_6Reconciliation": True,
        "uiAdoptionSkipped": True,
        "uiAcceptanceCredit": False,
        "nativeOrHostedAdoption": False,
        "manualOrderTruthful": True,
        "automaticPrioritizationClaim": False,
        "summaryProjectionClaim": "DERIVED_NONPERSISTENT_ONLY",
        "routeStartClaim": False,
        "carryoverAutomaticClaim": False,
        "sourceMutationClaim": False,
        "networkOrTelemetry": False,
        "newRootStoreWriterRenderer": False,
        "newModelSchemaMigration": False,
        "customerDataPresent": False,
        "customerSecretsPresent": False,
        "durableDelta": False,
    }
    schema = schema_document()
    artifact_hashes = {
        SCHEMA: sha(pretty(schema)),
        CONTRACT: sha(pretty(contract)),
        EVIDENCE: sha(pretty(evidence)),
        BRAND: sha(pretty(brand)),
    }
    manifest = {
        "schema": "V23P04C41ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": base["authority"],
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in artifact_hashes.items()],
        "sourceRows": base["sourceRows"],
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "counts": {
            "fencePathCount": len(PATH_FENCE),
            "existingPathCount": len(EXISTING_PATHS),
            "newPathCount": len(NEW),
            "productTestUIFixturePathCount": NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT,
            "toolingPathCount": NEW_TOOLING_DOCUMENTATION_PATH_COUNT,
            "durableFamilyCount": 0,
            "modelDeltaCount": 0,
            "schemaDeltaCount": 0,
            "migrationCount": 0,
            "storeDeltaCount": 0,
            "writerDeltaCount": 0,
            "rendererDeltaCount": 0,
            "backendDeltaCount": 0,
            "s10ReservationOverlapCount": 0,
        },
        "lifecycle": base["lifecycle"],
        "independence": base["independence"],
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "successor": {"cardID": "V23-P04-C42", "registerOrdinal": 130},
        "optionalProvider": "NONE",
        "scenarioEvidenceIDs": list(SELECTORS),
    }
    return {SCHEMA: schema, CONTRACT: contract, EVIDENCE: evidence, BRAND: brand, MANIFEST: manifest}


def schema_document() -> dict[str, Any]:
    hash_def = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    source_row = {
        "type": "object",
        "required": ["path", "status", "sha256"],
        "properties": {
            "path": {"type": "string"},
            "status": {"enum": ["SOURCE_PRESENT", "SOURCE_MISSING"]},
            "sha256": {"type": ["string", "null"], "pattern": "^[0-9a-f]{64}$"},
        },
        "additionalProperties": False,
    }
    flags = {
        "type": "object",
        "required": list(FLAGS),
        "properties": {name: {"const": False} for name in FLAGS},
        "additionalProperties": False,
    }
    authority_properties = {
        "cardID": {"const": CARD},
        "attemptID": {"const": 1},
        "registerOrdinal": {"const": ORDINAL},
        "title": {"const": TITLE},
        "appBaseHead": {"const": BASE},
        "appBaseTree": {"const": BASE_TREE},
        "coordinationHead": {"const": COORDINATION_HEAD},
        "coordinationTree": {"const": COORDINATION_TREE},
        "sequence": {"const": SEQUENCE},
        "allocationDigest": {"const": ALLOCATION_DIGEST},
        "prerequisiteDigest": {"const": PREREQUISITE_DIGEST},
        "contextDigest": {"const": CONTEXT_DIGEST},
        "pathFenceDigest": {"const": FENCE_DIGEST},
        "transitionDigest": {"const": TRANSITION_DIGEST},
        "ledgerDigest": {"const": LEDGER_DIGEST},
        "projectionDigest": {"const": PROJECTION_DIGEST},
        "fencePathCount": {"const": 18},
        "existingPathCount": {"const": 4},
        "newPathCount": {"const": 14},
        "productTestUIFixturePathCount": {"const": 7},
        "toolingPathCount": {"const": 8},
        "authorizedOverlapCount": {"const": 5},
        "unauthorizedOverlapCount": {"const": 0},
        "s10ReservationOverlapCount": {"const": 0},
        "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST},
        "orderedPathFence": {"type": "array", "const": list(PATH_FENCE)},
        "existingPaths": {"type": "array", "const": list(EXISTING_PATHS)},
        "newPaths": {"type": "array", "const": list(NEW)},
        "sourcePins": {"type": "array", "minItems": 4, "maxItems": 4},
        "finalHashesSealed": {"const": False},
    }
    lifecycle_properties = {
        "status": {"const": "IMPLEMENT_NOW"},
        "policyProfile": {"const": "PERSISTENT_OR_PRODUCT_DELTA"},
        "persistence": {"const": "NONPERSISTENT_DERIVED_REBUILDABLE_SUMMARY"},
        "persistentSchemaVersion": {"const": "UNCHANGED_EXISTING_C57_OWNER"},
        "recordsSchemaVersion": {"const": "UNCHANGED_EXISTING_C57_OWNER"},
        "durableFamily": {"const": "NONE"},
        "summaryProjection": {"const": "MyDaySummaryProjectionV1"},
        "projectionPersistence": {"const": "NONPERSISTENT"},
        "projectionDerived": {"const": True},
        "projectionRebuildable": {"const": True},
        "manualOrderOnly": {"const": True},
        "automaticPrioritization": {"const": False},
        "sourceTruthMutation": {"const": False},
        "canonicalWriterOwner": {"const": EXISTING_PATHS[0]},
        "canonicalReplayOwner": {"const": EXISTING_PATHS[0]},
        "todayCompositionOwner": {"const": EXISTING_PATHS[2]},
        "todayCompositionContractOwner": {"const": EXISTING_PATHS[1]},
        "fixtureHarnessOwner": {"const": EXISTING_PATHS[3]},
        "carryoverDisposition": {"const": "EXPLICIT_ONLY"},
        "reconciliationDisposition": {"const": "INCUMBENT_SOURCE_RECONCILIATION"},
        "newDurableFamilyCount": {"const": 0},
        "newModelCount": {"const": 0},
        "newSchemaCount": {"const": 0},
        "newMigrationCount": {"const": 0},
        "newStoreCount": {"const": 0},
        "newWriterCount": {"const": 0},
        "newRouteEngineCount": {"const": 0},
        "newRendererCount": {"const": 0},
        "newBackendCount": {"const": 0},
        "resetDisposition": {"const": "EXISTING_LIFECYCLE_CONTRACT"},
        "eraseDisposition": {"const": "EXISTING_MY_DAY_TRUTH_PURGE_CONTRACT"},
        "backupRestoreDisposition": {"const": "PRESERVE_EXACT_PLANS"},
        "cloneDisposition": {"const": "OMIT_PLANS"},
        "forkDisposition": {"const": "RETAIN_NONACTIVE_HISTORY_ONLY"},
        "sourceHistoryDisposition": {"const": "NEVER_REWRITE"},
    }
    independence_properties = {
        "entitlementIndependent": {"const": True},
        "manualOrderIsSoleAuthority": {"const": True},
        "summaryIsDerivedNonpersistent": {"const": True},
        "dueAndReadinessAreReadOnlyInputs": {"const": True},
        "c57WriterAndReplayReused": {"const": True},
        "c22AndC12ReadOnly": {"const": True},
        "typedStartResumeIntent": {"const": True},
        "explicitCarryoverAndReconcile": {"const": True},
        "newModel": {"const": False},
        "newSchema": {"const": False},
        "newStore": {"const": False},
        "newWriter": {"const": False},
        "newMigration": {"const": False},
        "newRouteEngine": {"const": False},
        "newRoot": {"const": False},
        "newRenderer": {"const": False},
        "newBackend": {"const": False},
        "newNetwork": {"const": False},
        "newTelemetry": {"const": False},
        "automaticPrioritization": {"const": False},
        "hiddenScheduleMutation": {"const": False},
        "sourceMutation": {"const": False},
        "claimsFabricated": {"const": False},
        "customerDataInTooling": {"const": False},
        "secretsInTooling": {"const": False},
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C41MyDayWorkflowToolingV1",
        "type": "object",
        "required": ["schema", "cardID", "ordinal", "authority", "sourceRows", "sourceReady", "flags", "finalHashesSealed", "lifecycle", "independence"],
        "properties": {
            "schema": {"const": "V23P04C41MyDayWorkflowToolingV1"},
            "cardID": {"const": CARD},
            "ordinal": {"const": ORDINAL},
            "authority": {"$ref": "#/$defs/authority"},
            "sourceRows": {"type": "array", "minItems": len(SOURCE_PATHS), "maxItems": len(SOURCE_PATHS), "items": {"$ref": "#/$defs/sourceRow"}},
            "sourceReady": {"type": "boolean"},
            "flags": {"$ref": "#/$defs/flags"},
            "finalHashesSealed": {"const": False},
            "lifecycle": {"$ref": "#/$defs/lifecycle"},
            "independence": {"$ref": "#/$defs/independence"},
            "scenarioEvidenceIDs": {"type": "array", "const": list(SELECTORS)},
        },
        "additionalProperties": True,
        "$defs": {
            "sha256": hash_def,
            "sourceRow": source_row,
            "flags": flags,
            "authority": {"type": "object", "required": list(authority_properties), "properties": authority_properties, "additionalProperties": False},
            "lifecycle": {"type": "object", "required": list(lifecycle_properties), "properties": lifecycle_properties, "additionalProperties": False},
            "independence": {"type": "object", "required": list(independence_properties), "properties": independence_properties, "additionalProperties": False},
        },
    }


if __name__ == "__main__":
    print(json.dumps(authority(), sort_keys=True, indent=2))
