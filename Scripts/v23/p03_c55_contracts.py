#!/usr/bin/env python3
"""Fail-closed Parts & Stock contract tooling for V23-P03-C55.

The product lanes and tooling lane share one hydrated fence.  Generation is
allowed only after every new source row is present and passes the static
contract checks.  The manifest seals every current fence input except itself,
which avoids a circular digest while retaining a complete reproducible input
inventory.  Native, hosted, adoption, acceptance, and release flags remain
false until their later authorities exist.
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

CARD = "V23-P03-C55"
TITLE = "Bounded local Parts & Stock catalog, storage labels, append-only movements, work usage, transfer, and balance projection"
REGISTER_ORDINAL = 86

# The values below are the immutable card/fence authority supplied by the
# C55 hydration record.  They are metadata only; this lane never reads or
# writes the external coordination store.
BASE_HEAD = "e4bb386889a4051efeb9359fef9a90fbd7c70d54"
BASE_TREE = "1a409af2305ddc1e78754ccd70ea05f9572ed44d"
COORDINATION_HEAD = "3aa53643bccfecf070b9805041faf7f5536684c7"
COORDINATION_TREE = "a6c2a8f5319761ad333ac91d66f07764d4a14b2d"
COORDINATION_CAS_SEQUENCE = 364
CONTEXT_DIGEST = "dbd3e3505c1a0e91a0bb2ede75b9bcd4ee32caa8665f70d32f78c2d4ff6f8ee7"
FENCE_DIGEST = "7c8198a356f283683194f05b593e6cb11b0cdb32e4a1fad3d2a48d049e64b906"
PREREQUISITE_DIGEST = "6f2d54da1c0cf5aea1740df3e24ceb4e910bbf834f32f92c7aa118e4c839ceee"
HYDRATION_TRANSITION_DIGEST = "52f225304d45a333bf31ed861879c63e60b345c5dd038601d14aa6937a85988e"
COORDINATION_LEDGER_DIGEST = "47705368b24e20e196067451b07d7c4fedc700c94576164e425bbe342b2148a8"
COORDINATION_PROJECTION_DIGEST = "26e44dafb53b79340b47715141948d3886f3f6c67e4f5fbc7509fc95ec8f306f"

PRIOR_FENCE_COUNT = 84
PRIOR_OWNED_PATH_COUNT = 1370
AUTHORIZED_OVERLAP_COUNT = 3915
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
S10_RESERVED_PATH_COUNT = 86

# Immutable source slices sealed by the C55 hydration record.
DOSSIER_SHA256 = "cd8af6fd0f7d03098aac5df963a1f5902400ee71c93e3cb3a322f38d87bc83e8"
DOSSIER_BYTES = 7916
REGISTER_ROW_SHA256 = "acef3136f58f6eb9003f7813e7308661854acd701be09978c3ed57eab23dbed9"
REGISTER_ROW_BYTES = 313
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217

SCHEMA_PATH = "Scripts/v23/parts-stock.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C55PartsStockContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C55PartsStockEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C55BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C55-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c55_contracts.py",
    "Scripts/v23/generate_p03_c55_contracts.py",
    "Scripts/v23/verify_p03_c55_contracts.py",
)
GENERATED_PATHS = (CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
OUTPUT_PATHS = (SCHEMA_PATH, *GENERATED_PATHS)

# Product implementation owns these six rows.  They are deliberately absent
# on the C55 tooling-base tree and therefore never get synthesized here.
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/PartsStock/PartsStockContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/PartsStockPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/PartsStock/PartsStockCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/PartsStock/PartsStockLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_63PartsStockTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/PartsStock/V22P03C55PartsStockCorpusV1.json",
)

# C55's hydrated fence includes the accepted C51 inventory plus the direct
# C49 work-resource contract rows and the five existing local lifecycle
# authorities needed for closure.  The C51 inventory is pinned so a later
# mutation cannot silently widen this card's fence.
_C51_PATH = Path(__file__).with_name("p03_c51_contracts.py")
_C51_SHA256 = "22a6629879e577588f422b52092db3efc17edc73eb5516180186d83675719f3c"
_C49_IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/WorkResources/WorkResourceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkResourcePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/WorkResources/WorkResourceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/WorkResources/WorkResourceLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_56WorkResourceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/WorkResources/V22P03C49WorkResourceCorpusV1.json",
)
_C55_LIFECYCLE_SUPPORT_PATHS = (
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsLogger.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/SystemHealthContractsV1.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/S2PersistenceLedgerTests.swift",
)
_BACKUP_PROPAGATION_PATHS = (
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
)
_MUTATION_PROJECTION_PATHS = (
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
)


def _sealed_c51_existing() -> tuple[str, ...]:
    """Load only the prior committed inventory; never load coordination state."""
    if not _C51_PATH.is_file() or hashlib.sha256(_C51_PATH.read_bytes()).hexdigest() != _C51_SHA256:
        raise ValueError("sealed C51 tooling inventory differs")
    spec = importlib.util.spec_from_file_location("_sealed_p03_c51_contracts", _C51_PATH)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load sealed C51 tooling inventory")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return tuple(module.EXISTING_PATHS)


EXISTING_PATHS = _sealed_c51_existing() + _C49_IMPLEMENTATION_PATHS + _C55_LIFECYCLE_SUPPORT_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_PATHS)
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
GENERATED_INPUT_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH)

FLAGS = {name: False for name in (
    "activation", "native", "hosted", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
SELECTOR_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
CONTRACT_REFS = (
    "LocalPartDefinitionV1", "StockStorageLocationV1", "StockMovementEventV1",
    "StockBalanceProjectionV1", "StockTransferReceiptV1", "StockUseOnWorkReceiptV1",
    "StockUseReversalReceiptV1", "StockReturnAgainstUseReceiptV1",
    "AbandonUnverifiedStockDispositionV1", "StockAbandonmentReceiptV1",
    "StockPartRetirementReceiptV1", "PartsStockMutationV1", "PartsStockBackupSnapshotV1",
)
SOURCE_LANE_NOTE = "Six source rows are audited, never synthesized, and sealed with the complete current fence input inventory."

# This is intentionally closed. Values are uppercase canonical codes; no
# locale/display label or caller-provided unit alias is persisted as truth.
CANONICAL_UNITS = (
    "EACH", "MILLIMETER", "CENTIMETER", "METER", "INCH", "FOOT",
    "GRAM", "KILOGRAM", "OUNCE", "POUND", "MILLILITER", "LITER",
    "FLUID_OUNCE", "GALLON",
)
STORAGE_LABEL_KINDS = ("SHOP", "VEHICLE", "KIT", "OTHER")
MOVEMENT_KINDS = (
    "OPENING_COUNT", "PHYSICAL_COUNT", "ADJUSTMENT_INCREASE", "ADJUSTMENT_DECREASE",
    "USE_ON_WORK", "RETURN_AGAINST_USE", "TRANSFER_OUT", "TRANSFER_IN", "REVERSE_USE",
)
BALANCE_STATES = ("UNKNOWN", "KNOWN")
KNOWN_ONLY_MUTATIONS = ("ADJUSTMENT", "USE", "TRANSFER")
PERSISTENCE_ROW_TYPES = (
    "LocalPartDefinitionRowV1", "StockStorageLocationRowV1", "StockMovementEventRowV1",
    "StockUseReceiptRowV1", "StockReturnReceiptRowV1", "StockUseReversalReceiptRowV1",
    "AbandonUnverifiedStockRowV1",
)
C55_SNAPSHOT_ROW_CAP = 100_000
C55_TERMINAL_IDENTITY_CAP = 200_000
C55_FRESH_DESTINATION_IDENTITY_DISPOSITION = "destinationPreservingPartsStock"
C55_CLONE_FORK_IDENTITY_DISPOSITION = "destination"
C55_SAME_REPLICA_IDENTITY_DISPOSITION = "preserve"
LIFECYCLE_COVERAGE = (
    "SCHEMA_VERSION", "MIGRATION", "WRITER_QUERY", "BACKUP",
    "REPLACE_RESTORE", "CLONE_FORK", "IMPORT_EXPORT", "JOURNAL_REPLAY",
    "SEARCH_REBUILD", "REPORT_PROJECTION", "DELETE_ERASE", "RETENTION",
    "COMPATIBILITY", "DOWNGRADE_FORWARD_FIX", "INTERRUPTION", "IDEMPOTENT_RECEIPTS",
)
BACKUP_PROPAGATION = {
    "persistentSchemaVersion": 41,
    "recordsSchemaVersion": 40,
    "durableFamilyCount": 7,
    "canonicalSnapshotType": "PartsStockBackupSnapshotV1",
    "recordEnvelopeField": "partsStockSnapshot",
    "restoresSevenFamiliesAtomically": True,
    "usesIncumbentLifecyclePort": True,
    "derivedBalanceAndSearchAreRebuilt": True,
    "preparedRestoreSnapshot": True,
    "materializeRestoreStaging": True,
    "exactTopology": {
        "movementEvents": "movements",
        "transfer": "paired_transfer_out_and_in_movements",
        "useReceipts": "uses",
        "useReversalReceipts": "reversals",
        "returnReceipts": "returns",
        "abandonmentDispositions": "abandonments",
    },
}
SECURITY_AUDIT = {
    "virtualPartLocationStockBalanceStreamCASSeparateFromLocationCatalog": True,
    "dualPhysicalAndStreamPostImages": True,
    "nativeProjectedWorkspaceClosure": True,
    "partLocationOnlyExternalBaselines": True,
    "activeRev1CloneFork": True,
    "materializeBeforeInsert": True,
    "nilStreamExternalProjection": True,
    "terminalIdentityBoundIncludesWorkResourceSuccessors": True,
    "contiguousMovementStreamReplayAndGenesis": True,
    "stableMutationPostImageOrdering": True,
    "exactC55ExpectedIdentityMembership": True,
    "statefulRevisionMapReplayTerminalEquality": True,
    "cloneForkDefinitionsOnlyJournalQuarantine": True,
    "mixedHistoryRetainedReceiptProjection": True,
    "overflowSafeCatalogAndBalanceReplay": True,
    "exactReplayDigestComparison": True,
    "firstAndSubsequentReturnFrontierResolution": True,
    "unitHistoryAndExplicitMaterialUnitBinding": True,
    "retirementCompletenessThrows": True,
    "decodedPredecessorCatalogBinding": True,
    "exactBackupTransferUseReversalReturnTopology": True,
    "exactPartsStockSnapshotJournalClosure": True,
    "c49SuccessorSchemaAdmissionAndWorkClosure": True,
    "exactAbandonmentRetirementReplayBinding": True,
    "records40Persistent41SystematicAdmission": True,
    "integerNSNumberNoFractionalTruncation": True,
    "singleCloneForkPreparation": True,
}
EXCLUDED_CAPABILITIES = (
    "VENDORS", "PROCUREMENT", "PURCHASING", "PURCHASE_ORDERS", "VALUATION",
    "TAX", "INVOICING", "SERIALIZED_LOTS", "RESERVATIONS", "CLOUD_SYNC",
    "REPLENISHMENT_AUTOMATION",
)


def canonical(value: Any) -> bytes:
    """Return deterministic JSON bytes and reject non-finite numeric values."""
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8") + b"\n"


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


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


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(
        ["git", "cat-file", "-e", f"{BASE_HEAD}:{relative}"],
        cwd=root, capture_output=True,
    ).returncode == 0


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed: set[str] = set()
    for command in (
        ["git", "diff", "--name-only", BASE_HEAD, "--"],
        ["git", "diff", "--cached", "--name-only", "--"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        result = subprocess.run(command, cwd=root, check=True, capture_output=True, text=True)
        changed.update(line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip())
    return tuple(sorted(changed))


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"{label} missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    # Do not enable DOTALL for whole Swift files: a missing broad pattern can
    # otherwise make greedy ``.*`` backtracking effectively unbounded.  A
    # caller that needs a cross-line assertion should use explicit ``\\s*``
    # or separate token checks.
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I) is None]
    if missing:
        raise ValueError(f"{label} missing patterns:" + ",".join(missing))


def _require_order(text: str, before: str, after: str, label: str) -> None:
    """Require two source-grounded regexes in the declared execution order."""
    before_match = re.search(before, text, re.I)
    after_match = re.search(after, text, re.I)
    if before_match is None or after_match is None or before_match.start() >= after_match.start():
        raise ValueError(f"{label} order differs")


def _require_exact_enum_values(text: str, enum_name: str, expected: tuple[str, ...], label: str) -> None:
    """Prove a closed Swift raw-value enum has exactly the expected codes."""
    match = re.search(
        rf"enum\s+{re.escape(enum_name)}\b(.*?)(?=\n(?:enum|struct|class|protocol)\s+\w|\Z)",
        text,
        re.S,
    )
    if match is None:
        raise ValueError(f"{label} enum missing:{enum_name}")
    actual = tuple(re.findall(r'=\s*"([A-Z][A-Z0-9_]*)"', match.group(1)))
    if actual != expected:
        raise ValueError(f"{label} values differ:{enum_name}:{actual!r}")


def _swift_code(text: str) -> str:
    """Remove Swift comments before rejecting executable floating arithmetic."""
    return re.sub(r"//[^\r\n]*|/\*.*?\*/", "", text, flags=re.S)


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    sealed = not missing
    return {
        "disposition": "READY_FOR_SOURCE_REPROOF" if not missing else "PROVISIONAL_MISSING_SOURCE_LANES",
        "finalHashesSealed": sealed,
        "missingPaths": missing,
        "presentPaths": present,
        "requiredPathCount": len(IMPLEMENTATION_PATHS),
        "presentPathCount": len(present),
        "missingPathCount": len(missing),
    }


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    text = path.read_text(encoding="utf-8")
    return tuple(re.findall(r"(?m)^\s*func\s+(testV23P03C55(?:G|A|H|I|R)\d{2}\w*)\s*\(", text))


def _assert_exact_selectors(tests: str) -> tuple[str, ...]:
    selectors = tuple(re.findall(r"(?m)^\s*func\s+(testV23P03C55(?:G|A|H|I|R)\d{2}\w*)\s*\(", tests))
    if len(selectors) != 5:
        raise ValueError("C55 requires exactly five G/A/H/I/R selectors")
    if tuple(selector[13:16] for selector in selectors) != SELECTOR_SUFFIXES:
        raise ValueError("C55 selector order must be G01,A01,H01,I01,R01")
    if len(set(selectors)) != 5:
        raise ValueError("C55 selectors must be unique")
    return selectors


def _assert_no_forbidden_claims(source: str) -> None:
    # A denial may document the exclusion; executable-looking positive claims
    # are rejected.  This keeps the scanner useful without banning the
    # required exclusion vocabulary from comments/receipts.
    forbidden = re.compile(
        r"\b(?:vendor|procurement|purchas(?:e|ing)|purchase.?order|valuation|tax|invoice|"
        r"serialized.?lot|reservation|cloud|replenish(?:ment)?|URLSession|WebSocket)\b",
        re.I,
    )
    for match in forbidden.finditer(source):
        window = source[max(0, match.start() - 180): match.end() + 180]
        if re.search(r"\b(?:no|not|never|unsupported|excluded|forbidden|absent|false)\b", window, re.I) is None:
            raise ValueError("C55 excluded capability claim:" + match.group(0))


def _assert_backup_propagation(root: Path) -> None:
    """Audit the existing V4 envelope without taking ownership of its files."""
    by_path = {path: _text(root, path) for path in _BACKUP_PROPAGATION_PATHS}
    backup = "\n".join(by_path.values())
    _require_tokens(
        backup,
        (
            "C55PartsStockBackupEnrollmentV1", "recordsSchemaVersion = 40",
            "C55PartsStockBackupImportBoundaryV1", "restoresSevenFamiliesAtomically",
            "usesIncumbentLifecyclePort", "derivedBalanceAndSearchAreRebuilt",
            "C55PartsStockKernelBackupRestoreEnrollmentV1", "persistentSchemaVersion = 41",
            "canonicalSnapshotType = \"PartsStockBackupSnapshotV1\"", "partsStockSnapshot",
            "preparedRestoreSnapshot", "materializeRestoreStaging",
            "C55PartsStockPersistentSchemaBoundaryV1", "source=40,target=41,addedModels=7",
            "canonicalRowsOnly=true",
            "movements", "uses", "reversals", "returns", "abandonments",
        ),
        "C55 V4 schema40 backup propagation",
    )
    _require_patterns(
        backup,
        (
            r"C55PartsStockBackupEnrollmentV1\.validate",
            r"C55PartsStockBackupImportBoundaryV1\.validate",
            r"partsStockSnapshot.*PartsStockBackupSnapshotV1",
            r"recordsSchemaVersion.*C55PartsStockBackupEnrollmentV1\.recordsSchemaVersion",
            r"persistentSchemaVersion.*C55PartsStockBackupEnrollmentV1\.persistentSchemaVersion",
            r"snapshot\.uses\.allSatisfy",
            r"snapshot\.reversals\.allSatisfy",
            r"snapshot\.returns\.allSatisfy",
            r"snapshot\.abandonments\.allSatisfy",
        ),
        "C55 V4 schema40 backup bindings",
    )
    # Every existing boundary must admit the same exact records/persistent
    # pair.  Checking the combined text alone would allow one boundary to
    # silently omit C55 while another happened to mention the constants.
    _require_patterns(
        by_path["FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift"],
        (
            r"persistentSchemaVersion\s*==\s*41",
            r"recordsSchemaVersion\s*==\s*40",
            r"records\.recordsSchemaVersion\s*==\s*recordsSchemaVersion",
            r"records\.partsStockSnapshot",
            r"snapshot\.movements",
            r"snapshot\.uses",
            r"snapshot\.reversals",
            r"snapshot\.returns",
            r"snapshot\.abandonments",
            r"private\s+static\s+func\s+validateJournal",
            r"receipt\.commandBodySHA256\s*==",
            r"receipt\.expectedRevision\s*==\s*envelope\.expectedRevision",
            r"receipt\.postImages\s*==\s*images",
            r"receiptExpected\.count\s*==\s*concurrency\.count",
            r"receiptExpected\s*==\s*expectedByMutation",
            r"terminalStockMap\s*==\s*stockState",
            r"existing\.revision\.addingReportingOverflow\(1\)",
            r"parts\[value\.predecessorPart\.partID\]\s*==\s*value\.predecessorPart",
            r"case\s+let\s+\.applyPartsStock\(mutation\)",
            r"canonicalSnapshotEntries\s*==\s*canonicalReceiptEntries",
            r"C49BackupEnrollmentV1\.recordsSchemaVersion\.\.\.\s*C55PartsStockBackupEnrollmentV1\.recordsSchemaVersion",
        ),
        "C55 records40/persistent41 archive and journal admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift"],
        (
            r"records\.recordsSchemaVersion\s*==\s*recordsSchemaVersion",
            r"persistentSchemaVersion\s*==\s*41",
            r"C55PartsStockBackupEnrollmentV1\.validate",
            r"restoresSevenFamiliesAtomically",
            r"usesIncumbentLifecyclePort",
            r"derivedBalanceAndSearchAreRebuilt",
        ),
        "C55 records40/persistent41 import admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift"],
        (
            r"records\.recordsSchemaVersion\s*>=\s*C55PartsStockBackupEncodingBoundaryV1\.recordsSchemaVersion",
            r"C55PartsStockBackupEnrollmentV1\.validate\(records\)",
            r"fields\[\"partsStockSnapshot\"\]",
            r"validC55PartsStock",
        ),
        "C55 records40 encoder admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift"],
        (
            r"validateC55PartsStock",
            r"C55PartsStockBackupEnrollmentV1\.validate\(records",
            r"records\.recordsSchemaVersion\s*==\s*C55PartsStockBackupEnrollmentV1\.recordsSchemaVersion",
        ),
        "C55 records40 decoder admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift"],
        (
            r"C55PartsStockBackupPackageValidationV1",
            r"records\.recordsSchemaVersion\s*==\s*C55PartsStockBackupEnrollmentV1\.recordsSchemaVersion",
            r"manifest\.source\.persistentSchemaVersion\s*==\s*C55PartsStockBackupEnrollmentV1\.persistentSchemaVersion",
            r"C55PartsStockBackupEnrollmentV1\.validate",
        ),
        "C55 records40 package admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift"],
        (
            r"records\.recordsSchemaVersion\s*>=\s*C55PartsStockBackupEnrollmentV1\.recordsSchemaVersion",
            r"C55PartsStockBackupImportBoundaryV1\.validate",
            r"preparedRestoreSnapshot",
            r"materializeRestoreStaging",
            r"records\.partsStockSnapshot",
            r"stripPartsStock",
            r"removedPartsStockReceiptIndices",
            r"removedPartsStockWorkEntryIDs",
            r"removedPartsStockRevisionIdentities",
            r"requiredConcurrencyIdentities",
            r"projectedRevision",
            r"reissuedEnvelope",
            r"sidecarsForReissuedReceipt",
            r"terminalRevisionByIdentity",
            r"noteTerminalRevisions",
            r"deterministicWriterInstanceID",
            r"targetReceipts",
            r"validateC49WorkResources",
        ),
        "C55 records40 restore and clone/fork quarantine admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift"],
        (
            r"C55PartsStockKernelBackupRestoreEnrollmentV1",
            r"persistentSchemaVersion\s*=\s*41",
            r"durableFamilies\.count\s*==\s*7",
            r"canonicalSnapshotType\s*==\s*\"PartsStockBackupSnapshotV1\"",
        ),
        "C55 persistent41 kernel admission",
    )
    _require_patterns(
        by_path["FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"],
        (r"source=40,target=41,addedModels=7", r"canonicalRowsOnly=true"),
        "C55 persistent41 schema admission",
    )
    snapshot_source = "\n".join(
        _text(root, path) for path in IMPLEMENTATION_PATHS[:2]
    )
    _require_tokens(
        snapshot_source,
        (
            "PartsStockBackupSnapshotV1", "StockTransferReceiptV1",
            "StockUseOnWorkReceiptV1", "StockUseReversalReceiptV1",
            "StockReturnAgainstUseReceiptV1", "movements", "uses", "reversals",
            "returns", "abandonments",
        ),
        "C55 exact backup transfer/use/reversal/return topology",
    )
    _require_patterns(
        snapshot_source,
        (
            r"outbound\.kind\s*==\s*\.transferOut",
            r"inbound\.kind\s*==\s*\.transferIn",
            r"outbound\.relatedMovementID\s*==\s*inbound\.movementID",
            r"inbound\.relatedMovementID\s*==\s*outbound\.movementID",
            r"func\s+validate\(parts:\s*\[LocalPartDefinitionV1\],\s*locations:\s*\[StockStorageLocationV1\],\s*movements:\s*\[StockMovementEventV1\],\s*uses:\s*\[StockUseOnWorkReceiptV1\],\s*reversals:\s*\[StockUseReversalReceiptV1\],\s*returns:\s*\[StockReturnAgainstUseReceiptV1\],\s*abandonments:",
            r"private\s+static\s+func\s+replay\(movements:",
            r"event\.expectedLocationRevision\s*==\s*expectedRevision",
            r"event\.preBalance\s*==\s*expectedBalance",
            r"event\.kind\s*!=\s*\.openingCount",
            r"Set\(dispositions\.map\(\\\.locationID\)\)\s*==\s*unknownLocationIDs",
            r"disposition\.lastLocationRevision\s*==\s*tip\.locationRevision",
        ),
        "C55 exact backup topology and stream replay graph",
    )


def _assert_mutation_concurrency_projection(root: Path) -> None:
    """Prove C55's virtual balance stream is not the location catalog row."""
    by_path = {path: _text(root, path) for path in _MUTATION_PROJECTION_PATHS}
    mutation = by_path["FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift"]
    adapter = by_path["FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift"]
    journal = by_path["FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift"]
    receipt = by_path["FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift"]
    writer = by_path["FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift"]

    _require_tokens(
        mutation,
        (
            "StockBalanceStreamIdentityV1", "stockBalanceStream", "partID", "locationID",
            "expectedLocationRevision", "mutationPostImages", "stockMovementEvent",
            "stockUseReceipt", "stockUseReversalReceipt", "stockReturnReceipt",
            "workResourceEntry",
        ),
        "C55 virtual balance concurrency contract",
    )
    _require_patterns(
        mutation,
        (
            r"static\s+func\s+entity\(partID:\s*UUID,\s*locationID:\s*UUID\)",
            r"StockBalanceStreamIdentityV1\.entity\(partID:\s*value\.part\.partID,\s*locationID:\s*value\.locationID\)",
            r"StockBalanceStreamIdentityV1\.entity\(partID:\s*value\.outbound\.part\.partID,\s*locationID:\s*value\.outbound\.locationID\)",
            r"StockBalanceStreamIdentityV1\.entity\(partID:\s*value\.returnMovement\.part\.partID,\s*locationID:\s*value\.returnMovement\.locationID\)",
            r"func\s+expectedRevision\(for\s+identity",
            r"mutationPostImages",
            r"sorted\s*\{\s*\$0\.stableKey\s*<\s*\$1\.stableKey\s*\}",
            r"sorted\s*\{\s*try\s+\$0\.identity\.stableKey\s*<\s*\$1\.identity\.stableKey\s*\}",
        ),
        "C55 per-part/location stream identities and stable postimage order",
    )
    _require_patterns(
        adapter,
        (
            r"StockStorageLocationRowV1",
            r"StockBalanceStreamIdentityV1\.entity\(partID:\s*value\.part\.partID,\s*locationID:\s*value\.locationID\)",
            r"func\s+currentBalances\(partID:\s*UUID,\s*workspaceID:\s*WorkspaceID,\s*unit:\s*StockUnitV1\)",
            r"Set\(stream\.map\(\\\.locationRevision\)\)\.count\s*==\s*stream\.count",
            r"event\.expectedLocationRevision\s*==\s*revision",
            r"event\.preBalance\s*==\s*balance",
            r"value\.expectedLocationRevision\s*==\s*prior\.locationRevision",
            r"value\.preBalance\s*==\s*prior\.balance",
            r"event\.kind\s*==\s*\.openingCount\s*\|\|\s*event\.kind\s*==\s*\.physicalCount",
            r"func\s+replayBalanceStream",
            r"source\.sorted\s*\{\s*\(\$0\.locationRevision",
            r"predecessor\.revision\.addingReportingOverflow\(1\)",
            r"try\s+appendMovement\(value\.outbound\);\s*try\s+appendMovement\(value\.inbound\)",
            r"try\s+appendMovement\(value\.reversalMovement\)",
            r"try\s+appendMovement\(value\.returnMovement\)",
            r"case\s+\.stockBalanceStream:\s*exists\s*=\s*false",
        ),
        "C55 location catalog and stream separation",
    )
    _require_patterns(
        journal,
        (
            r"for\s+concurrency\s+in\s+try\s+mutation\.concurrencyIdentities\s+where\s+concurrency\.kind\s*==\s*\.stockBalanceStream",
            r"FetchDescriptor<EntityMutationRevisionRow>",
            r"row\.externalProjectionSHA256\s*=\s*nil",
            r"EntityMutationRevisionRow\(identity:\s*concurrency,\s*revision:\s*image\.revision\)",
            r"case\s+\.stockBalanceStream:\s*return\s+try\s+tombstone",
            r"case\s+\.stockMovementEvent:.*StockBalanceStreamIdentityV1",
        ),
        "C55 virtual stream revision CAS",
    )
    _require_patterns(
        receipt,
        (
            r"case\s+let\s+\.partsStock\(_,\s*kind,\s*value,\s*_,\s*_\):\s*switch\s+kind",
            r"case\s+\.stockMovementEvent:\s*guard\s+value\.kind\s*==\s*\.stockBalanceStream",
            r"case\s+\.localPartDefinition,\s*\.stockStorageLocation,\s*\.stockUseReceipt,\s*\.stockUseReversalReceipt,\s*\.stockReturnReceipt,\s*\.stockAbandonment:\s*guard\s+value\.kind\s*==\s*kind",
            r"partsStock\(id:UUID,kind:WorkspaceEntityKindV1",
            r"hasPartsStockPostImage",
            r"expectedRevision\.entityRevisions\.count\s*==\s*postImageConcurrencySet\.count",
            r"expectedIdentitySet\s*==\s*postImageConcurrencySet",
        ),
        "C55 receipt stream postimage and exact expected identity distinction",
    )
    _require_tokens(
        writer,
        ("applyPartsStock", "mutationPostImages", "concurrencyIdentities", "expectedRevision", "staleEntityRevision"),
        "C55 canonical writer stream admission",
    )


