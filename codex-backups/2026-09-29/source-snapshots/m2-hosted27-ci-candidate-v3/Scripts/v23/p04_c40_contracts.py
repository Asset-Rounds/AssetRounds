#!/usr/bin/env python3
"""Pinned, deterministic tooling contracts for V23-P04-C40.

The C40 lane describes the bounded manual and portable service-request
workflow.  It is deliberately a consumer of the existing service-request
writer and the purpose-namespaced portable exchange store; this module does
not add a store, importer, renderer, backend, network path, or claim.
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
CARD = "V23-P04-C40"
ORDINAL = 128
TITLE = "Manual and portable service-request capture, duplicate triage, accept/decline/convert, and customer-safe status handoff"
BASE = "43ac236be18334ba74072656697d138f0c6204bc"
BASE_TREE = "f1a12547aefcd668ef1938e79f1394a0a31d38bd"
COORDINATION_HEAD = "b0155f70e84f0626e739a3ce8fa0f04f380a658a"
COORDINATION_TREE = "0cd0c67491b8f5f15140462618f5e893ef75da70"
SEQUENCE = 560
ALLOCATION_DIGEST = "aeb9ddfc4ec0a55f0b9eedf2da0e7cdee4d6d68a0c3853f07e550a5708cd4adf"
PREREQUISITE_DIGEST = "b8cfb626306dc7430aa38b25ac2920b6fd26d4489c9008676b5ebbb6ee7284ef"
CONTEXT_DIGEST = "340dd7bb2948d19f47ea390763ac904cfa700fb65f6e9f597eddf0fb2249910e"
FENCE_DIGEST = "8cde48407a196fc41dabcef75b3e6311a7544f4bb00ebbbfd44e5f8b81a8bb99"
CORRECTION_DIGEST = "a447fe29a061aceaabc569a2171531d95c3fcee7a45f2f310c447102d36b0c83"
TRANSITION_DIGEST = "d0c9a2e3cc47688340b1def64e4f56dedccac430c779029f1cead494b3ec3381"
LEDGER_DIGEST = "2908026c89704cddc72ad8abad83f1211964b2f15010230cd5e9ebcd70fd710c"
PROJECTION_DIGEST = "b616da4f5a76e163ae957efd3514e808d7bfe5f47c9cc4acbd699730c61d5518"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
CORRECTION_RECEIPT = "receipts/V23-P04-C40-draft-purpose-test-support-hydration-fence-correction-v2.json"
CORRECTION_TRANSITION = "transitions/000560-V23-P04-C40-attempt-1-HYDRATING-to-HYDRATING-draft-purpose-test-support-fence-correction.json"
FINAL_HASHES_SEALED = False

# Generic v23 tooling aliases.
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

ALL_PATHS = (
    "FieldEvidenceApp/Application/ServiceRequests/ServiceRequestCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/ReviewExchange/PortableExchangeSessionStoreV2.swift",
    "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
    "FieldEvidenceApp/Domain/ServiceRequests/ServiceRequestWorkflowContractsV1.swift",
    "FieldEvidenceApp/Application/ServiceRequests/ServiceRequestWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/ServiceRequests/ServiceRequestWorkflowView.swift",
    "FieldEvidenceAppTests/V9_103ServiceRequestWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/ServiceRequests/V23P04C40ServiceRequestWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C40ServiceRequestWorkflowUITests.swift",
    "Scripts/v23/p04_c40_contracts.py",
    "Scripts/v23/generate_p04_c40_contracts.py",
    "Scripts/v23/verify_p04_c40_contracts.py",
    "Scripts/v23/service-request-workflow.schema.json",
    "docs/design/v23/tooling/V23P04C40ServiceRequestWorkflowContractV1.json",
    "docs/design/v23/tooling/V23P04C40ServiceRequestWorkflowEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P04C40BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P04-C40-tooling-manifest.json",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
)
EXISTING_PATHS = (
    "FieldEvidenceApp/Application/ServiceRequests/ServiceRequestCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/ReviewExchange/PortableExchangeSessionStoreV2.swift",
    "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
)
PRODUCT = (*EXISTING_PATHS, *ALL_PATHS[3:9])
ALLOCATION_PATHS = ALL_PATHS[:-1]
ALLOCATION_EXISTING_PATHS = ALLOCATION_PATHS[:3]
ALLOCATION_NEW_PATHS = ALLOCATION_PATHS[3:]
SCRIPTS = (
    "Scripts/v23/p04_c40_contracts.py",
    "Scripts/v23/generate_p04_c40_contracts.py",
    "Scripts/v23/verify_p04_c40_contracts.py",
)
SCHEMA = "Scripts/v23/service-request-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C40ServiceRequestWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C40ServiceRequestWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C40BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C40-tooling-manifest.json"
NEW = tuple(path for path in ALL_PATHS if path not in EXISTING_PATHS)
PATH_FENCE = ALL_PATHS
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = PRODUCT
NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT = 7
NEW_TOOLING_DOCUMENTATION_PATH_COUNT = 8

SELECTOR_ROWS = (
    ("G01", "V23-P04-C40-G01", "GOLDEN"),
    ("A01", "V23-P04-C40-A01", "ALTERNATE"),
    ("H01", "V23-P04-C40-H01", "HOSTILE"),
    ("I01", "V23-P04-C40-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C40-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

SOURCES = ["PORTABLE_SUBMISSION", "PHONE", "EMAIL", "TEXT", "PAPER", "IN_PERSON", "OTHER"]
STATES = [
    "OPEN_UNTRIAGED",
    "OPEN_ACCEPTED",
    "HANDLED_BY_LINKED_WORK",
    "DECLINED",
    "CLOSED_NO_WORK",
    "SUPERSEDED",
]
DISPOSITIONS = [
    "ACCEPT_AS_NEW",
    "ACCEPT_AND_LINK_DUPLICATE",
    "DECLINE_WITH_REASON",
    "RECORD_HISTORY_ONLY",
    "KEEP_QUARANTINED",
    "DISCARD_UNIMPORTED",
]
HOSTILE_CASES = [
    "CORRUPT_CANONICAL_BYTES",
    "UNKNOWN_PROTOCOL_RELEASE",
    "STALE_WORKSPACE_FRONTIER",
    "WRONG_INVITATION",
    "WRONG_SCOPE",
    "REBINDING",
    "DIVERGENT_SAME_SUBMISSION_ID",
    "CROSS_PURPOSE_REVIEW_NAMESPACE",
    "ENCRYPTED_SERVICE_REQUEST_IN_V1",
    "PATH_TRAVERSAL",
    "SYMLINK",
    "CASE_MISMATCH",
    "TYPE_OR_MAGIC_MISMATCH",
    "COMPRESSION_BOMB",
    "HOSTILE_UNICODE",
    "OVERSIZE_FILE_OR_MEDIA",
    "MOVED_RETIRED_OR_DELETED_TARGET",
]
INTERRUPTION_BOUNDARIES = [
    "DRAFT_CHECKPOINT",
    "CANCEL_BEFORE_PREVIEW",
    "PROTECTED_DATA_UNAVAILABLE",
    "STORAGE_UNAVAILABLE",
    "AFTER_IMPORT_EFFECT_BEFORE_RECEIPT",
    "AFTER_WORK_LINK_EFFECT_BEFORE_RECEIPT",
    "RELAUNCH_WITH_PENDING_SESSION_FINALIZATION",
]
LIFECYCLE = {
    "backupReplaceRestorePreservesEligibleSessions": True,
    "cloneAndForkInvalidateOutstandingCapabilities": True,
    "eraseRemovesOwnedStagingAndCapabilities": True,
    "escapedCopiesCanBeAcknowledgedButNotRecalled": True,
    "reviewNamespaceIsIndependent": True,
    "siblingSubmissionsArePreserved": True,
}
TRUTH = {
    "contactPromotionPurpose": "OPERATIONAL_CONTACT_ONLY",
    "portableFilesAreCleartext": True,
    "previewWritesCanonical": False,
    "recipientModeRequiresEntitlement": False,
    "statusFormats": ["PDF", "TEXT"],
    "statusProvesReceiptOrDelivery": False,
    "workConversionIsSeparate": True,
}
CLAIMS = {
    "authenticatedRequester": False,
    "automaticDuplicateMerge": False,
    "automaticWorkCreation": False,
    "deliveryConfirmed": False,
    "emergencyIntake": False,
    "encryptedServiceRequestV1": False,
    "marketingConsent": False,
    "portalAvailable": False,
    "requesterAuthorityVerified": False,
    "slaPromised": False,
    "telemetryWritten": False,
    "urgencyVerified": False,
}
CORPUS_SCHEMA = "V23P04C40ServiceRequestWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "cardID",
        "claims",
        "containsCustomerData",
        "containsSecrets",
        "dispositions",
        "evidenceIDs",
        "hostileCases",
        "interruptionBoundaries",
        "lifecycle",
        "schema",
        "schemaVersion",
        "scenarios",
        "sources",
        "states",
        "synthetic",
        "testOnly",
        "truth",
    )
)

CORPUS_SCENARIOS = [
    {"id": "V23-P04-C40-G01", "kind": "GOLDEN", "canonicalEffects": 2},
    {"id": "V23-P04-C40-A01", "kind": "ALTERNATE", "manualChannels": 6},
    {"id": "V23-P04-C40-H01", "kind": "HOSTILE", "partialEffectsAllowed": False},
    {"id": "V23-P04-C40-I01", "kind": "INTERRUPTION", "maximumEffectsPerMutation": 1},
    {"id": "V23-P04-C40-R01", "kind": "RECOVERY", "exactReplayRequired": True},
]

SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "evidenceID": "V23-P04-C40-G01",
        "focus": "MANUAL_AND_PORTABLE_CAPTURE_ZERO_WRITE_PREVIEW_DERIVED_TRIAGE_AND_EXPLICIT_DISPOSITION",
        "expectedEffects": {
            "sources": ["PHONE", "EMAIL", "TEXT", "PAPER", "IN_PERSON", "OTHER", "PORTABLE_SUBMISSION"],
            "previewWritesCanonical": False,
            "duplicateSuggestions": "EXPLAINABLE_ONLY",
            "availableDispositions": list(DISPOSITIONS),
            "needsTriageProjection": "DERIVED_REBUILDABLE",
        },
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "evidenceID": "V23-P04-C40-A01",
        "focus": "PURPOSE_NAMESPACED_PORTABLE_DRAFT_REVIEW_AND_SEPARATE_WORK_CONVERSION_STATUS_HANDOFF",
        "expectedEffects": {
            "recipientModeEntitlementIndependent": True,
            "portableFiles": "CLEARTEXT_V23",
            "workConversion": "SEPARATE_EXPLICIT_MUTATION",
            "linkage": "IMMUTABLE_REQUEST_WORK_LINEAGE",
            "statusFormats": ["PDF", "TEXT"],
            "statusDeliveryClaim": False,
        },
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "evidenceID": "V23-P04-C40-H01",
        "focus": "HOSTILE_PORTABLE_INPUT_SCOPE_PROTOCOL_BYTES_DUPLICATE_FRONTIER_AND_PURPOSE_ISOLATION",
        "expectedEffects": {
            "unknownOrCorrupt": "FAIL_VISIBLE_NO_PARTIAL_CANONICAL_SUCCESS",
            "duplicateMerge": "NEVER_AUTOMATIC",
            "wrongScope": "REJECT",
            "encryptedV1": "REJECT_UNSUPPORTED_PROTOCOL",
            "claims": "ALL_FALSE",
        },
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "evidenceID": "V23-P04-C40-I01",
        "focus": "DRAFT_CHECKPOINT_PREVIEW_CANCEL_STORAGE_PROTECTED_DATA_EFFECT_BEFORE_RECEIPT_AND_RELAUNCH",
        "expectedEffects": {
            "preview": "ZERO_WRITE",
            "retry": "SAME_EFFECT_OR_NO_EFFECT",
            "effectBeforeReceipt": "RECOVER_OR_ROLL_BACK_VISIBLY",
            "pendingFinalization": "RESUME_OR_ROLL_BACK",
        },
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "evidenceID": "V23-P04-C40-R01",
        "focus": "CANONICAL_RECEIPTS_BACKUP_RESTORE_CLONE_FORK_ERASE_SEARCH_REBUILD_AND_ESCAPED_COPY_TRUTH",
        "expectedEffects": {
            "backupRestore": "PRESERVE_ELIGIBLE_SESSIONS",
            "cloneFork": "INVALIDATE_OUTSTANDING_CAPABILITIES",
            "erase": "REMOVE_OWNED_STAGING_AND_CAPABILITIES",
            "search": "DERIVED_REBUILDABLE_NEEDS_TRIAGE",
            "escapedCopies": "ACKNOWLEDGE_NOT_RECALL",
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
    "V23-P04-C40": (7105, "dfadca21d19ae2fafab31cb74da5b441d62412cf1aed042a86645aac25f63a02"),
    "V23-P04-C40-register": (313, "0298a50940eb5652e77051e267454be847c4b042a577157ce0c45af9ef14ef13"),
    "V23-P04-C41-register": (320, "3424fddd0018c1074502c726574498f027614a8ffe8413b4766c2bdd03357b35"),
}
SOURCE_PROJECTION = {
    "acceptedExpansionHead": BASE,
    "acceptedExpansionTree": BASE_TREE,
    "canonicalSuccessor": {"cardID": "V23-P04-C41", "registerOrdinal": 129},
    "dossierSlices": [
        {
            "byteCount": 7105,
            "endLine": 8479,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
            "sha256": SOURCE_PINS["V23-P04-C40"][1],
            "startLine": 8420,
        },
        {
            "byteCount": 313,
            "endLine": 309,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": SOURCE_PINS["V23-P04-C40-register"][1],
            "startLine": 309,
        },
        {
            "byteCount": 320,
            "endLine": 310,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": SOURCE_PINS["V23-P04-C41-register"][1],
            "startLine": 310,
        },
        {
            "byteCount": 308,
            "endLine": 463,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": "e0c104d58c235cfb7dff80091ddfa9789d199958c415b639adae83f9e9caa2e0",
            "startLine": 463,
        },
        {
            "byteCount": 775,
            "endLine": 1613,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": "dea8e2db3f887af2d1a1f99a255414e37a4ec5412652957874aa7ac2226ea189",
            "startLine": 1611,
        },
        {
            "byteCount": 94,
            "endLine": 3133,
            "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md",
            "sha256": "a78c8184c0573c9fbbdfd1a917a66c58327797aee6c7d1384ac2315d6ca8cc35",
            "startLine": 3133,
        },
    ],
    "outcome": "MANUAL_AND_PORTABLE_SERVICE_REQUEST_INTAKE_INSIDE_TODAY_WORK_SITE_ASSET_WITH_INTERRUPTION_SAFE_DRAFTS_ZERO_WRITE_PREVIEW_SUGGESTION_ONLY_DUPLICATE_REASONS_EXPLICIT_DISPOSITIONS_SEPARATE_CREATE_WORK_IMMUTABLE_REQUEST_WORK_LINK_CUSTOMER_SAFE_PDF_TEXT_STATUS_SEARCHABLE_NEEDS_TRIAGE",
    "sourceAuthorityMode": "USER_STANDING_OWNER_AUTHORIZATION_RELAYED_BY_ORCHESTRATOR",
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
    value = os.environ.get("V23_P04_C40_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C40 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    dossier_match = re.search(rb'(?ms)^### V23-P04-C40 .*?(?=^<a id="v23-p04-c41"|\Z)', blueprint)
    if dossier_match is None:
        raise ValueError("missing pinned source block: V23-P04-C40")
    rows = {
        "V23-P04-C40": dossier_match.group(0),
        "V23-P04-C40-register": next(
            (line for line in foundation.splitlines(keepends=True) if b"v23-p04-c40-register" in line),
            None,
        ),
        "V23-P04-C41-register": next(
            (line for line in foundation.splitlines(keepends=True) if b"v23-p04-c41-register" in line),
            None,
        ),
    }
    result: list[dict[str, Any]] = []
    for anchor, value in rows.items():
        if value is None:
            raise ValueError(f"missing pinned source row: {anchor}")
        measured = (len(value), sha(value))
        if measured != SOURCE_PINS[anchor]:
            raise ValueError(f"source pin drift: {anchor} expected={SOURCE_PINS[anchor]} actual={measured}")
        result.append({"anchor": anchor, "utf8Length": measured[0], "sha256": measured[1]})
    return result


def _require(value: Any, expected: Any, label: str) -> None:
    if value != expected:
        raise ValueError(f"{label} drift")


def _coordination_evidence(root: Path) -> None:
    _require(git("rev-parse", "HEAD", cwd=root), COORDINATION_HEAD, "coordination HEAD")
    _require(git("rev-parse", "HEAD^{tree}", cwd=root), COORDINATION_TREE, "coordination tree")
    context = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json")
    fence = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    correction = read_json(root / CORRECTION_RECEIPT)
    transition = read_json(root / CORRECTION_TRANSITION)
    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    projection = read_json(root / "projections/ActiveWorkSetProjectionV1.json")

    blockers = [
        "DIRECT_RECEIPTS_PROVISIONAL_ZERO_ACCEPTANCE_CREDIT",
        "ACCEPTED_S10_6_RECONCILIATION_PENDING",
        "NATIVE_COMPILE_UNIT_UI_RECOVERY_AND_HOSTED_RUNS_NOT_RUN",
    ]
    _require(
        (context.get("cardID"), context.get("attemptID"), context.get("registerOrdinal")),
        (CARD, 1, ORDINAL),
        "context identity",
    )
    _require(context.get("contextDigest"), CONTEXT_DIGEST, "context digest")
    _require(context.get("ownerAuthorizedPathAllocationDigest"), ALLOCATION_DIGEST, "context allocation")
    _require(context.get("provisionalPrerequisiteDigest"), PREREQUISITE_DIGEST, "context prerequisite")
    _require(context.get("repository"), {"appBaseHead": BASE, "appBaseTree": BASE_TREE}, "context repository")
    _require(context.get("acceptanceBlockers"), blockers, "context blockers")
    for key in ("acceptanceCredit", "acceptanceEnabled", "adoptionEnabled", "hostedDispatchEnabled", "hostedDispatchRan", "nativeCompileRan", "physicalDeviceEnabled", "publicationEnabled", "releaseCredit", "releaseReady", "phase10PollingDuringParallelExecution"):
        _require(context.get(key), False, f"context {key}")
    _require(context.get("planningStatus"), "NOT_STARTED", "context planning status")
    _require(context.get("hydrationRevision"), 2, "context hydration revision")
    _require(
        context.get("hydrationFenceCorrectionPolicy"),
        "P04_C40_DRAFT_PURPOSE_V1_SERVICE_REQUEST_ADDITION_REQUIRES_SHARED_TEST_SUPPORT_MAKE_REGISTRY_ALLCASES_EXHAUSTIVE_SWITCH_TO_MAP_SERVICE_REQUEST_TO_EXISTING_APPLY_SERVICE_REQUEST_MUTATION_KIND",
        "context hydration correction policy",
    )
    _require(context.get("productTestUIFixturePathCount"), 7, "context product path count")
    _require(context.get("toolingDocumentationPathCount"), 8, "context tooling path count")
    _require(context.get("requiresAcceptedS10_6Reconciliation"), True, "context S10 reconciliation")
    _require(context.get("lineage"), {"disposition": "ADDED_V23"}, "context lineage")
    _require(context.get("directPrerequisites"), ["V23-P03-C52", "V23-P04-C35"], "direct prerequisites")
    proof = {
        "allAcceptanceCreditFalse": True,
        "duplicateCount": 0,
        "expectedDirectEdgeCount": 2,
        "failedIntermediateAcceptanceCount": 0,
        "incompatibleCount": 0,
        "missingCount": 0,
        "observedDirectEdgeCount": 2,
        "orphanCount": 0,
        "staleCount": 0,
        "uniqueCardCount": 2,
    }
    _require(context.get("directPrerequisiteProof"), proof, "direct prerequisite proof")
    _require(context.get("existingPaths"), list(EXISTING_PATHS), "context existing paths")
    _require(context.get("newPaths"), list(NEW), "context new paths")
    _require(context.get("expectedArtifacts"), list(PATH_FENCE), "context artifact fence")
    persistence = {
        "canonicalManualCommitOwner": EXISTING_PATHS[0],
        "draftPurposeExtensionOwner": EXISTING_PATHS[2],
        "newImporterCount": 0,
        "newMigrationCount": 0,
        "newPersistentModelCount": 0,
        "newPersistentSchemaCount": 0,
        "newRendererCount": 0,
        "newRootCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "noNewDurableFamily": True,
        "portableDraftIsolation": "PURPOSE_NAMESPACED_WITHOUT_REVIEW_GRAMMAR_OR_QUOTA_MIXING",
        "portableDraftMigrationOwner": EXISTING_PATHS[1],
    }
    _require(context.get("persistenceDecision"), persistence, "context persistence")
    _require(context.get("sourceProjection"), SOURCE_PROJECTION, "context source projection")

    _require(fence.get("cardID"), CARD, "fence card")
    _require(fence.get("attemptID"), 1, "fence attempt")
    _require(fence.get("baseHead"), BASE, "fence base head")
    _require(fence.get("baseTree"), BASE_TREE, "fence base tree")
    _require(fence.get("fenceDigest"), FENCE_DIGEST, "fence digest")
    _require(fence.get("hydrationRevision"), 2, "fence hydration revision")
    _require(fence.get("frozenS10ReservationDigest"), FROZEN_S10_DIGEST, "fence S10 reservation")
    _require(fence.get("allowedCreateOrReplacePaths"), list(PATH_FENCE), "fence allowed paths")
    _require(fence.get("existingPaths"), list(EXISTING_PATHS), "fence existing paths")
    _require(fence.get("newPaths"), list(NEW), "fence new paths")
    _require(fence.get("allowedDeletePaths"), [], "fence delete paths")
    _require(fence.get("allowedRenamePaths"), [], "fence rename paths")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C40 path overlaps S10 reservation")
    prior = fence.get("priorFenceProof", {})
    for key, expected in {
        "authorizationBasis": "C40_OWNER_ALLOCATION_DECISION_AND_C36_DRAFT_PURPOSE_SEMANTIC_OWNER_WITH_SHARED_TEST_SUPPORT_EXISTING_ENVELOPE",
        "authorizedOverlapEdgeCount": 5,
        "fenceCount": 131,
        "inheritedExistingPathEnvelopeOverlapCount": 57,
        "overlapEdgeCount": 62,
        "priorFenceSetDigest": "4213b4c91155d5cd45a4b4c445c604b3069879a26057b9c2ee97c1ad53f8ec10",
        "priorOwnedPathCount": 4,
        "s10ReservedOverlapCount": 0,
        "unauthorizedOverlapCount": 0,
    }.items():
        _require(prior.get(key), expected, f"prior fence {key}")
    for key in ("acceptanceCredit", "acceptanceEnabled", "adoptionEnabled", "hostedDispatchEnabled", "hostedDispatchRan", "nativeCompileRan", "physicalDeviceEnabled", "publicationEnabled", "releaseCredit", "releaseReady", "phase10PollingDuringParallelExecution"):
        _require(fence.get(key), False, f"fence {key}")

    _require(allocation.get("cardID"), CARD, "allocation card")
    _require(allocation.get("allocationDigest"), ALLOCATION_DIGEST, "allocation digest")
    _require(allocation.get("exactOrderedPaths"), list(ALLOCATION_PATHS), "allocation paths")
    _require(allocation.get("existingPaths"), list(ALLOCATION_EXISTING_PATHS), "allocation existing")
    _require(allocation.get("newPaths"), list(ALLOCATION_NEW_PATHS), "allocation new")
    _require(allocation.get("newProductTestUIFixturePathCount"), 6, "allocation product count")
    _require(allocation.get("newToolingDocumentationPathCount"), 8, "allocation tooling count")
    _require(allocation.get("s10ReservedOverlapCount"), 0, "allocation S10 overlap")
    for key in ("acceptanceCredit", "acceptanceEnabled", "adoptionEnabled", "hostedDispatchEnabled", "hostedDispatchRan", "nativeCompileRan", "physicalDeviceEnabled", "publicationEnabled", "releaseCredit", "releaseReady", "phase10PollingDuringParallelExecution"):
        _require(allocation.get(key), False, f"allocation {key}")
    _require(allocation.get("persistenceDecision"), persistence, "allocation persistence")
    _require(allocation.get("sourceProjection"), SOURCE_PROJECTION, "allocation projection")

    _require(prerequisite.get("prerequisiteDigest"), PREREQUISITE_DIGEST, "prerequisite digest")
    _require(prerequisite.get("successorCardID"), CARD, "prerequisite successor")
    _require(prerequisite.get("canonicalDirectPrerequisiteCardIDs"), ["V23-P03-C52", "V23-P04-C35"], "prerequisite cards")
    _require(prerequisite.get("ordinaryDirectEdgeCount"), 2, "prerequisite edge count")
    _require(prerequisite.get("directPrerequisiteProof"), proof, "prerequisite proof")
    _require(prerequisite.get("acceptanceCredit"), False, "prerequisite acceptance")
    _require(
        prerequisite.get("immediateSequentialPredecessor"),
        {
            "candidateHead": BASE,
            "candidateTree": BASE_TREE,
            "cardID": "V23-P04-C39",
            "checkpointDigest": "33d1999c443938bf18dff15a712529480a0081a2828b2a724d1d6357b8179211",
            "verificationReceiptDigest": "7e6f80d776276869b8cfa373da5b017bc4bd0a8d52099c65c67c6eb87f9e0cfe",
        },
        "immediate predecessor",
    )
    _require(
        correction,
        {
            "acceptanceCredit": False,
            "acceptanceEnabled": False,
            "addedPaths": ["FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift"],
            "adoptionEnabled": False,
            "allowedPathCount": 18,
            "attemptID": 1,
            "authorizedPriorFenceOverlapCount": 5,
            "cardID": CARD,
            "contextDigest": CONTEXT_DIGEST,
            "createdAt": "2026-09-01T23:35:00Z",
            "existingPathCount": 4,
            "fenceDigest": FENCE_DIGEST,
            "hostedDispatchEnabled": False,
            "hostedDispatchRan": False,
            "hydrationRevision": 2,
            "inheritedExistingPathEnvelopeOverlapCount": 57,
            "initialHydrationTransitionDigest": "ee8f4e1167175231f0be8b3e9cd49bc03c7f7f28cd4411f67b1ad3f8cff17fc4",
            "nativeCompileRan": False,
            "newPathCount": 14,
            "originalAllocationDigest": ALLOCATION_DIGEST,
            "phase10PollingDuringParallelExecution": False,
            "physicalDeviceEnabled": False,
            "priorAllowedPathCount": 17,
            "priorContextDigest": "b86374dc3070b78c6cc7383e2c533f96e7c804bbd97c3d7dc78c2daa06695471",
            "priorFenceDigest": "6e69e47dec0491781d96861a108b0461721506e2b4ea6ef5d595c92725b321da",
            "productTestUIFixturePathCount": 7,
            "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
            "publicationEnabled": False,
            "reason": "P04_C40_DRAFT_PURPOSE_V1_SERVICE_REQUEST_ADDITION_REQUIRES_SHARED_TEST_SUPPORT_MAKE_REGISTRY_ALLCASES_EXHAUSTIVE_SWITCH_TO_MAP_SERVICE_REQUEST_TO_EXISTING_APPLY_SERVICE_REQUEST_MUTATION_KIND",
            "receiptDigest": CORRECTION_DIGEST,
            "releaseCredit": False,
            "releaseReady": False,
            "requiresAcceptedS10_6Reconciliation": True,
            "s10ReservedOverlapCount": 0,
            "schema": "HydratedPathFenceCorrectionReceiptV1",
            "schemaVersion": 1,
            "semanticRequirement": "DRAFT_PURPOSE_V1_SERVICE_REQUEST_CASE_REQUIRES_EXHAUSTIVE_SHARED_TEST_SUPPORT_REGISTRY_MAPPING_TO_EXISTING_WORKSPACE_COMMAND_KIND_APPLY_SERVICE_REQUEST",
            "toolingDocumentationPathCount": 8,
            "unauthorizedPriorFenceOverlapCount": 0,
        },
        "correction receipt",
    )
    _require(
        transition,
        {
            "attemptID": 1,
            "candidateHead": BASE,
            "candidateTree": BASE_TREE,
            "cardID": CARD,
            "contextDigest": CONTEXT_DIGEST,
            "createdAt": "2026-09-01T23:35:00Z",
            "fromState": "HYDRATING",
            "hydrationCorrectionReceiptDigest": CORRECTION_DIGEST,
            "newLedgerDigest": LEDGER_DIGEST,
            "originalAllocationDigest": ALLOCATION_DIGEST,
            "pathFenceDigest": FENCE_DIGEST,
            "priorContextDigest": "b86374dc3070b78c6cc7383e2c533f96e7c804bbd97c3d7dc78c2daa06695471",
            "priorLedgerDigest": "d850789733698390454389fd2af351cef56c1a2cb2a0439693905bbba134f15e",
            "priorPathFenceDigest": "6e69e47dec0491781d96861a108b0461721506e2b4ea6ef5d595c92725b321da",
            "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
            "reason": "P04_C40_DRAFT_PURPOSE_V1_SERVICE_REQUEST_ADDITION_REQUIRES_SHARED_TEST_SUPPORT_MAKE_REGISTRY_ALLCASES_EXHAUSTIVE_SWITCH_TO_MAP_SERVICE_REQUEST_TO_EXISTING_APPLY_SERVICE_REQUEST_MUTATION_KIND",
            "schema": "BootstrapStateTransitionV1",
            "schemaVersion": 1,
            "sequence": SEQUENCE,
            "toState": "HYDRATING",
            "transitionDigest": TRANSITION_DIGEST,
        },
        "transition",
    )
    expected_entry = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "classification": "IMPLEMENT_NOW",
        "contextDigest": CONTEXT_DIGEST,
        "directPrerequisites": ["V23-P03-C52", "V23-P04-C35"],
        "hydrationFenceCorrectionDigest": CORRECTION_DIGEST,
        "hydrationRevision": 2,
        "ordinal": ORDINAL,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "planningStatus": "NOT_STARTED",
        "portableDraftIsolationRequired": True,
        "productTestUIFixturePathCount": 7,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "serviceRequestScope": "TODAY_WORK_SITE_ASSET_NO_FIFTH_ROOT",
        "state": "HYDRATING",
        "stateReason": "P04_C40_DRAFT_PURPOSE_V1_SERVICE_REQUEST_ADDITION_REQUIRES_SHARED_TEST_SUPPORT_MAKE_REGISTRY_ALLCASES_EXHAUSTIVE_SWITCH_TO_MAP_SERVICE_REQUEST_TO_EXISTING_APPLY_SERVICE_REQUEST_MUTATION_KIND",
        "toolingDocumentationPathCount": 8,
        "zeroWritePreviewRequired": True,
    }
    _require(ledger.get("casSequence"), SEQUENCE, "ledger sequence")
    _require(ledger.get("ledgerDigest"), LEDGER_DIGEST, "ledger digest")
    entries = [entry for entry in ledger.get("attempts", ()) if entry.get("cardID") == CARD]
    if entries != [expected_entry]:
        raise ValueError("ledger C40 entry drift")
    _require(projection.get("ledgerDigest"), LEDGER_DIGEST, "projection ledger")
    _require(projection.get("projectionDigest"), PROJECTION_DIGEST, "projection digest")
    _require(projection.get("nextEligibleCardID"), None, "projection next card")
    _require(projection.get("nextEligibleRegisterOrdinal"), None, "projection next ordinal")
    entries = [entry for entry in projection.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if entries != [expected_entry]:
        raise ValueError("projection C40 entry drift")


def authority() -> dict[str, Any]:
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
        "sourcePins": _source_slices(),
        "finalHashesSealed": FINAL_HASHES_SEALED,
    }
    coordination = _coordination_root()
    if coordination is None or not coordination.is_dir():
        if not (ROOT / MANIFEST).is_file():
            raise ValueError("coordination authority unavailable and no portable manifest")
        manifest = read_json(ROOT / MANIFEST)
        if manifest.get("authority") != result:
            raise ValueError("portable authority mismatch")
    else:
        _coordination_evidence(coordination)
    return result


def rows() -> tuple[list[dict[str, Any]], bool]:
    result: list[dict[str, Any]] = []
    for path in SOURCE_PATHS:
        target = ROOT / path
        present = target.is_file()
        result.append({"path": path, "status": "SOURCE_PRESENT" if present else "SOURCE_MISSING", "sha256": sha(target.read_bytes()) if present else None})
    return result, all(row["status"] == "SOURCE_PRESENT" for row in result)


def counts() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in git(*args).splitlines() if line}

    changed = names("diff", "--name-only", BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard")
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
        "persistence": "PERSISTENT_OR_PRODUCT_DELTA",
        "persistentSchemaVersion": 36,
        "recordsSchemaVersion": 35,
        "durableFamily": "NONE",
        "canonicalManualCommitOwner": EXISTING_PATHS[0],
        "canonicalWriteOwner": "ServiceRequestCoordinatorV1",
        "portableDraftMigrationOwner": EXISTING_PATHS[1],
        "draftPurposeExtensionOwner": EXISTING_PATHS[2],
        "portableSessionNamespace": "SERVICE_REQUEST",
        "newDurableFamilyCount": 0,
        "newPersistentModelCount": 0,
        "newPersistentSchemaCount": 0,
        "newImporterCount": 0,
        "newMigrationCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "newRendererCount": 0,
        "newBackendCount": 0,
        "projectionPersistence": "NONPERSISTENT_DERIVED_REBUILDABLE",
        "previewPersistence": "NONPERSISTENT_ZERO_WRITE",
        "resetDisposition": "EXISTING_LIFECYCLE_CONTRACT",
        "eraseDisposition": "EXISTING_ERASE_OWNED_STAGING_AND_CAPABILITIES",
        "backupRestoreDisposition": "PRESERVE_ELIGIBLE_SESSIONS",
        "cloneForkDisposition": "INVALIDATE_OUTSTANDING_CAPABILITIES",
        "escapedCopyDisposition": "ACKNOWLEDGE_NOT_RECALL",
    }
    independence = {
        "entitlementIndependent": True,
        "portableRecipientFlowIsolated": True,
        "c48SoleStore": True,
        "canonicalManualCommitOwner": EXISTING_PATHS[0],
        "draftPurposeExtensionOwner": EXISTING_PATHS[2],
        "portableDraftMigrationOwner": EXISTING_PATHS[1],
        "portableDraftIsolation": "PURPOSE_NAMESPACED_WITHOUT_REVIEW_GRAMMAR_OR_QUOTA_MIXING",
        "reviewNamespaceIndependent": True,
        "newStore": False,
        "newWriter": False,
        "newImporter": False,
        "newRenderer": False,
        "newRoot": False,
        "newBackend": False,
        "newNetwork": False,
        "newTelemetry": False,
        "newMarketing": False,
        "newContactWriter": False,
        "claimsFabricated": False,
        "customerDataInTooling": False,
        "secretsInTooling": False,
    }
    return {
        "schema": "V23P04C40ServiceRequestWorkflowToolingV1",
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


def documents() -> dict[str, Any]:
    base = _base_document()
    requirements = {
        "manualCapture": True,
        "portableCapture": True,
        "todayWorkSiteAssetNoFifthRoot": True,
        "interruptionSafeDrafts": True,
        "previewZeroWrite": True,
        "duplicateReasonsSuggestionOnly": True,
        "explicitDispositions": list(DISPOSITIONS),
        "separateCreateWork": True,
        "immutableRequestWorkLink": True,
        "customerSafeStatus": True,
        "statusFormats": ["PDF", "TEXT"],
        "statusDoesNotClaimReceiptOrDelivery": True,
        "searchableNeedsTriageProjection": True,
        "needsTriageDerivedRebuildable": True,
        "purposeNamespacedPortableDrafts": True,
        "reviewGrammarAndQuotaUnmixed": True,
        "recipientModeEntitlementIndependent": True,
        "portableFilesCleartextInV23": True,
        "portableServiceKindsRejectedByEnvelope": True,
        "canonicalManualCommitOwner": EXISTING_PATHS[0],
        "c48SoleStore": "PortableExchangeSessionStoreV2",
        "c14CanonicalApplyOnly": True,
        "noNewRoot": True,
        "noNewStore": True,
        "noNewWriter": True,
        "noNewImporter": True,
        "noNewRenderer": True,
        "noNewModel": True,
        "noNewSchemaFamily": True,
        "noNewMigration": True,
        "noBackend": True,
        "noNetwork": True,
        "noTelemetry": True,
        "noMarketingWrites": True,
        "noContactWrites": True,
        "requesterIdentityVerified": False,
        "requesterAuthorityVerified": False,
        "contactVerified": False,
        "urgencyVerified": False,
        "deliveryConfirmed": False,
        "emergencyIntake": False,
        "portalAvailable": False,
        "slaPromised": False,
        "automaticDuplicateMerge": False,
        "automaticWorkCreation": False,
        "encryptedServiceRequestV1": False,
        "marketingConsent": False,
        "telemetryWritten": False,
        "fiveEvidenceScenarios": True,
        "scenarioSelectors": list(SELECTORS),
        "finalHashesUnsealed": True,
    }
    corpus_expectations = {
        "schema": CORPUS_SCHEMA,
        "schemaVersion": 1,
        "cardID": CARD,
        "testOnly": True,
        "synthetic": True,
        "containsCustomerData": False,
        "containsSecrets": False,
        "sources": list(SOURCES),
        "states": list(STATES),
        "dispositions": list(DISPOSITIONS),
        "scenarios": list(CORPUS_SCENARIOS),
        "evidenceIDs": list(SELECTORS),
        "hostileCases": list(HOSTILE_CASES),
        "interruptionBoundaries": list(INTERRUPTION_BOUNDARIES),
        "lifecycle": dict(LIFECYCLE),
        "truth": dict(TRUTH),
        "claims": dict(CLAIMS),
    }
    contract = {
        **base,
        "contract": "ServiceRequestWorkflowContractV1",
        "journeyRefs": ["FJ08"],
        "directPrerequisites": ["V23-P03-C52", "V23-P04-C35"],
        "aggregateMemberships": [
            "AutonomousRequiredAcceptedSetV1",
            "P04ShippingSurfaceSetV1",
            "P04BrandClosureSetV1",
            "PublicCapabilityTruthSetV1",
            "ContactPurposeSeparationSetV1",
        ],
        "invalidationConsumers": [
            "V23-P04-C27:STATE_INVENTORY",
            "V23-P04-C29:EXACT_CANDIDATE",
            "V23-P05-C01:RELEASE_SELECTOR",
        ],
        "optionalCapabilityProviders": [],
        "contractRefs": [
            "ServiceRequestImportPlanV1",
            "PortableExchangeSessionStoreV2",
            "ServiceRequestStatusArtifactV1",
            "DirectPrerequisiteEvidenceSetV1",
            "CardAcceptanceInclusionProofV1",
            "CardAcceptanceInclusionProofRecoveryReceiptV1",
            "CandidateAcceptanceCompatibilityReceiptV1",
        ],
        "requirements": requirements,
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusExpectations": corpus_expectations,
        "outcome": SOURCE_PROJECTION["outcome"],
        "claims": dict(CLAIMS),
    }
    evidence = {
        **base,
        "receipt": "ServiceRequestWorkflowEvidenceReceiptV1",
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusSchema": CORPUS_SCHEMA,
        "corpusExpectations": corpus_expectations,
        "claims": dict(CLAIMS),
        "prohibitedClaims": [
            "requester identity verified",
            "requester authority verified",
            "contact verified",
            "urgency verified",
            "delivery confirmed",
            "portal available",
            "emergency intake",
            "SLA promised",
            "automatic duplicate merge",
            "automatic work creation",
            "encrypted service request V1",
            "telemetry",
            "network",
            "marketing consent",
        ],
        "lifecycle": dict(LIFECYCLE),
        "sourceSlices": list(SOURCE_PROJECTION["dossierSlices"][:3]),
        "manualCanonicalOwner": EXISTING_PATHS[0],
        "portableStoreOwner": EXISTING_PATHS[1],
        "draftPurposeOwner": EXISTING_PATHS[2],
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
        "customerSafeStatusClaim": False,
        "deliveryClaim": False,
        "identityClaim": False,
        "urgencyClaim": False,
        "portalClaim": False,
        "emergencyClaim": False,
        "slaClaim": False,
        "networkOrTelemetry": False,
        "marketingOrContactWrites": False,
        "newRootStoreWriterRenderer": False,
        "portableDraftPurposeNamespaced": True,
        "reviewNamespaceIndependent": True,
        "customerDataPresent": False,
        "customerSecretsPresent": False,
        "durableDelta": False,
    }
    schema = schema_document()
    hashes = {
        CONTRACT: sha(pretty(contract)),
        EVIDENCE: sha(pretty(evidence)),
        BRAND: sha(pretty(brand)),
        SCHEMA: sha(pretty(schema)),
    }
    manifest = {
        "schema": "V23P04C40ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": base["authority"],
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in hashes.items()],
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
        "directPrerequisites": ["V23-P03-C52", "V23-P04-C35"],
        "successor": {"cardID": "V23-P04-C41", "registerOrdinal": 129},
        "optionalProvider": "NONE",
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
        "properties": {key: {"const": False} for key in FLAGS},
        "additionalProperties": False,
    }
    authority_properties: dict[str, Any] = {
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
        "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3},
        "finalHashesSealed": {"const": False},
    }
    lifecycle_properties: dict[str, Any] = {
        "status": {"const": "IMPLEMENT_NOW"},
        "persistence": {"const": "PERSISTENT_OR_PRODUCT_DELTA"},
        "persistentSchemaVersion": {"const": 36},
        "recordsSchemaVersion": {"const": 35},
        "durableFamily": {"const": "NONE"},
        "canonicalManualCommitOwner": {"const": EXISTING_PATHS[0]},
        "canonicalWriteOwner": {"const": "ServiceRequestCoordinatorV1"},
        "portableDraftMigrationOwner": {"const": EXISTING_PATHS[1]},
        "draftPurposeExtensionOwner": {"const": EXISTING_PATHS[2]},
        "portableSessionNamespace": {"const": "SERVICE_REQUEST"},
        "newDurableFamilyCount": {"const": 0},
        "newPersistentModelCount": {"const": 0},
        "newPersistentSchemaCount": {"const": 0},
        "newImporterCount": {"const": 0},
        "newMigrationCount": {"const": 0},
        "newStoreCount": {"const": 0},
        "newWriterCount": {"const": 0},
        "newRendererCount": {"const": 0},
        "newBackendCount": {"const": 0},
        "projectionPersistence": {"const": "NONPERSISTENT_DERIVED_REBUILDABLE"},
        "previewPersistence": {"const": "NONPERSISTENT_ZERO_WRITE"},
        "resetDisposition": {"const": "EXISTING_LIFECYCLE_CONTRACT"},
        "eraseDisposition": {"const": "EXISTING_ERASE_OWNED_STAGING_AND_CAPABILITIES"},
        "backupRestoreDisposition": {"const": "PRESERVE_ELIGIBLE_SESSIONS"},
        "cloneForkDisposition": {"const": "INVALIDATE_OUTSTANDING_CAPABILITIES"},
        "escapedCopyDisposition": {"const": "ACKNOWLEDGE_NOT_RECALL"},
    }
    independence_properties = {
        "entitlementIndependent": {"const": True},
        "portableRecipientFlowIsolated": {"const": True},
        "c48SoleStore": {"const": True},
        "canonicalManualCommitOwner": {"const": EXISTING_PATHS[0]},
        "draftPurposeExtensionOwner": {"const": EXISTING_PATHS[2]},
        "portableDraftMigrationOwner": {"const": EXISTING_PATHS[1]},
        "portableDraftIsolation": {"const": "PURPOSE_NAMESPACED_WITHOUT_REVIEW_GRAMMAR_OR_QUOTA_MIXING"},
        "reviewNamespaceIndependent": {"const": True},
        "newStore": {"const": False},
        "newWriter": {"const": False},
        "newImporter": {"const": False},
        "newRenderer": {"const": False},
        "newRoot": {"const": False},
        "newBackend": {"const": False},
        "newNetwork": {"const": False},
        "newTelemetry": {"const": False},
        "newMarketing": {"const": False},
        "newContactWriter": {"const": False},
        "claimsFabricated": {"const": False},
        "customerDataInTooling": {"const": False},
        "secretsInTooling": {"const": False},
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C40ServiceRequestWorkflowToolingV1",
        "type": "object",
        "required": [
            "schema",
            "cardID",
            "ordinal",
            "authority",
            "sourceRows",
            "sourceReady",
            "flags",
            "finalHashesSealed",
            "lifecycle",
            "independence",
        ],
        "properties": {
            "schema": {"const": "V23P04C40ServiceRequestWorkflowToolingV1"},
            "cardID": {"const": CARD},
            "ordinal": {"const": ORDINAL},
            "authority": {"$ref": "#/$defs/authority"},
            "sourceRows": {"type": "array", "minItems": len(SOURCE_PATHS), "maxItems": len(SOURCE_PATHS), "items": {"$ref": "#/$defs/sourceRow"}},
            "sourceReady": {"type": "boolean"},
            "flags": {"$ref": "#/$defs/flags"},
            "finalHashesSealed": {"const": False},
            "lifecycle": {"$ref": "#/$defs/lifecycle"},
            "independence": {"$ref": "#/$defs/independence"},
            "contract": {"type": "string"},
            "receipt": {"type": "string"},
            "requirements": {"type": "object"},
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
