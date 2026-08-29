#!/usr/bin/env python3
"""Deterministic disabled-communications tooling model for V23-P03-C44."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

# C44 deliberately reuses the sealed C43 serialization/manifest machinery while
# replacing every authority, fence, corpus, and source-conformance rule below.
_BASE = Path(__file__).with_name("p03_c43_contracts.py")
_BASE_SHA256 = "ab05e01553dd69dac2a47493c57a463c57f5306cd62ce2b42747a67838db49ea"
if hashlib.sha256(_BASE.read_bytes()).hexdigest() != _BASE_SHA256:
    raise ValueError("sealed C43 tooling model differs")
exec(compile(_BASE.read_text(encoding="utf-8"), str(_BASE), "exec"), globals())

CARD = "V23-P03-C44"
TITLE = "Consent-based customer communications, research participation, and marketing-contact separation boundary"
REGISTER_ORDINAL = 74
BASE_HEAD = "6c132a300ae22aced1af9a1be1c26585cb86fcef"
BASE_TREE = "b91ab7918f698c87515026e36b520a02fa4eedb4"
COORDINATION_HEAD = "76185233c7a4e60b6b61426baeff22e2505e5cd9"
COORDINATION_TREE = "c724ea2c6c886282aba565a4c0f36fb45755b8ce"
COORDINATION_CAS_SEQUENCE = 314
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "7650b0b80a28f0423269b377b111d302e7203487caa20847ff44bdd6c4123812"
CONTEXT_DIGEST = "4c3ebdce6b4adfb87a4e686bd80302abe6c6a548add816d52dbf74535efa0980"
FENCE_DIGEST = "e8dcdb28ee6b90b726bf3a12b678c3311313f4a3b21a3473cee9b0ed7b152be2"
HYDRATION_TRANSITION_DIGEST = "242e1ef01b340618406295c05266b0988881aeb90e71953f0df943927c6b6f0a"
COORDINATION_LEDGER_DIGEST = "766bc46c81922312afcc614ebebd44949c7e91c8ece86bb263b518cae7622967"
COORDINATION_PROJECTION_DIGEST = "c3103fc2f8e38789d0be51b99fc2cac342513a80c1e75436617117c0bffaa9cf"

SCHEMA_PATH = "Scripts/v23/communication-consent.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C44CommunicationConsentContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C44CommunicationConsentEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C44BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C44-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c44_contracts.py",
    "Scripts/v23/generate_p03_c44_contracts.py",
    "Scripts/v23/verify_p03_c44_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Communications/CommunicationConsentContractsV1.swift",
    "FieldEvidenceAppTests/TestSupport/Communications/CommunicationConsentSyntheticEvaluatorV1.swift",
    "FieldEvidenceAppTests/TestSupport/Communications/ZeroSubscriberTransmissionConformanceScannerV1.swift",
    "FieldEvidenceAppTests/V9_51CommunicationConsentTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Communications/V22P03C44CommunicationConsentCorpusV1.json",
    "Release/V23P03C44CommunicationConsentActivationBoundaryV1.md",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
EXISTING_PATHS: tuple[str, ...] = ()
PATH_FENCE = NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "MarketingContactV1", "CommunicationConsentReceiptV1", "CommunicationPreferenceV1",
    "SuppressionRecordV1", "ContactSourceV1", "ConsentDisclosureReleaseV1",
    "EmailServiceProviderAdapterV1", "ZeroSubscriberTransmissionConformanceReceiptV1",
)
TEST_METHODS = (
    "testV23P03C44G01IndependentAffirmativeEnrollmentCreatesOnlyExactPurposeMarketingContact",
    "testV23P03C44A01TransactionalOperationalAndResearchSourcesNeverInferMarketingConsent",
    "testV23P03C44H01NormalizationCollisionsStaleDisclosureAndCrossPurposeReuseFailClosed",
    "testV23P03C44I01WithdrawalSuppressionAndProviderRetryRemainIdempotentWithoutTransmission",
    "testV23P03C44R01ArchiveRuntimeRollbackAndSupersessionPreserveZeroSubscriberPosture",
)
PURPOSES = ("NEWSLETTER", "PRODUCT_UPDATE", "RESEARCH_INVITATION", "TRANSACTIONAL_OR_SUPPORT")
HOSTILE_CASES = (
    "PLUS_ADDRESS_CASE_OR_UNICODE_NORMALIZATION_COLLISION", "SHARED_MAILBOX", "ADDRESS_CHANGE",
    "DUPLICATE_CONSENT", "PRECHECKED_CHECKBOX", "STALE_DISCLOSURE", "MINOR_OR_INCAPACITY_AMBIGUITY",
    "UNKNOWN_JURISDICTION", "CONSENT_AFTER_WITHDRAWAL", "SEND_RACE_WITH_UNSUBSCRIBE",
    "ERASED_OR_REIMPORTED_LIST", "PROVIDER_OUTAGE_OR_DUPLICATE_WEBHOOK", "CREDENTIAL_IN_BUNDLE_OR_LOG",
    "HASHED_EMAIL_LABELED_ANONYMOUS", "AUDIENCE_EXPORT_DESCRIBED_AS_NEWSLETTER",
    "TRANSACTIONAL_COPY_CONTAINING_MARKETING",
)
ARCHIVE_SURFACES = (
    "DEPENDENCY", "ARCHIVE", "LINK", "RESOURCE", "STRING", "ROUTE", "SETTINGS",
    "BACKGROUND_TASK", "CREDENTIAL", "ENDPOINT", "RUNTIME_NETWORK",
)
STATIC_SCAN_SUFFIXES = {
    ".swift", ".plist", ".xcprivacy", ".entitlements", ".xcconfig", ".strings", ".xcstrings",
    ".json", ".pbxproj",
}
FLAGS = {key: False for key in (
    "native", "hosted", "physical", "archive", "runtime", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "archiveAcceptance", "runtimeAcceptance",
    "adoptionEvidence", "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution",
)}
PERSISTENCE: dict[str, Any] = {
    "mode": "NONPERSISTENT_STATIC_POLICY_AND_SYNTHETIC_TESTSUPPORT_ONLY",
    "persistentSchemaVersion": None, "recordsSchemaVersion": None,
    "persistentKindLifecycleModelCount": 0, "durableFamilyCount": 0, "persistedFamilies": [],
    "contactInstancePersistence": False, "consentInstancePersistence": False,
    "preferenceInstancePersistence": False, "suppressionInstancePersistence": False,
    "runtimeInvocation": False, "networkLifecycle": False,
    "acceptedContractReleaseDisposition": "IMMUTABLE_VERSION_AND_DIGEST_SUPERSESSION_ONLY",
}


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[3]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C44(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def _closed_corpus(root: Path) -> dict[str, Any]:
    corpus = json.loads(_text(root, IMPLEMENTATION_PATHS[4]))
    keys = {
        "schema", "schemaVersion", "cardID", "classification", "collectionDisposition", "purposes",
        "consentTruthTable", "normalizationCases", "disclosureReleases", "suppressionCases", "hostileCases",
        "archiveProofs", "lifecycle", "invariants", "evidenceIDs", "statusFlags",
    }
    if set(corpus) != keys:
        raise ValueError("C44 closed corpus top-level differs")
    return corpus


def require_source_ready(root: Path) -> None:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    if missing:
        raise ValueError("C44 stable source absent:" + ",".join(missing))
    if observed_selectors(root) != TEST_METHODS:
        raise ValueError("C44 exact ordered G/A/H/I/R selectors differ")
    _closed_corpus(root)


def _forbidden_active_surface(text: str) -> list[str]:
    """Purpose-aware scan: Apple support modules and inert example URLs are not provider activation."""
    code = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    forbidden = {
        "network client": r"\b(?:URLSession|NWConnection)\b",
        "provider SDK": r"^\s*import\s+(?:Mailchimp|SendGrid|Braze|Iterable|CustomerIO|FirebaseMessaging)\b",
        "live endpoint": r"\bhttps?://(?!example\.invalid\b)[^\s\"']+",
        "credential source": r"\b(?:apiKey|clientSecret|providerCredential|bearerToken)\b\s*=",
        "runtime adapter": r"\b(?:LiveEmailServiceProviderAdapter|SubscriberRepository|MarketingSendQueue)\b",
    }
    return [name for name, pattern in forbidden.items() if re.search(pattern, code, re.I | re.M)]


def _scan_text(raw: bytes) -> str:
    return raw.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def _shipping_scan_paths(root: Path) -> list[str]:
    paths: set[str] = set()
    app = root / "FieldEvidenceApp"
    if not app.is_dir():
        raise ValueError("C44 shipping app directory absent")
    for target in app.rglob("*"):
        if target.is_file() and target.suffix.lower() in STATIC_SCAN_SUFFIXES:
            paths.add(target.relative_to(root).as_posix())
    for pattern in (
        "FieldEvidenceApp.xcodeproj/project.pbxproj",
        "FieldEvidenceApp.xcodeproj/**/Package.resolved",
        "**/Info.plist", "**/PrivacyInfo.xcprivacy",
        "Package.swift", "Package.resolved", "**/Package.swift", "**/Package.resolved",
    ):
        for target in root.glob(pattern):
            if target.is_file() and "FieldEvidenceAppTests" not in target.parts and not any(part in {".git", ".build", "DerivedData"} for part in target.parts):
                paths.add(target.relative_to(root).as_posix())
    ordered = sorted(paths, key=lambda value: (value.lower(), value))
    if not ordered or "FieldEvidenceApp.xcodeproj/project.pbxproj" not in ordered:
        raise ValueError("C44 bounded shipping/project scan inventory absent")
    return ordered


def _dependency_inventory(root: Path, paths: list[str]) -> dict[str, Any]:
    manifest_paths = [path for path in paths if path.endswith("Package.swift")]
    resolved_paths = [path for path in paths if path.endswith("Package.resolved")]
    project_paths = [path for path in paths if path.endswith("project.pbxproj")]
    remote_urls: set[str] = set()
    product_names: set[str] = set()
    resolved_identities: set[str] = set()
    for path in project_paths:
        text = _scan_text((root / path).read_bytes())
        remote_urls.update(re.findall(r"repositoryURL\s*=\s*\"([^\"]+)\"", text))
        match = re.search(r"/\* Begin XCSwiftPackageProductDependency section \*/(.*?)/\* End XCSwiftPackageProductDependency section \*/", text, re.S)
        if match:
            product_names.update(re.findall(r"productName\s*=\s*([^;\n]+)", match.group(1)))
    for path in manifest_paths:
        text = _scan_text((root / path).read_bytes())
        remote_urls.update(re.findall(r"\.package\s*\(\s*url:\s*\"([^\"]+)\"", text))
        product_names.update(re.findall(r"\.product\s*\(\s*name:\s*\"([^\"]+)\"", text))
    for path in resolved_paths:
        try:
            value = json.loads((root / path).read_text(encoding="utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError(f"C44 package resolution differs:{path}:{error}") from error
        pins = value.get("pins", value.get("object", {}).get("pins", []))
        for pin in pins:
            identity = pin.get("identity") or pin.get("package")
            location = pin.get("location") or pin.get("repositoryURL")
            if identity:
                resolved_identities.add(str(identity))
            if location:
                remote_urls.add(str(location))
    inventory = {
        "packageManifestPaths": manifest_paths,
        "packageResolvedPaths": resolved_paths,
        "projectFilePaths": project_paths,
        "remotePackageURLs": sorted(remote_urls),
        "linkedPackageProducts": sorted(value.strip().strip('"') for value in product_names),
        "resolvedPackageIdentities": sorted(resolved_identities),
    }
    return {**inventory, "inventoryDigest": sha256_value(inventory)}


def _recognized_scan_exemptions(path: str, text: str) -> list[dict[str, Any]]:
    rules = (
        ("FEEDBACK_MESSAGEUI_OR_SUPPORT", r"\b(?:MessageUI|MFMailComposeViewController|FeedbackConfigurationV1)\b"),
        ("STOREKIT_COMMERCE", r"\b(?:StoreKit|Product\.products|Transaction\.updates)\b"),
        ("METRICKIT_OS_SUBSCRIBER", r"\b(?:MetricKit|MXMetricManager|MXMetricManagerSubscriber)\b"),
        ("LOCAL_NOTIFICATION", r"\b(?:UNUserNotificationCenter|UNNotificationRequest)\b"),
        ("INERT_SCHEMA_OR_EXAMPLE_INVALID_URL", r"(?:\$schema|example\.invalid|assetrounds\.invalid)"),
        ("DISPATCH_CONCURRENCY", r"^\s*import\s+Dispatch\b|\bDispatchQueue\b"),
        ("LOCAL_AUTHENTICATION", r"^\s*import\s+LocalAuthentication\b|\bLAContext\b"),
    )
    rows = []
    for kind, pattern in rules:
        count = len(re.findall(pattern, text, re.I | re.M))
        if count:
            rows.append({"kind": kind, "path": path, "occurrenceCount": count})
    return rows


def _static_prohibited_findings(path: str, text: str) -> list[dict[str, str]]:
    if path == IMPLEMENTATION_PATHS[0]:
        return []
    code = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    rules = (
        ("C44_CONTRACT_REFERENCE_OUTSIDE_INERT_OWNER", r"\b(?:" + "|".join(map(re.escape, CONTRACT_NAMES)) + r")\b"),
        ("C44_PROVIDER_CONFORMER", r"(?::|extension[^\n{]+:)\s*EmailServiceProviderAdapterV1\b"),
        ("PROVIDER_SDK_OR_PACKAGE", r"\b(?:Mailchimp|SendGrid|Braze|Iterable|CustomerIO|ConstantContact|HubSpot)\b"),
        ("SUBSCRIBER_OR_MARKETING_REPOSITORY", r"\b(?:Subscriber|MarketingContact|CommunicationConsent|CommunicationPreference|Suppression)(?:Repository|Store|Row|Entity|ManagedObject|Model)\b"),
        ("OPERATIONAL_CONTACT_TO_SUBSCRIBER_CONVERTER", r"\b(?:Party|Site|ServiceParty|ServiceContact|OperationalContact)(?:To|As|Into)(?:Subscriber|MarketingContact)\b|\b(?:Subscriber|MarketingContact)(?:From|For)(?:Party|Site|ServiceParty|ServiceContact|OperationalContact)\b"),
        ("C44_PERSISTENCE_LIFECYCLE_REACHABILITY", r"\b(?:Backup|Restore|Persistence|Search|Report|Delete|Erase)[A-Za-z0-9_]*(?:Subscriber|MarketingContact|CommunicationConsent|CommunicationPreference|Suppression)\b|\b(?:Subscriber|MarketingContact|CommunicationConsent|CommunicationPreference|Suppression)[A-Za-z0-9_]*(?:Backup|Restore|Persistence|Search|Report|Delete|Erase)\b"),
        ("SIGNUP_PREFERENCE_ROUTE_OR_RESOURCE", r"\b(?:NewsletterSignup|MarketingSignup|NewsletterRoute|SubscriberSettings|MarketingPreferenceView|CommunicationPreferenceRoute)\b"),
        ("PROVIDER_CREDENTIAL_OR_ENDPOINT", r"\b(?:marketing|newsletter|subscriber|mailchimp|sendgrid)[A-Za-z0-9_]*(?:APIKey|ClientSecret|Credential|Endpoint|BaseURL)\b"),
        ("SEND_OR_BACKGROUND_DELIVERY", r"\b(?:MarketingSendQueue|NewsletterSend|EmailCampaignSender|SubscriberUploadTask|BackgroundMarketingTask)\b"),
        ("AD_AUDIENCE_IDENTITY", r"\b(?:LookalikeAudience|RetargetingAudience|AdAudience|HashedEmailAudience|CustomerMatch)\b"),
        ("LIVE_PROVIDER_OR_SUBSCRIBER_URL", r"\bhttps?://(?!example\.invalid\b|assetrounds\.invalid\b)[^\s\"']*(?:mailchimp|sendgrid|braze|iterable|customer\.io|subscribe|newsletter)[^\s\"']*"),
    )
    findings = []
    for rule_id, pattern in rules:
        for match in re.finditer(pattern, code, re.I | re.M):
            findings.append({"path": path, "ruleID": rule_id, "matchedSHA256": sha256_bytes(match.group(0).encode())})
    return findings


def bounded_repository_scan(root: Path) -> dict[str, Any]:
    paths = _shipping_scan_paths(root)
    rows: list[dict[str, Any]] = []
    findings: list[dict[str, str]] = []
    exemptions: list[dict[str, Any]] = []
    for path in paths:
        raw = (root / path).read_bytes()
        rows.append({"path": path, "sha256": sha256_bytes(raw), "byteCount": len(raw)})
        text = _scan_text(raw)
        findings.extend(_static_prohibited_findings(path, text))
        exemptions.extend(_recognized_scan_exemptions(path, text))
    dependency_inventory = _dependency_inventory(root, paths)
    findings.sort(key=lambda item: (item["path"].lower(), item["path"], item["ruleID"], item["matchedSHA256"]))
    exemptions.sort(key=lambda item: (item["path"].lower(), item["path"], item["kind"]))
    proof = {
        "scope": "BOUNDED_SHIPPING_APP_PROJECT_DEPENDENCY_CONFIGURATION_STATIC_BYTES",
        "scannedPaths": paths,
        "scannedPathCount": len(paths),
        "pathSetSHA256": sha256_value(paths),
        "aggregateContentSHA256": sha256_value(rows),
        "dependencyPackageInventory": dependency_inventory,
        "dependencyPackageInventorySHA256": sha256_value(dependency_inventory),
        "recognizedExemptions": exemptions,
        "prohibitedFindings": findings,
        "prohibitedFindingCount": len(findings),
        "claimsNativeArchiveOrLinkedBinaryInspection": False,
        "claimsRuntimeNetworkObservation": False,
    }
    return {**proof, "scanDigest": sha256_value(proof)}


def assert_static_scan_clean(scan: dict[str, Any]) -> None:
    paths = scan.get("scannedPaths", [])
    if (
        paths != sorted(paths, key=lambda value: (value.lower(), value))
        or scan.get("scannedPathCount") != len(paths)
        or scan.get("pathSetSHA256") != sha256_value(paths)
        or scan.get("prohibitedFindings") != []
        or scan.get("prohibitedFindingCount") != 0
        or scan.get("claimsNativeArchiveOrLinkedBinaryInspection") is not False
        or scan.get("claimsRuntimeNetworkObservation") is not False
    ):
        raise ValueError("C44 bounded shipping repository scan differs or found prohibited surface")


def assert_source_regressions(root: Path) -> None:
    require_source_ready(root)
    static_scan = bounded_repository_scan(root)
    assert_static_scan_clean(static_scan)
    contracts = _tokens(root, IMPLEMENTATION_PATHS[0], *CONTRACT_NAMES, *PURPOSES)
    for token in (
        "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION", "REVIEW_REQUIRED", "plus",
        "comparison", "disclosure", "presentedLocale", "withdraw", "suppression",
        "PENDING_EXACT_CANDIDATE_ARCHIVE_RUNTIME_NATIVE_EVIDENCE", "authorizesIssuance = false",
    ):
        if token.lower() not in contracts.lower():
            raise ValueError("C44 contract semantics regressed:" + token)
    forbidden = _forbidden_active_surface(contracts)
    if forbidden:
        raise ValueError("C44 active provider/transmission surface detected:" + ",".join(forbidden))
    evaluator = _tokens(root, IMPLEMENTATION_PATHS[1], "CommunicationConsentSyntheticEvaluatorV1", "synthetic", "canonical")
    scanner = _tokens(
        root, IMPLEMENTATION_PATHS[2], "ZeroSubscriberTransmissionConformanceScannerV1",
        "claimsReleaseArchiveInspection", "claimsRuntimeNetworkObservation",
        "feedbackMessageUISupport", "storeKitCommerce", "metricKitOSSubscriber",
        "notificationCenterOrLocalScheduling", "inertSchemaOrExampleURL", "dispatchConcurrency",
        "localAuthentication", "providerSDKOrBinding", "providerCredentialOrEndpoint",
        "sendQueueOrBackgroundTask", "signupPreferenceRouteOrHandler", "operationalContactConversion",
        "mailingImportOrExport", "plainAddressHash", "adAudienceOrTrackingIdentity",
    )
    if re.search(r"\b(?:URLSession|NWConnection)\b|^\s*import\s+(?:Mailchimp|SendGrid|Braze|Iterable|CustomerIO)\b", evaluator, re.I | re.M):
        raise ValueError("C44 evaluator gained network/provider API")
    tests = _tokens(root, IMPLEMENTATION_PATHS[3], *TEST_METHODS)
    for token in ("transactional", "operational", "normalization", "disclosure", "withdraw", "suppression", "retry", "rollback", "supersed"):
        if token.lower() not in tests.lower():
            raise ValueError("C44 hostile/recovery coverage regressed:" + token)
    _tokens(
        root, IMPLEMENTATION_PATHS[5], "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION",
        "unbound future application port", "compiled archive", "linked-binary",
        "resource", "string", "route", "settings", "background-task", "credential", "endpoint",
        "controlled runtime-network observation", "No native-archive, linked-binary, runtime-network, public-copy, App Privacy, or Release-acceptance result is claimed",
    )
    corpus = _closed_corpus(root)
    proof_dispositions = ["STATIC_SOURCE_SCAN_CLEAN"] + ["PENDING_NOT_ACCEPTING"] * 10
    dependency_proof = corpus.get("archiveProofs", [{}])[0]
    expected_repository_proof = {
        "repositoryScanPathCount": static_scan["scannedPathCount"],
        "repositoryScanPathSetSHA256": static_scan["pathSetSHA256"],
        "repositoryScanAggregateContentSHA256": static_scan["aggregateContentSHA256"],
        "repositoryScanDependencyInventorySHA256": static_scan["dependencyPackageInventorySHA256"],
        "repositoryScanDigest": static_scan["scanDigest"],
        "repositoryScanProhibitedFindingCount": 0,
    }
    if (
        corpus.get("schema") != "V22P03C44CommunicationConsentCorpusV1"
        or corpus.get("schemaVersion") != 1 or corpus.get("cardID") != CARD
        or corpus.get("classification") != "PREPARE_NOW"
        or corpus.get("collectionDisposition") != "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION"
        or [item.get("purpose") for item in corpus.get("purposes", [])] != list(PURPOSES)
        or corpus.get("hostileCases") != list(HOSTILE_CASES)
        or [item.get("surface") for item in corpus.get("archiveProofs", [])] != list(ARCHIVE_SURFACES)
        or [item.get("disposition") for item in corpus.get("archiveProofs", [])] != proof_dispositions
        or any(item.get("forbiddenFindings") != [] for item in corpus.get("archiveProofs", []))
        or any(dependency_proof.get(key) != value for key, value in expected_repository_proof.items())
        or corpus.get("evidenceIDs") != [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
        or corpus.get("statusFlags") != {key: False for key in ("native", "hosted", "adoption", "acceptance", "release")}
    ):
        raise ValueError("C44 corpus authority differs")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (0, 14, 14) or len(set(PATH_FENCE)) != 14:
        raise ValueError("C44 fence must be unique 14=0+14")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C44 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C44 base tree differs")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"C44 new path existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 0 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C44 authority/status proof differs")
    if PERSISTENCE["durableFamilyCount"] != 0 or PERSISTENCE["persistentKindLifecycleModelCount"] != 0:
        raise ValueError("C44 must remain nonpersistent")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE,
        "classification": "PREPARE_NOW", "planningStatus": "NOT_STARTED",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST, "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": 14, "existingPathCount": 0, "newPathCount": 14,
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
        "directPrerequisiteCards": ["V23-P03-C20"], "nextCard": "V23-P03-C45", "nextRegisterOrdinal": 75,
    }


def _closed_object(properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties, "required": required}


def schema_document(root: Path | None = None) -> dict[str, Any]:
    root = root or Path(__file__).resolve().parents[2]
    static_scan = bounded_repository_scan(root)
    assert_static_scan_clean(static_scan)
    text = {"type": "string", "minLength": 1}
    strings = lambda minimum=1: {"type": "array", "minItems": minimum, "uniqueItems": True, "items": text}
    purpose = _closed_object({
        "purpose": {"enum": list(PURPOSES)}, "createsMarketingContact": {"type": "boolean"},
        "independentAffirmativeEnrollmentRequired": {"type": "boolean"}, "consentNontransitive": {"const": True},
        "transactionalExclusionOnly": {"type": "boolean"},
    }, ["purpose", "createsMarketingContact", "independentAffirmativeEnrollmentRequired", "consentNontransitive", "transactionalExclusionOnly"])
    truth = _closed_object({key: text for key in (
        "caseID", "source", "disclosureReleaseID", "presentedLocale", "verificationStatus"
    )} | {
        "purpose": {"enum": list(PURPOSES)},
        "expectedDisposition": {"enum": [
            "ELIGIBLE_EXPLICIT_INDEPENDENT_ENROLLMENT", "REVIEW_REQUIRED",
            "INELIGIBLE_TRANSACTIONAL_OR_SUPPORT", "INELIGIBLE_NONAFFIRMATIVE",
            "INELIGIBLE_SOURCE", "INELIGIBLE_DISCLOSURE", "INELIGIBLE_LAWFUL_BASIS",
        ]},
        "affirmative": {"type": "boolean"}, "prechecked": {"type": "boolean"}, "inferred": {"type": "boolean"}},
        ["caseID", "purpose", "source", "affirmative", "prechecked", "inferred", "disclosureReleaseID", "presentedLocale", "verificationStatus", "expectedDisposition"])
    normalization = _closed_object({key: text for key in ("caseID", "enteredAddress", "comparisonAddress", "policyReleaseID")} | {"collisionDisposition": {"const": "REVIEW_REQUIRED"}},
        ["caseID", "enteredAddress", "comparisonAddress", "policyReleaseID", "collisionDisposition"])
    disclosure = _closed_object({
        "releaseID": text, "version": {"type": "integer", "minimum": 1}, "digest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        "locales": strings(), "immutable": {"const": True}, "superseded": {"type": "boolean"},
    }, ["releaseID", "version", "digest", "locales", "immutable", "superseded"])
    suppression = _closed_object({key: text for key in ("caseID", "purpose", "channel")} | {
        "tokenKind": {"const": "CONTACT_INFO_PSEUDONYMOUS_NOT_ANONYMOUS"},
        "deleteReimportDisposition": {"const": "BLOCKED"},
        "plainHashForbidden": {"const": True}, "audienceUseForbidden": {"const": True},
    }, ["caseID", "purpose", "channel", "tokenKind", "plainHashForbidden", "deleteReimportDisposition", "audienceUseForbidden"])
    archive = _closed_object({"surface": {"enum": list(ARCHIVE_SURFACES)}, "disposition": {"enum": ["STATIC_SOURCE_SCAN_CLEAN", "PENDING_NOT_ACCEPTING"]}, "forbiddenFindings": {"type": "array", "maxItems": 0}}, ["surface", "disposition", "forbiddenFindings"])
    dependency_proof_keys = [
        "repositoryScanPathCount", "repositoryScanPathSetSHA256", "repositoryScanAggregateContentSHA256",
        "repositoryScanDependencyInventorySHA256", "repositoryScanDigest", "repositoryScanProhibitedFindingCount",
    ]
    archive_items = []
    for index, surface in enumerate(ARCHIVE_SURFACES):
        properties = {**archive["properties"], "surface": {"const": surface}, "disposition": {"const": "STATIC_SOURCE_SCAN_CLEAN" if index == 0 else "PENDING_NOT_ACCEPTING"}}
        required = list(archive["required"])
        if index == 0:
            properties |= {
                "repositoryScanPathCount": {"const": static_scan["scannedPathCount"]},
                "repositoryScanPathSetSHA256": {"const": static_scan["pathSetSHA256"]},
                "repositoryScanAggregateContentSHA256": {"const": static_scan["aggregateContentSHA256"]},
                "repositoryScanDependencyInventorySHA256": {"const": static_scan["dependencyPackageInventorySHA256"]},
                "repositoryScanDigest": {"const": static_scan["scanDigest"]},
                "repositoryScanProhibitedFindingCount": {"const": 0},
            }
            required += dependency_proof_keys
        archive_items.append(_closed_object(properties, required))
    lifecycle_keys = ["persistence", "contracts", "providerPort", "runtimeStorage", "runtimeProvider", "runtimeNetwork", "retry", "rollback", "supersession"]
    invariant_keys = [
        "purposeConsentNontransitive", "transactionalNeverCreatesMarketingContact", "operationalContactsNeverConvert",
        "exactEnteredAddressPreserved", "normalizationPolicyVersioned", "collisionsRequireReview", "disclosureReleaseAndLocalePinned",
        "withdrawalAppendOnly", "suppressionSurvivesDeleteAndReimport", "plainHashForbidden", "suppressionNotAudience",
        "providerPortUnbound", "providerSecretsAbsentFromApp", "noSubscriberPersistence", "noNetworkTransmission",
        "configCannotActivate", "ownerAcceptanceRequired", "adAudienceEquivalenceForbidden",
    ]
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/communication-consent.schema.json",
        "title": "V23 P03 C44 Communication Consent Corpus", "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C44CommunicationConsentCorpusV1"}, "schemaVersion": {"const": 1},
            "cardID": {"const": CARD}, "classification": {"const": "PREPARE_NOW"},
            "collectionDisposition": {"const": "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION"},
            "purposes": {"type": "array", "minItems": 4, "maxItems": 4, "items": purpose},
            "consentTruthTable": {"type": "array", "minItems": 8, "items": truth},
            "normalizationCases": {"type": "array", "minItems": 3, "items": normalization},
            "disclosureReleases": {"type": "array", "minItems": 1, "items": disclosure},
            "suppressionCases": {"type": "array", "minItems": 3, "items": suppression},
            "hostileCases": {"const": list(HOSTILE_CASES)},
            "archiveProofs": {"type": "array", "minItems": 11, "maxItems": 11, "items": False, "prefixItems": archive_items},
            "lifecycle": _closed_object({key: text for key in lifecycle_keys}, lifecycle_keys),
            "invariants": _closed_object({key: {"const": True} for key in invariant_keys}, invariant_keys),
            "evidenceIDs": {"const": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]},
            "statusFlags": _closed_object({key: {"const": False} for key in ("native", "hosted", "adoption", "acceptance", "release")}, ["native", "hosted", "adoption", "acceptance", "release"]),
        },
        "required": [
            "schema", "schemaVersion", "cardID", "classification", "collectionDisposition", "purposes",
            "consentTruthTable", "normalizationCases", "disclosureReleases", "suppressionCases", "hostileCases",
            "archiveProofs", "lifecycle", "invariants", "evidenceIDs", "statusFlags",
        ],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    static_scan = bounded_repository_scan(root)
    assert_static_scan_clean(static_scan)
    semantics = {
        "contractNames": list(CONTRACT_NAMES), "fiveSelectors": list(observed_selectors(root)),
        "fourPurposesRemainExactlySeparated": True, "operationalContactNeverInfersMarketingEnrollment": True,
        "transactionalOrSupportNeverCreatesMarketingRows": True, "consentIsIndependentAffirmativeAndNontransitive": True,
        "enteredAddressAndVersionedComparisonPolicyArePreserved": True, "normalizationCollisionRequiresReview": True,
        "disclosureDigestLocaleVerificationAndWithdrawalHistoryAreBound": True,
        "minimumKeyedSuppressionSurvivesDeleteReimportAndIsNotAnonymousOrAudience": True,
        "providerPortRemainsUnboundWithNoRuntimeStorageCredentialsEndpointOrTransmission": True,
        "zeroSubscriberReceiptIsUnissuablePendingExactCandidateEvidence": True,
        "boundedShippingRepositoryAndDependencyStaticScanIsClean": True,
        "staticInventoryDoesNotClaimNativeArchiveLinkedBinaryOrRuntimeProof": True,
        "exactCandidateArchiveLinkResourceStringRouteSettingsBackgroundCredentialEndpointAndRuntimeEvidenceIsPendingNotAccepting": True,
        "messageUIStoreKitMetricKitOSSubscriberLocalNotificationsInertURLsDispatchAndLocalAuthenticationArePurposeAwareScanExemptions": True,
    }
    return _sealed({"schema": "V23P03C44CommunicationConsentContractV1", "schemaVersion": 1, "authority": authority(), "persistence": PERSISTENCE, "staticRepositoryScan": static_scan, "requiredSemantics": semantics})


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    static_scan = bounded_repository_scan(root)
    assert_static_scan_clean(static_scan)
    return _sealed({
        "schema": "V23P03C44CommunicationConsentEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "classification": "PREPARE_NOW", "collectionDisposition": "DISABLED_NO_SUBSCRIBER_COLLECTION_OR_TRANSMISSION",
        "evidenceIDs": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")],
        "testSelectors": list(observed_selectors(root)), "persistence": PERSISTENCE,
        "staticRepositoryScan": static_scan,
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
        "receiptIssuanceState": "PENDING_EXACT_CANDIDATE_ARCHIVE_RUNTIME_NATIVE_EVIDENCE",
        "authorizesIssuance": False, "archiveProofState": "PENDING_NOT_ACCEPTING",
        "runtimeNetworkProofState": "PENDING_NOT_ACCEPTING", "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    })


def brand_document() -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C44BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "uiSurfaceDelta": False, "brandSurfaceDelta": False, "publicClaimDelta": False,
        "nativeIPadSurface": False, "customerVisibleSignupOrPreferenceUI": False, "subscriberCollection": False,
        "networkTransmission": False, "runtimeProvider": False, "customerWorkTransmission": False,
        "adAudienceExport": False, "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    static_scan = bounded_repository_scan(root)
    assert_static_scan_clean(static_scan)
    rendered = {
        SCHEMA_PATH: pretty(schema_document(root)), CONTRACT_PATH: pretty(contract_document(root)),
        EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document()),
    }
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "schema": "V23P03C44ToolingManifestV1", "schemaVersion": 1, "authority": authority(),
        "pathFence": list(PATH_FENCE), "pathFenceCount": 14, "existingPathCount": 0, "newPathCount": 14,
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0, "artifacts": rows,
        "artifactSetDigest": sha256_value(rows), "staticRepositoryScan": static_scan,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    }))
    return rendered
