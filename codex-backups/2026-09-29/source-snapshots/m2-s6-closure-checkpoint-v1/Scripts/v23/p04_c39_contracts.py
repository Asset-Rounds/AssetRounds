#!/usr/bin/env python3
"""Pinned deterministic tooling contracts for V23-P04-C39.

The C39 lane is a local, optional rating-request capability.  It derives
eligibility from already-finalized value, records only the fact that the
system was asked, and keeps Support independent of the rating path.  This
module emits static authority/evidence artifacts; it never calls StoreKit,
opens a network connection, or creates a second preference/store owner.
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
CARD = "V23-P04-C39"
ORDINAL = 124
TITLE = "Native App Store rating eligibility and always-visible support fallback from generic finalized-value receipts"
BASE = "98171901b302c63d667f59d6a9ac02413aaba762"
BASE_TREE = "d4016d0e556d6f7f60926571348d919b0605009b"
COORDINATION_HEAD = "435f91c8c756b741c275d21cde7adece48761294"
COORDINATION_TREE = "26c6f9b72bee52b4722842f66beda130bbfb8513"
SEQUENCE = 555
ALLOCATION_DIGEST = "c20e155a3a3b49232faa454a48a79900720f1d72a0a56c9b4e78bfafb369ed71"
PREREQUISITE_DIGEST = "4bb1eceee8ff7df5c4b5c4776c483db7fa4d62400b566ac28d9cc6c5eaa44dc2"
CONTEXT_DIGEST = "49538d614820ea6356f0deccaf931bcaa8a849f8d2158e3d595b8b36faf2fa8f"
FENCE_DIGEST = "90bd582fba3ebae8f3a983ebc2ea95248970407a008e3f51f5b05c37c0a0c198"
TRANSITION_DIGEST = "b59610ff7facf995bdd7795591b9f427891efd7dfbb91cb4ea393c2522354b12"
LEDGER_DIGEST = "4c1f8c067a3da8471f06dcf8be8138a27d169576b2787a067affcfeb99eecf94"
PROJECTION_DIGEST = "26f5fc20257e10c09409cbfaab60c0c040eed7a551b827c9f21c0839e31b0ff7"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FINAL_HASHES_SEALED = False

# Common aliases keep this lane consumable by generic v23 tooling checks.
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
    "FieldEvidenceApp/Domain/Feedback/RatingEligibilityContractsV1.swift",
    "FieldEvidenceApp/Application/Feedback/RatingEligibilityCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Feedback/RatingRequestAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceApp/Features/Settings/RatingSupportWorkflowView.swift",
    "FieldEvidenceAppTests/V9_102RatingEligibilityWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/Feedback/V23P04C39RatingSupportWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C39RatingSupportWorkflowUITests.swift",
    "Scripts/v23/p04_c39_contracts.py",
    "Scripts/v23/generate_p04_c39_contracts.py",
    "Scripts/v23/verify_p04_c39_contracts.py",
    "Scripts/v23/rating-support-workflow.schema.json",
    "docs/design/v23/tooling/V23P04C39RatingSupportWorkflowContractV1.json",
    "docs/design/v23/tooling/V23P04C39RatingSupportWorkflowEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P04C39BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P04-C39-tooling-manifest.json",
)
PRODUCT = ALL_PATHS[:10]
SCRIPTS = (
    "Scripts/v23/p04_c39_contracts.py",
    "Scripts/v23/generate_p04_c39_contracts.py",
    "Scripts/v23/verify_p04_c39_contracts.py",
)
SCHEMA = "Scripts/v23/rating-support-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C39RatingSupportWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C39RatingSupportWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C39BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C39-tooling-manifest.json"
EXISTING_PATHS = (
    "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
)
NEW = tuple(path for path in ALL_PATHS if path not in EXISTING_PATHS)
PATH_FENCE = ALL_PATHS
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = PRODUCT
NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT = 7
NEW_TOOLING_DOCUMENTATION_PATH_COUNT = 8

SELECTOR_ROWS = (
    ("G01", "V23-P04-C39-G01", "GOLDEN"),
    ("A01", "V23-P04-C39-A01", "ALTERNATE"),
    ("H01", "V23-P04-C39-H01", "HOSTILE"),
    ("I01", "V23-P04-C39-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C39-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

EXCLUDED_SERIES = [
    "PRACTICE",
    "IMPORTED",
    "HISTORIC",
    "DUPLICATE",
    "REOPENED",
    "SUPERSEDED",
    "NONFINAL",
]
SUPPRESSION_CONTEXTS = [
    "ERROR",
    "RECOVERY",
    "PURCHASE",
    "PERMISSION",
    "IMPORT",
    "EXPORT",
    "CAPTURE",
    "DESTRUCTIVE",
]
LEDGER_STATES = [
    "ABSENT_FRESH_INSTALL",
    "ERASED_COOLDOWN",
    "READY",
    "DISABLED_CORRUPT",
    "DISABLED_FUTURE",
    "DISABLED_MIGRATION_FAILURE",
]
PERSISTED_FIELDS = [
    "policyDigest",
    "marketingVersion",
    "build",
    "attemptAt",
    "outcome",
]
FORBIDDEN_PERSISTED_IDENTIFIERS = [
    "customerID",
    "workspaceID",
    "activityID",
    "snapshotID",
    "receiptID",
    "mutationID",
    "reviewText",
    "starValue",
    "sentiment",
    "storeResponse",
    "conversion",
]

SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "evidenceID": "V23-P04-C39-G01",
        "focus": "FINALIZED_VALUE_ELIGIBILITY_AND_NATIVE_SCENE_BOUND_REQUEST",
        "expectedEffects": {
            "distinctFinalizedActivitySeries": 3,
            "minimumDays": 7,
            "nativeRequestAPI": "AppStore.requestReview(in:)",
            "attemptLedgerWrites": 1,
            "supportAvailable": True,
        },
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "evidenceID": "V23-P04-C39-A01",
        "focus": "ELIGIBILITY_BOUNDARIES_VERSION_WINDOWS_EXCLUSIONS_AND_ALWAYS_VISIBLE_SUPPORT",
        "expectedEffects": {
            "oneAttemptPerMarketingVersion": True,
            "minimumDaysBetweenAttempts": 120,
            "maximumRollingYearAttempts": 2,
            "supportIndependent": True,
            "resetPreservesLedger": True,
            "eraseCooldownDays": 365,
        },
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "evidenceID": "V23-P04-C39-H01",
        "focus": "INVALID_LEDGER_PLATFORM_IDENTITY_ACTIVE_CONTEXT_AND_PRIVACY_REJECTION",
        "expectedEffects": {
            "corruptFutureMigrationFailure": "DISABLE_AUTO_REQUEST",
            "missingAppStoreIdentity": "TYPED_DISABLED_RATING_LINK",
            "forbiddenContextsRejected": True,
            "prohibitedWrites": 0,
        },
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "evidenceID": "V23-P04-C39-I01",
        "focus": "DUPLICATE_SCENE_INVOCATION_APP_DEATH_RESET_ERASE_AND_CLOCK_BOUNDARIES",
        "expectedEffects": {
            "duplicateInvocation": "IDEMPOTENT",
            "appDeath": "AT_MOST_ONE_CONSERVATIVE_ATTEMPT",
            "sceneUnavailable": "NO_REQUEST",
            "canonicalEffects": [0, 1],
        },
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "evidenceID": "V23-P04-C39-R01",
        "focus": "LOCAL_LEDGER_RECOVERY_SUPPORT_PRESERVATION_AND_ZERO_COLLECTION",
        "expectedEffects": {
            "retry": "SAME_ATTEMPT_OR_NO_EFFECT",
            "eraseState": "ERASED_COOLDOWN",
            "supportAvailable": True,
            "networkWrites": 0,
            "telemetryWrites": 0,
        },
    },
)

CORPUS_SCHEMA = "V23P04C39RatingSupportWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema",
        "schemaVersion",
        "cardID",
        "testOnly",
        "synthetic",
        "containsCustomerData",
        "containsSecrets",
        "scenarioIDs",
        "thresholds",
        "boundaryVectors",
        "includedReadbacks",
        "excludedCompletionCases",
        "activeContextSuppressions",
        "ledgerStates",
        "interruptionVectors",
        "truth",
        "claims",
    )
)
CORPUS_SCENARIO_IDS = list(SELECTORS)
CORPUS_THRESHOLDS = {
    "minimumDistinctSeries": 3,
    "minimumCompletionSpanSeconds": 604800,
    "minimumAttemptSeparationSeconds": 10368000,
    "rollingYearSeconds": 31536000,
    "maximumAttemptsPerRollingYear": 2,
    "eraseCooldownSeconds": 31536000,
}
CORPUS_BOUNDARY_VECTORS = [
    {"caseID": "SEVEN_DAYS_MINUS_ONE_SECOND", "seconds": 604799, "eligible": False},
    {"caseID": "SEVEN_DAYS_EXACT", "seconds": 604800, "eligible": True},
    {"caseID": "ONE_HUNDRED_TWENTY_DAYS_MINUS_ONE_SECOND", "seconds": 10367999, "eligible": False},
    {"caseID": "ONE_HUNDRED_TWENTY_DAYS_EXACT", "seconds": 10368000, "eligible": True},
    {"caseID": "ROLLING_YEAR_MINUS_ONE_SECOND", "seconds": 31535999, "eligible": False},
    {"caseID": "ROLLING_YEAR_EXACT", "seconds": 31536000, "eligible": True},
    {"caseID": "ERASE_COOLDOWN_MINUS_ONE_SECOND", "seconds": 31535999, "eligible": False},
    {"caseID": "ERASE_COOLDOWN_EXACT", "seconds": 31536000, "eligible": True},
]
CORPUS_INCLUDED_READBACKS = [
    "LOCAL_FINALIZATION_RECEIPT_MATCHING_CURRENT_FINALIZED_SNAPSHOT_V1",
    "LOCAL_FINALIZATION_RECEIPT_MATCHING_CURRENT_FINALIZED_SNAPSHOT_V2",
]
CORPUS_EXCLUDED_COMPLETIONS = [
    "PRACTICE",
    "IMPORTED",
    "HISTORIC",
    "DUPLICATE_RECEIPT",
    "DUPLICATE_ACTIVITY_SERIES",
    "REPORT_GENERATION",
    "AMENDMENT",
    "REOPENED",
    "SUPERSEDED",
    "NONFINAL",
    "MISSING_RECEIPT",
    "MISSING_READBACK",
    "MISMATCHED_READBACK",
    "NONCURRENT_READBACK",
    "WRONG_WORKSPACE",
]
CORPUS_ACTIVE_CONTEXTS = [
    "ERROR",
    "RECOVERY",
    "PURCHASE",
    "PERMISSION",
    "IMPORT",
    "EXPORT_OR_SHARE",
    "CAPTURE",
    "DESTRUCTIVE_CONFIRMATION",
    "ACTIVE_WORK",
]
CORPUS_LEDGER_STATES = [
    "ABSENT_FRESH_INSTALL",
    "VALID",
    "ERASED_COOLDOWN",
    "CORRUPT",
    "FUTURE",
    "MIGRATION_FAILED",
]
CORPUS_HOSTILE_CASES = [
    "CLOCK_ROLLBACK",
    "VERSION_PARSE_FAILURE",
    "REPEATED_SCENE_EVENTS",
    "PROMPT_DURING_FAILURE_RECOVERY",
    "MISSING_APP_STORE_ID",
    "UNSUPPORTED_PLATFORM",
    "CUSTOM_STAR_DIALOG",
    "PROMPT_REWARD_OR_EFFECT_COPY",
]
CORPUS_INTERRUPTION_CASES = [
    "BEFORE_ATTEMPT_RESERVATION",
    "AFTER_ATTEMPT_RESERVATION_BEFORE_SYSTEM_CALL",
    "AFTER_SYSTEM_CALL_BEFORE_RETURN",
    "DUPLICATE_SAME_EVENT",
    "KILL_AND_RELAUNCH",
]
CORPUS_RECOVERY_CASES = [
    "RESET_PRESERVES_LEDGER",
    "ERASE_COOLDOWN",
    "ABSENT_FRESH_INSTALL_REEARNS_THRESHOLD",
    "CORRUPT_FUTURE_MIGRATION_FAILED_DISABLE",
    "SUPPORT_PRESERVED",
    "ZERO_TELEMETRY_NETWORK_MARKETING_CONTACT_WRITES",
]
CORPUS_TRUTH = {
    "attemptDisposition": "SYSTEM_CONSIDERATION_REQUESTED",
    "systemPromptDisplayKnown": False,
    "supportAlwaysVisible": True,
    "supportConditionedOnRating": False,
    "ordinaryResetClearsAttemptHistory": False,
    "eraseRetainsCustomerData": False,
    "sceneUnavailableRecordsAttempt": False,
    "storeNoOpIsSuccess": False,
    "automaticRequestRequiresVerifiedAppStoreID": True,
}
CORPUS_CLAIMS = {
    "telemetryWritten": False,
    "analyticsWritten": False,
    "networkWritten": False,
    "marketingWritten": False,
    "contactWritten": False,
    "reviewContentStored": False,
    "starValueStored": False,
    "sentimentStored": False,
    "promptDisplayStored": False,
    "submissionStored": False,
    "storeResponseStored": False,
    "conversionStored": False,
    "rewardOffered": False,
    "ratingEffectClaimed": False,
}

FLAGS = {
    key: False
    for key in (
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
    "V23-P04-C39": (7519, "3feef54884e139e44071498650851ffe782514f3bce5de4326ccc5b4f503031e"),
    "V21-P04-C39": (5761, "ffeedbb4bb0a4dcb1336d0945808bbb48e4cb8f2c8674eaab47addbedca801df"),
    "V23-P04-C39-register": (318, "e0762666d1ce4800153258b3f74402d6292cbfbb4a12564f75ef0df4d6bf1589"),
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
    value = os.environ.get("V23_P04_C39_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C39 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")

    def block(card: str, indent: bytes) -> bytes:
        pattern = rb"(?ms)^" + re.escape(indent) + rb"### " + re.escape(card.encode()) + rb" .*?(?=^" + re.escape(indent) + rb"### |\Z)"
        match = re.search(pattern, blueprint)
        if match is None:
            raise ValueError(f"missing pinned source block: {card}")
        return match.group(0)

    marker = b'<a id="v23-p04-c39-register"></a>'
    register_lines = [line for line in foundation.splitlines(keepends=True) if marker in line]
    if len(register_lines) != 1:
        raise ValueError("missing or ambiguous pinned C39 register row")
    values = {
        "V23-P04-C39": block("V23-P04-C39", b""),
        "V21-P04-C39": block("V21-P04-C39", b"    "),
        "V23-P04-C39-register": register_lines[0],
    }
    result: list[dict[str, Any]] = []
    for anchor, value in values.items():
        measured = (len(value), sha(value))
        if measured != SOURCE_PINS[anchor]:
            raise ValueError(f"source pin drift: {anchor} expected={SOURCE_PINS[anchor]} actual={measured}")
        result.append({"anchor": anchor, "utf8Length": measured[0], "sha256": measured[1]})
    return result


def _coordination_evidence(root: Path) -> None:
    if git("rev-parse", "HEAD", cwd=root) != COORDINATION_HEAD or git("rev-parse", "HEAD^{tree}", cwd=root) != COORDINATION_TREE:
        raise ValueError("coordination identity drift")
    context = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json")
    fence = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    blockers = [
        "DIRECT_RECEIPT_PROVISIONAL_ZERO_ACCEPTANCE_CREDIT",
        "ACCEPTED_S10_6_RECONCILIATION_PENDING",
        "NATIVE_COMPILE_UNIT_UI_AND_RECOVERY_RUNS_NOT_RUN",
    ]
    if context.get("cardID") != CARD or context.get("attemptID") != 1 or context.get("registerOrdinal") != ORDINAL:
        raise ValueError("coordination context identity drift")
    if context.get("contextDigest") != CONTEXT_DIGEST or context.get("ownerAuthorizedPathAllocationDigest") != ALLOCATION_DIGEST or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("coordination context digest drift")
    if context.get("repository") != {"appBaseHead": BASE, "appBaseTree": BASE_TREE}:
        raise ValueError("coordination context app base drift")
    if context.get("acceptanceBlockers") != blockers or context.get("acceptanceCredit") is not False or context.get("acceptanceEnabled") is not False or context.get("adoptionEnabled") is not False:
        raise ValueError("C39 acceptance boundary drift")
    if tuple(context.get("existingPaths", ())) != EXISTING_PATHS or tuple(context.get("newPaths", ())) != NEW or tuple(context.get("expectedArtifacts", ())) != PATH_FENCE:
        raise ValueError("coordination context path fence drift")
    direct = ["V23-P04-C16"]
    proof = {
        "allAcceptanceCreditFalse": True,
        "duplicateCount": 0,
        "expectedDirectEdgeCount": 1,
        "failedIntermediateAcceptanceCount": 0,
        "incompatibleCount": 0,
        "missingCount": 0,
        "observedDirectEdgeCount": 1,
        "orphanCount": 0,
        "staleCount": 0,
        "uniqueCardCount": 1,
    }
    if context.get("directPrerequisites") != direct or context.get("directPrerequisiteProof") != proof:
        raise ValueError("C39 direct prerequisite proof drift")
    persistence = {
        "appleAPIDecision": "AppStore.requestReview(in:)",
        "corruptFutureOrMigrationFailure": "DISABLE_AUTO_REQUEST",
        "eraseDisposition": "ERASED_COOLDOWN_365_DAYS",
        "excludedSeries": EXCLUDED_SERIES,
        "freshInstall": "EARNS_THRESHOLD",
        "missingAppStoreIdentity": "TYPED_DISABLED_RATING_LINK",
        "ratingAttemptLedger": "DEVICE_LOCAL_NONWORKSPACE",
        "resetDisposition": "PRESERVE_LEDGER",
        "support": "ALWAYS_VISIBLE",
        "suppressionFlows": SUPPRESSION_CONTEXTS,
        "telemetry": "PROHIBITED",
        "threshold": {
            "distinctFinalizedActivitySeries": 3,
            "maximumRollingYearAttempts": 2,
            "minimumDays": 7,
            "minimumDaysBetweenAttempts": 120,
            "perMarketingVersion": 1,
        },
        "truthBoundary": "ATTEMPT_RECORDS_APP_CALL_NEVER_PROMPT_SHOWN_RATING_REVIEW_SUBMISSION_OR_EFFECT",
        "workspaceDurableFamilyCount": 0,
        "workspaceMigrationCount": 0,
        "workspaceModelCount": 0,
        "workspaceSchemaCount": 0,
        "workspaceStoreCount": 0,
        "workspaceWriterCount": 0,
    }
    if context.get("persistenceDecision") != persistence:
        raise ValueError("C39 persistence decision drift")
    projection = context.get("sourceProjection", {})
    expected_projection = {
        "acceptedExpansionHead": BASE,
        "acceptedExpansionTree": BASE_TREE,
        "canonicalSuccessor": {"cardID": "V23-P04-C40", "registerOrdinal": 128},
        "outcome": "NATIVE_APP_STORE_RATING_ELIGIBILITY_AND_ALWAYS_VISIBLE_SUPPORT_FALLBACK_FROM_GENERIC_FINALIZED_VALUE_RECEIPTS_DEVICE_LOCAL_AND_TELEMETRY_FREE",
        "sourceAuthorityMode": "USER_STANDING_OWNER_AUTHORIZATION_RELAYED_BY_ORCHESTRATOR",
    }
    if projection != expected_projection or context.get("lineage") != {"disposition": "REFINED_WITHOUT_LOSS"}:
        raise ValueError("C39 source projection/lineage drift")

    if fence.get("cardID") != CARD or fence.get("attemptID") != 1 or fence.get("fenceDigest") != FENCE_DIGEST or fence.get("frozenS10ReservationDigest") != FROZEN_S10_DIGEST or fence.get("baseHead") != BASE or fence.get("baseTree") != BASE_TREE:
        raise ValueError("coordination fence identity drift")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or tuple(fence.get("existingPaths", ())) != EXISTING_PATHS or tuple(fence.get("newPaths", ())) != NEW or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("coordination allowed path drift")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C39 path overlaps S10 reservation")
    prior = fence.get("priorFenceProof", {})
    if not isinstance(prior, dict) or prior.get("authorizationBasis") != "P02_C10_PREFERENCES_P00_C11_ERASE_AND_P02_C02_ERASE_RECOVERY_SOLE_OWNER_LINEAGES" or prior.get("authorizedOverlapEdgeCount") != 4 or prior.get("fenceCount") != 129 or prior.get("overlapEdgeCount") != 122 or prior.get("priorFenceSetDigest") != "0c0307e3dc3cc6b7a9b81e186e4ae68295457187cd7003621dd56e9924702721" or prior.get("priorOwnedPathCount") != 3 or prior.get("s10ReservedOverlapCount") != 0 or prior.get("unauthorizedOverlapCount") != 0 or prior.get("inheritedExistingPathEnvelopeOverlapCount") != 118:
        raise ValueError("C39 prior fence proof drift")

    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    if allocation.get("cardID") != CARD or allocation.get("allocationDigest") != ALLOCATION_DIGEST or tuple(allocation.get("exactOrderedPaths", ())) != PATH_FENCE or allocation.get("existingPaths") != list(EXISTING_PATHS) or allocation.get("newPaths") != list(NEW) or allocation.get("newProductTestUIFixturePathCount") != NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT or allocation.get("newToolingDocumentationPathCount") != NEW_TOOLING_DOCUMENTATION_PATH_COUNT or allocation.get("s10ReservedOverlapCount") != 0 or allocation.get("acceptanceCredit") is not False:
        raise ValueError("C39 allocation evidence drift")
    if allocation.get("persistenceDecision") != persistence or allocation.get("sourceProjection") != expected_projection:
        raise ValueError("C39 allocation semantic drift")

    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    expected_predecessor = {
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": "V23-P04-C38",
        "checkpointDigest": "724e470c7bb47e27710ed69d6fc3ac2821e4205da66fcc23e3389186cd74da5e",
        "verificationReceiptDigest": "9ba21034ab89d78b8e1e74ad5c9ddced800c505442bbd82f90cdb779344030e0",
    }
    if prerequisite.get("prerequisiteDigest") != PREREQUISITE_DIGEST or prerequisite.get("successorCardID") != CARD or prerequisite.get("canonicalDirectPrerequisiteCardIDs") != direct or prerequisite.get("ordinaryDirectEdgeCount") != 1 or prerequisite.get("directPrerequisiteProof") != proof or prerequisite.get("acceptanceCredit") is not False or prerequisite.get("immediateSequentialPredecessor") != expected_predecessor:
        raise ValueError("C39 prerequisite evidence drift")

    transition = read_json(root / f"transitions/{SEQUENCE:06d}-{CARD}-attempt-1-NOT_STARTED-to-HYDRATING.json")
    expected_transition = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "createdAt": "2026-09-01T22:45:00Z",
        "directPrerequisiteCheckpointDigests": ["3738094484c1ea8c898fe1b114d8cccb00b8b5f503f226194a4d4f40668b841e"],
        "fromState": "NOT_STARTED",
        "newLedgerDigest": LEDGER_DIGEST,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "priorLedgerDigest": "f4daaf3678ad493a3b61076d3a1423e9900b37d8850d421fc54e3a2fd71d5391",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "sequence": SEQUENCE,
        "toState": "HYDRATING",
        "transitionDigest": TRANSITION_DIGEST,
    }
    if transition != expected_transition:
        raise ValueError("C39 transition evidence drift")

    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    expected_entry = {
        "appleAPIDecision": "AppStore.requestReview(in:)",
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "classification": "IMPLEMENT_NOW",
        "contextDigest": CONTEXT_DIGEST,
        "directPrerequisites": direct,
        "ordinal": ORDINAL,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "planningStatus": "NOT_STARTED",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "ratingAttemptLedgerScope": "DEVICE_LOCAL_NONWORKSPACE",
        "state": "HYDRATING",
        "stateReason": "P04_C39_DEVICE_LOCAL_TELEMETRY_FREE_RATING_ELIGIBILITY_AND_ALWAYS_VISIBLE_SUPPORT_HYDRATING",
        "telemetryProhibited": True,
        "workspaceDurableFamilyCount": 0,
    }
    if ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != LEDGER_DIGEST:
        raise ValueError("C39 ledger identity drift")
    entries = [entry for entry in ledger.get("attempts", ()) if entry.get("cardID") == CARD]
    if len(entries) != 1 or entries[0] != expected_entry:
        raise ValueError("C39 ledger entry drift")
    active = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    projection_entries = [entry for entry in active.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if active.get("ledgerDigest") != LEDGER_DIGEST or active.get("projectionDigest") != PROJECTION_DIGEST or active.get("nextEligibleCardID") is not None or active.get("nextEligibleRegisterOrdinal") is not None or len(projection_entries) != 1 or projection_entries[0] != expected_entry:
        raise ValueError("C39 projection drift")


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
        "authorizedOverlapCount": 4,
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
    }


def _base_document() -> dict[str, Any]:
    auth = authority()
    source_rows, source_ready = rows()
    lifecycle = {
        "status": "IMPLEMENT_NOW",
        "persistence": "PERSISTENT_OR_PRODUCT_DELTA",
        "ratingAttemptLedger": "DEVICE_LOCAL_NONWORKSPACE",
        "solePreferenceOwner": "PreferencesAdapterV1",
        "eraseOwner": "EraseAllService",
        "canonicalPersistentSchema": None,
        "canonicalRows": [],
        "canonicalWriteOwners": [],
        "newDurableFamilyCount": 0,
        "newModelCount": 0,
        "newSchemaCount": 0,
        "newMigrationCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "resetDisposition": "PRESERVE_LEDGER",
        "eraseDisposition": "ERASED_COOLDOWN_365_DAYS",
        "backupExportSearchDiagnostics": "EXCLUDED_DEVICE_LOCAL_PREFERENCE",
    }
    independence = {
        "preferencesAdapterSoleOwner": True,
        "eraseAllServiceSoleOwner": True,
        "s6_6EraseRecoveryRegression": True,
        "newStore": False,
        "newWriter": False,
        "newRenderer": False,
        "newBackend": False,
        "newTelemetry": False,
        "newNetwork": False,
        "newMarketing": False,
        "newContactWriter": False,
        "persistedCustomerIdentifiers": False,
        "persistedWorkspaceIdentifiers": False,
        "persistedActivityIdentifiers": False,
        "persistedSnapshotIdentifiers": False,
        "persistedReceiptIdentifiers": False,
        "supportIndependent": True,
        "optionalProviderOnly": True,
    }
    return {
        "schema": "V23P04C39RatingSupportWorkflowToolingV1",
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
        "closedTypedWorkflow": True,
        "modernAppStoreRequestReview": True,
        "requestAPI": "AppStore.requestReview(in:)",
        "sceneBoundRequest": True,
        "solePreferencesAdapter": True,
        "soleEraseAllService": True,
        "s6_6EraseRecoveryRegression": True,
        "deviceLocalNonWorkspaceLedger": True,
        "persistedLedgerExcludesCustomerWorkspaceActivitySnapshotReceiptIdentifiers": True,
        "threeDistinctFinalizedActivitySeries": True,
        "minimumSevenDays": True,
        "stableMarketingVersion": True,
        "naturalIdleStoppingPoint": True,
        "matchingFinalizationReceiptAndCurrentFinalizedSnapshot": True,
        "oneAttemptPerMarketingVersion": True,
        "minimum120DaysBetweenAttempts": True,
        "maximumTwoAttemptsPerRollingYear": True,
        "excludedSeries": list(EXCLUDED_SERIES),
        "suppressionContexts": list(SUPPRESSION_CONTEXTS),
        "resetDisposition": "PRESERVE_LEDGER",
        "eraseDisposition": "ERASED_COOLDOWN_365_DAYS",
        "freshInstallDisposition": "ABSENT_FRESH_INSTALL_EARNS_THRESHOLD",
        "corruptFutureMigrationFailureDisposition": "DISABLE_AUTO_REQUEST",
        "duplicateInvocationDisposition": "IDEMPOTENT",
        "appDeathDisposition": "AT_MOST_ONE_CONSERVATIVE_ATTEMPT",
        "missingAppStoreIdentity": "TYPED_DISABLED_RATING_LINK",
        "supportAlwaysVisible": True,
        "supportIndependentOfRating": True,
        "noPromptDisplayRecording": True,
        "noStarRecording": True,
        "noReviewRecording": True,
        "noSubmissionRecording": True,
        "noStoreResponseRecording": True,
        "noConversionRecording": True,
        "noTelemetry": True,
        "noAnalytics": True,
        "noNetwork": True,
        "noMarketingWrites": True,
        "noContactWrites": True,
        "noDeprecatedRequestAPI": True,
        "noCustomRatingDialog": True,
        "noNewDurableFamily": True,
        "noNewModel": True,
        "noNewSchema": True,
        "noNewMigration": True,
        "noNewStore": True,
        "noNewWriter": True,
        "noParallelRenderer": True,
        "noParallelBackend": True,
        "fiveEvidenceScenarios": True,
        "scenarioSelectors": list(SELECTORS),
        "finalHashesUnsealed": True,
    }
    contract = {
        **base,
        "contract": "RatingSupportWorkflowContractV1",
        "requirements": requirements,
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusExpectations": {
            "schema": CORPUS_SCHEMA,
            "schemaVersion": 1,
            "cardID": CARD,
            "testOnly": True,
            "synthetic": True,
            "containsCustomerData": False,
            "containsSecrets": False,
            "scenarioIDs": list(CORPUS_SCENARIO_IDS),
            "thresholds": dict(CORPUS_THRESHOLDS),
            "boundaryVectors": list(CORPUS_BOUNDARY_VECTORS),
            "includedReadbacks": list(CORPUS_INCLUDED_READBACKS),
            "excludedCompletionCases": list(CORPUS_EXCLUDED_COMPLETIONS),
            "activeContextSuppressions": list(CORPUS_ACTIVE_CONTEXTS),
            "ledgerStates": list(CORPUS_LEDGER_STATES),
            "interruptionVectors": list(CORPUS_INTERRUPTION_CASES),
            "truth": dict(CORPUS_TRUTH),
            "hostileCases": list(CORPUS_HOSTILE_CASES),
            "recoveryCases": list(CORPUS_RECOVERY_CASES),
            "claims": dict(CORPUS_CLAIMS),
        },
    }
    evidence = {
        **base,
        "receipt": "RatingSupportWorkflowEvidenceReceiptV1",
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "scenarioEvidenceIDs": list(SELECTORS),
        "claims": dict(CORPUS_CLAIMS),
        "prohibitedClaims": [
            "prompt shown",
            "star value",
            "review submitted",
            "store response",
            "conversion",
            "provider adoption",
            "provider acceptance",
            "network",
            "telemetry",
            "marketing effect",
        ],
        "corpusSchema": CORPUS_SCHEMA,
        "corpusScenarioIDs": list(CORPUS_SCENARIO_IDS),
        "thresholds": dict(CORPUS_THRESHOLDS),
        "boundaryVectors": list(CORPUS_BOUNDARY_VECTORS),
        "includedReadbacks": list(CORPUS_INCLUDED_READBACKS),
        "excludedCompletionCases": list(CORPUS_EXCLUDED_COMPLETIONS),
        "activeContextSuppressions": list(CORPUS_ACTIVE_CONTEXTS),
        "ledgerStates": list(CORPUS_LEDGER_STATES),
        "interruptionVectors": list(CORPUS_INTERRUPTION_CASES),
        "truth": dict(CORPUS_TRUTH),
        "hostileCases": list(CORPUS_HOSTILE_CASES),
        "interruptionCases": list(CORPUS_INTERRUPTION_CASES),
        "recoveryCases": list(CORPUS_RECOVERY_CASES),
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
        "nativeRatingClaim": False,
        "hostedRatingClaim": False,
        "systemPromptOutcomeClaim": False,
        "supportAlwaysVisible": True,
        "supportIndependentOfRating": True,
        "missingAppStoreIdentity": "TYPED_DISABLED_RATING_LINK",
        "nativeOrHostedNetwork": False,
        "telemetryOrMarketing": False,
        "contactWrites": False,
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
        "schema": "V23P04C39ToolingManifestV1",
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
            "s10ReservationOverlapCount": 0,
        },
        "lifecycle": base["lifecycle"],
        "independence": base["independence"],
        "optionalProvider": "EXTERNAL_APP_STORE_IDENTITY:RATING_LINK",
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
        "fencePathCount": {"const": len(PATH_FENCE)},
        "existingPathCount": {"const": len(EXISTING_PATHS)},
        "newPathCount": {"const": len(NEW)},
        "productTestUIFixturePathCount": {"const": NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT},
        "toolingPathCount": {"const": NEW_TOOLING_DOCUMENTATION_PATH_COUNT},
        "authorizedOverlapCount": {"const": 4},
        "unauthorizedOverlapCount": {"const": 0},
        "s10ReservationOverlapCount": {"const": 0},
        "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST},
        "orderedPathFence": {"type": "array", "const": list(PATH_FENCE)},
        "existingPaths": {"type": "array", "const": list(EXISTING_PATHS)},
        "newPaths": {"type": "array", "const": list(NEW)},
        "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3},
        "finalHashesSealed": {"const": False},
    }
    lifecycle = {
        "type": "object",
        "required": [
            "status",
            "persistence",
            "ratingAttemptLedger",
            "solePreferenceOwner",
            "eraseOwner",
            "canonicalPersistentSchema",
            "canonicalRows",
            "canonicalWriteOwners",
            "newDurableFamilyCount",
            "newModelCount",
            "newSchemaCount",
            "newMigrationCount",
            "newStoreCount",
            "newWriterCount",
            "resetDisposition",
            "eraseDisposition",
            "backupExportSearchDiagnostics",
        ],
        "properties": {
            "status": {"const": "IMPLEMENT_NOW"},
            "persistence": {"const": "PERSISTENT_OR_PRODUCT_DELTA"},
            "ratingAttemptLedger": {"const": "DEVICE_LOCAL_NONWORKSPACE"},
            "solePreferenceOwner": {"const": "PreferencesAdapterV1"},
            "eraseOwner": {"const": "EraseAllService"},
            "canonicalPersistentSchema": {"type": ["string", "null"]},
            "canonicalRows": {"type": "array"},
            "canonicalWriteOwners": {"type": "array"},
            "newDurableFamilyCount": {"const": 0},
            "newModelCount": {"const": 0},
            "newSchemaCount": {"const": 0},
            "newMigrationCount": {"const": 0},
            "newStoreCount": {"const": 0},
            "newWriterCount": {"const": 0},
            "resetDisposition": {"const": "PRESERVE_LEDGER"},
            "eraseDisposition": {"const": "ERASED_COOLDOWN_365_DAYS"},
            "backupExportSearchDiagnostics": {"const": "EXCLUDED_DEVICE_LOCAL_PREFERENCE"},
        },
        "additionalProperties": False,
    }
    independence = {
        "type": "object",
        "required": [
            "preferencesAdapterSoleOwner",
            "eraseAllServiceSoleOwner",
            "s6_6EraseRecoveryRegression",
            "newStore",
            "newWriter",
            "newRenderer",
            "newBackend",
            "newTelemetry",
            "newNetwork",
            "newMarketing",
            "newContactWriter",
            "persistedCustomerIdentifiers",
            "persistedWorkspaceIdentifiers",
            "persistedActivityIdentifiers",
            "persistedSnapshotIdentifiers",
            "persistedReceiptIdentifiers",
            "supportIndependent",
            "optionalProviderOnly",
        ],
        "properties": {
            "preferencesAdapterSoleOwner": {"const": True},
            "eraseAllServiceSoleOwner": {"const": True},
            "s6_6EraseRecoveryRegression": {"const": True},
            "newStore": {"const": False},
            "newWriter": {"const": False},
            "newRenderer": {"const": False},
            "newBackend": {"const": False},
            "newTelemetry": {"const": False},
            "newNetwork": {"const": False},
            "newMarketing": {"const": False},
            "newContactWriter": {"const": False},
            "persistedCustomerIdentifiers": {"const": False},
            "persistedWorkspaceIdentifiers": {"const": False},
            "persistedActivityIdentifiers": {"const": False},
            "persistedSnapshotIdentifiers": {"const": False},
            "persistedReceiptIdentifiers": {"const": False},
            "supportIndependent": {"const": True},
            "optionalProviderOnly": {"const": True},
        },
        "additionalProperties": False,
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C39RatingSupportWorkflowToolingV1",
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
            "schema": {"const": "V23P04C39RatingSupportWorkflowToolingV1"},
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
            "lifecycle": lifecycle,
            "independence": independence,
        },
    }


if __name__ == "__main__":
    print(json.dumps(authority(), sort_keys=True, indent=2))
