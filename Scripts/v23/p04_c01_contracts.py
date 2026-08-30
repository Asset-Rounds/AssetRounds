#!/usr/bin/env python3
"""Fail-closed static tooling for V23-P04-C01 RecoveryCenter.

This lane owns only the contract/schema/evidence projection.  The Recovery
Center Swift rows are read-only inputs.  Until every one of those rows exists
and satisfies the source audit, generated documents remain explicitly
provisional and contain no fabricated source hash.
"""
from __future__ import annotations

import ast
import hashlib
import importlib.util
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
CARD = "V23-P04-C01"
TITLE = "Visible local reliability, recovery freshness, encrypted-backup option, and user-controlled Support and Recovery Center"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 89

# Hydration authority.  The coordination commit is deliberately recorded as
# an exact object here; no authority is inferred from a moving branch.
BASE_HEAD = "f8c797fe0e6524f85a15b771e84f899fd9763bc0"
BASE_TREE = "5ba84e18b17cadb31062d240854b991e474c7a39"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "7865dec825fc9b30d9f7367f725322fc42df3d7b"
COORDINATION_TREE = "073a7a1bec19312a1f60e052bd67464a9066073e"
COORDINATION_CAS_SEQUENCE = 377
HYDRATION_REVISION = 2
CONTEXT_DIGEST = "e032c21cd95df0074537a163bb3c57fd280dbaed0e375efa612673357d069425"
FENCE_DIGEST = "f59c7d2d98907aed26492f3a06d6de52ce1436790ddfda9da157689346d0a706"
PREREQUISITE_DIGEST = "d579aa7d8a3882e871b311a8d3be2852ea61332c3a0d502c7de705737008fd9b"
HYDRATION_TRANSITION_DIGEST = "27f055f2c24511d58b0005c581cc3b433e910a841540f8ec6f45422e2365c928"
FENCE_CORRECTION_DIGEST = "0fcf8ef9cbc552182cd1781cb1512f54b7f6ba9ab24190e848f17d5fe1bee1df"
COORDINATION_LEDGER_DIGEST = "8f26f6306e6ef6d809bb4bdaf0c5ca1c0f79a279be2512b54e4ecbae5cc47d02"
COORDINATION_PROJECTION_DIGEST = "24c97be7186938b61c820cc8fdfbbea26c619d0ff9cf7401807f27bbdd334d22"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

DOSSIER_SHA256 = "f427c7b716f80e5dd4de2eeb415b748bc424cbca3f36f9141d953a6cc0a2c34f"
DOSSIER_BYTES = 7561
INHERITED_V21_BLOCK_SHA256 = "fb047a08f2009dbc98cb11a3f65297c38a7eb39680b064ffbb223acd6c83dc5a"
INHERITED_V21_BLOCK_BYTES = 12642
REGISTER_ROW_SHA256 = "ac098b8fe94021852dd5d7c36e9539dfb2c2d8d26c6d17ae921a063b2cccaa2a"
REGISTER_ROW_BYTES = 323
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217
REGISTER_ROW = "| 89 | <a id=\"v23-p04-c01-register\"></a>[`V23-P04-C01`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p04-c01) | Visible local reliability, recovery freshness, encrypted-backup option, and user-controlled Support and Recovery Center | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C22`, `V23-P03-C34` | `REFINED_WITHOUT_LOSS` |"

EXPECTED_EXISTING_PATH_COUNT = 217
EXPECTED_NEW_PATH_COUNT = 15
EXPECTED_FENCE_PATH_COUNT = 232
AUTHORIZED_OVERLAP_COUNT = 4788
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 87
PRIOR_OWNED_PATH_COUNT = 1412
S10_RESERVED_PATH_COUNT = 86

SCHEMA_PATH = "Scripts/v23/recovery-center.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C01RecoveryCenterContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C01RecoveryCenterEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C01BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C01-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c01_contracts.py",
    "Scripts/v23/generate_p04_c01_contracts.py",
    "Scripts/v23/verify_p04_c01_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
