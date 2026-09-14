#!/usr/bin/env python3
"""Native-route protocol tests using disposable facts, never native PASS evidence."""
import copy
import importlib.util
import json
import re
from pathlib import Path
import shutil
import tempfile
import unittest


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


class AdmissionTests(unittest.TestCase):
    def test_both_providers_and_all_supported_tiers_use_same_contract(self):
        for provider in ("github", "bitrise"):
            for tier in CI.TIERS:
                e, s = environment(provider, tier), selection(tier)
                for ref in CI.REFS:
                    e["GITHUB_REF"] = ref
                    for stage in ("dispatch", "worker"):
                        with self.subTest(provider=provider, tier=tier, ref=ref, stage=stage):
                            value = CI.admission(s, e, HEAD, stage)
                            self.assertEqual(value["contractID"], CI.CONTRACT)
                            self.assertEqual(value["runnerProvider"], provider)
                            self.assertEqual(value["head"], HEAD)

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


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="v23-native-protocol-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)

    def fixture(self, provider="github", tier="N8"):
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
    def prior_05b38c1_pool(self, default):
        self.assertEqual(len(default["unitTestSelectors"]), 524)
        prior = copy.deepcopy(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:514]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '49396D1F0A6B5CBB36EB9965E26B5DE3291F7F550DBF2C4E346A07329C1CD3B8')
        return prior

    def prior_05b38c1_map(self, mapping):
        prior = copy.deepcopy(mapping)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        prior = self.prior_05b38c1_pool(default)
        prior_map = self.prior_05b38c1_map(mapping)
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
        prior = self.prior_05b38c1_pool(default)
        prior["unitTestSelectors"] = prior["unitTestSelectors"][:504]
        self.assertEqual(CI.sha256(CI.canonical(prior)), '42333C57BC5A301D897D9C74C39B7A1AD99A70393EE2F155B584A659DA65A333')
        return prior

    def prior_af2df5f_map(self, mapping):
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
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
        original = [s.rsplit("/", 1)[1] for s in prior["unitTestSelectors"]
                    if CI.selection_class(s) == "V23PartsStockReplacementHistoryTests"]
        self.assertEqual(len(original), 8)
        self.assertEqual(declared, original[:3] + [s.rsplit("/", 1)[1] for s in c55] + original[3:])
        for selector in resolver + c55:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text(encoding="utf-8")
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_47d433e_map(self, mapping):
        prior = self.prior_af2df5f_map(mapping)
        group = next(g for g in prior["groups"] if g["id"] == "report-camera-recovery")
        self.assertEqual(group["methodCount"], 14)
        self.assertEqual(group["classes"].pop(), "V9_18PackLifecycleIntegrationTests")
        group["methodCount"] = 3
        self.assertEqual(CI.sha256(CI.canonical(prior)), '0E5745A8430315B2C09B1382ACEB2EA8244EE27ABA5F7860550417CFC3615D88')
        return prior

    def test_finalization_readback_preserves_exact_47d_pool_and_complete_new_methods(self):
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in expected[3:]])
        for selector in expected:
            method = selector.rsplit("/", 1)[1]
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_0e90d6c_map(self, mapping):
        prior = self.prior_47d433e_map(mapping)
        archive = next(g for g in prior["groups"] if g["id"] == "archive-contracts")
        self.assertEqual(archive["methodCount"], 25)
        self.assertEqual(archive["classes"][-2:], ["V23FieldDraftAsyncCommitTests", "V23BackupManifestMemberTests"])
        archive["classes"] = archive["classes"][:-2]
        archive["methodCount"] = 11
        self.assertEqual(CI.sha256(CI.canonical(prior)), '62BA7A780325B00F54EA9D7DFA8FB46B2F19BB0BF6994A0D4BFD3C8470F5ACC9')
        return prior

    def test_archive_async_admission_preserves_exact_0e_pool_and_complete_pairs(self):
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        prior = self.prior_0e90d6c_map(mapping)
        codec = next(g for g in prior["groups"] if g["id"] == "mutation-command-codec")
        self.assertEqual(codec["methodCount"], 29)
        self.assertEqual(codec["classes"], ["V10_02MutationEnvelopeReceiptTests", "V23FirstSignReceiptClockTests", "V23PartsStockReplacementHistoryTests", "V23PartsStockReplacementProjectionTests"])
        codec["classes"] = codec["classes"][:2]
        codec["methodCount"] = 14
        return prior

    def test_c55_admission_preserves_exact_ff8_pool_and_complete_paired_classes(self):
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
                supplemental = [s.rsplit("/", 1)[1] for s in self.af2_c55_supplemental_selectors()]
                self.assertEqual([name for name in declared if name in supplemental], supplemental)
                declared = [name for name in declared if name not in supplemental]
            self.assertEqual(declared, [s.rsplit("/", 1)[1] for s in expected if CI.selection_class(s) == klass])
        for selector in expected:
            bundle, klass, method = selector.split("/")
            source = (ROOT / bundle / (klass + ".swift")).read_text()
            self.assertEqual(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", source)), 1)

    def prior_f86664a_map(self, mapping):
        prior = self.prior_ff8ae4c_map(mapping)
        reference = next(g for g in prior["groups"] if g["id"] == "reference-owner-replacement")
        self.assertEqual(reference["methodCount"], 51)
        self.assertEqual(reference["classes"].pop(), "V23ReferenceOwnerReplacementCommandPlanTests")
        reference["methodCount"] = 40
        return prior

    def test_command_plan_admission_preserves_exact_f86664a_pool_and_map(self):
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        prior = self.prior_f86664a_map(mapping)
        archive = next(g for g in prior["groups"] if g["id"] == "archive-contracts")
        self.assertEqual(archive["methodCount"], 11)
        self.assertEqual(archive["classes"].pop(), "V23FieldDraftStageDigestBackupTests")
        archive["methodCount"] = 8
        return prior

    def test_stage_digest_admission_preserves_exact_12e5742_pool_and_map(self):
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        self.assertEqual(len(default["unitTestSelectors"]), 524)
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
            for path in (*CI.PROTOCOL_PATHS, "Scripts/ci-selection.json", CI.SELECTION_MAP_PATH):
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        groups = [CI.resolve_selection(default, mapping, group["id"])
                  for group in mapping["groups"]]
        self.assertEqual(sum(len(group["unitTestSelectors"]) for group in groups), 524)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
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
        default = CI.read_json(ROOT / "Scripts/ci-selection.json")
        mapping = CI.read_json(ROOT / CI.SELECTION_MAP_PATH)
        unknown = copy.deepcopy(mapping)
        unknown["groups"][0]["classes"].append("UnselectedAuthorityTests")
        with self.assertRaisesRegex(ValueError, "selection group contains unselected class"):
            CI.resolve_selection(default, unknown, "notification-controls")
        workflow = (ROOT / ".github/workflows/ios-ci.yml").read_text()
        field = workflow.split("      native_selection_id:\n", 1)[1].split(
            "      s10_4_minimum_core_smoke_id:", 1)[0]
        choices = [line.strip()[2:] for line in field.splitlines()
                   if line.startswith("          - ")]
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


if __name__ == "__main__":
    unittest.main()
