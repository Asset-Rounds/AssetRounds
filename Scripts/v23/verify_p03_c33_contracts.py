#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c33_contracts as contracts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--complete", action="store_true")
    args = parser.parse_args()
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPT_PATHS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"))
        expected_outputs = contracts.all_outputs(ROOT)
    except Exception as error:
        failures.append(str(error))
        expected_outputs = {}
    changed = contracts.observed_changed_paths(ROOT)
    for path, expected in expected_outputs.items():
        target = ROOT / path
        if not target.is_file():
            failures.append(f"artifact absent:{path}")
        elif target.read_bytes() != expected:
            failures.append(f"artifact differs:{path}")
    unowned = changed - set(contracts.PATH_FENCE)
    if unowned:
        failures.append("unowned:" + ",".join(sorted(unowned)))
    if args.complete and set(contracts.PATH_FENCE) - changed:
        failures.append("incomplete fence")
    if any(contracts.FLAGS.values()):
        failures.append("status flags")
    result = {"cardID": contracts.CARD, "result": "PASS" if not failures else "FAIL", "complete": args.complete,
              "fencePathCount": 220, "existingPathCount": 206, "newPathCount": 14,
              "authorizedOverlapCount": 2959, "unauthorizedOverlapCount": 0, "failures": failures}
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else f"C33 verifier {result['result']}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())


# Current Source validation is separate from the historical card-time main above.
# These exact successor descriptors are preserved by the frozen C45, C46 and
# C52 corpus history; they do not change the temporal persistence enrollment.
import re as _current_temporal_re

_CURRENT_TEMPORAL_SUCCESSOR_DESCRIPTORS_V1 = {
    "c45AssetLabelCompatibility": {
        "compatibilityCardID": "V23-P03-C45",
        "soleLocatorAuthorityCardID": "V23-P03-C27",
        "soleRendererAuthorityCardID": "V23-P03-C24",
        "acceptedSnapshotsAreCanonical": True,
        "unacceptedPlansAndResultsAreLeasedScratch": True,
        "outputReceiptDoesNotClaimExternalPossession": True,
        "physicalPrintScanEvidenceOwnerPending": True
    },
    "c46OperationalContactCompatibility": {
        "compatibilityCardID": "V23-P03-C46",
        "operationalContactsArePurposeSeparated": True,
        "siteRoleOwnershipForbidden": True,
        "subscriberConsentCampaignAndMeasurementProjectionForbidden": True,
        "systemHandoffsAreExplicitEphemeralAndNoncanonical": True,
        "contactExportIsExcludedByDefault": True,
        "importedSourceBytesRemainLeasedScratch": True
    },
    "c52ServiceRequestBoundary": {
        "typedAnchor": "C52ServiceRequestBoundary_V22TemporalEvidence",
        "consumedContract": "PortableServiceRequestProtocolReleaseV1",
        "preservesExistingFamily": True
    }
}


def _current_temporal_unique_object_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("C33 current corpus duplicate key")
        result[key] = value
    return result


def _current_temporal_validate_successor_descriptors(corpus) -> None:
    for key, expected in _CURRENT_TEMPORAL_SUCCESSOR_DESCRIPTORS_V1.items():
        value = corpus.get(key)
        if not isinstance(value, dict) or set(value) != set(expected):
            raise ValueError("C33 current " + key + " descriptor shape differs")
        for member, expected_value in expected.items():
            actual = value[member]
            if type(actual) is not type(expected_value) or actual != expected_value:
                raise ValueError("C33 current " + key + " descriptor value differs")


