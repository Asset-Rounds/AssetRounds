#!/usr/bin/env python3
"""Windows-safe protocol tests. Every executed child is Python, never Xcode."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zipfile
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("compiler_timing", ROOT / "Scripts/v23-compiler-timing.py")
TIMING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TIMING)


class CompilerTimingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="v23-compiler-timing-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "Scripts").mkdir()
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        # Legacy admission stays exercised against its frozen source objects,
        # even while the checked-in active observation uses schema5.
        self.config = dict(schemaVersion=1, mode="timing-f6-source-v1",
            sourceHead=TIMING.SOURCE_HEAD, sourceTrees=copy.deepcopy(TIMING.SOURCE_TREES),
            sampleIntervalSeconds=5, **TIMING.SOURCE_SELECTION_HASHES)
        default = subprocess.check_output(["git", "show", TIMING.SOURCE_HEAD + ":Scripts/ci-selection.json"], cwd=ROOT)
        mapping = subprocess.check_output(["git", "show", TIMING.SOURCE_HEAD + ":Scripts/ci-selection-map.json"], cwd=ROOT)
        (self.root / "Scripts/ci-selection.json").write_bytes(default)
        (self.root / "Scripts/ci-selection-map.json").write_bytes(mapping)
        selector_spec = importlib.util.spec_from_file_location("selector", ROOT / "Scripts/v23-native-ci.py")
        selector = importlib.util.module_from_spec(selector_spec)
        selector_spec.loader.exec_module(selector)
        selected = selector.resolve_selection(json.loads(default), json.loads(mapping), "catalog-file-authority")
        self.resolved = self.artifacts / "ci-selection.selected.json"
        self.resolved.write_bytes(selector.canonical(selected))
        self.env = {
            "CI_NATIVE_ACCEPTANCE_CONTRACT": TIMING.CONTRACT,
            "GITHUB_REPOSITORY": "Asset-Rounds/AssetRounds",
            "GITHUB_REF": "refs/heads/codex/v23-s10-integration-20260910",
            "GITHUB_SHA": "a" * 40,
            "CI_RUNNER_PROVIDER": "github", "CI_RUNNER_LABEL": "macos-26",
            "NATIVE_SELECTION_ID": "catalog-file-authority",
            "CI_TASK_ID": "V23-INTEGRATION-20260910", "CI_TIER": "N8",
            "CI_SETUP_ARTIFACT_TIMEOUT_SECONDS": "300",
            "CI_BUILD_TIMEOUT_SECONDS": "1200", "CI_TEST_TIMEOUT_SECONDS": "900",
            "CI_UI_TIMEOUT_SECONDS": "0", "CI_TOTAL_BUDGET_SECONDS": "2400",
            "CI_RUN_UI_SMOKE": "false", "CI_SELECTOR_RUN_UI_SMOKE": "false",
            "CODE_SIGNING_ALLOWED": "NO", "RUNNER_ARCH": "ARM64",
            "DEVELOPER_DIR": "/Applications/Xcode_26.6.app/Contents/Developer",
            "PROJECT_PATH": "FieldEvidenceApp.xcodeproj", "SCHEME": "FieldEvidenceApp",
            "CONFIGURATION": "Debug", "CI_SIMULATOR_UDID": "53084A6F-DD88-48EC-BF58-62A55A3B0DEA",
            "CI_DESTINATION": "platform=iOS Simulator,id=53084A6F-DD88-48EC-BF58-62A55A3B0DEA",
            "RUNNER_TEMP": str(self.root / "runner"), "CI_ARTIFACT_DIR": str(self.artifacts),
            "CI_SELECTION_PATH": str(self.resolved),
            "DISPATCH_NATIVE_SELECTION_SHA256": self.config["resolvedSelectionSHA256"],
        }
        self.command = TIMING.expected_command(self.env)

    def git(self, *args):
        if args == ("rev-parse", "HEAD"):
            return (self.env["GITHUB_SHA"] + "\n").encode()
        if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
            return (self.config["sourceTrees"][args[1][5:]] + "\n").encode()
        self.assertIn(args[0], ("diff", "ls-files"))
        self.assertEqual(args[args.index("--") + 1:], TIMING.SOURCE_PATHS)
        return b""

    def admit(self, config=None, environment=None, command=None, git=None, platform="darwin"):
        return TIMING.admit(config or self.config, environment or self.env,
                            command or self.command, self.root, git or self.git, platform)

    def testClosedConfigurationRejectsUnknownMissingDuplicateAndOverrideFields(self):
        target = self.root / "timing.json"

        def load(value):
            target.write_text(json.dumps(value), encoding="utf-8")
            return TIMING.read_configuration(target)

        self.assertEqual(load(self.config), self.config)
        for key in self.config:
            changed = copy.deepcopy(self.config)
            del changed[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                load(changed)
        for key, value in (("extra", True), ("schemaVersion", True), ("mode", "acceptance"),
                           ("sourceHead", "b" * 40), ("sourceTrees", []),
                           ("selectionSHA256", "0" * 63), ("selectionMapSHA256", "z" * 64),
                           ("resolvedSelectionSHA256", None), ("sampleIntervalSeconds", True),
                           ("sampleIntervalSeconds", 1), ("buildTimeoutSeconds", 2400),
                           ("otherSwiftFlags", "-Ounchecked")):
            with self.subTest(field=key, value=value), self.assertRaises(ValueError):
                load({**self.config, key: value})
        changed = copy.deepcopy(self.config)
        changed["sourceTrees"]["../outside"] = changed["sourceTrees"].pop("FieldEvidenceApp")
        with self.assertRaises(ValueError):
            load(changed)
        changed = copy.deepcopy(self.config)
        changed["sourceTrees"]["FieldEvidenceApp"] = "invalid"
        with self.assertRaises(ValueError):
            load(changed)
        raw = json.dumps(self.config)
        target.write_text(raw[:-1] + ',"mode":"timing-f6-source-v1"}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            TIMING.read_configuration(target)

    def testAdmissionBindsExactHostedSourceSelectorAndUnchangedBudgets(self):
        self.assertEqual(self.admit(), self.env["GITHUB_SHA"])
        for key, value in self.env.items():
            changed = dict(self.env)
            changed[key] = "unexpected" if value else "nonempty"
            # Runtime paths are intentionally variable, but changing them without
            # changing the actual base command still violates exact argv binding.
            with self.subTest(environment=key), self.assertRaises((ValueError, OSError)):
                self.admit(environment=changed)
        for platform in ("win32", "linux"):
            with self.subTest(platform=platform), self.assertRaises(ValueError):
                self.admit(platform=platform)
        for path in TIMING.SOURCE_PATHS:
            def changed_git(*args):
                return b"b" * 40 if args == ("rev-parse", "HEAD:" + path) else self.git(*args)
            with self.subTest(tree=path), self.assertRaisesRegex(ValueError, "tree"):
                self.admit(git=changed_git)
        for kind in ("diff", "ls-files"):
            def changed_git(*args):
                return b"unadmitted.swift\n" if args[0] == kind else self.git(*args)
            with self.subTest(dirty=kind), self.assertRaisesRegex(ValueError, "source"):
                self.admit(git=changed_git)
        for path in (self.root / "Scripts/ci-selection.json", self.root / "Scripts/ci-selection-map.json",
                     self.resolved):
            original = path.read_bytes()
            path.write_bytes(original + b" ")
            with self.subTest(selector=str(path)), self.assertRaisesRegex(ValueError, "bytes"):
                self.admit()
            path.write_bytes(original)
        stale = Path(self.env["RUNNER_TEMP"]) / "FieldEvidenceDerivedData/Build"
        stale.mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "fresh DerivedData"):
            self.admit()

    def testNativeArgvAddsOnlyTimingObservationsAndLegacyWrapperIsExact(self):
        changed = TIMING.diagnostic_command(self.command)
        self.assertEqual(changed[:-3], self.command[:-1])
        self.assertEqual(changed[-3:], ["-showBuildTimingSummary",
            "OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -warn-long-function-bodies=500"
            " -Xfrontend -warn-long-expression-type-checking=200", "build-for-testing"])
        self.assertIn("CODE_SIGNING_ALLOWED=NO", changed)
        for invalid in (self.command + ["clean"], [*self.command[:-1], "test"],
                        [*self.command[:-1], "-skip-testing:FieldEvidenceAppTests", self.command[-1]]):
            with self.subTest(argv=invalid), self.assertRaises(ValueError):
                self.admit(command=invalid)
        before = subprocess.check_output(["git", "show", TIMING.SOURCE_HEAD + ":Scripts/build-smoke.sh"], cwd=ROOT)
        # Replay the original instrumented wrapper, independent of later routes.
        after = subprocess.check_output(["git", "show",
            "3ed1b0068819fbb43a0c4ecf0442847f1913ad81:Scripts/build-smoke.sh"], cwd=ROOT)
        addition = b'''compiler_timing_prefix=(xcodebuild)
if [ "${CI_NATIVE_ACCEPTANCE_CONTRACT:-none}" = v23.integration.current-native.v1 ]; then
  compiler_timing_prefix=(python3 Scripts/v23-compiler-timing.py -- xcodebuild)
fi

"${compiler_timing_prefix[@]}" \\
'''
        self.assertEqual(after.count(addition), 1)
        self.assertEqual(after.replace(addition, b"xcodebuild \\\n"), before)
        self.assertEqual(subprocess.check_output(["git", "show", TIMING.SOURCE_HEAD + ":Scripts/run-with-timeout.sh"], cwd=ROOT),
                         (ROOT / "Scripts/run-with-timeout.sh").read_bytes())

    def testSourceAndConfigurationCannotDriftTogetherWhileClaimingF6(self):
        for path in TIMING.SOURCE_PATHS:
            changed = copy.deepcopy(self.config)
            changed["sourceTrees"][path] = "b" * 40

            def changed_git(*args):
                return b"b" * 40 if args == ("rev-parse", "HEAD:" + path) else self.git(*args)

            with self.subTest(jointTreeDrift=path), self.assertRaisesRegex(ValueError, "fixed f6"):
                self.admit(config=changed, git=changed_git)
        for key, path in (("selectionSHA256", self.root / "Scripts/ci-selection.json"),
                          ("selectionMapSHA256", self.root / "Scripts/ci-selection-map.json"),
                          ("resolvedSelectionSHA256", self.resolved)):
            before = path.read_bytes()
            changed_bytes = before + b" "
            path.write_bytes(changed_bytes)
            changed = copy.deepcopy(self.config)
            changed[key] = hashlib.sha256(changed_bytes).hexdigest().upper()
            environment = dict(self.env)
            if key == "resolvedSelectionSHA256":
                environment["DISPATCH_NATIVE_SELECTION_SHA256"] = changed[key]
            with self.subTest(jointSelectorDrift=key), self.assertRaisesRegex(ValueError, "fixed f6"):
                self.admit(config=changed, environment=environment)
            path.write_bytes(before)
        # Independently authenticate the constants against actual frozen Git
        # objects; configuration equality alone is insufficient provenance.
        for path, tree in TIMING.SOURCE_TREES.items():
            observed = subprocess.check_output(["git", "rev-parse", TIMING.SOURCE_HEAD + ":" + path], cwd=ROOT).decode().strip()
            self.assertEqual(observed, tree)
        for key, path in (("selectionSHA256", "Scripts/ci-selection.json"),
                          ("selectionMapSHA256", "Scripts/ci-selection-map.json")):
            observed = subprocess.check_output(["git", "show", TIMING.SOURCE_HEAD + ":" + path], cwd=ROOT)
            self.assertEqual(hashlib.sha256(observed).hexdigest().upper(), TIMING.SOURCE_SELECTION_HASHES[key])
        self.assertEqual(hashlib.sha256(self.resolved.read_bytes()).hexdigest().upper(),
                         TIMING.SOURCE_SELECTION_HASHES["resolvedSelectionSHA256"])

    def testProcessParserKeepsOriginalTimesAndRejectsMalformedCompilerMetadata(self):
        valid = " 123 45 199.2 20:12.44 01-00:20:19 15744 R Mon Sep 14 22:05:03 2026 /Applications/Xcode 26.app/swift-frontend"
        others = " 300 1 3.4 0:12.01 00:40 2048 S Mon Sep 14 22:05:03 2026 /some/unrelated-program"
        rows, malformed = TIMING.parse_processes(valid + "\n" + others + "\n")
        self.assertEqual(malformed, 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["cpuTime"], "20:12.44")
        self.assertEqual(rows[0]["elapsedTime"], "01-00:20:19")
        self.assertEqual(rows[0]["cpuPercentDecayingAverage"], 199.2)
        self.assertEqual(rows[0]["key"], "123@Mon Sep 14 22:05:03 2026")
        for old, new in (("199.2", "nan"), ("199.2", "-2"), ("15744", "-1"),
                         ("20:12.44", "bad"), ("01-00:20:19", "invalid"), ("2026", "year")):
            with self.subTest(old=old, new=new):
                parsed, malformed = TIMING.parse_processes(valid.replace(old, new))
                self.assertEqual(parsed, [])
                self.assertEqual(malformed, 1)
        self.assertEqual(TIMING.parse_processes("\n"), ([], 0))
        self.assertEqual(TIMING.parse_processes("truncated metadata"), ([], 1))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            TIMING.parse_processes(valid + "\n" + valid)

    def testProcessArgvAndLifecycleDoNotTurnPIDReuseOrDisappearanceIntoSuccess(self):
        row = "123 45 5.2 0:12.44 00:20 15744 S Mon Sep 14 22:05:03 2026 /tool/swift-frontend"
        processes, _ = TIMING.parse_processes(row)
        process = processes[0]
        output = ("123 Mon Sep 14 22:05:03 2026 /tool/swift-frontend -primary-file /workspace/A.swift\n"
                  "456 Mon Sep 14 22:05:03 2026 /tool/swift-frontend foreign\n").encode()
        observed = subprocess.CompletedProcess([], 0, output, b"")
        with mock.patch.object(TIMING.subprocess, "run", return_value=observed):
            commands = TIMING.process_commands(processes)
        self.assertEqual(commands, {process["key"]: "/tool/swift-frontend -primary-file /workspace/A.swift"})
        for mismatch in (output.replace(b"22:05:03", b"22:05:04"),
                         output.replace(b"/tool/swift-frontend", b"/unrelated/process"), b""):
            with mock.patch.object(TIMING.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, mismatch, b"")):
                self.assertEqual(TIMING.process_commands(processes), {})
        observations = TIMING.ProcessObservations()
        first, gone = observations.observe({"processes": processes}, 5.0, commands)
        self.assertEqual(len(first), 1)
        self.assertEqual(gone, [])
        self.assertIsNone(first[0]["exitStatus"])
        self.assertFalse(first[0]["commandIsExactArgv"])
        self.assertEqual(observations.observe({"processes": processes}, 10.0, {}), ([], []))
        first, gone = observations.observe({"processes": []}, 15.0, {})
        self.assertEqual(first, [])
        self.assertEqual(gone[0]["lastObservedSeconds"], 10.0)
        self.assertIsNone(gone[0]["exitStatus"])
        self.assertFalse(gone[0]["completionProven"])
        replacement, _ = TIMING.parse_processes(row.replace("22:05:03", "22:05:30"))
        first, gone = observations.observe({"processes": replacement}, 20.0, {})
        self.assertEqual(first[0]["firstObservedSeconds"], 20.0)
        self.assertNotEqual(first[0]["key"], process["key"])
        self.assertIsNone(first[0]["psRenderedCommand"])

    def testPythonChildRetainsBothStreamsAndExitStatusDespiteObserverFailure(self):
        harness = '''import importlib.util,sys
from pathlib import Path
s=importlib.util.spec_from_file_location("timing",sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
def failed(): raise OSError("observed ps unavailable")
code=m.run_observed_build([sys.executable,"-c","import sys,time;print('native-stdout',flush=True);print('native-stderr',file=sys.stderr,flush=True);time.sleep(.1);sys.exit(7)"],Path(sys.argv[2]),{"purpose":"test","nativeAcceptance":False},interval=.01,sampler=failed,commands_reader=lambda _: {})
sys.exit(code)
'''
        observed = subprocess.run([sys.executable, "-c", harness, str(ROOT / "Scripts/v23-compiler-timing.py"),
                                   str(self.artifacts)], capture_output=True, timeout=10)
        self.assertEqual(observed.returncode, 7, observed.stderr)
        self.assertEqual(observed.stdout, b"native-stdout\r\n" if sys.platform == "win32" else b"native-stdout\n")
        self.assertIn(b"native-stderr", observed.stderr)
        rows = [json.loads(row) for row in (self.artifacts / "events.jsonl").read_text().splitlines()]
        self.assertEqual(rows[0]["event"], "build-request")
        self.assertTrue(any(row["event"] == "observation-error" for row in rows))
        self.assertEqual(rows[-1]["buildReturnCode"], 7)
        self.assertFalse(rows[-1]["nativeAcceptance"])
        self.assertFalse(rows[-1]["providerQualification"])
        self.assertEqual(rows[-1]["receivedSignals"], [])
        self.assertEqual([row["elapsedSeconds"] for row in rows], sorted(row["elapsedSeconds"] for row in rows))

    def testWatchdogSignalRetainsUnfinishedCompilerWithoutInventedExit(self):
        process, _ = TIMING.parse_processes("123 45 9.0 0:12.00 00:20 2048 R Mon Sep 14 22:05:03 2026 /tool/swift-frontend")
        for terminal in (None, -signal.SIGTERM):
            output = self.root / ("unfinished" if terminal is None else "signalled")
            output.mkdir()

            class Child:
                pid = 45
                status = None

                def poll(self): return self.status

                def send_signal(self, received):
                    self.received = received

                def wait(self, timeout):
                    if terminal is None:
                        raise subprocess.TimeoutExpired("test-child", timeout)
                    self.status = terminal
                    return terminal

            def sample():
                signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
                return {"logicalCPUCount": 4, "loadAverages": [1.0, 1.0, 1.0],
                        "processes": process, "malformedMetadataRows": 0}

            child = Child()
            with mock.patch.object(TIMING.subprocess, "Popen", return_value=child):
                status = TIMING.run_observed_build(["fake-owned-child"], output, {"purpose": "test"},
                                                   sampler=sample, commands_reader=lambda _: {})
            self.assertEqual(status, 128 + signal.SIGTERM)
            self.assertEqual(child.received, signal.SIGTERM)
            rows = [json.loads(row) for row in (output / "events.jsonl").read_text().splitlines()]
            self.assertEqual(rows[-1]["buildReturnCode"], terminal)
            self.assertEqual(rows[-1]["receivedSignals"], [signal.SIGTERM])
            self.assertIn(process[0]["key"], rows[-1]["processesWithUnobservedTerminal"])
            self.assertIsNone(rows[2]["newlyObserved"][0]["exitStatus"])
            self.assertFalse(rows[-1]["nativeAcceptance"])

    def testSamplingDeadlineIncludesObserverCostAndRetainsOverrun(self):
        clock = [0.0]
        starts, waits = [], []
        costs = iter([2.0, 2.0, 7.0, 2.0])

        class Child:
            pid = 45
            status = None

            def poll(self): return self.status

            def wait(self, timeout):
                waits.append(timeout)
                clock[0] += timeout
                if len(starts) == 4:
                    self.status = 0
                    return 0
                raise subprocess.TimeoutExpired("test-child", timeout)

        def sample():
            starts.append(clock[0])
            clock[0] += next(costs)
            return {"logicalCPUCount": 4, "loadAverages": [1.0, 1.0, 1.0],
                    "processes": [], "malformedMetadataRows": 0}

        with mock.patch.object(TIMING.time, "monotonic", side_effect=lambda: clock[0]), \
             mock.patch.object(TIMING.subprocess, "Popen", return_value=Child()):
            result = TIMING.run_observed_build(["fake-owned-child"], self.artifacts, {"purpose": "test"},
                                               sampler=sample, commands_reader=lambda _: {})
        self.assertEqual(result, 0)
        self.assertEqual(starts, [0.0, 5.0, 10.0, 17.0])
        self.assertEqual(waits, [3.0, 3.0, 0, 3.0])
        events = [json.loads(row) for row in (self.artifacts / "events.jsonl").read_text().splitlines()]
        samples = [row for row in events if row["event"] == "sample"]
        self.assertEqual([row["sampleStartElapsedSeconds"] for row in samples], starts)
        missed = [row for row in events if row["event"] == "sampling-deadline-missed"]
        self.assertEqual(len(missed), 1)
        self.assertEqual(missed[0]["overrunSeconds"], 2.0)


class CurrentSourceTimingTests(unittest.TestCase):
    admit = CompilerTimingTests.admit
    testClosedConfigurationRejectsUnknownMissingDuplicateAndOverrideFields = CompilerTimingTests.testClosedConfigurationRejectsUnknownMissingDuplicateAndOverrideFields
    testAdmissionBindsExactHostedSourceSelectorAndUnchangedBudgets = CompilerTimingTests.testAdmissionBindsExactHostedSourceSelectorAndUnchangedBudgets
    testNativeArgvAddsOnlyTimingObservationsAndLegacyWrapperIsExact = CompilerTimingTests.testNativeArgvAddsOnlyTimingObservationsAndLegacyWrapperIsExact

    def setUp(self):
        CompilerTimingTests.setUp(self)
        self.config = copy.deepcopy(TIMING.CURRENT_PROFILE)
        self.assertEqual(self.config["schemaVersion"], 2)
        default = subprocess.check_output(["git", "show", self.config["sourceHead"] + ":Scripts/ci-selection.json"], cwd=ROOT)
        mapping = subprocess.check_output(["git", "show", self.config["sourceHead"] + ":Scripts/ci-selection-map.json"], cwd=ROOT)
        (self.root / "Scripts/ci-selection.json").write_bytes(default)
        (self.root / "Scripts/ci-selection-map.json").write_bytes(mapping)
        selector_path = self.root / "historical-native-ci.py"
        selector_path.write_bytes(subprocess.check_output(["git", "show",
            self.config["sourceHead"] + ":Scripts/v23-native-ci.py"], cwd=ROOT))
        spec = importlib.util.spec_from_file_location("current_selector", selector_path)
        selector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(selector)
        selected = selector.resolve_selection(json.loads(default), json.loads(mapping), TIMING.CURRENT_SELECTION_ID)
        self.resolved.write_bytes(selector.canonical(selected))
        self.assertEqual(len(json.loads(default)["unitTestSelectors"]), 738)
        self.assertEqual(len(json.loads(mapping)["groups"]), 41)
        self.assertEqual(selected["unitTestSelectors"], [
            "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/"
            "testParentFinalizationCheckNoIssueUsesOriginalFiveSagaHistory"])
        self.env.update(NATIVE_SELECTION_ID=TIMING.CURRENT_SELECTION_ID,
            DISPATCH_NATIVE_SELECTION_SHA256=self.config["resolvedSelectionSHA256"])

    def git(self, *args):
        if args == ("cat-file", "commit", "HEAD"):
            parent = self.config.get("parentHead", self.config["sourceHead"])
            return ("tree " + "c" * 40 + "\nparent " + parent + "\n\nmessage\n").encode()
        return CompilerTimingTests.git(self, *args)

    def testCurrentSourceAndConfigurationCannotDriftTogether(self):
        # Equivalent schema2 anti-rebinding pair; the superclass retains the
        # original f6 case independently.
        for path in TIMING.SOURCE_PATHS:
            changed = copy.deepcopy(self.config)
            changed["sourceTrees"][path] = "b" * 40
            def changed_git(*args):
                return b"b" * 40 if args == ("rev-parse", "HEAD:" + path) else self.git(*args)
            with self.subTest(jointTreeDrift=path), self.assertRaisesRegex(ValueError, "fixed current"):
                self.admit(config=changed, git=changed_git)
        for key, path in (("selectionSHA256", self.root / "Scripts/ci-selection.json"),
                          ("selectionMapSHA256", self.root / "Scripts/ci-selection-map.json"),
                          ("resolvedSelectionSHA256", self.resolved)):
            before = path.read_bytes()
            changed_bytes = before + b" "
            path.write_bytes(changed_bytes)
            changed = copy.deepcopy(self.config)
            changed[key] = hashlib.sha256(changed_bytes).hexdigest().upper()
            environment = dict(self.env)
            if key == "resolvedSelectionSHA256": environment["DISPATCH_NATIVE_SELECTION_SHA256"] = changed[key]
            with self.subTest(jointSelectorDrift=key), self.assertRaisesRegex(ValueError, "fixed current"):
                self.admit(config=changed, environment=environment)
            path.write_bytes(before)
        for path, tree in self.config["sourceTrees"].items():
            actual = subprocess.check_output(["git", "rev-parse", self.config["sourceHead"] + ":" + path], cwd=ROOT).decode().strip()
            self.assertEqual(actual, tree)
        for key, path in (("selectionSHA256", "Scripts/ci-selection.json"),
                          ("selectionMapSHA256", "Scripts/ci-selection-map.json")):
            actual = subprocess.check_output(["git", "show", self.config["sourceHead"] + ":" + path], cwd=ROOT)
            self.assertEqual(hashlib.sha256(actual).hexdigest().upper(), self.config[key])
        self.assertEqual(hashlib.sha256(self.resolved.read_bytes()).hexdigest().upper(),
            self.config["resolvedSelectionSHA256"])

    def testCurrentObservationDeniesIndirectParentAndOtherSelectedQuestion(self):
        def wrong_parent(*args):
            return b"parent " + b"b" * 40 + b"\n\nmessage\n" if args == ("cat-file", "commit", "HEAD") else self.git(*args)
        with self.assertRaisesRegex(ValueError, "direct parent"):
            self.admit(git=wrong_parent)
        with self.assertRaisesRegex(ValueError, "NATIVE_SELECTION_ID"):
            self.admit(environment={**self.env, "NATIVE_SELECTION_ID": "catalog-file-authority"})


class ShallowSourceTimingTests(CurrentSourceTimingTests):
    def setUp(self):
        super().setUp()
        self.config = copy.deepcopy(TIMING.SHALLOW_PROFILE)
        self.assertEqual(self.config, TIMING.SHALLOW_PROFILE)
        self.assertEqual(self.config["schemaVersion"], 3)

    def testActualDepthOneCommitRetainsParentWithoutTraversableHistory(self):
        origin, shallow = self.root / "origin", self.root / "shallow"
        origin.mkdir()
        def run(at, *args):
            return subprocess.check_output(["git", *args], cwd=at, stderr=subprocess.PIPE)
        run(origin, "init", "--quiet")
        for key, value in (("user.name", "Timing Test"), ("user.email", "timing@example.invalid"),
                           ("commit.gpgsign", "false")):
            run(origin, "config", key, value)
        run(origin, "commit", "--quiet", "--allow-empty", "-m", "parent")
        parent = run(origin, "rev-parse", "HEAD").decode().strip()
        run(origin, "commit", "--quiet", "--allow-empty", "-m", "child")
        run(self.root, "clone", "--quiet", "--depth=1", origin.as_uri(), str(shallow))
        self.assertEqual(run(shallow, "rev-parse", "--is-shallow-repository").strip(), b"true")
        with self.assertRaises(subprocess.CalledProcessError):
            run(shallow, "rev-parse", "--verify", "HEAD^")
        self.assertIsNone(TIMING.require_direct_parent(lambda *a: run(shallow, *a), parent))
        with self.assertRaisesRegex(ValueError, "direct parent"):
            TIMING.require_direct_parent(lambda *a: run(shallow, *a), "b" * 40)
        # Full production admission uses the fixed b8 parent, independently of
        # this miniature Git fixture's arbitrary object identities.
        self.assertEqual(self.admit(), self.env["GITHUB_SHA"])

    def testHeaderRejectsRootMergeDuplicateMalformedAndMessageOnlyParent(self):
        parent = self.config["parentHead"].encode()
        valid = b"parent " + parent
        for raw in (b"tree " + b"c" * 40 + b"\n\nparent " + parent,
                    valid + b"\nparent " + b"d" * 40 + b"\n\nmessage",
                    valid + b"\n" + valid + b"\n\nmessage",
                    b"parent\t" + parent + b"\n\nmessage",
                    valid + b" \n\nmessage", valid + b"\nmessage"):
            def malformed(*args):
                return raw if args == ("cat-file", "commit", "HEAD") else self.git(*args)
            with self.subTest(raw=raw), self.assertRaisesRegex(ValueError, "direct parent"):
                self.admit(git=malformed)
        def message_parent(*args):
            return self.git(*args) + b"parent foreign\n" if args == ("cat-file", "commit", "HEAD") else self.git(*args)
        self.assertEqual(self.admit(git=message_parent), self.env["GITHUB_SHA"])


class CommandSourceTimingTests(ShallowSourceTimingTests):
    def setUp(self):
        super().setUp()
        self.config = copy.deepcopy(TIMING.COMMAND_PROFILE)
        self.assertEqual(TIMING.validate_configuration(self.config), TIMING.COMMAND_PROFILE)
        self.assertEqual(self.config["schemaVersion"], 4)

    def testFinalCommandColumnPreservesLongSpacedShortAndNoArgumentExecutables(self):
        for executable in ("/Applications/Xcode_26.6.app/Contents/Developer/Toolchains/"
                           "XcodeDefault.xctoolchain/usr/bin/swift-frontend",
                           "/Applications/Tool Chain/usr/bin/swift-frontend", "xcodebuild"):
            for arguments in (" -primary-file /workspace/A.swift", "", "\t-filelist /workspace/source-files"):
                metadata = "123 45 5.2 0:12.44 00:20 15744 S Mon Sep 14 22:05:03 2026 " + executable
                processes, malformed = TIMING.parse_processes(metadata)
                self.assertEqual(malformed, 0)
                rendered = executable + arguments
                output = ("123 Mon Sep 14 22:05:03 2026 " + rendered + "\n").encode()
                def query(argv, **kwargs):
                    self.assertEqual(argv, ["/bin/ps", "-ww", "-p", "123", "-o", "pid=,lstart=,command="])
                    self.assertEqual(kwargs["timeout"], 2)
                    self.assertEqual(kwargs["env"]["LC_ALL"], "C")
                    return subprocess.CompletedProcess(argv, 0, output, b"")
                with self.subTest(executable=executable, arguments=arguments), \
                     mock.patch.object(TIMING.subprocess, "run", side_effect=query):
                    self.assertEqual(TIMING.process_commands(processes), {processes[0]["key"]: rendered})

    def testFinalCommandColumnRejectsIdentityAndExecutablePrefixSubstitution(self):
        executable = "/Applications/Xcode_26.6.app/Contents/Developer/usr/bin/swift-frontend"
        processes, _ = TIMING.parse_processes("123 45 5.2 0:12.44 00:20 15744 S Mon Sep 14 22:05:03 2026 " + executable)
        prefix = "123 Mon Sep 14 22:05:03 2026 "
        valid = prefix + executable + " -primary-file /workspace/A.swift\n"
        for row in (valid.replace("123 ", "456 ", 1), valid.replace("22:05:03", "22:05:04"),
                    prefix + executable + "-foreign -primary-file /workspace/A.swift\n",
                    prefix + "/unrelated/process secret\n", prefix + executable[:16] + " " + executable,
                    "not-a-pid Mon Sep 14 22:05:03 2026 " + executable, "123 malformed", ""):
            with self.subTest(row=row), mock.patch.object(TIMING.subprocess, "run",
                    return_value=subprocess.CompletedProcess([], 1, row.encode(), b"")):
                self.assertEqual(TIMING.process_commands(processes), {})
        with mock.patch.object(TIMING.subprocess, "run") as query:
            self.assertEqual(TIMING.process_commands([]), {})
            query.assert_not_called()


def passive_fixture_source_archive(source_root, parent):
    # Prospective sources may live below an ignored directory in the actual
    # repository. git archive otherwise restricts output to that cwd prefix.
    repository = subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                         cwd=source_root, text=True).strip()
    return subprocess.check_output(["git", "archive", "--format=zip", parent], cwd=repository)


def run_passive_build_fixture(case, ci, directory, selector, receipt_exit=0, build_exit=0):
    """Real Git/receipt/shell/observer; substitute Darwin OS, Xcode and write failure.

    Shared only by the current interruption route's existing shell assertions.
    The fixture owns its Git objects/index/refs and does not modify ROOT's Git.
    """
    case.assertEqual(selector, TIMING.INTERRUPTION_SELECTION_ID)
    base = Path(directory).resolve()
    checkout = base / "c"
    checkout.mkdir()
    archive = passive_fixture_source_archive(ROOT, case.source_parent)
    extract_path = "\\\\?\\" + str(checkout) if os.name == "nt" else checkout
    zipfile.ZipFile(io.BytesIO(archive)).extractall(extract_path)
    owned = ("Scripts/build-smoke.sh", "Scripts/v23-native-ci.py", "Scripts/v23-compiler-timing.py",
             "Scripts/v23-compiler-timing.json", "Scripts/test-v23-compiler-timing.py")
    for relative in owned:
        (checkout / relative).write_bytes((ROOT / relative).read_bytes())
    subprocess.check_call(["git", "init", "-q", str(checkout)])
    common = subprocess.check_output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=ROOT, text=True).strip()
    (checkout / ".git/objects/info/alternates").write_text((Path(common) / "objects").as_posix() + "\n", encoding="utf-8", newline="\n")
    def git(*args, data=None):
        return subprocess.check_output(["git", *args], cwd=checkout, input=data)
    git("config", "core.autocrlf", "false")
    git("config", "core.longpaths", "true")
    git("read-tree", case.source_parent)
    for relative in owned:
        mode = git("ls-tree", case.source_parent, "--", relative).split()[0].decode()
        blob = git("hash-object", "-w", "--stdin", data=(checkout / relative).read_bytes()).decode().strip()
        git("update-index", "--add", "--cacheinfo", mode, blob, relative)
    tree = git("write-tree").decode().strip()
    identity = dict(os.environ, GIT_AUTHOR_NAME="Observer fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                    GIT_COMMITTER_NAME="Observer fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    head = subprocess.check_output(["git", "commit-tree", tree, "-p", case.source_parent,
                                   "-m", "Disposable observer fixture; no native evidence"],
                                  cwd=checkout, env=identity, text=True).strip()
    git("update-ref", "HEAD", head)
    for relative, expected in case.source_trees.items():
        case.assertEqual(git("rev-parse", "HEAD:" + relative).decode().strip(), expected)
    case.assertEqual(git("diff", "HEAD", "--"), b"")
    bash = Path(shutil.which("git")).resolve().parents[1] / "bin/bash.exe" if os.name == "nt" else Path(shutil.which("bash"))
    def shell_path(path):
        if os.name != "nt": return str(path)
        return subprocess.check_output([str(bash), "-c", 'cygpath -u "$1"', "_", str(path)], text=True).strip()
    binary = base / "bin"
    binary.mkdir()
    shim = base / "python-entry.py"
    shim.write_text('''import importlib.util,json,os,runpy,subprocess,sys
from pathlib import Path
from unittest import mock
target=sys.argv[1]; sys.argv=sys.argv[1:]
output=Path(os.environ['CI_ARTIFACT_DIR'])
if target == 'Scripts/v23-native-ci.py':
    with Path(os.environ['TEST_EVENTS_NATIVE']).open('a') as stream: stream.write('receipt\\n')
    original_open=Path.open
    def receipt_open(path,mode='r',*args,**kwargs):
        if path == output/os.environ['TEST_RECEIPT_NAME'] and mode=='xb' and os.environ['TEST_RECEIPT_EXIT']!='0':
            raise SystemExit(int(os.environ['TEST_RECEIPT_EXIT']))
        return original_open(path,mode,*args,**kwargs)
    with mock.patch.object(Path,'open',receipt_open): runpy.run_path(target,run_name='__main__')
    raise SystemExit(0)
if target != 'Scripts/v23-compiler-timing.py': raise AssertionError('unexpected Python entry')
spec=importlib.util.spec_from_file_location('observer_entry',target)
m=importlib.util.module_from_spec(spec)
with mock.patch.object(sys,'platform','darwin'): spec.loader.exec_module(m)
original_popen,original_check,original_run=subprocess.Popen,subprocess.check_output,subprocess.run
def launch(argv,*args,**kwargs):
    if argv and argv[0]=='xcodebuild':
        if argv != m.expected_command(os.environ,m.read_configuration(Path('Scripts/v23-compiler-timing.json'))):
            raise AssertionError('changed admitted build argv')
        if args or kwargs: raise AssertionError('changed inherited streams/process group')
        with (output/'observed-launch.json').open('x') as stream: json.dump(argv,stream)
        return original_popen([os.environ['TEST_BASH'],os.environ['TEST_XCODE'],*argv[1:]])
    return original_popen(argv,*args,**kwargs)
def check(argv,*args,**kwargs):
    if argv[:2]==['/bin/ps','-axo']:
        return b'123 45 9.0 0:12.00 00:20 2048 R Mon Sep 14 22:05:03 2026 /tool/swift-frontend\\n'
    return original_check(argv,*args,**kwargs)
def run(argv,*args,**kwargs):
    if argv[:2]==['/bin/ps','-ww']:
        return subprocess.CompletedProcess(argv,0,b'123 Mon Sep 14 22:05:03 2026 /tool/swift-frontend -module-name FieldEvidenceAppTests\\n',b'')
    return original_run(argv,*args,**kwargs)
def forbidden(*args,**kwargs): raise AssertionError('passive profile must not query or add flags')
with mock.patch.object(m.subprocess,'Popen',side_effect=launch), mock.patch.object(m.subprocess,'check_output',side_effect=check), mock.patch.object(m.subprocess,'run',side_effect=run), mock.patch.object(m.os,'getloadavg',return_value=(1.,1.,1.),create=True), mock.patch.object(m,'run_observed_capability',side_effect=forbidden), mock.patch.object(m,'diagnostic_command',side_effect=forbidden):
    raise SystemExit(m.main())
''', encoding="utf-8", newline="\n")
    (binary / "python3").write_text('#!/bin/bash\nexec "' + shell_path(Path(sys.executable)) + '" "' + shell_path(shim) + '" "$@"\n', encoding="utf-8", newline="\n")
    (binary / "python3").chmod(0o755)
    xcode = binary / "xcodebuild"
    xcode.write_text('''#!/bin/bash
printf "build\\n" >> "$TEST_EVENTS"
printf "%s\\n" "$@" > "$TEST_BUILD_ARGS"
sleep 0.1
if [ "$TEST_BUILD_EXIT" != 0 ]; then exit "$TEST_BUILD_EXIT"; fi
mkdir -p "$CI_ARTIFACT_DIR/Build.xcresult" "$RUNNER_TEMP/FieldEvidenceDerivedData/Build/Products/Debug-iphonesimulator/FieldEvidenceApp.app"
touch "$CI_ARTIFACT_DIR/Build.xcresult/result" "$RUNNER_TEMP/FieldEvidenceDerivedData/Build/Products/fixture.xctestrun" "$RUNNER_TEMP/FieldEvidenceDerivedData/Build/Products/Debug-iphonesimulator/FieldEvidenceApp.app/Info.plist"
''', encoding="utf-8", newline="\n")
    xcode.chmod(0o755)
    artifact = base / "artifact"
    artifact.mkdir()
    resolved = artifact / "ci-selection.selected.json"
    resolved.write_bytes(ci.canonical(case.selected))
    udid = "00000000-0000-0000-0000-000000000001"
    e = dict(os.environ, **case.bound_environment())
    e.update(GITHUB_WORKSPACE=str(checkout), GITHUB_SHA=head, NATIVE_SELECTION_ID=selector,
        PROJECT_PATH="FieldEvidenceApp.xcodeproj", SCHEME="FieldEvidenceApp", CONFIGURATION="Debug",
        CODE_SIGNING_ALLOWED="NO", CI_SIMULATOR_UDID=udid, CI_DESTINATION="platform=iOS Simulator,id=" + udid,
        CI_TASK_ID="V23-INTEGRATION-20260910", CI_TIER="D30", CI_SETUP_ARTIFACT_TIMEOUT_SECONDS="300",
        CI_BUILD_TIMEOUT_SECONDS="1800", CI_TEST_TIMEOUT_SECONDS="900", CI_UI_TIMEOUT_SECONDS="0",
        CI_TOTAL_BUDGET_SECONDS="3000", CI_RUN_UI_SMOKE="false", CI_SELECTOR_RUN_UI_SMOKE="false",
        RUNNER_ARCH="ARM64", DEVELOPER_DIR="/Applications/Xcode_26.6.app/Contents/Developer",
        MSYS2_ENV_CONV_EXCL="DEVELOPER_DIR",
        CI_ARTIFACT_DIR=str(artifact), CI_SELECTION_PATH=str(resolved), RUNNER_TEMP=str(base / "runner temp"),
        TEST_BASH=str(bash), TEST_XCODE=str(xcode), TEST_EVENTS=shell_path(base / "events"),
        TEST_EVENTS_NATIVE=str(base / "events"), TEST_BUILD_ARGS=shell_path(base / "build-args"),
        TEST_RECEIPT_EXIT=str(receipt_exit), TEST_RECEIPT_NAME=ci.NO_INDEX_RECEIPT, TEST_BUILD_EXIT=str(build_exit))
    admitted = subprocess.run([sys.executable, str(checkout / "Scripts/v23-native-ci.py"), "admit"],
                              cwd=checkout, env=e, capture_output=True, text=True)
    case.assertEqual(admitted.returncode, 0, admitted.stderr)
    result = subprocess.run([str(bash), "-c", 'export PATH="$1:$PATH"; exec bash Scripts/build-smoke.sh', "_", shell_path(binary)],
                            cwd=checkout, env=e, capture_output=True, text=True, timeout=60)
    events = (base / "events").read_text().splitlines() if (base / "events").exists() else []
    args = (base / "build-args").read_text().splitlines() if (base / "build-args").exists() else []
    if receipt_exit:
        case.assertFalse((artifact / ci.NO_INDEX_RECEIPT).exists())
        case.assertFalse((artifact / "v23-compiler-timing").exists())
    else:
        case.assertEqual(result.returncode, build_exit, result.stderr)
        receipt = ci.read_json(artifact / ci.NO_INDEX_RECEIPT)
        launched = ci.read_json(artifact / "observed-launch.json")
        compared, expected = list(launched), list(receipt["argv"])
        if os.name == "nt":
            for index in (10, 12):
                compared[index], expected[index] = Path(compared[index]).as_posix(), Path(expected[index]).as_posix()
        case.assertEqual(compared, expected)
        rows = [json.loads(line) for line in (artifact / "v23-compiler-timing/events.jsonl").read_bytes().splitlines()]
        case.assertEqual(rows[0]["command"], launched)
        case.assertEqual(rows[0]["baseCommand"], launched)
        case.assertEqual(rows[0]["buildWatchdogSeconds"], 1800)
        case.assertEqual(rows[-1]["buildReturnCode"], build_exit)
        case.assertFalse(rows[0]["nativeAcceptance"])
        case.assertFalse(rows[-1]["providerQualification"])
        case.assertFalse((artifact / "v23-compiler-timing/capability-events.jsonl").exists())
    return result, e, events, args


class InterruptionPassiveTimingTests(unittest.TestCase):
    admit = CompilerTimingTests.admit
    git = CurrentSourceTimingTests.git
    testAdmissionBindsExactHostedSourceSelectorAndUnchangedBudgets = CompilerTimingTests.testAdmissionBindsExactHostedSourceSelectorAndUnchangedBudgets

    def setUp(self):
        CompilerTimingTests.setUp(self)
        self.config = TIMING.read_configuration(ROOT / "Scripts/v23-compiler-timing.json")
        self.assertEqual(self.config, TIMING.INTERRUPTION_PROFILE)
        for relative in ("Scripts/ci-selection.json", "Scripts/ci-selection-map.json"):
            data = subprocess.check_output(["git", "show", self.config["sourceHead"] + ":" + relative], cwd=ROOT)
            (self.root / relative).write_bytes(data)
        spec = importlib.util.spec_from_file_location("passive_selector", ROOT / "Scripts/v23-native-ci.py")
        selector = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(selector)
        selected = selector.resolve_selection(
            json.loads((self.root / "Scripts/ci-selection.json").read_bytes()),
            json.loads((self.root / "Scripts/ci-selection-map.json").read_bytes()),
            TIMING.INTERRUPTION_SELECTION_ID)
        self.assertEqual(selected["unitTestSelectors"], [
            "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testRetainedLiveContextDefersCleanupUntilColdRecovery",
            "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEveryInterruptionRecoversOldOrFullyErasedNew"])
        self.assertEqual((selected["tier"], selected["buildTimeoutSeconds"], selected["testTimeoutSeconds"],
                          selected["setupArtifactTimeoutSeconds"], selected["totalBudgetSeconds"],
                          selected["uiTimeoutSeconds"], selected["runUISmoke"]),
                         ("D30", 1800, 900, 300, 3000, 0, False))
        self.resolved.write_bytes(selector.canonical(selected))
        self.env.update(NATIVE_SELECTION_ID=TIMING.INTERRUPTION_SELECTION_ID, CI_TIER="D30",
                        CI_BUILD_TIMEOUT_SECONDS="1800", CI_TOTAL_BUDGET_SECONDS="3000",
                        DISPATCH_NATIVE_SELECTION_SHA256=self.config["resolvedSelectionSHA256"])
        self.command = TIMING.expected_command(self.env, self.config)

    def testClosedPassiveProfileRejectsMissingExtraAndJointSourceDrift(self):
        self.assertEqual(TIMING.validate_configuration(self.config), self.config)
        for key in self.config:
            changed = copy.deepcopy(self.config)
            del changed[key]
            with self.subTest(missing=key), self.assertRaises(ValueError):
                TIMING.validate_configuration(changed)
        for key, value in (("extra", True), ("schemaVersion", True), ("schemaVersion", 6),
                           ("parentHead", "a" * 40), ("sourceHead", "a" * 40),
                           ("sampleIntervalSeconds", 1), ("sampleIntervalSeconds", True), ("sampleIntervalSeconds", 5.0),
                           ("mode", "timing-command-source-v4"), ("selectionSHA256", "A" * 64),
                           ("selectionMapSHA256", "B" * 64), ("resolvedSelectionSHA256", "C" * 64)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                TIMING.validate_configuration({**self.config, key: value})
        for path in TIMING.SOURCE_PATHS:
            changed = copy.deepcopy(self.config)
            changed["sourceTrees"][path] = "b" * 40
            def drift(*args):
                return b"b" * 40 if args == ("rev-parse", "HEAD:" + path) else self.git(*args)
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "fixed interruption"):
                self.admit(config=changed, git=drift)
            actual = subprocess.check_output(["git", "rev-parse", self.config["sourceHead"] + ":" + path], cwd=ROOT).decode().strip()
            self.assertEqual(actual, self.config["sourceTrees"][path])
        target = self.root / "profile.json"
        raw = json.dumps(self.config)
        target.write_text(raw[:-1] + ',"schemaVersion":5}', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            TIMING.read_configuration(target)

    def testPassiveArgvRejectsAddedFlagsOmittedIndexAndForeignAction(self):
        self.assertEqual(self.command, TIMING.expected_command(self.env)[:-1] +
                         ["COMPILER_INDEX_STORE_ENABLE=NO", "build-for-testing"])
        for command in (TIMING.expected_command(self.env), TIMING.diagnostic_command(self.command),
                        self.command[:-1] + ["test"], self.command + ["clean"],
                        self.command[:-1] + ["-only-testing:FieldEvidenceAppTests", self.command[-1]],
                        self.command[:-2] + ["COMPILER_INDEX_STORE_ENABLE=YES", self.command[-1]],
                        self.command[:-1] + ["COMPILER_INDEX_STORE_ENABLE=NO", self.command[-1]]):
            with self.subTest(command=command), self.assertRaisesRegex(ValueError, "exact base build argv"):
                self.admit(command=command)

    def testPassiveAdmissionRejectsRootMergeIndirectAndMalformedParent(self):
        valid = b"parent " + self.config["parentHead"].encode()
        for header in (b"tree " + b"c" * 40, b"parent " + b"d" * 40,
                       valid + b"\nparent " + b"d" * 40, valid + b"\n" + valid,
                       valid + b" ", valid.replace(b"parent ", b"parent\t")):
            def wrong(*args):
                return header + b"\n\nmessage" if args == ("cat-file", "commit", "HEAD") else self.git(*args)
            with self.subTest(header=header), self.assertRaisesRegex(ValueError, "exact single direct parent"):
                self.admit(git=wrong)

    def testPassiveFixtureArchiveUsesRepositoryRootFromIgnoredNestedSource(self):
        repository = self.root / "archive-origin"
        (repository / "Scripts").mkdir(parents=True)
        body = b"fixture build bytes\n"
        (repository / "Scripts/build-smoke.sh").write_bytes(body)
        (repository / ".gitignore").write_text("nested/\n", encoding="utf-8")
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=repository, stderr=subprocess.PIPE)
        git("init", "--quiet")
        git("config", "core.autocrlf", "false")
        git("config", "core.hooksPath", str(self.root / "no-hooks"))
        git("add", "--", ".gitignore", "Scripts/build-smoke.sh")
        git("-c", "user.name=Archive fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Archive origin")
        parent = git("rev-parse", "HEAD").decode().strip()
        nested = repository / "nested/prospective/source"
        nested.mkdir(parents=True)
        # Reproduce the actual failure: a valid, empty archive from the nested cwd.
        restricted = subprocess.check_output(["git", "archive", "--format=zip", parent], cwd=nested)
        self.assertEqual(zipfile.ZipFile(io.BytesIO(restricted)).namelist(), [])
        archive = passive_fixture_source_archive(nested, parent)
        self.assertEqual(archive, passive_fixture_source_archive(repository, parent))
        with zipfile.ZipFile(io.BytesIO(archive)) as retained:
            self.assertEqual(retained.namelist(), [".gitignore", "Scripts/", "Scripts/build-smoke.sh"])
            self.assertEqual(retained.read("Scripts/build-smoke.sh"), body)
        with self.assertRaises(subprocess.CalledProcessError):
            passive_fixture_source_archive(nested, "0" * 40)

    def make_real_git_fixture(self):
        checkout = self.root / "checkout"
        origin = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=ROOT).decode().strip()
        subprocess.check_call(["git", "clone", "--quiet", "--shared", "--no-checkout", origin, str(checkout)])
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=checkout, stderr=subprocess.PIPE)
        git("config", "core.autocrlf", "false")
        git("config", "core.hooksPath", str(self.root / "no-hooks"))
        git("sparse-checkout", "set", "--no-cone", "/Scripts/")
        git("checkout", "--quiet", "--detach", self.config["sourceHead"])
        for name in ("v23-compiler-timing.py", "v23-compiler-timing.json"):
            (checkout / "Scripts" / name).write_bytes((ROOT / "Scripts" / name).read_bytes())
        git("add", "--", "Scripts/v23-compiler-timing.py", "Scripts/v23-compiler-timing.json")
        git("-c", "user.name=Protocol fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Passive observer fixture; no native evidence")
        head = git("rev-parse", "HEAD").decode().strip()
        for path, expected in self.config["sourceTrees"].items():
            self.assertEqual(git("rev-parse", "HEAD:" + path).decode().strip(), expected)
        self.assertEqual(git("diff", "HEAD", "--", *TIMING.SOURCE_PATHS), b"")
        return checkout, head

    def testRealMainPreservesArgvAndRetainsNonzeroSamplerFailureAndInterruptedEvidence(self):
        # Real Git/admission/main/observer run. Windows substitutes only the
        # Darwin platform and OS process interfaces; no admission is mocked.
        checkout, head = self.make_real_git_fixture()
        original_popen, original_check, original_run = subprocess.Popen, subprocess.check_output, subprocess.run
        compiler = "123 45 9.0 0:12.00 00:20 2048 R Mon Sep 14 22:05:03 2026 /tool/swift-frontend\n"
        old_defaults = TIMING.admit.__defaults__
        self.addCleanup(setattr, TIMING.admit, "__defaults__", old_defaults)
        TIMING.admit.__defaults__ = ("darwin",)
        for label, status in (("success", 0), ("compiler-failure", 7), ("sampler-failure", 7), ("interrupted", None)):
            artifact = self.root / label
            artifact.mkdir()
            resolved = artifact / "ci-selection.selected.json"
            resolved.write_bytes(self.resolved.read_bytes())
            env = dict(self.env, GITHUB_SHA=head, CI_ARTIFACT_DIR=str(artifact),
                       CI_SELECTION_PATH=str(resolved), RUNNER_TEMP=str(self.root / (label + "-runner")))
            command = TIMING.expected_command(env, self.config)
            launches = []
            class InterruptedChild:
                pid = 45
                signals = []
                def poll(self): return None
                def send_signal(self, value): self.signals.append(value)
                def wait(self, timeout): raise subprocess.TimeoutExpired("owned-build", timeout)
            child = InterruptedChild()
            def launch(argv, *args, **kwargs):
                if argv and argv[0] == "xcodebuild":
                    self.assertEqual(argv, command)
                    self.assertEqual(args, ())
                    self.assertEqual(kwargs, {})  # Preserve streams and process group.
                    self.assertIn(b'build-request', (artifact / "v23-compiler-timing/events.jsonl").read_bytes())
                    launches.append(argv)
                    if status is None: return child
                    return original_popen([sys.executable, "-c", "import time,sys;time.sleep(.1);sys.exit(" + str(status) + ")"])
                return original_popen(argv, *args, **kwargs)
            def check(argv, *args, **kwargs):
                if argv[:2] == ["/bin/ps", "-axo"]:
                    if label == "sampler-failure": raise OSError("test-only ps unavailable")
                    if status is None: signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
                    return compiler.encode()
                return original_check(argv, *args, **kwargs)
            def run(argv, *args, **kwargs):
                if argv[:2] == ["/bin/ps", "-ww"]:
                    return subprocess.CompletedProcess(argv, 0,
                        b"123 Mon Sep 14 22:05:03 2026 /tool/swift-frontend -module-name FieldEvidenceAppTests\n", b"")
                return original_run(argv, *args, **kwargs)
            previous_handler = signal.getsignal(signal.SIGTERM)
            with self.subTest(label=label), mock.patch.object(TIMING.Path, "cwd", return_value=checkout), \
                 mock.patch.object(TIMING.sys, "argv", ["Scripts/v23-compiler-timing.py", "--", *command]), \
                 mock.patch.dict(TIMING.os.environ, env), \
                 mock.patch.object(TIMING.os, "getloadavg", return_value=(1., 1., 1.), create=True), \
                 mock.patch.object(TIMING.subprocess, "Popen", side_effect=launch), \
                 mock.patch.object(TIMING.subprocess, "check_output", side_effect=check), \
                 mock.patch.object(TIMING.subprocess, "run", side_effect=run), \
                 mock.patch.object(TIMING, "diagnostic_command", side_effect=AssertionError("passive flags prohibited")), \
                 mock.patch.object(TIMING, "run_observed_capability", side_effect=AssertionError("passive query prohibited")):
                self.assertEqual(TIMING.main(), status if status is not None else 128 + signal.SIGTERM)
            self.assertEqual(launches, [command])
            self.assertEqual(signal.getsignal(signal.SIGTERM), previous_handler)
            events = [json.loads(line) for line in (artifact / "v23-compiler-timing/events.jsonl").read_bytes().splitlines()]
            first, terminal = events[0], events[-1]
            self.assertEqual((first["command"], first["baseCommand"], first["head"]), (command, command, head))
            self.assertEqual(first["buildWatchdogSeconds"], 1800)
            self.assertEqual(first["configuration"]["sampleIntervalSeconds"], 5)
            self.assertFalse(first["nativeAcceptance"])
            self.assertFalse(first["providerQualification"])
            self.assertFalse(terminal["nativeAcceptance"])
            self.assertFalse(terminal["providerQualification"])
            self.assertEqual(terminal["buildReturnCode"], status)
            self.assertFalse((artifact / "v23-compiler-timing/capability-events.jsonl").exists())
            if label == "sampler-failure":
                self.assertTrue(any(e["event"] == "observation-error" for e in events))
            if status is None:
                self.assertEqual(child.signals, [signal.SIGTERM])
                self.assertEqual(terminal["receivedSignals"], [signal.SIGTERM])
                self.assertIn("123@Mon Sep 14 22:05:03 2026", terminal["processesWithUnobservedTerminal"])


class CapabilityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="v23-capability-test-")
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        self.metadata = {"purpose": "compiler-timing-diagnostic", "head": "a" * 40,
                         "nativeAcceptance": False, "providerQualification": False,
                         "buildWatchdogSeconds": 1200}
        self.empty_sample = lambda: {"logicalCPUCount": 4, "loadAverages": [1.0, 1.0, 1.0],
                                     "processes": [], "malformedMetadataRows": 0}

    def rows(self):
        rows = [json.loads(line) for line in (self.output / "capability-events.jsonl").read_bytes().splitlines()]
        self.assertEqual(rows[0]["event"], "capability-query-request")
        self.assertEqual(rows[-1]["event"], "capability-terminal-observation")
        self.assertFalse(rows[-1]["nativeAcceptance"])
        self.assertFalse(rows[-1]["providerQualification"])
        self.assertEqual([r["elapsedSeconds"] for r in rows], sorted(r["elapsedSeconds"] for r in rows))
        return rows

    def query(self, program, **kwargs):
        return TIMING.run_observed_capability([sys.executable, "-c", program], self.output,
            self.metadata, sampler=kwargs.pop("sampler", self.empty_sample),
            commands_reader=lambda _: {}, interval=.01, **kwargs)

    def testTimeoutRetainsPartialStreamsAndKillsExactlyOneQuery(self):
        program = ("import sys,time;print('partial stdout',flush=True);"
                   "print('partial stderr',file=sys.stderr,flush=True);time.sleep(30)")
        children = []
        original = TIMING.subprocess.Popen

        def launch(*args, **kwargs):
            # Durable request exists before the child can emit any bytes.
            self.assertIn(b'capability-query-request', (self.output / "capability-events.jsonl").read_bytes())
            child = original(*args, **kwargs)
            children.append(child)
            return child

        with mock.patch.object(TIMING.subprocess, "Popen", side_effect=launch):
            self.assertEqual(self.query(program, timeout_seconds=.5), 65)
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].poll())
        self.assertIn(b"partial stdout", (self.output / "swift-frontend-help.txt").read_bytes())
        self.assertIn(b"partial stderr", (self.output / "swift-frontend-help.stderr.txt").read_bytes())
        rows = self.rows()
        self.assertEqual(rows[0]["timeoutSeconds"], .5)
        self.assertTrue(any(r["event"] == "capability-process" for r in rows))
        self.assertTrue(any(r["event"] == "capability-sample" for r in rows))
        self.assertTrue(rows[-1]["timedOut"])
        self.assertEqual(rows[-1]["status"], "timeout")
        self.assertFalse(rows[-1]["flagsAdmitted"])
        self.assertFalse((self.output / "events.jsonl").exists())

    def testSupportedFlagsAndBothStreamsSurviveObserverErrors(self):
        def failed():
            raise OSError("ps unavailable")

        program = ("import sys,time;print('  -warn-long-function-bodies <n>');"
                   "print('  -warn-long-expression-type-checking <n>');"
                   "print('help warning',file=sys.stderr);time.sleep(.1)")
        self.assertEqual(self.query(program, sampler=failed), 0)
        rows = self.rows()
        self.assertTrue(any(r["event"] == "capability-observation-error" for r in rows))
        self.assertEqual(rows[0]["timeoutSeconds"], 10)
        self.assertEqual(rows[0]["buildWatchdogSeconds"], 1200)
        self.assertEqual(rows[-1]["capabilityReturnCode"], 0)
        self.assertEqual(rows[-1]["status"], "supported")
        self.assertTrue(rows[-1]["flagsAdmitted"])
        self.assertIn(b"help warning", (self.output / "swift-frontend-help.stderr.txt").read_bytes())

    def testMissingFlagSubstringNonzeroAndMissingExecutableDenyWithEvidence(self):
        cases = [
            ("print('-warn-long-function-bodies <n>')", "missing-required-flag", 0),
            ("print('-warn-long-function-bodies-extra');print('-warn-long-expression-type-checking')", "missing-required-flag", 0),
            ("import sys;print('-warn-long-function-bodies');print('-warn-long-expression-type-checking');sys.exit(7)", "nonzero-exit", 7),
        ]
        base = self.output
        for i, (program, status, code) in enumerate(cases):
            self.output = base / str(i)
            self.output.mkdir()
            with self.subTest(status=status, program=program):
                self.assertEqual(self.query(program), 65)
                row = self.rows()[-1]
                self.assertEqual(row["status"], status)
                self.assertEqual(row["capabilityReturnCode"], code)
                self.assertFalse(row["flagsAdmitted"])
        self.output = base / "missing"
        self.output.mkdir()
        with mock.patch.object(TIMING.subprocess, "Popen") as launch:
            self.assertEqual(TIMING.run_observed_capability([str(base / "missing-frontend"), "-help-hidden"],
                self.output, self.metadata), 65)
        launch.assert_not_called()
        self.assertEqual(self.rows()[-1]["status"], "error")

    def testSlowObserverCannotExtendQueryDeadline(self):
        release, began = threading.Event(), threading.Event()

        def slow():
            began.set()
            release.wait(5)
            return self.empty_sample()

        started = time.monotonic()
        try:
            self.assertEqual(self.query("import time;time.sleep(30)", sampler=slow, timeout_seconds=.2), 65)
            self.assertTrue(began.is_set())
            self.assertLess(time.monotonic() - started, 2)
            self.assertTrue(self.rows()[-1]["samplerStillActive"])
            self.assertEqual(self.rows()[-1]["status"], "timeout")
            retained = (self.output / "capability-events.jsonl").read_bytes()
        finally:
            release.set()
        # The observer never writes to an event stream after its owner closes it.
        self.assertEqual((self.output / "capability-events.jsonl").read_bytes(), retained)

    def testSignalKillsReapsOwnedQueryAndDeniesBuild(self):
        class Child:
            pid = 42
            status = None
            signals = []
            killed = 0

            def poll(self): return self.status
            def send_signal(self, signum): self.signals.append(signum)
            def kill(self):
                self.killed += 1
                self.status = -signal.SIGTERM
            def wait(self, timeout=None):
                if self.status is None:
                    signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)
                    raise subprocess.TimeoutExpired("owned-query", timeout)
                return self.status

        child = Child()
        previous = signal.getsignal(signal.SIGTERM)
        with mock.patch.object(TIMING.subprocess, "Popen", return_value=child) as launch:
            self.assertEqual(self.query("unused"), 65)
        launch.assert_called_once()
        self.assertEqual(child.signals, [signal.SIGTERM])
        self.assertEqual(child.killed, 1)
        self.assertEqual(signal.getsignal(signal.SIGTERM), previous)
        terminal = self.rows()[-1]
        self.assertEqual(terminal["status"], "interrupted")
        self.assertEqual(terminal["receivedSignals"], [signal.SIGTERM])
        self.assertEqual(terminal["capabilityReturnCode"], -signal.SIGTERM)

    def testMainRequiresPinnedSingleQueryBeforeUnchangedBuild(self):
        direct = ["/Applications/Xcode_26.6.app/Contents/Developer/Toolchains/"
                  "XcodeDefault.xctoolchain/usr/bin/swift-frontend", "-help-hidden"]
        self.assertEqual(TIMING.capability_command({"DEVELOPER_DIR": TIMING.DEVELOPER_DIR}), direct)
        for env in ({}, {"DEVELOPER_DIR": "/other/Xcode"}):
            with self.assertRaises(ValueError):
                TIMING.capability_command(env)
        (self.output / "Scripts").mkdir()
        config = json.dumps(TIMING.COMMAND_PROFILE).encode()
        (self.output / "Scripts/v23-compiler-timing.json").write_bytes(config)
        base_command = ["xcodebuild", "original-value", "build-for-testing"]
        for status in (65, 0):
            artifact = self.output / str(status)
            artifact.mkdir()
            with mock.patch.object(TIMING.Path, "cwd", return_value=self.output), \
                 mock.patch.object(TIMING.sys, "argv", ["helper", "--", *base_command]), \
                 mock.patch.dict(TIMING.os.environ, {"CI_ARTIFACT_DIR": str(artifact), "DEVELOPER_DIR": TIMING.DEVELOPER_DIR}), \
                 mock.patch.object(TIMING, "admit", return_value="a" * 40), \
                 mock.patch.object(TIMING, "run_observed_capability", return_value=status) as query, \
                 mock.patch.object(TIMING, "run_observed_build", return_value=7) as build:
                self.assertEqual(TIMING.main(), 65 if status else 7)
                query.assert_called_once()
                self.assertEqual(query.call_args.args[0], direct)
                self.assertEqual(query.call_args.kwargs, {})  # No timeout override.
                self.assertEqual(query.call_args.args[2]["baseCommand"], base_command)
                if status:
                    build.assert_not_called()
                else:
                    build.assert_called_once_with(TIMING.diagnostic_command(base_command),
                        artifact / "v23-compiler-timing", query.call_args.args[2])


if __name__ == "__main__":
    unittest.main()
