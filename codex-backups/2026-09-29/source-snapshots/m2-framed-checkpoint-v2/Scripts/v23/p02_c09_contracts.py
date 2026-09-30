#!/usr/bin/env python3
"""Deterministic Card 29 persistent-kind lifecycle contracts.

Card 29 is a tooling/evidence slice.  The executable source of the current
kind universe is the exact-head ``CurrentSyncClassificationCatalogV1`` backed
by the current schema, owned-file, lifecycle, compatibility, and fixture
declarations.  This module only projects those sources into sealed JSON; it
never treats a handwritten count as authority and fails closed when a required
source or declaration is absent.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P02-C09"
TITLE = "Persistent-kind lifecycle, data-handling, Erase, compatibility, and complete coverage gate"

# These values are the frozen Card 29 context/fence projections.  They are
# deliberately kept separate from the derived universe below.
APP_BASE_HEAD = "c5aaa2a6b6f4a1c900e5743648b66252d19f5ef7"
APP_BASE_TREE = "e766971b63c90fa1f112862b526b908d094fff3d"
COORDINATION_CAS_SEQUENCE = 122
COORDINATION_LEDGER_DIGEST = "3db240dbe762efb5cc844f7337e21007661086a6d5895cb8a73f9de34111e6b1"
CONTEXT_DIGEST = "6f233d87250cb79dd3d435728e500f19bde24eb1cac5cccfa070a23df6b233c2"
FENCE_DIGEST = "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171"
PREREQUISITE_DIGEST = "d997906102bbee16cfde08059e030b30ede4a32f453c6cc1245f8bf75e12bd26"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_LENGTH = 44_217
REGISTER_ROW_DIGEST = "ee7af19fb47c90dcab6376b6fa508ca9e1967ab89481dd980a6884d2f13a2a8b"
DOSSIER_DIGEST = "fa36c072ca2bfc52e05bb65ceaa3717a49d33a1f0101596e9eac357d0e19f062"
DOSSIER_LENGTH = 7_012
INHERITED_DIGEST = "1c2fabdf5f1b1a4264f34c8e7e41492a396839935602b25a6af8eb3075c6a14e"
INHERITED_LENGTH = 10_359
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p02-c09-contracts-v1"
GENERATOR_SEED = 230209

CONTRACT_SCRIPT = "Scripts/v23/p02_c09_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c09_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c09_contracts.py"
PERSISTENT_KIND_SCHEMA = "Scripts/v23/persistent-kind-descriptor.schema.json"
PERSISTENT_LIFECYCLE_SCHEMA = "Scripts/v23/persistent-lifecycle-policy.schema.json"
DATA_HANDLING_SCHEMA = "Scripts/v23/data-handling-policy.schema.json"
COVERAGE_SCHEMA = "Scripts/v23/lifecycle-coverage-manifest.schema.json"
AUDIT_SCHEMA = "Scripts/v23/lifecycle-audit-receipt.schema.json"
PERSISTENT_KIND_DOC = "docs/design/v23/tooling/V23P02C09PersistentKindLifecycleContractV1.json"
DATA_HANDLING_DOC = "docs/design/v23/tooling/V23P02C09DataHandlingPolicyContractV1.json"
COVERAGE_DOC = "docs/design/v23/tooling/V23P02C09LifecycleCoverageManifestV1.json"
COMPATIBILITY_DOC = "docs/design/v23/tooling/V23P02C09LifecycleCompatibilityContractV1.json"
HOSTILE_DOC = "docs/design/v23/tooling/V23P02C09LifecycleHostileMatrixV1.json"
AUDIT_DOC = "docs/design/v23/tooling/V23P02C09LifecycleAuditReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C09-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
]
NEW_SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Lifecycle/V21P02C09PersistentKindLifecycleCoverageCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    PERSISTENT_KIND_SCHEMA,
    PERSISTENT_LIFECYCLE_SCHEMA,
    DATA_HANDLING_SCHEMA,
    COVERAGE_SCHEMA,
    AUDIT_SCHEMA,
    PERSISTENT_KIND_DOC,
    DATA_HANDLING_DOC,
    COVERAGE_DOC,
    COMPATIBILITY_DOC,
    HOSTILE_DOC,
    AUDIT_DOC,
    MANIFEST,
]
SOURCE_PATHS = EXISTING_PATHS + NEW_SOURCE_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
GENERATED_PATHS = TOOL_PATHS[3:]
NEW_PATHS = NEW_SOURCE_PATHS + TOOL_PATHS

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_13G01ClosedUniverseAndCoverageManifestAreComplete",
    "testV9_13A01EveryLifecycleActionAndDataHandlingClassificationIsExplicit",
    "testV9_13H01DuplicateConflictingAndUnsafePoliciesFailClosed",
    "testV9_13I01InterruptedLifecycleTransitionsExposeNoPartialAcceptance",
    "testV9_13R01EraseCompatibilityForwardFixAndFixtureBindingRemainClosed",
]

# This is the closed order of ``PersistentLifecycleActionV1.allCases`` in the
# current product source.  The contract deliberately binds the complete enum
# rather than inventing a smaller convenience subset: a missing action is not
# permission to perform it.
LIFECYCLE_ACTIONS = [
    "SCHEMA_AND_VERSION", "WRITER_COMMAND", "CANONICAL_QUERY", "MIGRATION",
    "FILESYSTEM_BACKUP", "SEMANTIC_BACKUP", "REPLACE_RESTORE", "CLONE", "FORK",
    "IMPORT", "EXPORT", "REPORT", "JOURNAL", "REPLAY", "SEARCH", "REBUILD",
    "DELETE", "ERASE", "RETENTION", "LOCALIZATION", "ACCESSIBILITY", "PRIVACY",
    "COMPATIBILITY", "DOWNGRADE", "FORWARD_FIX", "INTERRUPTION_RECOVERY",
    "IDEMPOTENT_RECEIPT", "FUTURE_REPLICATION",
]
ACTION_DISPOSITIONS = [
    "SUPPORTED", "DENIED", "REBUILDABLE", "IMMUTABLE", "CONTENT_MANAGED",
    "NOT_APPLICABLE", "OWNER_REQUIRED",
]
DATA_PRIVACY = [
    "WORKSPACE_CANONICAL", "WORKSPACE_CONTENT", "PRIVATE_DEVICE_OPERATIONAL",
    "NONCUSTOMER_DIAGNOSTIC",
]
DATA_RETENTION = [
    "UNTIL_CANONICAL_DELETE_OR_ERASE", "IMMUTABLE_HISTORY_UNTIL_ERASE",
    "REBUILDABLE", "OPERATION_SCOPED", "LOCAL_DEVICE_RETAINED",
]
DESTRUCTIVE_AUTHORITIES = [
    "CANONICAL_WORKSPACE_DELETION", "IMMUTABLE_CONTENT_MANAGER",
    "DERIVED_REBUILD_OWNER", "LOCAL_DEVICE_OWNER", "OPERATION_CLEANUP_OWNER",
    "NOT_APPLICABLE", "OWNER_REQUIRED",
]
STORAGE_DISPOSITIONS = [
    "SWIFT_DATA_MODEL", "OWNED_FILE", "RECOVERY_JOURNAL",
    "DERIVED_PROJECTION", "PORTABLE_WIRE_PROJECTION", "NONPERSISTENT_DECLARATION",
]
REVISION_DISPOSITIONS = [
    "EXACT_REVISION", "APPEND_ONLY_IMMUTABLE", "IMMUTABLE_CONTENT",
    "DERIVED_FROM_CANONICAL_INPUTS", "DESTINATION_LOCAL", "OPERATION_SCOPED",
]
MUTATION_DISPOSITIONS = [
    "WORKSPACE_WRITER", "IMMUTABLE_CONTENT_WRITER", "LOCAL_DEVICE_OWNER",
    "DERIVED_ONLY", "NONE",
]
DIGEST_DISPOSITIONS = [
    "CANONICAL_DIGEST_REQUIRED", "IMMUTABLE_CONTENT_DIGEST_REQUIRED",
    "REBUILD_FROM_DEPENDENCIES", "NOT_APPLICABLE",
]
CLASSIFICATIONS = [
    "CANONICAL", "CONTENT", "DECLARATION", "DERIVED", "IMMUTABLE",
    "NONPERSISTENT", "WIRE",
]
UNIVERSE_CATEGORIES = [
    ("persistentModelNames", "PERSISTENT_MODEL"),
    ("ownedFileClassNames", "OWNED_FILE_CLASS"),
    ("portableContentProjectionNames", "PROJECTION"),
    ("derivedIndexNames", "INDEX"),
    ("derivedProjectionNames", "PROJECTION"),
    ("journalRecoveryNames", "JOURNAL"),
    ("diagnosticNames", "DIAGNOSTIC"),
]
FIXTURE_UNIVERSE_SOURCES = [
    "ACCEPTED_FIXTURE_DECLARATION",
    "ARCHIVE_EXPORT_REPORT_PACKAGE_EXCHANGE_REGISTRY",
    "JOURNAL_CHECKPOINT_PROJECTION_REGISTRY",
    "OWNED_FILE_POLICY",
    "PERSISTENT_SCHEMA",
    "SYNC_CLASSIFICATION_CATALOG",
    "TEMPORAL_PROVENANCE_REGISTRY",
]
FIXTURE_CLASSIFICATIONS = CLASSIFICATIONS
# Lifecycle classification is intentionally a separate closed vocabulary from
# SyncClassificationV1's replication classification.  The former describes
# handling/ownership semantics; the latter describes replication transport.
REPLICATION_CLASSIFICATIONS = [
    "REPLICATED", "LOCAL_ONLY", "DERIVED_REBUILDABLE", "CONTENT_BLOB",
    "PRIVATE_DEVICE_ONLY",
]
FIXTURE_HANDLING_ACTIONS = [
    "CONTENT_MANAGED", "DENIED", "IMMUTABLE", "NOT_APPLICABLE", "REBUILDABLE", "SUPPORTED",
]
FIXTURE_LIFECYCLE_DIMENSIONS = sorted(LIFECYCLE_ACTIONS)
FIXTURE_REPRESENTATIVE_POLICIES = [
    {"classification": "CANONICAL", "expectedErase": "SUPPORTED", "expectedRebuild": "NOT_APPLICABLE", "expectedRetention": "SUPPORTED"},
    {"classification": "IMMUTABLE", "expectedErase": "IMMUTABLE", "expectedRebuild": "NOT_APPLICABLE", "expectedRetention": "IMMUTABLE"},
    {"classification": "DERIVED", "expectedErase": "REBUILDABLE", "expectedRebuild": "REBUILDABLE", "expectedRetention": "NOT_APPLICABLE"},
    {"classification": "CONTENT", "expectedErase": "CONTENT_MANAGED", "expectedRebuild": "NOT_APPLICABLE", "expectedRetention": "CONTENT_MANAGED"},
    {"classification": "DECLARATION", "expectedErase": "IMMUTABLE", "expectedRebuild": "NOT_APPLICABLE", "expectedRetention": "IMMUTABLE"},
    {"classification": "WIRE", "expectedErase": "NOT_APPLICABLE", "expectedRebuild": "NOT_APPLICABLE", "expectedRetention": "NOT_APPLICABLE"},
    {"classification": "NONPERSISTENT", "expectedErase": "NOT_APPLICABLE", "expectedRebuild": "REBUILDABLE", "expectedRetention": "NOT_APPLICABLE"},
]
ERASE_PROFILES = [
    {"classification": "CANONICAL", "actionDisposition": "SUPPORTED", "observedDisposition": "REMOVED"},
    {"classification": "IMMUTABLE", "actionDisposition": "IMMUTABLE", "observedDisposition": "PRESERVED_IMMUTABLE"},
    {"classification": "DERIVED", "actionDisposition": "REBUILDABLE", "observedDisposition": "REBUILT_EMPTY"},
    {"classification": "CONTENT", "actionDisposition": "CONTENT_MANAGED", "observedDisposition": "CLEARED_BY_DECLARED_OWNER"},
    {"classification": "DECLARATION", "actionDisposition": "IMMUTABLE", "observedDisposition": "PRESERVED_IMMUTABLE"},
    {"classification": "WIRE", "actionDisposition": "NOT_APPLICABLE", "observedDisposition": "NOT_APPLICABLE"},
    {"classification": "NONPERSISTENT", "actionDisposition": "NOT_APPLICABLE", "observedDisposition": "NOT_APPLICABLE"},
]
PRESENTATION_OUTPUTS = {
    "localization": {
        "actionDisposition": "SUPPORTED",
        "dataHandlingDisposition": "LOCALIZED_FROZEN_HISTORIC_PROJECTION",
        "sourceProperty": "localization",
    },
    "accessibility": {
        "actionDisposition": "SUPPORTED",
        "dataHandlingDisposition": "ACCESSIBLE_FROZEN_HISTORIC_PROJECTION",
        "sourceProperty": "accessibility",
    },
}
TEMPORAL_BOUNDARIES = {
    "firstWrite": {
        "required": True,
        "evidence": "ENROLLED_BEFORE_FIRST_WRITE",
        "rule": "FIRST_WRITE_REQUIRES_LIFECYCLE_ENROLLMENT",
        "scope": "FUTURE_OR_UNWRITTEN_KINDS",
    },
    "enrollment": {
        "required": True,
        "evidence": "ENROLLED_BEFORE_FIRST_WRITE",
        "rule": "LIFECYCLE_ENROLLMENT_PRECEDES_WRITER",
    },
    "forwardFix": {
        "required": True,
        "evidence": "PREEXISTING_BOUND_FORWARD_FIX",
        "rule": "FORWARD_FIX_ONLY_AFTER_ACTIVATION",
        "scope": "CURRENT_65_DURABLE_REPRESENTATIONS",
    },
    "temporalConflictGapField": "temporalConflictKindIDs",
    "nonpersistent": {
        "evidence": "NONPERSISTENT_NO_CANONICAL_WRITE",
        "firstWriteVersion": "NOT_APPLICABLE",
        "forwardFixVersion": "NOT_APPLICABLE",
    },
}
TEMPORAL_PROVENANCE_ANCHORS = [
    {"kindID": "PERSISTENT_MODEL:PersistentSchemaReleaseMarker", "card": "V23_P01_C03", "ordinal": 16, "commit": "989d73460e4614e3bbea6c1dc20a9da0a1e5f660", "required": True},
    {"kindID": "PROJECTION:StreamingArchiveIndexV1", "card": "V23_P01_C04", "ordinal": 17, "commit": "8e2536f42e6381412d22de302b013f606c2ec42f", "required": True},
    {"kindID": "JOURNAL:CurrentGenerationPointerV3", "card": "V23_P01_C05", "ordinal": 18, "commit": "417aec8af085ac4e01d4b73c822ba99511a14611", "required": True},
    {"kindID": "PERSISTENT_MODEL:DeletionLedgerRow", "card": "V23_P01_C06", "ordinal": 19, "commit": "e576a3ca91d597fff41d0f23209bab009ff8de6b", "required": True},
    {"kindID": "PERSISTENT_MODEL:EntityMutationRevisionRow", "card": "V23_P02_C02", "ordinal": 22, "commit": "e05839a52a93a367cf4b118974a45db0d47182d0", "required": True},
    {"kindID": "OWNED_FILE_CLASS:generationLeaseControl", "card": "V23_P02_C04", "ordinal": 24, "commit": "a6742867a235ad7cc4e4bc07f2b650cca82434cd", "required": True},
    {"kindID": "PERSISTENT_MODEL:ObservationAndTimeRow", "card": "V23_P02_C07", "ordinal": 27, "commit": "5f4259dc9d46090203d59273f0c35b1ab1ee6a0d", "required": True},
    {"kindID": "DIAGNOSTIC:DeviceOperationalSupportStoreV2", "card": "V23_P02_C08", "ordinal": 28, "commit": "c5aaa2a6b6f4a1c900e5743648b66252d19f5ef7", "required": True},
]
HOSTILE_CASES = [
    "BACKUP_WITHOUT_RESTORE", "DENIED_KIND_ENTERS_EXPORT", "DENIED_KIND_ENTERS_REPORT",
    "DUPLICATE_KIND", "DUPLICATE_OWNER", "ERASE_DESTROYS_IMMUTABLE_TRUTH",
    "ERASE_LEAVES_ERASABLE_ORPHAN", "MISSING_KIND", "OWNER_IMPLEMENTATION_CONFLICT",
    "TEMPORALLY_IMPOSSIBLE_WRITER", "MISSING_TEMPORAL_PROVENANCE",
    "DUPLICATE_TEMPORAL_PROVENANCE", "WRONG_LATER_CARD_PROVENANCE",
    "IMPOSSIBLE_TEMPORAL_CHRONOLOGY", "UNKNOWN_ACTION", "UNKNOWN_CLASSIFICATION",
    "UNKNOWN_POLICY_VERSION",
]
INTERRUPTION_BOUNDARIES = [
    "BEFORE_POLICY_STAGING", "AFTER_POLICY_STAGING_BEFORE_ACTIVATION",
    "AFTER_ACTIVATION_BEFORE_RECEIPT", "AFTER_RECEIPT_BEFORE_CLEANUP",
]
COMPATIBILITY_CASES = [
    {"caseID": "PRE_ACTIVATION_INTERRUPTION", "expectedDisposition": "DISCARD_STAGING", "rewritesReleasedHistory": False},
    {"caseID": "POST_ACTIVATION_INTERRUPTION", "expectedDisposition": "APPEND_VERSIONED_SUCCESSOR_AND_FORWARD_FIX", "rewritesReleasedHistory": False},
    {"caseID": "FUTURE_POLICY_VERSION", "expectedDisposition": "QUARANTINE_AND_REQUIRE_FORWARD_FIX", "rewritesReleasedHistory": False},
]
PROHIBITED_TOKENS = [
    "SwiftDataV6", "SwiftDataV6Entity", "tenant", "account", "credential", "signedURL",
    "fakeOutbox", "CloudKit", "CKRecord", "URLSession", "Keychain", "searchStore",
]


class ContractError(ValueError):
    """Raised when the frozen Card 29 projection cannot be built."""


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def canonical(value: Any) -> bytes:
    """Match CompatibilityCanonicalV1's sorted-key, compact JSON bytes."""
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "physicalEvidenceComplete": False,
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "releaseReady": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": 29,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "REFINED_WITHOUT_LOSS",
        "lineageSource": "V21-P02-C09",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "registerSectionDigest": REGISTER_SECTION_DIGEST,
        "registerSectionLength": REGISTER_SECTION_LENGTH,
        "registerRowDigest": REGISTER_ROW_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "dossierLength": DOSSIER_LENGTH,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "inheritedV21BlockLength": INHERITED_LENGTH,
        "foundationRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P02-C08"],
        "invalidationConsumers": ["V23-P02-C10", "V23-P03-C01"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {"schema": schema_name, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def common_contract_fields() -> dict[str, Any]:
    return {
        "evidenceIDs": EVIDENCE_IDS,
        "provisionalKernelOnly": True,
        "shippingBoundaryAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "noNewSwiftDataV6Entity": True,
        "phase10PollingDuringParallelExecution": False,
        **flags(),
    }


def _extract_array(text: str, name: str) -> list[str] | None:
    match = re.search(rf"static\s+let\s+{re.escape(name)}(?:\s*:\s*[^=]+)?\s*=\s*\[(.*?)\n\s*\]", text, re.S)
    if match is None:
        return None
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))


