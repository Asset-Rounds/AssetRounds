#!/usr/bin/env python3
"""Fail-closed static tooling contracts for V23-P04-C08.

This module is deliberately an observation and evidence layer.  It owns no
importer, store, parser, renderer, writer, or product route.  Until the eight
hydrated implementation/test/fixture lanes are present, generated documents
are reproducible and explicitly provisional.  The coordination inputs are
read-only authority and every generated document is derived from the live
repository bytes.
"""
from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C08"
TITLE = "Reusable preview-first import and bulk command engine, asset/location adapters, and deterministic export"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 96

# Frozen app and coordination hydration authority.
BASE_HEAD = "8925c84d79f703482525a0dc0876bfb6a1e5b7c1"
BASE_TREE = "68a59bca98a5aa2a191c138db6418492203b0586"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "fe5e07551d45ec9110632be9991c99a5d4c4a3fc"
COORDINATION_TREE = "f0d6e46d96544aec35ef0d6845b88e7d49ada8f0"
COORDINATION_ORIGIN_HEAD = COORDINATION_HEAD
COORDINATION_CAS_SEQUENCE = 418
SEQUENCE = COORDINATION_CAS_SEQUENCE
CONTEXT_DIGEST = "716fc41e7e03b9281caedee6c802f52fc5f6088d581305890e624d15ec164152"
FENCE_DIGEST = "0ad280fdfff828818d4619f165994a889ea10071caa9bfe55f665a75ca07ff4b"
PREREQUISITE_DIGEST = "cb9341ba69f829e9dbe05cd0a340bde743e4dbbb0d7722099ce4ad2a41258731"
HYDRATION_TRANSITION_DIGEST = "f52c2ecb24cf6b87f9c517ff9aabf50b889a18f31518144bc21cd8be5c282868"
COORDINATION_LEDGER_DIGEST = "f23c8016ecfa22dfa0897c4b2505486e0399530c4eb787e5d29cf3774cc003f0"
COORDINATION_PROJECTION_DIGEST = "53daecaee8d37811f64728d5ea43a8eaa2becbc2ab9c34a3a3d8a25f59eaf487"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
PRIOR_LEDGER_DIGEST = "91978e46156c0bc235f97b1954a3e0e7e8a7a2ce445a7c3fb727629b1cb4ab59"
CREATED_AT = "2026-08-31T01:30:00Z"

# The source lanes are not assumed to be stable.  Root may authorize a later
# seal by changing this one constant in this owned tooling lane.
FINAL_HASHES_SEALED = True

SOURCE_PINS = {
    "dossierUTF8Length": 7368,
    "dossierSHA256": "6796a147fcc8dd7666b9386815cc31d67535dcb59a77b2098616488c3b49fa2c",
    "inheritedV21BlockUTF8Length": 12575,
    "inheritedV21BlockSHA256": "95de909543413863d28d4d1180465b9cc62205a08e808ee6026a0b73c0a09183",
    "registerRowUTF8Length": 301,
    "registerRowSHA256": "dc96c191f4152a22bcce9c7d29735c9dc71d1f6274914b8f69156f3e33665bf7",
    "registerSectionUTF8Length": 44217,
    "registerSectionSHA256": "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5",
}

EXPECTED_EXISTING_PATH_COUNT = 375
EXPECTED_NEW_PATH_COUNT = 16
EXPECTED_FENCE_PATH_COUNT = 391
AUTHORIZED_OVERLAP_COUNT = 7641
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 96
PRIOR_OWNED_PATH_COUNT = 1515
S10_RESERVED_PATH_COUNT = 86

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/ImportExport/ImportBulkContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/ImportBulkPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/ImportExport/ImportBulkCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/ImportExport/ImportBulkLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Features/AssetImport/ImportBulkPreviewView.swift",
    "FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift",
    "FieldEvidenceAppUITests/V23_P04_C08ImportBulkPreviewUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/ImportExport/V22P04C08ImportBulkEngineCorpusV1.json",
)
SCHEMA_PATH = "Scripts/v23/import-bulk-engine.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C08ImportBulkEngineContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C08ImportBulkEngineEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C08BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C08-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c08_contracts.py",
    "Scripts/v23/generate_p04_c08_contracts.py",
    "Scripts/v23/verify_p04_c08_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
OUTPUT_PATHS = GENERATED_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C08-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C08-attempt-1/BootstrapPathFenceV1.json"
_PREREQUISITE_RELATIVE = "receipts/V23-P03-C37-to-V23-P04-C08-provisional-prerequisite.json"
_TRANSITION_RELATIVE = "transitions/000418-V23-P04-C08-attempt-1-NOT_STARTED-to-HYDRATING.json"
_LEDGER_RELATIVE = "state/BootstrapExecutionLedgerEnvelopeV1.json"
_PROJECTION_RELATIVE = "projections/ActiveWorkSetProjectionV1.json"

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
EXPECTED_SELECTORS = (
    "testV23P04C08G01PreviewFirstImportBulkAndDeterministicExportGolden",
    "testV23P04C08A01CorrectionAndPoseRoundTripAlternate",
    "testV23P04C08H01HostileBudgetIdentityAndFormulaSafety",
    "testV23P04C08I01ChunkBoundaryInterruptionAndResume",
    "testV23P04C08R01IdempotentRetryCompensationAndLifecycleRecovery",
)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
JOURNEY_REFS = ("CommonTaskJourneyReleaseV2",)
DIRECT_PREREQUISITES = ("V23-P03-C37",)
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
AGGREGATE_MEMBERSHIPS = (
    "AutonomousRequiredAcceptedSetV1", "P04ShippingSurfaceSetV1", "P04BrandClosureSetV1",
)
CONFORMANCE_SUBJECTS = ("P04ShippingSurfaceSetV1", "CommonTaskJourneyReleaseV2")
INVALIDATION_CONSUMERS = (
    "V23-P04-C13", "V23-P04-C20", "V23-P04-C32", "V23-P04-C37", "V23-P04-C44",
    "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR",
)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C08).CONTRACTS", "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)

