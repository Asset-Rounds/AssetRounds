#!/usr/bin/env python3
"""Deterministic Card 30 settings/capability tooling contracts.

The Card 30 contract is deliberately generated from the nine exact source,
resource, test, and fixture inputs in ``PATH_FENCE``.  The values below are
the closed policy vocabularies from the frozen V23 plan; the source scanners
then require the implementation and fixture to bind those vocabularies.  A
missing input is represented as pending while the tooling slice is hydrated,
but the hostile verifier refuses a pending final receipt.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Iterable

import sys

sys.dont_write_bytecode = True

CARD = "V23-P02-C10"
ORDINAL = 30
TITLE = "Typed settings, permissions, capability availability, fallback, privacy, and scratch-data lifecycle boundary"
GENERATOR_VERSION = "p02-c10-contracts-v1"
GENERATOR_SEED = 230210

# Exact Card 30 hydration authority.  These are facts from the committed
# coordination context, not user-editable generated output.
APP_BASE_HEAD = "1c8b3d99826a207d3b18b3e0429231c31804f317"
APP_BASE_TREE = "3107903158238e5e5eaed78322c3564b06c648e2"
COORDINATION_HEAD = "229ce1e9c7071d392760192875c6af23600b32fc"
COORDINATION_TREE = "cf1009737e0d90a9063a4bc20b77731d6ec219ba"
COORDINATION_CAS_SEQUENCE = 126
COORDINATION_LEDGER_DIGEST = "e68b44ec70e97dc820772c54439507d28239d7f64c580bcb56c1f44cbccdfad6"
COORDINATION_CONTEXT_DIGEST = "30e8590878c7ebf335245cbc37e160523194a0be0cef648c125eda46e2aa294e"
COORDINATION_FENCE_DIGEST = "9d402508388e16f092697f74de5bdc56fbe8eee6934bfa40c5eeb12675d905d7"
PREREQUISITE_DIGEST = "1a7d61ef7f4ceef1870050720df9ad977d35c2c48f9b0959ac613bf88526d38d"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_LENGTH = 44217
REGISTER_ROW_DIGEST = "687fc037e858db407a047219a3005292a3939c0a61e111c4ebe23f5af36e55bf"
DOSSIER_DIGEST = "007c51ae082a6d427490bea4e4e5722153ce02fb3f468802fd40dda71c3d3be7"
DOSSIER_LENGTH = 7206
INHERITED_V21_DIGEST = "67d5181c69e6410e40a5bb8d5cc9e87a44cd1f4e4d027bfdc800924e6e245765"
INHERITED_V21_LENGTH = 19063
FOUNDATION_REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DIRECT_GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_MANIFEST_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_MANIFEST_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_MANIFEST_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_MANIFEST_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_MANIFEST_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

CONTRACT_SCRIPT = "Scripts/v23/p02_c10_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c10_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c10_contracts.py"

SETTINGS_SCHEMA = "Scripts/v23/settings-registry.schema.json"
AVAILABILITY_SCHEMA = "Scripts/v23/feature-availability.schema.json"
CAPABILITY_SCHEMA = "Scripts/v23/capability-permission-matrix.schema.json"
FEATURE_SCHEMA = "Scripts/v23/feature-policy.schema.json"
ENTRY_SCHEMA = "Scripts/v23/entry-assist-policy.schema.json"
FALLBACK_SCHEMA = "Scripts/v23/typed-availability-fallback-receipt.schema.json"

SETTINGS_DOC = "docs/design/v23/tooling/V23P02C10SettingsLifecycleContractV1.json"
CAPABILITY_DOC = "docs/design/v23/tooling/V23P02C10CapabilityAvailabilityContractV1.json"
FEATURE_DOC = "docs/design/v23/tooling/V23P02C10FeaturePolicyRegistryV1.json"
ENTRY_DOC = "docs/design/v23/tooling/V23P02C10EntryAssistPrivacyContractV1.json"
EVIDENCE_DOC = "docs/design/v23/tooling/V23P02C10SettingsCapabilityEvidenceReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C10-tooling-manifest.json"

EXISTING_PATHS: list[str] = []
SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift",
    "FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift",
    "FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift",
    "FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Settings/FeaturePolicyLoaderV1.swift",
    "FieldEvidenceApp/Infrastructure/System/SystemCapabilityAdaptersV1.swift",
    "FieldEvidenceApp/Resources/FeaturePolicyV1.json",
    "FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Settings/V21P02C10SettingsCapabilityCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    SETTINGS_SCHEMA,
    AVAILABILITY_SCHEMA,
    CAPABILITY_SCHEMA,
    FEATURE_SCHEMA,
    ENTRY_SCHEMA,
    FALLBACK_SCHEMA,
    SETTINGS_DOC,
    CAPABILITY_DOC,
    FEATURE_DOC,
    ENTRY_DOC,
    EVIDENCE_DOC,
    MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
GENERATED_PATHS = TOOL_PATHS[3:]

TEST_METHODS = [
    "testV9_14G01TypedSettingsScopesMigrationAndLifecycle",
    "testV9_14A01AvailabilityReasonsPreserveHistoricEssentialOperations",
    "testV9_14H01CapabilityPermissionsConsentFallbackAndScratchAreClosed",
    "testV9_14I01InterruptionRecoveryIsIdempotentAndCreatesNoCanonicalLeak",
    "testV9_14R01HapticsAndEntryAssistRemainPrivateBoundedAndRecoverable",
]

AVAILABILITY_REASONS = [
    "AVAILABLE",
    "PACKAGE_NOT_ENABLED",
    "NOT_ENTITLED",
    "UNSUPPORTED_OS_OR_DEVICE",
    "PERMISSION_NOT_DETERMINED",
    "PERMISSION_LIMITED",
    "PERMISSION_DENIED",
    "PERMISSION_RESTRICTED",
    "OFFLINE_CONTENT_MISSING",
    "RECOVERY_BLOCKED",
    "WORKSPACE_POLICY_DISABLED",
    "PACKAGE_RETIRED",
    "TEMPORARILY_UNAVAILABLE",
]
SETTING_SCOPES = ["DEVICE_LOCAL", "WORKSPACE_CANONICAL", "DERIVED"]
SETTING_VALUE_KINDS = ["BOOLEAN", "BOUNDED_STRING", "BOUNDED_STRING_SET", "RECENT_INPUT_MEMORY"]
PREFERENCE_STORAGE = ["SOLE_DEVICE_PREFERENCES_ADAPTER", "WORKSPACE_WRITER", "NONPERSISTENT_DERIVED"]
PERMISSION_STATES = ["NOT_DETERMINED", "LIMITED", "AUTHORIZED", "DENIED", "RESTRICTED", "UNSUPPORTED"]
CAPABILITY_STATES = ["AVAILABLE", "UNAVAILABLE", "NOT_DETERMINED", "LIMITED", "DENIED", "RESTRICTED", "UNSUPPORTED", "INTERRUPTED"]
FEATURE_STATES = ["ENABLED", "PREPARED_DISABLED"]
SCRATCH_PURPOSES = ["CAPTURE", "IMPORT", "SOURCE", "SUPPORT_EXPORT"]
SCRATCH_TERMINAL_EVENTS = ["ACCEPT", "REJECT", "CANCEL", "EXPIRY", "CRASH_RECOVERY", "PROTECTED_DATA_LOSS", "FAILED_PUBLICATION"]
SETTINGS_LIFECYCLE_OPERATIONS = [
    "MIGRATION", "BACKUP", "RESTORE", "CLONE", "FORK", "IMPORT", "EXPORT",
    "REPORT", "SEARCH", "RESET", "REBUILD", "REPLAY", "DELETE", "ERASE",
    "RETENTION", "COMPATIBILITY", "DOWNGRADE", "FORWARD_FIX", "INTERRUPTION_RECOVERY",
]
SETTING_LIFECYCLE_DISPOSITIONS = [
    "DEVICE_LOCAL_ONLY", "WORKSPACE_CANONICAL_INCLUDED", "EXCLUDED", "REBUILD_DERIVED",
    "RESTORE_DEFAULT", "PRESERVE_CANONICAL", "CLEAR_CANONICAL", "FAIL_CLOSED",
]
FALLBACK_PERSISTENCE_DISPOSITIONS = [
    "NO_CANONICAL_EFFECT_UNTIL_ACCEPTANCE", "DEVICE_LOCAL_ONLY",
    "WORKSPACE_CANONICAL_AFTER_ACCEPTANCE",
]
FALLBACK_DATA_DISPOSITIONS = [
    "PRIOR_HISTORY_PRESERVED", "SCRATCH_DELETED_NO_CANONICAL_EFFECT",
    "ACCEPTED_IMMUTABLE_CONTENT",
]
FALLBACK_REENTRY_TRIGGERS = [
    "CAPABILITY_STATE_CHANGED", "PERMISSION_CHANGED", "USER_INITIATED_RETRY",
    "MANUAL_PATH_SELECTED",
]
CAPABILITY_IDS_FALLBACK = [
    "CAMERA", "SCAN_OCR", "SPEECH_DICTATION", "MICROPHONE_AUDIO_VIDEO",
    "PHOTO_LIBRARY", "LOCATION", "REMINDERS_NOTIFICATIONS", "FILES_SHARE", "DIAGNOSTIC_EXPORT",
]
EVIDENCE_IDS = [f"{CARD}-{family}" for family in ("G01", "A01", "H01", "I01", "R01")]
FAMILIES = {"G01": "GOLDEN", "A01": "ALTERNATE", "H01": "HOSTILE", "I01": "INTERRUPTION", "R01": "RECOVERY"}
INTERRUPTION_BOUNDARIES = [
    "BEFORE_SCRATCH_STAGING",
    "AFTER_SCRATCH_STAGING_BEFORE_ACCEPTANCE",
    "BEFORE_CANONICAL_PUBLICATION",
    "AFTER_CANONICAL_EFFECT_BEFORE_RECEIPT",
    "DURING_SUPPORT_EXPORT",
]
HOSTILE_CASES = [
    "DEVICE_SCOPE_LEAK",
    "WORKSPACE_SCOPE_LEAK",
    "DUPLICATE_SETTING_KEY",
    "INVALID_TYPED_VALUE",
    "INVALID_LEGACY_VALUE",
    "UNKNOWN_AVAILABILITY_REASON",
    "PERMISSION_PROMPT_AT_LAUNCH",
    "PERMISSION_PROMPT_DURING_BACKGROUND_PREFLIGHT",
    "CONSENT_INFERRED_FROM_PERMISSION",
    "CAPTURE_INDICATOR_ENDS_EARLY",
    "SOURCE_SCRATCH_EXPORTED",
    "SUPPORT_EXPORT_BYPASSES_LEASE",
    "CANONICAL_PUBLICATION_BEFORE_ACCEPTANCE",
    "DUPLICATE_RETRY_EFFECT",
    "HAPTIC_FEATURE_LOCAL_KEY",
    "RAW_FREE_TEXT_IN_RECENT_MEMORY",
]
PROHIBITED_TOKENS = [
    "try!", "fatalError(", "preconditionFailure(", "URLSession", "CloudKit", "CKRecord",
    "remoteConfig", "serverKillSwitch", "cohort", "hasPermissions", "masterAssistance",
    "backgroundLocation", "alwaysLocation", "permissionCoercion",
]


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


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


def base(schema_name: str) -> dict[str, Any]:
    return {
        "schema": schema_name,
        "schemaVersion": 1,
        "cardID": CARD,
        "registerOrdinal": ORDINAL,
        "title": TITLE,
        "generatorVersion": GENERATOR_VERSION,
        "generatorSeed": GENERATOR_SEED,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": ORDINAL,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "REFINED_WITHOUT_LOSS",
        "lineageSource": "V21-P02-C10",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "contextDigest": COORDINATION_CONTEXT_DIGEST,
        "pathFenceDigest": COORDINATION_FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "registerSectionDigest": REGISTER_SECTION_DIGEST,
        "registerSectionLength": REGISTER_SECTION_LENGTH,
        "registerRowDigest": REGISTER_ROW_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "dossierLength": DOSSIER_LENGTH,
        "inheritedV21BlockDigest": INHERITED_V21_DIGEST,
        "inheritedV21BlockLength": INHERITED_V21_LENGTH,
        "foundationRegisterDigest": FOUNDATION_REGISTER_DIGEST,
        "directGraphDigest": DIRECT_GRAPH_DIGEST,
        "facetManifestDigest": FACET_MANIFEST_DIGEST,
        "selectorManifestDigest": SELECTOR_MANIFEST_DIGEST,
        "relationManifestDigest": RELATION_MANIFEST_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_MANIFEST_DIGEST,
        "impactManifestDigest": IMPACT_MANIFEST_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P02-C09"],
        "invalidationConsumers": ["V23-P02-C11", "V23-P03-C09"],
        "nativeOrHostedEvidenceClaimed": False,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceEnabled": False,
        "adoptionEnabled": False,
        "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def _read(root: Path, relative: str) -> tuple[bytes, bool]:
    path = root / relative
    try:
        return path.read_bytes(), True
    except FileNotFoundError:
        return b"", False
    except OSError as error:
        raise ContractError(f"cannot read {relative}: {error}") from error


def source_rows(root: Path) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    pending: list[str] = []
    for relative in SOURCE_PATHS:
        data, present = _read(root, relative)
        if not present:
            pending.append(relative)
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data), "present": present})
    return rows, pending


def _balanced_block(text: str, marker: str) -> str:
    start = text.find(marker)
    if start < 0:
        return ""
    brace = text.find("{", start)
    if brace < 0:
        return ""
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    return ""


def swift_enum_values(text: str, enum_name: str) -> list[str]:
    block = _balanced_block(text, f"enum {enum_name}")
    if not block:
        block = _balanced_block(text, f"struct {enum_name}")
    values: list[str] = []
    for name, raw in re.findall(r"\bcase\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*\"([^\"]+)\")?", block):
        values.append(raw or re.sub(r"(?<!^)([A-Z])", r"_\1", name).upper())
    return list(dict.fromkeys(values))


def swift_symbols(text: str) -> list[str]:
    return sorted(set(re.findall(r"\b(?:enum|struct|protocol|class)\s+([A-Za-z_][A-Za-z0-9_]*)", text)))


def _fixture(root: Path) -> tuple[dict[str, Any], str, bool]:
    relative = SOURCE_PATHS[-1]
    raw, present = _read(root, relative)
    if not present:
        return {}, sha(raw), False
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError(f"invalid Card30 fixture: {error}") from error
    if not isinstance(value, dict):
        raise ContractError("Card30 fixture must be an object")
    return value, sha(raw), True


def _resource(root: Path) -> tuple[dict[str, Any], str, bool]:
    relative = SOURCE_PATHS[6]
    raw, present = _read(root, relative)
    if not present:
        return {}, sha(raw), False
    try:
        value = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ContractError(f"invalid FeaturePolicyV1 resource: {error}") from error
    if not isinstance(value, dict):
        raise ContractError("FeaturePolicyV1 resource must be an object")
    return value, sha(raw), True


def _source_texts(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for relative in SOURCE_PATHS:
        if not relative.endswith(".swift"):
            continue
        raw, present = _read(root, relative)
        result[relative] = raw.decode("utf-8", errors="strict") if present else ""
    return result


def _find_enum_values(texts: Iterable[str], enum_name: str, fallback: list[str]) -> list[str]:
    found: list[str] = []
    for text in texts:
        found.extend(swift_enum_values(text, enum_name))
    values = list(dict.fromkeys(found))
    if not values:
        raise ContractError(f"required source enum is absent or unparseable: {enum_name}")
    return values


def _setting_descriptors(text: str) -> list[dict[str, Any]]:
    # The source initializer is intentionally parsed into a projection, not
    # reimplemented.  This catches a changed key/scope/default without making
    # the tooling a second settings registry.
    block = _balanced_block(text, "static func current()")
    if not block:
        raise ContractError("SettingsRegistryV1.current source body is absent or unparseable")
    chunks = re.findall(r"try\s+SettingDescriptorV1\((.*?)\n\s*\)", block, re.S)
    result: list[dict[str, Any]] = []
    for chunk in chunks:
        key = re.search(r'\bkey:\s*"([^"]+)"', chunk)
        key_constant = re.search(r'\bkey:\s*HapticFeedbackPreferenceV1\.key\b', chunk)
        localization = re.search(r'\blocalizationKey:\s*"([^"]+)"', chunk)
        if not key and not key_constant:
            raise ContractError("setting descriptor key is absent or unparseable")
        def enum(field: str) -> str | None:
            hit = re.search(rf"\b{field}:\s*\.([A-Za-z0-9_]+)", chunk)
            return re.sub(r"(?<!^)([A-Z])", r"_\1", hit.group(1)).upper() if hit else None
        def integer(field: str, default: int) -> int:
            hit = re.search(rf"\b{field}:\s*([0-9_]+)", chunk)
            if hit:
                return int(hit.group(1).replace("_", ""))
            maximum = re.search(
                rf"\b{field}:\s*SettingDescriptorV1\.maximumValueBytes\b", chunk
            )
            return 65_536 if maximum else default
        row = {
            "key": key.group(1) if key else "device.hapticFeedback",
            "valueKind": enum("valueKind") or "UNKNOWN",
            "scope": enum("scope") or "UNKNOWN",
            "storage": enum("storage") or "UNKNOWN",
            "backup": enum("backup") or "UNKNOWN",
            "reset": enum("reset") or "UNKNOWN",
            "erase": enum("erase") or "UNKNOWN",
            "privacy": enum("privacy") or "UNKNOWN",
            "localizationKey": localization.group(1) if localization else "UNKNOWN",
            "maximumCanonicalBytes": integer("maximumCanonicalBytes", 0),
            "migrationVersion": integer("migrationVersion", 0),
        }
        if any(value == "UNKNOWN" for value in row.values()) or row["maximumCanonicalBytes"] <= 0 or row["migrationVersion"] <= 0:
            raise ContractError(f"setting descriptor is incomplete: {row['key']}")
        result.append(row)
    if not result:
        raise ContractError("SettingsRegistryV1.current contains no parseable descriptors")
    return sorted(result, key=lambda row: row["key"])


def _fixture_pick(fixture: dict[str, Any], *keys: str, default: Any = None) -> Any:
    for key in keys:
        if key in fixture:
            return fixture[key]
    return default


def exact_semantics(root: Path) -> dict[str, Any]:
    texts = _source_texts(root)
    settings_text = texts.get(SOURCE_PATHS[0], "")
    capability_text = texts.get(SOURCE_PATHS[1], "")
    all_swift = list(texts.values())
    fixture, fixture_digest, fixture_present = _fixture(root)
    resource, resource_digest, resource_present = _resource(root)

    reasons = _find_enum_values(all_swift, "FeatureAvailabilityReasonV1", AVAILABILITY_REASONS)
    if set(reasons) != set(AVAILABILITY_REASONS):
        # The policy vocabulary is frozen; a source enum that is incomplete is
        # a contract error rather than permission to silently widen/narrow it.
        if any("FeatureAvailabilityReasonV1" in text for text in all_swift):
            raise ContractError(f"Card30 availability reason set differs: {reasons}")
        reasons = list(AVAILABILITY_REASONS)
    capability_ids = sorted(_find_enum_values(all_swift, "CapabilityIDV1", CAPABILITY_IDS_FALLBACK))
    capability_states = sorted(_find_enum_values(all_swift, "CapabilityRuntimeStateV1", CAPABILITY_STATES))
    permission_states = sorted(_find_enum_values(all_swift, "CapabilityPermissionStateV1", PERMISSION_STATES))
    feature_states = _find_enum_values(all_swift, "FeaturePolicyStateV1", FEATURE_STATES)
    lifecycle_operations = _find_enum_values(all_swift, "SettingsLifecycleOperationV1", SETTINGS_LIFECYCLE_OPERATIONS)
    lifecycle_dispositions = _find_enum_values(all_swift, "SettingLifecycleDispositionV1", SETTING_LIFECYCLE_DISPOSITIONS)
    fallback_persistence = _find_enum_values(all_swift, "FallbackPersistenceDispositionV1", FALLBACK_PERSISTENCE_DISPOSITIONS)
    fallback_data = _find_enum_values(all_swift, "FallbackDataDispositionV1", FALLBACK_DATA_DISPOSITIONS)
    fallback_reentry = _find_enum_values(all_swift, "FallbackReentryTriggerV1", FALLBACK_REENTRY_TRIGGERS)
    for actual, expected, label in [
        (lifecycle_operations, SETTINGS_LIFECYCLE_OPERATIONS, "settings lifecycle operations"),
        (lifecycle_dispositions, SETTING_LIFECYCLE_DISPOSITIONS, "settings lifecycle dispositions"),
        (fallback_persistence, FALLBACK_PERSISTENCE_DISPOSITIONS, "fallback persistence dispositions"),
        (fallback_data, FALLBACK_DATA_DISPOSITIONS, "fallback data dispositions"),
        (fallback_reentry, FALLBACK_REENTRY_TRIGGERS, "fallback reentry triggers"),
    ]:
        if actual != expected:
            raise ContractError(f"Card30 {label} differ: {actual}")

    tests_text = texts.get(SOURCE_PATHS[7], "")
    found_tests = re.findall(r"\bfunc\s+(testV9_14[A-Za-z0-9_]+)\s*\(", tests_text)
    if found_tests != TEST_METHODS:
        raise ContractError(f"exact Card30 tests differ: {found_tests}")
    test_methods = found_tests
    descriptors = _setting_descriptors(settings_text)
    setting_keys = [row["key"] for row in descriptors]

    # Test methods are source-derived. The fixture deliberately contains
    # policy data only and is never allowed to backfill a missing test.
    fixture_methods = list(test_methods)
    required_fixture_keys = {
        "availabilityScenarios", "availabilityReasons", "settingScopes",
        "capabilityIDs", "interruptionBoundaries", "hostileCases",
        "essentialOperations", "permissionStates", "captureKinds",
        "scratchSourcePurposes", "scratchTerminalDispositions",
        "scratchFaultEvents", "scratchExcludedConsumers", "featureIDs", "entryAssist",
    }
    missing_fixture_keys = sorted(required_fixture_keys - set(fixture))
    if missing_fixture_keys:
        raise ContractError(f"fixture omits required matrices: {missing_fixture_keys}")
    scenario_rows = fixture["availabilityScenarios"]
    scenario_reasons = [row.get("reason") for row in scenario_rows if isinstance(row, dict) and isinstance(row.get("reason"), str)] if isinstance(scenario_rows, list) else []
    declared_reasons = fixture["availabilityReasons"]
    declared_scopes = fixture["settingScopes"]
    declared_capabilities = fixture["capabilityIDs"]
    interruption = fixture["interruptionBoundaries"]
    hostile = fixture["hostileCases"]
    if sorted(scenario_reasons) != sorted(reasons) or sorted(declared_reasons) != sorted(reasons):
        raise ContractError("fixture availability matrices differ from source enum")
    if sorted(declared_scopes) != sorted(SETTING_SCOPES):
        raise ContractError("fixture setting scopes differ")
    if sorted(declared_capabilities) != sorted(capability_ids):
        raise ContractError("fixture capability IDs differ from source enum")
    if sorted(interruption) != sorted(INTERRUPTION_BOUNDARIES) or sorted(hostile) != sorted(HOSTILE_CASES):
        raise ContractError("fixture interruption/hostile matrices differ")

    source_rows, pending = source_rows_for(root)
    source_binding_rows = []
    for row in source_rows:
        source_binding_rows.append({"path": row["path"], "bytes": row["bytes"], "sha256": row["sha256"], "present": row["present"]})

    return {
        "settings": {
            "descriptors": descriptors,
            "keys": setting_keys,
            "scopes": list(SETTING_SCOPES),
            "valueKinds": list(SETTING_VALUE_KINDS),
            "storageDispositions": list(PREFERENCE_STORAGE),
            "maximumValueBytes": 65_536,
            "soleAdapter": "PreferencesAdapterV1",
            "defaultHapticKey": "device.hapticFeedback",
            "defaultHapticValue": True,
            "defaultHapticState": "ON",
            "workspaceCanonicalRepresentation": "WorkspaceSettingRecordV1",
            "derivedPersistence": "FORBIDDEN",
            "registryPort": "SettingsRegistryPortV1",
            "lifecycleOperations": lifecycle_operations,
            "lifecycleDispositions": lifecycle_dispositions,
            "preferenceEnvelope": {
                "type": "PreferenceStorageEnvelopeV1",
                "schemaVersion": 1,
                "canonicalValueAndMigrationReceiptAtomic": True,
                "migrationRequestDigestBound": True,
                "legacySourceDigestBound": True,
                "sameOperationConflictFailsClosed": True,
                "reservedStoragePrefixRejectedAsLegacyInput": True,
                "migrationReceiptDecodeGuards": [
                    "NONZERO_OPERATION_ID", "DESCRIPTOR_KEY", "MIGRATION_VERSION",
                    "CANONICAL_DIGEST_SHAPE",
                ],
                "replayRechecksReceiptAgainstCanonicalValue": True,
            },
        },
        "availability": {
            "reasons": reasons,
            "nextActionPerReason": True,
            "manualFallbackWhenApplicable": True,
            "blocksOnlyNewOperation": True,
            "essentialOperationsPreserved": ["READ", "EXPORT", "BACKUP", "RESTORE", "RECOVERY", "DELETE", "ERASE"],
            "historicTruthPreserved": True,
        },
        "capability": {
            "capabilityIDs": capability_ids,
            "capabilityStates": capability_states,
            "permissionStates": permission_states,
            "purposeStringRequired": True,
            "firstUseOnly": True,
            "neverFirstLaunchPrompt": True,
            "neverInstallPrompt": True,
            "neverRestorePrompt": True,
            "neverBackgroundPreflightPrompt": True,
            "explicitConsentRequired": True,
            "activeIndicator": "FULL_CAPTURE_DURATION",
            "permissionIsNotConsent": True,
            "revocationPreservesDraft": True,
            "revocationPublishesCanonical": False,
            "fallbackRegistry": "PermissionFallbackRegistryV1",
            "scratchAdapter": "ScratchDataLeaseV1",
            "permissionRequestTimings": _find_enum_values(all_swift, "PermissionRequestTimingV1", []),
            "notificationRequestTiming": "EXPLICIT_USER_INITIATED_FEATURE_BOUNDARY",
            "capturePhases": _find_enum_values(all_swift, "ActiveCapturePhaseV1", []),
            "scratchConsumers": _find_enum_values(all_swift, "ScratchDataConsumerV1", []),
            "scratchPublicationDispositions": _find_enum_values(all_swift, "ScratchPublicationDispositionV1", []),
            "capabilityAwareFallbackValidation": True,
        },
        "featurePolicy": {
            "states": feature_states,
            "resourcePath": SOURCE_PATHS[6],
            "resourcePresent": resource_present,
            "resourceDigest": resource_digest,
            "resource": resource,
            "signedBundleOnly": True,
            "unknownVersionFailsClosed": True,
            "missingPolicyFailsClosed": True,
            "remoteConfig": False,
            "network": False,
            "cohort": False,
            "releaseTestInjection": False,
            "historicAccessPreserved": True,
            "resolutionOwner": "FeaturePolicyResolutionV1",
            "noDuplicateAvailabilityAuthority": True,
        },
        "entryAssist": {
            "policy": "EntryAssistPolicyV1",
            "sourceKinds": ["REVIEWED_RECENT_OPTION", "REVIEWED_STABLE_LOCAL_REFERENCE"],
            "suggestionKinds": ["OPTION_ID", "STABLE_LOCAL_REFERENCE"],
            "maximumSuggestionsPerField": 3,
            "maximumEntries": 128,
            "retentionSeconds": 7_776_000,
            "scope": "DEVICE_LOCAL_BY_WORKSPACE_AND_SEMANTIC_FIELD",
            "doubleRevalidation": ["DISPLAY", "EXPLICIT_ACCEPTANCE"],
            "explicitReviewRequired": True,
            "autoSubmission": False,
            "rawFreeText": False,
            "workspaceIsolation": True,
            "opaqueReferenceSyntax": {
                "OPTION_ID": "option:<lowercase-sha256>",
                "STABLE_LOCAL_REFERENCE": "local-ref:<lowercase-uuid>",
                "canonicalDecodeRevalidates": True,
            },
            "haptic": {
                "key": "device.hapticFeedback",
                "default": "ON",
                "oneGlobalPreference": True,
                "runtimeAvailabilityRequired": True,
                "safeContextRequired": True,
                "noPerFeatureKeys": True,
                "noPhysicalSensationClaim": True,
                "textIconAccessibilityPreserved": True,
            },
        },
        "fixture": {
            "present": fixture_present,
            "sha256": fixture_digest,
            "topLevelKeys": sorted(fixture),
            "methods": fixture_methods,
            "declaredReasons": list(declared_reasons) if isinstance(declared_reasons, list) else [],
            "declaredScopes": list(declared_scopes) if isinstance(declared_scopes, list) else [],
            "declaredCapabilities": list(declared_capabilities) if isinstance(declared_capabilities, list) else [],
            "availabilityScenarioCount": len(scenario_rows) if isinstance(scenario_rows, list) else 0,
            "essentialOperations": list(fixture["essentialOperations"]),
            "permissionStates": list(fixture["permissionStates"]),
            "captureKinds": list(fixture["captureKinds"]),
            "scratchSourcePurposes": list(fixture["scratchSourcePurposes"]),
            "scratchTerminalDispositions": list(fixture["scratchTerminalDispositions"]),
            "scratchFaultEvents": list(fixture["scratchFaultEvents"]),
            "scratchExcludedConsumers": list(fixture["scratchExcludedConsumers"]),
            "featureIDs": list(fixture["featureIDs"]),
            "entryAssistBounds": dict(fixture["entryAssist"]),
            "interruptionBoundaries": list(interruption) if isinstance(interruption, list) else [],
            "hostileCases": list(hostile) if isinstance(hostile, list) else [],
        },
        "sourceBindings": source_binding_rows,
        "pendingInputs": pending,
    }


def source_rows_for(root: Path) -> tuple[list[dict[str, Any]], list[str]]:
    return source_rows(root)


def common_fields(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    return {
        "authority": authority(),
        "pathFence": {"paths": PATH_FENCE, "count": len(PATH_FENCE), "digest": COORDINATION_FENCE_DIGEST, "s10Overlap": False},
        "provisional": flags(),
        "exactFiveTests": {"required": True, "methods": TEST_METHODS, "count": 5},
        "sourceBindings": semantics["sourceBindings"],
    }


def settings_contract(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    settings = semantics["settings"]
    return seal({
        **base("V23P02C10SettingsLifecycleContractV1"),
        **common_fields(root, semantics),
        "owner": "SettingsRegistryV1",
        "registry": settings,
        "scopeRules": {
            "DEVICE_LOCAL": {"storage": "SOLE_DEVICE_PREFERENCES_ADAPTER", "backup": "EXCLUDED_DEVICE_LOCAL", "workspaceExport": False, "reset": "RESTORE_DEFAULT", "erase": "RESTORE_DEFAULT"},
            "WORKSPACE_CANONICAL": {"storage": "WORKSPACE_WRITER", "backup": "CANONICAL_WORKSPACE_BACKUP", "workspaceExport": True, "reset": "EXPLICIT_CANONICAL_RESET", "erase": "CLEAR_CANONICAL"},
            "DERIVED": {"storage": "NONPERSISTENT_DERIVED", "backup": "NOT_APPLICABLE", "workspaceExport": False, "reset": "REBUILD", "erase": "REBUILD"},
        },
        "migration": {
            "idempotent": True,
            "sameInputSameReceipt": True,
            "invalidLegacyValue": "REPLACED_INVALID_LEGACY_WITH_DEFAULT",
            "absence": "INITIALIZED_FROM_ABSENCE",
            "unknownKey": "FAIL_CLOSED",
            "directFeatureKeyAccess": False,
        },
        "lifecycle": {
            "backup": True, "restore": True, "reset": True, "erase": True,
            "replay": True, "interruption": True, "deviceLocalMemoryExcluded": True,
            "workspaceCanonicalUsesExpectedRevisionAndReceipt": True,
            "derivedNeverPersists": True,
            "operations": settings["lifecycleOperations"],
            "dispositions": settings["lifecycleDispositions"],
            "preferenceEnvelope": settings["preferenceEnvelope"],
        },
    })


def capability_contract(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    availability = semantics["availability"]
    capability = semantics["capability"]
    return seal({
        **base("V23P02C10CapabilityAvailabilityContractV1"),
        **common_fields(root, semantics),
        "owner": "FeatureAvailabilityPolicyV1",
        "availability": availability,
        "capability": capability,
        "permissionFallback": {
            "registry": "PermissionFallbackRegistryV1",
            "oneLocalizedPurposePerCapability": True,
            "manualPathRequiredWhenProviderUnavailable": True,
            "fallbackNeverSatisfiesMediaRequirement": True,
            "providerFailurePreservesDraft": True,
            "capturePurposes": SCRATCH_PURPOSES[:3],
            "supportOutputPurpose": "SUPPORT_EXPORT",
        },
        "scratch": {
            "owner": "P02-C08_SOLE_SHARED_SCRATCH_ROOT",
            "purposes": SCRATCH_PURPOSES,
            "terminalCleanup": SCRATCH_TERMINAL_EVENTS,
            "sourcePurposesExcludedFrom": ["BACKUP", "SEARCH", "REPORT", "SUPPORT_EXPORT", "DIAGNOSTICS"],
            "supportExportRequiresDistinctLease": True,
            "canonicalPublicationRequiresExplicitAcceptance": True,
            "recoveryPort": "CapabilityScratchLeasePortV1.recoverAfterInterruption",
            "isolationPolicy": "ScratchIsolationPolicyV1",
            "consumers": capability["scratchConsumers"],
            "publicationDispositions": capability["scratchPublicationDispositions"],
            "capturePhases": capability["capturePhases"],
            "maximumActiveLeaseCount": 128,
            "writeReservationPerLease": True,
            "finishAndRecoveryRejectActiveWrites": True,
        },
    })


def feature_contract(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    return seal({
        **base("V23P02C10FeaturePolicyRegistryV1"),
        **common_fields(root, semantics),
        "owner": "FeaturePolicyLoaderV1",
        "policy": semantics["featurePolicy"],
        "descriptor": {
            "stableFeatureID": True,
            "state": FEATURE_STATES,
            "packageRequirement": True,
            "capabilityRequirement": True,
            "minimumPlatformRequirement": True,
            "safeFallback": True,
            "exactConsumers": True,
        },
        "forbidden": ["REMOTE_CONFIG", "URL_TTL", "COHORT_BUCKET", "ACCOUNT_BUCKET", "SERVER_KILL_SWITCH", "USER_DEFAULTS_OVERRIDE", "DOWNLOADED_EXECUTABLE_POLICY", "RELEASE_TEST_INJECTION"],
        "evaluation": {"signedBundleDigestBound": True, "resolutionOwner": "FeaturePolicyResolutionV1", "noDuplicateAvailabilityAuthority": True, "malformedFailsClosed": True, "duplicateFailsClosed": True, "unknownVersionFailsClosed": True, "historicAccessPreserved": True},
    })


def entry_contract(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    return seal({
        **base("V23P02C10EntryAssistPrivacyContractV1"),
        **common_fields(root, semantics),
        "owner": "EntryAssistPolicyV1",
        "entryAssist": semantics["entryAssist"],
        "privacy": {
            "allowedValues": ["LOW_RISK_CLOSED_OPTION_IDS", "STABLE_LOCAL_REFERENCES"],
            "forbiddenValues": ["RAW_FREE_TEXT", "CONTACT", "EMAIL", "ADDRESS", "MEASUREMENT", "CONDITION", "RESULT", "PASS_FAIL", "FINDING", "SEVERITY", "EVIDENCE", "SIGN_OFF", "QUALIFICATION", "OBSERVATION_TIMESTAMP"],
            "excludedFrom": ["WORKSPACE_TRUTH", "BACKUP", "RESTORE", "ARCHIVE", "EXPORT", "JOURNAL", "REPORT", "SEARCH", "SPOTLIGHT", "SUPPORT", "DIAGNOSTICS", "ANALYTICS"],
        },
        "haptic": semantics["entryAssist"]["haptic"],
        "invalidSuggestionEffects": {"command": False, "receipt": False, "canonicalValue": False, "analyticsRow": False, "crossWorkspaceMemory": False},
    })


def evidence_contract(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    return seal({
        **base("V23P02C10SettingsCapabilityEvidenceReceiptV1"),
        **common_fields(root, semantics),
        "owner": "V9_14SettingsCapabilityLifecycleTests",
        "evidence": [
            {"evidenceID": evidence, "family": FAMILIES[family], "familyCode": family, "testMethod": method}
            for evidence, family, method in zip(EVIDENCE_IDS, ("G01", "A01", "H01", "I01", "R01"), TEST_METHODS)
        ],
        "requirements": {
            "G01": ["EXACT_FENCE", "THREE_SETTINGS_SCOPES", "TYPED_DEFAULT_AND_VALIDATION", "EXACT_THIRTEEN_AVAILABILITY_REASONS", "SIGNED_FEATURE_POLICY"],
            "A01": ["IDEMPOTENT_LEGACY_MIGRATION", "ESSENTIAL_OPERATIONS_VISIBLE", "EXPLICIT_PURPOSE_AND_MANUAL_FALLBACK", "USER_INITIATED_PERMISSION_BOUNDARY", "SCRATCH_PURPOSE_ISOLATION"],
            "H01": HOSTILE_CASES,
            "I01": INTERRUPTION_BOUNDARIES + ["RELAUNCH_IDEMPOTENT", "NO_CANONICAL_LEAK", "NO_DUPLICATE_EFFECT"],
            "R01": ["HAPTIC_DEFAULT_ON", "NO_PER_FEATURE_HAPTIC_KEY", "RECENT_MEMORY_3_128_90D", "WORKSPACE_ISOLATION", "RESET_ERASE_RECOVERY", "TYPED_FALLBACK_RECEIPT"],
        },
        "hostile": {"cases": HOSTILE_CASES, "prohibitedTokens": PROHIBITED_TOKENS, "failClosed": True},
        "interruption": {"boundaries": INTERRUPTION_BOUNDARIES, "relaunchResumesOrFailsClosed": True, "priorAcceptedGenerationPreserved": True},
        "brandImpact": {"manifestType": "BrandImpactManifestV1", "manifestCount": 1, "changedScreens": [], "changedStates": [], "affectedConsumers": ["V23-P02-C10", "V23-P02-C11", "V23-P03-C09"], "nativeOrHostedClaimed": False},
        "fixtureBinding": semantics["fixture"],
        "sourceDigestRows": semantics["sourceBindings"],
    })


def fallback_contract(root: Path, semantics: dict[str, Any]) -> dict[str, Any]:
    typed_receipt = {
        "schemaVersion": 1,
        "candidateHead": APP_BASE_HEAD,
        "candidateTree": APP_BASE_TREE,
        "providerID": "SYSTEM_CAPABILITY_ADAPTER",
        "providerSliceDigest": "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6",
        "consumerID": "CHECK_RUNNER",
        "capabilityID": "FILES_AND_SHARE",
        "availabilityReason": "PERMISSION_DENIED",
        "mandatoryCoreComplete": True,
        "visibleFallback": "SAVE_LOCALLY",
        "persistenceDisposition": "NO_CANONICAL_EFFECT_UNTIL_ACCEPTANCE",
        "dataDisposition": "PRIOR_HISTORY_PRESERVED",
        "reentryTrigger": "CAPABILITY_STATE_CHANGED",
        "localizedVisibleStateKey": "availability.PERMISSION_DENIED.state",
        "localizedVisibleCopyKey": "availability.PERMISSION_DENIED.copy",
        "localizedNextActionKey": "availability.PERMISSION_DENIED.action",
        "fallbackTestArtifactIDs": ["V23-P02-C10-A01-FALLBACK"],
        "evidenceArtifactIDs": ["V23-P02-C10-A01-RECEIPT"],
        "zeroUnsupportedPublicClaim": True,
    }
    return seal({
        **base("V23P02C10TypedAvailabilityFallbackReceiptV1"),
        **common_fields(root, semantics),
        "owner": "PermissionFallbackRegistryV1",
        "receipt": {
            "provider": "CAPABILITY_OR_OPTIONAL_PROVIDER",
            "consumer": "EXPLICIT_FEATURE_ENTRY_POINT",
            "candidate": "TYPED_PROVIDER_CANDIDATE",
            "reason": "CLOSED_FEATURE_AVAILABILITY_REASON",
            "coreDisposition": "MANDATORY_CORE_REMAINS_VISIBLE",
            "fallbackDisposition": "COMPLETE_MANUAL_PATH_WHEN_APPLICABLE",
            "dataDisposition": "NO_CANONICAL_SUGGESTION_OR_EVIDENCE_UNTIL_ACCEPTANCE",
            "tests": TEST_METHODS,
            "reentryTrigger": "USER_INITIATED_RETRY_OR_MANUAL_PATH",
            "unsupportedClaims": [],
        },
        "reasonSet": AVAILABILITY_REASONS,
        "permissionStates": PERMISSION_STATES,
        "typedReceipt": typed_receipt,
        "typedReceiptFields": list(typed_receipt),
        "typedReceiptSemantics": {
            "candidateIsExactHeadAndTree": True,
            "threeLocalizationKeys": ["localizedVisibleStateKey", "localizedVisibleCopyKey", "localizedNextActionKey"],
            "fallbackTestsNonemptySorted": True,
            "evidenceArtifactIDsNonemptySorted": True,
            "mandatoryCoreComplete": True,
            "zeroUnsupportedPublicClaim": True,
            "providerSliceDigestRequired": True,
            "persistenceDispositions": FALLBACK_PERSISTENCE_DISPOSITIONS,
            "dataDispositions": FALLBACK_DATA_DISPOSITIONS,
            "reentryTriggers": FALLBACK_REENTRY_TRIGGERS,
            "capabilityAwareFallback": {
                "availableRequiresNoFallback": True,
                "unavailableUsesCapabilityDescriptor": True,
                "hapticsMayUseNoFallback": True,
                "cameraRequires": "CHOOSE_EXISTING_PHOTO",
            },
        },
        "noPermissionConsentEquivalence": True,
        "noFallbackMediaEquivalence": True,
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
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"const": value}
    if isinstance(value, int):
        return {"const": value}
    if isinstance(value, float):
        return {"const": value}
    if isinstance(value, str):
        if key == "artifactDigest" or key.lower().endswith("digest") or key == "sha256":
            return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
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
        if data is None:
            data, present = _read(root, relative)
            if not present:
                pending.append(relative)
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return rows, pending


def manifest(root: Path, generated: dict[str, bytes], semantics: dict[str, Any]) -> dict[str, Any]:
    rows, pending = _manifest_rows(root, generated)
    return seal({
        **base("V23-P02-C10-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "authority": authority(),
        "pathFence": PATH_FENCE,
        "pathFenceCount": len(PATH_FENCE),
        "existingPaths": EXISTING_PATHS,
        "newPaths": PATH_FENCE,
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
        "fenceProof": {"baseHead": APP_BASE_HEAD, "baseTree": APP_BASE_TREE, "pathFenceDigest": COORDINATION_FENCE_DIGEST, "priorFenceCount": 0, "priorOwnedPathCount": 0, "priorFenceOverlapCount": 0, "authorizedPriorFenceOverlapCount": 0, "unauthorizedPriorFenceOverlapCount": 0, "allowedDeletePaths": [], "allowedRenamePaths": [], "activeS10ReservationDigest": S10_RESERVATION_DIGEST, "activeS10Overlap": False},
        "semanticCoverage": {"availabilityReasonCount": len(AVAILABILITY_REASONS), "settingScopeCount": len(SETTING_SCOPES), "exactTestCount": len(TEST_METHODS), "scratchPurposeCount": len(SCRATCH_PURPOSES), "interruptionBoundaryCount": len(INTERRUPTION_BOUNDARIES), "fixtureDigest": semantics["fixture"]["sha256"], "sourcePending": bool(semantics["pendingInputs"])},
        "strictSchemaCount": 6,
        "provisionalKernelOnly": True,
        "nativeEvidenceClaimed": False,
        "hostedEvidenceClaimed": False,
        "physicalEvidenceClaimed": False,
        "acceptanceClaimed": False,
        "releaseClaimed": False,
        "noPhase10Polling": True,
        **flags(),
    })


def validate_fence(root: Path) -> None:
    changed = subprocess.run(["git", "-C", str(root), "diff", "--name-only", APP_BASE_HEAD], check=True, capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    changed_set = {line.replace("\\", "/") for line in changed if line}
    status = subprocess.run(["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"], check=True, capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    for line in status:
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"Card30 delete/rename is not allowed: {line}")
        changed_set.add(raw.replace("\\", "/"))
    outside = sorted(changed_set - set(PATH_FENCE))
    if outside:
        raise ContractError(f"Card30 out-of-fence delta: {outside}")


def all_contracts(root: Path) -> dict[str, dict[str, Any]]:
    validate_fence(root)
    semantics = exact_semantics(root)
    return {
        SETTINGS_DOC: settings_contract(root, semantics),
        CAPABILITY_DOC: capability_contract(root, semantics),
        FEATURE_DOC: feature_contract(root, semantics),
        ENTRY_DOC: entry_contract(root, semantics),
        EVIDENCE_DOC: evidence_contract(root, semantics),
        # This sixth contract is a schema-backed generated contract even
        # though its public receipt is embedded in the evidence document.
        "__fallback__": fallback_contract(root, semantics),
    }


def all_outputs(root: Path) -> dict[str, bytes]:
    contracts = all_contracts(root)
    settings = contracts[SETTINGS_DOC]
    capability = contracts[CAPABILITY_DOC]
    feature = contracts[FEATURE_DOC]
    entry = contracts[ENTRY_DOC]
    evidence = contracts[EVIDENCE_DOC]
    fallback = contracts["__fallback__"]
    generated: dict[str, bytes] = {
        SETTINGS_SCHEMA: pretty(schema("V23P02C10SettingsLifecycleContractV1", settings)),
        AVAILABILITY_SCHEMA: pretty(schema("V23P02C10CapabilityAvailabilityContractV1", capability)),
        CAPABILITY_SCHEMA: pretty(schema("V23P02C10CapabilityPermissionMatrixV1", capability)),
        FEATURE_SCHEMA: pretty(schema("V23P02C10FeaturePolicyRegistryV1", feature)),
        ENTRY_SCHEMA: pretty(schema("V23P02C10EntryAssistPrivacyContractV1", entry)),
        FALLBACK_SCHEMA: pretty(schema("V23P02C10TypedAvailabilityFallbackReceiptV1", fallback)),
        SETTINGS_DOC: pretty(settings),
        CAPABILITY_DOC: pretty(capability),
        FEATURE_DOC: pretty(feature),
        ENTRY_DOC: pretty(entry),
        EVIDENCE_DOC: pretty(evidence),
    }
    generated[MANIFEST] = pretty(manifest(root, generated, exact_semantics(root)))
    return generated


if __name__ == "__main__":
    print(json.dumps({"card": CARD, "fenceCount": len(PATH_FENCE), "generatedCount": len(GENERATED_PATHS)}, sort_keys=True))