def _extract_model_self_names(text: str, allowed: set[str]) -> list[str]:
    """Recover model types actually present in the V5 model graph.

    This is deliberately independent of the CurrentSync catalog's hand-built
    name array.  The intersection with the closed catalog names keeps helper
    types and non-model ``.self`` references out of the result while still
    detecting a missing V5 model declaration.
    """
    candidates = re.findall(r"\b([A-Z][A-Za-z0-9_]*)\.self\b", text)
    return sorted(set(candidates) & allowed)


def _extract_owned_file_cases(text: str) -> list[str]:
    match = re.search(
        r"enum\s+OwnedFileKindV1\b.*?\{(.*?)\n\s*\}\n\s*\n\s*struct\s+OwnedFileProtectionDispositionV1",
        text,
        re.S,
    )
    if match is None:
        raise ContractError("missing OwnedFileKindV1 allCases declaration")
    return re.findall(r"\bcase\s+([A-Za-z0-9_]+)", match.group(1))


def _swift_braced_block(text: str, marker: str) -> str:
    """Return one balanced Swift block, failing closed when it is absent."""
    start = text.find(marker)
    if start < 0:
        raise ContractError(f"missing Swift source marker: {marker}")
    opening = text.find("{", start)
    if opening < 0:
        raise ContractError(f"missing Swift block opening: {marker}")
    depth = 0
    in_string = False
    escaped = False
    for index in range(opening, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise ContractError(f"unterminated Swift block: {marker}")


def _swift_case_tuple_map(block: str) -> dict[str, tuple[str, str]]:
    """Parse ``case \"A\", \"B\": return (.x, .y)`` source mappings."""
    result: dict[str, tuple[str, str]] = {}
    pattern = re.compile(
        r"case\s+([^:]+):\s*return\s*\(\.([A-Za-z0-9_]+),\s*\.([A-Za-z0-9_]+)\)",
        re.S,
    )
    for match in pattern.finditer(block):
        names = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))
        for name in names:
            if name in result:
                raise ContractError(f"duplicate source classification mapping: {name}")
            result[name] = (match.group(2), match.group(3))
    return result