def _assert_integer_number_boundary(root: Path) -> None:
    """Reject NSNumber decimals/exponents instead of truncating them."""
    encoder = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift")
    _require_patterns(
        encoder,
        (
            r"if\s+let\s+value\s*=\s*value\s+as\?\s+NSNumber",
            r"CFGetTypeID\(value\)\s*!=\s*CFBooleanGetTypeID\(\)",
            r"let\s+representation\s*=\s*value\.stringValue",
            r"!representation\.contains\(\"\.\"\)",
            r"!representation\.contains\(\"e\"\)",
            r"!representation\.contains\(\"E\"\)",
            r"let\s+integer\s*=\s*Int\(representation\)",
            r"return\s+\.integer\(integer\)",
        ),
        "C55 exact integer NSNumber boundary",
    )
    if re.search(r"\b(?:Float|Double)\b", _swift_code(encoder)):
        raise ValueError("C55 backup NSNumber boundary uses Float/Double")


def _assert_retirement_completeness(contracts: str, coordinator: str) -> None:
    """Require throwing validation, never lossy retirement projection scans."""
    start = contracts.index("struct StockPartRetirementReceiptV1")
    end = contracts.index("enum PartsStockMutationV1", start)
    retirement = contracts[start:end]
    _require_patterns(
        retirement,
        (
            r"try\s+verifiedBalances\.forEach\s*\{\s*try\s+\$0\.validate\(\)",
            r"!verifiedBalances\.isEmpty",
            r"verifiedBalances\.allSatisfy",
            r"quantity\.mantissa\s*==\s*0",
        ),
        "C55 throwing retirement completeness",
    )
    if re.search(r"compactMap|try\?", retirement, re.I):
        raise ValueError("C55 retirement completeness may not compactMap or try?")
    marker = "func retirePart"
    start = coordinator.index(marker)
    next_method = coordinator.find("\n    @discardableResult func ", start + len(marker))
    region = coordinator[start:] if next_method < 0 else coordinator[start:next_method]
    if re.search(r"compactMap|try\?", region, re.I):
        raise ValueError("C55 coordinator retirement completeness may not compactMap or try?")