OUTPUT_PATHS = GENERATED_PATHS

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Recovery/RecoveryCenterContractsV1.swift",
    "FieldEvidenceApp/Application/Recovery/RecoveryCenterCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Recovery/RecoveryCenterLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift",
    "FieldEvidenceAppTests/V9_66RecoveryCenterTests.swift",
    "FieldEvidenceAppUITests/V23_P04_C01RecoveryCenterUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/RecoveryCenter/V22P04C01RecoveryCenterCorpusV1.json",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C01-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C01-attempt-1/BootstrapPathFenceV1.json"

def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate JSON key:" + key)
        value[key] = item
    return value


def _coordination_root() -> Path:
    candidates = (
        Path(r"C:\AssetRounds-v23-coordination"),
        ROOT.parent / "AssetRounds-v23-coordination",
    )
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C01 coordination fence is unavailable")


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("coordination object required:" + relative)
    return value


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C01 context digest/card mismatch")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST:
        raise ValueError("C01 path fence digest/card mismatch")
    if context.get("hydrationRevision") != HYDRATION_REVISION or fence.get("hydrationRevision") != HYDRATION_REVISION:
        raise ValueError("C01 hydration revision differs")
    existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(fence.get("newPaths", ()))
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C01 existing path fence cardinality differs")
    if hydrated_new != NEW_PATHS:
        raise ValueError("C01 hydrated new-path ordering differs")
    if tuple(context.get("existingPaths", ())) != existing or tuple(context.get("newPaths", ())) != hydrated_new:
        raise ValueError("C01 context/fence path sets differ")
    return existing, hydrated_new


EXISTING_PATHS, _HYDRATED_NEW_PATHS = _load_hydrated_paths()
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
RECOVERY_STATES = (
    "HEALTHY", "CHECKING", "ACTIONABLE", "IN_PROGRESS", "INTERRUPTED",
    "FILE_REQUIRED", "VALIDATION_FAILED", "PARTIAL_SAFE", "COMPLETE",
    "RESTART_REQUIRED", "EXTERNAL_ACTION_REQUIRED",
)
RECOVERY_SOURCES = (
    "BACKUP", "RESTORE", "GENERATION", "FINALIZATION", "REPORTING",
    "STORAGE", "PROTECTED_DATA", "JOBS", "PACKAGE_READINESS", "COMMERCE", "DIAGNOSTICS",
)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C01).CONTRACTS",
    "RecoveryCenterProjectionV1", "RecoverabilityVerificationStagingV1",
    "RecoverabilityVerificationReceiptV1", "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)
