#!/usr/bin/env python3
"""Pinned deterministic tooling for V23-P04-C38.

The C38 lane describes bounded advanced recurrence and exception-calendar
workflow behavior while consuming the existing C51/C12/C22 schedule, override,
occurrence, due, and reminder owners.  These artifacts are static evidence
until the named native and hosted gates run; this module never creates a
second recurrence engine, store, writer, calendar, reminder, or server.
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
CARD = "V23-P04-C38"
ORDINAL = 123
TITLE = "Advanced recurrence/exception-calendar authoring, due projection, reminders, history, and DST recovery"
BASE = "4971e4e4ac939000d87b23dce1df6e6c2a83fa84"
BASE_TREE = "e62505274cb1d188e741bd186d8dc947e34905e5"
COORDINATION_HEAD = "2e18e556cf726d03510cbf8a1222ce9b70482b32"
COORDINATION_TREE = "dfdfff71d0e2055568c3ca56628c8d6ff2ceccbc"
SEQUENCE = 551
ALLOCATION_DIGEST = "34fc7000066a50cdd9ae9e0cbd0341a2b01f1346e24083642a38c6f554db1c06"
PREREQUISITE_DIGEST = "6a89590421106d8fb21c731b0d202b35355fd96aefd263b380611f4ae16b200c"
CONTEXT_DIGEST = "d7fdce209aa17f2d231fd8f41713dd24adcf106f8724c80a2fa256faa2dd2cd2"
FENCE_DIGEST = "d7eddeea643a5de6bb25f51add5cecd365b5afe7d760bf2ad197e42c21d9defc"
TRANSITION_DIGEST = "4afbce4d55c224159548c7c90f3aa2a103293d10ba64151d0553bb2d98ae5721"
LEDGER_DIGEST = "07fad0d9f974035d400e82a144b282a0ab6c48eada40895afb162fcc07f41f60"
PROJECTION_DIGEST = "c4b82396a94e66ad3489ffc89b6cc87495e9ae4838c8c242455146dd75e30702"
CORRECTION_RECEIPT_DIGEST = "f9cb0d0251123711d1944c5c82960cfefed08465012f883186218d6a665a9a60"
HYDRATION_REVISION = 2
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FINAL_HASHES_SEALED = False

# Generic aliases are intentionally kept stable for repository-wide v23
# tooling checks.
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

PRODUCT = (
    "FieldEvidenceApp/Application/Scheduling/AdvancedRecurrenceWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/Scheduling/AdvancedRecurrenceWorkflowView.swift",
    "FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/Scheduling/V23P04C38AdvancedRecurrenceWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C38AdvancedRecurrenceWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c38_contracts.py",
    "Scripts/v23/generate_p04_c38_contracts.py",
    "Scripts/v23/verify_p04_c38_contracts.py",
)
SCHEMA = "Scripts/v23/advanced-recurrence-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C38AdvancedRecurrenceWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C38AdvancedRecurrenceWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C38BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C38-tooling-manifest.json"
NEW = (*PRODUCT, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
EXISTING_PATHS = ("FieldEvidenceApp/Application/Workflow/ScheduleCoordinatorV1.swift",)
PATH_FENCE = (*NEW, *EXISTING_PATHS)
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = PRODUCT

SELECTOR_ROWS = (
    ("G01", "V23-P04-C38-G01", "GOLDEN"),
    ("A01", "V23-P04-C38-A01", "ALTERNATE"),
    ("H01", "V23-P04-C38-H01", "HOSTILE"),
    ("I01", "V23-P04-C38-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C38-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "evidenceID": "V23-P04-C38-G01",
        "focus": "BOUNDED_RECURRENCE_GRAMMAR_AND_DETERMINISTIC_OCCURRENCE_IDENTITY",
        "expectedEffects": {
            "patterns": ["DAILY", "WEEKLY", "CALENDAR_DAY", "WEEKDAY", "LAST_DAY"],
            "intervalBounds": {"DAILY": [1, 365], "WEEKLY": [1, 52], "CALENDAR_DAY": [1, 12], "WEEKDAY": [1, 12], "LAST_DAY": [1, 12]},
            "deterministicOccurrenceIdentity": True,
            "dueHistoryAppendOnly": True,
            "reminderHistoryAppendOnly": True,
        },
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "evidenceID": "V23-P04-C38-A01",
        "focus": "EXCEPTION_PRECEDENCE_CALENDAR_CASES_AND_SCOPES",
        "expectedEffects": {
            "calendarCases": ["LEAP_DAY", "MONTH_END", "LAST_WEEKDAY"],
            "scopes": ["THIS_OCCURRENCE", "THIS_AND_FUTURE", "ENTIRE_SERIES"],
            "overrideKinds": ["SKIP", "MOVE", "ADD_ONE"],
        },
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "evidenceID": "V23-P04-C38-H01",
        "focus": "INVALID_GRAMMAR_OVERRIDE_PREVIEW_AND_OCCURRENCE_IDENTITY_REJECTION",
        "expectedEffects": {
            "rejectedCases": [
                "ZERO_INTERVAL",
                "IMPOSSIBLE_DATE",
                "UNBOUNDED_EXPANSION",
                "DUPLICATE_SAME_PRIORITY_OVERRIDE",
                "STALE_PREVIEW",
                "UNSUPPORTED_FUTURE_RECURRENCE",
                "OCCURRENCE_IDENTITY_DRIFT",
            ],
            "canonicalWrites": 0,
        },
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "evidenceID": "V23-P04-C38-I01",
        "focus": "DST_TIMEZONE_CLOCK_REMINDER_AND_EFFECT_BEFORE_RECEIPT_RECOVERY",
        "expectedEffects": {
            "interruptionCases": [
                "SPRING_FORWARD",
                "FALL_BACK",
                "TIME_ZONE_CHANGE",
                "MANUAL_CLOCK_CHANGE",
                "REMINDER_DENIED",
                "REMINDER_CHANGED",
                "CANCEL_BEFORE_EFFECT",
                "EFFECT_BEFORE_RECEIPT_EXACT_RETRY",
            ],
            "canonicalEffects": [0, 1],
        },
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "evidenceID": "V23-P04-C38-R01",
        "focus": "COMPLETION_IMMUTABILITY_EXACT_REPLAY_REBUILD_RESTORE_AND_DIVERGENCE_QUARANTINE",
        "expectedEffects": {
            "recoveryCases": [
                "COMPLETION_IMMUTABLE_AFTER_SCHEDULE_CHANGE",
                "EXACT_REPLAY",
                "DETERMINISTIC_REBUILD",
                "RESTORE_IDENTICAL",
                "INTERRUPTED_EDITOR_RESUME",
                "DIVERGENT_REPLAY_REJECTED",
            ],
            "replayEffects": 1,
            "divergentEffects": 0,
        },
    },
)

CORPUS_SCHEMA = "V23P04C38AdvancedRecurrenceWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema",
        "schemaVersion",
        "cardID",
        "testOnly",
        "synthetic",
        "containsCustomerData",
        "containsSecrets",
        "evidenceIDs",
        "golden",
        "alternate",
        "hostileCases",
        "interruptionCases",
        "recoveryCases",
        "persistence",
        "claims",
    )
)
CORPUS_GOLDEN = {
    "patterns": [
        {"kind": "DAILY", "minimumInterval": 1, "maximumInterval": 365},
        {"kind": "WEEKLY", "minimumInterval": 1, "maximumInterval": 52},
        {"kind": "CALENDAR_DAY", "minimumInterval": 1, "maximumInterval": 12},
        {"kind": "WEEKDAY", "minimumInterval": 1, "maximumInterval": 12},
        {"kind": "LAST_DAY", "minimumInterval": 1, "maximumInterval": 12},
    ],
    "overrideKinds": ["SKIP", "MOVE", "ADD_ONE"],
    "deterministicOccurrenceIdentity": True,
    "dueHistoryAppendOnly": True,
    "reminderHistoryAppendOnly": True,
}
CORPUS_ALTERNATE = {
    "calendarCases": ["LEAP_DAY", "MONTH_END", "LAST_WEEKDAY"],
    "scopes": ["THIS_OCCURRENCE", "THIS_AND_FUTURE", "ENTIRE_SERIES"],
}
CORPUS_HOSTILE_CASES = [
    "ZERO_INTERVAL",
    "IMPOSSIBLE_DATE",
    "UNBOUNDED_EXPANSION",
    "DUPLICATE_SAME_PRIORITY_OVERRIDE",
    "STALE_PREVIEW",
    "UNSUPPORTED_FUTURE_RECURRENCE",
    "OCCURRENCE_IDENTITY_DRIFT",
]
CORPUS_INTERRUPTION_CASES = [
    "SPRING_FORWARD",
    "FALL_BACK",
    "TIME_ZONE_CHANGE",
    "MANUAL_CLOCK_CHANGE",
    "REMINDER_DENIED",
    "REMINDER_CHANGED",
    "CANCEL_BEFORE_EFFECT",
    "EFFECT_BEFORE_RECEIPT_EXACT_RETRY",
]
CORPUS_RECOVERY_CASES = [
    "COMPLETION_IMMUTABLE_AFTER_SCHEDULE_CHANGE",
    "EXACT_REPLAY",
    "DETERMINISTIC_REBUILD",
    "RESTORE_IDENTICAL",
    "INTERRUPTED_EDITOR_RESUME",
    "DIVERGENT_REPLAY_REJECTED",
]
CORPUS_PERSISTENCE = {
    "addsDurableFamily": False,
    "changesSchema": False,
    "createsRecurrenceEngine": False,
}
CORPUS_CLAIMS = {
    "nativeCalendarIntegrated": False,
    "nativeReminderIntegrated": False,
    "hostedCalendarIntegrated": False,
    "hostedReminderIntegrated": False,
    "providerAdopted": False,
    "providerAccepted": False,
    "providerReleased": False,
    "networkRequired": False,
    "accountRequired": False,
    "entitlementRequired": False,
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
    "V23-P04-C38": (7276, "60314b0905777276c68d00838bbeaae01361678bb97735c99100043385728b77"),
    "V21-P04-C38": (3957, "57082aa32ece619b30e5ec7d6f4ce0a7a5d8c6d1459e93a37b149a690bab8c43"),
    "V23-P04-C38-register": (330, "26622b69a77009276b6afc3d2772261e50c38e7657629496f66cc7544e62f7fd"),
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
    value = os.environ.get("V23_P04_C38_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C38 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")

    def block(card: str, indent: bytes) -> bytes:
        pattern = rb"(?ms)^" + re.escape(indent) + rb"### " + re.escape(card.encode()) + rb" .*?(?=^" + re.escape(indent) + rb"### |\Z)"
        match = re.search(pattern, blueprint)
        if match is None:
            raise ValueError(f"missing pinned source block: {card}")
        return match.group(0)

    marker = b"<a id=\"v23-p04-c38-register\"></a>"
    register_lines = [line for line in foundation.splitlines(keepends=True) if marker in line]
    if len(register_lines) != 1:
        raise ValueError("missing or ambiguous pinned C38 register row")
    values = {
        "V23-P04-C38": block("V23-P04-C38", b""),
        "V21-P04-C38": block("V21-P04-C38", b"    "),
        "V23-P04-C38-register": register_lines[0],
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
        "ALL_DIRECT_RECEIPTS_PROVISIONAL_ZERO_ACCEPTANCE_CREDIT",
        "EXISTING_C51_C22_CANONICAL_SCHEDULE_OVERRIDE_DUE_REMINDER_OWNERS_ONLY",
        "ACCEPTED_S10_6_RECONCILIATION_PENDING",
        "NATIVE_COMPILE_UNIT_UI_AND_RECOVERY_RUNS_NOT_RUN",
    ]
    if context.get("cardID") != CARD or context.get("registerOrdinal") != ORDINAL:
        raise ValueError("coordination context identity drift")
    if context.get("contextDigest") != CONTEXT_DIGEST or context.get("pathFenceDigest") != FENCE_DIGEST or context.get("hydrationRevision") != HYDRATION_REVISION or context.get("overrideCommitOwner") != "ScheduleCoordinatorV1" or context.get("ownerAuthorizedPathAllocationDigest") != ALLOCATION_DIGEST or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("coordination context digest drift")
    if context.get("repository") != {"appBaseHead": BASE, "appBaseTree": BASE_TREE}:
        raise ValueError("coordination context app base drift")
    if context.get("acceptanceBlockers") != blockers or context.get("acceptanceCredit") is not False or context.get("acceptanceEnabled") is not False or context.get("adoptionEnabled") is not False:
        raise ValueError("C38 acceptance boundary drift")
    if tuple(context.get("existingPaths", ())) != EXISTING_PATHS or tuple(context.get("newPaths", ())) != NEW or tuple(context.get("expectedArtifacts", ())) != PATH_FENCE:
        raise ValueError("coordination context path fence drift")
    direct = ["V23-P03-C51", "V23-P04-C12", "V23-P04-C22"]
    proof = {"allAcceptanceCreditFalse": True, "duplicateCount": 0, "expectedDirectEdgeCount": 3, "failedIntermediateAcceptanceCount": 0, "incompatibleCount": 0, "missingCount": 0, "observedDirectEdgeCount": 3, "orphanCount": 0, "staleCount": 0, "uniqueCardCount": 3}
    if context.get("directPrerequisites") != direct or context.get("directPrerequisiteProof") != proof:
        raise ValueError("C38 direct prerequisite proof drift")
    persistence = {
        "canonicalPersistentSchema": "V53",
        "canonicalRows": ["ScheduleDefinitionReleaseRow", "OccurrenceHistoryEventRow", "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"],
        "canonicalWriteOwners": ["ScheduleMutationV1", "ScheduleCoordinatorV1", "WorkspaceWriterV1"],
        "derivedOnly": ["OccurrenceDueQueueStateV1", "LocalReminderReconciliationV1", "DueQueueProjectionV1", "ReminderProjectionV1"],
        "newDurableFamilyCount": 0,
        "newMigrationCount": 0,
        "newModelCount": 0,
        "newSchemaCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "totalModelCount": 168,
    }
    if context.get("persistenceDecision") != persistence:
        raise ValueError("C38 persistence decision drift")
    consumption = {
        "dueReminderOwner": "V23-P04-C22",
        "persistentContractSchema": "V53",
        "prohibition": "NO_NEW_DURABLE_FAMILY_MODEL_SCHEMA_MIGRATION_STORE_WRITER_OR_CANONICAL_SERIES_OVERRIDE_DUE_OR_REMINDER_TRUTH",
        "reinspectionOwner": "V23-P04-C12",
        "reinspectionSchema": "ReinspectionAndExceptionSchemaV1",
        "scheduleAndOverrideRows": ["ScheduleDefinitionReleaseRow", "OccurrenceHistoryEventRow", "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"],
        "scheduleExceptionOwner": "V23-P03-C51",
        "totalModelCount": 168,
    }
    projection = context.get("sourceProjection", {})
    if projection.get("acceptedExpansionHead") != BASE or projection.get("acceptedExpansionTree") != BASE_TREE or projection.get("contractConsumption") != consumption:
        raise ValueError("C38 source projection drift")
    if projection.get("lineage") != {"disposition": "EXACT_WITH_GENERATION_REBIND", "predecessorCardID": "V21-P04-C38"}:
        raise ValueError("C38 lineage authority drift")
    if projection.get("canonicalSuccessor") != {"cardID": "V23-P04-C39", "registerOrdinal": 124} or projection.get("sourceAuthorityMode") != "REPRODUCED_FROM_OWNER_PINNED_ACCEPTED_APP_GIT_BLOBS":
        raise ValueError("C38 successor/source authority drift")

    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST or fence.get("frozenS10ReservationDigest") != FROZEN_S10_DIGEST or fence.get("baseHead") != BASE or fence.get("baseTree") != BASE_TREE or fence.get("hydrationRevision") != HYDRATION_REVISION:
        raise ValueError("coordination fence identity drift")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or tuple(fence.get("existingPaths", ())) != EXISTING_PATHS or tuple(fence.get("newPaths", ())) != NEW or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("coordination allowed path drift")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C38 path overlaps S10 reservation")
    prior = fence.get("priorFenceProof", {})
    if not isinstance(prior, dict) or prior.get("authorizationBasis") != "C28_C51_SCHEDULE_COORDINATOR_SEMANTIC_OWNER_LINEAGE_AND_USER_RELAYED_CORRECTION_AUTHORITY" or prior.get("authorizedOverlapEdgeCount") != 2 or prior.get("fenceCount") != 129 or prior.get("overlapEdgeCount") != 13 or prior.get("priorFenceSetDigest") != "ff30d99367c68a95bcd27a81a40bf2e44b84a159d70b29c42ca352aa075149c9" or prior.get("priorOwnedPathCount") != 1 or prior.get("s10ReservedOverlapCount") != 0 or prior.get("unauthorizedOverlapCount") != 0 or prior.get("inheritedExistingPathEnvelopeOverlapCount") != 11:
        raise ValueError("C38 prior fence proof drift")

    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    if allocation.get("cardID") != CARD or allocation.get("allocationDigest") != ALLOCATION_DIGEST or tuple(allocation.get("exactOrderedPaths", ())) != NEW or allocation.get("existingPaths") != [] or allocation.get("newPaths") != list(NEW) or allocation.get("newProductTestUIFixturePathCount") != 5 or allocation.get("newToolingDocumentationPathCount") != 8 or allocation.get("s10ReservedOverlapCount") != 0 or allocation.get("acceptanceCredit") is not False:
        raise ValueError("C38 allocation evidence drift")
    if allocation.get("persistenceDecision") != persistence or allocation.get("sourceProjection", {}).get("contractConsumption") != consumption:
        raise ValueError("C38 allocation semantic drift")

    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    if prerequisite.get("prerequisiteDigest") != PREREQUISITE_DIGEST or prerequisite.get("successorCardID") != CARD or prerequisite.get("canonicalDirectPrerequisiteCardIDs") != direct or prerequisite.get("ordinaryDirectEdgeCount") != 3 or prerequisite.get("directPrerequisiteProof") != proof or prerequisite.get("acceptanceCredit") is not False:
        raise ValueError("C38 prerequisite evidence drift")
    if prerequisite.get("immediateSequentialPredecessor") != {
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": "V23-P04-C37",
        "checkpointDigest": "072f7c13611e6cff2ee3e636779c7ecb54ef5f1721fff2c39d44acee90e88633",
        "verificationReceiptDigest": "958a122c70cf09a0654dee92ef975bb1d06335fdcb70d75300e0c8c8c16733f9",
    }:
        raise ValueError("C38 immediate predecessor evidence drift")

    transition = read_json(root / f"transitions/{SEQUENCE:06d}-{CARD}-attempt-1-HYDRATING-to-HYDRATING-schedule-override-commit-fence-correction.json")
    expected_transition = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "createdAt": "2026-09-01T22:15:00Z",
        "fromState": "HYDRATING",
        "hydrationCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "newLedgerDigest": LEDGER_DIGEST,
        "originalAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "priorContextDigest": "aa1d7c36c5a6ca1157956ba7085e779c94c68da79e1000a0bd380fec203e3f75",
        "priorLedgerDigest": "ecbbd6b273c48bcc10c26a5e2543c331e60f4b938d3b7c9dc53f3780c237512c",
        "priorPathFenceDigest": "664b6e80be4d4d1ed4c310254ff415f55bb1e6d9863808fe296c8436412928ea",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "reason": "P04_C38_REQUIRES_CANONICAL_OVERRIDE_AUTHORING_NOT_VALIDATION_ONLY_APPROXIMATION_SCHEDULE_COORDINATOR_IS_EXISTING_SOLE_WRITER_SURFACE_OVER_SCHEDULE_OVERRIDE_EVENT_ROW_AND_SCHEDULE_MUTATION_PAYLOAD_V1_APPEND_OVERRIDE_EVENT",
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "sequence": SEQUENCE,
        "toState": "HYDRATING",
        "transitionDigest": TRANSITION_DIGEST,
    }
    if transition != expected_transition:
        raise ValueError("C38 transition evidence drift")

    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    if ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != LEDGER_DIGEST:
        raise ValueError("C38 ledger identity drift")
    expected_entry = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "canonicalPersistentSchema": "V53",
        "cardID": CARD,
        "classification": "IMPLEMENT_NOW",
        "contextDigest": CONTEXT_DIGEST,
        "directPrerequisites": direct,
        "hydrationFenceCorrectionDigest": CORRECTION_RECEIPT_DIGEST,
        "hydrationRevision": HYDRATION_REVISION,
        "newDurableFamilyCount": 0,
        "ordinal": ORDINAL,
        "overrideCommitOwner": "ScheduleCoordinatorV1",
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "planningStatus": "NOT_STARTED",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "reinspectionOwner": "V23-P04-C12",
        "scheduleTruthOwners": ["V23-P03-C51", "V23-P04-C22"],
        "state": "HYDRATING",
        "stateReason": "P04_C38_REQUIRES_CANONICAL_OVERRIDE_AUTHORING_NOT_VALIDATION_ONLY_APPROXIMATION_SCHEDULE_COORDINATOR_IS_EXISTING_SOLE_WRITER_SURFACE_OVER_SCHEDULE_OVERRIDE_EVENT_ROW_AND_SCHEDULE_MUTATION_PAYLOAD_V1_APPEND_OVERRIDE_EVENT",
        "totalModelCount": 168,
    }
    entries = [entry for entry in ledger.get("attempts", ()) if entry.get("cardID") == CARD]
    if len(entries) != 1 or entries[0] != expected_entry:
        raise ValueError("C38 ledger entry drift")
    active = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    projection_entries = [entry for entry in active.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if active.get("ledgerDigest") != LEDGER_DIGEST or active.get("projectionDigest") != PROJECTION_DIGEST or len(projection_entries) != 1 or projection_entries[0] != expected_entry:
        raise ValueError("C38 projection drift")

    correction = read_json(root / f"receipts/{CARD}-schedule-override-commit-hydration-fence-correction-v2.json")
    if correction.get("schema") != "HydratedPathFenceCorrectionReceiptV1" or correction.get("receiptDigest") != CORRECTION_RECEIPT_DIGEST or correction.get("cardID") != CARD or correction.get("hydrationRevision") != HYDRATION_REVISION or correction.get("allowedPathCount") != 14 or correction.get("existingPathCount") != 1 or correction.get("newPathCount") != 13 or correction.get("addedPaths") != list(EXISTING_PATHS) or correction.get("soleCanonicalWriter") != "ScheduleCoordinatorV1" or correction.get("canonicalMutationPayload") != "ScheduleMutationPayloadV1.appendOverrideEvent" or correction.get("validationOnlyProhibited") is not True or correction.get("unauthorizedPriorFenceOverlapCount") != 0:
        raise ValueError("C38 hydration correction receipt drift")


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
        "fencePathCount": 14,
        "existingPathCount": 1,
        "newPathCount": 13,
        "productTestUIFixturePathCount": 5,
        "toolingPathCount": 8,
        "authorizedOverlapCount": 2,
        "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0,
        "frozenS10ReservationDigest": FROZEN_S10_DIGEST,
        "orderedPathFence": list(PATH_FENCE),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW),
        "hydrationRevision": HYDRATION_REVISION,
        "correctionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
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
        "existingPathCount": 1,
        "newPathCount": len(NEW),
        "productTestUIFixturePathCount": len(PRODUCT),
        "toolingPathCount": len(OWNED),
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
        "canonicalPersistentSchema": "V53",
        "totalModelCount": 168,
        "canonicalRows": ["ScheduleDefinitionReleaseRow", "OccurrenceHistoryEventRow", "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"],
        "canonicalWriteOwners": ["ScheduleMutationV1", "ScheduleCoordinatorV1", "WorkspaceWriterV1"],
        "derivedOnly": ["OccurrenceDueQueueStateV1", "LocalReminderReconciliationV1", "DueQueueProjectionV1", "ReminderProjectionV1"],
        "readOnlyOwners": ["V23-P03-C51", "V23-P04-C12", "V23-P04-C22"],
        "newDurableFamilyCount": 0,
        "newModelCount": 0,
        "newSchemaCount": 0,
        "newMigrationCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
    }
    independence = {
        "scheduleExceptionOwner": "V23-P03-C51",
        "reinspectionOwner": "V23-P04-C12",
        "dueReminderOwner": "V23-P04-C22",
        "canonicalPersistentSchema": "V53",
        "totalModelCount": 168,
        "newDurableFamily": False,
        "newModel": False,
        "newSchema": False,
        "newMigration": False,
        "newStore": False,
        "newWriter": False,
        "secondRecurrenceEngine": False,
        "cron": False,
        "rrule": False,
        "server": False,
        "calendarIntegration": False,
        "backgroundExecution": False,
        "holidayDatabase": False,
    }
    return {
        "schema": "V23P04C38AdvancedRecurrenceWorkflowToolingV1",
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
        "boundedClosedRecurrenceGrammar": True,
        "deterministicOccurrenceIdentity": True,
        "exceptionPrecedence": True,
        "exceptionScopes": ["THIS_OCCURRENCE", "THIS_AND_FUTURE", "ENTIRE_SERIES"],
        "completedOccurrenceImmutable": True,
        "dstRecovery": True,
        "timezoneRecovery": True,
        "clockChangeRecovery": True,
        "reminderReconciliation": True,
        "exactInterruptionReplay": True,
        "expectedRevisionMutationID": True,
        "oneCanonicalWriterTransaction": True,
        "durableReceipt": True,
        "effectBeforeReceiptRecovery": True,
        "canonicalOwners": ["V23-P03-C51", "V23-P04-C22"],
        "reinspectionOwner": "V23-P04-C12",
        "persistentSchema": "V53",
        "totalModelCount": 168,
        "noCron": True,
        "noRRULE": True,
        "noServer": True,
        "noCalendarIntegration": True,
        "noBackgroundExecution": True,
        "noHolidayDatabase": True,
        "noSecondRecurrenceEngine": True,
        "noNewDurableFamily": True,
        "noNewModel": True,
        "noNewSchema": True,
        "noNewMigration": True,
        "noNewStore": True,
        "noNewWriter": True,
        "fiveEvidenceScenarios": True,
        "scenarioSelectors": list(SELECTORS),
        "futureReentry": "CLOSED_TYPED_REENTRY_ONLY",
        "finalHashesUnsealed": True,
    }
    contract = {
        **base,
        "contract": "AdvancedRecurrenceWorkflowContractV1",
        "requirements": requirements,
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusExpectations": {
            "schema": CORPUS_SCHEMA,
            "golden": dict(CORPUS_GOLDEN),
            "alternate": dict(CORPUS_ALTERNATE),
            "hostileCases": list(CORPUS_HOSTILE_CASES),
            "interruptionCases": list(CORPUS_INTERRUPTION_CASES),
            "recoveryCases": list(CORPUS_RECOVERY_CASES),
            "persistence": dict(CORPUS_PERSISTENCE),
            "claims": dict(CORPUS_CLAIMS),
        },
    }
    evidence = {
        **base,
        "receipt": "AdvancedRecurrenceWorkflowEvidenceReceiptV1",
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "scenarioEvidenceIDs": list(SELECTORS),
        "claims": dict(CORPUS_CLAIMS),
        "prohibitedClaims": ["native calendar", "native reminder", "hosted calendar", "hosted reminder", "provider adoption", "provider acceptance", "network", "account", "entitlement"],
        "golden": dict(CORPUS_GOLDEN),
        "alternate": dict(CORPUS_ALTERNATE),
        "hostileCases": list(CORPUS_HOSTILE_CASES),
        "interruptionCases": list(CORPUS_INTERRUPTION_CASES),
        "recoveryCases": list(CORPUS_RECOVERY_CASES),
        "persistence": dict(CORPUS_PERSISTENCE),
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
        "nativeCalendarClaim": False,
        "nativeReminderClaim": False,
        "hostedCalendarClaim": False,
        "hostedReminderClaim": False,
        "scheduleTruthOwner": "V23-P03-C51",
        "dueReminderTruthOwner": "V23-P04-C22",
        "reinspectionOwner": "V23-P04-C12",
        "customerDataPresent": False,
        "customerSecretsPresent": False,
        "networkOrServer": False,
        "cronOrRRULE": False,
        "backgroundExecution": False,
        "holidayDatabase": False,
        "secondRecurrenceEngine": False,
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
        "schema": "V23P04C38ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": base["authority"],
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in hashes.items()],
        "sourceRows": base["sourceRows"],
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "counts": {"fencePathCount": 14, "existingPathCount": 1, "newPathCount": 13, "productTestUIFixturePathCount": 5, "toolingPathCount": 8, "durableFamilyCount": 0, "modelDeltaCount": 0, "schemaDeltaCount": 0, "migrationCount": 0, "storeDeltaCount": 0, "writerDeltaCount": 0, "s10ReservationOverlapCount": 0},
        "lifecycle": base["lifecycle"],
        "independence": base["independence"],
    }
    return {SCHEMA: schema, CONTRACT: contract, EVIDENCE: evidence, BRAND: brand, MANIFEST: manifest}


def schema_document() -> dict[str, Any]:
    hash_def = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    source_row = {
        "type": "object",
        "required": ["path", "status", "sha256"],
        "properties": {"path": {"type": "string"}, "status": {"enum": ["SOURCE_PRESENT", "SOURCE_MISSING"]}, "sha256": {"type": ["string", "null"], "pattern": "^[0-9a-f]{64}$"}},
        "additionalProperties": False,
    }
    flags = {"type": "object", "required": list(FLAGS), "properties": {key: {"const": False} for key in FLAGS}, "additionalProperties": False}
    authority_properties: dict[str, Any] = {
        "cardID": {"const": CARD}, "attemptID": {"const": 1}, "registerOrdinal": {"const": ORDINAL}, "title": {"const": TITLE},
        "appBaseHead": {"const": BASE}, "appBaseTree": {"const": BASE_TREE}, "coordinationHead": {"const": COORDINATION_HEAD}, "coordinationTree": {"const": COORDINATION_TREE}, "sequence": {"const": SEQUENCE},
        "allocationDigest": {"const": ALLOCATION_DIGEST}, "prerequisiteDigest": {"const": PREREQUISITE_DIGEST}, "contextDigest": {"const": CONTEXT_DIGEST}, "pathFenceDigest": {"const": FENCE_DIGEST}, "transitionDigest": {"const": TRANSITION_DIGEST}, "ledgerDigest": {"const": LEDGER_DIGEST}, "projectionDigest": {"const": PROJECTION_DIGEST},
        "fencePathCount": {"const": 14}, "existingPathCount": {"const": 1}, "newPathCount": {"const": 13}, "productTestUIFixturePathCount": {"const": 5}, "toolingPathCount": {"const": 8}, "authorizedOverlapCount": {"const": 2}, "unauthorizedOverlapCount": {"const": 0}, "s10ReservationOverlapCount": {"const": 0}, "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST}, "orderedPathFence": {"type": "array", "const": list(PATH_FENCE)}, "existingPaths": {"type": "array", "const": list(EXISTING_PATHS)}, "newPaths": {"type": "array", "const": list(NEW)}, "hydrationRevision": {"const": HYDRATION_REVISION}, "correctionReceiptDigest": {"const": CORRECTION_RECEIPT_DIGEST}, "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3}, "finalHashesSealed": {"const": False},
    }
    lifecycle = {
        "type": "object",
        "required": ["status", "persistence", "canonicalPersistentSchema", "totalModelCount", "canonicalRows", "canonicalWriteOwners", "derivedOnly", "readOnlyOwners", "newDurableFamilyCount", "newModelCount", "newSchemaCount", "newMigrationCount", "newStoreCount", "newWriterCount"],
        "properties": {
            "status": {"const": "IMPLEMENT_NOW"}, "persistence": {"const": "PERSISTENT_OR_PRODUCT_DELTA"}, "canonicalPersistentSchema": {"const": "V53"}, "totalModelCount": {"const": 168},
            "canonicalRows": {"const": ["ScheduleDefinitionReleaseRow", "OccurrenceHistoryEventRow", "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow"]}, "canonicalWriteOwners": {"const": ["ScheduleMutationV1", "ScheduleCoordinatorV1", "WorkspaceWriterV1"]}, "derivedOnly": {"const": ["OccurrenceDueQueueStateV1", "LocalReminderReconciliationV1", "DueQueueProjectionV1", "ReminderProjectionV1"]}, "readOnlyOwners": {"const": ["V23-P03-C51", "V23-P04-C12", "V23-P04-C22"]},
            "newDurableFamilyCount": {"const": 0}, "newModelCount": {"const": 0}, "newSchemaCount": {"const": 0}, "newMigrationCount": {"const": 0}, "newStoreCount": {"const": 0}, "newWriterCount": {"const": 0},
        },
        "additionalProperties": False,
    }
    independence = {
        "type": "object",
        "required": ["scheduleExceptionOwner", "reinspectionOwner", "dueReminderOwner", "canonicalPersistentSchema", "totalModelCount", "newDurableFamily", "newModel", "newSchema", "newMigration", "newStore", "newWriter", "secondRecurrenceEngine", "cron", "rrule", "server", "calendarIntegration", "backgroundExecution", "holidayDatabase"],
        "properties": {
            "scheduleExceptionOwner": {"const": "V23-P03-C51"}, "reinspectionOwner": {"const": "V23-P04-C12"}, "dueReminderOwner": {"const": "V23-P04-C22"}, "canonicalPersistentSchema": {"const": "V53"}, "totalModelCount": {"const": 168},
            "newDurableFamily": {"const": False}, "newModel": {"const": False}, "newSchema": {"const": False}, "newMigration": {"const": False}, "newStore": {"const": False}, "newWriter": {"const": False}, "secondRecurrenceEngine": {"const": False}, "cron": {"const": False}, "rrule": {"const": False}, "server": {"const": False}, "calendarIntegration": {"const": False}, "backgroundExecution": {"const": False}, "holidayDatabase": {"const": False},
        },
        "additionalProperties": False,
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C38AdvancedRecurrenceWorkflowToolingV1",
        "type": "object",
        "required": ["schema", "cardID", "ordinal", "authority", "sourceRows", "sourceReady", "flags", "finalHashesSealed", "lifecycle", "independence"],
        "properties": {"schema": {"const": "V23P04C38AdvancedRecurrenceWorkflowToolingV1"}, "cardID": {"const": CARD}, "ordinal": {"const": ORDINAL}, "authority": {"$ref": "#/$defs/authority"}, "sourceRows": {"type": "array", "minItems": 5, "maxItems": 5, "items": {"$ref": "#/$defs/sourceRow"}}, "sourceReady": {"type": "boolean"}, "flags": {"$ref": "#/$defs/flags"}, "finalHashesSealed": {"const": False}, "lifecycle": {"$ref": "#/$defs/lifecycle"}, "independence": {"$ref": "#/$defs/independence"}, "contract": {"type": "string"}, "receipt": {"type": "string"}, "requirements": {"type": "object"}, "scenarioEvidenceIDs": {"type": "array", "const": list(SELECTORS)}},
        "additionalProperties": True,
        "$defs": {"sha256": hash_def, "sourceRow": source_row, "flags": flags, "authority": {"type": "object", "required": list(authority_properties), "properties": authority_properties, "additionalProperties": False}, "lifecycle": lifecycle, "independence": independence},
    }