def _assert_catalog_history_and_material_binding(
    contracts: str, models: str, adapter: str
) -> None:
    """Bind decoded predecessors to catalog revision/digest and material unit."""
    _require_patterns(
        contracts,
        (
            r"frozenReference\(\)",
            r"historical:\s*\[String:\s*LocalPartReferenceSnapshotV1\]",
            r"guard\s+let\s+current\s*=\s*catalog\[movement\.part\.partID\]",
            r"movement\.part\.partRevision\s*<=\s*current\.revision",
            r"movement\.part\.partRevision\s*==\s*current\.revision",
            r"movement\.part\s*==\s*\(try\s+current\.frozenReference\(\)\)",
            r"\$0\.unit\s*==\s*movement\.unit\.rawValue",
            r"predecessorFrontier\?\.workResourceSuccessorSHA256\s*==\s*workResourcePredecessor\.entrySHA256",
        ),
        "C55 unit history and material binding",
    )
    _require_patterns(
        models,
        (
            r"PartsStockPersistenceCodecV1\.decode\(LocalPartDefinitionV1\.self",
            r"guard\s+value\.workspaceID\.rawValue\s*==\s*workspaceUUID",
            r"value\.partID\s*==\s*partID",
            r"value\.revision\s*==\s*revision",
            r"value\.archived\s*==\s*archived",
        ),
        "C55 decoded catalog predecessor binding",
    )
    _require_patterns(
        adapter,
        (
            r"let\s+predecessor\s*=\s*try\s+row\.value\(\)",
            r"predecessor\s*==\s*declared",
            r"let\s+actual\s*=\s*try\s+currentBalances",
            r"actual\s*==\s*value\.verifiedBalances",
            r"value\.part\s*==\s*\(try\s+part\.frozenReference\(\)\)",
            r"predecessor\.canonicalUnit\s*!=\s*value\.canonicalUnit",
        ),
        "C55 persisted predecessor catalog binding",
    )


def _assert_replay_and_return_frontier(contracts: str, lifecycle: str, adapter: str) -> None:
    """Require exact digest replay and explicit first/subsequent Return frontiers."""
    _require_patterns(
        contracts,
        (
            r"rebuilt\.eventSHA256\s*==\s*eventSHA256",
            r"rebuilt\.receiptSHA256\s*==\s*receiptSHA256",
            r"expected\s*==\s*receiptSHA256",
            r"predecessorFrontier\?\.resultingReturnedMantissa\s*\?\?\s*0",
            r"predecessorFrontier\s*==\s*nil\s*\?\s*workResourcePredecessor\s*==\s*sourceUse\.workResourceSuccessor",
            r"predecessorFrontier\?\.sourceUseReceiptID\s*==\s*sourceUse\.receiptID",
            r"predecessorFrontier\?\.workResourceSuccessorRevision\s*==\s*workResourcePredecessor\.revision",
            r"frontierSnapshot\(\)",
        ),
        "C55 exact replay and Return frontier contract",
    )
    _require_patterns(
        lifecycle,
        (
            r"for\s+event\s+in\s+movements",
            r"try\s+event\.validate\(\)",
            r"try\s+Self\.validateGraph\(snapshot\)",
            r"try\s+preparedRestoreSnapshot\(",
        ),
        "C55 replay validation",
    )
    _require_patterns(
        adapter,
        (
            r"var\s+frontier:\s*StockReturnFrontierSnapshotV1\?",
            r"let\s+candidates\s*=\s*remaining\.filter\s*\{\s*\$0\.predecessorFrontier\s*==\s*frontier\s*\}",
            r"value\.predecessorFrontier\s*==\s*frontier",
            r"frontier\?\.workResourceSuccessorID\s*\?\?\s*sourceUse\.workResourceSuccessor\.entryID",
        ),
        "C55 first/subsequent Return frontier resolution",
    )


def _assert_single_clone_fork_preparation(lifecycle: str, restore_service: str) -> None:
    """Ensure the lifecycle and restore projections remain deliberately equivalent."""
    _require_patterns(
        lifecycle,
        (
            r"func\s+preparedRestoreSnapshot\(",
            r"case\s+\.cloneDefinitions,\s*\.forkRequiresRecount",
            r"let\s+materialized\s*=\s*try\s+preparedRestoreSnapshot\(",
            r"movements:\s*\[\]",
            r"uses:\s*\[\]",
            r"reversals:\s*\[\]",
            r"returns:\s*\[\]",
            r"abandonments:\s*\[\]",
        ),
        "C55 lifecycle clone/fork preparation",
    )
    _require_patterns(
        restore_service,
        (
            r"func\s+preparedCloneForkPartsStockSnapshot\(",
            r"try\s+source\.validate\(\)",
            r"source\.workspaceID\s*!=\s*targetWorkspaceID",
            r"source\.parts\.filter\s*\{\s*!\$0\.archived\s*\}",
            r"source\.locations\.filter\s*\{\s*!\$0\.archived\s*\}",
            r"workspaceID:\s*targetWorkspaceID",
            r"archived:\s*false",
            r"revision:\s*1",
            r"movements:\s*\[\]",
            r"uses:\s*\[\]",
            r"reversals:\s*\[\]",
            r"returns:\s*\[\]",
            r"abandonments:\s*\[\]",
            r"try\s+prepared\.validate\(\)",
            r"C55PartsStockBackupImportBoundaryV1\.validate",
            r"normalized\s*=\s*try\s+rebindingWorkResources",
            r"preparedCloneForkPartsStockSnapshot\(",
        ),
        "C55 restore-service clone/fork preparation",
    )
    parity = (
        r"(?:snapshot|source)\.parts\.filter\s*\{\s*!\$0\.archived\s*\}",
        r"(?:snapshot|source)\.locations\.filter\s*\{\s*!\$0\.archived\s*\}",
        r"displayName:\s*(?:source|value)\.displayName",
        r"canonicalUnit:\s*(?:source|value)\.canonicalUnit",
        r"productIdentities:\s*(?:source|value)\.productIdentities",
        r"preferredMinimum:\s*(?:source|value)\.preferredMinimum",
        r"workspaceID:\s*targetWorkspaceID",
        r"archived:\s*false",
        r"revision:\s*1",
        r"kind:\s*(?:source|value)\.kind",
        r"label:\s*(?:source|value)\.label",
        r"binLabel:\s*(?:source|value)\.binLabel",
        r"movements:\s*\[\]",
        r"uses:\s*\[\]",
        r"reversals:\s*\[\]",
        r"returns:\s*\[\]",
        r"abandonments:\s*\[\]",
    )
    _require_patterns(lifecycle, parity, "C55 lifecycle/restore clone/fork parity")
    _require_patterns(restore_service, parity, "C55 restore/lifecycle clone/fork parity")