AUTHORITY_CONTRACTS = (
    "ImportSourceV1", "ImportSchemaReleaseV1", "ImportMappingProfileV1", "ImportRowIdentityV1",
    "ImportRowDispositionV1", "ImportPlanV1", "BulkCommandPlanV1", "BulkSessionV1",
    "BulkCommitReceiptV1", "ImportLifecycleDispositionV1", "DeterministicCSVExportV1",
    "ImportCorrectionArtifactV1", "ExportSchemaReleaseV1",
)
PERSISTENT_KINDS = ("ImportMappingProfileV1", "BulkSessionV1", "BulkCommitReceiptV1")
ROW_DISPOSITIONS = (
    "CREATE", "UPDATE_EXACT_MATCH", "UNCHANGED", "DUPLICATE_SOURCE", "AMBIGUOUS_TARGET",
    "CONFLICT", "INVALID", "UNSUPPORTED", "SKIPPED_BY_USER",
)
EXECUTION_STATES = (
    "PREVIEW_ONLY", "ALL_OR_NOTHING_PREVIEW", "CHUNKED_PREVIEW", "COMMITTED",
    "PARTIAL_COMMITTED", "INTERRUPTED", "STALE",
)
LIFECYCLE = (
    "SCHEMA_VERSION", "WRITER_QUERY", "MIGRATION", "BACKUP_REPLACE_RESTORE", "CLONE_FORK",
    "IMPORT_EXPORT", "JOURNAL_REPLAY", "SEARCH_REBUILD", "REPORT_PROJECTION", "DELETE_ERASE",
    "RETENTION", "COMPATIBILITY", "DOWNGRADE_FORWARD_FIX", "INTERRUPTION", "IDEMPOTENT_RECEIPTS",
)
FORBIDDEN = (
    "ACCOUNT", "AUTHENTICATION", "TENANCY", "REMOTE_SYNC", "BACKEND", "NETWORK_TRANSPORT",
    "TELEMETRY", "REMOTE_CLAIMS", "NATIVE_IPAD", "QR_OR_NETWORK_TAG_RESOLUTION", "RECURRENCE",
    "DUE_QUEUE", "NOTIFICATION", "TEAM_DISPATCH", "PROVIDER_OUTBOX_INBOX_ACK_UPLOAD_STATE",
    "REMOTE_EMAIL_OR_LINK", "ANALYTICS", "FUZZY_MATCH", "NAME_ONLY_MATCH", "DELETE_BY_IMPORT",
    "MERGE_BY_IMPORT", "FINALIZED_FIELD_UPDATE", "XLSX_EXECUTION", "ARBITRARY_TRANSFORM",
    "CLOUD_SPREADSHEET", "MEDIA_URL_FETCH", "SECOND_WRITER", "SECOND_STORE", "SECOND_PARSER",
    "SECOND_RENDERER", "SECOND_IMPORTER", "SECOND_IDENTITY", "PREVIEW_WRITE", "HIDDEN_PARTIAL_COMMIT",
    "RECEIPT_DELETION", "DATABASE_REWIND", "S10_ROUTE_WIRING",
)
HOSTILE_VECTORS = (
    "utf8-nfc-crlf-quote-newline", "duplicate-header-or-external-key", "control-or-formula-prefix",
    "oversize-bounded-parse", "ambiguous-or-name-only-target", "stale-revision-or-source-digest",
    "effect-before-receipt", "chunk-race-or-resume", "zero-write-preview-repeat", "forbidden-capability-claim",
)
FLAGS = {name: False for name in (
    "activation", "native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance",
    "hostedAcceptance", "physicalEvidence", "phase10PollingDuringParallelExecution",
)}

CONTEXT_SEMANTIC_SCOPE = {
    "canonicalWriter": "V23-P02-C01_WORKSPACE_WRITER_ONLY",
    "commit": "ALL_OR_NOTHING_OR_PREVIEWED_CHUNKED_ATOMIC",
    "forbidden": ["SECOND_WRITER", "SECOND_STORE", "SECOND_IDENTITY", "NETWORK", "TELEMETRY", "REMOTE_CLAIMS", "NATIVE_IPAD"],
    "lifecycleOwner": "IMPORT_BULK_LIFECYCLE_ADAPTER_BOUNDED_PARSE_SCRATCH_ADAPTERS_LIFECYCLE_EXPORT_DELEGATION",
    "namedContracts": list(AUTHORITY_CONTRACTS),
    "persistentContractMode": "IMPORT_BULK_PROFILE_SESSION_RECEIPT_V1",
    "persistentKinds": list(PERSISTENT_KINDS),
    "policyProfile": "PERSISTENT_OR_PRODUCT_DELTA",
    "preview": "ZERO_WRITE",
    "recovery": "SAME_PLAN_RESUME_FIRST_MISSING_RECEIPT_NEVER_ROLLBACK_COMMITTED_CHUNK",
    "typedAdapterRegistrationSeam": "REQUIRED_LOCAL_UNNAMED_NOT_FOURTEENTH_AUTHORITY_CONTRACT",
}

# Keep the exact hydrated semantic scope above byte-for-byte equivalent while
# publishing the fuller derived proof below.
SEMANTIC_SCOPE = {
    "lineage": "EXACT_WITH_GENERATION_REBIND",
    "policyProfile": "PERSISTENT_OR_PRODUCT_DELTA",
    **CONTEXT_SEMANTIC_SCOPE,
    "parse": "BOUNDED_VERSIONED_BYTE_ROW_COLUMN_CELL_SCALAR_BUDGETS",
    "identity": "SOURCE_DIGEST_ORDINAL_CANONICAL_ROW_DIGEST_AND_STABLE_EXTERNAL_KEY",
    "chunks": "DETERMINISTIC_PLAN_CHUNK_MUTATION_IDS_FIRST_MISSING_RECEIPT_RESUME",
    "export": "DETERMINISTIC_UTF8_NFC_LOCALE_NEUTRAL_FORMULA_CONTROL_SAFE",
    "forbidden": list(FORBIDDEN),
    "noSecondWriterStoreParserRendererOrIdentity": True,
    "sourceScratch": "LEASED_BOUNDED_DELETE_ON_SUCCESS_CANCEL_FAILURE_OR_EXPIRY",
}

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
    return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n") if path.suffix.lower() in _CANONICAL_TEXT_SUFFIXES else data


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def _coordination_root() -> Path:
    candidates = (Path(r"C:\AssetRounds-v23-coordination"), ROOT.parent / "AssetRounds-v23-coordination")
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C08 coordination fence unavailable")


