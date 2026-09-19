#!/usr/bin/env python3
"""Native-route protocol tests using disposable facts, never native PASS evidence."""
import copy
import base64
import hashlib
import os
import subprocess
import time
import importlib.util
import json
import re
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("native_ci", ROOT / "Scripts/v23-native-ci.py")
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)
HEAD = "1" * 40
UDID = "00000000-0000-0000-0000-000000000001"
UNIT = "FieldEvidenceAppTests/NativeFixtureTests/testActualMethod"
UI = "FieldEvidenceAppUITests/NativeJourneyTests/testContinuousJourney"


def selection(tier="N8"):
    return {"schemaVersion": 1, "taskID": CI.TASK, "tier": tier, "runUISmoke": tier != "N8",
            **dict(zip(CI.BUDGET_KEYS, CI.TIERS[tier])), "unitTestSelectors": [UNIT],
            "uiTestSelectors": [] if tier == "N8" else [UI]}


def environment(provider="github", tier="N8"):
    lane = next(name for name, binding in CI.LANES.items() if binding[0] == provider)
    return {
        "GITHUB_REPOSITORY": CI.REPOSITORY, "GITHUB_REF": sorted(CI.REFS)[0],
        "GITHUB_SHA": HEAD, "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1",
        "GITHUB_EVENT_NAME": "workflow_dispatch", "SHARED_LANE": lane,
        "SHARED_SHARD": "none", "SHARED_SEGMENT": "none", "SMOKE_ID": "none",
        "SHARED_SOURCE_RUN": "", "SHARED_SOURCE_MAP": "", "SHARED_UI": str(tier != "N8").lower(),
        "CI_NATIVE_ACCEPTANCE_CONTRACT": CI.CONTRACT, "CI_RUNNER_PROVIDER": provider,
        "CI_RUNNER_LABEL": CI.LANES[lane][1], "DISPATCH_RUN_UI_SMOKE": str(tier != "N8").lower(),
        "DISPATCH_NATIVE_SELECTION_ID": CI.DEFAULT_SELECTION_ID,
        "DISPATCH_NATIVE_SELECTION_SHA256": CI.sha256(CI.canonical(selection(tier))),
        "DISPATCH_NATIVE_SELECTION_MAP_SHA256": "",
        "DISPATCH_S10_4_SHARD_ID": "none", "DISPATCH_S10_4_SEGMENT_ID": "none",
        "DISPATCH_S10_4_EXECUTION_ROLE": "independent", "DISPATCH_S10_4_PILOT_MODE": "false",
        "DISPATCH_S10_4_UNIT_ONLY": "false", "DISPATCH_S10_4_PAYLOAD_ARTIFACT_NAME": "",
        "DISPATCH_S10_4_DIAGNOSTIC_PROBE_ID": "none",
        "DISPATCH_S10_4_DIAGNOSTIC_EXECUTION_LANE": "none", "CI_S10_4_SHARED_BUILD_MODE": "none",
        "CI_S10_4_SHARED_PAYLOAD_RUN_ID": "", "WORKER_S10_4_MINIMUM_SEGMENT_ID": "none",
        "WORKER_S10_4_SHARED_MATRIX_ID": "", "WORKER_S10_4_MINIMUM_CORE_SMOKE_ID": "none",
        "WORKER_S10_4_SEGMENT_SOURCE_RUN_IDS": "", "NATIVE_PRIOR_JOB_STATUS": "success",
        "CI_NATIVE_CREATED_SIMULATOR_UDID": UDID,
    }


def native_tree(method=UNIT, ui=False):
    bundle = "FieldEvidenceAppUITests" if ui else "FieldEvidenceAppTests"
    return {"testNodes": [{"nodeType": "Test Plan", "children": [
        {"nodeType": "UI test bundle" if ui else "Unit test bundle", "name": bundle, "children": [
            {"nodeType": "Test Suite", "children": [
                {"nodeType": "Test Case", "nodeIdentifier": method[len(bundle) + 1:] + "()",
                 "result": "Passed"}]}]}]}]}


def leaf(tree):
    return tree["testNodes"][0]["children"][0]["children"][0]["children"][0]


def step(source, name):
    marker = "      - name: " + name + "\n"
    if source.count(marker) != 1:
        raise AssertionError("expected one source step: " + name)
    return source.split(marker, 1)[1].split("\n      - name:", 1)[0]


def diagnostic_line(base_kind="database", **changes):
    backup, directory = CI.OWNED_FILE_DISPOSITIONS[base_kind]
    values = {
        "policyID": CI.SIMULATOR_DIAGNOSTIC_POLICY_ID,
        "disposition": CI.SIMULATOR_DIAGNOSTIC_DISPOSITION,
        "kind": base_kind,
        "request": "complete",
        "capabilityBefore": "false",
        "capabilityAfter": "false",
        "urlProtection": CI.SIMULATOR_FALLBACK_PROTECTION,
        "backupExcluded": str(backup).lower(),
        "expectsDirectory": str(directory).lower(),
        "identityUnchanged": "true",
    }
    values.update(changes)
    return CI.SIMULATOR_DIAGNOSTIC_PREFIX + " " + " ".join(
        key + "=" + values[key] for key in CI.SIMULATOR_DIAGNOSTIC_FIELDS) + "\n"


def diagnostic_frame(stream_id, sequence, payload):
    raw = payload.encode("utf-8") if isinstance(payload, str) else payload
    return (json.dumps({
        "schema": CI.SIMULATOR_DIAGNOSTIC_FRAME_SCHEMA,
        "streamID": stream_id,
        "sequence": sequence,
        "payloadBase64": base64.b64encode(raw).decode("ascii"),
        "payloadByteCount": len(raw),
        "payloadSHA256": CI.sha256(raw),
    }, separators=(",", ":")) + "\n").encode()


def diagnostic_transport(artifact, streams=(), status=None, **changes):
    simulator = artifact / "simulator-selection.txt"
    if not simulator.exists():
        simulator.write_text(
            "runtime=iOS 26.2\nruntime_build=23C54\nname=iPhone 17\n"
            f"udid={UDID}\ninitial_state=Shutdown\n")
    directory = artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY
    files = []
    if streams:
        directory.mkdir()
    for stream_id, payloads in streams:
        raw = b"".join(diagnostic_frame(stream_id, index, payload)
                       for index, payload in enumerate(payloads, 1))
        name = stream_id + ".jsonl"
        (directory / name).write_bytes(raw)
        files.append({"name": name, "bytes": len(raw), "sha256": CI.sha256(raw)})
    files.sort(key=lambda value: value["name"])
    value = {
        "schema": CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA,
        "status": status or ("AVAILABLE" if files else "ZERO_USE"),
        "simulatorUDID": UDID,
        "appBundleID": CI.SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID,
        "appRelativeDirectory": CI.SIMULATOR_DIAGNOSTIC_APP_DIRECTORY,
        "sourcePath": CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH,
        "sourceSHA256": CI.SIMULATOR_DIAGNOSTIC_SOURCE_SHA256,
        "files": files,
        "fileCount": len(files),
        "totalBytes": sum(item["bytes"] for item in files),
        "inventorySHA256": CI.sha256(CI.canonical(files)),
        "collectionBoundSeconds": 3,
    }
    value.update(changes)
    (artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS).write_bytes(CI.canonical(value))
    return value


def rebind_diagnostic_transport(artifact, status="AVAILABLE", **changes):
    directory = artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY
    files = []
    if directory.exists():
        for path in sorted(directory.iterdir(), key=lambda value: value.name):
            if path.is_file() and not path.is_symlink():
                raw = path.read_bytes()
                files.append({"name": path.name, "bytes": len(raw), "sha256": CI.sha256(raw)})
    value = CI.read_json(artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS)
    value.update({"status": status, "files": files, "fileCount": len(files),
                  "totalBytes": sum(item["bytes"] for item in files),
                  "inventorySHA256": CI.sha256(CI.canonical(files)), **changes})
    (artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS).write_bytes(CI.canonical(value))
    return value



# Exact inverse used only by historical admission checks. Actual partition checks
# below read the committed candidates directly through CI.read_json.
REPORT_PARTITION_ALIASES = {'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginWriterTests/testFrozenBeginWriterCommitsOriginalTimeAndReplaysWithoutEffects': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testFrozenBeginWriterCommitsOriginalTimeAndReplaysWithoutEffects', 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginWriterTests/testFrozenBeginWriterRecoversSavedTimeZoneBeforeRecheckDraft': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testFrozenBeginWriterRecoversSavedTimeZoneBeforeRecheckDraft', 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginWriterTests/testFrozenBeginWriterRejectsReceiptBodyTimeAndRevisionChangesWithoutQuarantine': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testFrozenBeginWriterRejectsReceiptBodyTimeAndRevisionChangesWithoutQuarantine', 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginWriterTests/testFrozenBeginWriterUsesFreshWorkspaceCASButRejectsStaleTarget': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testFrozenBeginWriterUsesFreshWorkspaceCASButRejectsStaleTarget', 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginWriterTests/testFrozenBeginWriterRejectsMissingOrChangedTimeZoneProofBeforeDraft': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testFrozenBeginWriterRejectsMissingOrChangedTimeZoneProofBeforeDraft', 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginWriterTests/testFrozenBeginWriterRejectsDirtyAndRetiredSessionsWithoutEffects': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testFrozenBeginWriterRejectsDirtyAndRetiredSessionsWithoutEffects', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginPersistsRawParentWithoutWorkflowOrBeginEffects': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginPersistsRawParentWithoutWorkflowOrBeginEffects', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginPersistsPreparedBeforeTargetsAndBindsCheck': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginPersistsPreparedBeforeTargetsAndBindsCheck', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRecoversSavedTimeZoneBeforeRecheck': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginRecoversSavedTimeZoneBeforeRecheck', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRecoversWorkflowAndBoundAcknowledgementLoss': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginRecoversWorkflowAndBoundAcknowledgementLoss', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRejectsSourceAdvanceBeforeEitherTargetEffect': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginRejectsSourceAdvanceBeforeEitherTargetEffect', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRejectsChangedCommandAndForeignWorkflowWithoutEffects': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginRejectsChangedCommandAndForeignWorkflowWithoutEffects', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRejectsChangedSiteAndInitialPostimage': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginRejectsChangedSiteAndInitialPostimage', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginColdReopenReusesPreparedAttemptAndOriginalReceipts': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginColdReopenReusesPreparedAttemptAndOriginalReceipts', 'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginUsesOriginalCreationReceiptForContinuationAccess': 'FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/testDurableInitialBeginUsesOriginalCreationReceiptForContinuationAccess'}
REPORT_PARTITION_GROUPS = [{'id': 'c36-checkrunner-foundations', 'classes': ['V23CheckRunnerEditableFieldValuesTests', 'V23CheckRunnerBeginHistoryTests'], 'methodCount': 14}, {'id': 'c36-frozen-begin-preparation', 'classes': ['V23CheckRunnerFrozenBeginPreparationTests'], 'methodCount': 6}, {'id': 'c36-frozen-begin-writer', 'classes': ['V23CheckRunnerFrozenBeginWriterTests'], 'methodCount': 6}, {'id': 'c36-durable-begin', 'classes': ['V23CheckRunnerDurableInitialBeginTests'], 'methodCount': 9}, {'id': 'c36-field-contracts', 'classes': ['V23CheckRunnerItemFieldContractsTests'], 'methodCount': 49}]
DURABLE_PARTITION_CHOICES = ['c36-durable-begin-lifecycle', 'c36-durable-begin-guards']
SOURCE_GRAPH_PARTITION_CHOICES = ['c36-source-graph-regular', 'c36-source-graph-compact-maximum', 'c36-source-graph-complete-maximum']
PREPARTITION_REPORT = {'id': 'report-camera-recovery', 'classes': ['S3_6CameraRecoveryTests', 'S4_5CorrectionTests', 'S6_2BackupExportTests', 'V9_18PackLifecycleIntegrationTests', 'V23CheckRunnerEditableFieldValuesTests', 'V23CheckRunnerBeginHistoryTests', 'V23CheckRunnerFrozenBeginPreparationTests', 'V23CheckRunnerItemFieldContractsTests'], 'methodCount': 110}
RAW_PHOTO_POOL_SHA256 = '62673E1257EE72462439FA8770F3D3CFB50ED2FB06F0674C7C9E8D5FE2FDBEBB'
RAW_PHOTO_MAP_SHA256 = '77E605D5BE168687CC9EB81C4F695806C6A6E2FCD619411C64AA7E251676CEAC'

PAIR_STARTUP_POOL_SHA256 = '62F78130A529F9BDAE378F9A9A152E32E178CC5F132BEC1FDEF37D2CAAAAE722'
PAIR_STARTUP_MAP_SHA256 = '70D3F3C4C034D82397564BA554425A2FFB93E51A345B1075CBD72F82610FF110'
PHOTO_BACKUP_PARTITION_CHOICES = ['c36-photo-backup-transport', 'c36-photo-backup-restore']


EXPECTED_PARENT_FINALIZATION_PARTITIONS = [['c36-parent-finalization-check-no-issue', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckNoIssueUsesOriginalFiveSagaHistory'], ['c36-parent-finalization-check-visible-issue', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckVisibleIssueUsesOriginalFiveSagaHistory'], ['c36-parent-finalization-check-could-not-verify', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckCouldNotVerifyUsesOriginalFiveSagaHistory'], ['c36-parent-finalization-recheck-resolved', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckResolvedUsesOriginalFiveSagaHistory'], ['c36-parent-finalization-recheck-still-visible', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckStillVisibleUsesOriginalFiveSagaHistory'], ['c36-parent-finalization-recheck-different-issue', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckDifferentIssueUsesOriginalFiveSagaHistory'], ['c36-parent-finalization-recheck-could-not-verify', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckCouldNotVerifyUsesOriginalFiveSagaHistory']]

EXPECTED_DESTINATION_SELECTORS = [
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testIterativeLineageComposesFortyHopsAcrossRepeatedWorkspacesWithoutPayloadGrowth",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testLineageBindsLaterCheckpointPrefixAndRejectsBranchPayloadDriftAndUnreviewedActivation",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testLineageRejectsRehashedPredecessorClaimsAndCannotReuseValidationForDifferentHistory",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testForeignLiveLineageReadPreservesAllOriginalsAndDeniesDirtyAncestorQuarantineAndRetirement",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testFirstCreateReceiptAuthenticatesRetainedSourceAndPreservesOriginalBytes",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testSelfConsistentCreateReceiptCannotAuthenticateChangedMappingOrGeneration",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testForeignLiveReviewReadDeniesTamperQuarantineDirtyAndRetiredReadersWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testFirstReviewDerivesCompleteReplacementAndForkRelationsWithoutChangingOriginals",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testFirstReviewRetryUsesGenerationBoundFreshIdentities",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testRehashedPlausibleRelationsStillRequireExactSourceCoverage",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testClosedCodecRejectsUnknownTagsKeysNoncanonicalAndInitialStateSubstitutions",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testEachRetainedGraphGetsItsOwnReviewWithoutRevivingItsDisposition",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testPredecessorShapeIsClosedAndDoesNotAuthenticateAnAncestor",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testContinueUsesActualWriterReceiptAndPreservesRoundSourceAndReplay",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testRebaseRequiresAnAdvancedMappedRoundAndGrantsNoReadinessOrRoundEffect",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testDiscardBindsAbsentAndArchivedTargetsWithoutLosingHistoryOrRevivingWork",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testClosedTargetContractRejectsUnboundClaimsAndWrongRoundDigestWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testPreparedProofRejectsContextCommandAndLateRoundChangesAndCannotBeReused",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testResolutionRechecksDirtyCorruptMissingQuarantinedAndRetiredSourceWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testReplacementThenForkRetainsOriginalNamespaceAndRequiresFreshReviewReceipt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testConfirmedTerminalUsesActualAtomicReceiptForAbsentAndArchivedTargetsAndExactReplay",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testTerminalRecoveryAfterReopenReadsStoredOriginalWithoutAllocatingAnotherAttempt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testTerminalRequiresExplicitPendingDiscardAndRejectsWrongPlanTimePayloadAndKnownIDs",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testPreparedTerminalProofIsSingleUseContextBoundAndRechecksCompetingWrites",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testOwnedContentAndUnboundStageWritesDenyDiscardBeforeAnyEffect",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testTerminalAdmissionRejectsDirtyCorruptMissingQuarantinedAndRetiredHistoryWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testOriginalWriterInterruptionBoundariesRollbackOrRecoverExactlyOneTerminal",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testSeparateContinuationBindsActualResolutionAndPreservesOneSourceAcrossRereview",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testLegacyCommandBytesStayExactAndClosedBindingTamperingHasNoEffect",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testPreparedContinuationIsSingleUseContextBoundAndRechecksCurrentRoundAndReview",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testColdOriginalRecoverySurvivesArchivedRoundAndRejectsMissingSourceReceipt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testDirtyCorruptQuarantinedAndPreemptedSourceStateDeniesWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testRealWriterFaultBoundariesRollbackOrRecoverExactlyOneContinuation",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testProductionServiceRecoversBeforePreparationAndRejectsForeignOrRetiredOwners",
    "FieldEvidenceAppTests/V9_30FieldDraftResilienceTests/testReviewedTargetCarrierPreservesLegacyMyDayCanonicalResolutionBytes"
]
DESTINATION_GROUP_IDS = ['c36-destination-review', 'c36-destination-resolution', 'c36-destination-discard', 'c36-destination-continuation']

def prepartition_values(default, mapping):
    if len(default.get('unitTestSelectors', [])) == 773:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                CI.GENERATED_SELECTION_POOL_SHA256, CI.GENERATED_SELECTION_MAP_SHA256):
            raise AssertionError('changed generated destination inputs')
        if default['unitTestSelectors'][738:] != EXPECTED_DESTINATION_SELECTORS:
            raise AssertionError('changed exact destination append')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        default['unitTestSelectors'] = default['unitTestSelectors'][:738]
        if [g['id'] for g in mapping['groups'][41:]] != DESTINATION_GROUP_IDS:
            raise AssertionError('changed destination group order')
        mapping['groups'] = mapping['groups'][:41]
        for group in mapping['groups']:
            group['methodCount'] -= 1 if group['id'] == 'c36-raw-staging' else 0
    if len(default.get('unitTestSelectors', [])) == 738:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                '1F2C99A95F04D378A6FB6FB0656FC0A9A6DC6A42D711E3FDD55996F86D25D572', 'E1128081C187ABE0B9E2B69CA3998EA79EA71B4124A8BBD14942418F066F3A4E'):
            raise AssertionError('changed generated parent-finalization inputs')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        if tuple(default['unitTestSelectors'][731:]) != CI.PARENT_FINALIZATION_SELECTORS:
            raise AssertionError('changed exact parent finalization append')
        default['unitTestSelectors'] = default['unitTestSelectors'][:731]
        for group in mapping['groups']:
            group['methodCount'] -= 7 if group['id'] == 'report-camera-recovery' else 0
    if len(default.get('unitTestSelectors', [])) == 731:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                '42337B38E49081DA1D0F9265235B3787DE105C6E695123A6F2CEB560779E2878',
                '1891580B81536B16989FDB4976A4288FB548A18DA0280C5D7345A22AD2DD5E85'):
            raise AssertionError('changed generated clone-retirement inputs')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        if tuple(default['unitTestSelectors'][723:]) != CI.CLONE_RETIREMENT_SELECTORS:
            raise AssertionError('changed exact retirement append')
        default['unitTestSelectors'] = default['unitTestSelectors'][:723]
        for group in mapping['groups']:
            group['methodCount'] -= 8 if group['id'] == 'restore-acceptance' else 0
    if len(default.get('unitTestSelectors', [])) == 723:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                'C5BFBCF739DCD2BCAF77801385CD1A16C116D6AFE07F1AD02162F0AEF9030AA0',
                '955D579A27A62C179660C0F8A4A38FF4D91FB9241244BA3B0334A9AF1B0C7A6E'):
            raise AssertionError('changed generated configuration-clone inputs')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        if tuple(default['unitTestSelectors'][716:]) != CI.CONFIGURATION_CLONE_SELECTORS:
            raise AssertionError('changed exact clone append')
        default['unitTestSelectors'] = default['unitTestSelectors'][:716]
        for group in mapping['groups']:
            group['methodCount'] -= {'report-camera-recovery': 2, 'restore-acceptance': 5}.get(group['id'], 0)
    if len(mapping.get('groups', [])) == 41:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                '930A9B3C186EDD0D09F9F630A9214A0FDD95362465B8FEFFBC735D78CF83AA5D', '5BB4E7E1FA935EE74B962F4572F9384FBF5DC4E0BFA83178547D89E0A4287248'):
            raise AssertionError('changed generated photo-backup enrollment inputs')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        if tuple(default['unitTestSelectors'][-15:]) != CI.PHOTO_BACKUP_PARENT_SELECTORS:
            raise AssertionError('changed exact photo backup append')
        default['unitTestSelectors'] = default['unitTestSelectors'][:-15]
        if mapping['groups'][-1] != {'id': 'backup-capacity',
                                    'classes': ['S4_1DeterministicRendererTests'], 'methodCount': 1}:
            raise AssertionError('changed capacity group')
        mapping['groups'] = mapping['groups'][:-1]
        increments = {'report-camera-recovery': 11, 'archive-contracts': 1, 'restore-acceptance': 2}
        for group in mapping['groups']:
            group['methodCount'] -= increments.get(group['id'], 0)
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                PAIR_STARTUP_POOL_SHA256, PAIR_STARTUP_MAP_SHA256):
            raise AssertionError('changed historical701/40 output')
    if len(mapping.get('groups', [])) == 40:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                PAIR_STARTUP_POOL_SHA256, PAIR_STARTUP_MAP_SHA256):
            raise AssertionError('changed generated pair-startup enrollment inputs')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        default['unitTestSelectors'] = default['unitTestSelectors'][:-4]
        mapping['groups'] = mapping['groups'][:-1]
        owner = next(g for g in mapping['groups'] if g['id'] == 'notification-owner')
        if owner['methodCount'] != 77:
            raise AssertionError('changed startup owner count')
        owner['methodCount'] = 75
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                RAW_PHOTO_POOL_SHA256, RAW_PHOTO_MAP_SHA256):
            raise AssertionError('changed exact raw-photo reconstruction')
    if len(mapping.get('groups', [])) == 39:
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                RAW_PHOTO_POOL_SHA256, RAW_PHOTO_MAP_SHA256):
            raise AssertionError('changed generated enrollment inputs')
        default, mapping = copy.deepcopy(default), copy.deepcopy(mapping)
        default['unitTestSelectors'] = default['unitTestSelectors'][:-5]
        mapping['groups'] = mapping['groups'][:-2]
        if (CI.sha256(CI.canonical(default)), CI.sha256(CI.canonical(mapping))) != (
                CI.DURABLE_BEGIN_BASE_POOL_SHA256, CI.DURABLE_BEGIN_BASE_MAP_SHA256):
            raise AssertionError('changed exact incumbent reconstruction')
    if len(mapping.get('groups', [])) != 37:
        raise AssertionError('expected actual37 report partition')
    if mapping['groups'][32:] != REPORT_PARTITION_GROUPS:
        raise AssertionError('changed report partition groups')
    expected_aliases = set(REPORT_PARTITION_ALIASES)
    if {s for s in default['unitTestSelectors'] if s.split('/')[1] in
            ('V23CheckRunnerFrozenBeginWriterTests','V23CheckRunnerDurableInitialBeginTests')} != expected_aliases:
        raise AssertionError('changed report partition aliases')
    prior, prior_map = copy.deepcopy(default), copy.deepcopy(mapping)
    prior['unitTestSelectors'] = [REPORT_PARTITION_ALIASES.get(s,s) for s in prior['unitTestSelectors']]
    prior_map['groups'] = prior_map['groups'][:32]
    group = next(g for g in prior_map['groups'] if g['id']=='report-camera-recovery')
    if group != {'id': 'report-camera-recovery', 'classes': ['S3_6CameraRecoveryTests', 'S4_5CorrectionTests', 'S6_2BackupExportTests', 'V9_18PackLifecycleIntegrationTests'], 'methodCount': 26}:
        raise AssertionError('changed retained report group')
    group.update(copy.deepcopy(PREPARTITION_REPORT))
    if CI.sha256(CI.canonical(prior)) != '612FA6C2014FAEBA66E9479B39D15539740394964A46B1AC558BC159C9F48500' or CI.sha256(CI.canonical(prior_map)) != 'EB3636645D15460F179DAA1FE30AFA47BC110A3BB66A371FA69F488C54EFDF67':
        raise AssertionError('prepartition exact source hash differs')
    return prior, prior_map

def prepartition_read_json(path):
    prior, mapping = prepartition_values(CI.read_json(ROOT / 'Scripts/ci-selection.json'),
                                         CI.read_json(ROOT / CI.SELECTION_MAP_PATH))
    if path == ROOT / 'Scripts/ci-selection.json': return prior
    if path == ROOT / CI.SELECTION_MAP_PATH: return mapping
    raise AssertionError('foreign historical source path')

def frozen_begin_suite_source():
    return '\n'.join((ROOT / 'FieldEvidenceAppTests' / (name+'.swift')).read_text(encoding='utf-8') for name in (
        'V23CheckRunnerFrozenBeginPreparationTests','V23CheckRunnerFrozenBeginWriterTests','V23CheckRunnerDurableInitialBeginTests'))

def prepartition_workflow(workflow):
    choice = '          - ' + CI.BUILD_WATCHDOG_SELECTION_ID + '\n'
    if workflow.count(choice) != 1: raise AssertionError('missing exact build watchdog choice')
    workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 773 methods across 45 bounded groups',
                                'all 738 methods across 41 bounded groups')
    for group_id in DESTINATION_GROUP_IDS + ['c36-destination-legacy-bytes']:
        workflow = workflow.replace('          - ' + group_id + '\n', '')
    for group_id, _ in CI.PARENT_FINALIZATION_METHOD_PARTITIONS:
        choice = '          - ' + group_id + '\n'
        if workflow.count(choice) != 1: raise AssertionError('missing exact parent finalization choice')
        workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 738 methods across 41 bounded groups',
                                'all 731 methods across 41 bounded groups')
    for group_id, _ in CI.CLONE_RETIREMENT_METHOD_PARTITIONS:
        choice = '          - ' + group_id + '\n'
        if workflow.count(choice) != 1: raise AssertionError('missing exact retirement choice')
        workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 731 methods across 41 bounded groups',
                                'all 723 methods across 41 bounded groups')
    choice = '          - c36-photo-configuration-clone\n'
    if workflow.count(choice) != 1: raise AssertionError('missing exact clone choice')
    workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 723 methods across 41 bounded groups',
                                'all 716 methods across 41 bounded groups')
    for group_id in ('backup-capacity', *PHOTO_BACKUP_PARTITION_CHOICES):
        choice = '          - ' + group_id + '\n'
        if workflow.count(choice) != 1: raise AssertionError('missing exact photo backup choice')
        workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 716 methods across 41 bounded groups',
                                'all 701 methods across 40 bounded groups')
    choice = '          - c36-startup-recovery\n'
    if workflow.count(choice) != 1: raise AssertionError('missing exact startup group choice')
    workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 701 methods across 40 bounded groups',
                                'all 697 methods across 39 bounded groups')
    for group_id in ('mutation-receipt-safety', 'c36-raw-staging'):
        choice = '          - ' + group_id + '\n'
        if workflow.count(choice) != 1: raise AssertionError('missing exact generated choice')
        workflow = workflow.replace(choice, '')
    workflow = workflow.replace('all 697 methods across 39 bounded groups',
                                'all 692 methods across 37 bounded groups')
    for partition_id in SOURCE_GRAPH_PARTITION_CHOICES+DURABLE_PARTITION_CHOICES:
        choice='          - '+partition_id+'\n'
        if workflow.count(choice)!=1: raise AssertionError('missing exact durable workflow choice')
        workflow=workflow.replace(choice,'')
    for group in REPORT_PARTITION_GROUPS:
        choice='          - '+group['id']+'\n'
        if workflow.count(choice)!=1: raise AssertionError('missing exact report workflow choice')
        workflow=workflow.replace(choice,'')
    workflow=workflow.replace('all 692 methods across 37 bounded groups','all 618 methods across 32 bounded groups')
    if CI.sha256(workflow.encode()) != '2C4DF68D3A0EA8ABC3DFB72BF7197BAF83FF327DB65DA0ECA543749C42D3D14C':
        raise AssertionError('changed prepartition workflow')
    return workflow

class GeneratedSelectionAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name).resolve()
        manifest = CI.read_json(ROOT / 'Scripts/v23-selection-manifest.json')
        paths = ['Scripts/v23-selection-manifest.json', 'Scripts/v23-selection-generator.py',
                 'Scripts/ci-selection.json', CI.SELECTION_MAP_PATH]
        paths += ['FieldEvidenceAppTests/' + name + '.swift' for name in sorted({
            CI.selection_class(selector) for selector in manifest['selectorPool']})]
        for relative in paths:
            target = cls.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        cls.default = CI.read_json(cls.root / 'Scripts/ci-selection.json')
        cls.mapping = CI.read_json(cls.root / CI.SELECTION_MAP_PATH)

    def test_current_generated_profile_admits_exact_new_groups_and_binds_protocol_sources(self):
        report = CI.verify_generated_selection(self.root, self.default, self.mapping)
        self.assertEqual((report['selectorCount'], report['groupCount']), (773, 45))
        for group_id, count in [('mutation-receipt-safety', 1), ('c36-raw-staging', 5),
                                ('notification-owner', 77), ('c36-startup-recovery', 2),
                                ('backup-capacity', 1), ('c36-photo-backup-transport', 12),
                                ('c36-photo-backup-restore', 3), ('c36-photo-configuration-clone', 7)]:
            e = environment()
            e['NATIVE_SELECTION_ID'] = group_id
            selected, record = CI.selected_input(self.root, e)
            self.assertEqual(len(selected['unitTestSelectors']), count)
            self.assertEqual(record['selectionID'], group_id)
            self.assertEqual(tuple(selected[key] for key in CI.BUDGET_KEYS), CI.TIERS['N8'])
        for relative in ('Scripts/v23-selection-manifest.json', 'Scripts/v23-selection-generator.py'):
            self.assertEqual(CI.PROTOCOL_PATHS.count(relative), 1)

    def test_current_admission_rejects_manifest_output_and_source_declaration_drift(self):
        path = self.root / 'Scripts/v23-selection-manifest.json'
        original = path.read_bytes()
        changed = CI.read_json(path)
        current = next(profile for profile in changed['profiles'] if profile['id'] == CI.GENERATED_SELECTION_PROFILE)
        current['excludedGroupIDs'] = ['c36-startup-recovery']
        try:
            path.write_bytes(CI.canonical(changed))
            with self.assertRaisesRegex(ValueError, 'differs from manifest/source'):
                CI.verify_generated_selection(self.root, self.default, self.mapping)
        finally:
            path.write_bytes(original)
        hostile = copy.deepcopy(self.default)
        hostile['unitTestSelectors'][-1], hostile['unitTestSelectors'][-2] = hostile['unitTestSelectors'][-2], hostile['unitTestSelectors'][-1]
        with self.assertRaises(ValueError):
            CI.resolve_selection(hostile, self.mapping, 'c36-startup-recovery')
        source_cases = (
            ('S6_2BackupExportTests.swift',
             b'func testSixPhotoSameWorkspaceRestorePublishesCompositionAndColdRecoveryIsAtomic('),
            ('S6_3BackupValidationTests.swift',
             b'func testPhotoBackupMemberStreamingIsBoundedCancellableAndAnchored('),
            ('S6_4AtomicRestoreTests.swift',
             b'func testOwnedGenerationCleanupDoesNotApplyGenerationGrammarToImportPackages('),
            ('S4_1DeterministicRendererTests.swift',
             b'func testCapacityOverflowAndUnexpectedStageOrFinalFailClosed('),
            ('V9_30FieldDraftResilienceTests.swift',
             b'func testRestoreInitializationMatchesActorPublicationAndReopensExactBytes('),
            ('V9_15AppLockLifecycleTests.swift',
             b'func testConfigurationStartupRecoveryTokenBindsRepairOperationAndRevokes('),
            ('S3_4ResumeRecoveryTests.swift',
             b'func testMediaReconcileRemovesOrphansAndPreservesMismatchForMaintenance('),
        )
        for filename, old in source_cases:
            source = self.root / 'FieldEvidenceAppTests' / filename
            original = source.read_bytes()
            self.assertEqual(original.count(old), 1)
            try:
                source.write_bytes(original.replace(old, b'func helperNotSelected('))
                with self.subTest(filename=filename), self.assertRaisesRegex(
                        ValueError, 'missing or duplicate source method'):
                    CI.verify_generated_selection(self.root, self.default, self.mapping)
            finally:
                source.write_bytes(original)


EXPECTED_RETIREMENT_PARTITIONS = [['c36-clone-retirement-old-pointer', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementOldPointerRollbackRestoresExactIncumbent'], ['c36-clone-retirement-pointer-cleanup', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementPointerLagAndPrivateCleanupResume'], ['c36-clone-retirement-terminal-metadata', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementTerminalMetadataResumesWithoutBaseIntent'], ['c36-clone-retirement-rollback', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementRollbackInterruptionsResume'], ['c36-clone-retirement-unclaimed-binding', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementUnclaimedScaffoldAndBindingTamperFailClosed'], ['c36-clone-retirement-private-hostility', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementChangedPrivateBytesAndUnknownNodesRemainUntouched'], ['c36-clone-retirement-access-cancel', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementAccessAndCancellationRetainRecoveryOwner'], ['c36-clone-retirement-inode-substitution', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementClaimRejectsAnInodeSubstitution']]

