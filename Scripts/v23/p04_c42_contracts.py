#!/usr/bin/env python3
"""Deterministic authority and artifact definitions for V23-P04-C42.

The C42 tooling lane describes the manual Party/contact/Site-role workflow;
it is not a second Party store, contact writer, merge engine, router, or
network integration.  All generated artifacts remain provisional until the
product, tests, fixture, and UI lanes provide their own evidence.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C42"
ORDINAL = 130
TITLE = "Party, contact, and Site-role workflow"
BASE = "44a4f9d0e1480ff0675e38736e4d93211d12366e"
BASE_TREE = "b481c3c05fbf25ca3cb2567a7fee54034cf99e89"
COORDINATION_HEAD = "2341e165de38e686be54c424170988513986c70d"
COORDINATION_TREE = "abacf71fd74db6be2912c5121b5f37916a2ff4ba"
SEQUENCE = 568
ALLOCATION_DIGEST = "e013b151f497179ed10142abfe38592ac2bd4c35831ca7fe46a36b71716d8da9"
PREREQUISITE_DIGEST = "30a81ac38c212780b1fe63fb88647b611e71acde798ff189519e546719204278"
CONTEXT_DIGEST = "0a059f20e6696208a1acd705bf4380ac4c015d1c5cc85f6002fb7406020c2cdf"
FENCE_DIGEST = "c909f5a449fbec95e4ebaf23a913486112744df0743fc8efde5b67c90ed16af4"
TRANSITION_DIGEST = "81c20c5fc5d0aba596db961a3abd6ec6618fbd2af7d5cd1af8ee8a07c39f7eb0"
LEDGER_DIGEST = "03eac3a8266270f605f5f661b14727b8218ce55e4acdeb859d064a9d864b699b"
PROJECTION_DIGEST = "755967ed6542b392e8e6b46b0b386edcb814702bcddb08be1dbd5e71deb88433"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
TRANSITION_PATH = "transitions/000568-V23-P04-C42-attempt-1-NOT_STARTED-to-HYDRATING.json"
FINAL_HASHES_SEALED = False

# Compatibility aliases used by the other v23 tooling lanes.
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
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Application/Accountability/PartyAccountabilityCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Contacts/OperationalContactContractsV1.swift",
    "FieldEvidenceApp/Application/Contacts/OperationalContactCoordinatorV1.swift",
)
NEW_PRODUCT_PATHS = (
    "FieldEvidenceApp/Domain/Contacts/PartyContactSiteRoleWorkflowContractsV1.swift",
    "FieldEvidenceApp/Application/Contacts/PartyContactSiteRoleWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/Contacts/PartyContactSiteRoleWorkflowView.swift",
    "FieldEvidenceAppTests/V9_105PartyContactSiteRoleWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/Contacts/V23P04C42PartyContactSiteRoleWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C42PartyContactSiteRoleWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c42_contracts.py",
    "Scripts/v23/generate_p04_c42_contracts.py",
    "Scripts/v23/verify_p04_c42_contracts.py",
)
SCHEMA = "Scripts/v23/party-contact-site-role-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C42PartyContactSiteRoleWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C42PartyContactSiteRoleWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C42BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C42-tooling-manifest.json"
TOOLING_PATHS = (*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
NEW = (*NEW_PRODUCT_PATHS, *TOOLING_PATHS)
PATH_FENCE = (*EXISTING_PATHS, *NEW)
OWNED = frozenset(TOOLING_PATHS)
PRODUCT = (*EXISTING_PATHS, *NEW_PRODUCT_PATHS)
SOURCE_PATHS = PRODUCT
NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT = 6
NEW_TOOLING_DOCUMENTATION_PATH_COUNT = 8

DIRECT_PREREQUISITES = ["V23-P03-C46", "V23-P04-C16"]
AGGREGATE_MEMBERSHIPS = [
    "AutonomousRequiredAcceptedSetV1",
    "P04ShippingSurfaceSetV1",
    "P04BrandClosureSetV1",
    "ContactPurposeSeparationSetV1",
]
INVALIDATION_CONSUMERS = [
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
]
CONTRACT_REFS = [
    "ServicePartyReferenceV1",
    "SitePartyRoleEventV1",
    "ServiceContactPointV1",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
]
SELECTOR_ROWS = (
    ("G01", "V23-P04-C42-G01", "GOLDEN"),
    ("A01", "V23-P04-C42-A01", "ALTERNATE"),
    ("H01", "V23-P04-C42-H01", "HOSTILE"),
    ("I01", "V23-P04-C42-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C42-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)
SHORT_SELECTORS = tuple(row[0] for row in SELECTOR_ROWS)

PARTY_KINDS = ["PERSON", "ORGANIZATION"]
PARTY_STATES = ["EFFECTIVE", "RETIRED"]
CONTACT_KINDS = ["PHONE", "EMAIL"]
CONTACT_LIFECYCLE = ["EFFECTIVE", "RETIRED"]
SITE_ROLES = ["OWNER", "OPERATOR", "CLIENT", "SERVICE_PROVIDER", "CONTACT"]
GOLDEN = {
    "operations": ["CREATE_PARTY", "ADD_PHONE", "ADD_EMAIL", "SET_PREFERRED_PER_KIND", "APPEND_SITE_ROLE", "READ_HISTORY"],
    "canonicalEffectsPerAcceptedMutation": 1,
    "implicitCascadeEffects": 0,
}
ALTERNATE = {
    "partyOperations": ["RENAME", "EDIT_PROFILE", "RETIRE"],
    "contactOperations": ["EDIT", "RETIRE", "REACTIVATE", "CHANGE_PREFERRED_WITHIN_KIND"],
    "roleOperations": ["SUPERSEDE", "REVERSE"],
    "legacyCustomerPresentation": "SITE_ROLE_LABEL_ONLY",
}
HOSTILE_CASES = [
    "EQUAL_NAME_DISTINCT_PARTY_IDS",
    "EQUAL_PHONE_DISTINCT_CONTACT_IDS",
    "EQUAL_EMAIL_DISTINCT_CONTACT_IDS",
    "STALE_REVISION",
    "WRONG_WORKSPACE",
    "DIVERGENT_SAME_MUTATION_ID",
    "HIDDEN_CASCADE_ATTEMPT",
    "RETIRED_PARTY_REACTIVATION_ATTEMPT",
    "CONTACT_PURPOSE_CONFLATION",
]
INTERRUPTION_BOUNDARIES = ["BEFORE_EFFECT", "AFTER_EFFECT_BEFORE_RECEIPT", "AFTER_RECEIPT_BEFORE_RETURN"]
RECOVERY = {
    "entities": ["PARTY", "CONTACT_POINT", "SITE_ROLE_EVENT"],
    "exactReplayReturnsSameReceipt": True,
    "sameMutationDifferentBodyRejects": True,
    "historicalContactSnapshotsRemainFrozen": True,
    "partyRenameFansOutToHistoricalSnapshots": False,
    "preserveSiblingNamespaces": True,
}
CLAIMS = {
    "fuzzyMerge": False,
    "automaticDeduplication": False,
    "implicitContactCascade": False,
    "implicitRoleCascade": False,
    "partyReactivation": False,
    "marketingContactPurpose": False,
    "hostedDependency": False,
    "nativeBuildVerified": False,
}
CORPUS_SCHEMA = "V23P04C42PartyContactSiteRoleWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema", "schemaVersion", "cardID", "testOnly", "synthetic", "evidenceIDs", "selectors",
        "partyKinds", "partyStates", "contactKinds", "contactLifecycle", "siteRoles", "golden",
        "alternate", "hostileCases", "interruptionBoundaries", "recovery", "claims",
    )
)
SCENARIO_ROWS = (
    {
        "id": "G01", "kind": "GOLDEN", "evidenceID": "V23-P04-C42-G01",
        "focus": "DISTINCT_PARTY_CONTACT_UUIDS_CREATE_PREFERRED_CHANNEL_SITE_ROLE_HISTORY_AND_EXACT_ZERO_CASCADE_IMPACT",
        "expectedEffects": {"acceptedMutationEffects": 1, "implicitCascadeEffects": 0, "identityMerge": False, "history": "READ_ONLY"},
    },
    {
        "id": "A01", "kind": "ALTERNATE", "evidenceID": "V23-P04-C42-A01",
        "focus": "MANUAL_EDIT_PARTY_CONTACT_RETIRE_REACTIVATE_PREFERRED_KIND_AND_APPEND_ONLY_ROLE_REVERSAL",
        "expectedEffects": {"partyRetirement": "IRREVERSIBLE", "contactRetirement": "REVERSIBLE", "roleHistory": "APPEND_ONLY", "presentation": "SITE_ROLE_LABEL_ONLY"},
    },
    {
        "id": "H01", "kind": "HOSTILE", "evidenceID": "V23-P04-C42-H01",
        "focus": "EQUAL_VALUES_WARN_NOT_MERGE_STALE_WRONG_WORKSPACE_DIVERGENT_REPLAY_AND_PURPOSE_CONFLATION_FAIL_CLOSED",
        "expectedEffects": {"warnings": "NON_IDENTITY", "cascadeCount": 0, "invalidInput": "FAIL_CLOSED", "claims": "ALL_FALSE"},
    },
    {
        "id": "I01", "kind": "INTERRUPTION", "evidenceID": "V23-P04-C42-I01",
        "focus": "RECEIPT_FIRST_RECOVERY_AT_BEFORE_EFFECT_AFTER_EFFECT_BEFORE_RECEIPT_AND_AFTER_RECEIPT_BOUNDARIES",
        "expectedEffects": {"retry": "EXACT_REPLAY", "receipt": "SAME_RECEIPT", "partialEffect": "RECOVER_WITHOUT_DUPLICATE"},
    },
    {
        "id": "R01", "kind": "RECOVERY", "evidenceID": "V23-P04-C42-R01",
        "focus": "HISTORICAL_SNAPSHOTS_SIBLING_NAMESPACE_PRESERVATION_PARTY_RETIREMENT_AND_CONTACT_REACTIVATION",
        "expectedEffects": {"snapshots": "FROZEN", "namespace": "PRESERVED", "partyReactivation": False, "contactReactivation": True},
    },
)
FLAGS = {name: False for name in (
    "native", "hosted", "physicalDevice", "adoption", "acceptance", "release", "nativeAcceptance",
    "hostedAcceptance", "physicalEvidence", "adoptionEvidence", "acceptanceCredit", "releaseReadiness",
    "phase10PollingDuringParallelExecution",
)}

SOURCE_PINS = {
    "V23-P04-C42": (7038, "67c40603cb9339e728808f7a6b771b6f762207d0b6af53fa2ff5fc6b0fe11f81"),
    "V23-P04-C42-register": (313, "b890b9c2ff0888445e75488ff1401a51a37f497ba9ff22544886e123d4f4be8d"),
    "V23-P04-C42-acceptance-rows": (3370, "f5d71c55cbb989646c5f0a08d804b4a269f891f7db5fa88a7bab9f6bdec9c0d2"),
    "V23-P04-C42-lineage": (94, "1444baa626e38d8ba2df80d8bd828b40f68ea20cc6ce252c1dc6e0f526c2f2e3"),
}
SOURCE_PROJECTION = {
    "acceptedExpansionHead": BASE,
    "acceptedExpansionTree": BASE_TREE,
    "canonicalSuccessor": {"cardID": "V23-P04-C43", "registerOrdinal": 131},
    "dossierSlices": [
        {"byteCount": 7038, "startLine": 8541, "endLine": 8600, "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md", "sha256": SOURCE_PINS["V23-P04-C42"][1]},
        {"byteCount": 313, "startLine": 311, "endLine": 311, "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md", "sha256": SOURCE_PINS["V23-P04-C42-register"][1]},
        {"byteCount": 3370, "startLine": 1624, "endLine": 1634, "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md", "sha256": SOURCE_PINS["V23-P04-C42-acceptance-rows"][1]},
        {"byteCount": 94, "startLine": 3135, "endLine": 3135, "path": "C:\\Users\\palat\\OneDrive\\Desktop\\Asset Rounds Expansion Prompt\\EXPANSION_V23_FOUNDATION_PLAN.md", "sha256": SOURCE_PINS["V23-P04-C42-lineage"][1]},
    ],
    "outcome": "MANUAL_PARTY_CONTACT_SITE_ROLE_CREATE_EDIT_RETIRE_PREFERRED_CHANNEL_HISTORY_REVERSIBLE_ACTIONS_EXPECTED_REVISIONS_WARNINGS_NOT_IDENTITY_MERGES_EXACT_IMPACT_PREVIEWS_WITHOUT_HIDDEN_CASCADES_OR_HISTORICAL_REWRITE",
    "sourceAuthorityMode": "PINNED_BLUEPRINT_FOUNDATION_AND_READ_ONLY_ACCEPTED_APP_OWNER_INVENTORY",
}
PERSISTENCE_DECISION = {
    "autoCreateParty": False,
    "communicationOrMarketing": False,
    "contactsAccess": False,
    "contractProviderC38": {
        "acceptanceCredit": False, "attemptID": 1, "canonicalState": "CHECKPOINTED", "cardID": "V23-P04-C38",
        "checkpointDigest": "724e470c7bb47e27710ed69d6fc3ac2821e4205da66fcc23e3389186cd74da5e",
        "currentnessDisposition": "CURRENT_APP_BASE_DESCENDS_FROM_EFFECTIVE_PROVISIONAL_CANDIDATE",
        "semanticRole": "PARTY_SITE_ROLE_CONTRACT_PROVIDER_READ_ONLY",
        "verificationReceiptDigest": "9ba21034ab89d78b8e1e74ad5c9ddced800c505442bbd82f90cdb779344030e0",
    },
    "existingOperationalContactContractsOwner": EXISTING_PATHS[2],
    "existingOperationalContactCoordinatorOwner": EXISTING_PATHS[3],
    "existingPartyAccountabilityContractsOwner": EXISTING_PATHS[0],
    "existingPartyAccountabilityCoordinatorOwner": EXISTING_PATHS[1],
    "hiddenCascadeOrMerge": False,
    "historicalSnapshotRewrite": False,
    "identityInference": False,
    "newDurableFamilyCount": 0,
    "newMigrationCount": 0,
    "newModelCount": 0,
    "newSchemaCount": 0,
    "newStoreCount": 0,
    "newWriterCount": 0,
    "rootOrNetworkOrTelemetry": False,
}
DIRECT_PREREQUISITE_PROOF = {
    "allAcceptanceCreditFalse": True, "duplicateCount": 0, "expectedDirectEdgeCount": 2,
    "failedIntermediateAcceptanceCount": 0, "incompatibleCount": 0, "missingCount": 0,
    "observedDirectEdgeCount": 2, "orphanCount": 0, "staleCount": 0, "uniqueCardCount": 2,
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
    value = os.environ.get("V23_P04_C42_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _line_slice(raw: bytes, start: int, end: int) -> bytes:
    lines = raw.splitlines(keepends=True)
    return b"".join(lines[start - 1:end])


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C42 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    values = (
        ("V23-P04-C42", _line_slice(blueprint, 8541, 8600)),
        ("V23-P04-C42-register", _line_slice(foundation, 311, 311)),
        ("V23-P04-C42-acceptance-rows", _line_slice(foundation, 1624, 1634)),
        ("V23-P04-C42-lineage", _line_slice(foundation, 3135, 3135)),
    )
    result: list[dict[str, Any]] = []
    for anchor, value in values:
        expected_length, expected_sha = SOURCE_PINS[anchor]
        actual = (len(value), sha(value))
        if actual != (expected_length, expected_sha):
            raise ValueError(f"source pin drift: {anchor} expected={(expected_length, expected_sha)} actual={actual}")
        result.append({"anchor": anchor, "utf8Length": actual[0], "sha256": actual[1]})
    return result


def _require(value: Any, expected: Any, label: str) -> None:
    if value != expected:
        raise ValueError(f"{label} drift")


def _false_keys(document: dict[str, Any]) -> None:
    for key in (
        "acceptanceCredit", "acceptanceEnabled", "adoptionEnabled", "hostedDispatchEnabled", "hostedDispatchRan",
        "nativeCompileRan", "phase10PollingDuringParallelExecution", "physicalDeviceEnabled", "publicationEnabled",
        "releaseCredit", "releaseReady",
    ):
        _require(document.get(key), False, key)


def _coordination_evidence(root: Path) -> None:
    _require(git("rev-parse", "HEAD", cwd=root), COORDINATION_HEAD, "coordination HEAD")
    _require(git("show", "-s", "--format=%T", COORDINATION_HEAD, cwd=root), COORDINATION_TREE, "coordination tree")
    context = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json")
    fence = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    transition = read_json(root / TRANSITION_PATH)
    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    projection = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    blockers = ["DIRECT_RECEIPTS_PROVISIONAL_ZERO_ACCEPTANCE_CREDIT", "ACCEPTED_S10_6_RECONCILIATION_PENDING", "NATIVE_COMPILE_UNIT_UI_RECOVERY_AND_HOSTED_RUNS_NOT_RUN"]
    _require((context.get("cardID"), context.get("attemptID"), context.get("registerOrdinal")), (CARD, 1, ORDINAL), "context identity")
    for key, expected in {"title": TITLE, "classification": "IMPLEMENT_NOW", "contextDigest": CONTEXT_DIGEST, "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "repository": {"appBaseHead": BASE, "appBaseTree": BASE_TREE}, "acceptanceBlockers": blockers, "planningStatus": "NOT_STARTED", "lineage": {"disposition": "ADDED_V23"}, "directPrerequisites": DIRECT_PREREQUISITES, "directPrerequisiteProof": DIRECT_PREREQUISITE_PROOF, "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW), "expectedArtifacts": list(PATH_FENCE), "persistenceDecision": PERSISTENCE_DECISION, "sourceProjection": SOURCE_PROJECTION, "requiresAcceptedS10_6Reconciliation": True}.items():
        _require(context.get(key), expected, f"context {key}")
    _false_keys(context)
    for key, expected in {"cardID": CARD, "attemptID": 1, "baseHead": BASE, "baseTree": BASE_TREE, "fenceDigest": FENCE_DIGEST, "allowedCreateOrReplacePaths": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW), "allowedDeletePaths": [], "allowedRenamePaths": [], "frozenS10ReservationDigest": FROZEN_S10_DIGEST}.items():
        _require(fence.get(key), expected, f"fence {key}")
    _false_keys(fence)
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C42 path overlaps S10 reservation")
    prior = fence.get("priorFenceProof", {})
    for key, expected in {"authorizationBasis": "C46_PARTY_ACCOUNTABILITY_AND_C16_OPERATIONAL_CONTACT_CANONICAL_OWNER_SEAMS_WITH_C38_PARTY_SITE_ROLE_CONTRACT_PROVIDER_READ_ONLY", "authorizedOverlapEdgeCount": 3, "fenceCount": 132, "inheritedExistingPathEnvelopeOverlapCount": 35, "overlapEdgeCount": 38, "priorFenceSetDigest": "de0f94e0bacdd42256531a76511cc55c4ce5d39a16835e821aa1670cda1da39a", "priorOwnedPathCount": 4, "s10ReservedOverlapCount": 0, "unauthorizedOverlapCount": 0}.items():
        _require(prior.get(key), expected, f"prior fence {key}")
    for key, expected in {"cardID": CARD, "allocationDigest": ALLOCATION_DIGEST, "exactOrderedPaths": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW), "newProductTestUIFixturePathCount": 6, "newToolingDocumentationPathCount": 8, "s10ReservedOverlapCount": 0, "persistenceDecision": PERSISTENCE_DECISION, "sourceProjection": SOURCE_PROJECTION}.items():
        _require(allocation.get(key), expected, f"allocation {key}")
    _false_keys(allocation)
    for key, expected in {"prerequisiteDigest": PREREQUISITE_DIGEST, "successorCardID": CARD, "canonicalDirectPrerequisiteCardIDs": DIRECT_PREREQUISITES, "ordinaryDirectEdgeCount": 2, "directPrerequisiteProof": DIRECT_PREREQUISITE_PROOF, "acceptanceCredit": False, "immediateSequentialPredecessor": {"candidateHead": BASE, "candidateTree": BASE_TREE, "cardID": "V23-P04-C41", "checkpointDigest": "12ecc6c943dc3dbe46764a52f41fca2c8922ceb05cf73777c75550a79387d02c", "verificationReceiptDigest": "6f02beb5225c0b02520ad6ab8a54d36d9585345c6959aadb3497299b173c37ae"}}.items():
        _require(prerequisite.get(key), expected, f"prerequisite {key}")
    _false_keys(prerequisite)
    for key, expected in {"schema": "BootstrapStateTransitionV1", "attemptID": 1, "candidateHead": BASE, "candidateTree": BASE_TREE, "cardID": CARD, "contextDigest": CONTEXT_DIGEST, "fromState": "NOT_STARTED", "toState": "HYDRATING", "newLedgerDigest": LEDGER_DIGEST, "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "sequence": SEQUENCE, "transitionDigest": TRANSITION_DIGEST, "directPrerequisiteCheckpointDigests": ["898f51f4398c0971a279c4e28f8de302d227e318caeb15c0bb68f51f848ef15b", "3738094484c1ea8c898fe1b114d8cccb00b8b5f503f226194a4d4f40668b841e"]}.items():
        _require(transition.get(key), expected, f"transition {key}")
    _require(ledger.get("casSequence"), SEQUENCE, "ledger sequence")
    _require(ledger.get("ledgerDigest"), LEDGER_DIGEST, "ledger digest")
    active = next((entry for entry in ledger.get("attempts", []) if entry.get("cardID") == CARD), None)
    _require(bool(active), True, "ledger C42 attempt")
    if active:
        for key, expected in {"attemptID": 1, "cardID": CARD, "ordinal": ORDINAL, "classification": "IMPLEMENT_NOW", "candidateHead": BASE, "candidateTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST, "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "directPrerequisites": DIRECT_PREREQUISITES, "planningStatus": "NOT_STARTED", "state": "HYDRATING", "identityInference": False, "hiddenCascadeOrMerge": False, "newDurableFamilyCount": 0}.items():
            _require(active.get(key), expected, f"ledger {key}")
    _require(projection.get("ledgerDigest"), LEDGER_DIGEST, "projection ledger")
    _require(projection.get("projectionDigest"), PROJECTION_DIGEST, "projection digest")
    _require((projection.get("nextEligibleCardID"), projection.get("nextEligibleRegisterOrdinal")), (None, None), "projection next eligible")
    projected = next((entry for entry in projection.get("activeEntries", []) if entry.get("cardID") == CARD), None)
    _require(bool(projected), True, "projection C42 attempt")
    if projected:
        for key, expected in {"attemptID": 1, "cardID": CARD, "ordinal": ORDINAL, "candidateHead": BASE, "candidateTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "state": "HYDRATING", "stateReason": "P04_C42_MANUAL_PARTY_CONTACT_SITE_ROLE_WORKFLOW_WITH_EXACT_PREVIEWS_AND_REVERSIBLE_ACTIONS_HYDRATING"}.items():
            _require(projected.get(key), expected, f"projection {key}")


def authority() -> dict[str, Any]:
    source_pins = _source_slices()
    result = {"cardID": CARD, "attemptID": 1, "registerOrdinal": ORDINAL, "title": TITLE, "appBaseHead": BASE, "appBaseTree": BASE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE, "sequence": SEQUENCE, "allocationDigest": ALLOCATION_DIGEST, "prerequisiteDigest": PREREQUISITE_DIGEST, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "transitionDigest": TRANSITION_DIGEST, "ledgerDigest": LEDGER_DIGEST, "projectionDigest": PROJECTION_DIGEST, "fencePathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW), "productTestUIFixturePathCount": NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT, "toolingPathCount": NEW_TOOLING_DOCUMENTATION_PATH_COUNT, "authorizedOverlapCount": 3, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0, "frozenS10ReservationDigest": FROZEN_S10_DIGEST, "orderedPathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW), "sourcePins": source_pins, "finalHashesSealed": FINAL_HASHES_SEALED}
    coordination = _coordination_root()
    if coordination is None or not coordination.is_dir():
        if not (ROOT / MANIFEST).is_file():
            raise ValueError("coordination authority unavailable and no portable manifest")
        _require(read_json(ROOT / MANIFEST).get("authority"), result, "portable authority")
    else:
        _coordination_evidence(coordination)
    return result


def rows() -> tuple[list[dict[str, Any]], bool]:
    result = []
    for path in SOURCE_PATHS:
        target = ROOT / path
        result.append({"path": path, "status": "SOURCE_PRESENT" if target.is_file() else "SOURCE_MISSING", "sha256": sha(target.read_bytes()) if target.is_file() else None})
    return result, all(row["status"] == "SOURCE_PRESENT" for row in result)


def counts() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in git(*args).splitlines() if line}
    changed = names("diff", "--name-only", BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard")
    return {"changedPathCount": len(changed & set(PATH_FENCE)), "unownedChangedPathCount": len(changed - set(PATH_FENCE)), "missingPathCount": sum(not (ROOT / p).is_file() for p in PATH_FENCE), "fencePathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW), "productTestUIFixturePathCount": NEW_PRODUCT_TEST_UI_FIXTURE_PATH_COUNT, "toolingPathCount": NEW_TOOLING_DOCUMENTATION_PATH_COUNT, "s10ReservationOverlapCount": 0, "durableFamilyCount": 0, "modelDeltaCount": 0, "schemaDeltaCount": 0, "migrationCount": 0, "storeDeltaCount": 0, "writerDeltaCount": 0, "rendererDeltaCount": 0, "backendDeltaCount": 0}


def _base_document() -> dict[str, Any]:
    auth = authority()
    source_rows, source_ready = rows()
    lifecycle = {"status": "IMPLEMENT_NOW", "policyProfile": "NONPERSISTENT_OR_EXISTING_OWNER_DELTA", "persistence": "EXISTING_PARTY_CONTACT_SITE_ROLE_OWNERS", "persistentSchemaVersion": "UNCHANGED_EXISTING_OWNER", "recordsSchemaVersion": "UNCHANGED_EXISTING_OWNER", "durableFamily": "NONE", "impactPreview": "EXACT_ZERO_CASCADE", "impactPreviewZeroWrite": True, "historicalSnapshots": "FROZEN", "siteRoleHistory": "APPEND_ONLY", "partyRetirement": "IRREVERSIBLE", "contactRetirement": "REVERSIBLE", "preferredScope": "PARTY_AND_CONTACT_KIND", "receiptRecovery": "RECEIPT_FIRST", "newDurableFamilyCount": 0, "newModelCount": 0, "newSchemaCount": 0, "newMigrationCount": 0, "newStoreCount": 0, "newWriterCount": 0, "newRendererCount": 0, "newBackendCount": 0}
    independence = {"distinctUUIDIdentity": True, "warningsAreNotMerges": True, "exactImpactAndCascadeZero": True, "partyRetirementIrreversible": True, "contactRetirementReversible": True, "preferredPerPartyAndKind": True, "roleHistoryAppendOnly": True, "receiptFirstRecovery": True, "historicalSnapshotsFrozen": True, "autoPartyCreation": False, "contactsAccess": False, "purposeConflation": False, "newModel": False, "newSchema": False, "newStore": False, "newWriter": False, "newMigration": False, "newRoot": False, "newNetwork": False, "newTelemetry": False, "claimsFabricated": False, "customerDataInTooling": False, "secretsInTooling": False}
    return {"schema": "V23P04C42PartyContactSiteRoleWorkflowToolingV1", "cardID": CARD, "ordinal": ORDINAL, "authority": auth, "sourceRows": source_rows, "sourceReady": source_ready, "flags": dict(FLAGS), "finalHashesSealed": FINAL_HASHES_SEALED, "lifecycle": lifecycle, "independence": independence}


def _requirements() -> dict[str, Any]:
    return {"distinctUUIDIdentity": True, "equalValuesWarnOnly": True, "warningsDoNotMerge": True, "exactImpactPreview": True, "cascadeCount": 0, "identityMergeCount": 0, "zeroWritePreview": True, "partyRetirementIrreversible": True, "contactRetirementReversible": True, "preferredPerPartyAndKind": True, "roleReversalAppendOnly": True, "historicalSnapshotsFrozen": True, "receiptFirstRecovery": True, "explicitExpectedRevisions": True, "manualPartyAndContactActions": True, "noAutoPartyCreation": True, "noContactsAccess": True, "noPurposeConflation": True, "noNewModel": True, "noNewSchemaFamily": True, "noNewStore": True, "noNewWriter": True, "noNewMigration": True, "noNewRoot": True, "noNetwork": True, "noTelemetry": True, "noBackend": True, "fiveEvidenceScenarios": True, "scenarioSelectors": list(SELECTORS), "finalHashesUnsealed": True, **{key: value for key, value in CLAIMS.items()}}


def _corpus_expectations() -> dict[str, Any]:
    return {"schema": CORPUS_SCHEMA, "schemaVersion": 1, "cardID": CARD, "testOnly": True, "synthetic": True, "evidenceIDs": list(SELECTORS), "selectors": list(SHORT_SELECTORS), "partyKinds": list(PARTY_KINDS), "partyStates": list(PARTY_STATES), "contactKinds": list(CONTACT_KINDS), "contactLifecycle": list(CONTACT_LIFECYCLE), "siteRoles": list(SITE_ROLES), "golden": dict(GOLDEN), "alternate": dict(ALTERNATE), "hostileCases": list(HOSTILE_CASES), "interruptionBoundaries": list(INTERRUPTION_BOUNDARIES), "recovery": dict(RECOVERY), "claims": dict(CLAIMS)}


def documents() -> dict[str, Any]:
    base = _base_document()
    corpus = _corpus_expectations()
    contract = {**base, "contract": "PartyContactSiteRoleWorkflowContractV1", "journeyRefs": ["FJ02"], "directPrerequisites": list(DIRECT_PREREQUISITES), "aggregateMemberships": list(AGGREGATE_MEMBERSHIPS), "invalidationConsumers": list(INVALIDATION_CONSUMERS), "optionalCapabilityProviders": [], "contractRefs": list(CONTRACT_REFS), "requirements": _requirements(), "scenarioEvidenceIDs": list(SELECTORS), "scenarioRows": list(SCENARIO_ROWS), "corpusExpectations": corpus, "partyKinds": list(PARTY_KINDS), "partyStates": list(PARTY_STATES), "contactKinds": list(CONTACT_KINDS), "contactLifecycle": list(CONTACT_LIFECYCLE), "siteRoles": list(SITE_ROLES), "golden": dict(GOLDEN), "alternate": dict(ALTERNATE), "hostileCases": list(HOSTILE_CASES), "interruptionBoundaries": list(INTERRUPTION_BOUNDARIES), "recovery": dict(RECOVERY), "claims": dict(CLAIMS), "outcome": SOURCE_PROJECTION["outcome"]}
    evidence = {**base, "receipt": "PartyContactSiteRoleWorkflowEvidenceReceiptV1", "receiptState": "PROVISIONAL_STATIC_TOOLING", "acceptanceCredit": False, "scenarioEvidenceIDs": list(SELECTORS), "scenarioRows": list(SCENARIO_ROWS), "corpusSchema": CORPUS_SCHEMA, "corpusExpectations": corpus, "claims": dict(CLAIMS), "prohibitedClaims": ["fuzzy or automatic identity merge", "implicit contact or role cascade", "party reactivation", "marketing or communications contact purpose", "contacts permission/access", "network, telemetry, hosted, native, adoption, acceptance, or release evidence"], "sourceSlices": list(SOURCE_PROJECTION["dossierSlices"]), "zeroWriteImpactPreview": True, "receiptFirstRecovery": True, "finalHashesSealed": False}
    brand = {"schema": "BrandImpactManifestV1", "cardID": CARD, "ordinal": ORDINAL, "flags": dict(FLAGS), "finalHashesSealed": False, "requiresAcceptedS10_6Reconciliation": True, "uiAdoptionSkipped": True, "uiAcceptanceCredit": False, "nativeOrHostedAdoption": False, "manualActionsTruthful": True, "warningsNotIdentityMerges": True, "exactCascadeCount": 0, "partyRetirementIrreversible": True, "contactRetirementReversible": True, "roleHistoryAppendOnly": True, "historicalSnapshotsFrozen": True, "purposeConflation": False, "networkOrTelemetry": False, "newRootStoreWriterRenderer": False, "newModelSchemaMigration": False, "customerDataPresent": False, "customerSecretsPresent": False, "durableDelta": False}
    schema = schema_document()
    artifact_hashes = {SCHEMA: sha(pretty(schema)), CONTRACT: sha(pretty(contract)), EVIDENCE: sha(pretty(evidence)), BRAND: sha(pretty(brand))}
    manifest = {"schema": "V23P04C42ToolingManifestV1", "cardID": CARD, "ordinal": ORDINAL, "authority": base["authority"], "pathFence": list(PATH_FENCE), "files": [{"path": p, "sha256": d} for p, d in artifact_hashes.items()], "sourceRows": base["sourceRows"], "flags": dict(FLAGS), "finalHashesSealed": False, "counts": {"fencePathCount": 18, "existingPathCount": 4, "newPathCount": 14, "productTestUIFixturePathCount": 6, "toolingPathCount": 8, "durableFamilyCount": 0, "modelDeltaCount": 0, "schemaDeltaCount": 0, "migrationCount": 0, "storeDeltaCount": 0, "writerDeltaCount": 0, "rendererDeltaCount": 0, "backendDeltaCount": 0, "s10ReservationOverlapCount": 0}, "lifecycle": base["lifecycle"], "independence": base["independence"], "directPrerequisites": list(DIRECT_PREREQUISITES), "successor": {"cardID": "V23-P04-C43", "registerOrdinal": 131}, "optionalProvider": "NONE", "scenarioEvidenceIDs": list(SELECTORS)}
    return {SCHEMA: schema, CONTRACT: contract, EVIDENCE: evidence, BRAND: brand, MANIFEST: manifest}


def schema_document() -> dict[str, Any]:
    authority_properties = {"cardID": {"const": CARD}, "attemptID": {"const": 1}, "registerOrdinal": {"const": ORDINAL}, "title": {"const": TITLE}, "appBaseHead": {"const": BASE}, "appBaseTree": {"const": BASE_TREE}, "coordinationHead": {"const": COORDINATION_HEAD}, "coordinationTree": {"const": COORDINATION_TREE}, "sequence": {"const": SEQUENCE}, "allocationDigest": {"const": ALLOCATION_DIGEST}, "prerequisiteDigest": {"const": PREREQUISITE_DIGEST}, "contextDigest": {"const": CONTEXT_DIGEST}, "pathFenceDigest": {"const": FENCE_DIGEST}, "transitionDigest": {"const": TRANSITION_DIGEST}, "ledgerDigest": {"const": LEDGER_DIGEST}, "projectionDigest": {"const": PROJECTION_DIGEST}, "fencePathCount": {"const": 18}, "existingPathCount": {"const": 4}, "newPathCount": {"const": 14}, "productTestUIFixturePathCount": {"const": 6}, "toolingPathCount": {"const": 8}, "authorizedOverlapCount": {"const": 3}, "unauthorizedOverlapCount": {"const": 0}, "s10ReservationOverlapCount": {"const": 0}, "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST}, "orderedPathFence": {"const": list(PATH_FENCE)}, "existingPaths": {"const": list(EXISTING_PATHS)}, "newPaths": {"const": list(NEW)}, "finalHashesSealed": {"const": False}}
    flags = {"type": "object", "required": list(FLAGS), "properties": {key: {"const": False} for key in FLAGS}, "additionalProperties": False}
    source_row = {"type": "object", "required": ["path", "status", "sha256"], "properties": {"path": {"type": "string"}, "status": {"enum": ["SOURCE_PRESENT", "SOURCE_MISSING"]}, "sha256": {"type": ["string", "null"]}}, "additionalProperties": False}
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "title": "V23P04C42PartyContactSiteRoleWorkflowToolingV1", "type": "object", "required": ["schema", "cardID", "ordinal", "authority", "sourceRows", "sourceReady", "flags", "finalHashesSealed", "lifecycle", "independence"], "properties": {"schema": {"const": "V23P04C42PartyContactSiteRoleWorkflowToolingV1"}, "cardID": {"const": CARD}, "ordinal": {"const": ORDINAL}, "authority": {"type": "object", "required": list(authority_properties), "properties": authority_properties, "additionalProperties": False}, "sourceRows": {"type": "array", "items": {"$ref": "#/$defs/sourceRow"}}, "sourceReady": {"type": "boolean"}, "flags": {"$ref": "#/$defs/flags"}, "finalHashesSealed": {"const": False}, "lifecycle": {"type": "object"}, "independence": {"type": "object"}}, "additionalProperties": True, "$defs": {"sourceRow": source_row, "flags": flags}}


if __name__ == "__main__":
    print(json.dumps(authority(), sort_keys=True, indent=2))