JOURNEY_REFS = ("FJ11",)
DIRECT_PREREQUISITES = ("V23-P03-C22", "V23-P03-C34")
OPTIONAL_CAPABILITY_PROVIDERS = ("V23-P03-C54:ENCRYPTED_BACKUP",)
LIFECYCLE_COVERAGE = (
    "SCHEMA_VERSION", "WRITER_QUERY", "MIGRATION", "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK", "IMPORT_EXPORT", "JOURNAL_REPLAY", "SEARCH_REBUILD",
    "REPORT_PROJECTION", "DELETE_ERASE", "RETENTION", "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX", "INTERRUPTION", "IDEMPOTENT_RECEIPTS",
)
PERSISTENT_CHANGE_MODE = "NONPERSISTENT_DERIVED_RECOVERY_CENTER_PROJECTION_AND_DEVICE_OPERATIONAL_SUPPORT_DRAFT"
PERSISTENT_CONTRACT_SCHEMA = "NONPERSISTENT_RECOVERY_CENTER_V1"
PERSISTENT_ROW_TYPES = ("SupportFeedbackDraftV1",)
NONPERSISTENT_TYPES = (
    "RecoveryCenterProjectionV1", "ReliabilityStateProjectionV1",
    "RecoveryAuthoritySnapshotV1", "PresentationClockV1", "SupportExportPreviewProjectionV1",
)
FLAGS = {name: False for name in (
    "activation", "native", "hosted", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

# This is intentionally changed to True only after every source lane and
# inherited fence input is stable.  A provisional artifact never carries a
# fabricated source hash.
FINAL_HASHES_SEALED = True

_PROVIDER_ARTIFACTS = {
    "V23-P03-C22": {
        "required": True,
        "pathFenceDigest": "c34e0f79176c9213abc467ff20e6f70282ded318b919768dbfd4506883fc2f40",
        "candidateHead": "d0485977644a71e49b8d4b898bb527e0353bd81e",
        "candidateTree": "2fc990ee64f9da6e84b07fddc2abed036f679630",
        "checkpointDigest": "827c81d1c99a110f592ae54c03b9953e3800470cadb9c77f9024384e32d9a2fb",
        "contextDigest": "4e2d0c1f46926387a8e15a798d551744fa23448c4790f466a4d5d3903d026dc4",
        "verificationReceiptDigest": "5365dd9ef144d40a81662ba3d2bf1fc69c30761c8905526a5703ad58953bd8bb",
        "contracts": ("RecoverabilityVerificationStagingV1", "RecoverabilityVerificationReceiptV1"),
        "paths": (
            "Scripts/v23/p03_c22_contracts.py", "Scripts/v23/generate_p03_c22_contracts.py",
            "Scripts/v23/verify_p03_c22_contracts.py", "Scripts/v23/recoverability-verification.schema.json",
            "docs/design/v23/tooling/V23P03C22RecoverabilityVerificationContractV1.json",
            "docs/design/v23/tooling/V23P03C22RecoverabilityVerificationEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23P03C22RecoverabilityVerificationBrandImpactManifestV1.json",
            "docs/design/v23/tooling/V23-P03-C22-tooling-manifest.json",
        ),
    },
    "V23-P03-C34": {
        "required": True,
        "pathFenceDigest": "0e54c0aae93e45c906fc6870cf7ccfec05557223382ca5cd95776c793af69be4",
        "candidateHead": "837fe50cc71f030618236aafe7896ac424f10437",
        "candidateTree": "965d8633d5bbd4f4f7d26941085e9a9e428185af",
        "checkpointDigest": "dd5d8023998cb467baa774f30e3fdf9d65439a9ab65379fc9db653d4c295c8bf",
        "contextDigest": "8add3078bd1abace390df25dab4bbdd8c9943e966c22f6b1f0624ea29f8a57db",
        "verificationReceiptDigest": "58421f28f14762752449cbf27896e68f663e4a9e51713d72c73b68525a6f7c6a",
        "contracts": ("RouteRegistryV1", "RecoveryRouteV1"),
        "paths": (
            "Scripts/v23/p03_c34_contracts.py", "Scripts/v23/generate_p03_c34_contracts.py",
            "Scripts/v23/verify_p03_c34_contracts.py", "Scripts/v23/route-registry.schema.json",
            "docs/design/v23/tooling/V23P03C34RouteRegistryContractV1.json",
            "docs/design/v23/tooling/V23P03C34RouteRegistryEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23P03C34BrandImpactManifestV1.json",
            "docs/design/v23/tooling/V23-P03-C34-tooling-manifest.json",
        ),
    },
    "V23-P03-C54": {
        "required": False,
        "capability": "ENCRYPTED_BACKUP",
        "pathFenceDigest": "be5dc8f42a5b026596149b405814a3e6c96f1a500ce2750339a439c18364fcec",
        "hydrationFenceCorrectionDigest": "bae9195a6ca691b81f00c091ea78c1630143595c7272f6822474f5c3bb9da1de",
        "candidateHead": "e4bb386889a4051efeb9359fef9a90fbd7c70d54",
        "candidateTree": "1a409af2305ddc1e78754ccd70ea05f9572ed44d",
        "checkpointDigest": "9e01caafe3162fdd642f31494cc135e2b06504d3ad0d583c71a3ed47c3e3f57d",
        "contextDigest": "6ff43b0c6ea104ca91a63e9e14312ad8fc12ecabc542b41f00fce33286c99d05",
        "verificationReceiptDigest": "4934744c662825104e850bf727f82a061106b4c9c02c5b3dd6c6b870d9946785",
        "contracts": ("EncryptedPortableEnvelopeProtocolReleaseV1", "EncryptedEnvelopeSealReceiptV1", "TypedAvailabilityAndFallbackReceiptV1"),
        "paths": (
            "Scripts/v23/p03_c54_contracts.py", "Scripts/v23/generate_p03_c54_contracts.py",
            "Scripts/v23/verify_p03_c54_contracts.py", "Scripts/v23/encrypted-portable-envelope.schema.json",
            "docs/design/v23/tooling/V23P03C54EncryptedPortableEnvelopeContractV1.json",
            "docs/design/v23/tooling/V23P03C54EncryptedPortableEnvelopeEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23P03C54BrandImpactManifestV1.json",
            "docs/design/v23/tooling/V23-P03-C54-tooling-manifest.json",
        ),
    },
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


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


def _authority_pins_ready() -> bool:
    values = (BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE, COORDINATION_HEAD, COORDINATION_TREE)
    digests = (
        CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST,
        COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST, FROZEN_S10_RESERVATION_DIGEST,
        DOSSIER_SHA256, INHERITED_V21_BLOCK_SHA256, REGISTER_ROW_SHA256, REGISTER_SECTION_SHA256,
    )
    return all(re.fullmatch(r"[0-9a-f]{8,40}", value) for value in values) and all(_valid_sha(value) for value in digests)


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def _base_exists(root: Path, relative: str) -> bool:
    global _BASE_PATH_CACHE
    if _BASE_PATH_CACHE is None:
        listing = subprocess.run(["git", "ls-tree", "-r", "--name-only", BASE_HEAD], cwd=root, check=True, capture_output=True, text=True).stdout
        _BASE_PATH_CACHE = frozenset(line.strip().replace("\\", "/") for line in listing.splitlines() if line.strip())
    return relative in _BASE_PATH_CACHE


_BASE_PATH_CACHE: frozenset[str] | None = None


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed: set[str] = set()
    for command in (("diff", "--name-only", BASE_HEAD, "--"), ("diff", "--cached", "--name-only", "--"), ("ls-files", "--others", "--exclude-standard")):
        result = subprocess.run(["git", *command], cwd=root, check=True, capture_output=True, text=True)
        changed.update(line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip())
    return tuple(sorted(changed))


def _candidate_identity(root: Path) -> None:
    if CANDIDATE_HEAD == BASE_HEAD:
        if _git(root, "show", "-s", "--format=%T", CANDIDATE_HEAD) != CANDIDATE_TREE:
            raise ValueError("C01 candidate tree differs from accepted base")
        return
    if not subprocess.run(["git", "cat-file", "-e", CANDIDATE_HEAD], cwd=root, capture_output=True).returncode == 0:
        return
    parent = _git(root, "show", "-s", "--format=%P", CANDIDATE_HEAD).split()
    tree = _git(root, "show", "-s", "--format=%T", CANDIDATE_HEAD)
    if tree != CANDIDATE_TREE or parent not in ([], [BASE_HEAD]):
        raise ValueError("C01 candidate identity differs")


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    selectors = observed_selectors(root)
    return {
        "requiredPathCount": len(IMPLEMENTATION_PATHS), "presentPathCount": len(present),
        "missingPathCount": len(missing), "presentPaths": present, "missingPaths": missing,
        "selectors": list(selectors), "hydrated": not missing,
    }


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    text = path.read_text(encoding="utf-8")
    return tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C01(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", text))


def _assert_exact_selectors(tests: str) -> tuple[str, ...]:
    selectors = tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C01(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", tests))
    if len(selectors) != 5 or tuple(selector[13:16] for selector in selectors) != SELECTOR_SUFFIXES or len(set(selectors)) != 5:
        raise ValueError("C01 requires exactly five ordered G/A/H/I/R selectors")
    return selectors


def _assert_provider_source_slices(root: Path) -> None:
    direct: list[str] = []
    for path in (
        "FieldEvidenceApp/Domain/Backup/RecoverabilityVerificationContractsV1.swift",
        "FieldEvidenceApp/Application/Backup/RecoverabilityVerificationCoordinatorV1.swift",
        "FieldEvidenceApp/Infrastructure/Backup/RecoverabilityVerificationLifecycleAdapterV1.swift",
        "FieldEvidenceApp/Domain/Navigation/RouteRegistryContractsV1.swift",
        "FieldEvidenceApp/Application/Navigation/RouteCoordinatorV1.swift",
    ):
        if (root / path).is_file():
            direct.append(_text(root, path))
    _require_tokens("\n".join(direct), ("RecoverabilityVerificationStagingV1", "RecoverabilityVerificationReceiptV1", "RouteRegistryV1"), "C22/C34 direct prerequisite source slices")


def _assert_s2_v3_regression(root: Path) -> None:
    path = "FieldEvidenceAppTests/S2PersistenceLedgerTests.swift"
    text = _text(root, path)
    _require_tokens(
        text,
        (
            "testDiagnosticsCreatesExactZeroBytesAndReloadsEveryCounterAndBucket",
            "testDiagnosticsCountersAndPurchaseBucketsSaturateAtInt64Max",
            "testDiagnosticsWriteFailureIsNonGatingAndDoesNotInventAnIncrement",
            "DeviceOperationalSupportSnapshotV2", "canonicalOperationalSupportData",
            "migratedV3Object", "Int64.max", "testStartupUsesTheFrozenOrderBeforeEnablingWrites",
        ),
        "S2 diagnostics V3 regression",
    )
    _require_patterns(text, (r"schemaVersion[^\n]{0,40}2", r"Int64"), "S2 diagnostics V3 schema/overflow regression")


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C01 source lanes missing:" + ",".join(status["missingPaths"]))
    contract = _text(root, IMPLEMENTATION_PATHS[0])
    coordinator = _text(root, IMPLEMENTATION_PATHS[1])
    adapter = _text(root, IMPLEMENTATION_PATHS[2])
    view = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[5])
    fixture = _json(root, IMPLEMENTATION_PATHS[6])
    fixture_text = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    _require_tokens(contract, (
        "RecoveryCenterStateV1", "RecoveryAuthoritySourceV1", "RecoveryAuthoritySnapshotV1",
        "ReliabilityStateProjectionV1", "RecoveryCenterProjectionV1", "RecoveryRouteV1",
        "SupportExportPreviewProjectionV1", "PrivacyDataProjectionV1", "PresentationClockV1",
        "SupportFeedbackDraftV1", "FeedbackHandoffPreviewV1", "FeedbackHandoffResultV1",
        "RecoveryCenterLifecycleV1", "NONPERSISTENT_DROP_AND_REBUILD",
        "NONPERSISTENT_MONOTONIC_ONLY", "DEVICE_OPERATIONAL_SUPPORT_STORE_ONLY",
        "ordinaryRecoveryRequiresEncryptedBackup", "ownsSecondRecoveryWriter", "ownsSecondRouter",
        "TypedAvailabilityAndFallbackReceiptV1",
    ), "C01 RecoveryCenter contract")
    _require_tokens(contract, RECOVERY_STATES + RECOVERY_SOURCES, "C01 closed state/source vocabulary")
    _require_patterns(contract, (
        r"case\s+healthy\s*=\s+\"HEALTHY\"", r"case\s+externalActionRequired\s*=\s+\"EXTERNAL_ACTION_REQUIRED\"",
        r"allCases\.count", r"statePrecedence", r"sorted", r"sourceSetSHA256",
        r"ordinaryRecoveryRequiresEncryptedBackup\s*=\s+false", r"ownsSecondRecoveryWriter\s*=\s+false",
        r"ownsSecondRouter\s*=\s+false",
    ), "C01 contract closure")
    _require_tokens(coordinator, (
        "RecoveryCenterCoordinatorV1", "RecoveryCenterProjectionV1", "PresentationClockV1",
        "SupportFeedbackDraftV1", "RecoverySupportExportPreparingV1",
        "RecoveryFeedbackHandoffPerformingV1", "RecoveryCenterCoordinatorBoundaryV1",
        "performsCanonicalWrites = false", "ownsRecoveryStore = false",
        "ownsScratchStorage = false", "ownsRouter = false", "nilSourceMeansHealthy = false",
    ), "C01 coordinator ownership")
    _require_tokens(adapter, (
        "RecoveryCenterLifecycleAdapterV1", "RecoverySupportExportPreparingV1",
        "RecoveryFeedbackHandoffPerformingV1", "DeviceOperationalSupportStoreV3",
        "SupportBundleBuilderV1", "SupportFeedbackDraftV1", "resetScratchData", "eraseScratchData",
        "createsSecondStore = false", "writesWorkspaceTruth = false",
        "includesDraftInBackupOrExport = false", "usesNetworkOrAutomaticUpload = false",
    ), "C01 lifecycle adapter")
    _require_tokens(view, (
        "RecoveryCenterView", "RecoveryCenterProjectionV1", "SupportFeedbackDraftV1",
        "RecoveryCenterAccessibilityIDV1", "standardBackup", "encryptedBackup",
        "supportDraft", "privacyBlocked", "RecoveryCenterStateV1",
    ), "C01 view route/projection")
    selectors = _assert_exact_selectors(tests)
    _require_tokens(tests, (CARD, *EVIDENCE_IDS, "RecoveryCenterCoordinatorV1", "RecoveryRouteV1", "SupportFeedbackDraftV1"), "C01 evidence tests")
    _require_tokens(ui_tests, (CARD, "UIAdoptionPendingPostS10", "XCTSkip", "recovery-center"), "C01 UI deferral test")
    _require_tokens(fixture_text, (CARD, *EVIDENCE_IDS, "HEALTHY", "EXTERNAL_ACTION_REQUIRED", "support", "privacy", "encryptedBackup"), "C01 fixture")
    source = "\n".join((contract, coordinator, adapter, view, tests, ui_tests))
    if re.search(r"\b(?:URLSession|URLRequest|CloudKit|CKContainer|WebSocket|NWConnection|TelemetryClient)\b", source, re.I):
        raise ValueError("C01 network/cloud/telemetry symbols present")
    _assert_s2_v3_regression(root)
    _assert_provider_source_slices(root)
    return selectors


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (217, 15, 232) or len(set(PATH_FENCE)) != 232:
        raise ValueError("C01 fence cardinality or uniqueness differs")
    if NEW_PATHS != _HYDRATED_NEW_PATHS:
        raise ValueError("C01 new-path ordering differs from hydrated fence")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C01 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 4788 or UNAUTHORIZED_OVERLAP_COUNT != 0 or S10_RESERVATION_OVERLAP_COUNT != 0:
        raise ValueError("C01 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C01 app base tree differs")
    _candidate_identity(root)
    missing_base = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C01 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C01 new path already exists at accepted base")


def provider_artifacts(root: Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for card, metadata in _PROVIDER_ARTIFACTS.items():
        files: list[dict[str, Any]] = []
        for path in metadata["paths"]:
            target = root / path
            if target.is_file():
                data = target.read_bytes()
                files.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_PROVIDER"})
            else:
                files.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_PROVIDER"})
        result.append({
            "providerCardID": card, "required": metadata["required"], "capability": metadata.get("capability"),
            "pathFenceDigest": metadata["pathFenceDigest"], "candidateHead": metadata["candidateHead"],
            "candidateTree": metadata["candidateTree"], "checkpointDigest": metadata["checkpointDigest"],
            "contextDigest": metadata["contextDigest"], "verificationReceiptDigest": metadata["verificationReceiptDigest"],
            "contracts": list(metadata["contracts"]), "files": files,
            "allFilesPresent": all(item["sha256"] is not None for item in files),
            "fallback": "DECLARED_TYPED_DISABLED_OR_MANUAL_FALLBACK" if not metadata["required"] else None,
        })
    return result


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "candidateHead": CANDIDATE_HEAD, "candidateTree": CANDIDATE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationRevision": HYDRATION_REVISION,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "fenceCorrectionDigest": FENCE_CORRECTION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "dossierSHA256": DOSSIER_SHA256, "dossierByteCount": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256, "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "registerOrdinal": REGISTER_ORDINAL, "directPrerequisiteCards": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT, "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT,
        "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT, "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
    }


def _common() -> dict[str, Any]:
    return {
        "cardID": CARD, "title": TITLE, "authority": authority(), "evidenceIDs": list(EVIDENCE_IDS),
        "statusFlags": FLAGS, "provisional": not FINAL_HASHES_SEALED, "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


def semantics(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "closedStateCount": len(RECOVERY_STATES), "recoveryStates": list(RECOVERY_STATES),
        "recoveryAuthoritySources": list(RECOVERY_SOURCES), "statePolicy": "EXACTLY_ELEVEN_CLOSED_TRUTHFUL_RECOVERY_CENTER_STATES",
        "contractRefs": list(CONTRACT_REFS), "journeyRefs": list(JOURNEY_REFS),
        "persistentChangeMode": PERSISTENT_CHANGE_MODE, "persistentContractSchema": PERSISTENT_CONTRACT_SCHEMA,
        "persistentRowTypes": list(PERSISTENT_ROW_TYPES), "nonpersistentTypes": list(NONPERSISTENT_TYPES),
        "schemaMigrationBackupRestoreDeleteExportDeltas": False,
        "supportFeedbackDraft": {
            "persistent": True, "owner": "P02-C08", "store": "DeviceOperationalSupportStoreV1",
            "workspaceCanonical": False, "workspaceBackup": False, "workspaceSearch": False,
            "workspaceJournal": False, "workspaceExport": False, "rawUserDefaults": False,
            "scratchPersistence": False, "boundedMessageBytes": 4096,
        },
        "projectionClockAndScratch": "NONCANONICAL_DROP_AND_REBUILD",
        "route": "SOLE_C34_TYPED_RECOVERY_CENTER_ROUTE_NO_SECOND_ROUTER",
        "entryPoints": ["SETTINGS_DATA_AND_RECOVERY", "TODAY_WARNING", "FAIL_CLOSED_STARTUP", "HELP_DIAGNOSTICS"],
        "startup": "BLOCKS_NORMAL_WORKSPACE_AND_SHELL_UNTIL_VALIDATION",
        "optionalEncryptedBackup": {
            "provider": "V23-P03-C54:ENCRYPTED_BACKUP", "typedAvailability": True,
            "availableOrDisabled": True, "standardRecoveryIndependent": True,
            "unavailableFallback": "MANUAL_FALLBACK", "neverGatesOrdinaryRecovery": True,
        },
        "supportExport": {
            "builder": "SupportBundleBuilderV1", "customerContent": False,
            "customerIdentifier": False, "rawLogs": False, "automaticUpload": False,
            "scratchLeaseDeletesOn": ["CANCEL", "SHARE", "EXPIRY", "FAILURE"],
        },
        "privacy": {"owner": "PrivacyPolicyClosureV1", "missingLiveLink": "BLOCKED_OR_DRAFT_NEVER_COMPLETE"},
        "presentationClock": "READ_ONLY_MONOTONIC_PRESENTATION_ONLY",
        "ownership": "NO_SECOND_WRITER_STORE_ROUTER_RENDERER_IMPORTER_OR_IDENTITY_SOURCE",
        "claims": "NO_SECURE_VERIFIED_SAVED_SENT_DELIVERED_OR_APPROVED_CLAIM_BEYOND_ACCEPTED_FACT",
        "lifecycleCoverage": list(LIFECYCLE_COVERAGE),
        "cloneFork": {"configurationClone": "DROPS_NONCANONICAL_RECOVERY_PROJECTION_AND_DRAFT", "workspaceFork": "NO_SECOND_RECOVERY_WRITER"},
        "selectors": list(selectors),
        "forbiddenCapabilities": ["SECOND_ENGINE", "SECOND_ROUTE", "NETWORK", "TELEMETRY", "CLOUD", "NATIVE_IPAD", "AUTOMATIC_UPLOAD", "CUSTOMER_IDENTITY", "DELIVERY_CLAIM"],
    }


def schema_document(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/recovery-center.schema.json",
        "title": TITLE, "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P04C01RecoveryCenterCorpusV1"}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
            "evidenceIDs": {"const": list(EVIDENCE_IDS)}, "selectors": {"const": list(selectors)},
            "recoveryStates": {"const": list(RECOVERY_STATES)}, "closedStateCount": {"const": 11},
            "contractRefs": {"const": list(CONTRACT_REFS)}, "journeyRefs": {"const": list(JOURNEY_REFS)},
            "persistentChangeMode": {"const": PERSISTENT_CHANGE_MODE}, "persistentContractSchema": {"const": PERSISTENT_CONTRACT_SCHEMA},
            "persistentRowTypes": {"const": list(PERSISTENT_ROW_TYPES)}, "nonpersistentTypes": {"const": list(NONPERSISTENT_TYPES)},
            "optionalEncryptedBackup": {"type": "object"}, "supportFeedbackDraft": {"type": "object"},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED}, "provisional": {"const": not FINAL_HASHES_SEALED},
        },
        "required": ["schema", "schemaVersion", "cardID", "evidenceIDs", "selectors", "recoveryStates", "closedStateCount", "contractRefs", "journeyRefs", "persistentChangeMode", "persistentContractSchema", "persistentRowTypes", "nonpersistentTypes", "optionalEncryptedBackup", "supportFeedbackDraft", "finalHashesSealed", "provisional"],
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None}


def _source_projection(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {
        "implementationPaths": list(IMPLEMENTATION_PATHS), "presentPaths": status["presentPaths"],
        "missingPaths": status["missingPaths"], "selectors": list(selectors),
        "sourceSemanticsInspected": bool(status["hydrated"] and not status["missingPaths"]),
        "registerRows": [REGISTER_ROW], "dossierSHA256": DOSSIER_SHA256, "dossierByteCount": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256, "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionByteCount": REGISTER_SECTION_BYTES,
    }


def contract_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C01RecoveryCenterContractV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "directPrerequisites": list(DIRECT_PREREQUISITES), "contractRefs": list(CONTRACT_REFS),
        "journeyRefs": list(JOURNEY_REFS), "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "semantics": semantics(selectors), "sourceProjection": _source_projection(root, selectors),
        "providerArtifacts": provider_artifacts(root),
    })


def evidence_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "focus": ["eleven-state projection", "freshness and startup gate", "standard recovery"], "selectorSuffix": "G01"},
        {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "focus": ["optional encrypted backup available", "typed unavailable/manual fallback", "privacy closure"], "selectorSuffix": "A01"},
        {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "focus": ["duplicate source/failure", "stale or corrupt frontier", "no unsupported claim"], "selectorSuffix": "H01"},
        {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "focus": ["effect-before-receipt", "relaunch and scratch cleanup", "support draft preservation"], "selectorSuffix": "I01"},
        {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "focus": ["replace/restore", "clone/fork quarantine", "erase and privacy-safe export"], "selectorSuffix": "R01"},
    ]
    return _sealed({
        "schema": "V23P04C01RecoveryCenterEvidenceReceiptV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "cases": cases, "testSelectors": list(selectors), "journey": "FJ11",
        "closedRecoveryStates": list(RECOVERY_STATES), "nativeCompileRan": False,
        "hostedDispatchEnabled": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "uiAdoptionSkipped": True, "sourceProjection": _source_projection(root, selectors),
        "providerArtifacts": provider_artifacts(root),
    })


