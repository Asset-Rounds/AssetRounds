#!/usr/bin/env python3
"""Fail-closed static tooling contracts for V23-P04-C07.

The card owns only its contract, evidence, brand, schema, and inventory
tooling.  Product lanes are observed rather than fabricated: while any of the
five exact source lanes is absent, generated artifacts remain deterministic
and explicitly provisional.
"""
from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C07"
TITLE = "RoundSession UI, search/export/delete/recovery, batch handoff, and local closeout"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 95

# Immutable app and coordination hydration authority.
BASE_HEAD = "0d26ac2daf11333fb7e16c3156a58f30885fafde"
BASE_TREE = "2e5cd268cbc791ecaff7c66073e3424dd427f79a"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "14f44e5fde1970b28f136783d3ccf56d063660de"
COORDINATION_TREE = "08ab523c4298ec78649568af4cbaa8964cb792dd"
COORDINATION_ORIGIN_HEAD = COORDINATION_HEAD
COORDINATION_CAS_SEQUENCE = 414
SEQUENCE = COORDINATION_CAS_SEQUENCE
CONTEXT_DIGEST = "674e959f3b8f8a5221e44223d3fbd8daba233d1d1f428e9b513b7c66a73702fd"
FENCE_DIGEST = "f4501ae3ef048d5ddb8b73fc2dca1b63144d2611fd7a26a64eb118ad24ae44df"
PREREQUISITE_DIGEST = "42b6f11692a2ded37790681b9d40c1b9aeaf12979990c078040d9fef85553f4e"
HYDRATION_TRANSITION_DIGEST = "772ddb8fd0c11e87a6255c997fa8ee217dd3e3a5ab507cabb14b17000972437a"
COORDINATION_LEDGER_DIGEST = "748d1297b3c0255e4254929b9855b3af9d8fdbe77ce72955af7f621e3dfb8096"
COORDINATION_PROJECTION_DIGEST = "4487c289604b238f668befbd21c64617018da4edf4309aaa2c2bda9dca83dab4"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
PRIOR_LEDGER_DIGEST = "f9785477fe531263fa44cb59812df0b249fae837ba932a5eb288ee43297dffe3"
CREATED_AT = "2026-08-31T01:00:00Z"

# Source/test lanes are frozen and the card owner has authorized the final
# deterministic tooling seal.
FINAL_HASHES_SEALED = True

# Exact source pins materialized by the C07 hydration controller.
SOURCE_PINS = {
    "dossierUTF8Length": 7307,
    "dossierSHA256": "d404a41be3c7cfb3e2d2293276a93826f5cb69f7ed9e732fdb6e61f7c236c448",
    "inheritedV21BlockUTF8Length": 8705,
    "inheritedV21BlockSHA256": "2d567f9b7055eb9f46f36e796953fe0a8f89b77a54d6cbdb30b3f1b6143ab4c3",
    "registerRowUTF8Length": 278,
    "registerRowSHA256": "254425c5085c13886652cfe79256a511b20bd42c5ec56ce86be494c270a57605",
    "registerSectionUTF8Length": 44217,
    "registerSectionSHA256": "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5",
    "impactRowUTF8Length": 327,
    "impactRowSHA256": "8bf587b455a0f855e1644a5946238c3c2a192a01bc499a64d1685837663e2c09",
    "relationRowCount": 14,
    "relationRowsUTF8Length": 5139,
    "relationRowsSHA256": "75224b5b8270aaa318963f2076939f5f9e74730a0179ff59675b8be090168824",
    "dependencyRowCount": 12,
    "dependencyRowsUTF8Length": 2093,
    "dependencyRowsSHA256": "e3d0a523a422907580730cc6994c7a28346fb0a78310d53ee6261ad886a8bb17",
}

EXPECTED_EXISTING_PATH_COUNT = 362
EXPECTED_NEW_PATH_COUNT = 13
EXPECTED_FENCE_PATH_COUNT = 375
AUTHORIZED_OVERLAP_COUNT = 7266
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 95
PRIOR_OWNED_PATH_COUNT = 1502
S10_RESERVED_PATH_COUNT = 86

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Features/Rounds/RoundSessionView.swift",
    "FieldEvidenceApp/Infrastructure/Rounds/FieldSectionIndexProjectionV1.swift",
    "FieldEvidenceAppUITests/V9_26RoundSessionUITests.swift",
    "FieldEvidenceAppTests/V9_26RoundSessionIntegrationTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Rounds/V22P04C07RoundSessionFieldFlowCorpusV1.json",
)
# Existing canonical sources are read-only inputs to the C07 proof.  They are
# not additional C07-owned paths and never become generated output.
SUPPORTING_SOURCE_PATHS = (
    "FieldEvidenceApp/Infrastructure/Rounds/RoundSessionLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
)
SCHEMA_PATH = "Scripts/v23/round-session-field-flow.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C07RoundSessionFieldFlowContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C07RoundSessionFieldFlowEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C07BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C07-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c07_contracts.py",
    "Scripts/v23/generate_p04_c07_contracts.py",
    "Scripts/v23/verify_p04_c07_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
OUTPUT_PATHS = GENERATED_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C07-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C07-attempt-1/BootstrapPathFenceV1.json"
_PREREQUISITE_RELATIVE = "receipts/V23-P04-C06-to-V23-P04-C07-provisional-prerequisite.json"
_TRANSITION_RELATIVE = "transitions/000414-V23-P04-C07-attempt-1-NOT_STARTED-to-HYDRATING.json"
_LEDGER_RELATIVE = "state/BootstrapExecutionLedgerEnvelopeV1.json"
_PROJECTION_RELATIVE = "projections/ActiveWorkSetProjectionV1.json"

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
JOURNEY_REFS = ("CommonTaskJourneyReleaseV2",)
DIRECT_PREREQUISITES = ("V23-P04-C06",)
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
AGGREGATE_MEMBERSHIPS = (
    "AutonomousRequiredAcceptedSetV1",
    "P04ShippingSurfaceSetV1",
    "P04BrandClosureSetV1",
)
CONFORMANCE_SUBJECTS = ("P04ShippingSurfaceSetV1", "CommonTaskJourneyReleaseV2")
INVALIDATION_CONSUMERS = (
    "V23-P04-C12",
    "V23-P04-C21",
    "V23-P04-C22",
    "V23-P06-C03",
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C07).CONTRACTS",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)