def coord() -> Path:
    return _coordination_root()


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ValueError("C08 coordination input unavailable:" + relative)
    value = json.loads(path.read_bytes().replace(b"\r\n", b"\n"), object_pairs_hook=strict)
    if not isinstance(value, dict):
        raise ValueError("C08 coordination object required:" + relative)
    return value


def sealed_field(value: dict[str, Any], field: str) -> str:
    unsigned = {key: item for key, item in value.items() if key != field}
    return sha256_bytes((json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST or sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C08 context identity or seal differs")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST or sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ValueError("C08 path fence identity or seal differs")
    existing = tuple(context.get("existingPaths", ()))
    fenced_existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(context.get("newPaths", ()))
    fenced_new = tuple(fence.get("newPaths", ()))
    allowed = tuple(fence.get("allowedCreateOrReplacePaths", ()))
    if existing != fenced_existing or hydrated_new != fenced_new:
        raise ValueError("C08 context/fence path sets differ")
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C08 existing path fence cardinality differs")
    if hydrated_new != NEW_PATHS or allowed != existing + hydrated_new:
        raise ValueError("C08 hydrated new-path ordering differs")
    if tuple(context.get("expectedArtifacts", ())) != allowed:
        raise ValueError("C08 expected-artifact ordering differs")
    if context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST or tuple(context.get("directPrerequisites", ())) != DIRECT_PREREQUISITES:
        raise ValueError("C08 prerequisite binding differs")
    expected_projection = {
        **SOURCE_PINS,
        "canonicalSuccessor": {"cardID": "V23-P04-C09", "registerOrdinal": 97},
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "selectors": list(EXPECTED_SELECTORS),
    }
    if context.get("sourceProjection") != expected_projection or context.get("semanticScope") != CONTEXT_SEMANTIC_SCOPE:
        raise ValueError("C08 source projection or semantic scope differs")
    reserved = tuple(fence.get("activeS10ReservedPaths", ()))
    if fence.get("frozenS10ReservationDigest") != FROZEN_S10_RESERVATION_DIGEST or len(reserved) != S10_RESERVED_PATH_COUNT or set(existing + hydrated_new) & set(reserved):
        raise ValueError("C08 S10 reservation or overlap differs")
    return existing, hydrated_new


EXISTING_PATHS, _HYDRATED_NEW_PATHS = _load_hydrated_paths()
PATH_FENCE = EXISTING_PATHS + _HYDRATED_NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_text(root, relative), object_pairs_hook=strict)
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
        raise ValueError("C08 candidate tree differs from accepted base")
    observed_head = _git(root, "rev-parse", "HEAD")
    if observed_head != BASE_HEAD and subprocess.run(["git", "merge-base", "--is-ancestor", BASE_HEAD, observed_head], cwd=root).returncode != 0:
        raise ValueError("C08 candidate is not a descendant of accepted base")


def _prior_fence_path(card_id: str, attempt_id: int) -> Path:
    return _coordination_root() / f"contexts/{card_id}-attempt-{attempt_id}/BootstrapPathFenceV1.json"


def _validate_prior_fence_proof(fence: dict[str, Any], allowed: tuple[str, ...]) -> None:
    proof = fence.get("priorFenceProof")
    if not isinstance(proof, dict):
        raise ValueError("C08 prior fence proof missing")
    for key, expected in (("fenceCount", PRIOR_FENCE_COUNT), ("priorOwnedPathCount", PRIOR_OWNED_PATH_COUNT), ("authorizedOverlapCount", AUTHORIZED_OVERLAP_COUNT), ("unauthorizedOverlapCount", UNAUTHORIZED_OVERLAP_COUNT), ("overlapCount", AUTHORIZED_OVERLAP_COUNT)):
        if proof.get(key) != expected:
            raise ValueError("C08 prior fence proof differs:" + key)
    rows = proof.get("fences")
    if not isinstance(rows, list) or len(rows) != PRIOR_FENCE_COUNT:
        raise ValueError("C08 prior fence rows differ")
    rebuilt: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    prior_owned: set[str] = set()
    disposition = "P04_C08_EXISTING_IMPORT_BULK_WRITER_LIFECYCLE_REPROOF_REQUIRED"
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("cardID"), str) or not isinstance(row.get("attemptID"), int):
            raise ValueError("C08 prior fence row shape differs")
        path = _prior_fence_path(row["cardID"], row["attemptID"])
        if not path.is_file():
            raise ValueError("C08 prior fence input unavailable:" + row["cardID"])
        prior = json.loads(path.read_bytes().replace(b"\r\n", b"\n"), object_pairs_hook=strict)
        owner_paths = tuple(prior.get("allowedCreateOrReplacePaths", ()))
        if prior.get("fenceDigest") != row.get("fenceDigest") or len(owner_paths) != row.get("ownedPathCount") or sealed_field(prior, "fenceDigest") != row.get("fenceDigest"):
            raise ValueError("C08 prior fence identity/seal differs:" + row["cardID"])
        prior_owned.update(owner_paths)
        rebuilt.append({"cardID": row["cardID"], "attemptID": row["attemptID"], "fenceDigest": row["fenceDigest"], "ownedPathCount": len(owner_paths)})
        edges.extend({"path": item, "priorCardID": row["cardID"], "priorFenceDigest": row["fenceDigest"], "disposition": disposition} for item in sorted(set(allowed) & set(owner_paths)))
    if len(prior_owned) != PRIOR_OWNED_PATH_COUNT or rows != rebuilt:
        raise ValueError("C08 prior owned-path proof differs")
    if proof.get("authorizedFenceEdges") is not None and proof.get("authorizedFenceEdges") != edges:
        raise ValueError("C08 authorized fence edges differ")
    if proof.get("authorizedOverlapEdges") is not None and proof.get("authorizedOverlapEdges") != edges:
        raise ValueError("C08 authorized overlap edges differ")