def brand_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C01BrandImpactManifestV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "iPhoneNativeOnly": True,
        "nativeIPadSurface": False, "onDeviceOnly": True, "uiTestDisposition": "EXPLICIT_POST_S10_ADOPTION_SKIP_NO_RESERVED_APP_COMPOSITION_AUTHORITY",
        "adoptionSkipped": True, "networkOrTelemetryFlow": False, "customerIdentityVerified": False,
        "deliveryOrLegalSignatureClaimed": False, "supportBundleAutomaticUpload": False,
        "privacyLiveClosureRequired": True, "sourceProjection": _source_projection(root, selectors),
    })


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_TOOLING"}
    target = root / path
    if not target.is_file():
        if FINAL_HASHES_SEALED:
            raise ValueError("cannot seal missing fence input:" + path)
        return {"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"}
    data = target.read_bytes()
    return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE"}


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
        "schema": "V23P04C01ToolingManifestV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "pathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS),
        "toolingEditPaths": list(TOOLING_EDIT_PATHS), "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS), "fencePathCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED",
        "files": rows, "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None,
        "sourceProjection": _source_projection(root, selectors), "providerArtifacts": provider_artifacts(root),
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
    print(json.dumps({"cardID": CARD, "sourceReady": source_status(ROOT)["hydrated"], "finalHashesSealed": FINAL_HASHES_SEALED, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT}, sort_keys=True))
