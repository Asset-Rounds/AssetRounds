#!/usr/bin/env python3
"""Deterministic provisional artifacts for V23-P03-C16."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C16"
TITLE = "Compiler-extracted String Catalog keys, exact shipping-locale truth, locale-aware units, frozen display, and semantic accessibility IDs"
APP_BASE_HEAD = "b8cda42978df63fc5ae1c9b786ffb4a80410407f"
APP_BASE_TREE = "027cae683452fde2cfae6e1b575f146ab87fba2d"
CONTEXT_DIGEST = "3f2a69f78720190a186e800a3d1b206e498fbe1f28329a4a5c12bbec946a3ae6"
FENCE_DIGEST = "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43"
PREREQUISITE_DIGEST = "7fa6f4843f91a21f43be3059e6a16e2612b1195f3bc61ccbb4f109847069c1b9"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
REGISTER_ROW_DIGEST = "e96ddc7f9eb9052b7dce758c8c4986b456098f3482a348a4de5fbd2e9fcb6459"
DOSSIER_DIGEST = "851dea838763020ced4b268647c9d2515b07d02518b64589d1211df573ec1ea5"
INHERITED_BLOCK_DIGEST = "0cde2b63bff18ee4eadc25ff96c6a3aeaa2cf5e465741d6187c0a1b6ebfa5fc9"

PATH_FENCE = [
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppUITests/V23_P03_C16LocalizationAccessibilityUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Localization/V21P03C16LocalizationAccessibilityCorpusV1.json",
    "Scripts/v23/p03_c16_contracts.py",
    "Scripts/v23/generate_p03_c16_contracts.py",
    "Scripts/v23/verify_p03_c16_contracts.py",
    "Scripts/v23/localization-accessibility.schema.json",
    "docs/design/v23/tooling/V23P03C16LocalizationAccessibilityContractV1.json",
    "docs/design/v23/tooling/V23P03C16LocalizationAccessibilityEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P03C16BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P03-C16-tooling-manifest.json",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
    "FieldEvidenceAppTests/V9_11PackRegistryTests.swift",
    "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift",
]
NEW_PATHS = PATH_FENCE[:15]
EXISTING_PATHS = PATH_FENCE[15:]
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C16LocalizationAccessibilityContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C16LocalizationAccessibilityEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C16BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C16-tooling-manifest.json"
OUTPUT_PATHS = [CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH]
SOURCE_PATHS = [path for path in PATH_FENCE if path not in OUTPUT_PATHS]
MANIFEST_INPUT_PATHS = [path for path in PATH_FENCE if path != MANIFEST_PATH]
CATALOG_PATH = PATH_FENCE[0]
FIXTURE_PATH = PATH_FENCE[6]
SCHEMA_PATH = PATH_FENCE[10]
SWIFT_TEST_PATH = PATH_FENCE[4]
UI_TEST_PATH = PATH_FENCE[5]

CATALOG_KEYS = [
    "common.done",
    "feedback.mail.attachment_count",
    "feedback.mail.body_template",
    "feedback.mail.composer.title",
    "feedback.mail.message.heading",
    "feedback.mail.message.label",
    "feedback.mail.recipient",
    "feedback.mail.subject",
    "package.illuminated_sign.guidance.authorized_position",
    "package.illuminated_sign.guidance.required_views",
    "package.illuminated_sign.guidance.visible_conditions_only",
]
PACKAGE_KEYS = [
    "package.illuminated_sign.guidance.required_views",
    "package.illuminated_sign.guidance.visible_conditions_only",
    "package.illuminated_sign.guidance.authorized_position",
]
LEGACY_MAIL_IDS = [
    "s8.4.mail.screen",
    "s8.4.mail.recipient",
    "s8.4.mail.attachment-count",
    "s8.4.mail.body",
    "s8.4.mail.done",
]
SEMANTIC_MAIL_IDS = [
    "feedback.mail.attachment-count",
    "feedback.mail.body",
    "feedback.mail.done",
    "feedback.mail.recipient",
    "feedback.mail.screen",
]
PSEUDO_LOCALES = ["ar-XB", "en-XA", "en-XB", "en-XL", "en-XT"]
EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_22G01CompilerExtractedCatalogAndShippingLocaleTruth",
    "testV9_22A01TestOnlyPseudoLocalesAndLocaleAwarePresentationRemainBounded",
    "testV9_22H01MissingDuplicateReassignedAndLocaleDriftInputsFailClosed",
    "testV9_22I01InterruptedExtractionLeavesNoPartialCatalogOrBinding",
    "testV9_22R01FrozenDisplayAndPackageDigestsRecoverIdempotently",
]
UI_TEST_METHODS = [
    "testV23P03C16G01CompilerCatalogAndShippingLocaleUI",
    "testV23P03C16A01PseudoLocaleAndRTLUI",
    "testV23P03C16H01HostileAccessibilityAndLocaleUI",
    "testV23P03C16I01InterruptedCatalogUI",
    "testV23P03C16R01FrozenDisplayAndRecoveryUI",
]
CHECKS = [
    "EXACT_18_PATH_FENCE_15_NEW_3_EXISTING_AND_ZERO_S10_OVERLAP",
    "SOLE_APPLICATION_LOCALIZABLE_XCSTRINGS_WITH_EXACT_EN_ONLY_CATALOG",
    "ELEVEN_TYPED_LITERAL_COMPILER_EXTRACTION_KEYS_AND_COMMENTS",
    "INFOPLIST_XCSTRINGS_READ_ONLY_P00_C06_INPUT",
    "SEMANTIC_ACCESSIBILITY_REGISTRY_AND_EXACT_FIVE_ID_LEGACY_NO_GROWTH_RATCHET",
    "SHIPPING_PACKAGE_RELEASE_SIDECAR_BINDS_THREE_LOCALIZATION_KEYS_WITHOUT_SCHEMA_CHANGE",
    "LOCALE_AWARE_PRESENTATION_AND_TEST_ONLY_PSEUDO_LOCALES",
    "FROZEN_HISTORIC_DISPLAY_AND_CANONICAL_BYTES_NEVER_RELOCALIZED",
    "ZERO_OR_COMPLETE_INTERRUPTION_AND_IDEMPOTENT_RECOVERY",
    "EXACT_FIVE_G01_A01_H01_I01_R01_UNIT_AND_HONEST_DEFERRED_UI_SELECTORS",
    "STATIC_ONLY_NO_CREDIT_AND_POST_S10_6_RECONCILIATION_REQUIRED",
]


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def artifact(path: str, raw: bytes) -> dict[str, Any]:
    return {"path": path, "bytes": len(raw), "sha256": sha256(raw)}


def seal(unsigned: dict[str, Any]) -> dict[str, Any]:
    return {**unsigned, "artifactDigest": sha256(pretty(unsigned))}


def load(root: Path, relative: str) -> Any:
    return json.loads((root / relative).read_text(encoding="utf-8"))


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "s10ReservationDigest": S10_RESERVATION_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST,
    }


def flags() -> dict[str, Any]:
    return {
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False,
        "hostedDispatchEnabled": False, "hostedDispatchRan": False,
        "adoptionEnabled": False, "acceptanceEnabled": False,
        "implementationCredit": False, "acceptanceCredit": False,
        "releaseCredit": False, "releaseReady": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing source artifact: {relative}")
        rows.append(artifact(relative, path.read_bytes()))
    return rows


def contract(root: Path) -> dict[str, Any]:
    catalog = load(root, CATALOG_PATH)
    fixture = load(root, FIXTURE_PATH)
    unsigned = {
        "schema": "V23P03C16LocalizationAccessibilityContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "pathFence": PATH_FENCE, "existingPaths": EXISTING_PATHS, "newPaths": NEW_PATHS,
        "lifecycle": {
            "mode": "NONPERSISTENT_IMMUTABLE_BUILD_AUTHORITY",
            "persistent": False, "writerCommand": "NOT_APPLICABLE",
            "migration": "NOT_APPLICABLE", "backupRestore": "NOT_APPLICABLE",
            "replaceRestore": "NOT_APPLICABLE", "cloneFork": "NOT_APPLICABLE",
            "journal": "NOT_APPLICABLE", "search": "NOT_APPLICABLE",
            "deleteErase": "NOT_APPLICABLE", "retention": "PROCESS_LIFETIME_ONLY",
            "rebuild": "DETERMINISTIC_REBUILD_FROM_BUNDLE",
            "interruption": "ZERO_OR_COMPLETE",
            "idempotency": "EXACT_CANONICAL_BYTES_ADOPTION",
            "schemaBehaviorDelta": False, "persistentWriteOccurred": False,
        },
        "localization": {
            "applicationCatalogCount": 1, "applicationCatalogPath": CATALOG_PATH,
            "sourceLanguage": catalog["sourceLanguage"], "shippingRuntimeLocales": ["en"],
            "completeCatalogLocales": ["en"], "appStorePrimaryLocale": "en-US",
            "pseudoLocales": PSEUDO_LOCALES, "pseudoLocalesShipping": False,
            "compilerExtractionRequired": True, "exportLocalizationsEqualityRequired": True,
            "compilerExtractionEvidence": "NOT_RUN_NO_CREDIT_WINDOWS_STATIC_ONLY",
            "exportLocalizationsEvidence": "NOT_RUN_NO_CREDIT_WINDOWS_STATIC_ONLY",
            "catalogKeys": CATALOG_KEYS, "partialLocaleAllowed": False,
            "infoPlistCatalogDisposition": "READ_ONLY_P00_C06_INPUT",
        },
        "accessibility": {
            "contract": "AccessibilityContractV1",
            "registry": "SemanticAccessibilityIDRegistryV1",
            "semanticIDs": SEMANTIC_MAIL_IDS, "legacyRuntimeIDs": LEGACY_MAIL_IDS,
            "legacyAllowlistGrowthAllowed": False, "zeroShippingAllowlistRequired": False,
            "zeroShippingAllowlistOwner": "V23-P04-C29",
            "reservedShippingCallsiteAdoption": "DEFERRED_PENDING_S10_6_RECONCILIATION",
            "savedPhotoCollision": "DEFERRED_S10_RESERVED_RUNTIME_PATHS",
        },
        "packageLocalization": {
            "binding": "PackageLocalizationReleaseBindingV1",
            "packageID": fixture["packageBindings"][0]["packageID"],
            "orderedKeys": PACKAGE_KEYS, "sidecarOnly": True,
            "packageSchemaChanged": False, "reportSchemaChanged": False,
        },
        "presentation": {
            "localeAwareHelpers": ["INTEGER", "DATE", "MEASUREMENT"],
            "adoptedLiveCallSites": ["FEEDBACK_MAIL_ATTACHMENT_INTEGER"],
            "dateAndMeasurementAdoption": "DECLARED_NOT_ADOPTED_NO_CREDIT_S10_RESERVED",
            "runtimeLanguagePinnedToEnglish": True,
            "canonicalIDsWireValuesUserContentLocalized": False,
            "historicReportDisplayRewritten": False,
            "frozenDisplayContract": "FrozenDisplaySnapshotV1",
        },
        "s10": {"activeReservationPathCount": 86, "overlapPaths": []},
        "brand": {"manifestCount": 1, "uiSurfaceDelta": True, "brandSurfaceDelta": True,
                  "affectedSurfacePaths": ["FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift"]},
        "evidenceIDs": EVIDENCE_IDS, "testMethods": TEST_METHODS,
        "uiTestMethods": UI_TEST_METHODS, "sourceArtifacts": source_rows(root), **flags(),
    }
    return seal(unsigned)


def evidence(root: Path, contract_value: dict[str, Any]) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C16LocalizationAccessibilityEvidenceReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "result": "PASS_STATIC_PROVISIONAL",
        "checks": CHECKS, "pathFenceCount": 18, "existingPathCount": 3,
        "newPathCount": 15, "sourcePathCount": 14, "generatedArtifactCount": 4,
        "catalogKeyCount": 11, "packageLocalizationKeyCount": 3,
        "semanticIDCount": 5, "legacyAllowlistCount": 5,
        "shippingRuntimeLocales": ["en"], "appStorePrimaryLocale": "en-US",
        "pseudoLocalesShipping": False, "legacyAllowlistGrowthAllowed": False,
        "zeroShippingAllowlistRequired": False,
        "compilerExtractionEvidence": "NOT_RUN_NO_CREDIT_WINDOWS_STATIC_ONLY",
        "exportLocalizationsEvidence": "NOT_RUN_NO_CREDIT_WINDOWS_STATIC_ONLY",
        "uiAcceptanceEvidence": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        "infoPlistCatalogDisposition": "READ_ONLY_P00_C06_INPUT",
        "s10FenceOverlapPaths": [], "sourceArtifacts": source_rows(root),
        "contractArtifact": artifact(CONTRACT_PATH, pretty(contract_value)),
        "evidenceMatrix": [
            {"evidenceID": evidence_id, "unitTestMethod": unit, "uiTestMethod": ui,
             "uiDisposition": "DECLARED_SKIPPED_PENDING_S10_6_RECONCILIATION"}
            for evidence_id, unit, ui in zip(EVIDENCE_IDS, TEST_METHODS, UI_TEST_METHODS)
        ],
        **flags(),
    }
    return seal(unsigned)


def brand_manifest() -> dict[str, Any]:
    return seal({
        "schema": "V23P03C16BrandImpactManifestV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "manifestCount": 1,
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "fullSweepTriggered": False,
        "affectedSurfacePaths": ["FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift"],
        "changedStates": ["FEEDBACK_MAIL_COMPOSER_ENGLISH_COPY_AND_ACCESSIBILITY_BINDING"],
        "reservedAffectedConsumerCount": 26,
        "reservedAffectedConsumerDisposition": "DEFERRED_PENDING_S10_6_RECONCILIATION",
        "savedPhotoCollisionDisposition": "DEFERRED_S10_RESERVED_RUNTIME_PATHS",
        "dynamicTypeRTLVoiceOverEvidence": "NOT_RUN_NO_CREDIT_S10_RESERVED",
        **flags(),
    })


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = []
    for relative in MANIFEST_INPUT_PATHS:
        raw = generated.get(relative)
        if raw is None:
            raw = (root / relative).read_bytes()
        rows.append(artifact(relative, raw))
    return seal({
        "schema": "V23P03C16ToolingManifestV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "pathFence": PATH_FENCE,
        "existingPaths": EXISTING_PATHS, "newPaths": NEW_PATHS,
        "pathFenceCount": 18, "existingPathCount": 3, "newPathCount": 15,
        "sourcePathCount": 14, "generatedArtifactCount": 4,
        "manifestInputCount": 17, "activeS10ReservationPathCount": 86,
        "s10FenceOverlapPaths": [], "artifacts": rows,
        "artifactSetDigest": sha256(canonical(rows)), "evidenceIDs": EVIDENCE_IDS,
        **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    contract_raw = pretty(contract(root))
    evidence_raw = pretty(evidence(root, json.loads(contract_raw)))
    brand_raw = pretty(brand_manifest())
    generated = {CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    generated[MANIFEST_PATH] = pretty(tooling_manifest(root, generated))
    return generated