def _assert_newly_landed_invariants(root: Path) -> None:
    """Audit the source-grounded C55 closure and terminal-map corrections."""
    models = _text(root, "FieldEvidenceApp/Domain/Models/PartsStockPersistenceModelsV1.swift")
    limits = _text(root, "FieldEvidenceApp/Domain/PartsStock/PartsStockContractsV1.swift")
    mutation = _text(root, "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift")
    mutation_receipt = _text(root, "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift")
    journal = _text(root, "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift")
    writer = _text(root, "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift")
    adapter = _text(root, "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift")
    v4 = _text(root, "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift")
    restore_identity = _text(root, "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift")
    restore = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift")
    package_validator = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift")
    lifecycle = _text(root, "FieldEvidenceApp/Infrastructure/PartsStock/PartsStockLifecycleAdapterV1.swift")
    tests = _text(root, IMPLEMENTATION_PATHS[4])

    # A movement owns a durable physical event row while its postimage carries
    # the independent virtual per-part/location stream identity. Use,
    # reversal, and Return add exactly one successor work-resource image.
    _require_patterns(
        mutation,
        (
            r"extension\s+PartsStockMutationV1",
            r"var\s+affectedIdentities:\s*\[WorkspaceEntityIdentityV1\]",
            r"var\s+concurrencyIdentities:\s*\[WorkspaceEntityIdentityV1\]",
            r"case\s+let\s+\.appendMovement\(value\):\s*return\s+\[try\s+StockBalanceStreamIdentityV1\.entity",
            r"case\s+let\s+\.transfer\(value\):\s*return\s+try\s+\[",
            r"case\s+let\s+\.use\(value\):\s*return\s+try\s+\[",
            r"case\s+let\s+\.reverseUse\(value\):\s*return\s+try\s+\[",
            r"case\s+let\s+\.returnAgainstUse\(value\):\s*return\s+try\s+\[",
            r"case\s+let\s+\.appendMovement\(v\):\s*return\s+\[image\(v\.movementID,\s*\.stockMovementEvent,\s*try\s+StockBalanceStreamIdentityV1\.entity",
            r"image\(v\.outbound\.movementID,\s*\.stockMovementEvent,\s*StockBalanceStreamIdentityV1\.entity",
            r"image\(v\.inbound\.movementID,\s*\.stockMovementEvent,\s*StockBalanceStreamIdentityV1\.entity",
            r"\.workResourceEntry\(id:\s*v\.workResourceSuccessor\.entryID,\s*concurrencyIdentity:",
            r"var\s+mutationPostImages:\s*\[MutationPostImageV1\]",
            r"sorted\s*\{\s*try\s+\$0\.identity\.stableKey\s*<\s*\$1\.identity\.stableKey\s*\}",
        ),
        "C55 dual physical and stream postimages",
    )
    _require_patterns(
        journal,
        (
            r"nonisolated\s+private\s+static\s+func\s+terminalStateIdentities\(",
            r"guard\s+case\s+let\s+\.partsStock\(id,\s*kind,\s*concurrency,\s*_,\s*_\)\s*=\s*image",
            r"let\s+physical\s*=\s*try\s+WorkspaceEntityIdentityV1\(kind:\s*kind,\s*id:\s*id\)",
            r"return\s+physical\s*==\s*concurrency\s*\?\s*\[physical\]\s*:\s*\[physical,\s*concurrency\]",
            r"for\s+entity\s+in\s+try\s+Self\.terminalStateIdentities\(for:\s*image\)",
            r"EntityMutationRevisionRow\(identity:\s*concurrency,\s*revision:\s*image\.revision\)",
            r"row\.externalProjectionSHA256\s*=\s*nil",
            r"descriptor\.fetchLimit\s*=\s*Self\.maximumC55TerminalRevisionRowCount\s*\+\s*1",
            r"guard\s+rows\.count\s*<=\s*Self\.maximumC55TerminalRevisionRowCount",
        ),
        "C55 terminal physical/stream expansion",
    )
    _require_patterns(
        v4,
        (
            r"let\s+concurrencyIdentity\s*=\s*try\s+image\.concurrencyIdentity",
            r"if\s+isStockKind\(identity\.kind\)\s*\{\s*nextStockState\[identity\]\s*=\s*image\.revision\s*\}",
            r"if\s+isStockKind\(concurrencyIdentity\.kind\)\s*\{\s*nextStockState\[concurrencyIdentity\]\s*=\s*image\.revision\s*\}",
            r"let\s+terminalStockMap\s*=\s*Dictionary\(",
            r"terminalStockMap\s*==\s*stockState",
        ),
        "C55 backup physical/stream terminal equality",
    )
    _require_patterns(
        adapter,
        (
            r"func\s+replayBalanceStream\(",
            r"modelContext\.insert\(try\s+StockMovementEventRowV1\(value\)\)",
            r"try\s+appendMovement\(value\.outbound\);\s*try\s+appendMovement\(value\.inbound\)",
            r"try\s+appendMovement\(value\.movement\)",
            r"try\s+appendMovement\(value\.reversalMovement\)",
            r"try\s+appendMovement\(value\.returnMovement\)",
            r"modelContext\.insert\(try\s+StockUseReceiptRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockUseReversalReceiptRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockReturnReceiptRowV1\(value\)\)",
        ),
        "C55 native physical movement persistence",
    )
    _require_patterns(
        writer,
        (
            r"case\s+\.applyPartsStock\(let\s+value\)",
            r"let\s+targets\s*=\s*try\s+value\.concurrencyIdentities",
            r"Set\(targets\)\.count\s*==\s*targets\.count",
            r"expected\[\$0\]\s*==\s*\(try\s+value\.expectedRevision\(for:\s*\$0\)\)",
        ),
        "C55 canonical writer stream CAS admission",
    )

    # The seven SwiftData rows and the snapshot row limit are one closure:
    # validate the bounded snapshot, materialize every row family into an
    # empty target, then perform one save and return the source/effect digests.
    _require_patterns(
        limits,
        (r"static\s+let\s+maximumSnapshotRows\s*=\s*100_000",),
        "C55 snapshot row cap",
    )
    _require_patterns(
        models,
        (
            r"let\s+count\s*=\s*parts\.count\s*\+\s*locations\.count\s*\+\s*movements\.count\s*\+\s*uses\.count\s*\+\s*reversals\.count\s*\+\s*returns\.count\s*\+\s*abandonments\.count",
            r"guard\s+count\s*<=\s*PartsStockLimitsV1\.maximumSnapshotRows",
            r"static\s+let\s+persistentTypes:\s*\[Any\.Type\]\s*=\s*\[LocalPartDefinitionRowV1\.self,\s*StockStorageLocationRowV1\.self,\s*StockMovementEventRowV1\.self,\s*StockUseReceiptRowV1\.self,\s*StockUseReversalReceiptRowV1\.self,\s*StockReturnReceiptRowV1\.self,\s*AbandonUnverifiedStockRowV1\.self\]",
        ),
        "C55 seven-row persistence closure",
    )
    _require_patterns(
        lifecycle,
        (
            r"func\s+materializeRestoreStaging\(",
            r"try\s+requireEmptyTarget\(workspaceID:\s*targetWorkspaceID\)",
            r"let\s+materialized\s*=\s*try\s+preparedRestoreSnapshot\(",
            r"modelContext\.insert\(try\s+LocalPartDefinitionRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockStorageLocationRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockMovementEventRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockUseReceiptRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockUseReversalReceiptRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+StockReturnReceiptRowV1\(value\)\)",
            r"modelContext\.insert\(try\s+AbandonUnverifiedStockRowV1\(value\)\)",
            r"try\s+modelContext\.save\(\)",
            r"snapshotSHA256:\s*snapshot\.snapshotSHA256",
            r"effectSHA256:\s*materialized\.snapshotSHA256",
        ),
        "C55 native restore staging closure",
    )
    _require_order(
        lifecycle,
        r"try\s+requireEmptyTarget\(workspaceID:\s*targetWorkspaceID\)",
        r"let\s+materialized\s*=\s*try\s+preparedRestoreSnapshot\(",
        "C55 empty-target validation before materialization",
    )
    _require_order(
        lifecycle,
        r"let\s+materialized\s*=\s*try\s+preparedRestoreSnapshot\(",
        r"modelContext\.insert\(try\s+LocalPartDefinitionRowV1\(value\)\)",
        "C55 materialize before insert",
    )
    _require_order(
        lifecycle,
        r"modelContext\.insert\(try\s+AbandonUnverifiedStockRowV1\(value\)\)",
        r"try\s+modelContext\.save\(\)",
        "C55 all seven rows before atomic save",
    )
    _require_order(
        restore,
        r"C55PartsStockBackupImportBoundaryV1\.validate\(",
        r"normalized\s*=\s*try\s+rebindingWorkResources",
        "C55 import validation before clone/fork rebinding",
    )
    _require_patterns(
        restore,
        (
            r"\.materializeRestoreStaging\(",
            r"targetWorkspaceID:\s*targetWorkspaceID",
            r"operationID:\s*partsStockOperationID",
            r"disposition:\s*disposition",
            r"completedAt:\s*partsStockCompletedAt",
        ),
        "C55 projected staging materialization",
    )

    # Fresh C55 installs and cross-replica replacements preserve the complete
    # terminal history while resetting the destination sequence. Clone/fork
    # remains the definitions-only `.destination` projection; a same-replica
    # replacement keeps the incumbent `.preserve` identity disposition.
    _require_patterns(
        mutation_receipt,
        (
            r"enum\s+MutationHistoryRestoreIdentityV1",
            r"case\s+preserve",
            r"case\s+destination\(WorkspaceReplicaIdentityV1,\s*generationID:\s*UUID\)",
            r"case\s+destinationPreservingPartsStock\(WorkspaceReplicaIdentityV1,\s*generationID:\s*UUID\)",
        ),
        "C55 restore identity dispositions",
    )
    _require_patterns(
        journal,
        (
            r"case\s+let\s+\.destinationPreservingPartsStock\(destination,\s*targetGenerationID\):",
            r"case\s+\.destinationPreservingPartsStock:",
            r"case\s+\.destination:",
            r"guard\s+Self\.isPartsStockCatalogKind\(value\.identity\.kind\)\s+else\s*\{\s*continue\s*\}",
            r"case\s+\.preserve:",
            r"externalProjection\s*=\s*Self\.isPartsStockCatalogKind\(value\.identity\.kind\)",
        ),
        "C55 fresh destination and clone/fork journal projection",
    )
    _require_patterns(
        journal,
        (
            r"case\s+let\s+\.destinationPreservingPartsStock\(destination,\s*targetGenerationID\):[\s\S]*?state\.lastLocalSequence\s*=\s*0",
            r"case\s+\.destinationPreservingPartsStock:[\s\S]*?externalProjection\s*=\s*Self\.isPartsStockCatalogKind\(value\.identity\.kind\)\s*\n?\s*\?\s*value\.externalProjectionSHA256\s*\n?\s*:\s*nil",
            r"case\s+\.destination:[\s\S]*?guard\s+Self\.isPartsStockCatalogKind\(value\.identity\.kind\)\s+else\s*\{\s*continue\s*\}",
        ),
        "C55 fresh destination terminal preservation and clone/fork quarantine",
    )
    _require_patterns(
        restore_identity,
        (
            r"static\s+func\s+disposition\(for\s+mode:\s*BackupRestoreMode\)\s*->\s*PartsStockRestoreDispositionV1",
            r"case\s+\.emptyInstall,\s*\.replaceExisting:\s*return\s+\.replace",
            r"case\s+\.clone:\s*return\s+\.cloneDefinitions",
            r"case\s+\.fork:\s*return\s+\.forkRequiresRecount",
        ),
        "C55 parts-stock lifecycle restore modes",
    )
    _require_patterns(
        restore,
        (
            r"identityDecision\.mode\s*==\s*\.emptyInstall[\s\S]*?identityDecision\.mode\s*==\s*\.replaceExisting[\s\S]*?disposition\s*=\s*\.destinationPreservingPartsStock\(",
            r"identityDecision\?\.mode\s*==\s*\.replaceExisting[\s\S]*?identityDecision\?\.targetPointer\.replicaID[\s\S]*?disposition\s*=\s*\.preserve",
            r"disposition\s*=\s*\.destination\(\s*identity,\s*generationID:\s*generationID\s*\)",
        ),
        "C55 fresh/same-replica/clone-fork identity selection",
    )

    # Only catalog rows can carry an external projected baseline. The virtual
    # stream and immutable stock facts must remain receipt-backed and nil.
    _require_patterns(
        v4,
        (
            r"var\s+externalPartBaselines:\s*\[UUID:\s*LocalPartDefinitionV1\]\s*=\s*\[:\]",
            r"var\s+externalLocationBaselines:\s*\[UUID:\s*StockStorageLocationV1\]\s*=\s*\[:\]",
            r"case\s+\.localPartDefinition:\s*guard\s+let\s+part\s*=\s*partByID",
            r"case\s+\.stockStorageLocation:\s*guard\s+let\s+location\s*=\s*locationByID",
            r"case\s+\.stockBalanceStream,\s*\.stockMovementEvent,\s*\.stockUseReceipt,",
            r"\.stockUseReversalReceipt,\s*\.stockReturnReceipt,\s*\.stockAbandonment:\s*throw",
            r"let\s+projected\s*=\s*!externalPartBaselines\.isEmpty\s*\|\|\s*!externalLocationBaselines\.isEmpty",
        ),
        "C55 part/location-only external baselines",
    )
    _require_patterns(
        journal,
        (
            r"nonisolated\s+private\s+static\s+func\s+isPartsStockCatalogKind\(",
            r"kind\s*==\s*\.localPartDefinition\s*\|\|\s*kind\s*==\s*\.stockStorageLocation",
            r"return\s+!Self\.isPartsStockKind\(value\.identity\.kind\)\s*\n?\s*\|\|\s*Self\.isPartsStockCatalogKind\(value\.identity\.kind\)\s*\n?\s*\|\|\s*value\.externalProjectionSHA256\s*==\s*nil",
            r"if\s+entity\.kind\s*==\s*\.stockBalanceStream",
            r"validProjection\s*=\s*row\.externalProjectionSHA256\s*==\s*nil",
            r"current\s*==\s*\(try\s+tombstone\(entity,\s*revision\)\)",
        ),
        "C55 nil stream and catalog baseline projection",
    )

    # The test lane covers both modes as active revision-one definition
    # projections, keeps unrelated C49 history, and strips all C55 facts.
    _require_patterns(
        tests,
        (
            r"for\s+\(index,\s*mode\)\s+in\s+\[BackupRestoreMode\.clone,\s*\.fork\]\.enumerated\(\)",
            r"c55RebindingWorkResourcesForTesting\(",
            r"projectedSnapshot\.parts\.allSatisfy\s*\{\s*!\$0\.archived\s*&&\s*\$0\.revision\s*==\s*1\s*\}",
            r"projectedSnapshot\.locations\.allSatisfy\s*\{\s*!\$0\.archived\s*&&\s*\$0\.revision\s*==\s*1\s*\}",
            r"projectedSnapshot\.movements\.isEmpty",
            r"projectedSnapshot\.uses\.isEmpty",
            r"projectedSnapshot\.reversals\.isEmpty",
            r"projectedSnapshot\.returns\.isEmpty",
            r"projectedSnapshot\.abandonments\.isEmpty",
            r"projectedEntry\.entryID,\s*unrelatedEntry\.entryID",
            r"XCTAssertEqual\(projected\.workResources\.count,\s*1\)",
        ),
        "C55 active revision-one clone/fork quarantine",
    )

    # Separate the 100,000 durable-row snapshot bound from the 200,000
    # terminal identity bound. A C55 row contributes at most its physical
    # identity plus one stream/concurrency or work-resource successor.
    _require_patterns(
        journal,
        (
            r"maximumReceiptValidationCount\s*=\s*100_000",
            r"maximumMutableContentValidationCount\s*=\s*100_000",
            r"maximumC55TerminalRevisionRowCount\s*=\s*200_000",
            r"maximumImportedEntityRevisionValidationCount\s*=\s*maximumC55TerminalRevisionRowCount",
            r"var\s+totalPostImageCount\s*=\s*0",
            r"totalPostImageCount\s*\+=\s*receipt\.postImages\.count",
            r"maximumPostImageRevisionByEntity\[entity\]\s*=\s*max\(",
        ),
        "C55 terminal identity bounds",
    )
    _require_patterns(
        mutation,
        (
            r"\.workResourceEntry\(id:\s*v\.workResourceSuccessor\.entryID",
            r"supersedesEntryID\s*\?\?\s*v\.workResourceSuccessor\.entryID",
            r"case\s+let\s+\.use\(v\):\s*return\s+try\s+\[",
            r"case\s+let\s+\.reverseUse\(v\):\s*return\s+try\s+\[",
            r"case\s+let\s+\.returnAgainstUse\(v\):\s*return\s+try\s+\[",
        ),
        "C55 work-resource successor terminal expansion",
    )
    _require_patterns(
        package_validator,
        (
            r"MutationJournalStoreV1\.validateImportedSnapshot\(history\)",
            r"history\.receipts\.count\s*\n?\s*<=\s*MutationJournalStoreV1\.maximumReceiptValidationCount",
        ),
        "C55 backup package admission bounds",
    )
    if re.search(
        r"history\.entityRevisions\.count\s*\n?\s*<=\s*MutationReceiptV1\.maximumPostImageCount",
        package_validator,
        re.I,
    ):
        raise ValueError(
            "C55 source mismatch: BackupPackageValidator caps history.entityRevisions "
            "at per-receipt maximumPostImageCount instead of the 200000 terminal identity cap"
        )


