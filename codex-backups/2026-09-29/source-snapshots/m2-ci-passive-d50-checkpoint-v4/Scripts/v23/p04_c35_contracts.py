"""Pinned tooling contracts for V23-P04-C35.

The C35 lane is a recipient-side review exchange.  It consumes the existing
C48 portable-exchange store as a read-only exact-byte replay seam and delegates
the only canonical C14 mutation to the existing workspace writer.  This module
is intentionally independent of the C33 installation workflow and C54's
optional encryption owner.  The generator and verifier import this module as
their single source of truth.
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
CARD = "V23-P04-C35"
ORDINAL = 120
BASE = "681b0306887c5fe3cac61bbbe3301e3815890b4f"
BASE_TREE = "43a2f696548480b7e9fd7b597316fe015301396a"
COORDINATION_HEAD = "75d6e2d5692c2cc7548bbb9d45378b1ad6e3aaf1"
COORDINATION_TREE = "fb253e276ea5f338eacd53e8c9601bbe5de10b53"
SEQUENCE = 537
ALLOCATION_DIGEST = "29a5c339ad47a438561b91c66ee8c917262778443436e471d8f50ef233840efa"
PREREQUISITE_DIGEST = "c85bd99436ad53a100ba4745d29ea08f1d7ca57ac993ffd8f05b4f0b960d5d32"
CONTEXT_DIGEST = "91d701f1461e7bd7193d948d2abbf7a252139c679ebd0e31632d79042dd0c288"
FENCE_DIGEST = "d36c0a3c2b351a525358e23554a76466a7c0bdb12079e648f4da7b956e00b7fe"
TRANSITION_DIGEST = "02fae8c2b92fbf6fca3883f0ba963ea86261786b4d91183d005564ce144f03b0"
LEDGER_DIGEST = "a79a7a1edbea2a75875dac4df4585bf6b4f8a8b73c1510a2ff1ee71751e8d26c"
PROJECTION_DIGEST = "fd6be7be53cc15cbe5455d181bf2a5ada2aa2124cc790d4e8b918937f50d2168"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FINAL_HASHES_SEALED = False

# Short aliases are kept for callers that consume every v23 tooling module
# through one generic import surface.
BTREE = BASE_TREE
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

EXISTING = (
    "FieldEvidenceApp/Infrastructure/ReviewExchange/PortableExchangeSessionStoreV2.swift",
)
PRODUCT = (
    "FieldEvidenceApp/Application/ReviewExchange/RecipientReviewWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/ReviewExchange/RecipientReviewWorkflowView.swift",
    "FieldEvidenceAppTests/V9_98RecipientReviewWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/ReviewExchange/V23P04C35RecipientReviewWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C35RecipientReviewWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c35_contracts.py",
    "Scripts/v23/generate_p04_c35_contracts.py",
    "Scripts/v23/verify_p04_c35_contracts.py",
)
SCHEMA = "Scripts/v23/recipient-review-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C35RecipientReviewWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C35RecipientReviewWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C35BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C35-tooling-manifest.json"

NEW = (*PRODUCT, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
PATH_FENCE = (*EXISTING, *NEW)
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = (*EXISTING, *PRODUCT)

SELECTOR_ROWS = (
    ("G01", "V23-P04-C35-G01", "GOLDEN"),
    ("A01", "V23-P04-C35-A01", "ALTERNATE"),
    ("H01", "V23-P04-C35-H01", "HOSTILE"),
    ("I01", "V23-P04-C35-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C35-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

# The fixture deliberately keeps scenario data synthetic and concrete.  The
# verifier checks the fixture's richer steps/cases/boundaries without treating
# any customer or encryption material as evidence.
SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "steps": [
            "CREATE_ISOLATED_REQUEST",
            "OPEN_REQUEST_OFFLINE",
            "CHECKPOINT_RESPONSE_DRAFT",
            "EXPORT_RESPONSE",
            "PREVIEW_IMPORT_ZERO_WRITE",
            "ACCEPT_AND_APPLY",
        ],
        "expectedCanonicalEffects": 1,
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "cases": [
            "LEGACY_CLEAR_RESPONSE",
            "RESPONSE_RECEIVED_ELSEWHERE_UNVERIFIED_HISTORY",
            "ENCRYPTION_DISABLED_MANUAL_FALLBACK",
        ],
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "cases": [
            "WRONG_PASSPHRASE_NEUTRAL_ERROR",
            "TAMPER_NEUTRAL_ERROR",
            "MISMATCHED_REQUEST",
            "MISMATCHED_PROOF",
            "CUSTOMER_UNSAFE_PAYLOAD",
            "DUPLICATE_RESPONSE",
            "DIVERGENT_SAME_RESPONSE_ID",
            "STALE_PREVIEW",
        ],
        "automaticApply": False,
        "expectedRejectedEffects": 0,
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "boundaries": [
            "DRAFT_CHECKPOINT",
            "RESPONSE_SEAL",
            "REQUEST_OPEN",
            "QUARANTINE_VALIDATION",
            "IMPORT_PREVIEW",
            "CANONICAL_EFFECT_BEFORE_RECEIPT",
        ],
        "result": "ZERO_OR_ONE_EXACT_EFFECT",
        "passphraseCleared": True,
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "cases": [
            "RELAUNCH_STORE_REPLAY",
            "BYTE_IDENTICAL_REEXPORT",
            "SAME_RECEIPT_OR_NO_EFFECT",
            "DIVERGENT_SAME_ID_QUARANTINED",
        ],
    },
)

CORPUS_SELECTORS = {
    "requestMode": "ISOLATED_RECIPIENT_REVIEW",
    "responseMode": "PORTABLE_FILE",
    "encryption": "DISABLED_MANUAL_FALLBACK",
    "decision": "ACCEPT_AND_APPLY",
    "networkRequired": False,
    "accountRequired": False,
    "entitlementRequired": False,
    "deliveryVerified": False,
    "readVerified": False,
    "identityVerified": False,
    "securityClaimed": False,
    "legalAcceptanceClaimed": False,
    "automaticApply": False,
    "automaticFinalize": False,
}
CORPUS_PERSISTENCE = {
    "persistentSchemaVersion": 36,
    "recordInventoryVersion": 35,
    "addsRecordFamily": False,
    "writer": "WorkspaceWriterV1",
    "sessionStore": "PortableExchangeSessionStoreV2",
    "namespace": "REVIEW",
}
CORPUS_EXCLUDED = [
    "WorkspaceID",
    "ReplicaID",
    "local sequence",
    "filesystem identity",
    "raw originals",
    "internal notes",
    "contacts",
]
CORPUS_FORBIDDEN_CLAIMS = [
    "sent",
    "delivered",
    "read",
    "verified identity",
    "secure",
    "signed",
    "legal acceptance",
    "customer approved",
]

CORPUS_EXPECTED = {
    "entitlementIndependent": True,
    "isolatedRecipientFlow": True,
    "exactRequestByteReplay": True,
    "responseReceivedElsewhereUnverified": True,
    "previewZeroWrite": True,
    "freshRevisionRequired": True,
    "explicitAcceptAndApplyRequired": True,
    "wrongPassphraseAndTamperNeutral": True,
    "legacyClearWarning": True,
    "noClearDowngrade": True,
    "ephemeralPassphrase": True,
    "c48SoleStore": True,
    "c14CanonicalApplyOnly": True,
    "c54OptionalOnly": True,
    "noSecondDurableFamily": True,
    "noNewWriter": True,
    "noNewMigration": True,
    "noIdentityDeliveryOrLegalClaim": True,
}
CORPUS_FLAG_KEYS = (
    "acceptance",
    "activation",
    "adoption",
    "hosted",
    "hostedAcceptance",
    "native",
    "nativeAcceptance",
    "physicalDevice",
    "physicalEvidence",
    "publication",
    "release",
)
FLAGS = {name: False for name in CORPUS_FLAG_KEYS}

SOURCE_PINS = {
    "V23-P04-C35": (
        7630,
        "9468219aceffb6b4668ff0417984320794b589b0a28151be61245bc6eeec49b1",
    ),
    "V21-P04-C35": (
        4885,
        "64650ce172e512e076ec2aff658105e9f378ec61bcb0c52fa73be47da416fb67",
    ),
    "V23-P04-C35-register": (
        329,
        "09604cb5ffa6bf8fde3bf302131f3aa923dfdb163a0c9f3ace5e10618bcc3afd",
    ),
}


def pretty(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def sha(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True, text=True
    ).stdout.strip()


def _git_bytes(*args: str, cwd: Path = ROOT) -> bytes:
    return subprocess.run(
        ["git", *args], cwd=cwd, check=True, capture_output=True
    ).stdout


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
        return json.loads(
            target.read_bytes().decode("utf-8"),
            object_pairs_hook=_duplicate_reject,
        )
    except FileNotFoundError as error:
        raise ValueError(f"missing JSON: {target.as_posix()}") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"malformed JSON: {target.as_posix()}") from error


def _coordination_root() -> Path | None:
    value = os.environ.get("V23_P04_C35_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C35 authority")
    blueprint = _git_bytes(
        "show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"
    )
    foundation = _git_bytes(
        "show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md"
    )

    def block(card: str, indent: bytes) -> bytes:
        pattern = (
            rb"(?ms)^"
            + re.escape(indent)
            + rb"### "
            + re.escape(card.encode())
            + rb" \xe2\x80\x94.*?(?=^"
            + re.escape(indent)
            + rb"### |\Z)"
        )
        match = re.search(pattern, blueprint)
        if match is None:
            raise ValueError(f"missing pinned source block: {card}")
        return match.group(0)

    marker = b'<a id="v23-p04-c35-register"></a>'
    register_lines = [line for line in foundation.splitlines(keepends=True) if marker in line]
    if len(register_lines) != 1:
        raise ValueError("missing or ambiguous pinned C35 register row")
    values = {
        "V23-P04-C35": block("V23-P04-C35", b""),
        "V21-P04-C35": block("V21-P04-C35", b"    "),
        "V23-P04-C35-register": register_lines[0],
    }
    result: list[dict[str, Any]] = []
    for anchor, value in values.items():
        measured = (len(value), sha(value))
        if measured != SOURCE_PINS[anchor]:
            raise ValueError(f"source pin drift: {anchor}")
        result.append(
            {"anchor": anchor, "utf8Length": measured[0], "sha256": measured[1]}
        )
    return result


def _coordination_evidence(root: Path) -> None:
    if (
        git("rev-parse", "HEAD", cwd=root) != COORDINATION_HEAD
        or git("rev-parse", "HEAD^{tree}", cwd=root) != COORDINATION_TREE
    ):
        raise ValueError("coordination identity drift")

    context = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json")
    fence = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    if context.get("cardID") != CARD or context.get("registerOrdinal") != ORDINAL:
        raise ValueError("coordination context identity drift")
    if (
        context.get("contextDigest") != CONTEXT_DIGEST
        or context.get("ownerAuthorizedPathAllocationDigest") != ALLOCATION_DIGEST
        or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST
    ):
        raise ValueError("coordination context digest drift")
    if context.get("repository") != {"appBaseHead": BASE, "appBaseTree": BASE_TREE}:
        raise ValueError("coordination context app base drift")
    if tuple(context.get("existingPaths", ())) != EXISTING or tuple(context.get("newPaths", ())) != NEW:
        raise ValueError("coordination context path fence drift")
    persistence = context.get("persistenceDecision", {})
    if persistence != {
        "consumedExistingStore": "PortableExchangeSessionStoreV2_NON_SWIFTDATA_V2_NAMESPACED_REVIEW_SERVICE_STAGING",
        "newDurableFamilyCount": 0,
        "newMigrationCount": 0,
        "newWriterCount": 0,
        "persistentSchema": "V36",
        "readOnlyExactRequestReplaySeam": True,
        "recordsSchemaVersion": 35,
        "secondDurableFamilyModelMigrationWriterOrStoreProhibited": True,
    }:
        raise ValueError("C35 persistence decision drift")
    consumption = context.get("sourceProjection", {}).get("contractConsumption", {})
    if consumption != {
        "existingReadOnlyReplayPath": EXISTING[0],
        "optionalEncryptionProvider": "V23-P03-C54:ENCRYPTED_REVIEW",
        "prohibition": "NO_C48_CONTRACT_OR_COORDINATOR_OWNERSHIP_NO_C54_ENCRYPTION_OWNERHIP_NO_SECOND_DURABLE_FAMILY_MODEL_MIGRATION_WRITER_OR_STORE",
        "providerCardID": "V23-P03-C48",
        "soleStore": "PortableExchangeSessionStoreV2",
    }:
        raise ValueError("C35 contract-consumption authority drift")
    lineage = context.get("sourceProjection", {}).get("lineage", {})
    if lineage != {
        "disposition": "REFINED_WITHOUT_LOSS",
        "predecessorCardID": "V21-P04-C35",
    }:
        raise ValueError("C35 lineage authority drift")
    if context.get("sourceProjection", {}).get("canonicalSuccessor") != {
        "cardID": "V23-P04-C36",
        "registerOrdinal": 121,
    }:
        raise ValueError("C35 successor authority drift")

    if (
        fence.get("fenceDigest") != FENCE_DIGEST
        or fence.get("frozenS10ReservationDigest") != FROZEN_S10_DIGEST
        or fence.get("baseHead") != BASE
        or fence.get("baseTree") != BASE_TREE
    ):
        raise ValueError("coordination fence identity drift")
    if (
        tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE
        or tuple(fence.get("existingPaths", ())) != EXISTING
        or tuple(fence.get("newPaths", ())) != NEW
        or fence.get("allowedDeletePaths") != []
        or fence.get("allowedRenamePaths") != []
    ):
        raise ValueError("coordination allowed path drift")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C35 path overlaps S10 reservation")
    proof = fence.get("priorFenceProof", {})
    if (
        proof.get("fenceCount"),
        proof.get("priorOwnedPathCount"),
        proof.get("overlapEdgeCount"),
        proof.get("authorizedOverlapEdgeCount"),
        proof.get("unauthorizedOverlapCount"),
        proof.get("s10ReservedOverlapCount"),
    ) != (125, 1, 5, 5, 0, 0):
        raise ValueError("prior fence proof drift")
    if proof.get("authorizationBasis") != "C35_REUSES_ONLY_C48_PORTABLE_EXCHANGE_STORE_READ_ONLY_EXACT_REQUEST_REPLAY_SEAM":
        raise ValueError("prior fence authorization drift")

    allocation = read_json(
        root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json"
    )
    if (
        allocation.get("cardID") != CARD
        or allocation.get("allocationDigest") != ALLOCATION_DIGEST
        or tuple(allocation.get("exactOrderedPaths", ())) != PATH_FENCE
        or allocation.get("existingPaths") != list(EXISTING)
        or allocation.get("newPaths") != list(NEW)
        or allocation.get("newProductTestUIFixturePathCount") != 5
        or allocation.get("newToolingDocumentationPathCount") != 8
        or allocation.get("s10ReservedOverlapCount") != 0
        or allocation.get("acceptanceCredit") is not False
    ):
        raise ValueError("C35 allocation evidence drift")
    if allocation.get("persistenceDecision") != persistence:
        raise ValueError("C35 allocation persistence drift")
    if allocation.get("sourceProjection", {}).get("contractConsumption") != consumption:
        raise ValueError("C35 allocation contract-consumption drift")

    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    if (
        prerequisite.get("prerequisiteDigest") != PREREQUISITE_DIGEST
        or prerequisite.get("successorCardID") != CARD
        or prerequisite.get("canonicalDirectPrerequisiteCardIDs") != [
            "V23-P03-C48",
            "V23-P04-C16",
        ]
        or prerequisite.get("ordinaryDirectEdgeCount") != 2
        or prerequisite.get("directPrerequisiteProof", {}).get("observedDirectEdgeCount") != 2
        or prerequisite.get("directPrerequisiteProof", {}).get("allAcceptanceCreditFalse") is not True
        or prerequisite.get("optionalProviderEvidence", {}).get("cardID") != "V23-P03-C54"
        or prerequisite.get("optionalProviderEvidence", {}).get("semanticRole") != "OPTIONAL_READ_ONLY_PROVIDER_NOT_DIRECT_PREREQUISITE"
        or prerequisite.get("acceptanceCredit") is not False
    ):
        raise ValueError("C35 prerequisite evidence drift")
    if prerequisite.get("optionalProviderEvidence", {}).get("checkpointDigest") != "9e01caafe3162fdd642f31494cc135e2b06504d3ad0d583c71a3ed47c3e3f57d":
        raise ValueError("C35 optional provider checkpoint drift")

    transition = read_json(
        root / f"transitions/{SEQUENCE:06d}-{CARD}-attempt-1-NOT_STARTED-to-HYDRATING.json"
    )
    transition_expected = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "createdAt": "2026-09-01T19:30:00Z",
        "directPrerequisiteCheckpointDigests": [
            "7ba7f8d7576925dc9990cc29510b56df3c7c8f4066cab5e226121e28b08f8bab",
            "3738094484c1ea8c898fe1b114d8cccb00b8b5f503f226194a4d4f40668b841e",
        ],
        "fromState": "NOT_STARTED",
        "newLedgerDigest": LEDGER_DIGEST,
        "optionalProviderCheckpointDigest": "9e01caafe3162fdd642f31494cc135e2b06504d3ad0d583c71a3ed47c3e3f57d",
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "priorC34CheckpointDigest": "fabdb7ba93196f17c2a70da93d6aa0f5752635625343174b796025d99e56f9d0",
        "priorC34VerificationDigest": "88eb312933ff390de54261f97f03014b6bb35b77a9b2c4d0be2b1e1f4b4f62a5",
        "priorLedgerDigest": "88142e50c857ae278dfe9c30dee77edc1f61da9ecb993b9d48cdf0017d26c493",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "sequence": SEQUENCE,
        "toState": "HYDRATING",
        "transitionDigest": TRANSITION_DIGEST,
    }
    if transition != transition_expected:
        raise ValueError("C35 transition evidence drift")

    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    if ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != LEDGER_DIGEST:
        raise ValueError("C35 ledger identity drift")
    ledger_entries = [entry for entry in ledger.get("attempts", ()) if entry.get("cardID") == CARD]
    if len(ledger_entries) != 1:
        raise ValueError("C35 ledger entry cardinality drift")
    ledger_entry = ledger_entries[0]
    for key, expected in {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "classification": "IMPLEMENT_NOW",
        "consumedStore": "PortableExchangeSessionStoreV2",
        "contextDigest": CONTEXT_DIGEST,
        "directPrerequisites": ["V23-P03-C48", "V23-P04-C16"],
        "optionalProvider": "V23-P03-C54:ENCRYPTED_REVIEW",
        "ordinal": ORDINAL,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "planningStatus": "NOT_STARTED",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "state": "HYDRATING",
    }.items():
        if ledger_entry.get(key) != expected:
            raise ValueError(f"C35 ledger entry drift: {key}")

    projection = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    if (
        projection.get("ledgerDigest") != LEDGER_DIGEST
        or projection.get("projectionDigest") != PROJECTION_DIGEST
        or projection.get("nextEligibleCardID") is not None
        or projection.get("nextEligibleRegisterOrdinal") is not None
        or projection.get("eligibilityBasis") != "P04_C35_HYDRATING_C36_NOT_ELIGIBLE_UNTIL_CHECKPOINT"
    ):
        raise ValueError("C35 projection identity drift")
    projection_entries = [entry for entry in projection.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if len(projection_entries) != 1 or projection_entries[0].get("state") != "HYDRATING":
        raise ValueError("C35 active projection drift")


def authority() -> dict[str, Any]:
    result = {
        "cardID": CARD,
        "ordinal": ORDINAL,
        "appBaseHead": BASE,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "sequence": SEQUENCE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "allocationDigest": ALLOCATION_DIGEST,
        "prerequisiteDigest": PREREQUISITE_DIGEST,
        "transitionDigest": TRANSITION_DIGEST,
        "ledgerDigest": LEDGER_DIGEST,
        "projectionDigest": PROJECTION_DIGEST,
        "fencePathCount": 14,
        "existingPathCount": 1,
        "newPathCount": 13,
        "productTestUIFixturePathCount": 5,
        "toolingPathCount": 8,
        "priorFenceProof": {
            "fenceCount": 125,
            "priorOwnedPathCount": 1,
            "overlapEdgeCount": 5,
            "authorizedOverlapEdgeCount": 5,
            "unauthorizedOverlapCount": 0,
            "s10ReservedOverlapCount": 0,
        },
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
        result.append(
            {
                "path": path,
                "status": "SOURCE_PRESENT" if present else "SOURCE_MISSING",
                "sha256": sha(target.read_bytes()) if present else None,
            }
        )
    return result, all(row["status"] == "SOURCE_PRESENT" for row in result)


def counts() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in git(*args).splitlines() if line}

    changed = (
        names("diff", "--name-only", BASE, "HEAD")
        | names("diff", "--name-only", "HEAD")
        | names("diff", "--cached", "--name-only")
        | names("ls-files", "--others", "--exclude-standard")
        | set(OWNED)
    )
    allowed = set(PATH_FENCE)
    return {
        "changedPathCount": len(changed & allowed),
        "unownedChangedPathCount": len(changed - allowed),
        "missingPathCount": sum(not (ROOT / path).is_file() for path in allowed),
        "fencePathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING),
        "newPathCount": len(NEW),
        "productTestUIFixturePathCount": len(PRODUCT),
        "toolingPathCount": len(OWNED),
        "s10ReservationOverlapCount": 0,
        "durableFamilyCount": 0,
        "parallelWriterCount": 0,
        "parallelKernelCount": 0,
        "parallelRendererCount": 0,
        "parallelBackendCount": 0,
    }


def documents() -> dict[str, Any]:
    auth = authority()
    source_rows, source_ready = rows()
    base = {
        "schema": "V23P04C35RecipientReviewWorkflowToolingV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "sourceRows": source_rows,
        "sourceReady": source_ready,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "lifecycle": {
            "persistentSchemaVersion": 36,
            "recordsSchemaVersion": 35,
            "durableFamily": "NONE",
            "newDurableFamilyCount": 0,
            "newWriterCount": 0,
            "newMigrationCount": 0,
            "newKernelCount": 0,
            "newRendererCount": 0,
            "newBackendCount": 0,
            "projectionPersistence": "NONPERSISTENT",
            "reportOwner": "EXISTING_WORKSPACE_WRITER_V1",
            "sessionStore": "PortableExchangeSessionStoreV2",
            "sessionNamespace": "REVIEW",
        },
        "independence": {
            "entitlementIndependent": True,
            "isolatedRecipientFlow": True,
            "installationDependency": False,
            "planDependency": False,
            "c33SemanticDependency": False,
            "optionalEncryptionProvider": "V23-P03-C54:ENCRYPTED_REVIEW",
            "optionalEncryptionOnly": True,
        },
    }
    contract = {
        **base,
        "contract": "RecipientReviewWorkflowContractV1",
        "requirements": {
            "entitlementIndependent": True,
            "isolatedRecipientFlow": True,
            "exactRequestByteReplay": True,
            "responseReceivedElsewhereUnverified": True,
            "previewZeroWrite": True,
            "freshRevisionRequired": True,
            "explicitAcceptAndApplyRequired": True,
            "wrongPassphraseAndTamperNeutral": True,
            "legacyClearWarning": True,
            "noClearDowngrade": True,
            "ephemeralPassphrase": True,
            "optionalEncryptionOnly": True,
            "serviceRequestInnerKindRejected": True,
            "c48SoleStore": True,
            "c14CanonicalApplyOnly": True,
            "c54OptionalOnly": True,
            "duplicateTerminalResponseQuarantined": True,
            "noIdentityDeliveryOrLegalClaim": True,
            "noSecondDurableFamilyStoreWriterMigration": True,
            "exactReplayIdempotent": True,
            "finalizedHistoryImmutable": True,
            "canonicalApplyOwner": "WorkspaceWriterV1",
            "canonicalApplyCard": "V23-P04-C14",
            "providerCardID": "V23-P03-C48",
            "soleStore": "PortableExchangeSessionStoreV2",
            "optionalProvider": "V23-P03-C54:ENCRYPTED_REVIEW",
            "canonicalCoordinator": "RecipientReviewWorkflowCoordinatorV1",
        },
        "scenarioEvidenceIDs": list(SELECTORS),
    }
    evidence = {
        **base,
        "receipt": "RecipientReviewWorkflowEvidenceReceiptV1",
        "scenarioEvidenceIDs": list(SELECTORS),
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "claims": {
            "identityVerified": False,
            "deliveryConfirmed": False,
            "readConfirmed": False,
            "authorizationProven": False,
            "legalSignature": False,
            "nonrepudiation": False,
            "confidentialityProven": False,
            "secure": False,
            "customerApproved": False,
            "telemetry": False,
            "marketing": False,
        },
        "prohibitedClaims": list(CORPUS_FORBIDDEN_CLAIMS),
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
        "installationDependency": False,
        "c33SemanticDependency": False,
        "c54EncryptionOwnerChanged": False,
        "claimsSafeCompliantPermittedApproved": False,
        "customerDataPresent": False,
        "customerSecretsPresent": False,
    }
    schema = schema_document()
    hashes = {
        CONTRACT: sha(pretty(contract)),
        EVIDENCE: sha(pretty(evidence)),
        BRAND: sha(pretty(brand)),
        SCHEMA: sha(pretty(schema)),
    }
    manifest = {
        "schema": "V23P04C35ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in hashes.items()],
        "sourceRows": source_rows,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "counts": {
            "fencePathCount": 14,
            "existingPathCount": 1,
            "newPathCount": 13,
            "productTestUIFixturePathCount": 5,
            "toolingPathCount": 8,
            "durableFamilyCount": 0,
            "s10ReservationOverlapCount": 0,
        },
        "independence": dict(base["independence"]),
    }
    return {
        SCHEMA: schema,
        CONTRACT: contract,
        EVIDENCE: evidence,
        BRAND: brand,
        MANIFEST: manifest,
    }


def schema_document() -> dict[str, Any]:
    hash_def = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    flags_def = {
        "type": "object",
        "required": list(CORPUS_FLAG_KEYS),
        "properties": {name: {"const": False} for name in CORPUS_FLAG_KEYS},
        "additionalProperties": False,
    }
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
    authority_properties: dict[str, Any] = {
        "cardID": {"const": CARD},
        "ordinal": {"const": ORDINAL},
        "appBaseHead": {"const": BASE},
        "appBaseTree": {"const": BASE_TREE},
        "coordinationHead": {"const": COORDINATION_HEAD},
        "coordinationTree": {"const": COORDINATION_TREE},
        "sequence": {"const": SEQUENCE},
        "contextDigest": {"const": CONTEXT_DIGEST},
        "pathFenceDigest": {"const": FENCE_DIGEST},
        "allocationDigest": {"const": ALLOCATION_DIGEST},
        "prerequisiteDigest": {"const": PREREQUISITE_DIGEST},
        "transitionDigest": {"const": TRANSITION_DIGEST},
        "ledgerDigest": {"const": LEDGER_DIGEST},
        "projectionDigest": {"const": PROJECTION_DIGEST},
        "fencePathCount": {"const": 14},
        "existingPathCount": {"const": 1},
        "newPathCount": {"const": 13},
        "productTestUIFixturePathCount": {"const": 5},
        "toolingPathCount": {"const": 8},
        "priorFenceProof": {
            "type": "object",
            "required": [
                "fenceCount",
                "priorOwnedPathCount",
                "overlapEdgeCount",
                "authorizedOverlapEdgeCount",
                "unauthorizedOverlapCount",
                "s10ReservedOverlapCount",
            ],
            "properties": {
                "fenceCount": {"const": 125},
                "priorOwnedPathCount": {"const": 1},
                "overlapEdgeCount": {"const": 5},
                "authorizedOverlapEdgeCount": {"const": 5},
                "unauthorizedOverlapCount": {"const": 0},
                "s10ReservedOverlapCount": {"const": 0},
            },
            "additionalProperties": False,
        },
        "s10ReservationOverlapCount": {"const": 0},
        "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST},
        "orderedPathFence": {
            "type": "array",
            "minItems": 14,
            "maxItems": 14,
            "uniqueItems": True,
            "items": {"type": "string"},
        },
        "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3},
        "finalHashesSealed": {"const": False},
    }
    lifecycle = {
        "type": "object",
        "required": [
            "persistentSchemaVersion",
            "recordsSchemaVersion",
            "durableFamily",
            "newDurableFamilyCount",
            "newWriterCount",
            "newMigrationCount",
            "newKernelCount",
            "newRendererCount",
            "newBackendCount",
            "projectionPersistence",
            "reportOwner",
            "sessionStore",
            "sessionNamespace",
        ],
        "properties": {
            "persistentSchemaVersion": {"const": 36},
            "recordsSchemaVersion": {"const": 35},
            "durableFamily": {"const": "NONE"},
            "newDurableFamilyCount": {"const": 0},
            "newWriterCount": {"const": 0},
            "newMigrationCount": {"const": 0},
            "newKernelCount": {"const": 0},
            "newRendererCount": {"const": 0},
            "newBackendCount": {"const": 0},
            "projectionPersistence": {"const": "NONPERSISTENT"},
            "reportOwner": {"const": "EXISTING_WORKSPACE_WRITER_V1"},
            "sessionStore": {"const": "PortableExchangeSessionStoreV2"},
            "sessionNamespace": {"const": "REVIEW"},
        },
        "additionalProperties": False,
    }
    independence = {
        "type": "object",
        "required": [
            "entitlementIndependent",
            "isolatedRecipientFlow",
            "installationDependency",
            "planDependency",
            "c33SemanticDependency",
            "optionalEncryptionProvider",
            "optionalEncryptionOnly",
        ],
        "properties": {
            "entitlementIndependent": {"const": True},
            "isolatedRecipientFlow": {"const": True},
            "installationDependency": {"const": False},
            "planDependency": {"const": False},
            "c33SemanticDependency": {"const": False},
            "optionalEncryptionProvider": {"const": "V23-P03-C54:ENCRYPTED_REVIEW"},
            "optionalEncryptionOnly": {"const": True},
        },
        "additionalProperties": False,
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C35RecipientReviewWorkflowToolingV1",
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
            "schema": {"const": "V23P04C35RecipientReviewWorkflowToolingV1"},
            "cardID": {"const": CARD},
            "ordinal": {"const": ORDINAL},
            "authority": {"$ref": "#/$defs/authority"},
            "sourceRows": {
                "type": "array",
                "minItems": 6,
                "maxItems": 6,
                "items": {"$ref": "#/$defs/sourceRow"},
            },
            "sourceReady": {"type": "boolean"},
            "flags": {"$ref": "#/$defs/flags"},
            "finalHashesSealed": {"const": False},
            "lifecycle": {"$ref": "#/$defs/lifecycle"},
            "independence": {"$ref": "#/$defs/independence"},
            "contract": {"type": "string"},
            "receipt": {"type": "string"},
            "requirements": {"type": "object"},
            "scenarioEvidenceIDs": {
                "type": "array",
                "const": list(SELECTORS),
            },
        },
        "additionalProperties": True,
        "$defs": {
            "sha256": hash_def,
            "sourceRow": source_row,
            "flags": flags_def,
            "authority": {
                "type": "object",
                "required": list(authority_properties),
                "properties": authority_properties,
                "additionalProperties": False,
            },
            "lifecycle": lifecycle,
            "independence": independence,
        },
    }


def source_semantic_rows() -> tuple[str, ...]:
    """Expose the exact C35 evidence IDs for verifier/import tooling."""

    return tuple(row[1] for row in SELECTOR_ROWS)
