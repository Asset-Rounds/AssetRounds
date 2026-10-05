"""Synthetic GH transport capability fixtures; no real API or native execution."""
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest import mock

path = Path(__file__).with_name("dev") / "v23-original.py"
spec = importlib.util.spec_from_file_location("original_raw_transport_fixture", path)
D = importlib.util.module_from_spec(spec)
spec.loader.exec_module(D)

HELP = b"FLAGS\n      --allow-escape-sequences   Preserve raw body\n"
RAW = b"\x1b[31moriginal\x00\xff\n"

class RawAPITransportTests(unittest.TestCase):
    def test_advertised_flag_preserves_exact_raw_body_for_all_endpoint_kinds(self):
        for endpoint in ("repos/a/b/actions/jobs/1/logs",
                         "repos/a/b/actions/runs/2/logs",
                         "repos/a/b/actions/artifacts/3/zip"):
            with self.subTest(endpoint=endpoint):
                with mock.patch.object(D.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, HELP, b""),
                    subprocess.CompletedProcess([], 0, RAW, b"")]) as call:
                    self.assertIs(D.api_bytes(endpoint), RAW)
                self.assertEqual(call.call_args_list, [
                    mock.call(["gh", "api", "--help"], cwd=D.ROOT, capture_output=True, check=True),
                    mock.call(["gh", "api", endpoint, "--allow-escape-sequences"],
                              cwd=D.ROOT, capture_output=True, check=True)])

    def test_older_cli_or_misleading_mentions_keep_exact_legacy_argv(self):
        for help_raw in (b"FLAGS\n  --hostname string\n",
                         b"See --allow-escape-sequences in a newer release\n",
                         b"  --allow-escape-sequences-extra dummy\n"):
            with self.subTest(help=help_raw):
                with mock.patch.object(D.subprocess, "run", side_effect=[
                    subprocess.CompletedProcess([], 0, help_raw, b""),
                    subprocess.CompletedProcess([], 0, RAW, b"")]) as call:
                    self.assertIs(D.api_bytes("logs"), RAW)
                self.assertEqual(call.call_args_list[-1],
                                 mock.call(["gh", "api", "logs"], cwd=D.ROOT,
                                           capture_output=True, check=True))

    def test_help_failure_preempts_get_and_no_sleep_or_fallback(self):
        failure = subprocess.CalledProcessError(1, ["gh", "api", "--help"], output=b"partial")
        with mock.patch.object(D.subprocess, "run", side_effect=failure) as call, \
                mock.patch.object(D.time, "sleep") as sleep:
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                D.api_bytes("logs")
        self.assertIs(caught.exception, failure)
        self.assertEqual(call.call_count, 1)
        sleep.assert_not_called()

    def test_get_failure_retains_existing_bound_without_returning_partial_bytes(self):
        failure = subprocess.CalledProcessError(1, ["gh", "api", "logs"],
                                                output=RAW, stderr=b"failed")
        with mock.patch.object(D.subprocess, "run", side_effect=[
                subprocess.CompletedProcess([], 0, HELP, b""), failure, failure, failure, failure]) as call, \
                mock.patch.object(D.time, "sleep") as sleep:
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                D.api_bytes("logs")
        self.assertIs(caught.exception, failure)
        self.assertEqual(call.call_count, 5)
        self.assertEqual(call.call_args_list[1:], [mock.call(
            ["gh", "api", "logs", "--allow-escape-sequences"], cwd=D.ROOT,
            capture_output=True, check=True)] * 4)
        self.assertEqual(sleep.call_args_list, [mock.call(15), mock.call(30), mock.call(45)])

    def test_streaming_payload_uses_same_capability_and_preserves_every_byte(self):
        for help_raw, suffix in ((HELP, ["--allow-escape-sequences"]), (b"old", [])):
            with self.subTest(suffix=suffix):
                holder = io.BytesIO(RAW)
                process = mock.Mock(stdout=holder)
                process.wait.return_value = 0
                process.poll.return_value = 0
                process.args = ["gh", "api", "fixture"]
                with mock.patch.object(D.subprocess, "run", return_value=
                        subprocess.CompletedProcess([], 0, help_raw, b"")), \
                        mock.patch.object(D.subprocess, "Popen", return_value=process) as born:
                    self.assertEqual(b"".join(D.phase1_payload_chunks(3)), RAW)
                born.assert_called_once_with(["gh", "api",
                    f"repos/{D.REPO}/actions/artifacts/3/zip"] + suffix,
                    cwd=D.ROOT, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL)
                self.assertTrue(holder.closed)
                process.wait.assert_called_once_with()
                process.terminate.assert_not_called()

    def test_streaming_help_failure_never_creates_process(self):
        failure = subprocess.CalledProcessError(1, ["gh", "api", "--help"], output=b"bad")
        with mock.patch.object(D.subprocess, "run", side_effect=failure), \
                mock.patch.object(D.subprocess, "Popen") as born:
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                next(D.phase1_payload_chunks(3))
        self.assertIs(caught.exception, failure)
        born.assert_not_called()

    def test_streaming_failure_never_claims_a_completed_body_or_retries(self):
        holder = io.BytesIO(RAW)
        process = mock.Mock(stdout=holder)
        process.wait.return_value = 1
        process.poll.return_value = 1
        process.args = ["gh", "api", "fixture"]
        with mock.patch.object(D.subprocess, "run", return_value=
                subprocess.CompletedProcess([], 0, HELP, b"")) as help_call, \
                mock.patch.object(D.subprocess, "Popen", return_value=process) as born:
            stream = D.phase1_payload_chunks(3)
            self.assertEqual(next(stream), RAW)
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                next(stream)
        self.assertEqual(caught.exception.returncode, 1)
        self.assertEqual(caught.exception.cmd, process.args)
        self.assertEqual(help_call.call_count, 1)
        self.assertEqual(born.call_count, 1)
        self.assertTrue(holder.closed)
        process.terminate.assert_not_called()

if __name__ == "__main__":
    unittest.main()