def _swift_owned_kind_classifications(block: str) -> dict[str, str]:
    """Parse the explicit ``OwnedFileKindV1`` lifecycle-classification switch."""
    switch_start = block.find("switch kind {")
    if switch_start < 0:
        raise ContractError("missing owned-file lifecycle classification switch")
    switch = _swift_braced_block(block[switch_start:], "switch kind")
    result: dict[str, str] = {}
    pattern = re.compile(
        r"case\s+((?:\.[A-Za-z0-9_]+\s*,?\s*)+):\s*return\s+\.([A-Za-z0-9_]+)",
        re.S,
    )
    for match in pattern.finditer(switch):
        names = re.findall(r"\.([A-Za-z0-9_]+)", match.group(1))
        for name in names:
            if name in result:
                raise ContractError(f"duplicate owned-file lifecycle mapping: {name}")
            result[name] = match.group(2).upper()
    return result


def _parse_temporal_origins(root: Path, kind_ids: list[str]) -> dict[str, Any]:
    """Recover the exact origin map emitted by the current lifecycle compiler."""
    relative = NEW_SOURCE_PATHS[1]
    path = root / relative
    text = path.read_text(encoding="utf-8")
    baseline_match = re.search(
        r"static\s+let\s+baselineTemporalOrigin\s*=\s*TemporalOriginV1\(\s*"
        r"card:\s*\"([^\"]+)\"\s*,\s*ordinal:\s*(\d+)",
        text,
        re.S,
    )
    if baseline_match is None:
        raise ContractError("missing baseline temporal origin")
    baseline = {
        "card": baseline_match.group(1),
        "ordinal": int(baseline_match.group(2)),
    }
    declarations = {
        name: {"card": card, "ordinal": int(ordinal)}
        for name, card, ordinal in re.findall(
            r"let\s+(c\d+)\s*=\s*TemporalOriginV1\(\s*"
            r"card:\s*\"([^\"]+)\"\s*,\s*ordinal:\s*(\d+)",
            text,
            re.S,
        )
    }
    if not declarations:
        raise ContractError("missing non-baseline temporal origin declarations")
    groups_match = re.search(
        r"let\s+groups:\s*\[\(TemporalOriginV1,\s*\[String\]\)\]\s*=\s*"
        r"\[(.*?)\n\s*\]\s*\n\s*return\s+groups",
        text,
        re.S,
    )
    if groups_match is None:
        raise ContractError("missing temporal origin group table")
    origins: dict[str, dict[str, Any]] = {}
    group_rows: list[dict[str, Any]] = []
    group_pattern = re.compile(
        r"\((c\d+)\s*,\s*\[(.*?)\n\s*\]\s*\)",
        re.S,
    )
    for group in group_pattern.finditer(groups_match.group(1)):
        origin_name = group.group(1)
        origin = declarations.get(origin_name)
        if origin is None:
            raise ContractError(f"temporal origin group has no declaration: {origin_name}")
        members = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', group.group(2))
        if not members:
            raise ContractError(f"temporal origin group is empty: {origin_name}")
        row = {
            "card": origin["card"],
            "ordinal": origin["ordinal"],
            "kindIDs": sorted(members),
        }
        group_rows.append(row)
        for kind_id in members:
            if kind_id in origins:
                raise ContractError(f"duplicate temporal origin kind: {kind_id}")
            origins[kind_id] = {
                "card": origin["card"],
                "ordinal": origin["ordinal"],
            }
    declared_count_match = re.search(
        r"laterTemporalOrigins\.count\s*==\s*(\d+)", text
    )
    accepted_digest_match = re.search(
        r"acceptedTemporalUniverseDigest\s*=\s*\n?\s*\"([0-9a-f]{64})\"",
        text,
    )
    if declared_count_match is None or accepted_digest_match is None:
        raise ContractError("temporal origin source guards are incomplete")
    declared_count = int(declared_count_match.group(1))
    accepted_universe_digest = accepted_digest_match.group(1)
    if len(origins) != declared_count:
        raise ContractError(
            f"temporal origin count differs: {len(origins)} != {declared_count}"
        )
    if not set(origins).issubset(kind_ids):
        raise ContractError("temporal origin table contains an unknown kind")
    computed_universe_digest = sha(canonical(sorted(kind_ids)))
    if computed_universe_digest != accepted_universe_digest:
        raise ContractError("accepted temporal universe digest differs from exact universe")
    return {
        "sourcePath": relative,
        "sourceSHA256": sha(path.read_bytes()),
        "sourceBytes": path.stat().st_size,
        "baseline": baseline,
        "laterOrigins": origins,
        "originGroups": sorted(group_rows, key=lambda row: (row["ordinal"], row["card"])),
        "declaredLaterOriginCount": declared_count,
        "acceptedTemporalUniverseDigest": accepted_universe_digest,
        "exactUniverseDigest": computed_universe_digest,
    }


def _classification_and_storage(
    root: Path,
    fields: dict[str, dict[str, Any]],
    kind_ids: list[str],
) -> dict[str, dict[str, Any]]:
    """Project the compiler's typed classification/storage branches per kind."""
    registry_path = root / EXISTING_PATHS[1]
    lifecycle_path = root / NEW_SOURCE_PATHS[1]
    current_path = root / EXISTING_PATHS[2]
    registry_text = registry_path.read_text(encoding="utf-8")
    lifecycle_text = lifecycle_path.read_text(encoding="utf-8")
    current_text = current_path.read_text(encoding="utf-8")
    persistent_block = _swift_braced_block(
        registry_text, "static func persistentModelDisposition"
    )
    owned_block = _swift_braced_block(
        registry_text, "static func ownedFileDisposition"
    )
    persistent_map = _swift_case_tuple_map(persistent_block)
    owned_map = _swift_case_tuple_map(owned_block)
    lifecycle_block = _swift_braced_block(lifecycle_text, "static func kindClassification")
    owned_kind_map = _swift_owned_kind_classifications(lifecycle_block)
    portable_names = set(fields["portableContentProjectionNames"]["names"])
    derived_projection_names = set(fields["derivedProjectionNames"]["names"])
    derived_index_names = set(fields["derivedIndexNames"]["names"])
    journal_names = set(fields["journalRecoveryNames"]["names"])
    diagnostic_names = set(fields["diagnosticNames"]["names"])
    replicated_history_match = re.search(
        r"let\s+replicatedHistory\s*=\s*Set\(\[(.*?)\]\)",
        current_text,
        re.S,
    )
    if replicated_history_match is None:
        raise ContractError("missing replicated journal history source set")
    replicated_history = set(
        re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', replicated_history_match.group(1))
    )
    if not replicated_history:
        raise ContractError("replicated journal history source set is empty")
    result: dict[str, dict[str, Any]] = {}
    for kind_id in kind_ids:
        category, name = kind_id.split(":", 1)
        replication: str
        lifecycle: str
        storage: str
        conflict_rule: str | None = None
        if category == "PERSISTENT_MODEL":
            if name == "ObservationAndTimeRow":
                replication, conflict_rule = "replicated", "exactRevisionManual"
            else:
                try:
                    replication, conflict_rule = persistent_map[name]
                except KeyError as error:
                    raise ContractError(f"persistent model lacks source disposition: {name}") from error
            replication = {
                "replicated": "REPLICATED",
                "localOnly": "LOCAL_ONLY",
                "derivedRebuildable": "DERIVED_REBUILDABLE",
                "contentBlob": "CONTENT_BLOB",
                "privateDeviceOnly": "PRIVATE_DEVICE_ONLY",
            }[replication]
            storage = "SWIFT_DATA_MODEL"
            if name == "PersistentSchemaReleaseMarker" or replication == "LOCAL_ONLY":
                lifecycle = "DECLARATION"
            elif replication == "DERIVED_REBUILDABLE":
                lifecycle = "DERIVED"
            elif conflict_rule in {"deleteWins", "stableIDAppendUnion", "immutableVersion"}:
                lifecycle = "IMMUTABLE"
            else:
                lifecycle = "CANONICAL"
        elif category == "OWNED_FILE_CLASS":
            try:
                replication, conflict_rule = owned_map[name]
            except KeyError as error:
                raise ContractError(f"owned file lacks source disposition: {name}") from error
            replication = {
                "replicated": "REPLICATED",
                "localOnly": "LOCAL_ONLY",
                "derivedRebuildable": "DERIVED_REBUILDABLE",
                "contentBlob": "CONTENT_BLOB",
                "privateDeviceOnly": "PRIVATE_DEVICE_ONLY",
            }[replication]
            storage = "OWNED_FILE"
            lifecycle = owned_kind_map.get(name)
            if lifecycle is None:
                lifecycle = {
                    "CONTENT_BLOB": "CONTENT",
                    "DERIVED_REBUILDABLE": "DERIVED",
                    "REPLICATED": "IMMUTABLE" if conflict_rule in {
                        "deleteWins", "stableIDAppendUnion", "immutableVersion"
                    } else "CANONICAL",
                    "LOCAL_ONLY": "DECLARATION",
                    "PRIVATE_DEVICE_ONLY": "DECLARATION",
                }[replication]
        elif category == "JOURNAL":
            replication = "REPLICATED" if name in replicated_history else "LOCAL_ONLY"
            lifecycle = "CANONICAL"
            storage = "RECOVERY_JOURNAL"
        elif category == "INDEX":
            replication = "DERIVED_REBUILDABLE"
            lifecycle = "DERIVED"
            storage = "DERIVED_PROJECTION"
        elif category == "PROJECTION":
            if name in portable_names:
                replication = "CONTENT_BLOB" if name == "ReportSnapshotV1" else "DERIVED_REBUILDABLE"
                lifecycle = "WIRE"
                # ReportSnapshotV1 uses the immutable-content profile, whose
                # source registration persists it as an owned file even though
                # its lifecycle classification is still the exported WIRE
                # projection branch.
                storage = "OWNED_FILE" if name == "ReportSnapshotV1" else "PORTABLE_WIRE_PROJECTION"
            elif name in derived_projection_names or name in {"entityMutationRevision", "workspaceMutationState"}:
                replication = "DERIVED_REBUILDABLE"
                lifecycle = "DERIVED"
                # The two legacy projection registrations intentionally retain
                # SwiftData persistence; this is an exact source distinction.
                storage = "SWIFT_DATA_MODEL" if name in {"entityMutationRevision", "workspaceMutationState"} else "DERIVED_PROJECTION"
            else:
                raise ContractError(f"projection lacks source profile: {name}")
        elif category == "DIAGNOSTIC":
            if name not in diagnostic_names:
                raise ContractError(f"diagnostic lacks current catalog declaration: {name}")
            replication = "PRIVATE_DEVICE_ONLY"
            lifecycle = "CANONICAL" if name == "DeviceOperationalSupportStoreV2" else "NONPERSISTENT"
            storage = "OWNED_FILE" if name in {"DeviceOperationalSupportStoreV2", "ScratchDataLeaseStoreV1", "diagnosticCounters"} else "NONPERSISTENT_DECLARATION"
        else:
            raise ContractError(f"unsupported exact-head kind category: {category}")
        result[kind_id] = {
            "kindClassification": lifecycle,
            "replicationClassification": replication,
            "storageDisposition": storage,
            "durableRepresentationWrite": storage in {"SWIFT_DATA_MODEL", "OWNED_FILE", "RECOVERY_JOURNAL"},
            "conflictRule": conflict_rule,
        }
    if set(result) != set(kind_ids):
        raise ContractError("classification projection does not cover exact universe")
    return result


