#!/usr/bin/env python3
"""Fail-closed tooling contract for V23-P03-C57 MyDayPlanV1.

The implementation rows are owned by the C57 source lane.  This module only
projects the sealed authority into deterministic schema/receipt artifacts and
audits the source rows when they are present.  It deliberately supports an
unsealed scaffold while those rows are being hydrated; no missing source row
is represented as a sealed hash.
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

CARD = "V23-P03-C57"
TITLE = "MyDayPlanV1, bounded membership/order/estimate, carryover, readiness projection, and source-truth reconciliation"
REGISTER_ORDINAL = 88

# Immutable C57 hydration authority.  The app base is the accepted C56 tree;
# the coordination hydration commit is recorded here but is never read at
# runtime.  Source implementation may be staged or committed later.
BASE_HEAD = "160f9b4e8440e730ce7ba725056f33d75471b09c"
BASE_TREE = "6223655a8657fa86467c2b0e9b0579e0c62e9b1d"
CANDIDATE_HEAD = "1ff39bf2"
CANDIDATE_TREE = "bf68792589b662c7e7ab27ec76762357d39302e5"
COORDINATION_HEAD = CANDIDATE_HEAD
COORDINATION_TREE = CANDIDATE_TREE
COORDINATION_CAS_SEQUENCE = 372
CONTEXT_DIGEST = "3baa3ea127c70c2286343ba1070e63461cbfc9dd757035723f4e068dead67f63"
FENCE_DIGEST = "9ca89ed7499e8a4ada6cb716d4a1384d4751abf0fa11a71121028b41e7abd60f"
PREREQUISITE_DIGEST = "e0a33e9c8ab580b041a2c3fd2eea4caba9dd04821f9efd50296abf39a632bff4"
HYDRATION_TRANSITION_DIGEST = "c1dce6fe8a03bc2d903e21c178faa49f17f1eac9fca75fa3d5ec1789b06bac3a"
COORDINATION_LEDGER_DIGEST = "ffaf89f9380c8b8bf1d7e5790f9c8e11b5d6c31d3db5e0e5903ca43061151e2b"
COORDINATION_PROJECTION_DIGEST = "d7426a4bcebc12b33453d2c06038d3a5afd7015368a136ebe140a15bd4f8aefe"

# Immutable planning slices supplied by the C57 hydration record.
DOSSIER_SHA256 = "f9f3f484758772242371d8c62cb836bcd5ce28632da4c3f291321d2a06e367c9"
DOSSIER_BYTES = 7090
REGISTER_ROW_SHA256 = "7b074e1b98caf476c18c3db255110031d42536517f041b6d6e19149f767a9815"
REGISTER_ROW_BYTES = 305
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217

EXPECTED_EXISTING_PATH_COUNT = 201
EXPECTED_NEW_PATH_COUNT = 14
EXPECTED_FENCE_PATH_COUNT = 215
AUTHORIZED_OVERLAP_COUNT = 4552
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 86
PRIOR_OWNED_PATH_COUNT = 1398
S10_RESERVED_PATH_COUNT = 86

SCHEMA_PATH = "Scripts/v23/my-day-plan.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C57MyDayPlanContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C57MyDayPlanEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C57BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C57-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c57_contracts.py",
    "Scripts/v23/generate_p03_c57_contracts.py",
    "Scripts/v23/verify_p03_c57_contracts.py",
)
GENERATED_PATHS = (CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_PATHS)
OUTPUT_PATHS = (SCHEMA_PATH, *GENERATED_PATHS)

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/MyDay/MyDayContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/MyDayPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/MyDay/MyDayCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/MyDay/MyDayLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_65MyDayPlanTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/MyDay/V22P03C57MyDayPlanCorpusV1.json",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

# Existing owners which are required to admit the two canonical My Day rows
# without making readiness/frontier/report/search values durable.  They remain
# inherited fence inputs and are never synthesized by this tooling lane.
_C57_SUPPORT_PATHS = (
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
)

# Provider inventories are loaded from the accepted local tooling modules,
# with source-byte pins so a provider cannot silently widen this fence.
_PROVIDERS = (
    ("p03_c15_contracts.py", "2a5f02f5f979c49723d69a2d14fe1ffacedb64b31d624c15fff1b11cdbf4340c", "C15"),
    ("p03_c28_contracts.py", "ef71565053ca34f23f07e55a33e34d8b76125fe7fd46d492279b624d6b9cae33", "C28"),
    ("p03_c34_contracts.py", "225f590eb6e5c74def572ddd9956450ba518e2776fd47f5a59368df8ce5f9a39", "C34"),
    ("p03_c51_contracts.py", "22a6629879e577588f422b52092db3efc17edc73eb5516180186d83675719f3c", "C51"),
)


def _provider_fence(file_name: str, expected_sha: str, label: str) -> tuple[str, ...]:
    path = Path(__file__).with_name(file_name)
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected_sha:
        raise ValueError(f"sealed {label} tooling inventory differs")
    spec = importlib.util.spec_from_file_location(f"_sealed_{label.lower()}_contracts", path)
    if spec is None or spec.loader is None:
        raise ValueError(f"sealed {label} tooling inventory unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    fence = tuple(module.PATH_FENCE)
    if not fence or len(fence) != len(set(fence)):
        raise ValueError(f"sealed {label} fence contains duplicates")
    return fence


_PROVIDER_FENCES = tuple(_provider_fence(*entry) for entry in _PROVIDERS)

# Provider modules expose NEW_PATHS.  Their tooling rows are the last eight
# rows of every fourteen-row NEW_PATHS tuple; they are loaded with the same
# byte pins as the fence inventories.
def _provider_new_paths() -> tuple[tuple[str, ...], ...]:
    values: list[tuple[str, ...]] = []
    for file_name, expected_sha, label in _PROVIDERS:
        path = Path(__file__).with_name(file_name)
        spec = importlib.util.spec_from_file_location(f"_sealed_{label.lower()}_new_paths", path)
        if spec is None or spec.loader is None:
            raise ValueError(f"sealed {label} tooling inventory unavailable")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        new = tuple(module.NEW_PATHS)
        if len(new) != 14:
            raise ValueError(f"sealed {label} new path count differs")
        values.append(new)
    return tuple(values)


_PROVIDER_NEW = _provider_new_paths()
_EXCLUDED_PROVIDER_TOOLING = frozenset(path for new in _PROVIDER_NEW for path in new[6:])
EXISTING_PATHS = tuple(sorted(set().union(*map(set, _PROVIDER_FENCES)) - _EXCLUDED_PROVIDER_TOOLING))
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
CONTRACT_REFS = (
    "MyDayKeyV1", "MyDayPlanV1", "MyDayCarryoverReceiptV1", "MyDayReadinessProjectionV1",
    "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1",
)
JOURNEY_REFS = ("FJ12",)
LIFECYCLE_COVERAGE = (
    "SCHEMA_VERSION", "WRITER_QUERY", "MIGRATION", "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK", "IMPORT_EXPORT", "JOURNAL_REPLAY", "SEARCH_REBUILD",
    "REPORT_PROJECTION", "DELETE_ERASE", "RETENTION", "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX", "INTERRUPTION", "IDEMPOTENT_RECEIPTS",
)
PERSISTENCE_ROW_TYPES = ("MyDayPlanRowV1", "MyDayCarryoverReceiptRowV1")
NONPERSISTENT_TYPES = ("MyDayReadinessProjectionV1", "MyDaySourceFrontierV1")
PERSISTENT_SCHEMA_VERSION = 42
RECORDS_SCHEMA_VERSION = 41
ACTIVE_MODEL_COUNT = 142
DURABLE_FAMILY_COUNT = 2
MAX_MEMBERSHIP = 50
MIN_ESTIMATE_MINUTES = 1
MAX_ESTIMATE_MINUTES = 720
REGISTER_ROW = '| 88 | <a id="v23-p03-c57-register"></a>[`V23-P03-C57`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c57) | MyDayPlanV1, bounded membership/order/estimate, carryover, readiness projection, and source-truth reconciliation | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C34`, `V23-P03-C51` | `ADDED_V23` |'
FLAGS = {name: False for name in (
    "activation", "native", "hosted", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

# All six source/test/fixture rows have now landed and passed the source
# contract audit; generated rows may therefore bind exact current bytes.
FINAL_HASHES_SEALED = True


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _json(root: Path, relative: str) -> dict[str, Any]:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + relative)
    return value


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate JSON key:" + key)
        value[key] = item
    return value


def _valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _authority_pins_ready() -> bool:
    heads = (BASE_HEAD, BASE_TREE, COORDINATION_HEAD, COORDINATION_TREE)
    digests = (CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST,
               COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST, DOSSIER_SHA256,
               REGISTER_ROW_SHA256, REGISTER_SECTION_SHA256)
    # The coordination handoff intentionally records its commit in the
    # accepted short form; the app base remains an exact forty-byte SHA.
    return all(re.fullmatch(r"[0-9a-f]{8,40}", value) for value in heads) and all(_valid_sha(value) for value in digests)


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    lower = text.lower()
    missing = [token for token in tokens if token.lower() not in lower]
    if missing:
        raise ValueError(f"{label} missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I | re.S) is None]
    if missing:
        raise ValueError(f"{label} missing patterns:" + ",".join(missing))


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(["git", "cat-file", "-e", f"{BASE_HEAD}:{relative}"], cwd=root, capture_output=True).returncode == 0


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed: set[str] = set()
    for command in (("diff", "--name-only", BASE_HEAD, "--"), ("diff", "--cached", "--name-only", "--"), ("ls-files", "--others", "--exclude-standard")):
        result = subprocess.run(["git", *command], cwd=root, check=True, capture_output=True, text=True)
        changed.update(line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip())
    return tuple(sorted(changed))


def _candidate_identity(root: Path) -> None:
    # The hydration candidate is optional during scaffold.  If its object is
    # available, it must be a direct child of the exact C56 app base.
    exists = subprocess.run(["git", "cat-file", "-e", CANDIDATE_HEAD], cwd=root, capture_output=True).returncode == 0
    if not exists:
        return
    parent = _git(root, "show", "-s", "--format=%P", CANDIDATE_HEAD).split()
    tree = _git(root, "show", "-s", "--format=%T", CANDIDATE_HEAD)
    if parent != [BASE_HEAD] or tree != CANDIDATE_TREE:
        raise ValueError("C57 candidate is not the exact direct child/tree of C56 base")


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    return {
        "hydrated": not missing,
        "requiredPathCount": len(IMPLEMENTATION_PATHS),
        "presentPathCount": len(present),
        "missingPathCount": len(missing),
        "presentPaths": present,
        "missingPaths": missing,
    }


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"(?m)^\s*func\s+(testV23P03C57(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def _assert_exact_selectors(tests: str) -> tuple[str, ...]:
    selectors = tuple(re.findall(r"(?m)^\s*func\s+(testV23P03C57(?:G|A|H|I|R)\d{2}\w*)\s*\(", tests))
    if len(selectors) != 5 or tuple(selector[13:16] for selector in selectors) != SELECTOR_SUFFIXES or len(set(selectors)) != 5:
        raise ValueError("C57 requires exactly five ordered G/A/H/I/R selectors")
    return selectors


def _assert_support_contracts(root: Path) -> None:
    by_path = {path: _text(root, path) for path in _C57_SUPPORT_PATHS}
    backup = "\n".join(by_path.values())
    _require_tokens(
        backup,
        (
            "C57MyDayBackupEnrollmentV1", "persistentSchemaVersion = 42", "recordsSchemaVersion = 41",
            "durableFamilyCount = 2", "MyDayPlanRowV1", "MyDayCarryoverReceiptRowV1",
            "myDayPlans", "myDayCarryoverReceipts", "nonactivePlanReferences",
            "exactNonactiveReferences", "replaceRestorePreservesExactHistory",
            "configurationCloneOmitsAllMyDayTruth", "workspaceForkRetainsNonactiveHistoryOnly",
            "readinessSourceStateAndDueAreExcluded", "C57MyDayKernelBackupRestoreEnrollmentV1",
            "derivedFamiliesExcluded", "PersistentSchemaV42", "v42PersistentModelNames",
            "C57MyDayBackupPackageValidationV1", "C57MyDayRestoreIdentityBoundaryV1",
        ),
        "C57 V42/records41 backup and persistence closure",
    )
    _require_patterns(
        backup,
        (
            r"recordsSchemaVersion\s*==\s*41",
            r"persistentSchemaVersion\s*==\s*42",
            r"records\.myDayPlans",
            r"records\.myDayCarryoverReceipts",
            r"records\.nonactivePlanReferences",
            r"exactNonactiveReferences",
            r"C57MyDayBackupEnrollmentV1\.validate",
            r"C57MyDayBackupPackageValidationV1\.validate",
            r"PersistentSchemaV41\.models\+\[MyDayPlanRowV1\.self,MyDayCarryoverReceiptRowV1\.self\]",
        ),
        "C57 backup exact-row admission",
    )
    _require_tokens(
        by_path["FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift"],
        ("commitMyDay", "applyMyDay", "persistedMyDayEffectMatches", "currentRevision", "concurrencyIdentities", "MyDayMutationReceiptV1", "MyDayCommandReplayResolutionV1"),
        "C57 incumbent writer and replay boundary",
    )
    _require_tokens(
        "\n".join(by_path[path] for path in _C57_SUPPORT_PATHS[11:]),
        ("C57MyDaySearchCoordinatorBoundaryV1", "C57MyDayLocalSearchIndexBoundaryV1", "C57MyDaySearchRebuildBoundaryV1", "C57MyDayReportProjectionRegistryV1", "C57MyDayKernelDeletionEraseEnrollmentV1", "C57MyDayEraseAllPolicyV1", "rebuildWritesNoMyDayCanonicalState", "registryOwnsNoMyDayPersistence"),
        "C57 derived search/report/delete closure",
    )


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C57 source lanes missing:" + ",".join(status["missingPaths"]))
    source = "\n".join(_text(root, path) for path in IMPLEMENTATION_PATHS[:4])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    fixture = _json(root, IMPLEMENTATION_PATHS[5])
    fixture_text = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    _assert_support_contracts(root)
    _require_tokens(source, CONTRACT_REFS[:4], "C57 closed MyDay contract declarations")
    _require_tokens(source, ("schemaVersion", "workspaceID", "civilDate", "ianaTimeZoneIdentifier", "manualOrder", "estimate"), "C57 plan identity and owned fields")
    _require_tokens(source, ("maximumItems", "minimumEstimateMinutes", "maximumEstimateMinutes", "wholeMinutes", "720", "reference"), "C57 bounded membership/estimate")
    _require_tokens(source, ("MyDaySourceStateV1", "MyDayReadinessV1", "dueAt", "frontiers", "currentReference", "sourceClosureSHA256"), "C57 projected source truth")
    _require_tokens(source, ("MyDayCarryoverPlanV1", "MyDayCarryoverReceiptV1", "targetKey", "selectedSourceItems", "preserve"), "C57 carryover boundary")
    _require_tokens(source, ("duplicateReference", "missingSource", "stale", "reopened", "retired", "reconciliation"), "C57 reconciliation topology")
    _require_tokens(source, ("C57MyDayLifecycleBoundaryV1", "readinessAndSourceStateAreNonpersistent", "replaceRestorePreservesExactPlans", "configurationCloneOmitsPlans", "workspaceForkRetainsNonactiveHistoryOnly", "dispatchesOrSchedulesWork", "storesActualDuration", "MyDayCommandReplayResolutionV1"), "C57 lifecycle boundary")
    _require_tokens(source, ("canonicalWriterIsIncumbentWorkspaceWriter", "lifecycleIsInfrastructureOwned", "sourceMutationCount", "storedDerivedProjectionCount"), "C57 ownership closure")
    _require_tokens(source, ("dispatchesOrSchedulesWork", "automaticallyCarriesAcrossDateOrZone", "removalMutatesSourceWork"), "C57 excluded mutation boundary")
    _require_patterns(source, (r"maximumItems\s*=\s*50", r"minimumEstimateMinutes\s*=\s*1", r"maximumEstimateMinutes\s*=\s*720", r"items\.count\s*<=\s*MyDayLimitsV1\.maximumItems"), "C57 bounds")
    selectors = _assert_exact_selectors(tests)
    _require_tokens(tests, (CARD, *EVIDENCE_IDS, "MyDayPlanV1", "carryover", "readiness", "source"), "C57 evidence selector coverage")
    _require_tokens(fixture_text, (CARD, *EVIDENCE_IDS, "maximumItems", "persistentSchemaVersion", "recordsSchemaVersion", "canonicalRowKinds"), "C57 fixture contract")
    if re.search(r"\b(?:URLSession|URLRequest|CloudKit|CKContainer|WebSocket|NWConnection)\b", source, re.I):
        raise ValueError("C57 network/runtime symbols present")
    return selectors


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (201, 14, 215) or len(set(PATH_FENCE)) != 215:
        raise ValueError("C57 fence cardinality or uniqueness differs")
    if NEW_PATHS != (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS):
        raise ValueError("C57 new-path ordering differs")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C57 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 4552 or UNAUTHORIZED_OVERLAP_COUNT != 0:
        raise ValueError("C57 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C57 app base tree differs")
    _candidate_identity(root)
    if any(not _base_exists(root, path) for path in EXISTING_PATHS):
        raise ValueError("C57 inherited fence path absent from base")
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C57 new path already exists at base")


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "candidateHead": CANDIDATE_HEAD, "candidateTree": CANDIDATE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "dossierSHA256": DOSSIER_SHA256, "dossierByteCount": DOSSIER_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256, "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "registerOrdinal": REGISTER_ORDINAL,
        "directPrerequisiteCards": ["V23-P03-C34", "V23-P03-C51"],
        "contractProviderCards": ["V23-P03-C15", "V23-P03-C28", "V23-P03-C51"],
        "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT, "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
    }


def _common() -> dict[str, Any]:
    return {
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS), "statusFlags": FLAGS,
        "provisional": not FINAL_HASHES_SEALED, "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


def semantics(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "contractRefs": list(CONTRACT_REFS), "journeyRefs": list(JOURNEY_REFS),
        "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION, "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
        "activeModelCount": ACTIVE_MODEL_COUNT, "durableFamilyCount": DURABLE_FAMILY_COUNT,
        "persistentRowTypes": list(PERSISTENCE_ROW_TYPES), "nonpersistentTypes": list(NONPERSISTENT_TYPES),
        "onePlanPerWorkspaceCapturedCivilDateAndTimeZone": True,
        "membership": {"maximumStableReferences": MAX_MEMBERSHIP, "existingRootsOnly": True, "manualOrderOwned": True},
        "estimate": {"wholeMinutesOnly": True, "minimum": MIN_ESTIMATE_MINUTES, "maximum": MAX_ESTIMATE_MINUTES, "neverActualDuration": True},
        "sourceTruthProjection": {"status": True, "due": True, "readiness": True, "completion": True, "cancellation": True, "reopen": True, "actualDuration": False},
        "carryover": {"midnight": True, "dst": True, "timeZoneChange": True, "explicitReceipt": "MyDayCarryoverReceiptV1", "preservesPriorHistory": True},
        "reconciliation": ["duplicate", "supersededOccurrence", "scheduleEdit", "completion", "reopen", "retirement", "restore", "visibleOutcome"],
        "lifecycleCoverage": list(LIFECYCLE_COVERAGE),
        "canonicalRecordWriter": "P02-C01", "artifactWriter": "NONPERSISTENT", "semanticLifecycleOwner": "P03-C57", "lifecycleEnrollmentOwner": "P02-C09", "primaryConsumers": ["P04-C41"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1", "P03ShippingSurfaceSetV1", "P04BrandClosureSetV1"],
        "invalidationConsumers": ["V23-P04-C41", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1", "FJ12"],
        "replaceRestore": "EXACT_MY_DAY_PLANS_AND_CARRYOVER_RECEIPTS",
        "configurationClone": "OMITS_PLANS", "workspaceFork": "RETAINS_NONACTIVE_HISTORY_ONLY",
        "forbiddenCapabilities": ["DISPATCH", "ROUTE_OPTIMIZATION", "AUTO_SCHEDULING", "DUE_DATE_MUTATION", "PLANNER_NOTIFICATIONS", "SECOND_WORK_LEDGER", "UNLISTED_ROOTS", "NETWORK", "TELEMETRY", "PROCUREMENT", "VALUATION", "TAX", "SERIALIZED_LOTS", "REPLENISHMENT", "NATIVE_IPAD"],
        "selectors": list(selectors),
    }


def schema_document(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/my-day-plan.schema.json",
        "title": TITLE, "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C57MyDayPlanCorpusV1"}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
            "contractRefs": {"const": list(CONTRACT_REFS)}, "journeyRefs": {"const": list(JOURNEY_REFS)}, "evidenceIDs": {"const": list(EVIDENCE_IDS)},
            "selectors": {"const": list(selectors)}, "persistentSchemaVersion": {"const": PERSISTENT_SCHEMA_VERSION},
            "recordsSchemaVersion": {"const": RECORDS_SCHEMA_VERSION}, "activeModelCount": {"const": ACTIVE_MODEL_COUNT},
            "durableFamilyCount": {"const": DURABLE_FAMILY_COUNT}, "maximumMembership": {"const": MAX_MEMBERSHIP},
            "estimateMinutes": {"type": "integer", "minimum": MIN_ESTIMATE_MINUTES, "maximum": MAX_ESTIMATE_MINUTES},
            "persistentRowTypes": {"const": list(PERSISTENCE_ROW_TYPES)}, "nonpersistentTypes": {"const": list(NONPERSISTENT_TYPES)},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED}, "provisional": {"const": not FINAL_HASHES_SEALED},
        },
        "required": ["schema", "schemaVersion", "cardID", "contractRefs", "journeyRefs", "evidenceIDs", "selectors", "persistentSchemaVersion", "recordsSchemaVersion", "activeModelCount", "durableFamilyCount", "maximumMembership", "persistentRowTypes", "nonpersistentTypes", "finalHashesSealed", "provisional"],
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None}


def _source_projection(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {"implementationPaths": list(IMPLEMENTATION_PATHS), "presentPaths": status["presentPaths"], "missingPaths": status["missingPaths"], "selectors": list(selectors), "sourceSemanticsInspected": bool(status["hydrated"] and not status["missingPaths"]), "registerRows": [REGISTER_ROW], "dossierSHA256": DOSSIER_SHA256, "dossierByteCount": DOSSIER_BYTES, "registerRowSHA256": REGISTER_ROW_SHA256, "registerRowByteCount": REGISTER_ROW_BYTES, "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionByteCount": REGISTER_SECTION_BYTES}


def contract_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({"schema": "V23P03C57MyDayPlanContractV1", "schemaVersion": 1, **_common(), "contractRefs": list(CONTRACT_REFS), "journeyRefs": list(JOURNEY_REFS), "directPrerequisites": ["V23-P03-C34", "V23-P03-C51"], "contractProviders": ["V23-P03-C15", "V23-P03-C28", "V23-P03-C51"], "semantics": semantics(selectors), "sourceProjection": _source_projection(root, selectors)})


def evidence_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "focus": ["bounded plan identity", "membership/order/estimate", "source readiness projection"]},
        {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "focus": ["DST", "time-zone change", "explicit carryover receipt"]},
        {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "focus": ["duplicate", "superseded occurrence", "retired/restored source"]},
        {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "focus": ["journal replay", "idempotency", "search rebuild"]},
        {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "focus": ["replace restore", "configuration clone", "workspace fork", "erase"]},
    ]
    return _sealed({"schema": "V23P03C57MyDayPlanEvidenceReceiptV1", "schemaVersion": 1, **_common(), "cases": cases, "testSelectors": list(selectors), "journey": "FJ12", "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalLockedState": "REQUIRED_PENDING_OWNER", "sourceProjection": _source_projection(root, selectors)})


def brand_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({"schema": "V23P03C57BrandImpactManifestV1", "schemaVersion": 1, **_common(), "uiSurfaceDelta": True, "brandSurfaceDelta": True, "iPhoneNativeOnly": True, "nativeIPadSurface": False, "onDeviceOnly": True, "networkOrTelemetryFlow": False, "customerIdentityVerified": False, "deliveryOrLegalSignatureClaimed": False, "sourceProjection": _source_projection(root, selectors)})


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE"}
    target = root / path
    if not target.is_file():
        if FINAL_HASHES_SEALED:
            raise ValueError("cannot seal missing fence input:" + path)
        return {"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"}
    data = target.read_bytes()
    return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE"}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    selectors = assert_source_contracts(root) if source_status(root)["hydrated"] else ()
    rendered: dict[str, bytes] = {SCHEMA_PATH: pretty(schema_document(selectors)), CONTRACT_PATH: pretty(contract_document(root, selectors)), EVIDENCE_PATH: pretty(evidence_document(root, selectors)), BRAND_PATH: pretty(brand_document(root, selectors))}
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({"schema": "V23P03C57ToolingManifestV1", "schemaVersion": 1, **_common(), "pathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "toolingEditPaths": list(TOOLING_EDIT_PATHS), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "fencePathCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS), "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED", "files": rows, "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None, "sourceProjection": _source_projection(root, selectors)})
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def _self_parse() -> None:
    for path in SCRIPT_PATHS:
        local = Path(__file__).with_name(Path(path).name)
        if local.is_file():
            ast.parse(local.read_text(encoding="utf-8"), filename=path)


if __name__ == "__main__":
    _self_parse()
    print(json.dumps({"cardID": CARD, "sourceReady": False, "finalHashesSealed": FINAL_HASHES_SEALED, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT}, sort_keys=True))
