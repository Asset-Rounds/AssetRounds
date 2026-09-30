#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C33."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C33"
TITLE = "Bounded temporal evidence clips, time-coded anchors, derivatives, retention, and recovery"
REGISTER_ORDINAL = 72
BASE_HEAD = "f1cb4b2d99e77f248b89830c02ba680312082b6b"
BASE_TREE = "f5c1497f5962805e4a58b10c51b4de9d5774370d"
COORDINATION_HEAD = "37ed1b7ea5bd5787a95d7347834b03838e43a9bf"
COORDINATION_TREE = "6f807016aef2b46baf4bb918bb9eb6ef9c7af300"
COORDINATION_CAS_SEQUENCE = 306
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "c09d765e5b57be9358248775060e9f5d5735dbc76523425b8f787bdf330d747c"
CONTEXT_DIGEST = "c2f402e56453950280e15c1cbdfad3693caeed300d473e6785d04aa1a8264c87"
FENCE_DIGEST = "1e194c984c3d445b719905a18a02333b0d604a7646b9b3f9d1bcfde58c254794"
HYDRATION_TRANSITION_DIGEST = "64ec1ed6a29a39a0d159f11dd93f4eb1e482654db78a663f396a168145d200ac"
COORDINATION_LEDGER_DIGEST = "498dcd45c1a85a9647b3dd1d27290f460454e45636a3b7a1f0fbf2c8bd371e7d"
COORDINATION_PROJECTION_DIGEST = "64f4601a5d5def5404fc4e6a3c589ec6aa29ee478ea2c99714acce2a71bb41b1"
AUTHORIZED_OVERLAP_COUNT = 2959
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/temporal-evidence.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C33TemporalEvidenceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C33TemporalEvidenceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C33BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C33-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c33_contracts.py",
    "Scripts/v23/generate_p03_c33_contracts.py",
    "Scripts/v23/verify_p03_c33_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c32_contracts as _c32

EXISTING_PATHS = tuple(_c32.EXISTING_PATHS) + tuple(_c32.NEW_PATHS[:6])
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Content/TemporalEvidenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/TemporalEvidencePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Content/TemporalEvidenceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Media/TemporalEvidenceLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_49TemporalEvidenceClipTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/TemporalEvidence/V22P03C33TemporalEvidenceCorpusV1.json",
    *SCRIPT_PATHS,
    *GENERATED_PATHS,
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CORE_CONTRACT_NAMES = (
    "TemporalEvidenceMediaLimitV1",
    "TemporalEvidenceLimitProfileV1",
    "TemporalEvidenceTargetV1",
    "TemporalEvidenceMediaFactsV1",
    "TemporalEvidenceClipV1",
    "TimecodedEvidenceAnchorV1",
    "TemporalEvidenceDerivativeV1",
    "TemporalEvidenceRetentionEventV1",
    "TemporalEvidenceCanonicalCodecV1",
    "TemporalEvidencePersistenceEnrollmentV1",
)
APPLICATION_CONTRACT_NAMES = (
    "TemporalEvidenceAdmissionSnapshotV1",
    "TemporalEvidenceCanonicalWorkspaceWritingV1",
    "TemporalEvidenceAcceptanceRequestV1",
    "TemporalEvidenceAcceptanceReceiptV1",
    "TemporalEvidenceCoordinatorV1",
)
CONTRACT_NAMES = CORE_CONTRACT_NAMES + APPLICATION_CONTRACT_NAMES
TEST_METHODS = (
    "testV23P03C33G01ReviewedClipPromotesImmutableContentAndOneCanonicalMutation",
    "testV23P03C33A01TypedLimitsAnchorsAndReplaceableDerivativesRemainBounded",
    "testV23P03C33H01InvalidMediaStaleAuthorityAndHostileRuntimeStatesFailClosed",
    "testV23P03C33I01EveryWriterBoundaryRecoversZeroOrCompleteWithoutOrphans",
    "testV23P03C33R01BackupRestoreReplayDeleteEraseAndRetentionRemainExact",
)
FLAGS = {key: False for key in (
    "native", "hosted", "adoption", "acceptance", "release", "nativeAcceptance",
    "hostedAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness",
    "phase10PollingDuringParallelExecution",
)}


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
        raise ValueError(f"C33 stable source absent:{path}")
    return target.read_text(encoding="utf-8")


