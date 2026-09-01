#!/usr/bin/env python3
"""Pinned deterministic tooling contracts for V23-P04-C37.

The C37 lane is an evidence-selected incumbent flat-file adapter workflow.  It
is deliberately disabled until an exact production profile is selected.  The
tooling describes the closed typed seam around the existing C50 adapter and
C08 import engine; it does not create a provider, network, credential, store,
writer, or persistent model.
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
CARD = "V23-P04-C37"
ORDINAL = 122
TITLE = "Evidence-selected first incumbent flat-file adapter with dry-run mapping and deterministic exchange"
BASE = "2576e34fd399fa9800f696a82cc945ad8fa3b2d9"
BASE_TREE = "2687b0f59764f9fc8836e643768df8b2d6dac66b"
COORDINATION_HEAD = "f0f3c599e3ec851e1f8b34a6bce808c2c192554c"
COORDINATION_TREE = "5b7a0e436be6bbe88802f21465cae8dbf63319f3"
SEQUENCE = 546
ALLOCATION_DIGEST = "6f10fa9ffd35e180f8780ed9623fc77904a921f45626d28d8d141b4f11e12663"
PREREQUISITE_DIGEST = "fe9c955636d805f0c2fe1f235156e70725a1e3d0c2d398f947f46b5d53780734"
CONTEXT_DIGEST = "4f73c1c6b4009340df653eb0a4c61d50ebf764cc0f30008bdc33dd1c8e8da9dd"
FENCE_DIGEST = "e273fb7e28d72993006a3bcae1478fb8d38523b4dc3a1a9826bcd2d31bb5e972"
TRANSITION_DIGEST = "c15a5d798078bc59952c0cba8ded6710c7171a266fa60ee2289be5600d21ac17"
LEDGER_DIGEST = "3ab274727f36594fb651d9c61e61d39a0ce8e91cebf356509364c764ec74dcf5"
PROJECTION_DIGEST = "bfddef3867d94bd22d11aba022806ac9303072cb00569b68cd13f190bc0cc215"
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

PRODUCT = (
    "FieldEvidenceApp/Application/Integrations/IncumbentFileAdapterWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/Integrations/IncumbentFileAdapterWorkflowView.swift",
    "FieldEvidenceAppTests/V9_100IncumbentFileAdapterWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/IncumbentExchange/V23P04C37IncumbentFileAdapterWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C37IncumbentFileAdapterWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c37_contracts.py",
    "Scripts/v23/generate_p04_c37_contracts.py",
    "Scripts/v23/verify_p04_c37_contracts.py",
)
SCHEMA = "Scripts/v23/incumbent-file-adapter-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C37IncumbentFileAdapterWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C37IncumbentFileAdapterWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C37BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C37-tooling-manifest.json"
NEW = (*PRODUCT, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
PATH_FENCE = NEW
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = PRODUCT

SELECTOR_ROWS = (
    ("G01", "V23-P04-C37-G01", "GOLDEN"),
    ("A01", "V23-P04-C37-A01", "ALTERNATE"),
    ("H01", "V23-P04-C37-H01", "HOSTILE"),
    ("I01", "V23-P04-C37-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C37-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "evidenceID": "V23-P04-C37-G01",
        "focus": "DISABLED_NO_SELECTED_PROFILE_ZERO_ACTIONS_AND_CLAIMS",
        "expectedEffects": {"productionFileAction": 0, "canonicalWrite": 0, "selectedProfileCount": 0},
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "evidenceID": "V23-P04-C37-A01",
        "focus": "IN_MEMORY_EXACT_PROFILE_DETERMINISTIC_PREVIEW_AND_EXPORT",
        "expectedEffects": {"productionSelection": False, "previewZeroWrite": True, "deterministicExport": True},
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "evidenceID": "V23-P04-C37-H01",
        "focus": "INVALID_FILE_RELEASE_SELECTION_MAPPING_AND_PRIVACY_INPUTS",
        "expectedEffects": {"rejectedEffects": 0},
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "evidenceID": "V23-P04-C37-I01",
        "focus": "EFFECT_BEFORE_RECEIPT_AND_SCRATCH_RECOVERY_WITHOUT_REIMPORT",
        "expectedEffects": {"canonicalEffects": [0, 1], "lostCallback": "UNKNOWN"},
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "evidenceID": "V23-P04-C37-R01",
        "focus": "EXACT_REPLAY_DIVERGENT_SOURCE_QUARANTINE_AND_CLEANUP",
        "expectedEffects": {"replayEffects": 1, "quarantineEffects": 0},
    },
)

CORPUS_SCHEMA = "V23P04C37IncumbentFileAdapterWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema",
        "schemaVersion",
        "cardID",
        "corpusID",
        "testOnly",
        "synthetic",
        "containsCustomerData",
        "containsSecrets",
        "evidenceIDs",
        "production",
        "syntheticAuthority",
        "hostileCases",
        "recoveryCases",
        "claims",
    )
)
CORPUS_PRODUCTION = {
    "status": "DISABLED_NO_SELECTED_PROFILE",
    "selectedProfileCount": 0,
    "fileActionCount": 0,
    "canonicalWriteCount": 0,
    "providerName": None,
    "providerSuccessClaim": False,
}
CORPUS_SYNTHETIC_AUTHORITY = {
    "selectedProfileCount": 1,
    "representation": "IN_MEMORY_SELECTED_PROFILE_SIMULATION",
    "shippedProductionSelectedProfileCount": 0,
    "deterministicPreview": True,
    "deterministicExport": True,
}
CORPUS_HOSTILE_CASES = [
    "UNKNOWN_VERSION",
    "NEWER_VERSION",
    "NON_UTF8_ENCODING",
    "FORMULA_PREFIX",
    "NON_NFC_UNICODE",
    "BYTE_LIMIT",
    "ROW_LIMIT",
    "COLUMN_LIMIT",
    "SCALAR_LIMIT",
    "PATH_TRAVERSAL_FILENAME",
    "ARCHIVE_LIKE_INPUT",
    "MISSING_STABLE_KEY",
    "AMBIGUOUS_STABLE_KEY",
    "MULTIPLE_SELECTIONS",
    "STALE_SELECTION",
]
CORPUS_RECOVERY_CASES = [
    "CANCEL_BEFORE_EFFECT",
    "KILL_BEFORE_EFFECT",
    "EFFECT_BEFORE_RECEIPT",
    "EXACT_RETRY_ONE_CANONICAL_EFFECT",
    "DIVERGENT_MUTATION_REJECTED",
    "DIVERGENT_SOURCE_REJECTED",
    "DIVERGENT_MAPPING_REJECTED",
    "DIVERGENT_FRONTIER_REJECTED",
    "SCRATCH_CLEANUP_IDEMPOTENT",
]
CORPUS_CLAIMS = {
    "fileCreatedMeansSynced": False,
    "fileCreatedMeansDelivered": False,
    "fileCreatedMeansProviderAccepted": False,
    "providerSDK": False,
    "networkEndpoint": False,
    "credentials": False,
    "securityClaim": False,
    "identityClaim": False,
    "legalClaim": False,
            "shippedProductionProfileSelected": False,
    "previewWritesCanonicalData": False,
    "automaticImport": False,
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
    "V23-P04-C37": (7376, "51c0ec0ab817454e36d99cd306ceb9e021c2a0ba744f890943792a2e7f976ad7"),
    "V21-P04-C37": (4011, "9d547f4219c6e4e8ffc62ad6bb2fd18f8f82e3f0d9ec15ef8a07dafa327e4996"),
    "V23-P04-C37-register": (327, "c29ca85c4862586a5e4997f07fda7282962d2fa684264da2a1d5edb2903f540b"),
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
    value = os.environ.get("V23_P04_C37_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C37 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")

    def block(card: str, indent: bytes) -> bytes:
        pattern = rb"(?ms)^" + re.escape(indent) + rb"### " + re.escape(card.encode()) + rb" .*?(?=^" + re.escape(indent) + rb"### |\Z)"
        match = re.search(pattern, blueprint)
        if match is None:
            raise ValueError(f"missing pinned source block: {card}")
        return match.group(0)

    marker = b'<a id="v23-p04-c37-register"></a>'
    register_lines = [line for line in foundation.splitlines(keepends=True) if marker in line]
    if len(register_lines) != 1:
        raise ValueError("missing or ambiguous pinned C37 register row")
    values = {
        "V23-P04-C37": block("V23-P04-C37", b""),
        "V21-P04-C37": block("V21-P04-C37", b"    "),
        "V23-P04-C37-register": register_lines[0],
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
        "DISABLED_NO_SELECTED_PROFILE_SELECTED_PROFILE_COUNT_ZERO",
        "ACCEPTED_S10_6_RECONCILIATION_PENDING",
        "NATIVE_COMPILE_UNIT_UI_AND_RECOVERY_RUNS_NOT_RUN",
    ]
    if context.get("cardID") != CARD or context.get("registerOrdinal") != ORDINAL:
        raise ValueError("coordination context identity drift")
    if context.get("contextDigest") != CONTEXT_DIGEST or context.get("ownerAuthorizedPathAllocationDigest") != ALLOCATION_DIGEST or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("coordination context digest drift")
    if context.get("repository") != {"appBaseHead": BASE, "appBaseTree": BASE_TREE}:
        raise ValueError("coordination context app base drift")
    if context.get("acceptanceBlockers") != blockers or context.get("acceptanceCredit") is not False or context.get("acceptanceEnabled") is not False or context.get("adoptionEnabled") is not False:
        raise ValueError("C37 acceptance boundary drift")
    if tuple(context.get("existingPaths", ())) != () or tuple(context.get("newPaths", ())) != NEW or tuple(context.get("expectedArtifacts", ())) != NEW:
        raise ValueError("coordination context path fence drift")
    direct = ["V23-P03-C50", "V23-P04-C08", "V23-P04-C16"]
    proof = {"allAcceptanceCreditFalse": True, "duplicateCount": 0, "expectedDirectEdgeCount": 3, "failedIntermediateAcceptanceCount": 0, "incompatibleCount": 0, "missingCount": 0, "observedDirectEdgeCount": 3, "orphanCount": 0, "staleCount": 0, "uniqueCardCount": 3}
    if context.get("directPrerequisites") != direct or context.get("directPrerequisiteProof") != proof:
        raise ValueError("C37 direct prerequisite proof drift")
    persistence = {
        "futureReentry": "CLOSED_TYPED_REENTRY_ONLY",
        "newDurableFamilyCount": 0,
        "newMigrationCount": 0,
        "newModelCount": 0,
        "newSchemaCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "readOnlyOwners": direct,
        "selectedProfileCount": 0,
        "selectedProfileDisposition": "DISABLED_NO_SELECTED_PROFILE",
    }
    if context.get("persistenceDecision") != persistence:
        raise ValueError("C37 persistence decision drift")
    consumption = {
        "adapterExchangeOwner": "IncumbentFileExchangeCoordinatorV1",
        "adapterPortOwner": "V23-P03-C50",
        "futureReentry": "CLOSED_TYPED_REENTRY_REQUIRES_EXACT_PROFILE_SELECTION_AND_NEW_MAPPING_PREVIEW",
        "importEngineOwner": "V23-P04-C08",
        "prohibition": "NO_VENDOR_LICENSE_TRADEMARK_EVIDENCE_NO_SDK_NETWORK_CREDENTIAL_STORE_WRITER_MODEL_SCHEMA_OR_DURABLE_FAMILY",
        "selectedProfileCount": 0,
        "selectionDisposition": "DISABLED_NO_SELECTED_PROFILE",
    }
    projection = context.get("sourceProjection", {})
    if projection.get("acceptedExpansionHead") != BASE or projection.get("acceptedExpansionTree") != BASE_TREE or projection.get("contractConsumption") != consumption:
        raise ValueError("C37 source projection drift")
    if projection.get("lineage") != {"disposition": "EXACT_WITH_GENERATION_REBIND", "predecessorCardID": "V21-P04-C37"}:
        raise ValueError("C37 lineage authority drift")
    if projection.get("canonicalSuccessor") != {"cardID": "V23-P04-C38", "registerOrdinal": 123} or projection.get("sourceAuthorityMode") != "REPRODUCED_FROM_OWNER_PINNED_ACCEPTED_APP_GIT_BLOBS":
        raise ValueError("C37 successor/source authority drift")

    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST or fence.get("frozenS10ReservationDigest") != FROZEN_S10_DIGEST or fence.get("baseHead") != BASE or fence.get("baseTree") != BASE_TREE:
        raise ValueError("coordination fence identity drift")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or tuple(fence.get("existingPaths", ())) != () or tuple(fence.get("newPaths", ())) != NEW or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("coordination allowed path drift")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C37 path overlaps S10 reservation")
    if fence.get("priorFenceProof") != {
        "authorizationBasis": "C37_OWNER_AUTHORIZED_ALL_NEW_WORKFLOW_UI_TEST_FIXTURE_AND_TOOLING_PATHS",
        "authorizedOverlapEdgeCount": 0,
        "authorizedOverlapEdges": [],
        "fenceCount": 127,
        "overlapEdgeCount": 0,
        "priorFenceSetDigest": "15e958dce090bd8404dd81fd178b9a71d0d0a4ca93378221d7d41771ffcb5290",
        "priorOwnedPathCount": 0,
        "s10ReservedOverlapCount": 0,
        "unauthorizedOverlapCount": 0,
    }:
        raise ValueError("C37 prior fence proof drift")

    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    if allocation.get("cardID") != CARD or allocation.get("allocationDigest") != ALLOCATION_DIGEST or tuple(allocation.get("exactOrderedPaths", ())) != NEW or allocation.get("existingPaths") != [] or allocation.get("newPaths") != list(NEW) or allocation.get("newProductTestUIFixturePathCount") != 5 or allocation.get("newToolingDocumentationPathCount") != 8 or allocation.get("s10ReservedOverlapCount") != 0 or allocation.get("acceptanceCredit") is not False:
        raise ValueError("C37 allocation evidence drift")
    if allocation.get("persistenceDecision") != persistence or allocation.get("sourceProjection", {}).get("contractConsumption") != consumption:
        raise ValueError("C37 allocation semantic drift")

    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    if prerequisite.get("prerequisiteDigest") != PREREQUISITE_DIGEST or prerequisite.get("successorCardID") != CARD or prerequisite.get("canonicalDirectPrerequisiteCardIDs") != direct or prerequisite.get("ordinaryDirectEdgeCount") != 3 or prerequisite.get("directPrerequisiteProof") != proof or prerequisite.get("acceptanceCredit") is not False:
        raise ValueError("C37 prerequisite evidence drift")
    if prerequisite.get("immediateSequentialPredecessor") != {
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": "V23-P04-C36",
        "checkpointDigest": "ada3a0ab0cfe73f50ff621af2d9b40a37becffd2ee5bbba6c8625153d7b45f41",
        "verificationReceiptDigest": "0892a25a12d3670efd42f7454cbbb6c33608a6ba4663fea153f8ecc9f4db25ef",
    }:
        raise ValueError("C37 immediate predecessor evidence drift")

    transition = read_json(root / f"transitions/{SEQUENCE:06d}-{CARD}-attempt-1-NOT_STARTED-to-HYDRATING.json")
    expected_transition = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "createdAt": "2026-09-01T21:30:00Z",
        "directPrerequisiteCheckpointDigests": [
            "e89b1e98c209cb621e4103f11e2ee7a110250d16baa8612db33a7a81e1231c3e",
            "764898529bcede38a53b7045addf9178b3b1d05774fc43c6e1b1fb9018197378",
            "3738094484c1ea8c898fe1b114d8cccb00b8b5f503f226194a4d4f40668b841e",
        ],
        "fromState": "NOT_STARTED",
        "newLedgerDigest": LEDGER_DIGEST,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "priorC36CheckpointDigest": "ada3a0ab0cfe73f50ff621af2d9b40a37becffd2ee5bbba6c8625153d7b45f41",
        "priorC36VerificationDigest": "0892a25a12d3670efd42f7454cbbb6c33608a6ba4663fea153f8ecc9f4db25ef",
        "priorLedgerDigest": "d6493b160bf1e88af4130a3ce12d1f6be05bea50aa2931763f67c8b289fe2c5b",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "sequence": SEQUENCE,
        "toState": "HYDRATING",
        "transitionDigest": TRANSITION_DIGEST,
    }
    if transition != expected_transition:
        raise ValueError("C37 transition evidence drift")

    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    if ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != LEDGER_DIGEST:
        raise ValueError("C37 ledger identity drift")
    expected_entry = {
        "adapterPortOwner": "V23-P03-C50",
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "classification": "IMPLEMENT_NOW",
        "closedFutureReentry": "CLOSED_TYPED_REENTRY_ONLY",
        "contextDigest": CONTEXT_DIGEST,
        "directPrerequisites": direct,
        "importEngineOwner": "V23-P04-C08",
        "ordinal": ORDINAL,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "planningStatus": "NOT_STARTED",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "selectedProfileCount": 0,
        "selectedProfileDisposition": "DISABLED_NO_SELECTED_PROFILE",
        "state": "HYDRATING",
        "stateReason": "P04_C37_EVIDENCE_SELECTED_FLAT_FILE_ADAPTER_HYDRATING_WITH_DISABLED_NO_SELECTED_PROFILE",
    }
    entries = [entry for entry in ledger.get("attempts", ()) if entry.get("cardID") == CARD]
    if len(entries) != 1 or entries[0] != expected_entry:
        raise ValueError("C37 ledger entry drift")
    active = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    projection_entries = [entry for entry in active.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if active.get("ledgerDigest") != LEDGER_DIGEST or active.get("projectionDigest") != PROJECTION_DIGEST or len(projection_entries) != 1 or projection_entries[0] != expected_entry:
        raise ValueError("C37 projection drift")


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
        "fencePathCount": 13,
        "existingPathCount": 0,
        "newPathCount": 13,
        "productTestUIFixturePathCount": 5,
        "toolingPathCount": 8,
        "authorizedOverlapCount": 0,
        "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0,
        "frozenS10ReservationDigest": FROZEN_S10_DIGEST,
        "orderedPathFence": list(PATH_FENCE),
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
        "existingPathCount": 0,
        "newPathCount": len(NEW),
        "productTestUIFixturePathCount": len(PRODUCT),
        "toolingPathCount": len(OWNED),
        "s10ReservationOverlapCount": 0,
        "durableFamilyCount": 0,
        "parallelImporterCount": 0,
        "parallelStoreCount": 0,
        "parallelWriterCount": 0,
        "parallelRendererCount": 0,
        "parallelBackendCount": 0,
    }


def _base_document() -> dict[str, Any]:
    auth = authority()
    source_rows, source_ready = rows()
    return {
        "schema": "V23P04C37IncumbentFileAdapterWorkflowToolingV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "sourceRows": source_rows,
        "sourceReady": source_ready,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "lifecycle": {
            "status": "DISABLED_NO_SELECTED_PROFILE",
            "selectedProfileCount": 0,
            "persistence": "NONPERSISTENT",
            "readOnlyOwners": ["V23-P03-C50", "V23-P04-C08", "V23-P04-C16"],
            "newDurableFamilyCount": 0,
            "newModelCount": 0,
            "newSchemaCount": 0,
            "newMigrationCount": 0,
            "newStoreCount": 0,
            "newWriterCount": 0,
        },
        "independence": {
            "selectedProfileCount": 0,
            "selectionDisposition": "DISABLED_NO_SELECTED_PROFILE",
            "c50ReadOnly": True,
            "c08ReadOnly": True,
            "c16ReadOnly": True,
            "network": False,
            "sdk": False,
            "login": False,
            "credentials": False,
            "profileSpecificStrings": False,
            "providerSuccessClaim": False,
            "newImporter": False,
            "newStore": False,
            "newWriter": False,
            "newRenderer": False,
            "newBackend": False,
        },
    }


def documents() -> dict[str, Any]:
    base = _base_document()
    requirements = {
        "closedTypedWorkflow": True,
        "disabledState": "DISABLED_NO_SELECTED_PROFILE",
        "selectedProfileCount": 0,
        "disabledZeroAction": True,
        "previewZeroWrite": True,
        "deterministicClosedSeam": True,
        "exactReleaseSelection": True,
        "optionalReadOnlyC50Exchange": True,
        "optionalReadOnlyC08ImportEngine": True,
        "readOnlyC16Prerequisite": True,
        "noNetwork": True,
        "noSDK": True,
        "noLogin": True,
        "noCredentials": True,
        "noProfileSpecificStrings": True,
        "noProviderSuccessClaim": True,
        "noParallelImporter": True,
        "noParallelStore": True,
        "noParallelWriter": True,
        "noParallelRenderer": True,
        "noParallelBackend": True,
        "nonPersistent": True,
        "finalHashesUnsealed": True,
        "fiveEvidenceScenarios": True,
        "manualCommandCases": ["previewInbound", "previewCanonicalImport", "beginCanonicalImport", "commitOrCancelCanonicalImport", "export", "recover"],
        "executeAPI": "IncumbentFileAdapterWorkflowCoordinatorV1.execute",
        "projectionAPI": "IncumbentFileAdapterWorkflowCoordinatorV1.projection",
        "previewAPI": "IncumbentFileExchangeCoordinatorV1.preview",
        "renderAPI": "IncumbentFileExchangeCoordinatorV1.render",
        "recoveryAPI": "IncumbentFileExchangeCoordinatorV1.recover",
        "importEngineOwner": "V23-P04-C08",
        "adapterPortOwner": "V23-P03-C50",
        "futureReentry": "CLOSED_TYPED_REENTRY_REQUIRES_EXACT_PROFILE_SELECTION_AND_NEW_MAPPING_PREVIEW",
        "noAutomaticImport": True,
        "noFileMeansSyncOrDelivery": True,
    }
    contract = {
        **base,
        "contract": "IncumbentFileAdapterWorkflowContractV1",
        "requirements": requirements,
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
        "corpusExpectations": {
            "schema": CORPUS_SCHEMA,
            "synthetic": True,
            "production": dict(CORPUS_PRODUCTION),
            "syntheticAuthority": dict(CORPUS_SYNTHETIC_AUTHORITY),
            "hostileCases": list(CORPUS_HOSTILE_CASES),
            "recoveryCases": list(CORPUS_RECOVERY_CASES),
        },
    }
    evidence = {
        **base,
        "receipt": "IncumbentFileAdapterWorkflowEvidenceReceiptV1",
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "scenarioEvidenceIDs": list(SELECTORS),
        "claims": dict(CORPUS_CLAIMS),
        "prohibitedClaims": ["provider success", "network access", "credential use", "profile-specific license", "sync", "delivery", "acceptance"],
        "productionBoundary": dict(CORPUS_PRODUCTION),
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
        "selectedProfileCount": 0,
        "profileState": "DISABLED_NO_SELECTED_PROFILE",
        "providerSuccessClaim": False,
        "networkOrSDK": False,
        "customerDataPresent": False,
        "customerSecretsPresent": False,
        "licenseTrademarkEvidence": False,
        "syncDeliveryAcceptanceClaim": False,
    }
    schema = schema_document()
    hashes = {
        CONTRACT: sha(pretty(contract)),
        EVIDENCE: sha(pretty(evidence)),
        BRAND: sha(pretty(brand)),
        SCHEMA: sha(pretty(schema)),
    }
    manifest = {
        "schema": "V23P04C37ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": base["authority"],
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in hashes.items()],
        "sourceRows": base["sourceRows"],
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "counts": {"fencePathCount": 13, "existingPathCount": 0, "newPathCount": 13, "productTestUIFixturePathCount": 5, "toolingPathCount": 8, "durableFamilyCount": 0, "s10ReservationOverlapCount": 0},
        "independence": dict(base["independence"]),
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
        "fencePathCount": {"const": 13}, "existingPathCount": {"const": 0}, "newPathCount": {"const": 13}, "productTestUIFixturePathCount": {"const": 5}, "toolingPathCount": {"const": 8}, "authorizedOverlapCount": {"const": 0}, "unauthorizedOverlapCount": {"const": 0}, "s10ReservationOverlapCount": {"const": 0}, "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST}, "orderedPathFence": {"type": "array", "const": list(PATH_FENCE)}, "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3}, "finalHashesSealed": {"const": False},
    }
    lifecycle = {
        "type": "object",
        "required": ["status", "selectedProfileCount", "persistence", "readOnlyOwners", "newDurableFamilyCount", "newModelCount", "newSchemaCount", "newMigrationCount", "newStoreCount", "newWriterCount"],
        "properties": {"status": {"const": "DISABLED_NO_SELECTED_PROFILE"}, "selectedProfileCount": {"const": 0}, "persistence": {"const": "NONPERSISTENT"}, "readOnlyOwners": {"const": ["V23-P03-C50", "V23-P04-C08", "V23-P04-C16"]}, "newDurableFamilyCount": {"const": 0}, "newModelCount": {"const": 0}, "newSchemaCount": {"const": 0}, "newMigrationCount": {"const": 0}, "newStoreCount": {"const": 0}, "newWriterCount": {"const": 0}},
        "additionalProperties": False,
    }
    independence = {
        "type": "object",
        "required": ["selectedProfileCount", "selectionDisposition", "c50ReadOnly", "c08ReadOnly", "c16ReadOnly", "network", "sdk", "login", "credentials", "profileSpecificStrings", "providerSuccessClaim", "newImporter", "newStore", "newWriter", "newRenderer", "newBackend"],
        "properties": {"selectedProfileCount": {"const": 0}, "selectionDisposition": {"const": "DISABLED_NO_SELECTED_PROFILE"}, "c50ReadOnly": {"const": True}, "c08ReadOnly": {"const": True}, "c16ReadOnly": {"const": True}, "network": {"const": False}, "sdk": {"const": False}, "login": {"const": False}, "credentials": {"const": False}, "profileSpecificStrings": {"const": False}, "providerSuccessClaim": {"const": False}, "newImporter": {"const": False}, "newStore": {"const": False}, "newWriter": {"const": False}, "newRenderer": {"const": False}, "newBackend": {"const": False}},
        "additionalProperties": False,
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C37IncumbentFileAdapterWorkflowToolingV1",
        "type": "object",
        "required": ["schema", "cardID", "ordinal", "authority", "sourceRows", "sourceReady", "flags", "finalHashesSealed", "lifecycle", "independence"],
        "properties": {"schema": {"const": "V23P04C37IncumbentFileAdapterWorkflowToolingV1"}, "cardID": {"const": CARD}, "ordinal": {"const": ORDINAL}, "authority": {"$ref": "#/$defs/authority"}, "sourceRows": {"type": "array", "minItems": 5, "maxItems": 5, "items": {"$ref": "#/$defs/sourceRow"}}, "sourceReady": {"type": "boolean"}, "flags": {"$ref": "#/$defs/flags"}, "finalHashesSealed": {"const": False}, "lifecycle": {"$ref": "#/$defs/lifecycle"}, "independence": {"$ref": "#/$defs/independence"}, "contract": {"type": "string"}, "receipt": {"type": "string"}, "requirements": {"type": "object"}, "scenarioEvidenceIDs": {"type": "array", "const": list(SELECTORS)}},
        "additionalProperties": True,
        "$defs": {"sha256": hash_def, "sourceRow": source_row, "flags": flags, "authority": {"type": "object", "required": list(authority_properties), "properties": authority_properties, "additionalProperties": False}, "lifecycle": lifecycle, "independence": independence},
    }