def _assert_source_contracts(root: Path) -> tuple[str, ...]:
    missing = source_status(root)["missingPaths"]
    if missing:
        return tuple(missing)

    contracts, models, coordinator, lifecycle, tests = (
        _text(root, path) for path in IMPLEMENTATION_PATHS[:5]
    )
    fixture = _json(root, IMPLEMENTATION_PATHS[5])
    all_product = "\n".join((contracts, models, coordinator, lifecycle))

    _require_tokens(
        contracts,
        (
            "LocalPartDefinitionV1", "StockStorageLocationV1", "StockMovementEventV1",
            "StockUseOnWorkReceiptV1", "StockReturnAgainstUseReceiptV1", "StockUseReversalReceiptV1",
            "StockAbandonmentReceiptV1", "StockPartRetirementReceiptV1",
            "StockQuantityV1", "StockUnitV1", "canonicalUnit", "scale",
            "shop", "vehicle", "kit", "other", "UNKNOWN", "KNOWN", "OPENING", "COUNT",
            "ADJUSTMENT", "USE", "RETURN", "TRANSFER", "AbandonUnverifiedStockDispositionV1",
        ),
        "C55 domain contracts",
    )
    if re.search(r"\b(?:Float|Double)\b", _swift_code(all_product)):
        raise ValueError("C55 quantity/stock arithmetic uses Float/Double")
    _require_patterns(
        contracts,
        (
            r"maximumStorageLabelBytes\s*=\s*80",
            r"StockQuantityV1.*(?:mantissa|scale)",
            r"let\s+mantissa:\s*Int64",
            r"let\s+scale:\s*Int",
            r"StockUnitV1:\s*String.*CaseIterable",
            r"case\s+unknown",
            r"case\s+known",
            r"if\s+kind\s*==\s*\.openingCount\s*\|\|\s*kind\s*==\s*\.physicalCount",
            r"StockReturnAgainstUseReceiptV1",
            r"expectedReturnedMantissa.*resultingReturnedMantissa",
            r"expectedReturnedMantissa\.addingReportingOverflow",
            r"sourceUseReceiptSHA256",
            r"predecessorFrontier",
            r"sourceUseReceiptID\s*==\s*sourceUse\.receiptID",
            r"sourceUseReceiptSHA256\s*==\s*sourceUse\.receiptSHA256",
            r"sourceUse:\s*StockUseOnWorkReceiptV1",
            r"workResourcePredecessor:\s*WorkResourceEntryV1",
            r"predecessorFrontier\s*==\s*nil\s*\?\s*workResourcePredecessor\s*==\s*sourceUse\.workResourceSuccessor",
            r"workResourceSuccessor\.mutationID\s*==\s*mutationID",
            r"AbandonUnverifiedStockDispositionV1",
            r"quantityRemainsUnknown",
            r"StockAbandonmentReceiptV1",
            r"dispositions",
            r"archivedPartSuccessor",
            r"StockPartRetirementReceiptV1",
            r"verifiedBalances",
            r"!verifiedBalances\.isEmpty",
            r"verifiedBalances\.allSatisfy",
            r"quantity\.mantissa\s*==\s*0",
        ),
        "C55 domain invariants",
    )
    _require_exact_enum_values(contracts, "StockUnitV1", CANONICAL_UNITS, "C55 canonical units")
    _require_exact_enum_values(contracts, "StockStorageKindV1", STORAGE_LABEL_KINDS, "C55 storage labels")
    _require_exact_enum_values(contracts, "StockMovementKindV1", MOVEMENT_KINDS, "C55 movement kinds")
    _require_tokens(
        models,
        (
            "@Model", "canonical", "LocalPartDefinitionV1", "StockStorageLocationV1",
            "StockMovementEventV1", "StockUseOnWorkReceiptV1", "StockReturnAgainstUseReceiptV1",
            "StockUseReversalReceiptV1", "AbandonUnverifiedStockDispositionV1", "PartsStockBackupSnapshotV1",
            "canonicalData", "persistentTypes", "snapshotSHA256", "reversals", "abandonments",
        ),
        "C55 persistence models",
    )
    if len(re.findall(r"@Model\b", models)) != 7:
        raise ValueError("C55 persistence model row count must be exactly seven")
    _require_patterns(
        models,
        (
            r"StockUseReversalReceiptRowV1",
            r"sourceUse\.receiptID\s*==\s*sourceUseReceiptID",
        ),
        "C55 reversal persistence identity",
    )
    _require_tokens(
        coordinator,
        (
            "PartsStockCanonicalWriterPortV1", "commitPartsStock", "makeMutationID",
            "PartsStockMutationV1", "MutationIDV1", "expectedLocationRevision",
            "StockReturnAgainstUseReceiptV1", "StockUseReversalReceiptV1",
            "StockAbandonmentReceiptV1", "StockPartRetirementReceiptV1", "retirePart", "revisePart",
            "sourceUse", "workResourcePredecessor", "workResourceSuccessor",
            "commit", "mutationID", "writer", "case .known", "adjustmentIncrease",
            "adjustmentDecrease", "useOnWork", "transferOut", "transferIn",
            "PartsStockExactMathV1", "completeBalances", "abandonUnknown", "currentBalance",
        ),
        "C55 coordinator",
    )
    _require_patterns(
        coordinator,
        (
            r"expectedLocationRevision",
            r"workResourceSuccessor",
            r"workResourcePredecessor",
            r"commitPartsStock",
            r"CAS-protected|canonical transaction",
            r"sourceUse",
            r"commit\(\.(?:use|reverseUse|returnAgainstUse)",
            r"func\s+revisePart\([^)]*hasMovementHistory:\s*Bool\)",
            r"archived:\s*false",
        ),
        "C55 atomic writer boundary",
    )
    _require_tokens(
        lifecycle,
        (
            "PartsStockLifecycleAdapterV1", "PartsStockLifecyclePortV1",
            "restorePartsStock", "deletePartsStock", "erasePartsStock",
            "rebuildPartsStockSearch", "snapshotForBackup", "restore",
            "replace", "cloneDefinitions", "forkRequiresRecount", "journal",
            "replay", "projection", "search", "rebuildSearch", "report", "delete", "erase",
            "PartsStockBackupSnapshotV1", "PartsStockRestoreDispositionV1",
            "preparedRestoreSnapshot", "materializeRestoreStaging",
            "featureDisablePreservesReadExportRecovery", "hostedOrParallelWriter",
        ),
        "C55 lifecycle closure",
    )
    selectors = _assert_exact_selectors(tests)
    _require_tokens(
        tests,
        (
            "canonicalUnit", "UNKNOWN", "KNOWN", "ABANDON_UNKNOWN_AUDIT", "CAS",
            "StockUseReversalReceiptV1", "StockReturnAgainstUseReceiptV1", "StockAbandonmentReceiptV1",
            "retirePart", "revisePart", "sourceUse",
            "workResourcePredecessor", "dispositions", "archivedPartSuccessor",
            "returnReceipt", "transferIsAtomic", "backup", "restore", "search", "report", "erase",
            "BACKUP_RESTORE_MIXED_HISTORY_CLONE_FORK",
        ),
        "C55 evidence tests",
    )
    if fixture.get("schema") != "V22P03C55PartsStockCorpusV1" or fixture.get("cardID") != CARD:
        raise ValueError("C55 fixture identity differs")
    fixture_ids = tuple(fixture.get("evidenceIDs", ()))
    if fixture_ids != EVIDENCE_IDS:
        raise ValueError("C55 fixture evidence selectors differ")
    if tuple(fixture.get("units", ())) != CANONICAL_UNITS:
        raise ValueError("C55 fixture canonical units differ")
    if tuple(fixture.get("storageKinds", ())) != STORAGE_LABEL_KINDS:
        raise ValueError("C55 fixture storage labels differ")
    if tuple(fixture.get("movementKinds", ())) != MOVEMENT_KINDS:
        raise ValueError("C55 fixture movement kinds differ")
    claims = fixture.get("claims", {})
    required_claims = (
        "unknownNeverZero", "openingOrCountEstablishesKnown", "adjustmentRequiresKnown",
        "useRequiresSufficientKnown", "transferRequiresKnownBothSides", "transferIsAtomic",
        "returnIsProvenanceBound", "returnUsesCASFrontier", "ordinaryRetirementRequiresKnownZero",
        "revisionCannotArchive", "appendOnly", "abandonmentPreservesUnknown", "retryIsIdempotent",
        "reportExcludesBalancesAndStorage", "cloneCopiesDefinitionsOnly", "forkRequiresRecount",
        "featureDisablePreservesReadExportRecovery",
    )
    if any(claims.get(key) is not True for key in required_claims):
        raise ValueError("C55 fixture required claim is not true")
    _require_tokens(
        json.dumps(fixture, sort_keys=True),
        (
            '"units"', "SHOP", "VEHICLE", "KIT", "OTHER", "UNKNOWN", "KNOWN",
            "OPENING_COUNT", "PHYSICAL_COUNT", "ADJUSTMENT_INCREASE", "USE_ON_WORK",
            "RETURN_AGAINST_USE", "TRANSFER_OUT", "TRANSFER_IN", "REVERSE_USE",
            "StockReturnAgainstUseReceiptV1", "ordinaryRetirementRequiresKnownZero",
            "abandonmentPreservesUnknown", "retryIsIdempotent",
            "BACKUP_RESTORE_MIXED_HISTORY_CLONE_FORK",
        ),
        "C55 fixture semantics",
    )
    adapter = _text(root, "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift")
    restore_service = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift")
    _assert_mutation_concurrency_projection(root)
    _assert_replay_and_return_frontier(contracts, lifecycle, adapter)
    _assert_catalog_history_and_material_binding(contracts, models, adapter)
    _assert_retirement_completeness(contracts, coordinator)
    _assert_integer_number_boundary(root)
    _assert_single_clone_fork_preparation(lifecycle, restore_service)
    _assert_newly_landed_invariants(root)
    _assert_no_forbidden_claims(all_product)
    _assert_backup_propagation(root)
    return ()


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    """Audit source rows, returning missing rows for provisional tooling."""
    return _assert_source_contracts(root)