def _tokens(root: Path, path: str, *tokens: str) -> str:
    text = _text(root, path)
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"C33 source regression:{path}:" + ",".join(missing))
    return text


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / NEW_PATHS[4]
    if not path.is_file():
        return ()
    return tuple(re.findall(r"\bfunc\s+(testV23P03C33(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8")))


def persistence_snapshot(root: Path) -> dict[str, Any]:
    core = _tokens(root, NEW_PATHS[0], "persistentSchemaVersion=33", "recordsSchemaVersion=32", "durableModelCount=2")
    models = _text(root, NEW_PATHS[1])
    families = re.findall(r"@Model\s+final\s+class\s+(\w+)", models)
    if families != ["TemporalEvidenceClipRow", "TimecodedEvidenceAnchorRow"] or "persistentFamilies" not in core:
        raise ValueError("C33 durable family declarations differ")
    return {
        "schemaRelease": "TEMPORAL_EVIDENCE_V1",
        "persistentSchemaVersion": 33,
        "recordsSchemaVersion": 32,
        "durableFamilyCount": len(families),
        "persistedFamilies": families,
        "nonpersistentFamilies": ["TemporalEvidenceCaptureScratchV1", "TemporalEvidenceDerivativeScratchV1"],
        "mode": "NEW_SCHEMA_VERSION",
        "migrationRequired": True, "backupRestoreRequired": True, "cloneForkRequired": True,
        "deleteEraseRequired": True, "exportReportRequired": True, "searchRebuildRequired": True,
        "replayRequired": True, "interruptionRecoveryRequired": True,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V33_WRITE",
    }


def require_source_ready(root: Path) -> None:
    missing = [path for path in NEW_PATHS[:6] if not (root / path).is_file()]
    if missing:
        raise ValueError("C33 stable source absent:" + ",".join(missing))
    selectors = observed_selectors(root)
    if len(selectors) != 5 or set(selectors) != set(TEST_METHODS):
        raise ValueError("C33 exact G/A/H/I/R selectors differ")
    persistence_snapshot(root)