COUNTS = ("EXPECTED", "VISITED", "COMPLETED", "INACCESSIBLE", "SKIPPED", "DEFERRED")
DISPOSITIONS = ("PENDING", "VISITED", "COMPLETED", "INACCESSIBLE", "SKIPPED", "DEFERRED")
SESSION_STATES = ("DRAFT", "ACTIVE", "PAUSED", "COMPLETED", "ARCHIVED")
TRANSITIONS = (
    "CREATE", "REVISE_SELECTION", "START", "VISIT_ITEM", "COMPLETE_ITEM",
    "MARK_INACCESSIBLE", "SKIP_ITEM", "DEFER_ITEM", "RETRY_ITEM", "PAUSE",
    "RESUME", "CLOSE", "ARCHIVE",
)
ANCHOR_STATES = ("CURRENT", "STALE_REQUIREMENT_FALLBACK")
LIFECYCLE = (
    "BACKUP", "REPLACE_RESTORE", "CLONE", "FORK", "IMPORT", "EXPORT", "REPORT",
    "JOURNAL", "REPLAY", "SEARCH", "REBUILD", "DELETE", "ERASE", "RETENTION",
    "COMPATIBILITY", "DOWNGRADE", "FORWARD_FIX", "INTERRUPTION", "IDEMPOTENT_RECEIPT",
)
FORBIDDEN = (
    "ACCOUNT", "AUTHENTICATION", "TENANCY", "REMOTE_SYNC", "BACKEND", "NETWORK_TRANSPORT",
    "QR_OR_NETWORK_TAG_RESOLUTION", "RECURRENCE", "DUE_QUEUE", "NOTIFICATION", "TEAM_DISPATCH",
    "PROVIDER_OUTBOX_INBOX_ACK_UPLOAD_STATE", "REMOTE_EMAIL_OR_LINK", "ANALYTICS", "NATIVE_IPAD",
    "S10_ROUTE_WIRING", "DISCARD_INCOMPLETE_WITHOUT_INFORMED_ACTION",
)
HOSTILE_VECTORS = (
    "resume-loses-position", "ui-source-disagreement", "inaccessible-item-blocks-closeout",
    "delete-search-export-orphan", "accessibility-regression", "duplicate-selection",
    "out-of-order-false-complete", "unknown-keys", "corrupt-schema", "partial-journal",
    "forbidden-route-qr-recurrence-due-notification-network",
)
INCLUDED = (
    "MANUAL_MULTI_ASSET_SELECTION_AND_ORDERING_UI",
    "DURABLE_PROGRESS_RESUME_AND_INACCESSIBLE_REASONS",
    "BOUNDED_SEARCH_INDEX_EXTENSION_AND_REBUILD",
    "BATCH_EXPORT_HANDOFF_AND_LOCAL_CLOSEOUT_RECONCILIATION",
    "DELETE_RECOVERY_UX",
    "COMMON_TASK_ACCESSIBILITY",
    "POSE_AXIS_EDITOR_STATE_AND_C36_DRAFT_POSITION_PRESERVATION",
    "COMPLETE_INCOMPLETE_FLAGGED_COUNTS_AND_JUMP",
    "PACKAGE_PERMITTED_OUT_OF_ORDER_WORK",
)
INVARIANTS = (
    "UI_NEVER_ADVANCES_AHEAD_OF_DURABLE_STATE",
    "MANUAL_FLOW_REQUIRES_NO_PERMISSION",
    "COMPLETED_RECORDS_AND_EXPORTS_RECONCILE_TO_CLOSEOUT",
    "BACK_NAVIGATION_FLUSHES_C36_BEFORE_LEAVING",
    "ROUTE_CONTAINS_NO_USER_TEXT_OR_VALUE",
    "UI_ADOPTION_AND_ACCEPTANCE_DEFERRED_PENDING_S10_6",
)
SEMANTIC_SCOPE = {
    "lineage": "EXACT_WITH_GENERATION_REBIND",
    "persistentContractMode": "CONTENT_ONLY",
    "schemaVersion": "NOT_APPLICABLE",
    "migrationRequired": False,
    "backupRestoreRequired": True,
    "deleteEraseRequired": True,
    "exportReportRequired": True,
    "downgradePolicy": "FORWARD_FIX_ONLY",
    "canonicalPersistenceOwner": "V23-P04-C05_ROUND_SESSION_V1",
    "derivedOwners": ["FieldSectionIndexProjectionV1", "FieldPositionAnchorV1"],
    "derivedLifecycle": {
        "FieldSectionIndexProjectionV1": "DETERMINISTIC_REBUILD_FROM_CANONICAL_ROUND_DRAFT_REQUIREMENT_AND_PACKAGE_INPUTS",
        "FieldPositionAnchorV1": "DEVICE_OPERATIONAL_STABLE_IDS_AND_BOUNDED_POSITION_ONLY",
    },
    "included": list(INCLUDED),
    "lifecycle": list(LIFECYCLE),
    "invariants": list(INVARIANTS),
    "forbidden": list(FORBIDDEN),
}
SOURCE_PROJECTION = {
    **SOURCE_PINS,
    "canonicalSuccessor": {"cardID": "V23-P04-C08", "registerOrdinal": 96},
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
}