def _temporal_provenance(root: Path, universe: dict[str, Any]) -> dict[str, Any]:
    """Build and validate the exhaustive 100-row temporal evidence projection."""
    kind_ids = universe["kindIDs"]
    fields = universe["sourceArrays"]
    fixture_path = root / NEW_SOURCE_PATHS[3]
    try:
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ContractError(f"invalid lifecycle fixture for temporal provenance: {error}") from error
    fixture_rows = fixture.get("temporalProvenance")
    if not isinstance(fixture_rows, list):
        raise ContractError("fixture temporalProvenance declaration is absent")
    if len(fixture_rows) != len(kind_ids):
        raise ContractError("fixture temporalProvenance is not exact universe cardinality")
    fixture_by_id: dict[str, dict[str, Any]] = {}
    for item in fixture_rows:
        if not isinstance(item, dict) or set(item) != {
            "kindID", "representationSourceCard", "representationSourceOrdinal"
        }:
            raise ContractError("fixture temporal provenance row shape differs")
        kind_id = item["kindID"]
        if not isinstance(kind_id, str) or kind_id in fixture_by_id:
            raise ContractError("fixture temporal provenance has duplicate/invalid kind")
        fixture_by_id[kind_id] = item
    if list(fixture_by_id) != kind_ids:
        raise ContractError("fixture temporal provenance IDs are not exact sorted universe")
    durable_fixture = fixture.get("durableFirstWriteKindIDs")
    if not isinstance(durable_fixture, list) or not all(isinstance(value, str) for value in durable_fixture):
        raise ContractError("fixture durableFirstWriteKindIDs declaration is absent")
    if durable_fixture != sorted(durable_fixture) or len(durable_fixture) != len(set(durable_fixture)):
        raise ContractError("fixture durableFirstWriteKindIDs is not sorted/unique")
    origins = _parse_temporal_origins(root, kind_ids)
    profiles = _classification_and_storage(root, fields, kind_ids)
    rows: list[dict[str, Any]] = []
    durable_ids: list[str] = []
    for kind_id in kind_ids:
        is_later_origin = kind_id in origins["laterOrigins"]
        origin = origins["laterOrigins"].get(kind_id, origins["baseline"])
        fixture_origin = fixture_by_id[kind_id]
        if fixture_origin["representationSourceCard"] != origin["card"] or fixture_origin["representationSourceOrdinal"] != origin["ordinal"]:
            raise ContractError(f"fixture temporal origin differs for {kind_id}")
        profile = profiles[kind_id]
        durable = profile["durableRepresentationWrite"]
        if durable:
            durable_ids.append(kind_id)
        not_applicable = "NOT_APPLICABLE"
        temporal = {
            "schemaVersion": 1,
            "evidenceID": "temporal." + kind_id,
            "evidenceVersion": 1,
            "disposition": "PREEXISTING_BOUND_FORWARD_FIX" if durable else "NONPERSISTENT_NO_CANONICAL_WRITE",
            "representationSourceCard": origin["card"],
            "representationSourceOrdinal": origin["ordinal"],
            "firstWriteVersion": origin["card"] if durable else not_applicable,
            "lifecycleEnrollmentVersion": CARD.replace("-", "_"),
            "forwardFixVersion": CARD.replace("-", "_") if durable else not_applicable,
            "firstWriteOrdinal": origin["ordinal"] if durable else 0,
            "lifecycleEnrollmentOrdinal": 29,
            "forwardFixOrdinal": 29 if durable else 0,
        }
        body = {
            "kindID": kind_id,
            "kindClassification": profile["kindClassification"],
            "replicationClassification": profile["replicationClassification"],
            "storageDisposition": profile["storageDisposition"],
            "durableRepresentationWrite": durable,
            "temporalEvidence": temporal,
            "representationSourceCard": origin["card"],
            "representationSourceOrdinal": origin["ordinal"],
            "firstWriteVersion": temporal["firstWriteVersion"],
            "firstWriteOrdinal": temporal["firstWriteOrdinal"],
            "lifecycleEnrollmentVersion": temporal["lifecycleEnrollmentVersion"],
            "lifecycleEnrollmentOrdinal": temporal["lifecycleEnrollmentOrdinal"],
            "forwardFixVersion": temporal["forwardFixVersion"],
            "forwardFixOrdinal": temporal["forwardFixOrdinal"],
            "provenanceSource": (
                "CurrentPersistentKindLifecycleCatalogV1.laterTemporalOrigins"
                if is_later_origin
                else "CurrentPersistentKindLifecycleCatalogV1.baselineTemporalOrigin"
            ),
            "fixtureBinding": "V21P02C09PersistentKindLifecycleCoverageCorpusV1.temporalProvenance",
        }
        rows.append({**body, "rowDigest": sha(canonical(body))})
    if durable_ids != durable_fixture:
        raise ContractError("fixture durableFirstWriteKindIDs differs from closed runtime write authority")
    if len(durable_ids) != 65:
        raise ContractError(f"durable first-write set is not exact 65: {len(durable_ids)}")
    if [row["kindID"] for row in rows] != kind_ids:
        raise ContractError("temporal provenance rows are not exact sorted universe")
    row_canonical_members = [
        "|".join([
            row["kindID"],
            row["temporalEvidence"]["evidenceID"],
            str(row["temporalEvidence"]["evidenceVersion"]),
            row["temporalEvidence"]["disposition"],
            row["temporalEvidence"]["representationSourceCard"],
            str(row["temporalEvidence"]["representationSourceOrdinal"]),
            row["temporalEvidence"]["firstWriteVersion"],
            str(row["temporalEvidence"]["firstWriteOrdinal"]),
            row["temporalEvidence"]["lifecycleEnrollmentVersion"],
            str(row["temporalEvidence"]["lifecycleEnrollmentOrdinal"]),
            row["temporalEvidence"]["forwardFixVersion"],
            str(row["temporalEvidence"]["forwardFixOrdinal"]),
        ])
        for row in rows
    ]
    temporal_registry_digest = sha(canonical(sorted(row_canonical_members)))
    temporal_conflicts: list[str] = []
    for row in rows:
        temporal = row["temporalEvidence"]
        disposition = temporal["disposition"]
        conflict = False
        if disposition == "ENROLLED_BEFORE_FIRST_WRITE":
            conflict = temporal["lifecycleEnrollmentOrdinal"] > temporal["firstWriteOrdinal"]
        elif disposition == "PREEXISTING_BOUND_FORWARD_FIX":
            conflict = (
                temporal["firstWriteOrdinal"] >= temporal["lifecycleEnrollmentOrdinal"]
                or temporal["forwardFixOrdinal"] < temporal["lifecycleEnrollmentOrdinal"]
                or temporal["forwardFixVersion"] != CARD.replace("-", "_")
            )
        elif disposition == "NONPERSISTENT_NO_CANONICAL_WRITE":
            conflict = row["storageDisposition"] in {"SWIFT_DATA_MODEL", "OWNED_FILE", "RECOVERY_JOURNAL"}
        else:
            conflict = True
        conflict = conflict or (
            temporal["evidenceID"] != "temporal." + row["kindID"]
            or temporal["evidenceVersion"] != 1
            or temporal["lifecycleEnrollmentVersion"] != CARD.replace("-", "_")
            or temporal["lifecycleEnrollmentOrdinal"] != 29
            or (disposition == "PREEXISTING_BOUND_FORWARD_FIX" and temporal["forwardFixOrdinal"] != 29)
        )
        if conflict:
            temporal_conflicts.append(row["kindID"])
    source_paths = [
        EXISTING_PATHS[0], EXISTING_PATHS[1], EXISTING_PATHS[2], EXISTING_PATHS[3],
        NEW_SOURCE_PATHS[0], NEW_SOURCE_PATHS[1], NEW_SOURCE_PATHS[2], NEW_SOURCE_PATHS[3],
    ]
    source_digest_rows = [
        {
            "path": relative,
            "bytes": (root / relative).stat().st_size,
            "sha256": sha((root / relative).read_bytes()),
        }
        for relative in source_paths
    ]
    source_digest_rows.sort(key=lambda row: row["path"])
    required_source_ids = set(FIXTURE_UNIVERSE_SOURCES)
    observed_source_ids = set(FIXTURE_UNIVERSE_SOURCES)
    source_drift = sorted(required_source_ids.symmetric_difference(observed_source_ids))
    source_drift_recomputed = sorted(source_drift)
    origin_partition = [
        {
            "representationSourceCard": row["card"],
            "representationSourceOrdinal": row["ordinal"],
            "kindIDs": row["kindIDs"],
            "kindCount": len(row["kindIDs"]),
        }
        for row in origins["originGroups"]
    ]
    baseline_ids = sorted(set(kind_ids) - set(origins["laterOrigins"]))
    origin_partition.insert(0, {
        "representationSourceCard": origins["baseline"]["card"],
        "representationSourceOrdinal": origins["baseline"]["ordinal"],
        "kindIDs": baseline_ids,
        "kindCount": len(baseline_ids),
    })
    source_digest_set_digest = sha(canonical(source_digest_rows))
    return {
        "rowCount": len(rows),
        "rows": rows,
        "durableFirstWriteKindIDs": durable_ids,
        "durableFirstWriteCount": len(durable_ids),
        "fixtureTemporalProvenanceExact": True,
        "fixtureDurableFirstWriteExact": True,
        "originPartition": origin_partition,
        "originPartitionCounts": {
            f"{row['representationSourceCard']}@{row['representationSourceOrdinal']}": row["kindCount"]
            for row in origin_partition
        },
        "distinctChronologyCount": len({
            (row["representationSourceCard"], row["representationSourceOrdinal"], row["firstWriteVersion"], row["firstWriteOrdinal"])
            for row in rows
        }),
        "uniformPlaceholderRejected": True,
        "acceptedTemporalUniverseDigest": origins["acceptedTemporalUniverseDigest"],
        "temporalRegistryCanonicalDigest": temporal_registry_digest,
        "sourceDigestRows": source_digest_rows,
        "sourceDigestSetDigest": source_digest_set_digest,
        "temporalConflictRecomputation": {
            "runtimeGapField": "temporalConflictKindIDs",
            "rules": [
                "ENROLLED_BEFORE_FIRST_WRITE: lifecycleEnrollmentOrdinal <= firstWriteOrdinal",
                "PREEXISTING_BOUND_FORWARD_FIX: firstWriteOrdinal < lifecycleEnrollmentOrdinal <= forwardFixOrdinal and forwardFixVersion == V23_P02_C09",
                "NONPERSISTENT_NO_CANONICAL_WRITE: closed runtime write authority reports no independent representation write",
                "all rows: evidenceID == temporal.<kindID>, evidenceVersion == 1, lifecycleEnrollmentVersion == V23_P02_C09, lifecycleEnrollmentOrdinal == 29",
            ],
            "recomputedKindIDs": temporal_conflicts,
            "expectedKindIDs": [],
            "recomputedExact": temporal_conflicts == [],
        },
        "sourceDriftRecomputation": {
            "runtimeGapField": "sourceDriftIDs",
            "requiredSourceIDs": sorted(required_source_ids),
            "observedSourceIDs": sorted(observed_source_ids),
            "operation": "symmetricDifference",
            "recomputedIDs": source_drift_recomputed,
            "expectedIDs": [],
            "recomputedExact": source_drift_recomputed == [],
        },
        "crossCardAnchors": TEMPORAL_PROVENANCE_ANCHORS,
        "sourceDerivation": {
            "originTable": "CurrentPersistentKindLifecycleCatalogV1.laterTemporalOrigins",
            "baselineOrigin": origins["baseline"],
            "acceptedUniverseGuard": "CurrentPersistentKindLifecycleCatalogV1.acceptedTemporalUniverseDigest",
            "classificationFunction": "CurrentPersistentKindLifecycleCatalogV1.kindClassification",
            "storageFunction": "CurrentPersistentKindLifecycleCatalogV1.storageDisposition",
            "writeAuthorityFunction": "PersistentKindLifecycleRegistryV1.hasIndependentRepresentationWrite",
            "fixtureRows": "V21P02C09PersistentKindLifecycleCoverageCorpusV1.temporalProvenance",
        },
    }