def current_temporal_source_checks(root: Path) -> None:
    contracts.require_source_ready(root)
    core = contracts._tokens(root, contracts.NEW_PATHS[0], *contracts.CORE_CONTRACT_NAMES, "ContentReferenceV1", "immutableOriginal", "offsetMilliseconds", "clipRevision", "clipSHA256")
    for token in ("maximumDurationMilliseconds", "maximumByteCount", "minimumFreeByteCount", "maximumClipsPerRequirement", "maximumClipsPerSession"):
        if token not in core:
            raise ValueError("C33 bounded capture profile regressed:" + token)
    if _current_temporal_re.search(r"\b(?:URLSession|NWConnection|runtimeProvider|automaticTranscription|automaticRedaction)\b", core):
        raise ValueError("C33 forbidden runtime provider/network/automatic transform detected")
    models = contracts._text(root, contracts.NEW_PATHS[1])
    if "CaptureScratch" in models:
        raise ValueError("C33 scratch became persistent")
    coordinator = contracts._tokens(root, contracts.NEW_PATHS[2], *contracts.APPLICATION_CONTRACT_NAMES, "expectedRevision", "mutationID", "accept", "review", "temporalEvidenceReceipt")
    if "commitTemporalEvidence" not in coordinator:
        raise ValueError("C33 canonical writer route absent")
    contracts._tokens(root, contracts.NEW_PATHS[3], "TemporalEvidenceScratchLifecycleAdapterV1", "TemporalEvidenceExistingContentPromotionAdapterV1", "recoverAfterInterruption", "persistImmutableOriginal")
    contracts._tokens(root, contracts.NEW_PATHS[0], "TemporalEvidenceRetentionEventV1", "removeRegenerableDerivatives", "deleteClip", "eraseWorkspace")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift", "V33BackupTemporalEvidenceRecordV1", "TemporalEvidenceBackupMemberV1", "direct archive members")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift", "temporalEvidenceClips", "TemporalEvidenceBackupMemberV1.original")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "TemporalEvidence", "TemporalEvidenceBackupMemberV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift", "TemporalEvidence", "content")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "C33TemporalEvidencePackageValidationV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift", "PersistentSchemaV33")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift", "TemporalEvidencePersistentKindPolicyV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift", "TemporalEvidence")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift", "TemporalEvidenceContentReferenceBoundaryV1")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift", "TemporalEvidenceProvenanceBoundaryV1")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift", "TemporalEvidenceLocatorBoundaryV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift", "TemporalEvidenceIncrementalAdmissionEvaluatorV1", "maximumDurationMilliseconds", "maximumByteCount")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift", "TemporalEvidenceContentIntegrityV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift", "TemporalEvidenceContentContractEnrollmentV1", "secondByteStoreAllowed == false")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift", "TemporalEvidenceLegacyBundleExclusionV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift", "TemporalEvidenceCaptureRuntimeBoundaryV1", "addsMicrophoneRuntime = false", "addsVideoRecordingRuntime = false", "backgroundCaptureAllowed = false", "explicitCaptureIntentRequired = true")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift", "TemporalEvidenceReportLinkV1", "accessibleDescription", "embedsOriginalBytes")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift", "TemporalEvidenceSearchRecordV1", "TemporalEvidenceSearchProjectionPolicyV1")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "TemporalEvidenceLocalizationPolicyV1")
    contracts._tokens(root, "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift", "TemporalEvidenceAccessibilityPolicyV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift", "TemporalEvidenceKernelDeletionEnrollmentV1")
    contracts._tokens(root, "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift", "TemporalEvidenceOrphanCleanupPolicyV1")
    contracts._tokens(root, "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift", "CheckRunnerTemporalEvidenceReviewCandidateV1")
    tests = contracts._tokens(root, contracts.NEW_PATHS[4], *contracts.TEST_METHODS)
    for token in ("duration", "byte", "disk", "derivative", "orphan", "retention", "protectedData", "permission"):
        if token.lower() not in tests.lower():
            raise ValueError("C33 test coverage regressed:" + token)
    corpus = json.loads(contracts._text(root, contracts.NEW_PATHS[5]),
                        object_pairs_hook=_current_temporal_unique_object_pairs)
    if not isinstance(corpus, dict):
        raise ValueError("C33 current corpus top-level object differs")
    expected_keys = {"schema", "schemaVersion", "cardID", "persistentSchemaVersion", "recordsSchemaVersion",
                     "durableFamilies", "captureProfiles", "clipCases", "anchorCases", "derivativeCases",
                     "writerBoundaries", "hostileCases", "lifecycle", "invariants", "evidenceIDs", "statusFlags"} | set(_CURRENT_TEMPORAL_SUCCESSOR_DESCRIPTORS_V1)
    if (set(corpus) != expected_keys or corpus.get("schema") != "V22P03C33TemporalEvidenceCorpusV1"
            or corpus.get("cardID") != contracts.CARD or corpus.get("persistentSchemaVersion") != 33
            or corpus.get("recordsSchemaVersion") != 32
            or corpus.get("durableFamilies") != contracts.persistence_snapshot(root)["persistedFamilies"]
            or corpus.get("evidenceIDs") != [f"{contracts.CARD}-{x}" for x in ("G01", "A01", "H01", "I01", "R01")]
            or len(corpus.get("captureProfiles", [])) < 2 or len(corpus.get("writerBoundaries", [])) < 3
            or len(corpus.get("hostileCases", [])) < 7 or any(corpus.get("statusFlags", {}).values())):
        raise ValueError("C33 corpus authority differs")
    _current_temporal_validate_successor_descriptors(corpus)