def require_source_ready(root: Path) -> None:
    missing = _assert_source_contracts(root)
    if missing:
        raise ValueError("C55 source lanes missing:" + ",".join(missing))


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (163, 14, 177):
        raise ValueError("C55 fence cardinality must be 177=163+14")
    if len(set(PATH_FENCE)) != len(PATH_FENCE):
        raise ValueError("C55 duplicate fence path")
    if NEW_PATHS != (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_PATHS):
        raise ValueError("C55 new path order differs")
    if TOOLING_EDIT_PATHS != (*SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_PATHS):
        raise ValueError("C55 tooling edit fence differs")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C55 S10 overlap")
    if any(FLAGS.values()):
        raise ValueError("C55 provisional status flag is true")
    if (
        PRIOR_FENCE_COUNT,
        PRIOR_OWNED_PATH_COUNT,
        AUTHORIZED_OVERLAP_COUNT,
        UNAUTHORIZED_OVERLAP_COUNT,
        S10_RESERVATION_OVERLAP_COUNT,
    ) != (84, 1370, 3915, 0, 0):
        raise ValueError("C55 prior inventory authority differs")
    if not all(re.fullmatch(r"[0-9a-f]{40}", value) for value in (
        BASE_HEAD, BASE_TREE, COORDINATION_HEAD, COORDINATION_TREE,
    )) or not all(re.fullmatch(r"[0-9a-f]{64}", value) for value in (
        CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST,
        COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST,
    )):
        raise ValueError("C55 authority digest shape")
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C55 new path already exists at accepted base")
    if any(not _base_exists(root, path) for path in EXISTING_PATHS):
        missing = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
        raise ValueError("C55 existing path absent at accepted base:" + ",".join(missing))


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": REGISTER_ORDINAL,
        "title": TITLE,
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
        "dossierSHA256": DOSSIER_SHA256,
        "dossierUTF8Length": DOSSIER_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowUTF8Length": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionUTF8Length": REGISTER_SECTION_BYTES,
        "directPrerequisiteFences": {
            "V23-P03-C27": "9864db2f420a45c4497326da79d41f27cbfb187c0fb62c3fca96c051694adc0a",
            "V23-P03-C49": "1f98c92b714a1e4dbecc689efa070f53bbd679fbbc681e5f37da49bdda53d431",
        },
        "inheritedV21PayloadPresent": False,
        "finalHashesSealed": True,
    }


def prior_prerequisite_proof() -> dict[str, Any]:
    fences = authority()["directPrerequisiteFences"]
    return {
        "cards": ["V23-P03-C27", "V23-P03-C49"],
        "fences": fences,
        "liveResealRequired": False,
        "provisionalUntilSourceLanesReady": False,
    }


def _seal_inputs_available(root: Path) -> bool:
    """Return whether every non-generated manifest input is present."""
    if source_status(root)["missingPaths"]:
        return False
    return all(
        (root / path).is_file()
        for path in MANIFEST_INPUT_PATHS
        if path not in GENERATED_INPUT_PATHS
    )


def _source_projection(root: Path, final_hashes_sealed: bool | None = None) -> dict[str, Any]:
    status = source_status(root)
    if final_hashes_sealed is None:
        final_hashes_sealed = bool(status["finalHashesSealed"])
    rows = []
    for path in IMPLEMENTATION_PATHS:
        if path in status["missingPaths"]:
            rows.append({"path": path, "status": "MISSING", "sha256": None, "byteCount": None})
            continue
        data = (root / path).read_bytes()
        rows.append({
            "path": path,
            "status": "SEALED" if final_hashes_sealed else "PRESENT_UNSEALED",
            "sha256": sha256_bytes(data),
            "byteCount": len(data),
        })
    return {
        **status,
        "finalHashesSealed": final_hashes_sealed,
        "paths": rows,
    }


def _semantics() -> dict[str, Any]:
    return {
        "persistenceRowCount": len(PERSISTENCE_ROW_TYPES),
        "persistenceRows": list(PERSISTENCE_ROW_TYPES),
        "snapshotRowCap": C55_SNAPSHOT_ROW_CAP,
        "terminalIdentityCap": C55_TERMINAL_IDENTITY_CAP,
        "terminalIdentityBoundIncludesWorkResourceSuccessors": True,
        "dualPhysicalAndStreamPostImages": True,
        "nativeProjectedWorkspaceClosure": True,
        "partLocationOnlyExternalBaselines": True,
        "activeRev1CloneFork": True,
        "materializeBeforeInsert": True,
        "nilStreamExternalProjection": True,
        "canonicalUnits": list(CANONICAL_UNITS),
        "canonicalUnitRule": "UPPERCASE_CLOSED_CODE_NO_FREEFORM_ALIAS",
        "quantityRepresentation": "EXACT_DECIMAL_MANTISSA_AND_SCALE_NO_FLOATING_POINT",
        "storageLabelKinds": list(STORAGE_LABEL_KINDS),
        "storageLabelMaximumUTF8Bytes": 80,
        "binLabelMaximumUTF8Bytes": 40,
        "partsAreNotAssets": True,
        "locationsAreNotSites": True,
        "balanceStates": list(BALANCE_STATES),
        "unknownUntilOpeningOrCount": True,
        "unknownIsNeverZero": True,
        "knownOnlyMutations": list(KNOWN_ONLY_MUTATIONS),
        "knownOnlyMovementKinds": [
            "ADJUSTMENT_INCREASE", "ADJUSTMENT_DECREASE", "USE_ON_WORK",
            "TRANSFER_OUT", "TRANSFER_IN",
        ],
        "openingAndCountEstablishKnownBalance": True,
        "adjustmentRequiresKnownBalance": True,
        "useRequiresSufficientKnownSource": True,
        "transferRequiresKnownSourceAndDestination": True,
        "returnContract": {
            "type": "StockReturnAgainstUseReceiptV1",
            "exactPriorUseRequired": True,
            "fullSourceUseIncluded": True,
            "sourceUse": "StockUseOnWorkReceiptV1",
            "workResourcePredecessorIncluded": True,
            "workResourcePredecessor": "WorkResourceEntryV1",
            "sourceUseAndWorkResourcePredecessorBound": True,
            "samePartUnitAndWorkLineageRequired": True,
            "knownDestinationRequired": True,
            "positiveQuantityRequired": True,
            "casProtectedOutstandingFrontier": True,
            "partialDoubleAndOverflowReturnRejected": True,
            "reportingOverflowRejected": True,
            "exactWorkResourcePredecessorRequired": True,
            "firstReturnRequiresNilPredecessor": True,
            "subsequentReturnRequiresPredecessorFrontier": True,
            "frontierResolutionUsesPriorAndResultingRemaining": True,
            "freeFormCorrectionIsAdjustment": True,
        },
        "atomicSuccessor": {
            "stockAndWorkResourceUpdatedTogether": True,
            "sameMutationIDAndExpectedRevision": True,
            "oneCanonicalWriterTransaction": True,
            "effectBeforeReceiptRecovery": True,
            "stockUseReversalIdentityBound": True,
            "retryIsIdempotent": True,
        },
        "restoreIdentity": {
            "freshC55Disposition": C55_FRESH_DESTINATION_IDENTITY_DISPOSITION,
            "freshC55EmptyInstallOrReplaceExisting": True,
            "freshC55ResetsSequence": True,
            "freshC55PreservesEveryTerminalRow": True,
            "freshC55ExternalProjectionOnlyPartAndLocation": True,
            "cloneForkDisposition": C55_CLONE_FORK_IDENTITY_DISPOSITION,
            "cloneForkDropsNonCatalogStock": True,
            "sameReplicaReplaceDisposition": C55_SAME_REPLICA_IDENTITY_DISPOSITION,
        },
        "unknownStockAbandonment": {
            "operation": "ABANDON_UNVERIFIED_STOCK",
            "receiptType": "StockAbandonmentReceiptV1",
            "auditReceiptRequired": True,
            "dispositionsArrayRequired": True,
            "archivedPartSuccessorRequired": True,
            "dispositions": "IMMUTABLE_UNKNOWN_QUANTITY_DISPOSITIONS",
            "archivedPartSuccessor": "LOCAL_PART_ARCHIVE_SUCCESSOR",
            "immutableUnknownQuantityDisposition": True,
            "neverAssertsZeroOrLoss": True,
            "ordinaryRetirementRequiresKnownZero": True,
        },
        "ordinaryRetirement": {
            "receiptType": "StockPartRetirementReceiptV1",
            "operation": "RETIRE_PART",
            "completeKnownZeroProjectionRequired": True,
            "verifiedProjectionNonempty": True,
            "zeroOnly": True,
            "archivedPartSuccessorRequired": True,
            "revisePartCannotArchive": True,
        },
        "appendOnlyMovements": list(MOVEMENT_KINDS),
        "historyRenamesDoNotRewrite": True,
        "excludedCapabilities": list(EXCLUDED_CAPABILITIES),
        "persistenceLifecycleSearchReportBackup": {
            "coverage": list(LIFECYCLE_COVERAGE),
            "persistentSchemaVersioned": True,
            "singleWriter": True,
            "backupAndReplaceRestore": True,
            "cloneAndForkRebindHistory": True,
            "importAndExport": True,
            "journalAndReplay": True,
            "searchAndRebuildDerivedOnly": True,
            "reportReviewedSnapshotsOnly": True,
            "deleteAndErase": True,
            "compatibilityAndForwardFix": True,
            "interruptionRecovery": True,
            "idempotentReceipts": True,
        },
        "backupPropagation": dict(BACKUP_PROPAGATION),
        "securityAudit": dict(SECURITY_AUDIT),
        "customerSafeReport": {
            "reviewedWorkMaterialSnapshotsOnly": True,
            "balancesExcluded": True,
            "internalLocationsExcluded": True,
        },
        "selectors": list(EVIDENCE_IDS),
    }


def schema_document() -> dict[str, Any]:
    """Return the contract schema; it is a schema for receipts, not app data."""
    digest = {"type": ["string", "null"], "pattern": "^[0-9a-f]{64}$"}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "urn:assetrounds:v23:p03:c55:parts-stock:v1",
        "title": "V23 P03 C55 Parts & Stock Contract",
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "V23P03C55PartsStockContractV1"},
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD},
            "title": {"type": "string", "const": TITLE},
            "authority": {"$ref": "#/$defs/authority"},
            "evidenceIDs": {"const": list(EVIDENCE_IDS)},
            "contractRefs": {"const": list(CONTRACT_REFS)},
            "journeyRefs": {"const": ["FJ06", "FJ13"]},
            "directPrerequisites": {"const": ["V23-P03-C27", "V23-P03-C49"]},
            "semantics": {"$ref": "#/$defs/semantics"},
            "sourceProjection": {"$ref": "#/$defs/sourceProjection"},
            "provisional": {"const": True},
            "finalHashesSealed": {"const": True},
            "unsupportedClaims": {"const": list(EXCLUDED_CAPABILITIES)},
            "sourceLaneNote": {"const": SOURCE_LANE_NOTE},
            "priorPrerequisiteProof": {"type": "object"},
            "s10ReservationOverlapCount": {"const": 0},
            "s10ReservedPathCount": {"const": 86},
            "statusFlags": {"$ref": "#/$defs/statusFlags"},
        },
        "required": [
            "schema", "schemaVersion", "cardID", "title", "authority", "evidenceIDs",
            "contractRefs", "journeyRefs", "directPrerequisites", "semantics",
            "sourceProjection", "provisional", "finalHashesSealed", "priorPrerequisiteProof",
            "unsupportedClaims", "sourceLaneNote", "s10ReservationOverlapCount", "s10ReservedPathCount", "statusFlags",
        ],
        "$defs": {
            "digest": digest,
            "authority": {
                "type": "object", "additionalProperties": False,
                "required": [
                    "cardID", "attemptID", "registerOrdinal", "appBaseHead", "appBaseTree",
                    "coordinationHead", "coordinationTree", "coordinationCASSequence",
                    "contextDigest", "pathFenceDigest", "provisionalPrerequisiteDigest",
                    "hydrationTransitionDigest", "coordinationLedgerDigest",
                    "coordinationProjectionDigest", "allowedPathCount", "existingPathCount",
                    "newPathCount", "authorizedOverlapCount", "unauthorizedOverlapCount",
                    "s10ReservationOverlapCount", "s10ReservedPathCount", "priorFenceCount",
                    "priorOwnedPathCount", "directPrerequisiteFences", "finalHashesSealed",
                ],
                "properties": {
                    "cardID": {"const": CARD}, "attemptID": {"const": 1},
                    "registerOrdinal": {"const": REGISTER_ORDINAL},
                    "title": {"type": "string"},
                    "appBaseHead": {"$ref": "#/$defs/digest"},
                    "appBaseTree": {"$ref": "#/$defs/digest"},
                    "coordinationHead": {"$ref": "#/$defs/digest"},
                    "coordinationTree": {"$ref": "#/$defs/digest"},
                    "coordinationCASSequence": {"const": COORDINATION_CAS_SEQUENCE},
                    "contextDigest": {"$ref": "#/$defs/digest"},
                    "pathFenceDigest": {"$ref": "#/$defs/digest"},
                    "provisionalPrerequisiteDigest": {"$ref": "#/$defs/digest"},
                    "hydrationTransitionDigest": {"$ref": "#/$defs/digest"},
                    "coordinationLedgerDigest": {"$ref": "#/$defs/digest"},
                    "coordinationProjectionDigest": {"$ref": "#/$defs/digest"},
                    "allowedPathCount": {"const": 177}, "existingPathCount": {"const": 163},
                    "newPathCount": {"const": 14}, "authorizedOverlapCount": {"const": 3915},
                    "unauthorizedOverlapCount": {"const": 0},
                    "s10ReservationOverlapCount": {"const": 0},
                    "s10ReservedPathCount": {"const": 86}, "priorFenceCount": {"const": 84},
                    "priorOwnedPathCount": {"const": 1370},
                    "dossierSHA256": digest, "dossierUTF8Length": {"type": ["integer", "null"]},
                    "registerRowSHA256": digest, "registerRowUTF8Length": {"type": ["integer", "null"]},
                    "registerSectionSHA256": digest, "registerSectionUTF8Length": {"type": ["integer", "null"]},
                    "directPrerequisiteFences": {
                        "type": "object", "additionalProperties": False,
                        "required": ["V23-P03-C27", "V23-P03-C49"],
                        "properties": {
                            "V23-P03-C27": {"const": "9864db2f420a45c4497326da79d41f27cbfb187c0fb62c3fca96c051694adc0a"},
                            "V23-P03-C49": {"const": "1f98c92b714a1e4dbecc689efa070f53bbd679fbbc681e5f37da49bdda53d431"},
                        },
                    },
                    "inheritedV21PayloadPresent": {"const": False},
                    "finalHashesSealed": {"const": True},
                },
            },
            "statusFlags": {
                "type": "object", "additionalProperties": False,
                "properties": {key: {"const": False} for key in FLAGS},
                "required": list(FLAGS),
            },
            "sourceProjection": {
                "type": "object", "additionalProperties": False,
                "required": ["disposition", "finalHashesSealed", "missingPaths", "presentPaths", "requiredPathCount", "presentPathCount", "missingPathCount", "paths"],
                "properties": {
                    "disposition": {"enum": ["PROVISIONAL_MISSING_SOURCE_LANES", "READY_FOR_SOURCE_REPROOF"]},
                    "finalHashesSealed": {"const": True},
                    "missingPaths": {"type": "array", "items": {"type": "string"}},
                    "presentPaths": {"type": "array", "items": {"type": "string"}},
                    "requiredPathCount": {"const": 6}, "presentPathCount": {"type": "integer", "minimum": 0, "maximum": 6},
                    "missingPathCount": {"type": "integer", "minimum": 0, "maximum": 6},
                    "paths": {"type": "array", "minItems": 6, "maxItems": 6},
                },
            },
            "semantics": {
                "type": "object", "additionalProperties": False,
                "required": [
                    "persistenceRowCount", "persistenceRows", "snapshotRowCap", "terminalIdentityCap",
                    "terminalIdentityBoundIncludesWorkResourceSuccessors", "dualPhysicalAndStreamPostImages",
                    "nativeProjectedWorkspaceClosure", "partLocationOnlyExternalBaselines", "activeRev1CloneFork",
                    "materializeBeforeInsert", "nilStreamExternalProjection",
                    "canonicalUnits", "canonicalUnitRule", "quantityRepresentation", "storageLabelKinds",
                    "storageLabelMaximumUTF8Bytes", "binLabelMaximumUTF8Bytes", "partsAreNotAssets", "locationsAreNotSites",
                    "balanceStates", "unknownUntilOpeningOrCount", "unknownIsNeverZero",
                    "knownOnlyMutations", "knownOnlyMovementKinds", "openingAndCountEstablishKnownBalance", "adjustmentRequiresKnownBalance",
                    "useRequiresSufficientKnownSource", "transferRequiresKnownSourceAndDestination",
                    "returnContract", "atomicSuccessor", "restoreIdentity", "unknownStockAbandonment", "ordinaryRetirement", "appendOnlyMovements",
                    "historyRenamesDoNotRewrite", "excludedCapabilities", "persistenceLifecycleSearchReportBackup",
                    "backupPropagation", "securityAudit",
                    "customerSafeReport", "selectors",
                ],
                "properties": {
                    "persistenceRowCount": {"const": 7},
                    "persistenceRows": {"const": list(PERSISTENCE_ROW_TYPES)},
                    "snapshotRowCap": {"const": C55_SNAPSHOT_ROW_CAP},
                    "terminalIdentityCap": {"const": C55_TERMINAL_IDENTITY_CAP},
                    "terminalIdentityBoundIncludesWorkResourceSuccessors": {"const": True},
                    "dualPhysicalAndStreamPostImages": {"const": True},
                    "nativeProjectedWorkspaceClosure": {"const": True},
                    "partLocationOnlyExternalBaselines": {"const": True},
                    "activeRev1CloneFork": {"const": True},
                    "materializeBeforeInsert": {"const": True},
                    "nilStreamExternalProjection": {"const": True},
                    "canonicalUnits": {"const": list(CANONICAL_UNITS)},
                    "canonicalUnitRule": {"const": "UPPERCASE_CLOSED_CODE_NO_FREEFORM_ALIAS"},
                    "quantityRepresentation": {"const": "EXACT_DECIMAL_MANTISSA_AND_SCALE_NO_FLOATING_POINT"},
                    "storageLabelKinds": {"const": list(STORAGE_LABEL_KINDS)},
                    "storageLabelMaximumUTF8Bytes": {"const": 80}, "binLabelMaximumUTF8Bytes": {"const": 40},
                    "partsAreNotAssets": {"const": True},
                    "locationsAreNotSites": {"const": True}, "balanceStates": {"const": list(BALANCE_STATES)},
                    "unknownUntilOpeningOrCount": {"const": True}, "unknownIsNeverZero": {"const": True},
                    "knownOnlyMutations": {"const": list(KNOWN_ONLY_MUTATIONS)},
                    "knownOnlyMovementKinds": {"const": [
                        "ADJUSTMENT_INCREASE", "ADJUSTMENT_DECREASE", "USE_ON_WORK",
                        "TRANSFER_OUT", "TRANSFER_IN",
                    ]},
                    "openingAndCountEstablishKnownBalance": {"const": True},
                    "adjustmentRequiresKnownBalance": {"const": True}, "useRequiresSufficientKnownSource": {"const": True},
                    "transferRequiresKnownSourceAndDestination": {"const": True},
                    "returnContract": {
                        "type": "object", "additionalProperties": False,
                        "required": [
                            "type", "exactPriorUseRequired", "fullSourceUseIncluded", "sourceUse",
                            "workResourcePredecessorIncluded", "workResourcePredecessor",
                            "sourceUseAndWorkResourcePredecessorBound", "samePartUnitAndWorkLineageRequired",
                            "knownDestinationRequired", "positiveQuantityRequired", "casProtectedOutstandingFrontier",
                            "partialDoubleAndOverflowReturnRejected", "reportingOverflowRejected",
                            "exactWorkResourcePredecessorRequired", "firstReturnRequiresNilPredecessor",
                            "subsequentReturnRequiresPredecessorFrontier",
                            "frontierResolutionUsesPriorAndResultingRemaining", "freeFormCorrectionIsAdjustment",
                        ],
                        "properties": {
                            "type": {"const": "StockReturnAgainstUseReceiptV1"},
                            "exactPriorUseRequired": {"const": True}, "fullSourceUseIncluded": {"const": True},
                            "sourceUse": {"const": "StockUseOnWorkReceiptV1"},
                            "workResourcePredecessorIncluded": {"const": True},
                            "workResourcePredecessor": {"const": "WorkResourceEntryV1"},
                            "sourceUseAndWorkResourcePredecessorBound": {"const": True},
                            "samePartUnitAndWorkLineageRequired": {"const": True},
                            "knownDestinationRequired": {"const": True}, "positiveQuantityRequired": {"const": True},
                            "casProtectedOutstandingFrontier": {"const": True},
                            "partialDoubleAndOverflowReturnRejected": {"const": True},
                            "reportingOverflowRejected": {"const": True},
                            "exactWorkResourcePredecessorRequired": {"const": True},
                            "firstReturnRequiresNilPredecessor": {"const": True},
                            "subsequentReturnRequiresPredecessorFrontier": {"const": True},
                            "frontierResolutionUsesPriorAndResultingRemaining": {"const": True},
                            "freeFormCorrectionIsAdjustment": {"const": True},
                        },
                    },
                    "atomicSuccessor": {
                        "type": "object", "additionalProperties": False,
                        "required": [
                            "stockAndWorkResourceUpdatedTogether", "sameMutationIDAndExpectedRevision",
                            "oneCanonicalWriterTransaction", "effectBeforeReceiptRecovery",
                            "stockUseReversalIdentityBound", "retryIsIdempotent",
                        ],
                        "properties": {
                            "stockAndWorkResourceUpdatedTogether": {"const": True},
                            "sameMutationIDAndExpectedRevision": {"const": True},
                            "oneCanonicalWriterTransaction": {"const": True},
                            "effectBeforeReceiptRecovery": {"const": True}, "retryIsIdempotent": {"const": True},
                            "stockUseReversalIdentityBound": {"const": True},
                        },
                    },
                    "restoreIdentity": {
                        "type": "object", "additionalProperties": False,
                        "required": [
                            "freshC55Disposition", "freshC55EmptyInstallOrReplaceExisting",
                            "freshC55ResetsSequence", "freshC55PreservesEveryTerminalRow",
                            "freshC55ExternalProjectionOnlyPartAndLocation", "cloneForkDisposition",
                            "cloneForkDropsNonCatalogStock", "sameReplicaReplaceDisposition",
                        ],
                        "properties": {
                            "freshC55Disposition": {"const": C55_FRESH_DESTINATION_IDENTITY_DISPOSITION},
                            "freshC55EmptyInstallOrReplaceExisting": {"const": True},
                            "freshC55ResetsSequence": {"const": True},
                            "freshC55PreservesEveryTerminalRow": {"const": True},
                            "freshC55ExternalProjectionOnlyPartAndLocation": {"const": True},
                            "cloneForkDisposition": {"const": C55_CLONE_FORK_IDENTITY_DISPOSITION},
                            "cloneForkDropsNonCatalogStock": {"const": True},
                            "sameReplicaReplaceDisposition": {"const": C55_SAME_REPLICA_IDENTITY_DISPOSITION},
                        },
                    },
                    "unknownStockAbandonment": {
                        "type": "object", "additionalProperties": False,
                        "required": [
                            "operation", "receiptType", "auditReceiptRequired", "dispositionsArrayRequired",
                            "archivedPartSuccessorRequired", "dispositions", "archivedPartSuccessor",
                            "immutableUnknownQuantityDisposition", "neverAssertsZeroOrLoss",
                            "ordinaryRetirementRequiresKnownZero",
                        ],
                        "properties": {
                            "operation": {"const": "ABANDON_UNVERIFIED_STOCK"},
                            "receiptType": {"const": "StockAbandonmentReceiptV1"},
                            "auditReceiptRequired": {"const": True}, "dispositionsArrayRequired": {"const": True},
                            "archivedPartSuccessorRequired": {"const": True},
                            "dispositions": {"const": "IMMUTABLE_UNKNOWN_QUANTITY_DISPOSITIONS"},
                            "archivedPartSuccessor": {"const": "LOCAL_PART_ARCHIVE_SUCCESSOR"},
                            "immutableUnknownQuantityDisposition": {"const": True},
                            "neverAssertsZeroOrLoss": {"const": True}, "ordinaryRetirementRequiresKnownZero": {"const": True},
                        },
                    },
                    "ordinaryRetirement": {
                        "type": "object", "additionalProperties": False,
                        "required": [
                            "receiptType", "operation", "completeKnownZeroProjectionRequired", "zeroOnly",
                            "verifiedProjectionNonempty", "archivedPartSuccessorRequired", "revisePartCannotArchive",
                        ],
                        "properties": {
                            "receiptType": {"const": "StockPartRetirementReceiptV1"},
                            "operation": {"const": "RETIRE_PART"},
                            "completeKnownZeroProjectionRequired": {"const": True}, "verifiedProjectionNonempty": {"const": True}, "zeroOnly": {"const": True},
                            "archivedPartSuccessorRequired": {"const": True}, "revisePartCannotArchive": {"const": True},
                        },
                    },
                    "appendOnlyMovements": {"const": list(MOVEMENT_KINDS)},
                    "historyRenamesDoNotRewrite": {"const": True}, "excludedCapabilities": {"const": list(EXCLUDED_CAPABILITIES)},
                    "persistenceLifecycleSearchReportBackup": {"type": "object"},
                    "backupPropagation": {
                        "type": "object", "additionalProperties": False,
                        "required": list(BACKUP_PROPAGATION),
                        "properties": {
                            "persistentSchemaVersion": {"const": 41}, "recordsSchemaVersion": {"const": 40},
                            "durableFamilyCount": {"const": 7},
                            "canonicalSnapshotType": {"const": "PartsStockBackupSnapshotV1"},
                            "recordEnvelopeField": {"const": "partsStockSnapshot"},
                            "restoresSevenFamiliesAtomically": {"const": True},
                            "usesIncumbentLifecyclePort": {"const": True},
                            "derivedBalanceAndSearchAreRebuilt": {"const": True},
                            "preparedRestoreSnapshot": {"const": True},
                            "materializeRestoreStaging": {"const": True},
                            "exactTopology": {
                                "type": "object", "additionalProperties": False,
                                "required": [
                                    "movementEvents", "transfer", "useReceipts",
                                    "useReversalReceipts", "returnReceipts",
                                    "abandonmentDispositions",
                                ],
                                "properties": {
                                    "movementEvents": {"const": "movements"},
                                    "transfer": {"const": "paired_transfer_out_and_in_movements"},
                                    "useReceipts": {"const": "uses"},
                                    "useReversalReceipts": {"const": "reversals"},
                                    "returnReceipts": {"const": "returns"},
                                    "abandonmentDispositions": {"const": "abandonments"},
                                },
                            },
                        },
                    },
                    "securityAudit": {
                        "type": "object", "additionalProperties": False,
                        "required": list(SECURITY_AUDIT),
                        "properties": {key: {"const": True} for key in SECURITY_AUDIT},
                    },
                    "customerSafeReport": {"type": "object"},
                    "selectors": {"const": list(EVIDENCE_IDS)},
                },
            },
        },
    }