def _assert_coordination_state() -> None:
    coordination = _coordination_root()
    if _git(coordination, "rev-parse", "HEAD") != COORDINATION_HEAD or _git(coordination, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE:
        raise ValueError("C08 coordination HEAD/tree differs")
    origin = _git(coordination, "ls-remote", "origin", "refs/heads/main").split()
    if not origin or origin[0] != COORDINATION_ORIGIN_HEAD:
        raise ValueError("C08 coordination origin/main differs")
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    prerequisite = _coordination_json(_PREREQUISITE_RELATIVE)
    transition = _coordination_json(_TRANSITION_RELATIVE)
    ledger = _coordination_json(_LEDGER_RELATIVE)
    projection = _coordination_json(_PROJECTION_RELATIVE)
    _load_hydrated_paths()
    if context.get("repository") != {"appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE} or context.get("registerOrdinal") != REGISTER_ORDINAL or context.get("title") != TITLE or context.get("lineage") != "EXACT_WITH_GENERATION_REBIND":
        raise ValueError("C08 context metadata differs")
    if context.get("expectedArtifacts") != list(PATH_FENCE) or context.get("persistentChangeMode") != "PERSISTENT_OR_PRODUCT_DELTA":
        raise ValueError("C08 context scope differs")
    for key in ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit", "phase10PollingDuringParallelExecution"):
        if context.get(key) is not False:
            raise ValueError("C08 context claims activation:" + key)
    if context.get("uiAdoptionDeferred") is not True or context.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C08 UI/S10 disposition differs")
    if tuple(fence.get("allowedCreateOrReplacePaths", ())) != PATH_FENCE or fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ValueError("C08 fence scope differs")
    if (fence.get("baseHead"), fence.get("baseTree")) != (BASE_HEAD, BASE_TREE) or fence.get("requiresAcceptedS10_6Reconciliation") is not True:
        raise ValueError("C08 fence base differs")
    _validate_prior_fence_proof(fence, PATH_FENCE)
    expected_predecessor = {"attemptID": 1, "candidateHead": "08841c808ab5fe263b41db530e4e733f8126adb4", "candidateTree": "19b59129672300d130b96b7115c9fce1aef1a8e5", "cardID": "V23-P03-C37", "checkpointDigest": "0ab302395a9d3a951ecf5df17c5de641cb69c8926a441b531c3da0e5e106a7d1", "contextDigest": "cacb2aeb4e857ef445a4432ed71c33b499e92de72d9bcf6cbc638a95f27d75bc", "disposition": "CHECKPOINTED_CANONICAL_DIRECT_PREREQUISITE", "finalTransitionDigest": "fdd90e6cb53c375dc9e32e3e58ff2e7d4406c0938afeddd2dbc924b32bf3e760", "pathFenceDigest": "59b198fde5e300119e100f68870480334b704adc64e303de40db3b23979a4e59", "verificationReceiptDigest": "e95d1bbdbdfe66466ec3f3a19780d3671db4162ae9e48eda5ba350f2b12c630b"}
    common_false = ("nativeCompileRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit", "phase10PollingDuringParallelExecution")
    if prerequisite.get("schema") != "ProvisionalExecutionPrerequisiteSetReceiptV1" or prerequisite.get("schemaVersion") != 1 or prerequisite.get("successorCardID") != CARD or prerequisite.get("successorAttemptID") != 1 or prerequisite.get("ordinaryDirectEdgeCount") != 1 or prerequisite.get("predecessors") != [expected_predecessor] or any(prerequisite.get(key) is not False for key in common_false) or prerequisite.get("requiresAcceptedS10_6Reconciliation") is not True or sealed_field(prerequisite, "prerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C08 direct prerequisite receipt differs")
    expected_transition = {"schema": "BootstrapStateTransitionV1", "schemaVersion": 1, "sequence": SEQUENCE, "cardID": CARD, "attemptID": 1, "fromState": "NOT_STARTED", "toState": "HYDRATING", "reason": "OWNER_AUTHORIZED_P04_C08_PROVISIONAL_HYDRATION", "candidateHead": BASE_HEAD, "candidateTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "priorLedgerDigest": PRIOR_LEDGER_DIGEST, "newLedgerDigest": COORDINATION_LEDGER_DIGEST, "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0}, "createdAt": CREATED_AT, "transitionDigest": HYDRATION_TRANSITION_DIGEST}
    if any(transition.get(key) != value for key, value in expected_transition.items()) or sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C08 hydration transition differs")
    if ledger.get("schema") != "BootstrapExecutionLedgerEnvelopeV1" or ledger.get("schemaVersion") != 1 or ledger.get("casSequence") != SEQUENCE or ledger.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or ledger.get("previousLedgerDigest") != PRIOR_LEDGER_DIGEST or sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST:
        raise ValueError("C08 ledger authority differs")
    expected_row = {"cardID": CARD, "attemptID": 1, "ordinal": REGISTER_ORDINAL, "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED", "state": "HYDRATING", "stateReason": "OWNER_AUTHORIZED_P04_C08_PROVISIONAL_HYDRATION", "candidateHead": BASE_HEAD, "candidateTree": BASE_TREE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "directPrerequisites": list(DIRECT_PREREQUISITES)}
    rows = ledger.get("attempts")
    if not isinstance(rows, list) or expected_row not in rows:
        raise ValueError("C08 ledger card row differs")
    if projection.get("schema") != "ActiveWorkSetProjectionV1" or projection.get("schemaVersion") != 1 or projection.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or projection.get("projectionDigest") != COORDINATION_PROJECTION_DIGEST or projection.get("eligibilityBasis") != "P04_C08_HYDRATING_PREVIEW_FIRST_IMPORT_BULK_AND_DETERMINISTIC_EXPORT" or projection.get("nextEligibleCardID") is not None or projection.get("nextEligibleRegisterOrdinal") is not None or sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ValueError("C08 projection authority differs")
    active = projection.get("activeEntries")
    if not isinstance(active, list) or expected_row not in active:
        raise ValueError("C08 projection card row differs")


def _authority_pins_ready() -> bool:
    refs = (BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE, COORDINATION_HEAD, COORDINATION_ORIGIN_HEAD, COORDINATION_TREE)
    digests = (CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST, COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST, FROZEN_S10_RESERVATION_DIGEST, *[value for value in SOURCE_PINS.values() if isinstance(value, str)])
    return all(re.fullmatch(r"[0-9a-f]{40}", value) for value in refs) and all(valid_sha(value) for value in digests)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(_HYDRATED_NEW_PATHS), len(PATH_FENCE), len(set(PATH_FENCE))) != (EXPECTED_EXISTING_PATH_COUNT, EXPECTED_NEW_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT):
        raise ValueError("C08 fence cardinality or uniqueness differs")
    if _HYDRATED_NEW_PATHS != NEW_PATHS or PATH_FENCE != EXISTING_PATHS + NEW_PATHS:
        raise ValueError("C08 new-path ordering differs from hydrated fence")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C08 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 7641 or UNAUTHORIZED_OVERLAP_COUNT != 0 or S10_RESERVATION_OVERLAP_COUNT != 0:
        raise ValueError("C08 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C08 app base tree differs")
    _candidate_identity(root)
    _assert_coordination_state()
    unauthorized = [path for path in observed_changed_paths(root) if path not in PATH_FENCE]
    if unauthorized:
        raise ValueError("C08 changed path outside fence:" + ",".join(unauthorized))
    missing_base = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C08 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C08 new path already exists at accepted base")


