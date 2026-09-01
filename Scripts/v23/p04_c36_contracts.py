"""Pinned static contracts for V23-P04-C36.

The C36 lane is a manual work-resource entry workflow.  Manual values are
owned by the existing C49 work-resource coordinator; the optional stock path
is delegated to C55's typed use/return composite coordinator.  This module is
the single source of truth used by the deterministic artifact generator and
the fail-closed verifier.
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
CARD = "V23-P04-C36"
ORDINAL = 121
BASE = "418b62093945ed53fa5fd1858954f8a9acadc401"
BASE_TREE = "aa85c6fd81a74d40dbe8126e27d13306c39df758"
COORDINATION_HEAD = "c023f91517c7821d30db1b1ee5681c80e0bdc176"
COORDINATION_TREE = "fab68164022f55fbacf45a70aa4dfb9b66ee2f4e"
SEQUENCE = 542
ALLOCATION_DIGEST = "52211de5dd92863d4263524a48e0c42e4397a163d9ae9b4ad438e615492a6e66"
PREREQUISITE_DIGEST = "8506ed2333572e2c5c480285e32f67a052a72ffb62625643066c4ad3b6bb931e"
CONTEXT_DIGEST = "044f8e8366404a54331f5e38e271d5268a680096e0f2a2dddf415c22dd021087"
FENCE_DIGEST = "d6e968a2fdf2790fe237ff89f7461a752799f91becda8612cc910416ec575c80"
TRANSITION_DIGEST = "b485c29ce243c799fa44728e14f113523c660ea84260727c6f19096a5340c2e0"
LEDGER_DIGEST = "d755332acb6622caf6ef2f05d857eb967bac53801b0085f8071da151dbea6a73"
PROJECTION_DIGEST = "803fdaecc3a1177402a57fb4cbe72ae0a696a084138b8a42b5fea996eb0e1683"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FINAL_HASHES_SEALED = False

# Common aliases keep this lane consumable by the generic v23 tooling checks.
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
    "FieldEvidenceApp/Application/PartsStock/PartsStockCoordinatorV1.swift",
)
PRODUCT = (
    "FieldEvidenceApp/Application/WorkResources/ManualWorkResourceWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/WorkResources/ManualWorkResourceWorkflowView.swift",
    "FieldEvidenceAppTests/V9_99ManualWorkResourceWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/WorkResources/V23P04C36ManualWorkResourceWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C36ManualWorkResourceWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c36_contracts.py",
    "Scripts/v23/generate_p04_c36_contracts.py",
    "Scripts/v23/verify_p04_c36_contracts.py",
)
SCHEMA = "Scripts/v23/manual-work-resource-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C36ManualWorkResourceWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C36ManualWorkResourceWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C36BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C36-tooling-manifest.json"

NEW = (*PRODUCT, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
CORRECTION_DIGEST = "7a5689dddc0c56c7ba9d40b8e4efec3477ffbf294785fb6ac50d4c5eedfb4530"
HYDRATION_REVISION = 2
HYDRATION_CORRECTION_POLICY = "P04_C36_C55_PARTS_STOCK_USE_RETURN_ALLOCATES_FRESH_MUTATION_ID_INTERNALLY_SO_CALLER_SUPPLIED_MUTATION_ID_OVERLOAD_DEFAULT_IS_REQUIRED_FOR_EXACT_EFFECT_BEFORE_RECEIPT_RETRY"
PATH_FENCE = (*NEW, *EXISTING)
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = ("FieldEvidenceApp/Application/PartsStock/PartsStockCoordinatorV1.swift", *PRODUCT)

SELECTOR_ROWS = (
    ("G01", "V23-P04-C36-G01", "GOLDEN"),
    ("A01", "V23-P04-C36-A01", "ALTERNATE"),
    ("H01", "V23-P04-C36-H01", "HOSTILE"),
    ("I01", "V23-P04-C36-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C36-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

SCENARIO_ROWS = (
    {
        "id": "G01",
        "kind": "GOLDEN",
        "evidenceID": "V23-P04-C36-G01",
        "focus": "COMPLETE_MANUAL_ENTRY_WITH_EXPLICIT_STOCK_USE",
        "expectedEffects": {"manualAppend": 1, "stockMovement": 1, "workResourceSuccessor": 1},
    },
    {
        "id": "A01",
        "kind": "ALTERNATE",
        "evidenceID": "V23-P04-C36-A01",
        "focus": "MANUAL_ONLY_TYPED_FALLBACK_WITHOUT_STOCK",
        "expectedEffects": {"manualAppend": 1, "stockMovement": 0},
    },
    {
        "id": "H01",
        "kind": "HOSTILE",
        "evidenceID": "V23-P04-C36-H01",
        "focus": "INVALID_VALUES_STALE_FRONTIERS_AND_DIVERGENT_MUTATIONS",
        "expectedEffects": {"rejectedEffects": 0},
    },
    {
        "id": "I01",
        "kind": "INTERRUPTION",
        "evidenceID": "V23-P04-C36-I01",
        "focus": "EFFECT_BEFORE_RECEIPT_ZERO_OR_ONE_ATOMIC_COMPOSITE",
        "expectedEffects": {"allowedEffects": [0, 1]},
    },
    {
        "id": "R01",
        "kind": "RECOVERY",
        "evidenceID": "V23-P04-C36-R01",
        "focus": "IDEMPOTENT_REPLAY_AND_EXACT_RETURN_LINEAGE",
        "expectedEffects": {"manualReceipts": 1, "stockUseReceipts": 1, "stockReturnReceipts": 1},
    },
)

CORPUS_SCHEMA = "V23P04C36ManualWorkResourceWorkflowCorpusV1"
CORPUS_TOP_LEVEL_KEYS = frozenset(
    (
        "schema",
        "schemaVersion",
        "cardID",
        "corpusID",
        "testOnly",
        "synthetic",
        "containsCustomerData",
        "containsProductionSecrets",
        "deterministicSeed",
        "evidenceIDs",
        "consumedPersistence",
        "selectors",
        "golden",
        "alternate",
        "hostileCases",
        "recoveryCases",
    )
)
CORPUS_PERSISTENCE_KEYS = frozenset(("manualWorkResource", "partsStock", "addsRecordFamily"))
CORPUS_VERSION_KEYS = frozenset(("schemaVersion", "recordInventoryVersion"))
CORPUS_SELECTOR_KEYS = frozenset(
    (
        "manualEntryAvailable",
        "stockOptional",
        "stockUseRequiresExplicitSelection",
        "automaticStockMovement",
        "catalogLookup",
        "liveBalanceClaim",
        "accountingClaim",
        "invoiceClaim",
        "availabilityClaim",
        "approvalClaim",
        "usesBinaryFloatingPoint",
        "requiresNetwork",
        "requiresAccount",
        "requiresEntitlement",
    )
)
CORPUS_SELECTORS = {
    "manualEntryAvailable": True,
    "stockOptional": True,
    "stockUseRequiresExplicitSelection": True,
    "automaticStockMovement": False,
    "catalogLookup": False,
    "liveBalanceClaim": False,
    "accountingClaim": False,
    "invoiceClaim": False,
    "availabilityClaim": False,
    "approvalClaim": False,
    "usesBinaryFloatingPoint": False,
    "requiresNetwork": False,
    "requiresAccount": False,
    "requiresEntitlement": False,
}
CORPUS_PERSISTENCE = {
    "manualWorkResource": {"schemaVersion": 37, "recordInventoryVersion": 36},
    "partsStock": {"schemaVersion": 41, "recordInventoryVersion": 40},
    "addsRecordFamily": False,
}
CORPUS_GOLDEN = {
    "durationMinutes": 95,
    "material": {
        "description": "M8 stainless bolt",
        "quantity": {"mantissa": 4, "scale": 0},
        "unit": "EACH",
        "useFromStock": True,
    },
    "manualQuantity": {"mantissa": 1250, "scale": 3},
    "directCost": {"mantissa": 1234, "currencyCode": "USD", "minorUnitScale": 2},
    "acceptedEffects": {"manualAppend": 1, "stockMovement": 1, "workResourceSuccessor": 1},
}
CORPUS_ALTERNATE = {
    "stockFeatureEnabled": False,
    "stockContextPresent": False,
    "manualEntryStillAvailable": True,
    "stockMovementCount": 0,
}
CORPUS_HOSTILE_CASES = [
    "DRAFT_TYPING_ZERO_EFFECT",
    "DRAFT_EDITING_ZERO_EFFECT",
    "INVALID_QUANTITY_MANTISSA",
    "INVALID_QUANTITY_SCALE",
    "INVALID_UNIT",
    "INVALID_CURRENCY",
    "INVALID_CURRENCY_SCALE",
    "ZERO_STOCK_QUANTITY",
    "STALE_WORK_REVISION",
    "STALE_STOCK_REVISION",
    "WRONG_WORK_LINEAGE",
    "WRONG_RETURN_FRONTIER",
    "WRONG_PART",
    "OVERRETURN",
    "DIVERGENT_SAME_MUTATION_ID",
]
CORPUS_RECOVERY_CASES = [
    "MANUAL_APPEND_EFFECT_BEFORE_RECEIPT",
    "STOCK_COMPOSITE_EFFECT_BEFORE_RECEIPT",
    "EXACT_RETRY_ONE_RECEIPT_ONE_EFFECT",
    "RETURN_REDUCES_SOURCE_MATERIAL_LINEAGE",
    "RETURN_RESTORES_STOCK_WITHIN_OUTSTANDING_USE",
]
CORPUS_FORBIDDEN_CLAIMS = [
    "accounting truth",
    "invoice truth",
    "catalog availability",
    "approval",
    "delivery",
    "verified identity",
    "secure",
    "customer approved",
]
CORPUS_EXPECTED = {
    "manualEntryComplete": True,
    "draftEditZeroStock": True,
    "explicitStockCompositeCommit": True,
    "c55SoleCompositeCommit": True,
    "callerSuppliedMutationID": True,
    "c55MutationIDCompatibilityOverload": True,
    "dtoMutationIDPropagation": True,
    "sameCommandStockRetry": True,
    "noDoubleC49Append": True,
    "frozenSuccessor": True,
    "sameMutationID": True,
    "returnFrontierBounded": True,
    "outstandingQuantityBounded": True,
    "optionalTypedStockFallback": True,
    "integerMantissaScale": True,
    "noDouble": True,
    "entitlementIndependent": True,
    "deterministicOutput": True,
    "noNewDurableFamily": True,
    "noNewWriter": True,
    "noNewMigration": True,
    "noNewStore": True,
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
FLAGS = {key: False for key in CORPUS_FLAG_KEYS}

SOURCE_PINS = {
    "V23-P04-C36": (7647, "c7efe3281bd77d1c0022150d88c118e7b69ab7bfd7149e3a3e1122ac2cdd2573"),
    "V21-P04-C36": (3659, "39506ab6cd9873c62951cee82a20864ae8b8922f8134039b425343e58b63f403"),
    "V23-P04-C36-register": (310, "04122b819fcdc243cd3b25c82c037404e838368ba200b48bbc701b6c0fa3c7d8"),
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
    value = os.environ.get("V23_P04_C36_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C36 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")

    def block(card: str, indent: bytes) -> bytes:
        pattern = rb"(?ms)^" + re.escape(indent) + rb"### " + re.escape(card.encode()) + rb" \xe2\x80\x94.*?(?=^" + re.escape(indent) + rb"### |\Z)"
        match = re.search(pattern, blueprint)
        if match is None:
            raise ValueError(f"missing pinned source block: {card}")
        return match.group(0)

    marker = b'<a id="v23-p04-c36-register"></a>'
    register_lines = [line for line in foundation.splitlines(keepends=True) if marker in line]
    if len(register_lines) != 1:
        raise ValueError("missing or ambiguous pinned C36 register row")
    values = {
        "V23-P04-C36": block("V23-P04-C36", b""),
        "V21-P04-C36": block("V21-P04-C36", b"    "),
        "V23-P04-C36-register": register_lines[0],
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
    if context.get("cardID") != CARD or context.get("registerOrdinal") != ORDINAL or context.get("hydrationRevision") != HYDRATION_REVISION or context.get("hydrationFenceCorrectionPolicy") != HYDRATION_CORRECTION_POLICY:
        raise ValueError("coordination context identity drift")
    if context.get("contextDigest") != CONTEXT_DIGEST or context.get("ownerAuthorizedPathAllocationDigest") != ALLOCATION_DIGEST or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("coordination context digest drift")
    if context.get("repository") != {"appBaseHead": BASE, "appBaseTree": BASE_TREE}:
        raise ValueError("coordination context app base drift")
    if tuple(context.get("existingPaths", ())) != EXISTING or tuple(context.get("newPaths", ())) != NEW or tuple(context.get("expectedArtifacts", ())) != PATH_FENCE:
        raise ValueError("coordination context path fence drift")
    persistence = {
        "manualOnlyAppendOwner": "WorkResourceCoordinator",
        "manualRecordPersistentSchema": "V37",
        "manualRecordRecordsSchemaVersion": 36,
        "newDurableFamilyCount": 0,
        "newMigrationCount": 0,
        "newStoreCount": 0,
        "newWriterCount": 0,
        "noSecondC49AppendAfterStockCompositeCommit": True,
        "stockPersistentSchema": "V41",
        "stockRecordsSchemaVersion": 40,
        "stockUseReturnSoleCompositeCommit": "PartsStockCoordinatorV1",
    }
    if context.get("persistenceDecision") != persistence:
        raise ValueError("C36 persistence decision drift")
    consumption = {
        "manualAppendOwner": "WorkResourceCoordinator",
        "manualProviderCardID": "V23-P03-C49",
        "manualRecordFamily": "ManualWorkResourceRecordRow_V37_RECORDS36",
        "optionalStockProvider": "V23-P03-C55:USE_FROM_STOCK",
        "prohibition": "NO_C49_OR_C55_OWNERHIP_NO_SECOND_COMMIT_NO_NEW_DURABLE_FAMILY_MODEL_SCHEMA_WRITER_OR_STORE",
        "soleCompositeCommit": "PartsStockCoordinatorV1_USE_OR_RETURN_WITH_EMBEDDED_FROZEN_WORK_SUCCESSOR",
        "stockFamily": "PartsStockCoordinatorV1_V41_RECORDS40",
    }
    if context.get("sourceProjection", {}).get("contractConsumption") != consumption:
        raise ValueError("C36 contract-consumption authority drift")
    if context.get("sourceProjection", {}).get("lineage") != {"disposition": "REFINED_WITHOUT_LOSS", "predecessorCardID": "V21-P04-C36"}:
        raise ValueError("C36 lineage authority drift")
    if context.get("sourceProjection", {}).get("canonicalSuccessor") != {"cardID": "V23-P04-C37", "registerOrdinal": 122}:
        raise ValueError("C36 successor authority drift")

    if fence.get("fenceDigest") != FENCE_DIGEST or fence.get("frozenS10ReservationDigest") != FROZEN_S10_DIGEST or fence.get("baseHead") != BASE or fence.get("baseTree") != BASE_TREE:
        raise ValueError("coordination fence identity drift")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or tuple(fence.get("existingPaths", ())) != EXISTING or tuple(fence.get("newPaths", ())) != NEW or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("coordination allowed path drift")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C36 path overlaps S10 reservation")
    proof = fence.get("priorFenceProof", {})
    if proof != {
        "authorizationBasis": "C36_C55_PARTS_STOCK_SOLE_COMPOSITE_COMMIT_REQUIRES_CALLER_SUPPLIED_MUTATION_ID_RECOVERY_OVERLOAD",
        "authorizedOverlapEdgeCount": 1,
        "authorizedOverlapEdges": [{
            "boundEvidence": {
                "providerCapability": "USE_FROM_STOCK",
                "providerCardID": "V23-P03-C55",
                "recoveryRequirement": "CALLER_SUPPLIED_MUTATION_ID_WITH_DEFAULT_PREVENTS_FRESH_ID_RETRY_DIVERGENCE",
            },
            "disposition": "AUTHORIZED_C55_EXISTING_OWNER_READ_ONLY_BACKWARD_COMPATIBLE_RECOVERY_OVERLOAD",
            "path": EXISTING[0],
            "priorAttemptID": 1,
            "priorCardID": "V23-P03-C55",
            "priorFenceDigest": "7c8198a356f283683194f05b593e6cb11b0cdb32e4a1fad3d2a48d049e64b906",
        }],
        "fenceCount": 127,
        "overlapEdgeCount": 1,
        "priorFenceSetDigest": "15cac08ee69172514769eead6de472beedc34313f988813224e31eb6f0a66213",
        "priorOwnedPathCount": 1918,
        "s10ReservedOverlapCount": 0,
        "unauthorizedOverlapCount": 0,
    }:
        raise ValueError("prior fence proof drift")

    allocation = read_json(root / f"receipts/{CARD}-owner-authorized-path-allocation-v1.json")
    if allocation.get("cardID") != CARD or allocation.get("allocationDigest") != ALLOCATION_DIGEST or tuple(allocation.get("exactOrderedPaths", ())) != NEW or allocation.get("existingPaths") != [] or allocation.get("newPaths") != list(NEW) or allocation.get("newProductTestUIFixturePathCount") != 5 or allocation.get("newToolingDocumentationPathCount") != 8 or allocation.get("s10ReservedOverlapCount") != 0 or allocation.get("acceptanceCredit") is not False:
        raise ValueError("C36 allocation evidence drift")
    if allocation.get("persistenceDecision") != persistence or allocation.get("sourceProjection", {}).get("contractConsumption") != consumption:
        raise ValueError("C36 allocation semantic drift")

    correction = read_json(root / f"receipts/{CARD}-parts-stock-recovery-hydration-fence-correction-v2.json")
    if correction != {
        "acceptanceCredit": False,
        "acceptanceEnabled": False,
        "addedPaths": list(EXISTING),
        "adoptionEnabled": False,
        "allowedPathCount": 14,
        "attemptID": 1,
        "authorizedPriorFenceOverlapCount": 1,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "createdAt": "2026-09-01T21:00:00Z",
        "existingPathCount": 1,
        "fenceDigest": FENCE_DIGEST,
        "hostedDispatchEnabled": False,
        "hostedDispatchRan": False,
        "hydrationRevision": HYDRATION_REVISION,
        "initialHydrationTransitionDigest": "8faba068df11b286104af46a02db62b49f2595dd2dee0740e495616ca4ffbd1b",
        "nativeCompileRan": False,
        "newPathCount": 13,
        "originalAllocationDigest": ALLOCATION_DIGEST,
        "phase10PollingDuringParallelExecution": False,
        "physicalDeviceEnabled": False,
        "priorAllowedPathCount": 13,
        "priorContextDigest": "594f1ea77c80c2be7bd523f39628bec48fd40db1cf1c489e077bb86f12713a94",
        "priorFenceDigest": "196afafbb35703882de38cc7542465812e86224381f8cf191f78f55cbeb8c664",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "publicationEnabled": False,
        "reason": HYDRATION_CORRECTION_POLICY,
        "receiptDigest": CORRECTION_DIGEST,
        "releaseCredit": False,
        "releaseReady": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "s10ReservedOverlapCount": 0,
        "schema": "HydratedPathFenceCorrectionReceiptV1",
        "schemaVersion": 1,
        "unauthorizedPriorFenceOverlapCount": 0,
    }:
        raise ValueError("C36 hydration fence correction drift")

    prerequisite = read_json(root / f"receipts/{CARD}-provisional-prerequisite.json")
    proof = prerequisite.get("directPrerequisiteProof", {})
    if prerequisite.get("prerequisiteDigest") != PREREQUISITE_DIGEST or prerequisite.get("successorCardID") != CARD or prerequisite.get("canonicalDirectPrerequisiteCardIDs") != ["V23-P03-C49", "V23-P04-C16"] or prerequisite.get("ordinaryDirectEdgeCount") != 2 or proof.get("observedDirectEdgeCount") != 2 or proof.get("expectedDirectEdgeCount") != 2 or proof.get("uniqueCardCount") != 2 or any(proof.get(key) != 0 for key in ("missingCount", "duplicateCount", "orphanCount", "staleCount", "incompatibleCount", "failedIntermediateAcceptanceCount")) or proof.get("allAcceptanceCreditFalse") is not True or prerequisite.get("optionalProviderEvidence", {}).get("cardID") != "V23-P03-C55" or prerequisite.get("optionalProviderEvidence", {}).get("semanticRole") != "OPTIONAL_READ_ONLY_PROVIDER_NOT_DIRECT_PREREQUISITE" or prerequisite.get("acceptanceCredit") is not False:
        raise ValueError("C36 prerequisite evidence drift")
    optional = prerequisite["optionalProviderEvidence"]
    if optional.get("checkpointDigest") != "b59b8a563b1b0688ec9fcffc481493f24cbd50b832f888fa49ea535937b775e9" or optional.get("verificationReceiptDigest") != "ac58bf7b97cdd1b5d89520738c05e366bfac43333fbf4323e5abe9f03eb63135":
        raise ValueError("C36 optional provider evidence drift")

    transition = read_json(root / f"transitions/{SEQUENCE:06d}-{CARD}-attempt-1-HYDRATING-to-HYDRATING-parts-stock-recovery-fence-correction.json")
    expected_transition = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "contextDigest": CONTEXT_DIGEST,
        "createdAt": "2026-09-01T21:00:00Z",
        "fromState": "HYDRATING",
        "hydrationCorrectionReceiptDigest": CORRECTION_DIGEST,
        "newLedgerDigest": LEDGER_DIGEST,
        "originalAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "priorContextDigest": "594f1ea77c80c2be7bd523f39628bec48fd40db1cf1c489e077bb86f12713a94",
        "priorLedgerDigest": "d0a86bc7cd31dc983032012bf65903ac0a7dc2d7db8b96244b722aaa3a2ebb1d",
        "priorPathFenceDigest": "196afafbb35703882de38cc7542465812e86224381f8cf191f78f55cbeb8c664",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "reason": HYDRATION_CORRECTION_POLICY,
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "sequence": SEQUENCE,
        "transitionDigest": TRANSITION_DIGEST,
        "toState": "HYDRATING",
    }
    if transition != expected_transition:
        raise ValueError("C36 transition evidence drift")

    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    if ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != LEDGER_DIGEST:
        raise ValueError("C36 ledger identity drift")
    entries = [entry for entry in ledger.get("attempts", ()) if entry.get("cardID") == CARD]
    if len(entries) != 1:
        raise ValueError("C36 ledger entry cardinality drift")
    expected_entry = {
        "attemptID": 1,
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "cardID": CARD,
        "classification": "IMPLEMENT_NOW",
        "consumedManualFamily": "V23-P03-C49_MANUAL_WORK_RESOURCE_RECORD_V37_RECORDS36",
        "contextDigest": CONTEXT_DIGEST,
        "directPrerequisites": ["V23-P03-C49", "V23-P04-C16"],
        "hydrationFenceCorrectionDigest": CORRECTION_DIGEST,
        "hydrationRevision": HYDRATION_REVISION,
        "optionalStockProvider": "V23-P03-C55:USE_FROM_STOCK_V41_RECORDS40",
        "ordinal": ORDINAL,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "planningStatus": "NOT_STARTED",
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "soleCompositeCommit": "PartsStockCoordinatorV1",
        "state": "HYDRATING",
        "stateReason": HYDRATION_CORRECTION_POLICY,
    }
    if entries[0] != expected_entry:
        raise ValueError("C36 ledger entry drift")

    projection = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    if projection.get("ledgerDigest") != LEDGER_DIGEST or projection.get("projectionDigest") != PROJECTION_DIGEST or projection.get("nextEligibleCardID") is not None or projection.get("nextEligibleRegisterOrdinal") is not None or projection.get("eligibilityBasis") != "P04_C36_HYDRATING_C37_NOT_ELIGIBLE_UNTIL_CHECKPOINT":
        raise ValueError("C36 projection identity drift")
    projection_entries = [entry for entry in projection.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if len(projection_entries) != 1 or projection_entries[0] != expected_entry:
        raise ValueError("C36 active projection drift")


def authority() -> dict[str, Any]:
    result = {
        "cardID": CARD,
        "ordinal": ORDINAL,
        "appBaseHead": BASE,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "sequence": SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "hydrationFenceCorrectionDigest": CORRECTION_DIGEST,
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
            "fenceCount": 127,
            "priorOwnedPathCount": 1918,
            "overlapEdgeCount": 1,
            "authorizedOverlapEdgeCount": 1,
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
        result.append({"path": path, "status": "SOURCE_PRESENT" if present else "SOURCE_MISSING", "sha256": sha(target.read_bytes()) if present else None})
    return result, all(row["status"] == "SOURCE_PRESENT" for row in result)


def counts() -> dict[str, int]:
    def names(*args: str) -> set[str]:
        return {line.replace("\\", "/") for line in git(*args).splitlines() if line}

    changed = names("diff", "--name-only", BASE, "HEAD") | names("diff", "--name-only", "HEAD") | names("diff", "--cached", "--name-only") | names("ls-files", "--others", "--exclude-standard") | set(OWNED)
    allowed = set(PATH_FENCE)
    return {
        "changedPathCount": len(changed & allowed),
        "unownedChangedPathCount": len(changed - allowed),
        "missingPathCount": sum(not (ROOT / path).is_file() for path in PATH_FENCE),
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
        "schema": "V23P04C36ManualWorkResourceWorkflowToolingV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "sourceRows": source_rows,
        "sourceReady": source_ready,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "lifecycle": {
            "manualPersistentSchemaVersion": 37,
            "manualRecordsSchemaVersion": 36,
            "stockPersistentSchemaVersion": 41,
            "stockRecordsSchemaVersion": 40,
            "durableFamily": "EXISTING_C49_WITH_OPTIONAL_C55",
            "newDurableFamilyCount": 0,
            "newWriterCount": 0,
            "newMigrationCount": 0,
            "newStoreCount": 0,
            "newKernelCount": 0,
            "newRendererCount": 0,
            "newBackendCount": 0,
            "projectionPersistence": "NONPERSISTENT",
            "manualAppendOwner": "WorkResourceCoordinatorV1",
            "stockCompositeOwner": "PartsStockCoordinatorV1",
            "stockAndWorkResourceUseIsAtomic": True,
            "noSecondC49AppendAfterStockCompositeCommit": True,
        },
        "independence": {
            "entitlementIndependent": True,
            "manualOnlyFallback": True,
            "optionalStockProvider": "V23-P03-C55:USE_FROM_STOCK",
            "installationDependency": False,
            "planDependency": False,
            "c33SemanticDependency": False,
            "c34PunchReviewDependency": False,
            "newWriter": False,
            "newStore": False,
            "newBackend": False,
        },
    }
    contract = {
        **base,
        "contract": "ManualWorkResourceWorkflowContractV1",
        "requirements": {
            **CORPUS_EXPECTED,
            "manualAppendOwner": "WorkResourceCoordinatorV1",
            "manualProviderCardID": "V23-P03-C49",
            "manualRecordFamily": "ManualWorkResourceRecordRow_V37_RECORDS36",
            "optionalStockProvider": "V23-P03-C55:USE_FROM_STOCK",
            "soleCompositeCommit": "PartsStockCoordinatorV1_USE_OR_RETURN_WITH_EMBEDDED_FROZEN_WORK_SUCCESSOR",
            "stockFamily": "PartsStockCoordinatorV1_V41_RECORDS40",
            "manualCommandCases": ["saveManual", "useFromStock", "returnToStock"],
            "executeAPI": "ManualWorkResourceWorkflowCoordinatorV1.execute",
            "projectionAPI": "ManualWorkResourceWorkflowCoordinatorV1.projection",
            "typedStockFallback": ["available", "disabled", "unavailable", "manualOnly"],
            "integerTypes": ["Int", "Int64"],
            "forbiddenNumericType": "Double",
            "stockCallerMutationIDParameter": "mutationID suppliedMutationID: MutationIDV1? = nil",
            "c36StockDTOField": "mutationID: MutationIDV1",
        },
        "scenarioEvidenceIDs": list(SELECTORS),
        "scenarioRows": list(SCENARIO_ROWS),
    }
    evidence = {
        **base,
        "receipt": "ManualWorkResourceWorkflowEvidenceReceiptV1",
        "scenarioEvidenceIDs": list(SELECTORS),
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
        "claims": {
            "saved": False,
            "stockChanged": False,
            "accountingTruth": False,
            "invoiceTruth": False,
            "catalogAvailability": False,
            "approval": False,
            "delivery": False,
            "identityVerified": False,
            "entitlementRequired": False,
            "nativeActivation": False,
            "hostedAcceptance": False,
            "customerApproved": False,
            "telemetry": False,
            "marketing": False,
        },
        "prohibitedClaims": list(CORPUS_FORBIDDEN_CLAIMS),
        "corpus": {
            "schema": CORPUS_SCHEMA,
            "synthetic": True,
            "evidenceIDs": list(SELECTORS),
        },
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
        "c34PunchReviewDependency": False,
        "customerDataPresent": False,
        "customerSecretsPresent": False,
        "claimsSafeCompliantPermittedApproved": False,
        "manualEntryClaim": False,
        "stockAvailabilityClaim": False,
        "accountingOrInvoiceClaim": False,
    }
    schema = schema_document()
    hashes = {CONTRACT: sha(pretty(contract)), EVIDENCE: sha(pretty(evidence)), BRAND: sha(pretty(brand)), SCHEMA: sha(pretty(schema))}
    manifest = {
        "schema": "V23P04C36ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in hashes.items()],
        "sourceRows": source_rows,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "counts": {"fencePathCount": 14, "existingPathCount": 1, "newPathCount": 13, "productTestUIFixturePathCount": 5, "toolingPathCount": 8, "durableFamilyCount": 0, "s10ReservationOverlapCount": 0},
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
    flags = {"type": "object", "required": list(CORPUS_FLAG_KEYS), "properties": {key: {"const": False} for key in CORPUS_FLAG_KEYS}, "additionalProperties": False}
    authority_properties: dict[str, Any] = {
        "cardID": {"const": CARD}, "ordinal": {"const": ORDINAL}, "appBaseHead": {"const": BASE}, "appBaseTree": {"const": BASE_TREE},
        "coordinationHead": {"const": COORDINATION_HEAD}, "coordinationTree": {"const": COORDINATION_TREE}, "sequence": {"const": SEQUENCE}, "hydrationRevision": {"const": HYDRATION_REVISION}, "hydrationFenceCorrectionDigest": {"const": CORRECTION_DIGEST},
        "contextDigest": {"const": CONTEXT_DIGEST}, "pathFenceDigest": {"const": FENCE_DIGEST}, "allocationDigest": {"const": ALLOCATION_DIGEST},
        "prerequisiteDigest": {"const": PREREQUISITE_DIGEST}, "transitionDigest": {"const": TRANSITION_DIGEST}, "ledgerDigest": {"const": LEDGER_DIGEST},
        "projectionDigest": {"const": PROJECTION_DIGEST}, "fencePathCount": {"const": 14}, "existingPathCount": {"const": 1}, "newPathCount": {"const": 13},
        "productTestUIFixturePathCount": {"const": 5}, "toolingPathCount": {"const": 8}, "s10ReservationOverlapCount": {"const": 0},
        "frozenS10ReservationDigest": {"const": FROZEN_S10_DIGEST}, "orderedPathFence": {"type": "array", "const": list(PATH_FENCE)},
        "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3}, "finalHashesSealed": {"const": False},
        "priorFenceProof": {"type": "object", "required": ["fenceCount", "priorOwnedPathCount", "overlapEdgeCount", "authorizedOverlapEdgeCount", "unauthorizedOverlapCount", "s10ReservedOverlapCount"], "properties": {"fenceCount": {"const": 127}, "priorOwnedPathCount": {"const": 1918}, "overlapEdgeCount": {"const": 1}, "authorizedOverlapEdgeCount": {"const": 1}, "unauthorizedOverlapCount": {"const": 0}, "s10ReservedOverlapCount": {"const": 0}}, "additionalProperties": False},
    }
    lifecycle = {"type": "object", "required": ["manualPersistentSchemaVersion", "manualRecordsSchemaVersion", "stockPersistentSchemaVersion", "stockRecordsSchemaVersion", "durableFamily", "newDurableFamilyCount", "newWriterCount", "newMigrationCount", "newStoreCount", "newKernelCount", "newRendererCount", "newBackendCount", "projectionPersistence", "manualAppendOwner", "stockCompositeOwner", "stockAndWorkResourceUseIsAtomic", "noSecondC49AppendAfterStockCompositeCommit"], "properties": {"manualPersistentSchemaVersion": {"const": 37}, "manualRecordsSchemaVersion": {"const": 36}, "stockPersistentSchemaVersion": {"const": 41}, "stockRecordsSchemaVersion": {"const": 40}, "durableFamily": {"const": "EXISTING_C49_WITH_OPTIONAL_C55"}, "newDurableFamilyCount": {"const": 0}, "newWriterCount": {"const": 0}, "newMigrationCount": {"const": 0}, "newStoreCount": {"const": 0}, "newKernelCount": {"const": 0}, "newRendererCount": {"const": 0}, "newBackendCount": {"const": 0}, "projectionPersistence": {"const": "NONPERSISTENT"}, "manualAppendOwner": {"const": "WorkResourceCoordinatorV1"}, "stockCompositeOwner": {"const": "PartsStockCoordinatorV1"}, "stockAndWorkResourceUseIsAtomic": {"const": True}, "noSecondC49AppendAfterStockCompositeCommit": {"const": True}}, "additionalProperties": False}
    independence = {"type": "object", "required": ["entitlementIndependent", "manualOnlyFallback", "optionalStockProvider", "installationDependency", "planDependency", "c33SemanticDependency", "c34PunchReviewDependency", "newWriter", "newStore", "newBackend"], "properties": {"entitlementIndependent": {"const": True}, "manualOnlyFallback": {"const": True}, "optionalStockProvider": {"const": "V23-P03-C55:USE_FROM_STOCK"}, "installationDependency": {"const": False}, "planDependency": {"const": False}, "c33SemanticDependency": {"const": False}, "c34PunchReviewDependency": {"const": False}, "newWriter": {"const": False}, "newStore": {"const": False}, "newBackend": {"const": False}}, "additionalProperties": False}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C36ManualWorkResourceWorkflowToolingV1",
        "type": "object",
        "required": ["schema", "cardID", "ordinal", "authority", "sourceRows", "sourceReady", "flags", "finalHashesSealed", "lifecycle", "independence"],
        "properties": {"schema": {"const": "V23P04C36ManualWorkResourceWorkflowToolingV1"}, "cardID": {"const": CARD}, "ordinal": {"const": ORDINAL}, "authority": {"$ref": "#/$defs/authority"}, "sourceRows": {"type": "array", "minItems": 6, "maxItems": 6, "items": {"$ref": "#/$defs/sourceRow"}}, "sourceReady": {"type": "boolean"}, "flags": {"$ref": "#/$defs/flags"}, "finalHashesSealed": {"const": False}, "lifecycle": {"$ref": "#/$defs/lifecycle"}, "independence": {"$ref": "#/$defs/independence"}, "contract": {"type": "string"}, "receipt": {"type": "string"}, "requirements": {"type": "object"}, "scenarioEvidenceIDs": {"type": "array", "const": list(SELECTORS)}},
        "additionalProperties": True,
        "$defs": {"sha256": hash_def, "sourceRow": source_row, "flags": flags, "authority": {"type": "object", "required": list(authority_properties), "properties": authority_properties, "additionalProperties": False}, "lifecycle": lifecycle, "independence": independence},
    }


def source_semantic_rows() -> tuple[str, ...]:
    """Return the stable five evidence IDs for generic tooling consumers."""

    return tuple(row[1] for row in SELECTOR_ROWS)
