#!/usr/bin/env python3
"""Deterministic V23-P00-C06 platform-scope contracts."""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
from pathlib import Path
from typing import Any

from c07_contracts import (
    DEPENDENCY_DISPOSITION_DIGEST, GRAPH_DIGEST, OVERRIDE_RECEIPT_DIGEST,
    PACKAGE_DIGEST, REGISTER_DIGEST, RELATION_DIGEST, RESERVATION_DIGEST,
    SELECTOR_DIGEST, ContractError, load_reservation, pretty_bytes, seal,
    sha256_bytes, validate_frozen_authority,
)

CARD_ID = "V23-P00-C06"
BASE_HEAD = "7b72263ea2c64a8f9bace8e87872d1a293400969"
BASE_TREE = "d3fbaa46c1a35c5a52909731dfbfa30fed3b1086"
CONTEXT_DIGEST = "afbb364ed404d4fbd57ee66c5707c8f670a002b8d81cdc425cc6a0cfb3c53d60"
BOOTSTRAP_FENCE_DIGEST = "ca49bcc135ddc270e18c42b808a804a6b1de71bb8a08647b32bccd3b1a9a6eca"
HYDRATED_SPEC_DIGEST = "94d972d447cccba8e06862ba672e0e79fa2228c71382157360534afc49229497"
HYDRATED_FENCE_DIGEST = "83f17a0763528e8ecf2959be04d73015d8ec4d20300c49613d9cbb4e945960bb"
PROVISIONAL_PREREQUISITE_DIGEST = "7ae46c43ce2211c539ee701edfeaadfe56e10d89d759046e2d20f0d9c07972ee"
DOSSIER_DIGEST = "cffd38d2cb51968dc4e04002c1adda95d87893458404e0ed6a1873c5d0800554"
INHERITED_BLOCK_DIGEST = "1198e87ffa91fbc0c46781b4b3adc384ce97a92079b93d4db71045e75782625b"
LEDGER_DIGEST = "5a3b288b6a83e354a96db269d0c830e8bf654d10e1fff4a8a5fe2f5d70a8db61"
LEDGER_CAS_SEQUENCE = 39
C12_MANIFEST_DIGEST = "01e5960fafb04523557257e6286257cd7103c7481039ed3006345b9c18fc6c15"
C12_SWIFT_RECEIPT_DIGEST = "d229005282b59b5002137b09d9415555190405eec7a51e066bc6744007f11229"
C07_MANIFEST_DIGEST = "1d339540d38e8378b861ef827713d0347197219b0d133c13a8b8de5949608619"
C07_RELEASE_ABSENCE_DIGEST = "2ba91558ce2f309b10181b52509bd557d89ef08774b1e7af61ecfbeaa91c5be0"
C07_RELEASE_INVENTORY_DIGEST = "30da83dc94aebc95be69af806aa7b87cb0fe938b7fc99c048c1bac7599b389aa"

PROJECT_PATH = "FieldEvidenceApp.xcodeproj/project.pbxproj"
INFO_PATH = "FieldEvidenceApp/Info.plist"
INFO_STRINGS_PATH = "FieldEvidenceApp/InfoPlist.xcstrings"
PRIVACY_PATH = "FieldEvidenceApp/PrivacyInfo.xcprivacy"
SCHEMA_PATH = "Scripts/v23/platform-scope-manifest.schema.json"
ARTIFACT_PATH = "docs/design/v23/tooling/V23PlatformScopeManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C06-tooling-manifest.json"
TOOLING_PATHS = [
    "Scripts/v23/c06_contracts.py", "Scripts/v23/generate_c06_contracts.py",
    "Scripts/v23/verify_c06_contracts.py", SCHEMA_PATH, ARTIFACT_PATH, MANIFEST_PATH,
]
FENCED_PATHS = [*TOOLING_PATHS, INFO_PATH, INFO_STRINGS_PATH]

CAMERA_PURPOSE = "Use the camera to add sign photos to reports stored on this iPhone."
EXPECTED_ORIENTATION_VALUES = [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
]
EXPECTED_PRIVACY_REASONS = [
    {"category": "NSPrivacyAccessedAPICategoryDiskSpace", "reasons": ["E174.1"]},
    {"category": "NSPrivacyAccessedAPICategoryFileTimestamp", "reasons": ["3B52.1", "C617.1"]},
    {"category": "NSPrivacyAccessedAPICategoryUserDefaults", "reasons": ["CA92.1"]},
]
APPLE_IMPORTS = {
    "AVFoundation", "Combine", "CoreFoundation", "CoreGraphics", "CoreText",
    "CryptoKit", "Darwin", "Foundation", "ImageIO", "MessageUI", "MetricKit",
    "OSLog", "PDFKit", "PhotosUI", "StoreKit", "SwiftData", "SwiftUI", "UIKit",
    "UniformTypeIdentifiers",
}

TARGET_CONFIGURATIONS = [
    ("FieldEvidenceApp", "Debug", "A00000000000000000000062"),
    ("FieldEvidenceApp", "Release", "A00000000000000000000063"),
    ("FieldEvidenceAppTests", "Debug", "A00000000000000000000064"),
    ("FieldEvidenceAppTests", "Release", "A00000000000000000000065"),
    ("FieldEvidenceAppUITests", "Debug", "A00000000000000000000066"),
    ("FieldEvidenceAppUITests", "Release", "A00000000000000000000067"),
]