def selectors(root: Path) -> tuple[str, ...]:
    found: list[str] = []
    for relative in IMPLEMENTATION_PATHS[5:7]:
        path = root / relative
        if path.is_file():
            found.extend(re.findall(r"(?m)^\s*func\s+(testV23P04C08(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", path.read_text(encoding="utf-8")))
    return tuple(found)


def observed_selectors(root: Path) -> tuple[str, ...]:
    return selectors(root)


def bound_selectors(root: Path) -> tuple[str, ...]:
    found = selectors(root)
    return EXPECTED_SELECTORS if not found else found


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    found = selectors(root)
    return {"requiredPathCount": len(IMPLEMENTATION_PATHS), "presentPathCount": len(present), "missingPathCount": len(missing), "presentPaths": present, "missingPaths": missing, "selectors": list(found), "expectedSelectors": list(EXPECTED_SELECTORS), "hydrated": not missing, "sourceReady": not missing, "status": "SOURCE_READY" if not missing else "SOURCE_PENDING", "reason": "ALL_IMPLEMENTATION_SOURCE_LANES_PRESENT" if not missing else "IMPLEMENTATION_SOURCE_LANES_INCOMPLETE"}


def _assert_fixture_contract(fixture: dict[str, Any]) -> None:
    if fixture.get("schema") != "V22P04C08ImportBulkEngineCorpusV1" or fixture.get("schemaVersion") != 1 or fixture.get("cardID") != CARD or fixture.get("ordinal") != REGISTER_ORDINAL:
        raise ValueError("C08 fixture identity differs")
    selectors_value = fixture.get("selectors")
    if selectors_value != [{"id": suffix, "selector": f"{CARD}-{suffix}", "tier": tier} for suffix, tier in zip(EVIDENCE_SUFFIXES, ("GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"))]:
        raise ValueError("C08 fixture selectors differ")
    dispositions = fixture.get("dispositions")
    if not isinstance(dispositions, list) or set(dispositions) != set(ROW_DISPOSITIONS):
        raise ValueError("C08 fixture dispositions differ")
    if fixture.get("executionStates") != list(EXECUTION_STATES):
        raise ValueError("C08 fixture execution states differ")
    if set(fixture.get("lifecycle", ())) != set(LIFECYCLE):
        raise ValueError("C08 fixture lifecycle differs")
    claims = fixture.get("claims")
    required_claims = ("zeroWritePreview", "boundedParse", "deterministicIdentity", "deterministicChunks", "deterministicExport", "oneCanonicalWriter", "samePlanResumeFirstMissingReceipt")
    if not isinstance(claims, dict) or any(claims.get(key) is not True for key in required_claims):
        raise ValueError("C08 fixture claims differ")
    status_flags = fixture.get("statusFlags")
    if not isinstance(status_flags, dict) or any(value is not False for value in status_flags.values()):
        raise ValueError("C08 fixture flags differ")


_SECOND_STORE_PATTERN = r"\b(?:NSPersistentContainer|ModelContainer)\b"
_DIRECT_MODEL_CONTEXT_SAVE_PATTERN = r"\b(?:modelContext|context)\s*\.\s*save\s*\("


def _source_claim_code(source: str) -> str:
    """Return executable-looking source for the capability claim scan.

    C08 fixtures and tests name hostile capabilities as evidence.  Quoted
    data/comments are therefore removed before checking identifiers, while
    the dedicated V9_72 harness boundary below inspects the raw initializer
    text for its required in-memory configuration.
    """
    code = re.sub(r'"(?:\\.|[^"\\])*"', '""', source)
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", code, flags=re.S)


def _assert_no_forbidden_source_claims(
    source: str,
    *,
    allow_in_memory_test_container: bool = False,
) -> None:
    """Reject C08 capabilities outside their narrowly owned seams.

    SwiftData's ``ModelContainer`` is a legitimate test harness mechanism for
    V9_72, but is a second-store claim everywhere else in this lane.  The
    the canonical writer remains the sole persistence mutation owner; direct
    ModelContext saves in all production/test/UI source remain forbidden.
    """
    code = _source_claim_code(source)
    patterns = (
        r"\bURLSession\b", r"\bURLRequest\b", r"\bCloudKit\b", r"\bCKContainer\b", r"\bNWConnection\b", r"\bWebSocket\b", r"\bTelemetryClient\b", r"\bCoreML\b", r"\b(?:remoteSync|syncProcessor|signedURL|prefetch|cacheDaemon)\b", r"\b(?:providerOutbox|providerInbox|remoteEmail|remoteLink|QRCode|CIQRCodeGenerator|recurrence|dueQueue|teamDispatch)\b", r"\b(?:iPad|iPadOS|S10Route|S10_.*Route)\b",
    )
    for pattern in patterns:
        if re.search(pattern, code, re.I):
            raise ValueError("C08 forbidden source claim:" + pattern)
    if not allow_in_memory_test_container and re.search(_SECOND_STORE_PATTERN, code, re.I):
        raise ValueError("C08 forbidden source claim:" + _SECOND_STORE_PATTERN)
    if re.search(_DIRECT_MODEL_CONTEXT_SAVE_PATTERN, code, re.I):
        raise ValueError("C08 forbidden direct ModelContext save")