FLAGS = {name: False for name in (
    "activation", "native", "hosted", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

DIRECT_PREREQUISITE_ROWS = (
    {
        "attemptID": 1,
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "cardID": "V23-P04-C06",
        "checkpointDigest": "125f7dcd888b5724b95aab1c0fc6a2d8db377da3861e5ef8b25b613b2c1aa7d5",
        "contextDigest": "f80df4adf42c3392e5639f6c65164c925f175567cc027811f905d6981e243bad",
        "disposition": "CHECKPOINTED_CANONICAL_DIRECT_PREREQUISITE",
        "finalTransitionDigest": "b4ec4f6678faeb7b08fa6efc2f71f099880f80e179b4d8414e842803809df002",
        "pathFenceDigest": "67a33ce68a08b9614e00d3e274f87b21126d72cd9be24bf0d6fd9482d1f710a6",
        "verificationReceiptDigest": "f7e48ccc231311062dd4f55b2e78340c512cd16ef0f07d73b2aee2d2569855e0",
    },
)

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
    if path.suffix.lower() in _CANONICAL_TEXT_SUFFIXES:
        return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def _coordination_root() -> Path:
    candidates = (Path(r"C:\AssetRounds-v23-coordination"), ROOT.parent / "AssetRounds-v23-coordination")
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C07 coordination fence is unavailable")


def coord() -> Path:
    return _coordination_root()


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ValueError("C07 coordination input unavailable:" + relative)
    value = json.loads(path.read_bytes(), object_pairs_hook=strict)
    if not isinstance(value, dict):
        raise ValueError("C07 coordination object required:" + relative)
    return value


def sealed_field(value: dict[str, Any], field: str) -> str:
    unsigned = {key: item for key, item in value.items() if key != field}
    return sha256_bytes((json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST or sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C07 context identity or seal differs")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST or sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ValueError("C07 path fence identity or seal differs")
    existing = tuple(context.get("existingPaths", ()))
    fenced_existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(context.get("newPaths", ()))
    fenced_new = tuple(fence.get("newPaths", ()))
    allowed = tuple(fence.get("allowedCreateOrReplacePaths", ()))
    if existing != fenced_existing or hydrated_new != fenced_new:
        raise ValueError("C07 context/fence path sets differ")
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C07 existing path fence cardinality differs")
    if hydrated_new != NEW_PATHS or allowed != existing + hydrated_new:
        raise ValueError("C07 hydrated new-path ordering differs")
    if tuple(context.get("expectedArtifacts", ())) != allowed:
        raise ValueError("C07 expected-artifact ordering differs")
    if context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST or tuple(context.get("directPrerequisites", ())) != DIRECT_PREREQUISITES:
        raise ValueError("C07 prerequisite binding differs")
    if context.get("sourceProjection") != SOURCE_PROJECTION or context.get("semanticScope") != SEMANTIC_SCOPE:
        raise ValueError("C07 source projection or semantic scope differs")
    reserved = tuple(fence.get("activeS10ReservedPaths", ()))
    if (
        fence.get("frozenS10ReservationDigest") != FROZEN_S10_RESERVATION_DIGEST
        or len(reserved) != S10_RESERVED_PATH_COUNT
        or set(existing + hydrated_new) & set(reserved)
    ):
        raise ValueError("C07 S10 reservation or overlap differs")
    return existing, hydrated_new


EXISTING_PATHS, _HYDRATED_NEW_PATHS = _load_hydrated_paths()
PATH_FENCE = EXISTING_PATHS + _HYDRATED_NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)


def _load_source_text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _text(root: Path, relative: str) -> str:
    return _load_source_text(root, relative)


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_load_source_text(root, relative), object_pairs_hook=strict)
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
        raise ValueError("C07 candidate tree differs from accepted base")
    observed_head = _git(root, "rev-parse", "HEAD")
    if observed_head != BASE_HEAD and subprocess.run(["git", "merge-base", "--is-ancestor", BASE_HEAD, observed_head], cwd=root).returncode != 0:
        raise ValueError("C07 candidate is not a descendant of accepted base")


def _prior_fence_path(card_id: str, attempt_id: int) -> Path:
    return _coordination_root() / f"contexts/{card_id}-attempt-{attempt_id}/BootstrapPathFenceV1.json"


def _validate_prior_fence_proof(fence: dict[str, Any], allowed: tuple[str, ...]) -> None:
    proof = fence.get("priorFenceProof")
    if not isinstance(proof, dict):
        raise ValueError("C07 prior fence proof missing")
    for key, expected in (
        ("fenceCount", PRIOR_FENCE_COUNT),
        ("priorOwnedPathCount", PRIOR_OWNED_PATH_COUNT),
        ("authorizedOverlapCount", AUTHORIZED_OVERLAP_COUNT),
        ("unauthorizedOverlapCount", UNAUTHORIZED_OVERLAP_COUNT),
        ("overlapCount", AUTHORIZED_OVERLAP_COUNT),
    ):
        if proof.get(key) != expected:
            raise ValueError("C07 prior fence proof differs:" + key)
    rows = proof.get("fences")
    if not isinstance(rows, list) or len(rows) != PRIOR_FENCE_COUNT:
        raise ValueError("C07 prior fence rows differ")
    rebuilt_rows: list[dict[str, Any]] = []
    expected_edges: list[dict[str, Any]] = []
    prior_owned: set[str] = set()
    disposition = "P04_C07_EXISTING_ROUND_SESSION_UI_SEARCH_EXPORT_DELETE_RECOVERY_AND_CLOSEOUT_OWNER_REPROOF_REQUIRED"
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("cardID"), str) or not isinstance(row.get("attemptID"), int):
            raise ValueError("C07 prior fence row shape differs")
        path = _prior_fence_path(row["cardID"], row["attemptID"])
        if not path.is_file():
            raise ValueError("C07 prior fence input unavailable:" + row["cardID"])
        prior = json.loads(path.read_bytes(), object_pairs_hook=strict)
        if not isinstance(prior, dict):
            raise ValueError("C07 prior fence object required:" + row["cardID"])
        owner_paths = tuple(prior.get("allowedCreateOrReplacePaths", ()))
        if prior.get("fenceDigest") != row.get("fenceDigest") or len(owner_paths) != row.get("ownedPathCount"):
            raise ValueError("C07 prior fence identity differs:" + row["cardID"])
        if sealed_field(prior, "fenceDigest") != row.get("fenceDigest"):
            raise ValueError("C07 prior fence seal differs:" + row["cardID"])
        prior_owned.update(owner_paths)
        rebuilt_rows.append({
            "cardID": row["cardID"],
            "attemptID": row["attemptID"],
            "fenceDigest": row["fenceDigest"],
            "ownedPathCount": len(owner_paths),
        })
        expected_edges.extend({
            "path": item,
            "priorCardID": row["cardID"],
            "priorFenceDigest": row["fenceDigest"],
            "disposition": disposition,
        } for item in sorted(set(allowed) & set(owner_paths)))
    if len(prior_owned) != PRIOR_OWNED_PATH_COUNT or proof.get("fences") != rebuilt_rows:
        raise ValueError("C07 prior owned-path proof differs")
    if proof.get("authorizedFenceEdges") is not None and proof.get("authorizedFenceEdges") != expected_edges:
        raise ValueError("C07 authorized fence edges differ")
    if proof.get("authorizedOverlapEdges") is not None and proof.get("authorizedOverlapEdges") != expected_edges:
        raise ValueError("C07 authorized overlap edges differ")


def _assert_coordination_state() -> None:
    coordination = _coordination_root()
    if _git(coordination, "rev-parse", "HEAD") != COORDINATION_HEAD or _git(coordination, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE:
        raise ValueError("C07 coordination HEAD/tree differs")
    origin = _git(coordination, "ls-remote", "origin", "refs/heads/main").split()
    if not origin or origin[0] != COORDINATION_ORIGIN_HEAD:
        raise ValueError("C07 coordination origin/main differs")
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    prerequisite = _coordination_json(_PREREQUISITE_RELATIVE)
    transition = _coordination_json(_TRANSITION_RELATIVE)
    ledger = _coordination_json(_LEDGER_RELATIVE)
    projection = _coordination_json(_PROJECTION_RELATIVE)
    _load_hydrated_paths()
    if context.get("repository") != {"appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE}:
        raise ValueError("C07 app base authority differs")
    if context.get("registerOrdinal") != REGISTER_ORDINAL or context.get("title") != TITLE or context.get("lineage") != "EXACT_WITH_GENERATION_REBIND":
        raise ValueError("C07 context metadata differs")
    if context.get("expectedArtifacts") != list(PATH_FENCE) or context.get("persistentChangeMode") != "CONTENT_ONLY_EXISTING_CANONICAL_KIND_WITH_DERIVED_UI_PROJECTIONS":
        raise ValueError("C07 context scope differs")
    if any(context.get(key) is not False for key in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit", "phase10PollingDuringParallelExecution")):
        raise ValueError("C07 context claims activation")
    if context.get("uiAdoptionDeferred") is not True or context.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C07 UI/S10 disposition differs")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("C07 fence scope differs")
    if (fence.get("baseHead"), fence.get("baseTree")) != (BASE_HEAD, BASE_TREE) or fence.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C07 fence base differs")
    if any(fence.get(key) is not False for key in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "releaseCredit", "phase10PollingDuringParallelExecution")):
        raise ValueError("C07 fence claims activation")
    _validate_prior_fence_proof(fence, PATH_FENCE)
    expected_prerequisite = {
        "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
        "schemaVersion": 1,
        "successorCardID": CARD,
        "successorAttemptID": 1,
        "ordinaryDirectEdgeCount": 1,
        "predecessors": list(DIRECT_PREREQUISITE_ROWS),
        "disposition": "PROVISIONALLY_SATISFIED_STATIC_IMPLEMENTATION_ONLY",
        "acceptanceCredit": False,
        "acceptanceEnabled": False,
        "adoptionEnabled": False,
        "hostedDispatchEnabled": False,
        "nativeCompileRan": False,
        "phase10PollingDuringParallelExecution": False,
        "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    if any(prerequisite.get(key) != value for key, value in expected_prerequisite.items()) or sealed_field(prerequisite, "prerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C07 direct prerequisite receipt differs")
    expected_transition = {
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "sequence": SEQUENCE,
        "cardID": CARD,
        "attemptID": 1,
        "fromState": "NOT_STARTED",
        "toState": "HYDRATING",
        "reason": "OWNER_AUTHORIZED_P04_C07_PROVISIONAL_HYDRATION",
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "priorLedgerDigest": PRIOR_LEDGER_DIGEST,
        "newLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "createdAt": CREATED_AT,
        "transitionDigest": HYDRATION_TRANSITION_DIGEST,
    }
    if any(transition.get(key) != value for key, value in expected_transition.items()) or sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C07 hydration transition differs")
    if (
        ledger.get("schema") != "BootstrapExecutionLedgerEnvelopeV1"
        or ledger.get("schemaVersion") != 1
        or ledger.get("casSequence") != SEQUENCE
        or ledger.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST
        or ledger.get("previousLedgerDigest") != PRIOR_LEDGER_DIGEST
        or sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST
    ):
        raise ValueError("C07 ledger authority differs")
    expected_row = {
        "cardID": CARD,
        "attemptID": 1,
        "ordinal": REGISTER_ORDINAL,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "state": "HYDRATING",
        "stateReason": "OWNER_AUTHORIZED_P04_C07_PROVISIONAL_HYDRATION",
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "directPrerequisites": list(DIRECT_PREREQUISITES),
    }
    rows = ledger.get("attempts")
    row = rows[-1] if isinstance(rows, list) and rows and rows[-1].get("cardID") == CARD else None
    if row != expected_row:
        raise ValueError("C07 ledger card row differs")
    if (
        projection.get("schema") != "ActiveWorkSetProjectionV1"
        or projection.get("schemaVersion") != 1
        or projection.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST
        or projection.get("projectionDigest") != COORDINATION_PROJECTION_DIGEST
        or projection.get("eligibilityBasis") != "P04_C07_HYDRATING_ROUND_SESSION_UI_SEARCH_EXPORT_DELETE_RECOVERY_BATCH_HANDOFF_AND_LOCAL_CLOSEOUT"
        or projection.get("nextEligibleCardID") is not None
        or projection.get("nextEligibleRegisterOrdinal") is not None
        or sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST
    ):
        raise ValueError("C07 projection authority differs")
    active = projection.get("activeEntries")
    projection_row = active[-1] if isinstance(active, list) and active and active[-1].get("cardID") == CARD else None
    if projection_row != expected_row:
        raise ValueError("C07 projection card row differs")


def _authority_pins_ready() -> bool:
    refs = (BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE, COORDINATION_HEAD, COORDINATION_ORIGIN_HEAD, COORDINATION_TREE)
    return all(re.fullmatch(r"[0-9a-f]{40}", value) for value in refs) and all(valid_sha(value) for value in SOURCE_PINS.values() if isinstance(value, str)) and valid_sha(CONTEXT_DIGEST) and valid_sha(FENCE_DIGEST) and valid_sha(PREREQUISITE_DIGEST) and valid_sha(HYDRATION_TRANSITION_DIGEST) and valid_sha(COORDINATION_LEDGER_DIGEST) and valid_sha(COORDINATION_PROJECTION_DIGEST) and valid_sha(FROZEN_S10_RESERVATION_DIGEST) and valid_sha(PRIOR_LEDGER_DIGEST)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(_HYDRATED_NEW_PATHS), len(PATH_FENCE), len(set(PATH_FENCE))) != (EXPECTED_EXISTING_PATH_COUNT, EXPECTED_NEW_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT):
        raise ValueError("C07 fence cardinality or uniqueness differs")
    if _HYDRATED_NEW_PATHS != NEW_PATHS or PATH_FENCE != EXISTING_PATHS + NEW_PATHS:
        raise ValueError("C07 new-path ordering differs from hydrated fence")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C07 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 7266 or UNAUTHORIZED_OVERLAP_COUNT != 0 or S10_RESERVATION_OVERLAP_COUNT != 0:
        raise ValueError("C07 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C07 app base tree differs")
    _candidate_identity(root)
    _assert_coordination_state()
    unauthorized = [path for path in observed_changed_paths(root) if path not in PATH_FENCE]
    if unauthorized:
        raise ValueError("C07 changed path outside fence:" + ",".join(unauthorized))
    missing_base = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C07 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C07 new path already exists at accepted base")


def selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[3]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C07(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", path.read_text(encoding="utf-8")))


def observed_selectors(root: Path) -> tuple[str, ...]:
    return selectors(root)


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    found = selectors(root)
    return {
        "requiredPathCount": len(IMPLEMENTATION_PATHS),
        "presentPathCount": len(present),
        "missingPathCount": len(missing),
        "presentPaths": present,
        "missingPaths": missing,
        "selectors": list(found),
        "hydrated": not missing,
        "sourceReady": not missing,
        "status": "SOURCE_READY" if not missing else "SOURCE_PENDING",
        "reason": "ALL_IMPLEMENTATION_SOURCE_LANES_PRESENT" if not missing else "IMPLEMENTATION_SOURCE_LANES_INCOMPLETE",
    }


def _assert_fixture_contract(fixture: dict[str, Any]) -> None:
    expected_selectors = [
        {"id": "G01", "selector": "V23-P04-C07-G01", "tier": "GOLDEN"},
        {"id": "A01", "selector": "V23-P04-C07-A01", "tier": "ALTERNATE"},
        {"id": "H01", "selector": "V23-P04-C07-H01", "tier": "HOSTILE"},
        {"id": "I01", "selector": "V23-P04-C07-I01", "tier": "INTERRUPTION"},
        {"id": "R01", "selector": "V23-P04-C07-R01", "tier": "RECOVERY"},
    ]
    if fixture.get("schema") != "V22P04C07RoundSessionFieldFlowCorpusV1" or fixture.get("schemaVersion") != 1 or fixture.get("cardID") != CARD or fixture.get("ordinal") != REGISTER_ORDINAL:
        raise ValueError("C07 fixture identity differs")
    if fixture.get("selectors") != expected_selectors:
        raise ValueError("C07 fixture selectors differ")
    expected_coverage = {
        "G01": ["multi-asset-happy-path", "selection-order", "complete-incomplete-flagged-parity", "jump-controls", "batch-handoff", "local-closeout-manifest"],
        "A01": ["applicable-pose-axis", "exact-c36-anchor", "back-kill-resume", "durable-ui-position", "out-of-order-permitted", "no-false-complete"],
        "H01": ["ui-source-disagreement", "inaccessible-blocks-closeout", "protected-data", "storage", "cancellation", "accessibility-truth"],
        "I01": ["effect-before-receipt", "journal-replay", "search-rebuild", "bounded-export", "no-orphans", "interruption-idempotence"],
        "R01": ["backup", "replace-restore", "clone", "fork", "import", "export", "report", "delete", "erase", "retention", "compatibility", "forward-fix", "recovery"],
    }
    if fixture.get("coverage") != expected_coverage:
        raise ValueError("C07 fixture coverage differs")
    required_lifecycle = {"BACKUP", "REPLACE_RESTORE", "CLONE", "FORK", "IMPORT", "EXPORT", "REPORT", "JOURNAL", "REPLAY", "SEARCH", "REBUILD", "DELETE", "ERASE", "RETENTION", "COMPATIBILITY", "FORWARD_FIX"}
    lifecycle = fixture.get("lifecycle")
    if not isinstance(lifecycle, list) or set(lifecycle) != required_lifecycle:
        raise ValueError("C07 fixture lifecycle inventory differs")
    required_forbidden = {"NETWORK", "QR", "RECURRENCE", "REMOTE_SYNC", "ROUTE_AUTOMATION"}
    if set(fixture.get("forbidden", ())) != required_forbidden:
        raise ValueError("C07 fixture forbidden set differs")
    if fixture.get("hostileCases") != ["inaccessible-item-blocks-closeout", "protected-data-unavailable", "storage-pressure", "ui-source-disagreement"]:
        raise ValueError("C07 fixture hostile cases differ")
    claims = fixture.get("claims")
    required_claims = (
        "accessibilityTruthRequired", "batchHandoffAndLocalCloseoutReconcile", "deleteRequiresInformedAction",
        "noFalseCompleteForOutOfOrderWork", "resumePreservesDurablePosition", "uiNeverLeadsCanonicalState",
    )
    if not isinstance(claims, dict) or any(claims.get(key) is not True for key in required_claims):
        raise ValueError("C07 fixture claims differ")
    status_flags = fixture.get("statusFlags")
    if not isinstance(status_flags, dict) or any(value is not False for value in status_flags.values()):
        raise ValueError("C07 fixture flags are not all false")


def _assert_no_forbidden_source_claims(source: str) -> None:
    # The corpus and integration assertions intentionally name forbidden
    # capabilities so that hostile coverage is auditable.  Scan executable
    # identifiers only; quoted data and comments are not product claims.
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    code = re.sub(r"//[^\n]*", "", code)
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.S)
    forbidden_patterns = (
        r"\bURLSession\b", r"\bURLRequest\b", r"\bCloudKit\b", r"\bCKContainer\b",
        r"\bNWConnection\b", r"\bWebSocket\b", r"\bTelemetryClient\b", r"\bCoreML\b",
        r"\b(?:remoteSync|syncProcessor|signedURL|prefetch|cacheDaemon)\b",
        r"\b(?:SwiftData|NSPersistentContainer|ModelContainer)\b", r"@Model\b",
        r"\b(?:providerOutbox|providerInbox|acknowledg(?:e|ement)|remoteEmail|remoteLink)\b",
        r"\b(?:QRCode|CIQRCodeGenerator|QRPayload|recurrence|dueQueue|teamDispatch)\b",
        r"\b(?:iPad|iPadOS|S10Route|S10_.*Route)\b",
    )
    for pattern in forbidden_patterns:
        if re.search(pattern, code, re.I):
            raise ValueError("C07 forbidden source claim:" + pattern)


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C07 source lanes missing:" + ",".join(status["missingPaths"]))
    view = _text(root, IMPLEMENTATION_PATHS[0])
    projection = _text(root, IMPLEMENTATION_PATHS[1])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[2])
    tests = _text(root, IMPLEMENTATION_PATHS[3])
    lifecycle = _text(root, SUPPORTING_SOURCE_PATHS[0])
    canonical_mutation = _text(root, SUPPORTING_SOURCE_PATHS[1])
    fixture = _json(root, IMPLEMENTATION_PATHS[4])
    fixture_text = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    _assert_fixture_contract(fixture)
    _require_patterns(view, (
        r"\bstruct\s+RoundSessionViewActionsV1\b", r"\bstruct\s+RoundSessionView\s*:\s*View\b",
        r"\bRoundSessionAccessibilityIDV1\b", r"\bForEach\s*\(\s*session\.items",
    ), "C07 RoundSession view declarations")
    _require_tokens(view, (
        "RoundSessionViewActionsV1", "openItem", "requestReorder", "jumpToNextIncomplete",
        "jumpToNextFlagged", "requestBatchHandoff", "requestRecovery", "preserveFieldPosition",
        "flushBeforeLeaving", "leaveAfterFlush", "RoundSessionV1", "readiness", "fieldPositionAnchor",
        "fieldSectionIndex", "fieldPositionRequirement", "batchHandoffStatus", "completed", "incomplete", "flagged", "closeout", "outOfOrder",
        "accessibilityIdentifier", "navigationTitle", "text(", "recovery", "handoff",
        "flushAndLeave", "readBack", "anchorReadbackMismatch", "anchorUnavailable", "projectedField",
        "packagePermitsOutOfOrderNavigation",
    ), "C07 RoundSession view")
    _require_patterns(view, (
        r"preserveFieldPosition\s*:\s*\(FieldPositionAnchorV1\)\s*async\s+throws\s*->\s*FieldPositionAnchorV1",
        r"if\s+let\s+fieldPositionAnchor",
        r"try\s+await\s+actions\.flushBeforeLeaving\(\)",
        r"try\s+await\s+actions\.preserveFieldPosition\(fieldPositionAnchor\)",
        r"guard\s+readBack\s*==\s*fieldPositionAnchor",
        r"fieldPositionRequirement\s*==\s*\.requiredForCurrentFieldFlow",
        r"let\s+permitsOutOfOrder\s*=\s*field\?\.packagePermitsOutOfOrderNavigation\s*==\s*true",
        r"\.disabled\(item\.order\s*==\s*0\s*\|\|\s*!permitsOutOfOrder\)",
        r"\.disabled\(item\.order\s*\+\s*1\s*==\s*session\.items\.count\s*\|\|\s*!permitsOutOfOrder\)",
    ), "C07 conditional anchor readback")
    _require_patterns(projection, (
        r"\b(?:enum|struct)\s+FieldSectionIndex(?:Projection|AnchorState|RequirementBinding|DraftAnchor|Field|Section)V1\b",
        r"\bFieldSectionIndexProjectionV1\b",
        r"struct\s+FieldSectionIndexProjectionV1\s*:\s*Equatable\s*,\s*Sendable",
        r"func\s+validate\(session\s+canonical:\s+RoundSessionV1\)",
        r"WorkspaceMutationCanonicalV1\.sha256\(Basis\(",
        r"projectionSHA256\s*=\s*digest",
    ), "C07 section projection declarations")
    projection_code = re.sub(r"//[^\n]*|/\*.*?\*/", "", projection, flags=re.S)
    if re.search(r"struct\s+FieldSectionIndexProjectionV1\s*:[^{\n]*\bCodable\b", projection_code):
        raise ValueError("C07 field section projection must remain non-Codable")
    _require_tokens(projection, (
        "RoundSessionV1", "FieldPositionAnchorV1", "DraftResumeAnchorV1", "FieldSectionIndexOutOfOrderPermissionV1",
        "requirementBindings", "draftAnchors", "packagePermissions", "packageReleaseID", "packageSHA256",
        "workflowSHA256", "permitsOutOfOrderNavigation", "nextIncomplete", "nextFlagged",
        "staleRequirementFallback", "incomplete", "flagged", "completeCount", "incompleteCount",
        "flaggedCount", "inconsistentCounts", "grouped", "sections", "requirementSHA256", "p.packageReleaseID",
        "p.packageSHA256", "p.workflowSHA256", "item.requirement.packageRelease",
    ), "C07 section projection")
    _require_patterns(projection, (
        r"packagePermissions\.count\s*==\s*session\.items\.count",
        r"Set\(packagePermissions\.map",
        r"p\.packageReleaseID\s*==\s*item\.requirement\.packageRelease\.packageReleaseID",
        r"p\.packageSHA256\s*==\s*item\.requirement\.packageRelease\.packageSHA256",
        r"p\.workflowSHA256\s*==\s*item\.requirement\.packageRelease\.workflowSHA256",
        r"bindings\.map.*hash:\s*\$0\.requirementSHA256",
        r"permissions\.map.*releaseID:\s*\$0\.packageReleaseID",
        r"sections\.map.*complete",
    ), "C07 exact package/workflow permission and digest basis")
    _require_tokens(canonical_mutation, (
        "enum WorkspaceMutationCanonicalV1", "static func data", "static func sha256",
        "JSONEncoder", "sortedKeys", "withoutEscapingSlashes", "millisecondsSince1970",
    ), "C07 canonical mutation digest")
    _require_patterns(canonical_mutation, (
        r"static\s+func\s+sha256\s*<T:\s*Encodable>\s*\(_\s*value:\s*T\)",
        r"SHA256\.hash\(data:\s*try\s+data\(value\)\)",
    ), "C07 exhaustive canonical mutation digest")
    lifecycle_methods = (
        "progress", "closeout", "searchProjection", "recoverProgress", "recoverCloseout",
        "save", "rebuildSearch", "fieldSectionIndex", "handoffManifest", "deletePreview",
        "recoverSearch", "recoverHandoff", "lifecycleEvidence",
    )
    for method in lifecycle_methods:
        _require_patterns(lifecycle, (rf"\bfunc\s+{method}\s*\(",), "C07 lifecycle adapter method")
    if lifecycle.count("validateCurrentFrontier") < 11:
        raise ValueError("C07 lifecycle adapter does not validate every current-frontier derivative")
    _require_tokens(lifecycle, (
        "RoundSessionLifecycleAdapterV1", "C07RoundSessionPostCommitResultV1", "roundCoordinator.save",
        "try receipt.validate()", "SearchIndexLifecyclePortV1", "invalidateAfterCanonicalCommit",
        "searchDisposition = .reconciled", "searchDisposition = .rebuildRequired", "catch",
        "C07RoundSessionSearchPostCommitDispositionV1", "C07RoundSessionDeletePreviewV1",
        "C07RoundSessionHandoffManifestV1", "C07RoundSessionLifecycleEvidenceV1",
        "ordinaryDisposition", "workspaceEraseOnly", "preserveCanonicalHistory",
    ), "C07 lifecycle adapter receipt and recovery truth")
    _require_patterns(lifecycle, (
        r"let\s+receipt\s*=\s*try\s+roundCoordinator\.save\(mutation\)",
        r"try\s+await\s+searchLifecycle\.invalidateAfterCanonicalCommit\(.*?catch\s*\{.*?searchDisposition\s*=\s*\.rebuildRequired",
        r"func\s+reconciledCloseout[\s\S]*session\.state\s*==\s*\.completed",
    ), "C07 post-commit and closeout truth")
    found = selectors(root)
    if len(found) != 5 or tuple(name[len("testV23P04C07"):len("testV23P04C07") + 3] for name in found) != SELECTOR_SUFFIXES or len(set(found)) != 5:
        raise ValueError("C07 requires exactly five ordered G/A/H/I/R selectors")
    combined_tests = "\n".join((view, projection, ui_tests, tests, fixture_text))
    _require_tokens(combined_tests, (
        "RoundSession", "multi", "selection-order", "completed", "incomplete", "flagged", "section", "position",
        "kill", "resume", "inaccessible", "closeout", "search", "export", "delete", "recovery",
        "accessibility", "XCTAssert", "receipt", "digest", "permission", "staleRevision",
    ), "C07 RoundSession integration evidence")
    _require_tokens(tests, (
        "Writer", "ReceiptWriter", "FailingSearch", "XCTAssertThrowsError", "inaccessibleHistory",
        "recoverProgress", "recoverCloseout", "recoverSearch", "recoverHandoff", "lifecycleEvidence",
        "String(repeating:\"f\",count:64)", "XCTAssertNotEqual", "rebuildRequired",
        "searchDisposition", "writer.commits",
    ), "C07 real G/A/H/I/R integration evidence")
    _require_patterns(tests, (
        r"func\s+testV23P04C07(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*\s*\(",
        r"Writer:.*staleRevision",
        r"receipt\s*=\s*try\s+makeReceipt",
        r"\.rebuildRequired",
        r"XCTAssertNotEqual\(i\.projectionSHA256",
        r"XCTAssertThrowsError\(try\s+a\.closeout",
        r"XCTAssertEqual\(try\s+a\.recover(?:Progress|Closeout|Search|Handoff)",
    ), "C07 integration failure/recovery and digest perturbation evidence")
    _require_tokens(ui_tests, (
        CARD, "adoptionEnabled", "acceptanceCredit", "XCTSkip", "S10.6",
    ), "C07 UI deferral test")
    source = "\n".join((view, projection, ui_tests, tests, fixture_text))
    _assert_no_forbidden_source_claims(source)
    return found


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": REGISTER_ORDINAL,
        "title": TITLE,
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "candidateHead": CANDIDATE_HEAD,
        "candidateTree": CANDIDATE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationOriginHead": COORDINATION_ORIGIN_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationSequence": SEQUENCE,
        "coordinationCASSequence": SEQUENCE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "prerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "priorLedgerDigest": PRIOR_LEDGER_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "sourcePins": dict(SOURCE_PINS),
        "directPrerequisiteCards": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT,
        "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "existingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "newPathCount": EXPECTED_NEW_PATH_COUNT,
        "fencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "finalHashesSealed": FINAL_HASHES_SEALED,
    }


def common() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "title": TITLE,
        "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "statusFlags": dict(FLAGS),
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "releaseCredit": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "requiresAcceptedS10_6Reconciliation": True,
        "uiAdoptionSkipped": True,
        "uiAcceptanceCredit": False,
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "provisional": not FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in IMPLEMENTATION_PATHS:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            rows.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SOURCE_PRESENT"})
        else:
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
    return rows


def supporting_source_rows(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in SUPPORTING_SOURCE_PATHS:
        target = root / path
        if not target.is_file():
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SUPPORTING_SOURCE"})
            continue
        data = canonical_file_bytes(target)
        rows.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "PRESENT_SUPPORTING_SOURCE"})
    return rows


