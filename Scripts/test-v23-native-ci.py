#!/usr/bin/env python3
"""Native-route protocol tests using disposable facts, never native PASS evidence."""
import copy
import importlib.util
import json
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
        self.assertEqual(sum(len(group["unitTestSelectors"]) for group in groups), 259)
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
