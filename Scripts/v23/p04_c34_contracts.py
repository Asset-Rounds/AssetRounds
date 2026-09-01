"""Pinned tooling contracts for V23-P04-C34.

This module deliberately keeps the C34 punch-review lane independent from the
C33 installation lane.  It is the single source of truth used by the
generator and verifier; no app state is written here.
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
CARD = "V23-P04-C34"
ORDINAL = 119
BASE = "ba328dbb397d34c408dd52f5fb6cb27a3e12ecfb"
BASE_TREE = "0bde1ef53e118d08e7e13d44bb333a683a9c6f60"
COORDINATION_HEAD = "1720acb997a0432fd269a9d2e27fd49d24740c0a"
COORDINATION_TREE = "110500a39e1bebd4830ff39abaf000594e253603"
SEQUENCE = 533
CONTEXT_DIGEST = "8604bcce9b4805e846141a54d1fc0f95040a88688205042c3dcd89d07f54b26c"
FENCE_DIGEST = "ba4a1c7e1bc88e6ecfaf447dfc7608e599b3076ac7ab7dbbcc225fe49c7c82f4"
ALLOCATION_DIGEST = "ae626d74b4c7a130e1c98db24d74a128e730339355e924d2d91d47c531d3c22b"
PREREQUISITE_DIGEST = "028acb8b3a44dd8747ebf6b67ccb5d5f6ded957c47db283c807060bf7c2025f2"
TRANSITION_DIGEST = "fe07f9eb422da141e5d53a1c819977654f27eaa08d20e18f87d2eb687ccb317d"
LEDGER_DIGEST = "91835becdcaf10033eba13d78c7feb753dd0d962898ec5456755b9c1d0c7e18e"
PROJECTION_DIGEST = "afe7e001d376982bc65525c08cfad8d15d7c077f72ea09f33d7b9918137b8811"
FROZEN_S10_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FINAL_HASHES_SEALED = False

# Short aliases retained for the sealed v23 tooling-module convention.  The
# descriptive names above remain canonical for C34-specific code.
BTREE = BASE_TREE
HEAD = COORDINATION_HEAD
CTREE = COORDINATION_TREE
SEQ = SEQUENCE
CONTEXT = CONTEXT_DIGEST
FENCE = FENCE_DIGEST
ALLOCATION = ALLOCATION_DIGEST
PREREQ = PREREQUISITE_DIGEST
TRANSITION = TRANSITION_DIGEST
LEDGER = LEDGER_DIGEST
PROJECTION = PROJECTION_DIGEST
S10 = FROZEN_S10_DIGEST

EXISTING = (
    "FieldEvidenceApp/Application/Activities/ActivityContractCoordinatorV2.swift",
    "FieldEvidenceApp/Domain/Activities/ActivityContractFamiliesV2.swift",
)
PRODUCT = (
    "FieldEvidenceApp/Application/Activities/PunchReviewWorkflowCoordinatorV1.swift",
    "FieldEvidenceApp/Features/Activities/PunchReviewWorkflowView.swift",
    "FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests.swift",
    "FieldEvidenceAppTests/Fixtures/V23/Activities/V23P04C34PunchReviewWorkflowCorpusV1.json",
    "FieldEvidenceAppUITests/V23_P04_C34PunchReviewWorkflowUITests.swift",
)
SCRIPTS = (
    "Scripts/v23/p04_c34_contracts.py",
    "Scripts/v23/generate_p04_c34_contracts.py",
    "Scripts/v23/verify_p04_c34_contracts.py",
)
SCHEMA = "Scripts/v23/punch-review-workflow.schema.json"
CONTRACT = "docs/design/v23/tooling/V23P04C34PunchReviewWorkflowContractV1.json"
EVIDENCE = "docs/design/v23/tooling/V23P04C34PunchReviewWorkflowEvidenceReceiptV1.json"
BRAND = "docs/design/v23/tooling/V23P04C34BrandImpactManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P04-C34-tooling-manifest.json"

NEW = (*PRODUCT, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
PATH_FENCE = (*EXISTING, *NEW)
OWNED = frozenset((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = (*EXISTING, *PRODUCT)

SELECTOR_ROWS = (
    ("G01", "V23-P04-C34-G01", "GOLDEN"),
    ("A01", "V23-P04-C34-A01", "ALTERNATE"),
    ("H01", "V23-P04-C34-H01", "HOSTILE"),
    ("I01", "V23-P04-C34-I01", "INTERRUPTION"),
    ("R01", "V23-P04-C34-R01", "RECOVERY"),
)
SELECTORS = tuple(row[1] for row in SELECTOR_ROWS)

SCENARIO_ROWS = (
    (
        "G01",
        "GOLDEN",
        (
            "standalone",
            "no_installation",
            "no_plan",
            "preparation",
            "review_decision",
            "correction",
            "recheck",
            "explicit_closeout",
            "deterministic_report",
        ),
    ),
    (
        "A01",
        "ALTERNATE",
        (
            "optional_installation_snapshot",
            "read_only_reference",
            "externally_installed_work",
            "no_installation_mutation",
        ),
    ),
    (
        "H01",
        "HOSTILE",
        (
            "stale_revision",
            "wrong_asset",
            "conflicting_recheck",
            "unresolved_count_mismatch",
            "no_partial_success",
            "no_compliance_inference",
        ),
    ),
    (
        "I01",
        "INTERRUPTION",
        (
            "interruption",
            "effect_before_receipt",
            "explicit_recovery",
            "same_mutation_id",
            "exactly_once",
        ),
    ),
    (
        "R01",
        "RECOVERY",
        (
            "reopen",
            "retry",
            "replay",
            "immutable_item_history",
            "immutable_correction_history",
            "same_authorized_receipt_or_effect",
            "deterministic_report_reconstruction",
        ),
    ),
)

CORPUS_EXPECTED = {
    "correctionAndRecheckHistoryImmutable": True,
    "explicitPreparationRequired": True,
    "installationSnapshotOptionalReadOnly": True,
    "noInstallationOrPlanRequired": True,
    "oneBoundedResult": True,
    "reportRebuildDeterministic": True,
    "retryIsIdempotent": True,
    "unresolvedCountReconciled": True,
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
    "V23-P04-C34": (7451, "074351a691c59ec4a7c152fc72e1dd946ed39cb8ab91f1eed5a37b6cc90b7bb0"),
    "V21-P04-C34": (3641, "7bd6129388c864f5f5ed3a0545d5d110c1e0c1ae3781ae836d7eb0ec436daf13"),
    "V23-P04-C34-register": (345, "230c1fc1c6bf16d9323457b8348df0c8d230a66d2ad2377c95c19eab3a62ac90"),
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
        return json.loads(target.read_bytes().decode("utf-8"), object_pairs_hook=_duplicate_reject)
    except FileNotFoundError as error:
        raise ValueError(f"missing JSON: {target.as_posix()}") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"malformed JSON: {target.as_posix()}") from error


def _coordination_root() -> Path | None:
    value = os.environ.get("V23_P04_C34_COORDINATION_ROOT")
    if value == "NONE":
        return None
    return Path(value) if value else ROOT.parent / "AssetRounds-v23-coordination"


def _source_slices() -> list[dict[str, Any]]:
    if git("rev-parse", f"{BASE}^{{tree}}") != BASE_TREE:
        raise ValueError("app base tree does not match pinned C34 authority")
    blueprint = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    foundation = _git_bytes("show", f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")

    def block(card: str, indent: bytes) -> bytes:
        pattern = rb"(?ms)^" + re.escape(indent) + rb"### " + re.escape(card.encode()) + rb" \xe2\x80\x94.*?(?=^" + re.escape(indent) + rb"### |\Z)"
        match = re.search(pattern, blueprint)
        if match is None:
            raise ValueError(f"missing pinned source block: {card}")
        return match.group(0)

    register_marker = b'<a id="v23-p04-c34-register"></a>'
    register_lines = [line for line in foundation.splitlines(keepends=True) if register_marker in line]
    if len(register_lines) != 1:
        raise ValueError("missing or ambiguous pinned C34 register row")
    values = {
        "V23-P04-C34": block("V23-P04-C34", b""),
        "V21-P04-C34": block("V21-P04-C34", b"    "),
        "V23-P04-C34-register": register_lines[0],
    }
    result: list[dict[str, Any]] = []
    for anchor, value in values.items():
        measured = (len(value), sha(value))
        if measured != SOURCE_PINS[anchor]:
            raise ValueError(f"source pin drift: {anchor}")
        result.append({"anchor": anchor, "utf8Length": len(value), "sha256": measured[1]})
    return result


def _coordination_evidence(root: Path) -> None:
    if git("rev-parse", "HEAD", cwd=root) != COORDINATION_HEAD or git("rev-parse", "HEAD^{tree}", cwd=root) != COORDINATION_TREE:
        raise ValueError("coordination identity drift")
    context = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json")
    fence = read_json(root / f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json")
    if context.get("cardID") != CARD or context.get("registerOrdinal") != ORDINAL:
        raise ValueError("coordination context identity drift")
    if context.get("contextDigest") != CONTEXT_DIGEST or context.get("ownerAuthorizedPathAllocationDigest") != ALLOCATION_DIGEST or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("coordination context digest drift")
    if context.get("repository") != {"appBaseHead": BASE, "appBaseTree": BASE_TREE}:
        raise ValueError("coordination context app base drift")
    if tuple(context.get("existingPaths", ())) != EXISTING or tuple(context.get("newPaths", ())) != NEW:
        raise ValueError("coordination context path fence drift")
    if context.get("persistenceDecision", {}).get("persistentSchema") != "V36" or context.get("persistenceDecision", {}).get("recordsSchemaVersion") != 35 or context.get("persistenceDecision", {}).get("newDurableFamilyCount") != 0:
        raise ValueError("coordination persistence decision drift")
    if context.get("persistenceDecision", {}).get("secondKernelStoreWriterRendererBackendProhibited") is not True:
        raise ValueError("C34 parallel backend prohibition missing")
    if context.get("sourceProjection", {}).get("contractConsumption", {}).get("prohibition") != "NO_INSTALLATION_OR_C33_SEMANTIC_DEPENDENCY_NO_SECOND_KERNEL_STORE_WRITER_RENDERER_BACKEND":
        raise ValueError("C34 independence authority drift")
    if fence.get("fenceDigest") != FENCE_DIGEST or fence.get("frozenS10ReservationDigest") != FROZEN_S10_DIGEST:
        raise ValueError("coordination fence digest drift")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or tuple(fence.get("existingPaths", ())) != EXISTING or tuple(fence.get("newPaths", ())) != NEW:
        raise ValueError("coordination allowed path drift")
    if set(PATH_FENCE) & set(fence.get("activeS10ReservedPaths", ())):
        raise ValueError("C34 path overlaps S10 reservation")
    proof = fence.get("priorFenceProof", {})
    if (proof.get("fenceCount"), proof.get("priorOwnedPathCount"), proof.get("overlapEdgeCount"), proof.get("authorizedOverlapEdgeCount"), proof.get("unauthorizedOverlapCount"), proof.get("s10ReservedOverlapCount")) != (124, 2, 4, 4, 0, 0):
        raise ValueError("prior fence proof drift")

    transition = read_json(root / f"transitions/{SEQUENCE:06d}-{CARD}-attempt-1-NOT_STARTED-to-HYDRATING.json")
    for key, expected in {
        "sequence": SEQUENCE,
        "cardID": CARD,
        "attemptID": 1,
        "fromState": "NOT_STARTED",
        "toState": "HYDRATING",
        "candidateHead": BASE,
        "candidateTree": BASE_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "ownerAuthorizedPathAllocationDigest": ALLOCATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "newLedgerDigest": LEDGER_DIGEST,
        "transitionDigest": TRANSITION_DIGEST,
        "c33SemanticDependency": "REMOVED_BY_COR-004",
    }.items():
        if transition.get(key) != expected:
            raise ValueError(f"transition identity drift: {key}")
    ledger = read_json(root / "state/BootstrapExecutionLedgerEnvelopeV1.json")
    if ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != LEDGER_DIGEST:
        raise ValueError("ledger identity drift")
    projection = read_json(root / "projections/ActiveWorkSetProjectionV1.json")
    if projection.get("ledgerDigest") != LEDGER_DIGEST or projection.get("projectionDigest") != PROJECTION_DIGEST:
        raise ValueError("projection identity drift")
    entries = [entry for entry in projection.get("activeEntries", ()) if entry.get("cardID") == CARD]
    if len(entries) != 1 or entries[0].get("state") != "HYDRATING":
        raise ValueError("active C34 projection drift")


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
        "fencePathCount": 15,
        "existingPathCount": 2,
        "newPathCount": 13,
        "productTestUIFixturePathCount": 5,
        "toolingPathCount": 8,
        "priorFenceProof": {
            "fenceCount": 124,
            "priorOwnedPathCount": 2,
            "overlapEdgeCount": 4,
            "authorizedOverlapEdgeCount": 4,
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
        "schema": "V23P04C34PunchReviewWorkflowToolingV1",
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
            "reportOwner": "EXISTING_SOLE_REPORT_RENDERER",
        },
        "independence": {
            "installationDependency": False,
            "installationSnapshotDisposition": "OPTIONAL_READ_ONLY_REFERENCE",
            "planRequired": False,
            "c33SemanticDependency": "REMOVED_BY_COR-004",
        },
    }
    contract = {
        **base,
        "contract": "PunchReviewWorkflowContractV1",
        "requirements": {
            "standalonePreparationRequired": True,
            "installationOrPlanRequired": False,
            "optionalInstallationSnapshotReadOnly": True,
            "externalInstalledWorkSupported": True,
            "explicitItemDispositionRequired": True,
            "correctionAndRecheckAppendOnly": True,
            "unresolvedCountReconciled": True,
            "explicitCloseoutRequired": True,
            "reportReadyOnlyFromRecordedCloseout": True,
            "noComplianceOrApprovalInference": True,
            "exactRevisionAndMutationIDRequired": True,
            "effectBeforeReceiptRecoverySupported": True,
            "retryIsIdempotent": True,
            "finalizedHistoryImmutable": True,
            "reportRebuildDeterministic": True,
            "oneBoundedResult": True,
            "singleCanonicalWriter": True,
            "noParallelStoreWriterRendererBackend": True,
            "canonicalCoordinator": "PunchReviewWorkflowCoordinatorV1",
            "consumedSharedFamily": "V23-P03-C47",
            "c33InstallationDependency": False,
        },
        "scenarioEvidenceIDs": [row[1] for row in SELECTOR_ROWS],
    }
    evidence = {
        **base,
        "receipt": "PunchReviewWorkflowEvidenceReceiptV1",
        "scenarioEvidenceIDs": [row[1] for row in SELECTOR_ROWS],
        "receiptState": "PROVISIONAL_STATIC_TOOLING",
        "acceptanceCredit": False,
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
        "claimsSafeCompliantPermittedApproved": False,
    }
    schema = schema_document()
    hashes = {
        CONTRACT: sha(pretty(contract)),
        EVIDENCE: sha(pretty(evidence)),
        BRAND: sha(pretty(brand)),
        SCHEMA: sha(pretty(schema)),
    }
    manifest = {
        "schema": "V23P04C34ToolingManifestV1",
        "cardID": CARD,
        "ordinal": ORDINAL,
        "authority": auth,
        "pathFence": list(PATH_FENCE),
        "files": [{"path": path, "sha256": digest} for path, digest in hashes.items()],
        "sourceRows": source_rows,
        "flags": dict(FLAGS),
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "counts": {
            "fencePathCount": 15,
            "existingPathCount": 2,
            "newPathCount": 13,
            "productTestUIFixturePathCount": 5,
            "toolingPathCount": 8,
            "durableFamilyCount": 0,
            "s10ReservationOverlapCount": 0,
        },
        "independence": dict(base["independence"]),
    }
    return {SCHEMA: schema, CONTRACT: contract, EVIDENCE: evidence, BRAND: brand, MANIFEST: manifest}


def schema_document() -> dict[str, Any]:
    """Return the strict contract schema written by the generator."""

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
        "appBaseHead": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
        "appBaseTree": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
        "coordinationHead": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
        "coordinationTree": {"type": "string", "pattern": "^[0-9a-f]{40}$"},
        "sequence": {"const": SEQUENCE},
        "contextDigest": hash_def,
        "pathFenceDigest": hash_def,
        "allocationDigest": hash_def,
        "prerequisiteDigest": hash_def,
        "transitionDigest": hash_def,
        "ledgerDigest": hash_def,
        "projectionDigest": hash_def,
        "fencePathCount": {"const": 15},
        "existingPathCount": {"const": 2},
        "newPathCount": {"const": 13},
        "productTestUIFixturePathCount": {"const": 5},
        "toolingPathCount": {"const": 8},
        "priorFenceProof": {
            "type": "object",
            "required": ["fenceCount", "priorOwnedPathCount", "overlapEdgeCount", "authorizedOverlapEdgeCount", "unauthorizedOverlapCount", "s10ReservedOverlapCount"],
            "properties": {
                "fenceCount": {"const": 124},
                "priorOwnedPathCount": {"const": 2},
                "overlapEdgeCount": {"const": 4},
                "authorizedOverlapEdgeCount": {"const": 4},
                "unauthorizedOverlapCount": {"const": 0},
                "s10ReservedOverlapCount": {"const": 0},
            },
            "additionalProperties": False,
        },
        "s10ReservationOverlapCount": {"const": 0},
        "frozenS10ReservationDigest": hash_def,
        "orderedPathFence": {"type": "array", "minItems": 15, "maxItems": 15, "uniqueItems": True, "items": {"type": "string"}},
        "sourcePins": {"type": "array", "minItems": 3, "maxItems": 3, "items": {"type": "object"}},
        "finalHashesSealed": {"const": False},
    }
    lifecycle_def = {
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
            "reportOwner": {"const": "EXISTING_SOLE_REPORT_RENDERER"},
        },
        "additionalProperties": False,
    }
    independence_def = {
        "type": "object",
        "required": [
            "installationDependency",
            "installationSnapshotDisposition",
            "planRequired",
            "c33SemanticDependency",
        ],
        "properties": {
            "installationDependency": {"const": False},
            "installationSnapshotDisposition": {"const": "OPTIONAL_READ_ONLY_REFERENCE"},
            "planRequired": {"const": False},
            "c33SemanticDependency": {"const": "REMOVED_BY_COR-004"},
        },
        "additionalProperties": False,
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": "V23P04C34PunchReviewWorkflowToolingV1",
        "type": "object",
        "required": ["schema", "cardID", "ordinal", "authority", "sourceRows", "sourceReady", "flags", "finalHashesSealed", "lifecycle", "independence"],
        "properties": {
            "schema": {"const": "V23P04C34PunchReviewWorkflowToolingV1"},
            "cardID": {"const": CARD},
            "ordinal": {"const": ORDINAL},
            "authority": {"$ref": "#/$defs/authority"},
            "sourceRows": {"type": "array", "minItems": 7, "maxItems": 7, "items": {"$ref": "#/$defs/sourceRow"}},
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
                "const": [
                    "V23-P04-C34-G01",
                    "V23-P04-C34-A01",
                    "V23-P04-C34-H01",
                    "V23-P04-C34-I01",
                    "V23-P04-C34-R01",
                ],
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
            "lifecycle": lifecycle_def,
            "independence": independence_def,
        },
    }


def source_semantic_rows() -> tuple[str, ...]:
    """Expose the exact C34 evidence IDs for verifier/import tooling."""

    return tuple(row[1] for row in SELECTOR_ROWS)