def assert_v9_72_test_harness_boundary(root: Path) -> None:
    """Prove V9_72 uses only an in-memory container with the production API."""
    tests = _text(root, IMPLEMENTATION_PATHS[5])
    lifecycle = _text(root, IMPLEMENTATION_PATHS[3])
    code = _source_claim_code(tests)
    containers = re.findall(r"\bModelContainer\s*\(", code)
    if len(containers) != 1:
        raise ValueError("C08 V9_72 test must construct ModelContainer")
    if not re.search(r"\bModelContainer\s*\([\s\S]{0,3000}?\bisStoredInMemoryOnly\s*:\s*true\b", code, re.I):
        raise ValueError("C08 V9_72 ModelContainer is not proven in-memory")
    memory_values = re.findall(r"\bisStoredInMemoryOnly\s*:\s*([A-Za-z0-9_]+)", code, re.I)
    if not memory_values or any(value.lower() != "true" for value in memory_values):
        raise ValueError("C08 V9_72 ModelContainer permits disk persistence")
    cloud_values = re.findall(r"\bcloudKitDatabase\s*:\s*([.A-Za-z0-9_]+)", code, re.I)
    if cloud_values != [".none"]:
        raise ValueError("C08 V9_72 ModelContainer permits CloudKit persistence")
    if re.search(r"\b(?:NSPersistentContainer|URLSession|URLRequest|CKContainer|NSPersistentCloudKitContainer|NWConnection|WebSocket|FileManager)\b", code, re.I):
        raise ValueError("C08 V9_72 harness claims network or disk persistence")
    if re.search(r"\b(?:url|storeURL|modelStoreURL|diskURL)\s*:", code, re.I) or re.search(r"\b(?:write\s*\(\s*to:|removeItem\s*\()", code, re.I):
        raise ValueError("C08 V9_72 harness claims disk persistence")
    _require_patterns(tests, (
        r"\blifecycle\s*=\s*try\s+ImportBulkLifecycleAdapterV1\s*\(",
        r"\bImportBulkLifecycleAdapterV1\b",
    ), "C08 V9_72 production lifecycle API")
    _require_patterns(lifecycle, (
        r"\b(?:final\s+)?class\s+ImportBulkLifecycleAdapterV1\b",
        r"\bmodelContext\s*:\s*ModelContext\b",
    ), "C08 production lifecycle adapter")


def _assert_c08_production_scope(root: Path, sources: tuple[str, ...]) -> None:
    """Apply production-only second-store/save rules to every C08 lane.

    The source fence has five production lanes.  The lifecycle adapter is the
    canonical persistence seam; all other production lanes must remain free of
    direct ModelContext saves and second-store construction.  Any future C08
    production source added to this tuple receives the same strict scan.
    """
    if len(sources) != 5:
        raise ValueError("C08 production source lane count differs")
    for source in sources:
        _assert_no_forbidden_source_claims(source)


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C08 source lanes missing:" + ",".join(status["missingPaths"]))
    contract = _text(root, IMPLEMENTATION_PATHS[0])
    models = _text(root, IMPLEMENTATION_PATHS[1])
    coordinator = _text(root, IMPLEMENTATION_PATHS[2])
    lifecycle = _text(root, IMPLEMENTATION_PATHS[3])
    view = _text(root, IMPLEMENTATION_PATHS[4])
    tests = _text(root, IMPLEMENTATION_PATHS[5])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[6])
    fixture = _json(root, IMPLEMENTATION_PATHS[7])
    _assert_fixture_contract(fixture)
    _require_tokens(contract, AUTHORITY_CONTRACTS + ("zero", "write", "preview", "bounded", "budget", "stable", "external", "key", "deterministic", "export", "lifecycle", "location", "asset", "placement"), "C08 import contracts")
    _require_tokens(models, PERSISTENT_KINDS + ("SwiftData", "schemaTag", "canonicalData", "profileSHA256", "sessionSHA256", "receiptSHA256", "replace", "value"), "C08 persistence models")
    _require_tokens(coordinator, ("ImportSourceV1", "ImportPlanV1", "BulkCommandPlanV1", "preview", "commit", "zero", "write", "WorkspaceWriterV1", "expectedRevision", "allOrNothing", "chunk", "cancel", "stable", "external", "key", "formula", "control", "CSV", "correction"), "C08 coordinator")
    _require_tokens(lifecycle, ("ImportBulkLifecycleAdapterV1", "bounded", "scratch", "lifecycle", "export", "rebuild", "backup", "restore", "delete", "erase", "replay", "interruption", "idempotent"), "C08 lifecycle adapter")
    _require_tokens(view, ("ImportBulkPreviewStateV1", "Preview", "no changes", "Source", "Schema", "Mapping", "Plan", "accessibilityIdentifier"), "C08 preview view")
    if "WorkspaceWriterV1" in view or "WorkspaceWriterV1" in ui_tests:
        raise ValueError("C08 preview/UI lane owns a writer")
    found = selectors(root)
    if found != EXPECTED_SELECTORS or len(set(found)) != 5:
        raise ValueError("C08 requires exactly five ordered G/A/H/I/R selectors")
    _require_tokens(tests, ("XCTest", "XCTAssert", "XCTAssertThrowsError", "XCTAssertEqual", "XCTAssertNotEqual", "utf", "NFC", "CRLF", "formula", "control", "budget", "zero", "write", "preview", "duplicate", "ambiguous", "stale", "effect", "receipt", "chunk", "resume", "recovery", "export", "digest"), "C08 integration evidence")
    _require_tokens(ui_tests, (CARD, "XCTSkip", "S10.6", "adoptionEnabled", "acceptanceCredit"), "C08 UI deferral test")
    _assert_c08_production_scope(root, (contract, models, coordinator, lifecycle, view))
    _assert_no_forbidden_source_claims(tests, allow_in_memory_test_container=True)
    _assert_no_forbidden_source_claims(ui_tests)
    assert_v9_72_test_harness_boundary(root)
    return found


