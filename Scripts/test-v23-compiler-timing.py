#!/usr/bin/env python3
"""Windows-safe protocol tests. Every executed child is Python, never Xcode."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
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
        self.config = TIMING.read_configuration(ROOT / "Scripts/v23-compiler-timing.json")
        default = (ROOT / "Scripts/ci-selection.json").read_bytes()
        mapping = (ROOT / "Scripts/ci-selection-map.json").read_bytes()
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
        after = (ROOT / "Scripts/build-smoke.sh").read_bytes()
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
        output = ("123 Mon Sep 14 22:05:03 2026 /tool/swift-frontend /tool/swift-frontend -primary-file /workspace/A.swift\n"
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


if __name__ == "__main__":
    unittest.main()
