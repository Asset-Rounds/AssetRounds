#!/usr/bin/env python3
"""Hostile, independent Card 30 tooling verifier.

This verifier intentionally does not compare the generated documents to a
second copy of the contracts module.  It derives the fence, source presence,
test selectors, closed vocabularies, and hostile semantic requirements from
the live worktree, then checks the generated JSON and strict schemas against
those independently derived facts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import p02_c10_contracts as c


EXACT_SOURCE_PATHS = [
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
EXACT_TOOL_PATHS = [
    "Scripts/v23/p02_c10_contracts.py",
    "Scripts/v23/generate_p02_c10_contracts.py",
    "Scripts/v23/verify_p02_c10_contracts.py",
    "Scripts/v23/settings-registry.schema.json",
    "Scripts/v23/feature-availability.schema.json",
    "Scripts/v23/capability-permission-matrix.schema.json",
    "Scripts/v23/feature-policy.schema.json",
    "Scripts/v23/entry-assist-policy.schema.json",
    "Scripts/v23/typed-availability-fallback-receipt.schema.json",
    "docs/design/v23/tooling/V23P02C10SettingsLifecycleContractV1.json",
    "docs/design/v23/tooling/V23P02C10CapabilityAvailabilityContractV1.json",
    "docs/design/v23/tooling/V23P02C10FeaturePolicyRegistryV1.json",
    "docs/design/v23/tooling/V23P02C10EntryAssistPrivacyContractV1.json",
    "docs/design/v23/tooling/V23P02C10SettingsCapabilityEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23-P02-C10-tooling-manifest.json",
]
EXACT_PATH_FENCE = EXACT_SOURCE_PATHS + EXACT_TOOL_PATHS
EXACT_GENERATED_PATHS = EXACT_TOOL_PATHS[3:]
EXACT_TEST_METHODS = [
    "testV9_14G01TypedSettingsScopesMigrationAndLifecycle",
    "testV9_14A01AvailabilityReasonsPreserveHistoricEssentialOperations",
    "testV9_14H01CapabilityPermissionsConsentFallbackAndScratchAreClosed",
    "testV9_14I01InterruptionRecoveryIsIdempotentAndCreatesNoCanonicalLeak",
    "testV9_14R01HapticsAndEntryAssistRemainPrivateBoundedAndRecoverable",
]
EXACT_REASONS = [
    "AVAILABLE", "PACKAGE_NOT_ENABLED", "NOT_ENTITLED", "UNSUPPORTED_OS_OR_DEVICE",
    "PERMISSION_NOT_DETERMINED", "PERMISSION_LIMITED", "PERMISSION_DENIED",
    "PERMISSION_RESTRICTED", "OFFLINE_CONTENT_MISSING", "RECOVERY_BLOCKED",
    "WORKSPACE_POLICY_DISABLED", "PACKAGE_RETIRED", "TEMPORARILY_UNAVAILABLE",
]
EXACT_SCOPES = ["DEVICE_LOCAL", "WORKSPACE_CANONICAL", "DERIVED"]
EXACT_CAPABILITY_IDS = [
    "AUDIO_CAPTURE", "CAMERA", "DIAGNOSTICS", "FILES_AND_SHARE", "HAPTICS",
    "LOCATION", "MICROPHONE", "NOTIFICATIONS", "PHOTO_LIBRARY", "REMINDERS",
    "SCAN_OCR", "SPEECH_DICTATION", "VIDEO_CAPTURE",
]
EXACT_PERMISSION_STATES = [
    "AUTHORIZED", "DENIED", "LIMITED", "NOT_DETERMINED", "NOT_REQUIRED", "RESTRICTED",
]
EXACT_LIFECYCLE_OPERATIONS = [
    "MIGRATION", "BACKUP", "RESTORE", "CLONE", "FORK", "IMPORT", "EXPORT",
    "REPORT", "SEARCH", "RESET", "REBUILD", "REPLAY", "DELETE", "ERASE",
    "RETENTION", "COMPATIBILITY", "DOWNGRADE", "FORWARD_FIX", "INTERRUPTION_RECOVERY",
]
EXACT_LIFECYCLE_DISPOSITIONS = [
    "DEVICE_LOCAL_ONLY", "WORKSPACE_CANONICAL_INCLUDED", "EXCLUDED", "REBUILD_DERIVED",
    "RESTORE_DEFAULT", "PRESERVE_CANONICAL", "CLEAR_CANONICAL", "FAIL_CLOSED",
]
EXACT_PERSISTENCE_DISPOSITIONS = [
    "NO_CANONICAL_EFFECT_UNTIL_ACCEPTANCE", "DEVICE_LOCAL_ONLY",
    "WORKSPACE_CANONICAL_AFTER_ACCEPTANCE",
]
EXACT_DATA_DISPOSITIONS = [
    "PRIOR_HISTORY_PRESERVED", "SCRATCH_DELETED_NO_CANONICAL_EFFECT",
    "ACCEPTED_IMMUTABLE_CONTENT",
]
EXACT_REENTRY_TRIGGERS = [
    "CAPABILITY_STATE_CHANGED", "PERMISSION_CHANGED", "USER_INITIATED_RETRY",
    "MANUAL_PATH_SELECTED",
]
EXACT_REASON_ACTIONS = {
    "AVAILABLE": "BEGIN", "PACKAGE_NOT_ENABLED": "ENABLE_PACKAGE",
    "NOT_ENTITLED": "VIEW_SUBSCRIPTION",
    "UNSUPPORTED_OS_OR_DEVICE": "USE_MANUAL_PATH",
    "PERMISSION_NOT_DETERMINED": "REQUEST_PERMISSION_AT_FEATURE_BOUNDARY",
    "PERMISSION_LIMITED": "USE_MANUAL_PATH", "PERMISSION_DENIED": "OPEN_SYSTEM_SETTINGS",
    "PERMISSION_RESTRICTED": "OPEN_SYSTEM_SETTINGS",
    "OFFLINE_CONTENT_MISSING": "DOWNLOAD_BUNDLED_CONTENT",
    "RECOVERY_BLOCKED": "RECOVER_LOCAL_DATA",
    "WORKSPACE_POLICY_DISABLED": "CHANGE_WORKSPACE_POLICY",
    "PACKAGE_RETIRED": "CHOOSE_CURRENT_PACKAGE",
    "TEMPORARILY_UNAVAILABLE": "RETRY",
}
EXACT_INTERRUPTION_BOUNDARIES = [
    "BEFORE_SCRATCH_STAGING", "AFTER_SCRATCH_STAGING_BEFORE_ACCEPTANCE",
    "BEFORE_CANONICAL_PUBLICATION", "AFTER_CANONICAL_EFFECT_BEFORE_RECEIPT",
    "DURING_SUPPORT_EXPORT",
]
FALSE_FLAGS = {
    "nativeCompileRan", "hostedDispatchRan", "physicalEvidenceComplete",
    "adoptionEnabled", "acceptanceEnabled", "releaseReady", "acceptanceCredit",
    "releaseCredit", "phase10PollingDuringParallelExecution", "nativeEvidenceClaimed",
    "hostedEvidenceClaimed", "physicalEvidenceClaimed", "acceptanceClaimed",
    "releaseClaimed",
}
AUTHORITY_EXPECTED = {
    "cardID": "V23-P02-C10",
    "registerOrdinal": 30,
    "appBaseHead": "1c8b3d99826a207d3b18b3e0429231c31804f317",
    "appBaseTree": "3107903158238e5e5eaed78322c3564b06c648e2",
    "coordinationHead": "229ce1e9c7071d392760192875c6af23600b32fc",
    "coordinationTree": "cf1009737e0d90a9063a4bc20b77731d6ec219ba",
    "coordinationCASSequence": 126,
    "coordinationLedgerDigest": "e68b44ec70e97dc820772c54439507d28239d7f64c580bcb56c1f44cbccdfad6",
    "contextDigest": "30e8590878c7ebf335245cbc37e160523194a0be0cef648c125eda46e2aa294e",
    "pathFenceDigest": "9d402508388e16f092697f74de5bdc56fbe8eee6934bfa40c5eeb12675d905d7",
    "provisionalPrerequisiteDigest": "1a7d61ef7f4ceef1870050720df9ad977d35c2c48f9b0959ac613bf88526d38d",
}
EXACT_SETTING_DESCRIPTORS = [
    {"key": "device.hapticFeedback", "valueKind": "BOOLEAN", "scope": "DEVICE_LOCAL",
     "storage": "SOLE_DEVICE_PREFERENCES_ADAPTER", "backup": "EXCLUDED_DEVICE_LOCAL",
     "reset": "RESTORE_DEFAULT", "erase": "RESTORE_DEFAULT",
     "privacy": "DEVICE_PREFERENCE_NO_CUSTOMER_DATA",
     "localizationKey": "settings.hapticFeedback", "maximumCanonicalBytes": 128,
     "migrationVersion": 1},
    {"key": "device.recentInputMemory", "valueKind": "RECENT_INPUT_MEMORY",
     "scope": "DEVICE_LOCAL", "storage": "SOLE_DEVICE_PREFERENCES_ADAPTER",
     "backup": "EXCLUDED_DEVICE_LOCAL", "reset": "RESTORE_DEFAULT",
     "erase": "RESTORE_DEFAULT", "privacy": "DEVICE_PREFERENCE_NO_CUSTOMER_DATA",
     "localizationKey": "settings.recentInputMemory", "maximumCanonicalBytes": 65_536,
     "migrationVersion": 1},
]


class VerificationError(ValueError):
    pass


def read(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise VerificationError(f"missing fenced input: {relative}")
    return path.read_bytes()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load(root: Path, relative: str) -> dict[str, Any]:
    try:
        value = json.loads(read(root, relative).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise VerificationError(f"invalid JSON {relative}: {error}") from error
    if not isinstance(value, dict):
        raise VerificationError(f"JSON root is not an object: {relative}")
    return value


def check_digest(value: dict[str, Any], label: str) -> None:
    actual = value.get("artifactDigest")
    if not isinstance(actual, str) or not re.fullmatch(r"[0-9a-f]{64}", actual):
        raise VerificationError(f"{label} has no valid artifactDigest")
    body = dict(value)
    body.pop("artifactDigest", None)
    expected = digest((json.dumps(body, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8"))
    if actual != expected:
        raise VerificationError(f"{label} artifactDigest mismatch")


def exact_test_methods(root: Path) -> list[str]:
    text = read(root, c.SOURCE_PATHS[7]).decode("utf-8")
    return re.findall(r"\bfunc\s+(testV9_14[A-Za-z0-9_]+)\s*\(", text)


def source_fence_check(root: Path) -> None:
    changed = subprocess.run(["git", "-C", str(root), "diff", "--name-only", c.APP_BASE_HEAD], check=True, capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    names = {line.replace("\\", "/") for line in changed if line}
    status = subprocess.run(["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"], check=True, capture_output=True, text=True, encoding="utf-8").stdout.splitlines()
    for line in status:
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise VerificationError(f"delete/rename is not allowed: {line}")
        names.add(raw.replace("\\", "/"))
    if c.SOURCE_PATHS != EXACT_SOURCE_PATHS or c.TOOL_PATHS != EXACT_TOOL_PATHS \
            or c.PATH_FENCE != EXACT_PATH_FENCE or c.GENERATED_PATHS != EXACT_GENERATED_PATHS:
        raise VerificationError("Card30 fence constants differ from independent exact path list")
    outside = sorted(names - set(EXACT_PATH_FENCE))
    if outside:
        raise VerificationError(f"out-of-fence worktree paths: {outside}")
    if len(EXACT_PATH_FENCE) != 24 or c.EXISTING_PATHS or len(EXACT_SOURCE_PATHS) != 9 or len(EXACT_TOOL_PATHS) != 15:
        raise VerificationError("Card30 fence constants are not exact")


def strict_schema_check(schema_value: dict[str, Any], title: str) -> None:
    if schema_value.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise VerificationError(f"{title} is not Draft 2020-12")
    def walk(node: Any, path: str) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            properties = node.get("properties")
            if not isinstance(properties, dict) or node.get("additionalProperties") is not False:
                raise VerificationError(f"{title}{path} is not a closed object")
            if set(node.get("required", [])) != set(properties):
                raise VerificationError(f"{title}{path} required/properties mismatch")
            for key, child in properties.items():
                walk(child, f"{path}.{key}")
        elif node.get("type") == "array":
            prefix = node.get("prefixItems")
            if not isinstance(prefix, list) or node.get("items") is not False:
                raise VerificationError(f"{title}{path} is not a closed tuple array")
            if node.get("minItems") != node.get("maxItems") or node.get("minItems") != len(prefix):
                raise VerificationError(f"{title}{path} array bounds differ")
            for index, child in enumerate(prefix):
                walk(child, f"{path}[{index}]")
    walk(schema_value, "$")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema and (type(instance) is not type(schema["const"]) or instance != schema["const"]):
        raise VerificationError(f"{path} const mismatch")
    kind = schema.get("type")
    if kind == "object":
        if not isinstance(instance, dict):
            raise VerificationError(f"{path} is not an object")
        properties = schema["properties"]
        if set(instance) != set(properties):
            raise VerificationError(f"{path} object keys differ")
        for key, child in properties.items():
            validate_instance(instance[key], child, f"{path}.{key}")
    elif kind == "array":
        if not isinstance(instance, list) or len(instance) != len(schema["prefixItems"]):
            raise VerificationError(f"{path} array shape differs")
        for index, child in enumerate(schema["prefixItems"]):
            validate_instance(instance[index], child, f"{path}[{index}]")
    elif kind == "string":
        if not isinstance(instance, str) or ("pattern" in schema and re.fullmatch(schema["pattern"], instance) is None):
            raise VerificationError(f"{path} string/pattern mismatch")
    elif kind == "null" and instance is not None:
        raise VerificationError(f"{path} is not null")


def schema_instance(schema: dict[str, Any]) -> Any:
    if "const" in schema:
        return schema["const"]
    if schema.get("type") == "object":
        return {key: schema_instance(child) for key, child in schema["properties"].items()}
    if schema.get("type") == "array":
        return [schema_instance(child) for child in schema["prefixItems"]]
    raise VerificationError("schema does not describe an exact candidate-bound instance")


def validate_with_jsonschema(instance: Any, schema: dict[str, Any], label: str) -> None:
    try:
        import jsonschema  # type: ignore[import-not-found]
    except ImportError:
        return
    try:
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(instance)
    except (jsonschema.exceptions.SchemaError, jsonschema.exceptions.ValidationError) as error:
        raise VerificationError(f"{label} jsonschema validation failed: {error}") from error


def walk_evidence_flags(value: Any, label: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FALSE_FLAGS:
                expected = child.get("const") if isinstance(child, dict) and "const" in child else child
                if expected is not False:
                    raise VerificationError(f"{label} overclaims {key}")
            if key == "requiresAcceptedS10_6Reconciliation":
                expected = child.get("const") if isinstance(child, dict) and "const" in child else child
                if expected is not True:
                    raise VerificationError(f"{label} omits S10.6 reconciliation")
            walk_evidence_flags(child, label)
    elif isinstance(value, list):
        for child in value:
            walk_evidence_flags(child, label)


def swift_block(source: str, marker: str) -> str:
    start = source.find(marker)
    if start < 0:
        raise VerificationError(f"missing Swift declaration: {marker}")
    brace = source.find("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise VerificationError(f"unterminated Swift declaration: {marker}")


def swift_enum_values(source: str, enum_name: str) -> list[str]:
    return re.findall(r'\bcase\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"([^"]+)"',
                      swift_block(source, f"enum {enum_name}"))


def semantic_check(root: Path, docs: dict[str, dict[str, Any]], manifest: dict[str, Any]) -> None:
    settings = docs[c.SETTINGS_DOC]
    capability = docs[c.CAPABILITY_DOC]
    feature = docs[c.FEATURE_DOC]
    entry = docs[c.ENTRY_DOC]
    evidence = docs[c.EVIDENCE_DOC]
    for value, label in [(settings, "settings"), (capability, "capability"), (feature, "feature"), (entry, "entry"), (evidence, "evidence")]:
        if value.get("schemaVersion") != 1 or value.get("cardID") != "V23-P02-C10":
            raise VerificationError(f"{label} identity mismatch")
        for key, expected in AUTHORITY_EXPECTED.items():
            if value.get("authority", {}).get(key) != expected:
                raise VerificationError(f"{label} authority {key} mismatch")
        if value.get("exactFiveTests") != {
            "required": True, "methods": EXACT_TEST_METHODS, "count": 5,
        }:
            raise VerificationError(f"{label} test binding mismatch")
        if value.get("pathFence") != {
            "paths": EXACT_PATH_FENCE, "count": 24,
            "digest": AUTHORITY_EXPECTED["pathFenceDigest"], "s10Overlap": False,
        }:
            raise VerificationError(f"{label} path-fence binding mismatch")
        walk_evidence_flags(value, label)

    registry = settings.get("registry", {})
    if registry.get("scopes") != EXACT_SCOPES or registry.get("valueKinds") != ["BOOLEAN", "BOUNDED_STRING", "BOUNDED_STRING_SET", "RECENT_INPUT_MEMORY"] or registry.get("storageDispositions") != ["SOLE_DEVICE_PREFERENCES_ADAPTER", "WORKSPACE_WRITER", "NONPERSISTENT_DERIVED"]:
        raise VerificationError("settings closed vocabularies mismatch")
    if registry.get("descriptors") != EXACT_SETTING_DESCRIPTORS \
            or registry.get("keys") != ["device.hapticFeedback", "device.recentInputMemory"]:
        raise VerificationError("settings descriptor matrix differs")
    if registry.get("defaultHapticKey") != "device.hapticFeedback" or registry.get("defaultHapticValue") is not True or registry.get("defaultHapticState") != "ON":
        raise VerificationError("haptic default is not bound")
    if settings.get("scopeRules", {}).get("DEVICE_LOCAL", {}).get("backup") != "EXCLUDED_DEVICE_LOCAL" or settings.get("scopeRules", {}).get("DERIVED", {}).get("storage") != "NONPERSISTENT_DERIVED":
        raise VerificationError("settings scope rule weakened")
    lifecycle = settings.get("lifecycle", {})
    if lifecycle.get("operations") != EXACT_LIFECYCLE_OPERATIONS \
            or lifecycle.get("dispositions") != EXACT_LIFECYCLE_DISPOSITIONS:
        raise VerificationError("settings lifecycle vocabulary is not closed")
    if registry.get("registryPort") != "SettingsRegistryPortV1" or lifecycle.get("preferenceEnvelope") != {
        "type": "PreferenceStorageEnvelopeV1", "schemaVersion": 1,
        "canonicalValueAndMigrationReceiptAtomic": True,
        "migrationRequestDigestBound": True, "legacySourceDigestBound": True,
        "sameOperationConflictFailsClosed": True,
        "reservedStoragePrefixRejectedAsLegacyInput": True,
        "migrationReceiptDecodeGuards": ["NONZERO_OPERATION_ID", "DESCRIPTOR_KEY",
                                          "MIGRATION_VERSION", "CANONICAL_DIGEST_SHAPE"],
        "replayRechecksReceiptAgainstCanonicalValue": True,
    }:
        raise VerificationError("settings registry/envelope migration authority differs")

    availability = capability.get("availability", {})
    if availability.get("reasons") != EXACT_REASONS or len(availability.get("reasons", [])) != 13:
        raise VerificationError("availability reason set is not exact thirteen")
    if availability.get("blocksOnlyNewOperation") is not True or availability.get("essentialOperationsPreserved") != ["READ", "EXPORT", "BACKUP", "RESTORE", "RECOVERY", "DELETE", "ERASE"]:
        raise VerificationError("availability hides essential operation truth")
    cap = capability.get("capability", {})
    if sorted(cap.get("capabilityIDs", [])) != sorted(EXACT_CAPABILITY_IDS) \
            or cap.get("permissionStates") != sorted(EXACT_PERMISSION_STATES) \
            or cap.get("capabilityStates") != ["AVAILABLE", "INTERRUPTED", "UNAVAILABLE", "UNSUPPORTED"]:
        raise VerificationError("capability/permission state matrix differs")
    for key in ("purposeStringRequired", "firstUseOnly", "neverFirstLaunchPrompt", "neverInstallPrompt", "neverRestorePrompt", "neverBackgroundPreflightPrompt", "explicitConsentRequired", "permissionIsNotConsent", "revocationPreservesDraft"):
        if cap.get(key) is not True:
            raise VerificationError(f"capability policy missing {key}")
    if cap.get("revocationPublishesCanonical") is not False or cap.get("activeIndicator") != "FULL_CAPTURE_DURATION":
        raise VerificationError("capability interruption/publication rule mismatch")
    if cap.get("notificationRequestTiming") != "EXPLICIT_USER_INITIATED_FEATURE_BOUNDARY" \
            or cap.get("permissionRequestTimings") != ["EXPLICIT_USER_INITIATED_FEATURE_BOUNDARY", "NEVER_REQUESTED"]:
        raise VerificationError("notification/request timing boundary differs")
    scratch = capability.get("scratch", {})
    if scratch.get("purposes") != c.SCRATCH_PURPOSES or scratch.get("terminalCleanup") != c.SCRATCH_TERMINAL_EVENTS:
        raise VerificationError("scratch purpose/terminal set mismatch")
    if scratch.get("supportExportRequiresDistinctLease") is not True or scratch.get("canonicalPublicationRequiresExplicitAcceptance") is not True:
        raise VerificationError("scratch/publishing boundary weakened")
    if scratch.get("recoveryPort") != "CapabilityScratchLeasePortV1.recoverAfterInterruption" \
            or scratch.get("isolationPolicy") != "ScratchIsolationPolicyV1" \
            or scratch.get("publicationDispositions") != ["ACCEPTED_INTO_IMMUTABLE_CONTENT", "REJECTED", "CANCELLED", "EXPIRED", "FAILED"] \
            or scratch.get("capturePhases") != ["AWAITING_EXPLICIT_CONSENT", "CONSENTED_NOT_CAPTURING", "CAPTURING_INDICATOR_VISIBLE", "STOPPED", "INTERRUPTED"]:
        raise VerificationError("scratch recovery/isolation or capture transitions differ")
    if scratch.get("maximumActiveLeaseCount") != 128 \
            or scratch.get("writeReservationPerLease") is not True \
            or scratch.get("finishAndRecoveryRejectActiveWrites") is not True:
        raise VerificationError("scratch write reservation/capacity boundary differs")
    if cap.get("capabilityAwareFallbackValidation") is not True:
        raise VerificationError("capability-aware fallback validation is absent")

    policy = feature.get("policy", {})
    for key in ("signedBundleOnly", "unknownVersionFailsClosed", "missingPolicyFailsClosed", "historicAccessPreserved"):
        if policy.get(key) is not True:
            raise VerificationError(f"feature policy missing {key}")
    for key in ("remoteConfig", "network", "cohort", "releaseTestInjection"):
        if policy.get(key) is not False:
            raise VerificationError(f"feature policy permits forbidden {key}")
    resource = load(root, EXACT_SOURCE_PATHS[6])
    if policy.get("resource") != resource or policy.get("resourceDigest") != digest(read(root, EXACT_SOURCE_PATHS[6])):
        raise VerificationError("feature policy is not bound to exact resource bytes")
    if feature.get("descriptor") != {
        "stableFeatureID": True, "state": ["ENABLED", "PREPARED_DISABLED"],
        "packageRequirement": True, "capabilityRequirement": True,
        "minimumPlatformRequirement": True, "safeFallback": True,
        "exactConsumers": True,
    }:
        raise VerificationError("feature descriptor contract differs")
    if policy.get("resolutionOwner") != "FeaturePolicyResolutionV1" \
            or policy.get("noDuplicateAvailabilityAuthority") is not True \
            or feature.get("evaluation", {}).get("resolutionOwner") != "FeaturePolicyResolutionV1" \
            or feature.get("evaluation", {}).get("noDuplicateAvailabilityAuthority") is not True:
        raise VerificationError("feature policy resolution authority duplicated or absent")

    ea = entry.get("entryAssist", {})
    if (ea.get("maximumSuggestionsPerField"), ea.get("maximumEntries"), ea.get("retentionSeconds")) != (3, 128, 7_776_000):
        raise VerificationError("entry-assist bounds mismatch")
    for key in ("explicitReviewRequired", "autoSubmission", "rawFreeText", "workspaceIsolation"):
        expected = key in ("explicitReviewRequired", "workspaceIsolation")
        if ea.get(key) is not expected:
            raise VerificationError(f"entry-assist privacy rule mismatch: {key}")
    if ea.get("opaqueReferenceSyntax") != {
        "OPTION_ID": "option:<lowercase-sha256>",
        "STABLE_LOCAL_REFERENCE": "local-ref:<lowercase-uuid>",
        "canonicalDecodeRevalidates": True,
    }:
        raise VerificationError("entry-assist opaque reference syntax differs")
    haptic = entry.get("haptic", {})
    for key in ("oneGlobalPreference", "runtimeAvailabilityRequired", "safeContextRequired", "noPerFeatureKeys", "noPhysicalSensationClaim", "textIconAccessibilityPreserved"):
        if haptic.get(key) is not True:
            raise VerificationError(f"haptic privacy rule missing {key}")

    evidence_rows = evidence.get("evidence", [])
    if len(evidence_rows) != 5 or [row.get("testMethod") for row in evidence_rows] != c.TEST_METHODS:
        raise VerificationError("evidence does not bind exact five selectors")
    if evidence.get("brandImpact", {}).get("manifestCount") != 1 or evidence.get("brandImpact", {}).get("changedScreens") != [] or evidence.get("brandImpact", {}).get("changedStates") != []:
        raise VerificationError("Card30 brand impact is not zero")
    if evidence.get("interruption", {}).get("boundaries") != EXACT_INTERRUPTION_BOUNDARIES:
        raise VerificationError("interruption boundary set mismatch")
    if evidence.get("hostile") != {
        "cases": c.HOSTILE_CASES, "prohibitedTokens": c.PROHIBITED_TOKENS, "failClosed": True,
    }:
        raise VerificationError("hostile evidence is not fail-closed")

    expected_source_rows = []
    for relative in EXACT_SOURCE_PATHS:
        data = read(root, relative)
        expected_source_rows.append({
            "path": relative, "bytes": len(data), "sha256": digest(data), "present": True,
        })
    for value, label in [(settings, "settings"), (capability, "capability"),
                         (feature, "feature"), (entry, "entry"), (evidence, "evidence")]:
        if value.get("sourceBindings") != expected_source_rows:
            raise VerificationError(f"{label} source bindings differ")
    if evidence.get("sourceDigestRows") != expected_source_rows:
        raise VerificationError("evidence source digest rows differ")

    if manifest.get("pathFenceCount") != 24 or manifest.get("pathFence") != EXACT_PATH_FENCE or manifest.get("strictSchemaCount") != 6:
        raise VerificationError("manifest fence/schema count mismatch")
    if manifest.get("pendingFencePaths"):
        raise VerificationError(f"manifest has pending inputs: {manifest['pendingFencePaths']}")
    for key in ("nativeEvidenceClaimed", "hostedEvidenceClaimed", "physicalEvidenceClaimed", "acceptanceClaimed", "releaseClaimed", "noPhase10Polling"):
        if manifest.get(key) is not (key == "noPhase10Polling"):
            raise VerificationError(f"manifest flag mismatch: {key}")
    walk_evidence_flags(manifest, "manifest")


def fixture_check_value(fixture: dict[str, Any], feature_ids: list[str]) -> None:
    expected_keys = {
        "schemaVersion", "fixtureIdentity", "authority", "settingKeys", "settingScopes",
        "availabilityReasons", "availabilityScenarios", "essentialOperations", "capabilityIDs",
        "permissionStates", "captureKinds", "scratchSourcePurposes",
        "scratchTerminalDispositions", "scratchFaultEvents", "scratchExcludedConsumers",
        "featureIDs", "entryAssist", "interruptionBoundaries", "hostileCases",
    }
    if set(fixture) != expected_keys or fixture.get("schemaVersion") != 1 \
            or fixture.get("fixtureIdentity") != "V21-P02-C10-SETTINGS-CAPABILITY-CORPUS-V1":
        raise VerificationError("Card30 fixture closure/identity differs")
    if fixture.get("authority") != {
        "cardID": "V23-P02-C10", "contextDigest": AUTHORITY_EXPECTED["contextDigest"],
        "pathFenceDigest": AUTHORITY_EXPECTED["pathFenceDigest"],
    }:
        raise VerificationError("Card30 fixture authority differs")
    scenarios = fixture["availabilityScenarios"]
    if fixture["availabilityReasons"] != sorted(EXACT_REASONS) \
            or not isinstance(scenarios, list) or len(scenarios) != 13:
        raise VerificationError("fixture availability matrix is not exact thirteen")
    scenario_map = {row.get("reason"): row for row in scenarios}
    if len(scenario_map) != 13 or set(scenario_map) != set(EXACT_REASONS):
        raise VerificationError("fixture availability scenarios omit/duplicate reasons")
    scenario_keys = {
        "reason", "nextAction", "packageEnabled", "entitled", "osAndDeviceSupported",
        "permission", "offlineContentAvailable", "recoveryReady", "workspacePolicyEnabled",
        "packageRetired", "temporarilyAvailable",
    }
    for reason, action in EXACT_REASON_ACTIONS.items():
        row = scenario_map[reason]
        if set(row) != scenario_keys or row.get("nextAction") != action:
            raise VerificationError(f"fixture availability scenario differs for {reason}")
    if fixture["settingScopes"] != sorted(EXACT_SCOPES) \
            or fixture["capabilityIDs"] != sorted(EXACT_CAPABILITY_IDS) \
            or fixture["permissionStates"] != sorted(EXACT_PERMISSION_STATES):
        raise VerificationError("fixture scope/capability/permission matrices differ")
    if fixture["settingKeys"] != ["device.hapticFeedback", "device.recentInputMemory"] \
            or fixture["entryAssist"] != {
                "maximumVisiblePerField": 3, "maximumEntries": 128, "retentionDays": 90,
            }:
        raise VerificationError("fixture settings/entry-assist matrix differs")
    if fixture["interruptionBoundaries"] != sorted(EXACT_INTERRUPTION_BOUNDARIES) \
            or fixture["hostileCases"] != sorted(c.HOSTILE_CASES) \
            or len(fixture["hostileCases"]) != 16:
        raise VerificationError("fixture interruption/hostile matrix differs")
    if feature_ids != fixture["featureIDs"]:
        raise VerificationError("resource/fixture feature IDs differ")


def source_binding_check(root: Path, docs: dict[str, dict[str, Any]]) -> None:
    owner_tokens = {
        EXACT_SOURCE_PATHS[0]: ["SettingsRegistryV1", "SettingDescriptorV1", "SettingScopeV1",
                                "HapticFeedbackPreferenceV1", "EntryAssistPolicyV1", "RecentInputMemoryV1",
                                "WorkspaceSettingRecordV1", "SettingsLifecycleOperationV1",
                                "SettingLifecycleDispositionV1"],
        EXACT_SOURCE_PATHS[1]: ["FeatureAvailabilityReasonV1", "CapabilityIDV1", "CapabilityStateV1",
                                "CapabilityPermissionMatrixV1", "PermissionFallbackRegistryV1",
                                "CapabilityUseReceiptV1", "ActiveCapturePresentationContractV1",
                                "TypedAvailabilityAndFallbackReceiptV1", "FeaturePolicyResolutionV1",
                                "FallbackPersistenceDispositionV1", "FallbackDataDispositionV1",
                                "FallbackReentryTriggerV1", "ScratchIsolationPolicyV1"],
        EXACT_SOURCE_PATHS[2]: ["SettingsRegistryPortV1", "DevicePreferencesPortV1",
                                "WorkspaceCanonicalSettingPortV1", "CapabilityRuntimePortV1",
                                "PermissionRequestTriggerV1", "PermissionRequestBoundaryV1"],
        EXACT_SOURCE_PATHS[3]: ["PreferencesAdapterV1", "SettingsMigrationReceiptV1",
                                "PreferenceStorageEnvelopeV1", "PreferenceMigrationRecordV1",
                                "requestDigest", "legacySourceDigest", "!$0.hasPrefix(Self.storagePrefix)",
                                "$0.receipt.operationID != SettingsValidationV1.zeroUUID"],
        EXACT_SOURCE_PATHS[4]: ["FeaturePolicyLoaderV1", "BundleFeaturePolicyDataProviderV1"],
        EXACT_SOURCE_PATHS[5]: ["SystemCapabilityRuntimeAdapterV1", "CapabilityScratchLeaseAdapterV1",
                                "UIKitHapticRuntimeAdapterV1"],
    }
    production: dict[str, str] = {}
    for path, tokens in owner_tokens.items():
        source = read(root, path).decode("utf-8", errors="strict")
        production[path] = source
        for token in tokens:
            if token not in source:
                raise VerificationError(f"{path} omits owned symbol {token}")
    settings_source = production[EXACT_SOURCE_PATHS[0]]
    capability_source = production[EXACT_SOURCE_PATHS[1]]
    if swift_enum_values(settings_source, "SettingScopeV1") != EXACT_SCOPES:
        raise VerificationError("production SettingScopeV1 differs")
    if swift_enum_values(capability_source, "FeatureAvailabilityReasonV1") != EXACT_REASONS:
        raise VerificationError("production availability reasons differ")
    if sorted(swift_enum_values(capability_source, "CapabilityIDV1")) != sorted(EXACT_CAPABILITY_IDS):
        raise VerificationError("production capability IDs differ")
    if sorted(swift_enum_values(capability_source, "CapabilityPermissionStateV1")) != sorted(EXACT_PERMISSION_STATES):
        raise VerificationError("production permission states differ")
    if swift_enum_values(settings_source, "SettingsLifecycleOperationV1") != EXACT_LIFECYCLE_OPERATIONS \
            or swift_enum_values(settings_source, "SettingLifecycleDispositionV1") != EXACT_LIFECYCLE_DISPOSITIONS:
        raise VerificationError("production settings lifecycle vocabulary differs")
    for enum_name, expected in [
        ("FallbackPersistenceDispositionV1", EXACT_PERSISTENCE_DISPOSITIONS),
        ("FallbackDataDispositionV1", EXACT_DATA_DISPOSITIONS),
        ("FallbackReentryTriggerV1", EXACT_REENTRY_TRIGGERS),
    ]:
        if swift_enum_values(capability_source, enum_name) != expected:
            raise VerificationError(f"production {enum_name} differs")
    settings_adapter = production[EXACT_SOURCE_PATHS[3]]
    system_adapter = production[EXACT_SOURCE_PATHS[5]]
    for token in ["CompatibilityCanonicalV1.validSHA256(suffix)",
                  "uuid.uuidString.lowercased() == suffix"]:
        if token not in settings_source:
            raise VerificationError(f"production opaque reference validation omits {token}")
    for token in ["visibleFallback == expectedFallback",
                  "CapabilityPermissionMatrixV1.current()",
                  "explicitConsentRecorded == (phase != .awaitingExplicitConsent)",
                  "indicatorPersistsAcrossSceneInactivity == capturing"]:
        if token not in capability_source:
            raise VerificationError(f"production capability closure omits {token}")
    for source, type_name in [
        (settings_source, "SettingsMigrationReceiptV1"),
        (settings_source, "SettingsLifecycleReceiptV1"),
        (capability_source, "ActiveCapturePresentationContractV1"),
        (capability_source, "ScratchPublicationLinkageReceiptV1"),
        (capability_source, "TypedAvailabilityAndFallbackReceiptV1"),
    ]:
        block = swift_block(source, f"struct {type_name}")
        if "init(from decoder: any Decoder) throws" not in block or "try self.init(" not in block:
            raise VerificationError(f"{type_name} does not decode through validated initialization")
    for token in ["private var writing: Set<UUID>", "writing.insert(lease.leaseID)",
                  "!writing.contains(lease.leaseID)", "writing.isEmpty"]:
        if token not in system_adapter:
            raise VerificationError(f"production scratch reservation omits {token}")
    if "!$0.hasPrefix(Self.storagePrefix)" not in settings_adapter:
        raise VerificationError("production legacy-key reservation is absent")
    tests = read(root, EXACT_SOURCE_PATHS[7]).decode("utf-8")
    actual_tests = exact_test_methods(root)
    if actual_tests != EXACT_TEST_METHODS or c.TEST_METHODS != EXACT_TEST_METHODS:
        raise VerificationError(f"exact Card30 test selectors differ: {actual_tests}")
    test_substance = {
        EXACT_TEST_METHODS[0]: ["SettingsRegistryV1.current", "PreferencesAdapterV1", "SettingsLifecycleOperationV1.allCases", "conflictingOperation", "PreferencesAdapterV1.storagePrefix + haptic.key", "CompatibilityCanonicalV1.decode(", "SettingsLifecycleReceiptV1.self"],
        EXACT_TEST_METHODS[1]: ["FeatureAvailabilityReasonV1.allCases", "TypedAvailabilityAndFallbackReceiptV1",
                                "fallbackTestArtifactIDs", "unavailableHaptics", "capabilityID: .camera",
                                "visibleFallback: .noFallback", "TypedAvailabilityAndFallbackReceiptV1.self"],
        EXACT_TEST_METHODS[2]: ["CapabilityPermissionMatrixV1", "PermissionRequestBoundaryV1",
                                "FeaturePolicyLoaderV1", "loader.resolve(featureID:", "requestTiming",
                                "ScratchIsolationPolicyV1", "ActiveCapturePresentationContractV1", "transition(to:",
                                "indicatorAccessibilityLabelKey", "indicatorPersistsAcrossSceneInactivity",
                                "ActiveCapturePresentationContractV1.self"],
        EXACT_TEST_METHODS[3]: ["CapabilityScratchLeaseAdapterV1", "AFTER_CANONICAL_EFFECT_BEFORE_RECEIPT",
                                "createdCanonicalEffect", "adoptedExistingEffect",
                                "failNextRelease", "scratchAdapter.finish", "recoverAfterInterruption",
                                "withTaskGroup", "protection == .complete", "backupPolicy == .excluded",
                                "ScratchPublicationLinkageReceiptV1.self"],
        EXACT_TEST_METHODS[4]: ["RecentInputMemoryV1", "maximumVisiblePerField", "workspaceID",
                                "HapticFeedbackPreferenceV1.logicalDefault", "canonicalMemory",
                                "rawCustomerText", 'schemaVersion\\\":2', "CompatibilityCanonicalV1.sha256(",
                                'valueID: "option:JohnSmith"'],
    }
    for method, tokens in test_substance.items():
        block = swift_block(tests, f"func {method}")
        for token in tokens:
            if token not in block:
                raise VerificationError(f"{method} lacks substantive token {token}")
    resource = load(root, EXACT_SOURCE_PATHS[6])
    if set(resource) != {"schemaVersion", "features"} or resource.get("schemaVersion") != 1:
        raise VerificationError("FeaturePolicyV1 resource schema version mismatch")
    features = resource.get("features")
    if not isinstance(features, list) or len(features) != 6:
        raise VerificationError("FeaturePolicyV1 resource is not exact six features")
    feature_ids = [row.get("featureID") for row in features]
    if feature_ids != sorted(feature_ids) or len(feature_ids) != len(set(feature_ids)):
        raise VerificationError("FeaturePolicyV1 feature IDs are not sorted/unique")
    required_feature_keys = {"featureID", "state", "requiredPackageIDs", "requiredCapabilities",
                             "minimumPlatformMajorVersion", "safeFallback", "consumers"}
    if any(set(row) != required_feature_keys for row in features):
        raise VerificationError("FeaturePolicyV1 feature row shape differs")
    # Tests and the synthetic fixture intentionally contain hostile spellings
    # as negative-test data (for example ``cohort`` and ``remote``).  Apply
    # the production-only forbidden-token scan to the implementation/resource
    # inputs, while separately checking that the test selectors and fixture
    # bindings are present.
    for path in EXACT_SOURCE_PATHS[:7]:
        text = read(root, path).decode("utf-8", errors="ignore")
        lowered = text.lower()
        for forbidden in c.PROHIBITED_TOKENS:
            if forbidden.lower() in lowered:
                raise VerificationError(f"forbidden Card30 token {forbidden!r} in {path}")
    fixture_check_value(load(root, EXACT_SOURCE_PATHS[-1]), feature_ids)


def manifest_check(root: Path, manifest: dict[str, Any]) -> None:
    if manifest.get("existingPaths") != [] or manifest.get("newPaths") != EXACT_PATH_FENCE:
        raise VerificationError("manifest existing/new partition differs")
    if manifest.get("sourcePaths") != EXACT_SOURCE_PATHS or manifest.get("sourcePathCount") != 9:
        raise VerificationError("manifest source partition differs")
    if manifest.get("toolingPaths") != EXACT_TOOL_PATHS or manifest.get("toolingPathCount") != 15:
        raise VerificationError("manifest tooling partition differs")
    if manifest.get("generatedPaths") != EXACT_GENERATED_PATHS:
        raise VerificationError("manifest generated partition differs")
    rows = manifest.get("artifacts")
    expected_paths = EXACT_PATH_FENCE[:-1]
    if not isinstance(rows, list) or [row.get("path") for row in rows] != expected_paths \
            or len(rows) != manifest.get("artifactCount") or len(rows) != 23:
        raise VerificationError("manifest artifact row closure differs")
    expected_rows = []
    for relative in expected_paths:
        data = read(root, relative)
        expected_rows.append({"path": relative, "bytes": len(data), "sha256": digest(data)})
    if rows != expected_rows:
        raise VerificationError("manifest artifact bytes/digests differ")
    canonical_rows = (json.dumps(expected_rows, ensure_ascii=False, sort_keys=True,
                                 indent=2, allow_nan=False) + "\n").encode("utf-8")
    if manifest.get("artifactSetDigest") != digest(canonical_rows):
        raise VerificationError("manifest artifact-set digest differs")
    if manifest.get("pendingFencePaths") != [] or manifest.get("pendingArtifactCount") != 0:
        raise VerificationError("manifest retains pending artifacts")
    fence = manifest.get("fenceProof", {})
    if fence != {
        "baseHead": AUTHORITY_EXPECTED["appBaseHead"],
        "baseTree": AUTHORITY_EXPECTED["appBaseTree"],
        "pathFenceDigest": AUTHORITY_EXPECTED["pathFenceDigest"],
        "priorFenceCount": 0, "priorOwnedPathCount": 0,
        "priorFenceOverlapCount": 0, "authorizedPriorFenceOverlapCount": 0,
        "unauthorizedPriorFenceOverlapCount": 0, "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "activeS10ReservationDigest": "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a",
        "activeS10Overlap": False,
    }:
        raise VerificationError("manifest fence proof differs")
    if manifest.get("semanticCoverage") != {
        "availabilityReasonCount": 13, "settingScopeCount": 3, "exactTestCount": 5,
        "scratchPurposeCount": 4, "interruptionBoundaryCount": 5,
        "fixtureDigest": digest(read(root, EXACT_SOURCE_PATHS[-1])), "sourcePending": False,
    }:
        raise VerificationError("manifest semantic coverage differs")
    check_digest(manifest, "manifest")


def fallback_check(value: dict[str, Any]) -> None:
    for key, expected in AUTHORITY_EXPECTED.items():
        if value.get("authority", {}).get(key) != expected:
            raise VerificationError(f"fallback authority {key} mismatch")
    if value.get("schema") != "V23P02C10TypedAvailabilityFallbackReceiptV1" \
            or value.get("reasonSet") != EXACT_REASONS:
        raise VerificationError("typed fallback identity/reason set differs")
    receipt = value.get("typedReceipt", {})
    if receipt.get("candidateHead") != AUTHORITY_EXPECTED["appBaseHead"] \
            or receipt.get("candidateTree") != AUTHORITY_EXPECTED["appBaseTree"]:
        raise VerificationError("typed fallback is not exact-candidate-bound")
    if receipt.get("providerSliceDigest") != "5f6f781a3a8ead62cb7d108de688cf801a01d58802cc909e4ee118c09c029fa6":
        raise VerificationError("typed fallback is not provider-slice bound")
    if receipt.get("mandatoryCoreComplete") is not True \
            or receipt.get("persistenceDisposition") != "NO_CANONICAL_EFFECT_UNTIL_ACCEPTANCE" \
            or receipt.get("dataDisposition") != "PRIOR_HISTORY_PRESERVED" \
            or receipt.get("zeroUnsupportedPublicClaim") is not True:
        raise VerificationError("typed fallback truth semantics differ")
    for key in ("localizedVisibleStateKey", "localizedVisibleCopyKey", "localizedNextActionKey"):
        if not isinstance(receipt.get(key), str) or not receipt[key]:
            raise VerificationError(f"typed fallback omits {key}")
    for key in ("fallbackTestArtifactIDs", "evidenceArtifactIDs"):
        values = receipt.get(key)
        if not isinstance(values, list) or not values or values != sorted(values) \
                or len(values) != len(set(values)):
            raise VerificationError(f"typed fallback {key} is not nonempty sorted unique")
    if value.get("noPermissionConsentEquivalence") is not True \
            or value.get("noFallbackMediaEquivalence") is not True:
        raise VerificationError("typed fallback equivalence boundary weakened")
    semantics = value.get("typedReceiptSemantics", {})
    if semantics.get("providerSliceDigestRequired") is not True \
            or semantics.get("persistenceDispositions") != EXACT_PERSISTENCE_DISPOSITIONS \
            or semantics.get("dataDispositions") != EXACT_DATA_DISPOSITIONS \
            or semantics.get("reentryTriggers") != EXACT_REENTRY_TRIGGERS:
        raise VerificationError("typed fallback disposition vocabularies differ")
    if semantics.get("capabilityAwareFallback") != {
        "availableRequiresNoFallback": True,
        "unavailableUsesCapabilityDescriptor": True,
        "hapticsMayUseNoFallback": True,
        "cameraRequires": "CHOOSE_EXISTING_PHOTO",
    }:
        raise VerificationError("typed capability-aware fallback rules differ")
    walk_evidence_flags(value, "typed fallback")
    check_digest(value, "typed fallback")


def expect_failure(operation: Any, label: str) -> None:
    try:
        operation()
    except (VerificationError, KeyError, TypeError, ValueError):
        return
    raise VerificationError(f"hostile tamper accepted: {label}")


def hostile_tamper_check(
    root: Path,
    docs: dict[str, dict[str, Any]],
    manifest: dict[str, Any],
    schemas: dict[str, dict[str, Any]],
    fallback: dict[str, Any],
) -> None:
    import copy
    schema = copy.deepcopy(schemas[c.SETTINGS_SCHEMA])
    schema["properties"]["registry"]["additionalProperties"] = True
    expect_failure(lambda: strict_schema_check(schema, "tampered schema"), "open nested schema")
    document = copy.deepcopy(docs[c.SETTINGS_DOC])
    document.pop("registry")
    expect_failure(lambda: validate_instance(document, schemas[c.SETTINGS_SCHEMA]),
                   "document field omission")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.CAPABILITY_DOC]["availability"]["reasons"][0] = "UNKNOWN_REASON"
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "unknown availability reason")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.FEATURE_DOC]["policy"]["remoteConfig"] = True
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "remote feature policy")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.ENTRY_DOC]["entryAssist"]["maximumEntries"] = 129
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "entry-assist bound")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.EVIDENCE_DOC]["provisional"]["releaseReady"] = True
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "provisional overclaim")
    changed_manifest = copy.deepcopy(manifest)
    changed_manifest["artifacts"][0]["sha256"] = "0" * 64
    expect_failure(lambda: manifest_check(root, changed_manifest), "manifest row digest")
    changed_manifest = copy.deepcopy(manifest)
    changed_manifest["artifacts"].pop()
    expect_failure(lambda: manifest_check(root, changed_manifest), "manifest row omission")
    changed_fallback = copy.deepcopy(fallback)
    changed_fallback["typedReceipt"]["candidateHead"] = "0" * 40
    expect_failure(lambda: fallback_check(changed_fallback), "fallback candidate head")
    changed_fallback = copy.deepcopy(fallback)
    changed_fallback["typedReceipt"]["fallbackTestArtifactIDs"] = []
    expect_failure(lambda: fallback_check(changed_fallback), "fallback test evidence omission")
    changed_fallback = copy.deepcopy(fallback)
    changed_fallback["typedReceipt"]["providerSliceDigest"] = "0" * 64
    expect_failure(lambda: fallback_check(changed_fallback), "fallback provider slice digest")
    changed_fallback = copy.deepcopy(fallback)
    changed_fallback["typedReceiptSemantics"]["dataDispositions"].append("UNKNOWN")
    expect_failure(lambda: fallback_check(changed_fallback), "fallback unknown disposition")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.SETTINGS_DOC]["lifecycle"]["operations"].pop()
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "settings lifecycle operation omission")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.SETTINGS_DOC]["lifecycle"]["preferenceEnvelope"]["canonicalValueAndMigrationReceiptAtomic"] = False
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "non-atomic preference migration receipt")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.FEATURE_DOC]["evaluation"]["resolutionOwner"] = "FeatureAvailabilityPolicyV1"
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "duplicate feature availability authority")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.CAPABILITY_DOC]["capability"]["notificationRequestTiming"] = "NEVER_REQUESTED"
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "notification timing weakening")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.SETTINGS_DOC]["lifecycle"]["preferenceEnvelope"]["reservedStoragePrefixRejectedAsLegacyInput"] = False
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "reserved preference namespace accepted as legacy")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.CAPABILITY_DOC]["scratch"]["writeReservationPerLease"] = False
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "scratch write reservation removed")
    changed_docs = copy.deepcopy(docs)
    changed_docs[c.ENTRY_DOC]["entryAssist"]["opaqueReferenceSyntax"]["OPTION_ID"] = "option:<free-text>"
    expect_failure(lambda: semantic_check(root, changed_docs, manifest),
                   "entry-assist opaque reference weakened")
    changed_fallback = copy.deepcopy(fallback)
    changed_fallback["typedReceiptSemantics"]["capabilityAwareFallback"]["cameraRequires"] = "NO_FALLBACK"
    expect_failure(lambda: fallback_check(changed_fallback),
                   "camera fallback weakened")
    fixture = load(root, EXACT_SOURCE_PATHS[-1])
    feature_ids = load(root, EXACT_SOURCE_PATHS[6])["features"]
    feature_ids = [row["featureID"] for row in feature_ids]
    changed_fixture = copy.deepcopy(fixture)
    changed_fixture["availabilityScenarios"].pop()
    expect_failure(lambda: fixture_check_value(changed_fixture, feature_ids),
                   "fixture scenario omission")
    changed_fixture = copy.deepcopy(fixture)
    changed_fixture["availabilityScenarios"][0]["reason"] = "UNKNOWN_REASON"
    expect_failure(lambda: fixture_check_value(changed_fixture, feature_ids),
                   "fixture unknown reason")
    changed_fixture = copy.deepcopy(fixture)
    changed_fixture["capabilityIDs"].append("UNKNOWN_CAPABILITY")
    expect_failure(lambda: fixture_check_value(changed_fixture, feature_ids),
                   "fixture capability addition")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        source_fence_check(root)
        source_binding_check(root, {})
        generator = subprocess.run(
            [sys.executable, "-B", str(root / c.GENERATOR_SCRIPT), "--check", "--root", str(root)],
            cwd=root, capture_output=True, text=True, encoding="utf-8",
        )
        if generator.returncode != 0:
            raise VerificationError(f"generator --check failed: {generator.stdout}{generator.stderr}")
        if generator.stdout.strip() != "Card30 verified 12 deterministic artifacts":
            raise VerificationError("generator --check output differs")
        docs = {relative: load(root, relative) for relative in (c.SETTINGS_DOC, c.CAPABILITY_DOC, c.FEATURE_DOC, c.ENTRY_DOC, c.EVIDENCE_DOC)}
        schemas = {relative: load(root, relative) for relative in EXACT_GENERATED_PATHS[:6]}
        for relative in EXACT_GENERATED_PATHS:
            path = root / relative
            if not path.is_file():
                raise VerificationError(f"missing generated artifact: {relative}")
            parsed = load(root, relative)
            if relative.endswith(".schema.json"):
                strict_schema_check(parsed, relative)
                walk_evidence_flags(parsed, relative)
            else:
                check_digest(parsed, relative)
                walk_evidence_flags(parsed, relative)
        schema_pairs = [
            (c.SETTINGS_SCHEMA, docs[c.SETTINGS_DOC]),
            (c.AVAILABILITY_SCHEMA, docs[c.CAPABILITY_DOC]),
            (c.CAPABILITY_SCHEMA, docs[c.CAPABILITY_DOC]),
            (c.FEATURE_SCHEMA, docs[c.FEATURE_DOC]),
            (c.ENTRY_SCHEMA, docs[c.ENTRY_DOC]),
        ]
        for schema_path, instance in schema_pairs:
            validate_instance(instance, schemas[schema_path])
            validate_with_jsonschema(instance, schemas[schema_path], schema_path)
        semantics = c.exact_semantics(root)
        fallback = c.fallback_contract(root, semantics)
        validate_instance(fallback, schemas[c.FALLBACK_SCHEMA])
        validate_with_jsonschema(fallback, schemas[c.FALLBACK_SCHEMA], c.FALLBACK_SCHEMA)
        fallback_check(fallback)
        manifest = load(root, c.MANIFEST)
        manifest_check(root, manifest)
        semantic_check(root, docs, manifest)
        hostile_tamper_check(root, docs, manifest, schemas, fallback)
        print("Card30 hostile verifier PASS: 24 fence paths, 23 sealed inputs, 6 strict schemas, 5 evidence tests")
        return 0
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Card30 hostile verifier FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