def assert_source_regressions(root: Path) -> None:
    require_source_ready(root)
    core = _tokens(root, NEW_PATHS[0], *CORE_CONTRACT_NAMES, "ContentReferenceV1", "immutableOriginal", "offsetMilliseconds", "clipRevision", "clipSHA256")
    for token in ("maximumDurationMilliseconds", "maximumByteCount", "minimumFreeByteCount", "maximumClipsPerRequirement", "maximumClipsPerSession"):
        if token not in core:
            raise ValueError("C33 bounded capture profile regressed:" + token)
    if re.search(r"\b(?:URLSession|NWConnection|runtimeProvider|automaticTranscription|automaticRedaction)\b", core):
        raise ValueError("C33 forbidden runtime provider/network/automatic transform detected")
    models = _text(root, NEW_PATHS[1])
    if "CaptureScratch" in models:
        raise ValueError("C33 scratch became persistent")
    coordinator = _tokens(root, NEW_PATHS[2], *APPLICATION_CONTRACT_NAMES, "expectedRevision", "mutationID", "accept", "review", "temporalEvidenceReceipt")
    if "commitTemporalEvidence" not in coordinator:
        raise ValueError("C33 canonical writer route absent")
    _tokens(root, NEW_PATHS[3], "TemporalEvidenceScratchLifecycleAdapterV1", "TemporalEvidenceExistingContentPromotionAdapterV1", "recoverAfterInterruption", "persistImmutableOriginal")
    _tokens(root, NEW_PATHS[0], "TemporalEvidenceRetentionEventV1", "removeRegenerableDerivatives", "deleteClip", "eraseWorkspace")
    _tokens(root, "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift", "V33BackupTemporalEvidenceRecordV1", "TemporalEvidenceBackupMemberV1", "direct archive members")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift", "temporalEvidenceClips", "TemporalEvidenceBackupMemberV1.original")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "TemporalEvidence", "TemporalEvidenceBackupMemberV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift", "TemporalEvidence", "content")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "C33TemporalEvidencePackageValidationV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift", "PersistentSchemaV33")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift", "TemporalEvidencePersistentKindPolicyV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift", "TemporalEvidence")
    _tokens(root, "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift", "TemporalEvidenceContentReferenceBoundaryV1")
    _tokens(root, "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift", "TemporalEvidenceProvenanceBoundaryV1")
    _tokens(root, "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift", "TemporalEvidenceLocatorBoundaryV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift", "TemporalEvidenceIncrementalAdmissionEvaluatorV1", "maximumDurationMilliseconds", "maximumByteCount")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift", "TemporalEvidenceContentIntegrityV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift", "TemporalEvidenceContentContractEnrollmentV1", "secondByteStoreAllowed == false")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift", "TemporalEvidenceLegacyBundleExclusionV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift", "TemporalEvidenceCaptureRuntimeBoundaryV1", "addsMicrophoneRuntime = false", "addsVideoRecordingRuntime = false", "backgroundCaptureAllowed = false", "explicitCaptureIntentRequired = true")
    _tokens(root, "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift", "TemporalEvidenceReportLinkV1", "accessibleDescription", "embedsOriginalBytes")
    _tokens(root, "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift", "TemporalEvidenceSearchRecordV1", "TemporalEvidenceSearchProjectionPolicyV1")
    _tokens(root, "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "TemporalEvidenceLocalizationPolicyV1")
    _tokens(root, "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift", "TemporalEvidenceAccessibilityPolicyV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift", "TemporalEvidenceKernelDeletionEnrollmentV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift", "TemporalEvidenceOrphanCleanupPolicyV1")
    _tokens(root, "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift", "CheckRunnerTemporalEvidenceReviewCandidateV1")
    tests = _tokens(root, NEW_PATHS[4], *TEST_METHODS)
    for token in ("duration", "byte", "disk", "derivative", "orphan", "retention", "protectedData", "permission"):
        if token.lower() not in tests.lower():
            raise ValueError("C33 test coverage regressed:" + token)
    corpus = json.loads(_text(root, NEW_PATHS[5]))
    expected_keys = {"schema", "schemaVersion", "cardID", "persistentSchemaVersion", "recordsSchemaVersion",
                     "durableFamilies", "captureProfiles", "clipCases", "anchorCases", "derivativeCases",
                     "writerBoundaries", "hostileCases", "lifecycle", "invariants", "evidenceIDs", "statusFlags"}
    if (set(corpus) != expected_keys or corpus.get("schema") != "V22P03C33TemporalEvidenceCorpusV1"
            or corpus.get("cardID") != CARD or corpus.get("persistentSchemaVersion") != 33
            or corpus.get("recordsSchemaVersion") != 32
            or corpus.get("durableFamilies") != persistence_snapshot(root)["persistedFamilies"]
            or corpus.get("evidenceIDs") != [f"{CARD}-{x}" for x in ("G01", "A01", "H01", "I01", "R01")]
            or len(corpus.get("captureProfiles", [])) < 2 or len(corpus.get("writerBoundaries", [])) < 3
            or len(corpus.get("hostileCases", [])) < 7 or any(corpus.get("statusFlags", {}).values())):
        raise ValueError("C33 corpus authority differs")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (206, 14, 220) or len(set(PATH_FENCE)) != 220:
        raise ValueError("C33 fence must be unique 220=206+14")
    if any("s10" in path.lower() or "phase10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C33 S10 overlap")
    tree = subprocess.run(["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD], check=True, capture_output=True, text=True).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C33 base tree differs")
    for path in EXISTING_PATHS:
        if not _base_exists(root, path):
            raise ValueError(f"existing absent at base:{path}")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"new existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 2959 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C33 authority proof differs")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL, "title": TITLE,
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST, "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": 220, "existingPathCount": 206, "newPathCount": 14,
        "authorizedOverlapCount": 2959, "unauthorizedOverlapCount": 0,
        "s10ReservationOverlapCount": 0, "directPrerequisiteCards": ["V23-P03-C25"],
        "nextCard": "V23-P03-C43", "nextRegisterOrdinal": 73,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value))}


