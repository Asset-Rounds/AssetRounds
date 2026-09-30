#!/usr/bin/env python3
"""Execute the checked-in runtime variant shell; this is not native evidence."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKER = Path(os.environ.get("V23_RUNTIME_WORKER_SOURCE", ROOT / ".github/workflows/ios-ci-worker.yml"))
SOURCE = WORKER.read_text()
START = "              # V23 uses the native Apple silicon runtime; legacy routes keep universal.\n"
END = "              # End V23 runtime architecture selection.\n"


def selection_body():
    if SOURCE.count(START) != 1 or SOURCE.count(END) != 1:
        raise AssertionError("Expected one runtime architecture selection")
    return SOURCE.split(START, 1)[1].split(END, 1)[0]


class RuntimeArchitectureTests(unittest.TestCase):
    def execute_selection(self, contract, runner_arch, uname_arch):
        git_bash = Path("C:/Program Files/Git/bin/bash.exe")
        shell = str(git_bash) if git_bash.is_file() else shutil.which("bash")
        self.assertIsNotNone(shell, "Bash is required to exercise actual source")
        env = dict(os.environ, CI_NATIVE_ACCEPTANCE_CONTRACT=contract,
                   RUNNER_ARCH=runner_arch, V23_TEST_UNAME_ARCH=uname_arch)
        script = ('set -euo pipefail\n'
                  'uname() { printf "%s\\n" "$V23_TEST_UNAME_ARCH"; }\n'
                  + selection_body()
                  + 'printf "%s\\n" "$runtime_architecture_variant"\n')
        return subprocess.run([shell, "--noprofile", "--norc", "-c", script],
                              env=env, capture_output=True, text=True, timeout=10)

    def test_current_contract_selects_arm64_only_on_exact_native_host(self):
        result = self.execute_selection("v23.integration.current-native.v1", "ARM64", "arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "arm64")
        for runner, machine in (("X64", "arm64"), ("ARM64", "x86_64"),
                                ("", "arm64"), ("ARM64", "")):
            with self.subTest(runner=runner, machine=machine):
                bad = self.execute_selection("v23.integration.current-native.v1", runner, machine)
                self.assertNotEqual(bad.returncode, 0)
                self.assertEqual(bad.stdout, "")

    def test_legacy_contracts_retain_universal_without_new_host_requirements(self):
        for contract in ("none", "s10.4", "future.unrecognized"):
            for runner, machine in (("ARM64", "arm64"), ("X64", "x86_64")):
                with self.subTest(contract=contract, runner=runner):
                    result = self.execute_selection(contract, runner, machine)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), "universal")

    def test_variant_is_inside_existing_bitrise_missing_runtime_budget(self):
        start = SOURCE.index(START)
        missing_runtime = SOURCE.rfind('runtime_provision_budget_seconds="$(( CI_SIMULATOR_BOOT_TIMEOUT_SECONDS - simulator_elapsed_seconds ))"', 0, start)
        self.assertGreater(missing_runtime, 0)
        self.assertIn('test "$runtime_provision_budget_seconds" -gt 0', SOURCE[missing_runtime:start])
        command = SOURCE[start:SOURCE.index('provision_pipeline_status=', start)]
        self.assertIn('Scripts/run-with-timeout.sh "$runtime_provision_budget_seconds"', command)
        self.assertIn('/usr/bin/xcodebuild -downloadPlatform iOS', command)
        self.assertIn('-buildVersion "$SIMULATOR_RUNTIME_BUILD"', command)
        self.assertIn('-architectureVariant "$runtime_architecture_variant"', command)
        self.assertIn('env -u BITRISE_BUILD_CACHE_AUTH_TOKEN -u BITRISE_BUILD_CACHE_WORKSPACE_ID', command)
        self.assertIn('test "$CI_RUNNER_PROVIDER" = "bitrise"', SOURCE[:missing_runtime])
        after = SOURCE[SOURCE.index('provision_pipeline_status=', start):]
        self.assertIn('.name == $name and .buildversion == $build and .isAvailable == true', after)
        self.assertIn('provision_zero_and_exact_runtime_verified=true', after)


if __name__ == "__main__":
    unittest.main()