def source_projection(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {
        "implementationPaths": list(IMPLEMENTATION_PATHS),
        "presentPaths": status["presentPaths"],
        "missingPaths": status["missingPaths"],
        "selectors": list(selectors_value),
        "sourceSemanticsInspected": bool(status["hydrated"]),
        "sourceReady": status["sourceReady"],
        "sourceStatus": status["status"],
        "sourceReason": status["reason"],
        "sourceRows": source_rows(root),
        "supportingSourcePaths": list(SUPPORTING_SOURCE_PATHS),
        "supportingSourceRows": supporting_source_rows(root),
        **SOURCE_PINS,
        "canonicalSuccessor": {"cardID": "V23-P04-C08", "registerOrdinal": 96},
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS),
        "conformanceSubjects": list(CONFORMANCE_SUBJECTS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
    }


def semantics(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {
        **SEMANTIC_SCOPE,
        "counts": list(COUNTS),
        "dispositions": list(DISPOSITIONS),
        "sessionStates": list(SESSION_STATES),
        "transitions": list(TRANSITIONS),
        "anchorStates": list(ANCHOR_STATES),
        "selectors": list(selectors_value),
        "evidenceIDs": list(EVIDENCE_IDS),
        "stateMachine": {
            "orderedItems": True,
            "packagePermittedOutOfOrder": True,
            "terminalDispositions": ["COMPLETED", "INACCESSIBLE", "SKIPPED", "DEFERRED"],
            "inaccessibleReasonsAreVisible": True,
            "closeoutRequiresAllExpectedItemsDispositioned": True,
            "uiNeverAdvancesAheadOfDurableState": True,
        },
        "sectionPosition": {
            "projection": "FieldSectionIndexProjectionV1",
            "anchor": "FieldPositionAnchorV1",
            "requirementBinding": "REQUIREMENT_SHA256",
            "changedRequirement": "STALE_REQUIREMENT_FALLBACK",
            "draftAnchor": "DraftResumeAnchorV1",
            "preserveAcrossBackKillResume": True,
            "routeContainsNoUserTextOrValue": True,
        },
        "countsAndJump": {
            "complete": "COMPLETED+INACCESSIBLE+SKIPPED+DEFERRED",
            "incomplete": "EXPECTED-COMPLETE",
            "flagged": "INACCESSIBLE+DEFERRED",
            "jumpToNextIncomplete": True,
            "jumpToNextFlagged": True,
        },
        "searchExportDeleteRecovery": {
            "searchIndex": "BOUNDED_EXTENSION_AND_DETERMINISTIC_REBUILD",
            "export": "BATCH_HANDOFF_RECONCILES_TO_CLOSEOUT",
            "delete": "EXPLICIT_RECOVERY_UX_PRESERVES_IMMUTABLE_HISTORY",
            "recovery": "DISABLE_NEW_ENTRY_PRESERVE_READ_EXPORT_RECOVERY",
            "orphanFree": True,
        },
        "closeout": {
            "requiresEveryExpectedItemDispositioned": True,
            "inaccessibleBlocksUntilExplicitDisposition": True,
            "completedRecordsAndExportsReconcile": True,
        },
        "sourceContractProof": {
            "fieldSectionIndexPersistence": "NONPERSISTENT_NON_CODABLE_DERIVED_ONLY",
            "fieldSectionIndexValidation": "validate(session: RoundSessionV1)",
            "packageWorkflowPermissionRows": [
                "itemID", "packageReleaseID", "packageSHA256", "workflowSHA256",
                "permitsOutOfOrderNavigation",
            ],
            "packageWorkflowPermissionGating": "EXACT_RELEASE_PACKAGE_AND_WORKFLOW_HASHES_PER_ITEM",
            "projectionDigest": "EXHAUSTIVE_WORKSPACE_MUTATION_CANONICAL_V1_BASIS",
            "projectionDigestInputs": [
                "session", "requirementBindings", "draftAnchors", "packagePermissions",
                "sections", "completeCount", "incompleteCount", "flaggedCount",
            ],
            "currentFrontierValidation": "ALL_SEARCH_CLOSEOUT_HANDOFF_DELETE_RECOVERY_LIFECYCLE_DERIVATIVES",
            "postCommitSearchFailure": "CANONICAL_RECEIPT_PRESERVED_REBUILD_REQUIRED",
            "uiBackFlow": "FLUSH_THEN_CONDITIONAL_REQUIRED_ANCHOR_READBACK",
            "digestPerturbationEvidence": True,
        },
        "lifecycle": list(LIFECYCLE),
        "forbiddenCapabilities": list(FORBIDDEN),
        "noNativeIPad": True,
        "noS10RouteWiring": True,
        "noProviderOrNotificationClaim": True,
        "noRecurrenceOrQRClaim": True,
        "accessibilityAndLocalization": {
            "dynamicType": True,
            "voiceOver": True,
            "voiceControl": True,
            "switchControl": True,
            "keyboardAndErrorFocus": True,
            "contrastAndNonColor": True,
            "reduceMotion": True,
            "localeAndRTL": True,
            "offlineAndPermissionOutcomesTruthful": True,
        },
        "ui": "POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT",
    }


def schema_document(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    sem = semantics(selectors_value)
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/round-session-field-flow.schema.json",
        "title": "V23-P04-C07 RoundSession field flow",
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "ROUND_SESSION_FIELD_FLOW_V1"},
            "schemaVersion": {"const": SCHEMA_VERSION},
            "cardID": {"const": CARD},
            "ordinal": {"const": REGISTER_ORDINAL},
            "selectors": {"const": list(selectors_value)},
            "counts": {"const": list(COUNTS)},
            "dispositions": {"const": list(DISPOSITIONS)},
            "sessionStates": {"const": list(SESSION_STATES)},
            "transitions": {"const": list(TRANSITIONS)},
            "lifecycle": {"const": list(LIFECYCLE)},
            "forbidden": {"const": list(FORBIDDEN)},
            "semantics": {"const": sem},
            "sourceReady": {"type": "boolean"},
            "physicalLockedState": {"const": "REQUIRED_PENDING_OWNER"},
            "uiAdoptionSkipped": {"const": True},
            "uiAcceptanceCredit": {"const": False},
            "statusFlags": {"const": dict(FLAGS)},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED},
            "provisional": {"const": not FINAL_HASHES_SEALED},
        },
        "required": [
            "schema", "schemaVersion", "cardID", "ordinal", "selectors", "counts", "dispositions",
            "sessionStates", "transitions", "lifecycle", "forbidden", "semantics", "sourceReady",
            "physicalLockedState", "uiAdoptionSkipped", "uiAcceptanceCredit", "statusFlags",
            "finalHashesSealed", "provisional",
        ],
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None}