def schema_document() -> dict[str, Any]:
    profile = {
        "type": "object", "additionalProperties": False,
        "properties": {
            "profileID": {"type": "string", "minLength": 1},
            "kind": {"enum": ["AUDIO", "VIDEO"]},
            "maximumDurationMilliseconds": {"type": "integer", "minimum": 1},
            "maximumByteCount": {"type": "integer", "minimum": 1},
            "containers": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "minLength": 1}},
            "codecs": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "minLength": 1}},
            "maximumPixelWidth": {"type": ["integer", "null"], "minimum": 1},
            "maximumPixelHeight": {"type": ["integer", "null"], "minimum": 1},
            "maximumClipsPerRequirement": {"type": "integer", "minimum": 1},
            "maximumClipsPerSession": {"type": "integer", "minimum": 1},
            "minimumFreeByteCount": {"type": "integer", "minimum": 1},
            "reportProjection": {"const": "TYPED_LINK_ONLY"},
        },
        "required": ["profileID", "kind", "maximumDurationMilliseconds", "maximumByteCount", "containers", "codecs", "maximumPixelWidth", "maximumPixelHeight", "maximumClipsPerRequirement", "maximumClipsPerSession", "minimumFreeByteCount", "reportProjection"],
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/temporal-evidence.schema.json",
        "title": "V23 P03 C33 Temporal Evidence Corpus", "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C33TemporalEvidenceCorpusV1"}, "schemaVersion": {"const": 1},
            "cardID": {"const": CARD}, "persistentSchemaVersion": {"const": 33}, "recordsSchemaVersion": {"const": 32},
            "durableFamilies": {"type": "array", "minItems": 1, "uniqueItems": True, "items": {"type": "string", "minLength": 1}},
            "captureProfiles": {"type": "array", "minItems": 2, "items": profile},
            "clipCases": {"type": "array", "minItems": 2, "items": {"type": "object", "additionalProperties": False, "properties": {
                "id": {"type": "string", "minLength": 1}, "kind": {"enum": ["AUDIO", "VIDEO"]},
                "review": {"const": "EXPLICIT"}, "originalDisposition": {"const": "IMMUTABLE_CONTENT_REFERENCE"},
                "canonicalMutationCount": {"const": 1},
            }, "required": ["id", "kind", "review", "originalDisposition", "canonicalMutationCount"]}},
            "anchorCases": {"type": "array", "minItems": 1, "items": {"type": "object", "additionalProperties": False, "properties": {
                "id": {"type": "string", "minLength": 1}, "offsetMilliseconds": {"type": "integer", "minimum": 0},
                "sourceBinding": {"const": "EXACT_CLIP_REVISION_AND_ORIGINAL_DIGEST"},
            }, "required": ["id", "offsetMilliseconds", "sourceBinding"]}},
            "derivativeCases": {"type": "array", "minItems": 1, "items": {"type": "object", "additionalProperties": False, "properties": {
                "kind": {"enum": ["WAVEFORM", "THUMBNAIL"]}, "sourceKind": {"enum": ["AUDIO", "VIDEO"]},
                "replacement": {"const": "REGENERABLE_WITHOUT_ORIGINAL_REWRITE"},
            }, "required": ["kind", "sourceKind", "replacement"]}},
            "writerBoundaries": {"type": "array", "minItems": 3, "uniqueItems": True, "items": {"type": "string", "minLength": 1}},
            "hostileCases": {"type": "array", "minItems": 7, "uniqueItems": True, "items": {"type": "string", "minLength": 1}},
            "lifecycle": {"type": "object", "additionalProperties": False, "properties": {
                "contentBytesArchive": {"const": "DIRECT_WITH_METADATA"}, "retry": {"const": "SAME_EFFECT_AND_RECEIPT_OR_NO_EFFECT"},
                "scratch": {"const": "DELETE_ON_CANCEL_CRASH_PERMISSION_LOSS_OR_DISK_PRESSURE"},
                "retention": {"const": "POLICY_BOUND_ORIGINAL_AND_REGENERABLE_DERIVATIVE"},
                "deleteErase": {"const": "WORKSPACE_SCOPED_NO_ORPHANS"}, "runtimeProvider": {"const": "NONE"},
            }, "required": ["contentBytesArchive", "retry", "scratch", "retention", "deleteErase", "runtimeProvider"]},
            "invariants": {"type": "object", "additionalProperties": False, "properties": {
                "oneCanonicalMutationPerAcceptance": {"const": True}, "captureRequiresExplicitIntent": {"const": True},
                "noUnboundedRecording": {"const": True}, "noBackgroundSurveillance": {"const": True},
                "noSecondByteStore": {"const": True}, "noAutomaticTranscription": {"const": True},
                "noAutomaticRedaction": {"const": True}, "noRuntimeProvider": {"const": True},
            }, "required": ["oneCanonicalMutationPerAcceptance", "captureRequiresExplicitIntent", "noUnboundedRecording", "noBackgroundSurveillance", "noSecondByteStore", "noAutomaticTranscription", "noAutomaticRedaction", "noRuntimeProvider"]},
            "evidenceIDs": {"const": [f"{CARD}-{x}" for x in ("G01", "A01", "H01", "I01", "R01")]},
            "statusFlags": {"type": "object", "additionalProperties": {"const": False}},
        },
        "required": ["schema", "schemaVersion", "cardID", "persistentSchemaVersion", "recordsSchemaVersion", "durableFamilies", "captureProfiles", "clipCases", "anchorCases", "derivativeCases", "writerBoundaries", "hostileCases", "lifecycle", "invariants", "evidenceIDs", "statusFlags"],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    persistence = persistence_snapshot(root)
    return _sealed({
        "schema": "V23P03C33TemporalEvidenceContractV1", "schemaVersion": 1,
        "authority": authority(), "persistence": persistence,
        "requiredSemantics": {
            "contractNames": list(CONTRACT_NAMES), "fiveSelectors": list(observed_selectors(root)),
            "packageProfilesBoundDurationBytesCodecsResolutionCountFreeSpaceAndProjection": True,
            "originalsAreImmutableAndDerivativesReplaceable": True,
            "anchorsBindClipRelativeMonotonicTimeAuthorAndSourceRevision": True,
            "leasedScratchPromotesOnlyAfterReview": True,
            "directContentBytesArchiveRestoreWithMetadata": True,
            "oneCanonicalWriterAndEffectBeforeReceiptReplay": True,
            "reportLinksTypedMetadataAndAccessibleDescription": True,
            "retentionDeleteEraseAndOrphanCleanupAreExact": True,
            "noRuntimeProviderNetworkTranscriptionRedactionOrSecondByteStore": True,
        },
    })


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    return _sealed({
        "schema": "V23P03C33TemporalEvidenceEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "evidenceIDs": [f"{CARD}-{x}" for x in ("G01", "A01", "H01", "I01", "R01")],
        "testSelectors": list(observed_selectors(root)), "persistence": persistence_snapshot(root),
        "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]), "statusFlags": FLAGS,
    })


def brand_document() -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C33BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "nativeIPadSurface": False,
        "telemetry": False, "networkProcessing": False, "runtimeProvider": False,
        "automaticTranscription": False, "automaticRedaction": False, "statusFlags": FLAGS,
    })


def _row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    raw = rendered[path] if path in rendered else (root / path).read_bytes()
    return {"path": path, "sha256": sha256_bytes(raw), "byteCount": len(raw)}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    rendered = {SCHEMA_PATH: pretty(schema_document()), CONTRACT_PATH: pretty(contract_document(root)),
                EVIDENCE_PATH: pretty(evidence_document(root)), BRAND_PATH: pretty(brand_document())}
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(_sealed({
        "schema": "V23P03C33ToolingManifestV1", "schemaVersion": 1, "authority": authority(),
        "pathFence": list(PATH_FENCE), "pathFenceCount": 220, "existingPathCount": 206, "newPathCount": 14,
        "authorizedOverlapCount": 2959, "unauthorizedOverlapCount": 0,
        "artifacts": rows, "artifactSetDigest": sha256_value(rows), "statusFlags": FLAGS,
    }))
    return rendered