INHERITED_CONTRACTS = [
    "SupportedDeviceFamilyDispositionV1", "ShippingOrientationDispositionV1",
    "OrientationReleaseEvidenceV1", "CompatiblePlatformAvailabilityV1",
    "CompatiblePlatformEvidenceV1", "PhysicalValidationDispositionV1",
    "RuntimeFileProtectionDispositionV1", "ApplePlatformRequirementSnapshotV1",
    "SceneLifecycleDispositionV1", "LaunchScreenDispositionV1",
    "ResizableIOSCompatibilityDispositionV1", "PlatformReleaseDisclosureManifestV1",
    "ReleaseArchiveInspectionReceiptV1", "ReleaseSigningFlowCapabilityV1",
    "PrivacyReconciliationReceiptV1", "PrivacyPolicyClosureV1",
    "ThirdPartySDKInventoryV1", "DependencyProvenanceManifestV1",
    "InheritedCommerceCompatibilityReceiptV1", "StoreKitReleaseRegressionReceiptV1",
    "AppCompatibilityManifestV1", "FileProtectionReleaseClosureV1",
    "InstalledFileProtectionVerificationReceiptV1", "CrashSymbolRetentionReceiptV1",
    "AppStorePlatformInputManifestV1",
]


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST, "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST, "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST, "bootstrapPathFenceDigest": BOOTSTRAP_FENCE_DIGEST,
        "hydratedSpecDigest": HYDRATED_SPEC_DIGEST, "hydratedPathFenceDigest": HYDRATED_FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PROVISIONAL_PREREQUISITE_DIGEST,
        "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST,
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "ledgerDigest": LEDGER_DIGEST, "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False, "acceptanceEnabled": False,
        "hostedDispatchEnabled": False, "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True, "releaseCredit": False,
    }


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          capture_output=True, text=True, encoding="utf-8").stdout


def validate_fence(root: Path) -> None:
    if len(FENCED_PATHS) != 8 or len(set(FENCED_PATHS)) != 8:
        raise ContractError("C06 fence must contain exactly eight unique paths")
    reservation = load_reservation(root)
    if set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C06 fence overlaps frozen Phase10 ownership")
    changed = {p.replace("\\", "/") for p in git(root, "diff", "--name-only", BASE_HEAD).splitlines() if p}
    if not changed <= set(FENCED_PATHS):
        raise ContractError(f"C06 out-of-fence delta: {sorted(changed - set(FENCED_PATHS))}")
    for line in git(root, "status", "--porcelain=v1", "--untracked-files=all").splitlines():
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C06 contains delete/rename: {line}")
        if raw.replace("\\", "/") not in FENCED_PATHS:
            raise ContractError(f"C06 contains out-of-fence work: {raw}")


def configuration_block(project: str, object_id: str) -> str:
    match = re.search(rf"^\t\t{object_id} /\* [^*]+ \*/ = \{{\n(.*?)(?=^\t\t[A-F0-9]+ /\*|^/\* End XCBuildConfiguration section \*/)", project, re.M | re.S)
    if not match:
        raise ContractError(f"missing build configuration {object_id}")
    return match.group(1)


def configuration_setting(block: str, key: str) -> str:
    match = re.search(rf"^\s*{re.escape(key)} = (.+);$", block, re.MULTILINE)
    if not match:
        raise ContractError(f"missing explicit build setting {key}")
    return match.group(1).strip().strip('"')


def configuration_list_ids(project: str, target: str) -> list[str]:
    marker = f'/* Build configuration list for PBXNativeTarget "{target}" */ = {{'
    start = project.find(marker)
    if start < 0:
        raise ContractError(f"missing target configuration list: {target}")
    finish = project.find("\n\t\t};", start)
    if finish < 0:
        raise ContractError(f"unterminated target configuration list: {target}")
    return re.findall(r"\b(A[0-9A-F]{23}) /\* (?:Debug|Release) \*/", project[start:finish])


def target_matrix(root: Path) -> list[dict[str, Any]]:
    project = (root / PROJECT_PATH).read_text(encoding="utf-8")
    expected_by_target: dict[str, list[str]] = {}
    rows = []
    for target, configuration, object_id in TARGET_CONFIGURATIONS:
        expected_by_target.setdefault(target, []).append(object_id)
        block = configuration_block(project, object_id)
        name = re.search(r"^\s*name = ([^;]+);$", block, re.MULTILINE)
        if not name or name.group(1) != configuration:
            raise ContractError(f"C06 target/configuration mapping differs: {target}/{configuration}")
        family = configuration_setting(block, "TARGETED_DEVICE_FAMILY")
        deployment = configuration_setting(block, "IPHONEOS_DEPLOYMENT_TARGET")
        supported = configuration_setting(block, "SUPPORTED_PLATFORMS").split()
        swift = configuration_setting(block, "SWIFT_VERSION")
        if family != "1" or deployment != "18.0" or supported != ["iphoneos", "iphonesimulator"]:
            raise ContractError(f"C06 target platform setting differs: {target}/{configuration}")
        rows.append({
            "target": target, "configuration": configuration,
            "buildConfigurationObjectID": object_id,
            "targetedDeviceFamily": family,
            "supportedPlatforms": supported,
            "minimumIOS": deployment,
            "currentSwiftVersion": swift,
            "requiredArchiveUIDeviceFamily": [1],
            "staticStatus": "PASS_IPHONE_ONLY_CONFIGURATION",
        })
    for target, expected in expected_by_target.items():
        if configuration_list_ids(project, target) != expected:
            raise ContractError(f"C06 target configuration membership differs: {target}")
    if len(rows) != 6 or project.count("TARGETED_DEVICE_FAMILY = 1;") != 6:
        raise ContractError("C06 target/configuration family cardinality differs")
    return rows