def _provider_artifacts(root: Path) -> list[dict[str, Any]]:
    provider_paths = (
        "FieldEvidenceApp/Domain/Rounds/RoundSessionContractsV1.swift",
        "FieldEvidenceApp/Domain/Models/RoundSessionPersistenceModelsV1.swift",
        "FieldEvidenceApp/Application/Rounds/RoundSessionCoordinatorV1.swift",
        "FieldEvidenceApp/Infrastructure/Rounds/RoundSessionLifecycleAdapterV1.swift",
        "Scripts/v23/p04_c05_contracts.py",
        "Scripts/v23/round-session.schema.json",
        "docs/design/v23/tooling/V23P04C05RoundSessionContractV1.json",
        "docs/design/v23/tooling/V23P04C05RoundSessionEvidenceReceiptV1.json",
        "docs/design/v23/tooling/V23P04C05BrandImpactManifestV1.json",
        "docs/design/v23/tooling/V23-P04-C05-tooling-manifest.json",
    )
    files: list[dict[str, Any]] = []
    for path in provider_paths:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            files.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "PRESENT_PROVIDER"})
        else:
            files.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_PROVIDER"})
    return [{
        "providerCardID": "V23-P04-C05",
        "required": True,
        "capability": "ROUND_SESSION_CANONICAL_PERSISTENCE_SEARCH_EXPORT_DELETE_AND_RECOVERY",
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "checkpointDigest": DIRECT_PREREQUISITE_ROWS[0]["checkpointDigest"],
        "contextDigest": DIRECT_PREREQUISITE_ROWS[0]["contextDigest"],
        "pathFenceDigest": DIRECT_PREREQUISITE_ROWS[0]["pathFenceDigest"],
        "verificationReceiptDigest": DIRECT_PREREQUISITE_ROWS[0]["verificationReceiptDigest"],
        "contracts": ["RoundSessionV1", "RoundSessionReferenceV1", "RoundSessionCanonicalCodecV1", "RoundSessionCloseoutReportProjectionV1", "RoundSessionSearchProjectionV1"],
        "paths": list(provider_paths),
        "files": files,
        "allFilesPresent": all(item["sha256"] is not None for item in files),
        "fallback": None,
    }]