def _common(root: Path) -> dict[str, Any]:
    return {
        "cardID": CARD,
        "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "priorPrerequisiteProof": prior_prerequisite_proof(),
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "statusFlags": FLAGS,
        "provisional": True,
        "finalHashesSealed": True,
        "sourceProjection": _source_projection(root, final_hashes_sealed=True),
    }


def contract_document(root: Path) -> dict[str, Any]:
    return {
        "schema": "V23P03C55PartsStockContractV1",
        "schemaVersion": 1,
        "title": TITLE,
        **_common(root),
        "contractRefs": [
            *CONTRACT_REFS,
        ],
        "journeyRefs": ["FJ06", "FJ13"],
        "directPrerequisites": ["V23-P03-C27", "V23-P03-C49"],
        "semantics": _semantics(),
        "unsupportedClaims": list(EXCLUDED_CAPABILITIES),
        "sourceLaneNote": SOURCE_LANE_NOTE,
    }


def evidence_document(root: Path) -> dict[str, Any]:
    return {
        "schema": "V23P03C55PartsStockEvidenceReceiptV1",
        "schemaVersion": 1,
        **_common(root),
        "cases": list(EVIDENCE_IDS),
        "testSelectors": list(EVIDENCE_IDS),
        "journeys": ["FJ06", "FJ13"],
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "acceptanceEligible": False,
        "staticChecks": {
            "persistenceRowCount": 7,
            "snapshotRowCap": C55_SNAPSHOT_ROW_CAP,
            "terminalIdentityCap": C55_TERMINAL_IDENTITY_CAP,
            "terminalIdentityBoundIncludesWorkResourceSuccessors": True,
            "dualPhysicalAndStreamPostImages": True,
            "nativeProjectedWorkspaceClosure": True,
            "partLocationOnlyExternalBaselines": True,
            "activeRev1CloneFork": True,
            "materializeBeforeInsert": True,
            "nilStreamExternalProjection": True,
            "freshC55Disposition": C55_FRESH_DESTINATION_IDENTITY_DISPOSITION,
            "freshC55EmptyInstallOrReplaceExisting": True,
            "freshC55ResetsSequence": True,
            "freshC55PreservesEveryTerminalRow": True,
            "freshC55ExternalProjectionOnlyPartAndLocation": True,
            "cloneForkDisposition": C55_CLONE_FORK_IDENTITY_DISPOSITION,
            "cloneForkDropsNonCatalogStock": True,
            "sameReplicaReplaceDisposition": C55_SAME_REPLICA_IDENTITY_DISPOSITION,
            "canonicalUnits": True,
            "boundedStorageLabels": True,
            "unknownUntilOpeningOrCount": True,
            "knownOnlyAdjustmentUseTransfer": True,
            "casAndProvenanceBoundReturn": True,
            "returnReportingOverflowAndExactPredecessor": True,
            "atomicStockWorkResourceSuccessor": True,
            "stockUseReversalIdentityBound": True,
            "auditedUnknownStockAbandonment": True,
            "knownZeroRetirementWithArchivedSuccessor": True,
            "retirementRequiresNonemptyKnownZeroProjections": True,
            "preparedRestoreSnapshotAndMaterializeStaging": True,
            "v4Schema40BackupPropagation": True,
            "virtualPartLocationStockBalanceStreamCASSeparateFromLocationCatalog": True,
            "contiguousMovementStreamReplayAndGenesis": True,
            "stableMutationPostImageOrdering": True,
            "exactC55ExpectedIdentityMembership": True,
            "statefulRevisionMapReplayTerminalEquality": True,
            "cloneForkDefinitionsOnlyJournalQuarantine": True,
            "mixedHistoryRetainedReceiptProjection": True,
            "overflowSafeCatalogAndBalanceReplay": True,
            "exactReplayDigestComparison": True,
            "firstAndSubsequentReturnFrontierResolution": True,
            "unitHistoryAndExplicitMaterialUnitBinding": True,
            "retirementCompletenessThrows": True,
            "decodedPredecessorCatalogBinding": True,
            "exactBackupTransferUseReversalReturnTopology": True,
            "exactPartsStockSnapshotJournalClosure": True,
            "c49SuccessorSchemaAdmissionAndWorkClosure": True,
            "exactAbandonmentRetirementReplayBinding": True,
            "records40Persistent41SystematicAdmission": True,
            "integerNSNumberNoFractionalTruncation": True,
            "singleCloneForkPreparation": True,
            "excludedProcurementValuationTaxSerializedCloudReplenishment": True,
            "persistenceLifecycleSearchReportBackupClosure": True,
        },
    }


def brand_document(root: Path) -> dict[str, Any]:
    return {
        "schema": "V23P03C55BrandImpactManifestV1",
        "schemaVersion": 1,
        **_common(root),
        "uiSurfaceDelta": True,
        "brandSurfaceDelta": True,
        "requiresS10_6Reconciliation": True,
        "shippingBrandClaimAuthorized": False,
        "customerIdentityVerified": False,
        "networkOrTelemetryFlow": False,
        "deliveryOrLegalSignatureClaimed": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
    }


def _sealed_row(path: str, data: bytes) -> dict[str, Any]:
    return {
        "path": path,
        "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE",
        "byteCount": len(data),
        "sha256": sha256_bytes(data),
    }


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    missing = _assert_source_contracts(root)
    if missing:
        raise ValueError("C55 source lanes missing:" + ",".join(missing))
    if not _seal_inputs_available(root):
        raise ValueError("C55 manifest inputs are incomplete")
    schema = schema_document()
    contract = contract_document(root)
    evidence = evidence_document(root)
    brand = brand_document(root)
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: pretty(schema),
        CONTRACT_PATH: pretty(contract),
        EVIDENCE_PATH: pretty(evidence),
        BRAND_PATH: pretty(brand),
    }
    rows: list[dict[str, Any]] = []
    for path in MANIFEST_INPUT_PATHS:
        data = rendered[path] if path in rendered else (root / path).read_bytes()
        rows.append(_sealed_row(path, data))
    manifest = {
        "schema": "V23P03C55ToolingManifestV1",
        "schemaVersion": 1,
        **_common(root),
        "pathFence": list(PATH_FENCE),
        "pathFenceCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "toolingEditPathCount": len(TOOLING_EDIT_PATHS),
        "toolingEditPaths": list(TOOLING_EDIT_PATHS),
        "sourcePaths": list(IMPLEMENTATION_PATHS),
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED",
        "artifactDigest": sha256_bytes(canonical(rows)),
        "files": rows,
        "sourceLaneRows": [row for row in rows if row["path"] in IMPLEMENTATION_PATHS],
    }
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def _self_parse() -> None:
    for path in SCRIPT_PATHS:
        source = Path(__file__).with_name(Path(path).name).read_text(encoding="utf-8")
        ast.parse(source, filename=path)


if __name__ == "__main__":
    _self_parse()
    print(json.dumps({
        "cardID": CARD,
        "sourceStatus": source_status(Path(__file__).resolve().parents[2]),
        "fencePathCount": len(PATH_FENCE),
        "newPathCount": len(NEW_PATHS),
        "toolingEditPathCount": len(TOOLING_EDIT_PATHS),
    }, indent=2, sort_keys=True))