class ReportPartitionTests(unittest.TestCase):
    def test_retirement_singletons_preserve_exact_coverage_and_budgets(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        expected = EXPECTED_RETIREMENT_PARTITIONS
        self.assertEqual([(i, list(m)) for i, m in CI.CLONE_RETIREMENT_METHOD_PARTITIONS],
                         [(i, [member]) for i, member in expected])
        observed = []
        for selection_id, member in expected:
            selected = CI.resolve_selection(default, mapping, selection_id)
            self.assertEqual(selected['unitTestSelectors'], [member])
            self.assertEqual({k: v for k, v in selected.items() if k != 'unitTestSelectors'},
                             {k: v for k, v in default.items() if k != 'unitTestSelectors'})
            bundle, klass, method = member.split('/')
            source = (ROOT / bundle / (klass + '.swift')).read_text(encoding='utf-8')
            self.assertEqual(len(re.findall(r'func\s+' + method + r'\s*\(', source)), 1)
            observed.extend(selected['unitTestSelectors'])
        self.assertEqual(observed, default['unitTestSelectors'][723:731])
        self.assertEqual(len(observed), len(set(observed)))
        self.assertFalse(set(observed) & set(default['unitTestSelectors'][:723]))

    def test_destination_family_has_exact_closed_groups_and_legacy_pair(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(default['unitTestSelectors'][738:], EXPECTED_DESTINATION_SELECTORS)
        observed = []
        for group_id, count in zip(DESTINATION_GROUP_IDS, [13, 7, 7, 7]):
            selected = CI.resolve_selection(default, mapping, group_id)
            self.assertEqual(len(selected['unitTestSelectors']), count)
            self.assertEqual({k: selected[k] for k in CI.BUDGET_KEYS},
                             {k: default[k] for k in CI.BUDGET_KEYS})
            observed.extend(selected['unitTestSelectors'])
        legacy = CI.resolve_selection(default, mapping, 'c36-destination-legacy-bytes')
        self.assertEqual(legacy['unitTestSelectors'], [EXPECTED_DESTINATION_SELECTORS[-1]])
        observed.extend(legacy['unitTestSelectors'])
        self.assertEqual(observed, EXPECTED_DESTINATION_SELECTORS)
        self.assertEqual(len(observed), len(set(observed)))
        self.assertFalse(set(observed) & set(default['unitTestSelectors'][:738]))
        for index in range(738, 773):
            missing = copy.deepcopy(default); del missing['unitTestSelectors'][index]
            duplicate = copy.deepcopy(default); duplicate['unitTestSelectors'][index] = default['unitTestSelectors'][738 if index != 738 else 739]
            foreign = copy.deepcopy(default); foreign['unitTestSelectors'][index] += 'Unknown'
            for hostile in (missing, duplicate, foreign):
                with self.subTest(index=index), self.assertRaises(ValueError):
                    CI.resolve_selection(hostile, mapping, 'c36-destination-legacy-bytes')
        reordered = copy.deepcopy(default)
        reordered['unitTestSelectors'][738:] = reversed(reordered['unitTestSelectors'][738:])
        with self.assertRaises(ValueError):
            CI.resolve_selection(reordered, mapping, 'c36-destination-review')
        overlap = copy.deepcopy(mapping)
        overlap['groups'][-1]['classes'].append(overlap['groups'][-2]['classes'][0])
        with self.assertRaises(ValueError):
            CI.resolve_selection(default, overlap, 'c36-destination-review')
        with self.assertRaisesRegex(ValueError, 'unknown selection ID'):
            CI.resolve_selection(default, mapping, 'c36-destination-unknown')

    def test_parent_finalization_singletons_have_exact_membership_and_unchanged_contract(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual([(i, list(m)) for i, m in CI.PARENT_FINALIZATION_METHOD_PARTITIONS],
                         [(i, [m]) for i, m in EXPECTED_PARENT_FINALIZATION_PARTITIONS])
        observed = []
        for selection_id, member in EXPECTED_PARENT_FINALIZATION_PARTITIONS:
            selected = CI.resolve_selection(default, mapping, selection_id)
            self.assertEqual(selected['unitTestSelectors'], [member])
            self.assertEqual({k: v for k, v in selected.items() if k != 'unitTestSelectors'},
                             {k: v for k, v in default.items() if k != 'unitTestSelectors'})
            e = environment(); e['NATIVE_SELECTION_ID'] = selection_id
            admitted, record = CI.selected_input(ROOT, e)
            self.assertEqual(admitted, selected)
            self.assertEqual(record['selectionID'], selection_id)
            self.assertEqual(tuple(selected[key] for key in CI.BUDGET_KEYS), CI.TIERS['N8'])
            observed.extend(selected['unitTestSelectors'])
        self.assertEqual(observed, default['unitTestSelectors'][731:738])
        self.assertEqual(len(observed), len(set(observed)))
        self.assertFalse(set(observed) & set(default['unitTestSelectors'][:731]))

    def test_parent_finalization_rejects_omission_duplicate_substitution_reorder_and_unknown_route(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        selected_id = EXPECTED_PARENT_FINALIZATION_PARTITIONS[0][0]
        for index in range(731, 738):
            missing = copy.deepcopy(default); missing['unitTestSelectors'].pop(index)
            duplicate = copy.deepcopy(default); duplicate['unitTestSelectors'][index] = default['unitTestSelectors'][731 if index != 731 else 732]
            substituted = copy.deepcopy(default); substituted['unitTestSelectors'][index] = default['unitTestSelectors'][0]
            foreign = copy.deepcopy(default); foreign['unitTestSelectors'][index] += 'Unknown'
            for hostile in (missing, duplicate, substituted, foreign):
                with self.subTest(index=index), self.assertRaises(ValueError):
                    CI.resolve_selection(hostile, mapping, selected_id)
        reordered = copy.deepcopy(default)
        reordered['unitTestSelectors'][731:738] = reversed(reordered['unitTestSelectors'][731:738])
        changed_budget = copy.deepcopy(default); changed_budget['testTimeoutSeconds'] += 1
        for hostile in (reordered, changed_budget):
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, selected_id)
        changed_map = copy.deepcopy(mapping)
        next(g for g in changed_map['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] -= 1
        with self.assertRaises(ValueError): CI.resolve_selection(default, changed_map, selected_id)
        with self.assertRaisesRegex(ValueError, 'unknown selection ID'):
            CI.resolve_selection(default, mapping, 'c36-parent-finalization-unknown')

    def test_retirement_denies_missing_reordered_foreign_duplicate_and_unknown_inputs(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        selected_id = EXPECTED_RETIREMENT_PARTITIONS[0][0]
        for index in range(723, 731):
            missing = copy.deepcopy(default); missing['unitTestSelectors'].pop(index)
            duplicate = copy.deepcopy(default); duplicate['unitTestSelectors'][index] = default['unitTestSelectors'][722]
            foreign = copy.deepcopy(default); foreign['unitTestSelectors'][index] += 'Unknown'
            for hostile in (missing, duplicate, foreign):
                with self.subTest(index=index), self.assertRaises(ValueError):
                    CI.resolve_selection(hostile, mapping, selected_id)
        reordered = copy.deepcopy(default)
        reordered['unitTestSelectors'][723:731] = reversed(reordered['unitTestSelectors'][723:731])
        changed_budget = copy.deepcopy(default); changed_budget['testTimeoutSeconds'] += 1
        for hostile in (reordered, changed_budget):
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, selected_id)
        changed_map = copy.deepcopy(mapping)
        next(g for g in changed_map['groups'] if g['id'] == 'restore-acceptance')['methodCount'] -= 1
        with self.assertRaises(ValueError): CI.resolve_selection(default, changed_map, selected_id)
        with self.assertRaisesRegex(ValueError, 'unknown selection ID'):
            CI.resolve_selection(default, mapping, 'c36-clone-retirement-unknown')

    def test_actual_whole_class_partition_preserves_692_methods_and_all_prior_members(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        prior, prior_map=prepartition_values(default,mapping)
        self.assertEqual(len(default['unitTestSelectors']),773)
        self.assertEqual(default['unitTestSelectors'][:677],prior['unitTestSelectors'][:677])
        seen=[]
        for group in mapping['groups']:
            actual=CI.resolve_selection(default,mapping,group['id'])
            self.assertEqual({k:actual[k] for k in CI.BUDGET_KEYS},{k:prior[k] for k in CI.BUDGET_KEYS})
            members=actual['unitTestSelectors']; seen.extend(members)
            self.assertEqual(len(members),group['methodCount'])
            for klass in (group['classes'] if group['id'] in [g['id'] for g in REPORT_PARTITION_GROUPS] else []):
                source=(ROOT / 'FieldEvidenceAppTests' / (klass+'.swift')).read_text(encoding='utf-8')
                declared=re.findall(r'^    func (test\w+)\(',source,re.M)
                self.assertEqual({s.rsplit('/',1)[1] for s in members if s.split('/')[1]==klass},set(declared))
            if group['id'] not in DESTINATION_GROUP_IDS + ['report-camera-recovery','notification-owner','mutation-receipt-safety','c36-raw-staging','c36-startup-recovery','archive-contracts','restore-acceptance','backup-capacity']+[g['id'] for g in REPORT_PARTITION_GROUPS]:
                self.assertEqual(actual,CI.resolve_selection(prior,prior_map,group['id']))
        self.assertEqual(len(seen),len(set(seen)))
        self.assertEqual(set(seen),set(default['unitTestSelectors']))
        report=[s for s in seen if s.split('/')[1] in {c for g in [mapping['groups'][13]]+REPORT_PARTITION_GROUPS for c in g['classes']}]
        self.assertEqual({REPORT_PARTITION_ALIASES.get(s,s) for s in report
                          if s not in CI.PHOTO_BACKUP_PARENT_SELECTORS + CI.CONFIGURATION_CLONE_SELECTORS + CI.PARENT_FINALIZATION_SELECTORS},
                         set(CI.resolve_selection(prior,prior_map,'report-camera-recovery')['unitTestSelectors']))
        workflow=(ROOT / '.github/workflows/ios-ci.yml').read_text(encoding='utf-8')
        prepartition_workflow(workflow)
        field=workflow.split('      native_selection_id:\n',1)[1].split('      s10_4_minimum_core_smoke_id:',1)[0]
        expected=[mapping['defaultSelectionID']]
        for group in mapping['groups']:
            expected.append(group['id'])
            if group['id']=='c36-source-graph': expected.extend(SOURCE_GRAPH_PARTITION_CHOICES)
            if group['id']=='c36-durable-begin': expected.extend(DURABLE_PARTITION_CHOICES)
            if group['id']=='backup-capacity': expected.extend(PHOTO_BACKUP_PARTITION_CHOICES + [CI.CONFIGURATION_CLONE_SELECTION_ID] + [i for i, _ in CI.CLONE_RETIREMENT_METHOD_PARTITIONS] + [i for i, _ in CI.PARENT_FINALIZATION_METHOD_PARTITIONS])
        expected.append('c36-destination-legacy-bytes')
        expected.insert(expected.index('c36-parent-finalization-check-no-issue') + 1,
                        CI.BUILD_WATCHDOG_SELECTION_ID)
        self.assertEqual([line.strip()[2:] for line in field.splitlines() if line.startswith('          - ')],expected)

    def test_photo_backup_partitions_cover_exact_append_once_and_keep_native_contract(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        seen = []
        for (partition_id, members), count in zip(CI.PHOTO_BACKUP_METHOD_PARTITIONS, (12, 3)):
            actual = CI.resolve_selection(default, mapping, partition_id)
            self.assertEqual(tuple(actual['unitTestSelectors']), members)
            self.assertEqual(len(members), count)
            self.assertEqual({k: v for k, v in actual.items() if k != 'unitTestSelectors'},
                             {k: v for k, v in default.items() if k != 'unitTestSelectors'})
            seen.extend(members)
        self.assertEqual(len(seen), len(set(seen)))
        self.assertEqual(set(seen), set(default['unitTestSelectors'][701:716]))
        self.assertEqual(tuple(default['unitTestSelectors'][701:716]), CI.PHOTO_BACKUP_PARENT_SELECTORS)
        for selector in seen:
            bundle, klass, method = selector.split('/')
            source = (ROOT / bundle / (klass + '.swift')).read_text(encoding='utf-8')
            self.assertEqual(len(re.findall(r'\bfunc\s+' + re.escape(method) + r'\s*\(', source)), 1)

    def test_photo_backup_partition_hostiles_preserve_closed_membership_order_and_limits(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        cases = []
        missing = copy.deepcopy(default); missing['unitTestSelectors'].pop(715); cases.append(missing)
        duplicate = copy.deepcopy(default); duplicate['unitTestSelectors'].append(default['unitTestSelectors'][715]); cases.append(duplicate)
        foreign = copy.deepcopy(default); foreign['unitTestSelectors'][715] += 'Unknown'; cases.append(foreign)
        reordered = copy.deepcopy(default)
        reordered['unitTestSelectors'][715], reordered['unitTestSelectors'][714] = reordered['unitTestSelectors'][714], reordered['unitTestSelectors'][715]
        cases.append(reordered)
        budget = copy.deepcopy(default); budget['testTimeoutSeconds'] = 901; cases.append(budget)
        for index, hostile in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(ValueError):
                CI.resolve_selection(hostile, mapping, PHOTO_BACKUP_PARTITION_CHOICES[0])
        wrong_map = copy.deepcopy(mapping); wrong_map['groups'][-1]['methodCount'] += 1
        with self.assertRaises(ValueError):
            CI.resolve_selection(default, wrong_map, PHOTO_BACKUP_PARTITION_CHOICES[1])
        with self.assertRaisesRegex(ValueError, 'unknown selection ID'):
            CI.resolve_selection(default, mapping, 'c36-photo-backup-unknown')

    def test_configuration_clone_selection_exact_source_members_and_unchanged_native_limits(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        selected = CI.resolve_selection(default, mapping, CI.CONFIGURATION_CLONE_SELECTION_ID)
        self.assertEqual(tuple(selected['unitTestSelectors']), CI.CONFIGURATION_CLONE_SELECTORS)
        self.assertEqual(len(selected['unitTestSelectors']), 7)
        self.assertEqual({k: v for k, v in selected.items() if k != 'unitTestSelectors'},
                         {k: v for k, v in default.items() if k != 'unitTestSelectors'})
        for selector in selected['unitTestSelectors']:
            bundle, klass, method = selector.split('/')
            source = (ROOT / bundle / (klass + '.swift')).read_text(encoding='utf-8')
            self.assertEqual(len(re.findall(r'\bfunc\s+' + re.escape(method) + r'\s*\(', source)), 1)
        self.assertFalse(set(selected['unitTestSelectors']) & set(CI.PHOTO_BACKUP_PARENT_SELECTORS))

    def test_configuration_clone_rejects_omission_duplicates_order_foreign_class_and_budget_drift(self):
        default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        cases = []
        missing = copy.deepcopy(default); missing['unitTestSelectors'].pop(); cases.append(missing)
        duplicate = copy.deepcopy(default); duplicate['unitTestSelectors'].append(default['unitTestSelectors'][-1]); cases.append(duplicate)
        foreign = copy.deepcopy(default); foreign['unitTestSelectors'][-1] += 'Unknown'; cases.append(foreign)
        reordered = copy.deepcopy(default)
        reordered['unitTestSelectors'][-1], reordered['unitTestSelectors'][-2] = reordered['unitTestSelectors'][-2], reordered['unitTestSelectors'][-1]
        cases.append(reordered)
        budget = copy.deepcopy(default); budget['testTimeoutSeconds'] = 901; cases.append(budget)
        for index, hostile in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(ValueError):
                CI.resolve_selection(hostile, mapping, CI.CONFIGURATION_CLONE_SELECTION_ID)
        wrong_map = copy.deepcopy(mapping)
        next(g for g in wrong_map['groups'] if g['id'] == 'restore-acceptance')['classes'].append('ForeignTests')
        with self.assertRaises(ValueError):
            CI.resolve_selection(default, wrong_map, CI.CONFIGURATION_CLONE_SELECTION_ID)
        with self.assertRaisesRegex(ValueError, 'unknown selection ID'):
            CI.resolve_selection(default, mapping, 'c36-photo-configuration-clone-unknown')

    def test_actual_durable_method_partitions_are_fixed_complete_and_keep_n8_budgets(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        parent=CI.resolve_selection(default,mapping,CI.DURABLE_BEGIN_PARENT_ID)
        self.assertEqual(tuple(parent['unitTestSelectors']),CI.DURABLE_BEGIN_PARENT_SELECTORS)
        seen=[]
        for partition_id,members in CI.DURABLE_BEGIN_METHOD_PARTITIONS:
            actual=CI.resolve_selection(default,mapping,partition_id)
            self.assertEqual(tuple(actual['unitTestSelectors']),members)
            self.assertEqual(tuple(actual[k] for k in CI.BUDGET_KEYS),CI.TIERS['N8'])
            seen.extend(actual['unitTestSelectors'])
        self.assertEqual(len(seen),len(set(seen)))
        self.assertEqual(set(seen),set(parent['unitTestSelectors']))
        source=(ROOT/'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests.swift').read_text(encoding='utf-8')
        declared={'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/'+name
                  for name in re.findall(r'^    func (test\w+)\(',source,re.M)}
        self.assertEqual(declared,set(CI.DURABLE_BEGIN_PARENT_SELECTORS))

    def test_durable_method_partitions_reject_missing_duplicate_foreign_reordered_and_unknown(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        parent=list(CI.DURABLE_BEGIN_PARENT_SELECTORS)
        cases=[]
        missing=copy.deepcopy(default);missing['unitTestSelectors'].remove(parent[0]);cases.append(missing)
        duplicate=copy.deepcopy(default);duplicate['unitTestSelectors'].append(parent[0]);cases.append(duplicate)
        foreign=copy.deepcopy(default);foreign['unitTestSelectors'].append(
            'FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testForeign');cases.append(foreign)
        reordered=copy.deepcopy(default)
        positions=[reordered['unitTestSelectors'].index(item) for item in parent]
        reordered['unitTestSelectors'][positions[0]],reordered['unitTestSelectors'][positions[1]]=parent[1],parent[0]
        cases.append(reordered)
        for hostile in cases:
            with self.subTest(case=cases.index(hostile)),self.assertRaises(ValueError):
                CI.resolve_selection(hostile,mapping,DURABLE_PARTITION_CHOICES[0])
        with self.assertRaisesRegex(ValueError,'unknown selection ID'):
            CI.resolve_selection(default,mapping,'c36-durable-begin-unknown')

    def test_durable_partitions_reject_budget_or_whole_map_changes(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        bad_budget=copy.deepcopy(default);bad_budget['testTimeoutSeconds']=1200
        with self.assertRaisesRegex(ValueError,'budgets'):
            CI.resolve_selection(bad_budget,mapping,DURABLE_PARTITION_CHOICES[0])
        for mutate in (lambda m:m['groups'].pop(),
                       lambda m:m['groups'].append(copy.deepcopy(m['groups'][-1])),
                       lambda m:m['groups'][32]['classes'].reverse()):
            hostile=copy.deepcopy(mapping);mutate(hostile)
            with self.subTest(mutate=mutate),self.assertRaises(ValueError):
                CI.resolve_selection(default,hostile,DURABLE_PARTITION_CHOICES[1])

    def test_actual_source_graph_partitions_are_fixed_23_1_1_complete_and_keep_n8_budgets(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        parent=CI.resolve_selection(default,mapping,CI.SOURCE_GRAPH_PARENT_ID)
        self.assertEqual(tuple(parent['unitTestSelectors']),CI.SOURCE_GRAPH_PARENT_SELECTORS)
        seen=[]
        for (partition_id,members),count in zip(CI.SOURCE_GRAPH_METHOD_PARTITIONS,(23,1,1)):
            actual=CI.resolve_selection(default,mapping,partition_id)
            self.assertEqual(len(actual['unitTestSelectors']),count)
            self.assertEqual(tuple(actual['unitTestSelectors']),members)
            self.assertEqual(tuple(actual[k] for k in CI.BUDGET_KEYS),CI.TIERS['N8'])
            seen.extend(actual['unitTestSelectors'])
        self.assertEqual(len(seen),len(set(seen)))
        self.assertEqual(set(seen),set(parent['unitTestSelectors']))
        for selector in CI.SOURCE_GRAPH_PARENT_SELECTORS:
            bundle,klass,method=selector.split('/')
            source=(ROOT/bundle/(klass+'.swift')).read_text(encoding='utf-8')
            self.assertEqual(len(re.findall(r'\bfunc\s+'+re.escape(method)+r'\s*\(',source)),1)

    def test_source_graph_partitions_reject_missing_duplicate_foreign_reordered_unknown_and_map_change(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json')
        mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        parent=list(CI.SOURCE_GRAPH_PARENT_SELECTORS)
        cases=[]
        missing=copy.deepcopy(default);missing['unitTestSelectors'].remove(parent[0]);cases.append(missing)
        duplicate=copy.deepcopy(default);duplicate['unitTestSelectors'].append(parent[0]);cases.append(duplicate)
        foreign=copy.deepcopy(default);foreign['unitTestSelectors'].append(
            'FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testForeign');cases.append(foreign)
        reordered=copy.deepcopy(default)
        positions=[reordered['unitTestSelectors'].index(item) for item in parent[:2]]
        reordered['unitTestSelectors'][positions[0]],reordered['unitTestSelectors'][positions[1]]=parent[1],parent[0]
        cases.append(reordered)
        for hostile in cases:
            with self.subTest(case=cases.index(hostile)),self.assertRaises(ValueError):
                CI.resolve_selection(hostile,mapping,SOURCE_GRAPH_PARTITION_CHOICES[0])
        changed_map=copy.deepcopy(mapping);changed_map['groups'][31]['methodCount']=24
        with self.assertRaises(ValueError):
            CI.resolve_selection(default,changed_map,SOURCE_GRAPH_PARTITION_CHOICES[1])
        with self.assertRaisesRegex(ValueError,'unknown selection ID'):
            CI.resolve_selection(default,mapping,'c36-source-graph-unknown')

    def test_actual_partition_rejects_missing_duplicate_foreign_and_changed_class_groups(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json'); mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        for mutate in (lambda m:m['groups'].pop(),lambda m:m['groups'].append(copy.deepcopy(m['groups'][-1])),
                       lambda m:m['groups'][-1].update(id='foreign'),lambda m:m['groups'][-1]['classes'].pop(),
                       lambda m:m['groups'][-1]['classes'].append('V23CheckRunnerBeginHistoryTests'),
                       lambda m:m['groups'][-1].update(methodCount=48)):
            hostile=copy.deepcopy(mapping); mutate(hostile)
            with self.assertRaises(ValueError): CI.resolve_selection(default,hostile,'c36-field-contracts')
        for mutate in (lambda p:p['unitTestSelectors'].pop(),lambda p:p['unitTestSelectors'].append(p['unitTestSelectors'][-1]),
                       lambda p:p['unitTestSelectors'].append('FieldEvidenceAppTests/ForeignTests/testForeign')):
            hostile=copy.deepcopy(default); mutate(hostile)
            with self.assertRaises(ValueError): CI.resolve_selection(hostile,mapping,'c36-durable-begin')

    def test_historical_inverse_rejects_same_count_reorder_alias_and_map_substitution(self):
        default=CI.read_json(ROOT / 'Scripts/ci-selection.json'); mapping=CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        hostile=copy.deepcopy(default)
        hostile['unitTestSelectors'][0],hostile['unitTestSelectors'][1]=hostile['unitTestSelectors'][1],hostile['unitTestSelectors'][0]
        with self.assertRaises(AssertionError):prepartition_values(hostile,mapping)
        hostile=copy.deepcopy(default); hostile['unitTestSelectors'][-1]=hostile['unitTestSelectors'][-1].replace('/test','/testForeign')
        with self.assertRaises(AssertionError):prepartition_values(hostile,mapping)
        hostile=copy.deepcopy(mapping); hostile['groups'][0]['classes'].reverse()
        hostile['groups'][0]['id']='foreign'
        with self.assertRaises(AssertionError):prepartition_values(default,hostile)

class AdmissionTests(unittest.TestCase):
    def test_both_providers_and_all_supported_tiers_use_same_contract(self):
        for provider in ("github", "bitrise"):
            for tier in ("N8", "P12", "F25"):
                e, s = environment(provider, tier), selection(tier)
                for stage in ("dispatch", "worker"):
                    with self.subTest(provider=provider, tier=tier, stage=stage):
                        value = CI.admission(s, e, HEAD, stage)
                        self.assertEqual(value["contractID"], CI.CONTRACT)
                        self.assertEqual(value["runnerProvider"], provider)
                        self.assertEqual(value["head"], HEAD)
                        self.assertTrue(value["diagnosticOnly"])
                        self.assertFalse(value["providerQualification"])
                        self.assertFalse(value["acceptance"])
                        self.assertFalse(value["releaseReady"])
                        self.assertEqual(value["simulatorFileProtectionDiagnosticPolicy"],
                                         CI.simulator_diagnostic_policy_binding(ROOT))

    def test_allowance_source_rejects_main_caller_policy_and_promotion_inputs(self):
        for stage in ("dispatch", "worker"):
            main = environment()
            main["GITHUB_REF"] = "refs/heads/main"
            with self.subTest(stage=stage, case="main"), self.assertRaisesRegex(ValueError, "never a main route"):
                CI.admission(selection(), main, HEAD, stage)
            for key in ("SIMULATOR_FILE_PROTECTION_POLICY_ID",
                        "CI_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_ONLY",
                        "DISPATCH_SIMULATOR_FILE_PROTECTION_ACCEPTANCE"):
                supplied = environment()
                supplied[key] = "true"
                with self.subTest(stage=stage, key=key), self.assertRaisesRegex(ValueError, "caller-supplied"):
                    CI.admission(selection(), supplied, HEAD, stage)

    def test_each_foreign_dispatch_input_is_rejected(self):
        for key in ("SHARED_SHARD", "SHARED_SEGMENT", "SHARED_SOURCE_RUN", "SHARED_SOURCE_MAP", "SMOKE_ID"):
            for value in ("foreign", None):
                e = environment("bitrise")
                if value is None:
                    del e[key]
                else:
                    e[key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CI.admission(selection(), e, HEAD, "dispatch")

    def test_each_foreign_worker_input_and_contract_is_rejected(self):
        valid = environment("bitrise")
        keys = [key for key in valid if key.startswith(("DISPATCH_", "WORKER_", "CI_S10_4_"))]
        keys += ["CI_NATIVE_ACCEPTANCE_CONTRACT", "CI_RUNNER_PROVIDER", "CI_RUNNER_LABEL"]
        for key in keys:
            for value in ("foreign", None):
                e = valid.copy()
                if value is None:
                    del e[key]
                else:
                    e[key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    CI.admission(selection(), e, HEAD, "worker")

    def test_repository_ref_event_and_original_identity_are_exact(self):
        for stage in ("dispatch", "worker"):
            for key, value in (("GITHUB_REPOSITORY", "fork/AssetRounds"), ("GITHUB_REF", "refs/heads/foreign"),
                               ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_SHA", "2" * 40),
                               ("GITHUB_SHA", "1" * 39), ("GITHUB_RUN_ID", "0"), ("GITHUB_RUN_ATTEMPT", "0")):
                e = environment()
                e[key] = value
                with self.subTest(stage=stage, key=key, value=value), self.assertRaises(ValueError):
                    CI.admission(selection(), e, HEAD, stage)

    def test_legacy_mode_cannot_admit_current_task_or_new_bitrise_lane(self):
        s, e = selection(), environment()
        e["CI_NATIVE_ACCEPTANCE_CONTRACT"] = "none"
        with self.assertRaises(ValueError):
            CI.admission(s, e, HEAD, "worker")
        s["taskID"] = "S10.4"
        self.assertIsNone(CI.admission(s, e, HEAD, "worker"))
        self.assertIsNone(CI.admission(s, e, HEAD, "dispatch"))
        e["SHARED_LANE"] = "bitrise-build-hub-xcode-26.6-acceptance"
        with self.assertRaises(ValueError):
            CI.admission(s, e, HEAD, "dispatch")
        e["CI_NATIVE_ACCEPTANCE_CONTRACT"] = CI.CONTRACT
        with self.assertRaises(ValueError):
            CI.admission(s, e, HEAD, "worker")

    def test_selector_shape_exact_methods_and_budgets_are_preserved(self):
        changes = (("schemaVersion", True), ("taskID", "S10.4"), ("tier", "custom"),
                   ("runUISmoke", True), ("buildTimeoutSeconds", 601), ("uiTimeoutSeconds", False),
                   ("unitTestSelectors", []), ("unitTestSelectors", [UNIT, UNIT]),
                   ("unitTestSelectors", ["FieldEvidenceAppTests/NativeFixtureTests"]),
                   ("unitTestSelectors", [UI]), ("uiTestSelectors", [UI]), ("extra", 1))
        for key, value in changes:
            s = selection()
            s[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                CI.validate_selection(s)

    def test_duplicate_json_keys_fail(self):
        with self.assertRaises(ValueError):
            json.loads('{"head":"a","head":"b"}', object_pairs_hook=CI.unique_pairs)


class UpdatedBuildBudgetAdmissionTests(unittest.TestCase):
    def test_previous_budget_cannot_dispatch_or_attest_current_policy(self):
        current = selection()
        previous = dict(current, buildTimeoutSeconds=600)
        for provider in ("github", "bitrise"):
            for stage in ("dispatch", "worker"):
                valid = environment(provider)
                CI.admission(current, valid, HEAD, stage)
                stale = environment(provider)
                stale["DISPATCH_NATIVE_SELECTION_SHA256"] = CI.sha256(CI.canonical(previous))
                with self.assertRaises(ValueError):
                    CI.admission(previous, stale, HEAD, stage)


class BuildWatchdogDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.default = CI.read_json(ROOT / 'Scripts/ci-selection.json')
        self.mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.selected = CI.resolve_selection(self.default, self.mapping, CI.BUILD_WATCHDOG_SELECTION_ID)
        self.record = {'selectionID': CI.BUILD_WATCHDOG_SELECTION_ID,
                       'selectionSHA256': CI.sha256(CI.canonical(self.selected)),
                       'selectionMapSHA256': CI.sha256(CI.canonical(self.mapping))}
        self.header = ('tree ' + 'a' * 40 + '\nparent ' + CI.BUILD_WATCHDOG_PARENT + '\n\nmessage\n').encode()

    def bound_environment(self, provider='github'):
        e = environment(provider)
        e.update(DISPATCH_NATIVE_SELECTION_ID=self.record['selectionID'],
                 DISPATCH_NATIVE_SELECTION_SHA256=self.record['selectionSHA256'],
                 DISPATCH_NATIVE_SELECTION_MAP_SHA256=self.record['selectionMapSHA256'])
        return e

    def test_closed_diagnostic_retains_exact_method_pool_and_ordinary_budgets(self):
        self.assertEqual(self.selected['unitTestSelectors'], [
            'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckNoIssueUsesOriginalFiveSagaHistory'])
        self.assertEqual(tuple(self.selected[k] for k in CI.BUDGET_KEYS), (300, 1800, 900, 0, 3000))
        self.assertEqual((self.selected['tier'], self.selected['runUISmoke'], self.selected['uiTestSelectors']),
                         ('D30', False, []))
        for name in [CI.DEFAULT_SELECTION_ID, 'c36-parent-finalization-check-no-issue'] + [g['id'] for g in self.mapping['groups']]:
            old = CI.resolve_selection(self.default, self.mapping, name)
            self.assertEqual(tuple(old[k] for k in CI.BUDGET_KEYS), (300, 1200, 900, 0, 2400))
        self.assertEqual(CI.sha256(CI.canonical(self.default)), CI.GENERATED_SELECTION_POOL_SHA256)
        self.assertEqual(CI.sha256(CI.canonical(self.mapping)), CI.GENERATED_SELECTION_MAP_SHA256)

    def test_diagnostic_rejects_other_methods_tiers_budgets_and_ids(self):
        for fields in ({'unitTestSelectors': [UNIT]}, {'unitTestSelectors': self.selected['unitTestSelectors'] * 2},
                       {'tier': 'N8'}, {'buildTimeoutSeconds': 1801}, {'testTimeoutSeconds': 901},
                       {'setupArtifactTimeoutSeconds': 301}, {'totalBudgetSeconds': 3001},
                       {'runUISmoke': True}, {'uiTestSelectors': [UI]}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                CI.validate_selection(dict(self.selected, **fields))
        with self.assertRaises(ValueError):
            CI.resolve_selection(self.default, self.mapping, CI.BUILD_WATCHDOG_SELECTION_ID + '-retry')

    def test_both_admission_stages_bind_original_github_attempt_and_approved_parent(self):
        for stage in ('dispatch', 'worker'):
            with mock.patch.object(CI.subprocess, 'check_output', return_value=self.header) as read:
                result = CI.admission(self.selected, self.bound_environment(), HEAD, stage, self.record)
            read.assert_called_once_with(['git', 'cat-file', 'commit', HEAD], cwd=ROOT)
            self.assertEqual(result['selectionID'], CI.BUILD_WATCHDOG_SELECTION_ID)
            self.assertTrue(result['diagnosticOnly'])
            self.assertFalse(result['acceptance'])
            self.assertFalse(result['providerQualification'])

    def test_admission_denies_foreign_provider_rerun_parent_and_selector_substitution(self):
        for stage in ('dispatch', 'worker'):
            for e, record, selected, header in (
                (self.bound_environment('bitrise'), self.record, self.selected, self.header),
                (dict(self.bound_environment(), GITHUB_RUN_ATTEMPT='2'), self.record, self.selected, self.header),
                (self.bound_environment(), self.record, self.selected, b'tree a\n\nmessage\n'),
                (self.bound_environment(), self.record, self.selected, self.header.replace(CI.BUILD_WATCHDOG_PARENT.encode(), b'b' * 40)),
                (self.bound_environment(), self.record, self.selected, self.header.replace(b'\n\n', b'\nparent ' + b'b' * 40 + b'\n\n')),
                (self.bound_environment(), dict(self.record, selectionID='c36-parent-finalization-check-no-issue'), self.selected, self.header),
                (self.bound_environment(), self.record, CI.resolve_selection(self.default, self.mapping, 'c36-parent-finalization-check-no-issue'), self.header),
            ):
                with self.subTest(stage=stage, provider=e['CI_RUNNER_PROVIDER']), mock.patch.object(
                        CI.subprocess, 'check_output', return_value=header), self.assertRaises(ValueError):
                    CI.admission(selected, e, HEAD, stage, record)

    def test_actual_worker_budget_filter_accepts_only_exact_diagnostic_and_retains_ordinary_tiers(self):
        worker = (ROOT / '.github/workflows/ios-ci-worker.yml').read_text(encoding='utf-8')
        start = worker.index('            def exact_keys:')
        start = worker.rfind("jq -e '", 0, start) + len("jq -e '")
        end = worker.index("' \"$CI_SELECTION_PATH\"", start)
        query = worker[start:end]
        cases = [(self.selected, True)] + [(selection(tier), True) for tier in ('N8', 'P12', 'F25')]
        cases += [(dict(self.selected, **fields), False) for fields in (
            {'buildTimeoutSeconds': 1200}, {'totalBudgetSeconds': 2400}, {'testTimeoutSeconds': 901},
            {'unitTestSelectors': [UNIT]}, {'taskID': 'S10.4'}, {'runUISmoke': True})]
        for value, expected in cases:
            with self.subTest(value=value):
                result = subprocess.run(['jq', '-e', query], input=json.dumps(value), text=True,
                                        capture_output=True, check=False)
                self.assertEqual(result.returncode == 0, expected, result.stderr)


class ResultTests(unittest.TestCase):
    def test_real_tree_shape_normalizes_only_method_parentheses(self):
        tree = native_tree()
        self.assertEqual(CI.executed_methods(tree, [UNIT], "FieldEvidenceAppTests", "Unit test bundle"), [UNIT])
        leaf(tree)["nodeIdentifier"] = UNIT
        self.assertEqual(CI.executed_methods(tree, [UNIT], "FieldEvidenceAppTests", "Unit test bundle"), [UNIT])
        self.assertEqual(CI.executed_methods(native_tree(UI, True), [UI], "FieldEvidenceAppUITests", "UI test bundle"), [UI])

    def test_failed_skipped_expected_failure_and_missing_status_are_rejected(self):
        for result in ("Failed", "Skipped", "Expected Failure", "Not Run", None):
            tree = native_tree()
            leaf(tree)["result"] = result
            with self.subTest(result=result), self.assertRaises(ValueError):
                CI.executed_methods(tree, [UNIT], "FieldEvidenceAppTests", "Unit test bundle")

    def test_duplicate_unexpected_missing_and_nested_test_cases_are_rejected(self):
        duplicate = native_tree()
        duplicate["testNodes"][0]["children"][0]["children"][0]["children"].append(copy.deepcopy(leaf(duplicate)))
        unexpected = native_tree()
        leaf(unexpected)["nodeIdentifier"] = "NativeFixtureTests/testOther"
        missing = native_tree()
        missing["testNodes"][0]["children"][0]["children"] = []
        nested = native_tree()
        leaf(nested)["children"] = [copy.deepcopy(leaf(nested))]
        for name, tree in (("duplicate", duplicate), ("unexpected", unexpected), ("missing", missing), ("nested", nested)):
            with self.subTest(name=name), self.assertRaises(ValueError):
                CI.executed_methods(tree, [UNIT], "FieldEvidenceAppTests", "Unit test bundle")

    def test_wrong_or_duplicate_bundles_and_unowned_cases_are_rejected(self):
        wrong = native_tree()
        wrong["testNodes"][0]["children"][0]["name"] = "OtherBundle"
        duplicate = native_tree()
        duplicate["testNodes"][0]["children"].append(copy.deepcopy(duplicate["testNodes"][0]["children"][0]))
        unowned = {"testNodes": [copy.deepcopy(leaf(native_tree()))]}
        for tree in (wrong, duplicate, unowned):
            with self.assertRaises(ValueError):
                CI.executed_methods(tree, [UNIT], "FieldEvidenceAppTests", "Unit test bundle")


class SimulatorDiagnosticEvidenceTests(unittest.TestCase):
    def test_policy_binding_is_derived_from_exact_tracked_policy_and_allowance_source(self):
        binding = CI.simulator_diagnostic_policy_binding(ROOT)
        self.assertEqual(binding["policySHA256"], CI.SIMULATOR_DIAGNOSTIC_POLICY_SHA256)
        self.assertEqual(binding["policyID"], CI.SIMULATOR_DIAGNOSTIC_POLICY_ID)
        self.assertTrue(binding["diagnosticOnly"])
        self.assertFalse(binding["countsAsPerKindProtectionSuccess"])
        self.assertFalse(binding["providerQualification"])
        self.assertEqual(binding["allowanceSourceSHA256"],
                         CI.sha256((ROOT / CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH).read_bytes()))
        native_source = (ROOT / "Scripts/v23-native-ci.py").read_text()
        self.assertEqual(native_source.count(CI.SIMULATOR_DIAGNOSTIC_POLICY_PATH), 1)
        swift_source = (ROOT / CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH).read_text()
        emission = swift_source.split('let facts = "' + CI.SIMULATOR_DIAGNOSTIC_PREFIX + '"', 1)[1].split(
            "diagnosticWriter.write(facts)", 1)[0]
        field_offsets = [emission.index(" " + field + "=") for field in CI.SIMULATOR_DIAGNOSTIC_FIELDS]
        self.assertEqual(field_offsets, sorted(field_offsets))
        self.assertNotIn(" path=", emission)
        with tempfile.TemporaryDirectory(prefix="v23-simulator-policy-") as directory:
            root = Path(directory)
            for relative in (CI.SIMULATOR_DIAGNOSTIC_POLICY_PATH, CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            self.assertEqual(CI.simulator_diagnostic_policy_binding(root), binding)
            with mock.patch.object(CI, "SIMULATOR_DIAGNOSTIC_SOURCE_SHA256",
                                   "2B2F3D7DD16E97357DE5816613AAE2C0F7F4E3F1F1B53E83B0A8D53E578AC27F"):
                with self.assertRaisesRegex(ValueError, "reviewed source digest"):
                    CI.simulator_diagnostic_policy_binding(root)
            (root / CI.SIMULATOR_DIAGNOSTIC_POLICY_PATH).write_bytes(b"{}\n")
            with self.assertRaisesRegex(ValueError, "policy digest"):
                CI.simulator_diagnostic_policy_binding(root)
            shutil.copyfile(ROOT / CI.SIMULATOR_DIAGNOSTIC_POLICY_PATH,
                            root / CI.SIMULATOR_DIAGNOSTIC_POLICY_PATH)
            source = root / CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH
            source.write_text(source.read_text().replace(CI.SIMULATOR_DIAGNOSTIC_PREFIX, "foreign", 1))
            with self.assertRaisesRegex(ValueError, "reviewed source digest"):
                CI.simulator_diagnostic_policy_binding(root)
            original_source = (ROOT / CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH).read_bytes()
            weakened_source = original_source.replace(b'readback.volumeSupportsProtection == false',
                                                       b'readback.volumeSupportsProtection != true', 1)
            self.assertNotEqual(weakened_source, original_source)
            self.assertIn(CI.SIMULATOR_DIAGNOSTIC_PREFIX.encode(), weakened_source)
            self.assertIn(b'#if DEBUG && os(iOS) && targetEnvironment(simulator)', weakened_source)
            source.write_bytes(weakened_source)
            with self.assertRaisesRegex(ValueError, "reviewed source digest"):
                CI.simulator_diagnostic_policy_binding(root)
            source.unlink()
            with self.assertRaisesRegex(ValueError, "allowance source"):
                CI.simulator_diagnostic_policy_binding(root)

    def test_closed_owned_kind_dispositions_match_swift_enum_and_policy_switch(self):
        source = (ROOT / CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH).read_text()
        enum_body = source.split("enum OwnedFileKindV1:", 1)[1].split("\n}", 1)[0]
        swift_kinds = set(re.findall(r"^\s*case\s+([A-Za-z][A-Za-z0-9]*)\s*$", enum_body, re.MULTILINE))
        self.assertEqual(set(CI.OWNED_FILE_DISPOSITIONS), swift_kinds)
        self.assertEqual(len(swift_kinds), 31)
        for kind in swift_kinds:
            event = CI.parse_simulator_diagnostic_line(diagnostic_line(kind))
            self.assertEqual((event["backupExcluded"], event["expectsDirectory"]),
                             CI.OWNED_FILE_DISPOSITIONS[kind])

    def test_exact_events_retain_order_and_duplicates_without_protection_credit(self):
        record = CI.admission(selection(), environment(), HEAD, "worker")
        with tempfile.TemporaryDirectory(prefix="v23-simulator-events-") as directory:
            artifact = Path(directory)
            lines = [diagnostic_line("database"), diagnostic_line("scratch"),
                     diagnostic_line("database")]
            log = "ordinary output\nfinished\n"
            (artifact / "test-smoke.log").write_bytes(log.encode("utf-8"))
            diagnostic_transport(artifact, [
                ("00000000-0000-0000-0000-000000000010", lines)
            ])
            evidence, error = CI.simulator_diagnostic_observations(ROOT, artifact, record)
            self.assertIsNone(error)
            self.assertEqual([item["kind"] for item in evidence["events"]],
                             ["database", "scratch", "database"])
            self.assertEqual(evidence["eventCount"], 3)
            self.assertFalse(evidence["zeroUseObserved"])
            self.assertFalse(evidence["countsAsPerKindProtectionSuccess"])
            self.assertEqual(evidence["testLog"]["sha256"], CI.sha256(log.encode()))

    def test_malformed_duplicate_unknown_and_hostile_event_values_fail_closed(self):
        variants = []
        for field, value in (
            ("policyID", "foreign"), ("disposition", "VERIFIED_COMPLETE"),
            ("kind", "foreignKind"), ("request", "none"),
            ("capabilityBefore", "true"), ("capabilityAfter", "unknown"),
            ("urlProtection", "complete"),
            ("backupExcluded", "true"), ("expectsDirectory", "true"),
            ("identityUnchanged", "false"),
        ):
            variants.append((field, diagnostic_line("database", **{field: value})))
        valid = diagnostic_line().strip()
        variants += [
            ("old-v1-marker", valid.replace(CI.SIMULATOR_DIAGNOSTIC_PREFIX,
                                             "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_V1", 1) + "\n"),
            ("removed-file-manager-field", valid.replace(
                " backupExcluded=", " fileManagerProtection=completeUntilFirstUserAuthentication backupExcluded=", 1) + "\n"),
            ("duplicate", valid + " kind=database\n"),
            ("missing", valid.rsplit(" ", 1)[0] + "\n"),
            ("reordered", valid.replace(" policyID=", " PLACEHOLDER=").replace(
                " disposition=", " policyID=").replace(" PLACEHOLDER=", " disposition=") + "\n"),
            ("prefixed", "x " + valid + "\n"),
            ("duplicate-marker", valid + " " + CI.SIMULATOR_DIAGNOSTIC_PREFIX + "\n"),
            ("interleaved-policy-write", diagnostic_line("stagingDirectory").replace(
                "urlProtection=", "urlPProtectedFilePolicy resource-value-mismatch "
                "protectionMatches=false backupMatches=true\nrotection=", 1)),
        ]
        for name, line in variants:
            with self.subTest(name=name), self.assertRaises(ValueError):
                CI.parse_simulator_diagnostic_line(line)
        record = CI.admission(selection(), environment(), HEAD, "worker")
        for marker in ("V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_V1",
                       "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_FOREIGN"):
            with self.subTest(marker=marker), tempfile.TemporaryDirectory(
                    prefix="v23-simulator-stale-marker-") as directory:
                artifact = Path(directory)
                (artifact / "test-smoke.log").write_text(
                    diagnostic_line().replace(CI.SIMULATOR_DIAGNOSTIC_PREFIX, marker, 1),
                    encoding="utf-8")
                diagnostic_transport(artifact)
                with self.assertRaisesRegex(ValueError, "transport parse"):
                    CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)
                retained = CI.read_json(artifact / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
                self.assertEqual(retained["parseStatus"], "INVALID")
                self.assertFalse(retained["zeroUseObserved"])
                self.assertEqual(retained["events"], [])

    def test_absent_log_is_unavailable_and_malformed_log_is_persisted_before_failure(self):
        record = CI.admission(selection(), environment(), HEAD, "worker")
        with tempfile.TemporaryDirectory(prefix="v23-simulator-persist-") as directory:
            artifact = Path(directory)
            diagnostic_transport(artifact)
            evidence = CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)
            self.assertEqual(evidence["testLog"]["availability"], "UNAVAILABLE")
            self.assertEqual(evidence["parseStatus"], "PASS")
            self.assertTrue(evidence["zeroUseObserved"])
        with tempfile.TemporaryDirectory(prefix="v23-simulator-invalid-") as directory:
            artifact = Path(directory)
            (artifact / "test-smoke.log").write_text(diagnostic_line(kind="database", capabilityAfter="true"))
            diagnostic_transport(artifact)
            with self.assertRaisesRegex(ValueError, "transport parse"):
                CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)
            retained = CI.read_json(artifact / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
            self.assertEqual(retained["testLog"]["availability"], "AVAILABLE")
            self.assertEqual(retained["parseStatus"], "INVALID")
            self.assertEqual(retained["events"], [])
            self.assertFalse(retained["zeroUseObserved"])

    def test_valid_prefix_events_survive_a_later_malformed_marker(self):
        record = CI.admission(selection(), environment(), HEAD, "worker")
        with tempfile.TemporaryDirectory(prefix="v23-simulator-partial-") as directory:
            artifact = Path(directory)
            (artifact / "test-smoke.log").write_text("ordinary output\n")
            diagnostic_transport(artifact, [
                ("00000000-0000-0000-0000-000000000011", [
                    diagnostic_line("database"),
                    diagnostic_line("scratch", identityUnchanged="false"),
                ])
            ])
            with self.assertRaisesRegex(ValueError, "transport parse"):
                CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)
            retained = CI.read_json(artifact / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
            self.assertEqual(retained["parseStatus"], "INVALID")
            self.assertEqual([event["kind"] for event in retained["events"]], ["database"])
            self.assertEqual(retained["eventCount"], 1)
            self.assertFalse(retained["zeroUseObserved"])

    def test_framed_streams_preserve_process_order_raw_bindings_and_semantic_duplicates(self):
        record = CI.admission(selection(), environment(), HEAD, "worker")
        streams = [
            ("00000000-0000-0000-0000-000000000021",
             [diagnostic_line("database"), diagnostic_line("database")]),
            ("00000000-0000-0000-0000-000000000022",
             [diagnostic_line("scratch")]),
        ]
        with tempfile.TemporaryDirectory(prefix="v23-framed-diagnostics-") as directory:
            artifact = Path(directory)
            (artifact / "test-smoke.log").write_text("XCTest output stays separate\n")
            diagnostic_transport(artifact, streams)
            evidence, error = CI.simulator_diagnostic_observations(ROOT, artifact, record)
            self.assertIsNone(error)
            self.assertEqual([item["kind"] for item in evidence["events"]],
                             ["database", "database", "scratch"])
            self.assertEqual([(item["streamID"], item["sequence"])
                              for item in evidence["rawRecords"]], [
                (streams[0][0], 1), (streams[0][0], 2), (streams[1][0], 1)])
            self.assertEqual(evidence["transport"]["inventorySHA256"],
                             CI.sha256(CI.canonical(evidence["transport"]["files"])))

    def test_framed_transport_rejects_structural_binding_and_availability_hostiles(self):
        stream = "00000000-0000-0000-0000-000000000031"
        cases = []
        valid = diagnostic_frame(stream, 1, diagnostic_line())
        duplicate_key = valid.replace(b'"sequence":1', b'"sequence":1,"sequence":1')
        cases.extend([
            ("duplicate-key", duplicate_key),
            ("truncated", valid[:-1]),
            ("sequence-gap", diagnostic_frame(stream, 2, diagnostic_line())),
            ("wrong-stream", diagnostic_frame(
                "00000000-0000-0000-0000-000000000032", 1, diagnostic_line())),
            ("embedded-cr", valid.replace(b"}\n", b"}\r\n")),
        ])
        record = CI.admission(selection(), environment(), HEAD, "worker")
        for name, raw in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory(
                    prefix="v23-frame-hostile-") as directory:
                artifact = Path(directory)
                (artifact / "test-smoke.log").write_text("ordinary\n")
                diagnostic_transport(artifact, [(stream, [diagnostic_line()])])
                path = artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY / (stream + ".jsonl")
                path.write_bytes(raw)
                rebind_diagnostic_transport(artifact)
                evidence, error = CI.simulator_diagnostic_observations(ROOT, artifact, record)
                self.assertIsNotNone(error)
                self.assertEqual(evidence["parseStatus"], "INVALID")
                self.assertEqual(evidence["transport"]["files"][0]["sha256"], CI.sha256(raw))
        for status in ("UNAVAILABLE", "UNSAFE", "INTERRUPTED"):
            with self.subTest(status=status), tempfile.TemporaryDirectory(
                    prefix="v23-frame-status-") as directory:
                artifact = Path(directory)
                (artifact / "test-smoke.log").write_text("ordinary\n")
                diagnostic_transport(artifact, status=status, error="retained failure")
                evidence, error = CI.simulator_diagnostic_observations(ROOT, artifact, record)
                self.assertIsNotNone(error)
                self.assertEqual(evidence["transport"]["status"], status)
                self.assertFalse(evidence["zeroUseObserved"])

        malformed_inventories = [
            ["not-an-object"],
            [{"name": "00000000-0000-0000-0000-000000000031.jsonl", "bytes": True,
              "sha256": "0" * 64}],
        ]
        for files in malformed_inventories:
            with self.subTest(files=files), tempfile.TemporaryDirectory(
                    prefix="v23-frame-inventory-") as directory:
                artifact = Path(directory)
                diagnostic_transport(
                    artifact, status="UNSAFE", error="retained failure", files=files,
                    fileCount=len(files), totalBytes=0,
                    inventorySHA256=CI.sha256(CI.canonical(files)))
                evidence, error = CI.simulator_diagnostic_observations(ROOT, artifact, record)
                self.assertIsInstance(error, ValueError)
                self.assertEqual(evidence["parseStatus"], "INVALID")

    def test_collector_binds_fresh_simulator_and_retains_available_zero_interrupted_and_unsafe(self):
        def fixture(directory, app_entries=(), interrupted=False, returncode=0,
                    monotonic=time.monotonic, read_chunk=None):
            root = Path(directory)
            artifact = root / "artifact"
            container = root / "container"
            artifact.mkdir()
            container.mkdir()
            (artifact / "simulator-selection.txt").write_text(
                "runtime=iOS 26.2\nruntime_build=23C54\nname=iPhone 17\n"
                f"udid={UDID}\ninitial_state=Shutdown\n")
            leaf = container / CI.SIMULATOR_DIAGNOSTIC_APP_DIRECTORY
            if app_entries:
                leaf.mkdir(parents=True)
                for name, raw in app_entries:
                    (leaf / name).write_bytes(raw)
            calls = []
            def fake_run(arguments, **keywords):
                calls.append((arguments, keywords))
                return subprocess.CompletedProcess(
                    arguments, returncode,
                    stdout=(str(container) + "\n") if returncode == 0 else "",
                    stderr="" if returncode == 0 else "missing app\n")
            e = {"CI_SIMULATOR_UDID": UDID, "CI_NATIVE_CREATED_SIMULATOR_UDID": UDID}
            status = CI.collect_simulator_diagnostic_transport(
                ROOT, artifact, e, interrupted=interrupted, run=fake_run,
                monotonic=monotonic, read_chunk=read_chunk)
            self.assertEqual(calls[0][0], [
                "xcrun", "simctl", "get_app_container", UDID,
                CI.SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID, "data"])
            self.assertEqual(calls[0][1]["timeout"], 2)
            self.assertEqual(CI.read_json(
                artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS), status)
            return artifact, status

        stream = "00000000-0000-0000-0000-000000000041"
        raw = diagnostic_frame(stream, 1, diagnostic_line())
        with tempfile.TemporaryDirectory(prefix="v23-collect-available-") as directory:
            artifact, status = fixture(directory, [(stream + ".jsonl", raw)])
            self.assertEqual(status["status"], "AVAILABLE")
            self.assertEqual(status["fileCount"], 1)
            self.assertEqual((artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY /
                              (stream + ".jsonl")).read_bytes(), raw)
        with tempfile.TemporaryDirectory(prefix="v23-collect-zero-") as directory:
            _, status = fixture(directory)
            self.assertEqual(status["status"], "ZERO_USE")
        with tempfile.TemporaryDirectory(prefix="v23-collect-empty-original-") as directory:
            artifact, status = fixture(directory, [(stream + ".jsonl", b"")])
            self.assertEqual(status["status"], "AVAILABLE")
            self.assertEqual(status["files"], [{
                "name": stream + ".jsonl", "bytes": 0, "sha256": CI.sha256(b""),
            }])
            self.assertEqual((artifact / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY /
                              (stream + ".jsonl")).read_bytes(), b"")
            (artifact / "test-smoke.log").write_text("ordinary\n")
            record = CI.admission(selection(), environment(), HEAD, "worker")
            with self.assertRaisesRegex(ValueError, "transport parse"):
                CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)
            evidence = CI.read_json(artifact / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
            self.assertEqual(evidence["transport"]["files"], status["files"])
            self.assertEqual(evidence["parseStatus"], "INVALID")
            self.assertFalse(evidence["zeroUseObserved"])
        with tempfile.TemporaryDirectory(prefix="v23-collect-interrupted-") as directory:
            _, status = fixture(directory, [(stream + ".jsonl", raw)], interrupted=True)
            self.assertEqual(status["status"], "INTERRUPTED")
            self.assertEqual(status["error"], "native command interrupted")
            self.assertEqual(status["files"][0]["sha256"], CI.sha256(raw))
        with tempfile.TemporaryDirectory(prefix="v23-collect-unavailable-") as directory:
            _, status = fixture(directory, returncode=1)
            self.assertEqual(status["status"], "UNAVAILABLE")
        with tempfile.TemporaryDirectory(prefix="v23-collect-unsafe-") as directory:
            _, status = fixture(directory, [("foreign.txt", b"raw original\n")])
            self.assertEqual(status["status"], "UNSAFE")
        with tempfile.TemporaryDirectory(prefix="v23-collect-deadline-") as directory:
            clock = [0.0]
            def monotonic():
                return clock[0]
            def slow_read(source, count):
                chunk = source.read(count)
                clock[0] = CI.SIMULATOR_DIAGNOSTIC_WORK_SECONDS + 0.01
                return chunk
            artifact, status = fixture(
                directory, [(stream + ".jsonl", raw)], monotonic=monotonic,
                read_chunk=slow_read)
            self.assertEqual(status["status"], "UNSAFE")
            self.assertIn("deadline", status["error"])
            self.assertEqual(status["files"], [{
                "name": stream + ".jsonl", "bytes": len(raw), "sha256": CI.sha256(raw),
            }])
            self.assertLess(clock[0], CI.SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS)
            self.assertFalse((artifact / (CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS + ".next")).exists())

    def test_smoke_collection_trap_preserves_all_three_native_command_vectors(self):
        source = (ROOT / "Scripts/test-smoke.sh").read_text()
        commands = [source.split("  shared_unit_command=(\n", 1)[1].split("  )\n", 1)[0]]
        commands.extend(re.findall(
            r"(?m)^  xcodebuild \\\n(?:    .*\n)+?    test-without-building\n", source))
        self.assertEqual(len(commands), 3)
        self.assertEqual(
            hashlib.sha256("\0".join(commands).encode()).hexdigest().upper(),
            "22FA5DD494FE30A677F8F013F829919EDC4D0F67BC2223C1DEA9DA76C56FAB9C",
        )
        trap = 'if [ "${CI_NATIVE_ACCEPTANCE_CONTRACT:-none}" = "v23.integration.current-native.v1" ]; then'
        self.assertEqual(source.count(trap), 1)
        self.assertLess(source.index(trap), source.index("only_testing_args=()"))
        self.assertEqual(source.count('python3 Scripts/v23-native-ci.py "${collector_args[@]}"'), 1)

    def test_forged_admission_promotion_is_rejected_even_with_exact_policy_and_log(self):
        for field, promoted in (("diagnosticOnly", False), ("providerQualification", True),
                                ("acceptance", True), ("releaseReady", True)):
            record = CI.admission(selection(), environment(), HEAD, "worker")
            record[field] = promoted
            with tempfile.TemporaryDirectory(prefix="v23-simulator-promotion-") as directory:
                artifact = Path(directory)
                (artifact / "test-smoke.log").write_bytes(b"no diagnostic use\n")
                diagnostic_transport(artifact)
                with self.subTest(field=field), self.assertRaisesRegex(ValueError, "admission classification"):
                    CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)

    def test_unsafe_log_shape_is_persisted_as_invalid_before_rejection(self):
        record = CI.admission(selection(), environment(), HEAD, "worker")
        with tempfile.TemporaryDirectory(prefix="v23-simulator-unsafe-") as directory:
            artifact = Path(directory)
            (artifact / "test-smoke.log").mkdir()
            diagnostic_transport(artifact)
            with self.assertRaisesRegex(ValueError, "transport parse"):
                CI.persist_simulator_diagnostic_observations(ROOT, artifact, record)
            retained = CI.read_json(artifact / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
            self.assertEqual(retained["testLog"]["availability"], "UNSAFE")
            self.assertEqual(retained["transport"]["status"], "ZERO_USE")
            self.assertEqual(retained["parseStatus"], "INVALID")
            self.assertFalse(retained["zeroUseObserved"])


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="v23-native-protocol-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def fixture(self, provider="github", tier="N8"):
        diagnostic = self.path / CI.SIMULATOR_DIAGNOSTIC_OUTPUT
        if diagnostic.exists():
            diagnostic.unlink()
        transport_status = self.path / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS
        if transport_status.exists():
            transport_status.unlink()
        transport_directory = self.path / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY
        if transport_directory.exists():
            shutil.rmtree(transport_directory)
        e, s = environment(provider, tier), selection(tier)
        record = CI.admission(s, e, HEAD, "worker")
        (self.path / "native-admission.json").write_bytes(CI.canonical(record))
        (self.path / "ci-selection.selected.json").write_bytes(CI.canonical(s))
        directory = ("/Applications/Xcode-26.6.0.app/Contents/Developer" if provider == "bitrise"
                     else "/Applications/Xcode_26.6.app/Contents/Developer")
        (self.path / "runner-provider.txt").write_text(
            f"provider={provider}\nlabel={record['runnerLabel']}\nrunner_architecture=ARM64\n"
            f"uname_architecture=arm64\ndeveloper_dir={directory}\nmacos_product_version=26.6.1\n")
        (self.path / "xcode-version.txt").write_text("Xcode 26.6\nBuild version 17F113\n")
        (self.path / "native-sdk.txt").write_text("sdk=iphonesimulator\nversion=26.5\nbuild=23F81a\n")
        (self.path / "simulator-selection.txt").write_text(
            f"runtime=iOS 26.2\nruntime_build=23C54\nname=iPhone 17\nudid={UDID}\ninitial_state=Shutdown\n")
        (self.path / "unit-test-results.json").write_bytes(CI.canonical(native_tree()))
        (self.path / "test-smoke.log").write_text("native fixture completed\n", encoding="utf-8")
        diagnostic_transport(self.path)
        if tier != "N8":
            (self.path / "ui-test-results.json").write_bytes(CI.canonical(native_tree(UI, True)))
            (self.path / "ui-final.png").write_bytes(b"\x89PNG\r\n\x1a\nprotocol-fixture-only")
        if provider == "bitrise":
            for name in ("bitrise-build-cache-cli-verification.txt", "bitrise-build-cache-wrapper-paths.txt"):
                (self.path / name).write_text("verified-source-fixture\n")
            (self.path / "bitrise-build-cache-activation.log").write_text(
                "activation_exit=0\ncache=true\ncache_push=true\nbenchmark_phase=established\n")
        return e, s, record

    def verify(self, fixture):
        e, s, record = fixture
        return CI.verify_checkpoint(ROOT, self.path, record, s, e)

    def test_native_checkpoint_is_not_whole_app_or_human_acceptance(self):
        result = self.verify(self.fixture())
        self.assertEqual(result["executedUnitMethods"], [UNIT])
        self.assertFalse(result["wholeAppAcceptance"])
        self.assertFalse(result["humanReviewComplete"])
        self.assertTrue(result["diagnosticOnly"])
        self.assertFalse(result["providerQualification"])
        self.assertEqual(result["simulatorFileProtectionDiagnostics"]["events"], [])
        self.assertTrue(result["simulatorFileProtectionDiagnostics"]["zeroUseObserved"])

    def test_cached_bitrise_ui_checkpoint_requires_actual_tests(self):
        result = self.verify(self.fixture("bitrise", "P12"))
        self.assertEqual(result["executedUIMethods"], [UI])
        (self.path / "unit-test-results.json").unlink()
        with self.assertRaises(ValueError):
            self.verify((environment("bitrise", "P12"), selection("P12"),
                         CI.admission(selection("P12"), environment("bitrise", "P12"), HEAD, "worker")))

    def test_upstream_failure_cannot_be_repaired_by_present_results(self):
        fixture = self.fixture()
        fixture[0]["NATIVE_PRIOR_JOB_STATUS"] = "failure"
        with self.assertRaises(ValueError):
            self.verify(fixture)
        retained = CI.read_json(self.path / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
        self.assertEqual(retained["testLog"]["availability"], "AVAILABLE")
        self.assertEqual(retained["parseStatus"], "PASS")
        self.assertTrue(retained["zeroUseObserved"])

    def test_failure_before_units_retains_explicitly_unavailable_log_not_zero_use(self):
        fixture = self.fixture()
        fixture[0]["NATIVE_PRIOR_JOB_STATUS"] = "failure"
        (self.path / "test-smoke.log").unlink()
        with self.assertRaisesRegex(ValueError, "earlier job failure"):
            self.verify(fixture)
        retained = CI.read_json(self.path / CI.SIMULATOR_DIAGNOSTIC_OUTPUT)
        self.assertEqual(retained["testLog"],
                         {"availability": "UNAVAILABLE", "path": "test-smoke.log", "sha256": None})
        self.assertEqual(retained["parseStatus"], "PASS")
        self.assertTrue(retained["zeroUseObserved"])
        self.assertEqual(retained["events"], [])

    def test_successful_checkpoint_retains_all_ordered_diagnostic_events(self):
        fixture = self.fixture()
        (self.path / CI.SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS).unlink()
        diagnostic_transport(self.path, [
            ("00000000-0000-0000-0000-000000000012", [
                diagnostic_line("database"), diagnostic_line("scratch"),
                diagnostic_line("database"),
            ])
        ])
        result = self.verify(fixture)
        evidence = result["simulatorFileProtectionDiagnostics"]
        self.assertEqual(CI.read_json(self.path / CI.SIMULATOR_DIAGNOSTIC_OUTPUT), evidence)
        self.assertEqual([event["kind"] for event in evidence["events"]],
                         ["database", "scratch", "database"])
        self.assertEqual(evidence["eventCount"], 3)
        self.assertFalse(evidence["zeroUseObserved"])
        self.assertFalse(result["providerQualification"])
        self.assertFalse(result["acceptance"])
        self.assertFalse(result["releaseReady"])

    def test_substituted_admission_sdk_runtime_or_simulator_fails(self):
        for name, replacement in (("native-admission.json", "{}"),
                                  ("ci-selection.selected.json", "{}"),
                                  ("native-sdk.txt", "sdk=iphonesimulator\nversion=26.4\nbuild=23F81a\n"),
                                  ("simulator-selection.txt", f"runtime=iOS 26.2\nruntime_build=wrong\nname=iPhone 17\nudid={UDID}\ninitial_state=Shutdown\n")):
            fixture = self.fixture()
            (self.path / name).write_text(replacement)
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.verify(fixture)

    def test_unowned_or_warm_simulator_and_unexpected_ui_fail(self):
        fixture = self.fixture()
        fixture[0]["CI_NATIVE_CREATED_SIMULATOR_UDID"] = "another"
        with self.assertRaises(ValueError):
            self.verify(fixture)
        fixture = self.fixture()
        path = self.path / "simulator-selection.txt"
        path.write_text(path.read_text().replace("Shutdown", "Booted"))
        with self.assertRaises(ValueError):
            self.verify(fixture)
        fixture = self.fixture()
        (self.path / "ui-final.png").write_bytes(b"unexpected")
        with self.assertRaises(ValueError):
            self.verify(fixture)

    def test_cache_provenance_cannot_replace_successful_activation(self):
        fixture = self.fixture("bitrise")
        (self.path / "bitrise-build-cache-activation.log").write_text("activation_exit=1\ncache=true\n")
        with self.assertRaises(ValueError):
            self.verify(fixture)

    def test_named_group_rejects_tampered_map_artifact_before_result_credit(self):
        e = environment()
        e["NATIVE_SELECTION_ID"] = "rating-eligibility"
        selected, record = CI.selected_input(ROOT, e)
        e.update({"DISPATCH_NATIVE_SELECTION_ID": record["selectionID"],
                  "DISPATCH_NATIVE_SELECTION_SHA256": record["selectionSHA256"],
                  "DISPATCH_NATIVE_SELECTION_MAP_SHA256": record["selectionMapSHA256"]})
        CI.admission(selected, e, HEAD, "worker", record)
        (self.path / "native-admission.json").write_bytes(CI.canonical(record))
        (self.path / "ci-selection.selected.json").write_bytes(CI.canonical(selected))
        (self.path / "ci-selection-map.json").write_text("{}\n")
        with self.assertRaises(ValueError):
            CI.verify_checkpoint(ROOT, self.path, record, selected, e)


class WorkflowWiringTests(unittest.TestCase):
    def compact_reference_append(self):
        return ['FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/' + name for name in [
            'testCompactReferenceAuthenticatesSourceAndAllOriginalCurrentFrontiers',
            'testCompactReferenceRejectsCanonicalRecomputedSourceAndFrontierSubstitutions',
            'testCompactReferencePreservesDisposedStateAndSeparateRoundFrontiers',
            'testCompactReferenceSeparatesGraphsAndIgnoresUnrelatedHistory',
            'testCompactReferenceMaximumGraphFitsPayloadBound',
            'testCompactReferenceLongLifecycleKeepsBoundedPayloadAndCompleteHistory',
        ]]

    def durable_initial_begin_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/' + name for name in ['testDurableInitialBeginPersistsRawParentWithoutWorkflowOrBeginEffects', 'testDurableInitialBeginPersistsPreparedBeforeTargetsAndBindsCheck', 'testDurableInitialBeginRecoversSavedTimeZoneBeforeRecheck', 'testDurableInitialBeginRecoversWorkflowAndBoundAcknowledgementLoss', 'testDurableInitialBeginRejectsSourceAdvanceBeforeEitherTargetEffect', 'testDurableInitialBeginRejectsChangedCommandAndForeignWorkflowWithoutEffects', 'testDurableInitialBeginRejectsChangedSiteAndInitialPostimage', 'testDurableInitialBeginColdReopenReusesPreparedAttemptAndOriginalReceipts', 'testDurableInitialBeginUsesOriginalCreationReceiptForContinuationAccess']]

    def prior_durable_begin_pool(self, default):
        self.assertEqual(len(default['unitTestSelectors']), 692)
        self.assertEqual(default['unitTestSelectors'][683:], self.durable_initial_begin_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:683]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '98F484B4B3A4158ADC9B0D289A4C83A88196A0693AEF3782B784B4A26F9F6F42')
        return prior

    def prior_durable_begin_map(self, mapping):
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 110)
        group['methodCount'] = 101
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'A3C6FFF48031FDA76F49E5B644CD5A3461F14888E545F0B6356B92E5E685EAA4')
        return prior

    def test_durable_initial_begin_admission_preserves_every_prior_selector_and_group(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        prior, prior_map = self.prior_durable_begin_pool(default), self.prior_durable_begin_map(mapping)
        appended = self.durable_initial_begin_append()
        source = frozen_begin_suite_source()
        declared = re.findall(r'^    func (test\w+)\(', source, re.M)
        self.assertEqual([name for name in declared if name.startswith('testDurableInitialBegin')],
                         [name.rsplit('/', 1)[1] for name in appended])
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        hostile = copy.deepcopy(default)
        hostile['unitTestSelectors'][0], hostile['unitTestSelectors'][1] = hostile['unitTestSelectors'][1], hostile['unitTestSelectors'][0]
        with self.assertRaises(AssertionError): self.prior_durable_begin_pool(hostile)
        for mutate in (lambda g: g.update(methodCount=109), lambda g: g['classes'].pop(),
                       lambda g: g['classes'].append('V23CheckRunnerFrozenBeginPreparationTests')):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def frozen_begin_writer_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/' + name for name in ['testFrozenBeginWriterCommitsOriginalTimeAndReplaysWithoutEffects', 'testFrozenBeginWriterRecoversSavedTimeZoneBeforeRecheckDraft', 'testFrozenBeginWriterRejectsReceiptBodyTimeAndRevisionChangesWithoutQuarantine', 'testFrozenBeginWriterUsesFreshWorkspaceCASButRejectsStaleTarget', 'testFrozenBeginWriterRejectsMissingOrChangedTimeZoneProofBeforeDraft', 'testFrozenBeginWriterRejectsDirtyAndRetiredSessionsWithoutEffects']]

    def prior_2197d6d_pool(self, default):
        if len(default['unitTestSelectors']) == 692:
            default = self.prior_durable_begin_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 683)
        self.assertEqual(default['unitTestSelectors'][677:], self.frozen_begin_writer_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:677]
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'ED924EF87843A6B7EAE8FEFD272623FB27745708FC6073F2310684549B7B5A4A')
        return prior

    def prior_2197d6d_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] == 110:
            mapping = self.prior_durable_begin_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 101)
        group['methodCount'] = 95
        self.assertEqual(CI.sha256(CI.canonical(prior)), '11970E5F7F8A198F3A4044EE420117D30C014C2749AD49314E510DD68AC3C1FB')
        return prior

    def test_frozen_begin_writer_admission_preserves_every_prior_selector_and_group(self):
        default = self.prior_durable_begin_pool(prepartition_read_json(ROOT / 'Scripts/ci-selection.json'))
        mapping = self.prior_durable_begin_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))
        prior, prior_map = self.prior_2197d6d_pool(default), self.prior_2197d6d_map(mapping)
        appended = self.frozen_begin_writer_append()
        source = frozen_begin_suite_source()
        declared = re.findall(r'^    func (test\w+)\(', source, re.M)
        self.assertEqual([name for name in declared if name.startswith('testFrozenBeginWriter')],
                         [name.rsplit('/', 1)[1] for name in appended])
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        hostile = copy.deepcopy(default)
        hostile['unitTestSelectors'][0], hostile['unitTestSelectors'][1] = hostile['unitTestSelectors'][1], hostile['unitTestSelectors'][0]
        with self.assertRaises(AssertionError): self.prior_2197d6d_pool(hostile)
        for mutate in (lambda g: g.update(methodCount=100), lambda g: g['classes'].pop(),
                       lambda g: g['classes'].append('V23CheckRunnerFrozenBeginPreparationTests')):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def frozen_finalization_revision_append(self):
        return ['FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/' + name for name in ['testFrozenFinalizationRevisionAllowsUnrelatedWorkspaceAdvance', 'testFrozenFinalizationRevisionRejectsStaleAttemptBeforeAnyEffect', 'testFrozenFinalizationReplayRequiresOriginalExpectedRevision', 'testFrozenFinalizationRevisionRejectsInterveningEvidenceAcceptance']]

    def prior_f020a32_pool(self, default):
        if len(default['unitTestSelectors']) in (683, 692):
            default = self.prior_2197d6d_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 677)
        self.assertEqual(default['unitTestSelectors'][673:], self.frozen_finalization_revision_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:673]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '948149139AC3A31E6EE4F7041843A86EBAA5F5C44383808A1EA393FF8891291D')
        return prior

    def prior_f020a32_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (101, 110):
            mapping = self.prior_2197d6d_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 95)
        group['methodCount'] = 91
        self.assertEqual(CI.sha256(CI.canonical(prior)), '6565EB3400B3C07391DAA1B34FC39599FE042EE8D0DE2F769B3A92B758D5608E')
        return prior

    def test_frozen_finalization_revision_admission_preserves_every_prior_selector_and_group(self):
        default = self.prior_2197d6d_pool(prepartition_read_json(ROOT / 'Scripts/ci-selection.json'))
        mapping = self.prior_2197d6d_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))
        prior, prior_map = self.prior_f020a32_pool(default), self.prior_f020a32_map(mapping)
        appended = self.frozen_finalization_revision_append()
        source = (ROOT / 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift').read_text(encoding='utf-8')
        declared = re.findall(r'^    func (test\w+)\(', source, re.M)
        for name in appended:
            self.assertEqual(declared.count(name.rsplit('/', 1)[1]), 1)
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        hostile = copy.deepcopy(default)
        hostile['unitTestSelectors'][0], hostile['unitTestSelectors'][1] = hostile['unitTestSelectors'][1], hostile['unitTestSelectors'][0]
        with self.assertRaises(AssertionError): self.prior_f020a32_pool(hostile)
        for mutate in (
            lambda g: g.update(methodCount=94),
            lambda g: g['classes'].pop(),
            lambda g: g['classes'].append('V9_18PackLifecycleIntegrationTests'),
            lambda g: g['classes'].append('V23CheckRunnerBeginReceiptReferenceTests'),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def commit_reconstruction_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name for name in [
            'testParentCommitReconstructionDerivesExactOutputsForAllSevenOutcomes',
            'testParentCommitReconstructionReusesFrozenSagasAndRowMutationsAfterColdDecode',
            'testParentCommitReconstructionRejectsUnpreparedAndNonCommittingCheckpoints',
            'testParentCommitReconstructionRejectsUnusableTerminalRevisionTimeAndMutation',
            'testParentCommitReconstructionRequiresExactPackageAndPreparedOutcome',
            'testPhotoCommitReconstructionBindsBothStepsAndFrozenReadyStage',
            'testPhotoCommitReconstructionReusesFrozenSagasRowsAndCommandsAfterColdDecode',
            'testPhotoCommitReconstructionRejectsIncompletePhasesAndNonCommittingStates',
            'testPhotoCommitReconstructionRejectsRehashedEnvelopeAndUnusableTerminalInputs',
            'testCommitReconstructionDerivesHashesFromTheEnclosingCheckpointWithoutRewritingPayload',
        ]]

    def prior_29fbcbc_pool(self, default):
        if len(default['unitTestSelectors']) in (677, 683, 692):
            default = self.prior_f020a32_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 673)
        self.assertEqual(default['unitTestSelectors'][663:], self.commit_reconstruction_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:663]
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'BBFBF0FF5B833CDEE3F9124624BEB25510A9C0694EDB5B490862F672DBA62688')
        return prior

    def prior_29fbcbc_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (95, 101, 110):
            mapping = self.prior_f020a32_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 91)
        group['methodCount'] = 81
        self.assertEqual(CI.sha256(CI.canonical(prior)), '8DF851FA1F1FFAB265DF84E4E84E5145EEFEFCF485F33D2E1C9659162295851A')
        return prior

    def test_commit_reconstruction_admission_preserves_prior_pool_map_and_complete_source_class(self):
        default = self.prior_f020a32_pool(prepartition_read_json(ROOT / 'Scripts/ci-selection.json'))
        mapping = self.prior_f020a32_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))
        prior, prior_map = self.prior_29fbcbc_pool(default), self.prior_29fbcbc_map(mapping)
        appended = self.commit_reconstruction_append()
        source = (ROOT / 'FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests.swift').read_text(encoding='utf-8')
        actual = ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name
                  for name in re.findall(r'^    func (test\w+)\(', source, re.M)]
        self.assertEqual(actual, self.parent_field_append() + self.parent_payload_append() + self.child_payload_append() + self.codec_definitions_append() + appended)
        self.assertEqual(len(actual), 49)
        self.assertEqual(len(actual), len(set(actual)))
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        for selectors in (
            [prior['unitTestSelectors'][1], prior['unitTestSelectors'][0]] + prior['unitTestSelectors'][2:] + appended,
            prior['unitTestSelectors'][:5] + appended + prior['unitTestSelectors'][5:],
        ):
            hostile = copy.deepcopy(default); hostile['unitTestSelectors'] = selectors
            with self.assertRaises(AssertionError): self.prior_29fbcbc_pool(hostile)
        for mutate in (
            lambda g: g.update(methodCount=90),
            lambda g: g['classes'].pop(),
            lambda g: g['classes'].append('V23CheckRunnerItemFieldContractsTests'),
            lambda g: g['classes'].append('V23CheckRunnerBeginReceiptReferenceTests'),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def codec_definitions_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name for name in [
            'testCodecDefinitionsBindTheCombinedGrammarAndRequiredPhotoProfile',
            'testCodecPurposeAuthorityRejectsWrongPurposesAndEveryModifiedReleaseComponent',
            'testReleasedCodecsPreservePayloadBytesAndRejectCrossRoleOrNoncanonicalInput',
            'testReleasedCodecLimitsUseCompleteUTF8PayloadBytes',
            'testParentCodecCheckpointBindsPreBeginScopeBaseAndAllSemanticAnchors',
            'testParentCodecRejectsRehashedEnvelopeSubstitutionsAndPhotoRole',
            'testPhotoCodecCheckpointBindsBothStepsAndAllFourDurablePhases',
            'testPhotoCodecRejectsRehashedIdentityScopeBaseAnchorStageAndRoleSubstitutions',
            'testCodecEnvelopeValidationPreservesRecoveryStateWithoutGrantingLifecycleAuthority',
        ]]

    def prior_b0d4f96_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 663)
        self.assertEqual(default['unitTestSelectors'][654:], self.codec_definitions_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:654]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '8C7DD11EAB5F915190B800D2580A7F032572E87C2A8A45AF6D8F19B366904543')
        return prior

    def prior_b0d4f96_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 81)
        group['methodCount'] = 72
        self.assertEqual(CI.sha256(CI.canonical(prior)), '1EC2E66DFA5E0915AABE3ED3D125D1EDDA757349B0E82637C5C7D041050E4ECD')
        return prior

    def test_codec_definitions_admission_preserves_prior_pool_map_and_complete_source_class(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        default, mapping = self.prior_29fbcbc_pool(default), self.prior_29fbcbc_map(mapping)
        prior, prior_map = self.prior_b0d4f96_pool(default), self.prior_b0d4f96_map(mapping)
        appended = self.codec_definitions_append()
        source = (ROOT / 'FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests.swift').read_text(encoding='utf-8')
        actual = ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name
                  for name in re.findall(r'^    func (test\w+)\(', source, re.M)]
        self.assertEqual(actual, self.parent_field_append() + self.parent_payload_append() + self.child_payload_append() + appended + self.commit_reconstruction_append())
        self.assertEqual(len(actual), len(set(actual)))
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        for selectors in (
            [prior['unitTestSelectors'][1], prior['unitTestSelectors'][0]] + prior['unitTestSelectors'][2:] + appended,
            prior['unitTestSelectors'][:5] + appended + prior['unitTestSelectors'][5:],
        ):
            hostile = copy.deepcopy(default); hostile['unitTestSelectors'] = selectors
            with self.assertRaises(AssertionError): self.prior_b0d4f96_pool(hostile)
        for mutate in (
            lambda g: g.update(methodCount=80),
            lambda g: g['classes'].pop(),
            lambda g: g['classes'].append('V23CheckRunnerItemFieldContractsTests'),
            lambda g: g['classes'].append('V23CheckRunnerBeginReceiptReferenceTests'),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def child_payload_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name for name in [
            'testPhotoChildAllFourPhasesRoundTripAcrossRoutesStagesAndSteps',
            'testPhotoChildClosedPhaseGrammarRejectsUnknownMissingAndPrematureValues',
            'testPhotoChildSourceProfileAndInspectionEnforceAllSourceBounds',
            'testPhotoChildValidatesRawStageAndProvenanceValueJoins',
            'testPhotoChildPairBoundsPathsAndDerivativeProfileAreClosed',
            'testPhotoChildPairMarkerBindsParentChildRawAndBothOutputs',
            'testPhotoChildPreparedAttemptPreservesEveryFrozenIdentityAndTime',
            'testPhotoChildPreparedAttemptRejectsAliasesWrongOutputsAndTimeRegressions',
            'testPhotoChildParentCorrespondenceRequiresExactBeginSourceAndSlot',
            'testPhotoChildPreparationTimeBoundariesReuseFrozenInputs',
            'testPhotoChildCanonicalCodecRejectsOversizeNoncanonicalAndNestedUnknownBytes',
            'testPhotoChildCommittedParentRequiresPreparedTerminalValues',
        ]]

    def prior_55e4655_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        if len(default['unitTestSelectors']) == 663:
            default = self.prior_b0d4f96_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 654)
        self.assertEqual(default['unitTestSelectors'][642:], self.child_payload_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:642]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '7AB37216D6F642EFFC2B17D40332A69EEE91D1AA519A77B4E502993C40D2FEE6')
        return prior

    def prior_55e4655_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] == 81:
            mapping = self.prior_b0d4f96_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 72)
        group['methodCount'] = 60
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'C04093189DB621B35A0BE41FEB50277CA7E3C67BD20E914D8F2B2BE46C5CAD8C')
        return prior

    def test_child_payload_admission_preserves_prior_pool_map_and_complete_source_class(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        default, mapping = self.prior_b0d4f96_pool(default), self.prior_b0d4f96_map(mapping)
        prior, prior_map = self.prior_55e4655_pool(default), self.prior_55e4655_map(mapping)
        appended = self.child_payload_append()
        source = (ROOT / 'FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests.swift').read_text(encoding='utf-8')
        actual = ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name
                  for name in re.findall(r'^    func (test\w+)\(', source, re.M)]
        self.assertEqual(actual, self.parent_field_append() + self.parent_payload_append() + appended + self.codec_definitions_append() + self.commit_reconstruction_append())
        self.assertEqual(len(actual), len(set(actual)))
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        for selectors in (
            [prior['unitTestSelectors'][1], prior['unitTestSelectors'][0]] + prior['unitTestSelectors'][2:] + appended,
            prior['unitTestSelectors'][:5] + appended + prior['unitTestSelectors'][5:],
        ):
            hostile = copy.deepcopy(default); hostile['unitTestSelectors'] = selectors
            with self.assertRaises(AssertionError): self.prior_55e4655_pool(hostile)
        for mutate in (
            lambda g: g.update(methodCount=71),
            lambda g: g['classes'].pop(),
            lambda g: g['classes'].append('V23CheckRunnerItemFieldContractsTests'),
            lambda g: g['classes'].append('V23CheckRunnerBeginReceiptReferenceTests'),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def parent_payload_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name for name in [
            'testParentPayloadBeginStatesRoundTripAndBindAllReceiptFields',
            'testParentPayloadRejectsSingleFieldBeginReferenceAndSourceForgeries',
            'testParentPayloadPreservesRawEditableBytesAnchorsAndSlots',
            'testEditingParentPayloadUsesClosedCanonicalPhaseShape',
            'testParentPayloadEnforcesActualTwoMiBBoundaryByEncodedUTF8Bytes',
            'testPreparedParentPayloadValidatesAllSevenOutcomeMediaRowsAgainstShippingRelease',
            'testPreparedParentPayloadRoundTripsAllFrozenValuesWithoutSelfDigests',
            'testPreparedParentPayloadRejectsZeroAliasesAndCausalRegressions',
            'testPreparedParentPayloadRejectsFieldSourceOutcomeProfileDriftAndNestedUnknownKeys',
        ]]

    def prior_1d4a731_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        if len(default['unitTestSelectors']) in (654, 663):
            default = self.prior_55e4655_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 642)
        self.assertEqual(default['unitTestSelectors'][633:], self.parent_payload_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:633]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '63306B8152662442681195637D61DF3800CA6348424BCA29E1CD08677D882E6E')
        return prior

    def prior_1d4a731_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (72, 81):
            mapping = self.prior_55e4655_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 60)
        group['methodCount'] = 51
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'C3043546189762CFBAE83C53A3B418E8C8DBB010C80254773101D8485B46C129')
        return prior

    def test_parent_payload_admission_preserves_prior_pool_map_and_complete_source_class(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        default, mapping = self.prior_55e4655_pool(default), self.prior_55e4655_map(mapping)
        prior, prior_map = self.prior_1d4a731_pool(default), self.prior_1d4a731_map(mapping)
        appended = self.parent_payload_append()
        source = (ROOT / 'FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests.swift').read_text(encoding='utf-8')
        actual = ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name
                  for name in re.findall(r'^    func (test\w+)\(', source, re.M)]
        self.assertEqual(actual, self.parent_field_append() + appended + self.child_payload_append() + self.codec_definitions_append() + self.commit_reconstruction_append())
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        hostile = copy.deepcopy(default)
        hostile['unitTestSelectors'][0], hostile['unitTestSelectors'][1] = hostile['unitTestSelectors'][1], hostile['unitTestSelectors'][0]
        with self.assertRaises(AssertionError): self.prior_1d4a731_pool(hostile)
        for mutate in (
            lambda g: g.update(methodCount=59),
            lambda g: g['classes'].pop(),
            lambda g: g['classes'].append('V23CheckRunnerItemFieldContractsTests'),
            lambda g: g['classes'].append('V23CheckRunnerBeginReceiptReferenceTests'),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def parent_field_append(self):
        return ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name for name in [
            'testAllSixSnapshotsUseShippingResolverAndCheckRecheckMatrix',
            'testSnapshotsHaveExactCanonicalRoundTripAndResolverInverse',
            'testInverseRejectsEveryStaleDisplayKeyVersionAndNoncanonicalNoteClaim',
            'testPrepareProjectsRawNotesWithoutMutatingEditorOrIrrelevantFields',
            'testPendingAndCommittedSlotsValidateExactPurposeAndSameChildReplacement',
            'testTwoSlotsRequireDistinctChildAndEvidenceIdentitiesAndValidLinkage',
            'testClosedSnapshotDecoderRejectsUnknownTagKeyAssociatedMissingAndType',
            'testClosedPhotoSlotDecoderRejectsUnknownTagKeyAssociatedMissingAndType',
            'testAllSemanticAnchorsProduceExactResumeAnchorStrings',
        ]]

    def prior_83def91_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        if len(default['unitTestSelectors']) in (642, 654, 663):
            default = self.prior_1d4a731_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 633)
        self.assertEqual(default['unitTestSelectors'][624:], self.parent_field_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:624]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '84ACB41C376A984B63A084C3D5B6575C9E00FC89DBD483F442F910E73F085468')
        return prior

    def prior_83def91_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (60, 72, 81):
            mapping = self.prior_1d4a731_map(mapping)
        prior = copy.deepcopy(mapping)
        group = next(g for g in prior['groups'] if g['id'] == 'report-camera-recovery')
        self.assertEqual(group['methodCount'], 51)
        self.assertEqual(group['classes'].pop(), 'V23CheckRunnerItemFieldContractsTests')
        group['methodCount'] = 42
        self.assertEqual(CI.sha256(CI.canonical(prior)), '227423ABFFD531551C55711ED7B8307E70D16278D7BEE9E66B21EBB3E7A5205E')
        return prior

    def test_parent_field_admission_preserves_prior_pool_map_and_complete_source_class(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        default, mapping = self.prior_1d4a731_pool(default), self.prior_1d4a731_map(mapping)
        prior, prior_map = self.prior_83def91_pool(default), self.prior_83def91_map(mapping)
        appended = self.parent_field_append()
        source = (ROOT / 'FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests.swift').read_text(encoding='utf-8')
        actual = ['FieldEvidenceAppTests/V23CheckRunnerItemFieldContractsTests/' + name
                  for name in re.findall(r'^    func (test\w+)\(', source, re.M)]
        self.assertEqual(actual, appended + self.parent_payload_append() + self.child_payload_append() + self.codec_definitions_append() + self.commit_reconstruction_append())
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'report-camera-recovery': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]],
                        appended + ['FieldEvidenceAppTests/ForeignTests/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'report-camera-recovery')
        for mutate in (
            lambda g: g.update(methodCount=50),
            lambda g: g['classes'].pop(),
            lambda g: g['classes'].append('V23CheckRunnerItemFieldContractsTests'),
            lambda g: g['classes'].append('V23CheckRunnerBeginReceiptReferenceTests'),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(next(g for g in hostile['groups'] if g['id'] == 'report-camera-recovery'))
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'report-camera-recovery')

    def prior_4977aa4_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        if len(default['unitTestSelectors']) in (633, 642, 654, 663):
            default = self.prior_83def91_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 624)
        self.assertEqual(default['unitTestSelectors'][618:], self.compact_reference_append())
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:618]
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'F5F33EAD1F1FF485A686F60D0EFAB37C012ADDD7953AF55BAB6D3440F3E907F3')
        return prior

    def prior_4977aa4_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (51, 60, 72, 81):
            mapping = self.prior_83def91_map(mapping)
        prior = copy.deepcopy(mapping)
        self.assertEqual(len(prior['groups']), 32)
        self.assertEqual(prior['groups'][-1], {
            'id': 'c36-source-graph', 'classes': ['V23RepetitiveCaptureSourcePackageTests',
                'V23RepetitiveCaptureSourceGraphReviewTests'], 'methodCount': 25})
        prior['groups'][-1]['methodCount'] = 19
        self.assertEqual(CI.sha256(CI.canonical(prior)), '21818651B2031F06DA47DB194A40D6349F28EC380D5740CF0BF5590E5035E876')
        return prior

    def test_compact_reference_admission_preserves_all_prior_methods_and_full_source_pairs(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        default, mapping = self.prior_83def91_pool(default), self.prior_83def91_map(mapping)
        prior, prior_map = self.prior_4977aa4_pool(default), self.prior_4977aa4_map(mapping)
        appended = self.compact_reference_append()
        source = (ROOT / 'FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests.swift').read_text(encoding='utf-8')
        names = re.findall(r'^    func (test\w+)\(', source, re.M)
        self.assertEqual(len(names), 21)
        self.assertEqual(len(names), len(set(names)))
        actual = ['FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/' + n for n in names]
        retained = [s for s in prior['unitTestSelectors'] if '/V23RepetitiveCaptureSourceGraphReviewTests/' in s]
        self.assertEqual(actual, retained + appended)
        for group in mapping['groups']:
            expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
            if group['id'] == 'c36-source-graph': expected['unitTestSelectors'].extend(appended)
            self.assertEqual(CI.resolve_selection(default, mapping, group['id']), expected)
        for changed in (appended[:-1], appended + [appended[0]], appended + ['FieldEvidenceAppTests/Foreign/testForeign']):
            hostile = copy.deepcopy(default)
            hostile['unitTestSelectors'] = prior['unitTestSelectors'] + changed
            with self.assertRaises(ValueError): CI.resolve_selection(hostile, mapping, 'c36-source-graph')
        hostile_map = copy.deepcopy(mapping)
        hostile_map['groups'][-1]['methodCount'] = 24
        with self.assertRaises(ValueError): CI.resolve_selection(default, hostile_map, 'c36-source-graph')

    def diagnostic_authority_append(self):
        return ['FieldEvidenceAppTests/V9_02FileAuthorityTests/' + name for name in [
            'testSimulatorDiagnosticClassifierRejectsEveryNonexactFact',
            'testSimulatorUnsupportedFileAndDirectoryRemainExplicitAcrossVerification',
            'testOwnedFileKindMatrixIsClosedAndHasExplicitDispositions',
            'testTemporaryFileSystemAppliesAndReadsBackEveryOwnedKind',
            'testRelativePathTraversalAndLinkEscapesFailClosed',
            'testHardLinkedOwnedFileIsRejectedBeforeAttributeMutation',
            'testMissingInvalidTypeAndAuthorityOrderingFailClosed',
            'testJournalMediaReportAndDiagnosticsKindsUseTargetedPolicy',
            'testOptionalSQLiteSidecarVerificationRejectsDanglingLinks',
        ]]

    def prior_d97bc81_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        if len(default['unitTestSelectors']) in (624, 633, 642, 654, 663):
            default = self.prior_4977aa4_pool(default)
        self.assertEqual(len(default['unitTestSelectors']), 618)
        prior = copy.deepcopy(default)
        prior['unitTestSelectors'] = prior['unitTestSelectors'][:590]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '81E40479A5C2F9CEDE66FA167BA542EA375AB317CD5F1C7A6B7D688153978603')
        return prior

    def prior_d97bc81_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        if mapping['groups'][-1]['methodCount'] == 25:
            mapping = self.prior_4977aa4_map(mapping)
        prior = copy.deepcopy(mapping)
        self.assertEqual(len(prior['groups']), 32)
        self.assertEqual(prior['groups'].pop(), {
            'id': 'c36-source-graph', 'classes': ['V23RepetitiveCaptureSourcePackageTests',
                'V23RepetitiveCaptureSourceGraphReviewTests'], 'methodCount': 19})
        catalog = next(g for g in prior['groups'] if g['id'] == 'catalog-file-authority')
        self.assertEqual(catalog['methodCount'], 26)
        catalog['methodCount'] = 17
        self.assertEqual(CI.sha256(CI.canonical(prior)), '0D2DC926B9DFA19394FC55039E22FEAA4576A1899CD36F658150572071555838')
        return prior

    def prior_d97bc81_workflow(self, workflow):
        workflow = prepartition_workflow(workflow)
        self.assertEqual(workflow.count('          - c36-source-graph\n'), 1)
        prior = workflow.replace('          - c36-source-graph\n', '').replace(
            'all 618 methods across 32 bounded groups', 'all 590 methods across 31 bounded groups')
        self.assertEqual(CI.sha256(prior.encode()), '198044448ECA007328282839AB8F8BE5B9EFAB7CED7C2171F49D24897B6C8ED3')
        return prior

    def test_simulator_and_source_graph_admission_retains_exact_prior_and_full_pairs(self):
        default = prepartition_read_json(ROOT / 'Scripts/ci-selection.json')
        mapping = prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)
        default, mapping = self.prior_4977aa4_pool(default), self.prior_4977aa4_map(mapping)
        prior, prior_map = self.prior_d97bc81_pool(default), self.prior_d97bc81_map(mapping)
        workflow = (ROOT / '.github/workflows/ios-ci.yml').read_text(encoding='utf-8')
        self.prior_d97bc81_workflow(workflow)
        authority, graphs = self.diagnostic_authority_append(), []
        for klass, count in [('V23RepetitiveCaptureSourcePackageTests', 4),
                             ('V23RepetitiveCaptureSourceGraphReviewTests', 15)]:
            source = (ROOT / 'FieldEvidenceAppTests' / (klass + '.swift')).read_text(encoding='utf-8')
            names = re.findall(r'^    func (test\w+)\(', source, re.M)
            names = [name for name in names if 'FieldEvidenceAppTests/' + klass + '/' + name
                     not in self.compact_reference_append()]
            self.assertEqual(len(names), count)
            self.assertEqual(len(names), len(set(names)))
            graphs.extend('FieldEvidenceAppTests/' + klass + '/' + name for name in names)
        self.assertEqual(default['unitTestSelectors'], prior['unitTestSelectors'] + authority + graphs)
        for selector in authority + graphs:
            bundle, klass, method = selector.split('/')
            source = (ROOT / bundle / (klass + '.swift')).read_text(encoding='utf-8')
            self.assertEqual(len(re.findall(r'\bfunc\s+' + re.escape(method) + r'\s*\(', source)), 1)
        choice_field = prepartition_workflow(workflow).split('      native_selection_id:\n', 1)[1].split(
            '      s10_4_minimum_core_smoke_id:', 1)[0]
        choices = [line.strip()[2:] for line in choice_field.splitlines() if line.startswith('          - ')]
        self.assertEqual(choices, [mapping['defaultSelectionID']] + [g['id'] for g in mapping['groups']])
        for group in mapping['groups']:
            selected = CI.resolve_selection(default, mapping, group['id'])
            if group['id'] == 'c36-source-graph':
                expected = {**prior, 'unitTestSelectors': graphs}
            else:
                expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
                if group['id'] == 'catalog-file-authority': expected['unitTestSelectors'].extend(authority)
            self.assertEqual(selected, expected)
        for mutate in (
            lambda m: m['groups'].pop(),
            lambda m: m['groups'].append(copy.deepcopy(m['groups'][-1])),
            lambda m: m['groups'][-1].update(id='foreign-graph'),
            lambda m: m['groups'][-1].update(methodCount=18),
            lambda m: m['groups'][-1]['classes'].reverse(),
            lambda m: m['groups'][-2].update(methodCount=29),
        ):
            hostile = copy.deepcopy(mapping); mutate(hostile)
            with self.assertRaises(ValueError): CI.resolve_selection(default, hostile, 'c36-source-graph')

    def prior_aa94e7f_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        if len(default['unitTestSelectors']) in (618, 624, 633, 642, 654, 663):
            default = self.prior_d97bc81_pool(default)
        self.assertEqual(len(default["unitTestSelectors"]), 590)
        prior = copy.deepcopy(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:560]
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'D4F805826CA5F12715A8D8426792874178BB101821F172BD89FE2DB1154538B6')
        return prior

    def prior_aa94e7f_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        if len(mapping['groups']) == 32:
            mapping = self.prior_d97bc81_map(mapping)
        prior = copy.deepcopy(mapping)
        self.assertEqual(len(prior["groups"]), 31)
        self.assertEqual(prior["groups"][-1], {'id': 'c36-restore-correspondence', 'classes': ['V23CheckRunnerRestoreCorrespondenceTests', 'V23CheckRunnerRestoreBeginCorrespondenceTests', 'V23CheckRunnerBeginReceiptReferenceTests'], 'methodCount': 30})
        del prior["groups"][-1]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '73DFB5EE3FAE668F41E15B8888562098619066A77DED904164C5857D24F01FFD')
        return prior

    def test_c36_correspondence_admission_preserves_prior_pool_map_and_shared_chain_pairs(self):
        workflow = self.prior_d97bc81_workflow((ROOT / '.github/workflows/ios-ci.yml').read_text(encoding='utf-8'))
        self.assertEqual(workflow.count('          - c36-restore-correspondence\n'), 1)
        prior_workflow = workflow.replace('          - c36-restore-correspondence\n', '').replace(
            'all 590 methods across 31 bounded groups', 'all 426 methods across 30 bounded groups')
        self.assertEqual(CI.sha256(prior_workflow.encode()), '468D3740CDAF6866AD8214C0D5C21BB61EE2AEA25EE0FA01DB63AE9A5DD1F846')
        default = self.prior_d97bc81_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))
        mapping = self.prior_d97bc81_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))
        choice_field = workflow.split('      native_selection_id:\n', 1)[1].split(
            '      s10_4_minimum_core_smoke_id:', 1)[0]
        choices = [line.strip()[2:] for line in choice_field.splitlines()
                   if line.startswith('          - ')]
        self.assertEqual(choices, [mapping['defaultSelectionID']]
                         + [group['id'] for group in mapping['groups']])
        prior = self.prior_aa94e7f_pool(default)
        prior_map = self.prior_aa94e7f_map(mapping)
        methods = {'V23CheckRunnerRestoreCorrespondenceTests': ['testAllIdentityKindsUseFixedNamespacesAndLiteralForkVectors', 'testActualRestoreDecisionModesProduceOnlyTheAuthorizedIdentityDisposition', 'testCanonicalSortingDigestRoundTripCoverageAndBidirectionalLookup', 'testConstructorsDeclaredCoverageAndLookupMissesFailClosed', 'testClosedCanonicalDecodingRejectsMalformedKeysAndRehashedSemanticAttacks'], 'V23CheckRunnerRestoreBeginCorrespondenceTests': ['testDependencyStateSeparatesPresenceFromZeroAndMaximumRevision', 'testDependencyStateRejectsInvalidDigestAndHostileClosedShapes', 'testDestinationDependencyRetainsIndependentStatesAndValidatesMappingRoles', 'testDestinationDependencyRejectsKindsNestedIdentityCorruptionAndUnknownKeys', 'testExpectedSourceEvidenceRoundTripsAuthenticCanonicalHistoryWithoutLosingProvenance', 'testExpectedSourceEvidenceRejectsForeignKeyMalformedMismatchAndNoncanonicalBytes', 'testDestinationBindingPreservesSourceBytesAndMapsOnlyOperationalMutationIDs', 'testDestinationBindingRequiresExactDependencyCardinalityAndPresentReferents', 'testDestinationBindingRejectsTimeZoneOptionalAndBasisDivergence', 'testDestinationBindingClosedDecodeAndFullCorrespondenceRejectHostileChanges', 'testBeginMutationCorrespondenceCoversEveryModeAndBothRolesWithWrappedHashes', 'testBeginMutationExactEvidenceRequiresFrozenRevisionSubsetAndAllowsUnrelatedRows', 'testBeginMutationFreshSourceReadSeparatesSameKeyCandidateFromExactEquality', 'testBeginMutationDestinationEvidenceAuthenticatesEveryReferenceField', 'testBeginMutationTimeZoneAbsenceRejectsDiscardedProvidedHistory', 'testBeginMutationClosedDecodeRejectsHostileRoleKeysHashesTimesAndReferences', 'testParentChildCorrespondenceCanonicalizesDependencyUnionAndDigestInEveryMode', 'testParentChildCorrespondenceRejectsParallelMapBindingSourceAndDigestDrift', 'testParentChildCorrespondencePhaseValidationIsStrictlyShapeBased', 'testChildCheckpointCorrespondenceDerivesExactProjectionAndPreservesHistoricalRevision', 'testChildTargetReceiptCorrespondenceBindsResultDigestAndOriginalTimes', 'testParentChildCorrespondenceRejectsChildCollisionsAndClonePublishesNoOperationalValue'], 'V23CheckRunnerBeginReceiptReferenceTests': ['testBothBeginRolesDeriveEveryReferenceFieldFromOriginalReceipt', 'testShapeValidSubstitutionsCannotReplaceExactBeginProvenance', 'testClosedReferenceRejectsMalformedShapeAndNestedIdentityKeys']}
        appended = ['FieldEvidenceAppTests/' + klass + '/' + method
                    for klass, names in methods.items() for method in names]
        self.assertEqual(len(appended), 30)
        self.assertEqual(default['unitTestSelectors'], prior['unitTestSelectors'] + appended)
        for klass, names in methods.items():
            source = (ROOT / 'FieldEvidenceAppTests' / (klass + '.swift')).read_text(encoding='utf-8')
            self.assertEqual(re.findall(r"\bfunc\s+(test\w+)\s*\(", source), names)
        self.assertEqual({k: v for k, v in default.items() if k != 'unitTestSelectors'},
                         {k: v for k, v in prior.items() if k != 'unitTestSelectors'})
        for group in mapping['groups']:
            with self.subTest(group=group['id']):
                actual = CI.resolve_selection(default, mapping, group['id'])
                if group['id'] == 'c36-restore-correspondence':
                    expected = copy.deepcopy(default)
                    expected['unitTestSelectors'] = appended
                else:
                    expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
                if group['id'] == 'capture-payload-codec':
                    self.assertEqual(len(actual['unitTestSelectors']), 20)
                    self.assertEqual(sum('/V23RepetitiveCaptureProgressDraftPayloadV2Tests/' in x
                                         for x in actual['unitTestSelectors']), 13)
                self.assertEqual(actual, expected)

        for mutate in (
            lambda m: m['groups'].pop(),
            lambda m: m['groups'].append(copy.deepcopy(m['groups'][-1])),
            lambda m: m['groups'][-1].update(id='foreign-correspondence'),
            lambda m: m['groups'][-1].update(methodCount=29),
            lambda m: m['groups'][-1]['classes'].reverse(),
        ):
            hostile = copy.deepcopy(mapping)
            mutate(hostile)
            with self.assertRaises(ValueError):
                CI.resolve_selection(default, hostile, 'c36-restore-correspondence')

    def prior_63409d1_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        self.assertEqual(len(default["unitTestSelectors"]), 560)
        prior = copy.deepcopy(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:554]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '8751EF4B036EB35E6D1FD91C83A13287EC8C62F9FC96F35D435CBD58720EFC14')
        return prior

    def prior_63409d1_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = copy.deepcopy(mapping)
        self.assertEqual(len(prior["groups"]), 30)
        group = next(g for g in prior["groups"] if g["id"] == 'report-camera-recovery')
        self.assertEqual(group["methodCount"], 42)
        self.assertEqual(group["classes"].pop(), 'V23CheckRunnerFrozenBeginPreparationTests')
        group["methodCount"] = 36
        self.assertEqual(CI.sha256(CI.canonical(prior)), '43DAE7A70FFF7713ABB0F27F2A2D32FF88F3F09B1BEB8713804020B2146819E2')
        return prior

    def test_frozen_begin_preparation_preserves_exact_prior_pool_map_and_pairs(self):
        default = self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))
        mapping = self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))
        prior = self.prior_63409d1_pool(default)
        prior_map = self.prior_63409d1_map(mapping)
        methods = ['testCaptureSourceUsesAuthenticatedEntryAndClosedCanonicalRoundTripWithoutEffects', 'testPrepareCheckFreezesStoredZoneCompleteCommandAndSourceCASWithoutEffects', 'testPrepareRecheckFreezesExplicitIssueParentAndOptionalZoneCommandWithoutEffects', 'testInvalidPreflightRequestPackageAndAccessAllocateNoIDsOrEffects', 'testChangedSourceForeignOwnerDirtyContextCompatibilityAndInvalidSessionFailWithoutPreparationEffects', 'testFrozenContractsRejectMalformedClosedBytesAndEncodeNoDestinationAuthority']
        appended = ['FieldEvidenceAppTests/V23CheckRunnerFrozenBeginPreparationTests/' + method for method in methods]
        self.assertEqual(default['unitTestSelectors'], prior['unitTestSelectors'] + appended)
        source = frozen_begin_suite_source()
        self.assertEqual(re.findall(r"\bfunc\s+(test\w+)\s*\(", source), methods + [name.rsplit("/", 1)[1] for name in self.frozen_begin_writer_append() + self.durable_initial_begin_append()])
        self.assertEqual({k: v for k, v in default.items() if k != 'unitTestSelectors'},
                         {k: v for k, v in prior.items() if k != 'unitTestSelectors'})
        for group in mapping['groups']:
            with self.subTest(group=group['id']):
                actual = CI.resolve_selection(default, mapping, group['id'])
                expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
                if group['id'] == 'report-camera-recovery':
                    expected['unitTestSelectors'].extend(appended)
                self.assertEqual(actual, expected)

    def prior_d3be307_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        self.assertEqual(len(default["unitTestSelectors"]), 554)
        prior = copy.deepcopy(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:547]
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'B3C4F982514ABB0AE884F001DEED4748DFAE8ADB5BC0110A67DCB2E5DB3D3B52')
        return prior

    def prior_d3be307_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = copy.deepcopy(mapping)
        self.assertEqual(len(prior["groups"]), 30)
        group = next(g for g in prior["groups"] if g["id"] == 'report-camera-recovery')
        self.assertEqual(group["methodCount"], 36)
        self.assertEqual(group["classes"].pop(), 'V23CheckRunnerBeginHistoryTests')
        group["methodCount"] = 29
        self.assertEqual(CI.sha256(CI.canonical(prior)), '019B1D20AD36A0D782027EED7F803B303968FED681A5B18E871F765BB5A32963')
        return prior

    def test_begin_history_admission_preserves_exact_prior_pool_map_and_pairs(self):
        default = self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json")))
        mapping = self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH)))
        prior = self.prior_d3be307_pool(default)
        prior_map = self.prior_d3be307_map(mapping)
        methods = ['testShippingBeginReturnsExactTimeZoneAndDraftHistoryWithoutCollapsingRevisionSnapshot', 'testExplicitWorkspaceNamespaceDistinguishesSameMutationIDAndReturnsAbsence', 'testDirtyContextDeniesHistoricalPresenceWithoutChangingRows', 'testInvalidatedWriterDeniesHistoricalRead', 'testSelectedQuarantineDeniesHistoricalPresenceWithoutChangingHistory', 'testWholeJournalCorruptionDeniesSelectedPresenceAndAbsenceWithoutWriting', 'testTypedEvidenceRejectsUnsupportedMismatchedAndGenericValidWrongEffects']
        appended = ['FieldEvidenceAppTests/V23CheckRunnerBeginHistoryTests/' + method for method in methods]
        self.assertEqual(default['unitTestSelectors'], prior['unitTestSelectors'] + appended)
        source = (ROOT / 'FieldEvidenceAppTests/V23CheckRunnerBeginHistoryTests.swift').read_text(encoding='utf-8')
        self.assertEqual(re.findall(r"\bfunc\s+(test\w+)\s*\(", source), methods)
        self.assertEqual({k: v for k, v in default.items() if k != 'unitTestSelectors'},
                         {k: v for k, v in prior.items() if k != 'unitTestSelectors'})
        for group in mapping['groups']:
            with self.subTest(group=group['id']):
                actual = CI.resolve_selection(default, mapping, group['id'])
                expected = copy.deepcopy(CI.resolve_selection(prior, prior_map, group['id']))
                if group['id'] == 'report-camera-recovery':
                    expected['unitTestSelectors'].extend(appended)
                self.assertEqual(actual, expected)

    def prior_bf6_stock_method_inventory(self, declared):
        self.assertEqual(declared, ['testPublicReplacementAndColdReadbackPreserveEmptyIncomingOverEmptyStock', 'testPublicReplacementAndColdReadbackRemoveNonemptyCurrentStockForEmptyIncoming', 'testPublicReplacementAndColdReadbackPreserveMixedIncomingOriginalHistory', 'testCurrentRecordsProjectEmptyAndNonemptyC55SnapshotsWithoutWritesAndRejectForeignRows', 'testPopulatedC55CanonicalBackupRoundTripsNumericDatesAndRejectsStringDates', 'testC52IdentityPolicyRejectsForeignEmptyC55AndAcceptsRestoredTargetProjection', 'testDeletionWinningPlanAcceptsDeclaredC55SchemasAndRejectsMalformedAuthority', 'testActorSnapshotRequiresExistingPartyButAcceptsExplicitUnlinkedActor', 'testAlternatingC49C55ProjectionIsDeterministicAndRetainsUnrelatedCurrentWork', 'testReceiptIdentityExportOrderAndShuffleUseGlobalRevisionOrder', 'testForeignRawMutationIDCollisionUsesActiveSourceKindAndPreservesRecord', 'testOriginalMembershipAndBindingHostilesFailBeforeProjection', 'testIncomingOtherFamilyOriginalsAndCausalTargetHistoryArePreserved'])
        prior = [name for name in declared if name not in ['testPopulatedC55CanonicalBackupRoundTripsNumericDatesAndRejectsStringDates', 'testC52IdentityPolicyRejectsForeignEmptyC55AndAcceptsRestoredTargetProjection']]
        self.assertEqual(prior, ['testPublicReplacementAndColdReadbackPreserveEmptyIncomingOverEmptyStock', 'testPublicReplacementAndColdReadbackRemoveNonemptyCurrentStockForEmptyIncoming', 'testPublicReplacementAndColdReadbackPreserveMixedIncomingOriginalHistory', 'testCurrentRecordsProjectEmptyAndNonemptyC55SnapshotsWithoutWritesAndRejectForeignRows', 'testDeletionWinningPlanAcceptsDeclaredC55SchemasAndRejectsMalformedAuthority', 'testActorSnapshotRequiresExistingPartyButAcceptsExplicitUnlinkedActor', 'testAlternatingC49C55ProjectionIsDeterministicAndRetainsUnrelatedCurrentWork', 'testReceiptIdentityExportOrderAndShuffleUseGlobalRevisionOrder', 'testForeignRawMutationIDCollisionUsesActiveSourceKindAndPreservesRecord', 'testOriginalMembershipAndBindingHostilesFailBeforeProjection', 'testIncomingOtherFamilyOriginalsAndCausalTargetHistoryArePreserved'])
        return prior

    def prior_bf6a1bc_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        prior = copy.deepcopy(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:535]
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'FFFD1AC00969457253334D778FFAD6159D52EC0C6CF47772A77094B3B3D6AB12')
        return prior

    def prior_bf6a1bc_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = copy.deepcopy(mapping)
        self.assertEqual(len(prior["groups"]), 30)
        for group_id, old_count, new_count, klass in [('archive-contracts', 44, 47, 'V23StoreSemanticValidationTests'), ('mutation-command-codec', 32, 34, None), ('report-camera-recovery', 22, 29, 'V23CheckRunnerEditableFieldValuesTests')]:
            group = next(g for g in prior["groups"] if g["id"] == group_id)
            self.assertEqual(group["methodCount"], new_count)
            group["methodCount"] = old_count
            if klass is not None:
                self.assertEqual(group["classes"].pop(), klass)
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'D4EE2F55B57E568CA60623460476943EB2D146800712D1F5710AA05832CE7671')
        return prior

    def test_bf6_semantic_validation_stock_and_editable_fields_preserve_prior_pool_and_map(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        prior = self.prior_bf6a1bc_pool(default)
        prior_map = self.prior_bf6a1bc_map(mapping)
        fields, stock, semantic = ['FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testAllSelectionCasesHaveLiveInverseAndExactCanonicalBytes', 'FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testClosedDecodingRejectsUnknownAssociatedMissingTagChoiceAndTypes', 'FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testRawEditableStringsRoundTripWithoutBlanketFieldCapsOrNormalization', 'FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testPreflightDefaultsAndIncumbentSnapshotInitialValuesRemainExact', 'FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testIncumbentInitialAndPrimaryCategoryTraceMatchesEditableValue', 'FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testIncumbentCouldNotVerifyCallbacksPreserveHighlightAndRawOverflow', 'FieldEvidenceAppTests/V23CheckRunnerEditableFieldValuesTests/testEveryIncumbentRecheckNoteCallbackIncludingIrrelevantAndNilSelection'], ['FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testPopulatedC55CanonicalBackupRoundTripsNumericDatesAndRejectsStringDates', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testC52IdentityPolicyRejectsForeignEmptyC55AndAcceptsRestoredTargetProjection'], ['FieldEvidenceAppTests/V23StoreSemanticValidationTests/testCurrentV53ValidationTraversesEveryLayerWithoutRetainingPredecessorBytesAndColdReopens', 'FieldEvidenceAppTests/V23StoreSemanticValidationTests/testEarlyAndLatestCanonicalRowCorruptionKeepTypedFailureAndColdOpenTargetMismatchWithoutRepair', 'FieldEvidenceAppTests/V23StoreSemanticValidationTests/testLowReleaseCanonicalProjectionsRetainExactNestedPredecessorBytes']
        self.assertEqual(default["unitTestSelectors"], prior["unitTestSelectors"] + fields + stock + semantic)
        changed = {"archive-contracts": (semantic, 47),
                   "mutation-command-codec": (stock, 34),
                   "report-camera-recovery": (fields, 29)}
        for group in mapping["groups"]:
            selected = CI.resolve_selection(default, mapping, group["id"])
            original = CI.resolve_selection(prior, prior_map, group["id"])
            if group["id"] in changed:
                appended, count = changed[group["id"]]
                self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + appended)
                self.assertEqual(len(selected["unitTestSelectors"]), count)
                for key in selected:
                    if key != "unitTestSelectors":
                        self.assertEqual(selected[key], original[key])
            else:
                self.assertEqual(selected, original)
        for klass, expected in (("V23CheckRunnerEditableFieldValuesTests", fields),
                                ("V23StoreSemanticValidationTests", semantic)):
            source = (ROOT / "FieldEvidenceAppTests" / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(re.findall(r"^    func (test\w+)\(", source, re.M),
                             [s.rsplit("/", 1)[1] for s in expected])
        for selector in fields + stock + semantic:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_b69a7ed_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        prior = self.prior_bf6a1bc_pool(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:524]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '8E4C8E00E1368725B0298AEA9348D588642AACC47E80B9B482E15B55AA772515')
        return prior

    def prior_b69a7ed_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_bf6a1bc_map(mapping)
        self.assertEqual(len(prior["groups"]), 30)
        archive = next(g for g in prior["groups"] if g["id"] == "archive-contracts")
        self.assertEqual(archive["classes"].pop(), "V23FieldDraftReadyStagePublicationTests")
        for group_id, current, original in (("archive-contracts", 44, 34),
                                           ("app-myday-production", 25, 24)):
            group = next(g for g in prior["groups"] if g["id"] == group_id)
            self.assertEqual(group["methodCount"], current)
            group["methodCount"] = original
        self.assertEqual(CI.sha256(CI.canonical(prior)), 'CB74ED6465F862E761B69A2D7632CA27C321BF9FDAA4FCCF7B24E2FB60750684')
        return prior

    def test_b69_atomic_publication_admission_retains_exact_prior_pool_map_and_pairs(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        prior = self.prior_b69a7ed_pool(default)
        prior_map = self.prior_b69a7ed_map(mapping)
        default = self.prior_bf6a1bc_pool(default)
        mapping = self.prior_bf6a1bc_map(mapping)
        kernel = ['FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testBundleCanonicalRoundTripAndPluralMutationMappingsPreserveIncumbentCase', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testBundleRejectsUnknownSchemaAndMalformedAtomicPairs', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testRealCoordinatorPublishesOnePairAndReplaysAfterSuccessorHotAndCold', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testPublicationReceiptRejectsExtraExpectedAndResultIdentity', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testOccupiedStageStalePredecessorAndDivergentRetryPreserveCommittedPair', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testInjectedFailureAfterStageInsertRollsBackBothRowsAndReceipt', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testReadbackRejectsDirtyContextAndInvalidatedWriter', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testReadbackRejectsSavedMissingHalfAndUnreceiptedPairWithoutWrites', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testAtomicPublicationBackupValidatesRejectsMissingHalvesAndRestoresSameWorkspaceCold', 'FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests/testEveryIncumbentFieldDraftPayloadCaseStillCanonicalRoundTrips']
        myday = ['FieldEvidenceAppTests/V23ProductionMyDayCommitTests/testMyDayAuthorizedDraftWriterRejectsReadyStageBeforeActiveOrRevokedAccessEffects']
        self.assertEqual(default["unitTestSelectors"][524:], kernel + myday)
        for group_id, appended, count in (("archive-contracts", kernel, 44),
                                           ("app-myday-production", myday, 25)):
            selected = CI.resolve_selection(default, mapping, group_id)
            original = CI.resolve_selection(prior, prior_map, group_id)
            self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + appended)
            self.assertEqual(len(selected["unitTestSelectors"]), count)
        for group in mapping["groups"]:
            if group["id"] not in ("archive-contracts", "app-myday-production"):
                self.assertEqual(CI.resolve_selection(default, mapping, group["id"]),
                                 CI.resolve_selection(prior, prior_map, group["id"]))
        source = (ROOT / "FieldEvidenceAppTests/V23FieldDraftReadyStagePublicationTests.swift").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"^    func (test\w+)\(", source, re.M),
                         [s.rsplit("/", 1)[1] for s in kernel])
        for selector in kernel + myday:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_05b38c1_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        prior = self.prior_b69a7ed_pool(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:514]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '49396D1F0A6B5CBB36EB9965E26B5DE3291F7F550DBF2C4E346A07329C1CD3B8')
        return prior

    def prior_05b38c1_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_b69a7ed_map(mapping)
        self.assertEqual(len(prior["groups"]), 30)
        archive = next(g for g in prior["groups"] if g["id"] == "archive-contracts")
        self.assertEqual(archive["classes"].pop(), "S3_2MediaPipelineTests")
        for group_id, current, original in (("archive-contracts", 34, 25),
                                           ("report-camera-recovery", 22, 21)):
            group = next(g for g in prior["groups"] if g["id"] == group_id)
            self.assertEqual(group["methodCount"], current)
            group["methodCount"] = original
        self.assertEqual(CI.sha256(CI.canonical(prior)), '3DB5B3DA2DC0EBDC9595B0DF2F7925580152EF995E6635FCFDA529F382A1C40F')
        return prior

    def test_05b_media_and_precision_admission_preserves_exact_pool_map_and_methods(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        prior = self.prior_05b38c1_pool(default)
        prior_map = self.prior_05b38c1_map(mapping)
        default = self.prior_b69a7ed_pool(default)
        mapping = self.prior_b69a7ed_map(mapping)
        media = ['FieldEvidenceAppTests/S3_2MediaPipelineTests/testSourceInspectionRetainsOriginalFactsAndExactNormalizedOutputs', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testSourceInspectionPreservesInvalidInputFailurePrecedence', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testNormalizerAndStoragePreflightEnforceTheFrozenMediaContract', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testRepresentativeInvalidSourcesFailClosedAndAlphaOrientationNormalize', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testTamperedStagingBundleWithExtraFileFailsPromotionClosed', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testCapacityUnavailableStopsBeforeFilesRowsOrDraftStepMutation', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testWideCloseAcceptanceAndRetakePersistExactRowsStepsAndBundlesAcrossReopen', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testC36AttachmentPreflightAccountsForScratchAndDurableStage', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testV23P03C34SceneResumeDoesNotStartMediaWork']
        precision = ['FieldEvidenceAppTests/S4_5CorrectionTests/testSubmillisecondProductionDateCanonicalizesOnceAndColdRecoveryAcceptsIt']
        self.assertEqual(default["unitTestSelectors"][514:], media + precision)
        for group_id, appended, count in (("archive-contracts", media, 34),
                                           ("report-camera-recovery", precision, 22)):
            selected = CI.resolve_selection(default, mapping, group_id)
            original = CI.resolve_selection(prior, prior_map, group_id)
            self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + appended)
            self.assertEqual(len(selected["unitTestSelectors"]), count)
        for group in mapping["groups"]:
            if group["id"] not in ("archive-contracts", "report-camera-recovery"):
                self.assertEqual(CI.resolve_selection(default, mapping, group["id"]),
                                 CI.resolve_selection(prior, prior_map, group["id"]))
        source = (ROOT / "FieldEvidenceAppTests/S3_2MediaPipelineTests.swift").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"^    func (test\w+)\(", source, re.M),
                         [s.rsplit("/", 1)[1] for s in media])
        for selector in media + precision:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def af2_c55_supplemental_selectors(self):
        return ['FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testCurrentRecordsProjectEmptyAndNonemptyC55SnapshotsWithoutWritesAndRejectForeignRows', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testDeletionWinningPlanAcceptsDeclaredC55SchemasAndRejectsMalformedAuthority', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testActorSnapshotRequiresExistingPartyButAcceptsExplicitUnlinkedActor']

    def prior_af2df5f_pool(self, default):
        if len(default['unitTestSelectors']) in (673, 677, 683, 692):
            default = self.prior_29fbcbc_pool(default)
        prior = self.prior_05b38c1_pool(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:504]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '42333C57BC5A301D897D9C74C39B7A1AD99A70393EE2F155B584A659DA65A333')
        return prior

    def prior_af2df5f_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_05b38c1_map(mapping)
        self.assertEqual(len(prior["groups"]), 30)
        for group_id, current, original in (("mutation-command-codec", 32, 29),
                                             ("report-camera-recovery", 21, 14)):
            group = next(g for g in prior["groups"] if g["id"] == group_id)
            self.assertEqual(group["methodCount"], current)
            group["methodCount"] = original
        self.assertEqual(CI.sha256(CI.canonical(prior)), '1F9A49FB295691F50AB532970D5878C7D6FC5E92C7177A4E5F37CD049DEB2B7A')
        return prior

    def test_af2_corrections_preserve_exact_pool_map_and_complete_resolver_c55_pairs(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        prior = self.prior_af2df5f_pool(default)
        prior_map = self.prior_af2df5f_map(mapping)
        default = self.prior_05b38c1_pool(default)
        mapping = self.prior_05b38c1_map(mapping)
        resolver = ['FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testEditableNoteProjectionPreservesIncumbentRawTextBoundaries', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testEditableNoteProjectionFeedsEveryStrictNoteBearingOutcome', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testOutcomeResolverNormalizesAllShippingAndAlternateOutcomesExactly', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testOutcomeResolverPreservesCheckLabelTrimAndRecheckStrictLabelRules', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testOutcomeResolverAppliesIncumbentCNVAndRecheckNoteBoundaries', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testOutcomeResolverValidatesActualCNVRegistryAndUniqueOutcomeDisplay', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testOutcomeResolverEvaluatesLazyProfileAtEachRequiredLookupAndPreservesErrors']
        c55 = self.af2_c55_supplemental_selectors()
        self.assertEqual(default["unitTestSelectors"][504:], resolver + c55)
        for group_id, appended, count in (("report-camera-recovery", resolver, 21),
                                           ("mutation-command-codec", c55, 32)):
            selected = CI.resolve_selection(default, mapping, group_id)
            original = CI.resolve_selection(prior, prior_map, group_id)
            self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + appended)
            self.assertEqual(len(selected["unitTestSelectors"]), count)
        for group in mapping["groups"]:
            if group["id"] not in ("report-camera-recovery", "mutation-command-codec"):
                self.assertEqual(CI.resolve_selection(default, mapping, group["id"]),
                                 CI.resolve_selection(prior, prior_map, group["id"]))
        resolver_source = (ROOT / "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift").read_text(encoding="utf-8")
        declared = re.findall(r"^    func (test(?:OutcomeResolver|EditableNoteProjection)\w+)\(", resolver_source, re.M)
        self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in resolver])
        c55_source = (ROOT / "FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests.swift").read_text(encoding="utf-8")
        declared = re.findall(r"^    func (test\w+)\(", c55_source, re.M)
        declared = self.prior_bf6_stock_method_inventory(declared)
        original = [s.rsplit("/", 1)[1] for s in prior["unitTestSelectors"]
                    if CI.selection_class(s) == "V23PartsStockReplacementHistoryTests"]
        self.assertEqual(len(original), 8)
        self.assertEqual(declared, original[:3] + [s.rsplit("/", 1)[1] for s in c55] + original[3:])
        for selector in resolver + c55:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_47d433e_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_af2df5f_map(mapping)
        group = next(g for g in prior["groups"] if g["id"] == "report-camera-recovery")
        self.assertEqual(group["methodCount"], 14)
        self.assertEqual(group["classes"].pop(), "V9_18PackLifecycleIntegrationTests")
        group["methodCount"] = 3
        self.assertEqual(CI.sha256(CI.canonical(prior)), '0E5745A8430315B2C09B1382ACEB2EA8244EE27ABA5F7860550417CFC3615D88')
        return prior

    def test_finalization_readback_preserves_exact_47d_pool_and_complete_new_methods(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior = copy.deepcopy(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:493]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '3B30E1B98324AEBCDF0B85D2E313680BD7A789A508416C63437A7C790D43C391')
        prior_map = self.prior_47d433e_map(mapping)
        default = self.prior_af2df5f_pool(default)
        mapping = self.prior_af2df5f_map(mapping)
        expected = ['FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testFinalizationWorkflowBranchesMatchNativeOutcomeAndEvidenceRules', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testRealCheckCompletionsBindKnownAndPartialEvidenceOutcomes', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testRealRecheckCompletionsRetainEveryNativeOutcomeAndOriginalHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testReadCommittedFinalizationReturnsActualCheckAndCNVReceiptsWithoutWrites', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testReadCommittedFinalizationCoversEveryRecheckOutcomeAndCurrentEvidenceMembership', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testReadCommittedFinalizationDistinguishesStableAbsenceFromOneSidedAuthority', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testReadCommittedFinalizationRejectsEveryChangedFrozenInputField', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testReadCommittedFinalizationRejectsRetiredWriterAndSurvivesColdReopen', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testReadCommittedFinalizationRejectsSnapshotCorruptionAndRestoresFixtureSafely', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testPackFinalizationReadbackRequiresExactPackageBindingAndDurableReceiptIdentity', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testCleanupFailureAfterSavedEffectReadsActualCommitBeforeAndAfterRecovery']
        self.assertEqual(default["unitTestSelectors"][493:504], expected)
        selected = CI.resolve_selection(default, mapping, "report-camera-recovery")
        original = CI.resolve_selection(prior, prior_map, "report-camera-recovery")
        self.assertEqual(len(original["unitTestSelectors"]), 3)
        self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + expected)
        self.assertEqual(len(selected["unitTestSelectors"]), 14)
        for group_id in ("archive-contracts", "mutation-command-codec"):
            self.assertEqual(CI.resolve_selection(default, mapping, group_id),
                             CI.resolve_selection(prior, prior_map, group_id))
        source = (ROOT / "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift").read_text()
        added = source.split("// MARK: - C36 authenticated finalization readback", 1)[1].split(
            "private enum C47ActivityContractCompatibility_", 1)[0]
        declared = re.findall(r"^    func (test\w+)\(", added, re.M)
        self.assertEqual(len(declared), len(set(declared)))
        self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in expected[3:] + self.frozen_finalization_revision_append()])
        for selector in expected:
            method = selector.rsplit("/", 1)[1]
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_0e90d6c_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_47d433e_map(mapping)
        archive = next(g for g in prior["groups"] if g["id"] == "archive-contracts")
        self.assertEqual(archive["methodCount"], 25)
        self.assertEqual(archive["classes"][-2:], ["V23FieldDraftAsyncCommitTests", "V23BackupManifestMemberTests"])
        archive["classes"] = archive["classes"][:-2]
        archive["methodCount"] = 11
        self.assertEqual(CI.sha256(CI.canonical(prior)), '62BA7A780325B00F54EA9D7DFA8FB46B2F19BB0BF6994A0D4BFD3C8470F5ACC9')
        return prior

    def test_archive_async_admission_preserves_exact_0e_pool_and_complete_pairs(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:479]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), 'D42D177B2983DDC48BF7D906A96C5C8E24BCF7E83E40887BFB317CD217442D65')
        prior_map = self.prior_0e90d6c_map(mapping)
        default = self.prior_05b38c1_pool(default)
        mapping = self.prior_05b38c1_map(mapping)
        expected = ['FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testAsyncTargetSuccessUsesExactReceiptAndOneIncumbentSagaBody', 'FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testContentSuspensionRequiresSameCurrentCommittingCheckpointBeforeFurtherWrites', 'FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testTargetSuspensionRequiresSameCurrentCommittingCheckpointBeforeReadBackOrSagaAdvance', 'FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testAsyncTargetRejectsWrongMutationAndWorkspaceReceiptsBeforeReadBack', 'FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testAsyncTargetSaveThenThrowRetainsEffectAndExactRetryCompletesOnce', 'FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testAsyncTargetCancellationAfterSaveRetainsEffectAndExactRetryCompletesOnce', 'FieldEvidenceAppTests/V23FieldDraftAsyncCommitTests/testSynchronousTargetInitializersPreserveExistingOrderingAndFailureBehavior', 'FieldEvidenceAppTests/V23FieldDraftStageDigestBackupTests/testPublicPackageValidatorAcceptsAsyncTargetReceiptFromExistingWriter', 'FieldEvidenceAppTests/V23BackupManifestMemberTests/testDraftStagingMemberUsesTypedUUIDsAndHonorsSchemaFloor', 'FieldEvidenceAppTests/V23BackupManifestMemberTests/testTemporalOriginalUsesOwnerConstructorAndHonorsSchemaFloor', 'FieldEvidenceAppTests/V23BackupManifestMemberTests/testC05DerivativeOwnerConstructorsAdmitMarkerAndOriginalAtCurrentSchema', 'FieldEvidenceAppTests/V23BackupManifestMemberTests/testTypedMemberPathsAndMIMEsRejectMalformedVariantsWithValidControls', 'FieldEvidenceAppTests/V23BackupManifestMemberTests/testTypedMembersRetainManifestHashOrderTotalSourceAndSchemaPredicates', 'FieldEvidenceAppTests/V23BackupManifestMemberTests/testDecoderRoundTripsTypedMembersAndRejectsUnknownFields']
        self.assertEqual(default["unitTestSelectors"][479:493], expected)
        selected = CI.resolve_selection(default, mapping, "archive-contracts")
        original = CI.resolve_selection(prior_pool, prior_map, "archive-contracts")
        self.assertEqual(len(original["unitTestSelectors"]), 11)
        self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + expected)
        self.assertEqual(len(selected["unitTestSelectors"]), 25)
        for klass in ["V23FieldDraftAsyncCommitTests", "V23BackupManifestMemberTests"]:
            source = (ROOT / "FieldEvidenceAppTests" / (klass + ".swift")).read_text()
            declared = re.findall(r"^    func (test\w+)\(", source, re.M)
            self.assertEqual(len(declared), len(set(declared)))
            self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in expected if CI.selection_class(s) == klass])
        for selector in expected:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_ff8ae4c_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_0e90d6c_map(mapping)
        codec = next(g for g in prior["groups"] if g["id"] == "mutation-command-codec")
        self.assertEqual(codec["methodCount"], 29)
        self.assertEqual(codec["classes"], ["V10_02MutationEnvelopeReceiptTests", "V23FirstSignReceiptClockTests", "V23PartsStockReplacementHistoryTests", "V23PartsStockReplacementProjectionTests"])
        codec["classes"] = codec["classes"][:2]
        codec["methodCount"] = 14
        return prior

    def test_c55_admission_preserves_exact_ff8_pool_and_complete_paired_classes(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:464]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), 'B6F713A9889C43E4C3F82C94A970726678AFB229D80C0FFA04A325F51A583179')
        prior_map = self.prior_ff8ae4c_map(mapping)
        default = self.prior_af2df5f_pool(default)
        mapping = self.prior_af2df5f_map(mapping)
        self.assertEqual(CI.sha256(CI.canonical(prior_map)), 'FF9568F96A872B357D55BBF3DA7DEF0FC152CC6CFACB18B6B5920C278DCA09C4')
        expected = ['FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testPublicReplacementAndColdReadbackPreserveEmptyIncomingOverEmptyStock', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testPublicReplacementAndColdReadbackRemoveNonemptyCurrentStockForEmptyIncoming', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testPublicReplacementAndColdReadbackPreserveMixedIncomingOriginalHistory', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testAlternatingC49C55ProjectionIsDeterministicAndRetainsUnrelatedCurrentWork', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testReceiptIdentityExportOrderAndShuffleUseGlobalRevisionOrder', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testForeignRawMutationIDCollisionUsesActiveSourceKindAndPreservesRecord', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testOriginalMembershipAndBindingHostilesFailBeforeProjection', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testIncomingOtherFamilyOriginalsAndCausalTargetHistoryArePreserved', 'FieldEvidenceAppTests/V23PartsStockReplacementProjectionTests/testProjectsAllMutationCasesAndSnapshotFamiliesDeterministically', 'FieldEvidenceAppTests/V23PartsStockReplacementProjectionTests/testCursorStagesExternalPredecessorAndMatchesOneShotFold', 'FieldEvidenceAppTests/V23PartsStockReplacementProjectionTests/testBindingBoundaryFailsClosed', 'FieldEvidenceAppTests/V23PartsStockReplacementProjectionTests/testSameWorkspaceInvalidOrderAndLossyHistoryAreRejected', 'FieldEvidenceAppTests/V23PartsStockReplacementProjectionTests/testExplicitCatalogBaselinesPreserveStrictlyValidatedValuesAndMissingRevisionOne', 'FieldEvidenceAppTests/V23PartsStockReplacementProjectionTests/testCatalogBaselineProofRejectsMissingForgedMismatchedAndForbiddenFamily', 'FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests/testHistoricReversalBasisRebindPreservesOpaquePlanAndClosesTargetReceipt']
        self.assertEqual(default["unitTestSelectors"][464:479], expected)
        selected = CI.resolve_selection(default, mapping, "mutation-command-codec")
        original = CI.resolve_selection(prior_pool, prior_map, "mutation-command-codec")
        self.assertEqual(len(original["unitTestSelectors"]), 14)
        self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + expected)
        self.assertEqual(len(selected["unitTestSelectors"]), 29)
        for klass in ["V23PartsStockReplacementHistoryTests", "V23PartsStockReplacementProjectionTests"]:
            source = (ROOT / "FieldEvidenceAppTests" / (klass + ".swift")).read_text()
            declared = re.findall(r"^    func (test\w+)\(", source, re.M)
            self.assertEqual(len(declared), len(set(declared)))
            if klass == "V23PartsStockReplacementHistoryTests":
                declared = self.prior_bf6_stock_method_inventory(declared)
                supplemental = [s.rsplit("/", 1)[1] for s in self.af2_c55_supplemental_selectors()]
                self.assertEqual([name for name in declared if name in supplemental], supplemental)
                declared = [name for name in declared if name not in supplemental]
            self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in expected if CI.selection_class(s) == klass])
        for selector in expected:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_f86664a_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_ff8ae4c_map(mapping)
        reference = next(g for g in prior["groups"] if g["id"] == "reference-owner-replacement")
        self.assertEqual(reference["methodCount"], 51)
        self.assertEqual(reference["classes"].pop(), "V23ReferenceOwnerReplacementCommandPlanTests")
        reference["methodCount"] = 40
        return prior

    def test_command_plan_admission_preserves_exact_f86664a_pool_and_map(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:453]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), '41E5A2751BD53DEEE4D968A86016EC278FE88CA9E096E1B992ADEB92EC1AA2A2')
        prior_map = self.prior_f86664a_map(mapping)
        self.assertEqual(CI.sha256(CI.canonical(prior_map)), 'ED133A6747F235ADECE6C4B39A1FBD365C6CF7284D75336BADB480E52CE0D365')
        expected = ['FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testMixedPlanHasExactSourceOrderCoverageAndHistoricalTargets', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testCoverageIsIndependentOfReceiptStorageOrder', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testEmptyAndSingleFamilyPlansRemainExplicit', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testNonselectedAuthenticatedEntryAndFullSourceHistoryRemainExact', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testExternalProducerObligationsRetainAuthenticatedSourceAndSuppliedTarget', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testRejectsMissingForeignAndTargetCollisionProducerBindings', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testAtomicGenerationImagesAndFrontierEvidenceAreExact', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testDependenciesMapExactProducersAndRejectIncompleteExternalProducerCoverage', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testGenuineCausationAndReversalMetadataMapToOneSelectedPredecessor', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testRejectsGenuineForwardCausationAndReversalPair', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testRejectsAuthenticatedCausationToNonselectedGuidedOwner']
        self.assertEqual(default["unitTestSelectors"][453:464], expected)
        selected = CI.resolve_selection(default, mapping, "reference-owner-replacement")
        original = CI.resolve_selection(prior_pool, prior_map, "reference-owner-replacement")
        self.assertEqual(selected["unitTestSelectors"], original["unitTestSelectors"] + expected)
        self.assertEqual(len(selected["unitTestSelectors"]), 51)
        source = (ROOT / "FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests.swift").read_text()
        declared = re.findall(r"^    func (test\w+)\(", source, re.M)
        self.assertEqual(len(declared), len(set(declared)))
        self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in expected])

    def prior_12e5742_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_f86664a_map(mapping)
        archive = next(g for g in prior["groups"] if g["id"] == "archive-contracts")
        self.assertEqual(archive["methodCount"], 11)
        self.assertEqual(archive["classes"].pop(), "V23FieldDraftStageDigestBackupTests")
        archive["methodCount"] = 8
        return prior

    def test_stage_digest_admission_preserves_exact_12e5742_pool_and_map(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:450]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), '37C46812503287DCEE72EAC00EC8A143D8A38CDF058777C96A0C2C75A5C2F4EA')
        prior_map = self.prior_12e5742_map(mapping)
        default = self.prior_05b38c1_pool(default)
        mapping = self.prior_05b38c1_map(mapping)
        self.assertEqual(CI.sha256(CI.canonical(prior_map)), 'FE7FDFCB15875FE158DEB96448028B465087772FC279742A51FA8AEA50A1CD44')
        expected = ['FieldEvidenceAppTests/V23FieldDraftStageDigestBackupTests/testPublicPackageValidatorAcceptsNonemptyProducerStageSHA256Commit', 'FieldEvidenceAppTests/V23FieldDraftStageDigestBackupTests/testContentDigestSubstitutionIsFullyRehashedButRejectedByBothProducersAndPackage', 'FieldEvidenceAppTests/V23FieldDraftStageDigestBackupTests/testSameOriginalBytesWithDifferentCanonicalStageMetadataCannotSatisfyPlan']
        self.assertEqual(default["unitTestSelectors"][450:453], expected)
        selected = CI.resolve_selection(default, mapping, "archive-contracts")
        original = CI.resolve_selection(prior_pool, prior_map, "archive-contracts")
        self.assertEqual(selected["unitTestSelectors"][:11], original["unitTestSelectors"] + expected)
        self.assertEqual(len(selected["unitTestSelectors"]), 25)
        for selector in expected:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_bea52c7_map(self, mapping):
        if next(g for g in mapping['groups'] if g['id'] == 'report-camera-recovery')['methodCount'] in (91, 95, 101, 110):
            mapping = self.prior_29fbcbc_map(mapping)
        prior = self.prior_12e5742_map(mapping)
        app = next(g for g in prior["groups"] if g["id"] == "app-myday-production")
        self.assertEqual(app["methodCount"], 24)
        self.assertEqual(app["classes"].pop(), "V23NativeScreenObservationTests")
        app["methodCount"] = 20
        round_group = next(g for g in prior["groups"] if g["id"] == "round-readiness-production")
        self.assertEqual(round_group["methodCount"], 6)
        round_group["methodCount"] = 5
        return prior

    def test_native_observation_admission_preserves_exact_bea52c7_pool_and_map(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:445]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), 'F075564395571E8C149E7E3FED45D9E769C2BDEE26AF00BC5792F7854EB1AF3A')
        self.assertEqual(CI.sha256(CI.canonical(self.prior_bea52c7_map(mapping))), 'D6E6BDB9DF2430F717C923897D7A57B65C966DFDACF05544784D4A1D73E19859')
        expected = ['FieldEvidenceAppTests/V23NativeScreenObservationTests/testRealSwiftUIBranchMountUnmountAndWindowScope', 'FieldEvidenceAppTests/V23NativeScreenObservationTests/testSelectedTabAndNativeBackRejectRetainedScreens', 'FieldEvidenceAppTests/V23NativeScreenObservationTests/testPresentedNativeControllerMasksCoveredHostAndDismissalRestoresIt', 'FieldEvidenceAppTests/V23NativeScreenObservationTests/testWitnessHasNoLayoutInteractionOrAccessibilityRoleAndClearsOnDismantle', 'FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testReadinessPreFinalHookRejectionDoesNotCarryHookOrWriteIntoNextOperation']
        self.assertEqual(default["unitTestSelectors"][445:450], expected)
        for selector in expected:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)
        default = self.prior_b69a7ed_pool(default)
        mapping = self.prior_b69a7ed_map(mapping)
        app = CI.resolve_selection(default, mapping, "app-myday-production")
        self.assertEqual(app["unitTestSelectors"][-4:], expected[:4])
        round_group = CI.resolve_selection(default, mapping, "round-readiness-production")
        self.assertEqual(round_group["unitTestSelectors"][-1:], expected[-1:])

    def prior_821f_groups(self, mapping, count=17):
        """Retain historical hash proofs after validating the two additive counts."""
        groups = self.prior_bea52c7_map(mapping)["groups"][:17]
        for group_id, current, prior in (("app-myday-production", 20, 13),
                                         ("mutation-command-codec", 14, 13)):
            group = next(item for item in groups if item["id"] == group_id)
            self.assertEqual(group["methodCount"], current)
            group["methodCount"] = prior
        return groups[:count]

    def test_reference_owner_admission_preserves_exact_698_pool_and_adds_complete_classes(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:405]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), '0FAF6BDA92295FE5D342E47DD997079384F4019AC130F91FA1EB797B4DE41122')
        prior_map = self.prior_bea52c7_map(mapping)
        prior_map["groups"] = prior_map["groups"][:29]
        self.assertEqual(CI.sha256(CI.canonical(prior_map)), '13816E50720D2F60B42E54656C02346578953A7D22B9011A5093B57C2B756BE2')
        expected = ['FieldEvidenceAppTests/V23ReferenceOwnerReplacementSourceTests/testAuthenticatedMixedHistoryRetainsExactOriginalsAndOrdersOwnFourFamilies', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementSourceTests/testWrongOwnerMutationAndExpectedFrontierFailClosed', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementSourceTests/testReceiptBodyMismatchAndDuplicateQualifiedMutationFailClosed', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementSourceTests/testRelevantQuarantineIsDeniedAfterSnapshotAuthentication', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testReplacementMutationNamespacesAreDeterministicAndDisjoint', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testReplacementMutationNamespacesBindSourceOwnerAndTargetGeneration', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testProjectsAllSevenPayloadsFromAuthenticatedHistoryWithoutRewritingContent', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testHistoricalManifestLookupUsesExactOlderReferenceDespiteNewerSnapshotFrontier', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testProjectionMapsOnlyRealDependenciesAndRetainsAuthenticatedReceiptOrder', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testProjectedCommandsProduceValidTypedTargetReceiptsAndEquivalentConflictEvidence', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testMissingManifestClaimLeaseAndReleaseDependenciesFailClosed', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testDuplicateHistoricalIdentityAndMappedMutationCollisionFailClosed', 'FieldEvidenceAppTests/V23WorkPacketReplacementCommandProjectionTests/testProjectionRejectsDifferentSourceOwnerAndNonReplacementIdentity', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testFiveReplacementMutationNamespacesAreDeterministicDisjointAndIdentityBound', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testAuthenticatedSourceClassifiesRoundDistinctFromGuidedSurveyAndRetainsForeignHistory', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testSourceRejectsRelevantQuarantineAndTypedRoundReceiptMismatch', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testProjectsCompleteHistoricalTransitionChainAndPreservesLiteralFacts', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testExactOlderAndNewerReferencesResolveDespiteNewerSnapshotFrontierAndRecordOrder', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testMissingDuplicateAndForkedHistoricalPredecessorsFailClosed', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testWrongOwnerAndMappedMutationCollisionFailClosedWhileForeignRoundIsIgnored', 'FieldEvidenceAppTests/V23RoundSessionReplacementCommandProjectionTests/testProjectedCommandsProduceValidTypedTargetReceiptsWithoutStorageClaim']
        expected += ['FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testProjectsAllSixPayloadsWithExactGraphAndAtomicGeneration', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testPreservesLiteralFieldsAndRebindsWorkPacketAndRoundReferences', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testExactHistoricalLookupsIncludeOldReleaseCalendarOverrideAndOccurrenceAnchor', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testEveryProjectedCommandBuildsCanonicalTypedTargetReceipt', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testProjectionIsIndependentOfStoredReceiptOrder', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRejectsMissingExternalBindingsAndWrongIdentity', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testBaselineBindingsAndPluralPromotionDependenciesUseExactReceiptPrefix', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRejectsMissingDuplicateForeignAndCollidingExternalProducerPairs', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testAddedOccurrenceReferencesAndOverrideFrontiersRecomputeFromExactOwners', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testUnknownProvenanceFailsClosedAfterAuthenticatedSourceConstruction', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testAllDaysTimeBasisRemainsLiteralWithTypedTargetReceipts', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRetiredExceptionMapsAddedReplacementAcrossIdentityNamespaces', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testExceptionRecomputesPriorEffectiveDigestAndOverrideProvenance', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testUnknownCompletionAndDifferentSourceProjectionsFailClosed', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRejectsConstructorValidMismatchedEmbeddedHistoricalRelease', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testHistoricalLookupRejectsUnknownDigestAndForeignAnchor', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRejectsRelevantQuarantineAndDuplicateAuthenticatedMutation', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRejectsConstructorValidForkedReleaseHistory', 'FieldEvidenceAppTests/V23ScheduleReplacementCommandProjectionTests/testRejectsMissingCalendarProducerAndDuplicateDefinitionBindings']
        self.assertEqual(default["unitTestSelectors"][405:445], expected)
        expected += ['FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testMixedPlanHasExactSourceOrderCoverageAndHistoricalTargets', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testCoverageIsIndependentOfReceiptStorageOrder', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testEmptyAndSingleFamilyPlansRemainExplicit', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testNonselectedAuthenticatedEntryAndFullSourceHistoryRemainExact', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testExternalProducerObligationsRetainAuthenticatedSourceAndSuppliedTarget', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testRejectsMissingForeignAndTargetCollisionProducerBindings', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testAtomicGenerationImagesAndFrontierEvidenceAreExact', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testDependenciesMapExactProducersAndRejectIncompleteExternalProducerCoverage', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testGenuineCausationAndReversalMetadataMapToOneSelectedPredecessor', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testRejectsGenuineForwardCausationAndReversalPair', 'FieldEvidenceAppTests/V23ReferenceOwnerReplacementCommandPlanTests/testRejectsAuthenticatedCausationToNonselectedGuidedOwner']
        group = mapping["groups"][-1]
        self.assertEqual(group, {'id': 'reference-owner-replacement', 'classes': ['V23ReferenceOwnerReplacementSourceTests', 'V23WorkPacketReplacementCommandProjectionTests', 'V23RoundSessionReplacementCommandProjectionTests', 'V23ScheduleReplacementCommandProjectionTests', 'V23ReferenceOwnerReplacementCommandPlanTests'], 'methodCount': 51})
        resolved = CI.resolve_selection(default, mapping, group["id"])
        self.assertEqual(resolved["unitTestSelectors"], expected)
        for klass in group["classes"]:
            source = (ROOT / "FieldEvidenceAppTests" / (klass + ".swift")).read_text()
            declared = re.findall(r"^    func (test\w+)\(", source, re.M)
            selected = [s.rsplit("/", 1)[1] for s in expected if CI.selection_class(s) == klass]
            self.assertEqual(len(declared), len(set(declared)), klass)
            self.assertEqual(declared, selected, klass)

    def test_schedule_admission_preserves_exact_4d_pool_and_map(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(len(mapping["groups"]), 30)
        prior_pool = copy.deepcopy(default)
        prior_pool["unitTestSelectors"] = prior_pool["unitTestSelectors"][:426]
        self.assertEqual(CI.sha256(CI.canonical(prior_pool)), '3564DC8CCA165D269AC18B2F90F98E7EEF0E1D4C2D6985C72F21536BC99813D1')
        prior_map = self.prior_bea52c7_map(mapping)
        group = prior_map["groups"][-1]
        self.assertEqual(group["id"], "reference-owner-replacement")
        self.assertEqual(group["methodCount"], 40)
        self.assertEqual(group["classes"].pop(), "V23ScheduleReplacementCommandProjectionTests")
        group["methodCount"] = 21
        self.assertEqual(CI.sha256(CI.canonical(prior_map)), '718D0A2573BDE2DCD581DEBF178FD54718387A22560D94E4EC81363A13A71A0F')

    def test_work_round_capture_and_descriptor_admission_preserves_821f_pool(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        self.assertEqual(len(default["unitTestSelectors"]), 547)
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][:298])),
                         "5ABC2B0E9AD06346872CEFE60223FAD2E2AC775AAB2C691A6EAC98F026EDFB0C")
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][298:405])),
                         "BC86EB9A4C01F799C151D7E78281A0B9D6046956C6A8E6C885C57DE2875F24A8")
        prior = copy.deepcopy(mapping)
        prior["groups"] = self.prior_821f_groups(mapping)
        self.assertEqual(CI.sha256(CI.canonical(prior)),
                         "5B20EF37267EC8FC25A5ABB66D025FCA7D5126ECB72913C590C8DEE483ADE75C")
        expected = [
            ("work-asset-production", ["V23ProductionWorkAssetTests"], 5),
            ("round-readiness-production", ["V23ProductionRoundReadinessTests"], 6),
            ("round-draft-ordering", ["V23ProductionRoundDraftOrderingTests"], 7),
            ("round-draft-ordering-presentation", ["V23ProductionRoundDraftOrderingPresentationTests"], 8),
            ("round-session-transition", ["V23ProductionRoundSessionTransitionTests"], 8),
            ("round-session-transition-presentation", ["V23ProductionRoundSessionTransitionPresentationTests"], 6),
            ("round-item-production", ["V23ProductionRoundItemTests"], 8),
            ("capture-progress-production", ["V23ProductionCaptureProgressTests"], 7),
            ("capture-recovery-production", ["V23ProductionCaptureRecoveryTests"], 7),
            ("scene-navigation-production", ["V23ProductionSceneNavigationTests"], 12),
            ("capture-payload-codec", ["V23RepetitiveCaptureDraftPayloadTests",
                                       "V23RepetitiveCaptureProgressDraftPayloadV2Tests"], 20),
            ("store-control-descriptor-ownership", ["V23StoreControlDescriptorOwnershipTests"], 6),
        ]
        self.assertEqual(mapping["groups"][17:29],
                         [dict(id=i, classes=c, methodCount=n) for i, c, n in expected])
        added_classes = {CI.selection_class(s) for s in default["unitTestSelectors"][298:405]}
        for klass in added_classes:
            source = (ROOT / "FieldEvidenceAppTests" / (klass + ".swift")).read_text()
            declarations = re.findall(r"^    func (test\w+)\(", source, re.M)
            selected = [s.rsplit("/", 1)[1] for s in default["unitTestSelectors"]
                        if CI.selection_class(s) == klass]
            self.assertEqual(len(declarations), len(set(declarations)), klass)
            self.assertEqual(set(declarations), set(selected), klass)
        source = (ROOT / "FieldEvidenceAppTests/V23ProductionFourRootShellTests.swift").read_text()
        base = source.split("class V23ProductionFourRootShellTestSupport: XCTestCase {", 1)[1].split(
            "final class V23ProductionFourRootShellTests:", 1)[0]
        self.assertNotRegex(base, r"\bfunc\s+test\w+\(")
        for group_id, _, _ in expected:
            selected = CI.resolve_selection(default, mapping, group_id)
            for key in ("schemaVersion", "taskID", "tier", "runUISmoke", "uiTestSelectors", *CI.BUDGET_KEYS):
                self.assertEqual(selected[key], default[key])
        missing = copy.deepcopy(default)
        missing["unitTestSelectors"].pop()
        with self.assertRaisesRegex(ValueError, "selection group members"):
            CI.resolve_selection(missing, mapping, expected[-1][0])
        override = copy.deepcopy(mapping)
        override["groups"][-1]["selectors"] = [UNIT]
        with self.assertRaisesRegex(ValueError, "selection group shape"):
            CI.resolve_selection(default, override, expected[-1][0])

    def test_required_evidence_extraction_retains_original_literal_body(self):
        body = (ROOT / "Scripts/validate-required-evidence.sh").read_bytes()
        allowed_prefix = (b'selection_path="${CI_SELECTION_PATH:-Scripts/ci-selection.json}"\n'
                          b'case "$selection_path" in\n'
                          b'  Scripts/ci-selection.json | "${CI_ARTIFACT_DIR:?}/ci-selection.selected.json") ;;\n'
                          b"  *) printf 'invalid closed selection path\\n' >&2; exit 65 ;;\n"
                          b'esac\n'
                          b'test -f "$selection_path"\n')
        preserved = body.replace(allowed_prefix, b"", 1).replace(
            b"' \"$selection_path\" > /dev/null", b"' Scripts/ci-selection.json > /dev/null").replace(
            b'"$selection_path" | awk', b'Scripts/ci-selection.json | awk')
        self.assertEqual(CI.sha256(preserved),
                         "76728F2ACA67ED1C77295F5FAF207E2CE3A8192CCE4F0D924B7C9991E6690FAE")
        source = (ROOT / ".github/workflows/ios-ci-worker.yml").read_text()
        self.assertEqual(step(source, "Validate required build and test evidence").strip(),
                         "id: validate_required_evidence\n"
                         "        if: ${{ always() && inputs.s10_4_pilot_mode == false && (inputs.runner_provider != 'bitrise' || inputs.s10_4_segment_id == 'none') }}\n"
                         "        shell: bash\n"
                         "        run: |\n"
                         "          bash --noprofile --norc -e -o pipefail Scripts/validate-required-evidence.sh")

    def test_extracted_required_evidence_is_bound_to_native_source_identity(self):
        relative = "Scripts/validate-required-evidence.sh"
        self.assertEqual(CI.PROTOCOL_PATHS.count(relative), 1)
        original = CI.source_binding(ROOT)
        self.assertEqual(original["protocolSources"][relative],
                         CI.sha256((ROOT / relative).read_bytes()))
        with tempfile.TemporaryDirectory(prefix="v23-native-source-binding-") as directory:
            root = Path(directory)
            for path in (*CI.PROTOCOL_PATHS, "Scripts/ci-selection.json", CI.SELECTION_MAP_PATH,
                         CI.SIMULATOR_DIAGNOSTIC_POLICY_PATH, CI.SIMULATOR_DIAGNOSTIC_SOURCE_PATH):
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / path, target)
            self.assertEqual(CI.source_binding(root), original)
            helper = root / relative
            helper.write_bytes(helper.read_bytes() + b"# source substitution fixture\n")
            changed = CI.source_binding(root)
            self.assertNotEqual(changed["protocolSources"][relative], original["protocolSources"][relative])
            self.assertNotEqual(changed["protocolSHA256"], original["protocolSHA256"])
            helper.unlink()
            with self.assertRaises(ValueError):
                CI.source_binding(root)

    def test_closed_selection_map_partitions_default_without_overrides(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        groups = [CI.resolve_selection(default, mapping, group["id"])
                  for group in mapping["groups"]]
        self.assertEqual(sum(len(group["unitTestSelectors"]) for group in groups), 547)
        self.assertEqual({item for group in groups for item in group["unitTestSelectors"]},
                         set(default["unitTestSelectors"]))
        self.assertEqual(CI.resolve_selection(default, mapping, CI.DEFAULT_SELECTION_ID), default)
        bad = copy.deepcopy(mapping)
        bad["groups"][0]["methodCount"] += 1
        with self.assertRaises(ValueError):
            CI.resolve_selection(default, bad, "notification-controls")
        with self.assertRaises(ValueError):
            CI.resolve_selection(default, mapping, "../../arbitrary")
        overlap = copy.deepcopy(mapping)
        overlap["groups"][0]["classes"].append("V9_15AppLockLifecycleTests")
        overlap["groups"][0]["methodCount"] += mapping["groups"][1]["methodCount"]
        with self.assertRaisesRegex(ValueError, "overlapping selection group"):
            CI.resolve_selection(default, overlap, "notification-controls")
        omission = copy.deepcopy(mapping)
        omission["groups"].pop()
        with self.assertRaises(ValueError):
            CI.resolve_selection(default, omission, "notification-controls")

    def test_app_myday_selection_is_additive_and_preserves_original_partition(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        selected = CI.resolve_selection(default, mapping, "app-myday-production")
        expected = ['FieldEvidenceAppTests/V23ProductionAppAccessTests/testFactorySettingTransactionsCompleteAndReopenWithoutRepair', 'FieldEvidenceAppTests/V23ProductionAppAccessTests/testFactoryKeepsStartupUnopenedAndBindsItsExactGateOnce', 'FieldEvidenceAppTests/V23ProductionFourRootShellTests/testActualNativeShellRestoresEachPersistedRootAndPreservesAcceptedTabIdentities', 'FieldEvidenceAppTests/V23ProductionFourRootShellTests/testActualStartupRestoresReadyReportIntoExistingDetailAndBackPersistsThroughScenePort', 'FieldEvidenceAppTests/V23ProductionMyDayCommitTests/testProductionSavePersistsExactCommitRowsReceiptsAndNoContentReservations', 'FieldEvidenceAppTests/V23ProductionMyDayCommitTests/testPlanningRequiresItsExactGateAndSessionBeforeAnyDraftWrite', 'FieldEvidenceAppTests/V23MyDayPlanningEditorTests/testTodayEditorAddsOrdersEstimatesRemovesAndSavesWithoutChangingSourceWork', 'FieldEvidenceAppTests/V23MyDayPlanningEditorTests/testPostEffectSaveFailureRetainsExactAttemptWithoutPublishingSuccessAndRetriesOnce', 'FieldEvidenceAppTests/V23MyDayPlanningEditorTests/testCarryoverConflictEditorReviewsActualActiveAndPreTargetSavePrefixesThenSavesSameDraft', 'FieldEvidenceAppTests/V23SearchReconciliationTests/testGuardedProjectionDropRejectsRevokedAndWrongConsumerTokensWithoutChangingBytes', 'FieldEvidenceAppTests/V23SearchReconciliationTests/testActualRebuildRevocationBeforeProjectionDropPreservesOldBytesAndFreshRetryCompletes']
        location = 'FieldEvidenceAppTests/V9_08GenerationLeaseTests/testReplacementLocationHistoryRetainsCurrentSchemaValidationAndRejectsInvalidReferences'
        self.assertEqual(selected["unitTestSelectors"][:11], expected)
        self.assertEqual(default["unitTestSelectors"][259:270], expected)
        self.assertEqual(default["unitTestSelectors"][270:271], [location])
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][:259])),
                         "E8F942EDCE2B513FFC66A01BF5D7003FDD885CD8B1F9EDF7F6D38426E1031400")
        historical_groups = self.prior_12e5742_map(mapping)["groups"][:15]
        owner = next(group for group in historical_groups if group["id"] == "notification-owner")
        self.assertEqual(owner["methodCount"], 75)
        owner["methodCount"] = 63
        generation = next(group for group in historical_groups
                          if group["id"] == "generation-leases-migration")
        self.assertEqual(generation["methodCount"], 5)
        generation["methodCount"] = 4
        resolved_generation = CI.resolve_selection(default, mapping, "generation-leases-migration")
        original_generation = [selector for selector in default["unitTestSelectors"][:259]
                               if selector.split("/")[1] in generation["classes"]]
        self.assertEqual(resolved_generation["unitTestSelectors"], original_generation + [location])
        self.assertEqual(CI.sha256(CI.canonical(historical_groups)),
                         "9CFA63307F86B2F88570672F8C4D35348CB97357893F68A37B3A70859224D66D")
        self.assertEqual(len(mapping["groups"]), 30)
        for key in ("schemaVersion", "taskID", "tier", "runUISmoke", "uiTestSelectors", *CI.BUDGET_KEYS):
            self.assertEqual(selected[key], default[key])
        for selector in expected + [location]:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)
        duplicate = copy.deepcopy(mapping)
        duplicate["groups"].append(copy.deepcopy(duplicate["groups"][-1]))
        with self.assertRaisesRegex(ValueError, "selection group count"):
            CI.resolve_selection(default, duplicate, "app-myday-production")

    def test_command_codec_selection_retains_original_pool_and_closed_partition(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        selected = CI.resolve_selection(default, mapping, "mutation-command-codec")
        names = ['testV10_02G01CanonicalEnvelopeReceiptBytesAndAtomicCommit', 'testCanonicalWorkAuthorityRoundTripsAndRequiresOriginalV53Source', 'testCanonicalWorkImportRejectsResealedEnvelopeAndUnchangedSourceRevisionForgery', 'testCanonicalWorkRejectsHostileCommandAndAuthorityBytes', 'testFinalizationLegacyEnvelopeAndSchemaOneIntentRoundTripWithoutWriterBinding', 'testFinalizationSchemaTwoAdmitsMigratedBaselineAndRejectsHostileBindings', 'testReviewedDraftEnvelopeRetainsExactPortableLocksAndCanonicalBytes', 'testMutationEnvelopeByteGateRejectsOversizeBeforeDecodeAndAdmitsBoundaryToDecoder', 'testFinalizationInspectionBindingPreservesAbsentBytesAndRejectsHostileCoding', 'testWorkspaceCommandDecoderDispatchesEveryCaseAndRejectsHostileGrammar', 'testFinalizationCorrectionBindingPreservesCanonicalDecodeAndEncoderReentry']
        expected = ["FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests/" + name for name in names]
        self.assertEqual(selected["unitTestSelectors"][:11], expected)
        self.assertEqual(default["unitTestSelectors"][271:282], expected)
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][:271])), "FEDC559AC2140B8C69C4B37F09E921FCDB60292263969A5E65558AE647647DC5")
        original_groups = self.prior_821f_groups(mapping, 16)
        owner = next(group for group in original_groups if group["id"] == "notification-owner")
        self.assertEqual(owner["methodCount"], 75)
        owner["methodCount"] = 63
        app = next(group for group in original_groups if group["id"] == "app-myday-production")
        self.assertEqual(app["methodCount"], 13)
        app["methodCount"] = 11
        self.assertEqual(CI.sha256(CI.canonical(original_groups)), "A347A6AFB64B7E532720C87FFE17363E3396AC42AC1FB87497BC8647CBA5AF95")
        for key in ("schemaVersion", "taskID", "tier", "runUISmoke", "uiTestSelectors", *CI.BUDGET_KEYS):
            self.assertEqual(selected[key], default[key])
        source = (ROOT / "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift").read_text()
        for name in names:
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(name) + r"\s*\(", source)), 1)

    def test_ingress_regressions_extend_exact_owner_and_preserve_prior_pool(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        names = ['testPhysicalIngressResumedEraseRejectsUnrelatedControlBeforeFrozenEffects', 'testPhysicalIngressFrozenEraseTerminalReplayNeverOpensDeletedPayload', 'testPhysicalIngressResumedEraseRejectsWellFormedMismatchedTerminalBeforeOtherTargetDeletion', 'testPhysicalIngressFrozenEraseRejectsReplacedTargetPayloadBeforeDeletion', 'testPhysicalIngressReplaceAdmitsWholeRootBeforeTargetPayloadHash']
        appended = ["FieldEvidenceAppTests/V9_15AppLockLifecycleTests/" + name for name in names]
        self.assertEqual(default["unitTestSelectors"][282:287], appended)
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][:282])), "28FC5CB6FBA869E43A6BEB6F7080486039AA07DF56AFE1729B146F2E4A02F620")
        selected = CI.resolve_selection(default, mapping, "notification-owner")
        self.assertEqual(len(selected["unitTestSelectors"]), 75)
        self.assertEqual(selected["unitTestSelectors"][63:68], appended)
        self.assertEqual(CI.sha256(CI.canonical(selected["unitTestSelectors"][:63])), "778C7B884583C58410EAC2DA4CC6D462824F01E8AAD72B6E218B0A606509FC4B")
        original_groups = self.prior_821f_groups(mapping)
        owner = next(group for group in original_groups if group["id"] == "notification-owner")
        self.assertEqual(owner["methodCount"], 75)
        owner["methodCount"] = 63
        app = next(group for group in original_groups if group["id"] == "app-myday-production")
        self.assertEqual(app["methodCount"], 13)
        app["methodCount"] = 11
        codec = next(group for group in original_groups if group["id"] == "mutation-command-codec")
        self.assertEqual(codec["classes"], ["V10_02MutationEnvelopeReceiptTests", "V23FirstSignReceiptClockTests"])
        self.assertEqual(codec["methodCount"], 13)
        codec["classes"] = ["V10_02MutationEnvelopeReceiptTests"]
        codec["methodCount"] = 11
        self.assertEqual(CI.sha256(CI.canonical(original_groups)), "BE3B0FDB49FA19ADF3B3ADDED0CE809B9C6961F36180D1C416C5BEB551E0C027")
        for key in ("schemaVersion", "taskID", "tier", "runUISmoke", "uiTestSelectors", *CI.BUDGET_KEYS):
            self.assertEqual(selected[key], default[key])
        source = (ROOT / "FieldEvidenceAppTests/V9_15AppLockLifecycleTests.swift").read_text()
        for name in names:
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(name) + r"\s*\(", source)), 1)

    def test_runtime_receipt_and_inventory_regressions_extend_exact_prior_pool(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        appended = ['FieldEvidenceAppTests/V23ProductionMyDayCommitTests/testMyDayWriterQuantizesFractionalCommitClockAndReplaysExactJournalTime', 'FieldEvidenceAppTests/V23ProductionMyDayCommitTests/testMyDayWriterRejectsInvalidCommitClockBeforeAnyCanonicalEffect', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressInitialAdmissionSnapshotUsesFixedControlInventories', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressFinalInventoryRejectsLateUnrelatedControlAndPreservesExistingReadyIntent']
        self.assertEqual(default["unitTestSelectors"][287:291], appended)
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][:287])), "89A305B5914EA4747B0FF7D992BF976BF99B6A4B502419A2B020079DDDBDE29E")
        original_groups = self.prior_821f_groups(mapping)
        for group_id, old_count, suffix in (("app-myday-production", 11, appended[:2]),
                                            ("notification-owner", 68, appended[2:])):
            group = next(item for item in original_groups if item["id"] == group_id)
            self.assertEqual(group["methodCount"], old_count + (7 if group_id == "notification-owner" else 2))
            group["methodCount"] = old_count
            selected = CI.resolve_selection(default, mapping, group_id)
            original = [item for item in default["unitTestSelectors"][:287]
                        if CI.selection_class(item) in group["classes"]]
            self.assertEqual(selected["unitTestSelectors"][:old_count + 2], original + suffix)
            self.assertEqual(len(original), old_count)
        codec = next(group for group in original_groups if group["id"] == "mutation-command-codec")
        self.assertEqual(codec["classes"], ["V10_02MutationEnvelopeReceiptTests", "V23FirstSignReceiptClockTests"])
        self.assertEqual(codec["methodCount"], 13)
        codec["classes"] = ["V10_02MutationEnvelopeReceiptTests"]
        codec["methodCount"] = 11
        self.assertEqual(CI.sha256(CI.canonical(original_groups)), "7FC16500C4791E32D5869140D6B86E08E4ACF514F0CE4920A91205D9ED810FBB")
        for selector in appended:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def test_first_sign_and_unpublished_recovery_extend_exact_f4_pool(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        appended = ['FieldEvidenceAppTests/V23FirstSignReceiptClockTests/testLocalFirstSignQuantizesGeneratedClockAndColdReplayPreservesExactBytes', 'FieldEvidenceAppTests/V23FirstSignReceiptClockTests/testLocalFirstSignRejectsInvalidGeneratedClockWithoutCanonicalEffect', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressMissingClaimedDirectoryWithoutEraseRecordRemainsDenied', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressInterruptedUnpublishedEraseRejectsReplacementOriginalDirectory', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressMalformedUnrelatedControlBlocksResumedEraseBeforeFirstEffect', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressChangedFrozenPublicationBlocksBeforeUnpublishedEraseEffect', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testPhysicalIngressFrozenMismatchPreflightDoesNotSettleEarlierRecoverableStates']
        self.assertEqual(default["unitTestSelectors"][291:298], appended)
        self.assertEqual(CI.sha256(CI.canonical(default["unitTestSelectors"][:291])), "F3207A7DE463625F01D239D2F2AAE394F31880AB12A2E089C3881FF46B6AC0CA")
        self.assertEqual(CI.sha256(CI.canonical({k: v for k, v in default.items() if k != "unitTestSelectors"})), "B13327745368CB0A522E9C3DFE13A99F555F686C7D35B11C1E0B4EE1FBAE0555")
        original_mapping = copy.deepcopy(mapping)
        original_mapping["groups"] = self.prior_821f_groups(mapping)
        for group_id, old_count, suffix in (("mutation-command-codec", 11, appended[:2]),
                                            ("notification-owner", 70, appended[2:])):
            group = next(item for item in original_mapping["groups"] if item["id"] == group_id)
            self.assertEqual(group["methodCount"], old_count + len(suffix))
            selected = CI.resolve_selection(default, mapping, group_id)
            original = [item for item in default["unitTestSelectors"][:291]
                        if CI.selection_class(item) in group["classes"]]
            self.assertEqual(selected["unitTestSelectors"][:old_count + len(suffix)], original + suffix)
            self.assertEqual(len(original), old_count)
            group["methodCount"] = old_count
            if group_id == "mutation-command-codec":
                self.assertEqual(group["classes"], ["V10_02MutationEnvelopeReceiptTests", "V23FirstSignReceiptClockTests"])
                group["classes"] = ["V10_02MutationEnvelopeReceiptTests"]
        self.assertEqual(CI.sha256(CI.canonical(original_mapping)), "4D2BB00E3151DE86EF6C2033A4951974E47E5043692F8CACE385DE5BA100904F")
        self.assertEqual(len(mapping["groups"]), 30)
        for selector in appended:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def test_closed_map_rejects_unselected_classes_and_workflow_choices_match(self):
        default = self.prior_d3be307_pool(self.prior_63409d1_pool(self.prior_aa94e7f_pool(prepartition_read_json(ROOT / "Scripts/ci-selection.json"))))
        mapping = self.prior_d3be307_map(self.prior_63409d1_map(self.prior_aa94e7f_map(prepartition_read_json(ROOT / CI.SELECTION_MAP_PATH))))
        unknown = copy.deepcopy(mapping)
        unknown["groups"][0]["classes"].append("UnselectedAuthorityTests")
        with self.assertRaisesRegex(ValueError, "selection group contains unselected class"):
            CI.resolve_selection(default, unknown, "notification-controls")
        workflow = self.prior_d97bc81_workflow((ROOT / ".github/workflows/ios-ci.yml").read_text(encoding='utf-8'))
        field = workflow.split("      native_selection_id:\n", 1)[1].split(
            "      s10_4_minimum_core_smoke_id:", 1)[0]
        choices = [line.strip()[2:] for line in field.splitlines()
                   if line.startswith("          - ")]
        self.assertEqual(choices.pop(), 'c36-restore-correspondence')
        self.assertEqual(choices, [mapping["defaultSelectionID"]]
                         + [group["id"] for group in mapping["groups"]])

    def test_selected_input_binds_the_checked_in_map_and_requested_id(self):
        e = environment()
        e["NATIVE_SELECTION_ID"] = "rating-eligibility"
        selected, record = CI.selected_input(ROOT, e)
        self.assertEqual(record["selectionID"], "rating-eligibility")
        self.assertEqual(len(selected["unitTestSelectors"]), 6)
        self.assertRegex(record["selectionSHA256"], r"^[0-9A-F]{64}$")
        self.assertEqual(record["selectionMapSHA256"],
                         CI.sha256((ROOT / CI.SELECTION_MAP_PATH).read_bytes()))

    def test_named_group_dispatcher_and_worker_reject_mismatched_bindings(self):
        e = environment()
        e["NATIVE_SELECTION_ID"] = "rating-eligibility"
        selected, record = CI.selected_input(ROOT, e)
        e.update({"DISPATCH_NATIVE_SELECTION_ID": record["selectionID"],
                  "DISPATCH_NATIVE_SELECTION_SHA256": record["selectionSHA256"],
                  "DISPATCH_NATIVE_SELECTION_MAP_SHA256": record["selectionMapSHA256"]})
        self.assertEqual(CI.admission(selected, e, HEAD, "dispatch", record)["selectionID"], "rating-eligibility")
        self.assertEqual(CI.admission(selected, e, HEAD, "worker", record)["selectionSHA256"], record["selectionSHA256"])
        for key in ("DISPATCH_NATIVE_SELECTION_ID", "DISPATCH_NATIVE_SELECTION_SHA256", "DISPATCH_NATIVE_SELECTION_MAP_SHA256"):
            bad = e.copy()
            bad[key] = "bad"
            with self.subTest(key=key), self.assertRaises(ValueError):
                CI.admission(selected, bad, HEAD, "worker", record)

    def test_dispatcher_admits_both_providers_before_worker(self):
        source = (ROOT / ".github/workflows/ios-ci.yml").read_text()
        native = step(source, "Validate ordinary V23 native acceptance selection")
        self.assertIn("github-xcode-26.6-acceptance", native)
        self.assertIn("bitrise-build-hub-xcode-26.6-acceptance", native)
        self.assertIn("python3 Scripts/v23-native-ci.py admit --stage dispatch", native)
        self.assertIn("NATIVE_SELECTION_ID: ${{ inputs.native_selection_id }}", native)
        self.assertIn("native_selection_map_sha256", source)
        self.assertEqual(source.count("native_acceptance_contract: ${{ needs.shared-selection.outputs.native_acceptance_contract || 'none' }}"), 2)
        self.assertIn("v23-bitrise-", source)
        self.assertIn("cancel-in-progress: false", source)

    def test_worker_orders_admission_native_evidence_and_secret_scan(self):
        source = (ROOT / ".github/workflows/ios-ci-worker.yml").read_text()
        self.assertIn("python3 Scripts/v23-native-ci.py admit --stage worker",
                      step(source, "Validate task selection and timeout tier"))
        selection = step(source, "Validate task selection and timeout tier")
        self.assertIn("python3 Scripts/v23-native-ci.py select --output", selection)
        self.assertIn("CI_SELECTION_PATH", selection)
        checkpoint = step(source, "Validate exact ordinary integration native checkpoint")
        self.assertIn("NATIVE_PRIOR_JOB_STATUS: ${{ job.status }}", checkpoint)
        self.assertIn("python3 Scripts/v23-native-ci.py verify", checkpoint)
        self.assertLess(source.index("- name: Validate required build and test evidence"),
                        source.index("- name: Validate exact ordinary integration native checkpoint"))
        self.assertLess(source.index("- name: Validate exact ordinary integration native checkpoint"),
                        source.index("- name: Verify Bitrise evidence contains no cache credentials"))
        self.assertLess(source.index("- name: Verify Bitrise evidence contains no cache credentials"),
                        source.index("- name: Hash collected evidence"))

    def test_development_modes_remain_nonaccepting_and_upload_stays_secret_gated(self):
        source = (ROOT / ".github/workflows/ios-ci-worker.yml").read_text()
        for name in ("Finalize Bitrise development-only shard evidence", "Fail closed after Bitrise development-only evidence"):
            self.assertIn("inputs.native_acceptance_contract != 'v23.integration.current-native.v1'", step(source, name))
        self.assertIn("exit 1", step(source, "Fail closed after Bitrise development-only evidence"))
        upload = step(source, "Upload build evidence")
        self.assertIn("steps.bitrise_credential_scan.outputs.safe_to_upload == 'true'", upload)
        self.assertIn("ios-ci-native-{0}-{1}-{2}-{3}", upload)
        self.assertIn("format('ios-ci-s10-4-diagnostic-{0}-{1}-{2}-{3}', github.run_id, github.run_attempt, inputs.s10_4_shard_id, inputs.s10_4_diagnostic_probe_id)", upload)
        self.assertIn("format('v23-{0}-{1}-', inputs.runner_provider, inputs.native_selection_id)", source)
        self.assertIn("cancel-in-progress: false", source)

    def test_owned_native_simulator_and_sdk_are_observed_not_assumed(self):
        source = (ROOT / ".github/workflows/ios-ci-worker.yml").read_text()
        setup = step(source, "Verify pinned toolchain, shared scheme, and simulator")
        self.assertIn("xcrun --sdk iphonesimulator --show-sdk-version", setup)
        self.assertIn("xcrun --sdk iphonesimulator --show-sdk-build-version", setup)
        self.assertIn("CI_NATIVE_CREATED_SIMULATOR_UDID=%s", setup)
        cleanup = step(source, "Remove owned isolated Simulator")
        self.assertIn('pilot_simulator_udid="${CI_NATIVE_CREATED_SIMULATOR_UDID:-}"', cleanup)
        self.assertIn('xcrun simctl delete "$pilot_simulator_udid"', cleanup)
        self.assertIn("native-simulator-lifecycle.txt", cleanup)


class SetupFailureEvidenceTests(unittest.TestCase):
    @staticmethod
    def failure_environment(provider="github"):
        return {
            "RUNTIME_SETUP_OUTCOME": "failure",
            "CI_TASK_ID": "V23-INTEGRATION-20260910",
            "CI_NATIVE_ACCEPTANCE_CONTRACT": CI.CONTRACT,
            "CI_RUNNER_PROVIDER": provider,
            "CI_RUNNER_LABEL": "macos-26" if provider == "github" else "bitrise-runner-Asset Roundddd",
            "CI_S10_4_SHARED_BUILD_MODE": "none",
            "CI_S10_4_SHARED_PAYLOAD_RUN_ID": "",
            "CI_S10_4_EXECUTION_ROLE": "independent",
            "CI_S10_4_PILOT_MODE": "false",
            "CI_S10_4_SHARD_ID": "none",
            "CI_S10_4_SEGMENT_ID": "none",
            "WORKER_S10_4_DIAGNOSTIC_PROBE_ID": "none",
        }

    def execute_hash_step(self, overrides):
        source = (ROOT / ".github/workflows/ios-ci-worker.yml").read_text()
        hash_step = step(source, "Hash collected evidence")
        self.assertIn("always() && (inputs.runner_provider != 'bitrise' || inputs.s10_4_execution_role == 'payload-consumer' || steps.bitrise_credential_scan.outputs.safe_to_upload == 'true')", hash_step)
        run_body = hash_step.split("        run: |\n", 1)[1]
        body = "\n".join(line[10:] if line.startswith("          ") else line for line in run_body.splitlines()) + "\n"
        self.assertNotIn("${{", body)
        # Windows' system bash may be WSL. Use Git Bash for this POSIX fixture.
        bash = str(Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe") if os.name == "nt" else shutil.which("bash")
        self.assertTrue(bash and Path(bash).is_file(), "a local Bash shell is required for evidence protocol tests")
        with tempfile.TemporaryDirectory(prefix="v23 hash evidence ") as directory:
            temporary = Path(directory)
            artifact = temporary / "artifacts"
            artifact.mkdir()
            (artifact / "nested").mkdir()
            originals = {"./native-setup.log": b"runtime missing\nprovision_exit=124\n", "./nested/original bytes.log": b"\x00retained original bytes\xff\n"}
            for name, data in originals.items():
                (artifact / name).write_bytes(data)
            (artifact / "SHA256SUMS.txt").write_text("stale manifest must be replaced\n")
            shell_file = temporary / "actual-hash-step.sh"
            shell_file.write_bytes(body.encode())
            shim = temporary / "bin"
            shim.mkdir()
            # Git for Windows provides sha256sum, but may omit Perl's shasum.
            # Adapt only the interface; execute the real SHA256 and check tools.
            shell_environment = {key: value for key, value in os.environ.items()
                                 if not key.startswith(("CI_", "WORKER_", "RUNTIME_SETUP_"))}
            available = subprocess.run([bash, "-c", "command -v shasum"], env=shell_environment, capture_output=True, text=True, timeout=15)
            if available.returncode:
                adapter = shim / "shasum"
                adapter.write_bytes(b'#!/usr/bin/env bash\nset -euo pipefail\ntest "$1:$2" = -a:256\nshift 2\nexec sha256sum "$@"\n')
                adapter.chmod(0o755)
            shell_environment.update(overrides)
            shell_environment.update({"CI_ARTIFACT_DIR": artifact.as_posix(), "RUNNER_TEMP": temporary.as_posix()})
            result = subprocess.run([bash, "-c", 'fixture_bin="$(cd "$1" && pwd)"; export PATH="$fixture_bin:$PATH"; exec bash "$2"', "fixture", shim.as_posix(), shell_file.as_posix()],
                                    env=shell_environment, capture_output=True, text=True, timeout=15)
            files = {"./" + path.relative_to(artifact).as_posix(): path.read_bytes() for path in artifact.rglob("*") if path.is_file()}
            for name, data in originals.items():
                self.assertEqual(files[name], data, result.stderr)
            return result, files

    def assert_verified_manifest(self, result, files):
        self.assertIn("./SHA256SUMS.txt", files, result.stderr)
        actual = {}
        for line in files["./SHA256SUMS.txt"].decode().splitlines():
            match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
            self.assertIsNotNone(match, line)
            digest, name = match.groups()
            self.assertNotIn(name, actual)
            actual[name] = digest
        expected = {name: hashlib.sha256(data).hexdigest() for name, data in files.items() if name != "./SHA256SUMS.txt"}
        self.assertEqual(actual, expected)
        self.assertEqual(list(actual), sorted(actual))
        self.assertNotIn("FAILED", result.stdout + result.stderr)
        for name in actual:
            self.assertIn(name + ": OK", result.stdout)

    def test_ordinary_setup_failure_retains_verified_originals_for_both_providers_and_stays_failed(self):
        for provider in ("github", "bitrise"):
            with self.subTest(provider=provider):
                result, files = self.execute_hash_step(self.failure_environment(provider))
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assert_verified_manifest(result, files)
                self.assertEqual(files["./v23-setup-failure-evidence.txt"], b"setup_elapsed_seconds=unavailable\nsetup_artifact_elapsed_seconds=unavailable\nacceptance_eligible=false\nreason=setup-failed-before-accounting\n")
                self.assertNotIn("./artifact-budget.txt", files)
                self.assertNotIn("./s10-4-setup-failure-evidence.txt", files)

    def test_ineligible_outcomes_modes_and_unknown_bindings_cannot_enter_failure_retention(self):
        variants = [
            {"RUNTIME_SETUP_OUTCOME": outcome} for outcome in ("success", "cancelled", "skipped", "", "unknown")
        ] + [
            {"CI_TASK_ID": "S10.4"}, {"CI_NATIVE_ACCEPTANCE_CONTRACT": "none"},
            {"CI_RUNNER_PROVIDER": "unknown"}, {"CI_RUNNER_LABEL": "macos-latest"},
            {"CI_RUNNER_PROVIDER": "bitrise"}, {"CI_S10_4_SHARED_BUILD_MODE": "consumer"},
            {"CI_S10_4_SHARED_PAYLOAD_RUN_ID": "123"}, {"CI_S10_4_EXECUTION_ROLE": "payload-consumer"},
            {"CI_S10_4_PILOT_MODE": "true"}, {"CI_S10_4_SHARD_ID": "a-shard"},
            {"CI_S10_4_SEGMENT_ID": "a-segment"}, {"WORKER_S10_4_DIAGNOSTIC_PROBE_ID": "a-probe"},
        ]
        variants += [{key: None} for key in self.failure_environment() if key != "CI_S10_4_SHARED_PAYLOAD_RUN_ID"]
        for changed in variants:
            with self.subTest(changed=changed):
                values = self.failure_environment()
                values.update(changed)
                values = {key: value for key, value in values.items() if value is not None}
                result, files = self.execute_hash_step(values)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(set(files), {"./native-setup.log", "./nested/original bytes.log"})

    def test_accounted_setup_preserves_original_budget_manifest_and_over_budget_failure(self):
        for outcome, budget, expected_returncode in (("success", 600, 0), ("failure", 600, 0), ("success", 0, 1)):
            with self.subTest(outcome=outcome, budget=budget):
                values = self.failure_environment()
                values.update({"RUNTIME_SETUP_OUTCOME": outcome, "CI_SETUP_ELAPSED_SECONDS": "17",
                               "CI_ARTIFACT_START_EPOCH": str(int(time.time())), "CI_SETUP_ARTIFACT_TIMEOUT_SECONDS": str(budget)})
                result, files = self.execute_hash_step(values)
                self.assertEqual(result.returncode, expected_returncode, result.stderr)
                self.assert_verified_manifest(result, files)
                self.assertNotIn("./v23-setup-failure-evidence.txt", files)
                accounting = dict(line.split("=", 1) for line in files["./artifact-budget.txt"].decode().splitlines())
                self.assertEqual(int(accounting["setup_elapsed_seconds"]), 17)
                self.assertGreaterEqual(int(accounting["artifact_elapsed_seconds"]), 0)
                self.assertEqual(int(accounting["setup_artifact_elapsed_seconds"]), 17 + int(accounting["artifact_elapsed_seconds"]))
                self.assertEqual(int(accounting["setup_artifact_budget_seconds"]), budget)



if __name__ == "__main__":
    unittest.main()
