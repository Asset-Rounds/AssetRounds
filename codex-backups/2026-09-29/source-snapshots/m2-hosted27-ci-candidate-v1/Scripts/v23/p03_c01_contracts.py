#!/usr/bin/env python3
"""Deterministic Card 32 package-registry contracts and sealed evidence.

This module is deliberately source-derived.  The Swift package declarations,
the bundled resource, the alternate test fixture, and the five V9_11 tests are
inputs to the generated contracts; a handwritten count or package description
is never accepted as a substitute for an absent or contradictory input.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P03-C01"
TITLE = "Closed package registry, declared capabilities/guidance, and shipping-sign adapter"
ORDINAL = 32

# Frozen coordination/context values supplied by the Card32 hydration record.
COORDINATION_HEAD = "a6153aaf387226be2d26068533c09d617df6b67f"
COORDINATION_TREE = "bf3ab3063e484100604f342051fd29175f1670aa"
APP_BASE_HEAD = "05d5bac1918bdb3b48d173a9d6e574c35411829b"
APP_BASE_TREE = "a03292d69db1ee420f4cfe7fd4154b141ff35986"
COORDINATION_CAS_SEQUENCE = 136
COORDINATION_LEDGER_DIGEST = "7146308e70de3b834c8f633e1351a37ad5853f0dc1bcf8328e9ca0e115fdbaea"
HYDRATION_PROJECTION_DIGEST = "4a58d7e09b8d28eef035824eccc7f630677bf6996013763d68897b3bfe6fd17e"
CONTEXT_DIGEST = "4221ebc43e391f9b81cad953b9ab2f4c188da324e6c434a92efb2687f941a028"
FENCE_DIGEST = "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3"
PREREQUISITE_DIGEST = "dfbe448a81c15d933055d5f640c82e13ea993ccc670669e70f247d875e6726b9"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_LENGTH = 44_217
REGISTER_ROW_DIGEST = "daf6b02630cb67cbeff9c84d57d064d62bf1ce81a2c4a4c558c5af9e83bbc81a"
REGISTER_ROW_LENGTH = 271
DOSSIER_DIGEST = "4a6b946aa6bd6afdaab69fe4900e6283063bfb1ef8ee000923b30d96f50d79e2"
DOSSIER_LENGTH = 7_075
INHERITED_DIGEST = "04eca5f8e695c815d008f1f9163d06af41b4afff0473e90709f5ec7a9db91aa0"
INHERITED_LENGTH = 7_084
FOUNDATION_REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DIRECT_GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_MANIFEST_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_MANIFEST_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_MANIFEST_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DISPOSITION_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_MANIFEST_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p03-c01-contracts-v1"
GENERATOR_SEED = 230301

CONTRACT_SCRIPT = "Scripts/v23/p03_c01_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p03_c01_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p03_c01_contracts.py"
REGISTRY_SCHEMA = "Scripts/v23/package-registry.schema.json"
CAPABILITY_SCHEMA = "Scripts/v23/package-capability.schema.json"
GUIDANCE_SCHEMA = "Scripts/v23/package-guidance.schema.json"
COMPATIBILITY_SCHEMA = "Scripts/v23/package-compatibility.schema.json"
SHIPPING_SCHEMA = "Scripts/v23/shipping-sign-adapter.schema.json"
EVIDENCE_SCHEMA = "Scripts/v23/package-registry-evidence-receipt.schema.json"
REGISTRY_DOC = "docs/design/v23/tooling/V23P03C01PackageRegistryContractV2.json"
CAPABILITY_DOC = "docs/design/v23/tooling/V23P03C01CapabilityGuidanceContractV1.json"
COMPATIBILITY_DOC = "docs/design/v23/tooling/V23P03C01PackageCompatibilityContractV1.json"
SHIPPING_DOC = "docs/design/v23/tooling/V23P03C01ShippingSignAdapterContractV1.json"
EVIDENCE_DOC = "docs/design/v23/tooling/V23P03C01PackageRegistryEvidenceReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C01-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Domain/Packs/SignPack.swift",
    "FieldEvidenceApp/Domain/Packs/SignPackLoader.swift",
    "FieldEvidenceApp/Resources/Packs/IlluminatedSignPack.json",
]
NEW_SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/ShippingIlluminatedSignAdapterV1.swift",
    "FieldEvidenceAppTests/V9_11PackRegistryTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Packs/V21P03C01AlternatePackV1.json",
]
SOURCE_PATHS = EXISTING_PATHS + NEW_SOURCE_PATHS
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    REGISTRY_SCHEMA,
    CAPABILITY_SCHEMA,
    GUIDANCE_SCHEMA,
    COMPATIBILITY_SCHEMA,
    SHIPPING_SCHEMA,
    EVIDENCE_SCHEMA,
    REGISTRY_DOC,
    CAPABILITY_DOC,
    COMPATIBILITY_DOC,
    SHIPPING_DOC,
    EVIDENCE_DOC,
    MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
GENERATED_PATHS = TOOL_PATHS[3:]
NEW_PATHS = NEW_SOURCE_PATHS + TOOL_PATHS

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
EVIDENCE_FAMILIES = ("G01", "A01", "H01", "I01", "R01")

CAPABILITY_VALUES = [
    "PHOTO_CAPTURE",
    "PHOTO_IMPORT",
    "VISIBLE_ISSUE_CLASSIFICATION",
    "COULD_NOT_VERIFY",
    "RECHECK",
    "WORK_EVIDENCE",
]
PERMISSION_VALUES = ["CAMERA", "PHOTO_LIBRARY_SELECTION"]
GUIDANCE_KIND_VALUES = ["EVIDENCE", "SAFETY", "LIMITATION"]
FAILURE_VALUES = [
    "invalidValue",
    "duplicatePackageID",
    "duplicateDeclaration",
    "unknownPackage",
    "incompatiblePackage",
    "undeclaredCapability",
    "undeclaredPermission",
    "undeclaredGuidance",
    "nonCanonicalData",
    "publicationInterrupted",
    "bundledPackageUnavailable",
]
PUBLICATION_BOUNDARIES = [
    "BEFORE_VALIDATION",
    "AFTER_VALIDATION_BEFORE_PUBLICATION",
    "AFTER_PUBLICATION_BEFORE_RECEIPT",
]
PACKAGE_ID = "field.evidence.illuminated_sign.v1"
REGISTRY_NAME = "PACKAGE_REGISTRY_V2"


class ContractError(ValueError):
    """Raised when Card32 inputs cannot form a truthful closed contract."""


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def canonical(value: Any) -> bytes:
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


def _read(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise ContractError(f"missing fenced input: {relative}")
    try:
        return path.read_bytes()
    except OSError as error:
        raise ContractError(f"cannot read fenced input: {relative}: {error}") from error


def _text(root: Path, relative: str) -> str:
    try:
        return _read(root, relative).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError(f"non-UTF-8 Swift input: {relative}") from error


def _json(root: Path, relative: str) -> dict[str, Any]:
    try:
        value = json.loads(_read(root, relative))
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid JSON input {relative}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"JSON input is not an object: {relative}")
    return value


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "uiSurfaceDelta": False,
        "brandSurfaceDelta": False,
        "requiresAcceptedS10_6Reconciliation": True,
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
        "lineageSource": "V21-P03-C01",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "registerSectionDigest": REGISTER_SECTION_DIGEST,
        "registerSectionLength": REGISTER_SECTION_LENGTH,
        "registerRowDigest": REGISTER_ROW_DIGEST,
        "registerRowLength": REGISTER_ROW_LENGTH,
        "dossierDigest": DOSSIER_DIGEST,
        "dossierLength": DOSSIER_LENGTH,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "inheritedV21BlockLength": INHERITED_LENGTH,
        "foundationRegisterDigest": FOUNDATION_REGISTER_DIGEST,
        "directGraphDigest": DIRECT_GRAPH_DIGEST,
        "facetManifestDigest": FACET_MANIFEST_DIGEST,
        "selectorManifestDigest": SELECTOR_MANIFEST_DIGEST,
        "relationManifestDigest": RELATION_MANIFEST_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "impactManifestDigest": IMPACT_MANIFEST_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P02-C09"],
        "invalidationConsumers": [
            "V23-P03-C02",
            "V23-P04-C27:STATE_INVENTORY",
            "V23-P04-C29:EXACT_CANDIDATE",
            "V23-P05-C01:RELEASE_SELECTOR",
        ],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def common_fields(schema_name: str) -> dict[str, Any]:
    return {
        "schema": schema_name,
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "persistentChangeMode": "DECLARATION_ONLY",
        "persistentContractSchema": REGISTRY_NAME,
        "migrationRequired": False,
        "backupRestoreRequired": False,
        "deleteEraseRequired": False,
        "exportReportRequired": False,
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "backupBehaviorDelta": False,
        "restoreBehaviorDelta": False,
        "deleteBehaviorDelta": False,
        "exportBehaviorDelta": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisionalKernelOnly": True,
        "shippingBoundaryAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
        "noNewSwiftDataV6Entity": True,
        "phase10PollingDuringParallelExecution": False,
        **flags(),
    }


def _swift_enum_values(text: str, enum_name: str) -> list[str]:
    match = re.search(
        rf"\benum\s+{re.escape(enum_name)}\b.*?\{{(.*?)\n\}}",
        text,
        re.S,
    )
    if match is None:
        raise ContractError(f"missing Swift enum: {enum_name}")
    values = re.findall(r"\bcase\s+[A-Za-z0-9_]+\s*=\s*\"([^\"]+)\"", match.group(1))
    if not values:
        raise ContractError(f"Swift enum has no raw values: {enum_name}")
    if len(values) != len(set(values)):
        raise ContractError(f"duplicate Swift enum values: {enum_name}")
    return values


def _static_string(text: str, name: str) -> str:
    match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*\"([^\"]+)\"", text)
    if match is None:
        raise ContractError(f"missing static source value: {name}")
    return match.group(1)


def _test_methods(root: Path) -> list[str]:
    text = _text(root, NEW_SOURCE_PATHS[4])
    methods = re.findall(r"\bfunc\s+(testV9_11[A-Za-z0-9_]*)\s*\(", text)
    if len(methods) != 5 or len(set(methods)) != 5:
        raise ContractError(f"expected exactly five V9_11 methods, found {methods}")
    families = [re.search(r"testV9_11([GAHIR]01)", name).group(1) for name in methods]
    if sorted(families) != sorted(EVIDENCE_FAMILIES):
        raise ContractError(f"V9_11 evidence families differ: {methods}")
    return methods


def _source_tokens(root: Path, relative: str, tokens: list[str]) -> None:
    text = _text(root, relative)
    lowered = text.lower()
    for token in tokens:
        if token.lower() not in lowered:
            raise ContractError(f"{relative}: required source token absent: {token}")


def _guidance(adapter: str) -> list[dict[str, str]]:
    pattern = re.compile(
        r"guidanceID:\s*\"([^\"]+)\"\s*,\s*kind:\s*\.([A-Za-z0-9_]+)\s*,\s*"
        r"localizationKey:\s*\"([^\"]+)\"",
        re.S,
    )
    rows = [
        {"guidanceID": guid, "kind": kind.upper(), "localizationKey": key}
        for guid, kind, key in pattern.findall(adapter)
    ]
    if not rows:
        raise ContractError("adapter declares no guidance")
    if len({row["guidanceID"] for row in rows}) != len(rows):
        raise ContractError("adapter guidance IDs are not unique")
    if any(row["kind"] not in GUIDANCE_KIND_VALUES for row in rows):
        raise ContractError("adapter guidance kind is outside closed enum")
    return sorted(rows, key=lambda row: row["guidanceID"])


def _case_references(adapter: str, label: str) -> list[str]:
    match = re.search(rf"\b{re.escape(label)}:\s*\[(.*?)\]", adapter, re.S)
    if match is None:
        raise ContractError(f"adapter has no {label} declaration")
    return re.findall(r"\.([A-Za-z0-9_]+)", match.group(1))


def _package_projection(root: Path) -> dict[str, Any]:
    sign_pack = _text(root, EXISTING_PATHS[0])
    contracts = _text(root, NEW_SOURCE_PATHS[0])
    registry = _text(root, NEW_SOURCE_PATHS[1])
    bundled = _text(root, NEW_SOURCE_PATHS[2])
    adapter = _text(root, NEW_SOURCE_PATHS[3])
    resource = _json(root, EXISTING_PATHS[2])

    enum_capabilities = _swift_enum_values(contracts, "InspectionPackageCapabilityV2")
    enum_permissions = _swift_enum_values(contracts, "InspectionPackagePermissionV2")
    enum_guidance = _swift_enum_values(contracts, "InspectionPackageGuidanceKindV2")
    if enum_capabilities != CAPABILITY_VALUES:
        raise ContractError("capability enum differs from closed Card32 registry")
    if enum_permissions != PERMISSION_VALUES:
        raise ContractError("permission enum differs from closed Card32 registry")
    if enum_guidance != GUIDANCE_KIND_VALUES:
        raise ContractError("guidance enum differs from closed Card32 registry")
    failure_cases = re.findall(r"\bcase\s+([A-Za-z0-9_]+)\s*\n", contracts[contracts.find("enum InspectionPackageFailureV2"):])
    if failure_cases[: len(FAILURE_VALUES)] != FAILURE_VALUES:
        raise ContractError("failure enum differs from closed Card32 registry")
    if _static_string(sign_pack, "illuminatedSignPackageID") != PACKAGE_ID:
        raise ContractError("SignPack package ID declaration differs")
    if resource.get("packID") != PACKAGE_ID:
        raise ContractError("bundled illuminated-sign package ID differs")
    if resource.get("schemaVersion") != 1 or resource.get("contentVersion") != 1:
        raise ContractError("bundled illuminated-sign source version differs")
    if _static_string(contracts, "name") != REGISTRY_NAME or int(re.search(r"static\s+let\s+version\s*=\s*(\d+)", contracts).group(1)) != 2:
        raise ContractError("PACKAGE_REGISTRY_V2 source declaration differs")
    if "static let packageID = SignPack.illuminatedSignPackageID" not in adapter:
        raise ContractError("shipping adapter package ID differs")
    if _static_string(bundled, "source") != "BUNDLED_ONLY":
        raise ContractError("bundled registry source is not BUNDLED_ONLY")
    if "runtimeDownloadsAllowed = false" not in bundled:
        raise ContractError("bundled registry runtime download policy is absent")
    caps = _case_references(adapter, "capabilities")
    perms = _case_references(adapter, "permissions")
    # The source ordering is intentionally checked against sorted raw values;
    # the adapter may list cases in any source order because the initializer
    # performs the deterministic sort.
    cap_case_map = {
        "photoCapture": "PHOTO_CAPTURE",
        "photoImport": "PHOTO_IMPORT",
        "visibleIssueClassification": "VISIBLE_ISSUE_CLASSIFICATION",
        "couldNotVerify": "COULD_NOT_VERIFY",
        "recheck": "RECHECK",
        "workEvidence": "WORK_EVIDENCE",
    }
    perm_case_map = {"camera": "CAMERA", "photoLibrarySelection": "PHOTO_LIBRARY_SELECTION"}
    declared_caps = sorted(cap_case_map.get(case, "") for case in caps)
    declared_perms = sorted(perm_case_map.get(case, "") for case in perms)
    if declared_caps != sorted(CAPABILITY_VALUES) or "" in declared_caps:
        raise ContractError("shipping adapter capability declaration is incomplete")
    if declared_perms != sorted(PERMISSION_VALUES) or "" in declared_perms:
        raise ContractError("shipping adapter permission declaration is incomplete")
    guidance = _guidance(adapter)
    if "ShippingIlluminatedSignParityReceiptV1" not in adapter or "exactParity" not in adapter:
        raise ContractError("shipping adapter parity receipt is absent")
    if "InspectionPackageRegistryPublisherV2.publish" not in bundled:
        raise ContractError("bundled registry does not publish through registry publisher")
    return {
        "packageID": PACKAGE_ID,
        "sourceSchemaVersion": resource["schemaVersion"],
        "contentVersion": resource["contentVersion"],
        "inspectionPackageSchemaVersion": 2,
        "minimumRegistryVersion": 2,
        "maximumRegistryVersion": 2,
        "capabilities": sorted(CAPABILITY_VALUES),
        "permissions": sorted(PERMISSION_VALUES),
        "advisoryGuidance": guidance,
        "sourceResourcePath": EXISTING_PATHS[2],
        "sourceResourceSHA256": sha(_read(root, EXISTING_PATHS[2])),
        "sourceCanonicalSHA256": sha(canonical(resource)),
        "resourceSchema": resource.get("schemaVersion"),
        "registryName": REGISTRY_NAME,
        "registryVersion": 2,
        "maximumPackageCount": 32,
        "orderedPackageIDs": [PACKAGE_ID],
    }


def source_bindings(root: Path, package: dict[str, Any], methods: list[str]) -> list[dict[str, Any]]:
    rows = [
        (EXISTING_PATHS[0], "shipping-source", ["SignPack", "illuminatedSignV1", "illuminatedSignPackageID"], ["SignPack", "illuminatedSignV1", "illuminatedSignPackageID"]),
        (EXISTING_PATHS[1], "shipping-source-loader", ["SignPackLoader", "loadBundled", "load(data:"], ["SignPackLoader", "loadBundled", "IlluminatedSignPack"]),
        (EXISTING_PATHS[2], "shipping-resource", ["schemaVersion", "packID", "contentVersion", PACKAGE_ID], ["schemaVersion", "packID", "contentVersion", PACKAGE_ID]),
        (NEW_SOURCE_PATHS[0], "package-contracts", ["InspectionPackageV2", "InspectionPackageCapabilityV2", "InspectionPackagePermissionV2", "InspectionPackageGuidanceV2", "InspectionPackageCanonicalCodecV2", "InspectionPackageCompatibilityValidatorV2", "InspectionPackageLifecycleV2", "InspectionPackageClosedCodingV2"], ["PACKAGE_REGISTRY_V2", "DECLARATION_ONLY", "DORMANT_REVERT_ALLOWED", "canonical", "sortedKeys", "undeclaredGuidance", "requireExactKeys", "CaseIterable", "allCases", "nonCanonicalData", "contentVersion == 1"]),
        (NEW_SOURCE_PATHS[1], "package-registry", ["InspectionPackageRegistryV2", "InspectionPackageRegistryPublisherV2", "InspectionPackageRegistryPublicationReceiptV2"], ["orderedPackageIDs", "publicationReceipt", "beforeValidation", "afterValidationBeforePublication", "afterPublicationBeforeReceipt", "persistentWriteOccurred", "canonicalPackages", "recover"]),
        (NEW_SOURCE_PATHS[2], "bundled-registry", ["BundledInspectionPackageRegistryV2", "BUNDLED_ONLY", "shippingPackageIDs"], ["runtimeDownloadsAllowed", "InspectionPackageRegistryPublisherV2.publish", "bundledPackageUnavailable"]),
        (NEW_SOURCE_PATHS[3], "shipping-adapter", ["ShippingIlluminatedSignAdapterV1", "ShippingIlluminatedSignParityReceiptV1"], ["inspectionPackage", "signPack", "parityReceipt", "exactParity", "sourceCanonicalSHA256", "roundTripCanonicalSHA256"]),
        (NEW_SOURCE_PATHS[4], "evidence-tests", methods, ["XCTestCase", "XCTAssert", "XCTAssertThrowsError", "duplicate", "unknown", "publicationInterrupted", "recover"]),
        (NEW_SOURCE_PATHS[5], "alternate-fixture", ["schemaVersion", "packageID", "advisoryGuidance", "presentation"], ["schemaVersion", "packageID", "advisoryGuidance", "presentation"]),
    ]
    result: list[dict[str, Any]] = []
    for relative, owner, symbols, tokens in rows:
        _source_tokens(root, relative, tokens)
        result.append({
            "path": relative,
            "owner": owner,
            "symbols": symbols,
            "requiredTokens": tokens,
            "bytes": len(_read(root, relative)),
            "sha256": sha(_read(root, relative)),
        })
    return result


def _common_contract(schema_name: str, root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    return {
        **common_fields(schema_name),
        "package": package,
        "testMethods": methods,
        "sourceBindings": source_bindings(root, package, methods),
    }


def registry_contract(root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    value = _common_contract("V23P03C01PackageRegistryContractV2", root, package, methods)
    value.update({
        "registry": {
            "name": REGISTRY_NAME,
            "version": 2,
            "source": "BUNDLED_ONLY",
            "closed": True,
            "maximumPackageCount": 32,
            "shippingPackageIDs": [PACKAGE_ID],
            "orderedPackageIDs": [PACKAGE_ID],
            "deterministicOrdering": "SORTED_ASCENDING_PACKAGE_ID",
            "duplicatePackageIDDisposition": "FAIL_CLOSED",
            "duplicateDeclarationDisposition": "FAIL_CLOSED",
            "unknownPackageDisposition": "FAIL_CLOSED",
            "incompatiblePackageDisposition": "FAIL_CLOSED",
            "undeclaredCapabilityDisposition": "FAIL_CLOSED",
            "undeclaredPermissionDisposition": "FAIL_CLOSED",
            "runtimeDownloadsAllowed": False,
            "userAuthoredPackagesAllowed": False,
            "secondShippingVerticalAllowed": False,
            "persistentWriteOccurred": False,
            "declarationOnly": True,
            "migrationRequired": False,
            "backupRestoreRequired": False,
            "deleteEraseRequired": False,
            "exportReportRequired": False,
            "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
            "failureKinds": FAILURE_VALUES,
        },
        "coding": {
            "strictDecodable": True,
            "exactCodingKeys": True,
            "unknownKeyDisposition": "FAIL_CLOSED",
            "duplicateKeyDisposition": "FAIL_CLOSED",
            "nonCanonicalDataDisposition": "FAIL_CLOSED",
            "canonicalCodec": "InspectionPackageCanonicalCodecV2",
            "canonicalEqualityRequired": True,
            "sortedKeys": True,
            "withoutEscapingSlashes": True,
            "maximumCanonicalBytes": 1_048_576,
            "contentVersionExact": 1,
        },
        "publication": {
            "publisher": "InspectionPackageRegistryPublisherV2",
            "boundaries": PUBLICATION_BOUNDARIES,
            "interruptionDisposition": "ZERO_OR_COMPLETE_VALIDATED_RESULT",
            "retryDisposition": "DETERMINISTIC_IDEMPOTENT_RECONSTRUCTION",
            "partialPublicationAllowed": False,
            "receiptRequired": True,
        },
        "kernelBoundary": {
            "signUITypeImported": False,
            "signFeatureTypeImported": False,
            "adapterOnlyShippingResolution": True,
        },
    })
    return value


def capability_contract(root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    value = _common_contract("V23P03C01CapabilityGuidanceContractV1", root, package, methods)
    value.update({
        "capabilities": {
            "closedValues": sorted(CAPABILITY_VALUES),
            "declaredShippingValues": package["capabilities"],
            "unknownDisposition": "FAIL_CLOSED",
            "undeclaredDisposition": "FAIL_CLOSED",
            "deterministicOrdering": "SORTED_ASCENDING_RAW_VALUE",
            "allDeclared": True,
        },
        "permissions": {
            "closedValues": sorted(PERMISSION_VALUES),
            "declaredShippingValues": package["permissions"],
            "unknownDisposition": "FAIL_CLOSED",
            "undeclaredDisposition": "FAIL_CLOSED",
            "deterministicOrdering": "SORTED_ASCENDING_RAW_VALUE",
            "allDeclared": True,
        },
        "guidance": {
            "closedKinds": sorted(GUIDANCE_KIND_VALUES),
            "entries": package["advisoryGuidance"],
            "localizationKeysOnly": True,
            "userContentInGuidance": False,
            "deterministicOrdering": "SORTED_ASCENDING_GUIDANCE_ID",
            "unknownKindDisposition": "FAIL_CLOSED",
        },
        "presentation": {
            "source": "ShippingIlluminatedSignAdapterV1",
            "historicDisplayBehaviorPreserved": True,
            "localizationAndAccessibilityOwnedByPackagePresentation": True,
        },
    })
    return value


def guidance_contract(root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    value = _common_contract("V23P03C01PackageGuidanceContractV1", root, package, methods)
    value.update({
        "guidance": {
            "closedKinds": sorted(GUIDANCE_KIND_VALUES),
            "entries": package["advisoryGuidance"],
            "requiredFields": ["guidanceID", "kind", "localizationKey"],
            "identifierMaximumBytes": 120,
            "localizationKeyMaximumBytes": 200,
            "localizationKeysOnly": True,
            "controlCharactersAllowed": False,
            "duplicateDisposition": "FAIL_CLOSED",
            "unknownKindDisposition": "FAIL_CLOSED",
            "deterministicOrdering": "SORTED_ASCENDING_GUIDANCE_ID",
        },
        "advisoryOnly": True,
        "noRuntimeRuleExecution": True,
        "noUserAuthoredRules": True,
    })
    return value


def compatibility_contract(root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    value = _common_contract("V23P03C01PackageCompatibilityContractV1", root, package, methods)
    value.update({
        "compatibility": {
            "registryName": REGISTRY_NAME,
            "registryVersion": 2,
            "packageSchemaVersion": 2,
            "packageContentVersion": 1,
            "minimumRegistryVersion": 2,
            "maximumRegistryVersion": 2,
            "validationOrder": [
                "CANONICAL_DECODE",
                "SCHEMA_VERSION",
                "PACKAGE_ID",
                "CONTENT_VERSION",
                "REGISTRY_VERSION_RANGE",
                "CAPABILITY_DECLARATIONS",
                "PERMISSION_DECLARATIONS",
                "PRESENTATION_VALIDATION",
            ],
            "unknownPackageDisposition": "FAIL_CLOSED",
            "incompatiblePackageDisposition": "FAIL_CLOSED",
            "nonCanonicalDataDisposition": "FAIL_CLOSED",
            "duplicateDeclarationDisposition": "FAIL_CLOSED",
            "validationBeforeExecution": True,
            "canonicalCodec": "InspectionPackageCanonicalCodecV2",
            "sortedKeys": True,
            "withoutEscapingSlashes": True,
            "maximumCanonicalBytes": 1_048_576,
            "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
            "revertRequiresAcceptedAdapter": True,
            "strictDecoder": "InspectionPackageClosedCodingV2.requireExactKeys",
            "exactCodingKeys": True,
            "unknownKeyDisposition": "FAIL_CLOSED",
            "duplicateKeyDisposition": "FAIL_CLOSED",
            "contentVersionExact": 1,
        },
        "lifecycle": {
            "mode": "DECLARATION_ONLY",
            "schema": REGISTRY_NAME,
            "migrationRequired": False,
            "backupRestoreRequired": False,
            "deleteEraseRequired": False,
            "exportReportRequired": False,
            "persistent": False,
        },
    })
    return value


def shipping_contract(root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    value = _common_contract("V23P03C01ShippingSignAdapterContractV1", root, package, methods)
    value.update({
        "shippingAdapter": {
            "type": "ShippingIlluminatedSignAdapterV1",
            "packageID": PACKAGE_ID,
            "sourceSchemaVersion": 1,
            "sourceContentVersion": 1,
            "inspectionPackageSchemaVersion": 2,
            "exactParityRequired": True,
            "displayParityRequired": True,
            "behaviorParityRequired": True,
            "byteOrderParityRequired": True,
            "sourceResourcePath": EXISTING_PATHS[2],
            "sourceCanonicalSHA256": package["sourceCanonicalSHA256"],
            "roundTripCanonicalSHA256": package["sourceCanonicalSHA256"],
            "parityReceiptType": "ShippingIlluminatedSignParityReceiptV1",
            "parityReceiptFields": [
                "packageID",
                "sourceSchemaVersion",
                "sourceContentVersion",
                "inspectionPackageSchemaVersion",
                "sourceCanonicalSHA256",
                "roundTripCanonicalSHA256",
                "exactParity",
            ],
            "signUITypeInKernel": False,
            "adapterOnly": True,
        },
        "bundleBoundary": {
            "source": "BUNDLED_ONLY",
            "resourceName": "IlluminatedSignPack",
            "resourceExtension": "json",
            "runtimeDownloadsAllowed": False,
            "testOnlyAlternateInProduction": False,
        },
    })
    return value


def evidence_contract(root: Path, package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    fixture = _json(root, NEW_SOURCE_PATHS[5])
    if fixture.get("schemaVersion") != 2 or fixture.get("packageID") == PACKAGE_ID:
        raise ContractError("alternate fixture does not prove a distinct schema-2 package")
    value = _common_contract("V23P03C01PackageRegistryEvidenceReceiptV1", root, package, methods)
    value.update({
        "evidence": [
            {
                "evidenceID": evidence_id,
                "family": family,
                "testMethod": method,
                "requiredOutcome": {
                    "G01": "CLOSED_BUNDLED_REGISTRY_AND_EXACT_ILLUMINATED_SIGN_PARITY",
                    "A01": "EXPLICIT_CAPABILITY_PERMISSION_GUIDANCE_AND_COMPATIBILITY_DECLARATIONS",
                    "H01": "DUPLICATE_UNKNOWN_INCOMPATIBLE_AND_ALTERNATE_FIXTURE_INPUTS_FAIL_CLOSED",
                    "I01": "EVERY_PUBLICATION_BOUNDARY_RELAUNCHES_TO_ZERO_OR_COMPLETE_VALIDATED_RESULT",
                    "R01": "DORMANT_DECLARATION_LIFECYCLE_AND_ADAPTER_RESOLUTION_REMAIN_DETERMINISTIC",
                }[family],
            }
            for evidence_id, family, method in zip(EVIDENCE_IDS, EVIDENCE_FAMILIES, methods)
        ],
        "hostileCases": [
            "DUPLICATE_PACKAGE_ID",
            "DUPLICATE_DECLARATION",
            "UNKNOWN_PACKAGE_ID",
            "INCOMPATIBLE_SCHEMA_OR_REGISTRY_RANGE",
            "UNDECLARED_CAPABILITY",
            "UNDECLARED_PERMISSION",
            "NON_CANONICAL_DATA",
            "ALTERNATE_FIXTURE_PRODUCTION_BUNDLE_ABSENCE",
            "ALTERNATE_FIXTURE_PRODUCTION_REGISTRY_ABSENCE",
            "KERNEL_SIGN_UI_DEPENDENCY_ABSENCE",
        ],
        "interruptionBoundaries": PUBLICATION_BOUNDARIES,
        "interruptionPolicy": {
            "deterministic": True,
            "idempotent": True,
            "partialAcceptedState": False,
            "zeroOrCompleteValidatedResult": True,
            "relaunchContinuation": "RECONSTRUCT_OR_FAIL_CLOSED",
        },
        "alternateFixture": {
            "path": NEW_SOURCE_PATHS[5],
            "schemaVersion": fixture["schemaVersion"],
            "packageID": fixture["packageID"],
            "productionBundlePath": EXISTING_PATHS[2],
            "productionRegistryPath": NEW_SOURCE_PATHS[2],
            "testOnly": True,
            "productionBundleMember": False,
            "productionRegistryMember": False,
            "exactAbsenceProofRequired": True,
        },
        "brandImpact": {
            "manifestType": "BrandImpactManifestV1",
            "manifestCount": 1,
            "changedScreens": [],
            "changedStates": [],
            "affectedConsumers": ["V23-P03-C02", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
            "completenessRationale": "No UI, project metadata, or launch composition changes are included; the closed consumer set is explicit.",
        },
        "privacy": {
            "customerDataInDiagnostics": False,
            "secretsInContracts": False,
            "networkTransport": False,
            "downloadedPackageBytes": False,
            "userAuthoredRules": False,
        },
        "sourceBindingDigest": sha(canonical(source_bindings(root, package, methods))),
    })
    return value


def _strict(value: Any, key: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {name: _strict(child, name) for name, child in value.items()},
        }
    if isinstance(value, list):
        return {
            "type": "array",
            "minItems": len(value),
            "maxItems": len(value),
            "prefixItems": [_strict(item) for item in value],
            "items": False,
        }
    if key == "artifactDigest" or key.lower().endswith("digest") or key.lower().endswith("sha256"):
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"const": value}
    if isinstance(value, int):
        return {"const": value}
    if isinstance(value, str):
        return {"const": value}
    raise ContractError(f"unsupported schema value at {key}: {type(value).__name__}")


def _schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{title}.schema.json",
        "title": title,
    })
    return result


def _artifact_rows(root: Path, generated: dict[str, bytes]) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    pending: list[str] = []
    for relative in MANIFEST_INPUT_PATHS:
        data = generated.get(relative)
        if data is None:
            path = root / relative
            if not path.is_file():
                pending.append(relative)
                continue
            data = path.read_bytes()
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return rows, pending


def tooling_manifest(root: Path, generated: dict[str, bytes], package: dict[str, Any], methods: list[str]) -> dict[str, Any]:
    rows, pending = _artifact_rows(root, generated)
    return seal({
        **common_fields("V23-P03-C01-tooling-manifest"),
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
            "allowedPathCount": 24,
            "existingPathCount": 3,
            "newPathCount": 21,
            "priorFenceOverlapCount": 0,
            "authorizedPriorFenceOverlapCount": 0,
            "unauthorizedPriorFenceOverlapCount": 0,
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "activeS10ReservationDigest": S10_RESERVATION_DIGEST,
            "activeS10Overlap": False,
        },
        "packageRegistry": package,
        "testMethods": methods,
        "evidenceIDs": EVIDENCE_IDS,
        "persistentContractSchema": REGISTRY_NAME,
        "persistentChangeMode": "DECLARATION_ONLY",
        "migrationRequired": False,
        "backupRestoreRequired": False,
        "deleteEraseRequired": False,
        "exportReportRequired": False,
        "privacyAllowlistOnly": True,
        "noNetwork": True,
        "noRuntimeDownloads": True,
        "noNewSwiftDataV6Entity": True,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "provisional": True,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    package = _package_projection(root)
    methods = _test_methods(root)
    registry = registry_contract(root, package, methods)
    capability = capability_contract(root, package, methods)
    guidance = guidance_contract(root, package, methods)
    compatibility = compatibility_contract(root, package, methods)
    shipping = shipping_contract(root, package, methods)
    evidence = evidence_contract(root, package, methods)
    registry_document = seal(registry)
    capability_document = seal(capability)
    compatibility_document = seal(compatibility)
    shipping_document = seal(shipping)
    evidence_document = seal(evidence)
    generated: dict[str, bytes] = {
        REGISTRY_SCHEMA: pretty(_schema("V23P03C01PackageRegistryContractV2", registry_document)),
        CAPABILITY_SCHEMA: pretty(_schema("V23P03C01CapabilityGuidanceContractV1", capability_document)),
        GUIDANCE_SCHEMA: pretty(_schema("V23P03C01PackageGuidanceContractV1", guidance)),
        COMPATIBILITY_SCHEMA: pretty(_schema("V23P03C01PackageCompatibilityContractV1", compatibility_document)),
        SHIPPING_SCHEMA: pretty(_schema("V23P03C01ShippingSignAdapterContractV1", shipping_document)),
        EVIDENCE_SCHEMA: pretty(_schema("V23P03C01PackageRegistryEvidenceReceiptV1", evidence_document)),
        REGISTRY_DOC: pretty(registry_document),
        CAPABILITY_DOC: pretty(capability_document),
        COMPATIBILITY_DOC: pretty(compatibility_document),
        SHIPPING_DOC: pretty(shipping_document),
        EVIDENCE_DOC: pretty(evidence_document),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated, package, methods))
    return generated