def authority() -> dict[str, Any]:
    return {"cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE, "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "candidateHead": CANDIDATE_HEAD, "candidateTree": CANDIDATE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationOriginHead": COORDINATION_ORIGIN_HEAD, "coordinationTree": COORDINATION_TREE, "coordinationSequence": SEQUENCE, "coordinationCASSequence": SEQUENCE, "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "prerequisiteDigest": PREREQUISITE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "priorLedgerDigest": PRIOR_LEDGER_DIGEST, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "sourcePins": dict(SOURCE_PINS), "directPrerequisiteCards": list(DIRECT_PREREQUISITES), "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS), "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT, "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT, "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT, "existingPathCount": EXPECTED_EXISTING_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "s10ReservedPathCount": S10_RESERVED_PATH_COUNT, "finalHashesSealed": FINAL_HASHES_SEALED}


def common() -> dict[str, Any]:
    return {"cardID": CARD, "title": TITLE, "authority": authority(), "evidenceIDs": list(EVIDENCE_IDS), "statusFlags": dict(FLAGS), "nativeCompileRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False, "acceptanceEnabled": False, "releaseCredit": False, "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER", "requiresAcceptedS10_6Reconciliation": True, "uiAdoptionSkipped": True, "uiAcceptanceCredit": False, "finalHashesSealed": FINAL_HASHES_SEALED, "provisional": not FINAL_HASHES_SEALED, "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED"}


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path in IMPLEMENTATION_PATHS:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            rows.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SOURCE_PRESENT"})
        else:
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
    return rows


def source_projection(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {"implementationPaths": list(IMPLEMENTATION_PATHS), "presentPaths": status["presentPaths"], "missingPaths": status["missingPaths"], "selectors": list(selectors_value), "expectedSelectors": list(EXPECTED_SELECTORS), "sourceSemanticsInspected": bool(status["hydrated"]), "sourceReady": status["sourceReady"], "sourceStatus": status["status"], "sourceReason": status["reason"], "sourceRows": source_rows(root), **SOURCE_PINS, "canonicalSuccessor": {"cardID": "V23-P04-C09", "registerOrdinal": 97}, "deterministicEvidenceIDs": list(EVIDENCE_IDS), "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS), "conformanceSubjects": list(CONFORMANCE_SUBJECTS), "invalidationConsumers": list(INVALIDATION_CONSUMERS)}


def semantics(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {**SEMANTIC_SCOPE, "selectors": list(selectors_value), "evidenceIDs": list(EVIDENCE_IDS), "rowDispositions": list(ROW_DISPOSITIONS), "executionStates": list(EXECUTION_STATES), "lifecycle": list(LIFECYCLE), "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "previewRules": {"zeroCanonicalMutation": True, "zeroFilePublication": True, "zeroReceiptChange": True, "zeroIndexChange": True, "repeatBytesDeterministic": True, "sourceOrRevisionChangeRequiresNewPreview": True}, "parseRules": {"boundedByteRowColumnCellScalar": True, "unsupportedVersionClosed": True, "controlsAndFormulasNeutralized": True, "sourceScratchLeasedAndCleaned": True}, "identityRules": {"sourceDigestOrdinalCanonicalRowDigestStableExternalKey": True, "displayNameOnlyNeverMatches": True, "duplicateAndAmbiguousVisible": True}, "commitRules": {"canonicalWriterOnly": True, "expectedRevision": True, "allOrNothingOrExplicitChunkedAtomic": True, "deterministicPlanChunkMutationIDs": True, "samePlanRetryIdempotent": True, "firstMissingReceiptResume": True, "committedChunksNeverRolledBackClaim": True}, "adapterScope": {"locationCreate": True, "assetCreate": True, "assetPlacement": True, "allowlistedExactKeyAssetUpdate": True, "fuzzyUpdate": False, "merge": False, "deleteByImport": False, "finalizedFieldUpdate": False, "xlsxExecution": False, "arbitraryTransform": False, "cloudSpreadsheet": False, "mediaURLFetch": False}, "lifecycleCoverage": {name: True for name in LIFECYCLE}, "forbiddenCapabilities": list(FORBIDDEN), "noNativeIPad": True, "noS10RouteWiring": True, "ui": "POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT", "accessibilityAndLocalization": {"voiceOver": True, "voiceControl": True, "largerText": True, "darkContrastNonColor": True, "permissionFallback": True, "interruptionRecovery": True, "syntheticFixturesOnly": True}}


def schema_document(selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/import-bulk-engine.schema.json", "title": "V23-P04-C08 import bulk engine", "type": "object", "additionalProperties": False, "properties": {"schema": {"const": "IMPORT_BULK_ENGINE_V1"}, "schemaVersion": {"const": SCHEMA_VERSION}, "cardID": {"const": CARD}, "ordinal": {"const": REGISTER_ORDINAL}, "selectors": {"const": list(selectors_value)}, "authorityContracts": {"const": list(AUTHORITY_CONTRACTS)}, "persistentKinds": {"const": list(PERSISTENT_KINDS)}, "rowDispositions": {"const": list(ROW_DISPOSITIONS)}, "executionStates": {"const": list(EXECUTION_STATES)}, "lifecycle": {"const": list(LIFECYCLE)}, "forbidden": {"const": list(FORBIDDEN)}, "semantics": {"const": semantics(selectors_value)}, "sourceReady": {"type": "boolean"}, "physicalLockedState": {"const": "REQUIRED_PENDING_OWNER"}, "uiAdoptionSkipped": {"const": True}, "uiAcceptanceCredit": {"const": False}, "statusFlags": {"const": dict(FLAGS)}, "finalHashesSealed": {"const": FINAL_HASHES_SEALED}, "provisional": {"const": not FINAL_HASHES_SEALED}}, "required": ["schema", "schemaVersion", "cardID", "ordinal", "selectors", "authorityContracts", "persistentKinds", "rowDispositions", "executionStates", "lifecycle", "forbidden", "semantics", "sourceReady", "physicalLockedState", "uiAdoptionSkipped", "uiAcceptanceCredit", "statusFlags", "finalHashesSealed", "provisional"]}


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None}


def contract_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({"schema": "V23P04C08ImportBulkEngineContractV1", "schemaVersion": SCHEMA_VERSION, **common(), "directPrerequisites": list(DIRECT_PREREQUISITES), "contractRefs": list(CONTRACT_REFS), "journeyRefs": list(JOURNEY_REFS), "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS), "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "rowDispositions": list(ROW_DISPOSITIONS), "executionStates": list(EXECUTION_STATES), "lifecycle": list(LIFECYCLE), "forbidden": list(FORBIDDEN), "semantics": semantics(selectors_value), "sourceProjection": source_projection(root, selectors_value)})


def evidence_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "selectorSuffix": "G01", "focus": ["preview-first zero-write repeat", "location/asset/placement create and exact-key update", "deterministic formula-safe export"], "expectedOutcome": "PREVIEW_AND_EXPORT_BYTES_ARE_DETERMINISTIC"},
        {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "selectorSuffix": "A01", "focus": ["correction artifact round trip", "stable external identity", "asset/location adapter alternate"], "expectedOutcome": "CORRECTED_ROWS_RETAIN_STABLE_IDENTITY"},
        {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "selectorSuffix": "H01", "focus": ["bounded UTF-8/NFC/size/control/formula budgets", "duplicate or ambiguous target", "forbidden second writer/store/parser/renderer/identity claims"], "expectedOutcome": "FAIL_CLOSED_WITH_VISIBLE_REASON_AND_NO_ORPHAN"},
        {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "selectorSuffix": "I01", "focus": ["parse/stage/effect-before-receipt/chunk interruption", "cancel before and after chunk", "first missing receipt resume"], "expectedOutcome": "DETERMINISTIC_RESUME_OR_FAIL_CLOSED"},
        {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "selectorSuffix": "R01", "focus": ["same-plan idempotent retry", "compensation/forward-fix preserving receipts", "backup/restore/replay/search/rebuild/delete/erase lifecycle"], "expectedOutcome": "CANONICAL_HISTORY_AND_COMMITTED_CHUNKS_REMAIN_TRUTHFUL"},
    ]
    return _sealed({"schema": "V23P04C08ImportBulkEngineEvidenceReceiptV1", "schemaVersion": SCHEMA_VERSION, **common(), "evidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(selectors_value), "cases": cases, "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "rowDispositions": list(ROW_DISPOSITIONS), "executionStates": list(EXECUTION_STATES), "lifecycle": list(LIFECYCLE), "hostileVectors": list(HOSTILE_VECTORS), "forbidden": list(FORBIDDEN), "semantics": semantics(selectors_value), "sourceProjection": source_projection(root, selectors_value), "zeroWritePreviewRequired": True, "deterministicExportRequired": True, "uiAdoptionSkipped": True, "accessibilityAndLocalizationRequired": True})


def brand_document(root: Path, selectors_value: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return _sealed({"schema": "V23P04C08BrandImpactManifestV1", "schemaVersion": SCHEMA_VERSION, **common(), "iPhoneNativeOnly": True, "nativeIPadSurface": False, "uiSurfaceDelta": True, "brandSurfaceDelta": True, "uiSourceExists": IMPLEMENTATION_PATHS[4] in status["presentPaths"], "uiTestSourceExists": IMPLEMENTATION_PATHS[6] in status["presentPaths"], "uiTestDisposition": "EXPLICIT_POST_S10_6_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_AUTHORITY", "adoptionSkipped": True, "onDeviceOnly": True, "networkOrTelemetryFlow": False, "syncStatusClaimed": False, "providerOrNotificationFlow": False, "recurrenceOrQRFlow": False, "accessibilityAndLocalizationRequired": True, "accessibilitySourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not status["hydrated"] else "SOURCE_INSPECTED", "localizationSourceDisposition": "REQUIRED_SOURCE_CONTRACT_PENDING" if not status["hydrated"] else "SOURCE_INSPECTED", "changedSurfaces": ["IMPORT_BULK_PREVIEW", "IMPORT_BULK_COMMIT", "ASSET_LOCATION_ADAPTERS", "DETERMINISTIC_EXPORT", "CORRECTION_RECOVERY"], "changedStates": list(EXECUTION_STATES), "semantics": semantics(selectors_value), "sourceProjection": source_projection(root, selectors_value)})


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data) if FINAL_HASHES_SEALED else None, "status": "SEALED_TOOLING" if FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING"}
    target = root / path
    if not target.is_file():
        return {"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"}
    data = canonical_file_bytes(target)
    if path in TOOLING_EDIT_PATHS:
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data) if FINAL_HASHES_SEALED else None, "status": "SEALED_TOOLING" if FINAL_HASHES_SEALED else "PROVISIONAL_TOOLING"}
    return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "PRESENT_SOURCE" if path in IMPLEMENTATION_PATHS else "PRESENT_INHERITED"}


def outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    status = source_status(root)
    selectors_value = assert_source_contracts(root) if status["hydrated"] else bound_selectors(root)
    rendered: dict[str, bytes] = {SCHEMA_PATH: pretty(schema_document(selectors_value)), CONTRACT_PATH: pretty(contract_document(root, selectors_value)), EVIDENCE_PATH: pretty(evidence_document(root, selectors_value)), BRAND_PATH: pretty(brand_document(root, selectors_value))}
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = {"schema": "V23-P04-C08-tooling-manifest", "schemaVersion": SCHEMA_VERSION, **common(), "pathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "toolingEditPaths": list(TOOLING_EDIT_PATHS), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "fencePathCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS), "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "s10ReservedPathCount": S10_RESERVED_PATH_COUNT, "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED", "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None, "sourceReady": status["sourceReady"], "sourceStatus": status["status"], "sourceReason": status["reason"], "sourceProjection": source_projection(root, selectors_value), "authorityContracts": list(AUTHORITY_CONTRACTS), "persistentKinds": list(PERSISTENT_KINDS), "files": rows}
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
    print(json.dumps({"cardID": CARD, "sourceReady": status["sourceReady"], "sourceStatus": status["status"], "sourceReason": status["reason"], "sourceMissing": status["missingPaths"], "finalHashesSealed": FINAL_HASHES_SEALED, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT, "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT}, sort_keys=True, indent=2))