def source_inventory(root: Path) -> dict[str, Any]:
    swift_paths = sorted((root / "FieldEvidenceApp").rglob("*.swift"))
    sources = [(p.relative_to(root).as_posix(), p.read_text(encoding="utf-8")) for p in swift_paths]
    project_text = (root / PROJECT_PATH).read_text(encoding="utf-8")
    privacy = sorted(p.relative_to(root).as_posix() for p in (root / "FieldEvidenceApp").rglob("PrivacyInfo.xcprivacy"))
    urls = sorted({m.group(0) for _, text in sources for m in re.finditer(r"https?://[^\s\"')]+", text)})
    placeholder_contacts = sorted({m.group(0) for _, text in sources for m in re.finditer(r"[A-Za-z0-9._%+-]+@example\.invalid", text)})
    raw_ips = sorted({m.group(0) for _, text in sources for m in re.finditer(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", text)})
    network_apis = sorted({path for path, text in sources if re.search(r"URLSession|NWConnection|Network\.framework", text)})
    storekit = sorted(path for path, text in sources if "StoreKit" in text or "AppStore.sync()" in text)
    imports = sorted({module for _, text in sources for module in re.findall(r"^import\s+([A-Za-z0-9_]+)", text, re.MULTILINE)})
    non_apple_imports = sorted(set(imports) - APPLE_IMPORTS)
    native_ipad_claims = sorted(path for path, text in sources if re.search(
        r"\b(?:native[- ]?iPad|UIDeviceFamily|TARGETED_DEVICE_FAMILY|UIScreen\.main|userInterfaceIdiom\s*==\s*\.pad)\b",
        text,
        re.IGNORECASE,
    ))
    executable_sources = [(path, re.sub(r"//.*?$|/\*.*?\*/", "", text, flags=re.M | re.S))
                          for path, text in sources]
    sync_calls = [{"path": path, "count": text.count("AppStore.sync()")}
                  for path, text in executable_sources if "AppStore.sync()" in text]
    product_ids = sorted({m.group(0) for _, text in sources for m in re.finditer(
        r"com\.palatis3\.fieldrecord\.sub\.[A-Za-z0-9._-]+", text
    )})
    package_refs = re.findall(r"XCRemoteSwiftPackageReference|XCSwiftPackageProductDependency", project_text)
    privacy_payload = plistlib.loads((root / PRIVACY_PATH).read_bytes())
    reason_rows = [{"category": row["NSPrivacyAccessedAPIType"],
                    "reasons": row["NSPrivacyAccessedAPITypeReasons"]}
                   for row in privacy_payload.get("NSPrivacyAccessedAPITypes", [])]
    permission_sources = sorted(path for path, text in sources
                                if re.search(r"requestAccess|requestAuthorization|authorizationStatus", text))
    app_configuration_facts = []
    for configuration, object_id in (("Debug", TARGET_CONFIGURATIONS[0][2]), ("Release", TARGET_CONFIGURATIONS[1][2])):
        block = configuration_block(project_text, object_id)
        app_configuration_facts.append({
            "configuration": configuration,
            "generatedInfoPlist": configuration_setting(block, "GENERATE_INFOPLIST_FILE"),
            "sourceInfoPlist": configuration_setting(block, "INFOPLIST_FILE"),
            "cameraPurpose": configuration_setting(block, "INFOPLIST_KEY_NSCameraUsageDescription"),
            "generatedSceneManifest": configuration_setting(block, "INFOPLIST_KEY_UIApplicationSceneManifest_Generation"),
            "generatedLaunchScreen": configuration_setting(block, "INFOPLIST_KEY_UILaunchScreen_Generation"),
            "bundleIdentifier": configuration_setting(block, "PRODUCT_BUNDLE_IDENTIFIER"),
            "marketingVersion": configuration_setting(block, "MARKETING_VERSION"),
            "buildVersion": configuration_setting(block, "CURRENT_PROJECT_VERSION"),
        })
    source_digest_paths = [
        PROJECT_PATH,
        INFO_PATH,
        INFO_STRINGS_PATH,
        PRIVACY_PATH,
        "FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift",
        "FieldEvidenceApp/Infrastructure/Diagnostics/MetricKitDiagnosticsAdapter.swift",
        "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift",
        "FieldEvidenceApp/Infrastructure/Commerce/StoreKitLifecycleCoordinator.swift",
        "FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift",
        "FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift",
        "FieldEvidenceApp/Domain/Commerce/EntitlementReducerV1.swift",
        "TestFixtures/StoreKit/FieldEvidence.storekit",
        "Release/ProvidedReleaseValuesV1.json",
        "Release/UnsignedRCMetadataV1.json",
    ]
    return {
        "sourceDigests": [{"path": path, "sha256": sha256_bytes((root / path).read_bytes())}
                          for path in source_digest_paths],
        "projectFacts": {
            "path": PROJECT_PATH,
            "sha256": sha256_bytes((root / PROJECT_PATH).read_bytes()),
            "reservedByActiveS10": True,
            "appConfigurations": app_configuration_facts,
            "fileSystemSynchronizedAppGroup": "PBXFileSystemSynchronizedRootGroup" in project_text,
            "infoPlistMembershipException": "membershipExceptions = (\n\t\t\t\tInfo.plist," in project_text,
            "storeKitFixtureDeclaredInApplicationResources": "FieldEvidence.storekit in Resources" in project_text,
            "entitlementsFileCount": len(list((root / "FieldEvidenceApp").rglob("*.entitlements"))),
            "explicitBackgroundModeSettingCount": project_text.count("UIBackgroundModes"),
        },
        "productionSwiftFileCount": len(swift_paths),
        "nativeIPadSourceClaimPaths": native_ipad_claims,
        "uiScreenMainReferenceCount": sum(text.count("UIScreen.main") for _, text in sources),
        "privacyManifestPaths": privacy,
        "privacyManifestCount": len(privacy),
        "privacyFacts": {"path": PRIVACY_PATH,
                         "sha256": sha256_bytes((root / PRIVACY_PATH).read_bytes()),
                         "tracking": privacy_payload.get("NSPrivacyTracking"),
                         "collectedDataTypeCount": len(privacy_payload.get("NSPrivacyCollectedDataTypes", [])),
                         "trackingDomains": privacy_payload.get("NSPrivacyTrackingDomains", []),
                         "requiredReasonAPIs": reason_rows},
        "permissionInventory": {"declaredUsageKeys": ["NSCameraUsageDescription"],
                                "cameraPurpose": CAMERA_PURPOSE,
                                "requestSourcePaths": permission_sources,
                                "firstLaunchPromptEvidence": "DEFERRED_NATIVE_ACCEPTANCE",
                                "denialAndManualFallbackEvidence": "DEFERRED_NATIVE_ACCEPTANCE"},
        "dependencyInventory": {"swiftPackageReferenceCount": package_refs.count("XCRemoteSwiftPackageReference"),
                                "swiftPackageProductCount": package_refs.count("XCSwiftPackageProductDependency"),
                                "importedModules": imports,
                                "nonAppleImportedModules": non_apple_imports,
                                "packageResolvedPresent": (root / "Package.resolved").is_file(),
                                "newSDKDisposition": "NONE_DECLARED"},
        "networkInventory": {"literalHTTPSDestinations": urls, "rawIPDestinations": raw_ips,
                             "placeholderContactValues": placeholder_contacts,
                             "placeholderReleaseLinksBlockRelease": bool(urls or placeholder_contacts),
                             "networkAPISourcePaths": network_apis,
                             "runtimeIPv6NAT64Evidence": "DEFERRED_NATIVE_ACCEPTANCE"},
        "commerceInventory": {"storeKitSourcePaths": storekit, "appStoreSyncCalls": sync_calls,
                              "productIDs": product_ids,
                              "storeKitFixtureAuthority": "CI_FIXTURE_ONLY_NOT_EXTERNAL_STORE_AUTHORITY",
                              "regressionEvidence": "DEFERRED_NATIVE_ACCEPTANCE"},
    }


def contract_rows() -> list[dict[str, Any]]:
    static = {
        "SupportedDeviceFamilyDispositionV1", "ShippingOrientationDispositionV1",
        "ApplePlatformRequirementSnapshotV1", "PrivacyReconciliationReceiptV1",
        "ThirdPartySDKInventoryV1", "DependencyProvenanceManifestV1",
        "InheritedCommerceCompatibilityReceiptV1", "AppCompatibilityManifestV1",
    }
    return [{
        "contract": name,
        "disposition": "STATIC_SOURCE_FACTS_RECORDED" if name in static else "DEFERRED_EXACT_ARCHIVE_OR_RUNTIME_EVIDENCE",
        "nativeEvidenceRequired": name not in static,
        "acceptanceSatisfied": False,
    } for name in INHERITED_CONTRACTS]


def contract_family_rows() -> list[dict[str, Any]]:
    families = [
        ("DEVICE_AND_ORIENTATION", INHERITED_CONTRACTS[0:3], "STATIC_SOURCE_FACTS_PLUS_ARCHIVE_AND_RUNTIME_DEFERRED"),
        ("COMPATIBLE_PLATFORM_AVAILABILITY", INHERITED_CONTRACTS[3:5], "OWNER_CHOICE_AND_RUNTIME_EVIDENCE_DEFERRED"),
        ("FILE_PROTECTION_AND_PHYSICAL", [
            "PhysicalValidationDispositionV1", "RuntimeFileProtectionDispositionV1",
            "FileProtectionReleaseClosureV1", "InstalledFileProtectionVerificationReceiptV1",
        ], "ARCHIVE_INSTALLED_RUNTIME_AND_PHYSICAL_EVIDENCE_DEFERRED"),
        ("APPLE_REQUIREMENT_SNAPSHOT", INHERITED_CONTRACTS[7:11], "SOURCE_GENERATION_FLAGS_OBSERVED_NATIVE_APPLICABILITY_DEFERRED"),
        ("ARCHIVE_DISCLOSURE_AND_SIGNING", [
            "PlatformReleaseDisclosureManifestV1", "ReleaseArchiveInspectionReceiptV1",
            "ReleaseSigningFlowCapabilityV1", "CrashSymbolRetentionReceiptV1",
        ], "EXACT_ARCHIVE_SIGNING_FIXTURE_AND_SYMBOL_EVIDENCE_DEFERRED"),
        ("PRIVACY_AND_DEPENDENCIES", INHERITED_CONTRACTS[14:18], "SOURCE_INVENTORY_RECORDED_ARCHIVE_POLICY_AND_STORE_FACTS_DEFERRED"),
        ("COMMERCE", INHERITED_CONTRACTS[18:20], "SOURCE_WIRING_RECORDED_EXTERNAL_STORE_AND_REGRESSION_EVIDENCE_DEFERRED"),
        ("APP_COMPATIBILITY_AND_STORE_INPUTS", [
            "AppCompatibilityManifestV1", "AppStorePlatformInputManifestV1",
        ], "SOURCE_FACTS_RECORDED_FINAL_STORE_INPUTS_DEFERRED"),
        ("NETWORK", [], "SOURCE_INVENTORY_RECORDED_IPV6_NAT64_OFFLINE_RUNTIME_DEFERRED"),
    ]
    return [{
        "familyID": family_id,
        "contracts": contracts,
        "status": status,
        "acceptanceSatisfied": False,
    } for family_id, contracts, status in families]


def deferred_evidence_rows() -> list[dict[str, Any]]:
    rows = [
        ("ARCHIVE_UIDEVICEFAMILY", "ARCHIVE", "V23-P05-C01", "NATIVE_DEVICE_FAMILY_CLAIM"),
        ("ARCHIVE_ORIENTATIONS", "ARCHIVE", "V23-P05-C01", "SHIPPING_ORIENTATION_CLAIM"),
        ("ARCHIVE_INFOPLIST", "ARCHIVE", "V23-P05-C01", "BUILT_METADATA_CLAIM"),
        ("ARCHIVE_ENTITLEMENTS_BACKGROUND", "ARCHIVE", "V23-P05-C01", "ENTITLEMENT_AND_BACKGROUND_MODE_CLAIM"),
        ("ARCHIVE_PRIVACY_REPORT", "ARCHIVE", "V23-P05-C01", "PRIVACY_RECONCILIATION_CLAIM"),
        ("ARCHIVE_LINKED_DEPENDENCIES", "ARCHIVE", "V23-P05-C01", "SDK_AND_DEPENDENCY_CLAIM"),
        ("ARCHIVE_SYMBOLS", "ARCHIVE", "V23-P05-C01", "CRASH_SYMBOL_RETENTION_CLAIM"),
        ("ARCHIVE_TEST_HOOK_SECRET_ENDPOINT_SCAN", "ARCHIVE", "V23-P05-C01", "RELEASE_ABSENCE_CLAIM"),
        ("ARCHIVE_DEFAULT_FILE_PROTECTION", "ARCHIVE", "V23-P05-C01", "DEFAULT_FILE_PROTECTION_CLAIM"),
        ("SIGNING_FLOW_FIXTURE", "NONRELEASE_SIGNING_FIXTURE", "V23-P05-C01", "NO_SOURCE_REBUILD_SIGNING_HANDOFF_CLAIM"),
        ("RUNTIME_CLEAN_INSTALL_LAUNCH", "INSTALLED_RUNTIME", "V23-P05-C01", "LAUNCH_SCREEN_CLAIM"),
        ("RUNTIME_SCENE_BACKGROUND_RESTORE", "INSTALLED_RUNTIME", "V23-P05-C01", "SCENE_LIFECYCLE_CLAIM"),
        ("RUNTIME_ORIENTATION_MATRIX", "INSTALLED_RUNTIME", "V23-P05-C01", "ORIENTATION_RUNTIME_CLAIM"),
        ("RUNTIME_COMPATIBILITY_RESIZABILITY", "INSTALLED_RUNTIME", "V23-P05-C01", "COMPATIBILITY_RESIZABILITY_CLAIM"),
        ("RUNTIME_IPAD_COMPAT_COMMON_TASK", "INSTALLED_RUNTIME", "V23-P05-C01", "IPAD_COMPATIBILITY_ONLY_CLAIM"),
        ("RUNTIME_IPV6_NAT64_OFFLINE", "INSTALLED_RUNTIME", "V23-P05-C01", "NETWORK_RUNTIME_CLAIM"),
        ("INSTALLED_FILE_PROTECTION_MATRIX", "INSTALLED_RUNTIME", "V23-P05-C02", "PER_KIND_FILE_PROTECTION_CLAIM"),
        ("PHYSICAL_LOCKED_DEVICE_PROTECTION", "PHYSICAL", "OWNER", "LOCKED_DEVICE_DATA_PROTECTION_CLAIM"),
        ("OWNER_MAC_AVAILABILITY", "OWNER", "OWNER", "APPLE_SILICON_MAC_AVAILABILITY_CLAIM"),
        ("OWNER_VISION_AVAILABILITY", "OWNER", "OWNER", "APPLE_VISION_PRO_AVAILABILITY_CLAIM"),
        ("MAC_VERIFY_COMPATIBILITY_ACTION", "EXTERNAL_STORE", "OWNER", "MAC_VERIFY_COMPATIBILITY_ACTION_CLAIM"),
        ("OWNER_PRIVACY_POLICY_URL", "OWNER", "OWNER", "LIVE_MATCHED_PRIVACY_POLICY_CLAIM"),
        ("OWNER_APP_PRIVACY_ANSWERS", "OWNER", "OWNER", "APP_PRIVACY_ANSWERS_CLAIM"),
        ("OWNER_STOREKIT_PRODUCT_CONFIGURATION", "EXTERNAL_STORE", "OWNER", "LIVE_STOREKIT_PRODUCT_CLAIM"),
        ("RELEASE_TEST_SUPPORT_ELIMINATION", "SOURCE_AND_ARCHIVE", "V23-P00-C07", "RELEASE_TEST_SUPPORT_ABSENCE_CLAIM"),
    ]
    return [{
        "evidenceID": evidence_id,
        "evidenceClass": evidence_class,
        "status": "REQUIRED_PENDING_OWNER" if evidence_class in {"OWNER", "PHYSICAL", "EXTERNAL_STORE"} else "NOT_RUN",
        "promotionOwner": owner,
        "claimBoundary": boundary,
        "blocksAcceptance": True,
    } for evidence_id, evidence_class, owner, boundary in rows]


def validate_semantics(value: dict[str, Any]) -> None:
    rows = value["inheritedContractClosure"]
    names = [row["contract"] for row in rows]
    if names != INHERITED_CONTRACTS or len(names) != 25 or len(set(names)) != 25:
        raise ContractError("C06 must close exactly 25 inherited contracts once")
    family_names = [name for family in value["contractFamilies"] for name in family["contracts"]]
    if len(family_names) != 25 or set(family_names) != set(INHERITED_CONTRACTS) or len(family_names) != len(set(family_names)):
        raise ContractError("C06 inherited contract-family allocation differs")
    if any(not row["disposition"] or row["acceptanceSatisfied"] for row in rows):
        raise ContractError("C06 contract disposition is missing or overclaims acceptance")
    if value["releaseDeviceFamily"] != "IPHONE_ONLY" or value["requiredArchiveUIDeviceFamily"] != [1]:
        raise ContractError("C06 native device family overclaim")
    if value["targetedDeviceFamily"] != "1" or value["nativeIPadSupport"] or value["upsideDownSupported"]:
        raise ContractError("C06 iPhone-only source disposition differs")
    if value["selectedOrientations"] != ["PORTRAIT", "LANDSCAPE_LEFT", "LANDSCAPE_RIGHT"]:
        raise ContractError("C06 orientation set differs")
    matrix = value["targetConfigurationMatrix"]
    if [(row["target"], row["configuration"], row["buildConfigurationObjectID"])
            for row in matrix] != TARGET_CONFIGURATIONS:
        raise ContractError("C06 target/configuration matrix differs")
    if any(
        row["targetedDeviceFamily"] != "1"
        or row["supportedPlatforms"] != ["iphoneos", "iphonesimulator"]
        or row["minimumIOS"] != "18.0"
        or row["currentSwiftVersion"] != "5.0"
        for row in matrix
    ):
        raise ContractError("C06 target platform or inherited Swift setting differs")
    inventory = value["sourceInventory"]
    privacy = inventory["privacyFacts"]
    if (
        inventory["privacyManifestPaths"] != [PRIVACY_PATH]
        or inventory["privacyManifestCount"] != 1
        or privacy["tracking"] is not False
        or privacy["collectedDataTypeCount"] != 0
        or privacy["trackingDomains"] != []
        or privacy["requiredReasonAPIs"] != EXPECTED_PRIVACY_REASONS
    ):
        raise ContractError("C06 privacy source facts differ")
    if inventory["nativeIPadSourceClaimPaths"] or inventory["uiScreenMainReferenceCount"]:
        raise ContractError("C06 source contains a native-iPad claim or UIScreen.main assumption")
    dependency = inventory["dependencyInventory"]
    if (
        dependency["swiftPackageReferenceCount"] != 0
        or dependency["swiftPackageProductCount"] != 0
        or dependency["nonAppleImportedModules"]
        or dependency["packageResolvedPresent"]
    ):
        raise ContractError("C06 undeclared dependency source differs")
    network = inventory["networkInventory"]
    if (
        network["networkAPISourcePaths"]
        or network["rawIPDestinations"]
        or network["literalHTTPSDestinations"] != [
            "https://example.invalid/privacy", "https://example.invalid/support", "https://example.invalid/terms"
        ]
        or network["placeholderContactValues"] != ["support@example.invalid"]
        or network["placeholderReleaseLinksBlockRelease"] is not True
    ):
        raise ContractError("C06 network and placeholder release-link inventory differs")
    commerce = inventory["commerceInventory"]
    if (
        commerce["appStoreSyncCalls"] != [{
            "path": "FieldEvidenceApp/Infrastructure/Commerce/StoreKitLifecycleCoordinator.swift", "count": 1
        }]
        or commerce["productIDs"] != ["com.palatis3.fieldrecord.sub.solo.monthly.v1"]
        or commerce["storeKitFixtureAuthority"] != "CI_FIXTURE_ONLY_NOT_EXTERNAL_STORE_AUTHORITY"
    ):
        raise ContractError("C06 StoreKit source inventory differs")
    project = inventory["projectFacts"]
    if (
        project["reservedByActiveS10"] is not True
        or project["fileSystemSynchronizedAppGroup"] is not True
        or project["infoPlistMembershipException"] is not True
        or project["storeKitFixtureDeclaredInApplicationResources"] is not True
        or project["entitlementsFileCount"] != 0
        or project["explicitBackgroundModeSettingCount"] != 0
    ):
        raise ContractError("C06 project source facts or Release-fixture blocker differ")
    expected_app_configuration = {
        "generatedInfoPlist": "YES",
        "sourceInfoPlist": INFO_PATH,
        "cameraPurpose": CAMERA_PURPOSE,
        "generatedSceneManifest": "YES",
        "generatedLaunchScreen": "YES",
        "bundleIdentifier": "com.palatis3.fieldrecord",
        "marketingVersion": "1.0",
        "buildVersion": "1",
    }
    if len(project["appConfigurations"]) != 2 or any(
        {key: row[key] for key in expected_app_configuration} != expected_app_configuration
        for row in project["appConfigurations"]
    ):
        raise ContractError("C06 app Info.plist generation settings differ")
    if value["infoPlist"]["orientationValues"] != EXPECTED_ORIENTATION_VALUES:
        raise ContractError("C06 Info.plist orientation source differs")
    if (
        value["infoPlistStrings"]["permissionKeys"] != ["NSCameraUsageDescription"]
        or value["infoPlistStrings"]["cameraPurpose"] != CAMERA_PURPOSE
    ):
        raise ContractError("C06 permission localization differs")
    evidence = value["deferredEvidence"]
    if evidence != deferred_evidence_rows() or len({row["evidenceID"] for row in evidence}) != len(evidence):
        raise ContractError("C06 deferred-evidence matrix differs")
    if any(row["status"] not in {"NOT_RUN", "REQUIRED_PENDING_OWNER"} or not row["blocksAcceptance"] for row in evidence):
        raise ContractError("C06 deferred evidence was promoted without proof")
    blocker = value["releaseTestSupportBlocker"]
    if (
        blocker["sourceScan"] != "FAIL_CLOSED_ACTIVE_HOOKS"
        or blocker["releaseAbsenceSatisfied"] is not False
        or blocker["reservedFindingCount"] != 206
        or blocker["unreservedFindingCount"] != 79
    ):
        raise ContractError("C06 C07 Release-test-support blocker differs")
    expected_prerequisites = {
        "C12ToolingManifestDigest": C12_MANIFEST_DIGEST,
        "SwiftLanguageModeClosureReceiptDigest": C12_SWIFT_RECEIPT_DIGEST,
        "C07ToolingManifestDigest": C07_MANIFEST_DIGEST,
        "C07ReleaseTestSupportAbsenceDigest": C07_RELEASE_ABSENCE_DIGEST,
        "C07ReleaseHookInventoryDigest": C07_RELEASE_INVENTORY_DIGEST,
    }
    if value["prerequisiteBindings"] != expected_prerequisites:
        raise ContractError("C06 prerequisite binding differs")
    expected_platform_facts = {
        "minimumRuntime": "iOS 18.0",
        "pinnedStableToolchain": "Xcode 26.6",
        "pinnedStableSimulatorRuntime": "iOS 26.5",
        "latestStableShippingRuntimeSnapshot": "iOS 26.6.1",
        "betaRuntime": "iOS/Xcode 27 DIAGNOSTIC_ONLY",
        "requirementSnapshotSource": "INHERITED_V21_P00_C06_BLOCK",
        "requirementSnapshotDisposition": "PLANNING_SNAPSHOT_ONLY_CURRENTNESS_NOT_RECHECKED",
        "observationDate": "NOT_RECORDED_IN_INCORPORATED_SOURCE",
        "recheckDeadline": "BEFORE_ARCHIVE_ACCEPTANCE_AND_IMMEDIATELY_BEFORE_UPLOAD",
        "macAvailability": "OWNER_DECISION_NOT_RUN",
        "visionAvailability": "OWNER_DECISION_NOT_RUN",
        "iPadCompatibilityMode": "DEFERRED_BOUNDED_SMOKE",
        "sceneLifecycle": "SWIFTUI_APP_LIFECYCLE_STATIC_SOURCE_ONLY",
        "launchScreen": "CONDITIONAL_NATIVE_EVIDENCE_DEFERRED",
        "resizableCompatibility": "CONDITIONAL_NATIVE_EVIDENCE_DEFERRED",
    }
    if value["platformFacts"] != expected_platform_facts:
        raise ContractError("C06 compatible-platform facts were combined or promoted")
    expected_evidence_disposition = {
        "archiveInspection": "DEFERRED_NATIVE_ACCEPTANCE",
        "installedRuntime": "DEFERRED_NATIVE_ACCEPTANCE",
        "compatibilityMode": "DEFERRED_NATIVE_ACCEPTANCE",
        "physicalLockedDevice": "REQUIRED_PENDING_OWNER",
        "signingFlowFixture": "DEFERRED_EXACT_XCODE_NONRELEASE_FIXTURE",
        "privacyPolicy": "DRAFT_LOCAL_RELEASE_BLOCKER",
        "appStoreInputs": "NOT_RUN_OWNER_ONLY",
    }
    if value["evidenceDisposition"] != expected_evidence_disposition:
        raise ContractError("C06 evidence disposition differs")
    forbidden = ("nativeCompileRan", "acceptanceEnabled", "releaseReady", "acceptanceCredit", "releaseCredit")
    if any(value[key] for key in forbidden):
        raise ContractError("C06 provisional artifact grants forbidden credit")
    if value["phase10PollingDuringParallelExecution"] is not False:
        raise ContractError("C06 provisional artifact would poll Phase10")


def build_artifact(root: Path) -> dict[str, Any]:
    validate_frozen_authority(root)
    validate_fence(root)
    c12_manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C12-tooling-manifest.json").read_text(encoding="utf-8"))
    c12_receipt = json.loads((root / "docs/design/v23/tooling/SwiftLanguageModeClosureReceiptV1.json").read_text(encoding="utf-8"))
    c07_manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C07-tooling-manifest.json").read_text(encoding="utf-8"))
    c07_absence = json.loads((root / "docs/design/v23/tooling/ReleaseTestSupportAbsenceReceiptV1.json").read_text(encoding="utf-8"))
    c07_inventory = json.loads((root / "docs/design/v23/tooling/ReleaseHookInventoryV1.json").read_text(encoding="utf-8"))
    if c12_manifest["artifactDigest"] != C12_MANIFEST_DIGEST or c12_receipt["artifactDigest"] != C12_SWIFT_RECEIPT_DIGEST:
        raise ContractError("C06 C12 prerequisite binding differs")
    if (
        c07_manifest["artifactDigest"] != C07_MANIFEST_DIGEST
        or c07_absence["artifactDigest"] != C07_RELEASE_ABSENCE_DIGEST
        or c07_inventory["artifactDigest"] != C07_RELEASE_INVENTORY_DIGEST
        or c07_inventory["releaseAbsenceSatisfied"] is not False
    ):
        raise ContractError("C06 C07 transitive Release-test-support evidence differs")
    info = plistlib.loads((root / INFO_PATH).read_bytes())
    orientations = info.get("UISupportedInterfaceOrientations")
    if orientations != EXPECTED_ORIENTATION_VALUES or "UIInterfaceOrientationPortraitUpsideDown" in orientations:
        raise ContractError("C06 source orientation declaration differs")
    strings = json.loads((root / INFO_STRINGS_PATH).read_text(encoding="utf-8"))
    camera = strings.get("strings", {}).get("NSCameraUsageDescription", {})
    purpose = camera.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
    if (
        strings.get("sourceLanguage") != "en"
        or strings.get("version") != "1.0"
        or list(strings.get("strings", {})) != ["NSCameraUsageDescription"]
        or purpose != CAMERA_PURPOSE
        or camera.get("extractionState") != "manual"
    ):
        raise ContractError("C06 camera purpose String Catalog differs")
    inventory = source_inventory(root)
    artifact = seal({
        "schema": "V23PlatformScopeManifestV1", "schemaVersion": 1, "cardID": CARD_ID,
        "authority": authority_binding(),
        "prerequisiteBindings": {"C12ToolingManifestDigest": C12_MANIFEST_DIGEST,
                                 "SwiftLanguageModeClosureReceiptDigest": C12_SWIFT_RECEIPT_DIGEST,
                                 "C07ToolingManifestDigest": C07_MANIFEST_DIGEST,
                                 "C07ReleaseTestSupportAbsenceDigest": C07_RELEASE_ABSENCE_DIGEST,
                                 "C07ReleaseHookInventoryDigest": C07_RELEASE_INVENTORY_DIGEST},
        "releaseDeviceFamily": "IPHONE_ONLY", "targetedDeviceFamily": "1",
        "requiredArchiveUIDeviceFamily": [1], "nativeIPadSupport": False,
        "selectedOrientations": ["PORTRAIT", "LANDSCAPE_LEFT", "LANDSCAPE_RIGHT"],
        "upsideDownSupported": False, "targetConfigurationMatrix": target_matrix(root),
        "infoPlist": {"path": INFO_PATH, "sha256": sha256_bytes((root / INFO_PATH).read_bytes()),
                      "orientationValues": orientations},
        "infoPlistStrings": {"path": INFO_STRINGS_PATH,
                             "sha256": sha256_bytes((root / INFO_STRINGS_PATH).read_bytes()),
                             "permissionKeys": ["NSCameraUsageDescription"], "cameraPurpose": purpose},
        "platformFacts": {
            "minimumRuntime": "iOS 18.0", "pinnedStableToolchain": "Xcode 26.6",
            "pinnedStableSimulatorRuntime": "iOS 26.5", "latestStableShippingRuntimeSnapshot": "iOS 26.6.1",
            "betaRuntime": "iOS/Xcode 27 DIAGNOSTIC_ONLY",
            "requirementSnapshotSource": "INHERITED_V21_P00_C06_BLOCK",
            "requirementSnapshotDisposition": "PLANNING_SNAPSHOT_ONLY_CURRENTNESS_NOT_RECHECKED",
            "observationDate": "NOT_RECORDED_IN_INCORPORATED_SOURCE",
            "recheckDeadline": "BEFORE_ARCHIVE_ACCEPTANCE_AND_IMMEDIATELY_BEFORE_UPLOAD",
            "macAvailability": "OWNER_DECISION_NOT_RUN",
            "visionAvailability": "OWNER_DECISION_NOT_RUN", "iPadCompatibilityMode": "DEFERRED_BOUNDED_SMOKE",
            "sceneLifecycle": "SWIFTUI_APP_LIFECYCLE_STATIC_SOURCE_ONLY",
            "launchScreen": "CONDITIONAL_NATIVE_EVIDENCE_DEFERRED",
            "resizableCompatibility": "CONDITIONAL_NATIVE_EVIDENCE_DEFERRED",
        },
        "sourceInventory": inventory,
        "inheritedContractClosure": contract_rows(),
        "contractFamilies": contract_family_rows(),
        "deferredEvidence": deferred_evidence_rows(),
        "releaseTestSupportBlocker": {
            "sourceScan": c07_absence["sourceScan"],
            "releaseAbsenceSatisfied": c07_inventory["releaseAbsenceSatisfied"],
            "reservedFindingCount": c07_absence["reservedFindingCount"],
            "unreservedFindingCount": c07_absence["unreservedFindingCount"],
            "disposition": "BLOCKS_RELEASE_AND_C06_ACCEPTANCE_PENDING_C07_REMEDIATION_AND_ARCHIVE_REPROOF",
        },
        "evidenceDisposition": {
            "archiveInspection": "DEFERRED_NATIVE_ACCEPTANCE", "installedRuntime": "DEFERRED_NATIVE_ACCEPTANCE",
            "compatibilityMode": "DEFERRED_NATIVE_ACCEPTANCE", "physicalLockedDevice": "REQUIRED_PENDING_OWNER",
            "signingFlowFixture": "DEFERRED_EXACT_XCODE_NONRELEASE_FIXTURE",
            "privacyPolicy": "DRAFT_LOCAL_RELEASE_BLOCKER", "appStoreInputs": "NOT_RUN_OWNER_ONLY",
        },
        "nativeCompileRan": False, "acceptanceEnabled": False, "releaseReady": False,
        "phase10PollingDuringParallelExecution": False,
        "provisionalDisposition": "STATIC_PLATFORM_SCOPE_GREEN_NATIVE_ARCHIVE_RUNTIME_AND_RELEASE_TEST_SUPPORT_CLOSURE_DEFERRED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    validate_semantics(artifact)
    return artifact


def build_schema(artifact: dict[str, Any]) -> dict[str, Any]:
    def kind(value: Any) -> str:
        if isinstance(value, bool): return "boolean"
        if isinstance(value, int): return "integer"
        if isinstance(value, str): return "string"
        if isinstance(value, list): return "array"
        if isinstance(value, dict): return "object"
        raise ContractError("unsupported schema type")
    properties = {}
    for key, value in artifact.items():
        if key in ("schema", "schemaVersion", "cardID", "authority", "releaseDeviceFamily",
                   "targetedDeviceFamily", "requiredArchiveUIDeviceFamily", "nativeIPadSupport",
                   "selectedOrientations", "upsideDownSupported", "nativeCompileRan", "acceptanceEnabled",
                   "releaseReady", "phase10PollingDuringParallelExecution", "acceptanceCredit", "releaseCredit"):
            properties[key] = {"const": value}
        elif key == "artifactDigest":
            properties[key] = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        else:
            properties[key] = {"type": kind(value)}
    return {"$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://assetrounds.invalid/v23/V23PlatformScopeManifestV1.schema.json",
            "title": "V23PlatformScopeManifestV1", "type": "object", "additionalProperties": False,
            "required": list(artifact), "properties": properties}


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    artifact = build_artifact(root)
    return {SCHEMA_PATH: build_schema(artifact), ARTIFACT_PATH: artifact}


def build_manifest(root: Path) -> dict[str, Any]:
    artifacts = []
    for relative in FENCED_PATHS:
        if relative == MANIFEST_PATH:
            continue
        path = root / relative
        if not path.is_file():
            raise ContractError(f"C06 manifest input missing: {relative}")
        artifacts.append({"path": relative, "sha256": sha256_bytes(path.read_bytes()), "bytes": path.stat().st_size})
    return seal({
        "schema": "V23P00C06ToolingManifestV1", "schemaVersion": 1, "cardID": CARD_ID,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "authority": authority_binding(),
        "pathFence": FENCED_PATHS, "toolingPaths": TOOLING_PATHS, "artifacts": artifacts,
        "artifactCount": len(artifacts), "nativeCompileRan": False,
        "phase10PollingDuringParallelExecution": False, "acceptanceCredit": False, "releaseCredit": False,
    })
