#!/usr/bin/env python3
"""Deterministic zero-collection tooling model for V23-P03-C43."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C43"
TITLE = "Privacy-first customer-learning and acquisition-measurement contract, zero-collection default, and explicit activation gate"
REGISTER_ORDINAL = 73
BASE_HEAD = "92f9fd0dda196da017a909248e5d5c65dc9fcfc1"
BASE_TREE = "b6c49a03dc96acf65c11d36b79e420e88fb3015e"
COORDINATION_HEAD = "40fdf45f071dacd8b47dea518e071a2b07510a5f"
COORDINATION_TREE = "dba3ec2b3e6f3b5822303ebd4bb5d05bcc3c2baa"
COORDINATION_CAS_SEQUENCE = 310
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "f25e638e7198ea80acc7416b3dd4fe30a1bbfd2b2902ee914af9202283d95b4d"
CONTEXT_DIGEST = "1bfab05155a2de75d1e088662d0b70619d11bf6840c5c68761f6fe768738a924"
FENCE_DIGEST = "0c4c80889e7b193b538751905fde435df24d298022d25828acfdc5354aa69649"
HYDRATION_TRANSITION_DIGEST = "a1a53a171394b9c4351687bd5fea96021756fc4518e876e777da231961746a15"
COORDINATION_LEDGER_DIGEST = "70f8bb799125d67fbf1e358e9b3847fc50a5ec147784bc8a233810fefb6e3198"
COORDINATION_PROJECTION_DIGEST = "d3e2e7d8b8bfa87997d6257d658fc96dee20b6116ed6b43c67b6cd1799bec99b"
AUTHORIZED_OVERLAP_COUNT = 0
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/customer-learning.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C43CustomerLearningContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C43CustomerLearningEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C43BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C43-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c43_contracts.py",
    "Scripts/v23/generate_p03_c43_contracts.py",
    "Scripts/v23/verify_p03_c43_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/CustomerLearning/CustomerLearningContractsV1.swift",
    "FieldEvidenceAppTests/TestSupport/CustomerLearning/CustomerLearningSyntheticEvaluatorV1.swift",
    "FieldEvidenceAppTests/TestSupport/CustomerLearning/ZeroCollectionConformanceScannerV1.swift",
    "FieldEvidenceAppTests/V9_50CustomerLearningMeasurementTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/CustomerLearning/V22P03C43CustomerLearningCorpusV1.json",
    "Release/V23P03C43CustomerLearningActivationBoundaryV1.md",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
EXISTING_PATHS: tuple[str, ...] = ()
PATH_FENCE = NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "CustomerLearningQuestionV1",
    "CustomerLearningMetricDefinitionV1",
    "MeasurementPurposeV1",
    "AcquisitionSourceVocabularyV1",
    "MeasurementSourceKindV1",
    "MeasurementActivationDecisionV1",
    "MeasurementCollectionDispositionV1",
    "ZeroCollectionConformanceReceiptV1",
)
TEST_METHODS = (
    "testV23P03C43G01StaticCatalogRemainsZeroCollectionAndPurposeBound",
    "testV23P03C43A01MissingThresholdAndDelayedSourcesRemainUnknownOrSuppressed",
    "testV23P03C43H01ForbiddenIdentityJoinsActivationAndRuntimeProvidersFailClosed",
    "testV23P03C43I01SyntheticEvaluationIsDeterministicAndLeavesNoRuntimeState",
    "testV23P03C43R01ArchiveRuntimeRollbackAndSupersessionPreserveZeroCollection",
)
SOURCE_KINDS = (
    "APP_STORE_CONNECT_AGGREGATE",
    "EXPLICIT_FIELD_RESEARCH",
    "REBUILDABLE_OPERATIONAL_RECEIPT_PROJECTION",
    "FUTURE_CONSENTED_PRODUCT_ANALYTICS",
)
HOSTILE_CASES = (
    "DENOMINATOR_DRIFT", "CAMPAIGN_LABEL_RENAME", "SMALL_COHORT", "DELAYED_OR_MISSING_APP_STORE_REPORT",
    "OPT_IN_POPULATION_BIAS", "DUPLICATE_SYNTHETIC_RECEIPT", "CLOCK_OR_TIME_ZONE_CHANGE",
    "CUSTOMER_TEXT_AS_DIMENSION", "HASHED_EMAIL_OR_DEVICE_ID_AS_ANONYMOUS", "TRANSITIVE_ANALYTICS_SDK",
    "HIDDEN_CRASH_OR_SUPPORT_LOGGING_REUSE", "REMOTE_ENABLE_FLAG", "CORRELATION_MEANS_CAUSATION_COPY",
)
FLAGS = {key: False for key in (
    "native", "hosted", "archive", "runtime", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "archiveAcceptance", "runtimeAcceptance",
    "adoptionEvidence", "acceptanceCredit", "releaseReadiness",
    "phase10PollingDuringParallelExecution",
)}
PERSISTENCE: dict[str, Any] = {
    "mode": "NONPERSISTENT_STATIC_POLICY_AND_SYNTHETIC_TESTSUPPORT_ONLY",
    "persistentSchemaVersion": None,
    "recordsSchemaVersion": None,
    "persistentKindLifecycleModelCount": 0,
    "durableFamilyCount": 0,
    "persistedFamilies": [],
    "eventInstancePersistence": False,
    "operationalReceiptProjectionPersistence": False,
    "runtimeInvocation": False,
    "networkLifecycle": False,
    "acceptedContractReleaseDisposition": "IMMUTABLE_VERSION_AND_DIGEST_SUPERSESSION_ONLY",
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_paths(root: Path, *args: str) -> set[str]:
    output = subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout
    return {path.replace("\\", "/") for path in output.splitlines() if path}


def observed_changed_paths(root: Path) -> set[str]:
    changed = _git_paths(root, "diff", "--name-only", f"{BASE_HEAD}..HEAD", "--")
    changed |= _git_paths(root, "diff", "--name-only", "--")
    changed |= _git_paths(root, "diff", "--cached", "--name-only", "--")
    changed |= _git_paths(root, "ls-files", "--others", "--exclude-standard")
    return changed


def _base_exists(root: Path, path: str) -> bool:
    return subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{path}"], capture_output=True).returncode == 0


def _text(root: Path, path: str) -> str:
    target = root / path
    if not target.is_file():
        raise ValueError(f"C43 stable source absent:{path}")
    return target.read_text(encoding="utf-8")


def _tokens(root: Path, path: str, *tokens: str) -> str:
    text = _text(root, path)
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"C43 source regression:{path}:" + ",".join(missing))
    return text


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[3]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C43(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def _closed_corpus(root: Path) -> dict[str, Any]:
    corpus = json.loads(_text(root, IMPLEMENTATION_PATHS[4]))
    keys = {
        "schema", "schemaVersion", "cardID", "classification", "collectionDisposition", "questions",
        "metricDefinitions", "sourceSeparation", "activationDecision", "hostileCases", "archiveProofs",
        "lifecycle", "invariants", "evidenceIDs", "statusFlags",
    }
    if set(corpus) != keys:
        raise ValueError("C43 closed corpus top-level differs")
    return corpus


def require_source_ready(root: Path) -> None:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    if missing:
        raise ValueError("C43 stable source absent:" + ",".join(missing))
    if observed_selectors(root) != TEST_METHODS:
        raise ValueError("C43 exact ordered G/A/H/I/R selectors differ")
    _closed_corpus(root)


def _forbidden_active_surface(text: str) -> list[str]:
    """Scan executable C43 Swift while excluding comments, inert schema IDs, and unrelated Apple support modules."""
    code = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    forbidden = {
        "URLSession": r"\bURLSession\b",
        "NWConnection": r"\bNWConnection\b",
        "analytics import": r"^\s*import\s+(?:FirebaseAnalytics|Amplitude|Mixpanel|Segment)\b",
        "runtime endpoint": r"\bhttps?://(?!example\.invalid\b)[^\s\"']+",
        "remote activation": r"\b(?:RemoteConfig|remoteEnable|campaignTokenHandler)\b",
        "identifier tracking": r"\b(?:ASIdentifierManager|advertisingIdentifier|IDFA|fingerprint)\b",
    }
    return [name for name, pattern in forbidden.items() if re.search(pattern, code, re.I | re.M)]


def assert_source_regressions(root: Path) -> None:
    require_source_ready(root)
    contracts = _tokens(root, IMPLEMENTATION_PATHS[0], *CONTRACT_NAMES, *SOURCE_KINDS)
    for token in (
        "DISABLED_NO_COLLECTION", "UNKNOWN", "SUPPRESSED", "MeasurementUserLinkageDispositionV1",
        "noncausal", "privacyThreshold", "missing", "remoteActivationEnabled", "ownerAcceptance",
        "PENDING_EXACT_CANDIDATE_ARCHIVE_RUNTIME_NATIVE_EVIDENCE", "authorizesIssuance = false",
    ):
        if token.lower() not in contracts.lower():
            raise ValueError("C43 contract semantics regressed:" + token)
    forbidden = _forbidden_active_surface(contracts)
    if forbidden:
        raise ValueError("C43 active runtime/collection surface detected:" + ",".join(forbidden))
    if re.search(r"\bfunc\s+evaluate\s*\(", contracts):
        raise ValueError("C43 shipping value evaluation entrypoint detected")
    evaluator = _tokens(
        root, IMPLEMENTATION_PATHS[1], "CustomerLearningSyntheticEvaluatorV1", ".unknown", "providerSuppressed",
        "synthetic", "canonicalResultData", "missing",
    )
    if re.search(r"\b(?:URLSession|NWConnection)\b|^\s*import\s+(?:FirebaseAnalytics|Amplitude|Mixpanel|Segment)\b", evaluator, re.I | re.M):
        raise ValueError("C43 synthetic evaluator gained network/provider API")
    scanner = _tokens(
        root, IMPLEMENTATION_PATHS[2], "ZeroCollectionConformanceScannerV1", "analyticsAttributionOrAdSDK",
        "productEventStore", "productMeasurementEndpoint", "backgroundProductUpload",
        "claimsReleaseArchiveInspection", "claimsRuntimeNetworkObservation",
    )
    if re.search(r"\b(?:URLSession|NWConnection)\b|^\s*import\s+(?:FirebaseAnalytics|Amplitude|Mixpanel|Segment)\b", scanner, re.I | re.M):
        raise ValueError("C43 conformance scanner gained network/provider API")
    tests = _tokens(root, IMPLEMENTATION_PATHS[3], *TEST_METHODS)
    for token in ("denominator", "campaign", "threshold", "missing", "duplicate", "customer", "remote", "rollback", "supersed"):
        if token.lower() not in tests.lower():
            raise ValueError("C43 hostile/recovery coverage regressed:" + token)
    release = _tokens(
        root, IMPLEMENTATION_PATHS[5], "DISABLED_NO_COLLECTION", "OWNER_ACCEPTED_PENDING_SEPARATE_IMPLEMENTATION_CARD",
        "Compiled archive", "linked binary", "string", "dependency", "domain", "background-task",
        "Controlled runtime network observation", "No archive, runtime-network, App Privacy, or Release-acceptance result is claimed",
    )
    corpus = _closed_corpus(root)
    if (
        corpus.get("schema") != "V22P03C43CustomerLearningCorpusV1"
        or corpus.get("schemaVersion") != 1
        or corpus.get("cardID") != CARD
        or corpus.get("classification") != "PREPARE_NOW"
        or corpus.get("collectionDisposition") != "DISABLED_NO_COLLECTION"
        or len(corpus.get("questions", [])) < 7
        or len(corpus.get("metricDefinitions", [])) < 7
        or [item.get("sourceKind") for item in corpus.get("sourceSeparation", [])] != list(SOURCE_KINDS)
        or any(item.get("nonjoinable") is not True or item.get("userLevelLinkageForbidden") is not True for item in corpus.get("sourceSeparation", []))
        or corpus.get("evidenceIDs") != [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
        or corpus.get("hostileCases") != list(HOSTILE_CASES)
        or [item.get("surface") for item in corpus.get("archiveProofs", [])] != ["DEPENDENCY", "LINK", "STRING", "DOMAIN", "BACKGROUND_TASK", "RUNTIME_NETWORK"]
        or [item.get("disposition") for item in corpus.get("archiveProofs", [])] != ["STATIC_SOURCE_SCAN_CLEAN"] + ["PENDING_NOT_ACCEPTING"] * 5
        or any(item.get("forbiddenFindings") != [] for item in corpus.get("archiveProofs", []))
        or corpus.get("statusFlags") != {key: False for key in ("native", "hosted", "adoption", "acceptance", "release")}
    ):
        raise ValueError("C43 corpus authority differs")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (0, 14, 14) or len(set(PATH_FENCE)) != 14:
        raise ValueError("C43 fence must be unique 14=0+14")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C43 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C43 base tree differs")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"C43 new path existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 0 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C43 authority/status proof differs")
    if PERSISTENCE["durableFamilyCount"] != 0 or PERSISTENCE["persistentKindLifecycleModelCount"] != 0:
        raise ValueError("C43 must remain nonpersistent")


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
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0, "directPrerequisiteCards": ["V23-P03-C21"],
        "nextCard": "V23-P03-C44", "nextRegisterOrdinal": 74,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value))}


def _string_array(min_items: int = 1) -> dict[str, Any]:
    return {"type": "array", "minItems": min_items, "uniqueItems": True, "items": {"type": "string", "minLength": 1}}


def schema_document() -> dict[str, Any]:
    question = {
        "type": "object", "additionalProperties": False,
        "properties": {
            "questionID": {"type": "string", "minLength": 1}, "version": {"type": "integer", "minimum": 1},
            "decisionID": {"type": "string", "minLength": 1}, "purpose": {"type": "string", "minLength": 1},
            "allowedSourceKinds": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"enum": list(SOURCE_KINDS)}},
            "exclusions": _string_array(),
        },
        "required": ["questionID", "version", "decisionID", "purpose", "allowedSourceKinds", "exclusions"],
    }
    metric = {
        "type": "object", "additionalProperties": False,
        "properties": {
            key: {"type": "string", "minLength": 1} for key in (
                "metricID", "questionID", "decisionID", "numeratorID", "denominatorID",
                "sourceReleaseID", "formula", "unit", "missingDataDisposition",
                "noncausalInterpretation",
            )
        } | {
            "version": {"type": "integer", "minimum": 1},
            "sourceKind": {"enum": list(SOURCE_KINDS)}, "exclusions": _string_array(),
            "privacyThreshold": {"type": "integer", "minimum": 1},
            "observationWindowDays": {"type": "integer", "minimum": 1},
            "attributionWindowDays": {"type": "integer", "minimum": 1},
        },
        "required": [
            "metricID", "version", "questionID", "decisionID", "numeratorID", "denominatorID", "formula", "unit",
            "sourceKind", "sourceReleaseID", "privacyThreshold", "missingDataDisposition", "noncausalInterpretation",
            "observationWindowDays", "attributionWindowDays", "exclusions",
        ],
    }
    source = {
        "type": "object", "additionalProperties": False,
        "properties": {
            "sourceKind": {"enum": list(SOURCE_KINDS)}, "releaseID": {"type": "string", "minLength": 1},
            "provenance": {"type": "string", "minLength": 1},
            "privacyThreshold": {"type": "integer", "minimum": 1}, "eligibility": {"type": "string", "minLength": 1},
            "refreshLagDays": {"type": "integer", "minimum": 0}, "missingness": {"type": "string", "minLength": 1},
            "nonjoinable": {"const": True}, "userLevelLinkageForbidden": {"const": True},
        },
        "required": ["sourceKind", "releaseID", "provenance", "privacyThreshold", "eligibility", "refreshLagDays", "missingness", "nonjoinable", "userLevelLinkageForbidden"],
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/customer-learning.schema.json",
        "title": "V23 P03 C43 Customer Learning Corpus", "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C43CustomerLearningCorpusV1"}, "schemaVersion": {"const": 1},
            "cardID": {"const": CARD}, "classification": {"const": "PREPARE_NOW"},
            "collectionDisposition": {"const": "DISABLED_NO_COLLECTION"},
            "questions": {"type": "array", "minItems": 7, "items": question},
            "metricDefinitions": {"type": "array", "minItems": 7, "items": metric},
            "sourceSeparation": {"type": "array", "minItems": 4, "maxItems": 4, "items": source},
            "activationDecision": {
                "type": "object", "additionalProperties": False,
                "properties": {
                    "state": {"const": "UNACTIVATED_OWNER_ACCEPTANCE_REQUIRED"},
                    "ownerAcceptanceRequired": {"const": True}, "configCannotActivate": {"const": True},
                    "expires": {"const": True},
                },
                "required": ["state", "ownerAcceptanceRequired", "configCannotActivate", "expires"],
            },
            "hostileCases": _string_array(12),
            "archiveProofs": {
                "type": "array", "minItems": 6, "maxItems": 6, "items": False,
                "prefixItems": [{
                    "type": "object", "additionalProperties": False,
                    "properties": {
                        "surface": {"const": surface}, "disposition": {"const": disposition},
                        "forbiddenFindings": {"type": "array", "maxItems": 0},
                    },
                    "required": ["surface", "disposition", "forbiddenFindings"],
                } for surface, disposition in (
                    ("DEPENDENCY", "STATIC_SOURCE_SCAN_CLEAN"),
                    ("LINK", "PENDING_NOT_ACCEPTING"),
                    ("STRING", "PENDING_NOT_ACCEPTING"),
                    ("DOMAIN", "PENDING_NOT_ACCEPTING"),
                    ("BACKGROUND_TASK", "PENDING_NOT_ACCEPTING"),
                    ("RUNTIME_NETWORK", "PENDING_NOT_ACCEPTING"),
                )],
            },
            "lifecycle": {
                "type": "object", "additionalProperties": False,
                "properties": {
                    "persistence": {"const": "NONPERSISTENT"}, "catalog": {"const": "STATIC_VERSIONED_POLICY"},
                    "evaluator": {"const": "SYNTHETIC_TEST_TARGET_ONLY"}, "runtimeStorage": {"const": "NONE"},
                    "runtimeProvider": {"const": "NONE"}, "runtimeNetwork": {"const": "NONE"},
                    "retry": {"const": "BYTE_IDENTICAL_RESULT_OR_NO_EFFECT"},
                    "rollback": {"const": "REMOVE_UNACTIVATED_CONTRACT_AND_TEST_CHANGES"},
                    "supersession": {"const": "IMMUTABLE_RELEASES_SUPERSEDED_NOT_REWRITTEN"},
                },
                "required": ["persistence", "catalog", "evaluator", "runtimeStorage", "runtimeProvider", "runtimeNetwork", "retry", "rollback", "supersession"],
            },
            "invariants": {
                "type": "object", "additionalProperties": False,
                "properties": {key: {"const": True} for key in (
                    "fourSourcesNonjoinable", "userLevelLinkageForbidden", "missingNeverZero", "thresholdSuppressesSmallCohort",
                    "evaluatorSyntheticOnly", "noProductionReceiptReader", "noWorkflowFrictionInput", "noDiagnosticsInput",
                    "noIdentityInput", "noNetwork", "noPersistence", "noRuntimeProvider", "configCannotActivate",
                    "ownerAcceptanceRequired", "noOperationalMetricBridge", "noScreenNameIdentity", "noCausalClaim",
                )},
                "required": [
                    "fourSourcesNonjoinable", "userLevelLinkageForbidden", "missingNeverZero", "thresholdSuppressesSmallCohort",
                    "evaluatorSyntheticOnly", "noProductionReceiptReader", "noWorkflowFrictionInput", "noDiagnosticsInput",
                    "noIdentityInput", "noNetwork", "noPersistence", "noRuntimeProvider", "configCannotActivate",
                    "ownerAcceptanceRequired", "noOperationalMetricBridge", "noScreenNameIdentity", "noCausalClaim",
                ],
            },
            "evidenceIDs": {"const": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]},
            "statusFlags": {
                "type": "object", "additionalProperties": False,
                "properties": {key: {"const": False} for key in ("native", "hosted", "adoption", "acceptance", "release")},
                "required": ["native", "hosted", "adoption", "acceptance", "release"],
            },
        },
        "required": [
            "schema", "schemaVersion", "cardID", "classification", "collectionDisposition", "questions",
            "metricDefinitions", "sourceSeparation", "activationDecision", "hostileCases", "archiveProofs",
            "lifecycle", "invariants", "evidenceIDs", "statusFlags",
        ],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    semantics = {
        "contractNames": list(CONTRACT_NAMES), "fiveSelectors": list(observed_selectors(root)),
        "vendorNeutralQuestionAndMetricCatalogsAreVersioned": True,
        "fourMeasurementSourcesRemainPurposeBoundAndNonjoinable": True,
        "unknownMissingAndSuppressedAreDistinctFromZero": True,
        "customerContentAndSilentlyInferredPeopleAreForbidden": True,
        "screenCopyCoordinatesCampaignLabelsAndAccessibilityIDsAreNotSemanticIdentity": True,
        "operationalReceiptsRemainOperationalTruthNotAnalytics": True,
        "zeroCollectionReceiptIsUnissuablePendingExactCandidateEvidence": True,
        "shippingValueEvaluationEntrypointIsAbsent": True,
        "syntheticEvaluatorIsDeterministicAndLeavesNoReleaseStorage": True,
        "activationRequiresUnexpiredExplicitOwnerAcceptance": True,
        "configurationCannotActivateCollection": True,
        "dependencyStaticSourceScanIsClean": True,
        "exactCandidateLinkStringDomainBackgroundTaskAndRuntimeNetworkEvidenceIsPendingNotAccepting": True,
        "noSDKEventStoreEndpointUploaderIdentifierTrackingProviderUIExportOrRuntimeInvocation": True,
    }
    return _sealed({
        "schema": "V23P03C43CustomerLearningContractV1", "schemaVersion": 1,
        "authority": authority(), "persistence": PERSISTENCE, "requiredSemantics": semantics,
    })


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    return _sealed({
        "schema": "V23P03C43CustomerLearningEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "classification": "PREPARE_NOW", "collectionDisposition": "DISABLED_NO_COLLECTION",
        "evidenceIDs": [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")],
        "testSelectors": list(observed_selectors(root)), "persistence": PERSISTENCE,
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
        "archiveProofState": "PENDING_NOT_ACCEPTING", "runtimeNetworkProofState": "PENDING_NOT_ACCEPTING",
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    })


def brand_document() -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C43BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "uiSurfaceDelta": False, "brandSurfaceDelta": False, "publicClaimDelta": False,
        "nativeIPadSurface": False, "customerVisibleMeasurementUI": False,
        "telemetry": False, "networkProcessing": False, "runtimeProvider": False,
        "customerContentCollection": False, "identityJoining": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    })


def _row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    raw = rendered[path] if path in rendered else (root / path).read_bytes()
    return {"path": path, "sha256": sha256_bytes(raw), "byteCount": len(raw)}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    rendered = {
        SCHEMA_PATH: pretty(schema_document()), CONTRACT_PATH: pretty(contract_document(root)),
        EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document()),
    }
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "schema": "V23P03C43ToolingManifestV1", "schemaVersion": 1, "authority": authority(),
        "pathFence": list(PATH_FENCE), "pathFenceCount": 14, "existingPathCount": 0, "newPathCount": 14,
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
        "artifacts": rows, "artifactSetDigest": sha256_value(rows),
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "statusFlags": FLAGS,
    }))
    return rendered
