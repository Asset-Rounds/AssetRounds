#!/usr/bin/env python3
"""Fail-closed static tooling for V23-P04-C03.

The C03 implementation is a nonpersistent, digest-bound illuminated-sign
sidecar.  This module is deliberately independent of the product build: it
binds the hydrated coordination fence, checks the source-owned contracts once
the seven implementation paths arrive, and renders deterministic schema,
evidence, brand, and inventory artifacts.
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
CARD = "V23-P04-C03"
TITLE = "Illuminated-sign playbooks and structured report facts"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 91

# Immutable app and coordination hydration authority.
BASE_HEAD = "2546d4af374a83b93a5e655445cc8d58e8921285"
BASE_TREE = "ee3935607a0f3b0f2a76518e4648a0955aa139cc"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "777c996bbb27064d0e9662a4860b6b22b9ae6d4a"
COORDINATION_TREE = "e981260ca4110eea9cb31a1b26bd2526cc2c531b"
COORDINATION_ORIGIN_HEAD = COORDINATION_HEAD
COORDINATION_CAS_SEQUENCE = 398
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "36a4f58d89bbc30a04fd9007d77ed1eebfb6c0986eab503d9ca1bd0b6fc68857"
CONTEXT_DIGEST = "ca36dbada09e3d994554ea651ad31d4fb08d3f2bdb49862ec2edc510bbefe7fd"
FENCE_DIGEST = "700e01cf30f6e0d24e2e699beefbbd986932d08290d56456fb4a1495725bb59f"
HYDRATION_TRANSITION_DIGEST = "d689fd1b4219b4a6a1d2c8be31e60a7aaa52141dc66c89aeadf6f291f40335f9"
COORDINATION_LEDGER_DIGEST = "d674bb38fc5779cf71ee0c9ad192f51375bd779d0cf55364ddc778a0058ea913"
COORDINATION_PROJECTION_DIGEST = "a1cbfe8a048b37f5f9e348c2a23b22cacb438ddb08f6bce70bf55d2e0be1b5fc"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

DOSSIER_SHA256 = "3e5a1662853a726a3ce8a9af4202b01db278d5543c0732aea82ccfcc672b2ecf"
DOSSIER_BYTES = 7223
INHERITED_V21_BLOCK_SHA256 = "e3e010efcb02ab5ef26b68069827369abecb05ad7243e8e050aa97f925e51c12"
INHERITED_V21_BLOCK_BYTES = 8498
REGISTER_ROW_SHA256 = "2b59a34dc9d3f55bf79760450a087920349fb6dc542b07d329fba0859c85e883"
REGISTER_ROW_BYTES = 266
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217

EXPECTED_EXISTING_PATH_COUNT = 288
EXPECTED_NEW_PATH_COUNT = 15
EXPECTED_FENCE_PATH_COUNT = 303
AUTHORIZED_OVERLAP_COUNT = 5906
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 91
PRIOR_OWNED_PATH_COUNT = 1443
S10_RESERVED_PATH_COUNT = 86

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Packs/IlluminatedSignPlaybookContractsV1.swift",
    "FieldEvidenceApp/Application/Packs/IlluminatedSignPlaybookCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/IlluminatedSignReportProjectionV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/IlluminatedSignPlaybookView.swift",
    "FieldEvidenceAppTests/V9_68IlluminatedSignPlaybookTests.swift",
    "FieldEvidenceAppUITests/V23_P04_C03IlluminatedSignPlaybookUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/IlluminatedSignPlaybook/V22P04C03IlluminatedSignPlaybookCorpusV1.json",
)
SCHEMA_PATH = "Scripts/v23/illuminated-sign-playbook.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C03IlluminatedSignPlaybookContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C03IlluminatedSignPlaybookEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C03BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C03-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c03_contracts.py",
    "Scripts/v23/generate_p04_c03_contracts.py",
    "Scripts/v23/verify_p04_c03_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
# Exported for verifiers and downstream static consumers.
OUTPUT_PATHS = GENERATED_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C03-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C03-attempt-1/BootstrapPathFenceV1.json"
_PREREQUISITE_RELATIVE = "receipts/V23-P04-C02-and-V23-P03-C37-to-V23-P04-C03-provisional-prerequisite.json"
_TRANSITION_RELATIVE = "transitions/000398-V23-P04-C03-attempt-1-NOT_STARTED-to-HYDRATING.json"
_LEDGER_RELATIVE = "state/BootstrapExecutionLedgerEnvelopeV1.json"
_PROJECTION_RELATIVE = "projections/ActiveWorkSetProjectionV1.json"

PLAYBOOK_IDS = (
    "general_visible_condition",
    "dark_section",
    "dim_or_uneven",
    "flicker_or_intermittent",
    "color_mismatch",
    "physical_damage",
    "other_visible_condition",
)
CAPTURE_SLOTS = ("wide_context", "close_detail", "work_context")
EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
JOURNEY_REFS = ("CommonTaskJourneyReleaseV2",)
DIRECT_PREREQUISITES = ("V23-P04-C02", "V23-P03-C37")
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
AGGREGATE_MEMBERSHIPS = (
    "AutonomousRequiredAcceptedSetV1",
    "P04ShippingSurfaceSetV1",
    "P04BrandClosureSetV1",
)
CONFORMANCE_SUBJECTS = ("P04ShippingSurfaceSetV1", "CommonTaskJourneyReleaseV2")
INVALIDATION_CONSUMERS = (
    "V23-P04-C04",
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C03).CONTRACTS",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
    "IlluminatedSignPack@1",
    "FieldDraftCheckpointV1",
    "PoseAxisDescriptorV1",
    "AssetPoseEventV1",
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
C03_LIFECYCLE = {
    "persistence": "NONPERSISTENT_DIGEST_BOUND_SIDECAR",
    "schema": "NOT_APPLICABLE",
    "store": "NOT_APPLICABLE",
    "writer": "INCUMBENT_FIELD_DRAFT_AND_POSE_AUTHORITIES",
    "evidence": "INCUMBENT_C05_EVIDENCE_METADATA_AUTHORITY",
    "backupRestoreDeleteErase": "NOT_APPLICABLE_DERIVED_FROM_DURABLE_AUTHORITIES",
    "networkDependency": False,
    "certificationAuthority": False,
}
PERSISTENCE = {
    "mode": "NONE_NONPERSISTENT_SIDECAR",
    "contentMode": "CONTENT_ONLY",
    "schemaVersionDelta": False,
    "recordsSchemaVersionDelta": False,
    "durableFamilyDelta": False,
    "persistentStoreWriter": "NONE_CARD_LOCAL",
    "incumbentFieldDraftAuthority": "FieldDraftCheckpointV1",
    "incumbentPoseAuthority": "V23-P03-C37",
    "incumbentEvidenceAuthority": "V23-P03-C05",
    "backupRestoreDeleteErase": "DERIVED_FROM_DURABLE_AUTHORITIES",
    "plansAndProjections": "NONPERSISTENT",
    "searchRebuild": "NO_NEW_INDEX_DERIVED_ONLY",
    "journalReplay": "C36_CHECKPOINT_AND_C05_ASSOCIATION_REPLAY",
}
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

# This remains false during hydration/source churn.  A later explicitly
# released sealing pass may change only this owned script constant after every
# source row is present and stable.
FINAL_HASHES_SEALED = True

DIRECT_PREREQUISITE_ROWS = (
    {
        "attemptID": 1,
        "candidateHead": "2546d4af374a83b93a5e655445cc8d58e8921285",
        "candidateTree": "ee3935607a0f3b0f2a76518e4648a0955aa139cc",
        "cardID": "V23-P04-C02",
        "checkpointDigest": "5921ccecd027c0f2cdfb6279f16817b683062b00a07d8bda97597a0a9c933253",
        "contextDigest": "69b4a6c0aa7c6a30431d28dddc4542d4178bed5f5ba2a5fc36b8925fb7f14f89",
        "disposition": "CHECKPOINTED_CANONICAL_DIRECT_PREREQUISITE",
        "finalTransitionDigest": "4a572e840f02a22c22f3fed0c76d82c7807d19b774f9e66366efbf184380bc25",
        "pathFenceDigest": "d978809591e63a7e74235a7e1029d546286aadc0bccdeed8bfb4ce2bb38d5768",
        "verificationReceiptDigest": "81fb14bc312d1b3c2ddc8f066b54cec3827e93ab19b7923f3a92c6094c489de9",
    },
    {
        "attemptID": 1,
        "candidateHead": "08841c808ab5fe263b41db530e4e733f8126adb4",
        "candidateTree": "19b59129672300d130b96b7115c9fce1aef1a8e5",
        "cardID": "V23-P03-C37",
        "checkpointDigest": "0ab302395a9d3a951ecf5df17c5de641cb69c8926a441b531c3da0e5e106a7d1",
        "contextDigest": "cacb2aeb4e857ef445a4432ed71c33b499e92de72d9bcf6cbc638a95f27d75bc",
        "disposition": "CHECKPOINTED_CANONICAL_DIRECT_PREREQUISITE",
        "finalTransitionDigest": "fdd90e6cb53c375dc9e32e3e58ff2e7d4406c0938afeddd2dbc924b32bf3e760",
        "pathFenceDigest": "59b198fde5e300119e100f68870480334b704adc64e303de40db3b23979a4e59",
        "verificationReceiptDigest": "e95d1bbdbdfe66466ec3f3a19780d3671db4162ae9e48eda5ba350f2b12c630b",
    },
)

_BASE_PATH_CACHE: frozenset[str] | None = None
_CANONICAL_TEXT_SUFFIXES = frozenset({
    ".csv", ".entitlements", ".json", ".md", ".pbxproj", ".plist", ".ps1",
    ".py", ".sh", ".strings", ".swift", ".toml", ".txt", ".xcstrings",
    ".xcscheme", ".yaml", ".yml",
})


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def canonical_file_bytes(path: Path) -> bytes:
    """Hash text with LF semantics while preserving binary bytes exactly."""
    data = path.read_bytes()
    if path.suffix.lower() in _CANONICAL_TEXT_SUFFIXES:
        return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data


def _normalized_text(data: bytes, relative: str) -> str:
    if data.startswith(b"\xef\xbb\xbf"):
        raise ValueError("UTF8 BOM:" + relative)
    try:
        return data.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
    except UnicodeDecodeError as exc:
        raise ValueError("UTF8 decode failed:" + relative) from exc


def _valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _coordination_root() -> Path:
    candidates = (
        Path(r"C:\AssetRounds-v23-coordination"),
        ROOT.parent / "AssetRounds-v23-coordination",
    )
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C03 coordination fence is unavailable")


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ValueError("C03 coordination input is unavailable:" + relative)
    value = json.loads(
        _normalized_text(path.read_bytes(), relative),
        object_pairs_hook=_strict_pairs,
    )
    if not isinstance(value, dict):
        raise ValueError("C03 coordination object required:" + relative)
    return value


def _sealed_field(value: dict[str, Any], field: str) -> str:
    unsigned = {key: item for key, item in value.items() if key != field}
    return sha256_bytes((json.dumps(
        unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ) + "\n").encode("utf-8"))


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C03 context digest/card mismatch")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST:
        raise ValueError("C03 path fence digest/card mismatch")
    if _sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C03 context seal differs")
    if _sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ValueError("C03 fence seal differs")
    existing = tuple(context.get("existingPaths", ()))
    fenced_existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(context.get("newPaths", ()))
    fenced_new = tuple(fence.get("newPaths", ()))
    allowed = tuple(fence.get("allowedCreateOrReplacePaths", ()))
    if existing != fenced_existing or hydrated_new != fenced_new:
        raise ValueError("C03 context/fence path sets differ")
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C03 existing path fence cardinality differs")
    # Hydration appends this card's complete fifteen-path slice after the
    # inherited 288-path prefix.  The manifest path is not moved specially;
    # it is self-excluded only when rows are rendered.
    expected_allowed = existing + hydrated_new
    if hydrated_new != NEW_PATHS or allowed != expected_allowed:
        raise ValueError("C03 hydrated new-path ordering differs")
    if tuple(context.get("expectedArtifacts", ())) != allowed:
        raise ValueError("C03 expected-artifact ordering differs")
    if context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C03 prerequisite digest differs")
    if tuple(context.get("directPrerequisites", ())) != DIRECT_PREREQUISITES:
        raise ValueError("C03 direct prerequisites differ")
    semantic = context.get("semanticScope", {})
    expected_semantic = {
        "eighthPlaybookForbidden": True,
        "illuminatedPack": "CANONICAL_CURRENT_OWNER",
        "playbookCount": 7,
        "reportProjection": "DERIVED_GUIDANCE_ONLY",
        "state": "NONPERSISTENT_SIDECAR_ONLY",
        "storeWriterSchemaDelta": "NONE",
        "uiAdoption": "POST_S10_SKIP_NO_RESERVED_COMPOSITION_EDIT",
    }
    if semantic != expected_semantic:
        raise ValueError("C03 semantic scope differs")
    source_projection = context.get("sourceProjection", {})
    for key, expected in {
        "dossierSHA256": DOSSIER_SHA256,
        "dossierUTF8Length": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
        "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowUTF8Length": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionUTF8Length": REGISTER_SECTION_BYTES,
    }.items():
        if source_projection.get(key) != expected:
            raise ValueError("C03 source projection differs:" + key)
    reserved = tuple(fence.get("activeS10ReservedPaths", ()))
    if (
        fence.get("frozenS10ReservationDigest") != FROZEN_S10_RESERVATION_DIGEST
        or len(reserved) != S10_RESERVED_PATH_COUNT
        or set(existing + hydrated_new) & set(reserved)
    ):
        raise ValueError("C03 S10 reservation or overlap differs")
    return existing, hydrated_new


EXISTING_PATHS, _HYDRATED_NEW_PATHS = _load_hydrated_paths()
# Preserve the sealed ordering exactly as hydrated: all 288 inherited paths,
# followed by this card's complete 15-path slice.  NEW_PATHS is checked against
# that hydrated suffix by assert_scaffold, but never used to reorder it here.
PATH_FENCE = EXISTING_PATHS + _HYDRATED_NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return _normalized_text(path.read_bytes(), relative)


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_text(root, relative), object_pairs_hook=_strict_pairs)
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


def _git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()


def _base_exists(root: Path, relative: str) -> bool:
    global _BASE_PATH_CACHE
    if _BASE_PATH_CACHE is None:
        listing = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", BASE_HEAD],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout
        _BASE_PATH_CACHE = frozenset(
            line.strip().replace("\\", "/")
            for line in listing.splitlines() if line.strip()
        )
    return relative in _BASE_PATH_CACHE


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed: set[str] = set()
    commands = (
        ("diff", "--name-only", BASE_HEAD, "--"),
        ("diff", "--cached", "--name-only", "--"),
        ("ls-files", "--others", "--exclude-standard"),
    )
    for command in commands:
        result = subprocess.run(
            ["git", *command], cwd=root, check=True, capture_output=True, text=True,
        )
        changed.update(
            line.strip().replace("\\", "/")
            for line in result.stdout.splitlines() if line.strip()
        )
    return tuple(sorted(changed))


def _candidate_identity(root: Path) -> None:
    if _git(root, "show", "-s", "--format=%T", CANDIDATE_HEAD) != CANDIDATE_TREE:
        raise ValueError("C03 candidate tree differs from accepted base")
    observed_head = _git(root, "rev-parse", "HEAD")
    if observed_head != BASE_HEAD:
        if subprocess.run(
            ["git", "merge-base", "--is-ancestor", BASE_HEAD, observed_head],
            cwd=root,
        ).returncode != 0:
            raise ValueError("C03 candidate is not a descendant of accepted base")


def _assert_coordination_state() -> None:
    coordination = _coordination_root()
    if (
        _git(coordination, "rev-parse", "HEAD") != COORDINATION_HEAD
        or _git(coordination, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE
    ):
        raise ValueError("C03 coordination HEAD/tree differs")
    origin = _git(coordination, "ls-remote", "origin", "refs/heads/main").split()
    if not origin or origin[0] != COORDINATION_ORIGIN_HEAD:
        raise ValueError("C03 coordination origin/main differs")

    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    prerequisite = _coordination_json(_PREREQUISITE_RELATIVE)
    transition = _coordination_json(_TRANSITION_RELATIVE)
    ledger = _coordination_json(_LEDGER_RELATIVE)
    projection = _coordination_json(_PROJECTION_RELATIVE)
    if _sealed_field(prerequisite, "prerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C03 prerequisite receipt seal differs")
    if (
        prerequisite.get("schema") != "ProvisionalExecutionPrerequisiteSetReceiptV1"
        or prerequisite.get("successorCardID") != CARD
        or prerequisite.get("successorAttemptID") != 1
        or prerequisite.get("ordinaryDirectEdgeCount") != 2
        or prerequisite.get("predecessors") != list(DIRECT_PREREQUISITE_ROWS)
    ):
        raise ValueError("C03 direct prerequisite receipt differs")
    if (
        context.get("contextDigest") != CONTEXT_DIGEST
        or fence.get("fenceDigest") != FENCE_DIGEST
        or context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST
    ):
        raise ValueError("C03 context/fence bindings differ")
    proof = fence.get("priorFenceProof", {})
    for key, expected in (
        ("fenceCount", PRIOR_FENCE_COUNT),
        ("priorOwnedPathCount", PRIOR_OWNED_PATH_COUNT),
        ("authorizedOverlapCount", AUTHORIZED_OVERLAP_COUNT),
        ("unauthorizedOverlapCount", UNAUTHORIZED_OVERLAP_COUNT),
        ("overlapCount", AUTHORIZED_OVERLAP_COUNT),
    ):
        if proof.get(key) != expected:
            raise ValueError("C03 prior fence proof differs:" + key)
    if any(
        fence.get(key) is not False
        for key in ("acceptanceCredit", "acceptanceEnabled", "adoptionEnabled",
                    "hostedDispatchEnabled", "nativeCompileRan", "releaseCredit",
                    "phase10PollingDuringParallelExecution", "physicalEvidenceComplete")
    ):
        raise ValueError("C03 fence claims activation")
    if (
        transition.get("cardID") != CARD
        or transition.get("attemptID") != 1
        or transition.get("sequence") != COORDINATION_CAS_SEQUENCE
        or transition.get("fromState") != "NOT_STARTED"
        or transition.get("toState") != "HYDRATING"
        or transition.get("candidateHead") != BASE_HEAD
        or transition.get("candidateTree") != BASE_TREE
        or transition.get("contextDigest") != CONTEXT_DIGEST
        or transition.get("pathFenceDigest") != FENCE_DIGEST
        or transition.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST
        or transition.get("newLedgerDigest") != COORDINATION_LEDGER_DIGEST
        or transition.get("transitionDigest") != HYDRATION_TRANSITION_DIGEST
    ):
        raise ValueError("C03 hydration transition differs")
    if _sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C03 hydration transition seal differs")
    if (
        ledger.get("schema") != "BootstrapExecutionLedgerEnvelopeV1"
        or ledger.get("casSequence") != COORDINATION_CAS_SEQUENCE
        or ledger.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST
        or ledger.get("previousLedgerDigest") != transition.get("priorLedgerDigest")
    ):
        raise ValueError("C03 ledger authority differs")
    if _sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST:
        raise ValueError("C03 ledger seal differs")
    if (
        projection.get("schema") != "ActiveWorkSetProjectionV1"
        or projection.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST
        or projection.get("projectionDigest") != COORDINATION_PROJECTION_DIGEST
        or projection.get("eligibilityBasis")
        != "P04_C03_HYDRATING_ILLUMINATED_SIGN_SEVEN_PLAYBOOK_NONPERSISTENT_SIDECAR"
    ):
        raise ValueError("C03 projection authority differs")
    if _sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ValueError("C03 projection seal differs")


def _assert_design_slices(root: Path) -> None:
    blueprint = _text(root, "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    plan = _text(root, "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    start = blueprint.index('<a id="v23-p04-c03"></a>')
    end = blueprint.index('<a id="v23-p04-c04"></a>', start)
    dossier = blueprint[start:end].rstrip() + "\n"
    inherited_start = blueprint.index("    ### V21-P04-C03 —")
    inherited_end = blueprint.index("    ### V21-P04-C04 —", inherited_start)
    inherited = blueprint[inherited_start:inherited_end].rstrip() + "\n"
    row = next(line for line in plan.splitlines() if line.startswith("| 91 |")) + "\n"
    for label, value, expected_bytes, expected_sha in (
        ("dossier", dossier, DOSSIER_BYTES, DOSSIER_SHA256),
        ("inherited", inherited, INHERITED_V21_BLOCK_BYTES, INHERITED_V21_BLOCK_SHA256),
        ("register row", row, REGISTER_ROW_BYTES, REGISTER_ROW_SHA256),
    ):
        data = value.encode("utf-8")
        if (len(data), sha256_bytes(data)) != (expected_bytes, expected_sha):
            raise ValueError("C03 design slice differs:" + label)


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    selectors = observed_selectors(root)
    return {
        "requiredPathCount": len(IMPLEMENTATION_PATHS),
        "presentPathCount": len(present),
        "missingPathCount": len(missing),
        "presentPaths": present,
        "missingPaths": missing,
        "selectors": list(selectors),
        "hydrated": not missing,
    }


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    text = _normalized_text(path.read_bytes(), IMPLEMENTATION_PATHS[4])
    return tuple(re.findall(
        r"(?m)^\s*func\s+(testV23P04C03(?:G|A|H|I|R)01[A-Za-z0-9_]*)\s*\(",
        text,
    ))


def _assert_exact_selectors(tests: str) -> tuple[str, ...]:
    selectors = tuple(re.findall(
        r"(?m)^\s*func\s+(testV23P04C03(?:G|A|H|I|R)01[A-Za-z0-9_]*)\s*\(",
        tests,
    ))
    suffixes = tuple(
        selector[len("testV23P04C03"):len("testV23P04C03") + 3]
        for selector in selectors
    )
    if (
        len(selectors) != 5
        or suffixes != SELECTOR_SUFFIXES
        or len(set(selectors)) != 5
    ):
        raise ValueError("C03 requires exactly five ordered G/A/H/I/R selectors")
    return selectors


def _assert_fixture_contract(fixture: dict[str, Any]) -> None:
    if (
        fixture.get("schema") != "V22P04C03IlluminatedSignPlaybookCorpusV1"
        or fixture.get("schemaVersion") != 1
        or fixture.get("cardID") != CARD
        or fixture.get("ordinal") != REGISTER_ORDINAL
    ):
        raise ValueError("C03 fixture identity differs")
    if fixture.get("contentMode") not in (
        "CONTENT_ONLY", "NONPERSISTENT_DIGEST_BOUND_SIDECAR",
    ):
        raise ValueError("C03 fixture content mode differs")
    ids = fixture.get("playbookIDs")
    if ids is None:
        rows = fixture.get("playbooks")
        if isinstance(rows, list):
            ids = [
                row.get("id", row.get("playbookID"))
                for row in rows if isinstance(row, dict)
            ]
    if ids != list(PLAYBOOK_IDS):
        raise ValueError("C03 fixture must contain exact seven playbooks")
    selectors = fixture.get("selectors", fixture.get("evidenceSelectors"))
    if not isinstance(selectors, list) or len(selectors) != 5:
        raise ValueError("C03 fixture selector inventory differs")
    observed = []
    for index, row in enumerate(selectors):
        if isinstance(row, dict):
            identifier = row.get("id", row.get("suffix"))
            selector = row.get("selector", row.get("test"))
        else:
            identifier = None
            selector = row
        suffix = EVIDENCE_SUFFIXES[index]
        if identifier not in (suffix, f"{CARD}-{suffix}") or selector not in (
            f"{CARD}-{suffix}", f"test{CARD.replace('-', '')}{suffix}01",
        ):
            raise ValueError("C03 fixture selector row differs:" + suffix)
        observed.append(suffix)
    if tuple(observed) != EVIDENCE_SUFFIXES:
        raise ValueError("C03 fixture selector order differs")
    if fixture.get("eighthPlaybookForbidden") is not True:
        raise ValueError("C03 fixture eighth-playbook guard missing")
    lifecycle = fixture.get("lifecycle")
    if lifecycle is not None and lifecycle != C03_LIFECYCLE:
        raise ValueError("C03 fixture lifecycle differs")
    forbidden = fixture.get("forbidden", fixture.get("forbiddenCapabilities", []))
    text = json.dumps(fixture, ensure_ascii=False, sort_keys=True).lower()
    for token in (
        "diagnosis", "electrical", "safety", "professional certification",
        "network", "telemetry", "unbounded",
    ):
        if token not in text and token.upper() not in {str(x).upper() for x in forbidden}:
            raise ValueError("C03 fixture prohibition missing:" + token)
    if fixture.get("uiAdoptionEnabled") is not False:
        raise ValueError("C03 fixture UI adoption is not disabled")


def _assert_pack_and_adapter(root: Path) -> None:
    pack = _json(root, "FieldEvidenceApp/Resources/Packs/IlluminatedSignPack.json")
    if (
        pack.get("schemaVersion") != 1
        or pack.get("packID") != "field.evidence.illuminated_sign.v1"
        or pack.get("contentVersion") != 1
    ):
        raise ValueError("C03 illuminated pack identity differs")
    purpose_rows = pack.get("evidencePurposes")
    if (
        not isinstance(purpose_rows, list)
        or [row.get("key") for row in purpose_rows] != list(CAPTURE_SLOTS)
        or any(not row.get("display") or not row.get("instruction") for row in purpose_rows)
    ):
        raise ValueError("C03 capture purpose registry differs")
    issue_rows = pack.get("issueLabels")
    issue_ids = [row.get("key") for row in issue_rows] if isinstance(issue_rows, list) else []
    if issue_ids != list(PLAYBOOK_IDS[1:]):
        raise ValueError("C03 pack issue registry differs")
    reasons = pack.get("couldNotVerifyReasons", {})
    if (
        not reasons.get("version")
        or not isinstance(reasons.get("entries"), list)
        or len(reasons["entries"]) < 3
    ):
        raise ValueError("C03 could-not-verify registry differs")
    disclaimer = str(pack.get("disclaimer", ""))
    if (
        "visible conditions" not in disclaimer.lower()
        or "not an electrical" not in disclaimer.lower()
        or "certification" not in disclaimer.lower()
    ):
        raise ValueError("C03 non-certification disclaimer differs")
    adapter = _text(root, "FieldEvidenceApp/Infrastructure/Packs/ShippingIlluminatedSignAdapterV1.swift")
    _require_tokens(
        adapter,
        (
            "ShippingIlluminatedSignParityReceiptV1",
            "sourceCanonicalSHA256",
            "roundTripCanonicalSHA256",
            "exactParity",
            "parityReceipt",
            "typedResponses",
            "exactSemanticParity",
            "inventedMeasurementCount",
            "sourceData == roundTripData",
        ),
        "C03 shipping adapter parity",
    )


def _assert_prerequisite_sources(root: Path) -> None:
    c02 = "\n".join(_text(root, path) for path in (
        "FieldEvidenceApp/Domain/Evidence/EvidenceCurationContractsV1.swift",
        "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift",
    ))
    _require_tokens(
        c02,
        (
            "EvidenceSequenceV1", "EvidenceSequenceItemV1",
            "EvidenceAssociationV1", "EvidenceMetadataMutationReceiptV1",
            "associationBinding", "sequenceSHA256",
        ),
        "C02 prerequisite source",
    )
    c37 = "\n".join(_text(root, path) for path in (
        "FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift",
        "FieldEvidenceApp/Domain/Models/PlacementPosePersistenceModelsV1.swift",
    ))
    _require_tokens(
        c37,
        (
            "PoseAxisDescriptorV1", "AssetPoseEventV1",
            "PoseAxisSemanticRoleV1", "PoseReferenceFrameV1",
            "PlacementPoseAdmissionClosureV1",
        ),
        "C37 prerequisite source",
    )
    c36 = "\n".join(_text(root, path) for path in (
        "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
        "FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift",
        "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift",
        "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift",
    ))
    _require_tokens(
        c36,
        (
            "FieldDraftCheckpointV1", "checkpointSHA256",
            "validateSuccessor", "draftRevision", "recoveryRequired",
        ),
        "C36 checkpoint prerequisite source",
    )


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C03 source lanes missing:" + ",".join(status["missingPaths"]))
    contract = _text(root, IMPLEMENTATION_PATHS[0])
    coordinator = _text(root, IMPLEMENTATION_PATHS[1])
    report = _text(root, IMPLEMENTATION_PATHS[2])
    view = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[5])
    fixture = _json(root, IMPLEMENTATION_PATHS[6])
    _assert_fixture_contract(fixture)
    _assert_pack_and_adapter(root)
    _assert_prerequisite_sources(root)

    _require_tokens(
        contract,
        (
            "IlluminatedSignPlaybookIDV1", "canonicalOrder",
            "maximumFacts = 7", "IlluminatedSignPlaybookRegistryV1",
            "IlluminatedSignPlaybookManifestV1",
            "IlluminatedSignCaptureSlotIDV1",
            "wideContext", "closeDetail", "workContext",
            "IlluminatedSignPoseTraceV1", "PoseAxisDescriptorV1",
            "AssetPoseEventV1", "IlluminatedSignPlaybookDraftPayloadV1",
            "checkedTime", "selectedVisibleCondition",
            "IlluminatedSignStructuredFactV1", "visibleConditionClaim",
            "comparisonIsProof", "diagnosisClaimed",
            "electricalCertification", "safetyCertification",
            "IlluminatedSignPlaybookCanonicalCodecV1", "static func sha256",
            "NONPERSISTENT_DIGEST_BOUND_SIDECAR",
            "INCUMBENT_FIELD_DRAFT_AND_POSE_AUTHORITIES",
            "INCUMBENT_C05_EVIDENCE_METADATA_AUTHORITY",
            "NOT_APPLICABLE_DERIVED_FROM_DURABLE_AUTHORITIES",
        ),
        "C03 playbook contract",
    )
    _require_patterns(
        contract,
        (
            r"maximumFacts\s*=\s*7",
            r"canonicalOrder:\s*\[Self\]",
            r"manifests\.count\s*==\s*IlluminatedSignPlaybookIDV1\.canonicalOrder\.count",
            r"Set\(ids\)\.count\s*==\s*IlluminatedSignPlaybookIDV1\.allCases\.count",
            r"visibleConditionClaim\s*==\s*\.visibleConditionsOnly",
            r"!comparisonIsProof",
            r"!diagnosisClaimed",
            r"!electricalCertification",
            r"!safetyCertification",
            r"captures\.count\s*<=\s*IlluminatedSignPlaybookLimitsV1\.maximumCaptureTraces",
            r"poseTrace\?\.validate",
            r"payloadSHA256\s*==",
        ),
        "C03 playbook contract closure",
    )
    _require_tokens(
        coordinator,
        (
            "IlluminatedSignPlaybookCoordinatorV1",
            "FieldDraftCheckpointV1", "checkpoint.validate",
            "validateSuccessor", "recover(", "reportSection",
            "IlluminatedSignPlaybookCheckpointProjectionV1",
            "IlluminatedSignPlaybookRecoveryV1",
            "associationEvents", "EvidenceAssociationLedgerV1",
            "C05", "C36", "C37",
        ),
        "C03 coordinator",
    )
    _require_tokens(
        report,
        (
            "IlluminatedSignReportProjectionV1",
            "IlluminatedSignReportSectionV1",
            "section.fact",
            "snapshot.validateSourceFrontier",
            "visibleConditionsOnly",
            "nonCertificationDisclaimer",
            "requiredNonCertificationDisclaimer",
            "completionSHA256",
            "evidenceSequenceHistory",
            "poseEventHistory",
        ),
        "C03 report projection",
    )
    if "ReportProjectionRegistryV1" in report:
        raise ValueError("C03 report projection must not adopt a post-S10 registry")
    _require_tokens(
        view,
        (
            "IlluminatedSignPlaybookView",
            "IlluminatedSignPlaybookAccessibilityIDV1",
            "capture", "pose", "couldNotVerify",
            "accessibilityLabel", "visibleConditionsOnly", "outcomeCouldNotVerify",
            "@Environment(\\.dynamicTypeSize)",
            "@Environment(\\.accessibilityReduceMotion)",
            "VStack", "ScrollView",
        ),
        "C03 view",
    )
    _require_patterns(
        view,
        (
            r"dynamicTypeSize\.isAccessibilitySize",
            r"\.accessibilityLabel\(",
            r"if\s+reduceMotion\s*\{\s*transaction\.animation\s*=\s*nil",
        ),
        "C03 accessibility/motion presentation",
    )
    if re.search(r"\b(?:left|right)\b", view, re.I):
        raise ValueError("C03 view contains non-RTL physical direction semantics")
    selectors = _assert_exact_selectors(tests)
    _require_tokens(
        tests,
        (
            "IlluminatedSignPlaybookCoordinatorV1",
            "IlluminatedSignPlaybookRegistryV1",
            "IlluminatedSignPlaybookIDV1", "canonicalOrder",
            "FieldDraftCheckpointV1", "PoseAxisDescriptorV1",
            "AssetPoseEventV1", "EvidenceSequenceItemV1",
            "eighthPlaybookForbidden",
            "hostileCases", "interruptionBoundaries", "recoveryCases",
            "comparisonIsProof", "visibleConditionsOnly",
            "diagnosisClaimed", "electricalCertification", "safetyCertification",
        ),
        "C03 unit tests",
    )
    _require_tokens(
        ui_tests,
        (CARD, "UIAdoptionPendingPostS10", "XCTSkip", "illuminated"),
        "C03 UI deferral test",
    )
    source = "\n".join((contract, coordinator, report, view, tests, ui_tests))
    if re.search(
        r"\b(?:URLSession|URLRequest|CloudKit|CKContainer|WebSocket|NWConnection|"
        r"TelemetryClient|CoreML|OpenAI|upload|remoteSync|server)\b",
        source, re.I,
    ):
        raise ValueError("C03 network/cloud/AI/telemetry symbols present")
    return selectors


def _authority_pins_ready() -> bool:
    refs = (
        BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE,
        COORDINATION_HEAD, COORDINATION_ORIGIN_HEAD, COORDINATION_TREE,
    )
    digests = (
        PREREQUISITE_DIGEST, CONTEXT_DIGEST, FENCE_DIGEST,
        HYDRATION_TRANSITION_DIGEST, COORDINATION_LEDGER_DIGEST,
        COORDINATION_PROJECTION_DIGEST, FROZEN_S10_RESERVATION_DIGEST,
        DOSSIER_SHA256, INHERITED_V21_BLOCK_SHA256, REGISTER_ROW_SHA256,
        REGISTER_SECTION_SHA256,
    )
    return (
        all(re.fullmatch(r"[0-9a-f]{40}", value) for value in refs)
        and all(_valid_sha(value) for value in digests)
    )


def assert_scaffold(root: Path) -> None:
    if (
        len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE), len(set(PATH_FENCE))
    ) != (
        EXPECTED_EXISTING_PATH_COUNT, EXPECTED_NEW_PATH_COUNT,
        EXPECTED_FENCE_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT,
    ):
        raise ValueError("C03 fence cardinality or uniqueness differs")
    if NEW_PATHS != _HYDRATED_NEW_PATHS:
        raise ValueError("C03 new-path ordering differs from hydrated fence")
    if any(
        "phase10" in path.lower() or "/s10" in path.lower()
        for path in PATH_FENCE
    ):
        raise ValueError("C03 fence contains Phase10/S10 path")
    if (
        not _authority_pins_ready()
        or AUTHORIZED_OVERLAP_COUNT != 5906
        or UNAUTHORIZED_OVERLAP_COUNT != 0
        or S10_RESERVATION_OVERLAP_COUNT != 0
    ):
        raise ValueError("C03 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C03 app base tree differs")
    _candidate_identity(root)
    _assert_coordination_state()
    _assert_design_slices(root)
    missing_base = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C03 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C03 new path already exists at accepted base")


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
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "dossierSHA256": DOSSIER_SHA256,
        "dossierByteCount": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
        "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionByteCount": REGISTER_SECTION_BYTES,
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


def _common() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "title": TITLE,
        "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "statusFlags": FLAGS,
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "acceptanceEnabled": False,
        "adoptionEnabled": False,
        "releaseCredit": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "provisional": not FINAL_HASHES_SEALED,
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


_PROVIDER_ARTIFACTS = {
    "V23-P04-C02": {
        "required": True,
        "facet": "C05_EVIDENCE_ASSOCIATION_AND_SEQUENCE_INPUT",
        "candidateHead": DIRECT_PREREQUISITE_ROWS[0]["candidateHead"],
        "candidateTree": DIRECT_PREREQUISITE_ROWS[0]["candidateTree"],
        "checkpointDigest": DIRECT_PREREQUISITE_ROWS[0]["checkpointDigest"],
        "contextDigest": DIRECT_PREREQUISITE_ROWS[0]["contextDigest"],
        "pathFenceDigest": DIRECT_PREREQUISITE_ROWS[0]["pathFenceDigest"],
        "verificationReceiptDigest": DIRECT_PREREQUISITE_ROWS[0]["verificationReceiptDigest"],
        "contracts": (
            "EvidenceSequenceV1", "EvidenceSequenceItemV1",
            "EvidenceAssociationV1", "EvidenceMetadataMutationReceiptV1",
        ),
        "paths": (
            "FieldEvidenceApp/Domain/Evidence/EvidenceCurationContractsV1.swift",
            "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift",
            "Scripts/v23/p04_c02_contracts.py",
            "Scripts/v23/evidence-curation.schema.json",
            "docs/design/v23/tooling/V23P04C02EvidenceCurationContractV1.json",
            "docs/design/v23/tooling/V23P04C02EvidenceCurationEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23-P04-C02-tooling-manifest.json",
        ),
    },
    "V23-P03-C37": {
        "required": True,
        "facet": "POSE_AXIS_AND_TYPED_EVENT_INPUT",
        "candidateHead": DIRECT_PREREQUISITE_ROWS[1]["candidateHead"],
        "candidateTree": DIRECT_PREREQUISITE_ROWS[1]["candidateTree"],
        "checkpointDigest": DIRECT_PREREQUISITE_ROWS[1]["checkpointDigest"],
        "contextDigest": DIRECT_PREREQUISITE_ROWS[1]["contextDigest"],
        "pathFenceDigest": DIRECT_PREREQUISITE_ROWS[1]["pathFenceDigest"],
        "verificationReceiptDigest": DIRECT_PREREQUISITE_ROWS[1]["verificationReceiptDigest"],
        "contracts": (
            "PoseAxisDescriptorV1", "AssetPoseEventV1",
            "PlacementPoseAdmissionClosureV1",
        ),
        "paths": (
            "FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift",
            "FieldEvidenceApp/Domain/Models/PlacementPosePersistenceModelsV1.swift",
            "Scripts/v23/p03_c37_contracts.py",
            "Scripts/v23/placement-pose.schema.json",
            "docs/design/v23/tooling/V23P03C37PlacementPoseContractV1.json",
            "docs/design/v23/tooling/V23P03C37PlacementPoseEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23-P03-C37-tooling-manifest.json",
        ),
    },
    "V23-P03-C36": {
        "required": True,
        "facet": "UNIVERSAL_CHECKPOINT_AND_DRAFT_RECOVERY_INPUT",
        "candidateHead": None,
        "candidateTree": None,
        "checkpointDigest": None,
        "contextDigest": None,
        "pathFenceDigest": None,
        "verificationReceiptDigest": None,
        "contracts": (
            "FieldDraftCheckpointV1", "DraftCommitSagaRecoveryV1",
            "FieldDraftLifecycleAdapterV1",
        ),
        "paths": (
            "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
            "FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift",
            "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift",
            "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift",
        ),
    },
}


def provider_artifacts(root: Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for card, metadata in _PROVIDER_ARTIFACTS.items():
        files: list[dict[str, Any]] = []
        for path in metadata["paths"]:
            target = root / path
            if target.is_file():
                data = canonical_file_bytes(target)
                files.append({
                    "path": path,
                    "byteCount": len(data),
                    "sha256": sha256_bytes(data),
                    "status": "SEALED_PROVIDER",
                })
            else:
                if FINAL_HASHES_SEALED and metadata["required"]:
                    raise ValueError("cannot seal missing C03 provider input:" + path)
                files.append({
                    "path": path,
                    "byteCount": None,
                    "sha256": None,
                    "status": "PENDING_PROVIDER",
                })
        result.append({
            "providerCardID": card,
            "required": metadata["required"],
            "capability": metadata["facet"],
            "candidateHead": metadata["candidateHead"],
            "candidateTree": metadata["candidateTree"],
            "checkpointDigest": metadata["checkpointDigest"],
            "contextDigest": metadata["contextDigest"],
            "pathFenceDigest": metadata["pathFenceDigest"],
            "verificationReceiptDigest": metadata["verificationReceiptDigest"],
            "contracts": list(metadata["contracts"]),
            "paths": list(metadata["paths"]),
            "files": files,
            "allFilesPresent": all(item["sha256"] is not None for item in files),
            "fallback": None,
        })
    return result


def semantics(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "registry": "EXACT_SEVEN_PREAUTHORIZED_PLAYBOOK_IDS_NO_EIGHTH",
        "playbookIDs": list(PLAYBOOK_IDS),
        "playbookCount": 7,
        "eighthPlaybookForbidden": True,
        "optionalDecisionGate": "DISABLED_OR_DEFERRED",
        "captureSlots": list(CAPTURE_SLOTS),
        "requiredCaptureSlots": ["wide_context", "close_detail"],
        "optionalCaptureSlots": ["work_context"],
        "visibleConditionClaim": "VISIBLE_CONDITIONS_ONLY",
        "diagnosisClaimed": False,
        "electricalCertification": False,
        "safetyCertification": False,
        "comparisonIsProof": False,
        "nonCertificationDisclaimerRequired": True,
        "packSource": "IlluminatedSignPack@1",
        "packSourceOwner": "CANONICAL_CURRENT_OWNER",
        "shippingAdapterParity": "EXACT_SOURCE_AND_ROUND_TRIP_CANONICAL_BYTES",
        "typedPose": "C37_SHARED_POSE_EDITOR_AXIS_FRAME_SOURCE_UNCERTAINTY_NOT_OBSERVED",
        "checkpointing": "C36_UNIVERSAL_CHECKPOINT_KILL_RESUME",
        "bareDirectionStorage": False,
        "report": "DERIVED_GUIDANCE_ONLY_STRUCTURED_FACTS",
        "persistence": PERSISTENCE,
        "lifecycle": dict(C03_LIFECYCLE),
        "lifecycleCoverage": list(LIFECYCLE_COVERAGE),
        "searchRebuild": "NO_NEW_INDEX_DERIVED_ONLY",
        "journalReplay": "CHECKPOINT_AND_ASSOCIATION_REPLAY_NO_CARD_WRITER",
        "backupRestoreDeleteErase": "DERIVED_FROM_DURABLE_AUTHORITIES",
        "selectors": list(selectors),
        "journeyRefs": list(JOURNEY_REFS),
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "ui": "POST_S10_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT",
        "noNetworkCloudTelemetryAI": True,
        "noUnboundedTemplateBuilderOrMedia": True,
        "noSecondEngineOrWriter": True,
        "forbiddenCapabilities": [
            "DIAGNOSIS", "ELECTRICAL_CERTIFICATION", "SAFETY_CERTIFICATION",
            "NETWORK", "CLOUD", "TELEMETRY", "REMOTE_SYNC",
            "UNBOUNDED_TEMPLATE_BUILDER", "UNBOUNDED_MEDIA",
            "SECOND_ENGINE", "SECOND_WRITER", "NATIVE_IPAD",
        ],
    }


def _source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path in IMPLEMENTATION_PATHS:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            rows.append({
                "path": path,
                "byteCount": len(data),
                "sha256": sha256_bytes(data),
                "status": "SEALED_SOURCE",
            })
        else:
            rows.append({
                "path": path,
                "byteCount": None,
                "sha256": None,
                "status": "PENDING_SOURCE",
            })
    return rows


def _source_projection(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {
        "implementationPaths": list(IMPLEMENTATION_PATHS),
        "presentPaths": status["presentPaths"],
        "missingPaths": status["missingPaths"],
        "selectors": list(selectors),
        "sourceSemanticsInspected": bool(status["hydrated"]),
        "sourceRows": _source_rows(root),
        "dossierSHA256": DOSSIER_SHA256,
        "dossierByteCount": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
        "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS),
        "conformanceSubjects": list(CONFORMANCE_SUBJECTS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
        "canonicalSuccessor": {"cardID": "V23-P04-C04", "registerOrdinal": 92},
        "playbookIDs": list(PLAYBOOK_IDS),
        "eighthPlaybookForbidden": True,
        "lifecycle": dict(C03_LIFECYCLE),
        "persistence": PERSISTENCE,
        "providerContractSlices": [
            {
                "providerCardID": card,
                "facet": metadata["facet"],
                "pathFenceDigest": metadata["pathFenceDigest"],
                "contracts": list(metadata["contracts"]),
            }
            for card, metadata in _PROVIDER_ARTIFACTS.items()
        ],
    }


def schema_document(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/illuminated-sign-playbook.schema.json",
        "title": TITLE,
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P04C03IlluminatedSignPlaybookCorpusV1"},
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD},
            "ordinal": {"const": REGISTER_ORDINAL},
            "contentMode": {"const": "NONPERSISTENT_DIGEST_BOUND_SIDECAR"},
            "playbookIDs": {"const": list(PLAYBOOK_IDS), "minItems": 7, "maxItems": 7},
            "playbookCount": {"const": 7},
            "eighthPlaybookForbidden": {"const": True},
            "captureSlots": {"const": list(CAPTURE_SLOTS)},
            "requiredCaptureSlots": {"const": ["wide_context", "close_detail"]},
            "optionalCaptureSlots": {"const": ["work_context"]},
            "evidenceIDs": {"const": list(EVIDENCE_IDS)},
            "selectors": {"const": list(selectors)},
            "journeyRefs": {"const": list(JOURNEY_REFS)},
            "directPrerequisites": {"const": list(DIRECT_PREREQUISITES)},
            "optionalCapabilityProviders": {"const": ["NONE"]},
            "visibleConditionClaim": {"const": "VISIBLE_CONDITIONS_ONLY"},
            "comparisonIsProof": {"const": False},
            "diagnosisClaimed": {"const": False},
            "electricalCertification": {"const": False},
            "safetyCertification": {"const": False},
            "nonCertificationDisclaimerRequired": {"const": True},
            "typedPoseBinding": {"const": "C37_SHARED_POSE_EDITOR"},
            "checkpointBinding": {"const": "C36_UNIVERSAL_CHECKPOINT"},
            "lifecycle": {"const": dict(C03_LIFECYCLE)},
            "persistence": {"const": PERSISTENCE},
            "statusFlags": {"const": FLAGS},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED},
            "provisional": {"const": not FINAL_HASHES_SEALED},
        },
        "required": [
            "schema", "schemaVersion", "cardID", "ordinal", "contentMode",
            "playbookIDs", "playbookCount", "eighthPlaybookForbidden",
            "captureSlots", "requiredCaptureSlots", "optionalCaptureSlots",
            "evidenceIDs", "selectors", "journeyRefs", "directPrerequisites",
            "optionalCapabilityProviders", "visibleConditionClaim",
            "comparisonIsProof", "diagnosisClaimed", "electricalCertification",
            "safetyCertification", "nonCertificationDisclaimerRequired",
            "typedPoseBinding", "checkpointBinding", "lifecycle", "persistence",
            "statusFlags", "finalHashesSealed", "provisional",
        ],
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {
        **value,
        "artifactDigest": (
            sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None
        ),
    }


def contract_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C03IlluminatedSignPlaybookContractV1",
        "schemaVersion": SCHEMA_VERSION,
        **_common(),
        "directPrerequisites": list(DIRECT_PREREQUISITES),
        "journeyRefs": list(JOURNEY_REFS),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "contractRefs": list(CONTRACT_REFS),
        "semantics": semantics(selectors),
        "sourceProjection": _source_projection(root, selectors),
        "providerArtifacts": provider_artifacts(root),
    })


def evidence_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {
            "evidenceID": EVIDENCE_IDS[0],
            "kind": "GOLDEN",
            "selectorSuffix": "G01",
            "focus": [
                "exact seven registry and source pack vocabulary",
                "wide and close capture completeness",
                "typed C37 pose with C36 checkpoint",
                "structured visible-condition report fact",
            ],
        },
        {
            "evidenceID": EVIDENCE_IDS[1],
            "kind": "ALTERNATE",
            "selectorSuffix": "A01",
            "focus": [
                "could-not-verify and safe authorized-position path",
                "frozen display and deterministic registry digest",
                "content-only nonpersistent sidecar",
            ],
        },
        {
            "evidenceID": EVIDENCE_IDS[2],
            "kind": "HOSTILE",
            "selectorSuffix": "H01",
            "focus": [
                "missing, duplicate, renamed, or eighth playbook rejected",
                "unsafe diagnosis, electrical, safety, or certification claims rejected",
                "forged pack, pose, frame, source, checkpoint, and evidence bindings rejected",
                "optional decision gate cannot enter the shipping registry",
            ],
        },
        {
            "evidenceID": EVIDENCE_IDS[3],
            "kind": "INTERRUPTION",
            "selectorSuffix": "I01",
            "focus": [
                "kill or cancel at every C36 checkpoint boundary",
                "relaunch exposes no partial accepted state",
                "deterministic replay or visible recovery-required state",
            ],
        },
        {
            "evidenceID": EVIDENCE_IDS[4],
            "kind": "RECOVERY",
            "selectorSuffix": "R01",
            "focus": [
                "remove affected playbook version while retaining kernel and prior content",
                "backup/restore/delete/Erase/report/search and journal closure",
                "reconcile exact source, receipts, projections, and evidence hashes",
            ],
        },
    ]
    return _sealed({
        "schema": "V23P04C03IlluminatedSignPlaybookEvidenceReceiptV1",
        "schemaVersion": SCHEMA_VERSION,
        **_common(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(selectors),
        "cases": cases,
        "playbookIDs": list(PLAYBOOK_IDS),
        "playbookCount": 7,
        "eighthPlaybookForbidden": True,
        "captureSlots": list(CAPTURE_SLOTS),
        "typedPoseBinding": "C37_SHARED_POSE_EDITOR_AXIS_FRAME_SOURCE_UNCERTAINTY_NOT_OBSERVED",
        "checkpointBinding": "C36_UNIVERSAL_CHECKPOINT_KILL_RESUME",
        "visibleConditionClaim": "VISIBLE_CONDITIONS_ONLY",
        "comparisonIsProof": False,
        "diagnosisClaimed": False,
        "electricalCertification": False,
        "safetyCertification": False,
        "nonCertificationDisclaimerRequired": True,
        "lifecycle": dict(C03_LIFECYCLE),
        "persistence": PERSISTENCE,
        "lifecycleCoverage": list(LIFECYCLE_COVERAGE),
        "uiAdoptionSkipped": True,
        "sourceProjection": _source_projection(root, selectors),
        "providerArtifacts": provider_artifacts(root),
    })


def brand_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C03BrandImpactManifestV1",
        "schemaVersion": SCHEMA_VERSION,
        **_common(),
        "iPhoneNativeOnly": True,
        "nativeIPadSurface": False,
        "uiSurfaceDelta": True,
        "brandSurfaceDelta": True,
        "changedStates": [
            "EMPTY", "CHECKING", "CAPTURE_REQUIRED", "POSE_REVIEW",
            "INCOMPLETE", "COMPLETE", "COULD_NOT_VERIFY", "RECOVERY_REQUIRED",
        ],
        "uiTestDisposition": "EXPLICIT_POST_S10_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_AUTHORITY",
        "adoptionSkipped": True,
        "uiAdoptionSkipped": True,
        "onDeviceOnly": True,
        "networkOrTelemetryFlow": False,
        "visibleConditionClaimsOnly": True,
        "nonCertificationStatementRequired": True,
        "accessibilityAndLocalizationRequired": True,
        "statusFlags": FLAGS,
        "sourceProjection": _source_projection(root, selectors),
    })


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {
            "path": path,
            "byteCount": len(data),
            "sha256": sha256_bytes(data),
            "status": "SEALED_TOOLING",
        }
    target = root / path
    if not target.is_file():
        if FINAL_HASHES_SEALED:
            raise ValueError("cannot seal missing C03 fence input:" + path)
        return {
            "path": path,
            "byteCount": None,
            "sha256": None,
            "status": "PENDING_SOURCE",
        }
    data = canonical_file_bytes(target)
    return {
        "path": path,
        "byteCount": len(data),
        "sha256": sha256_bytes(data),
        "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE",
    }


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    status = source_status(root)
    selectors = assert_source_contracts(root) if status["hydrated"] else observed_selectors(root)
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: pretty(schema_document(selectors)),
        CONTRACT_PATH: pretty(contract_document(root, selectors)),
        EVIDENCE_PATH: pretty(evidence_document(root, selectors)),
        BRAND_PATH: pretty(brand_document(root, selectors)),
    }
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest_base = {
        "schema": "V23-P04-C03-tooling-manifest",
        "schemaVersion": SCHEMA_VERSION,
        **_common(),
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
        "hashDisposition": (
            "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
            if FINAL_HASHES_SEALED
            else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
        ),
        "files": rows,
        "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None,
        "sourceProjection": _source_projection(root, selectors),
        "providerArtifacts": provider_artifacts(root),
    }
    rendered[MANIFEST_PATH] = pretty(_sealed(manifest_base))
    return rendered


def _self_parse() -> None:
    for path in SCRIPT_PATHS:
        local = ROOT / path
        if local.is_file():
            ast.parse(local.read_text(encoding="utf-8"), filename=path)


if __name__ == "__main__":
    _self_parse()
    print(json.dumps({
        "cardID": CARD,
        "sourceReady": source_status(ROOT)["hydrated"],
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "fencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "newPathCount": EXPECTED_NEW_PATH_COUNT,
    }, sort_keys=True))