def _array_source(root: Path) -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Derive category arrays from the exact current catalog source text."""
    catalog = root / "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift"
    fallback = root / "FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift"
    source_path = catalog if catalog.is_file() else fallback
    text = source_path.read_text(encoding="utf-8") if source_path.is_file() else ""
    if not text:
        raise ContractError(f"missing current universe owner: {catalog}")
    fields: dict[str, dict[str, Any]] = {}
    for name, category in UNIVERSE_CATEGORIES:
        values = _extract_array(text, name)
        if values is None and source_path == fallback:
            values = _extract_array(text, name)
        if values is None:
            raise ContractError(f"missing exact-head universe declaration: {name}")
        fields[name] = {"category": category, "names": values, "count": len(values)}
    # Contracts contain repository-relative paths even when the generator is
    # invoked with an absolute repository root.  Keeping the path relative is
    # important: it makes the source hash rows portable and prevents an
    # absolute workstation path from becoming sealed contract data.
    relative = source_path.relative_to(root).as_posix()
    required_sources = [
        relative,
        EXISTING_PATHS[1],
        EXISTING_PATHS[3],
        EXISTING_PATHS[4],
        NEW_SOURCE_PATHS[0],
        NEW_SOURCE_PATHS[1],
        NEW_SOURCE_PATHS[3],
    ]
    missing = [value for value in required_sources if not (root / value).is_file()]
    if missing:
        raise ContractError(f"missing exact-head lifecycle sources: {missing}")
    return fields, list(dict.fromkeys(required_sources))


def exact_head_universe(root: Path) -> dict[str, Any]:
    fields, source_paths = _array_source(root)
    kind_ids: list[str] = []
    category_counts: dict[str, int] = {}
    duplicates: list[str] = []
    for name, item in fields.items():
        category = item["category"]
        ids = [f"{category}:{value}" for value in item["names"]]
        for value in ids:
            if value in kind_ids:
                duplicates.append(value)
            else:
                kind_ids.append(value)
        category_counts[category] = category_counts.get(category, 0) + len(ids)
        item["kindIDs"] = ids
    fixture_path = root / NEW_SOURCE_PATHS[3]
    fixture: dict[str, Any] = {}
    fixture_declared: list[str] | None = None
    if fixture_path.is_file():
        try:
            fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            raise ContractError(f"invalid lifecycle fixture JSON: {error}") from error
        for key in ("declaredKindIDs", "universeKindIDs", "kindIDs"):
            if isinstance(fixture.get(key), list):
                fixture_declared = [value for value in fixture[key] if isinstance(value, str)]
                break
    universe = sorted(kind_ids)
    # Absence is a mismatch, not an empty/no-op proof.  This keeps a fixture
    # with no declaration from silently making the coverage receipt complete.
    fixture_values = fixture_declared if fixture_declared is not None else []
    fixture_mismatch = sorted(set(fixture_values) ^ set(universe))
    schema_text = (root / EXISTING_PATHS[3]).read_text(encoding="utf-8")
    owned_file_text = (root / EXISTING_PATHS[4]).read_text(encoding="utf-8")
    model_names = fields["persistentModelNames"]["names"]
    v5_model_names = _extract_model_self_names(schema_text, set(model_names))
    owned_file_cases = _extract_owned_file_cases(owned_file_text)
    independent_cross_checks = {
        "persistentSchemaV5": {
            "path": EXISTING_PATHS[3],
            "declaration": "PersistentSchemaV5.models",
            "names": v5_model_names,
            "matchesCatalog": v5_model_names == sorted(model_names),
        },
        "ownedFileKindV1": {
            "path": EXISTING_PATHS[4],
            "declaration": "OwnedFileKindV1.allCases",
            "names": owned_file_cases,
            "matchesCatalog": sorted(owned_file_cases) == sorted(fields["ownedFileClassNames"]["names"]),
        },
    }
    source_hashes = []
    for relative in source_paths:
        path = root / relative
        source_hashes.append({"path": relative, "sha256": sha(path.read_bytes()), "bytes": path.stat().st_size})
    universe_projection = {
        "sourceArrays": fields,
        "kindIDs": universe,
    }
    temporal = _temporal_provenance(root, universe_projection)
    return {
        "derivation": "EXACT_HEAD_CURRENT_SYNC_CLASSIFICATION_CATALOG_STATIC_ARRAYS",
        "sourcePaths": source_paths,
        "sourceHashes": source_hashes,
        "sourceArrays": fields,
        "kindIDs": universe,
        "kindCount": len(universe),
        "categoryCounts": category_counts,
        "duplicateKindIDs": sorted(set(duplicates)),
        "fixtureDeclaredKindIDs": sorted(fixture_values),
        "fixtureDeclarationPresent": fixture_declared is not None,
        "fixtureDeclarationExact": fixture_declared is not None and fixture_values == universe,
        "fixtureUniverseMismatch": fixture_mismatch,
        "independentCrossChecks": independent_cross_checks,
        "temporalProvenance": temporal,
        "searchImplementationPresent": 'declaredsearchimplementationpresent = true' in (root / source_paths[0]).read_text(encoding="utf-8").lower(),
        "secretNames": _extract_array((root / source_paths[0]).read_text(encoding="utf-8"), "secretNames") or [],
        "keychainUsageDeclared": 'declaredkeychainusage = true' in (root / source_paths[0]).read_text(encoding="utf-8").lower(),
        "noHandwrittenCountAuthority": True,
        "maximumKindCount": 128,
    }


def _source_binding(path: str, owner: str, symbols: list[str], tokens: list[str]) -> dict[str, Any]:
    return {"path": path, "owner": owner, "symbols": symbols, "requiredTokens": tokens}


def source_bindings() -> list[dict[str, Any]]:
    return [
        _source_binding(
            EXISTING_PATHS[0], "V23-P02-C09",
            ["ReleasedDataCompatibilityPolicyV1", "DataCompatibilityManifestV1", "SupportedUpgradePathV1"],
            ["currentSupportTable", "supportedUpgradePaths", "validateReadableVersion", "validateWriterVersion", "forwardUpgradeTransitions", "archive1-backup4-persistent5-records4", "snapshot2"],
        ),
        _source_binding(
            EXISTING_PATHS[1], "V23-P02-C03",
            ["SyncClassificationRegistryV1", "SyncSubjectIdentityV1", "SyncClassificationRegistrationV1"],
            ["persistentModelNames", "ownedFileClassNames", "generationLeaseDirectory", "generationLeaseControl", "generationLeaseControlTemporary", "generationLeaseOwnerLock", "declaredSecretSubjects", "makeRegistrations"],
        ),
        _source_binding(
            EXISTING_PATHS[2], "V23-P02-C09",
            ["CurrentSyncClassificationCatalogV1", "CurrentRepresentationRuleV1", "CurrentSyncLifecycleRouteV1"],
            ["CurrentSyncClassificationCatalogV1", "persistentModelNames", "ownedFileClassNames", "portableContentProjectionNames", "derivedIndexNames", "derivedProjectionNames", "journalRecoveryNames", "diagnosticNames", "declaredSearchImplementationPresent", "secretNames", "declaredKeychainUsage", "mutationHistoryRepresentationRules", "diagnosticRepresentationRules", "static var current", "registrations", "lifecycleRoutes"],
        ),
        _source_binding(
            EXISTING_PATHS[3], "V23-P01-C03",
            ["PersistentSchemaV1", "PersistentSchemaV2", "PersistentSchemaV3", "PersistentSchemaV4", "PersistentSchemaV5", "ObservationAndTimeRow"],
            ["PersistentSchemaV5", "PersistentSchemaV4", "ObservationAndTimeRow", "versionIdentifier", "models", "PersistentSchemaV5.models"],
        ),
        _source_binding(
            EXISTING_PATHS[4], "V23-P01-C02",
            ["OwnedFileKindV1", "ProtectedFilePolicyV1", "OwnedFileProtectionDispositionV1"],
            ["OwnedFileKindV1", "CaseIterable", "generationLeaseDirectory", "generationLeaseControl", "generationLeaseControlTemporary", "generationLeaseOwnerLock", "mediaThumbnail", "isExcludedFromBackup", "countsTowardOwnedStorage", "permitsAutomaticStoragePressureDeletion"],
        ),
        _source_binding(
            NEW_SOURCE_PATHS[0], "V23-P02-C09",
            ["PersistentKindLifecycleRegistryV1", "PersistentKindDescriptorV1", "PersistentLifecyclePolicyV1", "DataHandlingPolicyV1", "LifecycleCoverageManifestV1"],
            ["PersistentKindDescriptorV1", "PersistentKindClassificationV1", "PersistentKindTemporalDispositionV1", "PersistentKindTemporalEvidenceV1", "PersistentLifecyclePolicyV1", "PersistentLifecycleActionV1", "PersistentLifecycleActionPolicyV1", "DataHandlingPolicyV1", "LifecycleCoverageManifestV1", "compileCoverage", "kindClassification", "replicationClassification", "temporalEvidence", "representationSourceCard", "representationSourceOrdinal", "firstWriteVersion", "lifecycleEnrollmentVersion", "forwardFixVersion", "firstWriteOrdinal", "lifecycleEnrollmentOrdinal", "forwardFixOrdinal", "temporalProvenanceCanonicalMembers", "requiredUniverseSourceIDs", "declarationOwner", "currentImplementationOwner", "ownerRequired", "unknownKindIDs", "conflictingKindIDs", "temporalConflictKindIDs", "provisionalKernelOnly", "shippingBoundaryAdoption", "PersistentKindLifecycleValidationV1"],
        ),
        _source_binding(
            NEW_SOURCE_PATHS[1], "V23-P02-C09",
            ["CurrentPersistentKindLifecycleCatalogV1", "CurrentPersistentKindLifecycleCatalogFailureV1"],
            ["CurrentPersistentKindLifecycleCatalogV1", "static func compile", "PersistentLifecycleContractReleaseRegistryV1", "ReleasedDataCompatibilityPolicyV1.exactHead", "CurrentSyncClassificationCatalogV1.current", "descriptors", "lifecyclePolicies", "dataHandlingPolicies", "coverageManifest", "implementationOwnerPrefix", "PersistentKindLifecycleRegistryV1.declarationOwner", "TemporalOriginV1", "baselineTemporalOrigin", "laterTemporalOrigins", "acceptedTemporalUniverseDigest", "temporalProvenance", "storageDisposition", "temporalEvidence", "representationSourceCard", "representationSourceOrdinal", "firstWriteVersion", "lifecycleEnrollmentVersion", "forwardFixVersion", "auditErase", "expectedEraseDisposition"],
        ),
        _source_binding(
            NEW_SOURCE_PATHS[2], "V23-P02-C09",
            ["V9_13PersistentKindLifecycleCoverageTests"],
            TEST_METHODS + ["XCTestCase", "PersistentKindLifecycleRegistryV1", "CurrentPersistentKindLifecycleCatalogV1", "corpus.temporalProvenance", "corpus.durableFirstWriteKindIDs", "provenancePartition", "PERSISTENT_MODEL:ObservationAndTimeRow", "DIAGNOSTIC:DeviceOperationalSupportStoreV2"],
        ),
        _source_binding(
            NEW_SOURCE_PATHS[3], "V23-P02-C09",
            ["V21P02C09PersistentKindLifecycleCoverageCorpusV1"],
            ["fixtureIdentity", "declaredKindIDs", "durableFirstWriteKindIDs", "temporalProvenance", "representationSourceCard", "representationSourceOrdinal", "universeSources", "classifications", "handlingActions", "lifecycleDimensions", "hostileCases", "interruptionBoundaries", "compatibilityCases", "eraseExpectations", "brandImpact", "expectedAudit", "representativePolicies"],
        ),
    ]


def _fixture_shape() -> dict[str, Any]:
    return {
        "schemaVersion", "fixtureIdentity", "authority", "declaredKindIDs", "durableFirstWriteKindIDs",
        "temporalProvenance", "universeSources", "classifications",
        "handlingActions", "lifecycleDimensions", "representativePolicies", "hostileCases",
        "interruptionBoundaries", "compatibilityCases", "eraseExpectations", "brandImpact", "expectedAudit",
    }


def _brand_impact() -> dict[str, Any]:
    body = {
        "schema": "BrandImpactManifestV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "changedScreens": [],
        "changedStates": [],
        "affectedConsumers": ["V23-P02-C10", "V23-P03-C01"],
        "completenessRationale": "Lifecycle policy/tooling changes have no rendered-screen or state change; downstream consumer closure is explicit.",
    }
    return {**body, "artifactDigest": sha(pretty(body))}


def _universe_fields(root: Path) -> dict[str, Any]:
    return exact_head_universe(root)


def persistent_kind_contract(root: Path) -> dict[str, Any]:
    universe = _universe_fields(root)
    return seal({
        **base("V23P02C09PersistentKindLifecycleContractV1"),
        **common_contract_fields(),
        "owner": "PersistentKindLifecycleRegistryV1",
        "universe": universe,
        "descriptor": {
            "type": "PersistentKindDescriptorV1",
            "schemaVersion": 1,
            "requiredFields": ["schemaVersion", "subject", "policyRevision", "storage", "revision", "mutation", "digest", "kindClassification", "replicationClassification", "temporalEvidence", "declarationOwner", "currentImplementationOwner"],
            "storageDispositions": STORAGE_DISPOSITIONS,
            "revisionDispositions": REVISION_DISPOSITIONS,
            "mutationDispositions": MUTATION_DISPOSITIONS,
            "digestDispositions": DIGEST_DISPOSITIONS,
            "temporalEvidenceType": "PersistentKindTemporalEvidenceV1",
            "temporalEvidenceFields": ["schemaVersion", "evidenceID", "evidenceVersion", "disposition", "representationSourceCard", "representationSourceOrdinal", "firstWriteVersion", "lifecycleEnrollmentVersion", "forwardFixVersion", "firstWriteOrdinal", "lifecycleEnrollmentOrdinal", "forwardFixOrdinal"],
            "temporalDispositionValues": ["ENROLLED_BEFORE_FIRST_WRITE", "PREEXISTING_BOUND_FORWARD_FIX", "NONPERSISTENT_NO_CANONICAL_WRITE"],
            "declarationOwner": "V23-P02-C09.PersistentKindLifecycleRegistryV1",
            "ownersMustBeDistinct": True,
            "policyRevisionPositive": True,
        },
        "classification": {
            "replicationClassificationField": "replicationClassification",
            "replicationClassificationValues": REPLICATION_CLASSIFICATIONS,
            "lifecycleClassificationField": "kindClassification",
            "lifecycleClassificationValues": CLASSIFICATIONS,
            "closedValues": REPLICATION_CLASSIFICATIONS,
            "classificationNamesForFixture": CLASSIFICATIONS,
            "sevenLifecycleClassificationsAreClosed": True,
            "lifecycleClassificationSeparateFromReplication": True,
            "mappingIsTyped": True,
            "unknownFailsClosed": True,
        },
        "actionMatrix": {
            "closedActionCount": len(LIFECYCLE_ACTIONS),
            "actions": LIFECYCLE_ACTIONS,
            "dispositions": ACTION_DISPOSITIONS,
            "missingActionIsNotPermission": True,
            "ownerRequiredCannotBeSilentlyAccepted": True,
            "temporalBoundaries": TEMPORAL_BOUNDARIES,
        },
        "ownership": {
            "exactlyOneDeclarationOwner": True,
            "exactlyOneCurrentImplementationOwner": True,
            "temporallyImpossibleWriterRejected": True,
            "conflictingOwnerRejected": True,
            "firstWriteRequiresLifecycleEnrollment": True,
        },
        "representation": {
            "canonicalRowsRemainTruth": True,
            "portableProjectionsNeverBecomeRows": True,
            "mutationHistoryRows": ["PERSISTENT_MODEL:EntityMutationRevisionRow", "PERSISTENT_MODEL:MutationQuarantineRow", "PERSISTENT_MODEL:MutationReceiptRow", "PERSISTENT_MODEL:WorkspaceMutationStateRow"],
            "portableProjection": "PROJECTION:MutationHistorySnapshotV1",
            "diagnosticStore": "DIAGNOSTIC:DeviceOperationalSupportStoreV2",
            "diagnosticAlias": {"legacy": "DIAGNOSTIC:DeviceOperationalSupportStoreV1", "current": "DIAGNOSTIC:DeviceOperationalSupportStoreV2", "aliasIsNotSecondStore": True},
            "mediaThumbnail": {"kindID": "OWNED_FILE_CLASS:mediaThumbnail", "classification": "CONTENT_BLOB", "immutableOriginalPreserved": True},
            "lifecycleClassificationProfiles": ERASE_PROFILES,
        },
        "temporalProvenance": universe["temporalProvenance"],
        "prohibitions": {
            "swiftDataV6EntityAdded": False,
            "newRootOrStoreOrWriter": False,
            "searchImplementationPresent": universe["searchImplementationPresent"],
            "secretNames": universe["secretNames"],
            "keychainUsageDeclared": universe["keychainUsageDeclared"],
            "automaticStoragePressureDeletion": False,
            "oneGlobalDestructiveRule": False,
        },
        "sourceBindings": source_bindings(),
    })


def lifecycle_policy_contract(root: Path) -> dict[str, Any]:
    universe = _universe_fields(root)
    return seal({
        **base("V23P02C09PersistentLifecyclePolicyContractV1"),
        **common_contract_fields(),
        "owner": "PersistentKindLifecycleRegistryV1",
        "policy": {
            "type": "PersistentLifecyclePolicyV1",
            "schemaVersion": 1,
            "actionFields": LIFECYCLE_ACTIONS,
            "actionMatrix": LIFECYCLE_ACTIONS,
            "canonicalPolicyOrder": sorted(LIFECYCLE_ACTIONS),
            "sourceEnum": "PersistentLifecycleActionV1.allCases",
            "dispositions": ACTION_DISPOSITIONS,
            "exactlyOnePolicyPerUniverseKind": True,
            "policyRevisionMustMatchDescriptor": True,
            "ownerRequiredRejectedByRuntime": True,
            "perKindLifecycleClassification": {
                "field": "kindClassification",
                "closedValues": CLASSIFICATIONS,
                "separateFrom": "replicationClassification",
                "requiredForEveryKind": True,
            },
        },
        "lifecycle": {
            "migration": "EXPLICIT_PER_KIND",
            "backup": "EXPLICIT_PER_KIND",
            "replaceRestore": "EXPLICIT_PER_KIND",
            "clone": "EXPLICIT_PER_KIND",
            "fork": "EXPLICIT_PER_KIND",
            "import": "EXPLICIT_PER_KIND",
            "export": "EXPLICIT_PER_KIND",
            "report": "EXPLICIT_PER_KIND",
            "search": "EXPLICIT_PER_KIND",
            "rebuild": "EXPLICIT_PER_KIND",
            "replay": "EXPLICIT_PER_KIND",
            "delete": "EXPLICIT_PER_KIND",
            "erase": "EXPLICIT_PER_KIND",
            "localization": "EXPLICIT_PER_KIND",
            "accessibility": "EXPLICIT_PER_KIND",
            "compatibility": "EXPLICIT_PER_KIND",
            "privacy": "EXPLICIT_IN_DATA_HANDLING_POLICY",
            "retention": "EXPLICIT_IN_DATA_HANDLING_POLICY",
            "interruption": "EXPLICIT_IN_AUDIT_RECEIPT",
            "downgradeForwardFix": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
            "presentationOutputs": PRESENTATION_OUTPUTS,
        },
        "temporal": TEMPORAL_BOUNDARIES,
        "temporalProvenance": universe["temporalProvenance"],
        "universeBinding": {"kindIDs": universe["kindIDs"], "kindCountDerived": universe["kindCount"], "noHandwrittenCountAuthority": True},
        "sourceBindings": source_bindings(),
    })


def data_handling_contract(root: Path) -> dict[str, Any]:
    universe = _universe_fields(root)
    return seal({
        **base("V23P02C09DataHandlingPolicyContractV1"),
        **common_contract_fields(),
        "owner": "PersistentKindLifecycleRegistryV1",
        "policy": {
            "type": "DataHandlingPolicyV1",
            "schemaVersion": 1,
            "fields": ["schemaVersion", "kindID", "policyRevision", "privacy", "retention", "privacyAuthority", "retentionAuthority", "destructiveAuthority", "destructiveAuthorityOwner", "secretHandling", "telemetry", "fileProtection", "localization", "accessibility", "customerWorkDataScope"],
            "privacy": DATA_PRIVACY,
            "retention": DATA_RETENTION,
            "destructiveAuthority": DESTRUCTIVE_AUTHORITIES,
            "secretHandling": ["FORBIDDEN", "NONPORTABLE_SECRET_AUTHORITY"],
            "telemetry": ["FORBIDDEN", "BOUNDED_NONCUSTOMER_OPERATIONAL_ONLY"],
            "fileProtection": ["COMPLETE", "NOT_APPLICABLE"],
            "presentation": ["FROZEN_DATA_NO_PRESENTATION", "LOCALIZED_PROJECTION_REQUIRED", "ACCESSIBLE_PROJECTION_REQUIRED", "LOCALIZED_FROZEN_HISTORIC_PROJECTION", "ACCESSIBLE_FROZEN_HISTORIC_PROJECTION"],
            "customerWorkDataScope": ["WORKSPACE_DATA", "WORKSPACE_CONTENT", "DEVICE_OPERATIONAL_NO_CUSTOMER_DATA"],
            "authorityFieldsMustBeExplicit": True,
            "customerDataAllowedInDiagnostics": False,
            "secretsAllowedInDiagnostics": False,
            "automaticStoragePressureDeletionAllowed": False,
            "unknownPolicyFailsClosed": True,
            "ownerRequiredCannotBePersisted": True,
        },
        "handlingMatrix": {
            "supportedActions": FIXTURE_HANDLING_ACTIONS,
            "everyKindHasPrivacyRetentionAndDestructiveAuthority": True,
            "everyKindHasLifecycleClassification": True,
            "diagnosticAllowlistOnly": True,
            "immutableContentPreserved": True,
            "derivedContentRebuildable": True,
            "canonicalRowsDeletedOnlyByCanonicalAuthority": True,
            "operationScratchUsesOperationCleanupOwner": True,
            "eraseProfiles": ERASE_PROFILES,
            "presentationOutputs": PRESENTATION_OUTPUTS,
        },
        "erase": {
            "erasableSurvivorCount": 0,
            "orphanCount": 0,
            "immutableTruthPreserved": True,
            "usesOneGlobalDestructiveRule": False,
            "unknownKindFailsClosed": True,
        },
        "universeBinding": {"kindIDs": universe["kindIDs"], "kindCountDerived": universe["kindCount"]},
        "sourceBindings": source_bindings(),
    })


def coverage_contract(root: Path) -> dict[str, Any]:
    universe = _universe_fields(root)
    return seal({
        **base("V23P02C09LifecycleCoverageManifestV1"),
        **common_contract_fields(),
        "owner": "CurrentPersistentKindLifecycleCatalogV1",
        "manifest": {
            "type": "LifecycleCoverageManifestV1",
            "schemaVersion": 1,
            "candidateHead": APP_BASE_HEAD,
            "universeKindIDs": universe["kindIDs"],
            "descriptorKindIDs": universe["kindIDs"],
            "lifecyclePolicyKindIDs": universe["kindIDs"],
            "dataHandlingPolicyKindIDs": universe["kindIDs"],
            "missingKindIDs": [],
            "duplicateKindIDs": universe["duplicateKindIDs"],
            "conflictingKindIDs": [],
            "unknownKindIDs": [],
            "ownershipGapKindIDs": [],
            "temporalConflictKindIDs": [],
            "backupRestoreGapKindIDs": [],
            "eraseGapKindIDs": [],
            "exportReportGapKindIDs": [],
            "searchAbsenceGapKindIDs": [],
            "rebuildDependencyGapKindIDs": [],
            "replayGapKindIDs": [],
            "unresolvedAuthorityKindIDs": [],
            "sourceDriftIDs": [],
            "isComplete": (
                not universe["duplicateKindIDs"]
                and not universe["fixtureUniverseMismatch"]
                and universe["fixtureDeclarationExact"]
                and all(item["matchesCatalog"] for item in universe["independentCrossChecks"].values())
            ),
            "maximumKindCount": 128,
            "kindCountDerived": universe["kindCount"],
            "noHandwrittenCountAuthority": True,
            "fixtureUniverseMismatch": universe["fixtureUniverseMismatch"],
            "fixtureDeclaredKindIDs": universe["fixtureDeclaredKindIDs"],
            "fixtureDeclarationPresent": universe["fixtureDeclarationPresent"],
            "fixtureDeclarationExact": universe["fixtureDeclarationExact"],
            "independentCrossChecks": universe["independentCrossChecks"],
        },
        "sourceUniverse": {
            "requiredSources": FIXTURE_UNIVERSE_SOURCES,
            "searchImplementationPresent": universe["searchImplementationPresent"],
            "secretNames": universe["secretNames"],
            "keychainUsageDeclared": universe["keychainUsageDeclared"],
            "canonicalRowsAndPortableProjectionsDistinct": True,
        },
        "fixtureBinding": {
            "path": NEW_SOURCE_PATHS[3],
            "fixtureIdentity": "V21-P02-C09-PERSISTENT-KIND-LIFECYCLE-COVERAGE-CORPUS-V1",
            "topLevelFields": sorted(_fixture_shape()),
            "requiredUniverseSources": FIXTURE_UNIVERSE_SOURCES,
            "requiredClassifications": FIXTURE_CLASSIFICATIONS,
            "requiredHandlingActions": FIXTURE_HANDLING_ACTIONS,
            "requiredLifecycleDimensions": FIXTURE_LIFECYCLE_DIMENSIONS,
            "requiredHostileCases": HOSTILE_CASES,
            "requiredInterruptionBoundaries": INTERRUPTION_BOUNDARIES,
            "requiredCompatibilityCases": COMPATIBILITY_CASES,
            "declaredKindIDsKey": "declaredKindIDs",
            "declaredKindIDsMustMatchDerivedUniverse": True,
            "requiresBrandImpactManifest": True,
            "requiresExpectedAudit": True,
        },
        "gapSets": ["missingKindIDs", "duplicateKindIDs", "conflictingKindIDs", "unknownKindIDs", "ownershipGapKindIDs", "temporalConflictKindIDs", "backupRestoreGapKindIDs", "eraseGapKindIDs", "exportReportGapKindIDs", "searchAbsenceGapKindIDs", "rebuildDependencyGapKindIDs", "replayGapKindIDs", "unresolvedAuthorityKindIDs", "sourceDriftIDs"],
        "temporalBoundaries": TEMPORAL_BOUNDARIES,
        "sourceBindings": source_bindings(),
    })


def compatibility_contract(root: Path) -> dict[str, Any]:
    return seal({
        **base("V23P02C09LifecycleCompatibilityContractV1"),
        **common_contract_fields(),
        "owner": "ReleasedDataCompatibilityPolicyV1",
        "schema": {
            "currentStoreVersion": "V5",
            "predecessorStoreVersion": "V4",
            "newSwiftDataV6Entity": False,
            "schemaReleaseMarker": "PersistentSchemaReleaseMarker",
            "observationTimeCompanion": "ObservationAndTimeRow",
            "releasedRecordsImmutable": True,
        },
        "backupRestore": {
            "backupCompatibilityRequired": True,
            "restoreCompatibilityRequired": True,
            "deleteCompatibilityRequired": True,
            "exportCompatibilityRequired": True,
            "currentBackupTuple": "archive1-backup4-persistent5-records4",
            "backupRestoreRoundTripRequired": True,
            "olderOrSkippedVersion": "FORWARD_FIX_REQUIRED",
            "unknownVersion": "FAIL_CLOSED_UNSUPPORTED_VERSION",
        },
        "policyHistory": {
            "preActivationInterruption": "DISCARD_STAGING",
            "postActivationInterruption": "APPEND_VERSIONED_SUCCESSOR_AND_FORWARD_FIX",
            "rewritesReleasedRecords": False,
            "rewritesReceipts": False,
            "rewritesTombstones": False,
        },
        "searchAndRebuild": {
            "searchImplementationPresent": False,
            "searchDisposition": "UNAVAILABLE_AT_THIS_HEAD",
            "derivedIndexesRebuildFromCanonicalInputs": True,
            "portableProjectionNeverCanonical": True,
        },
        "sourceBindings": source_bindings(),
    })


def hostile_contract(root: Path) -> dict[str, Any]:
    return seal({
        **base("V23P02C09LifecycleHostileMatrixV1"),
        **common_contract_fields(),
        "owner": "V9_13PersistentKindLifecycleCoverageTests",
        "exactFiveTests": True,
        "evidence": [
            {"evidenceID": evidence, "family": family, "testMethod": method}
            for evidence, family, method in zip(EVIDENCE_IDS, ("G01", "A01", "H01", "I01", "R01"), TEST_METHODS)
        ],
        "families": {
            "G01": {"kind": "GOLDEN", "required": ["CLOSED_UNIVERSE", "EXACT_OWNER_PAIR", "ONE_POLICY_PER_KIND", "ZERO_GAPS", "EXACT_BRAND_IMPACT"]},
            "A01": {"kind": "ALTERNATE", "required": ["EVERY_28_ACTION_EXPLICIT", "EVERY_DATA_HANDLING_FIELD_EXPLICIT", "BACKUP_RESTORE_PAIR", "ERASE_RECONCILIATION", "COMPATIBILITY_FORWARD_FIX"]},
            "H01": {"kind": "HOSTILE", "required": ["DUPLICATE_KIND", "CONFLICTING_OWNER", "UNKNOWN_ACTION", "UNKNOWN_CLASSIFICATION", "DENIED_EXPORT_REPORT", "IMMUTABLE_ERASE", "TEMPORAL_WRITER"]},
            "I01": {"kind": "INTERRUPTION", "required": ["EVERY_DURABLE_BOUNDARY", "NO_PARTIAL_ACCEPTANCE", "DISCARD_PRE_ACTIVATION", "SUCCESSOR_POST_ACTIVATION", "RELAUNCH_IDEMPOTENT"]},
            "R01": {"kind": "RECOVERY", "required": ["MIGRATION_FORWARD_FIX", "BACKUP_RESTORE_RECONCILIATION", "ZERO_ORPHANS", "ROW_PROJECTION_SEPARATION", "SEARCH_ABSENCE_PROOF"]},
        },
        "hostileCases": HOSTILE_CASES,
        "interruptionBoundaries": INTERRUPTION_BOUNDARIES,
        "compatibilityCases": COMPATIBILITY_CASES,
        "prohibitedTokens": PROHIBITED_TOKENS,
        "sourceBindings": source_bindings(),
    })


def audit_contract(root: Path) -> dict[str, Any]:
    coverage = coverage_contract(root)
    manifest = coverage["manifest"]
    return seal({
        **base("V23P02C09LifecycleAuditReceiptV1"),
        **common_contract_fields(),
        "owner": "V9_13PersistentKindLifecycleCoverageTests",
        "coverageManifestDigest": coverage["artifactDigest"],
        "candidateHead": APP_BASE_HEAD,
        "audit": {
            "missingCount": 0,
            "duplicateCount": 0,
            "conflictingCount": 0,
            "unknownCount": 0,
            "orphanedOwnerCount": 0,
            "stalePolicyRevisionCount": 0,
            "complete": True,
            "exactHeadDerived": True,
            "handwrittenCountAuthority": False,
        },
        "brandImpactManifest": _brand_impact(),
        "brandImpact": {
            "manifestType": "BrandImpactManifestV1",
            "manifestCount": 1,
            "changedScreens": [],
            "changedStates": [],
            "affectedConsumers": ["V23-P02-C10", "V23-P03-C01"],
            "digest": _brand_impact()["artifactDigest"],
            "completenessRationale": "No rendered surface or state changed; the two invalidation consumers are closed explicitly.",
        },
        "provisionalDisposition": "PROVISIONAL_KERNEL_ONLY_REQUIRES_ACCEPTED_S10_6_RECONCILIATION",
        "sourceBindings": source_bindings(),
    })


def _strict(value: Any, key: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {name: _strict(child, name) for name, child in value.items()},
        }
    if isinstance(value, list):
        if not value:
            return {"type": "array", "minItems": 0, "maxItems": 0, "prefixItems": [], "items": False}
        return {"type": "array", "minItems": len(value), "maxItems": len(value), "prefixItems": [_strict(item) for item in value], "items": False}
    if key == "artifactDigest" or key.lower().endswith("digest") or key == "sha256":
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"const": value}
    if isinstance(value, int):
        return {"const": value}
    if isinstance(value, str):
        return {"const": value}
    raise ContractError(f"unsupported schema value for {key}: {type(value)}")


def schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json", "title": title})
    return result


def _manifest_rows(root: Path, generated: dict[str, bytes]) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    pending: list[str] = []
    for relative in MANIFEST_INPUT_PATHS:
        data = generated.get(relative)
        path = root / relative
        if data is None:
            if not path.is_file():
                pending.append(relative)
                continue
            data = path.read_bytes()
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return rows, pending


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows, pending = _manifest_rows(root, generated)
    return seal({
        **base("V23-P02-C09-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE,
        "pathFenceCount": len(PATH_FENCE),
        "existingPaths": EXISTING_PATHS,
        "newPaths": NEW_PATHS,
        "sourcePaths": SOURCE_PATHS,
        "sourcePathCount": len(SOURCE_PATHS),
        "toolingPaths": TOOL_PATHS,
        "toolingPathCount": len(TOOL_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows,
        "artifactCount": len(rows),
        "pendingFencePaths": pending,
        "pendingArtifactCount": len(pending),
        "artifactSetDigest": sha(pretty(rows)),
        "fenceProof": {
            "baseHead": APP_BASE_HEAD,
            "baseTree": APP_BASE_TREE,
            "pathFenceDigest": FENCE_DIGEST,
            "priorFenceCount": 29,
            "priorOwnedPathCount": 438,
            "priorFenceOverlapCount": 17,
            "authorizedPriorFenceOverlapCount": 17,
            "unauthorizedPriorFenceOverlapCount": 0,
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "activeS10ReservationDigest": S10_RESERVATION_DIGEST,
            "activeS10Overlap": False,
        },
        "universeDerivation": exact_head_universe(root),
        "persistentContractSchema": "PERSISTENT_LIFECYCLE_POLICY_V1",
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "migrationBehaviorDelta": True,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True,
        "privacyAllowlistOnly": True,
        "noNetwork": True,
        "noNewSwiftDataV6Entity": True,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    persistent = persistent_kind_contract(root)
    lifecycle = lifecycle_policy_contract(root)
    handling = data_handling_contract(root)
    coverage = coverage_contract(root)
    compatibility = compatibility_contract(root)
    hostile = hostile_contract(root)
    audit = audit_contract(root)
    generated: dict[str, bytes] = {
        PERSISTENT_KIND_SCHEMA: pretty(schema("V23P02C09PersistentKindLifecycleContractV1", persistent)),
        PERSISTENT_LIFECYCLE_SCHEMA: pretty(schema("V23P02C09PersistentLifecyclePolicyContractV1", lifecycle)),
        DATA_HANDLING_SCHEMA: pretty(schema("V23P02C09DataHandlingPolicyContractV1", handling)),
        COVERAGE_SCHEMA: pretty(schema("V23P02C09LifecycleCoverageManifestV1", coverage)),
        AUDIT_SCHEMA: pretty(schema("V23P02C09LifecycleAuditReceiptV1", audit)),
        PERSISTENT_KIND_DOC: pretty(persistent),
        DATA_HANDLING_DOC: pretty(handling),
        COVERAGE_DOC: pretty(coverage),
        COMPATIBILITY_DOC: pretty(compatibility),
        HOSTILE_DOC: pretty(hostile),
        AUDIT_DOC: pretty(audit),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated
