#!/usr/bin/env python3
"""Fail-closed static tooling contracts for V23-P04-C06.

The card owns only its contract, evidence, brand, schema, and inventory
tooling.  Product source lanes are deliberately observed rather than
fabricated: until all seven implementation paths are present, generated
artifacts remain deterministic but provisional and unsealed.
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
CARD = "V23-P04-C06"
TITLE = "OfflineReadinessManifestV1 and cold-launch field preflight"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 94

# Immutable app and coordination hydration authority.
BASE_HEAD = "37e5781e15fa84524da50049a7b16c1eda363c0c"
BASE_TREE = "7b69ccbb2e3a4d2ef3feffb66315682efe190a70"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "d01217e77f87f85861a20948a4840864e90bc57d"
COORDINATION_TREE = "8ebd74ebeab9176215e6f670c3360d55e1202921"
COORDINATION_ORIGIN_HEAD = COORDINATION_HEAD
COORDINATION_CAS_SEQUENCE = 410
SEQUENCE = COORDINATION_CAS_SEQUENCE
HYDRATION_REVISION = 1
CONTEXT_DIGEST = "f80df4adf42c3392e5639f6c65164c925f175567cc027811f905d6981e243bad"
FENCE_DIGEST = "67a33ce68a08b9614e00d3e274f87b21126d72cd9be24bf0d6fd9482d1f710a6"
PREREQUISITE_DIGEST = "3f7da1ca598dffebed74d46068dbc7027c71941c3067ec4136f4ba8787efa472"
HYDRATION_TRANSITION_DIGEST = "90618a5c1395cea5bed69fb75c55ea24cdefe8a3d180e5c4067f99295384a366"
COORDINATION_LEDGER_DIGEST = "172c6ad1b3875868a33283c73120764b36527708aa208729e57d958f9e6046ab"
COORDINATION_PROJECTION_DIGEST = "df19d07ce3c9e62c3eda4b3400953d5ca8ef8f4c6be869af58ea419c7b4822ec"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
PRIOR_LEDGER_DIGEST = "098a0c5ae78872a5fe4f896325bc311f0ceb24e92c25d19a1290d360d02089b0"

# These are the source pins materialized by the C06 hydration controller.
# They are authority inputs, not a permission to edit planning documents.
SOURCE_PINS = {
    "dossierUTF8Length": 7216,
    "dossierSHA256": "cc114b26912213522bcd8f3d817d21ae61659a196286e141366cffe8e1cd37d6",
    "inheritedV21BlockUTF8Length": 8195,
    "inheritedV21BlockSHA256": "014ecb54b52e78b8404d3db9b83ff5868205bd92b5ac1d097793c90bef881c19",
    "registerRowUTF8Length": 255,
    "registerRowSHA256": "da94d087d0eddf3347d64d65e77bb5ba10706a85d599926303c90cebcdbe1c49",
    "registerSectionUTF8Length": 44217,
    "registerSectionSHA256": "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5",
}
DOSSIER_SHA256 = SOURCE_PINS["dossierSHA256"]
DOSSIER_BYTES = SOURCE_PINS["dossierUTF8Length"]
INHERITED_V21_BLOCK_SHA256 = SOURCE_PINS["inheritedV21BlockSHA256"]
INHERITED_V21_BLOCK_BYTES = SOURCE_PINS["inheritedV21BlockUTF8Length"]
REGISTER_ROW_SHA256 = SOURCE_PINS["registerRowSHA256"]
REGISTER_ROW_BYTES = SOURCE_PINS["registerRowUTF8Length"]
REGISTER_SECTION_SHA256 = SOURCE_PINS["registerSectionSHA256"]
REGISTER_SECTION_BYTES = SOURCE_PINS["registerSectionUTF8Length"]

EXPECTED_EXISTING_PATH_COUNT = 347
EXPECTED_NEW_PATH_COUNT = 15
EXPECTED_FENCE_PATH_COUNT = 362
AUTHORIZED_OVERLAP_COUNT = 6904
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 94
PRIOR_OWNED_PATH_COUNT = 1487
S10_RESERVED_PATH_COUNT = 86

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/OfflineReadiness/OfflineReadinessManifestContractsV1.swift",
    "FieldEvidenceApp/Application/Rounds/OfflineReadinessPreflightCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/OfflineReadiness/OfflineReadinessManifestBuilderV1.swift",
    "FieldEvidenceApp/Features/Rounds/OfflineReadinessPreflightView.swift",
    "FieldEvidenceAppTests/V9_71OfflineReadinessManifestTests.swift",
    "FieldEvidenceAppUITests/V23_P04_C06OfflineReadinessPreflightUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/OfflineReadiness/V22P04C06OfflineReadinessManifestCorpusV1.json",
)
SCHEMA_PATH = "Scripts/v23/offline-readiness-manifest.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C06OfflineReadinessManifestContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C06OfflineReadinessEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C06BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C06-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c06_contracts.py",
    "Scripts/v23/generate_p04_c06_contracts.py",
    "Scripts/v23/verify_p04_c06_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
OUTPUT_PATHS = GENERATED_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C06-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C06-attempt-1/BootstrapPathFenceV1.json"
_PREREQUISITE_RELATIVE = "receipts/V23-P04-C05-to-V23-P04-C06-provisional-prerequisite.json"
_TRANSITION_RELATIVE = "transitions/000410-V23-P04-C06-attempt-1-NOT_STARTED-to-HYDRATING.json"
_LEDGER_RELATIVE = "state/BootstrapExecutionLedgerEnvelopeV1.json"
_PROJECTION_RELATIVE = "projections/ActiveWorkSetProjectionV1.json"

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
JOURNEY_REFS = ("CommonTaskJourneyReleaseV2",)
DIRECT_PREREQUISITES = ("V23-P04-C05",)
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
AGGREGATE_MEMBERSHIPS = (
    "AutonomousRequiredAcceptedSetV1",
    "P04ShippingSurfaceSetV1",
    "P04BrandClosureSetV1",
)
CONFORMANCE_SUBJECTS = ("P04ShippingSurfaceSetV1", "CommonTaskJourneyReleaseV2")
INVALIDATION_CONSUMERS = (
    "V23-P04-C07",
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C06).CONTRACTS",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)

REQUIREMENTS = (
    "PACKAGE",
    "GUIDANCE",
    "REFERENCE",
    "ASSET",
    "STORAGE",
    "PROTECTED_DATA",
    "CLOCK",
)
REQUIREMENT_CATEGORIES = (
    "PACKAGE",
    "SELECTED_ASSET",
    "GUIDANCE",
    "FIELD_REFERENCE",
    "CONTENT",
    "PROTECTION",
    "STORAGE",
    "CLOCK",
    "BINDING",
)
REQUIREMENT_STATES = (
    "SATISFIED",
    "MISSING",
    "CORRUPT",
    "PARTIAL",
    "WRONG_WORKSPACE",
    "PROTECTED_DATA_UNAVAILABLE",
    "CAPACITY_UNAVAILABLE",
    "INSUFFICIENT_CAPACITY",
    "UNCHECKABLE",
    "MISMATCH",
    "STALE",
)
REMEDIATIONS = (
    "REBUILD_PREFLIGHT",
    "RESTORE_EXACT_PACKAGE",
    "RESELECT_ASSETS",
    "RESTORE_GUIDANCE",
    "RESTORE_FIELD_REFERENCE",
    "RESTORE_EXACT_CONTENT",
    "UNLOCK_PROTECTED_DATA",
    "FREE_STORAGE",
    "CHECK_STORAGE_AGAIN",
    "CHECK_CLOCK_AND_TIME_ZONE",
)
MANUAL_FALLBACKS = (
    "DO_NOT_START",
    "DEFER_FIELD_WORK",
    "USE_APPROVED_MANUAL_PROCEDURE",
    "CONTACT_SUPERVISOR",
)
READINESS_STATUSES = ("READY", "BLOCKED", "WARNING", "STALE")
READINESS_REASONS = (
    "PACKAGE_MISMATCH",
    "SELECTED_ASSET_MISMATCH",
    "GUIDANCE_REFERENCE_MISMATCH",
    "FIELD_REFERENCE_UNAVAILABLE",
    "MISSING_MANDATORY_CONTENT",
    "MISSING_OPTIONAL_CONTENT",
    "CORRUPT_MANDATORY_CONTENT",
    "CORRUPT_OPTIONAL_CONTENT",
    "PARTIAL_MANDATORY_CONTENT",
    "PARTIAL_OPTIONAL_CONTENT",
    "WRONG_WORKSPACE_CONTENT",
    "PROTECTED_DATA_UNAVAILABLE",
    "STORAGE_UNCHECKABLE",
    "INSUFFICIENT_STORAGE",
    "STORAGE_ARITHMETIC_OVERFLOW",
    "CLOCK_UNCHECKABLE",
    "CLOCK_OR_TIME_ZONE_CHANGED",
    "SOURCE_BINDING_DRIFT",
)
STATUS_REASON_MATRIX = {
    "READY": (),
    "BLOCKED": (
        "PACKAGE_MISMATCH",
        "SELECTED_ASSET_MISMATCH",
        "GUIDANCE_REFERENCE_MISMATCH",
        "FIELD_REFERENCE_UNAVAILABLE",
        "MISSING_MANDATORY_CONTENT",
        "CORRUPT_MANDATORY_CONTENT",
        "PARTIAL_MANDATORY_CONTENT",
        "WRONG_WORKSPACE_CONTENT",
        "PROTECTED_DATA_UNAVAILABLE",
        "STORAGE_UNCHECKABLE",
        "INSUFFICIENT_STORAGE",
        "STORAGE_ARITHMETIC_OVERFLOW",
        "CLOCK_UNCHECKABLE",
    ),
    "WARNING": ("MISSING_OPTIONAL_CONTENT", "CORRUPT_OPTIONAL_CONTENT", "PARTIAL_OPTIONAL_CONTENT"),
    "STALE": ("CLOCK_OR_TIME_ZONE_CHANGED", "SOURCE_BINDING_DRIFT"),
}
FAILURE_COVERAGE = (
    "COLD_LAUNCH",
    "REBOOT",
    "TERMINATION",
    "PROTECTED_DATA",
    "MISSING_OR_CORRUPT_CONTENT",
    "LOW_STORAGE",
    "CLOCK_OR_TIME_ZONE",
)
FORBIDDEN_CAPABILITIES = (
    "NETWORK",
    "ACCOUNT",
    "SYNC",
    "PREFETCH",
    "CACHE_DAEMON",
    "UI_SYNC_CLAIM",
    "REMOTE_UPLOAD_OR_STATUS",
    "PERSISTENT_ROW",
    "CARD_LOCAL_STORE",
    "CARD_LOCAL_WRITER",
)
LIFECYCLE_COVERAGE = (
    "SCHEMA_VERSION",
    "WRITER_QUERY",
    "MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK",
    "IMPORT_EXPORT",
    "JOURNAL_REPLAY",
    "SEARCH_REBUILD",
    "REPORT_PROJECTION",
    "DELETE_ERASE",
    "RETENTION",
    "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX",
    "INTERRUPTION",
    "IDEMPOTENT_RECEIPTS",
)

# Source lanes are frozen and the root-directed final seal is authorized.
FINAL_HASHES_SEALED = True

FLAGS = {name: False for name in (
    "activation",
    "native",
    "hosted",
    "adoption",
    "acceptance",
    "release",
    "nativeAcceptance",
    "hostedAcceptance",
    "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

SEMANTIC_SCOPE = {
    "persistentContractMode": "DERIVED_ONLY",
    "schemaVersion": "OFFLINE_READINESS_V1",
    "canonicalReadinessRow": False,
    "migrationRequired": False,
    "backupRestoreRequired": False,
    "deleteEraseRequired": False,
    "exportReportRequired": False,
    "downgradePolicy": "DROP_AND_REBUILD",
    "bindings": [
        "ROUND_SESSION_REVISION",
        "PACKAGE_VERSION_AND_HASH",
        "ASSET_SET",
        "GUIDANCE_REFERENCE_IDS",
        "CONTENT_REFERENCE_HASHES",
        "STORAGE_BUDGET",
        "PROTECTION_STATE",
    ],
    "states": list(READINESS_STATUSES),
    "failureCoverage": list(FAILURE_COVERAGE),
    "forbidden": ["NETWORK", "ACCOUNT", "SYNC", "PREFETCH", "CACHE_DAEMON", "UI_SYNC_CLAIM", "REMOTE_UPLOAD_OR_STATUS"],
    "rebuild": "DETERMINISTIC_INVALIDATION_AND_REBUILD",
}

DIRECT_PREREQUISITE_ROWS = (
    {
        "attemptID": 1,
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "cardID": "V23-P04-C05",
        "checkpointDigest": "8edb487c30b1468d182a5720345a9f83cad24cacb7d7dd71b2c692526ecf8587",
        "contextDigest": "0da6087d34e3145e7516435c5458bae772f288c7646b70c941f0a905d0694667",
        "disposition": "CHECKPOINTED_CANONICAL_DIRECT_PREREQUISITE",
        "pathFenceDigest": "1bf82731526fa55f0f91c53f30a38cea7b246ef1c23ee93c7e4cb1c7398bab31",
        "verificationReceiptDigest": "f8b13e1b1dc58e2c28f9fe3dd8e305683e6ae050b0dac86c15146c5cf3fbc24e",
    },
)

_CANONICAL_TEXT_SUFFIXES = frozenset({
    ".csv", ".entitlements", ".json", ".md", ".pbxproj", ".plist", ".ps1",
    ".py", ".sh", ".strings", ".swift", ".toml", ".txt", ".xcstrings",
    ".xcscheme", ".yaml", ".yml",
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


def sha(value: bytes) -> str:
    return sha256_bytes(value)


def valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def canonical_file_bytes(path: Path) -> bytes:
    data = path.read_bytes()
    if path.suffix.lower() in _CANONICAL_TEXT_SUFFIXES:
        return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data


def file_bytes(path: Path) -> bytes:
    return canonical_file_bytes(path)


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def git(root: Path, *args: str) -> str:
    return _git(root, *args)


def _coordination_root() -> Path:
    candidates = (Path(r"C:\AssetRounds-v23-coordination"), ROOT.parent / "AssetRounds-v23-coordination")
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C06 coordination fence is unavailable")


def coord() -> Path:
    return _coordination_root()


def _normalized_json_bytes(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ValueError("C06 coordination input is unavailable:" + relative)
    value = json.loads(_normalized_json_bytes(path), object_pairs_hook=strict)
    if not isinstance(value, dict):
        raise ValueError("C06 coordination object required:" + relative)
    return value


def cjson(relative: str) -> dict[str, Any]:
    return _coordination_json(relative)


def sealed_field(value: dict[str, Any], field: str) -> str:
    unsigned = {key: item for key, item in value.items() if key != field}
    return sha256_bytes((json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def _sealed_field(value: dict[str, Any], field: str) -> str:
    return sealed_field(value, field)


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C06 context digest/card mismatch")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST:
        raise ValueError("C06 path fence digest/card mismatch")
    if sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C06 context seal differs")
    if sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ValueError("C06 fence seal differs")
    existing = tuple(context.get("existingPaths", ()))
    fenced_existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(context.get("newPaths", ()))
    fenced_new = tuple(fence.get("newPaths", ()))
    allowed = tuple(fence.get("allowedCreateOrReplacePaths", ()))
    if existing != fenced_existing or hydrated_new != fenced_new:
        raise ValueError("C06 context/fence path sets differ")
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C06 existing path fence cardinality differs")
    if hydrated_new != NEW_PATHS or allowed != existing + hydrated_new:
        raise ValueError("C06 hydrated new-path ordering differs")
    if tuple(context.get("expectedArtifacts", ())) != allowed:
        raise ValueError("C06 expected-artifact ordering differs")
    if context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C06 prerequisite digest differs")
    if tuple(context.get("directPrerequisites", ())) != DIRECT_PREREQUISITES:
        raise ValueError("C06 direct prerequisites differ")
    if context.get("sourceProjection") != {
        **SOURCE_PINS,
        "canonicalSuccessor": {"cardID": "V23-P04-C07", "registerOrdinal": 95},
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    }:
        raise ValueError("C06 hydrated source projection differs")
    if context.get("semanticScope") != SEMANTIC_SCOPE:
        raise ValueError("C06 semantic scope differs")
    reserved = tuple(fence.get("activeS10ReservedPaths", ()))
    if (
        fence.get("frozenS10ReservationDigest") != FROZEN_S10_RESERVATION_DIGEST
        or len(reserved) != S10_RESERVED_PATH_COUNT
        or set(existing + hydrated_new) & set(reserved)
    ):
        raise ValueError("C06 S10 reservation or overlap differs")
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


def _section_between(text: str, start: str, end: str | None, label: str) -> str:
    start_index = text.find(start)
    if start_index < 0:
        raise ValueError(label + " start marker missing:" + start)
    end_index = text.find(end, start_index + len(start)) if end else len(text)
    if end_index < 0:
        raise ValueError(label + " end marker missing:" + str(end))
    return text[start_index:end_index]


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
        raise ValueError("C06 candidate tree differs from accepted base")
    observed_head = _git(root, "rev-parse", "HEAD")
    if observed_head != BASE_HEAD:
        if subprocess.run(["git", "merge-base", "--is-ancestor", BASE_HEAD, observed_head], cwd=root).returncode != 0:
            raise ValueError("C06 candidate is not a descendant of accepted base")


def _prior_fence_path(card_id: str, attempt_id: int) -> Path:
    return _coordination_root() / f"contexts/{card_id}-attempt-{attempt_id}/BootstrapPathFenceV1.json"


def _validate_prior_fence_proof(fence: dict[str, Any], allowed: tuple[str, ...]) -> None:
    proof = fence.get("priorFenceProof")
    if not isinstance(proof, dict):
        raise ValueError("C06 prior fence proof missing")
    for key, expected in (
        ("fenceCount", PRIOR_FENCE_COUNT),
        ("priorOwnedPathCount", PRIOR_OWNED_PATH_COUNT),
        ("authorizedOverlapCount", AUTHORIZED_OVERLAP_COUNT),
        ("unauthorizedOverlapCount", UNAUTHORIZED_OVERLAP_COUNT),
        ("overlapCount", AUTHORIZED_OVERLAP_COUNT),
    ):
        if proof.get(key) != expected:
            raise ValueError("C06 prior fence proof differs:" + key)
    rows = proof.get("fences")
    if not isinstance(rows, list) or len(rows) != PRIOR_FENCE_COUNT:
        raise ValueError("C06 prior fence rows differ")
    rebuilt_rows: list[dict[str, Any]] = []
    expected_edges: list[dict[str, Any]] = []
    prior_owned: set[str] = set()
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("cardID"), str) or not isinstance(row.get("attemptID"), int):
            raise ValueError("C06 prior fence row shape differs")
        path = _prior_fence_path(row["cardID"], row["attemptID"])
        if not path.is_file():
            raise ValueError("C06 prior fence input unavailable:" + row["cardID"])
        prior = _coordination_json(str(path.relative_to(_coordination_root())).replace("\\", "/"))
        owner_paths = tuple(prior.get("allowedCreateOrReplacePaths", ()))
        if prior.get("fenceDigest") != row.get("fenceDigest") or len(owner_paths) != row.get("ownedPathCount"):
            raise ValueError("C06 prior fence identity differs:" + row["cardID"])
        if sealed_field(prior, "fenceDigest") != row.get("fenceDigest"):
            raise ValueError("C06 prior fence seal differs:" + row["cardID"])
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
            "disposition": "P04_C06_DERIVED_ONLY_OFFLINE_READINESS_EXISTING_OWNER_REPROOF_REQUIRED",
        } for item in sorted(set(allowed) & set(owner_paths)))
    if len(prior_owned) != PRIOR_OWNED_PATH_COUNT or proof.get("fences") != rebuilt_rows:
        raise ValueError("C06 prior owned-path proof differs")
    if proof.get("authorizedOverlapEdges") != expected_edges:
        raise ValueError("C06 authorized overlap proof differs")


def _assert_coordination_state() -> None:
    coordination = _coordination_root()
    if _git(coordination, "rev-parse", "HEAD") != COORDINATION_HEAD or _git(coordination, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE:
        raise ValueError("C06 coordination HEAD/tree differs")
    origin = _git(coordination, "ls-remote", "origin", "refs/heads/main").split()
    if not origin or origin[0] != COORDINATION_ORIGIN_HEAD:
        raise ValueError("C06 coordination origin/main differs")

    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    prerequisite = _coordination_json(_PREREQUISITE_RELATIVE)
    transition = _coordination_json(_TRANSITION_RELATIVE)
    ledger = _coordination_json(_LEDGER_RELATIVE)
    projection = _coordination_json(_PROJECTION_RELATIVE)
    if _sealed_field(prerequisite, "prerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C06 prerequisite receipt seal differs")
    expected_common = {
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    if (
        prerequisite.get("schema") != "ProvisionalExecutionPrerequisiteSetReceiptV1"
        or prerequisite.get("successorCardID") != CARD
        or prerequisite.get("successorAttemptID") != 1
        or prerequisite.get("ordinaryDirectEdgeCount") != 1
        or prerequisite.get("predecessors") != list(DIRECT_PREREQUISITE_ROWS)
        or any(prerequisite.get(key) != value for key, value in expected_common.items())
    ):
        raise ValueError("C06 direct prerequisite receipt differs")
    if context.get("contextDigest") != CONTEXT_DIGEST or fence.get("fenceDigest") != FENCE_DIGEST or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C06 context/fence bindings differ")
    existing, hydrated_new = _load_hydrated_paths()
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != existing + hydrated_new:
        raise ValueError("C06 fence ordering differs")
    if any(fence.get(key) is not False for key, value in expected_common.items() if value is False and key in fence):
        raise ValueError("C06 fence claims activation")
    if fence.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C06 fence reconciliation requirement differs")
    _validate_prior_fence_proof(fence, existing + hydrated_new)
    expected_transition = {
        "schema": "BootstrapStateTransitionV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "attemptID": 1,
        "sequence": COORDINATION_CAS_SEQUENCE,
        "createdAt": "2026-08-31T00:45:00Z",
        "fromState": "NOT_STARTED",
        "toState": "HYDRATING",
        "reason": "OWNER_AUTHORIZED_P04_C06_PROVISIONAL_HYDRATION",
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "priorLedgerDigest": PRIOR_LEDGER_DIGEST,
        "newLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "transitionDigest": HYDRATION_TRANSITION_DIGEST,
    }
    if any(transition.get(key) != value for key, value in expected_transition.items()) or sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C06 hydration transition differs")
    if ledger.get("schema") != "BootstrapExecutionLedgerEnvelopeV1" or ledger.get("schemaVersion") != 1 or ledger.get("casSequence") != COORDINATION_CAS_SEQUENCE or ledger.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or ledger.get("previousLedgerDigest") != PRIOR_LEDGER_DIGEST:
        raise ValueError("C06 ledger authority differs")
    if sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST:
        raise ValueError("C06 ledger seal differs")
    row = ledger.get("attempts", [])[-1] if isinstance(ledger.get("attempts"), list) and ledger.get("attempts") else None
    expected_row = {
        "cardID": CARD,
        "attemptID": 1,
        "ordinal": REGISTER_ORDINAL,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "state": "HYDRATING",
        "stateReason": "OWNER_AUTHORIZED_P04_C06_PROVISIONAL_HYDRATION",
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "directPrerequisites": list(DIRECT_PREREQUISITES),
    }
    if row != expected_row:
        raise ValueError("C06 ledger card row differs")
    if projection.get("schema") != "ActiveWorkSetProjectionV1" or projection.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or projection.get("projectionDigest") != COORDINATION_PROJECTION_DIGEST or projection.get("eligibilityBasis") != "P04_C06_HYDRATING_DERIVED_ONLY_OFFLINE_READINESS_PRECHECK":
        raise ValueError("C06 projection authority differs")
    if sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ValueError("C06 projection seal differs")
    projection_row = projection.get("activeEntries", [])[-1] if isinstance(projection.get("activeEntries"), list) and projection.get("activeEntries") else None
    if projection_row != expected_row:
        raise ValueError("C06 projection card row differs")


def _authority_pins_ready() -> bool:
    refs = (BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE, COORDINATION_HEAD, COORDINATION_ORIGIN_HEAD, COORDINATION_TREE)
    digests = (
        CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST,
        COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST, FROZEN_S10_RESERVATION_DIGEST,
        DOSSIER_SHA256, INHERITED_V21_BLOCK_SHA256, REGISTER_ROW_SHA256, REGISTER_SECTION_SHA256,
    )
    return all(re.fullmatch(r"[0-9a-f]{40}", value) for value in refs) and all(valid_sha(value) for value in digests)


def assert_scaffold(root: Path) -> None:
    existing, hydrated_new = _load_hydrated_paths()
    path_fence = existing + hydrated_new
    if (len(existing), len(hydrated_new), len(path_fence), len(set(path_fence))) != (EXPECTED_EXISTING_PATH_COUNT, EXPECTED_NEW_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT):
        raise ValueError("C06 fence cardinality or uniqueness differs")
    if hydrated_new != NEW_PATHS or path_fence != PATH_FENCE:
        raise ValueError("C06 new-path ordering differs from hydrated fence")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in path_fence):
        raise ValueError("C06 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 6904 or UNAUTHORIZED_OVERLAP_COUNT != 0 or S10_RESERVATION_OVERLAP_COUNT != 0:
        raise ValueError("C06 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C06 app base tree differs")
    _candidate_identity(root)
    _assert_coordination_state()
    unauthorized = [path for path in observed_changed_paths(root) if path not in path_fence]
    if unauthorized:
        raise ValueError("C06 changed path outside fence:" + ",".join(unauthorized))
    missing_base = [path for path in existing if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C06 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in hydrated_new):
        raise ValueError("C06 new path already exists at accepted base")


def selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C06(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", path.read_text(encoding="utf-8")))


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
        {"id": "G01", "selector": "V23-P04-C06-G01", "tier": "GOLDEN"},
        {"id": "A01", "selector": "V23-P04-C06-A01", "tier": "ALTERNATE"},
        {"id": "H01", "selector": "V23-P04-C06-H01", "tier": "HOSTILE"},
        {"id": "I01", "selector": "V23-P04-C06-I01", "tier": "INTERRUPTION"},
        {"id": "R01", "selector": "V23-P04-C06-R01", "tier": "RECOVERY"},
    ]
    if fixture.get("schema") != "V22P04C06OfflineReadinessManifestCorpusV1" or fixture.get("schemaVersion") != 1 or fixture.get("cardID") != CARD or fixture.get("ordinal") != REGISTER_ORDINAL:
        raise ValueError("C06 fixture identity differs")
    if fixture.get("selectors") != expected_selectors or fixture.get("statuses") != list(READINESS_STATUSES) or fixture.get("requirements") != list(REQUIREMENTS):
        raise ValueError("C06 fixture status/requirement selectors differ")
    if fixture.get("hostileVectors") != ["wrong-workspace", "missing-bytes", "corrupt-bytes", "partial-bytes", "package-drift", "guidance-drift", "reference-drift", "asset-drift", "field-reference-omitted", "field-reference-unrelated", "field-reference-unknown", "protected-data", "low-storage", "uncheckable-storage", "clock-timezone", "overflow", "duplicate", "unknown-key", "noncanonical-decode", "unknown-extra-content", "inconsistent-ready-status"]:
        raise ValueError("C06 hostile fixture vectors differ")
    if fixture.get("interruptionVectors") != ["snapshot", "readback", "build", "source-drift"] or fixture.get("recoveryVectors") != ["derived-view-removal", "drop-and-rebuild", "compatibility"]:
        raise ValueError("C06 interruption/recovery vectors differ")
    if fixture.get("forbidden") != ["PERSISTENCE", "BACKUP", "DELETE", "EXPORT", "SYNC", "NETWORK"]:
        raise ValueError("C06 forbidden fixture boundary differs")
    claims = fixture.get("claims")
    if claims != {
        "allFlagsFalse": True,
        "readinessIsDerived": True,
        "sourceDriftIsStaleWithoutPartialSuccess": True,
        "derivedViewRebuildPreservesRoundSessionAndCanonicalData": True,
        "noPersistenceBackupDeleteOrExportClaim": True,
        "optionalOnlyWarningMayStartFieldWork": True,
        "mandatorySatisfactionRemainsExplicit": True,
    }:
        raise ValueError("C06 fixture claims differ")
    if fixture.get("statusFlags") != {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False}:
        raise ValueError("C06 fixture flags differ")


def _assert_no_forbidden_source_claims(source: str) -> None:
    forbidden_patterns = (
        r"\bURLSession\b", r"\bURLRequest\b", r"\bCloudKit\b", r"\bCKContainer\b",
        r"\bNWConnection\b", r"\bWebSocket\b", r"\bTelemetryClient\b", r"\bCoreML\b",
        r"\b(?:remoteSync|syncProcessor|upload|signedURL|prefetch|cacheDaemon)\b",
        r"\b(?:SwiftData|NSPersistentContainer|ModelContainer)\b", r"@Model\b",
        r"\b(?:WorkspaceWriterV1|MutationReceiptV1|canonicalWriter|persistentWriter|writeToStore)\b",
    )
    for pattern in forbidden_patterns:
        if re.search(pattern, source, re.I):
            raise ValueError("C06 forbidden source claim:" + pattern)


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C06 source lanes missing:" + ",".join(status["missingPaths"]))
    contract = _text(root, IMPLEMENTATION_PATHS[0])
    coordinator = _text(root, IMPLEMENTATION_PATHS[1])
    builder = _text(root, IMPLEMENTATION_PATHS[2])
    view = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[5])
    fixture = _json(root, IMPLEMENTATION_PATHS[6])
    fixture_text = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    _assert_fixture_contract(fixture)
    _require_patterns(contract, (
        r"\b(?:struct|enum|class)\s+OfflineReadinessManifestV1\b",
        r"\b(?:struct|enum|class)\s+OfflineReadiness(?:Status|Reason|Requirement|RequirementCategory|Remediation|ManualFallback)V1\b",
        r"\b(?:struct|enum|class)\s+OfflineReadinessManifestReductionInputV1\b",
        r"\b(?:struct|enum|class)\s+OfflineReadinessManifestReductionV1\b",
        r"\b(?:struct|enum|class)\s+OfflineReadinessManifestSourceProofV1\b",
        r"\b(?:struct|enum|class)\s+OfflineReadinessManifestReducerV1\b",
        r"\b(?:struct|enum|class)\s+OfflineReadinessManifestCanonicalCodecV1\b",
    ), "C06 offline-readiness contract declarations")
    _require_tokens(contract, (
        "OFFLINE_READINESS_V1", "RoundSession", "package", "guidance", "reference", "asset", "storage",
        "protected", "READY", "BLOCKED", "WARNING", "STALE", "reason", "revision", "sha256",
        "canonical", "DROP_AND_REBUILD", "derived", "OfflineReadinessManifestReducerV1",
        "OfflineReadinessManifestSourceProofV1", "OfflineReadinessManifestReductionInputV1",
        "OfflineReadinessManifestReductionV1", "CaseIterable", "OfflineReadinessClosedCodingV1.exact",
        "CodingKeys.allCases", "Set", "sorted", "mandatoryRequirementsAreSatisfied", "mayStartFieldWork",
        "maySafelyCloseFieldWork", "checkedAt", "timeZoneIdentifier", "clockState", "manifestSHA256",
        "OfflineReadinessManifestCanonicalCodecV1.sha256",
    ), "C06 offline-readiness contract")
    manifest_section = _section_between(
        contract, "struct OfflineReadinessManifestV1", "struct OfflineReadinessManifestReductionInputV1",
        "C06 manifest contract section",
    )
    source_proof_section = _section_between(
        contract, "enum OfflineReadinessManifestSourceProofV1", "enum OfflineReadinessManifestReducerV1",
        "C06 source proof section",
    )
    reducer_section = _section_between(
        contract, "enum OfflineReadinessManifestReducerV1", "enum OfflineReadinessManifestCanonicalCodecV1",
        "C06 reducer section",
    )
    _require_tokens(source_proof_section, (
        "session", "expectedPackage", "observedPackage", "selectedAssets", "observedAssetIDs",
        "guidanceReferenceIDs", "availableGuidanceReferenceIDs", "contentRequirements",
        "contentObservations", "expectedFieldReferences", "referenceObservations", "storage", "access",
        "timeZoneIdentifier", "clockState", "OfflineReadinessManifestCanonicalCodecV1.sha256",
    ), "C06 source proof")
    if re.search(r"\bcheckedAt\b", source_proof_section, re.I):
        raise ValueError("C06 source proof includes checkedAt")
    _require_tokens(manifest_section, (
        "checkedAt", "timeZoneIdentifier", "clockState", "manifestSHA256", "Basis",
        "OfflineReadinessManifestCanonicalCodecV1.sha256", "OfflineReadinessManifestReducerV1.reduce",
        "requirements == reduction.requirements", "status == reduction.status",
        "sourceSnapshotSHA256 == reduction.sourceSnapshotSHA256",
    ), "C06 manifest digest contract")
    _require_patterns(manifest_section, (
        r"var\s+mayStartFieldWork\s*:\s*Bool[\s\S]*?\(status\s*==\s*\.ready\s*\|\|\s*status\s*==\s*\.warning\)[\s\S]*?mandatoryRequirementsAreSatisfied",
        r"var\s+maySafelyCloseFieldWork\s*:\s*Bool[\s\S]*?status\s*==\s*\.ready[\s\S]*?mandatoryRequirementsAreSatisfied",
    ), "C06 warning start-only contract")
    _require_patterns(reducer_section, (
        r"static\s+func\s+reduce\s*\(\s*_\s+input:\s+OfflineReadinessManifestReductionInputV1\s*\)",
        r"rows\.append", r"rows\.sort", r"return\s+\.init\(requirements:\s*rows",
        r"static\s+func\s+status", r"clockState\s*==\s*\.changedSincePriorManifest",
        r"\$0\.state\s*==\s*\.stale", r"\$0\.mandatory\s*&&\s*\$0\.state\s*!=\s*\.satisfied",
        r"!\$0\.mandatory\s*&&\s*\$0\.state\s*!=\s*\.satisfied", r"return\s+\.ready",
    ), "C06 sole reducer and status truth")
    _require_tokens(reducer_section, (
        "input.contentRequirements", "input.contentObservations", "input.expectedFieldReferences",
        "input.referenceObservations", ".package", ".selectedAsset", ".guidance", ".fieldReference",
        ".content", ".protection", ".storage", ".clock", ".binding",
    ), "C06 reducer requirement coverage")
    for enum_name in (
        "OfflineReadinessStatusV1", "OfflineReadinessRequirementCategoryV1", "OfflineReadinessRequirementStateV1",
        "OfflineReadinessReasonV1", "OfflineReadinessRemediationV1", "OfflineReadinessManualFallbackV1",
        "OfflineReadinessContentObservationStateV1", "OfflineReadinessClockStateV1", "OfflineReadinessCapacityStateV1",
    ):
        enum_section = _section_between(contract, "enum " + enum_name, "\n}\n", "C06 closed enum " + enum_name)
        _require_tokens(enum_section, ("CaseIterable",), "C06 closed enum " + enum_name)
    _require_tokens(manifest_section, (
        "requirements.filter", ".mandatory", ".state == .satisfied", "status == .ready || status == .warning",
        "status == .ready && mandatoryRequirementsAreSatisfied",
    ), "C06 manifest safety gates")
    _require_tokens(coordinator, (
        "OfflineReadinessPreflightCoordinatorV1", "RoundSession", "readback", "checkCancellation",
        "materialize", "checkedAt", "timeZoneIdentifier", "expectedFieldReferenceBindings",
        "storageObservation", "accessObservation",
    ), "C06 preflight coordinator")
    _require_tokens(builder, (
        "OfflineReadinessManifestBuilderV1", "build", "OfflineReadinessManifestReductionInputV1",
        "OfflineReadinessManifestReducerV1.reduce", "snapshot", "previous", "sourceSnapshotSHA256",
        "checkedAt", "timeZoneIdentifier", "clockState", "selectedAssets", "guidanceReferenceIDs",
        "availableGuidanceReferenceIDs", "contentRequirements", "contentObservations", "expectedFieldReferences",
        "fieldReferenceReadiness", "storage", "protected", "reduction", "requirements", "status",
    ), "C06 manifest builder")
    if builder.count("OfflineReadinessManifestReducerV1.reduce") != 1:
        raise ValueError("C06 builder must call the sole full-row reducer exactly once")
    if re.search(r"OfflineReadinessRequirementV1\s*\(", builder) or re.search(r"\b(?:var\s+rows|rows\.append)\b", builder):
        raise ValueError("C06 builder constructs or appends requirement rows")
    _require_tokens(view, (
        "OfflineReadinessPreflightView", ".ready", ".blocked", ".warning", ".stale", "accessibilityIdentifier",
        "localized", "manualFallback", "remediation", "onRebuild", "localOnlyDisclosure",
    ), "C06 preflight view")
    found = tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C06(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", tests))
    if len(found) != 5 or tuple(name[len("testV23P04C06"):len("testV23P04C06") + 3] for name in found) != SELECTOR_SUFFIXES or len(set(found)) != 5:
        raise ValueError("C06 requires exactly five ordered G/A/H/I/R selectors")
    _require_tokens(tests, (
        "OfflineReadinessManifestV1", "RoundSession", ".ready", ".blocked", ".warning", ".stale",
        "sourceSnapshotSHA256", "checkedAt", "timeZoneIdentifier",
        "clockState", "mayStartFieldWork", "maySafelyCloseFieldWork", "fieldReference", "cold", "launch",
        "rebuild", "protected", "storage", "clock", "XCTAssert",
    ), "C06 offline-readiness tests")
    _require_tokens(ui_tests, (
        CARD, "offline-readiness-preflight", "uiAdoptionEnabled", "uiAcceptanceCredit", "XCTSkip", "S10.6",
    ), "C06 UI deferral test")
    _require_tokens(fixture_text, (CARD, *EVIDENCE_IDS, *READINESS_STATUSES, *REQUIREMENTS), "C06 fixture")
    source = "\n".join((contract, coordinator, builder, view, tests, ui_tests, fixture_text))
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
        "coordinationSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "sourcePins": dict(SOURCE_PINS),
        "directPrerequisiteCards": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT,
        "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT,
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
        "acceptanceEnabled": False,
        "adoptionEnabled": False,
        "releaseCredit": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "uiAdoptionSkipped": True,
        "uiAcceptanceCredit": False,
        "provisional": not FINAL_HASHES_SEALED,
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
        "requiresAcceptedS10_6Reconciliation": True,
    }


def lifecycle() -> dict[str, Any]:
    return {
        "persistence": "DERIVED_ONLY",
        "schema": "OFFLINE_READINESS_V1",
        "persistentRow": False,
        "persistentSchema": False,
        "store": "NOT_APPLICABLE",
        "writer": "NONE_CARD_LOCAL",
        "migration": "NOT_APPLICABLE",
        "backupRestore": "NOT_APPLICABLE",
        "deleteErase": "NOT_APPLICABLE",
        "exportReport": "NOT_APPLICABLE",
        "searchRebuild": "NO_NEW_INDEX_DERIVED_ONLY",
        "journalReplay": "NOT_APPLICABLE_DERIVED_VIEW",
        "downgrade": "DROP_AND_REBUILD",
        "networkDependency": False,
        "syncDependency": False,
    }


def semantics(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {
        "persistentContractMode": "DERIVED_ONLY",
        "schemaVersion": "OFFLINE_READINESS_V1",
        "canonicalReadinessRow": False,
        "persistentRow": False,
        "persistentSchema": False,
        "migrationRequired": False,
        "backupRestoreRequired": False,
        "deleteEraseRequired": False,
        "exportReportRequired": False,
        "downgradePolicy": "DROP_AND_REBUILD",
        "bindings": list(SEMANTIC_SCOPE["bindings"]),
        "requirements": list(REQUIREMENTS),
        "statuses": list(READINESS_STATUSES),
        "reasonCodes": list(READINESS_REASONS),
        "statusReasonMatrix": {key: list(value) for key, value in STATUS_REASON_MATRIX.items()},
        "closedSets": {
            "statuses": list(READINESS_STATUSES),
            "categories": list(REQUIREMENT_CATEGORIES),
            "states": list(REQUIREMENT_STATES),
            "reasons": list(READINESS_REASONS),
            "remediations": list(REMEDIATIONS),
            "manualFallbacks": list(MANUAL_FALLBACKS),
        },
        "sourceProof": {
            "algorithm": "OFFLINE_READINESS_V1_CANONICAL_SHA256",
            "includes": [
                "ROUND_SESSION", "PACKAGE", "SELECTED_ASSET", "GUIDANCE", "FIELD_REFERENCE",
                "CONTENT", "STORAGE", "PROTECTION", "TIME_ZONE", "CLOCK",
            ],
            "excludes": ["CHECKED_AT", "DERIVED_REQUIREMENT_ROWS", "PRIOR_EVIDENCE"],
            "checkedAtExcluded": True,
        },
        "manifestDigest": {
            "algorithm": "OFFLINE_READINESS_V1_CANONICAL_SHA256",
            "checkedAtIncluded": True,
            "basisIncludes": ["CHECKED_AT", "TIME_ZONE", "CLOCK", "REQUIREMENT_ROWS", "STATUS", "SOURCE_SNAPSHOT_SHA256"],
        },
        "reducer": {
            "soleFullRowReducer": "OfflineReadinessManifestReducerV1.reduce",
            "builderOnlyMaterializesInput": True,
            "rowsSortedBy": "requirementID",
            "mandatoryCategories": ["PACKAGE", "SELECTED_ASSET", "GUIDANCE", "FIELD_REFERENCE", "CONTENT", "PROTECTION", "STORAGE", "CLOCK"],
        },
        "statusTruth": {
            "precedence": ["STALE", "BLOCKED", "WARNING", "READY"],
            "STALE": "clock changed or any row stale",
            "BLOCKED": "mandatory row not SATISFIED",
            "WARNING": "nonmandatory row not SATISFIED",
            "READY": "all rows SATISFIED",
        },
        "warningStartOnly": {
            "warningMayStartWhenMandatorySatisfied": True,
            "warningMaySafelyClose": False,
            "readyMaySafelyCloseWhenMandatorySatisfied": True,
        },
        "mandatoryBindingCategories": ["PACKAGE", "GUIDANCE", "FIELD_REFERENCE", "CONTENT", "SELECTED_ASSET", "STORAGE", "PROTECTION", "CLOCK"],
        "failureCoverage": list(FAILURE_COVERAGE),
        "coldLaunch": {
            "required": True,
            "reboot": True,
            "termination": True,
            "manifestIsCanonical": False,
            "rebuild": "DETERMINISTIC_INVALIDATION_AND_REBUILD",
            "preserves": ["ROUND_SESSION", "CANONICAL_DATA", "IMMUTABLE_HISTORY"],
        },
        "determinism": {
            "canonicalInputOrdering": True,
            "independentHashVerification": True,
            "partialSuccessForbidden": True,
            "sourceDriftIsStale": True,
        },
        "persistence": lifecycle(),
        "forbiddenCapabilities": list(FORBIDDEN_CAPABILITIES),
        "noNetworkCloudTelemetryAI": True,
        "noSyncStoreOrWriterClaim": True,
        "accessibilityAndLocalization": {
            "dynamicTypeThroughAX5": True,
            "voiceOver": True,
            "voiceControl": True,
            "switchControl": True,
            "contrast": True,
            "reduceMotion": True,
            "localeAndRTL": True,
            "truthfulStatusAndErrorFocus": True,
        },
        "ui": "POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT",
        "selectors": list(selectors_value),
        "evidenceIDs": list(EVIDENCE_IDS),
        "journeyRefs": list(JOURNEY_REFS),
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS),
        "conformanceSubjects": list(CONFORMANCE_SUBJECTS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
    }


def _source_rows(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in IMPLEMENTATION_PATHS:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            rows.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_SOURCE"})
        else:
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
    return rows


def _source_projection(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
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
        "sourceRows": _source_rows(root),
        **SOURCE_PINS,
        "canonicalSuccessor": {"cardID": "V23-P04-C07", "registerOrdinal": 95},
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS),
        "conformanceSubjects": list(CONFORMANCE_SUBJECTS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
    }


def schema_document(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/offline-readiness-manifest.schema.json",
        "title": TITLE,
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "OFFLINE_READINESS_V1"},
            "schemaVersion": {"const": SCHEMA_VERSION},
            "cardID": {"const": CARD},
            "ordinal": {"const": REGISTER_ORDINAL},
            "status": {"enum": list(READINESS_STATUSES)},
            "reason": {"enum": list(READINESS_REASONS)},
            "reasons": {"type": "array", "items": {"enum": list(READINESS_REASONS)}, "uniqueItems": True},
            "requirements": {"const": list(REQUIREMENTS)},
            "bindings": {"const": list(SEMANTIC_SCOPE["bindings"])},
            "sourceReady": {"type": "boolean"},
            "derivedOnly": {"const": True},
            "manifestIsCanonical": {"const": False},
            "coldLaunchRebuild": {"const": "DETERMINISTIC_INVALIDATION_AND_REBUILD"},
            "downgradePolicy": {"const": "DROP_AND_REBUILD"},
            "statusFlags": {"const": dict(FLAGS)},
            "selectors": {"const": list(selectors_value)},
            "evidenceIDs": {"const": list(EVIDENCE_IDS)},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED},
            "provisional": {"const": not FINAL_HASHES_SEALED},
        },
        "required": [
            "schema", "schemaVersion", "cardID", "ordinal", "status", "reason", "reasons",
            "requirements", "bindings", "sourceReady", "derivedOnly", "manifestIsCanonical",
            "coldLaunchRebuild", "downgradePolicy", "statusFlags", "selectors", "evidenceIDs",
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
            files.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_PROVIDER"})
        else:
            files.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_PROVIDER"})
    return [{
        "providerCardID": "V23-P04-C05",
        "required": True,
        "capability": "ROUND_SESSION_REVISION_AND_CANONICAL_CONTENT_BINDINGS",
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "checkpointDigest": DIRECT_PREREQUISITE_ROWS[0]["checkpointDigest"],
        "contextDigest": DIRECT_PREREQUISITE_ROWS[0]["contextDigest"],
        "pathFenceDigest": DIRECT_PREREQUISITE_ROWS[0]["pathFenceDigest"],
        "verificationReceiptDigest": DIRECT_PREREQUISITE_ROWS[0]["verificationReceiptDigest"],
        "contracts": ["RoundSessionV1", "RoundSessionReferenceV1", "RoundPackageContentRequirementV1", "RoundSessionCanonicalCodecV1"],
        "paths": list(provider_paths),
        "files": files,
        "allFilesPresent": all(item["sha256"] is not None for item in files),
        "fallback": None,
    }]


def contract_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C06OfflineReadinessManifestContractV1",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "contractRefs": list(CONTRACT_REFS),
        "journeyRefs": list(JOURNEY_REFS),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "semantics": semantics(selectors_value),
        "sourceProjection": _source_projection(root, selectors_value),
        "providerArtifacts": _provider_artifacts(root),
    })


def evidence_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {
            "evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "selectorSuffix": "G01",
            "focus": ["ready manifest deterministic repeat", "exact RoundSession/package/asset/guidance/reference bindings", "required storage and protected-data checks", "safe-to-start and safe-to-close local truth"],
            "expectedStatus": "READY", "allowedReasons": list(STATUS_REASON_MATRIX["READY"]),
        },
        {
            "evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "selectorSuffix": "A01",
            "focus": ["airplane-mode cold launch", "reboot, force-quit, and resume", "optional-content warning with manual fallback", "no network or sync claim"],
            "expectedStatus": "WARNING", "allowedReasons": list(STATUS_REASON_MATRIX["WARNING"]),
        },
        {
            "evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "selectorSuffix": "H01",
            "focus": ["wrong workspace", "missing, corrupt, or partial bytes", "package/guidance/reference/asset drift", "protected-data, storage, clock, duplicate, unknown-key, and noncanonical decode rejection"],
            "expectedStatus": "BLOCKED", "allowedReasons": list(STATUS_REASON_MATRIX["BLOCKED"]),
        },
        {
            "evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "selectorSuffix": "I01",
            "focus": ["snapshot, readback, build, and source-drift interruption", "terminate and relaunch at a durable boundary", "no partial success and deterministic continuation or fail-closed state"],
            "expectedStatus": "STALE", "allowedReasons": list(STATUS_REASON_MATRIX["STALE"]),
        },
        {
            "evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "selectorSuffix": "R01",
            "focus": ["remove derived preflight view", "drop-and-rebuild", "RoundSession and canonical data preserved", "compatibility rerun without relabeling unknown as ready"],
            "expectedStatus": "STALE", "allowedReasons": list(STATUS_REASON_MATRIX["STALE"]),
        },
    ]
    return _sealed({
        "schema": "V23P04C06OfflineReadinessEvidenceReceiptV1",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(selectors_value),
        "cases": cases,
        "statuses": list(READINESS_STATUSES),
        "reasonCodes": list(READINESS_REASONS),
        "statusReasonMatrix": {key: list(value) for key, value in STATUS_REASON_MATRIX.items()},
        "requirements": list(REQUIREMENTS),
        "bindings": list(SEMANTIC_SCOPE["bindings"]),
        "failureCoverage": list(FAILURE_COVERAGE),
        "coldLaunchRebuild": "DETERMINISTIC_INVALIDATION_AND_REBUILD",
        "preservesRoundSessionAndCanonicalData": True,
        "uiAdoptionSkipped": True,
        "accessibilityAndLocalizationRequired": True,
        "sourceProjection": _source_projection(root, selectors_value),
        "providerArtifacts": _provider_artifacts(root),
    })


def brand_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    source = source_status(root)
    return _sealed({
        "schema": "V23P04C06BrandImpactManifestV1",
        "schemaVersion": SCHEMA_VERSION,
        **common(),
        "iPhoneNativeOnly": True,
        "nativeIPadSurface": False,
        "uiSurfaceDelta": True,
        "brandSurfaceDelta": True,
        "uiSourceExists": IMPLEMENTATION_PATHS[3] in source["presentPaths"],
        "uiTestSourceExists": IMPLEMENTATION_PATHS[5] in source["presentPaths"],
        "uiTestDisposition": "EXPLICIT_POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_AUTHORITY",
        "adoptionSkipped": True,
        "uiAdoptionSkipped": True,
        "uiAcceptanceCredit": False,
        "onDeviceOnly": True,
        "networkOrTelemetryFlow": False,
        "syncStatusClaimed": False,
        "accessibilityAndLocalizationRequired": True,
        "accessibilitySourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not source["hydrated"] else "SOURCE_INSPECTED",
        "localizationSourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not source["hydrated"] else "SOURCE_INSPECTED",
        "changedStates": list(READINESS_STATUSES),
        "statusReasonMatrix": {key: list(value) for key, value in STATUS_REASON_MATRIX.items()},
        "sourceProjection": _source_projection(root, selectors_value),
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
        "status": "PROVISIONAL_TOOLING" if path in TOOLING_EDIT_PATHS and not FINAL_HASHES_SEALED else ("SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE"),
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
    manifest_base = {
        "schema": "V23-P04-C06-tooling-manifest",
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
        "sourceProjection": _source_projection(root, selectors_value),
        "providerArtifacts": _provider_artifacts(root),
        "files": rows,
    }
    rendered[MANIFEST_PATH] = pretty(_sealed(manifest_base))
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