def contract_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C07RoundSessionFieldFlowContractV1",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "contractRefs": list(CONTRACT_REFS),
        "journeyRefs": list(JOURNEY_REFS),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "semantics": semantics(selectors_value),
        "sourceProjection": source_projection(root, selectors_value),
        "providerArtifacts": _provider_artifacts(root),
    })


def evidence_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {
            "evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "selectorSuffix": "G01",
            "focus": ["multi-asset selection and deterministic ordering", "complete/incomplete/flagged counts", "next-incomplete and next-flagged navigation", "package-permitted out-of-order work", "section and field position anchors"],
            "expectedOutcome": "MULTI_ASSET_FLOW_RECONCILES_TO_DURABLE_ROUND_SESSION",
        },
        {
            "evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "selectorSuffix": "A01",
            "focus": ["kill and relaunch through UI transitions", "draft position and C36 anchor survive resume", "back flushes before leaving", "accessible non-color interruption outcomes"],
            "expectedOutcome": "DETERMINISTIC_RESUME_OR_VISIBLE_SAVE_BLOCK",
        },
        {
            "evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "selectorSuffix": "H01",
            "focus": ["resume loses position", "UI/source disagreement", "inaccessible item and closeout", "delete/search/export orphan detection", "forbidden account/network/QR/recurrence/notification/provider/S10/native-iPad scope"],
            "expectedOutcome": "FAIL_CLOSED_WITH_NO_ORPHAN_OR_FALSE_COMPLETE",
        },
        {
            "evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "selectorSuffix": "I01",
            "focus": ["durable transition interruption", "cancel/kill/relaunch at section and back boundaries", "flush-before-leave recovery", "idempotent continuation or visible failure"],
            "expectedOutcome": "DETERMINISTIC_CONTINUATION_OR_FAIL_CLOSED",
        },
        {
            "evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "selectorSuffix": "R01",
            "focus": ["disable new session UI entry", "preserve read/export/recovery of existing sessions", "batch closeout reconciles completed records and exports", "delete recovery preserves history"],
            "expectedOutcome": "RECOVERY_PRESERVES_CANONICAL_SESSION_AND_HISTORY",
        },
    ]
    return _sealed({
        "schema": "V23P04C07RoundSessionFieldFlowEvidenceReceiptV1",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(selectors_value),
        "cases": cases,
        "counts": list(COUNTS),
        "dispositions": list(DISPOSITIONS),
        "sessionStates": list(SESSION_STATES),
        "transitions": list(TRANSITIONS),
        "lifecycle": list(LIFECYCLE),
        "hostileVectors": list(HOSTILE_VECTORS),
        "forbidden": list(FORBIDDEN),
        "semantics": semantics(selectors_value),
        "preservesCanonicalRoundSessionAndImmutableHistory": True,
        "batchCloseoutReconciliationRequired": True,
        "uiAdoptionSkipped": True,
        "accessibilityAndLocalizationRequired": True,
        "sourceProjection": source_projection(root, selectors_value),
        "providerArtifacts": _provider_artifacts(root),
    })


def brand_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    source = source_status(root)
    return _sealed({
        "schema": "V23P04C07BrandImpactManifestV1",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "iPhoneNativeOnly": True,
        "nativeIPadSurface": False,
        "uiSurfaceDelta": True,
        "brandSurfaceDelta": True,
        "uiSourceExists": IMPLEMENTATION_PATHS[0] in source["presentPaths"],
        "uiTestSourceExists": IMPLEMENTATION_PATHS[2] in source["presentPaths"],
        "uiTestDisposition": "EXPLICIT_POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_AUTHORITY",
        "adoptionSkipped": True,
        "uiAdoptionSkipped": True,
        "uiAcceptanceCredit": False,
        "onDeviceOnly": True,
        "networkOrTelemetryFlow": False,
        "syncStatusClaimed": False,
        "providerOrNotificationFlow": False,
        "recurrenceOrQRFlow": False,
        "accessibilityAndLocalizationRequired": True,
        "accessibilitySourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not source["hydrated"] else "SOURCE_INSPECTED",
        "localizationSourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not source["hydrated"] else "SOURCE_INSPECTED",
        "changedSurfaces": ["ROUND_SESSION", "FIELD_SECTION_INDEX", "BATCH_HANDOFF", "LOCAL_CLOSEOUT", "DELETE_RECOVERY"],
        "changedStates": list(SESSION_STATES),
        "semantics": semantics(selectors_value),
        "sourceProjection": source_projection(root, selectors_value),
    })


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {
            "path": path,
            "byteCount": len(data),
            "sha256": sha256_bytes(data) if FINAL_HASHES_SEALED else None,
            "status": "SEALED_TOOLING" if FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING",
        }
    target = root / path
    if not target.is_file():
        return {"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"}
    data = canonical_file_bytes(target)
    return {
        "path": path,
        "byteCount": len(data),
        "sha256": sha256_bytes(data),
        "status": "PRESENT_SOURCE" if path in IMPLEMENTATION_PATHS else "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS and FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING" if path in TOOLING_EDIT_PATHS else "PRESENT_INHERITED",
    }


def outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    status = source_status(root)
    selectors_value = assert_source_contracts(root) if status["hydrated"] else observed_selectors(root)
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: pretty(schema_document(selectors_value)),
        CONTRACT_PATH: pretty(contract_document(root, selectors_value)),
        EVIDENCE_PATH: pretty(evidence_document(root, selectors_value)),
        BRAND_PATH: pretty(brand_document(root, selectors_value)),
    }
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = {
        "schema": "V23-P04-C07-tooling-manifest",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "pathFence": list(PATH_FENCE),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW_PATHS),
        "toolingEditPaths": list(TOOLING_EDIT_PATHS),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "fencePathCount": len(PATH_FENCE),
        "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED",
        "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None,
        "sourceReady": status["sourceReady"],
        "sourceStatus": status["status"],
        "sourceReason": status["reason"],
        "sourceProjection": source_projection(root, selectors_value),
        "providerArtifacts": _provider_artifacts(root),
        "files": rows,
    }
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
    print(json.dumps({
        "cardID": CARD,
        "sourceReady": status["sourceReady"],
        "sourceStatus": status["status"],
        "sourceReason": status["reason"],
        "sourceMissing": status["missingPaths"],
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "fencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "newPathCount": EXPECTED_NEW_PATH_COUNT,
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
    }, sort_keys=True, indent=2))
