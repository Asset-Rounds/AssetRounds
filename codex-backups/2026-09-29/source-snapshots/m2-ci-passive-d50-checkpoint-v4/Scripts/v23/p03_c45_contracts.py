#!/usr/bin/env python3
"""Deterministic asset-label tooling model for V23-P03-C45."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

# Reuse only the sealed canonical JSON, manifest-row, git-diff, and hashing
# machinery. C45 replaces all card authority and semantic validation below.
_BASE = Path(__file__).with_name("p03_c44_contracts.py")
_BASE_SHA256 = "6dc2d85bdf8fffb2eef4de35ed051eb7662576153f81541b5a200fb1bd88bf4e"
if hashlib.sha256(_BASE.read_bytes()).hexdigest() != _BASE_SHA256:
    raise ValueError("sealed C44 tooling model differs")
exec(compile(_BASE.read_text(encoding="utf-8"), str(_BASE), "exec"), globals())

_C33 = Path(__file__).with_name("p03_c33_contracts.py")
_C33_SHA256 = "ab153d94f9be87c3ed07581421f69ad7031476b904055051f36457eb8f8c2eac"
if hashlib.sha256(_C33.read_bytes()).hexdigest() != _C33_SHA256:
    raise ValueError("sealed C33 cumulative fence source differs")
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c33_contracts as _c33

CARD = "V23-P03-C45"
TITLE = "Deterministic label templates, opaque QR payloads, visible short codes, batch plans, and artifact manifests"
REGISTER_ORDINAL = 75
BASE_HEAD = "e02e729e88031ad24db141708cd0da73268683a2"
BASE_TREE = "81e28dc812d35eb27f2be18d5960602558d11c38"
COORDINATION_HEAD = "3272a0b9288c86bc66fec3e6448b8c33d2cd20c3"
COORDINATION_TREE = "572f33e362e2f4136d095ef6a9585c39f41947d4"
COORDINATION_CAS_SEQUENCE = 318
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "7a7f689054ac3af86d90bd236def07ef46dba3c7d629536e0862328f91ee0cab"
CONTEXT_DIGEST = "eb9fa861680052a951381147ef002d36441424e0e16be360bc22ccddd5dc4fa6"
FENCE_DIGEST = "97601b20a277b7c1cc811b6fc8276008e766077279ed52af0f10d276b04123c1"
HYDRATION_TRANSITION_DIGEST = "1a884e6ccfbc5ab2326030a2c9424c52a73096163aeb655b5a2026f9ca39afbb"
COORDINATION_LEDGER_DIGEST = "e514597db130194bd524008921c88ca185326a3fb5003a45b09bcba2c01af01e"
COORDINATION_PROJECTION_DIGEST = "55c539dbbc31c7a8b74e6fdc79df689a7d4c213be69380ed81089e446d3c644b"
AUTHORIZED_OVERLAP_COUNT = 3171
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/asset-label.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C45AssetLabelContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C45AssetLabelEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C45BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C45-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c45_contracts.py",
    "Scripts/v23/generate_p03_c45_contracts.py",
    "Scripts/v23/verify_p03_c45_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetLabelPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Labels/AssetLabelCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_52AssetLabelTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Labels/V22P03C45AssetLabelCorpusV1.json",
)
EXISTING_PATHS = tuple(_c33.EXISTING_PATHS) + tuple(_c33.NEW_PATHS[:6])
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "ManualShortCodeV1", "AssetLabelTemplateReleaseV1", "LabelDisclosureProfileV1",
    "AssetLabelItemSnapshotV1", "AssetLabelGenerationPlanV1", "AcceptedLabelGenerationSnapshotV1",
    "LabelReprintEligibilityV1", "LabelProjectionResultV1", "LabelOutputReceiptV1",
    "LabelOutputActivationDecisionV1",
)
TEST_METHODS = (
    "testV23P03C45G01AcceptedPlanGeneratesByteIdenticalPDFCSVTextAndIndependentQRDecode",
    "testV23P03C45A01ManualShortCodeAndCameraResolutionParityPreserveExplicitStart",
    "testV23P03C45H01MalformedStaleRevokedAndOversizedInputsFailClosedWithoutWrongEntity",
    "testV23P03C45I01LocatorIssuanceAndRenderPublicationRecoverZeroOrCompleteWithoutPartialOutput",
    "testV23P03C45R01BackupRestoreReplayDeleteEraseReprintAndScratchCleanupRemainExact",
)
DISCLOSURE_PROFILES = (
    "SHORT_CODE_ONLY", "ASSET_AND_SHORT_CODE", "ASSET_LOCATION_AND_SHORT_CODE",
)
ARTIFACT_FORMATS = ("PDF", "CSV", "ACCESSIBLE_STRUCTURED_TEXT")
REPRINT_ELIGIBILITIES = (
    "ACTIVE_EXACT_REPRINT", "HISTORIC_EXPORT_ONLY", "BLOCKED_MISSING_RELEASE",
)
HOSTILE_CASES = (
    "MALFORMED_PAYLOAD", "FOREIGN_PAYLOAD", "PARTIAL_PAYLOAD", "OVERSIZED_PAYLOAD",
    "COPIED_PAYLOAD", "REVOKED_PAYLOAD", "REPLACED_PAYLOAD", "DUPLICATE_SELECTION",
    "STALE_ASSET_REVISION", "STALE_LOCATOR_REVISION", "UNSUPPORTED_TEMPLATE_GEOMETRY",
    "CONTENT_DOES_NOT_FIT", "UNICODE_RTL_CONTROL_OR_BIDI_INPUT", "FORMULA_UNSAFE_CSV_INPUT",
    "LOW_STORAGE", "PROTECTED_DATA", "RENDERER_FAILURE", "DIGEST_FAILURE", "CANCELLATION",
    "CROP_RESCALE_GLARE_ABRASION_CURVATURE_LOW_CONTRAST_OBLIQUE_OR_DISTANCE",
)
INTERRUPTION_BOUNDARIES = (
    "BEFORE_LOCATOR_ISSUANCE_RECEIPT", "AFTER_LOCATOR_ISSUANCE_RECEIPT",
    "EACH_RENDER_CHECKPOINT", "AFTER_FINAL_BYTES_BEFORE_PUBLICATION",
)
COMPATIBILITY_KEY = "c45AssetLabelCompatibility"
COMPATIBILITY = {
    "compatibilityCardID": CARD,
    "soleLocatorAuthorityCardID": "V23-P03-C27",
    "soleRendererAuthorityCardID": "V23-P03-C24",
    "acceptedSnapshotsAreCanonical": True,
    "unacceptedPlansAndResultsAreLeasedScratch": True,
    "outputReceiptDoesNotClaimExternalPossession": True,
    "physicalPrintScanEvidenceOwnerPending": True,
}
COMPATIBILITY_CORPORA = tuple(
    path for path in EXISTING_PATHS
    if path.startswith("FieldEvidenceAppTests/Fixtures/") and path.endswith(".json")
)
FLAGS = {key: False for key in (
    "native", "hosted", "physical", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "adoptionEvidence",
    "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution",
)}


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C45(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def _closed_corpus(root: Path) -> dict[str, Any]:
    corpus = json.loads(_text(root, IMPLEMENTATION_PATHS[5]))
    keys = {
        "schema", "schemaVersion", "cardID", "classification", "persistentSchemaVersion",
        "recordsSchemaVersion", "durableFamilies", "contractNames", "templateReleases",
        "manualShortCodeCases", "disclosureProfiles", "generationPlans", "artifactCases",
        "qrPayloadCases", "reprintCases", "hostileCases", "interruptionBoundaries",
        "lifecycle", "invariants", "evidenceIDs", "statusFlags",
    }
    if set(corpus) != keys:
        raise ValueError("C45 closed corpus top-level differs")
    return corpus


def _require_keys(value: Any, keys: tuple[str, ...], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != set(keys):
        raise ValueError(f"C45 closed {label} shape differs")
    return value


def _validate_corpus_cases(corpus: dict[str, Any]) -> None:
    digest_pattern = re.compile(r"^[0-9a-f]{64}$")
    templates = corpus.get("templateReleases")
    if not isinstance(templates, list) or len(templates) < 4:
        raise ValueError("C45 template release corpus differs")
    for item in templates:
        item = _require_keys(item, ("templateID", "version", "pageProfile", "rendererReleaseID", "digest", "integralModuleScaling", "interpolationDisabled", "quietZoneModules", "immutable"), "template release")
        if (not all(isinstance(item[key], str) and item[key] for key in ("templateID", "pageProfile", "rendererReleaseID"))
                or not isinstance(item["version"], int) or item["version"] < 1
                or not digest_pattern.fullmatch(item["digest"])
                or item["integralModuleScaling"] is not True or item["interpolationDisabled"] is not True
                or not isinstance(item["quietZoneModules"], int) or item["quietZoneModules"] < 4
                or item["immutable"] is not True):
            raise ValueError("C45 template release value differs")
    short_codes = corpus.get("manualShortCodeCases")
    if not isinstance(short_codes, list) or len(short_codes) < 4:
        raise ValueError("C45 short-code corpus differs")
    for item in short_codes:
        item = _require_keys(item, ("caseID", "version", "canonicalAlphabet", "entered", "canonical", "checkCharacter", "disposition"), "short-code case")
        if (not all(isinstance(item[key], str) and item[key] for key in ("caseID", "canonicalAlphabet", "entered", "canonical", "checkCharacter"))
                or not isinstance(item["version"], int) or item["version"] < 1
                or item["disposition"] not in {"VALID", "INVALID_CHECK", "CONFUSABLE_REJECTED", "COLLISION_RETRY"}):
            raise ValueError("C45 short-code case value differs")
    plans = corpus.get("generationPlans")
    if not isinstance(plans, list) or len(plans) < 4:
        raise ValueError("C45 generation-plan corpus differs")
    for item in plans:
        item = _require_keys(item, ("planID", "orderedAssetIDs", "explicitUserOrder", "assetIDTieBreak", "maximumItemCount", "generatedTimeDisposition", "expectedDisposition"), "generation plan")
        assets = item["orderedAssetIDs"]
        if (not isinstance(item["planID"], str) or not item["planID"]
                or not isinstance(assets, list) or not assets or len(assets) != len(set(assets))
                or not all(isinstance(value, str) and value for value in assets)
                or not isinstance(item["explicitUserOrder"], bool) or item["assetIDTieBreak"] is not True
                or not isinstance(item["maximumItemCount"], int) or item["maximumItemCount"] < 1
                or not all(isinstance(item[key], str) and item[key] for key in ("generatedTimeDisposition", "expectedDisposition"))):
            raise ValueError("C45 generation-plan value differs")
    artifacts = corpus.get("artifactCases")
    if not isinstance(artifacts, list) or len(artifacts) < 3:
        raise ValueError("C45 artifact corpus differs")
    for item in artifacts:
        item = _require_keys(item, ("caseID", "formats", "samePlanByteIdentical", "formulaSafeCSV", "accessibleStructuredText", "filenamesExcludeCustomerSiteAndAssetNames", "pdfSHA256", "csvSHA256", "structuredTextSHA256"), "artifact case")
        if (not isinstance(item["caseID"], str) or not item["caseID"] or item["formats"] != list(ARTIFACT_FORMATS)
                or any(item[key] is not True for key in ("samePlanByteIdentical", "formulaSafeCSV", "accessibleStructuredText", "filenamesExcludeCustomerSiteAndAssetNames"))
                or not all(isinstance(item[key], str) and digest_pattern.fullmatch(item[key]) for key in ("pdfSHA256", "csvSHA256", "structuredTextSHA256"))):
            raise ValueError("C45 artifact case value differs")
    qr_cases = corpus.get("qrPayloadCases")
    if not isinstance(qr_cases, list) or len(qr_cases) < 6:
        raise ValueError("C45 QR corpus differs")
    for item in qr_cases:
        item = _require_keys(item, ("caseID", "payload", "expectedDisposition", "requiresPreview", "requiresExplicitStart", "containsURL", "grantsAuthorization"), "QR case")
        if (not all(isinstance(item[key], str) and item[key] for key in ("caseID", "payload", "expectedDisposition"))
                or item["requiresPreview"] is not True or item["requiresExplicitStart"] is not True
                or item["containsURL"] is not False or item["grantsAuthorization"] is not False):
            raise ValueError("C45 QR case value differs")
    reprints = corpus.get("reprintCases")
    if not isinstance(reprints, list) or len(reprints) < 3:
        raise ValueError("C45 reprint corpus differs")
    for item in reprints:
        item = _require_keys(item, ("caseID", "snapshotState", "locatorState", "releaseAvailable", "expectedEligibility", "historicWarningRequired"), "reprint case")
        if (not all(isinstance(item[key], str) and item[key] for key in ("caseID", "snapshotState", "locatorState"))
                or not isinstance(item["releaseAvailable"], bool) or not isinstance(item["historicWarningRequired"], bool)
                or item["expectedEligibility"] not in REPRINT_ELIGIBILITIES):
            raise ValueError("C45 reprint case value differs")
    lifecycle_keys = ("migration", "backup", "restore", "cloneFork", "deleteErase", "export", "searchReplay", "scratch", "receipts", "templateRendererReleases", "downgradeForwardFix")
    lifecycle = _require_keys(corpus.get("lifecycle"), lifecycle_keys, "lifecycle")
    if not all(isinstance(lifecycle[key], str) and lifecycle[key] for key in lifecycle_keys):
        raise ValueError("C45 lifecycle value differs")
    invariant_keys = (
        "soleLocatorAuthority", "soleRendererAuthority", "shortCodeIsConvenienceNotAuthorization",
        "qrContainsOnlyOpaqueLocatorAndCheck", "previewAndExplicitStartRequired", "stableSelectionOrder",
        "acceptedSnapshotCanonical", "unacceptedPlansAreScratch", "samePlanByteIdenticalArtifacts",
        "formulaSafeCSV", "accessibleStructuredText", "activeReprintRequiresUnchangedActiveLocator",
        "historicExportWarnsAndCannotDeploy", "missingReleaseBlocks", "receiptDoesNotClaimExternalPossession",
        "noSecondRenderer", "noSecondIdentifierStore", "noHostedResolver", "noNetworkProvider",
        "physicalEvidenceOwnerPending",
    )
    invariants = _require_keys(corpus.get("invariants"), invariant_keys, "invariants")
    if any(invariants[key] is not True for key in invariant_keys):
        raise ValueError("C45 invariant value differs")
    flags = _require_keys(corpus.get("statusFlags"), ("native", "hosted", "physical", "adoption", "acceptance", "release"), "status flags")
    if any(flags[key] is not False for key in flags):
        raise ValueError("C45 status flag value differs")


def _persistence(root: Path) -> dict[str, Any]:
    corpus = _closed_corpus(root)
    version = corpus.get("persistentSchemaVersion")
    records = corpus.get("recordsSchemaVersion")
    families = corpus.get("durableFamilies")
    if (not isinstance(version, int) or version < 1 or not isinstance(records, int) or records < 1
            or not isinstance(families, list) or not families or len(families) != len(set(families))
            or not all(isinstance(item, str) and item for item in families)):
        raise ValueError("C45 persistence authority differs")
    persistence_text = _text(root, IMPLEMENTATION_PATHS[0]) + _text(root, IMPLEMENTATION_PATHS[1])
    for token in (str(version), str(records), *families):
        if token not in persistence_text:
            raise ValueError("C45 persistence source/corpus differs:" + token)
    return {
        "mode": "PERSISTENT_ACCEPTED_SNAPSHOT_AND_EXISTING_LOCATOR_BINDING_TRUTH",
        "persistentSchemaVersion": version, "recordsSchemaVersion": records,
        "durableFamilyCount": len(families), "persistedFamilies": families,
        "acceptedGenerationSnapshotPersistent": True,
        "locatorAndShortCodeBindingUsesExistingP03C27Writer": True,
        "unacceptedPlanAndProjectionResultPersistent": False,
        "templateAndRendererReleasesImmutableCompatibilityInputs": True,
        "outputReceiptClaimsExternalPossession": False,
    }


def require_source_ready(root: Path) -> None:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    if missing:
        raise ValueError("C45 stable source absent:" + ",".join(missing))
    if observed_selectors(root) != TEST_METHODS:
        raise ValueError("C45 exact ordered G/A/H/I/R selectors differ")
    _closed_corpus(root)


def _compatibility_corpora(root: Path) -> None:
    if len(COMPATIBILITY_CORPORA) != 7:
        raise ValueError("C45 compatibility corpus inventory differs")
    for path in COMPATIBILITY_CORPORA:
        value = json.loads(_text(root, path))
        if value.get(COMPATIBILITY_KEY) != COMPATIBILITY:
            raise ValueError("C45 compatibility closure differs:" + path)


def _assert_publication_ownership_sources(root: Path) -> None:
    store_path = "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift"
    store = _tokens(
        root, store_path,
        "EvidenceBundleStoreAssetLabelPublicationV1",
        "AssetLabelContentPublicationMarkerV1",
        'let contentID = "asset-label-\\(job.id.rawValue.uuidString.lowercased())-\\(suffix)"',
        'locatorID: "c05-\\(contentID)"',
        'components: ["content", published.reference.workspaceID, published.reference.contentID]',
        'name: "original.bin"',
        '".asset-label-publications"',
        '"publication.json"',
        "publishOrAdoptAssetLabelArtifacts",
        "adoptAssetLabelArtifacts",
        "removeAssetLabelPublishedOutput",
    )
    _tokens(
        root, IMPLEMENTATION_PATHS[3],
        "static func production", "contentStore: EvidenceBundleStore",
        "publishOrAdoptAssetLabelArtifacts", "adoptAssetLabelArtifacts",
        "removeAssetLabelPublishedOutput", "discardUncommittedAssetLabelArtifacts",
    )
    if not re.search(
        r"Set\(publishedArtifacts\.map\s*\{\s*\$0\.reference\.contentID\s*\}\)\.count\s*==\s*publishedArtifacts\.count",
        store,
    ):
        raise ValueError("C45 sole-store marker content identities are not unique")
    ownership_path = "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift"
    ownership = _tokens(
        root, ownership_path,
        "validateC45ActivePublicationOwnership(values)",
        "bindingByJobID", "bindingByContentID", "bindingByLocatorID",
        "where snapshot.disposition == .activeSourceWorkspace",
        "existing != canonicalBinding", "AssetLabelContractFailureV1.duplicateIdentity",
    )
    required_assignments = (
        r"bindingByJobID\[binding\.jobID\]\s*=\s*canonicalBinding",
        r"bindingByContentID\[contentID\]\s*=\s*canonicalBinding",
        r"bindingByLocatorID\[locatorID\]\s*=\s*canonicalBinding",
    )
    if not all(re.search(pattern, ownership) for pattern in required_assignments):
        raise ValueError("C45 global active publication ownership binding differs")


def _assert_history_aware_issuance_sources(root: Path) -> None:
    coordinator = _tokens(
        root, "FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift",
        "ManualShortCodeIssuanceCoordinatorV1", "maximumCollisionAttempts = 32",
        "durableReceipt(mutationID:", "manualShortCodeIsAvailable",
        "query.locators(lookupKey:", "shortCodeCollisionLimitReached",
    )
    if coordinator.count("writer.manualShortCodeIsAvailable") < 2:
        raise ValueError("C45 issuance does not check the canonical writer before prepare and issue")
    writer = _tokens(
        root, "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
        "historicalLocatorValues", "MutationEnvelopeV1.decodeCanonical",
        "case let .applyAssetLocator", "requireUnusedManualShortCode",
        "currentCollision", "historicalCollision", "WorkspaceMutationFailureV1.sequenceCollision",
    )
    if not re.search(
        r"guard\s+!currentCollision\s*,\s*!historicalCollision\s+else",
        writer,
    ):
        raise ValueError("C45 manual short-code reservation is not current-and-history aware")
    if writer.count("try requireUnusedManualShortCode") != 3:
        raise ValueError("C45 bind/rebind/replace history-aware reservation coverage differs")


def _assert_production_scratch_sources(root: Path) -> None:
    lifecycle = _tokens(
        root, IMPLEMENTATION_PATHS[3],
        "AssetLabelArtifactScratchStoreV1", "static func production",
        "jobStagingRootURL: URL", 'appendingPathComponent("asset-label-render", isDirectory: true)',
        "discardUncommittedAssetLabelArtifacts", "discardRecoveredTerminalScratch",
    )
    if lifecycle.count('rootURL: jobStagingRootURL.appendingPathComponent("asset-label-render"') != 1:
        raise ValueError("C45 production scratch namespace differs")
    _tokens(
        root, "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift",
        'stagingRelativePath: "asset-label-render/\\(jobID.rawValue.uuidString.lowercased())"',
    )
    cleanup = _tokens(
        root, "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
        "AssetLabelDerivedScratchCleanupV1", "generationRootURL: URL",
        'lastPathComponent == "generations"', 'lastPathComponent == "FieldEvidenceData"',
        'appendingPathComponent("jobs", isDirectory: true)',
        'appendingPathComponent("asset-label-render", isDirectory: true)',
        "removeAttempts(referencing assetID: UUID)",
    )
    if not re.search(
        r"rootURL\s*=\s*generationRoot\s*\.appendingPathComponent\(\"jobs\".*?"
        r"\.appendingPathComponent\(\"asset-label-render\"",
        cleanup,
        re.S,
    ):
        raise ValueError("C45 deletion is not bound to the exact production generation scratch root")
    _tokens(
        root, "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
        "AssetLabelDerivedScratchCleanupV1", "generationRootURL: generationRootURL",
        ").removeAttempts(referencing: intent.assetID)",
    )


def _assert_native_text_environment_sources(root: Path) -> None:
    contracts = _tokens(
        root, IMPLEMENTATION_PATHS[0],
        "AssetLabelNativeFontIdentityV1", "fontFileSHA256",
        "AssetLabelNativeTextEnvironmentV1", "coreTextVersion", "operatingSystemBuild",
        "baseFont", "selectedFonts", "environmentSHA256",
        "nativeTextLayoutReleaseID", "context.nativeTextEnvironment==outputReceipt.nativeTextEnvironment",
    )
    if "case schemaVersion,planSHA256,nativeTextLayoutReleaseID,coreTextVersion,operatingSystemBuild,baseFont,selectedFonts,environmentSHA256" not in contracts:
        raise ValueError("C45 native text environment closed coding keys differ")
    renderer = _tokens(
        root, "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
        "import CoreText", "assetLabelNativeTextEnvironment", "CTGetCoreTextVersion()",
        'sysctlbyname("kern.osversion"', "CTFontCopyPostScriptName",
        "CTFontCopyAttribute(font, kCTFontURLAttribute)", ".isRegularFileKey", ".fileSizeKey",
        "FileHandle(forReadingFrom: fontURL)", "hasher.update(data: bytes)",
        "fontFileSHA256: digest", "nativeTextEnvironment.selectedFonts.contains",
    )
    if renderer.count("CTGetCoreTextVersion()") != 1 or renderer.count('sysctlbyname("kern.osversion"') != 2:
        raise ValueError("C45 CoreText or operating-system release binding differs")
    if not re.search(
        r"guard\s+try\s+assetLabelNativeFontIdentity\(baseFont\)\s*==\s*"
        r"nativeTextEnvironment\.baseFont",
        renderer,
    ):
        raise ValueError("C45 native base-font file identity is not enforced during rendering")
    _tokens(
        root, IMPLEMENTATION_PATHS[3],
        '"native-text-environment.json"',
        "nativeTextEnvironment: projection.nativeTextEnvironment",
        "assetLabelNativeTextEnvironment(for: snapshot.plan)",
        "nativeTextEnvironment: currentEnvironment",
    )


def assert_source_regressions(root: Path) -> None:
    require_source_ready(root)
    contracts = _tokens(root, IMPLEMENTATION_PATHS[0], *CONTRACT_NAMES)
    for token in (
        "AR1:", "SHORT_CODE_ONLY", "ASSET_AND_SHORT_CODE", "ASSET_LOCATION_AND_SHORT_CODE",
        "ACTIVE_EXACT_REPRINT", "HISTORIC_EXPORT_ONLY", "BLOCKED_MISSING_RELEASE",
        "GENERATED", "HANDED_OFF_TO_SYSTEM", "explicit", "preview", "check",
    ):
        if token.lower() not in contracts.lower():
            raise ValueError("C45 contract semantics regressed:" + token)
    forbidden = (
        r"^\s*import\s+(?:Network|WebKit)\b", r"\bURLSession\b", r"\bhttps?://",
        r"\b(?:PrinterSDK|ManagedLabelService|HostedResolver|PublicRequestQR)\b",
    )
    stripped = re.sub(r"/\*.*?\*/|//[^\n]*", "", contracts, flags=re.S)
    if any(re.search(pattern, stripped, re.I | re.M) for pattern in forbidden):
        raise ValueError("C45 contract gained forbidden hosted/provider surface")
    persistence = _tokens(root, IMPLEMENTATION_PATHS[1], "AcceptedLabelGenerationSnapshotV1")
    coordinator = _tokens(root, IMPLEMENTATION_PATHS[2], "expectedRevision", "MutationID", "AssetLabelCanonicalWorkspaceWritingV1", "scratch")
    lifecycle = _tokens(root, IMPLEMENTATION_PATHS[3], "backup", "restore", "delete", "Erase", "search", "replay")
    enrolled_sources = []
    for path in (*EXISTING_PATHS, *IMPLEMENTATION_PATHS[:4]):
        if path.endswith(".swift"):
            text = _text(root, path)
            if "AssetLabel" in text or "AcceptedLabelGenerationSnapshot" in text:
                enrolled_sources.append((path, text))
    for token in ("migration", "backup", "restore", "delete", "Erase", "export", "search", "replay", "clone", "fork", "retention"):
        if not any(token.lower() in text.lower() for _, text in enrolled_sources):
            raise ValueError("C45 durable lifecycle regressed:" + token)
    renderer_refs = sum(text.count("DeterministicPDFRendererV1") for text in (contracts, coordinator, lifecycle))
    locator_refs = sum(text.count("AssetLocator") for text in (contracts, persistence, coordinator, lifecycle))
    if renderer_refs < 1 or locator_refs < 1:
        raise ValueError("C45 sole renderer/locator integration absent")
    tests = _tokens(root, IMPLEMENTATION_PATHS[4], *TEST_METHODS)
    for token in (
        "byte", "PDF", "CSV", "QR", "manual", "camera", "malformed", "stale", "revoked",
        "oversized", "interrupt", "backup", "restore", "delete", "Erase", "scratch",
    ):
        if token.lower() not in tests.lower():
            raise ValueError("C45 hostile/recovery coverage regressed:" + token)
    corpus = _closed_corpus(root)
    if (
        corpus.get("schema") != "V22P03C45AssetLabelCorpusV1"
        or corpus.get("schemaVersion") != 1 or corpus.get("cardID") != CARD
        or corpus.get("classification") != "IMPLEMENT_NOW"
        or corpus.get("contractNames") != list(CONTRACT_NAMES)
        or corpus.get("disclosureProfiles") != list(DISCLOSURE_PROFILES)
        or corpus.get("hostileCases") != list(HOSTILE_CASES)
        or corpus.get("interruptionBoundaries") != list(INTERRUPTION_BOUNDARIES)
        or corpus.get("evidenceIDs") != [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
        or corpus.get("statusFlags") != {key: False for key in ("native", "hosted", "physical", "adoption", "acceptance", "release")}
    ):
        raise ValueError("C45 corpus authority differs")
    _validate_corpus_cases(corpus)
    _persistence(root)
    _compatibility_corpora(root)
    _assert_publication_ownership_sources(root)
    _assert_history_aware_issuance_sources(root)
    _assert_production_scratch_sources(root)
    _assert_native_text_environment_sources(root)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (212, 14, 226) or len(set(PATH_FENCE)) != 226:
        raise ValueError("C45 fence must be unique 226=212+14")
    if tuple(PATH_FENCE[218:]) != (*SCRIPT_PATHS, *GENERATED_PATHS):
        raise ValueError("C45 tooling rows 219-226 differ")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C45 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C45 base tree differs")
    for path in EXISTING_PATHS:
        if not _base_exists(root, path):
            raise ValueError(f"C45 existing path absent at base:{path}")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"C45 new path existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 3171 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C45 authority/status proof differs")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE,
        "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST, "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": 226, "existingPathCount": 212, "newPathCount": 14,
        "authorizedOverlapCount": 3171, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
        "directPrerequisiteCards": ["V23-P03-C24", "V23-P03-C27"],
        "nextCard": "V23-P03-C46", "nextRegisterOrdinal": 76,
    }


def _closed_object(properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties, "required": required}


def schema_document(root: Path | None = None) -> dict[str, Any]:
    text = {"type": "string", "minLength": 1}
    digest = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    strings = lambda minimum=1: {"type": "array", "minItems": minimum, "uniqueItems": True, "items": text}
    template = _closed_object({
        "templateID": text, "version": {"type": "integer", "minimum": 1}, "pageProfile": text,
        "rendererReleaseID": text, "digest": digest, "integralModuleScaling": {"const": True},
        "interpolationDisabled": {"const": True}, "quietZoneModules": {"type": "integer", "minimum": 4},
        "immutable": {"const": True},
    }, ["templateID", "version", "pageProfile", "rendererReleaseID", "digest", "integralModuleScaling", "interpolationDisabled", "quietZoneModules", "immutable"])
    short_code = _closed_object({
        "caseID": text, "version": {"type": "integer", "minimum": 1}, "canonicalAlphabet": text,
        "entered": text, "canonical": text, "checkCharacter": text,
        "disposition": {"enum": ["VALID", "INVALID_CHECK", "CONFUSABLE_REJECTED", "COLLISION_RETRY"]},
    }, ["caseID", "version", "canonicalAlphabet", "entered", "canonical", "checkCharacter", "disposition"])
    plan = _closed_object({
        "planID": text, "orderedAssetIDs": strings(), "explicitUserOrder": {"type": "boolean"},
        "assetIDTieBreak": {"const": True}, "maximumItemCount": {"type": "integer", "minimum": 1},
        "generatedTimeDisposition": text, "expectedDisposition": text,
    }, ["planID", "orderedAssetIDs", "explicitUserOrder", "assetIDTieBreak", "maximumItemCount", "generatedTimeDisposition", "expectedDisposition"])
    artifact = _closed_object({
        "caseID": text, "formats": {"const": list(ARTIFACT_FORMATS)}, "samePlanByteIdentical": {"const": True},
        "formulaSafeCSV": {"const": True}, "accessibleStructuredText": {"const": True},
        "filenamesExcludeCustomerSiteAndAssetNames": {"const": True},
        "pdfSHA256": digest, "csvSHA256": digest, "structuredTextSHA256": digest,
    }, ["caseID", "formats", "samePlanByteIdentical", "formulaSafeCSV", "accessibleStructuredText", "filenamesExcludeCustomerSiteAndAssetNames", "pdfSHA256", "csvSHA256", "structuredTextSHA256"])
    qr = _closed_object({
        "caseID": text, "payload": text, "expectedDisposition": text, "requiresPreview": {"const": True},
        "requiresExplicitStart": {"const": True}, "containsURL": {"const": False},
        "grantsAuthorization": {"const": False},
    }, ["caseID", "payload", "expectedDisposition", "requiresPreview", "requiresExplicitStart", "containsURL", "grantsAuthorization"])
    reprint = _closed_object({
        "caseID": text, "snapshotState": text, "locatorState": text, "releaseAvailable": {"type": "boolean"},
        "expectedEligibility": {"enum": list(REPRINT_ELIGIBILITIES)}, "historicWarningRequired": {"type": "boolean"},
    }, ["caseID", "snapshotState", "locatorState", "releaseAvailable", "expectedEligibility", "historicWarningRequired"])
    lifecycle_keys = ["migration", "backup", "restore", "cloneFork", "deleteErase", "export", "searchReplay", "scratch", "receipts", "templateRendererReleases", "downgradeForwardFix"]
    invariant_keys = [
        "soleLocatorAuthority", "soleRendererAuthority", "shortCodeIsConvenienceNotAuthorization",
        "qrContainsOnlyOpaqueLocatorAndCheck", "previewAndExplicitStartRequired", "stableSelectionOrder",
        "acceptedSnapshotCanonical", "unacceptedPlansAreScratch", "samePlanByteIdenticalArtifacts",
        "formulaSafeCSV", "accessibleStructuredText", "activeReprintRequiresUnchangedActiveLocator",
        "historicExportWarnsAndCannotDeploy", "missingReleaseBlocks", "receiptDoesNotClaimExternalPossession",
        "noSecondRenderer", "noSecondIdentifierStore", "noHostedResolver", "noNetworkProvider",
        "physicalEvidenceOwnerPending",
    ]
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/asset-label.schema.json",
        "title": "V23 P03 C45 Asset Label Corpus", "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C45AssetLabelCorpusV1"}, "schemaVersion": {"const": 1},
            "cardID": {"const": CARD}, "classification": {"const": "IMPLEMENT_NOW"},
            "persistentSchemaVersion": {"type": "integer", "minimum": 1},
            "recordsSchemaVersion": {"type": "integer", "minimum": 1},
            "durableFamilies": strings(), "contractNames": {"const": list(CONTRACT_NAMES)},
            "templateReleases": {"type": "array", "minItems": 4, "items": template},
            "manualShortCodeCases": {"type": "array", "minItems": 4, "items": short_code},
            "disclosureProfiles": {"const": list(DISCLOSURE_PROFILES)},
            "generationPlans": {"type": "array", "minItems": 4, "items": plan},
            "artifactCases": {"type": "array", "minItems": 3, "items": artifact},
            "qrPayloadCases": {"type": "array", "minItems": 6, "items": qr},
            "reprintCases": {"type": "array", "minItems": 3, "items": reprint},
            "hostileCases": {"const": list(HOSTILE_CASES)},
            "interruptionBoundaries": {"const": list(INTERRUPTION_BOUNDARIES)},
            "lifecycle": _closed_object({key: text for key in lifecycle_keys}, lifecycle_keys),
            "invariants": _closed_object({key: {"const": True} for key in invariant_keys}, invariant_keys),
            "evidenceIDs": {"const": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]},
            "statusFlags": _closed_object({key: {"const": False} for key in ("native", "hosted", "physical", "adoption", "acceptance", "release")}, ["native", "hosted", "physical", "adoption", "acceptance", "release"]),
        },
        "required": [
            "schema", "schemaVersion", "cardID", "classification", "persistentSchemaVersion",
            "recordsSchemaVersion", "durableFamilies", "contractNames", "templateReleases",
            "manualShortCodeCases", "disclosureProfiles", "generationPlans", "artifactCases",
            "qrPayloadCases", "reprintCases", "hostileCases", "interruptionBoundaries",
            "lifecycle", "invariants", "evidenceIDs", "statusFlags",
        ],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    semantics = {
        "contractNames": list(CONTRACT_NAMES), "fiveSelectors": list(observed_selectors(root)),
        "manualShortCodeUsesFrozenCaseInsensitiveConfusableResistantAlphabetAndCheck": True,
        "shortCodeAndQRRemainLocatorConvenienceNotAuthorization": True,
        "qrGrammarIsAR1OpaqueLocatorCheckWithNoURLIdentitySecretOrAutomaticStart": True,
        "existingLocatorAuthorityExclusivelyIssuesRebindsAndRevokes": True,
        "existingDocumentRendererExclusivelyProducesDeterministicPDFCSVAndAccessibleText": True,
        "templateAndRendererReleasesAreImmutableCompatibilityInputs": True,
        "stableOrderNFCBidiIsolationFixedLayoutAndMetadataProduceRepeatBytes": True,
        "acceptedGenerationSnapshotIsMinimalImmutableCanonicalRegenerationTruth": True,
        "unacceptedPlansAndResultsAreLeasedDerivedScratchExcludedFromBackup": True,
        "activeHistoricAndBlockedReprintStatesRemainExactAndTruthful": True,
        "outputReceiptPreservesDigestsWithoutClaimingExternalPossession": True,
        "publishedArtifactsUseExactJobDerivedSoleEvidenceBundleStoreNamespace": True,
        "sameJobRequiresIdenticalCanonicalPublicationBinding": True,
        "contentAndLocatorIDsAreGloballyUniqueAcrossActiveSnapshots": True,
        "historicSnapshotsAreExcludedFromActivePublicationOwnership": True,
        "manualShortCodeNamespaceRejectsCurrentAndCanonicalHistoryReuse": True,
        "productionScratchAndDeletionShareExactGenerationJobsNamespace": True,
        "acceptedOutputAndReprintBindCoreTextOSBuildAndFontFileDigests": True,
        "durableLifecycleCoversMigrationBackupRestoreCloneForkDeleteEraseExportSearchReplayAndForwardFix": True,
        "physicalPrintScanEvidenceRemainsOwnerPendingUntilP05C02": True,
        "noSecondRendererIdentifierStoreHostedResolverProviderNetworkOrLabelAuthorization": True,
    }
    return _sealed({"schema": "V23P03C45AssetLabelContractV1", "schemaVersion": 1, "authority": authority(), "persistence": _persistence(root), "requiredSemantics": semantics})


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    return _sealed({
        "schema": "V23P03C45AssetLabelEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "classification": "IMPLEMENT_NOW", "evidenceIDs": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")],
        "testSelectors": list(observed_selectors(root)), "persistence": _persistence(root),
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
        "nativeEvidenceState": "PENDING_NOT_ACCEPTING", "physicalPrintScanEvidenceState": "REQUIRED_PENDING_OWNER",
        "adoptionState": "PENDING_NOT_ACCEPTING", "acceptanceState": "PENDING_NOT_ACCEPTING",
        "releaseState": "PENDING_NOT_ACCEPTING", "statusFlags": FLAGS,
    })


def brand_document() -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C45BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "publicClaimDelta": False,
        "nativeIPadSurface": False, "dynamicTypeThroughAX5": True, "voiceOverSpellsShortCode": True,
        "stateNeverReliesOnlyOnColor": True, "filenamesExcludeCustomerSiteAndAssetNames": True,
        "networkProviderContactMeasurementOrMarketingFlow": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    rendered = {
        SCHEMA_PATH: pretty(schema_document(root)), CONTRACT_PATH: pretty(contract_document(root)),
        EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document()),
    }
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "schema": "V23P03C45ToolingManifestV1", "schemaVersion": 1, "authority": authority(),
        "pathFence": list(PATH_FENCE), "pathFenceCount": 226, "existingPathCount": 212, "newPathCount": 14,
        "authorizedOverlapCount": 3171, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
        "artifacts": rows, "artifactSetDigest": sha256_value(rows),
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    }))
    return rendered
