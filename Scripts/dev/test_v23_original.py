"""Fixture-only tests for v23-original.py (no network, no Git mutation, no dispatch).

Run from the repository root (Windows or macOS):
  python -m unittest discover -s Scripts/dev -p "test_v23_original.py"
  python Scripts/dev/prun.py Scripts/dev/test_v23_original.py -j 8

The single-job fixture under fixtures/single-36104533833 is a small copy of the
retained original 36104533833 (evidence root, read only): its three logs keep
only the lines the summarizer reads (the same regexes), so the summary still
equals the retained-summary.json it produced. The shared-route runs are
synthesized from it in memory.

Byte identity with the reviewed baseline tool (SHA-256 72CF4D9F...A6D2):
GOLDEN_* are digests the baseline produced for the same fixtures; the direct
comparisons also run when a baseline copy is available ($V23_ORIGINAL_BASELINE,
else <repo>/.codex-temp/native-tools/v23-original.py) and are skipped otherwise.
"""
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

REAL_SUBPROCESS_RUN = subprocess.run
HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
TOOL = HERE / "v23-original.py"
CURRENT = Path(os.environ.get("V23_ORIGINAL_BASELINE")
               or REPO_ROOT / ".codex-temp" / "native-tools" / "v23-original.py")
FIXTURE = HERE / "fixtures" / "single-36104533833"
SINGLE_RUN = 36104533833
DOT = chr(0xB7)
FIXED_NOW = "2026-09-25T12:00:00+00:00"
ZIP_TIME = (2026, 9, 25, 0, 0, 0)
# Produced by the reviewed baseline tool (72CF4D9F...A6D2) from these fixtures.
GOLDEN_SINGLE_SUMMARY = "1E1862364D523DE236E6D33A052BD55CEAFC7729A709FF6A45923133E64F3E24"
GOLDEN_SINGLE_JOB_LOG_SUMMARY = "F388941033DD1749D4C47B3CFAAEA5992A66B92E27C62DD509E3A59DF6C2C575"
GOLDEN_SHARED_SUMMARY = "3D7A91FFB6D16AB95D2B42A8C30A39E1FF7D4770BDDC8AF884D316092AC338C0"
GOLDEN_SINGLE_DISPATCH = "1B125F39D6BE3B06B210A5DF43222AB393BB065B8B69E5429D19857F155CF4E8"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


NEW = load(TOOL, "v23_original_next")
OLD = load(CURRENT, "v23_original_current") if CURRENT.is_file() else None
REPO = NEW.REPO


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def zip_bytes(files):
    """Deterministic on every platform: fixed time, stored entries, fixed attributes."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as bundle:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=ZIP_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 0
            info.external_attr = 0o644 << 16
            bundle.writestr(info, data)
    return buffer.getvalue()


@contextlib.contextmanager
def evidence_root(module, root):
    with mock.patch.object(module, "EVIDENCE", root), \
            mock.patch.object(module, "LEDGER", root / "v23-original-ledger.jsonl"), \
            mock.patch.object(module, "ATTEMPTS", root / "v23-original-attempts"), \
            mock.patch.object(module, "now", lambda: FIXED_NOW), \
            mock.patch("time.sleep", lambda seconds: None):
        yield


class FakeGitHub:
    """Serves one completed run; honours per_page/page and records every call."""

    def __init__(self, run, jobs, artifacts, blobs, logs):
        self.run, self.jobs, self.artifacts, self.blobs, self.logs = run, jobs, artifacts, blobs, logs
        self.calls = []

    def _page(self, items, key, query):
        size = int(re.search(r"per_page=(\d+)", query).group(1))
        page = re.search(r"page=(\d+)$", query) if "&page=" in query else None
        start = (int(page.group(1)) - 1) * size if page else 0
        return {key: copy.deepcopy(items[start:start + size]), "total_count": len(items)}

    def api(self, path):
        self.calls.append(("api", path))
        base = f"repos/{REPO}/actions/runs/{self.run['id']}"
        if path == base:
            return copy.deepcopy(self.run)
        if path.startswith(base + "/attempts/1/jobs?"):
            return self._page(self.jobs, "jobs", path.split("?", 1)[1])
        if path.startswith(base + "/artifacts?"):
            return self._page(self.artifacts, "artifacts", path.split("?", 1)[1])
        raise AssertionError("unexpected api path " + path)

    def api_bytes(self, path):
        self.calls.append(("bytes", path))
        if path == f"repos/{REPO}/actions/runs/{self.run['id']}/attempts/1/logs":
            return self.logs
        match = re.fullmatch(rf"repos/{re.escape(REPO)}/actions/artifacts/(\d+)/zip", path)
        if match and int(match.group(1)) in self.blobs:
            return self.blobs[int(match.group(1))]
        raise AssertionError("unexpected download " + path)


# --------------------------------------------------------------------------
# Existing single-job selections: identical outputs and code path.
# --------------------------------------------------------------------------

def stage_single(root, drop_test_log=False):
    target = root / str(SINGLE_RUN)
    shutil.copytree(FIXTURE, target, ignore=shutil.ignore_patterns("retained-summary.json"))
    if drop_test_log:
        (target / "artifact" / "test-smoke.log").unlink()
    return target


def summarize_bytes(module, drop_test_log):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        directory = stage_single(root, drop_test_log)
        with evidence_root(module, root), contextlib.redirect_stdout(io.StringIO()):
            module.summarize(SINGLE_RUN)
        return (directory / "summary.json").read_bytes()


def tree_bytes(directory):
    walk = Path("\\\\?\\" + str(directory.resolve())) if os.name == "nt" else directory.resolve()
    return {p.relative_to(walk).as_posix(): p.read_bytes() for p in sorted(walk.rglob("*")) if p.is_file()}


class GenericExtractionTests(unittest.TestCase):
    def test_empty_original_log_zip_publishes_empty_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "logs.zip"
            archive.write_bytes(zip_bytes({}))
            target = root / "run-logs"
            NEW.extract(archive, target)
            self.assertTrue(target.is_dir())
            self.assertEqual(list(target.iterdir()), [])
            self.assertFalse(root.joinpath("run-logs.partial").exists())

    def test_nonempty_original_log_zip_keeps_real_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "logs.zip"
            archive.write_bytes(zip_bytes({"job/log.txt": b"original log\n"}))
            target = root / "run-logs"
            NEW.extract(archive, target)
            self.assertEqual(target.joinpath("job/log.txt").read_bytes(), b"original log\n")
            self.assertFalse(root.joinpath("run-logs.partial").exists())

    def test_empty_zip_never_replaces_existing_retained_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "logs.zip"
            archive.write_bytes(zip_bytes({}))
            target = root / "run-logs"
            target.mkdir()
            sentinel = target / "retained.txt"
            sentinel.write_bytes(b"keep original")
            with self.assertRaises(SystemExit):
                NEW.extract(archive, target)
            self.assertEqual(sentinel.read_bytes(), b"keep original")

    def test_unsafe_zip_refuses_before_temporary_directory_creation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "logs.zip"
            archive.write_bytes(zip_bytes({"../escaped.txt": b"unsafe"}))
            target = root / "run-logs"
            with self.assertRaises(SystemExit):
                NEW.extract(archive, target)
            self.assertFalse(target.exists())
            self.assertFalse(root.joinpath("run-logs.partial").exists())
            self.assertFalse(root.parent.joinpath("escaped.txt").exists())


class SingleJobIdentityTests(unittest.TestCase):
    @unittest.skipUnless(OLD, "current tool not present")
    def test_summary_bytes_identical_to_current_tool(self):
        for drop in (False, True):
            with self.subTest(jobLogFallback=drop):
                self.assertEqual(summarize_bytes(NEW, drop), summarize_bytes(OLD, drop))

    def test_summary_bytes_equal_the_baseline_golden_digests(self):
        self.assertEqual(sha(summarize_bytes(NEW, False)), GOLDEN_SINGLE_SUMMARY)
        self.assertEqual(sha(summarize_bytes(NEW, True)), GOLDEN_SINGLE_JOB_LOG_SUMMARY)

    def test_summary_equals_retained_original_summary(self):
        produced = json.loads(summarize_bytes(NEW, False))
        retained = json.loads((FIXTURE / "retained-summary.json").read_text(encoding="utf-8"))
        produced.pop("atUTC")
        retained.pop("atUTC")
        self.assertEqual(produced, retained)
        self.assertNotIn("route", produced)

    def test_job_log_fallback_still_parses_the_step_log(self):
        produced = json.loads(summarize_bytes(NEW, True))
        self.assertTrue(produced["resultsFromJobLog"])
        self.assertEqual(produced["counts"], {"Failed": 1, "Passed": 14})

    def single_collect(self, module):
        run = json.loads((FIXTURE / "run.json").read_text(encoding="utf-8"))
        jobs = json.loads((FIXTURE / "jobs.json").read_text(encoding="utf-8"))["jobs"]
        files = {name: (FIXTURE / "artifact" / name).read_bytes()
                 for name in ("ci-selection.selected.json", "test-smoke.log", "build-smoke.log",
                              "unit-test-results.json", "native-admission.json")}
        blob = zip_bytes(files)
        listing = json.loads((FIXTURE / "artifacts.json").read_text(encoding="utf-8"))["artifacts"]
        listing[0]["digest"] = "sha256:" + hashlib.sha256(blob).hexdigest()
        folder = f"GitHub Xcode 26.6 acceptance {DOT} none {DOT} none _ verify"
        logs = zip_bytes({f"{folder}/23_Run targeted tests.txt":
                          (FIXTURE / "run-logs" / folder / "23_Run targeted tests.txt").read_bytes(),
                          f"0_{folder}.txt": b"whole job\n"})
        fake = FakeGitHub(run, jobs, listing, {listing[0]["id"]: blob}, logs)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / str(SINGLE_RUN)
            directory.mkdir()
            shutil.copy(FIXTURE / "dispatch.json", directory / "dispatch.json")
            output = io.StringIO()
            with evidence_root(module, root), mock.patch.object(module, "api", fake.api), \
                    mock.patch.object(module, "api_bytes", fake.api_bytes), contextlib.redirect_stdout(output):
                module.collect(SINGLE_RUN, False)
            return fake.calls, tree_bytes(directory), output.getvalue()

    @unittest.skipUnless(OLD, "current tool not present")
    def test_collect_identical_to_current_tool(self):
        new_calls, new_files, new_output = self.single_collect(NEW)
        old_calls, old_files, old_output = self.single_collect(OLD)
        self.assertEqual(new_calls, old_calls)
        self.assertEqual(new_output, old_output)
        self.assertEqual(sorted(new_files), sorted(old_files))
        for name in new_files:
            if name == "collector.claim.json":
                continue  # carries the collector's own SHA-256
            if name == "manifest.json":
                new_manifest, old_manifest = json.loads(new_files[name]), json.loads(old_files[name])
                for manifest in (new_manifest, old_manifest):
                    manifest["files"].pop("collector.claim.json")
                self.assertEqual(new_manifest, old_manifest)
                continue
            self.assertEqual(new_files[name], old_files[name], name)


# --------------------------------------------------------------------------
# Shared-build route fixtures.
# --------------------------------------------------------------------------

RUN = 36200000001
HEAD = "b215af485879fcbb15d6059ab0fdf13f54bc8ad8"
PARENT = "c614b8d1a5c1f6635eb270d1339a7c190511f7e5"
IDS = [f"S{n:02d}" for n in range(1, 41)]
ORDER = list(reversed(IDS))
TREE, XCTESTRUN, ARCHIVE = "1" * 64, "2" * 64, "3" * 64
PRODUCER_JOB = f"V23 shared coverage producer {DOT} build-for-testing (development only) / verify"


def consumer_job_name(pid):
    return f"V23 shared coverage consumer {DOT} {pid} (development only) / verify"


def selectors(pid):
    return [f"FieldEvidenceAppTests/Class{pid}Tests/test{name}" for name in ("Alpha", "Beta", "Gamma")]


def partitions_file():
    value = {"schema": "v23-coverage-partitions.v1", "censusHead": PARENT, "sweepOrder": ORDER,
             "partitions": [{"id": x, "estimatedSeconds": 60.0, "selectors": selectors(x)} for x in IDS]}
    return (json.dumps(value, indent=2) + "\n").encode()


def plan(raw=None):
    raw = partitions_file() if raw is None else raw
    return {"schemaVersion": 1, "taskID": "V23-INTEGRATION-20260910", "tier": "D40P", "runUISmoke": False,
            "setupArtifactTimeoutSeconds": 300, "buildTimeoutSeconds": 2400, "testTimeoutSeconds": 0,
            "uiTimeoutSeconds": 0, "totalBudgetSeconds": 3000,
            "unitTestSelectors": [s for x in ORDER for s in selectors(x)], "uiTestSelectors": [],
            "sharedCoverage": {"partitionsPath": "Scripts/v23-coverage-partitions.json",
                               "partitionsSHA256": sha(partitions_file()), "partitionIDs": ORDER,
                               "partitionID": None, "developmentOnly": True, "acceptance": False}}


def consumer_selection(pid):
    value = copy.deepcopy(plan())
    value.update(tier="D50C", buildTimeoutSeconds=0, testTimeoutSeconds=3000, totalBudgetSeconds=3600,
                 unitTestSelectors=selectors(pid))
    value["sharedCoverage"]["partitionID"] = pid
    return value


def test_line(selector, state, seconds=None):
    _, cls, method = selector.split("/")
    tail = f" ({seconds:.3f} seconds)." if seconds is not None else "."
    return f"Test Case '-[FieldEvidenceAppTests.{cls} {method}]' {state}{tail}\n"


def passing_log(pid):
    return "".join(test_line(s, "started") + test_line(s, "passed", 0.25) for s in selectors(pid))


def step(number, name, conclusion, start=None, seconds=0):
    base = 1_790_000_000 if start is None else start
    stamp = lambda offset: f"2026-09-25T{(base + offset) // 3600 % 24:02d}:{(base + offset) // 60 % 60:02d}:" \
                           f"{(base + offset) % 60:02d}Z"
    return {"number": number, "name": name, "status": "completed", "conclusion": conclusion,
            "started_at": stamp(0), "completed_at": stamp(seconds)}


class SharedScenario:
    """One synthetic shared run: 40 consumers x 3 methods, modelled on the retained original."""

    def __init__(self):
        self.plan = plan()
        self.plan_sha = sha(canonical(self.plan))
        self.payload_name = f"v23-shared-payload-{RUN}-1-{HEAD}"
        self.metadata = canonical({"schema": "v23-shared-payload.v1", "payloadArtifactName": self.payload_name,
                                   "products": {"treeSHA256": TREE, "xctestrunSHA256": XCTESTRUN}})
        self.receipt = {"schema": "v23-shared-payload-receipt.v1", "role": "producer",
                        "payloadArtifactName": self.payload_name,
                        "archive": {"name": "FieldEvidencePayload.tar", "bytes": 4096, "sha256": ARCHIVE},
                        "metadataSHA256": sha(self.metadata), "productsTreeSHA256": TREE,
                        "xctestrunSHA256": XCTESTRUN, "head": HEAD, "runID": str(RUN), "runAttempt": "1",
                        "developmentOnly": True, "acceptance": False}
        self.files = {"producer": self.producer_files(), **{x: self.consumer_files(x) for x in IDS}}
        self.job_logs = {}          # job name -> step log text (run-logs zip)
        self.whole_logs = {NEW.SHARED_SELECTION_JOB: "selection ok"}  # job name -> whole job log
        self.jobs = self.make_jobs()
        self.unlisted = set()       # labels whose artifact is absent from the listing
        self.bad_digest = set()
        self.extra_artifacts = []
        self.payload_listed = True

    def admission(self, role, pid):
        return canonical({"selectionID": NEW.SHARED_SELECTION_ID, "head": HEAD, "runID": str(RUN),
                          "runAttempt": "1", "sharedCoverage": {
                              "role": role, "partitionID": pid, "payloadArtifactName": self.payload_name,
                              "planSHA256": self.plan_sha, "partitionsSHA256": self.plan["sharedCoverage"][
                                  "partitionsSHA256"]}})

    def producer_files(self):
        return {"build-smoke.log": b"x.swift:1:2: warning: w\n** TEST BUILD SUCCEEDED **\n",
                "no-index-build-command.json": b"{}\n", "ci-selection.selected.json": canonical(self.plan),
                "native-admission.json": self.admission("producer", None),
                "v23-shared-payload.json": self.metadata,
                "v23-shared-payload-receipt.json": canonical(self.receipt)}

    def delta(self, pid, **changes):
        added = [{"path": f"Logs/Test/Run-{i:02d}.xcresult", "type": "directory"} for i in range(25)]
        value = {"schema": "v23-shared-deriveddata-delta.v1", "partitionID": pid,
                 "derivedDataRoot": "/Users/runner/work/_temp/FieldEvidenceDerivedData",
                 "excludedSubtree": "Build/Products", "beforeEntryCount": 1, "afterEntryCount": 26,
                 "added": added, "addedCount": 25, "changed": [], "changedCount": 0, "removed": [],
                 "removedCount": 0, "compileEvidence": [], "developmentOnly": True, "acceptance": False}
        value.update(changes)
        return value

    def fingerprint(self, pid, phase, tree=TREE, delta=None, delta_bytes=None, summary_changes=None,
                    matches_before=None, entry_count=9, partition=None):
        value = {"schema": "v23-shared-fingerprint.v1", "phase": phase,
                 "partitionID": pid if partition is None else partition,
                 "productsTreeSHA256": tree, "xctestrunSHA256": XCTESTRUN, "entryCount": entry_count,
                 "matchesProducer": tree == TREE, "buildEvidence": [], "error": None}
        if phase == "before":
            value["derivedDataEntries"] = [{"path": "Logs", "type": "directory"}]
            return canonical(value)
        delta = self.delta(pid) if delta is None else delta
        data = canonical(delta) if delta_bytes is None else delta_bytes
        value["matchesBefore"] = (tree == TREE and entry_count == 9) if matches_before is None else matches_before
        value["derivedDataDelta"] = dict({"path": "v23-shared-deriveddata-delta.json", "sha256": sha(data),
                                          "addedCount": delta["addedCount"], "changedCount": delta["changedCount"],
                                          "removedCount": delta["removedCount"]}, **(summary_changes or {}))
        return canonical(value)

    def set_after(self, pid, delta=None, delta_bytes=None, **fingerprint):
        delta = self.delta(pid) if delta is None else delta
        data = canonical(delta) if delta_bytes is None else delta_bytes
        self.files[pid]["v23-shared-deriveddata-delta.json"] = data
        self.files[pid]["v23-shared-fingerprint-after.json"] = self.fingerprint(
            pid, "after", delta=delta, delta_bytes=data, **fingerprint)

    def consumer_files(self, pid):
        restore = {"schema": "v23-shared-restore.v1", "role": "consumer", "partitionID": pid,
                   "payloadArtifactName": self.payload_name, "archive": dict(self.receipt["archive"]),
                   "metadataSHA256": sha(self.metadata), "productsTreeSHA256": TREE,
                   "xctestrunSHA256": XCTESTRUN, "restoreSeconds": 12.5, "head": HEAD,
                   "developmentOnly": True, "acceptance": False}
        return {"ci-selection.selected.json": canonical(consumer_selection(pid)),
                "native-admission.json": self.admission("consumer", pid),
                "v23-shared-payload.json": self.metadata, "v23-shared-restore.json": canonical(restore),
                "v23-shared-fingerprint-before.json": self.fingerprint(pid, "before"),
                "v23-shared-fingerprint-after.json": self.fingerprint(pid, "after"),
                "v23-shared-deriveddata-delta.json": canonical(self.delta(pid)),
                "test-smoke.log": passing_log(pid).encode(), "unit-test-results.json": b"{\"testNodes\":[]}\n"}

    def make_jobs(self):
        fixture = json.loads((FIXTURE / "jobs.json").read_text(encoding="utf-8"))["jobs"]
        other = [dict(copy.deepcopy(j), run_id=RUN) for j in fixture if j["conclusion"] == "skipped"]
        other.append(dict(copy.deepcopy(other[0]), id=900000000001,
                          name=f"GitHub Xcode 26.6 acceptance {DOT} none {DOT} none"))
        selection = dict(copy.deepcopy(next(j for j in fixture if j["name"] == NEW.SHARED_SELECTION_JOB)),
                         run_id=RUN)
        start = 1_790_000_000
        producer = {"id": 800000000000, "name": PRODUCER_JOB, "status": "completed", "conclusion": "success",
                    "created_at": "2026-09-25T06:48:37Z", "started_at": "2026-09-25T06:48:47Z",
                    "completed_at": "2026-09-25T07:20:47Z", "runner_name": "GitHub Actions 1",
                    "steps": [step(1, "Set up job", "success", start, 1),
                              step(18, NEW.SHARED_BUILD_STEP, "success", start + 60, 600),
                              step(19, "Seal V23 shared coverage payload", "success", start + 660, 30),
                              step(20, NEW.SHARED_PAYLOAD_UPLOAD_STEP, "success", start + 690, 20),
                              step(23, NEW.SHARED_TEST_STEP, "skipped", start + 710, 0),
                              step(57, NEW.SHARED_UPLOAD_STEP, "success", start + 720, 5)]}
        jobs = other + [selection, producer]
        for index, pid in enumerate(ORDER):
            jobs.append(self.consumer_job(pid, 800000000001 + index, "success"))
            self.job_logs[consumer_job_name(pid)] = passing_log(pid)
        return jobs

    def consumer_job(self, pid, identifier, conclusion, upload="success", tests="success"):
        start = 1_790_001_000
        return {"id": identifier, "name": consumer_job_name(pid), "status": "completed", "conclusion": conclusion,
                "created_at": "2026-09-25T07:20:50Z", "started_at": "2026-09-25T07:21:00Z",
                "completed_at": "2026-09-25T07:26:00Z", "runner_name": "GitHub Actions 2",
                "steps": [step(1, "Set up job", "success", start, 1),
                          step(13, NEW.SHARED_RESTORE_STEP, "success", start + 10, 30),
                          step(23, NEW.SHARED_TEST_STEP, tests, start + 60, 120),
                          step(57, NEW.SHARED_UPLOAD_STEP, upload, start + 200, 5)]}

    def set_consumer(self, pid, conclusion, upload="success", tests="success"):
        index = next(i for i, j in enumerate(self.jobs) if j["name"] == consumer_job_name(pid))
        self.jobs[index] = self.consumer_job(pid, self.jobs[index]["id"], conclusion, upload, tests)

    def build(self):
        blobs, listing, identifier = {}, [], 1000
        names = NEW.shared_artifact_names(RUN, HEAD, IDS)
        for label in ["producer", *IDS]:
            identifier += 1
            if label in self.unlisted:
                continue
            blob = zip_bytes(self.files[label])
            blobs[identifier] = blob
            digest = "sha256:" + hashlib.sha256(blob).hexdigest()
            listing.append({"id": identifier, "expired": False, "size_in_bytes": len(blob),
                            "name": names["producer"] if label == "producer" else names["consumers"][label],
                            "digest": "sha256:" + "0" * 64 if label in self.bad_digest else digest})
        if self.payload_listed:
            listing.append({"id": 5000, "name": self.payload_name, "expired": False, "size_in_bytes": 123456789,
                            "digest": "sha256:" + "4" * 64})
        listing += self.extra_artifacts
        logs = {}
        for number, (name, text) in enumerate(sorted(self.job_logs.items())):
            folder = NEW.job_log_name(name)
            logs[f"{folder}/23_Run targeted tests.txt"] = "".join(
                "2026-09-25T07:22:00.0000000Z " + line for line in text.splitlines(True)).encode()
        for number, (name, text) in enumerate(sorted(self.whole_logs.items())):
            logs[f"{number}_{NEW.job_log_name(name)}.txt"] = text.encode()
        run = {"id": RUN, "head_sha": HEAD, "head_branch": NEW.BRANCH, "event": "workflow_dispatch",
               "path": NEW.WORKFLOW_PATH, "run_attempt": 1, "status": "completed", "conclusion": "failure",
               "run_started_at": "2026-09-25T06:48:17Z", "updated_at": "2026-09-25T08:48:17Z"}
        return FakeGitHub(run, self.jobs, listing, blobs, zip_bytes(logs))

    def dispatch_record(self):
        with mock.patch.object(NEW, "git_bytes", lambda *argv: partitions_file()):
            partitions = NEW.shared_partitions(HEAD, self.plan)
        return {"runID": RUN, "head": HEAD, "parent": PARENT, "selection": NEW.SHARED_SELECTION_ID,
                "lane": NEW.LANE, "url": "https://example.invalid/run", "resolvedSelection": self.plan,
                "resolvedSelectionSHA256": self.plan_sha, "sharedPartitions": partitions,
                "acceptance": False, "releaseReady": False}

    def collect(self, test, module=NEW):
        """Run the real collector against the fake API; returns (summary, fake, error, directory)."""
        temporary = tempfile.TemporaryDirectory()
        test.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        directory = root / str(RUN)
        directory.mkdir()
        (directory / "dispatch.json").write_text(json.dumps(self.dispatch_record()), encoding="utf-8")
        fake = self.build()
        error = None
        with evidence_root(module, root), mock.patch.object(module, "api", fake.api), \
                mock.patch.object(module, "api_bytes", fake.api_bytes), contextlib.redirect_stdout(io.StringIO()):
            try:
                module.collect(RUN, False)
            except SystemExit as caught:
                error = caught
        summary = json.loads((directory / "summary.json").read_text(encoding="utf-8"))
        return summary, fake, error, directory


# --------------------------------------------------------------------------
# Shared-build route tests.
# --------------------------------------------------------------------------

class PaginationTests(unittest.TestCase):
    def fake(self, pages, totals=None):
        calls = []

        def api(path):
            calls.append(path)
            page = int(re.search(r"&page=(\d+)", path).group(1))
            items = pages[page - 1] if page <= len(pages) else []
            total = (totals or {}).get(page, sum(len(p) for p in pages))
            return {"jobs": items, "total_count": total}
        return api, calls

    def test_combines_pages_in_one_page_shape(self):
        pages = [[{"id": i} for i in range(100)], [{"id": i} for i in range(100, 169)]]
        api, calls = self.fake(pages)
        with mock.patch.object(NEW, "api", api):
            value = NEW.paginated("repos/x/jobs", "jobs", NEW.SHARED_MAX_JOBS)
        self.assertEqual(value["total_count"], 169)
        self.assertEqual([j["id"] for j in value["jobs"]], list(range(169)))
        self.assertEqual(calls, ["repos/x/jobs?per_page=100&page=1", "repos/x/jobs?per_page=100&page=2"])
        self.assertEqual(set(value), {"jobs", "total_count"})

    def test_short_listing_duplicates_changes_and_bounds_fail_closed(self):
        cases = {
            "collected": ([[{"id": 1}]], {1: 2, 2: 2}),
            "duplicate": ([[{"id": i} for i in range(100)], [{"id": 5}]], None),
            "changed": ([[{"id": i} for i in range(100)], [{"id": 100}]], {1: 101, 2: 102}),
            "outside": ([[{"id": 1}]], {1: 501}),
        }
        for label, (pages, totals) in cases.items():
            with self.subTest(label):
                api, _ = self.fake(pages, totals)
                with mock.patch.object(NEW, "api", api), self.assertRaises(SystemExit) as caught:
                    NEW.paginated("repos/x/jobs", "jobs", NEW.SHARED_MAX_JOBS)
                self.assertIn(label, str(caught.exception))


class ArtifactAndJobMatchingTests(unittest.TestCase):
    def test_exact_artifact_names_only(self):
        names = NEW.shared_artifact_names(RUN, HEAD, IDS)
        self.assertEqual(names["producer"], f"ios-ci-native-github-v23-shared-coverage-d50x-producer-{RUN}-1")
        self.assertEqual(names["consumers"]["S07"],
                         f"ios-ci-native-github-v23-shared-coverage-d50x-consumer-S07-{RUN}-1")
        self.assertEqual(names["payload"], f"v23-shared-payload-{RUN}-1-{HEAD}")
        decoys = [f"ios-ci-native-github-v23-shared-coverage-d50x-consumer-S7-{RUN}-1",
                  f"ios-ci-native-github-v23-shared-coverage-d50x-consumer-S07-{RUN}-2",
                  f"ios-ci-native-github-v23-shared-coverage-d50x-consumer-S07-{RUN + 1}-1",
                  f"ios-ci-native-github-v23-shared-coverage-d50x-producer-S01-{RUN}-1",
                  f"ios-ci-native-github-v23-shared-coverage-d50x-consumer-S41-{RUN}-1",
                  f"v23-shared-payload-{RUN}-1-{PARENT}"]
        listing = [{"id": i, "name": n} for i, n in enumerate(decoys)]
        listing += [{"id": 100, "name": names["producer"]}, {"id": 101, "name": names["consumers"]["S07"]},
                    {"id": 102, "name": names["payload"]}]
        matched = NEW.match_shared_artifacts(listing, RUN, HEAD, IDS)
        self.assertEqual(matched["producer"]["id"], 100)
        self.assertEqual(matched["consumers"]["S07"]["id"], 101)
        self.assertEqual(matched["payload"]["id"], 102)
        self.assertEqual(sum(v is not None for v in matched["consumers"].values()), 1)
        self.assertEqual(matched["unexpected"], sorted(decoys))
        self.assertEqual(matched["problems"], [])
        doubled = NEW.match_shared_artifacts(listing + [{"id": 103, "name": names["consumers"]["S07"]}],
                                             RUN, HEAD, IDS)
        self.assertIsNone(doubled["consumers"]["S07"])
        self.assertEqual(len(doubled["problems"]), 1)

    def test_job_names_select_partitions(self):
        jobs = [{"id": 1, "name": NEW.SHARED_SELECTION_JOB, "conclusion": "success"},
                {"id": 2, "name": PRODUCER_JOB, "conclusion": "success"},
                {"id": 3, "name": consumer_job_name("S03"), "conclusion": "success"},
                {"id": 4, "name": consumer_job_name("S99"), "conclusion": "success"},
                {"id": 5, "name": f"V23 shared coverage consumer {DOT} " + "${{ matrix.partition_id }} "
                                  "(development only)", "conclusion": "skipped"},
                {"id": 6, "name": "GitHub Xcode 26.6 acceptance", "conclusion": "skipped"}]
        found = NEW.match_shared_jobs(jobs, IDS)
        self.assertEqual(found["selection"]["id"], 1)
        self.assertEqual(found["producer"]["id"], 2)
        self.assertEqual(list(found["consumers"]), ["S03"])
        self.assertEqual([j["id"] for j in found["placeholders"]], [5])
        self.assertEqual([j["id"] for j in found["other"]], [6])
        self.assertEqual(found["problems"], ["consumer jobs for partitions outside the plan ['S99']"])


class SharedCollectionTests(unittest.TestCase):
    def test_complete_run_summary_bytes_equal_the_baseline(self):
        _, _, error, directory = SharedScenario().collect(self)
        self.assertIsNone(error)
        self.assertEqual(sha((directory / "summary.json").read_bytes()), GOLDEN_SHARED_SUMMARY)
        if OLD is not None:
            _, _, _, old_directory = SharedScenario().collect(self, OLD)
            self.assertEqual((directory / "summary.json").read_bytes(), (old_directory / "summary.json").read_bytes())

    def test_complete_run(self):
        scenario = SharedScenario()
        summary, fake, error, directory = scenario.collect(self)
        self.assertIsNone(error)
        self.assertEqual(summary["route"], "shared-build")
        self.assertEqual(summary["integrity"], {"ok": True, "problems": []})
        self.assertEqual(summary["sharedChecks"], {"ok": True, "problems": []})
        self.assertTrue(summary["coverage"]["exact"])
        self.assertEqual((summary["coverage"]["executed"], summary["coverage"]["notExecuted"]), (120, 0))
        self.assertEqual(summary["counts"], {"Passed": 120})
        self.assertEqual(summary["partitionStatuses"], {"success": 40})
        self.assertEqual(summary["planSHA256"], scenario.plan_sha)
        self.assertTrue(summary["selectionMatchesDispatch"])
        self.assertEqual(summary["build"]["succeeded"], True)
        self.assertEqual(summary["build"]["stepSeconds"], 600.0)
        self.assertEqual(summary["build"]["swiftWarnings"], 1)
        self.assertEqual(summary["budgets"]["consumer"]["testTimeoutSeconds"], 3000)
        consumer = summary["jobs"]["consumers"]["S01"]
        self.assertEqual((consumer["queueSeconds"], consumer["runSeconds"], consumer["testSeconds"],
                          consumer["restoreSeconds"]), (10.0, 300.0, 120.0, 30.0))
        self.assertEqual(summary["jobs"]["producer"]["buildSeconds"], 600.0)
        entry = summary["partitions"]["S17"]
        self.assertEqual((entry["logSource"], entry["selectionSource"], entry["counts"]),
                         ("artifact", "artifact", {"Passed": 3}))
        self.assertTrue(entry["restore"]["matchesProducer"])
        self.assertTrue(entry["fingerprints"]["before"]["matchesProducer"])
        self.assertTrue(entry["fingerprints"]["after"]["matchesProducer"])
        self.assertTrue(entry["admission"]["planSHA256Matches"] and entry["admission"]["bindingMatches"])
        self.assertEqual(summary["tests"][selectors("S17")[0]]["partition"], "S17")
        delta = entry["derivedDataDelta"]
        self.assertEqual((delta["addedCount"], delta["changedCount"], delta["removedCount"], delta["failed"]),
                         (25, 0, 0, []))
        self.assertEqual(delta["addedPaths"], [f"Logs/Test/Run-{i:02d}.xcresult" for i in range(20)])
        self.assertEqual(entry["afterBuildEvidence"], [])
        self.assertTrue(entry["fingerprints"]["after"]["matchesBefore"])
        self.assertFalse(summary["acceptance"])
        self.assertTrue(all((directory / "artifacts" / x / "test-smoke.log").is_file() for x in IDS))
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        self.assertIn("artifacts/S40/v23-shared-restore.json", manifest["files"])
        self.assertNotIn("summary.json", manifest["files"])

    def test_mixed_consumer_tiers_are_named_with_their_budgets(self):
        # Owner decision 16: a known-slow solo partition runs as D90S beside D50C partitions.
        scenario = SharedScenario()
        solo = dict(consumer_selection(IDS[0]), tier="D90S", testTimeoutSeconds=5400, totalBudgetSeconds=6000)
        scenario.files[IDS[0]]["ci-selection.selected.json"] = canonical(solo)
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        self.assertEqual(summary["tier"], {"producer": "D40P", "consumer": ["D50C", "D90S"]})
        self.assertEqual(summary["budgets"]["consumer"]["D90S"]["testTimeoutSeconds"], 5400)
        self.assertEqual(summary["budgets"]["consumer"]["D50C"]["testTimeoutSeconds"], 3000)
        uniform, _, _, _ = SharedScenario().collect(self)
        self.assertEqual(uniform["tier"], {"producer": "D40P", "consumer": "D50C"})

    def test_payload_is_recorded_but_never_downloaded(self):
        summary, fake, error, directory = SharedScenario().collect(self)
        self.assertEqual(summary["payloadArtifact"], {
            "name": f"v23-shared-payload-{RUN}-1-{HEAD}", "id": 5000, "sizeInBytes": 123456789,
            "digest": "sha256:" + "4" * 64, "expired": False, "downloaded": False})
        downloads = [path for kind, path in fake.calls if kind == "bytes"]
        self.assertNotIn(f"repos/{REPO}/actions/artifacts/5000/zip", downloads)
        self.assertEqual(len(downloads), 1 + 41)  # logs zip + producer + 40 consumers
        self.assertFalse((directory / "artifact-5000.zip").exists())

    def test_jobs_and_artifacts_are_paginated(self):
        scenario = SharedScenario()
        template = scenario.jobs[0]
        scenario.jobs = [dict(copy.deepcopy(template), id=700000000000 + i, name=f"Padding {i}")
                         for i in range(60)] + scenario.jobs
        scenario.extra_artifacts = [{"id": 6000 + i, "name": f"unrelated-{i}", "expired": False,
                                     "size_in_bytes": 1, "digest": None} for i in range(70)]
        summary, fake, error, directory = scenario.collect(self)
        self.assertIsNone(error)
        api_paths = [path for kind, path in fake.calls if kind == "api"]
        self.assertIn(f"repos/{REPO}/actions/runs/{RUN}/attempts/1/jobs?per_page=100&page=2", api_paths)
        self.assertIn(f"repos/{REPO}/actions/runs/{RUN}/artifacts?per_page=100&page=2", api_paths)
        jobs = json.loads((directory / "jobs.json").read_text(encoding="utf-8"))
        self.assertEqual(len(jobs["jobs"]), jobs["total_count"])
        self.assertGreater(jobs["total_count"], 100)
        self.assertEqual(len(summary["jobs"]["consumers"]), 40)
        self.assertEqual(len(summary["unexpectedArtifacts"]), 70)
        self.assertTrue(summary["integrity"]["ok"])

    def test_union_reports_missing_and_duplicate_selectors(self):
        scenario = SharedScenario()
        changed = consumer_selection("S02")
        changed["unitTestSelectors"] = selectors("S02")[:2] + [selectors("S03")[0]]
        scenario.files["S02"]["ci-selection.selected.json"] = canonical(changed)
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        coverage = summary["coverage"]
        self.assertFalse(coverage["exact"])
        self.assertEqual(coverage["missing"], [selectors("S02")[2]])
        self.assertEqual(coverage["duplicates"], [selectors("S03")[0]])
        self.assertEqual(coverage["extra"], [])
        self.assertFalse(summary["partitions"]["S02"]["selectionMatchesDispatch"])
        self.assertIn("S02: executed selection differs from the dispatched partition",
                      summary["sharedChecks"]["problems"])
        self.assertTrue(summary["integrity"]["ok"])

    def test_fingerprint_mismatch_is_reported_not_fatal(self):
        scenario = SharedScenario()
        scenario.files["S05"]["v23-shared-fingerprint-after.json"] = scenario.fingerprint("S05", "after", "9" * 64)
        scenario.files["S06"]["build-smoke.log"] = b"** BUILD SUCCEEDED **\n"
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        self.assertTrue(summary["partitions"]["S05"]["fingerprints"]["before"]["matchesProducer"])
        self.assertFalse(summary["partitions"]["S05"]["fingerprints"]["after"]["matchesProducer"])
        self.assertEqual(summary["partitions"]["S06"]["buildEvidence"], ["build-smoke.log"])
        problems = summary["sharedChecks"]["problems"]
        self.assertIn("S05: fingerprint after differs from the producer or partition or shows build evidence",
                      problems)
        self.assertIn("S05: fingerprint after does not match before (matchesBefore/products/entryCount)", problems)
        self.assertIn("S06: consumer build evidence present ['build-smoke.log']", problems)
        self.assertFalse(summary["sharedChecks"]["ok"])
        self.assertTrue(summary["integrity"]["ok"])

    def test_after_fingerprint_must_match_before_and_partition(self):
        scenario = SharedScenario()
        scenario.set_after("S20", matches_before=False)
        scenario.set_after("S21", entry_count=10, matches_before=True)
        scenario.set_after("S22", partition="S01")
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        problems = summary["sharedChecks"]["problems"]
        for pid in ("S20", "S21"):
            self.assertFalse(summary["partitions"][pid]["fingerprints"]["after"]["matchesBefore"])
            self.assertIn(f"{pid}: fingerprint after does not match before (matchesBefore/products/entryCount)",
                          problems)
        self.assertFalse(summary["partitions"]["S22"]["fingerprints"]["after"]["partitionMatches"])
        self.assertIn("S22: fingerprint after differs from the producer or partition or shows build evidence",
                      problems)
        self.assertEqual(len(problems), 3)
        self.assertTrue(summary["integrity"]["ok"])

    def test_delta_sha_mismatch_is_reported(self):
        scenario = SharedScenario()
        scenario.set_after("S23", summary_changes={"sha256": "0" * 64})
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        self.assertEqual(summary["partitions"]["S23"]["derivedDataDelta"]["failed"], ["sha256"])
        self.assertEqual(summary["sharedChecks"]["problems"], ["S23: DerivedData delta fails ['sha256']"])
        self.assertTrue(summary["integrity"]["ok"])

    def test_missing_delta_is_reported(self):
        scenario = SharedScenario()
        del scenario.files["S24"]["v23-shared-deriveddata-delta.json"]
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        self.assertFalse(summary["partitions"]["S24"]["derivedDataDelta"]["present"])
        self.assertEqual(summary["sharedChecks"]["problems"], ["S24: DerivedData delta missing"])
        self.assertTrue(summary["integrity"]["ok"])

    def test_delta_compile_evidence_is_reported(self):
        scenario = SharedScenario()
        evidence = ["Logs/Build/A.xcactivitylog: CompileSwift"]
        scenario.set_after("S25", delta=scenario.delta("S25", compileEvidence=evidence))
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        delta = summary["partitions"]["S25"]["derivedDataDelta"]
        self.assertEqual((delta["compileEvidence"], delta["failed"]), (evidence, ["compileEvidence"]))
        self.assertEqual(summary["sharedChecks"]["problems"], ["S25: DerivedData delta fails ['compileEvidence']"])

    def test_delta_canonical_counts_partition_and_classification(self):
        scenario = SharedScenario()
        scenario.set_after("S26", delta_bytes=(json.dumps(scenario.delta("S26"), indent=1) + "\n").encode())
        scenario.set_after("S27", summary_changes={"addedCount": 24})
        scenario.set_after("S28", delta=scenario.delta("S28", partitionID="S01"))
        scenario.set_after("S29", delta=scenario.delta("S29", acceptance=True))
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        failed = {pid: summary["partitions"][pid]["derivedDataDelta"]["failed"]
                  for pid in ("S26", "S27", "S28", "S29")}
        self.assertEqual(failed, {"S26": ["canonical"], "S27": ["counts"], "S28": ["partition"],
                                  "S29": ["classification"]})
        self.assertEqual(len(summary["sharedChecks"]["problems"]), 4)
        self.assertTrue(summary["integrity"]["ok"])

    def test_restore_receipt_must_equal_producer_receipt(self):
        scenario = SharedScenario()
        restore = json.loads(scenario.files["S04"]["v23-shared-restore.json"])
        restore["archive"]["sha256"] = "8" * 64
        scenario.files["S04"]["v23-shared-restore.json"] = canonical(restore)
        scenario.files["S09"]["v23-shared-payload.json"] = scenario.metadata + b" "
        summary, _, _, _ = scenario.collect(self)
        self.assertFalse(summary["partitions"]["S04"]["restore"]["matchesProducer"])
        self.assertFalse(summary["partitions"]["S09"]["restore"]["matchesProducer"])
        self.assertTrue(summary["partitions"]["S08"]["restore"]["matchesProducer"])
        self.assertIn("S04: restore archive/metadata differ from the producer receipt",
                      summary["sharedChecks"]["problems"])

    def test_partial_run_reports_failed_cancelled_and_skipped_consumers(self):
        scenario = SharedScenario()
        failing = selectors("S07")[1]
        scenario.files["S07"]["test-smoke.log"] = (
            test_line(selectors("S07")[0], "started") + test_line(selectors("S07")[0], "passed", 1.0)
            + test_line(failing, "started")
            + "/Users/runner/X.swift:12: error: -[FieldEvidenceAppTests.ClassS07Tests testBeta] : XCTAssertTrue failed\n"
            + "V23_RESTORE_DIAGNOSIS phase=seal step=2\n"
            + test_line(failing, "failed", 2.5)).encode()
        scenario.set_consumer("S07", "failure", tests="failure")
        scenario.set_consumer("S08", "cancelled", upload="skipped", tests="cancelled")
        scenario.set_consumer("S09", "skipped", upload="skipped", tests="skipped")
        scenario.unlisted |= {"S08", "S09"}
        for pid in ("S08", "S09"):
            del scenario.job_logs[consumer_job_name(pid)]
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        self.assertTrue(summary["integrity"]["ok"])
        s07, s08, s09 = (summary["partitions"][x] for x in ("S07", "S08", "S09"))
        self.assertEqual((s07["status"], s07["counts"]), ("failure", {"Failed": 1, "NotStarted": 1, "Passed": 1}))
        self.assertEqual(s07["failures"], {failing: ["XCTAssertTrue failed"]})
        self.assertEqual(s07["namedDiagnostics"], ["V23_RESTORE_DIAGNOSIS phase=seal step=2"])
        self.assertIn("S07: V23_RESTORE_DIAGNOSIS phase=seal step=2", summary["namedDiagnostics"])
        self.assertEqual(s07["seconds"], 3.5)
        self.assertEqual((s08["status"], s08["artifact"]["listed"], s08["artifact"]["required"]),
                         ("cancelled", False, False))
        self.assertEqual(s09["status"], "skipped")
        self.assertEqual(s08["selectionSource"], "dispatch")
        self.assertEqual(summary["counts"], {"Failed": 1, "NotStarted": 7, "Passed": 112})
        self.assertEqual(summary["partitionStatuses"], {"cancelled": 1, "failure": 1, "skipped": 1, "success": 37})
        self.assertEqual(sorted(summary["artifactsNotExtracted"]), ["S08", "S09"])
        self.assertTrue(summary["coverage"]["exact"])  # declared from the dispatch-recorded partitions
        self.assertEqual(summary["coverage"]["declaredFrom"], {"artifact": 38, "dispatch": 2})

    def test_missing_artifact_of_completed_job_fails_collection_after_retention(self):
        scenario = SharedScenario()
        scenario.unlisted.add("S10")
        summary, _, error, directory = scenario.collect(self)
        self.assertIsNotNone(error)
        self.assertIn("S10: missing artifact", str(error))
        self.assertFalse(summary["integrity"]["ok"])
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        self.assertTrue(any(note.startswith("S10: missing artifact") for note in manifest["notes"]))
        self.assertTrue((directory / "artifacts" / "S11").is_dir())

    def test_digest_mismatch_fails_collection_and_is_never_extracted(self):
        scenario = SharedScenario()
        scenario.bad_digest.add("S11")
        summary, _, error, directory = scenario.collect(self)
        self.assertIsNotNone(error)
        self.assertFalse((directory / "artifacts" / "S11").exists())
        state = summary["partitions"]["S11"]["artifact"]
        self.assertEqual((state["retained"], state["digestMatches"], state["extracted"]), (True, False, False))
        self.assertTrue(any(p.startswith("S11: artifact digest mismatch") for p in summary["integrity"]["problems"]))
        # The corrupt artifact is never trusted; the job's own step log is used instead.
        self.assertEqual(summary["partitions"]["S11"]["logSource"], "job-step-log")

    def test_job_logs_are_matched_by_consumer_job_name(self):
        scenario = SharedScenario()
        for pid in ("S12", "S14"):
            del scenario.files[pid]["test-smoke.log"]
        failing = selectors("S12")[2]
        scenario.job_logs[consumer_job_name("S12")] = (
            test_line(selectors("S12")[0], "passed", 0.5) + test_line(selectors("S12")[1], "passed", 0.5)
            + test_line(failing, "started"))  # interrupted
        del scenario.job_logs[consumer_job_name("S14")]
        scenario.whole_logs[consumer_job_name("S14")] = "2026 " + test_line(selectors("S14")[0], "passed", 1.0)
        scenario.whole_logs[consumer_job_name("S15")] = "2026 " + test_line(selectors("S14")[1], "failed", 1.0)
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        s12, s14 = summary["partitions"]["S12"], summary["partitions"]["S14"]
        self.assertEqual((s12["logSource"], s12["resultsFromJobLog"]), ("job-step-log", True))
        self.assertEqual(s12["counts"], {"Interrupted": 1, "Passed": 2})
        self.assertEqual(s12["interrupted"], [failing])
        self.assertEqual(s14["logSource"], "job-log")
        self.assertEqual(s14["counts"], {"NotStarted": 2, "Passed": 1})
        self.assertEqual(summary["resultsFromJobLog"], ["S12", "S14"])
        self.assertEqual(summary["partitions"]["S13"]["logSource"], "artifact")

    def test_producer_failure_leaves_consumers_unexpanded(self):
        scenario = SharedScenario()
        producer = next(j for j in scenario.jobs if j["name"] == PRODUCER_JOB)
        producer["conclusion"] = "failure"
        for item in producer["steps"]:
            if item["name"] == NEW.SHARED_BUILD_STEP:
                item["conclusion"] = "failure"
            elif item["name"] == NEW.SHARED_PAYLOAD_UPLOAD_STEP:
                item["conclusion"] = "skipped"
        scenario.files["producer"]["build-smoke.log"] = b"a.swift:3:4: error: nope\n** TEST BUILD FAILED **\n"
        del scenario.files["producer"]["v23-shared-payload.json"]
        del scenario.files["producer"]["v23-shared-payload-receipt.json"]
        scenario.jobs = [j for j in scenario.jobs if not j["name"].startswith("V23 shared coverage consumer")]
        scenario.jobs.append({"id": 1, "name": f"V23 shared coverage consumer {DOT} "
                                               "${{ matrix.partition_id }} (development only)",
                              "status": "completed", "conclusion": "skipped", "steps": []})
        scenario.unlisted |= set(IDS)
        scenario.payload_listed = False
        scenario.job_logs.clear()
        summary, _, error, _ = scenario.collect(self)
        self.assertIsNone(error)
        self.assertTrue(summary["integrity"]["ok"])
        self.assertEqual(summary["partitionStatuses"], {"NoJob": 40})
        self.assertEqual(summary["counts"], {"NotStarted": 120})
        self.assertEqual((summary["build"]["succeeded"], summary["build"]["swiftErrors"],
                          summary["build"]["stepConclusion"]), (False, 1, "failure"))
        self.assertIsNone(summary["payloadArtifact"])
        self.assertEqual(len(summary["jobs"]["placeholders"]), 1)
        self.assertIn("producer: payload receipt or metadata missing; consumer payload bindings unverified",
                      summary["sharedChecks"]["problems"])

    def test_summarize_rederives_the_same_summary_from_retained_files(self):
        scenario = SharedScenario()
        summary, _, _, directory = scenario.collect(self)
        root = directory.parent
        with evidence_root(NEW, root), mock.patch.object(NEW, "api", None), mock.patch.object(NEW, "api_bytes", None):
            again = NEW.summarize(RUN)
        self.assertEqual(json.loads(json.dumps(again)), summary)
        self.assertEqual(len(list(directory.glob("summary*.json"))), 2)


# --------------------------------------------------------------------------
# Dispatch.
# --------------------------------------------------------------------------

# The run-kind input a development dispatch passes (choice, default gate).
KIND_INPUT_TEXT = ("      v23_run_kind:\n        description: kind\n        required: false\n        default: gate\n"
                   "        type: choice\n        options:\n          - gate\n          - development\n")
WORKFLOW_TEXT = ("          - v23-dev-batch-no-index-d50\n          - v23-shared-coverage-d50x\n"
                 "          - c36-round-item-completion-no-index-build30m\n" + KIND_INPUT_TEXT)
DEV = "v23-dev-batch-no-index-d50"
ORDINARY_D30 = "c36-round-item-completion-no-index-build30m"
WORKER_PATH = ".github/workflows/ios-ci-worker.yml"
FIXTURE_DISPATCH = json.loads((FIXTURE / "dispatch.json").read_text(encoding="utf-8"))
FIXTURE_RUN = json.loads((FIXTURE / "run.json").read_text(encoding="utf-8"))
DEV_HEAD, DEV_PARENT = FIXTURE_DISPATCH["head"], FIXTURE_DISPATCH["parent"]
DEV_PLAN = FIXTURE_DISPATCH["resolvedSelection"]
OTHER_HEAD = "e" * 40
TERM = ("${{ github.event.inputs.v23_run_kind == 'development' && "
        "(github.event.inputs.native_selection_id == 'v23-dev-batch-no-index-d50' || "
        "github.event.inputs.native_selection_id == 'v23-shared-coverage-d50x') && "
        "format('-development-{0}', github.sha) || '' }}")
SHARED_WORKER_PATH = ".github/workflows/ios-ci-shared-worker.yml"
PER_RUN = "${{ github.run_id }}"
REASON = "setup failure on the runner, not the source"
ORDINARY_PLAN = {"tier": "D30", "unitTestSelectors": ["x"]}


def caller_text(per_head=True, worker="./.github/workflows/ios-ci-worker.yml", group=None, job_group=None):
    """A caller in the shape of ios-ci.yml: choices, top-level group, the dev-batch job and decoys."""
    group = group if group is not None else "v23-${{ inputs.native_selection_id }}" + (TERM if per_head else "")
    job_concurrency = "" if job_group is None else f"    concurrency:\n      group: {job_group}\n"
    return ("on:\n  workflow_dispatch:\n    inputs:\n      native_selection_id:\n        options:\n" + WORKFLOW_TEXT
            + f"\nconcurrency:\n  group: {group}\n  cancel-in-progress: false\n\njobs:\n"
            "  shared-selection:\n    runs-on: ubuntu-24.04\n"
            "  github-shard:\n    needs: shared-selection\n"
            "    if: ${{ inputs.execution_lane == 'github-xcode-26.6-acceptance' && "
            "inputs.native_selection_id != 'v23-shared-coverage-d50x' }}\n"
            + job_concurrency + f"    uses: {worker}\n"
            "  v23-shared-producer:\n"
            "    if: ${{ inputs.execution_lane == 'github-xcode-26.6-acceptance' && "
            "inputs.native_selection_id == 'v23-shared-coverage-d50x' }}\n"
            "    uses: ./.github/workflows/ios-ci-shared-worker.yml\n"
            "  v23-shared-consumer:\n    needs: [shared-selection, v23-shared-producer]\n"
            "    if: ${{ inputs.execution_lane == 'github-xcode-26.6-acceptance' && "
            "inputs.native_selection_id == 'v23-shared-coverage-d50x' }}\n"
            "    uses: ./.github/workflows/ios-ci-shared-worker.yml\n"
            "  getmac-shard:\n    if: ${{ inputs.execution_lane == 'getmac-xcode-26.6-development-only' }}\n"
            "    uses: ./.github/workflows/ios-ci-worker.yml\n")


def worker_text(per_head=True, group=None, job_group=None):
    group = group if group is not None else "v23-github-${{ inputs.native_selection_id }}" + (TERM if per_head else "")
    job_concurrency = "" if job_group is None else f"    concurrency:\n      group: {job_group}\n"
    return (f"name: worker\non:\n  workflow_call:\n\nconcurrency:\n  group: {group}\n  cancel-in-progress: false\n\n"
            "jobs:\n  verify:\n    runs-on: macos-26\n" + job_concurrency)


def shared_worker_text(group="v23-github-${{ inputs.native_selection_id }}-" + "${{ github.run_id }}"):
    return (f"name: shared\non:\n  workflow_call:\n\nconcurrency:\n  group: {group}\n  cancel-in-progress: false\n\n"
            "jobs:\n  verify:\n    runs-on: macos-26\n")


class DispatchHarness:
    def __init__(self, module, root, selection, active=(), known_runs=(), partitions_raw=None, resolved=None,
                 head=HEAD, parent=PARENT, workflow=WORKFLOW_TEXT, worker=None, workers=None, run_records=None,
                 cancel_code=0):
        self.module, self.root, self.selection = module, root, selection
        self.active = list(active)
        self.known_runs = list(known_runs)
        self.partitions_raw = partitions_file() if partitions_raw is None else partitions_raw
        self.resolved = resolved
        self.head, self.parent, self.workflow = head, parent, workflow
        self.workers = dict(workers or {})
        if worker is not None:
            self.workers[WORKER_PATH] = worker
        self.run_records = dict(run_records or {})
        self.cancel_code = cancel_code
        self.ledger_at_cancel = None
        self.dispatched = False
        self.calls = []
        self.preflight_error = None

    def preflight(self, *args):
        self.calls.append(("observation_preflight", args))
        if self.preflight_error is not None:
            raise SystemExit(self.preflight_error)

    def run(self, *argv):
        self.calls.append(("run", argv))
        if argv[:2] == ("git", "fetch"):
            return ""
        if argv == ("git", "rev-parse", "HEAD") or argv == ("git", "rev-parse", f"origin/{NEW.BRANCH}"):
            return self.head + "\n"
        if argv == ("git", "rev-parse", f"{self.head}^"):
            return self.parent + "\n"
        if argv == ("git", "show", f"{self.head}:{NEW.WORKFLOW_PATH}"):
            return self.workflow
        raise AssertionError(argv)

    def subprocess_run(self, argv, **kwargs):
        self.calls.append(("subprocess", tuple(argv)))
        if argv[:2] == ["gh", "workflow"]:
            self.dispatched = True
        if argv[:3] == ["gh", "run", "cancel"]:
            self.ledger_at_cancel = ledger_lines(self.root)
            if self.cancel_code is None:
                raise FileNotFoundError("gh")
            return subprocess.CompletedProcess(argv, self.cancel_code, "", "HTTP 409" if self.cancel_code else "")
        return subprocess.CompletedProcess(argv, 0, b"", b"")

    def runs_for(self, head):
        self.calls.append(("runs_for", head))
        runs = list(self.known_runs)
        if self.dispatched:
            runs.append({"id": RUN, "event": "workflow_dispatch", "path": NEW.WORKFLOW_PATH,
                         "head_branch": NEW.BRANCH, "run_attempt": 1, "html_url": "https://example.invalid/run"})
        return runs

    def api(self, path):
        self.calls.append(("api", path))
        match = re.fullmatch(rf"repos/{re.escape(REPO)}/actions/runs/(\d+)", path)
        if match:
            return copy.deepcopy(self.run_records[int(match.group(1))])
        status = re.search(r"status=(\w+)", path).group(1)
        return {"workflow_runs": [run for run in self.active if run.get("status") == status]}

    def git_bytes(self, *argv):
        self.calls.append(("git_bytes", argv))
        for path, text in self.workers.items():
            if argv == ("show", f"{self.head}:{path}"):
                return text.encode("utf-8")
        if len(argv) == 2 and argv[1].endswith(".yml"):
            raise AssertionError("unexpected workflow read " + argv[1])
        return self.partitions_raw

    def resolve(self, head, selection):
        self.calls.append(("resolve", head, selection))
        value = self.resolved if self.resolved is not None else (
            plan() if selection == NEW.SHARED_SELECTION_ID else {"tier": "D50", "unitTestSelectors": ["x"]})
        return value, sha(canonical(value))

    def call(self, function, *args, **kwargs):
        module = self.module
        patches = [mock.patch.object(module, "run", self.run), mock.patch.object(module, "runs_for", self.runs_for),
                   mock.patch.object(module, "api", self.api),
                   mock.patch.object(module, "resolve_selection", self.resolve),
                   mock.patch("subprocess.run", self.subprocess_run)]
        # Most older dispatch fixtures use historical synthetic heads. Keep their
        # workflow behavior focused; exact profile admission is tested separately.
        if hasattr(module, "preflight_compiler_observation_source"):
            patches.append(mock.patch.object(module, "preflight_compiler_observation_source",
                side_effect=self.preflight))
        if hasattr(module, "git_bytes"):
            patches.append(mock.patch.object(module, "git_bytes", self.git_bytes))
        output = io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(evidence_root(module, self.root))
            for patch in patches:
                stack.enter_context(patch)
            stack.enter_context(contextlib.redirect_stdout(output))
            getattr(module, function)(*args, **kwargs)
        return output.getvalue()

    def dispatch(self, **kwargs):
        return self.call("dispatch", self.selection, **kwargs)

    def cancel(self, run_id, reason):
        return self.call("cancel", run_id, reason)


def write_ledger(root, entries):
    with (root / "v23-original-ledger.jsonl").open("a", encoding="utf-8", newline="\n") as stream:
        for entry in entries:
            stream.write(json.dumps(entry) + "\n")


def ledger_lines(root):
    path = root / "v23-original-ledger.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()] if path.exists() else []


def dispatch_scenario(module, **kwargs):
    """The pre-existing ordinary dispatch beside an active run of another selection."""
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        write_ledger(root, [{"runID": 11, "selection": ORDINARY_D30}])
        harness = DispatchHarness(module, root, DEV, active=[{"id": 11, "status": "in_progress"}])
        output = harness.dispatch(**kwargs)
        return harness.calls, output, tree_bytes(root)


def without_gate_kind(result, test):
    """The scenario with the recorded kind removed (asserted to be gate everywhere it is recorded)."""
    calls, output, tree = result

    def strip(value):
        test.assertEqual(value.pop("kind"), "gate")
        return value
    output = json.dumps(strip(json.loads(output)), indent=2) + "\n"
    stripped = {}
    for name, data in tree.items():
        if name == "v23-original-ledger.jsonl":
            lines = [json.loads(line) for line in data.decode("utf-8").splitlines()]
            lines[1:] = [strip(line) for line in lines[1:]]
            stripped[name] = "".join(json.dumps(line, sort_keys=True) + "\n" for line in lines).encode("utf-8")
        elif name.endswith(".json"):
            stripped[name] = (json.dumps(strip(json.loads(data)), indent=2, sort_keys=True) + "\n").encode("utf-8")
        else:
            stripped[name] = data
    test.assertEqual(sorted(tree), sorted(stripped))
    return calls, output, stripped


def scenario_digest(result):
    calls, output, tree = result
    return sha(json.dumps([calls, output, {k: v.decode("utf-8") for k, v in tree.items()}],
                          sort_keys=True).encode("utf-8"))


class DispatchTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def write_ledger(self, entries):
        write_ledger(self.root, entries)

    def test_shared_refuses_while_any_other_run_is_active(self):
        self.write_ledger([{"runID": 11, "selection": "v23-dev-batch-no-index-d50"}])
        for status in ("queued", "in_progress", "waiting", "pending", "requested"):
            for kind, expected in (("gate", "requires zero other active runs"),
                                   ("development", "are not ledgered development runs")):
                with self.subTest(status=status, kind=kind):
                    harness = DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID,
                                              active=[{"id": 11, "status": status}])
                    with self.assertRaises(SystemExit) as caught:
                        harness.dispatch(kind=kind)
                    self.assertIn(expected, str(caught.exception))
                    self.assertFalse(harness.dispatched)
                    self.assertFalse((self.root / "v23-original-attempts").exists())

    def test_shared_dispatch_with_zero_active_records_the_partitions(self):
        harness = DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID)
        output = harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)
        record = json.loads((self.root / str(RUN) / "dispatch.json").read_text(encoding="utf-8"))
        self.assertEqual(record["resolvedSelectionSHA256"], sha(canonical(plan())))
        self.assertEqual(record["sharedPartitions"]["partitionIDs"], ORDER)
        self.assertEqual(record["sharedPartitions"]["selectors"]["S03"], selectors("S03"))
        self.assertEqual(record["sharedPartitions"]["partitionsSHA256"], sha(partitions_file()))
        self.assertEqual(record["kind"], "development")
        self.assertNotIn("sharedPartitions", output)
        self.assertNotIn("resolvedSelection\"", output)
        self.assertEqual(len((self.root / "v23-original-ledger.jsonl").read_text().splitlines()), 1)
        argv = next(call[1] for call in harness.calls if call[0] == "subprocess" and call[1][0] == "gh")
        self.assertIn("native_selection_id=v23-shared-coverage-d50x", argv)

    def test_shared_refuses_a_plan_not_bound_to_the_partitions_file(self):
        altered = json.loads(partitions_file())
        altered["sweepOrder"] = IDS
        other_order = (json.dumps(altered, indent=2) + "\n").encode()
        wrong_tier = dict(plan(), tier="D50C")
        for label, kwargs in {"digest": {"partitions_raw": partitions_file() + b"\n"},
                              "order": {"partitions_raw": other_order},
                              "tier": {"resolved": wrong_tier}}.items():
            with self.subTest(label):
                harness = DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID, **kwargs)
                with self.assertRaises(SystemExit) as caught:
                    harness.dispatch(kind="gate")
                self.assertIn("binding refused", str(caught.exception))
                self.assertFalse(harness.dispatched)

    def test_existing_refusals_are_kept(self):
        self.write_ledger([{"runID": 11, "selection": "v23-dev-batch-no-index-d50"}])
        harness = DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID,
                                  active=[{"id": i, "status": "queued"} for i in range(5)])
        with self.assertRaisesRegex(SystemExit, "capacity is 5"):
            harness.dispatch(kind="development")
        harness = DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID, known_runs=[{"id": 77}])
        with self.assertRaisesRegex(SystemExit, "not dispatched by this ledger"):
            harness.dispatch(kind="development")
        harness = DispatchHarness(NEW, self.root, "v23-dev-batch-no-index-d50", active=[{"id": 11, "status": "queued"}])
        with self.assertRaisesRegex(SystemExit, "this selection is active"):
            harness.dispatch(kind="gate")
        harness = DispatchHarness(NEW, self.root, "not-a-choice")
        with self.assertRaisesRegex(SystemExit, "not a workflow choice"):
            harness.dispatch()
        DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID).dispatch(kind="development")
        with self.assertRaisesRegex(SystemExit, "already requested"):
            DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID, known_runs=[]).dispatch(kind="development")

    def test_other_selections_refused_while_a_shared_run_is_active(self):
        self.write_ledger([{"runID": 11, "selection": NEW.SHARED_SELECTION_ID}])
        for status in ("queued", "in_progress", "waiting", "pending", "requested"):
            with self.subTest(status):
                harness = DispatchHarness(NEW, self.root, "v23-dev-batch-no-index-d50",
                                          active=[{"id": 11, "status": status}])
                with self.assertRaisesRegex(SystemExit, "v23-shared-coverage-d50x is active"):
                    harness.dispatch(kind="gate")
                self.assertFalse(harness.dispatched)
                self.assertFalse((self.root / "v23-original-attempts").exists())
        harness = DispatchHarness(NEW, self.root, "v23-dev-batch-no-index-d50")
        harness.dispatch(kind="gate")  # the shared run is no longer active
        self.assertTrue(harness.dispatched)

    def test_existing_selection_still_dispatches_beside_active_runs(self):
        self.write_ledger([{"runID": 11, "selection": "c36-round-item-completion-no-index-build30m"}])
        harness = DispatchHarness(NEW, self.root, "v23-dev-batch-no-index-d50", active=[{"id": 11, "status": "queued"}])
        harness.dispatch(kind="gate")
        record = json.loads((self.root / str(RUN) / "dispatch.json").read_text(encoding="utf-8"))
        self.assertNotIn("sharedPartitions", record)
        self.assertNotIn("git_bytes", [call[0] for call in harness.calls])

    @unittest.skipUnless(OLD, "current tool not present")
    def test_existing_selection_dispatch_identical_to_current_tool_apart_from_the_kind(self):
        self.assertEqual(without_gate_kind(dispatch_scenario(NEW, kind="gate"), self), dispatch_scenario(OLD))

    def test_existing_selection_dispatch_equals_the_baseline_golden_digest_apart_from_the_kind(self):
        self.assertEqual(scenario_digest(without_gate_kind(dispatch_scenario(NEW, kind="gate"), self)),
                         GOLDEN_SINGLE_DISPATCH)

    def test_ledger_events_never_count_as_dispatched_originals(self):
        write_ledger(self.root, [{"runID": 11, "head": OTHER_HEAD, "selection": DEV, "kind": "development"},
                                 {"event": "cancel-intent", "runID": 11, "head": OTHER_HEAD, "selection": DEV},
                                 {"event": "cancel-complete", "runID": 11, "head": OTHER_HEAD, "selection": DEV,
                                  "exitCode": 0}])
        with evidence_root(NEW, self.root):
            self.assertEqual([x["runID"] for x in NEW.ledger_dispatches()], [11])
            self.assertEqual([x["event"] for x in NEW.ledger_events()], ["cancel-intent", "cancel-complete"])
        harness = DispatchHarness(NEW, self.root, DEV)
        harness.dispatch(kind="gate")
        self.assertEqual([x.get("event") for x in ledger_lines(self.root)],
                         [None, "cancel-intent", "cancel-complete", None])


# --------------------------------------------------------------------------
# Run kinds: development or gate.
# --------------------------------------------------------------------------

class RunKindTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def records(self):
        attempts = sorted((self.root / "v23-original-attempts").glob("*.json"))
        return ([json.loads(p.read_text(encoding="utf-8")) for p in attempts],
                json.loads((self.root / str(RUN) / "dispatch.json").read_text(encoding="utf-8")),
                ledger_lines(self.root))

    def test_kind_is_required_for_the_two_dual_use_routes(self):
        for selection in (DEV, NEW.SHARED_SELECTION_ID):
            with self.subTest(selection):
                harness = DispatchHarness(NEW, self.root, selection)
                with self.assertRaisesRegex(SystemExit, "--kind development\\|gate is required"):
                    harness.dispatch()
                self.assertEqual(harness.calls, [])
        with self.assertRaisesRegex(SystemExit, "--kind must be one of"):
            DispatchHarness(NEW, self.root, DEV).dispatch(kind="acceptance")
        with mock.patch.object(sys, "argv", ["v23-original.py", "dispatch", "--selection", DEV, "--kind", "other"]), \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
            NEW.main()
        self.assertEqual(caught.exception.code, 2)

    def test_other_selections_default_to_gate_and_record_it_everywhere(self):
        harness = DispatchHarness(NEW, self.root, ORDINARY_D30, resolved=ORDINARY_PLAN)
        output = harness.dispatch()
        attempts, record, ledger = self.records()
        self.assertEqual(([a["kind"] for a in attempts], record["kind"], ledger[-1]["kind"]), (["gate"], "gate", "gate"))
        self.assertIn('"kind": "gate"', output)

    def test_development_kind_is_recorded_everywhere(self):
        harness = DispatchHarness(NEW, self.root, DEV, resolved=DEV_PLAN)
        harness.dispatch(kind="development")
        attempts, record, ledger = self.records()
        self.assertEqual(([a["kind"] for a in attempts], record["kind"], ledger[-1]["kind"]),
                         (["development"], "development", "development"))

    def test_development_kind_needs_a_development_route(self):
        for selection, resolved in ((ORDINARY_D30, ORDINARY_PLAN), (ORDINARY_D30, dict(ORDINARY_PLAN, acceptance=False)),
                                    (DEV, {"tier": "D50", "unitTestSelectors": ["x"]})):
            with self.subTest(selection=selection, resolved=resolved):
                harness = DispatchHarness(NEW, self.root, selection, resolved=resolved)
                with self.assertRaisesRegex(SystemExit, "--kind development is only for development routes"):
                    harness.dispatch(kind="development")
                self.assertFalse(harness.dispatched)
                self.assertFalse((self.root / "v23-original-attempts").exists())

    def test_gate_is_refused_when_head_and_selection_already_have_any_original(self):
        for label, kind in (("development", "development"), ("gate", "gate"), ("unmarked", None)):
            with self.subTest(label):
                root = Path(tempfile.mkdtemp())
                self.addCleanup(shutil.rmtree, root, True)
                entry = {"runID": 21, "head": DEV_HEAD, "selection": DEV}
                if kind:
                    entry["kind"] = kind
                write_ledger(root, [entry])
                harness = DispatchHarness(NEW, root, DEV, head=DEV_HEAD, resolved=DEV_PLAN, known_runs=[{"id": 21}])
                with self.assertRaisesRegex(SystemExit, "a gate original .* is refused"):
                    harness.dispatch(kind="gate")
                self.assertFalse(harness.dispatched)
        for name in (f"{DEV_HEAD}-{DEV}.json", f"{DEV_HEAD}-{DEV}.infra-retry.json"):
            with self.subTest(name):
                root = Path(tempfile.mkdtemp())
                self.addCleanup(shutil.rmtree, root, True)
                (root / "v23-original-attempts").mkdir()
                (root / "v23-original-attempts" / name).write_text("{}\n", encoding="utf-8")
                harness = DispatchHarness(NEW, root, DEV, head=DEV_HEAD, resolved=DEV_PLAN)
                with self.assertRaisesRegex(SystemExit, "a gate original .* is refused"):
                    harness.dispatch(kind="gate")
        write_ledger(self.root, [{"runID": 21, "head": OTHER_HEAD, "selection": DEV, "kind": "development"},
                                 {"runID": 22, "head": DEV_HEAD, "selection": ORDINARY_D30, "kind": "gate"}])
        harness = DispatchHarness(NEW, self.root, DEV, head=DEV_HEAD, resolved=DEV_PLAN)
        harness.dispatch(kind="gate")  # other heads and other selections do not count
        self.assertTrue(harness.dispatched)

    def test_development_after_any_original_is_still_refused(self):
        DispatchHarness(NEW, self.root, DEV, resolved=DEV_PLAN).dispatch(kind="gate")
        harness = DispatchHarness(NEW, self.root, DEV, resolved=DEV_PLAN, known_runs=[{"id": RUN}])
        with self.assertRaisesRegex(SystemExit, "already requested"):
            harness.dispatch(kind="development")


# --------------------------------------------------------------------------
# Development routes: classification, evidence root.
# --------------------------------------------------------------------------

class DevelopmentRouteTests(unittest.TestCase):
    def test_named_routes_need_their_development_binding(self):
        self.assertTrue(NEW.development_route(DEV, DEV_PLAN))
        self.assertTrue(NEW.development_route(NEW.SHARED_SELECTION_ID, plan()))
        self.assertTrue(NEW.development_route(NEW.SHARED_SELECTION_ID, consumer_selection("S01")))
        claims = copy.deepcopy(DEV_PLAN)
        claims["devBatch"]["acceptance"] = True
        missing = {k: v for k, v in DEV_PLAN.items() if k != "devBatch"}
        wrong_tier = dict(copy.deepcopy(DEV_PLAN), tier="N8")
        for label, value in {"acceptance": claims, "missing": missing, "tier": wrong_tier, "none": None}.items():
            with self.subTest(label):
                self.assertFalse(NEW.development_route(DEV, value))

    def test_other_selections_need_development_only_and_a_development_tier(self):
        self.assertFalse(NEW.development_route(ORDINARY_D30, ORDINARY_PLAN))
        self.assertFalse(NEW.development_route(ORDINARY_D30, dict(ORDINARY_PLAN, acceptance=False)))
        self.assertFalse(NEW.development_route("c36-live-host", dict(ORDINARY_PLAN, tier="N8", developmentOnly=True)))
        self.assertTrue(NEW.development_route(ORDINARY_D30, dict(ORDINARY_PLAN, developmentOnly=True)))
        self.assertTrue(NEW.development_route(ORDINARY_D30, dict(ORDINARY_PLAN, developmentOnly=True, acceptance=False)))
        self.assertFalse(NEW.development_route(ORDINARY_D30, dict(ORDINARY_PLAN, developmentOnly=True, acceptance=True)))


class CompilerObservationDispatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workflow = (REPO_ROOT / NEW.WORKFLOW_PATH).read_text(encoding="utf-8")

    def test_default_dispatch_remains_ordinary_and_explicit_d50_is_bound(self):
        self.assertTrue(NEW.compiler_observation_input_declared(self.workflow))
        self.assertTrue(NEW.default_false_boolean_input_declared(
            self.workflow, NEW.SWIFT_DRIVER_JOBS_TWO_INPUT))
        ordinary = DispatchHarness(NEW, self.root, DEV, workflow=self.workflow, resolved=DEV_PLAN)
        ordinary.dispatch(kind="development")
        ordinary_record = json.loads((self.root / str(RUN) / "dispatch.json").read_text())
        self.assertNotIn("compilerObservation", ordinary_record)
        self.assertFalse(any("v23_d50_compiler_observation=" in str(call)
                             for call in ordinary.calls))
        with tempfile.TemporaryDirectory() as directory:
            host = Path(directory)
            observed = DispatchHarness(NEW, host, DEV, workflow=self.workflow, resolved=DEV_PLAN)
            observed.dispatch(kind="development", compiler_observation=True)
            record = json.loads((host / str(RUN) / "dispatch.json").read_text())
            with evidence_root(NEW, host):
                self.assertTrue(NEW.check_compiler_observation_record(record))
            self.assertEqual(record["kind"], "development")
            self.assertFalse(record["acceptance"])
            self.assertIn("v23_d50_compiler_observation=true", record["argv"])
            self.assertTrue(ledger_lines(host)[0]["compilerObservation"])
            attempt = json.loads((host / "v23-original-attempts" / record["attemptName"]).read_text())
            self.assertTrue(attempt["compilerObservation"])
            for downgrade in (dict(record, compilerObservation=False),
                              {key: value for key, value in record.items()
                               if key != "compilerObservation"}):
                with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "ledger/dispatch downgrade"):
                    NEW.check_compiler_observation_record(downgrade)
            ledger_path = host / "v23-original-ledger.jsonl"
            retained_ledger = ledger_path.read_text()
            downgraded_ledger = dict(ledger_lines(host)[0])
            downgraded_ledger.pop("compilerObservation")
            ledger_path.write_text(json.dumps(downgraded_ledger) + "\n")
            with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "attempt/dispatch downgrade"):
                NEW.check_compiler_observation_record(dict(record, compilerObservation=False))
            decoy = dict(record, compilerObservation=False,
                         attemptName=record["head"] + "-v23-dev-batch-no-index-d50.infra-retry.json")
            with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "attempt/dispatch downgrade"):
                NEW.check_compiler_observation_record(decoy)
            noncanonical = dict(decoy, attemptName="a" * 40 + "-other.json")
            with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "noncanonical attempt name"):
                NEW.check_compiler_observation_record(noncanonical)
            ledger_path.write_text(retained_ledger)
            attempt["compilerObservation"] = False
            (host / "v23-original-attempts" / record["attemptName"]).write_text(json.dumps(attempt))
            with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "attempt/dispatch"):
                NEW.check_compiler_observation_record(record)

    def test_driver_two_jobs_requires_observation_and_binds_attempt_ledger_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            host = Path(directory)
            observed = DispatchHarness(NEW, host, DEV, workflow=self.workflow, resolved=DEV_PLAN)
            observed.dispatch(kind="development", compiler_observation=True,
                swift_driver_jobs_two=True)
            self.assertLess(
                next(i for i, call in enumerate(observed.calls) if call[0] == "observation_preflight"),
                next(i for i, call in enumerate(observed.calls) if call[0] == "runs_for"))
            record = json.loads((host / str(RUN) / "dispatch.json").read_text())
            self.assertTrue(record["compilerObservation"])
            self.assertTrue(record["swiftDriverJobsTwo"])
            self.assertIn("v23_d50_swift_driver_jobs_two=true", record["argv"])
            with evidence_root(NEW, host):
                self.assertTrue(NEW.check_compiler_observation_record(record))
            attempt_path = host / "v23-original-attempts" / record["attemptName"]
            attempt = json.loads(attempt_path.read_text())
            self.assertTrue(attempt["swiftDriverJobsTwo"])
            self.assertTrue(ledger_lines(host)[0]["swiftDriverJobsTwo"])
            for downgraded in (dict(record, swiftDriverJobsTwo=False),
                               {key: value for key, value in record.items()
                                if key != "swiftDriverJobsTwo"},
                               dict(record, compilerObservation=False)):
                with self.subTest(downgraded=downgraded), evidence_root(NEW, host), \
                     self.assertRaises(SystemExit):
                    NEW.check_compiler_observation_record(downgraded)
            ledger_path = host / "v23-original-ledger.jsonl"
            original_ledger = ledger_path.read_text()
            downgraded_ledger = dict(ledger_lines(host)[0])
            downgraded_ledger.pop("swiftDriverJobsTwo")
            ledger_path.write_text(json.dumps(downgraded_ledger) + "\n")
            with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "ledger/dispatch"):
                NEW.check_compiler_observation_record(record)
            ledger_path.write_text(original_ledger)
            attempt.pop("swiftDriverJobsTwo")
            attempt_path.write_text(json.dumps(attempt))
            with evidence_root(NEW, host), self.assertRaisesRegex(SystemExit, "attempt/dispatch"):
                NEW.check_compiler_observation_record(record)

    def test_observation_preflight_refuses_before_attempt_ledger_or_workflow(self):
        harness = DispatchHarness(NEW, self.root, DEV, workflow=self.workflow, resolved=DEV_PLAN)
        harness.preflight_error = "compiler observation source preflight refused"
        with self.assertRaisesRegex(SystemExit, "source preflight refused"):
            harness.dispatch(kind="development", compiler_observation=True,
                             swift_driver_jobs_two=True)
        self.assertFalse(harness.dispatched)
        self.assertFalse((self.root / "v23-original-attempts").exists())
        self.assertFalse((self.root / "v23-original-ledger.jsonl").exists())
        self.assertFalse(any(call[0] in ("runs_for", "api") for call in harness.calls))

    def test_exact_f9_observation_source_preflight_and_hostile_bindings(self):
        import importlib.util
        timing_path = REPO_ROOT / "Scripts/v23-compiler-timing.py"
        spec = importlib.util.spec_from_file_location("preflight_timing_test", timing_path)
        timing = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(timing)
        profile = timing.DEVELOPMENT_F9_J2_PROFILE
        prospective_head = "b" * 40
        selected = (REPO_ROOT / "Scripts/ci-selection.json").read_bytes()
        mapping = (REPO_ROOT / "Scripts/ci-selection-map.json").read_bytes()
        overridden = {}

        def git(*args):
            if args in overridden:
                return overridden[args]
            if args == ("cat-file", "commit", "HEAD"):
                return ("tree " + "c" * 40 + "\nparent " + profile["parentHead"] +
                        "\n\nmessage\n").encode()
            if args == ("rev-parse", "HEAD"):
                return (prospective_head + "\n").encode()
            if args[0] == "rev-parse" and args[1].startswith("HEAD:"):
                return (profile["sourceTrees"][args[1][5:]] + "\n").encode()
            if args[0] == "show":
                relative = args[1].split(":", 1)[1]
                if relative == "Scripts/ci-selection.json":
                    return selected
                if relative == "Scripts/ci-selection-map.json":
                    return mapping
                return (REPO_ROOT / relative).read_bytes()
            raise AssertionError(args)

        with mock.patch.object(NEW, "git_bytes", side_effect=git):
            NEW.preflight_compiler_observation_source(
                prospective_head, profile["resolvedSelectionSHA256"], True)
            cases = [
                (("cat-file", "commit", "HEAD"), b"tree " + b"c" * 40 + b"\nparent " +
                 b"0" * 40 + b"\n\nmessage\n"),
                (("cat-file", "commit", "HEAD"), b"tree " + b"c" * 40 + b"\nparent " +
                 profile["parentHead"].encode() + b"\nparent " + b"0" * 40 + b"\n\nmessage\n"),
                (("rev-parse", "HEAD:FieldEvidenceApp"), b"0" * 40 + b"\n"),
                (("show", prospective_head + ":Scripts/ci-selection.json"), selected + b" "),
                (("show", prospective_head + ":Scripts/ci-selection-map.json"), mapping + b" "),
                (("show", prospective_head + ":Scripts/v23-compiler-timing.py"), b"dirty"),
                (("show", prospective_head + ":Scripts/" + timing.DEVELOPMENT_F9_J2_FILE), b"dirty"),
            ]
            for key, value in cases:
                overridden[key] = value
                with self.subTest(key=key), self.assertRaisesRegex(
                        SystemExit, "source preflight refused"):
                    NEW.preflight_compiler_observation_source(
                        prospective_head, profile["resolvedSelectionSHA256"], True)
                overridden.clear()
            with self.assertRaisesRegex(SystemExit, "source preflight refused"):
                NEW.preflight_compiler_observation_source(
                    prospective_head, "0" * 64, True)
            with self.assertRaisesRegex(SystemExit, "source preflight refused"):
                NEW.preflight_compiler_observation_source(
                    prospective_head, profile["resolvedSelectionSHA256"], False)

    def test_driver_two_jobs_refuses_unobserved_or_gate_before_dispatch(self):
        for route, kind, observation in ((DEV, "development", False),
                                         (DEV, "gate", True),
                                         (NEW.SHARED_SELECTION_ID, "development", True)):
            with self.subTest(route=route, kind=kind, observation=observation):
                with tempfile.TemporaryDirectory() as directory:
                    harness = DispatchHarness(NEW, Path(directory), route,
                        workflow=self.workflow,
                        resolved=DEV_PLAN if route == DEV else None)
                    with self.assertRaises(SystemExit):
                        harness.dispatch(kind=kind, compiler_observation=observation,
                            swift_driver_jobs_two=True)
                    self.assertFalse(harness.dispatched)

    def test_opt_in_refuses_gate_other_route_or_missing_boolean_before_dispatch(self):
        for route, kind, workflow in ((DEV, "gate", self.workflow),
                                      (NEW.SHARED_SELECTION_ID, "development", self.workflow),
                                      (DEV, "development", self.workflow.replace(
                                          "      v23_d50_compiler_observation:",
                                          "      absent_observation_input:"))):
            with self.subTest(route=route, kind=kind):
                with tempfile.TemporaryDirectory() as directory:
                    harness = DispatchHarness(NEW, Path(directory), route, workflow=workflow,
                        resolved=DEV_PLAN if route == DEV else None)
                    with self.assertRaises(SystemExit):
                        harness.dispatch(kind=kind, compiler_observation=True)
                    self.assertFalse(harness.dispatched)


class RUI1OriginalTests(unittest.TestCase):
    def test_explicit_kind_and_serialized_dispatch_request_ui(self):
        plan = {'tier': 'RUI1', 'runUISmoke': True, 'unitTestSelectors': ['unit'],
                'uiTestSelectors': ['ui'], 'uiBatch': {'developmentOnly': True, 'acceptance': False}}
        route = NEW.UI_BATCH_SELECTION_ID
        self.assertTrue(NEW.development_route(route, plan))
        self.assertFalse(NEW.development_route('other', plan))
        self.assertFalse(NEW.development_route(route, dict(plan, uiBatch={'acceptance': False})))
        self.assertNotIn(route, NEW.PER_HEAD_SELECTIONS)
        with self.assertRaisesRegex(SystemExit, '--kind'): NEW.run_kind(route, None)
        for kind in ('gate', 'development'):
            with tempfile.TemporaryDirectory() as temporary:
                harness = DispatchHarness(NEW, Path(temporary), route, resolved=plan,
                    workflow=(REPO_ROOT / NEW.WORKFLOW_PATH).read_text())
                harness.dispatch(kind=kind)
                calls = [entry[1] for entry in harness.calls if entry[0] == 'subprocess' and entry[1][:2] == ('gh','workflow')]
                self.assertEqual(len(calls), 1)
                self.assertIn('run_ui_smoke=true', calls[0])
                if kind == 'development':
                    self.assertIn('v23_run_kind=development', calls[0])
                else:
                    self.assertFalse(any(x.startswith('v23_run_kind=') for x in calls[0]))  # default gate

    def test_ui_failures_and_interruption_are_counted_and_cannot_be_infra_retries(self):
        route = NEW.UI_BATCH_SELECTION_ID
        for outcome in ('failed', 'started'):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                directory = stage_single(root)
                dispatch_path = directory / 'dispatch.json'
                dispatch = json.loads(dispatch_path.read_bytes())
                dispatch['selection'] = route
                selected_path = directory / 'artifact/ci-selection.selected.json'
                selected = json.loads(selected_path.read_bytes())
                selector = 'FieldEvidenceAppUITests/V23Phase1CriticalStatesUITests/test3SettingsAppLockAndCover'
                selected.update(tier='RUI1', runUISmoke=True, uiTestSelectors=[selector], uiBatch={'acceptance':False})
                selected_path.write_bytes(canonical(selected))
                dispatch.update(resolvedSelection=selected, resolvedSelectionSHA256=sha(canonical(selected)))
                dispatch_path.write_bytes(canonical(dispatch))
                log = directory / 'artifact/ui-smoke.log'
                log.write_text("Test Case '-[FieldEvidenceAppUITests.V23Phase1CriticalStatesUITests test3SettingsAppLockAndCover]' "
                               + outcome + (" (1.234 seconds).\n" if outcome == 'failed' else "\n"))
                with evidence_root(NEW, root): summary = NEW.summarize(SINGLE_RUN)
                self.assertEqual(summary['tests'][selector]['result'], 'Failed' if outcome == 'failed' else 'Interrupted')
                self.assertFalse(summary['ownerReview']['verifiedOriginals'])
                refusals, _ = NEW.infra_failure_classification(summary, [], SINGLE_RUN, summary['head'], route)
                self.assertTrue(any('test phase ran' in r for r in refusals))

    def test_collection_never_issues_review_for_failed_or_mismatched_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            dispatched = {'head': HEAD, 'selection': NEW.UI_BATCH_SELECTION_ID, 'resolvedSelectionSHA256': '0'*64}
            for observed, initial in (({'id':123,'conclusion':'failure'}, []),
                                      ({'id':123,'conclusion':'success'}, ['wrong artifacts']),
                                      ({'id':123,'conclusion':'success'}, [])):
                notes = list(initial)
                with mock.patch.object(NEW, 'git_bytes', side_effect=AssertionError('no checkout on invalid original')):
                    NEW.collect_ui_review(directory, dispatched, observed, notes)
                self.assertGreater(len(notes), len(initial))
                self.assertFalse((directory / 'owner-review.html').exists())
                self.assertFalse((directory / 'rui1-collected-review.json').exists())

    def test_success_without_verified_package_fails_after_retaining_raw_export_manifest(self):
        run = json.loads((FIXTURE / 'run.json').read_bytes())
        run['conclusion'] = 'success'
        jobs = json.loads((FIXTURE / 'jobs.json').read_bytes())['jobs']
        files = {name: (FIXTURE / 'artifact' / name).read_bytes()
                 for name in ('ci-selection.selected.json', 'test-smoke.log', 'build-smoke.log',
                              'unit-test-results.json', 'native-admission.json')}
        selected = json.loads(files['ci-selection.selected.json'])
        selected.update(tier='RUI1', runUISmoke=True, uiTestSelectors=['FieldEvidenceAppUITests/Fixture/testState'])
        files['ci-selection.selected.json'] = canonical(selected)
        export_name = 'rui1-original-attachments/manifest.json'
        files[export_name] = b'[]\n'  # Hostile incomplete export, retained intact.
        files['nested/summary-original.json'] = b'{"raw":"original"}\n'
        blob = zip_bytes(files)
        listing = json.loads((FIXTURE / 'artifacts.json').read_bytes())['artifacts']
        listing[0].update(name=f'ios-ci-native-github-{NEW.UI_BATCH_SELECTION_ID}-{SINGLE_RUN}-1',
                          digest='sha256:' + hashlib.sha256(blob).hexdigest())
        fake = FakeGitHub(run, jobs, listing, {listing[0]['id']: blob}, zip_bytes({'whole-job.txt':b'original\n'}))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / str(SINGLE_RUN)
            directory.mkdir()
            dispatched = json.loads((FIXTURE / 'dispatch.json').read_bytes())
            dispatched.update(selection=NEW.UI_BATCH_SELECTION_ID, resolvedSelection=selected,
                              resolvedSelectionSHA256=sha(files['ci-selection.selected.json']))
            (directory / 'dispatch.json').write_bytes(canonical(dispatched))
            def denied(directory, dispatched, observed, notes):
                notes.append('synthetic protocol rejection: incomplete original export')
            with evidence_root(NEW, root), mock.patch.object(NEW, 'api', fake.api), \
                    mock.patch.object(NEW, 'api_bytes', fake.api_bytes), \
                    mock.patch.object(NEW, 'collect_ui_review', side_effect=denied), \
                    contextlib.redirect_stdout(io.StringIO()), self.assertRaisesRegex(SystemExit,'original validation failed'):
                NEW.collect(SINGLE_RUN, False)
            manifest = json.loads((directory / 'manifest.json').read_bytes())
            self.assertEqual(manifest['files']['artifact/' + export_name], sha(files[export_name]))
            self.assertEqual(manifest['files']['artifact/nested/summary-original.json'],
                             sha(files['nested/summary-original.json']))
            self.assertEqual((directory / 'artifact' / export_name).read_bytes(), files[export_name])
            self.assertIn('run-logs.zip', manifest['files'])
            self.assertIn('artifact-' + str(listing[0]['id']) + '.zip', manifest['files'])
            self.assertFalse((directory / 'owner-review.html').exists())
            self.assertFalse(json.loads((directory / 'summary.json').read_bytes())['ownerReview']['verifiedOriginals'])

    def test_collector_uses_committed_verifier_and_dispatch_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / 'artifact').mkdir()
            raw = b'{"protocol":"fixture"}\n'
            (directory / 'artifact/ci-selection.selected.json').write_bytes(raw)
            dispatched = {'head': HEAD, 'selection': NEW.UI_BATCH_SELECTION_ID, 'resolvedSelectionSHA256': sha(raw)}
            archive = io.BytesIO()
            import tarfile
            with tarfile.open(fileobj=archive, mode='w'): pass
            calls = []
            def check(args, **kwargs):
                calls.append((args, kwargs))
                return subprocess.CompletedProcess(args, 0, b'{"acceptance":false,"humanReviewCompleted":false}\n', b'')
            with mock.patch.object(NEW, 'git_bytes', return_value=archive.getvalue()) as tree, \
                    mock.patch.object(NEW.subprocess, 'run', side_effect=check):
                notes = []
                NEW.collect_ui_review(directory, dispatched, {'id':123,'conclusion':'success'}, notes)
            tree.assert_called_once_with('archive', '--format=tar', HEAD)
            argv, kwargs = calls[0]
            self.assertEqual(argv[2:4], ['Scripts/v23-ui-evidence.py', 'collect'])
            self.assertEqual(argv[argv.index('--expected-head')+1], HEAD)
            self.assertEqual(argv[argv.index('--expected-run')+1], '123')
            self.assertEqual(kwargs['cwd'], argv[argv.index('--root')+1])
            self.assertEqual(notes, [])
            self.assertFalse(json.loads((directory / 'rui1-collected-review.json').read_bytes())['acceptance'])


class EvidenceRootTests(unittest.TestCase):
    def test_configured_root_wins_on_every_platform(self):
        for os_name in ("nt", "posix"):
            configured = str(Path(tempfile.gettempdir()) / "evidence")
            self.assertEqual(NEW.evidence_root({"V23_EVIDENCE_ROOT": configured}, os_name), Path(configured))

    def test_defaults_keep_windows_and_use_home_elsewhere(self):
        self.assertEqual(NEW.evidence_root({}, "nt"), Path("C:/AssetRounds-v23-review-evidence"))
        self.assertEqual(NEW.evidence_root({"V23_EVIDENCE_ROOT": ""}, "nt"), Path("C:/AssetRounds-v23-review-evidence"))
        self.assertEqual(NEW.evidence_root({}, "posix"), Path.home() / "AssetRounds-v23-review-evidence")

    def test_unc_and_device_roots_are_refused_on_windows(self):
        for configured in ("\\\\server\\share\\evidence", "//server/share/evidence", "\\\\?\\C:\\evidence",
                           "\\\\.\\C:\\evidence"):
            with self.subTest(configured), self.assertRaisesRegex(SystemExit, "UNC or device paths"):
                NEW.evidence_root({"V23_EVIDENCE_ROOT": configured}, "nt")

    def test_module_paths_follow_the_root(self):
        environment = dict(os.environ, V23_EVIDENCE_ROOT=str(Path(tempfile.gettempdir()) / "v23-root"))
        with mock.patch.dict(os.environ, environment, clear=True):
            module = load(TOOL, "v23_original_env")
        self.assertEqual(module.EVIDENCE, Path(tempfile.gettempdir()) / "v23-root")
        self.assertEqual(module.LEDGER, module.EVIDENCE / "v23-original-ledger.jsonl")
        self.assertEqual(module.ATTEMPTS, module.EVIDENCE / "v23-original-attempts")
        self.assertEqual(module.ROOT, REPO_ROOT)

    def test_publish_never_replaces_an_existing_record(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / "run.json"
            NEW.save_bytes(target, b"first\n")
            with self.assertRaises(FileExistsError):
                NEW.save_bytes(target, b"second\n")
            self.assertEqual(target.read_bytes(), b"first\n")


# --------------------------------------------------------------------------
# Infrastructure reruns.
# --------------------------------------------------------------------------

WORKER_JOB = f"GitHub Xcode 26.6 acceptance {DOT} none {DOT} none / verify"
TOOLCHAIN = "Verify pinned toolchain, shared scheme, and simulator"
BEFORE_BUILD = (("Set up job", "success"), ("Prepare evidence directory", "success"),
                ("Check out the exact revision", "success"), ("Validate task selection and timeout tier", "success"),
                (TOOLCHAIN, "success"), ("Verify setup budget before build", "success"))
BOOTED = (("Boot selected Simulator", "success"), ("Await selected Simulator boot", "success"))
BUILT = (("Build unsigned simulator app", "success"),)
FINISHED = (("Validate required build and test evidence", "success"),
            ("Validate exact ordinary integration native checkpoint", "success"),
            ("Remove owned isolated Simulator", "success"), ("Upload build evidence", "success"),
            ("Complete job", "success"))
SETUP_FAILURE = BEFORE_BUILD + (("Boot selected Simulator", "failure"),
                                ("Validate required build and test evidence", "failure"),
                                ("Upload build evidence", "success"), ("Complete job", "success"))
ARTIFACT_FAILURE = BEFORE_BUILD + BOOTED + BUILT + (("Run targeted tests", "success"),) + FINISHED[:3] + (
    ("Upload build evidence", "failure"), ("Complete job", "success"))
RUNNER_FAILURE = BEFORE_BUILD + BOOTED + BUILT
TEST_PHASE_FAILURE = BEFORE_BUILD + BOOTED + BUILT + (("Run targeted tests", "failure"),) + FINISHED
BUILD_FAILURE = BEFORE_BUILD + BOOTED + (("Build unsigned simulator app", "failure"),) + FINISHED
SELECTION_FAILURE = BEFORE_BUILD[:3] + (("Validate task selection and timeout tier", "failure"),) + FINISHED[-2:]
TOOLCHAIN_FAILURE = BEFORE_BUILD[:4] + ((TOOLCHAIN, "failure"),) + FINISHED[-2:]
BUDGET_FAILURE = BEFORE_BUILD + BOOTED + BUILT + (("Run targeted tests", "success"),) + FINISHED[:2] + (
    ("Verify selected total budget before upload", "failure"), ("Upload build evidence", "success"))


def step_records(pairs, job=WORKER_JOB):
    return [{"job": job, "step": name, "conclusion": conclusion, "startedAt": None, "completedAt": None}
            for name, conclusion in pairs]


def retained_summary():
    """The real summary of the fixture original: 1 Failed, 14 Passed."""
    return json.loads(summarize_bytes(NEW, False))


def crafted_summary(result, steps, conclusion="failure", swift_errors=0):
    summary = retained_summary()
    summary.update(conclusion=conclusion, steps=step_records(steps), counts={result: len(summary["tests"])})
    summary["build"]["swiftErrors"] = swift_errors
    for value in summary["tests"].values():
        value.update(result=result, failures=[], seconds=None if result == "NotStarted" else 1.0,
                     lines=0 if result == "NotStarted" else 2)
    return summary


def fixture_jobs(worker_conclusion="failure"):
    jobs = json.loads((FIXTURE / "jobs.json").read_text(encoding="utf-8"))["jobs"]
    for job in jobs:
        if job["name"] == WORKER_JOB:
            job["conclusion"] = worker_conclusion
    return jobs


def classify(summary, jobs=None, run_id=SINGLE_RUN, head=DEV_HEAD, selection=DEV):
    return NEW.infra_failure_classification(summary, fixture_jobs() if jobs is None else jobs, run_id, head, selection)


class InfraClassificationTests(unittest.TestCase):
    def test_setup_artifact_and_runner_failures_qualify(self):
        refusals, causes = classify(crafted_summary("NotStarted", SETUP_FAILURE))
        self.assertEqual((refusals, causes), ([], [{"job": WORKER_JOB, "step": "Boot selected Simulator",
                                                     "conclusion": "failure", "category": "setup"}]))
        refusals, causes = classify(crafted_summary("Passed", ARTIFACT_FAILURE))
        self.assertEqual((refusals, [c["category"] for c in causes]), ([], ["artifact"]))
        refusals, causes = classify(crafted_summary("NotStarted", RUNNER_FAILURE))
        self.assertEqual((refusals, causes), ([], [{"job": WORKER_JOB, "step": None, "conclusion": "failure",
                                                     "category": "runner"}]))

    def test_the_retained_test_failure_is_refused(self):
        refusals, _ = classify(retained_summary())
        self.assertTrue(any("1 tests failed or were interrupted" in r for r in refusals), refusals)
        self.assertTrue(any("the test phase started and failed" in r for r in refusals), refusals)

    def test_test_build_source_toolchain_and_budget_failures_are_refused(self):
        cases = {
            "test phase": (crafted_summary("NotStarted", TEST_PHASE_FAILURE), "the test phase started and failed"),
            "interrupted": (crafted_summary("Interrupted", RUNNER_FAILURE), "tests failed or were interrupted"),
            "build step": (crafted_summary("NotStarted", BUILD_FAILURE), "'Build unsigned simulator app'"),
            "compile": (crafted_summary("NotStarted", SETUP_FAILURE, swift_errors=3), "3 Swift compile errors"),
            "selection": (crafted_summary("NotStarted", SELECTION_FAILURE), "'Validate task selection and timeout tier'"),
            "toolchain": (crafted_summary("NotStarted", TOOLCHAIN_FAILURE), f"'{TOOLCHAIN}'"),
            "budget after tests": (crafted_summary("Passed", BUDGET_FAILURE),
                                   "not a artifact or runner step after its tests executed"),
            "cancelled": (crafted_summary("NotStarted", SETUP_FAILURE, conclusion="cancelled"), "concluded 'cancelled'"),
            "success": (crafted_summary("Passed", BEFORE_BUILD, conclusion="success"), "concluded 'success'"),
        }
        for label, (summary, expected) in cases.items():
            with self.subTest(label):
                refusals, causes = classify(summary)
                self.assertTrue(any(expected in r for r in refusals), refusals)
        self.assertNotIn(TOOLCHAIN, NEW.INFRA_SETUP_STEPS | NEW.INFRA_ARTIFACT_STEPS | NEW.INFRA_RUNNER_STEPS)

    def test_nothing_proven_and_identity_mismatch_are_refused(self):
        refusals, _ = classify(crafted_summary("NotStarted", RUNNER_FAILURE), jobs=fixture_jobs("success"))
        self.assertEqual(refusals, ["no failing step or failed job proves a setup, artifact or runner failure"])
        refusals, _ = classify(crafted_summary("NotStarted", SETUP_FAILURE), head=OTHER_HEAD)
        self.assertEqual(len(refusals), 1)
        self.assertIn("summary identity", refusals[0])

    def test_shared_route_classifies_each_consumer_job(self):
        executed, idle = consumer_job_name("S01"), consumer_job_name("S02")
        tests = {**{s: {"result": "Passed"} for s in selectors("S01")},
                 **{s: {"result": "NotStarted"} for s in selectors("S02")}}

        def shared_summary(idle_steps, executed_steps=(("Run targeted tests", "success"),)):
            return {"runID": RUN, "head": HEAD, "selection": NEW.SHARED_SELECTION_ID, "conclusion": "failure",
                    "route": "shared-build", "build": {"swiftErrors": 0}, "tests": tests,
                    "partitions": {"S01": {"job": {"name": executed}, "counts": {"Passed": 3}},
                                   "S02": {"job": {"name": idle}, "counts": {"NotStarted": 3}}},
                    "steps": step_records(executed_steps, executed) + step_records(idle_steps, idle)}
        jobs = [{"name": executed, "conclusion": "success"}, {"name": idle, "conclusion": "failure"}]
        refusals, causes = NEW.infra_failure_classification(
            shared_summary((("Set up job", "success"), ("Boot selected Simulator", "failure"))), jobs,
            RUN, HEAD, NEW.SHARED_SELECTION_ID)
        self.assertEqual((refusals, [c["category"] for c in causes]), ([], ["setup"]))
        for failing in ("Verify and restore V23 shared coverage payload", TOOLCHAIN):
            with self.subTest(failing):
                refusals, _ = NEW.infra_failure_classification(
                    shared_summary(((failing, "failure"),)), jobs, RUN, HEAD, NEW.SHARED_SELECTION_ID)
                self.assertEqual(len(refusals), 1)
        refusals, _ = NEW.infra_failure_classification(
            shared_summary((), (("Run targeted tests", "success"), ("Boot selected Simulator", "failure"))),
            jobs, RUN, HEAD, NEW.SHARED_SELECTION_ID)
        self.assertEqual(len(refusals), 1)
        self.assertIn("after its tests executed", refusals[0])


def development_dispatch(kind="development"):
    record = copy.deepcopy(FIXTURE_DISPATCH)
    if kind is not None:
        record["kind"] = kind
    return record


def stage_original(test, summary=None, ledger=True, collected=True, ledger_head=DEV_HEAD, kind="development",
                   ledger_kind="same"):
    """Evidence root holding the fixture original 36104533833 as a ledgered, collected dev-batch run."""
    temporary = tempfile.TemporaryDirectory()
    test.addCleanup(temporary.cleanup)
    root = Path(temporary.name)
    directory = stage_single(root)
    (directory / "dispatch.json").write_text(json.dumps(development_dispatch(kind), indent=2, sort_keys=True) + "\n",
                                             encoding="utf-8", newline="\n")
    if collected:
        if summary is None:
            with evidence_root(NEW, root), contextlib.redirect_stdout(io.StringIO()):
                NEW.summarize(SINGLE_RUN)
        else:
            (directory / "summary.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n",
                                                    encoding="utf-8", newline="\n")
        (directory / "manifest.json").write_text(json.dumps({"runID": SINGLE_RUN, "files": {}, "notes": []}),
                                                 encoding="utf-8")
    attempts = root / "v23-original-attempts"
    attempts.mkdir()
    (attempts / f"{DEV_HEAD}-{DEV}.json").write_bytes(b'{"original": true}\n')
    if ledger:
        entry = {"runID": SINGLE_RUN, "head": ledger_head, "parent": DEV_PARENT, "selection": DEV,
                 "url": FIXTURE_DISPATCH["url"], "requestedAtUTC": FIXTURE_DISPATCH["requestedAtUTC"]}
        entry_kind = kind if ledger_kind == "same" else ledger_kind
        if entry_kind is not None:
            entry["kind"] = entry_kind
        write_ledger(root, [entry])
    return root


def retry_harness(root, status="completed", conclusion="failure", selection=DEV, resolved=DEV_PLAN, known=(SINGLE_RUN,)):
    record = dict(FIXTURE_RUN, status=status, conclusion=conclusion)
    return DispatchHarness(NEW, root, selection, head=DEV_HEAD, parent=DEV_PARENT, resolved=resolved,
                           known_runs=[{"id": x} for x in known], run_records={SINGLE_RUN: record})


class InfraRetryDispatchTests(unittest.TestCase):
    def retry_path(self, root):
        return root / "v23-original-attempts" / f"{DEV_HEAD}-{DEV}.infra-retry.json"

    def assert_refused(self, root, harness, expected, reason=REASON, kind="development"):
        with self.assertRaises(SystemExit) as caught:
            harness.dispatch(kind=kind, infra_retry_of=SINGLE_RUN, reason=reason)
        self.assertIn(expected, str(caught.exception))
        self.assertFalse(harness.dispatched)
        self.assertFalse(self.retry_path(root).exists())
        self.assertFalse((root / str(RUN)).exists())
        return str(caught.exception)

    def test_setup_failure_allows_one_recorded_rerun(self):
        root = stage_original(self, crafted_summary("NotStarted", SETUP_FAILURE))
        original_attempt = (root / "v23-original-attempts" / f"{DEV_HEAD}-{DEV}.json").read_bytes()
        harness = retry_harness(root)
        output = harness.dispatch(kind="development", infra_retry_of=SINGLE_RUN, reason="  " + REASON + "\n")
        self.assertTrue(harness.dispatched)
        self.assertIn(f'"infraRetryOf": {SINGLE_RUN}', output)
        ledger = ledger_lines(root)
        self.assertEqual([x["runID"] for x in ledger], [SINGLE_RUN, RUN])
        self.assertEqual((ledger[1]["infraRetryOf"], ledger[1]["infraRetryReason"], ledger[1]["head"], ledger[1]["kind"]),
                         (SINGLE_RUN, REASON, DEV_HEAD, "development"))
        attempt = json.loads(self.retry_path(root).read_text(encoding="utf-8"))
        self.assertEqual((attempt["infraRetryOf"], attempt["infraRetryReason"], attempt["kind"]),
                         (SINGLE_RUN, REASON, "development"))
        self.assertEqual(attempt["infraRetryEvidence"]["causes"],
                         [{"job": WORKER_JOB, "step": "Boot selected Simulator", "conclusion": "failure",
                           "category": "setup"}])
        self.assertEqual(attempt["infraRetryEvidence"]["summarySHA256"],
                         sha((root / str(SINGLE_RUN) / "summary.json").read_bytes()))
        self.assertEqual((root / "v23-original-attempts" / f"{DEV_HEAD}-{DEV}.json").read_bytes(), original_attempt)
        record = json.loads((root / str(RUN) / "dispatch.json").read_text(encoding="utf-8"))
        self.assertEqual((record["infraRetryOf"], record["infraRetryReason"], record["acceptance"], record["kind"]),
                         (SINGLE_RUN, REASON, False, "development"))
        self.assertIn(("api", f"repos/{REPO}/actions/runs/{SINGLE_RUN}"), harness.calls)

    def test_only_one_rerun_per_head_and_selection(self):
        root = stage_original(self, crafted_summary("NotStarted", SETUP_FAILURE))
        retry_harness(root).dispatch(kind="development", infra_retry_of=SINGLE_RUN, reason=REASON)
        # The rerun's own infrastructure failure never yields a third original here.
        (root / str(RUN) / "summary.json").write_text(json.dumps(crafted_summary("NotStarted", SETUP_FAILURE)),
                                                      encoding="utf-8")
        for target in (RUN, SINGLE_RUN):
            with self.subTest(target):
                again = retry_harness(root, known=(SINGLE_RUN, RUN))
                with self.assertRaisesRegex(SystemExit, "already had its one infrastructure rerun"):
                    again.dispatch(kind="development", infra_retry_of=target, reason=REASON)
                self.assertFalse(again.dispatched)
        self.assertEqual(len(ledger_lines(root)), 2)
        root = stage_original(self, crafted_summary("NotStarted", SETUP_FAILURE))
        self.retry_path(root).write_text("{}\n", encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "already had its one infrastructure rerun"):
            retry_harness(root).dispatch(kind="development", infra_retry_of=SINGLE_RUN, reason=REASON)

    def test_artifact_and_runner_failures_allow_a_rerun(self):
        for label, summary in {"artifact": crafted_summary("Passed", ARTIFACT_FAILURE),
                               "runner": crafted_summary("NotStarted", RUNNER_FAILURE)}.items():
            with self.subTest(label):
                root = stage_original(self, summary)
                harness = retry_harness(root)
                harness.dispatch(kind="development", infra_retry_of=SINGLE_RUN, reason=REASON)
                self.assertTrue(harness.dispatched)
                attempt = json.loads(self.retry_path(root).read_text(encoding="utf-8"))
                self.assertEqual([c["category"] for c in attempt["infraRetryEvidence"]["causes"]], [label])

    def test_tests_that_ran_and_failed_and_toolchain_failures_are_refused(self):
        root = stage_original(self)  # the real collected summary: 1 Failed, 14 Passed
        message = self.assert_refused(root, retry_harness(root), "is not an infrastructure failure")
        self.assertIn("tests failed or were interrupted", message)
        root = stage_original(self, crafted_summary("NotStarted", TEST_PHASE_FAILURE))
        self.assert_refused(root, retry_harness(root), "the test phase started and failed")
        root = stage_original(self, crafted_summary("NotStarted", TOOLCHAIN_FAILURE))
        self.assert_refused(root, retry_harness(root), f"'{TOOLCHAIN}'")

    def test_gate_historical_and_unmarked_runs_are_never_rerun(self):
        summary = crafted_summary("NotStarted", SETUP_FAILURE)
        for label, (kind, ledger_kind, expected) in {
                "gate": ("gate", "same", "has gate or unmarked originals"),
                "historical": (None, "same", "has gate or unmarked originals"),
                "dispatch disagrees": ("gate", "development", "is not recorded as a development run"),
                "ledger unmarked": ("development", None, "has gate or unmarked originals")}.items():
            with self.subTest(label):
                root = stage_original(self, summary, kind=kind, ledger_kind=ledger_kind)
                self.assert_refused(root, retry_harness(root), expected)
        root = stage_original(self, summary)
        write_ledger(root, [{"runID": 31, "head": DEV_HEAD, "selection": DEV, "kind": "gate"}])
        self.assert_refused(root, retry_harness(root, known=(SINGLE_RUN, 31)), "has gate or unmarked originals [31]")

    def test_rerun_needs_the_development_kind_and_route(self):
        root = stage_original(self, crafted_summary("NotStarted", SETUP_FAILURE))
        for kind in ("gate", None):
            with self.subTest(kind):
                harness = retry_harness(root)
                self.assert_refused(root, harness, "--kind" if kind is None else "needs --kind development", kind=kind)
                self.assertEqual(harness.calls, [])
        ordinary = retry_harness(root, selection=ORDINARY_D30, resolved=ORDINARY_PLAN)
        self.assert_refused(root, ordinary, "only for development routes")
        self.assertNotIn("api", [call[0] for call in ordinary.calls])
        claims = copy.deepcopy(DEV_PLAN)
        claims["devBatch"]["acceptance"] = True
        self.assert_refused(root, retry_harness(root, resolved=claims), "only for development routes")

    def test_unterminal_unledgered_foreign_and_uncollected_runs_are_refused(self):
        summary = crafted_summary("NotStarted", SETUP_FAILURE)
        root = stage_original(self, summary)
        for status in ("queued", "in_progress", "waiting"):
            with self.subTest(status):
                self.assert_refused(root, retry_harness(root, status=status, conclusion=None), "not terminal")
        root = stage_original(self, summary, ledger=False)
        self.assert_refused(root, retry_harness(root), "is not a ledgered original")
        root = stage_original(self, summary, ledger_head=OTHER_HEAD)
        self.assert_refused(root, retry_harness(root), "is not a ledgered original")
        root = stage_original(self, summary, collected=False)
        self.assert_refused(root, retry_harness(root), "is not collected")

    def test_missing_reason_is_refused_before_any_action(self):
        root = stage_original(self, crafted_summary("NotStarted", SETUP_FAILURE))
        for reason in (None, "", "   \n"):
            with self.subTest(repr(reason)):
                harness = retry_harness(root)
                self.assert_refused(root, harness, "requires a non-empty --reason", reason=reason)
                self.assertEqual(harness.calls, [])
        harness = retry_harness(root)
        with self.assertRaisesRegex(SystemExit, "only accepted with --infra-retry-of"):
            harness.dispatch(kind="development", reason=REASON)
        self.assertEqual(harness.calls, [])

    def test_command_line_requires_reason_with_rerun(self):
        for argv in (["dispatch", "--selection", DEV, "--kind", "development", "--infra-retry-of", str(SINGLE_RUN)],
                     ["dispatch", "--selection", DEV, "--kind", "development", "--reason", REASON],
                     ["cancel", "--run", str(SINGLE_RUN)]):
            with self.subTest(argv), mock.patch.object(sys, "argv", ["v23-original.py", *argv]), \
                    contextlib.redirect_stderr(io.StringIO()), mock.patch.object(NEW, "dispatch") as dispatch, \
                    mock.patch.object(NEW, "cancel") as cancel, self.assertRaises(SystemExit) as caught:
                NEW.main()
            self.assertEqual(caught.exception.code, 2)
            dispatch.assert_not_called()
            cancel.assert_not_called()

    def test_cancelled_originals_are_refused(self):
        summary = crafted_summary("NotStarted", SETUP_FAILURE)
        for event in ("cancel-intent", "cancel-complete"):
            with self.subTest(event):
                root = stage_original(self, summary)
                write_ledger(root, [{"event": event, "runID": SINGLE_RUN, "head": DEV_HEAD, "selection": DEV}])
                self.assert_refused(root, retry_harness(root), "was cancelled through this ledger")


# --------------------------------------------------------------------------
# Cancellation.
# --------------------------------------------------------------------------

def stage_active(test, dispatch_record=None, ledger_kind="same"):
    temporary = tempfile.TemporaryDirectory()
    test.addCleanup(temporary.cleanup)
    root = Path(temporary.name)
    (root / str(SINGLE_RUN)).mkdir()
    record = development_dispatch() if dispatch_record is None else dispatch_record
    (root / str(SINGLE_RUN) / "dispatch.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n",
                                                          encoding="utf-8", newline="\n")
    entry = {"runID": SINGLE_RUN, "head": record["head"], "parent": record["parent"], "selection": record["selection"],
             "url": record["url"], "requestedAtUTC": record["requestedAtUTC"]}
    entry_kind = record.get("kind") if ledger_kind == "same" else ledger_kind
    if entry_kind is not None:
        entry["kind"] = entry_kind
    write_ledger(root, [entry])
    return root


def cancel_harness(root, status="in_progress", cancel_code=0):
    return DispatchHarness(NEW, root, DEV, head=DEV_HEAD, cancel_code=cancel_code,
                           run_records={SINGLE_RUN: dict(FIXTURE_RUN, status=status, conclusion=None)})


GH_CANCEL = ("subprocess", ("gh", "run", "cancel", str(SINGLE_RUN), "--repo", REPO))


class CancelTests(unittest.TestCase):
    def test_cancels_an_active_development_run_with_intent_then_completion(self):
        root = stage_active(self)
        harness = cancel_harness(root)
        harness.cancel(SINGLE_RUN, " known broken: C57 fixture rejects every save ")
        self.assertIn(GH_CANCEL, harness.calls)
        # The intent is on disk before `gh run cancel` runs; the completion follows it.
        self.assertEqual([x.get("event") for x in harness.ledger_at_cancel], [None, "cancel-intent"])
        intent, completion = ledger_lines(root)[1:]
        self.assertEqual({k: intent[k] for k in ("event", "runID", "head", "selection", "kind", "reason",
                                                 "statusBefore", "requestedAtUTC")},
                         {"event": "cancel-intent", "runID": SINGLE_RUN, "head": DEV_HEAD, "selection": DEV,
                          "kind": "development", "reason": "known broken: C57 fixture rejects every save",
                          "statusBefore": "in_progress", "requestedAtUTC": FIXED_NOW})
        self.assertEqual({k: completion[k] for k in ("event", "runID", "exitCode", "completedAtUTC")},
                         {"event": "cancel-complete", "runID": SINGLE_RUN, "exitCode": 0, "completedAtUTC": FIXED_NOW})
        with self.assertRaisesRegex(SystemExit, "already cancelled"):
            cancel_harness(root).cancel(SINGLE_RUN, "again")

    def test_a_cancelled_run_is_still_collected(self):
        root = stage_active(self)
        cancel_harness(root).cancel(SINGLE_RUN, "known broken")
        jobs = json.loads((FIXTURE / "jobs.json").read_text(encoding="utf-8"))["jobs"]
        folder = f"GitHub Xcode 26.6 acceptance {DOT} none {DOT} none _ verify"
        logs = zip_bytes({f"{folder}/23_Run targeted tests.txt":
                          (FIXTURE / "run-logs" / folder / "23_Run targeted tests.txt").read_bytes()})
        fake = FakeGitHub(dict(FIXTURE_RUN, status="completed", conclusion="cancelled"), jobs, [], {}, logs)
        with evidence_root(NEW, root), mock.patch.object(NEW, "api", fake.api), \
                mock.patch.object(NEW, "api_bytes", fake.api_bytes), contextlib.redirect_stdout(io.StringIO()):
            NEW.collect(SINGLE_RUN, False)
        directory = root / str(SINGLE_RUN)
        summary = json.loads((directory / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual((summary["conclusion"], summary["artifactMissing"], summary["resultsFromJobLog"]),
                         ("cancelled", True, True))
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        self.assertIn("run-logs.zip", manifest["files"])
        self.assertTrue(manifest["notes"])
        self.assertEqual([x.get("event") for x in ledger_lines(root)], [None, "cancel-intent", "cancel-complete"])

    def test_refusals(self):
        ordinary = dict(copy.deepcopy(FIXTURE_DISPATCH), selection=ORDINARY_D30, kind="development",
                        resolvedSelection=dict(ORDINARY_PLAN, acceptance=False))
        cases = {"non-development route": (stage_active(self, ordinary), "in_progress", REASON,
                                           "was not dispatched as a development route"),
                 "gate": (stage_active(self, development_dispatch("gate")), "in_progress", REASON,
                          "is not recorded as a development run"),
                 "historical": (stage_active(self, development_dispatch(None)), "in_progress", REASON,
                                "is not recorded as a development run"),
                 "ledger unmarked": (stage_active(self, ledger_kind=None), "in_progress", REASON,
                                     "is not recorded as a development run"),
                 "terminal": (stage_active(self), "completed", REASON, "not active"),
                 "reason": (stage_active(self), "in_progress", "  ", "non-empty --reason")}
        for label, (root, status, reason, expected) in cases.items():
            with self.subTest(label):
                harness = cancel_harness(root, status)
                with self.assertRaises(SystemExit) as caught:
                    harness.cancel(SINGLE_RUN, reason)
                self.assertIn(expected, str(caught.exception))
                self.assertNotIn(GH_CANCEL, harness.calls)
                self.assertEqual([x.get("event") for x in ledger_lines(root)], [None])
        harness = cancel_harness(stage_active(self))
        with self.assertRaisesRegex(SystemExit, "not a ledgered original"):
            harness.cancel(RUN, REASON)
        self.assertEqual(harness.calls, [])

    def test_a_failed_cancel_is_recorded_and_may_be_repeated(self):
        root = stage_active(self)
        with self.assertRaisesRegex(SystemExit, "gh run cancel failed"):
            cancel_harness(root, cancel_code=1).cancel(SINGLE_RUN, REASON)
        completion = ledger_lines(root)[-1]
        self.assertEqual((completion["event"], completion["exitCode"], completion["error"]),
                         ("cancel-complete", 1, "HTTP 409"))
        with self.assertRaisesRegex(SystemExit, "gh run cancel failed"):
            cancel_harness(root, cancel_code=None).cancel(SINGLE_RUN, REASON)
        self.assertEqual((ledger_lines(root)[-1]["exitCode"], ledger_lines(root)[-1]["error"]), (None, "gh"))
        cancel_harness(root).cancel(SINGLE_RUN, REASON)
        self.assertEqual([(x.get("event"), x.get("exitCode")) for x in ledger_lines(root)],
                         [(None, None), ("cancel-intent", None), ("cancel-complete", 1), ("cancel-intent", None),
                          ("cancel-complete", None), ("cancel-intent", None), ("cancel-complete", 0)])


# --------------------------------------------------------------------------
# Parallel development batches.
# --------------------------------------------------------------------------

def read_workflow(path):
    return (REPO_ROOT / path).read_text(encoding="utf-8")


class ParallelDevBatchTests(unittest.TestCase):
    def setUp(self):
        self.fresh_root()

    def fresh_root(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        write_ledger(self.root, [{"runID": 11, "head": DEV_HEAD, "parent": DEV_PARENT, "selection": DEV,
                                  "kind": "development"}])

    def harness(self, head=OTHER_HEAD, active_head=DEV_HEAD, **kwargs):
        active = {"id": 11, "status": "in_progress"}
        if active_head is not None:
            active["head_sha"] = active_head
        kwargs.setdefault("workflow", caller_text())
        kwargs.setdefault("workers", {WORKER_PATH: worker_text(), SHARED_WORKER_PATH: shared_worker_text()})
        return DispatchHarness(NEW, self.root, kwargs.pop("selection", DEV), head=head,
                               resolved=kwargs.pop("resolved", DEV_PLAN), active=[active], **kwargs)

    def assert_parallel_refused(self, harness, expected, kind="development"):
        with self.assertRaises(SystemExit) as caught:
            harness.dispatch(kind=kind)
        self.assertIn(expected, str(caught.exception))
        self.assertFalse(harness.dispatched)
        self.assertFalse((self.root / "v23-original-attempts").exists())
        return str(caught.exception)

    def test_allowed_at_a_different_head_with_per_head_groups(self):
        harness = self.harness()
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)
        self.assertIn(("git_bytes", ("show", f"{OTHER_HEAD}:{WORKER_PATH}")), harness.calls)
        self.assertEqual([x["runID"] for x in ledger_lines(self.root)], [11, RUN])
        self.assertTrue((self.root / "v23-original-attempts" / f"{OTHER_HEAD}-{DEV}.json").is_file())

    def test_development_passes_the_kind_input_and_gate_argv_is_unchanged(self):
        def argv(harness):
            return next(call[1] for call in harness.calls if call[0] == "subprocess" and call[1][:2] == ("gh", "workflow"))
        harness = DispatchHarness(NEW, self.root, DEV, head=OTHER_HEAD, resolved=DEV_PLAN)
        harness.dispatch(kind="development")
        self.assertEqual(argv(harness)[-2:], ("-f", "v23_run_kind=development"))
        self.fresh_root()
        harness = DispatchHarness(NEW, self.root, DEV, head=OTHER_HEAD, resolved=DEV_PLAN)
        harness.dispatch(kind="gate")
        self.assertFalse(any("v23_run_kind" in item for item in argv(harness)))
        self.assertEqual(argv(harness)[-2:], ("-f", "s10_4_shared_segment_id=none"))

    def test_development_needs_the_declared_kind_input_at_the_head(self):
        declared = caller_text()
        for label, workflow in {
                "absent": declared.replace(KIND_INPUT_TEXT, ""),
                "default development": declared.replace("default: gate", "default: development"),
                "not a choice": declared.replace("        type: choice\n        options:\n          - gate\n"
                                                 "          - development\n", "        type: string\n"),
                "extra option": declared.replace("          - development\n", "          - development\n          - other\n"),
                "commented": declared.replace("      v23_run_kind:", "      # v23_run_kind:")}.items():
            with self.subTest(label):
                self.fresh_root()
                harness = self.harness(workflow=workflow)
                self.assert_parallel_refused(harness, "does not declare that choice input")
                self.assertNotIn("resolve", [call[0] for call in harness.calls])
        self.fresh_root()
        harness = self.harness(workflow=declared.replace(KIND_INPUT_TEXT, ""))
        harness.active = []
        harness.dispatch(kind="gate")  # a gate passes nothing and needs no kind input
        self.assertTrue(harness.dispatched)

    def test_worker_is_read_from_the_dev_batch_job(self):
        other = ".github/workflows/ios-ci-worker-next.yml"
        harness = self.harness(workflow=caller_text(worker="./" + other),
                               workers={other: worker_text(), WORKER_PATH: worker_text(False)})
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)
        reads = [call[1][1] for call in harness.calls if call[0] == "git_bytes"]
        self.assertEqual(reads, [f"{OTHER_HEAD}:{other}"])
        self.fresh_root()
        harness = self.harness(workflow=caller_text(worker="./" + other),
                               workers={other: worker_text(False), WORKER_PATH: worker_text()})
        self.assert_parallel_refused(harness, f"{other} concurrency group does not include")
        harness = self.harness(workflow=caller_text(worker="Asset-Rounds/other/.github/workflows/w.yml@main"))
        self.assert_parallel_refused(harness, "calls a workflow that is not a readable local path")

    def test_gate_kinds_never_run_in_parallel(self):
        self.assert_parallel_refused(self.harness(), r"this selection is active (at any head)", kind="gate")
        (self.root / "v23-original-ledger.jsonl").unlink()
        write_ledger(self.root, [{"runID": 11, "head": DEV_HEAD, "selection": DEV, "kind": "gate"}])
        self.assert_parallel_refused(self.harness(), r"this selection is active (at any head)")
        (self.root / "v23-original-ledger.jsonl").unlink()
        write_ledger(self.root, [{"runID": 11, "head": DEV_HEAD, "selection": DEV}])
        self.assert_parallel_refused(self.harness(), r"this selection is active (at any head)")

    def test_refused_at_the_same_head(self):
        harness = self.harness(active_head=OTHER_HEAD)
        self.assert_parallel_refused(harness, "is active at this head")
        self.assertNotIn("git_bytes", [call[0] for call in harness.calls])

    def test_refused_when_the_active_head_is_unknown(self):
        (self.root / "v23-original-ledger.jsonl").unlink()
        write_ledger(self.root, [{"runID": 11, "selection": DEV, "kind": "development"}])
        self.assert_parallel_refused(self.harness(active_head=None), "is active at this head")

    def test_refused_without_per_head_groups_in_caller_and_worker(self):
        for label, (caller, worker, expected) in {
                "neither": (False, False, [NEW.WORKFLOW_PATH, WORKER_PATH]),
                "caller only": (True, False, [WORKER_PATH]),
                "worker only": (False, True, [NEW.WORKFLOW_PATH])}.items():
            with self.subTest(label):
                harness = self.harness(workflow=caller_text(caller), workers={WORKER_PATH: worker_text(worker)})
                message = self.assert_parallel_refused(harness, "needs per-head concurrency groups")
                for path in (NEW.WORKFLOW_PATH, WORKER_PATH):
                    self.assertEqual(f"{path} concurrency group does not include" in message, path in expected)

    def test_terms_inside_yaml_comments_do_not_count(self):
        commented = "v23-${{ inputs.native_selection_id }} # " + TERM
        for label, kwargs in {
                "caller": {"workflow": caller_text(group=commented)},
                "worker": {"workers": {WORKER_PATH: worker_text(group="v23-github # " + TERM)}},
                "caller job": {"workflow": caller_text(job_group="dev-x # " + TERM)},
                "worker job": {"workers": {WORKER_PATH: worker_text(job_group="verify-x #" + TERM)}},
                "per-run comment": {"workers": {WORKER_PATH: worker_text(group="v23-github # " + PER_RUN)}},
                "comment line": {"workflow": caller_text(per_head=False).replace(
                    "\nconcurrency:\n", "\nconcurrency:\n  # group: x" + TERM + "\n")}}.items():
            with self.subTest(label):
                self.assert_parallel_refused(self.harness(**kwargs), "does not include github.sha")

    def test_quoted_job_level_and_per_run_groups_are_accepted(self):
        harness = self.harness(workflow=caller_text(group='"v23-${{ inputs.native_selection_id }}' + TERM + '"',
                                                    job_group="dev-" + TERM + "  # per head"),
                               workers={WORKER_PATH: worker_text(job_group="verify-" + TERM)})
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)
        # A group naming the run is unique per run, so it separates heads too.
        self.fresh_root()
        harness = self.harness(workflow=caller_text(job_group="dev-" + PER_RUN),
                               workers={WORKER_PATH: worker_text(group="v23-github-" + PER_RUN)})
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)

    def test_committed_workflows_give_development_originals_per_head_groups(self):
        caller = read_workflow(NEW.WORKFLOW_PATH)
        self.assertTrue(NEW.run_kind_input_declared(caller))
        self.assertEqual(NEW.DEVELOPMENT_PER_HEAD_GROUP_TERM, TERM)
        routes = {DEV: {"github-shard": WORKER_PATH},
                  NEW.SHARED_SELECTION_ID: {"v23-shared-producer": SHARED_WORKER_PATH,
                                            "v23-shared-consumer": SHARED_WORKER_PATH}}
        for selection, workers in routes.items():
            with self.subTest(selection):
                jobs = NEW.route_jobs(caller, selection)
                self.assertEqual({job: worker for job, (_, worker) in jobs.items() if worker}, workers)
                harness = DispatchHarness(NEW, self.root, selection, workflow=caller,
                                          workers={path: read_workflow(path) for path in set(workers.values())})
                with mock.patch.object(NEW, "git_bytes", harness.git_bytes):
                    self.assertEqual(NEW.per_head_concurrency_problems(HEAD, caller, selection), [])
        # The caller appends the separate closed cold term; every old term remains exact once.
        cold_term = ("${{ github.event.inputs.v23_run_kind == 'development' && "
                     "github.event.inputs.native_selection_id == 'v23-cold-shared-original-v1' && "
                     "format('-development-{0}', github.sha) || '' }}")
        self.assertEqual(NEW.COLD_PER_HEAD_GROUP_TERM, cold_term)
        worker = read_workflow(WORKER_PATH)
        for text, suffix in ((caller, TERM + cold_term), (worker, TERM)):
            group = NEW.concurrency_group(text)
            self.assertIn("native_selection_id", group)
            self.assertTrue(group.endswith(suffix), group)
            self.assertEqual(text.count(TERM), 1)
        self.assertEqual(caller.count(cold_term), 1)
        self.assertNotIn(cold_term, worker)
        self.assertIn(PER_RUN, NEW.concurrency_group(read_workflow(SHARED_WORKER_PATH)))
        harness = self.harness(workflow=caller, workers={WORKER_PATH: worker})
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)

    def test_other_selections_keep_the_any_head_refusal(self):
        write_ledger(self.root, [{"runID": 12, "head": DEV_HEAD, "selection": ORDINARY_D30, "kind": "development"}])
        harness = DispatchHarness(NEW, self.root, ORDINARY_D30, head=OTHER_HEAD,
                                  resolved=dict(ORDINARY_PLAN, developmentOnly=True),
                                  active=[{"id": 12, "status": "queued", "head_sha": DEV_HEAD}],
                                  workflow=caller_text(), workers={WORKER_PATH: worker_text()})
        self.assert_parallel_refused(harness, "this selection is active (at any head)")

    def test_group_parser(self):
        self.assertEqual(NEW.concurrency_group(worker_text()), "v23-github-${{ inputs.native_selection_id }}" + TERM)
        self.assertIsNone(NEW.concurrency_group("jobs:\n  a:\n    concurrency:\n      group: x\n"))
        self.assertIsNone(NEW.concurrency_group(worker_text() + worker_text()))
        self.assertIsNone(NEW.concurrency_group("concurrency:\n  group: >-\n    x\n"))
        self.assertEqual(NEW.concurrency_group("concurrency: 'a''b' # c\n"), "a'b")
        self.assertEqual(NEW.concurrency_group("concurrency:  # c\n  # group: no\n  group: yes # no\n"), "yes")
        self.assertEqual(NEW.concurrency_groups(worker_text(job_group="j"), 4), ["j"])
        self.assertEqual(NEW.DEVELOPMENT_PER_HEAD_GROUP_TERM, TERM)
        self.assertEqual(NEW.PER_HEAD_SELECTIONS, (DEV, NEW.SHARED_SELECTION_ID))


class ParallelSharedSweepTests(unittest.TestCase):
    """Development shared sweeps: beside development runs at other heads only; gates unchanged."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def harness(self, selection, active, head=OTHER_HEAD, **kwargs):
        kwargs.setdefault("workflow", caller_text())
        kwargs.setdefault("workers", {WORKER_PATH: worker_text(), SHARED_WORKER_PATH: shared_worker_text()})
        resolved = kwargs.pop("resolved", None if selection == NEW.SHARED_SELECTION_ID else DEV_PLAN)
        return DispatchHarness(NEW, self.root, selection, head=head, resolved=resolved,
                               active=[dict(status="in_progress", **run) for run in active], **kwargs)

    def refused(self, harness, expected, kind="development"):
        with self.assertRaises(SystemExit) as caught:
            harness.dispatch(kind=kind)
        self.assertIn(expected, str(caught.exception))
        self.assertFalse(harness.dispatched)
        self.assertFalse((self.root / "v23-original-attempts").exists())

    def test_development_sweep_runs_beside_development_runs_at_other_heads(self):
        write_ledger(self.root, [{"runID": 11, "head": DEV_HEAD, "selection": DEV, "kind": "development"},
                                 {"runID": 12, "head": DEV_HEAD, "selection": NEW.SHARED_SELECTION_ID,
                                  "kind": "development"}])
        harness = self.harness(NEW.SHARED_SELECTION_ID, [{"id": 11, "head_sha": DEV_HEAD},
                                                         {"id": 12, "head_sha": DEV_HEAD}])
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)
        # The other active sweep made the per-head check read the slim worker at this head.
        self.assertIn(("git_bytes", ("show", f"{OTHER_HEAD}:{SHARED_WORKER_PATH}")), harness.calls)
        record = json.loads((self.root / str(RUN) / "dispatch.json").read_text(encoding="utf-8"))
        self.assertEqual((record["kind"], record["argv"][-1]), ("development", "v23_run_kind=development"))

    def test_development_sweep_refusals(self):
        for label, (ledger, active, expected) in {
                "gate run": ([{"runID": 11, "head": DEV_HEAD, "selection": DEV, "kind": "gate"}],
                             [{"id": 11, "head_sha": DEV_HEAD}], "are not ledgered development runs"),
                "unmarked run": ([{"runID": 11, "head": DEV_HEAD, "selection": DEV}],
                                 [{"id": 11, "head_sha": DEV_HEAD}], "are not ledgered development runs"),
                "unknown run": ([], [{"id": 99, "head_sha": DEV_HEAD}], "are not ledgered development runs"),
                "gate sweep": ([{"runID": 11, "head": DEV_HEAD, "selection": NEW.SHARED_SELECTION_ID, "kind": "gate"}],
                               [{"id": 11, "head_sha": DEV_HEAD}], "are not ledgered development runs"),
                "same head": ([{"runID": 11, "head": OTHER_HEAD, "selection": DEV, "kind": "development"}],
                              [{"id": 11, "head_sha": OTHER_HEAD}], "never overlaps another run of its head"),
                "unknown head": ([{"runID": 11, "selection": DEV, "kind": "development"}],
                                 [{"id": 11}], "never overlaps another run of its head")}.items():
            with self.subTest(label):
                (self.root / "v23-original-ledger.jsonl").unlink(missing_ok=True)
                write_ledger(self.root, ledger)
                self.refused(self.harness(NEW.SHARED_SELECTION_ID, active), expected)

    def test_parallel_sweeps_need_per_head_groups(self):
        write_ledger(self.root, [{"runID": 12, "head": DEV_HEAD, "selection": NEW.SHARED_SELECTION_ID,
                                  "kind": "development"}])
        harness = self.harness(NEW.SHARED_SELECTION_ID, [{"id": 12, "head_sha": DEV_HEAD}],
                               workflow=caller_text(per_head=False))
        self.refused(harness, "needs per-head concurrency groups")
        harness = self.harness(NEW.SHARED_SELECTION_ID, [{"id": 12, "head_sha": DEV_HEAD}],
                               workers={WORKER_PATH: worker_text(), SHARED_WORKER_PATH: shared_worker_text("v23-x")})
        self.refused(harness, f"{SHARED_WORKER_PATH} concurrency group does not include")

    def test_gate_sweep_keeps_zero_active_and_blocks_everything(self):
        write_ledger(self.root, [{"runID": 11, "head": DEV_HEAD, "selection": DEV, "kind": "development"}])
        self.refused(self.harness(NEW.SHARED_SELECTION_ID, [{"id": 11, "head_sha": DEV_HEAD}]),
                     "requires zero other active runs", kind="gate")
        (self.root / "v23-original-ledger.jsonl").unlink()
        for kind in ("gate", None):
            with self.subTest(kind=kind):
                (self.root / "v23-original-ledger.jsonl").unlink(missing_ok=True)
                entry = {"runID": 11, "head": DEV_HEAD, "selection": NEW.SHARED_SELECTION_ID}
                if kind:
                    entry["kind"] = kind
                write_ledger(self.root, [entry])
                for dispatch_kind in ("development", "gate"):
                    self.refused(self.harness(DEV, [{"id": 11, "head_sha": DEV_HEAD}]),
                                 "v23-shared-coverage-d50x is active; no other selection", kind=dispatch_kind)

    def test_beside_a_development_sweep_only_development_at_other_heads(self):
        write_ledger(self.root, [{"runID": 11, "head": DEV_HEAD, "selection": NEW.SHARED_SELECTION_ID,
                                  "kind": "development"}])
        self.refused(self.harness(DEV, [{"id": 11, "head_sha": DEV_HEAD}]),
                     "v23-shared-coverage-d50x is active; no other selection", kind="gate")
        self.refused(self.harness(DEV, [{"id": 11, "head_sha": OTHER_HEAD}]),
                     "is active at this head (or at an unknown head)")
        harness = self.harness(DEV, [{"id": 11, "head_sha": DEV_HEAD}])
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)
        # Different selections never share a group, so no per-head read was needed.
        self.assertNotIn("git_bytes", [call[0] for call in harness.calls])


class Phase1RegistrationTests(unittest.TestCase):
    """Synthetic pending intent only; no approval or native evidence is fabricated."""

    def fixture(self, purpose=None):
        gate = NEW.phase1_gates()
        sources = {path: gate.sha((REPO_ROOT / path).read_bytes()) for path in gate.SOURCES}
        selected = {"unitTestSelectors": ["SyntheticTests/Test/testOnly"], "uiTestSelectors": []}
        value = gate.make_plan(purpose=purpose or gate.CANDIDATE, head=HEAD, tree="9" * 40,
                              selection=gate.SHARED, resolved_bytes=gate.canonical(selected), sources=sources,
                              requested_at="2026-09-26T12:00:00Z")
        return gate, value, selected

    def invoke(self, root, gate, value, selected, *, records=(), attempts=(), remote=None,
               main_head=None, unknown=False, source_changed=False):
        plan_file = root / "synthetic-plan.json"
        plan_file.write_bytes(gate.canonical(value))
        attempt_dir = root / "v23-original-attempts"
        attempt_dir.mkdir(exist_ok=True)
        for name in attempts:
            (attempt_dir / name).write_text("synthetic failed or ambiguous attempt")
        calls = []

        def fake_run(*argv):
            calls.append(argv)
            if argv == ("git", "fetch", "--quiet", "origin", NEW.BRANCH, "main"):
                return ""
            values = {"HEAD": HEAD, f"origin/{NEW.BRANCH}": remote or HEAD,
                      "origin/main": main_head or gate.BASE_MAIN, f"{HEAD}^{{tree}}": "9" * 40}
            if argv[:2] == ("git", "rev-parse"):
                return values[argv[2]] + "\n"
            raise AssertionError(argv)

        def committed_bytes(*argv):
            self.assertEqual(argv[0], "show")
            path = argv[1].split(":", 1)[1]
            raw = (REPO_ROOT / path).read_bytes()
            return raw + b"changed" if source_changed and path == gate.COLLECTOR else raw

        with evidence_root(NEW, root), mock.patch.object(NEW, "run", fake_run), \
                mock.patch.object(NEW, "git_bytes", committed_bytes), \
                mock.patch.object(NEW, "ledger", return_value=list(records)), \
                mock.patch.object(NEW, "resolve_selection", return_value=(selected, gate.sha(gate.canonical(selected)))), \
                mock.patch.object(NEW, "runs_for", return_value=[{"id": 999}] if unknown else []), \
                contextlib.redirect_stdout(io.StringIO()):
            result = NEW.preregister_phase1(plan_file)
        return result, calls

    def test_registers_pending_exact_source_without_dispatch_or_attempt(self):
        gate, value, selected = self.fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            record, calls = self.invoke(root, gate, value, selected)
            self.assertFalse(record["dispatchEnabled"])
            self.assertEqual(record["functionalQualification"], gate.PENDING)
            self.assertEqual(list((root / "v23-original-attempts").iterdir()), [])
            self.assertFalse((root / "v23-original-ledger.jsonl").exists())
            self.assertEqual(calls[0], ("git", "fetch", "--quiet", "origin", NEW.BRANCH, "main"))
            self.assertTrue(all(call[0] == "git" for call in calls))
            path = root / "v23-phase1-plans" / (gate.original_stem(value) + ".json")
            original = path.read_bytes()
            with self.assertRaisesRegex(SystemExit, "already exists"):
                self.invoke(root, gate, value, selected)
            self.assertEqual(path.read_bytes(), original)

    def test_moved_refs_source_unknown_runs_and_legacy_originals_refused(self):
        gate, value, selected = self.fixture()
        variants = ({"remote": "8" * 40}, {"main_head": "8" * 40}, {"unknown": True},
                    {"source_changed": True},
                    {"records": [{"head": HEAD, "selection": gate.SHARED, "kind": "development", "runID": 1}]},
                    {"attempts": [HEAD + "-" + gate.SHARED + ".json"]})
        for variant in variants:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                with self.assertRaises(SystemExit):
                    self.invoke(root, gate, value, selected, **variant)
                self.assertFalse((root / "v23-phase1-plans").exists())

    def test_exact_main_registration_refuses_before_any_network(self):
        gate, value, _ = self.fixture(NEW.phase1_gates().EXACT_MAIN)
        with tempfile.TemporaryDirectory() as temporary:
            plan_file = Path(temporary) / "synthetic-main-plan.json"
            plan_file.write_bytes(gate.canonical(value))
            with mock.patch.object(NEW, "run") as run:
                with self.assertRaisesRegex(SystemExit, "prerequisites are not implemented"):
                    NEW.preregister_phase1(plan_file)
                run.assert_not_called()

    def test_every_new_phase1_dispatch_refuses_before_any_effect(self):
        for kind in (None, "gate", "development"):
            for plan in ("missing.json", "", "synthetic-plan.json"):
                with self.subTest(kind=kind, plan=plan), mock.patch.object(NEW, "run") as run, \
                        mock.patch.object(NEW, "write_new") as write, mock.patch.object(NEW, "append_ledger") as ledger:
                    with self.assertRaisesRegex(SystemExit, "dispatch disabled"):
                        NEW.dispatch(NEW.SHARED_SELECTION_ID, kind, phase1_plan=plan)
                    run.assert_not_called()
                    write.assert_not_called()
                    ledger.assert_not_called()


def synthetic_phase1_observations(gate, plan):
    """Test-only API responses, never root authority or real evidence."""
    return {"repository": {"id": 77, "full_name": REPO},
            "workflow": {"id": 7, "path": NEW.WORKFLOW_PATH, "state": "active"},
            "refs": {"integration": {"ref": gate.INTEGRATION_REF, "object": {"type": "commit", "sha": plan["head"]}},
                     "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": gate.BASE_MAIN}}},
            "headRuns": {"total_count": 0, "workflow_runs": []},
            "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in gate.ACTIVE_RUN_STATUSES}}


class Phase1AttemptLifecycleTests(unittest.TestCase):
    """Actual dormant caller flow; only Git/API/process boundaries are synthetic."""

    def fixture(self, base, shared=False):
        gate, directory, attempt_path, observed, artifacts, calls, downloads, commands = Phase1CollectionCallerTests.fixture(self, base, shared)
        attempt = gate.decode(attempt_path.read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
        plan = gate.parse_plan(attempt["planBytes"].encode())
        plan_path = base / "synthetic-candidate-plan.json"
        plan_path.write_bytes(gate.canonical(plan))
        shutil.rmtree(NEW.phase1_lifecycle_directory(gate, plan))
        attempt_path.unlink()
        shutil.rmtree(directory)
        NEW.LEDGER.write_bytes(b"")
        observations = synthetic_phase1_observations(gate, plan)
        state = {"runs": [], "requests": [], "effect": "success", "publish": True, "observations": observations,
                 "observed": observed, "beforeRuns": [], "requestHook": None}
        original_api, original_process = NEW.api, NEW.subprocess.run
        def api(endpoint):
            calls.append(endpoint)
            if endpoint == f"repos/{REPO}":
                return copy.deepcopy(observations["repository"])
            if endpoint == f"repos/{REPO}/actions/workflows/{NEW.WORKFLOW}":
                return copy.deepcopy(observations["workflow"])
            for key, ref in (("integration", NEW.BRANCH), ("main", "main")):
                if endpoint == f"repos/{REPO}/git/ref/heads/{ref}":
                    return copy.deepcopy(observations["refs"][key])
            for status in gate.ACTIVE_RUN_STATUSES:
                if endpoint == f"repos/{REPO}/actions/runs?status={status}&per_page={NEW.PAGE_SIZE}&page=1":
                    return copy.deepcopy(observations["activeRuns"][status])
            prefix = f"repos/{REPO}/actions/runs?head_sha={HEAD}&per_page={NEW.PAGE_SIZE}&page="
            if endpoint.startswith(prefix):
                page = int(endpoint.removeprefix(prefix))
                rows = state["runs"] if state["requests"] else state["beforeRuns"]
                return {"total_count": len(rows), "workflow_runs": copy.deepcopy(rows[(page-1)*NEW.PAGE_SIZE:page*NEW.PAGE_SIZE])}
            for row in state["runs"]:
                if row["id"] != RUN and endpoint == f"repos/{REPO}/actions/runs/{row['id']}":
                    return copy.deepcopy(row)
            return original_api(endpoint)
        def git_run(*args):
            self.assertEqual(args[0], "git")
            if args[1] in ("fetch", "diff"):
                return ""
            self.assertEqual(args[1], "rev-parse")
            if args[2].endswith("^{tree}"):
                return plan["tree"] + "\n"
            if args[2] == "origin/main":
                return observations["refs"]["main"]["object"]["sha"] + "\n"
            if args[2] == "origin/" + NEW.BRANCH:
                return observations["refs"]["integration"]["object"]["sha"] + "\n"
            self.assertEqual(args[2], "HEAD")
            return HEAD + "\n"
        def process(argv, **kwargs):
            if argv[:3] != ["gh", "workflow", "run"]:
                return original_process(argv, **kwargs)
            # The real exclusive writer completed before the only remote effect.
            consumed = gate.decode(attempt_path.read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
            registration = (base / "v23-phase1-plans" / (gate.original_stem(plan) + ".json")).read_bytes()
            gate.validate_attempt(consumed, plan, registration)
            self.assertEqual(argv, gate.dispatch_argv(plan, 7))
            self.assertEqual(kwargs["input"], gate.canonical(gate.dispatch_inputs(plan)))
            self.assertFalse(kwargs["check"])
            self.assertEqual(kwargs["cwd"], NEW.ROOT)
            state["requests"].append(copy.deepcopy(consumed))
            if state["publish"]:
                state["runs"] = copy.deepcopy(state["beforeRuns"]) + [copy.deepcopy(observed)]
            if state["requestHook"]:
                state["requestHook"]()
            if state["effect"] == "crash":
                raise KeyboardInterrupt("synthetic interruption after remote effect")
            if state["effect"] == "uncertain":
                raise OSError("synthetic response lost after remote effect")
            return subprocess.CompletedProcess(argv, 0 if state["effect"] == "success" else 1, b"synthetic CLI output", b"")
        stack = contextlib.ExitStack()
        for name, replacement in (("api", api), ("run", git_run), ("phase1_gates", lambda: gate),
                                  ("phase1_timestamp", lambda: "2026-09-26T12:01:00Z")):
            stack.enter_context(mock.patch.object(NEW, name, replacement))
        stack.enter_context(mock.patch.object(NEW.subprocess, "run", process))
        # The only authorization bypass is explicit and confined to this test.
        stack.enter_context(mock.patch.object(gate, "refuse_dispatch", return_value=None))
        self.addCleanup(stack.close)
        return gate, plan, plan_path, attempt_path, directory, state, calls

    def invoke(self, plan, path):
        return NEW.dispatch(plan["selection"], "gate", phase1_plan=path)

    def test_real_dormant_entry_and_discovery_refuse_before_all_effects(self):
        with mock.patch.object(NEW, "api") as api, mock.patch.object(NEW, "run") as run:
            for discover in (False, True):
                with self.assertRaisesRegex(ValueError, "dispatch disabled"):
                    NEW.phase1_candidate_lifecycle("missing", discover=discover)
            api.assert_not_called(); run.assert_not_called()

    def test_actual_attempt_writer_discovery_and_collector_reader_agree_for_both_routes(self):
        for shared in (False, True):
            with self.subTest(shared=shared), tempfile.TemporaryDirectory() as temporary:
                gate, plan, path, attempt, directory, state, _ = self.fixture(Path(temporary).resolve(), shared)
                record = self.invoke(plan, path)
                self.assertEqual(len(state["requests"]), 1)
                self.assertEqual(record["functionalQualification"], gate.PENDING)
                before = attempt.read_bytes()
                NEW.phase1_original_context(RUN)  # actual reader, no schema stub
                with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                    NEW.collect(RUN, False)
                self.assertEqual(json.loads((directory / "phase1-lifecycle.json").read_bytes())["history"][0]["status"],
                                 "DISCOVERED_PENDING_PROOF")
                with self.assertRaisesRegex(SystemExit, "already consumed"):
                    self.invoke(plan, path)
                self.assertEqual(attempt.read_bytes(), before)
                self.assertEqual(len(state["requests"]), 1)

    def test_zero_then_unique_discovery_is_append_only_and_never_redispatches(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, plan, path, attempt, directory, state, _ = self.fixture(Path(temporary).resolve())
            state["publish"] = False
            with self.assertRaisesRegex(SystemExit, "AWAITING_ORIGINAL"):
                self.invoke(plan, path)
            history = NEW.phase1_lifecycle_directory(gate, plan)
            first = (history / "000000.json").read_bytes()
            state["runs"] = [state["observed"]]
            record = NEW.phase1_candidate_lifecycle(path, discover=True)
            immutable_record = (directory / "dispatch.json").read_bytes()
            NEW.phase1_candidate_lifecycle(path, discover=True)
            self.assertEqual((directory / "dispatch.json").read_bytes(), immutable_record)
            self.assertEqual((history / "000000.json").read_bytes(), first)
            self.assertEqual(len(state["requests"]), 1)
            self.assertEqual(len(NEW.ledger_dispatches()), 1)
            self.assertEqual(record["runID"], RUN)
            NEW.phase1_original_context(RUN)

    def test_uncertain_or_interrupted_request_consumes_and_retains_later_run_without_attribution(self):
        for effect in ("uncertain", "nonzero", "crash"):
            with self.subTest(effect=effect), tempfile.TemporaryDirectory() as temporary:
                gate, plan, path, attempt, directory, state, _ = self.fixture(Path(temporary).resolve())
                state["effect"] = effect
                with self.assertRaises(KeyboardInterrupt if effect == "crash" else SystemExit):
                    self.invoke(plan, path)
                before = attempt.read_bytes()
                with self.assertRaisesRegex(ValueError, "ATTRIBUTION_PENDING"):
                    NEW.phase1_candidate_lifecycle(path, discover=True)
                receipt, entries = NEW.phase1_read_lifecycle(gate, plan, gate.decode(before, limit=gate.MAX_ATTEMPT_BYTES))
                self.assertEqual(entries[-1]["runID"], RUN)
                self.assertEqual(entries[-1]["status"], "ATTRIBUTION_PENDING")
                self.assertFalse(directory.exists())
                self.assertEqual(NEW.ledger_dispatches(), [])
                self.assertEqual(attempt.read_bytes(), before)
                self.assertEqual(len(state["requests"]), 1)
                with self.assertRaisesRegex(SystemExit, "already consumed"):
                    self.invoke(plan, path)

    def test_moved_refs_ambiguous_and_nonoriginal_runs_are_retained_without_claiming_attribution(self):
        for variant in ("moved", "multiple", "attempt2", "foreign", "repository", "oldtime"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                gate, plan, path, attempt, directory, state, _ = self.fixture(Path(temporary).resolve())
                state["publish"] = False
                with self.assertRaises(SystemExit): self.invoke(plan, path)
                observed = copy.deepcopy(state["observed"])
                if variant == "moved": state["observations"]["refs"]["integration"]["object"]["sha"] = "a" * 40
                if variant == "attempt2": observed["run_attempt"] = 2
                if variant == "foreign": observed["workflow_id"] = 999
                if variant == "repository": observed["repository"]["id"] = 999
                if variant == "oldtime": observed["created_at"] = "2026-09-26T11:00:00Z"
                state["runs"] = [observed]
                if variant == "multiple": state["runs"].append(dict(observed, id=RUN+1))
                with self.assertRaisesRegex(ValueError, "ATTRIBUTION_PENDING"):
                    NEW.phase1_candidate_lifecycle(path, discover=True)
                state["observations"]["refs"]["integration"]["object"]["sha"] = HEAD
                state["runs"] = [state["observed"]]
                with self.assertRaisesRegex(ValueError, "ATTRIBUTION_PENDING"):
                    NEW.phase1_candidate_lifecycle(path, discover=True)
                _, entries = NEW.phase1_read_lifecycle(gate, plan, gate.decode(attempt.read_bytes(), limit=gate.MAX_ATTEMPT_BYTES))
                self.assertTrue(any("prior attribution gap" in p for p in entries[-1]["problems"]))
                self.assertFalse(directory.exists())
                self.assertEqual(len(state["requests"]), 1)

    def test_actual_predispatch_pagination_unknown_legacy_active_and_duplicate_census_refuse(self):
        for variant in ("unknown-page2", "duplicate-page2", "legacy", "active", "workflow", "main", "input"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                gate, plan, path, attempt, directory, state, calls = self.fixture(Path(temporary).resolve())
                known = {"id": RUN-1, "head_sha": HEAD}
                if variant in ("unknown-page2", "duplicate-page2"):
                    state["beforeRuns"] = [known, dict(known, id=RUN-2 if variant == "unknown-page2" else RUN-1)]
                    NEW.LEDGER.write_bytes(gate.canonical({"runID": RUN-1, "head": HEAD, "selection": "unrelated", "kind": "development"}))
                if variant == "legacy": NEW.LEDGER.write_bytes(gate.canonical({"runID": RUN-1, "head": HEAD, "selection": plan["selection"], "kind": "development"}))
                if variant == "active": state["observations"]["activeRuns"]["queued"] = {"total_count": 1, "workflow_runs": [known]}
                if variant == "workflow": state["observations"]["workflow"]["path"] = "other.yml"
                if variant == "main": state["observations"]["refs"]["main"]["object"]["sha"] = "a"*40
                if variant == "input": plan["purpose"] = gate.EXACT_MAIN; plan["ref"] = "refs/heads/main"; path.write_bytes(gate.canonical(plan))
                with mock.patch.object(NEW, "PAGE_SIZE", 1), self.assertRaises(SystemExit): self.invoke(plan, path)
                self.assertFalse(attempt.exists())
                self.assertEqual(state["requests"], [])
                if "page2" in variant: self.assertTrue(any("head_sha=" in x and x.endswith("page=2") for x in calls))

    def test_actual_run_pagination_preserves_known_originals_and_collects_unique_new_one(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, plan, path, attempt, directory, state, calls = self.fixture(Path(temporary).resolve())
            state["beforeRuns"] = [{"id": RUN-i-1, "head_sha": HEAD} for i in range(101)]
            NEW.LEDGER.write_bytes(b"".join(gate.canonical({"runID": row["id"], "head": HEAD,
                "selection": "synthetic-unrelated", "kind": "development"}) for row in state["beforeRuns"]))
            record = self.invoke(plan, path)
            self.assertEqual(record["runID"], RUN)
            captured = gate.decode(attempt.read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
            self.assertEqual(len(captured["knownRunIDs"]), 101)
            self.assertEqual(captured["observations"]["headRuns"]["workflow_runs"], state["beforeRuns"])
            self.assertGreaterEqual(sum("head_sha=" in x and x.endswith("page=2") for x in calls), 2)
            NEW.phase1_original_context(RUN)

    def test_failed_durable_consumption_never_reaches_dispatch_and_partial_is_never_reused(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, plan, path, attempt, directory, state, _ = self.fixture(Path(temporary).resolve())
            original_fsync = gate.os.fsync
            def fail_consumed_fsync(fd):
                if attempt.exists(): raise OSError("synthetic consumed-file fsync uncertainty")
                return original_fsync(fd)
            with mock.patch.object(gate.os, "fsync", side_effect=fail_consumed_fsync):
                with self.assertRaises(OSError): self.invoke(plan, path)
            self.assertEqual(state["requests"], [])
            self.assertTrue(attempt.exists())
            before = attempt.read_bytes()
            with self.assertRaisesRegex(SystemExit, "already consumed"): self.invoke(plan, path)
            self.assertEqual(attempt.read_bytes(), before)

    def test_direct_collection_refreshes_full_census_after_late_second_original_and_retains_safe_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, plan, path, attempt, directory, state, calls = self.fixture(Path(temporary).resolve(), shared=True)
            state["beforeRuns"] = [{"id": RUN-i-1, "head_sha": HEAD} for i in range(101)]
            NEW.LEDGER.write_bytes(b"".join(gate.canonical({"runID": row["id"], "head": HEAD,
                "selection": "synthetic-unrelated", "kind": "development"}) for row in state["beforeRuns"]))
            self.invoke(plan, path)
            consumed = attempt.read_bytes()
            initial_calls = len(calls)
            state["runs"].append(dict(state["observed"], id=RUN+1))
            with self.assertRaisesRegex(SystemExit, "INCOMPLETE"): NEW.collect(RUN, False)
            proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
            self.assertEqual(proof["originalAttribution"]["status"], "ATTRIBUTION_PENDING")
            self.assertTrue(proof["originalAttribution"]["retentionOnly"])
            self.assertEqual(set(proof["artifacts"]), {"producer", "S01", "payload"})
            self.assertTrue((directory / "run-logs.zip").is_file())
            self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())
            self.assertGreaterEqual(sum("head_sha=" in x and x.endswith("page=2") for x in calls[initial_calls:]), 2)
            observed = [json.loads(p.read_bytes()) for p in sorted((directory / "phase1-collection-observations").iterdir())]
            self.assertEqual([v["phase"] for v in observed], ["begin", "end"])
            self.assertTrue(all(v["entry"]["status"] == "ATTRIBUTION_PENDING" for v in observed))
            self.assertFalse(proof["acceptance"])
            self.assertEqual(attempt.read_bytes(), consumed)
            self.assertEqual(len(state["requests"]), 1)
            with self.assertRaisesRegex(ValueError, "attributed original"): NEW.phase1_original_context(RUN)

    def test_collection_retains_attribution_gaps_for_missing_substituted_ref_or_repository_observations(self):
        for variant in ("missing", "substituted", "head", "integration", "main", "repository"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                _, plan, path, _, directory, state, _ = self.fixture(Path(temporary).resolve())
                self.invoke(plan, path)
                if variant == "missing": state["runs"] = []
                if variant == "substituted": state["runs"] = [dict(state["observed"], id=RUN+1)]
                if variant == "head": state["runs"][0]["head_sha"] = "f"*40
                if variant in ("integration", "main"): state["observations"]["refs"][variant]["object"]["sha"] = "f"*40
                if variant == "repository": state["observations"]["repository"]["id"] = 999
                with self.assertRaisesRegex(SystemExit, "INCOMPLETE"): NEW.collect(RUN, False)
                proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
                self.assertEqual(proof["originalAttribution"]["status"], "ATTRIBUTION_PENDING")
                self.assertTrue((directory / "artifacts/rui1/synthetic-only.txt").is_file())
                self.assertEqual(len(state["requests"]), 1)

    def test_end_collection_census_detects_original_appearing_during_artifact_retention(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, plan, path, _, directory, state, _ = self.fixture(Path(temporary).resolve())
            self.invoke(plan, path)
            download = NEW.api_bytes
            def late(endpoint):
                raw = download(endpoint)
                if "/artifacts/" in endpoint and len(state["runs"]) == 1:
                    state["runs"].append(dict(state["observed"], id=RUN+1))
                return raw
            with mock.patch.object(NEW, "api_bytes", side_effect=late), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect(RUN, False)
            observations = [json.loads(p.read_bytes()) for p in sorted((directory / "phase1-collection-observations").iterdir())]
            self.assertEqual([v["entry"]["status"] for v in observations], ["DISCOVERED_PENDING_PROOF", "ATTRIBUTION_PENDING"])
            self.assertEqual(json.loads((directory / "phase1-raw-proof.json").read_bytes())["originalAttribution"]["status"], "ATTRIBUTION_PENDING")
            self.assertEqual(len(state["requests"]), 1)

    def test_census_transport_partial_and_same_claim_resume_keep_prior_gap_and_originals(self):
        for fail_scope in ("begin", "end"):
            with self.subTest(fail_scope=fail_scope), tempfile.TemporaryDirectory() as temporary:
                gate, plan, path, _, directory, state, _ = self.fixture(Path(temporary).resolve())
                self.invoke(plan, path)
                real_api, seen = NEW.api, []
                def interrupted(endpoint):
                    if "head_sha=" in endpoint:
                        seen.append(endpoint)
                        if len(seen) == (1 if fail_scope == "begin" else 2):
                            raise subprocess.CalledProcessError(1, ["synthetic API transport interruption"])
                    return real_api(endpoint)
                with mock.patch.object(NEW, "api", side_effect=interrupted), self.assertRaisesRegex(SystemExit, "resume the same"):
                    NEW.collect(RUN, False)
                partial = directory / "phase1-collection-partials/000000.json"
                partial_raw, claim = partial.read_bytes(), (directory / "collector.claim.json").read_bytes()
                self.assertFalse((directory / "manifest.json").exists())
                self.assertFalse((directory / "phase1-chain-check.log").exists())
                self.assertTrue((directory / "artifacts/rui1/synthetic-only.txt").is_file())
                with self.assertRaisesRegex(SystemExit, "INCOMPLETE"): NEW.collect(RUN, True)
                self.assertEqual(partial.read_bytes(), partial_raw)
                self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
                self.assertEqual(json.loads((directory / "phase1-raw-proof.json").read_bytes())["originalAttribution"]["status"], "ATTRIBUTION_PENDING")
                self.assertEqual(len(state["requests"]), 1)
                self.assertEqual(len(list((directory / "phase1-collection-observations").iterdir())), 4)
                if fail_scope == "end": self.assertEqual(len(list((directory / "phase1-checker-observations").iterdir())), 2)

    def test_collection_second_page_transport_failure_keeps_first_page_and_independent_observations(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, plan, path, _, directory, state, _ = self.fixture(Path(temporary).resolve())
            state["beforeRuns"] = [{"id": RUN-i-1, "head_sha": HEAD} for i in range(101)]
            NEW.LEDGER.write_bytes(b"".join(json.dumps({"runID": row["id"], "head": HEAD,
                "selection": "synthetic-unrelated", "kind": "development"}).encode()+b"\n" for row in state["beforeRuns"]))
            self.invoke(plan, path)
            real_api, failed = NEW.api, []
            def second_page(endpoint):
                if "head_sha=" in endpoint and endpoint.endswith("page=2") and not failed:
                    failed.append(endpoint)
                    raise subprocess.CalledProcessError(1, ["gh", "api", endpoint])
                return real_api(endpoint)
            with mock.patch.object(NEW, "api", side_effect=second_page), self.assertRaisesRegex(SystemExit, "resume the same"):
                NEW.collect(RUN, False)
            first = json.loads(sorted((directory / "phase1-collection-observations").iterdir())[0].read_bytes())["entry"]["snapshot"]
            self.assertTrue(first["transportFailure"])
            self.assertEqual(len(first["runPages"]), 1)
            self.assertEqual(len(first["runPages"][0]["response"]["workflow_runs"]), 100)
            self.assertEqual(first["repository"]["id"], 77)
            self.assertEqual(first["refs"]["integration"]["object"]["sha"], HEAD)
            self.assertIsNone(first["headRuns"])
            self.assertIn("page=2", first["error"])
            with self.assertRaisesRegex(SystemExit, "INCOMPLETE"): NEW.collect(RUN, True)
            self.assertEqual(json.loads((directory / "phase1-raw-proof.json").read_bytes())["originalAttribution"]["status"], "ATTRIBUTION_PENDING")
            self.assertEqual(len(state["requests"]), 1)

    def test_collection_exception_still_retains_end_census_without_downloading_substituted_run(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, plan, path, _, directory, state, _ = self.fixture(Path(temporary).resolve())
            self.invoke(plan, path)
            state["observed"]["run_attempt"] = 2
            download = NEW.api_bytes
            with mock.patch.object(NEW, "api_bytes", wraps=download) as fetched, self.assertRaises(ValueError): NEW.collect(RUN, False)
            fetched.assert_not_called()
            observations = [json.loads(p.read_bytes()) for p in sorted((directory / "phase1-collection-observations").iterdir())]
            self.assertEqual([v["phase"] for v in observations], ["begin", "end-exception"])
            self.assertEqual(observations[-1]["entry"]["status"], "ATTRIBUTION_PENDING")
            self.assertFalse((directory / "manifest.json").exists())
            self.assertFalse((directory / "phase1-collector-active").exists())
            self.assertFalse((NEW.EVIDENCE / "phase1-dispatch-active").exists())
            self.assertEqual(len(state["requests"]), 1)

    def test_original_reader_rejects_attempt_input_and_discovery_history_substitution(self):
        for variant in ("input", "argv", "request", "chain", "missing", "legacy-schema", "tail", "page"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                gate, plan, path, attempt, directory, state, _ = self.fixture(Path(temporary).resolve())
                self.invoke(plan, path)
                lifecycle = NEW.phase1_lifecycle_directory(gate, plan)
                if variant in ("input", "argv", "legacy-schema"):
                    value = gate.decode(attempt.read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
                    if variant == "input": value["inputBytes"] = "{}\n"
                    if variant == "argv": value["argv"][-1] = "--rerun"
                    if variant == "legacy-schema": value["schema"] = "v23-phase1-original-attempt.v1"
                    attempt.write_bytes(gate.canonical(value))
                if variant == "request":
                    value = gate.decode((lifecycle / "request.json").read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
                    value["exitCode"] = 1
                    (lifecycle / "request.json").write_bytes(gate.canonical(value))
                if variant == "chain":
                    value = gate.decode((lifecycle / "000000.json").read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
                    value["previousSHA256"] = "A" * 64
                    (lifecycle / "000000.json").write_bytes(gate.canonical(value))
                if variant == "missing": (lifecycle / "000000.json").unlink()
                if variant == "tail":
                    NEW.phase1_candidate_lifecycle(path, discover=True)
                    (lifecycle / "000001.json").unlink()
                if variant == "page":
                    value = gate.decode((lifecycle / "000000.json").read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)
                    value["snapshot"]["runPages"][0]["response"]["workflow_runs"] = []
                    (lifecycle / "000000.json").write_bytes(gate.canonical(value))
                with self.assertRaises(ValueError): NEW.phase1_original_context(RUN)
                self.assertEqual(len(state["requests"]), 1)


class Phase1CollectionCallerTests(unittest.TestCase):
    """Synthetic root/API originals; no native, hosted or human approval fixtures."""

    def fixture(self, base, shared=False, reader=False):
        import tarfile
        gate = NEW.phase1_gates()
        selected = {"unitTestSelectors": ["SyntheticTests/Test/testOnly"], "uiTestSelectors": []}
        reader_case = None
        if reader:
            self.assertTrue(shared)
            reader_tests = load(HERE / "test_v23_retained_payload.py", "collector_real_reader_fixtures")
            ci, reader_gate, kernel = reader_tests.M.source_modules(REPO_ROOT)
            selected = ci["shared_selection"](REPO_ROOT)
        plan = gate.make_plan(purpose=gate.CANDIDATE, head=HEAD, tree="9" * 40,
            selection=gate.SHARED if shared else gate.RUI1, resolved_bytes=gate.canonical(selected),
            sources={p: gate.sha((REPO_ROOT / p).read_bytes()) for p in gate.SOURCES},
            requested_at="2026-09-26T12:00:00Z")
        registration_dir = base / "v23-phase1-plans"
        registration_path, _ = gate.register_candidate(plan, registration_dir)
        observations = synthetic_phase1_observations(gate, plan)
        attempt = gate.make_attempt(plan, registration_path.read_bytes(), collector_id="a" * 32,
            requested_at="2026-09-26T12:01:00Z", observations=observations, ledger_bytes="", attempt_names=[])
        attempts = base / "v23-original-attempts"
        attempts.mkdir()
        attempt_path = attempts / (gate.original_stem(plan) + ".json")
        attempt_path.write_bytes(gate.canonical(attempt))
        record = {"runID": RUN, "runAttempt": 1, "kind": "gate", "head": HEAD, "ref": plan["ref"],
            "selection": plan["selection"], "phase1PlanBytes": gate.canonical(plan).decode(),
            "phase1Purpose": plan["purpose"], "phase1PlanSHA256": attempt["planSHA256"],
            "phase1AttemptSHA256": gate.sha(attempt_path.read_bytes()),
            "phase1RegistrationSHA256": attempt["registrationSHA256"], "phase1RegistrationSchema": gate.REGISTRATION_SCHEMA,
            "resolvedSelectionSHA256": plan["selectionSHA256"], "requestedAtUTC": attempt["requestedAtUTC"]}
        partitions = {"partitionIDs": ["S01"]}
        if reader:
            partitions = {"partitionIDs": selected[ci["SHARED_KEY"]]["partitionIDs"]}
        if shared:
            record["sharedPartitions"] = partitions
        directory = base / str(RUN)
        directory.mkdir()
        (directory / "dispatch.json").write_bytes(gate.canonical(record))
        (base / "v23-original-ledger.jsonl").write_bytes(gate.canonical(record))
        observed = {"id": RUN, "run_attempt": 1, "workflow_id": 7, "head_sha": HEAD,
            "head_branch": NEW.BRANCH, "path": NEW.WORKFLOW_PATH, "event": "workflow_dispatch",
            "repository": {"full_name": REPO, "id": 77}, "head_repository": {"full_name": REPO, "id": 77},
            "created_at": "2026-09-26T12:01:01Z", "status": "completed", "conclusion": "success"}
        # Same closed writer/reader schema as the new caller; these are explicitly
        # synthetic protocol fixtures and do not assert a real request occurred.
        with mock.patch.object(NEW, "ATTEMPTS", attempts), mock.patch.object(NEW, "LEDGER", base / "v23-original-ledger.jsonl"), mock.patch.object(NEW, "phase1_timestamp", return_value="2026-09-26T12:01:02Z"):
            lifecycle = NEW.phase1_lifecycle_directory(gate, plan)
            lifecycle.mkdir()
            receipt = NEW.phase1_request_receipt(gate, attempt, result=subprocess.CompletedProcess(attempt["argv"], 0, b"", b""))
            gate.write_immutable(lifecycle / "request.json", gate.canonical(receipt))
            entry = NEW.phase1_record_discovery(gate, plan, attempt, {"refs": observations["refs"],
                "headRuns": {"total_count": 1, "workflow_runs": [observed]}, "directRun": observed, "error": None,
                "repository": observations["repository"], "transportFailure": False, "runPages": [{"endpoint": f"repos/{REPO}/actions/runs?head_sha={HEAD}&per_page={NEW.PAGE_SIZE}&page=1",
                              "response": {"total_count": 1, "workflow_runs": [observed]}}]})
        with mock.patch.object(NEW, "shared_partitions", return_value=partitions):
            record = NEW.phase1_dispatch_record(gate, plan, attempt, selected, entry)
        (directory / "dispatch.json").write_bytes(gate.canonical(record))
        anchors = [row for row in map(json.loads, (base / "v23-original-ledger.jsonl").read_text().splitlines()) if "event" in row]
        (base / "v23-original-ledger.jsonl").write_bytes(b"".join(gate.canonical(x) for x in anchors + [record]))
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("synthetic-only.txt", "not native evidence")
            archive.writestr("phase1-original-event.json", json.dumps({"repository": {"full_name": REPO},
                "ref": plan["ref"], "inputs": gate.dispatch_inputs(plan)}))
        zipped = buffer.getvalue()
        # The prospective collector retains this raw outer ZIP without opening
        # its inner payload. Its SHA must never be replaced by the inner SHA.
        self.stage1_inner_tar = b"synthetic inner TAR bytes; not native DATA"
        self.stage1_payload_zip = zip_bytes({
            "shared-payload.tar": self.stage1_inner_tar,
            "transport-only.txt": b"synthetic Stage1 raw original",
        })
        worker_blobs = {}
        if reader:
            reader_case = reader_tests.RetainedPayloadBehaviorTests("test_success_recomputes_real_kernel_facts_but_original_proof_stays_pending")
            for key, value in {"root": REPO_ROOT, "ci": ci, "gate": reader_gate, "kernel": kernel,
                               "sources": plan["sources"], "resolved": selected, "plan": plan,
                               "run_id": RUN}.items():
                setattr(reader_case, key, value)
            reader_case.setUp()
            self.addCleanup(reader_case.doCleanups)
            workers, labels = reader_case.worker_fixture()
            event = gate.canonical({"repository": {"full_name": REPO}, "ref": plan["ref"],
                                    "inputs": gate.dispatch_inputs(plan)})
            for label in labels:
                files = tree_bytes(workers / label)
                if label != "producer":
                    files["phase1-activity-logs/"] = b""
                files["phase1-original-event.json"] = event
                worker_blobs[label] = zip_bytes(files)
            self.stage1_payload_zip = reader_case.zip.read_bytes()
            self.stage1_inner_tar = reader_case.tar.read_bytes()
            self.stage2_reader_fixture = reader_case
        if shared:
            names = NEW.shared_artifact_names(RUN, HEAD, partitions["partitionIDs"])
            artifact_names = [names["producer"], *names["consumers"].values(), names["payload"]]
        else:
            artifact_names = [f"ios-ci-native-github-{gate.RUI1}-{RUN}-1"]
        artifacts = [{"id": index + 20, "name": name, "expired": False, "digest": "sha256:" + sha(zipped).lower(),
            "size_in_bytes": len(zipped), "workflow_run": {"id": RUN, "head_sha": HEAD, "head_branch": NEW.BRANCH,
                                                           "repository_id": 77, "head_repository_id": 77}}
            for index, name in enumerate(artifact_names)]
        payload_identifier = artifacts[-1]["id"] if shared else None
        if shared:
            artifacts[-1].update(digest="sha256:" + sha(self.stage1_payload_zip).lower(),
                # API declaration and actual outer-ZIP byte count are separate.
                size_in_bytes=len(self.stage1_payload_zip) + 17)
        artifact_blobs = {}
        if reader:
            for artifact, label in zip(artifacts[:-1], ["producer"] + partitions["partitionIDs"]):
                blob = worker_blobs[label]
                artifact_blobs[artifact["id"]] = blob
                artifact.update(digest="sha256:" + sha(blob).lower(), size_in_bytes=len(blob))
        source = io.BytesIO()
        archive_paths = list(gate.SOURCES)
        if reader:
            # The real Git archive contains the complete checkout. Source-
            # resolved selection and diagnostic worker joins read this real
            # project, every unit Swift input and the approved allowance source.
            allowance_source = REPO_ROOT / ci["SIMULATOR_DIAGNOSTIC_SOURCE_PATH"]
            self.assertEqual(sha(allowance_source.read_bytes()), ci["SIMULATOR_DIAGNOSTIC_SOURCE_SHA256"])
            discovery_inputs = [REPO_ROOT / ci["UNIT_PROJECT_PATH"], allowance_source,
                                *ci["unit_test_source_files"](REPO_ROOT)]
            for path in discovery_inputs:
                relative = path.relative_to(REPO_ROOT).as_posix()
                self.assertNotIn(relative, archive_paths)
                archive_paths.append(relative)
        with tarfile.open(fileobj=source, mode="w") as archive:
            for p in archive_paths:
                archive.add(REPO_ROOT / p, arcname=p)
        calls, downloads, commands = [], [], []
        def api(endpoint):
            calls.append(endpoint)
            if endpoint == f"repos/{REPO}":
                return copy.deepcopy(observations["repository"])
            if endpoint == f"repos/{REPO}/git/ref/heads/{NEW.BRANCH}":
                return copy.deepcopy(observations["refs"]["integration"])
            if endpoint == f"repos/{REPO}/git/ref/heads/main":
                return copy.deepcopy(observations["refs"]["main"])
            if endpoint == f"repos/{REPO}/actions/runs?head_sha={HEAD}&per_page={NEW.PAGE_SIZE}&page=1":
                return {"total_count": 1, "workflow_runs": [copy.deepcopy(observed)]}
            if endpoint == f"repos/{REPO}/actions/workflows/7":
                return {"id": 7, "path": NEW.WORKFLOW_PATH}
            # Exercise actual pagination callers, mocking only the API boundary.
            if endpoint == f"repos/{REPO}/actions/runs/{RUN}/attempts/1/jobs?per_page={NEW.PAGE_SIZE}&page=1":
                return {"total_count": 1, "jobs": [{"id": 1, "run_id": RUN, "run_attempt": 1,
                    "head_sha": HEAD, "status": "completed"}]}
            prefix = f"repos/{REPO}/actions/runs/{RUN}/artifacts?per_page={NEW.PAGE_SIZE}&page="
            if endpoint.startswith(prefix):
                page = int(endpoint.removeprefix(prefix))
                return {"total_count": len(artifacts), "artifacts": copy.deepcopy(
                    artifacts[(page - 1) * NEW.PAGE_SIZE:page * NEW.PAGE_SIZE])}
            # Discovery reads the exact direct run ID named by this synthetic
            # census. Return it so the real original/attempt guard can refuse
            # a foreign ID; keep every API route limited to this repository.
            direct = f"repos/{REPO}/actions/runs/{observed['id']}"
            self.assertIn(endpoint, (f"repos/{REPO}/actions/runs/{RUN}",
                f"repos/{REPO}/actions/runs/{RUN}/attempts/1", direct))
            return copy.deepcopy(observed)
        def download(endpoint):
            downloads.append(endpoint)
            if shared:
                self.assertNotEqual(endpoint,
                    f"repos/{REPO}/actions/artifacts/{payload_identifier}/zip",
                    "prospective payload transport must use the bounded stream")
            if reader:
                match = re.fullmatch(r"repos/" + re.escape(REPO) + r"/actions/artifacts/(\d+)/zip", endpoint)
                if match:
                    return artifact_blobs[int(match[1])]
            return zipped
        def payload_chunks(identifier):
            self.assertIs(type(identifier), int)
            self.assertEqual(identifier, payload_identifier)
            downloads.append(f"repos/{REPO}/actions/artifacts/{identifier}/zip")
            width = min(31, NEW.PHASE1_PAYLOAD_CHUNK_BYTES)
            for offset in range(0, len(self.stage1_payload_zip), width):
                yield self.stage1_payload_zip[offset:offset + width]
        def git_bytes(*args):
            if args[0] == "show":
                self.assertTrue(args[1].startswith(HEAD + ":"))
                return (REPO_ROOT / args[1].split(":", 1)[1]).read_bytes()
            self.assertEqual(args, ("archive", "--format=tar", HEAD))
            return source.getvalue()
        def checked(args, **kwargs):
            commands.append(args)
            if reader and args[:3] == [sys.executable, "-B", "-c"]:
                self.assertEqual(args[3], NEW.PHASE1_PAYLOAD_READER_BOOTSTRAP)
                self.assertEqual(Path(args[-3]), Path(kwargs["cwd"]))
                self.assertEqual(args[-2], NEW.PHASE1_RETAINED_READER_SHA256)
                self.assertEqual(args[-2], sha((REPO_ROOT / "Scripts/dev/v23-retained-payload.py").read_bytes()))
                self.assertRegex(args[-1], r"^[0-9A-F]{64}$")
                return REAL_SUBPROCESS_RUN(args, **kwargs)
            self.assertEqual(args[:4], [sys.executable, "-B", "Scripts/v23-native-ci.py", "phase1-retained-chain"])
            self.assertEqual(args[-1], str((directory / "phase1-chain-request.json").resolve()))
            self.assertTrue((Path(kwargs["cwd"]) / "Scripts/v23-native-ci.py").is_file())
            # Deliberate failing exact-source checker: transport alone cannot complete proof.
            return subprocess.CompletedProcess(args, 1, b"", b"synthetic missing raw native results\n")
        stack = contextlib.ExitStack()
        for name, replacement in (("EVIDENCE", base), ("ATTEMPTS", attempts), ("LEDGER", base / "v23-original-ledger.jsonl"),
            ("api", api), ("api_bytes", download),
            ("phase1_payload_chunks", payload_chunks),
            ("git_bytes", git_bytes), ("run", lambda *args: "9" * 40 + "\n"),
            ("resolve_selection", lambda *args: (selected, plan["selectionSHA256"])),
            ("shared_partitions", lambda *args: partitions)):
            stack.enter_context(mock.patch.object(NEW, name, replacement))
        stack.enter_context(mock.patch.object(NEW.subprocess, "run", checked))
        stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.addCleanup(stack.close)
        if reader:
            self.stage2_artifact_blobs = artifact_blobs
            self.stage2_source_tar = source
        return gate, directory, attempt_path, observed, artifacts, calls, downloads, commands

    def test_real_collection_caller_requires_origin_retains_payload_and_never_completes_transport_only(self):
        for shared in (False, True):
            with self.subTest(shared=shared), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, calls, downloads, commands = self.fixture(Path(temporary).resolve(), shared)
                with self.assertRaisesRegex(SystemExit, "raw proof INCOMPLETE"):
                    NEW.collect(RUN, False)
                proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
                self.assertEqual(proof["status"], "INCOMPLETE")
                self.assertEqual(proof["functionalQualification"], gate.PENDING)
                self.assertEqual(set(proof["dispatchInputBindings"]), {"producer", "S01"} if shared else {"rui1"})
                self.assertFalse(proof["releaseReady"])
                self.assertEqual(len(commands), 1)
                manifest = json.loads((directory / "manifest.json").read_bytes())
                self.assertNotIn("manifest.json", manifest["files"])
                self.assertIn("run-attempt-1.json", manifest["files"])
                self.assertIn("phase1-chain-check.log", manifest["files"])
                self.assertFalse((directory / "phase1-collector-active").exists())
                if shared:
                    self.assertIn(f"repos/{REPO}/actions/artifacts/{artifacts[-1]['id']}/zip", downloads)
                    self.assertTrue(proof["artifacts"]["payload"]["downloaded"])
                    self.assert_payload_transport(directory, proof,
                        self.stage1_payload_zip, "COMPLETE")
                with self.assertRaisesRegex(ValueError, "immutable"):
                    NEW.collect(RUN, True)


    def payload_attempts(self, directory, identifier):
        root = directory / "phase1-payload-transports" / str(identifier)
        if not root.exists():
            return []
        attempts = sorted(root.iterdir())
        self.assertEqual([p.name for p in attempts],
                         ["%06d" % i for i in range(len(attempts))])
        return attempts

    def collection_state(self, directory):
        final = directory / "phase1-raw-proof.json"
        if final.is_file():
            return json.loads(final.read_bytes())
        partials = sorted((directory / "phase1-collection-partials").glob("*.json"))
        self.assertTrue(partials, "an unresolved transport must retain a partial")
        return json.loads(partials[-1].read_bytes())

    def assert_stage1_pending(self, gate, directory, state):
        self.assertEqual(state["status"], "INCOMPLETE")
        self.assertEqual(state["functionalQualification"], gate.PENDING)
        self.assertFalse(state["acceptance"])
        self.assertFalse(state["releaseReady"])
        if "providerQualification" in state:
            self.assertFalse(state["providerQualification"])
        self.assertFalse((directory / "artifacts/payload").exists())
        self.assertEqual(list(directory.rglob("FACTS.json")), [])
        self.assertEqual(list(directory.rglob("shared-payload.tar")), [])

    def assert_payload_transport(self, directory, state, raw, status):
        payload = state["artifacts"]["payload"]
        self.assertEqual(payload["transportStatus"], status)
        self.assertEqual(payload["downloaded"], status == "COMPLETE")
        raw_path = directory / payload["rawZIP"]["path"]
        self.assertEqual(raw_path.name, "raw.zip")
        self.assertEqual(raw_path.read_bytes(), raw)
        self.assertEqual(payload["rawZIP"]["bytes"], len(raw))
        self.assertEqual(payload["rawZIP"]["SHA256"].upper(), sha(raw))
        receipt_path = directory / payload["transportReceipt"]["path"]
        receipt_raw = receipt_path.read_bytes()
        self.assertEqual(receipt_path, raw_path.parent / "receipt.json")
        self.assertEqual(payload["transportReceipt"]["SHA256"].upper(), sha(receipt_raw))
        receipt = json.loads(receipt_raw)
        request = json.loads((raw_path.parent / "request.json").read_bytes())
        self.assertEqual(receipt["schema"], "v23-phase1-payload-transport.v1")
        self.assertEqual(request["schema"], "v23-phase1-payload-transport-request.v1")
        claim = (directory / "collector.claim.json").read_bytes()
        listing = json.loads((directory / "artifacts.json").read_bytes())
        artifact = next(a for a in listing["artifacts"] if type(a) is dict and type(a.get("id")) is int and a["id"] == payload["id"])
        self.assertEqual(request["claimSHA256"], sha(claim))
        self.assertEqual(request["apiArtifactSHA256"], sha(NEW.phase1_gates().canonical(artifact)))
        self.assertEqual(request["artifactID"], payload["id"])
        self.assertEqual(request["apiDigest"], payload["digest"])
        self.assertEqual(request["declaredAPISizeBytes"], artifact["size_in_bytes"])
        self.assertEqual(request["runID"], RUN)
        self.assertEqual(request["runAttempt"], 1)
        self.assertEqual(raw_path, directory / "phase1-payload-transports" / str(payload["id"]) /
                         ("%06d" % request["index"]) / "raw.zip")
        self.assertEqual({k: receipt[k] for k in request if k not in ("schema", "atUTC")},
                         {k: request[k] for k in request if k not in ("schema", "atUTC")})
        self.assertEqual(receipt["status"], status)
        self.assertEqual(receipt["actualZIPBytes"], len(raw))
        self.assertEqual(receipt["actualZIPSHA256"], sha(raw))
        self.assertEqual(receipt["responseComplete"], status in ("COMPLETE", "DIGEST_MISMATCH", "DURABILITY_FAILURE"))
        self.assertEqual(receipt["durableRaw"], status != "DURABILITY_FAILURE")
        self.assertEqual(receipt["digestVerified"], status in ("COMPLETE", "DURABILITY_FAILURE"))
        self.assertEqual(receipt["rawIdentity"], NEW.phase1_payload_identity(raw_path.lstat()))
        return payload, raw_path.parent

    def test_phase1_payload_retains_outer_bytes_once_with_independent_declared_size(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, downloads, commands = self.fixture(Path(temporary).resolve(), shared=True)
            identifier, declared = artifacts[-1]["id"], artifacts[-1]["size_in_bytes"]
            stream = NEW.phase1_payload_chunks
            request_before_get = []
            def witnessed(identifier):
                attempts = self.payload_attempts(directory, identifier)
                self.assertEqual(len(attempts), 1)
                request = attempts[0] / "request.json"
                request_before_get.append(request.read_bytes())
                self.assertEqual(json.loads(request_before_get[-1])["schema"],
                                 "v23-phase1-payload-transport-request.v1")
                yield from stream(identifier)
            with mock.patch.object(NEW, "phase1_payload_chunks", witnessed), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect_phase1(RUN, False)
            state = self.collection_state(directory)
            self.assert_stage1_pending(gate, directory, state)
            payload, attempt_dir = self.assert_payload_transport(directory, state,
                self.stage1_payload_zip, "COMPLETE")
            self.assertNotEqual(declared, payload["rawZIP"]["bytes"])
            listing = json.loads((directory / "artifacts.json").read_bytes())
            self.assertEqual(listing["artifacts"][-1]["size_in_bytes"], declared)
            self.assertEqual(len(request_before_get), 1)
            self.assertEqual((attempt_dir / "request.json").read_bytes(), request_before_get[0])
            self.assertEqual(len(commands), 1)
            endpoint = f"repos/{REPO}/actions/artifacts/{identifier}/zip"
            self.assertEqual(downloads.count(endpoint), 1)
            before = tree_bytes(attempt_dir)
            with self.assertRaisesRegex(ValueError, "immutable"):
                NEW.collect_phase1(RUN, True)
            self.assertEqual(tree_bytes(attempt_dir), before)
            self.assertEqual(downloads.count(endpoint), 1)

    def test_phase1_payload_origin_and_ambiguous_metadata_refuse_before_stream(self):
        original_cases = ({"run_attempt": 2}, {"run_attempt": True}, {"id": RUN + 1},
            {"head_sha": "a" * 40}, {"head_branch": "main"},
            {"repository": {"full_name": "foreign/repository", "id": 77}},
            {"head_repository": {"full_name": REPO, "id": 999}})
        for changes in original_cases:
            with self.subTest(original=changes), tempfile.TemporaryDirectory() as temporary:
                _, directory, _, observed, artifacts, _, downloads, _ = self.fixture(Path(temporary).resolve(), shared=True)
                identifier = artifacts[-1]["id"]
                observed.update(changes)
                with mock.patch.object(NEW, "phase1_payload_chunks", side_effect=AssertionError("unauthenticated payload GET")), self.assertRaises(ValueError):
                    NEW.collect_phase1(RUN, False)
                self.assertNotIn(f"repos/{REPO}/actions/artifacts/{identifier}/zip", downloads)
                self.assertEqual(self.payload_attempts(directory, identifier), [])
                self.assertFalse((directory / "manifest.json").exists())
        metadata_cases = ("missing", "duplicate-name", "duplicate-id", "expired", "bool-id",
            "bool-run", "foreign-run", "foreign-head", "foreign-ref", "foreign-repository",
            "foreign-head-repository", "missing-digest", "upper-digest", "bool-size")
        for case in metadata_cases:
            with self.subTest(payload=case), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, downloads, _ = self.fixture(Path(temporary).resolve(), shared=True)
                payload = artifacts[-1]
                identifier = payload["id"]
                if case == "missing": artifacts.pop()
                elif case == "duplicate-name": artifacts.append(dict(payload, id=999))
                elif case == "duplicate-id": artifacts.append(dict(payload, name="foreign-artifact"))
                elif case == "expired": payload["expired"] = True
                elif case == "bool-id": payload["id"] = True
                elif case == "missing-digest": payload.pop("digest")
                elif case == "upper-digest": payload["digest"] = "sha256:" + "A" * 64
                elif case == "bool-size": payload["size_in_bytes"] = True
                else:
                    key, value = {"bool-run": ("id", True), "foreign-run": ("id", RUN + 1),
                        "foreign-head": ("head_sha", "a" * 40), "foreign-ref": ("head_branch", "main"),
                        "foreign-repository": ("repository_id", 999),
                        "foreign-head-repository": ("head_repository_id", 999)}[case]
                    payload["workflow_run"][key] = value
                with mock.patch.object(NEW, "phase1_payload_chunks", side_effect=AssertionError("refused payload GET")), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                    NEW.collect_phase1(RUN, False)
                state = self.collection_state(directory)
                self.assert_stage1_pending(gate, directory, state)
                self.assertFalse(state["artifacts"].get("payload", {}).get("downloaded", False))
                self.assertEqual(self.payload_attempts(directory, identifier), [])
                self.assertNotIn(f"repos/{REPO}/actions/artifacts/{identifier}/zip", downloads)
                self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())

    def test_phase1_wrong_outer_digest_retains_failed_raw_and_later_safe_originals(self):
        for expected_digest in ("f" * 64, sha(b"synthetic inner TAR bytes; not native DATA").lower()):
            with self.subTest(digest=expected_digest), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, downloads, _ = self.fixture(Path(temporary).resolve(), shared=True)
                payload = artifacts.pop()
                payload["digest"] = "sha256:" + expected_digest
                artifacts.insert(0, payload)
                with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                    NEW.collect_phase1(RUN, False)
                state = self.collection_state(directory)
                self.assert_stage1_pending(gate, directory, state)
                _, attempt_dir = self.assert_payload_transport(directory, state,
                    self.stage1_payload_zip, "DIGEST_MISMATCH")
                self.assertNotEqual(expected_digest, sha(self.stage1_payload_zip).lower())
                self.assertTrue((directory / "artifacts/producer/synthetic-only.txt").is_file())
                self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())
                original = tree_bytes(attempt_dir)
                claim = (directory / "collector.claim.json").read_bytes()
                with self.assertRaises((ValueError, FileExistsError)):
                    NEW.collect_phase1(RUN, False)
                self.assertEqual(tree_bytes(attempt_dir), original)
                self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
                self.assertEqual(downloads.count(f"repos/{REPO}/actions/artifacts/{payload['id']}/zip"), 1)

    def test_phase1_interrupted_payload_resume_keeps_prefix_history_and_same_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary).resolve()
            gate, directory, _, _, artifacts, _, _, commands = self.fixture(base, shared=True)
            identifier = artifacts[-1]["id"]
            prefix = self.stage1_payload_zip[:19]
            def interrupted(identifier):
                yield prefix
                raise OSError("synthetic interrupted payload transport")
            with mock.patch.object(NEW, "phase1_payload_chunks", interrupted), self.assertRaisesRegex(SystemExit, "resume the same"):
                NEW.collect_phase1(RUN, False)
            state = self.collection_state(directory)
            self.assert_stage1_pending(gate, directory, state)
            _, first = self.assert_payload_transport(directory, state, prefix, "PARTIAL")
            first_bytes = tree_bytes(first)
            partial = directory / "phase1-collection-partials/000000.json"
            partial_bytes = partial.read_bytes()
            claim = (directory / "collector.claim.json").read_bytes()
            unrelated = base / "independent-original.txt"
            unrelated.write_bytes(b"independent retained evidence")
            self.assertFalse((directory / "manifest.json").exists())
            self.assertEqual(commands, [])
            self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())
            with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect_phase1(RUN, True)
            resumed = self.collection_state(directory)
            self.assert_stage1_pending(gate, directory, resumed)
            _, second = self.assert_payload_transport(directory, resumed,
                self.stage1_payload_zip, "COMPLETE")
            self.assertEqual(second.name, "000001")
            self.assertEqual(self.payload_attempts(directory, identifier), [first, second])
            self.assertEqual(tree_bytes(first), first_bytes)
            self.assertEqual(partial.read_bytes(), partial_bytes)
            self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
            self.assertEqual(unrelated.read_bytes(), b"independent retained evidence")

    def test_phase1_completed_payload_is_reused_when_only_worker_transport_resumes(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, downloads, commands = self.fixture(Path(temporary).resolve(), shared=True)
            producer, identifier = artifacts[0]["id"], artifacts[-1]["id"]
            download = NEW.api_bytes
            def interrupted(endpoint):
                if endpoint == f"repos/{REPO}/actions/artifacts/{producer}/zip":
                    raise OSError("synthetic worker interruption")
                return download(endpoint)
            with mock.patch.object(NEW, "api_bytes", interrupted), self.assertRaisesRegex(SystemExit, "resume the same"):
                NEW.collect_phase1(RUN, False)
            state = self.collection_state(directory)
            payload, retained = self.assert_payload_transport(directory, state,
                self.stage1_payload_zip, "COMPLETE")
            retained_bytes = tree_bytes(retained)
            claim = (directory / "collector.claim.json").read_bytes()
            partial = (directory / "phase1-collection-partials/000000.json").read_bytes()
            self.assertEqual(commands, [])
            with mock.patch.object(NEW, "phase1_payload_chunks", side_effect=AssertionError("completed raw downloaded again")), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect_phase1(RUN, True)
            resumed = self.collection_state(directory)
            self.assert_stage1_pending(gate, directory, resumed)
            self.assertEqual(resumed["artifacts"]["payload"], payload)
            self.assertEqual(tree_bytes(retained), retained_bytes)
            self.assertEqual(len(self.payload_attempts(directory, identifier)), 1)
            self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
            self.assertEqual((directory / "phase1-collection-partials/000000.json").read_bytes(), partial)
            self.assertTrue((directory / "artifacts/producer/synthetic-only.txt").is_file())
            self.assertEqual(downloads.count(f"repos/{REPO}/actions/artifacts/{identifier}/zip"), 1)

    def test_phase1_resume_refuses_changed_prefix_or_ancestor_without_new_get(self):
        for hostile in ("raw-bytes", "ancestor", "request-control", "receipt-control",
                        "partial-control", "claim-control"):
            with self.subTest(hostile=hostile), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, _, _ = self.fixture(Path(temporary).resolve(), shared=True)
                identifier = artifacts[-1]["id"]
                prefix = self.stage1_payload_zip[:19]
                def interrupted(identifier):
                    yield prefix
                    raise OSError("synthetic first interruption")
                with mock.patch.object(NEW, "phase1_payload_chunks", interrupted), self.assertRaisesRegex(SystemExit, "resume the same"):
                    NEW.collect_phase1(RUN, False)
                attempt_dir = self.payload_attempts(directory, identifier)[0]
                raw_path = attempt_dir / "raw.zip"
                partial_path = directory / "phase1-collection-partials/000000.json"
                if hostile == "raw-bytes": raw_path.write_bytes(b"X" + prefix[1:])
                elif hostile == "ancestor":
                    group = attempt_dir.parent
                    saved = directory / "independent-saved-payload-ancestor"
                    group.rename(saved)
                    shutil.copytree(saved, group)
                elif hostile == "partial-control":
                    partial = json.loads(partial_path.read_bytes())
                    partial["retainedFiles"][raw_path.relative_to(directory).as_posix()] = "0" * 64
                    partial_path.write_bytes(gate.canonical(partial))
                elif hostile == "claim-control":
                    claim_value = json.loads((directory / "collector.claim.json").read_bytes())
                    claim_value["collectorID"] = "b" * 32
                    (directory / "collector.claim.json").write_bytes(gate.canonical(claim_value))
                else:
                    (attempt_dir / ("request.json" if hostile == "request-control" else "receipt.json")).write_bytes(b"{}\n")
                original = tree_bytes(attempt_dir)
                partial_original = partial_path.read_bytes()
                claim = (directory / "collector.claim.json").read_bytes()
                with mock.patch.object(NEW, "phase1_payload_chunks", side_effect=AssertionError("unsafe resume GET")), self.assertRaises((ValueError, SystemExit)):
                    NEW.collect_phase1(RUN, True)
                self.assertEqual(tree_bytes(attempt_dir), original,
                                 "inspection refusal must not repair or replace the hostile retained input")
                self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
                self.assertEqual(partial_path.read_bytes(), partial_original)
                self.assertEqual(len(self.payload_attempts(directory, identifier)), 1)
                self.assertFalse((directory / "manifest.json").exists())

    def test_phase1_payload_first_excess_byte_is_not_retained_as_complete(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, _, commands = self.fixture(Path(temporary).resolve(), shared=True)
            artifacts[-1]["size_in_bytes"] = 8
            prefix = self.stage1_payload_zip[:9]
            def excess(identifier):
                yield prefix[:4]
                yield prefix[4:8]
                yield prefix[8:]
            with mock.patch.object(NEW, "PHASE1_PAYLOAD_MAX_ZIP_BYTES", 8), \
                    mock.patch.object(NEW, "PHASE1_PAYLOAD_CHUNK_BYTES", 4), \
                    mock.patch.object(NEW, "phase1_payload_chunks", excess), \
                    self.assertRaisesRegex(SystemExit, "resume the same"):
                NEW.collect_phase1(RUN, False)
            state = self.collection_state(directory)
            self.assert_stage1_pending(gate, directory, state)
            self.assert_payload_transport(directory, state, prefix, "BOUND_EXCEEDED")
            self.assertFalse((directory / "manifest.json").exists())
            self.assertEqual(commands, [])
            self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())

    def test_phase1_payload_durable_failures_report_actual_owned_prefix(self):
        for cut in ("write-prefix", "raw-fsync"):
            with self.subTest(cut=cut), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, _, _, _, commands = self.fixture(Path(temporary).resolve(), shared=True)
                write = NEW.phase1_payload_write
                def failed_write(stream, block):
                    write(stream, block[:7])
                    raise OSError("synthetic raw write failure after actual prefix")
                def failed_fsync(stream):
                    raise OSError("synthetic raw fsync failure after actual full write")
                hook, replacement = ("phase1_payload_write", failed_write) if cut == "write-prefix" else ("phase1_payload_fsync", failed_fsync)
                with mock.patch.object(NEW, hook, replacement), self.assertRaisesRegex(SystemExit, "resume the same"):
                    NEW.collect_phase1(RUN, False)
                state = self.collection_state(directory)
                self.assert_stage1_pending(gate, directory, state)
                actual = self.stage1_payload_zip[:7] if cut == "write-prefix" else self.stage1_payload_zip
                self.assert_payload_transport(directory, state, actual,
                    "PARTIAL" if cut == "write-prefix" else "DURABILITY_FAILURE")
                self.assertFalse((directory / "manifest.json").exists())
                self.assertEqual(commands, [])
                self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())

    def test_phase1_late_payload_census_change_cannot_promote_retained_raw(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, _, _ = self.fixture(Path(temporary).resolve(), shared=True)
            stream = NEW.phase1_payload_chunks
            original_digest = artifacts[-1]["digest"]
            def late(identifier):
                yield from stream(identifier)
                artifacts[-1]["digest"] = "sha256:" + "b" * 64
            with mock.patch.object(NEW, "phase1_payload_chunks", late), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect_phase1(RUN, False)
            state = self.collection_state(directory)
            self.assert_stage1_pending(gate, directory, state)
            payload, _ = self.assert_payload_transport(directory, state,
                self.stage1_payload_zip, "COMPLETE")
            self.assertEqual(payload["digest"], original_digest)
            self.assertTrue(any("census changed" in p for p in state["problems"]))
            self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())


    def test_phase1_payload_attempt_directory_is_durable_before_effects_and_failure_stays_unresolved(self):
        for fail_sync in (False, True):
            with self.subTest(fail_sync=fail_sync), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, downloads, commands = self.fixture(Path(temporary).resolve(), shared=True)
                identifier = artifacts[-1]["id"]
                history = directory / "phase1-payload-transports" / str(identifier)
                target = history / "000000"
                endpoint = f"repos/{REPO}/actions/artifacts/{identifier}/zip"
                events = []
                syncs = []
                fsync, durable, write, chunks = gate.os.fsync, gate.durable_directory, gate.write_immutable, NEW.phase1_payload_chunks
                def directory_durable(path):
                    if path == target:
                        self.assertTrue(target.is_dir())
                        if os.name != "nt":
                            self.assertEqual(target.stat().st_mode & 0o777, 0o700)
                        self.assertEqual(list(target.iterdir()), [])
                        events.append("directory-durability-begin")
                        if os.name == "nt" and fail_sync:
                            # The existing Windows routine has no directory
                            # fsync. Inject its operation failure at the same
                            # target boundary rather than adding a platform skip.
                            raise OSError("synthetic attempt-entry durability failure")
                        result = durable(path)
                        events.append("directory-durability-complete")
                        return result
                    return durable(path)
                def directory_sync(descriptor):
                    actual = os.fstat(descriptor)
                    parent = history.lstat() if history.exists() else None
                    if parent and (actual.st_dev, actual.st_ino) == (parent.st_dev, parent.st_ino):
                        # This is the actual parent-directory fsync in the
                        # existing platform-aware durable_directory routine.
                        self.assertTrue(target.is_dir())
                        self.assertEqual(target.stat().st_mode & 0o777, 0o700)
                        self.assertEqual(list(target.iterdir()), [])
                        self.assertEqual(events, ["directory-durability-begin"])
                        syncs.append((actual.st_dev, actual.st_ino))
                        if fail_sync:
                            raise OSError("synthetic attempt-entry directory fsync failure")
                        return fsync(descriptor)
                    return fsync(descriptor)
                def request_write(path, raw):
                    if path == target / "request.json":
                        self.assertEqual(events, ["directory-durability-begin", "directory-durability-complete"])
                        self.assertTrue((target / "raw.zip").is_file())
                        events.append("request-write")
                    return write(path, raw)
                def transport(identifier):
                    self.assertEqual(events, ["directory-durability-begin", "directory-durability-complete", "request-write"])
                    self.assertTrue((target / "request.json").is_file())
                    events.append("payload-get")
                    yield from chunks(identifier)
                with mock.patch.object(NEW, "phase1_gates", return_value=gate), \
                        mock.patch.object(gate.os, "fsync", directory_sync), \
                        mock.patch.object(gate, "durable_directory", directory_durable), \
                        mock.patch.object(gate, "write_immutable", request_write), \
                        mock.patch.object(NEW, "phase1_payload_chunks", transport), \
                        self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                    NEW.collect_phase1(RUN, False)
                state = self.collection_state(directory)
                self.assert_stage1_pending(gate, directory, state)
                self.assertTrue((directory / "artifacts/producer/synthetic-only.txt").is_file())
                self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())
                self.assertEqual(len(syncs), 0 if os.name == "nt" else 1)
                if not fail_sync:
                    self.assertEqual(events, ["directory-durability-begin", "directory-durability-complete", "request-write", "payload-get"])
                    self.assert_payload_transport(directory, state, self.stage1_payload_zip, "COMPLETE")
                    self.assertEqual(downloads.count(endpoint), 1)
                else:
                    self.assertEqual(events, ["directory-durability-begin"])
                    self.assertNotIn("payload", state["artifacts"])
                    self.assertEqual(list(target.iterdir()), [])
                    self.assertNotIn(endpoint, downloads)
                    self.assertEqual(commands, [])
                    self.assertFalse((directory / "manifest.json").exists())
                    claim = (directory / "collector.claim.json").read_bytes()
                    partial = (directory / "phase1-collection-partials/000000.json").read_bytes()
                    with mock.patch.object(NEW, "phase1_payload_chunks", side_effect=AssertionError("unresolved directory retried")), \
                            self.assertRaisesRegex(SystemExit, "resume the same"):
                        NEW.collect_phase1(RUN, True)
                    resumed = self.collection_state(directory)
                    self.assert_stage1_pending(gate, directory, resumed)
                    self.assertNotIn("payload", resumed["artifacts"])
                    self.assertEqual(list(target.iterdir()), [])
                    self.assertEqual(self.payload_attempts(directory, identifier), [target])
                    self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
                    self.assertEqual((directory / "phase1-collection-partials/000000.json").read_bytes(), partial)
                    self.assertFalse((directory / "manifest.json").exists())

    def test_phase1_complete_resume_refuses_whitespace_controls_without_partial_hash_anchor(self):
        for control in ("request.json", "receipt.json"):
            with self.subTest(control=control), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, downloads, _ = self.fixture(Path(temporary).resolve(), shared=True)
                producer, identifier = artifacts[0]["id"], artifacts[-1]["id"]
                download = NEW.api_bytes
                def interrupted(endpoint):
                    if endpoint == f"repos/{REPO}/actions/artifacts/{producer}/zip":
                        raise OSError("synthetic worker interruption")
                    return download(endpoint)
                with mock.patch.object(NEW, "api_bytes", interrupted), self.assertRaisesRegex(SystemExit, "resume the same"):
                    NEW.collect_phase1(RUN, False)
                state = self.collection_state(directory)
                _, target = self.assert_payload_transport(directory, state, self.stage1_payload_zip, "COMPLETE")
                # This hostile synthetic fixture removes the secondary hash
                # anchor to isolate canonical control-byte validation. No real
                # evidence tree or retained v1 artifact is touched.
                shutil.rmtree(directory / "phase1-collection-partials")
                path = target / control
                canonical = path.read_bytes()
                altered = canonical + b"\n"
                self.assertEqual(json.loads(altered), json.loads(canonical))
                self.assertNotEqual(sha(altered), sha(canonical))
                path.write_bytes(altered)
                retained = tree_bytes(target)
                claim = (directory / "collector.claim.json").read_bytes()
                decode, refusals = gate.decode, []
                def observed_decode(raw, *args, **kwargs):
                    try:
                        return decode(raw, *args, **kwargs)
                    except gate.Refused as error:
                        if raw == altered:
                            self.assertIn("noncanonical plan bytes", str(error))
                            refusals.append(str(error))
                        raise
                with mock.patch.object(NEW, "phase1_gates", return_value=gate), \
                        mock.patch.object(gate, "decode", observed_decode), \
                        mock.patch.object(NEW, "phase1_payload_chunks", side_effect=AssertionError("noncanonical complete transport re-GET")), \
                        self.assertRaisesRegex(SystemExit, "resume the same"):
                    NEW.collect_phase1(RUN, True)
                resumed = self.collection_state(directory)
                self.assert_stage1_pending(gate, directory, resumed)
                self.assertNotIn("payload", resumed["artifacts"])
                self.assertEqual(len(refusals), 1)
                self.assertTrue(any("retained transport unresolved" in problem for problem in resumed["problems"]))
                self.assertEqual(tree_bytes(target), retained)
                self.assertEqual(path.read_bytes(), altered)
                self.assertEqual(self.payload_attempts(directory, identifier), [target])
                self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
                self.assertEqual(downloads.count(f"repos/{REPO}/actions/artifacts/{identifier}/zip"), 1)
                self.assertFalse((directory / "manifest.json").exists())

    def test_collector_joins_actual_authenticated_event_inputs_to_consumed_attempt(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, _, _ = self.fixture(Path(temporary).resolve())
            original_download = NEW.api_bytes
            def substituted(endpoint):
                raw = original_download(endpoint)
                if "/artifacts/" not in endpoint: return raw
                source, target = io.BytesIO(raw), io.BytesIO()
                with zipfile.ZipFile(source) as old, zipfile.ZipFile(target, "w") as new:
                    for name in old.namelist():
                        payload = old.read(name)
                        if name == "phase1-original-event.json":
                            event = json.loads(payload); event["inputs"]["s10_4_shared_payload_run_id"] = "999"
                            payload = json.dumps(event).encode()
                        new.writestr(zipfile.ZipInfo(name, ZIP_TIME), payload)
                altered = target.getvalue()
                return altered
            # Authenticate the substituted ZIP as the synthetic API original;
            # transport validity must not mask input mismatch against the attempt.
            altered = substituted(f"repos/{REPO}/actions/artifacts/{artifacts[0]['id']}/zip")
            artifacts[0].update(digest="sha256:" + sha(altered).lower(), size_in_bytes=len(altered))
            with mock.patch.object(NEW, "api_bytes", side_effect=substituted), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect(RUN, False)
            proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
            self.assertEqual(proof["dispatchInputBindings"], {})
            self.assertTrue(any("original dispatch input binding" in x for x in proof["problems"]))
            self.assertTrue((directory / "artifacts/rui1/phase1-original-event.json").is_file())

    def test_foreign_or_nonoriginal_api_refuses_before_downloading(self):
        for changes in ({"run_attempt": 2}, {"run_attempt": True}, {"head_sha": "a" * 40},
                        {"head_branch": "main"}, {"workflow_id": 9}, {"repository": {"full_name": "other/repo"}},
                        {"head_repository": {"full_name": "other/repo"}}, {"created_at": "2026-09-25T12:00:00Z"}):
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as temporary:
                _, directory, _, observed, _, _, downloads, _ = self.fixture(Path(temporary).resolve())
                observed.update(changes)
                with self.assertRaises(ValueError):
                    NEW.collect(RUN, False)
                self.assertEqual(downloads, [])
                self.assertFalse((directory / "manifest.json").exists())

    def test_artifact_origin_and_digest_are_mandatory_not_caller_dictionaries(self):
        for changes in ({"digest": None}, {"expired": "false"}, {"id": True},
                        {"workflow_run": {"id": RUN, "head_sha": "a" * 40, "head_branch": NEW.BRANCH}},
                        {"digest": "sha256:" + "a" * 64}):
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as temporary:
                _, directory, _, _, artifacts, _, _, _ = self.fixture(Path(temporary).resolve())
                artifacts[0].update(changes)
                # Authorized C2 failure-finalization retains a named refusal and
                # safe originals; it must not turn an invalid artifact into proof.
                with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                    NEW.collect(RUN, False)
                proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
                self.assertEqual(proof["status"], "INCOMPLETE")
                self.assertEqual(proof["artifacts"], {})
                self.assertTrue(any("artifact[0] refused" in p for p in proof["problems"]))
                self.assertFalse((directory / "artifacts/rui1").exists())
                self.assertTrue((directory / "manifest.json").is_file())

    def test_bad_first_artifact_cannot_hide_later_safe_originals_or_raw_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, _, artifacts, _, downloads, _ = self.fixture(Path(temporary).resolve(), shared=True)
            artifacts[0]["digest"] = None
            with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect(RUN, False)
            proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
            self.assertEqual(set(proof["artifacts"]), {"S01", "payload"})
            self.assertTrue(proof["artifacts"]["payload"]["downloaded"])
            self.assert_payload_transport(directory, proof,
                self.stage1_payload_zip, "COMPLETE")
            self.assertFalse((directory / "artifacts/producer").exists())
            self.assertEqual((directory / "artifacts/S01/synthetic-only.txt").read_text(), "not native evidence")
            self.assertIn(f"repos/{REPO}/actions/jobs/1/logs", downloads)
            self.assertNotIn(f"repos/{REPO}/actions/artifacts/{artifacts[0]['id']}/zip", downloads)
            self.assertIn(f"repos/{REPO}/actions/artifacts/{artifacts[2]['id']}/zip", downloads)
            self.assertTrue((directory / "phase1-job-logs/1.log").is_file())

    def test_duplicate_artifact_ids_or_names_refuse_ambiguous_members_but_keep_other_originals(self):
        for key in ("id", "name"):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                _, directory, _, _, artifacts, _, _, _ = self.fixture(Path(temporary).resolve(), shared=True)
                artifacts.append(dict(artifacts[0], **{("name" if key == "id" else "id"): "foreign" if key == "id" else 999}))
                with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                    NEW.collect(RUN, False)
                proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
                self.assertEqual(set(proof["artifacts"]), {"S01", "payload"})
                self.assertIn("duplicate artifact name or ID census", proof["problems"])

    def test_actual_artifact_pagination_retains_safe_original_after_cross_page_duplicate_and_malformed_members(self):
        with mock.patch.object(NEW, "PAGE_SIZE", 2), tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, calls, downloads, _ = self.fixture(Path(temporary).resolve(), shared=True)
            duplicate = dict(artifacts[0], name="synthetic-foreign-duplicate")
            # Duplicate producer spans pages; malformed originals remain visible.
            artifacts.insert(1, ["synthetic malformed member"])
            artifacts.extend([duplicate, None, {"id": ["invalid identity"], "name": {"invalid": "name"}}])
            with mock.patch.object(NEW, "PAGE_SIZE", 2), self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect(RUN, False)
            proof = json.loads((directory / "phase1-raw-proof.json").read_bytes())
            self.assertEqual(set(proof["artifacts"]), {"S01", "payload"})
            self.assertIn("duplicate artifact name or ID census", proof["problems"])
            self.assertEqual(sum("refused" in p for p in proof["problems"]), 5)
            self.assertFalse((directory / "artifacts/producer").exists())
            self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())
            self.assertNotIn(f"repos/{REPO}/actions/artifacts/{artifacts[0]['id']}/zip", downloads)
            self.assertIn(f"repos/{REPO}/actions/artifacts/{artifacts[3]['id']}/zip", downloads)
            self.assert_payload_transport(directory, proof, self.stage1_payload_zip, "COMPLETE")
            self.assert_stage1_pending(gate, directory, proof)
            prefix = f"repos/{REPO}/actions/runs/{RUN}/artifacts?per_page=2&page="
            self.assertEqual([c for c in calls if c.startswith(prefix)],
                             [prefix + str(p) for p in (1, 2, 3, 4, 1, 2, 3, 4)])
            self.assertEqual(json.loads((directory / "artifacts.json").read_bytes())["artifacts"], artifacts)
            self.assertEqual((directory / "artifacts.json").read_bytes(),
                             (directory / "artifacts-after-collection.json").read_bytes())

    def test_gate_artifact_pagination_refuses_incomplete_changed_or_unbounded_envelopes(self):
        gate = NEW.phase1_gates()
        cases = [([None], "API object"),
                 ([{"total_count": True, "artifacts": []}], "total_count bound"),
                 ([{"total_count": 4, "artifacts": []}], "total_count bound"),
                 ([{"total_count": 1, "artifacts": None}], "bounded page"),
                 ([{"total_count": 1, "artifacts": [None, None, None]}], "bounded page"),
                 ([{"total_count": 1, "artifacts": [None, None]}], "exceeds total_count"),
                 ([{"total_count": 1, "artifacts": []}], "incomplete empty page"),
                 ([{"total_count": 3, "artifacts": [None, None]},
                   {"total_count": 2, "artifacts": []}], "total_count changed"),
                 ([{"total_count": 3, "artifacts": [None]},
                   {"total_count": 3, "artifacts": [None]}], "bounded page count")]
        for replies, expected in cases:
            with self.subTest(expected=expected), mock.patch.object(NEW, "api", side_effect=replies), \
                    mock.patch.object(NEW, "PAGE_SIZE", 2), mock.patch.object(NEW, "SHARED_MAX_ARTIFACTS", 3):
                with self.assertRaisesRegex(ValueError, expected):
                    NEW.phase1_artifact_census(gate, "synthetic/artifacts")

    def test_interrupted_transport_keeps_safe_originals_and_resumes_same_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, _, artifacts, _, _, commands = self.fixture(Path(temporary).resolve(), shared=True)
            original_download = NEW.api_bytes
            def interrupted(endpoint):
                if endpoint.endswith("/artifacts/%d/zip" % artifacts[0]["id"]):
                    raise subprocess.CalledProcessError(1, ["synthetic transport"])
                return original_download(endpoint)
            with mock.patch.object(NEW, "api_bytes", side_effect=interrupted), self.assertRaisesRegex(SystemExit, "resume the same"):
                NEW.collect(RUN, False)
            claim = (directory / "collector.claim.json").read_bytes()
            partial_path = directory / "phase1-collection-partials/000000.json"
            partial_raw = partial_path.read_bytes()
            partial = json.loads(partial_raw)
            self.assertEqual(partial["status"], "INCOMPLETE")
            self.assertEqual(set(partial["artifacts"]), {"S01", "payload"})
            self.assertEqual(commands, [])
            self.assertTrue((directory / "artifacts/S01/synthetic-only.txt").is_file())
            self.assertFalse((directory / "manifest.json").exists())
            with self.assertRaisesRegex(SystemExit, "raw proof INCOMPLETE"):
                NEW.collect(RUN, True)
            self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
            self.assertEqual(partial_path.read_bytes(), partial_raw)
            self.assertTrue((directory / "artifacts/producer/synthetic-only.txt").is_file())
            self.assertTrue((directory / "manifest.json").is_file())
            self.assertEqual(len(commands), 1)

    def test_missing_consumed_attempt_refuses_before_api_and_claim_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, attempt, _, _, calls, _, _ = self.fixture(Path(temporary).resolve())
            raw = attempt.read_bytes()
            attempt.unlink()
            with self.assertRaises(FileNotFoundError):
                NEW.collect(RUN, False)
            self.assertEqual(calls, [])
            attempt.write_bytes(raw)
            (directory / "collector.claim.json").write_text("{}\n")
            with self.assertRaises(ValueError):
                NEW.collect(RUN, True)
            self.assertEqual(calls, [])
            with self.assertRaises(FileExistsError):
                NEW.collect(RUN, False)

    def test_nonterminal_original_retains_claim_and_resumes_without_consuming_another_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, observed, _, _, _, _ = self.fixture(Path(temporary).resolve())
            observed.update(status="in_progress", conclusion=None)
            with self.assertRaisesRegex(ValueError, "not completed"):
                NEW.collect(RUN, False)
            self.assertTrue((directory / "collector.claim.json").exists())
            self.assertFalse((directory / "run.json").exists())
            observed.update(status="completed", conclusion="success")
            with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
                NEW.collect(RUN, True)

    def test_legacy_collision_and_active_collector_refuse_without_api(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, _, calls, _, _ = self.fixture(Path(temporary).resolve())
            ledger = NEW.LEDGER.read_bytes()
            with NEW.LEDGER.open("ab") as stream:
                stream.write(gate.canonical({"runID": RUN - 1, "head": HEAD,
                    "selection": gate.RUI1, "kind": "development"}))
            with self.assertRaisesRegex(ValueError, "sole preregistered"):
                NEW.collect(RUN, False)
            self.assertEqual(calls, [])
            NEW.LEDGER.write_bytes(ledger)
            (directory / "phase1-collector-active").mkdir()
            with self.assertRaises(FileExistsError):
                NEW.collect(RUN, False)
            self.assertEqual(calls, [])
            with self.assertRaises(FileExistsError):
                NEW.collect(RUN, True)
            self.assertEqual(calls, [])

    def test_phase1_marker_or_consumed_attempt_cannot_masquerade_as_development(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, _, calls, _, _ = self.fixture(Path(temporary).resolve())
            record = json.loads((directory / "dispatch.json").read_bytes())
            record["kind"] = "development"
            for marked in (True, False):
                if not marked:
                    record = {k: v for k, v in record.items() if not k.startswith("phase1")}
                (directory / "dispatch.json").write_bytes(gate.canonical(record))
                NEW.LEDGER.write_bytes(gate.canonical(record))
                _, reason = NEW.recorded_development(RUN)
                self.assertIn("Phase1", reason)
                with self.assertRaisesRegex(SystemExit, "Phase1"):
                    NEW.cancel(RUN, "synthetic forbidden cancellation")
                self.assertEqual(calls, [])

    def test_manifest_denied_child_scan_never_returns_partial_closure_and_restored_scan_succeeds(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / "readable.txt").write_bytes(b"visible original")
            denied = root / "denied"
            denied.mkdir()
            (denied / "original.bin").write_bytes(b"required nested original")
            original_scandir = os.scandir
            calls = []
            def scandir(path):
                calls.append(Path(path))
                if Path(path) == denied:
                    raise PermissionError("synthetic denied child scandir")
                return original_scandir(path)
            with mock.patch.object(NEW.os, "scandir", side_effect=scandir):
                with self.assertRaisesRegex(PermissionError, "denied child"):
                    NEW.phase1_file_manifest(root)
            self.assertIn(root, calls)
            self.assertIn(denied, calls)
            self.assertEqual(NEW.phase1_file_manifest(root), {
                "denied/original.bin": sha(b"required nested original"),
                "readable.txt": sha(b"visible original")})

    def test_zip_gate_rejects_unsafe_types_duplicates_and_file_ancestors(self):
        import stat
        gate = NEW.phase1_gates()
        for names in (("../escape",), ("a", "a"), ("A", "a"), ("a", "a/b"), ("a\\b",), ("link",)):
            with self.subTest(names=names), tempfile.TemporaryDirectory() as temporary:
                archive = Path(temporary) / "original.zip"
                with zipfile.ZipFile(archive, "w") as bundle:
                    for name in names:
                        info = zipfile.ZipInfo(name)
                        if name == "link":
                            info.external_attr = (stat.S_IFLNK | 0o777) << 16
                        bundle.writestr(info, "synthetic")
                with self.assertRaises(ValueError):
                    NEW.phase1_zip_extract(gate, archive, Path(temporary) / "out")



class Phase1PayloadBridgeTests(unittest.TestCase):
    """Actual dormant collector + frozen real-reader child, synthetic bytes only."""
    fixture = Phase1CollectionCallerTests.fixture
    collection_state = Phase1CollectionCallerTests.collection_state
    payload_attempts = Phase1CollectionCallerTests.payload_attempts
    assert_payload_transport = Phase1CollectionCallerTests.assert_payload_transport

    def bridge_attempts(self, directory):
        root = directory / "phase1-payload-recomputations"
        if not root.exists():
            return []
        attempts = sorted(root.iterdir())
        self.assertEqual([p.name for p in attempts], ["%06d" % i for i in range(len(attempts))])
        return attempts

    def fixture_bridge(self, temporary):
        # Synthetic positive storage measurement; keep the real headroom guard
        # and reader child. Nested insufficient-space patches still override it.
        storage = mock.patch.object(NEW.os, "statvfs", return_value=SimpleNamespace(
            f_bavail=8 * 1024 ** 3, f_frsize=1))
        storage.start()
        self.addCleanup(storage.stop)
        return self.fixture(Path(temporary).resolve(), shared=True, reader=True)

    def collect_incomplete(self, resume=False):
        with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
            NEW.collect_phase1(RUN, resume)

    def bind_payload(self, artifacts):
        self.stage1_payload_zip = self.stage2_reader_fixture.zip.read_bytes()
        artifacts[-1].update(digest="sha256:" + sha(self.stage1_payload_zip).lower(),
                             size_in_bytes=len(self.stage1_payload_zip) + 17)

    def assert_pending(self, gate, directory):
        state = self.collection_state(directory)
        self.assertEqual(state["status"], "INCOMPLETE")
        self.assertEqual(state["functionalQualification"], gate.PENDING)
        for key in ("acceptance", "releaseReady"):
            self.assertIs(state[key], False)
        if "providerQualification" in state:
            self.assertIs(state["providerQualification"], False)
        return state

    def assert_no_success(self, directory):
        for path in (directory / "phase1-payload-recomputations").glob("*/receipt.json"):
            receipt = json.loads(path.read_bytes())
            self.assertNotEqual(receipt["status"], "RECOMPUTED_DURABLE_PAYLOAD_DATA")

    def assert_actual_discovery_inputs(self, gate, archived_root, request):
        root = Path(archived_root)
        project = root / "FieldEvidenceApp.xcodeproj/project.pbxproj"
        allowance = root / "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift"
        unit_root = root / "FieldEvidenceAppTests"
        namespace = [unit_root, *sorted(unit_root.rglob("*"))]
        swift_paths = sorted(p.relative_to(root).as_posix() for p in namespace
                             if p.is_file() and p.suffix == ".swift")
        identity_keys = ("dev", "ino", "mode", "uid", "gid", "nlink", "size", "mtime_ns", "ctime_ns", "flags")
        def identity(path, keys=identity_keys):
            info = path.lstat()
            return {key: getattr(info, "st_" + key, 0) for key in keys}
        files = {}
        for relative in [project.relative_to(root).as_posix(), allowance.relative_to(root).as_posix(), *swift_paths]:
            path = root / relative
            raw = path.read_bytes()
            self.assertNotIn(relative, gate.SOURCES)
            files[relative] = {"identity": identity(path), "bytes": len(raw), "SHA256": sha(raw)}
        members = sorted([{"path": p.relative_to(root).as_posix(),
                           "kind": "directory" if p.is_dir() else "file"} for p in namespace],
                         key=lambda row: row["path"])
        directories = {p.relative_to(root).as_posix(): identity(p) for p in namespace if p.is_dir()}
        ancestors = {str(p): identity(p, ("dev", "ino", "mode", "uid", "gid"))
                     for start in (unit_root, project.parent, allowance.parent) for p in (start, *start.parents)}
        stable = {"files": {name: {"bytes": row["bytes"], "SHA256": row["SHA256"]}
                            for name, row in files.items()},
                  "orderedSwiftPaths": swift_paths, "members": members}
        expected = {"schema": "v23-phase1-discovery-inputs.v1", "files": files,
                    "orderedSwiftPaths": swift_paths, "members": members, "directories": directories,
                    "ancestors": ancestors, "contentSHA256": sha(canonical(stable))}
        self.assertEqual(request["inputs"]["discovery"], expected)
        self.assertEqual(request["binding"]["discoveryInputsSHA256"], expected["contentSHA256"])
        self.assertTrue(swift_paths)
        return expected

    def test_authenticated_full_join_uses_frozen_child_and_actual_data_hashes(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, downloads, commands = self.fixture_bridge(temporary)
            real_child = NEW.phase1_payload_reader_run
            discovery_inputs = []
            def observed(root, request_path, request_sha256):
                request = json.loads(request_path.read_bytes())
                discovery_inputs.append(self.assert_actual_discovery_inputs(gate, root, request))
                result = real_child(root, request_path, request_sha256)
                self.assertEqual(self.assert_actual_discovery_inputs(gate, root, request), discovery_inputs[-1])
                return result
            with mock.patch.object(NEW, "phase1_payload_reader_run", observed):
                self.collect_incomplete()
            self.assertEqual(len(discovery_inputs), 1)
            state = self.assert_pending(gate, directory)
            self.assert_payload_transport(directory, state, self.stage1_payload_zip, "COMPLETE")
            attempts = self.bridge_attempts(directory)
            self.assertEqual(len(attempts), 1)
            bridge = attempts[0]
            request_raw = (bridge / "request.json").read_bytes()
            request = json.loads(request_raw)
            receipt = json.loads((bridge / "receipt.json").read_bytes())
            self.assertEqual(receipt["schema"], "v23-phase1-payload-recomputation.v1")
            self.assertEqual(receipt["status"], "RECOMPUTED_DURABLE_PAYLOAD_DATA")
            reader = bridge / "reader-owned"
            facts_raw = (reader / "FACTS.json").read_bytes()
            facts = json.loads(facts_raw)
            envelope_raw = (bridge / "input-envelope.json").read_bytes()
            envelope = json.loads(envelope_raw)
            listing = json.loads((directory / "artifacts.json").read_bytes())
            payload_api = next(a for a in listing["artifacts"] if a["id"] == artifacts[-1]["id"])
            self.assertEqual(set(request), {"schema", "index", "atUTC", "binding", "inputs", "envelopeSHA256", "rawPath", "workersPath", "headroom"})
            self.assertEqual(request["schema"], "v23-phase1-payload-recomputation-request.v1")
            self.assertEqual(request["index"], 0)
            raw_path = directory / state["artifacts"]["payload"]["rawZIP"]["path"]
            transport_receipt = directory / state["artifacts"]["payload"]["transportReceipt"]["path"]
            binding = request["binding"]
            self.assertEqual(binding, {"runID": RUN, "runAttempt": 1, "head": HEAD,
                "tree": self.stage2_reader_fixture.plan["tree"], "ref": self.stage2_reader_fixture.plan["ref"],
                "planSHA256": sha(gate.canonical(self.stage2_reader_fixture.plan)),
                "claimSHA256": sha((directory / "collector.claim.json").read_bytes()),
                "attemptSHA256": sha((directory / "phase1-attempt.json").read_bytes()),
                "dispatchSHA256": sha((directory / "dispatch.json").read_bytes()),
                "registrationSHA256": sha((directory / "phase1-registration.json").read_bytes()),
                "sources": {p: sha((REPO_ROOT / p).read_bytes()) for p in gate.SOURCES},
                "apiArtifactSHA256": sha(gate.canonical(payload_api)), "artifactID": payload_api["id"],
                "apiDigest": payload_api["digest"], "declaredAPISizeBytes": payload_api["size_in_bytes"],
                "rawZIP": {"path": raw_path.relative_to(directory).as_posix(), "bytes": len(raw_path.read_bytes()),
                           "SHA256": sha(raw_path.read_bytes())},
                "transportReceiptSHA256": sha(transport_receipt.read_bytes()),
                "transportRequestSHA256": sha((raw_path.parent / "request.json").read_bytes()),
                "discoveryInputsSHA256": discovery_inputs[0]["contentSHA256"]})
            self.assertEqual(request["envelopeSHA256"], sha(envelope_raw))
            self.assertEqual(request["rawPath"], str(raw_path))
            self.assertEqual(request["workersPath"], str(directory / "artifacts"))
            self.assertEqual(set(request["headroom"]), {"availableBytes", "requiredBytes", "reserveBytes"})
            self.assertGreaterEqual(request["headroom"]["availableBytes"], request["headroom"]["requiredBytes"])
            self.assertEqual(request["headroom"]["availableBytes"], 8 * 1024 ** 3)
            self.assertEqual(request["headroom"]["requiredBytes"],
                len(raw_path.read_bytes()) + 4 * 1024 ** 3 + 96 * 1024 ** 2 + 256 + 3 * 1024 ** 3)
            self.assertEqual(request["headroom"]["reserveBytes"], 3 * 1024 ** 3)
            self.assertEqual(set(request["inputs"]), {"raw", "controls", "workers", "sources", "discovery"})
            self.assertEqual(request["inputs"]["discovery"], discovery_inputs[0])
            self.assertEqual(request["inputs"]["raw"]["SHA256"], sha(raw_path.read_bytes()))
            self.assertEqual(request["inputs"]["raw"]["bytes"], len(raw_path.read_bytes()))
            self.assertEqual(request["inputs"]["raw"]["identity"], NEW.phase1_payload_identity(raw_path.lstat()))
            self.assertEqual(set(request["inputs"]["controls"]), {"dispatch.json", "collector.claim.json", "phase1-registration.json",
                "phase1-attempt.json", "run.json", "run-attempt-1.json", "workflow.json", "jobs.json", "artifacts.json",
                (raw_path.parent / "request.json").relative_to(directory).as_posix(),
                transport_receipt.relative_to(directory).as_posix()})
            for name, snapshot in request["inputs"]["controls"].items():
                raw = (directory / name).read_bytes()
                self.assertEqual(snapshot, {"bytes": len(raw), "SHA256": sha(raw),
                    "identity": NEW.phase1_payload_identity((directory / name).lstat())})
            self.assertEqual({name: snapshot["SHA256"] for name, snapshot in request["inputs"]["sources"].items()}, binding["sources"])
            self.assertEqual(request["inputs"]["workers"], NEW.phase1_bridge_tree(gate, directory / "artifacts"))
            self.assertEqual(receipt["requestSHA256"], sha(request_raw))
            self.assertEqual(receipt["ownedTree"], NEW.phase1_bridge_tree(gate, reader))
            self.assertEqual(receipt["results"]["FACTS.json"], {"bytes": len(facts_raw), "SHA256": sha(facts_raw),
                "identity": NEW.phase1_payload_identity((reader / "FACTS.json").lstat())})
            self.assertEqual(receipt["proofStatus"], "INCOMPLETE")
            self.assertEqual(receipt["functionalQualification"], gate.PENDING)
            self.assertIs(receipt["inputInvariance"], True)
            for key in ("acceptance", "providerQualification", "releaseReady", "continuationRequired"):
                self.assertIs(receipt[key], False)
            self.assertEqual(envelope, {"schema": "v23-retained-payload-input.v1", "plan": self.stage2_reader_fixture.plan,
                "runID": RUN, "runAttempt": 1, "payloadArtifact": payload_api})
            self.assertEqual((reader / "input-envelope.json").read_bytes(), envelope_raw)
            self.assertEqual((reader / "payload.zip").read_bytes(), self.stage1_payload_zip)
            self.assertEqual(facts["envelopeSHA256"], sha(envelope_raw))
            self.assertEqual(facts["outerZIP"]["sha256"], sha(self.stage1_payload_zip).lower())
            self.assertEqual(facts["archive"]["sha256"], sha((reader / "transport" / "FieldEvidencePayload.tar").read_bytes()))
            self.assertNotEqual(facts["outerZIP"]["sha256"].upper(), facts["archive"]["sha256"])
            self.assertNotEqual(facts["outerZIP"]["bytes"], payload_api["size_in_bytes"])
            metadata_raw = (reader / "extracted" / "v23-shared-payload.json").read_bytes()
            metadata = json.loads(metadata_raw)
            self.assertEqual(facts["metadataSHA256"], sha(metadata_raw))
            self.assertEqual(metadata["planSHA256"], envelope["plan"]["selectionSHA256"])
            self.assertNotEqual(metadata["planSHA256"], sha(gate.canonical(envelope["plan"])))
            self.assertEqual(set(facts["workerJoins"]["workers"]),
                {"producer", *self.stage2_reader_fixture.resolved[self.stage2_reader_fixture.ci["SHARED_KEY"]]["partitionIDs"]})
            self.assertEqual(facts["workerJoins"]["status"], "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA")
            self.assertTrue(facts["pendingProof"])
            self.assertEqual(facts["sourceSHA256"], envelope["plan"]["sources"])
            self.assertEqual(facts["products"], self.stage2_reader_fixture.products)
            children = [c for c in commands if c[:3] == [sys.executable, "-B", "-c"]]
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0][-1], sha(request_raw))
            self.assertEqual(downloads.count(f"repos/{REPO}/actions/artifacts/{artifacts[-1]['id']}/zip"), 1)
            with self.assertRaisesRegex(gate.Refused, "dispatch disabled"):
                gate.refuse_dispatch()

    def test_foreign_and_forged_payload_api_cannot_reach_reader_child(self):
        cases = ("run", "head", "ref", "attempt-original", "name", "id", "digest", "expired")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, observed, artifacts, _, _, _ = self.fixture_bridge(temporary)
                payload = artifacts[-1]
                if case == "run": payload["workflow_run"]["id"] = RUN + 1
                elif case == "head": payload["workflow_run"]["head_sha"] = "a" * 40
                elif case == "ref": payload["workflow_run"]["head_branch"] = "main"
                elif case == "attempt-original": observed["run_attempt"] = 2
                elif case == "name": payload["name"] = "caller-chosen-payload"
                elif case == "id": payload["id"] = True
                elif case == "digest": payload["digest"] = "sha256:" + "f" * 64
                elif case == "expired": payload["expired"] = True
                with mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("unapproved reader execution")):
                    if case == "attempt-original":
                        with self.assertRaises(ValueError): NEW.collect_phase1(RUN, False)
                    else:
                        self.collect_incomplete()
                self.assert_no_success(directory)
                self.assertEqual(self.bridge_attempts(directory), [])

    def test_api_extra_fields_stay_data_and_cannot_select_reader_or_envelope(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, _, artifacts, _, _, commands = self.fixture_bridge(temporary)
            payload = artifacts[-1]
            payload["reader"] = "/caller/unapproved.py"
            payload["envelope"] = {"schema": "caller-authenticated", "acceptance": True}
            self.collect_incomplete()
            bridge = self.bridge_attempts(directory)[0]
            envelope = json.loads((bridge / "input-envelope.json").read_bytes())
            self.assertEqual(envelope["schema"], "v23-retained-payload-input.v1")
            self.assertEqual(envelope["payloadArtifact"], payload)
            children = [c for c in commands if c[:3] == [sys.executable, "-B", "-c"]]
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0][3], NEW.PHASE1_PAYLOAD_READER_BOOTSTRAP)
            self.assertNotIn(payload["reader"], children[0])
            self.assertEqual(json.loads((bridge / "receipt.json").read_bytes())["status"], "RECOMPUTED_DURABLE_PAYLOAD_DATA")

    def test_complete_self_consistent_foreign_original_cannot_cross_root_authority(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, downloads, _ = self.fixture_bridge(temporary)
            template = self.stage2_reader_fixture
            reader_tests = load(HERE / "test_v23_retained_payload.py", "foreign_original_real_reader_fixtures")
            foreign = reader_tests.RetainedPayloadBehaviorTests("test_success_recomputes_real_kernel_facts_but_original_proof_stays_pending")
            plan = gate.make_plan(purpose=gate.CANDIDATE, head="a" * 40, tree="b" * 40,
                selection=gate.SHARED, resolved_bytes=gate.canonical(template.resolved),
                sources=template.sources, requested_at=template.plan["requestedAtUTC"])
            for key, value in {"root": template.root, "ci": template.ci, "gate": template.gate,
                               "kernel": template.kernel, "sources": template.sources,
                               "resolved": template.resolved, "plan": plan, "run_id": RUN + 1}.items():
                setattr(foreign, key, value)
            foreign.setUp()
            self.addCleanup(foreign.doCleanups)
            workers, labels = foreign.worker_fixture()
            names = NEW.shared_artifact_names(RUN + 1, plan["head"], labels[1:])
            foreign_names = [names["producer"], *names["consumers"].values(), names["payload"]]
            event = gate.canonical({"repository": {"full_name": REPO}, "ref": plan["ref"], "inputs": gate.dispatch_inputs(plan)})
            for artifact, label, name in zip(artifacts[:-1], labels, foreign_names[:-1]):
                files = tree_bytes(workers / label)
                files["phase1-original-event.json"] = event
                if label != "producer": files["phase1-activity-logs/"] = b""
                blob = zip_bytes(files)
                self.stage2_artifact_blobs[artifact["id"]] = blob
                artifact.update(name=name, digest="sha256:" + sha(blob).lower(), size_in_bytes=len(blob))
            self.stage1_payload_zip = foreign.zip.read_bytes()
            artifacts[-1].update(name=foreign_names[-1], digest="sha256:" + sha(self.stage1_payload_zip).lower(),
                                 size_in_bytes=len(self.stage1_payload_zip) + 17)
            for artifact in artifacts:
                artifact["workflow_run"].update(id=RUN + 1, head_sha=plan["head"])
            with mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("foreign reader execution")):
                self.collect_incomplete()
            self.assert_pending(gate, directory)
            self.assertEqual(self.bridge_attempts(directory), [])
            self.assertEqual(downloads, [f"repos/{REPO}/actions/runs/{RUN}/attempts/1/logs",
                                         f"repos/{REPO}/actions/jobs/1/logs"])

    def test_missing_final_or_extra_worker_never_produces_complete_data(self):
        for case in ("missing-final", "extra-census"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, _, commands = self.fixture_bridge(temporary)
                if case == "missing-final": artifacts.pop(-2)
                else: artifacts.append(dict(artifacts[0], id=99999, name="unexpected-worker"))
                self.collect_incomplete()
                self.assert_pending(gate, directory)
                self.assert_no_success(directory)
                self.assertEqual(len([c for c in commands if c[:3] == [sys.executable, "-B", "-c"]]), 0)

    def test_reader_headroom_accepts_exact_required_bytes(self):
        gate = NEW.phase1_gates()
        outer_zip = zip_bytes({"synthetic-only.txt": b"synthetic headroom boundary"})
        required = len(outer_zip) + 4 * 1024 ** 3 + 96 * 1024 ** 2 + 256 + 3 * 1024 ** 3
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            with mock.patch.object(NEW.os, "statvfs", return_value=SimpleNamespace(
                    f_bavail=required, f_frsize=1)) as measured_storage:
                headroom = NEW.phase1_payload_reader_headroom(gate, directory, len(outer_zip))
            measured_storage.assert_called_once_with(directory)
            self.assertEqual(headroom, {"availableBytes": required, "requiredBytes": required,
                                        "reserveBytes": 3 * 1024 ** 3})

    def test_reader_headroom_refuses_one_byte_below_required(self):
        gate = NEW.phase1_gates()
        outer_zip = zip_bytes({"synthetic-only.txt": b"synthetic headroom boundary"})
        required = len(outer_zip) + 4 * 1024 ** 3 + 96 * 1024 ** 2 + 256 + 3 * 1024 ** 3
        available = SimpleNamespace(f_bavail=required - 1, f_frsize=1)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            with mock.patch.object(NEW.os, "statvfs", return_value=available) as measured_storage:
                with self.assertRaisesRegex(gate.Refused, "bridge measured reader storage headroom"):
                    NEW.phase1_payload_reader_headroom(gate, directory, len(outer_zip))
            measured_storage.assert_called_once_with(directory)
            self.assertEqual(available.f_bavail * available.f_frsize, required - 1)

    def test_insufficient_measured_storage_refuses_before_reader_or_new_destination(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, _, _ = self.fixture_bridge(temporary)
            with mock.patch.object(NEW.os, "statvfs", return_value=SimpleNamespace(f_bavail=1, f_frsize=1)), \
                    mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("insufficient-space reader")):
                self.collect_incomplete()
            state = self.assert_pending(gate, directory)
            self.assert_payload_transport(directory, state, self.stage1_payload_zip, "COMPLETE")
            self.assertEqual(self.bridge_attempts(directory), [])
            self.assert_no_success(directory)

    def test_unapproved_archived_reader_bytes_refuse_before_any_child(self):
        import tarfile
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, _, _, _, _, commands = self.fixture_bridge(temporary)
            buffer = io.BytesIO()
            self.stage2_source_tar.seek(0)
            with tarfile.open(fileobj=self.stage2_source_tar, mode="r") as original, tarfile.open(fileobj=buffer, mode="w") as forged:
                for entry in original.getmembers():
                    if not entry.isfile():
                        forged.addfile(entry)
                        continue
                    raw = original.extractfile(entry).read()
                    if entry.name == "Scripts/dev/v23-retained-payload.py":
                        raw += b"\nraise RuntimeError('unapproved reader must never execute')\n"
                        entry.size = len(raw)
                    forged.addfile(entry, io.BytesIO(raw))
            self.stage2_source_tar.seek(0)
            self.stage2_source_tar.truncate()
            self.stage2_source_tar.write(buffer.getvalue())
            with self.assertRaisesRegex(ValueError, "archived.*source|source.*archived"):
                NEW.collect_phase1(RUN, False)
            self.assertEqual(commands, [])
            self.assert_no_success(directory)

    def test_raw_source_or_final_worker_change_during_child_cannot_seal_success(self):
        for case in ("raw", "source", "last-worker"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, _, _ = self.fixture_bridge(temporary)
                real_child = NEW.phase1_payload_reader_run
                def changed(root, request, request_sha256):
                    result = real_child(root, request, request_sha256)
                    if case == "source":
                        path = Path(root) / "Scripts/dev/v23-retained-payload.py"
                    elif case == "raw":
                        path = directory / "phase1-payload-transports" / str(artifacts[-1]["id"]) / "000000/raw.zip"
                    else:
                        labels = self.stage2_reader_fixture.resolved[self.stage2_reader_fixture.ci["SHARED_KEY"]]["partitionIDs"]
                        path = directory / "artifacts" / labels[-1] / "test-smoke.log"
                    with path.open("ab") as stream: stream.write(b"\nsynthetic interval substitution\n")
                    return result
                with mock.patch.object(NEW, "phase1_payload_reader_run", changed):
                    self.collect_incomplete()
                self.assert_pending(gate, directory)
                self.assert_no_success(directory)
                self.assertTrue(self.bridge_attempts(directory))

    def test_nonexecutable_project_and_swift_discovery_changes_during_child_stay_unresolved(self):
        for case in ("project", "allowance-source", "swift-comment", "swift-body", "swift-add", "swift-remove"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, downloads, commands = self.fixture_bridge(temporary)
                real_child = NEW.phase1_payload_reader_run
                observations = []
                def changed(root, request_path, request_sha256):
                    request = json.loads(request_path.read_bytes())
                    discovery = request["inputs"]["discovery"]
                    archived = Path(root)
                    executable_bytes = {p: (archived / p).read_bytes() for p in gate.SOURCES}
                    result = real_child(root, request_path, request_sha256)
                    self.assertEqual(result.returncode, 0)
                    facts = request_path.parent / "reader-owned/FACTS.json"
                    facts_raw = facts.read_bytes()
                    self.assertFalse((facts.parent / "FAILURE.json").exists())
                    if case in ("project", "allowance-source"):
                        relative = self.stage2_reader_fixture.ci["UNIT_PROJECT_PATH" if case == "project"
                                                                 else "SIMULATOR_DIAGNOSTIC_SOURCE_PATH"]
                        path = archived / relative
                        before = path.read_bytes()
                        changed_bytes = before + b"\n// synthetic fixed read-input interval substitution\n"
                    elif case == "swift-add":
                        relative = "FieldEvidenceAppTests/Stage2DiscoveryIntervalAdded.swift"
                        path = archived / relative
                        self.assertFalse(path.exists())
                        self.assertNotIn(relative, discovery["files"])
                        before = None
                        changed_bytes = b"// synthetic Swift census addition after reader completion\n"
                    else:
                        candidates = []
                        for relative in discovery["orderedSwiftPaths"]:
                            path = archived / relative
                            raw = path.read_bytes()
                            body = re.search(rb"\bfunc\s+test[A-Za-z0-9_]+\s*\([^)]*\)[^{]*\{", raw)
                            if body is not None:
                                candidates.append((relative, path, raw, body))
                        self.assertTrue(candidates, "actual unit Swift census must contain a test body")
                        relative, path, before, body = candidates[0]
                        if case == "swift-comment":
                            changed_bytes = before + b"\n// synthetic Swift interval substitution\n"
                        elif case == "swift-body":
                            changed_bytes = before[:body.end()] + b"\n        _ = 17\n" + before[body.end():]
                        else:
                            changed_bytes = None
                    self.assertNotIn(relative, gate.SOURCES)
                    if before is not None:
                        self.assertEqual(discovery["files"][relative]["SHA256"], sha(before))
                        self.assertEqual(discovery["files"][relative]["bytes"], len(before))
                    if changed_bytes is None:
                        path.unlink()
                        self.assertFalse(path.exists())
                    else:
                        path.write_bytes(changed_bytes)
                        self.assertNotEqual(changed_bytes, before)
                        self.assertEqual(path.read_bytes(), changed_bytes)
                    self.assertEqual({p: (archived / p).read_bytes() for p in gate.SOURCES}, executable_bytes)
                    observations.append({"path": relative, "facts": facts_raw})
                    return result
                with mock.patch.object(NEW, "phase1_payload_reader_run", changed):
                    self.collect_incomplete()
                self.assertEqual(len(observations), 1)
                bridge = self.bridge_attempts(directory)[0]
                receipt = json.loads((bridge / "receipt.json").read_bytes())
                self.assertEqual(receipt["status"], "REFUSED_PRESERVED_DATA")
                self.assertIs(receipt["inputInvariance"], False)
                self.assertIs(receipt["continuationRequired"], True)
                self.assertEqual((bridge / "reader-owned/FACTS.json").read_bytes(), observations[0]["facts"])
                self.assertFalse((directory / "manifest.json").exists())
                self.assertFalse((directory / "phase1-raw-proof.json").exists())
                state = self.assert_pending(gate, directory)
                self.assert_payload_transport(directory, state, self.stage1_payload_zip, "COMPLETE")
                self.assert_no_success(directory)
                self.assertEqual(downloads.count(f"repos/{REPO}/actions/artifacts/{artifacts[-1]['id']}/zip"), 1)
                self.assertEqual(len([c for c in commands if c[:3] == [sys.executable, "-B", "-c"]]), 1)

    def test_captured_request_sha_refuses_canonical_substitution_before_reader_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, _, _, _, commands = self.fixture_bridge(temporary)
            real_child = NEW.phase1_payload_reader_run
            captures = []
            def substituted(root, request_path, request_sha256):
                original = request_path.read_bytes()
                self.assertEqual(request_sha256, sha(original))
                request = json.loads(original)
                request["binding"]["apiArtifactSHA256"] = "F" * 64
                substituted_raw = gate.canonical(request)
                self.assertNotEqual(sha(substituted_raw), request_sha256)
                request_path.write_bytes(substituted_raw)
                captures.append(substituted_raw)
                return real_child(root, request_path, request_sha256)
            with mock.patch.object(NEW, "phase1_payload_reader_run", substituted):
                self.collect_incomplete()
            self.assertEqual(len(captures), 1)
            bridge = self.bridge_attempts(directory)[0]
            self.assertEqual((bridge / "request.json").read_bytes(), captures[0])
            self.assertFalse((bridge / "reader-owned").exists())
            self.assertEqual(list(bridge.rglob("FACTS.json")), [])
            self.assert_no_success(directory)
            self.assert_pending(gate, directory)
            self.assertFalse((directory / "manifest.json").exists())
            self.assertEqual(len([c for c in commands if c[:3] == [sys.executable, "-B", "-c"]]), 1)

    def test_hostile_zip_tar_and_distinct_inner_digest_keep_raw_originals(self):
        import tarfile
        for case in ("zip-path", "zip-symlink", "zip-crc", "tar-path", "tar-link", "tar-sparse", "inner-digest"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                gate, directory, _, _, artifacts, _, _, _ = self.fixture_bridge(temporary)
                reader = self.stage2_reader_fixture
                if case == "zip-path": reader.write_zip(members=[("../escape", b"bad")])
                elif case == "zip-symlink":
                    info = zipfile.ZipInfo("FieldEvidencePayload.tar")
                    info.create_system, info.external_attr = 3, (stat.S_IFLNK | 0o777) << 16
                    buffer = io.BytesIO()
                    with zipfile.ZipFile(buffer, "w") as bundle: bundle.writestr(info, b"target")
                    reader.zip.write_bytes(buffer.getvalue())
                elif case == "zip-crc":
                    raw = bytearray(reader.zip.read_bytes())
                    local, central = raw.index(b"PK\x03\x04"), raw.index(b"PK\x01\x02")
                    wrong = (struct.unpack_from("<I", raw, local + 14)[0] + 1) & 0xFFFFFFFF
                    struct.pack_into("<I", raw, local + 14, wrong)
                    struct.pack_into("<I", raw, central + 16, wrong)
                    reader.zip.write_bytes(raw)
                elif case.startswith("tar-"):
                    info = tarfile.TarInfo("FieldEvidencePayload/../escape" if case == "tar-path" else "FieldEvidencePayload/hostile")
                    if case == "tar-link": info.type, info.linkname = tarfile.LNKTYPE, "target"
                    if case == "tar-sparse": info.pax_headers = {"GNU.sparse.name": "hidden"}
                    reader.hostile_tar([(info, b"")])
                else: reader.write_zip(digest=("F" * 64 + " %d FieldEvidencePayload.tar\n" % reader.archive["bytes"]).encode())
                self.bind_payload(artifacts)
                raw_before = self.stage1_payload_zip
                self.collect_incomplete()
                state = self.assert_pending(gate, directory)
                self.assert_payload_transport(directory, state, raw_before, "COMPLETE")
                self.assert_no_success(directory)
                self.assertTrue(self.bridge_attempts(directory))
                self.assertFalse((Path(temporary) / "escape").exists())

    def test_lost_child_completion_and_same_claim_resume_preserve_old_index(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, artifacts, _, downloads, _ = self.fixture_bridge(temporary)
            real_child = NEW.phase1_payload_reader_run
            def lost_completion(root, request, request_sha256):
                real_child(root, request, request_sha256)
                raise subprocess.TimeoutExpired("synthetic lost child completion", 180)
            with mock.patch.object(NEW, "phase1_payload_reader_run", lost_completion):
                self.collect_incomplete()
            old = self.bridge_attempts(directory)
            self.assertEqual(len(old), 1)
            old_bytes = tree_bytes(old[0])
            claim = (directory / "collector.claim.json").read_bytes()
            self.assert_no_success(directory)
            self.collect_incomplete(resume=True)
            attempts = self.bridge_attempts(directory)
            self.assertEqual(len(attempts), 2)
            self.assertEqual(tree_bytes(attempts[0]), old_bytes)
            self.assertEqual((directory / "collector.claim.json").read_bytes(), claim)
            self.assertEqual(json.loads((attempts[1] / "receipt.json").read_bytes())["status"], "RECOMPUTED_DURABLE_PAYLOAD_DATA")
            self.assert_pending(gate, directory)
            self.assertEqual(downloads.count(f"repos/{REPO}/actions/artifacts/{artifacts[-1]['id']}/zip"), 1)

    def test_unexplained_nonzero_child_cannot_seal_original_without_failure_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, _, _, _, _, _, _ = self.fixture_bridge(temporary)
            real_child = NEW.phase1_payload_reader_run
            def failed_response(root, request, request_sha256):
                completed = real_child(root, request, request_sha256)
                self.assertEqual(completed.returncode, 0)
                return subprocess.CompletedProcess(completed.args, 1)
            with mock.patch.object(NEW, "phase1_payload_reader_run", failed_response):
                self.collect_incomplete()
            bridge = self.bridge_attempts(directory)[0]
            receipt = json.loads((bridge / "receipt.json").read_bytes())
            self.assertEqual(receipt["status"], "REFUSED_PRESERVED_DATA")
            self.assertIs(receipt["continuationRequired"], True)
            self.assertTrue((bridge / "reader-owned/FACTS.json").is_file())
            self.assertFalse((bridge / "reader-owned/FAILURE.json").exists())
            self.assertFalse((directory / "manifest.json").exists())
            self.assertFalse((directory / "phase1-raw-proof.json").exists())
            self.assert_pending(gate, directory)

    def test_preexisting_or_linked_history_refuses_without_blind_repair(self):
        for case in ("unresolved-index", "symlink-root", "hardlinked-control"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temporary:
                _, directory, _, _, _, _, _, _ = self.fixture_bridge(temporary)
                owner = Path(temporary) / "owner-content"
                owner.mkdir()
                sentinel = owner / "preserve.json"
                sentinel.write_bytes(b"owner bytes must remain exact\n")
                root = directory / "phase1-payload-recomputations"
                if case == "symlink-root":
                    root.symlink_to(owner, target_is_directory=True)
                else:
                    root.mkdir(mode=0o700)
                    attempt = root / "000000"
                    attempt.mkdir(mode=0o700)
                    if case == "hardlinked-control": os.link(sentinel, attempt / "request.json")
                    else: (attempt / "owner-partial").write_bytes(b"preserve partial\n")
                before = tree_bytes(owner)
                with mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("unresolved history executed")):
                    with self.assertRaises((SystemExit, ValueError, OSError)):
                        NEW.collect_phase1(RUN, False)
                self.assertEqual(tree_bytes(owner), before)
                self.assertFalse((root / "000001").exists())
                self.assert_no_success(directory)

    def test_bridge_request_fsync_failure_precedes_child_and_stays_unresolved(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, _, artifacts, _, _, _ = self.fixture_bridge(temporary)
            actual_fsync = os.fsync
            failed = []
            def failure(descriptor):
                opened = os.fstat(descriptor)
                for path in (directory / "phase1-payload-recomputations").glob("*/request.json"):
                    named = path.lstat()
                    if (opened.st_dev, opened.st_ino) == (named.st_dev, named.st_ino) and not failed:
                        failed.append(path)
                        raise OSError("synthetic bridge request fsync failure")
                return actual_fsync(descriptor)
            with mock.patch.object(NEW.os, "fsync", failure), \
                    mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("non-durable bridge child")):
                with self.assertRaises((SystemExit, ValueError, OSError)):
                    NEW.collect_phase1(RUN, False)
            self.assertEqual(len(failed), 1)
            root = directory / "phase1-payload-recomputations"
            before = tree_bytes(root)
            self.assertEqual(list(root.rglob("FACTS.json")), [])
            self.assertFalse((directory / "manifest.json").exists())
            self.assert_no_success(directory)
            with mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("blindly repaired bridge child")):
                with self.assertRaises((SystemExit, ValueError, OSError)):
                    NEW.collect_phase1(RUN, True)
            self.assertEqual(tree_bytes(root), before)
            self.assertFalse((root / "000001").exists())
            self.assertEqual((directory / "phase1-payload-transports" / str(artifacts[-1]["id"]) /
                              "000000/raw.zip").read_bytes(), self.stage1_payload_zip)


    def test_final_receipt_fsync_failure_has_no_sealed_original_or_blind_resume(self):
        with tempfile.TemporaryDirectory() as temporary:
            _, directory, _, _, _, _, _, _ = self.fixture_bridge(temporary)
            actual_fsync, failed = os.fsync, []
            def failure(descriptor):
                opened = os.fstat(descriptor)
                for path in (directory / "phase1-payload-recomputations").glob("*/receipt.json"):
                    named = path.lstat()
                    if (opened.st_dev, opened.st_ino) == (named.st_dev, named.st_ino) and not failed:
                        failed.append(path)
                        raise OSError("synthetic final bridge receipt fsync failure")
                return actual_fsync(descriptor)
            with mock.patch.object(NEW.os, "fsync", failure):
                with self.assertRaises((SystemExit, ValueError, OSError)):
                    NEW.collect_phase1(RUN, False)
            self.assertEqual(len(failed), 1)
            self.assertFalse((directory / "manifest.json").exists())
            self.assertFalse((directory / "phase1-raw-proof.json").exists())
            root = directory / "phase1-payload-recomputations"
            before = tree_bytes(root)
            self.assertTrue((root / "000000/reader-owned/FACTS.json").is_file())
            # Immutable success-looking bytes whose fsync failed are retained
            # for inspection; absence of a completed original blocks reuse.
            with mock.patch.object(NEW, "phase1_payload_reader_run", side_effect=AssertionError("unsealed receipt reused")):
                with self.assertRaises((SystemExit, ValueError, OSError)):
                    NEW.collect_phase1(RUN, True)
            self.assertEqual(tree_bytes(root), before)
            self.assertFalse((root / "000001").exists())


class Phase1ReviewRegistrationTests(unittest.TestCase):
    """Explicit synthetic protocol mode only; no real review or approval records."""

    def fixture(self, base, owner=False):
        gate, directory, attempt_path, observed, artifacts, calls, downloads, commands = Phase1CollectionCallerTests.fixture(self, base)
        with self.assertRaisesRegex(SystemExit, "raw proof INCOMPLETE"):
            NEW.collect(RUN, False)
        (base / ".phase1-test-only").write_bytes(b"SYNTHETIC PROTOCOL FIXTURES ONLY\n")
        plan = gate.parse_plan(gate.decode(attempt_path.read_bytes(), limit=gate.MAX_ATTEMPT_BYTES)["planBytes"].encode())
        message = base / "test-only-message.txt"
        context = base / "test-only-context.txt"
        message.write_bytes("SYNTHETIC TEST ONLY: approve fixture — no human approval.\r\n".encode())
        context.write_bytes(b"SYNTHETIC TEST ONLY conversation; these are invented protocol identities.\n")
        request = {"schema": gate.REVIEW_REQUEST_SCHEMA, "testOnly": True,
            "subject": "rui1-cold-original", "reportedDisposition": "approve", "head": plan["head"], "tree": plan["tree"],
            "originals": [{"runID": RUN, "manifestSHA256": gate.sha((directory / "manifest.json").read_bytes())}],
            "gallery": None, "messageSHA256": gate.sha(message.read_bytes()), "contextSHA256": gate.sha(context.read_bytes()),
            "messageReference": "test-only:actual-message-reference", "conversationReference": "test-only:task",
            "messageTimestampUTC": "2026-09-26T12:02:00Z", "speakerReference": "test-only:reviewer-task",
            "reviewer": {"model": "test-only:model", "effort": "test-only:effort", "authorReference": "test-only:author-task",
                "independenceReference": "test-only:retained-separate-task-reference"}}
        if owner:
            request.update(subject="owner-critical-states", reviewer=None, speakerReference="test-only:owner")
            artifact = directory / "artifacts/rui1"
            cat_raw = (REPO_ROOT / gate.CATALOGUE).read_bytes()
            catalogue = json.loads(cat_raw)
            rows, attachments = [], {}
            for state in catalogue["states"]:
                row = {"stateID": state["id"], "method": state["method"], "order": state["order"]}
                for key, suffix in (("image", "png"), ("audit", "json")):
                    name = "test-only-gallery/" + state["id"] + "." + suffix
                    path = artifact / name; path.parent.mkdir(exist_ok=True)
                    path.write_bytes(("SYNTHETIC TEST ONLY " + name).encode())
                    row[key], row[key + "SHA256"] = name, gate.sha(path.read_bytes())
                    attachments[name] = gate.sha(path.read_bytes())
                rows.append(row)
            proof = {"schema": "v23-rui1-review.v1", "head": HEAD, "runID": str(RUN), "runAttempt": "1",
                "selectionSHA256": plan["selectionSHA256"], "catalogueSHA256": gate.sha(cat_raw),
                "humanReviewCompleted": False, "states": rows}
            proof_raw = gate.canonical(proof)
            (artifact / "rui1-review.json").write_bytes(proof_raw)
            ui = load(REPO_ROOT / "Scripts/v23-ui-evidence.py", "c4_synthetic_ui_source")
            presentation = ui.review_page(REPO_ROOT, artifact, proof)
            (artifact / "rui1-review.html").write_bytes(presentation)
            # This fixture is deliberately NOT a valid native result. Only the
            # subprocess boundary below supplies synthetic checker success.
            def checker(argv, **kwargs):
                self.assertEqual(argv[:4], [sys.executable, "-B", "Scripts/v23-ui-evidence.py", "collect"])
                self.assertEqual(argv[-4:], ["--expected-head", HEAD, "--expected-run", str(RUN)])
                self.assertEqual(argv[argv.index("--artifact") + 1], str(artifact.resolve()))
                source = Path(kwargs["cwd"])
                self.assertEqual(gate.sha((source / "Scripts/v23-ui-evidence.py").read_bytes()), plan["sources"]["Scripts/v23-ui-evidence.py"])
                commands.append(argv)
                return subprocess.CompletedProcess(argv, 0, proof_raw, b"")
            patch = mock.patch.object(NEW.subprocess, "run", checker); patch.start(); self.addCleanup(patch.stop)
            self.reseal(gate, directory)
            request["originals"][0]["manifestSHA256"] = gate.sha((directory / "manifest.json").read_bytes())
            request["gallery"] = {"catalogueSHA256": gate.sha(cat_raw), "proofSHA256": gate.sha(proof_raw),
                "presentationSHA256": gate.sha(presentation), "checklistSHA256": gate.sha(presentation),
                "attachmentsSHA256": gate.sha(gate.canonical(attachments))}
        request_path = base / "test-only-review-request.json"
        request_path.write_bytes(gate.canonical(request))
        patch = mock.patch.object(NEW, "phase1_timestamp", return_value="2026-09-26T12:05:00Z")
        patch.start(); self.addCleanup(patch.stop)
        return gate, directory, request, request_path, message, context, calls, commands

    def reseal(self, gate, directory):
        """Build modified synthetic fixtures only; never called on real evidence."""
        path = directory / "manifest.json"
        manifest = gate.decode(path.read_bytes(), limit=32 * 1024 * 1024)
        files = NEW.phase1_file_manifest(directory); files.pop("manifest.json")
        manifest["files"] = files
        manifest["rawProofSHA256"] = gate.sha((directory / "phase1-raw-proof.json").read_bytes())
        path.write_bytes(gate.canonical(manifest))

    def invoke(self, request, message, context):
        return NEW.register_phase1_review(request, message, context, test_only=True)

    def test_actual_collector_to_registration_to_reader_preserves_pending_and_verbatim(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, request, path, message, context, calls, _ = self.fixture(Path(temporary).resolve())
            before = NEW.phase1_file_manifest(directory)
            call_count = len(calls)
            result = self.invoke(path, message, context)
            self.assertEqual(len(calls), call_count)  # local capture never authenticates current remote authority
            self.assertEqual(result["functionalQualification"], gate.PENDING)
            self.assertEqual(result["retainedOriginals"][0]["originals"][0]["rawProofStatus"], "INCOMPLETE")
            self.assertFalse(result["acceptance"])
            self.assertEqual(NEW.phase1_file_manifest(directory), before)
            records = NEW.phase1_read_reviews(gate, HEAD, test_only=True)
            self.assertEqual(records[0]["messageUTF8"].encode(), message.read_bytes())
            self.assertEqual(records[0]["contextUTF8"].encode(), context.read_bytes())
            self.assertEqual(NEW.assess_phase1_reviews(HEAD, test_only=True), result)
            with self.assertRaisesRegex(ValueError, "duplicate review"):
                self.invoke(path, message, context)
            self.assertEqual(len(NEW.phase1_read_reviews(gate, HEAD, test_only=True)), 1)

    def test_owner_gallery_uses_actual_frozen_checker_caller_and_exact_bundle(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, request, path, message, context, _, commands = self.fixture(Path(temporary).resolve(), owner=True)
            result = self.invoke(path, message, context)
            self.assertEqual(len(result["subjects"]["owner-critical-states"]), 1)
            self.assertEqual(result["functionalQualification"], gate.PENDING)
            records = NEW.phase1_read_reviews(gate, HEAD, test_only=True)
            self.assertEqual(records[0]["bindings"]["gallery"], request["gallery"])
            self.assertEqual(len([c for c in commands if c[2] == "Scripts/v23-ui-evidence.py"]), 3)
            # Complete original closure rejects even a single replaced image.
            image = next((directory / "artifacts/rui1/test-only-gallery").glob("*.png"))
            image.write_bytes(b"substituted synthetic image")
            with self.assertRaisesRegex(ValueError, "sealed original census"):
                NEW.assess_phase1_reviews(HEAD, test_only=True)

    def test_owner_fake_native_proof_cannot_pass_actual_checker(self):
        real_process = subprocess.run
        with tempfile.TemporaryDirectory() as temporary:
            gate, _, _, path, message, context, _, _ = self.fixture(Path(temporary).resolve(), owner=True)
            with mock.patch.object(NEW.subprocess, "run", real_process):
                with self.assertRaisesRegex(ValueError, "RUI1 checker failed"):
                    self.invoke(path, message, context)
            self.assertEqual(NEW.phase1_read_reviews(gate, HEAD, test_only=True), [])

    def test_owner_declared_bundle_or_verifier_output_substitution_refuses(self):
        for key in ("catalogueSHA256", "proofSHA256", "presentationSHA256", "checklistSHA256", "attachmentsSHA256"):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary:
                gate, _, request, path, message, context, _, _ = self.fixture(Path(temporary).resolve(), owner=True)
                request["gallery"][key] = "0" * 64; path.write_bytes(gate.canonical(request))
                with self.assertRaisesRegex(ValueError, "presented bundle"):
                    self.invoke(path, message, context)
        with tempfile.TemporaryDirectory() as temporary:
            gate, _, _, path, message, context, _, _ = self.fixture(Path(temporary).resolve(), owner=True)
            with mock.patch.object(NEW.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"{}", b"")):
                with self.assertRaisesRegex(ValueError, "verified RUI1 proof"):
                    self.invoke(path, message, context)

    def test_source_original_and_test_mode_hostiles_refuse_without_write(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, directory, request, path, message, context, _, _ = self.fixture(Path(temporary).resolve())
            with self.assertRaisesRegex(ValueError, "test-only"):
                NEW.register_phase1_review(path, message, context)
            for field, value in (("head", "7" * 40), ("tree", "8" * 40), ("messageSHA256", "0" * 64),
                ("contextSHA256", "0" * 64), ("messageReference", ""), ("subject", "shared-cold-original"),
                ("originals", [{"runID": RUN, "manifestSHA256": "0" * 64}])):
                with self.subTest(field=field):
                    path.write_bytes(gate.canonical(dict(request, **{field: value})))
                    with self.assertRaises(ValueError): self.invoke(path, message, context)
            path.write_bytes(gate.canonical(request))
            context.write_bytes(b"substituted context")
            with self.assertRaisesRegex(ValueError, "context bytes"): self.invoke(path, message, context)
            self.assertFalse((NEW.EVIDENCE / "v23-phase1-reviews" / HEAD / "000000.json").exists())
            self.assertTrue((directory / "manifest.json").exists())

    def test_conflicting_messages_and_self_review_remain_visible_pending(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, _, request, path, message, context, _, _ = self.fixture(Path(temporary).resolve())
            self.invoke(path, message, context)
            request.update(reportedDisposition="changes-requested", messageReference="test-only:later-response",
                           speakerReference=request["reviewer"]["authorReference"])
            message.write_bytes(b"SYNTHETIC TEST ONLY: changes requested.\n")
            request["messageSHA256"] = gate.sha(message.read_bytes()); path.write_bytes(gate.canonical(request))
            result = self.invoke(path, message, context)
            self.assertEqual(len(result["subjects"]["rui1-cold-original"]), 2)
            self.assertIn("rui1-cold-original", result["unresolvedSubjects"])
            self.assertEqual(len(result["declaredIndependenceGaps"]), 1)
            self.assertEqual(result["functionalQualification"], gate.PENDING)
            self.assertFalse(result["acceptance"])

    def test_lost_ledger_append_retains_record_and_refuses_automatic_repair(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, _, _, path, message, context, _, _ = self.fixture(Path(temporary).resolve())
            with mock.patch.object(NEW, "phase1_append_ledger", side_effect=OSError("synthetic disk failure")):
                with self.assertRaises(OSError): self.invoke(path, message, context)
            record = NEW.EVIDENCE / "v23-phase1-reviews" / HEAD / "000000.json"
            original = record.read_bytes()
            with self.assertRaisesRegex(ValueError, "ledger-anchored"): self.invoke(path, message, context)
            self.assertEqual(record.read_bytes(), original)
            self.assertFalse((NEW.EVIDENCE / "phase1-dispatch-active").exists())

    def test_history_deletion_truncation_empty_directory_and_symlink_refuse(self):
        for mutation in ("delete", "truncate", "empty-directory", "link"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                gate, _, _, path, message, context, _, _ = self.fixture(Path(temporary).resolve())
                self.invoke(path, message, context)
                parent = NEW.EVIDENCE / "v23-phase1-reviews" / HEAD
                record = parent / "000000.json"
                if mutation == "delete": record.unlink()
                elif mutation == "truncate": record.write_bytes(record.read_bytes()[:-8])
                elif mutation == "empty-directory": (parent / "000001.json").mkdir()
                else: record.unlink(); record.symlink_to(message)
                with self.assertRaises(ValueError): NEW.assess_phase1_reviews(HEAD, test_only=True)

    def test_input_replacement_and_active_lock_prevent_capture(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, _, _, path, message, context, _, _ = self.fixture(Path(temporary).resolve())
            lock = NEW.EVIDENCE / "phase1-dispatch-active"; lock.mkdir()
            with self.assertRaises(FileExistsError): self.invoke(path, message, context)
            lock.rmdir()
            original = NEW.phase1_review_bindings
            def replace(*args):
                result = original(*args); message.write_bytes(b"replaced during validation"); return result
            with mock.patch.object(NEW, "phase1_review_bindings", replace):
                with self.assertRaisesRegex(ValueError, "source bytes changed"): self.invoke(path, message, context)
            self.assertEqual(NEW.phase1_read_reviews(gate, HEAD, test_only=True), [])

    def test_duplicate_json_keys_and_denied_real_scan_refuse(self):
        with tempfile.TemporaryDirectory() as temporary:
            gate, _, request, path, message, context, _, _ = self.fixture(Path(temporary).resolve())
            path.write_bytes(gate.canonical(request).replace(b'"schema":', b'"schema":"duplicate","schema":'))
            with self.assertRaisesRegex(ValueError, "duplicate JSON"): self.invoke(path, message, context)
            path.write_bytes(gate.canonical(request)); self.invoke(path, message, context)
            original_scan = NEW.os.scandir
            def denied(path):
                if Path(path) == NEW.EVIDENCE / "v23-phase1-reviews" / HEAD:
                    raise PermissionError("synthetic denied review scan")
                return original_scan(path)
            with mock.patch.object(NEW.os, "scandir", denied):
                with self.assertRaises(PermissionError): NEW.assess_phase1_reviews(HEAD, test_only=True)
            self.assertEqual(NEW.assess_phase1_reviews(HEAD, test_only=True)["functionalQualification"], gate.PENDING)


    def test_integration_review_joins_both_actual_original_contexts(self):
        with tempfile.TemporaryDirectory() as temporary, tempfile.TemporaryDirectory() as other_temporary:
            base, other = Path(temporary).resolve(), Path(other_temporary).resolve()
            gate, _, request, path, message, context, _, _ = self.fixture(base)
            first_run, second_run = RUN, RUN + 1
            # Separate explicitly synthetic originals use the real existing
            # collector writer. Only Git/API/process boundaries are fixtures.
            with mock.patch.dict(globals(), RUN=second_run):
                _, second_dir, _, _, _, _, _, _ = Phase1CollectionCallerTests.fixture(self, other, shared=True)
                with self.assertRaisesRegex(SystemExit, "raw proof INCOMPLETE"):
                    NEW.collect(second_run, False)
            shutil.copytree(second_dir, base / str(second_run))
            for name in ("v23-phase1-plans", "v23-original-attempts"):
                shutil.copytree(other / name, base / name, dirs_exist_ok=True)
            with (base / "v23-original-ledger.jsonl").open("ab") as stream:
                stream.write((other / "v23-original-ledger.jsonl").read_bytes())
            request.update(subject="candidate-integration", originals=sorted(request["originals"] + [
                {"runID": second_run, "manifestSHA256": gate.sha((base / str(second_run) / "manifest.json").read_bytes())}],
                key=lambda item: item["runID"]))
            path.write_bytes(gate.canonical(request))
            with mock.patch.object(NEW, "EVIDENCE", base), mock.patch.object(NEW, "ATTEMPTS", base / "v23-original-attempts"), \
                 mock.patch.object(NEW, "LEDGER", base / "v23-original-ledger.jsonl"):
                result = self.invoke(path, message, context)
                self.assertEqual(len(result["subjects"]["candidate-integration"]), 1)
                bound = result["retainedOriginals"][0]["originals"]
                self.assertEqual({item["runID"] for item in bound}, {first_run, second_run})
                self.assertEqual({item["selection"] for item in bound}, set(gate.SELECTIONS))
                self.assertEqual(result["functionalQualification"], gate.PENDING)
                self.assertFalse(result["acceptance"])


class ColdOriginalControlBoundaryTests(unittest.TestCase):
    """Cold originals retain strict controls while ordinary development stays usable."""

    def plan_fixture(self):
        contract = NEW.phase1_gates()
        sources = {path: contract.sha((REPO_ROOT / path).read_bytes()) for path in contract.SOURCES}
        selected = {"tier": "D40P", "runUISmoke": False,
            "unitTestSelectors": ["SyntheticTests/Test/testOnly"], "uiTestSelectors": [],
            "sharedCoverage": {"partitionsPath": contract.PARTITIONS,
                "partitionsSHA256": sources[contract.PARTITIONS], "partitionIDs": ["S01"], "partitionID": None,
                "developmentOnly": True, "acceptance": False}}
        value = contract.make_cold_plan(head=HEAD, tree="9" * 40, resolved_bytes=contract.canonical(selected),
            sources=sources, requested_at="2026-09-26T12:00:00Z")
        return contract, value, selected

    def test_missing_simultaneous_gate_wrong_kind_retry_reason_and_compiler_refuse_before_effects(self):
        contract, value, _ = self.plan_fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            path = root / "synthetic-cold-plan.json"
            path.write_bytes(contract.canonical(value))
            variants = ({}, {"cold_plan": path, "kind": None}, {"cold_plan": path, "kind": "gate"},
                {"cold_plan": path, "phase1_plan": path, "kind": "development"},
                {"cold_plan": path, "compiler_observation": True, "kind": "development"},
                {"cold_plan": path, "swift_driver_jobs_two": True, "kind": "development"},
                {"cold_plan": path, "infra_retry_of": 1, "kind": "development"},
                {"cold_plan": path, "reason": "retry", "kind": "development"})
            for kwargs in variants:
                with self.subTest(kwargs=kwargs), evidence_root(NEW, root), \
                        mock.patch.object(NEW, "run") as git, mock.patch.object(NEW, "api") as api, \
                        mock.patch.object(NEW.subprocess, "run") as process, \
                        mock.patch.object(NEW, "append_ledger") as append, \
                        mock.patch.object(NEW, "write_new") as write:
                    with self.assertRaises((SystemExit, ValueError)):
                        NEW.dispatch(contract.COLD_SELECTION, **kwargs)
                    for effect in (git, api, process, append, write): effect.assert_not_called()
                    self.assertFalse((root / "v23-original-attempts").exists())
                    self.assertFalse((root / "v23-original-ledger.jsonl").exists())
                    self.assertFalse((root / "cold-dispatch-active").exists())

    def record_fixture(self, root, variant):
        record = {"runID": RUN, "head": HEAD, "selection": DEV, "kind": "development",
                  "resolvedSelection": copy.deepcopy(DEV_PLAN), "resolvedSelectionSHA256": sha(canonical(DEV_PLAN))}
        ledger_record = copy.deepcopy(record)
        if variant == "cold-selection": record["selection"] = ledger_record["selection"] = NEW.COLD_SELECTION_ID
        if variant == "dispatch-marker": record["coldPurpose"] = ""
        if variant == "ledger-marker": ledger_record["coldPlanSHA256"] = "partial"
        directory = root / str(RUN)
        directory.mkdir()
        (directory / "dispatch.json").write_bytes(canonical(record))
        write_ledger(root, [ledger_record])
        if variant == "consumed-prefix":
            attempts = root / "v23-original-attempts"
            attempts.mkdir()
            (attempts / (HEAD + "-" + NEW.COLD_PURPOSE + "-" + NEW.COLD_SELECTION_ID + ".json")).write_bytes(b"{")
        if variant == "malformed-record": (directory / "dispatch.json").write_bytes(b"{")
        return record

    def test_ordinary_development_is_admitted_but_cold_markers_and_partial_attempts_refuse_cancel_retry(self):
        for variant in ("legacy", "cold-selection", "dispatch-marker", "ledger-marker", "consumed-prefix", "malformed-record"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                record = self.record_fixture(root, variant)
                before = tree_bytes(root)
                with evidence_root(NEW, root):
                    _, reason = NEW.recorded_development(RUN)
                    if variant == "legacy":
                        self.assertIsNone(reason)
                        continue
                    self.assertIn("cold", reason.lower())
                    with mock.patch.object(NEW, "api") as api, mock.patch.object(NEW.subprocess, "run") as process, \
                            mock.patch.object(NEW, "append_ledger") as append, mock.patch.object(NEW, "write_new") as write:
                        with self.assertRaisesRegex(SystemExit, "cold"):
                            NEW.cancel(RUN, "synthetic broken-run reason")
                        with self.assertRaisesRegex(SystemExit, "cold"):
                            NEW.infra_retry_admission(HEAD, record["selection"], DEV_PLAN,
                                sha(canonical(DEV_PLAN)), RUN, "synthetic infrastructure reason", "development")
                        for effect in (api, process, append, write): effect.assert_not_called()
                self.assertEqual(tree_bytes(root), before)

    def test_public_legacy_dispatch_cold_retry_refuses_before_git_resolution_remote_or_evidence_effects(self):
        # Genuine stored records exercise the public legacy-selection entry;
        # the cold detector remains real. Even a partial marker/consumed prefix
        # must stop before the deeper retry helper or any operational boundary.
        for variant in ("cold-selection", "dispatch-marker", "ledger-marker", "consumed-prefix", "malformed-record"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                self.record_fixture(root, variant)
                before = tree_bytes(root)
                names_before = sorted(path.relative_to(root).as_posix() for path in root.rglob("*"))
                write_attempts = []; actual_open = Path.open
                def observed_open(path, mode="r", *args, **kwargs):
                    if any(flag in mode for flag in "wax+"):
                        write_attempts.append((str(path), mode))
                        raise AssertionError("public cold retry reached an evidence write")
                    return actual_open(path, mode, *args, **kwargs)
                with evidence_root(NEW, root), contextlib.ExitStack() as stack:
                    effects = {}
                    for name in ("run", "git_bytes", "resolve_selection", "api", "api_bytes", "runs_for",
                                 "infra_retry_admission", "append_ledger", "write_new", "cold_append_ledger",
                                 "phase1_append_ledger", "cold_original_lifecycle", "phase1_candidate_lifecycle"):
                        effects[name] = stack.enter_context(mock.patch.object(NEW, name,
                            side_effect=AssertionError("public cold retry reached " + name)))
                    effects["subprocess.run"] = stack.enter_context(mock.patch.object(NEW.subprocess, "run",
                        side_effect=AssertionError("public cold retry reached a process")))
                    for method in ("mkdir", "write_bytes", "write_text", "touch", "unlink", "rmdir", "rename", "replace"):
                        effects["Path." + method] = stack.enter_context(mock.patch.object(Path, method, autospec=True,
                            side_effect=AssertionError("public cold retry mutated a path via " + method)))
                    stack.enter_context(mock.patch.object(Path, "open", autospec=True, side_effect=observed_open))
                    with self.assertRaisesRegex(SystemExit, "cold original/partial attempt"):
                        NEW.dispatch(DEV, kind="development", infra_retry_of=RUN,
                                     reason="synthetic infrastructure failure; never retry a cold original")
                    for name, effect in effects.items():
                        with self.subTest(effect=name): effect.assert_not_called()
                    self.assertEqual(write_attempts, [])
                self.assertEqual(tree_bytes(root), before)
                self.assertEqual(sorted(path.relative_to(root).as_posix() for path in root.rglob("*")), names_before)
                self.assertFalse((root / "cold-dispatch-active").exists())
                self.assertFalse((root / "phase1-dispatch-active").exists())

    def test_partial_consumed_attempt_blocks_dispatch_before_git_api_lock_or_writer(self):
        contract, value, _ = self.plan_fixture()
        for raw in (b"", b"{", b"{}\n"):
            with self.subTest(raw=raw), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                path = root / "synthetic-cold-plan.json"
                path.write_bytes(contract.canonical(value))
                attempts = root / "v23-original-attempts"; attempts.mkdir()
                target = attempts / (contract.cold_original_stem(value) + ".json")
                target.write_bytes(raw)
                before = tree_bytes(root)
                with evidence_root(NEW, root), mock.patch.object(NEW, "run") as git, \
                        mock.patch.object(NEW, "api") as api, mock.patch.object(NEW.subprocess, "run") as process:
                    with self.assertRaisesRegex(ValueError, "consumed"):
                        NEW.dispatch(contract.COLD_SELECTION, kind="development", cold_plan=path)
                    with self.assertRaisesRegex(SystemExit, "consumed"):
                        NEW.preregister_cold(path)
                    for effect in (git, api, process): effect.assert_not_called()
                self.assertEqual(tree_bytes(root), before)
                self.assertFalse((root / "cold-dispatch-active").exists())

    def test_cold_and_ordinary_artifact_names_are_closed_distinct_and_share_payload_identity(self):
        legacy = NEW.shared_artifact_names(RUN, HEAD, ["S01"])
        cold = NEW.shared_artifact_names(RUN, HEAD, ["S01"], selection=NEW.COLD_SELECTION_ID)
        self.assertNotEqual(legacy["producer"], cold["producer"])
        self.assertNotEqual(legacy["consumers"]["S01"], cold["consumers"]["S01"])
        self.assertEqual(legacy["payload"], cold["payload"])
        self.assertIn(NEW.COLD_SELECTION_ID, cold["producer"])
        with self.assertRaises(SystemExit):
            NEW.shared_artifact_names(RUN, HEAD, ["S01"], selection="caller-chosen-cold")


class ColdOriginalCollectionTests(unittest.TestCase):
    """Actual cold context/collector, with synthetic Git/API/transport boundaries only."""
    plan_fixture = ColdOriginalControlBoundaryTests.plan_fixture

    def durable_worker_files(self, core, plan, selected, event, binding, record):
        """Synthetic worker transport; real disposable producer I/O, no app proof.

        Authentication and emitter fields are parser-test stand-ins only. The
        existing producer supplies the raw sink, sealed union and actual owner
        outcomes; none of these bytes grants reader or gate qualification.
        """
        native_path = REPO_ROOT / "Scripts/v23-native-ci.py"
        native_raw = native_path.read_bytes()
        self.assertEqual(sha(native_raw), plan["sources"]["Scripts/v23-native-ci.py"])
        native = load(native_path, "v23_cold_original_synthetic_worker")
        writer_path = native.SIMULATOR_DIAGNOSTIC_SOURCE_PATH
        writer_raw = (REPO_ROOT / writer_path).read_bytes()
        self.assertEqual(sha(writer_raw), native.SIMULATOR_DIAGNOSTIC_SOURCE_SHA256)
        self.assertNotIn(writer_path, plan["sources"], "closed cold plan must not acquire a counterfeit PFP key")
        with tempfile.TemporaryDirectory(prefix="synthetic-cold-worker-") as temporary:
            artifact = Path(temporary).resolve()
            context = {"schema": native.COLD_DURABLE_CONTEXT_SCHEMA,
                "executionScope": core.COLD_PURPOSE, "head": plan["head"], "tree": plan["tree"],
                "runID": record["runID"], "runAttempt": "1", "role": "consumer",
                "partitionID": record["sharedCoverage"]["partitionID"],
                "originalEventSHA256": sha(event), "eventBindingSHA256": sha(core.canonical(binding)),
                "admissionSHA256": sha(core.canonical(record)), "planSHA256": binding["planSHA256"],
                "selectionSHA256": plan["selectionSHA256"], "writerSourceSHA256": sha(writer_raw),
                "simulatorUDID": "00000000-0000-0000-0000-000000000001"}
            self.assertEqual(len(context), 15)
            owners = {}
            prepared = native.cold_durable_prepare(artifact, context, owners)
            context.update(durableSinkPath=prepared["path"],
                           durableSinkBindingSHA256=prepared["bindingSHA256"])
            (artifact / "native-admission.json").write_bytes(core.canonical(record))
            (artifact / native.COLD_EMITTED_FORWARD_RECEIPT).write_bytes(core.canonical({
                "context": context, "contextSHA256": sha(core.canonical(context))}))
            controls = []
            for suffix, kind in (("21", "database"), ("22", "scratch")):
                # Explicitly synthetic emitters: these fields exercise the
                # parser protocol, never actual app identity or app lifetime.
                stream = "00000000-0000-0000-0000-0000000000" + suffix
                emitter = "10000000-0000-0000-0000-0000000000" + suffix
                backup, directory = native.OWNED_FILE_DISPOSITIONS[kind]
                values = {"policyID": native.SIMULATOR_DIAGNOSTIC_POLICY_ID,
                    "disposition": native.SIMULATOR_DIAGNOSTIC_DISPOSITION, "kind": kind,
                    "request": "complete", "capabilityBefore": "false", "capabilityAfter": "false",
                    "urlProtection": native.SIMULATOR_FALLBACK_PROTECTION,
                    "backupExcluded": str(backup).lower(), "expectsDirectory": str(directory).lower(),
                    "identityUnchanged": "true"}
                payload = (native.SIMULATOR_DIAGNOSTIC_PREFIX + " " + " ".join(
                    key + "=" + values[key] for key in native.SIMULATOR_DIAGNOSTIC_FIELDS) + "\n").encode()
                frame = core.canonical({"schema": native.SIMULATOR_DIAGNOSTIC_FRAME_SCHEMA,
                    "streamID": stream, "sequence": 1,
                    "payloadBase64": native.base64.b64encode(payload).decode("ascii"),
                    "payloadByteCount": len(payload), "payloadSHA256": sha(payload)})
                common = {"schema": native.COLD_DURABLE_RECORD_SCHEMA, "streamID": stream,
                    "emitterID": emitter, "contextSHA256": sha(core.canonical(context)),
                    "bindingSHA256": prepared["bindingSHA256"]}
                controls.append(core.canonical({**common, "kind": "STREAM_START", "actualPID": 100,
                    "actualHome": "/synthetic-fixture-home", "actualBundleID": native.SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID,
                    "actualExecutable": "/synthetic-fixture-home/FieldEvidenceApp"}))
                commit = {**common, "sequence": 1, "frameBytes": len(frame), "frameSHA256": sha(frame)}
                controls.extend((core.canonical({**commit, "kind": "FRAME_PREPARE"}), frame,
                                 core.canonical({**commit, "kind": "FRAME_COMMIT"})))
            with (Path(prepared["path"]) / "EMITTED.jsonl").open("ab") as emitted:
                emitted.write(b"".join(controls))
            with mock.patch.object(native, "cold_worker_context",
                    return_value=(binding, event, selected, plan["selectionSHA256"])), \
                    contextlib.redirect_stdout(io.StringIO()):
                status = native.cold_durable_collect(REPO_ROOT, artifact,
                    {"CI_SIMULATOR_UDID": context["simulatorUDID"]}, False, 0,
                    native.time.monotonic(), native.time.monotonic)
            self.assertEqual(status["status"], "AVAILABLE")
            proof = json.loads((artifact / native.COLD_DURABLE_PROOF).read_bytes())
            self.assertEqual(proof["status"], "SEALED_EMITTED_TRANSPORT_ONLY")
            self.assertEqual((artifact / native.COLD_DURABLE_ROOT / "STATE").read_bytes(), b"SEALED\n")
            self.assertEqual(len(proof["observed"]["streams"]), 2)
            self.assertTrue(all(row.get("closeReturned") is True and row.get("closeUncertain") is False
                                and row.get("error") is None for row in proof["io"] if row.get("closeEntered") is True))
            self.assert_pending({**proof, "status": "INCOMPLETE"})
            return {str(path.relative_to(artifact)).replace(os.sep, "/"): path.read_bytes()
                    for path in artifact.rglob("*") if path.is_file()}

    def fixture(self, base):
        core, plan, selected = self.plan_fixture()
        gate = core.ColdContract()
        parts = {"partitionsPath": core.PARTITIONS, "partitionsSHA256": plan["sources"][core.PARTITIONS],
                 "partitionIDs": ["S01"], "selectors": {"S01": selected["unitTestSelectors"]}}
        registration_path, _ = core.register_cold(plan, base / "v23-cold-plans")
        observations = synthetic_phase1_observations(core, plan)
        attempt = core.make_cold_attempt(plan, registration_path.read_bytes(), collector_id="a" * 32,
            requested_at="2026-09-26T12:01:00Z", observations=observations, ledger_bytes="", attempt_names=[])
        attempts = base / "v23-original-attempts"; attempts.mkdir()
        attempt_path = attempts / (core.cold_original_stem(plan) + ".json")
        attempt_path.write_bytes(core.canonical(attempt))
        observed = {"id": RUN, "run_attempt": 1, "workflow_id": 7, "head_sha": HEAD,
            "head_branch": NEW.BRANCH, "path": NEW.WORKFLOW_PATH, "event": "workflow_dispatch",
            "repository": {"full_name": REPO, "id": 77}, "head_repository": {"full_name": REPO, "id": 77},
            "created_at": "2026-09-26T12:01:01Z", "status": "completed", "conclusion": "success"}
        event = core.canonical({"repository": {"full_name": REPO}, "ref": plan["ref"],
                                "inputs": core.cold_dispatch_inputs(plan)})
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": REPO,
            "GITHUB_REF": plan["ref"], "GITHUB_SHA": HEAD, "GITHUB_RUN_ID": str(RUN),
            "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKFLOW_SHA": HEAD,
            "GITHUB_WORKFLOW_REF": REPO + "/" + NEW.WORKFLOW_PATH + "@" + plan["ref"]}
        binding = core.bind_cold_original_event(event, environment, head=HEAD, tree=plan["tree"],
            resolved_bytes=core.canonical(selected), sources=plan["sources"])
        names = NEW.shared_artifact_names(RUN, HEAD, parts["partitionIDs"], selection=core.COLD_SELECTION)
        files, blobs, artifacts = {}, {}, []
        for index, label in enumerate(("producer", "S01")):
            role = "producer" if label == "producer" else "consumer"
            record = {"coldOriginal": binding, "head": HEAD, "gitTree": plan["tree"], "ref": plan["ref"],
                "runID": str(RUN), "runAttempt": "1", "selectionID": core.COLD_SELECTION,
                "sharedCoverage": {"role": role, "partitionID": None if role == "producer" else label,
                    "payloadArtifactName": names["payload"], "planSHA256": plan["selectionSHA256"],
                    "partitionsSHA256": plan["sources"][core.PARTITIONS]}}
            checkpoint = {"coldOriginal": binding, "executedUnitMethods": [] if role == "producer" else parts["selectors"][label],
                "executedUIMethods": [], "providerQualification": False, "acceptance": False, "releaseReady": False}
            files[label] = {"synthetic-only.txt": b"not native evidence", "cold-original-event.json": event,
                "cold-original-plan.json": core.canonical(plan), "cold-event-binding.json": core.canonical(binding),
                "native-admission.json": core.canonical(record), "native-checkpoint.json": core.canonical(checkpoint)}
            receipts = ("v23-shared-payload.json", "v23-shared-payload-receipt.json") if role == "producer" else (
                "v23-shared-payload.json", "v23-shared-restore.json", "v23-shared-fingerprint-before.json",
                "v23-shared-fingerprint-after.json", "v23-shared-deriveddata-delta.json")
            for name in receipts:
                files[label][name] = core.canonical({"syntheticTestOnly": True, "name": name,
                                                   "acceptance": False, "providerQualification": False})
            products = [{"path": "synthetic-product.txt", "type": "file", "size": 4,
                         "mode": 0o644, "sha256": sha(b"DATA")}]
            live = {}
            for stage in (("seal",) if role == "producer" else ("restore", "before", "after")):
                stage_receipts = receipts if stage in ("seal", "after") else receipts[:2 if stage == "restore" else 3]
                value = {"schema": "v23-cold-shared-live-observation.v1", "stage": stage,
                    "eventBindingSHA256": core.sha(core.canonical(binding)), "originalEventSHA256": core.sha(event),
                    "admissionSHA256": core.sha(core.canonical(record)), "planSHA256": core.sha(core.canonical(plan)),
                    "selectionSHA256": plan["selectionSHA256"], "head": HEAD, "tree": plan["tree"],
                    "runID": str(RUN), "runAttempt": "1", "role": role,
                    "partitionID": None if role == "producer" else label, "products": products,
                    "receiptSHA256": {name: core.sha(files[label][name]) for name in stage_receipts},
                    "status": "INCOMPLETE", "functionalQualification": "PENDING", "processLifetimes": "PENDING",
                    "executionScope": core.COLD_PURPOSE, "developmentOnly": True,
                    "providerQualification": False, "acceptance": False, "releaseReady": False}
                files[label]["cold-shared-observation-" + stage + ".json"] = core.canonical(value)
                live[stage] = value
            checkpoint["coldSharedObservations"] = live
            files[label]["native-checkpoint.json"] = core.canonical(checkpoint)
            if role == "consumer":
                files[label].update(self.durable_worker_files(core, plan, selected, event, binding, record))
            blobs[index + 20] = zip_bytes(files[label])
            artifacts.append({"id": index + 20, "name": names["producer"] if role == "producer" else names["consumers"][label],
                "expired": False, "digest": "sha256:" + sha(blobs[index + 20]).lower(), "size_in_bytes": len(blobs[index + 20]),
                "workflow_run": {"id": RUN, "head_sha": HEAD, "head_branch": NEW.BRANCH,
                                 "repository_id": 77, "head_repository_id": 77}})
        inner_tar = b"synthetic inner TAR; Stage1 must retain the outer ZIP without opening it"
        payload = zip_bytes({"FieldEvidencePayload.tar": inner_tar})
        payload_id = 22
        artifacts.append({"id": payload_id, "name": names["payload"], "expired": False,
            "digest": "sha256:" + sha(payload).lower(), "size_in_bytes": len(payload) + 17,
            "workflow_run": {"id": RUN, "head_sha": HEAD, "head_branch": NEW.BRANCH,
                             "repository_id": 77, "head_repository_id": 77}})
        jobs = [{"id": index + 1, "name": name, "run_id": RUN, "run_attempt": 1, "head_sha": HEAD,
                 "status": "completed", "conclusion": "success", "steps": []} for index, name in enumerate(
                    (NEW.SHARED_SELECTION_JOB, NEW.SHARED_PRODUCER_JOB,
                     "V23 shared coverage consumer " + DOT + " S01 (development only) / verify"))]
        directory = base / str(RUN); directory.mkdir()
        calls, downloads, commands = [], [], []
        state = {"core": core, "gate": gate, "plan": plan, "selected": selected, "parts": parts,
            "attempt": attempt_path, "observed": observed, "jobs": jobs, "artifacts": artifacts,
            "files": files, "blobs": blobs, "payload": payload, "innerTAR": inner_tar,
            "payloadID": payload_id, "directory": directory, "calls": calls, "downloads": downloads,
            "commands": commands, "observations": observations, "runs": [observed],
            "stage1BridgeBoundaryCalls": []}
        def api(endpoint):
            calls.append(endpoint)
            if endpoint == f"repos/{REPO}": return copy.deepcopy(observations["repository"])
            for key, ref in (("integration", NEW.BRANCH), ("main", "main")):
                if endpoint == f"repos/{REPO}/git/ref/heads/{ref}": return copy.deepcopy(observations["refs"][key])
            if endpoint in (f"repos/{REPO}/actions/workflows/7", f"repos/{REPO}/actions/workflows/{NEW.WORKFLOW}"):
                return copy.deepcopy(observations["workflow"])
            prefix = f"repos/{REPO}/actions/runs?head_sha={HEAD}&per_page={NEW.PAGE_SIZE}&page="
            if endpoint.startswith(prefix):
                page = int(endpoint.removeprefix(prefix))
                rows = state["runs"]
                return {"total_count": len(rows), "workflow_runs": copy.deepcopy(rows[(page - 1) * NEW.PAGE_SIZE:page * NEW.PAGE_SIZE])}
            base_run = f"repos/{REPO}/actions/runs/{RUN}"
            if endpoint in (base_run, base_run + "/attempts/1"): return copy.deepcopy(observed)
            # Discovery fetches IDs actually returned by the mutable census;
            # a hostile row stays hostile at both discovery and frozen GETs.
            for row in state["runs"]:
                identifier = row.get("id")
                if type(identifier) is int and identifier > 0 and endpoint == f"repos/{REPO}/actions/runs/{identifier}":
                    return copy.deepcopy(row)
            for path, key, rows in ((base_run + "/attempts/1/jobs", "jobs", jobs),
                                    (base_run + "/artifacts", "artifacts", artifacts)):
                if endpoint.startswith(path + "?per_page="):
                    page = int(re.search(r"page=(\d+)$", endpoint).group(1))
                    return {"total_count": len(rows), key: copy.deepcopy(rows[(page - 1) * NEW.PAGE_SIZE:page * NEW.PAGE_SIZE])}
            raise AssertionError("unexpected synthetic cold API endpoint " + endpoint)
        def download(endpoint):
            downloads.append(endpoint)
            if endpoint == f"repos/{REPO}/actions/runs/{RUN}/attempts/1/logs":
                return zip_bytes({"synthetic-log.txt": b"not native execution proof"})
            if re.fullmatch(r"repos/" + re.escape(REPO) + r"/actions/jobs/[1-3]/logs", endpoint):
                return b"synthetic complete job log, no native proof\n"
            match = re.fullmatch(r"repos/" + re.escape(REPO) + r"/actions/artifacts/(\d+)/zip", endpoint)
            self.assertIsNotNone(match)
            identifier = int(match.group(1))
            self.assertNotEqual(identifier, payload_id, "cold payload must use bounded streaming")
            return blobs[identifier]
        def chunks(identifier):
            self.assertIn(identifier, (20, 21, payload_id))
            downloads.append(f"repos/{REPO}/actions/artifacts/{identifier}/zip")
            raw = payload if identifier == payload_id else blobs[identifier]
            for offset in range(0, len(raw), 31): yield raw[offset:offset + 31]
        def git_bytes(*args):
            self.assertEqual(args[0], "show", "cold Stage1 must not archive or run a reader")
            writer_path = "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift"
            if args[1] == plan["tree"] + ":" + writer_path:
                # Synthetic frozen-tree archive boundary; actual current writer
                # bytes are authenticated by the frozen Native Source pin.
                return (REPO_ROOT / writer_path).read_bytes()
            self.assertTrue(args[1].startswith(HEAD + ":"))
            return (REPO_ROOT / args[1].split(":", 1)[1]).read_bytes()
        def process(*args, **kwargs):
            commands.append(args)
            raise AssertionError("cold raw collection must not invoke a child, native tool or dispatch")
        def stage1_bridge_boundary(actual_gate, actual_plan, operation):
            # This one-partition raw-collection fixture stops at the NEW bridge
            # boundary. Full33/3716 payload/worker recomputation has separate
            # actual-function/reader checks and future authentic originals.
            # Never invoke its archive/reader operation or synthesize success.
            self.assertIs(actual_gate, gate)
            self.assertEqual(actual_plan, plan)
            self.assertEqual(parts["partitionIDs"], ["S01"])
            self.assertEqual(selected["unitTestSelectors"], ["SyntheticTests/Test/testOnly"])
            self.assertTrue(callable(operation))
            state["stage1BridgeBoundaryCalls"].append({
                "syntheticTestOnly": True, "boundary": "cold_v2_archived_call",
                "partitionIDs": ["S01"], "planSHA256": core.sha(core.canonical(plan))})
            return {"schema": NEW.COLD_PAYLOAD_RECOMPUTATION_SCHEMA_V2,
                "status": "PENDING_UNAVAILABLE_ORIGINAL_INPUTS",
                "functionalQualification": gate.PENDING, "providerQualification": False,
                "gateQualification": False, "acceptance": False, "releaseReady": False,
                "syntheticTestOnly": True, "fixtureScope": "STAGE1_ONE_PARTITION_BOUNDARY_ONLY"}
        stack = contextlib.ExitStack()
        for name, replacement in (("EVIDENCE", base), ("ATTEMPTS", attempts), ("LEDGER", base / "v23-original-ledger.jsonl"),
                ("cold_gates", lambda: gate), ("cold_timestamp", lambda: "2026-09-26T12:01:02Z"),
                ("api", api), ("api_bytes", download), ("phase1_payload_chunks", chunks),
                ("git_bytes", git_bytes), ("run", lambda *args: plan["tree"] + "\n"),
                ("resolve_selection", lambda *args: (selected, plan["selectionSHA256"])),
                ("shared_partitions", lambda *args: parts)):
            stack.enter_context(mock.patch.object(NEW, name, replacement))
        stack.enter_context(mock.patch.object(NEW.subprocess, "run", process))
        stack.enter_context(mock.patch.object(NEW, "cold_v2_archived_call", stage1_bridge_boundary))
        stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.addCleanup(stack.close)
        lifecycle = NEW.cold_lifecycle_directory(gate, plan); lifecycle.mkdir()
        receipt = NEW.cold_request_receipt(gate, attempt,
            result=subprocess.CompletedProcess(attempt["argv"], 0, b"", b""))
        gate.write_immutable(lifecycle / "request.json", gate.canonical(receipt))
        entry = NEW.cold_record_discovery(gate, plan, attempt, {
            "repository": observations["repository"], "refs": observations["refs"],
            "headRuns": {"total_count": 1, "workflow_runs": [observed]}, "directRun": observed,
            "error": None, "transportFailure": False,
            "runPages": [{"endpoint": f"repos/{REPO}/actions/runs?head_sha={HEAD}&per_page={NEW.PAGE_SIZE}&page=1",
                          "response": {"total_count": 1, "workflow_runs": [observed]}}]})
        record = NEW.cold_dispatch_record(gate, plan, attempt, selected, entry)
        gate.write_immutable(directory / "dispatch.json", gate.canonical(record))
        NEW.cold_append_ledger(gate, record)
        return state

    def collect_incomplete(self, resume=False):
        with self.assertRaisesRegex(SystemExit, "INCOMPLETE"):
            NEW.collect(RUN, resume)

    def state(self, directory):
        proof = directory / "cold-raw-proof.json"
        if proof.exists(): return json.loads(proof.read_bytes())
        return json.loads(sorted((directory / "cold-collection-partials").iterdir())[-1].read_bytes())

    def assert_pending(self, state):
        self.assertEqual((state["status"], state["functionalQualification"]), ("INCOMPLETE", "PENDING"))
        for key in ("providerQualification", "acceptance", "releaseReady"): self.assertIs(state[key], False)

    def transports(self, fixture):
        root = fixture["directory"] / "cold-payload-transports" / str(fixture["payloadID"])
        entries = sorted(root.iterdir())
        self.assertEqual([path.name for path in entries], ["%06d" % index for index in range(len(entries))])
        return entries

    def test_stage1_new_bridge_boundary_retains_only_marked_pending_data_without_reader_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.fixture(Path(temporary).resolve())
            self.collect_incomplete()
            self.assertEqual(f["stage1BridgeBoundaryCalls"], [{"syntheticTestOnly": True,
                "boundary": "cold_v2_archived_call", "partitionIDs": ["S01"],
                "planSHA256": f["core"].sha(f["core"].canonical(f["plan"]))}])
            self.assertEqual(json.loads((f["directory"] / "cold-payload-recomputed-facts-v2.json").read_bytes()),
                {"schema": NEW.COLD_PAYLOAD_RECOMPUTATION_SCHEMA_V2,
                 "status": "PENDING_UNAVAILABLE_ORIGINAL_INPUTS",
                 "functionalQualification": f["gate"].PENDING, "providerQualification": False,
                 "gateQualification": False, "acceptance": False, "releaseReady": False,
                 "syntheticTestOnly": True, "fixtureScope": "STAGE1_ONE_PARTITION_BOUNDARY_ONLY"})
            self.assertFalse((f["directory"] / "cold-payload-recomputations-v2").exists())
            self.assertFalse((f["directory"] / "phase1-payload-recomputations").exists())
            self.assertEqual(f["commands"], [])
            self.assertEqual(f["parts"]["partitionIDs"], ["S01"])
            self.assertEqual(f["selected"]["unitTestSelectors"], ["SyntheticTests/Test/testOnly"])
            self.assert_pending(self.state(f["directory"]))
            transport = self.transports(f)[0]
            self.assertEqual((transport / "raw.zip").read_bytes(), f["payload"])
            self.assertEqual(json.loads((transport / "receipt.json").read_bytes())["status"], "COMPLETE")

    def test_actual_cold_context_retains_raw_outer_zip_and_bound_workers_without_reader_or_gate_credit(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.fixture(Path(temporary).resolve())
            self.assertEqual(NEW.cold_original_context(RUN)[3], f["plan"])
            self.collect_incomplete()
            proof = self.state(f["directory"]); self.assert_pending(proof)
            self.assertEqual(set(proof["dispatchInputBindings"]), {"producer", "S01"})
            self.assertEqual(set(proof["artifacts"]), {"producer", "S01", "payload"})
            self.assertEqual(proof["originalAttribution"]["status"], "DISCOVERED_PENDING_PROOF")
            self.assertFalse(any(problem.startswith(("worker ", "artifact[", "cold complete"))
                                 for problem in proof["problems"]), proof["problems"])
            transport = self.transports(f)[0]
            receipt = json.loads((transport / "receipt.json").read_bytes())
            self.assertEqual((receipt["status"], receipt["actualZIPBytes"], receipt["actualZIPSHA256"]),
                             ("COMPLETE", len(f["payload"]), sha(f["payload"])))
            self.assertEqual((transport / "raw.zip").read_bytes(), f["payload"])
            self.assertNotEqual(receipt["actualZIPBytes"], receipt["declaredAPISizeBytes"])
            self.assertNotEqual(receipt["actualZIPSHA256"], sha(f["innerTAR"]))
            self.assertEqual(f["commands"], [])
            self.assertFalse((f["directory"] / "phase1-raw-proof.json").exists())
            self.assertFalse((f["directory"] / "phase1-payload-recomputations").exists())
            manifest = json.loads((f["directory"] / "manifest.json").read_bytes())
            self.assertEqual(manifest["schema"], "v23-cold-original-manifest.v1")
            self.assertEqual(manifest["files"]["cold-raw-proof.json"], sha((f["directory"] / "cold-raw-proof.json").read_bytes()))
            before = tree_bytes(f["directory"])
            with self.assertRaisesRegex(ValueError, "immutable"): NEW.collect(RUN, True)
            self.assertEqual(tree_bytes(f["directory"]), before)
            retained = json.loads((f["directory"] / "cold-emitted-retained-facts.json").read_bytes())
            self.assertEqual(set(retained["consumerFacts"]), {"S01"})
            facts = retained["consumerFacts"]["S01"]
            self.assertTrue(facts["committedEmittedBytesComplete"])
            self.assertEqual(len(facts["observed"]["streams"]), 2)
            self.assertEqual(facts["observed"]["rawSHA256"],
                             sha(f["files"]["S01"]["cold-emitted-durable-original/EMITTED.jsonl"]))
            self.assertEqual(facts["files"], [{"name": row["streamID"] + ".jsonl", "bytes": row["bytes"],
                "sha256": row["sha256"]} for row in facts["observed"]["streams"]])
            for key in ("countsAreTotalInvocations", "processLifetimesProven", "physicalRetirementProven",
                        "providerQualification", "acceptance", "releaseReady"):
                self.assertIs(facts[key], False)
            self.assertEqual(facts["functionalQualification"], "PENDING")
        for variant in ("missing-proof", "unsealed", "raw-drift", "derived-drift", "source-drift", "context-drift"):
            with self.subTest(durable=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); files = f["files"]["S01"]
                if variant == "missing-proof": del files["cold-emitted-durable-proof.json"]
                if variant == "unsealed": files["cold-emitted-durable-original/STATE"] = b"OPEN\n"
                if variant == "raw-drift":
                    raw = files["cold-emitted-durable-original/EMITTED.jsonl"]
                    files["cold-emitted-durable-original/EMITTED.jsonl"] = b"\n".join(raw.split(b"\n")[:-2]) + b"\n"
                if variant == "derived-drift":
                    name = next(name for name in files if name.startswith("simulator-file-protection-transport/"))
                    files[name] += b"drift\n"
                if variant in ("source-drift", "context-drift"):
                    proof = json.loads(files["cold-emitted-durable-proof.json"])
                    proof["context"]["writerSourceSHA256" if variant == "source-drift" else "admissionSHA256"] = "F" * 64
                    files["cold-emitted-durable-proof.json"] = canonical(proof)
                f["blobs"][21] = zip_bytes(files)
                f["artifacts"][1].update(digest="sha256:" + sha(f["blobs"][21]).lower(), size_in_bytes=len(f["blobs"][21]))
                self.collect_incomplete()
                proof = self.state(f["directory"]); self.assert_pending(proof)
                self.assertTrue(any("worker S01" in problem for problem in proof["problems"]), proof["problems"])
                retained = json.loads((f["directory"] / "cold-emitted-retained-facts.json").read_bytes())
                self.assertNotIn("S01", retained["consumerFacts"])
                self.assertEqual(f["commands"], [])
                self.assertFalse((f["directory"] / "phase1-raw-proof.json").exists())
                self.assertFalse((f["directory"] / "phase1-payload-recomputations").exists())

    def test_actual_context_refuses_dispatch_supplied_reduced_census_before_any_collection_api(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.fixture(Path(temporary).resolve())
            path = f["directory"] / "dispatch.json"
            dispatched = json.loads(path.read_bytes())
            dispatched["sharedPartitions"]["selectors"]["S01"] = []
            path.write_bytes(f["core"].canonical(dispatched))
            with mock.patch.object(NEW, "api") as api:
                with self.assertRaisesRegex(ValueError, "committed ordered partition census"):
                    NEW.cold_original_context(RUN)
                api.assert_not_called()
            self.assertEqual(f["commands"], [])


    def test_bad_authenticated_original_attempt_repo_head_and_workflow_refuse_before_payload_get(self):
        for changes in ({"id": RUN + 1}, {"run_attempt": 2}, {"run_attempt": True},
                        {"workflow_id": 8}, {"head_sha": "f" * 40}, {"head_branch": "main"},
                        {"repository": {"full_name": REPO, "id": 78}}, {"path": "foreign.yml"}):
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); f["observed"].update(changes)
                with mock.patch.object(NEW, "phase1_payload_chunks") as chunks:
                    with self.assertRaises(ValueError): NEW.collect(RUN, False)
                    chunks.assert_not_called()
                if changes.get("id") == RUN + 1:
                    self.assertIn(f"repos/{REPO}/actions/runs/{RUN + 1}", f["calls"])
                    self.assertIn(f"repos/{REPO}/actions/runs/{RUN}", f["calls"])
                self.assertFalse((f["directory"] / "manifest.json").exists())
                self.assertTrue((f["directory"] / "collector.claim.json").is_file())

    def test_artifact_origin_id_name_expiry_digest_and_ambiguous_census_never_reach_payload_stream(self):
        for variant in ("run", "head", "ref", "repository", "id-bool", "name", "expired", "digest", "duplicate"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); artifact = f["artifacts"][-1]
                if variant == "run": artifact["workflow_run"]["id"] += 1
                if variant == "head": artifact["workflow_run"]["head_sha"] = "f" * 40
                if variant == "ref": artifact["workflow_run"]["head_branch"] = "main"
                if variant == "repository": artifact["workflow_run"]["repository_id"] += 1
                if variant == "id-bool": artifact["id"] = True
                if variant == "name": artifact["name"] = "caller-chosen-payload"
                if variant == "expired": artifact["expired"] = True
                if variant == "digest": artifact["digest"] = "sha256:NOT_A_DIGEST"
                if variant == "duplicate": f["artifacts"].append(copy.deepcopy(artifact))
                original = NEW.phase1_payload_chunks
                def valid_only(identifier):
                    self.assertNotEqual(identifier, f["payloadID"], "invalid payload reached transport")
                    yield from original(identifier)
                with mock.patch.object(NEW, "phase1_payload_chunks", valid_only):
                    self.collect_incomplete()
                proof = self.state(f["directory"]); self.assert_pending(proof)
                self.assertNotIn("payload", proof["artifacts"])
                self.assertTrue(proof["problems"])
                self.assertTrue((f["directory"] / "artifacts/S01/synthetic-only.txt").is_file())

    def test_worker_event_identity_role_payload_method_and_gate_masquerade_are_retained_as_failures(self):
        for variant in ("run", "head", "role", "payload", "methods", "gate", "event", "plan"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); files = f["files"]["S01"]
                admission = json.loads(files["native-admission.json"])
                checkpoint = json.loads(files["native-checkpoint.json"])
                if variant == "run": admission["runID"] = str(RUN + 1)
                if variant == "head": admission["head"] = "f" * 40
                if variant == "role": admission["sharedCoverage"]["role"] = "producer"
                if variant == "payload": admission["sharedCoverage"]["payloadArtifactName"] = "caller-payload"
                if variant == "methods": checkpoint["executedUnitMethods"] = []
                if variant == "gate": admission["phase1Gate"] = admission["coldOriginal"]
                if variant == "event":
                    event = json.loads(files["cold-original-event.json"]); event["inputs"]["v23_run_kind"] = "gate"
                    files["cold-original-event.json"] = canonical(event)
                if variant == "plan": files["cold-original-plan.json"] += b" "
                files["native-admission.json"] = canonical(admission)
                files["native-checkpoint.json"] = canonical(checkpoint)
                f["blobs"][21] = zip_bytes(files)
                f["artifacts"][1].update(digest="sha256:" + sha(f["blobs"][21]).lower(), size_in_bytes=len(f["blobs"][21]))
                self.collect_incomplete()
                proof = self.state(f["directory"]); self.assert_pending(proof)
                self.assertTrue(any("worker S01" in problem for problem in proof["problems"]))
                self.assertEqual(f["commands"], [])

    def test_authenticated_hostile_worker_zip_is_retained_but_never_extracted_outside_its_role(self):
        for variant in ("path", "symlink", "duplicate"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); buffer = io.BytesIO()
                with zipfile.ZipFile(buffer, "w") as bundle:
                    if variant == "path":
                        bundle.writestr("../../escaped-cold-worker.txt", b"hostile authenticated worker bytes")
                    elif variant == "symlink":
                        member = zipfile.ZipInfo("cold-worker-link")
                        member.create_system = 3; member.external_attr = (stat.S_IFLNK | 0o777) << 16
                        bundle.writestr(member, b"../../escaped-cold-worker.txt")
                    else:
                        bundle.writestr("duplicate-worker.txt", b"first")
                        bundle.writestr("duplicate-worker.txt", b"second")
                raw = buffer.getvalue(); f["blobs"][20] = raw
                f["artifacts"][0].update(digest="sha256:" + sha(raw).lower(), size_in_bytes=len(raw))
                self.collect_incomplete()
                proof = self.state(f["directory"]); self.assert_pending(proof)
                self.assertTrue(any("artifact[0] refused" in problem for problem in proof["problems"]))
                self.assertNotIn("producer", proof["artifacts"])
                retained = f["directory"] / "cold-payload-transports/20/000000"
                receipt = json.loads((retained / "receipt.json").read_bytes())
                self.assertEqual(receipt["status"], "COMPLETE")
                self.assertEqual((retained / "raw.zip").read_bytes(), raw)
                self.assertFalse((f["directory"] / "escaped-cold-worker.txt").exists())
                self.assertFalse((f["directory"] / "artifacts/producer/cold-worker-link").exists())
                self.assertEqual(f["commands"], [])

    def test_outer_zip_digest_mismatch_keeps_original_bytes_terminal_and_pending(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.fixture(Path(temporary).resolve())
            f["artifacts"][-1]["digest"] = "sha256:" + "f" * 64
            self.collect_incomplete()
            proof = self.state(f["directory"]); self.assert_pending(proof)
            receipt = json.loads((self.transports(f)[0] / "receipt.json").read_bytes())
            self.assertEqual(receipt["status"], "DIGEST_MISMATCH")
            self.assertFalse(receipt["digestVerified"])
            self.assertEqual(receipt["actualZIPSHA256"], sha(f["payload"]))
            self.assertTrue(any("digest mismatch" in problem for problem in proof["problems"]))

    def test_live_observation_source_identity_receipt_bytes_and_checkpoint_join_cannot_be_forged(self):
        for variant in ("event", "admission", "plan", "selection", "role", "stage", "head", "attempt",
                        "lifetime", "qualification", "products", "receipt", "unknown-receipt", "checkpoint", "missing"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); files = f["files"]["S01"]
                name = "cold-shared-observation-before.json"
                value = json.loads(files[name])
                for case, field in (("event", "eventBindingSHA256"), ("admission", "admissionSHA256"),
                                    ("plan", "planSHA256"), ("selection", "selectionSHA256")):
                    if variant == case: value[field] = "F" * 64
                if variant == "role": value["role"] = "producer"
                if variant == "stage": value["stage"] = "seal"
                if variant == "head": value["head"] = "f" * 40
                if variant == "attempt": value["runAttempt"] = "2"
                if variant == "lifetime": value["processLifetimes"] = "PROVEN"
                if variant == "qualification": value["providerQualification"] = True
                if variant == "products": value["products"] = None
                if variant == "unknown-receipt": value["receiptSHA256"]["../caller-receipt.json"] = "F" * 64
                files[name] = canonical(value)
                checkpoint = json.loads(files["native-checkpoint.json"])
                checkpoint["coldSharedObservations"]["before"] = value
                if variant == "checkpoint": checkpoint["coldSharedObservations"]["before"]["products"] = []
                files["native-checkpoint.json"] = canonical(checkpoint)
                if variant == "receipt": files["v23-shared-payload.json"] += b"changed packed receipt bytes"
                if variant == "missing": del files[name]
                f["blobs"][21] = zip_bytes(files)
                f["artifacts"][1].update(digest="sha256:" + sha(f["blobs"][21]).lower(), size_in_bytes=len(f["blobs"][21]))
                self.collect_incomplete()
                proof = self.state(f["directory"]); self.assert_pending(proof)
                self.assertTrue(any("worker S01" in problem for problem in proof["problems"]))
                self.assertEqual(f["commands"], [])

    def test_interrupted_raw_continuation_preserves_prefix_controls_attempt_and_same_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.fixture(Path(temporary).resolve())
            prefix = f["payload"][:19]
            original = NEW.phase1_payload_chunks
            def interrupted(identifier):
                if identifier != f["payloadID"]:
                    yield from original(identifier); return
                yield prefix
                raise OSError("synthetic transport interruption")
            with mock.patch.object(NEW, "phase1_payload_chunks", interrupted): self.collect_incomplete()
            first = self.transports(f)[0]; first_bytes = tree_bytes(first)
            receipt = json.loads((first / "receipt.json").read_bytes())
            self.assertEqual((receipt["status"], (first / "raw.zip").read_bytes()), ("PARTIAL", prefix))
            partial = f["directory"] / "cold-collection-partials/000000.json"
            partial_bytes = partial.read_bytes(); self.assert_pending(json.loads(partial_bytes))
            claim_bytes = (f["directory"] / "collector.claim.json").read_bytes()
            attempt_bytes = f["attempt"].read_bytes()
            self.assertFalse((f["directory"] / "manifest.json").exists())
            self.collect_incomplete(resume=True)
            self.assert_pending(self.state(f["directory"]))
            self.assertEqual([p.name for p in self.transports(f)], ["000000", "000001"])
            self.assertEqual(tree_bytes(first), first_bytes)
            self.assertEqual(partial.read_bytes(), partial_bytes)
            self.assertEqual((f["directory"] / "collector.claim.json").read_bytes(), claim_bytes)
            self.assertEqual(f["attempt"].read_bytes(), attempt_bytes)
            self.assertEqual((self.transports(f)[1] / "raw.zip").read_bytes(), f["payload"])
            self.assertEqual(f["commands"], [])

    def test_completed_raw_is_reused_when_only_worker_transport_continues(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.fixture(Path(temporary).resolve()); original = NEW.phase1_payload_chunks
            def interrupted(identifier):
                if identifier == 20: raise OSError("synthetic worker transport")
                yield from original(identifier)
            with mock.patch.object(NEW, "phase1_payload_chunks", interrupted): self.collect_incomplete()
            retained = self.transports(f)[0]; before = tree_bytes(retained)
            claim = (f["directory"] / "collector.claim.json").read_bytes()
            def worker_only(identifier):
                self.assertNotEqual(identifier, f["payloadID"], "completed raw GET repeated")
                yield from original(identifier)
            with mock.patch.object(NEW, "phase1_payload_chunks", worker_only):
                self.collect_incomplete(resume=True)
            self.assertEqual(tree_bytes(retained), before)
            self.assertEqual(len(self.transports(f)), 1)
            self.assertEqual((f["directory"] / "collector.claim.json").read_bytes(), claim)
            self.assert_pending(self.state(f["directory"]))

    def test_first_excess_byte_write_prefix_and_fsync_failure_cannot_seal_a_complete_original(self):
        for variant in ("excess", "write", "fsync"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve()); actual = f["payload"]
                with contextlib.ExitStack() as stack:
                    if variant == "excess":
                        actual = f["payload"][:9]
                        stack.enter_context(mock.patch.object(NEW, "PHASE1_PAYLOAD_MAX_ZIP_BYTES", 8))
                    elif variant == "write":
                        actual = f["payload"][:7]; write = NEW.phase1_payload_write
                        def failed_write(stream, block):
                            write(stream, block[:7]); raise OSError("synthetic write after actual prefix")
                        stack.enter_context(mock.patch.object(NEW, "phase1_payload_write", failed_write))
                    else:
                        stack.enter_context(mock.patch.object(NEW, "phase1_payload_fsync", side_effect=OSError("synthetic raw fsync failure")))
                    self.collect_incomplete()
                proof = self.state(f["directory"]); self.assert_pending(proof)
                retained = self.transports(f)[0]
                receipt = json.loads((retained / "receipt.json").read_bytes())
                self.assertEqual(receipt["status"], {"excess": "BOUND_EXCEEDED", "write": "PARTIAL", "fsync": "DURABILITY_FAILURE"}[variant])
                self.assertEqual((retained / "raw.zip").read_bytes(), actual)
                self.assertEqual(receipt["actualZIPBytes"], len(actual))
                self.assertEqual(receipt["actualZIPSHA256"], sha(actual))
                self.assertFalse((f["directory"] / "manifest.json").exists())
                self.assertEqual(f["commands"], [])

    def test_changed_raw_inode_bytes_claim_or_request_refuses_same_original_resume_without_new_get(self):
        for variant in ("bytes", "inode", "claim", "request"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                f = self.fixture(Path(temporary).resolve())
                original = NEW.phase1_payload_chunks
                def interrupted(identifier):
                    if identifier != f["payloadID"]:
                        yield from original(identifier); return
                    yield f["payload"][:19]; raise OSError("synthetic transport")
                with mock.patch.object(NEW, "phase1_payload_chunks", interrupted): self.collect_incomplete()
                retained = self.transports(f)[0]
                if variant == "bytes": (retained / "raw.zip").write_bytes(b"changed retained prefix")
                if variant == "inode":
                    raw = retained / "raw.zip"; original = raw.read_bytes()
                    raw.rename(f["directory"] / "original-inode.zip"); raw.write_bytes(original)
                if variant == "claim":
                    path = f["directory"] / "collector.claim.json"; value = json.loads(path.read_bytes())
                    value["collectorID"] = "b" * 32; path.write_bytes(canonical(value))
                if variant == "request": (retained / "request.json").write_bytes(b"{}\n")
                before = tree_bytes(retained)
                with mock.patch.object(NEW, "phase1_payload_chunks") as chunks:
                    if variant == "claim":
                        with self.assertRaises(ValueError): NEW.collect(RUN, True)
                    else:
                        self.collect_incomplete(resume=True)
                    chunks.assert_not_called()
                self.assertEqual(tree_bytes(retained), before)
                self.assertFalse((f["directory"] / "manifest.json").exists())


class ColdAttemptLifecycleTests(unittest.TestCase):
    """Actual dispatch reservation and discovery, with remote effects replaced."""
    plan_fixture = ColdOriginalControlBoundaryTests.plan_fixture
    durable_worker_files = ColdOriginalCollectionTests.durable_worker_files
    assert_pending = ColdOriginalCollectionTests.assert_pending
    fixture = ColdOriginalCollectionTests.fixture

    def prepare(self, base):
        f = self.fixture(base)
        shutil.rmtree(NEW.cold_lifecycle_directory(f["gate"], f["plan"]))
        f["attempt"].unlink(); shutil.rmtree(f["directory"])
        NEW.LEDGER.write_bytes(b""); f["runs"].clear()
        path = base / "synthetic-cold-plan.json"; path.write_bytes(f["core"].canonical(f["plan"]))
        f["planPath"] = path; f["requests"] = []
        original_api = NEW.api
        def api(endpoint):
            for status in f["core"].ACTIVE_RUN_STATUSES:
                if endpoint == f"repos/{REPO}/actions/runs?status={status}&per_page={NEW.PAGE_SIZE}&page=1":
                    return {"total_count": 0, "workflow_runs": []}
            return original_api(endpoint)
        def git(*argv):
            self.assertEqual(argv[0], "git")
            if argv[1] in ("fetch", "diff"): return ""
            self.assertEqual(argv[1], "rev-parse")
            if argv[2].endswith("^{tree}"): return f["plan"]["tree"] + "\n"
            return {"HEAD": HEAD, "origin/" + NEW.BRANCH: HEAD,
                    "origin/main": f["core"].BASE_MAIN}[argv[2]] + "\n"
        def process(argv, **kwargs):
            # The actual exclusive reservation must be complete before the sole
            # synthetic remote request, with exact bytes and no inherited stdin.
            consumed = f["core"].decode(f["attempt"].read_bytes(), limit=f["core"].MAX_ATTEMPT_BYTES)
            registration = (base / "v23-cold-plans" / (f["core"].cold_original_stem(f["plan"]) + ".json")).read_bytes()
            f["core"].validate_cold_attempt(consumed, f["plan"], registration)
            self.assertEqual(argv, f["core"].cold_dispatch_argv(f["plan"], 7))
            self.assertEqual(kwargs["input"], f["core"].canonical(f["core"].cold_dispatch_inputs(f["plan"])))
            self.assertIs(kwargs["check"], False)
            f["requests"].append(copy.deepcopy(consumed)); f["runs"].append(f["observed"])
            return subprocess.CompletedProcess(argv, 0, b"synthetic request response", b"")
        stack = contextlib.ExitStack()
        for name, replacement in (("run", git), ("api", api), ("cold_timestamp", lambda: "2026-09-26T12:01:00Z")):
            stack.enter_context(mock.patch.object(NEW, name, replacement))
        stack.enter_context(mock.patch.object(NEW.subprocess, "run", process))
        self.addCleanup(stack.close)
        return f

    def test_actual_cold_dispatch_preconsumes_once_and_discovery_only_continues_same_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.prepare(Path(temporary).resolve())
            record = NEW.dispatch(f["core"].COLD_SELECTION, kind="development", cold_plan=f["planPath"])
            self.assertEqual(len(f["requests"]), 1)
            self.assertEqual((record["runID"], record["kind"], record["status"], record["functionalQualification"]),
                             (RUN, "development", "INCOMPLETE", "PENDING"))
            self.assertIs(record["developmentOnly"], True)
            for key in ("providerQualification", "acceptance", "releaseReady"): self.assertIs(record[key], False)
            consumed = f["attempt"].read_bytes()
            dispatch_bytes = (f["directory"] / "dispatch.json").read_bytes()
            with self.assertRaisesRegex(ValueError, "consumed"):
                NEW.dispatch(f["core"].COLD_SELECTION, kind="development", cold_plan=f["planPath"])
            continued = NEW.cold_original_lifecycle(f["planPath"], kind="development", discover=True)
            self.assertEqual(continued, record)
            self.assertEqual(f["attempt"].read_bytes(), consumed)
            self.assertEqual((f["directory"] / "dispatch.json").read_bytes(), dispatch_bytes)
            self.assertEqual(len(f["requests"]), 1)
            self.assertEqual(NEW.cold_original_context(RUN)[3], f["plan"])

    def test_uncertain_attempt_fsync_never_dispatches_and_retained_consumption_never_retries(self):
        with tempfile.TemporaryDirectory() as temporary:
            f = self.prepare(Path(temporary).resolve()); fsync = f["core"].os.fsync
            def failed(fd):
                if f["attempt"].exists(): raise OSError("synthetic consumed-file fsync uncertainty")
                return fsync(fd)
            with mock.patch.object(f["core"].os, "fsync", failed):
                with self.assertRaises(OSError):
                    NEW.dispatch(f["core"].COLD_SELECTION, kind="development", cold_plan=f["planPath"])
            self.assertEqual(f["requests"], [])
            self.assertTrue(f["attempt"].exists()); consumed = f["attempt"].read_bytes()
            with self.assertRaisesRegex(ValueError, "consumed"):
                NEW.dispatch(f["core"].COLD_SELECTION, kind="development", cold_plan=f["planPath"])
            self.assertEqual(f["attempt"].read_bytes(), consumed)
            self.assertFalse(f["directory"].exists())


# BEGIN LOCAL DEVELOPMENT EVENT TESTS V1
@unittest.skipUnless(sys.platform == "darwin", "local27 real-FD fixtures require the reviewed Darwin route")
class LocalDevelopmentEventTests(unittest.TestCase):
    """Disposable real-FD fixtures; no native, provider, Git or qualification proof."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="local-development-data-")
        self.root = Path(self.temporary.name).resolve()
        self.inputs = self.root / "inputs"; self.inputs.mkdir()
        self.original = self.root / "original"; self.original.mkdir()
        self.source = self.root / "source"; self.source.mkdir()
        self.packets = self.root / "packets"; self.packets.mkdir()
        self.recorded_packets = self.root / "recorded-packets"; self.recorded_packets.mkdir()
        self.evidence = self.root / "evidence"; self.evidence.mkdir()
        self.attempts = self.evidence / "v23-local-development-attempts"; self.attempts.mkdir()
        self.ledger_path = self.evidence / "v23-original-ledger.jsonl"
        self.legacy = canonical({"runID": 42, "head": HEAD, "selection": "legacy", "kind": "gate"})
        self.ledger_path.write_bytes(self.legacy)
        source_map = self.put("source-map.json", {"App.swift": {"sha256": "a" * 64, "bytes": 7, "mode": "0o644"}})
        frozen = self.put("source-freeze.json", {"sourceHEAD": HEAD, "sourceWorktree": str(self.source),
            "allInputs": {key: source_map[key] for key in ("path", "sha256")}})
        policy = self.put("policy.json", {"testOnly": True, "purpose": "synthetic local27 fixture"})
        toolchain = self.put("toolchain.json", {"xcodeVersion": "27.0", "xcodeBuild": "27A266a",
            "sdkVersion": "27.0", "runtimeVersion": "26.2", "runtimeBuild": "23C54"})
        bindings = dict.fromkeys(NEW.LOCAL_ROLES)
        bindings.update(sourceMap=source_map, sourceFreeze=frozen, policy=policy, toolchain=toolchain)
        self.request = {"schema": NEW.LOCAL_REQUEST_SCHEMA, "registrationMode": "prospective",
            "originalKind": "build-for-testing", "originalDirectory": str(self.original), "questionID": "compile-data-v1",
            "head": HEAD, "sourceWorktree": str(self.source), "selectors": [],
            "plannedArgv": ["/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild", "build-for-testing"],
            "bindings": bindings, "registration": None}
        self.patches = contextlib.ExitStack()
        # Only the immutable decision pin is synthetic; all FD/hash/schema logic is genuine.
        self.patches.enter_context(mock.patch.object(NEW, "LOCAL_POLICY_SHA", policy["sha256"]))
        self.patches.enter_context(mock.patch.object(NEW, "LEDGER", self.ledger_path))
        self.patches.enter_context(mock.patch.object(NEW, "now", return_value=FIXED_NOW))
        self.patches.enter_context(mock.patch.object(NEW, "api", side_effect=AssertionError("provider effect")))
        self.patches.enter_context(mock.patch.object(NEW, "run", side_effect=AssertionError("Git/command effect")))
        self.patches.enter_context(mock.patch.object(NEW.subprocess, "run", side_effect=AssertionError("launch effect")))

    def tearDown(self):
        self.patches.close()
        self.temporary.cleanup()

    def ref(self, path):
        raw = path.read_bytes()
        return {"path": str(path), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}

    def put(self, name, value, directory=None):
        path = (directory or self.inputs) / name
        path.write_bytes(NEW.local_canonical(value))
        return self.ref(path)

    def prepare(self, request=None, name="event.json", event="local-development-registered"):
        reference = self.put("request-" + name, request or self.request)
        output = (self.recorded_packets if event == "local-development-recorded" else self.packets) / name
        value = NEW.local_prepare(reference, str(output), event)
        return value, self.ref(output)

    def launch_receipts(self, request, registration=None, result=True):
        request = copy.deepcopy(request)
        command = {"argv": request["plannedArgv"], "atUTC": FIXED_NOW, "cwd": str(self.source)}
        if registration is not None:
            command["localDevelopmentRegistration"] = {key: registration[key] for key in ("path", "sha256")}
        command_ref = self.put("COMMAND.json", command, self.original)
        start = {"pid": 123, "rootPID": 122, "atUTC": FIXED_NOW, "commandSHA256": command_ref["sha256"]}
        request["bindings"].update(command=command_ref, start=self.put("START.json", start, self.original))
        if result:
            request["bindings"]["result"] = self.put("RESULT.json", {"exitCode": 1, "ownedOuterTimedOut": False,
                "sourceHEAD": HEAD, "trackedInputs": {key: request["bindings"]["sourceMap"][key] for key in ("path", "sha256")},
                "command": {key: command_ref[key] for key in ("path", "sha256")}, "runtimeExecuted": False}, self.original)
        request["registration"] = registration
        return request

    def append(self, reference):
        return NEW.local_append(reference, hashlib.sha256(self.ledger_path.read_bytes()).hexdigest())

    def captured_source_request(self, label):
        """Real disposable Source bytes/facts in the current producer's closed row shape."""
        leaf = self.source / "App.swift"
        raw = b"// disposable captured Source fixture\n"
        leaf.write_bytes(raw); leaf.chmod(0o644)
        info = leaf.lstat()
        ten = {key: getattr(info, key) for key in ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid",
            "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns", "st_flags")}
        row = {"bytes": len(raw), "mode": oct(stat.S_IMODE(info.st_mode)),
            "sha256": hashlib.sha256(raw).hexdigest(), "fullTen": ten}
        return self.source_map_request({"App.swift": row}, label), row

    def source_map_request(self, mapping, label):
        request = copy.deepcopy(self.request)
        source_map = self.put(label + "-source-map.json", mapping)
        frozen = self.put(label + "-source-freeze.json", {"sourceHEAD": HEAD,
            "sourceWorktree": str(self.source), "allInputs": source_map})
        request["bindings"].update(sourceMap=source_map, sourceFreeze=frozen)
        return request

    def test_public_local_register_accepts_captured_fullten_rows_and_ref3_without_promotion(self):
        request, row = self.captured_source_request("captured-current")
        request_ref = self.put("captured-current-request.json", request)
        output = self.packets / "captured-current-event.json"
        absent = self.root / "unrelated-current-evidence"
        args = ["v23-original.py", "local-register", "--request", request_ref["path"],
            "--sha256", request_ref["sha256"], "--bytes", str(request_ref["bytes"]), "--output", str(output)]
        with mock.patch.object(NEW, "EVIDENCE", absent), mock.patch.object(sys, "argv", args), \
                contextlib.redirect_stdout(io.StringIO()):
            NEW.main()
        event = NEW.local_json(output.read_bytes())
        self.assertEqual(NEW.local_json(event["requestBytes"].encode()), request)
        self.assertEqual(NEW.local_json(Path(request["bindings"]["sourceMap"]["path"]).read_bytes()), {"App.swift": row})
        self.assertEqual(set(row), {"sha256", "bytes", "mode", "fullTen"})
        self.assertEqual(event["classification"], NEW.LOCAL_CLASSIFICATION)
        self.assertEqual(event["retentionStatus"], "DATA_ONLY_UNQUALIFIED")
        self.assertEqual(event["ledgerStatus"], "PENDING_APPEND")
        self.assertIsNone(event["tupleFacts"]["runtimeExecuted"])
        self.assertFalse(absent.exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_captured_source_fullten_frames_refuse_missing_extra_and_noninteger_fields(self):
        _, row = self.captured_source_request("frame-base")
        variants = []
        missing = copy.deepcopy(row); del missing["fullTen"]["st_size"]; variants.append(("missing-ten", missing))
        extra = copy.deepcopy(row); extra["fullTen"]["unknown"] = 0; variants.append(("extra-ten", extra))
        for label, frame in (("null-ten", None), ("list-ten", []), ("string-ten", "frame")):
            bad = copy.deepcopy(row); bad["fullTen"] = frame; variants.append((label, bad))
        for key in row["fullTen"]:
            bad = copy.deepcopy(row); bad["fullTen"][key] = True; variants.append(("bool-" + key, bad))
        bad = copy.deepcopy(row); bad["fullTen"]["st_mtime_ns"] = 1.0; variants.append(("float-ten", bad))
        bad = copy.deepcopy(row); bad["fullTen"]["st_uid"] = "501"; variants.append(("string-in-ten", bad))
        missing = copy.deepcopy(row); del missing["bytes"]; variants.append(("missing-row", missing))
        extra = copy.deepcopy(row); extra["unknown"] = False; variants.append(("extra-row", extra))
        for label, bad in variants:
            with self.subTest(label=label):
                request = self.source_map_request({"App.swift": bad}, label)
                with self.assertRaises(ValueError): self.prepare(request, label + "-event.json")
                self.assertFalse((self.packets / (label + "-event.json")).exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_captured_source_fullten_requires_regular_singleton_materialized_consistent_rows(self):
        request, row = self.captured_source_request("consistent-base")
        variants = []
        for label, key, value in (("directory", "st_mode", stat.S_IFDIR | 0o644),
                ("fifo", "st_mode", stat.S_IFIFO | 0o644), ("hardlink", "st_nlink", 2),
                ("online-only", "st_flags", 0x40000000), ("mode-mismatch", "st_mode", stat.S_IFREG | 0o600),
                ("length-mismatch", "st_size", row["bytes"] + 1), ("negative-size", "st_size", -1)):
            bad = copy.deepcopy(row); bad["fullTen"][key] = value; variants.append((label, bad))
        for label, key, value in (("bad-sha", "sha256", "G" * 64), ("short-sha", "sha256", "a" * 63),
                ("bool-bytes", "bytes", True), ("negative-bytes", "bytes", -1), ("unsupported-mode", "mode", "0o444")):
            bad = copy.deepcopy(row); bad[key] = value; variants.append((label, bad))
        for label, bad in variants:
            with self.subTest(label=label):
                hostile = self.source_map_request({"App.swift": bad}, label)
                with self.assertRaises(ValueError): self.prepare(hostile, label + "-event.json")
                self.assertFalse((self.packets / (label + "-event.json")).exists())
        for label, key, value in (("wrong-raw-sha", "sha256", "0" * 64),
                ("wrong-raw-length", "bytes", request["bindings"]["sourceMap"]["bytes"] + 1)):
            with self.subTest(label=label):
                hostile = copy.deepcopy(request); hostile["bindings"]["sourceMap"][key] = value
                with self.assertRaises(ValueError): self.prepare(hostile, label + "-event.json")
                self.assertFalse((self.packets / (label + "-event.json")).exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_captured_freeze_ref3_preserves_exact_bytes_path_hash_and_historical_ref2(self):
        request, row = self.captured_source_request("freeze-ref-base")
        reference = request["bindings"]["sourceMap"]
        historical = self.source_map_request({"App.swift": row}, "historical-freeze")
        # The source-map raw bytes are identical despite the distinct fixture path.
        historical["bindings"]["sourceFreeze"] = self.put("historical-freeze-exact.json", {
            "sourceHEAD": HEAD, "sourceWorktree": str(self.source),
            "allInputs": {key: historical["bindings"]["sourceMap"][key] for key in ("path", "sha256")}})
        value, _ = self.prepare(historical, "historical-ref2-event.json")
        self.assertEqual(value["classification"], NEW.LOCAL_CLASSIFICATION)
        variants = []
        for key in ("path", "sha256"):
            bad = dict(reference); del bad[key]; variants.append(("missing-" + key, bad))
        variants.append(("extra", dict(reference, unknown=False)))
        for label, key, val in (("wrong-path", "path", str(self.inputs / "foreign-map.json")),
                ("wrong-sha", "sha256", "0" * 64), ("bool-bytes", "bytes", True),
                ("zero-bytes", "bytes", 0), ("negative-bytes", "bytes", -1),
                ("wrong-bytes", "bytes", reference["bytes"] + 1),
                ("json-cap", "bytes", NEW.LOCAL_JSON_LIMIT + 1), ("raw-cap", "bytes", NEW.LOCAL_LIMIT + 1)):
            bad = dict(reference); bad[key] = val; variants.append((label, bad))
        for label, bad in variants:
            with self.subTest(label=label):
                hostile = copy.deepcopy(request)
                hostile["bindings"]["sourceFreeze"] = self.put(label + "-frozen-ref.json", {
                    "sourceHEAD": HEAD, "sourceWorktree": str(self.source), "allInputs": bad})
                with self.assertRaises(ValueError): self.prepare(hostile, label + "-ref-event.json")
                self.assertFalse((self.packets / (label + "-ref-event.json")).exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_captured_map_support_keeps_historical_rows_declaration_and_control_caps(self):
        _, row = self.captured_source_request("limits-base")
        legacy = {key: row[key] for key in ("sha256", "bytes", "mode")}
        request = self.source_map_request({"App.swift": legacy}, "legacy-row")
        value, _ = self.prepare(request, "legacy-row-event.json")
        self.assertEqual(value["classification"], NEW.LOCAL_CLASSIFICATION)
        # A consistent large historical declaration is DATA, not an allocation or live-file proof.
        large = copy.deepcopy(row); large["bytes"] = large["fullTen"]["st_size"] = 45191672
        request = self.source_map_request({"App.swift": large}, "large-declaration")
        value, _ = self.prepare(request, "large-declaration-event.json")
        self.assertEqual(value["classification"], NEW.LOCAL_CLASSIFICATION)
        for label, mapping in (("empty-map", {}), ("count-cap", {"Source" + str(i) + ".swift": legacy for i in range(10001)})):
            with self.subTest(label=label):
                request = self.source_map_request(mapping, label)
                with self.assertRaises(ValueError): self.prepare(request, label + "-event.json")
                self.assertFalse((self.packets / (label + "-event.json")).exists())
        for label, count in (("json-cap", NEW.LOCAL_JSON_LIMIT + 1), ("raw-cap", NEW.LOCAL_LIMIT + 1)):
            with self.subTest(label=label):
                request = copy.deepcopy(self.request); request["bindings"]["sourceMap"]["bytes"] = count
                with self.assertRaises(ValueError): self.prepare(request, label + "-map-event.json")
                self.assertFalse((self.packets / (label + "-map-event.json")).exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_prepare_is_pending_without_opening_missing_canonical_ledger_or_launching(self):
        self.ledger_path.unlink()
        value, _ = self.prepare()
        self.assertEqual(value["ledgerStatus"], "PENDING_APPEND")
        self.assertFalse(value["classification"]["executionAuthority"])
        self.assertIsNone(value["tupleFacts"]["macOS"])
        self.assertIsNone(value["tupleFacts"]["productsSHA256"])
        self.assertFalse(self.ledger_path.exists())
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_after_fact_failed_original_is_retained_without_backdated_registration(self):
        request = copy.deepcopy(self.request); request["registrationMode"] = "after-the-fact"
        request = self.launch_receipts(request)
        value, reference = self.prepare(request, event="local-development-recorded")
        self.assertEqual(value["recordedAtUTC"], FIXED_NOW)
        self.assertEqual(value["registrationMode"], "after-the-fact")
        self.assertEqual(value["originalIdentity"]["command"], request["bindings"]["command"])
        result = self.append(reference)
        self.assertTrue(result["ledgerAppended"])
        self.assertTrue(self.ledger_path.read_bytes().startswith(self.legacy))
        self.assertFalse(result["classification"]["acceptance"])
        self.assertFalse(result["classification"]["gateQualification"])

    def test_prospective_ledger_reservation_actual_command_and_start_are_required(self):
        registration, reference = self.prepare(name="registration.json")
        self.append(reference)
        request = self.launch_receipts(self.request, reference)
        value, recorded = self.prepare(request, "recorded.json", "local-development-recorded")
        self.append(recorded)
        rows = [json.loads(line) for line in self.ledger_path.read_text().splitlines()]
        self.assertEqual([row.get("event") for row in rows], [None, "local-development-registered", "local-development-recorded"])
        self.assertEqual(rows[1]["questionKey"], rows[2]["questionKey"])
        self.assertEqual(NEW.ledger_dispatches(), [json.loads(self.legacy)])
        self.assertEqual(len(NEW.ledger_events()), 2)
        self.assertFalse(value["classification"]["exactMainVerification"])

    def test_retrospective_and_missing_registration_cannot_masquerade_as_prospective(self):
        for hostile in ("missing", "after-fact", "command", "start"):
            with self.subTest(hostile=hostile):
                self.original = self.root / ("original-" + hostile); self.original.mkdir()
                base = copy.deepcopy(self.request); base["originalDirectory"] = str(self.original)
                _, registration = self.prepare(base, name=hostile + "-reg.json")
                request = self.launch_receipts(base, registration)
                if hostile == "missing": request["registration"] = None
                elif hostile == "after-fact": request["registrationMode"] = "after-the-fact"
                elif hostile == "command":
                    request["bindings"]["command"] = self.put("COMMAND.json", {"argv": request["plannedArgv"]}, self.original)
                else:
                    request["bindings"]["start"] = self.put("START.json", {"pid": 123, "commandSHA256": "f" * 64}, self.original)
                with self.assertRaises(ValueError):
                    self.prepare(request, hostile + "-bad.json", "local-development-recorded")
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_unledgered_reservation_does_not_satisfy_prospective_append(self):
        _, reservation = self.prepare(name="reservation.json")
        request = self.launch_receipts(self.request, reservation)
        _, reference = self.prepare(request, "recorded.json", "local-development-recorded")
        with self.assertRaisesRegex(ValueError, "already be ledgered"):
            self.append(reference)
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_build_native_selection_and_same_head_changed_map_keys_stay_distinct(self):
        first = NEW.local_question_key(self.request)
        native = copy.deepcopy(self.request)
        native.update(originalKind="test-without-building", selectors=["FieldEvidenceAppTests/Example/testReal"])
        native["plannedArgv"] = ["xcodebuild", "test-without-building", "-only-testing:" + native["selectors"][0]]
        self.assertNotEqual(first, NEW.local_question_key(NEW.local_request(native)))
        changed = copy.deepcopy(self.request); changed["bindings"]["sourceMap"]["sha256"] = "b" * 64
        self.assertNotEqual(first, NEW.local_question_key(changed))
        for wrong in (dict(native, selectors=[]), dict(self.request, selectors=native["selectors"])):
            with self.assertRaisesRegex(ValueError, "build/native"):
                NEW.local_request(wrong)

    def test_wrong_result_map_foreign_receipt_parent_and_wrong_toolchain_refuse(self):
        request = self.launch_receipts(dict(self.request, registrationMode="after-the-fact"))
        request["bindings"]["result"] = self.put("RESULT.json", {"exitCode": 0,
            "trackedInputs": {"path": "/foreign/map.json", "sha256": "a" * 64}}, self.original)
        with self.assertRaisesRegex(ValueError, "input-map"):
            self.prepare(request, event="local-development-recorded")
        request["bindings"]["result"] = None
        request["bindings"]["start"] = self.put("foreign-start.json", {"pid": 123})
        with self.assertRaisesRegex(ValueError, "receipt parent"):
            self.prepare(request, event="local-development-recorded")
        bad = copy.deepcopy(self.request)
        bad["originalDirectory"] = str(self.root / "toolchain-future-original")
        bad["bindings"]["toolchain"] = self.put("bad-toolchain.json", {"xcodeVersion": "26.6", "xcodeBuild": "17F113",
            "runtimeVersion": "26.2", "runtimeBuild": "23C54"})
        with self.assertRaisesRegex(ValueError, "local27"):
            self.prepare(bad)

    def test_duplicate_nonfinite_unknown_keys_and_forged_authority_refuse(self):
        for raw in (b'{"x":1,"x":2}', b'{"x":NaN}', b'{"x":Infinity}'):
            with self.assertRaises(ValueError): NEW.local_json(raw)
        bad = dict(self.request, runID=123)
        with self.assertRaisesRegex(ValueError, "closed request"):
            NEW.local_request(bad)
        value, _ = self.prepare()
        for key in ("acceptance", "gateQualification", "executionAuthority", "releaseReady"):
            bad = copy.deepcopy(value); bad["classification"][key] = True
            with self.assertRaisesRegex(ValueError, "classification"):
                NEW.local_event(bad)

    def test_missing_and_wrong_preimage_ledgers_are_not_created_or_repaired(self):
        _, reference = self.prepare()
        original = self.ledger_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "preimage"):
            NEW.local_append(reference, "f" * 64)
        self.assertEqual(self.ledger_path.read_bytes(), original)
        self.ledger_path.unlink()
        with self.assertRaises(FileNotFoundError): self.append_without_read(reference)
        self.assertFalse(self.ledger_path.exists())
        self.assertEqual(list(self.attempts.iterdir()), [])

    def append_without_read(self, reference):
        return NEW.local_append(reference, hashlib.sha256(self.legacy).hexdigest())

    def test_duplicate_and_partial_consumed_keys_refuse_without_ledger_changes(self):
        value, reference = self.prepare()
        claim = self.attempts / (value["questionKey"] + "-" + value["event"] + ".json")
        claim.write_bytes(b"partial original append attempt\n")
        before = self.ledger_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "consumed"):
            self.append(reference)
        self.assertEqual(self.ledger_path.read_bytes(), before)
        self.assertEqual(claim.read_bytes(), b"partial original append attempt\n")

    def test_symlink_hardlink_and_fifo_substitution_are_refused_before_read(self):
        reference = self.request["bindings"]["sourceMap"]
        path = Path(reference["path"]); saved = path.with_suffix(".saved"); path.rename(saved)
        try:
            for kind in ("symlink", "hardlink", "fifo"):
                with self.subTest(kind=kind):
                    if kind == "symlink": path.symlink_to(saved)
                    elif kind == "hardlink": os.link(saved, path)
                    else: os.mkfifo(path)
                    fence = NEW.LocalFence()
                    try:
                        with self.assertRaises(ValueError): NEW.local_read(fence, reference, capture=True)
                    finally:
                        fence.close(); path.unlink()
        finally:
            saved.rename(path)

    def test_open_race_fifo_is_nonblocking_and_registered_before_refusal(self):
        reference = self.request["bindings"]["sourceMap"]
        path = Path(reference["path"]); saved = path.with_suffix(".saved")
        actual_open = os.open
        calls = []
        def racing_open(name, flags, *args, **kwargs):
            if name == path.name and not saved.exists():
                path.rename(saved); os.mkfifo(path)
                calls.append(flags)
            return actual_open(name, flags, *args, **kwargs)
        fence = NEW.LocalFence()
        try:
            with mock.patch.object(NEW.os, "open", side_effect=racing_open):
                with self.assertRaisesRegex(ValueError, "named/held"):
                    NEW.local_read(fence, reference, capture=True)
            self.assertEqual(len(calls), 1)
            self.assertTrue(calls[0] & os.O_NONBLOCK)
            self.assertTrue(calls[0] & os.O_NOFOLLOW)
            self.assertGreater(len(fence.held), 0)
        finally:
            fence.close()
            if saved.exists(): path.unlink(); saved.rename(path)

    def test_ctime_only_input_drift_is_not_resnapshotted(self):
        reference = self.request["bindings"]["sourceMap"]
        fence = NEW.LocalFence()
        try:
            NEW.local_read(fence, reference, capture=True)
            expected = [tuple(item[3]) for item in fence.held]
            path = Path(reference["path"])
            mode = stat.S_IMODE(path.stat().st_mode)
            os.chmod(path, mode ^ stat.S_IXUSR); os.chmod(path, mode)
            current = NEW.local_fact(path.lstat())
            self.assertEqual(current[:8], expected[-1][:8])
            self.assertEqual(current[9], expected[-1][9])
            self.assertNotEqual(current[8], expected[-1][8])
            with self.assertRaisesRegex(ValueError, "initial full facts"):
                fence.check()
            self.assertEqual([tuple(item[3]) for item in fence.held], expected)
        finally: fence.close()

    def test_zero_and_positive_short_reads_and_writes_preserve_exact_bytes(self):
        reference = self.request["bindings"]["sourceMap"]
        actual_read, actual_write = os.read, os.write
        def short_read(fd, count): return actual_read(fd, min(count, 3))
        def short_write(fd, raw): return actual_write(fd, raw[:max(1, len(raw) // 2)])
        with mock.patch.object(NEW.os, "read", side_effect=short_read), \
                mock.patch.object(NEW.os, "write", side_effect=short_write):
            _, event = self.prepare()
            self.assertTrue(self.append(event)["ledgerAppended"])
        empty = self.inputs / "empty"; empty.write_bytes(b"")
        fence = NEW.LocalFence()
        try:
            raw, _ = NEW.local_read(fence, self.ref(empty), capture=True)
            self.assertEqual(raw, b"")
        finally: fence.close()
        bad = dict(reference, bytes=reference["bytes"] - 1)
        fence = NEW.LocalFence()
        try:
            with self.assertRaisesRegex(ValueError, "expected raw size"):
                NEW.local_read(fence, bad, capture=True)
        finally: fence.close()

    def test_zero_append_write_consumes_key_and_never_repairs(self):
        value, reference = self.prepare()
        ledger_ino = self.ledger_path.stat().st_ino
        actual_write = os.write
        def zero_write(fd, raw):
            if os.fstat(fd).st_ino == ledger_ino: return 0
            return actual_write(fd, raw)
        with mock.patch.object(NEW.os, "write", side_effect=zero_write):
            with self.assertRaisesRegex(ValueError, "positive bounded"):
                self.append(reference)
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        claim = self.attempts / (value["questionKey"] + "-" + value["event"] + ".json")
        before = claim.read_bytes()
        with self.assertRaisesRegex(ValueError, "consumed"):
            self.append(reference)
        self.assertEqual(claim.read_bytes(), before)
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_tuple_forgery_duplicate_event_and_original_outputs_refuse(self):
        value, reference = self.prepare()
        bad = copy.deepcopy(value); bad["tupleFacts"]["xcodeVersion"] = "26.6"
        forged = self.put("forged-event.json", bad)
        with self.assertRaisesRegex(ValueError, "derives"):
            self.append(forged)
        self.append(reference)
        before = self.ledger_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "already ledgered"):
            self.append(reference)
        self.assertEqual(self.ledger_path.read_bytes(), before)
        ref = self.put("request-output.json", self.request)
        with self.assertRaisesRegex(ValueError, "cannot modify original"):
            NEW.local_prepare(ref, str(self.original / "bad.json"), "local-development-registered")
        self.assertFalse((self.original / "bad.json").exists())

    def test_public_cli_routes_local_before_generic_evidence_directory_creation(self):
        request = self.put("request-cli.json", self.request)
        args = ["v23-original.py", "local-register", "--request", request["path"], "--sha256", request["sha256"],
                "--bytes", str(request["bytes"]), "--output", str(self.packets / "cli.json")]
        absent = self.root / "unrelated-evidence"
        with mock.patch.object(NEW, "EVIDENCE", absent), mock.patch.object(sys, "argv", args), \
                contextlib.redirect_stdout(io.StringIO()):
            NEW.main()
        self.assertTrue((self.packets / "cli.json").is_file())
        self.assertFalse(absent.exists())

    def test_registration_refuses_existing_launch_receipts_and_supports_absent_original(self):
        request = self.launch_receipts(dict(self.request, registrationMode="after-the-fact"))
        with self.assertRaisesRegex(ValueError, "after launch"):
            self.prepare()
        future = copy.deepcopy(self.request); future["originalDirectory"] = str(self.root / "future-original")
        value, _ = self.prepare(future, "future.json")
        self.assertEqual(value["registrationMode"], "prospective")
        self.assertFalse(Path(future["originalDirectory"]).exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_online_only_canonical_ledger_is_refused_before_open_or_consumption(self):
        _, reference = self.prepare()
        actual_stat, actual_open = os.stat, os.open
        calls = []
        def online_stat(name, *args, **kwargs):
            info = actual_stat(name, *args, **kwargs)
            if name == self.ledger_path.name:
                fields = {key: getattr(info, key) for key in ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid",
                    "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns")}
                return SimpleNamespace(**fields, st_flags=0x40000000)
            return info
        def observed_open(name, *args, **kwargs):
            calls.append(name); return actual_open(name, *args, **kwargs)
        with mock.patch.object(NEW.os, "stat", side_effect=online_stat), \
                mock.patch.object(NEW.os, "open", side_effect=observed_open):
            with self.assertRaisesRegex(ValueError, "online-only"):
                self.append_without_read(reference)
        self.assertNotIn(self.ledger_path.name, calls)
        self.assertEqual(list(self.attempts.iterdir()), [])
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_real_growth_after_first_read_refuses_first_excess_without_output(self):
        reference = self.request["bindings"]["sourceMap"]
        path = Path(reference["path"]); inode = path.stat().st_ino
        actual_read = os.read
        changed = []
        def growing_read(fd, count):
            result = actual_read(fd, count)
            if os.fstat(fd).st_ino == inode and not changed:
                with path.open("ab") as stream: stream.write(b"X")
                changed.append(True)
            return result
        fence = NEW.LocalFence()
        try:
            with mock.patch.object(NEW.os, "read", side_effect=growing_read):
                with self.assertRaisesRegex(ValueError, "first excess"):
                    NEW.local_read(fence, reference, capture=True)
            self.assertEqual(changed, [True])
            self.assertEqual(path.stat().st_size, reference["bytes"] + 1)
        finally: fence.close()

    def test_ledger_fsync_failure_retains_appended_bytes_and_consumed_key_without_retry(self):
        value, reference = self.prepare()
        inode = self.ledger_path.stat().st_ino; actual_fsync = os.fsync
        def failing_fsync(fd):
            if os.fstat(fd).st_ino == inode: raise OSError("synthetic ledger fsync uncertainty")
            return actual_fsync(fd)
        with mock.patch.object(NEW.os, "fsync", side_effect=failing_fsync):
            with self.assertRaisesRegex(OSError, "uncertainty"):
                self.append(reference)
        expected = self.legacy + NEW.local_canonical(value)
        self.assertEqual(self.ledger_path.read_bytes(), expected)
        claim = self.attempts / (value["questionKey"] + "-" + value["event"] + ".json")
        before = claim.read_bytes()
        with self.assertRaisesRegex(ValueError, "already ledgered"):
            self.append(reference)
        self.assertEqual(self.ledger_path.read_bytes(), expected)
        self.assertEqual(claim.read_bytes(), before)

    def test_checked_ledger_close_failure_never_repeats_close_or_claims_success(self):
        value, reference = self.prepare()
        inode = self.ledger_path.stat().st_ino; actual_close = os.close
        closes = []
        def uncertain_close(fd):
            is_ledger = os.fstat(fd).st_ino == inode
            result = actual_close(fd)
            if is_ledger:
                closes.append(fd)
                raise OSError("synthetic checked close uncertainty after actual close")
            return result
        with mock.patch.object(NEW.os, "close", side_effect=uncertain_close):
            with self.assertRaisesRegex(OSError, "checked close"):
                self.append(reference)
        self.assertEqual(len(closes), 1)
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy + NEW.local_canonical(value))
        self.assertTrue((self.attempts / (value["questionKey"] + "-" + value["event"] + ".json")).is_file())

    def test_late_absent_original_creation_refuses_without_new_baseline(self):
        request = copy.deepcopy(self.request); request["originalDirectory"] = str(self.root / "future-original")
        fence = NEW.LocalFence()
        try:
            NEW.local_validate_inputs(fence, request, "local-development-registered")
            expected = [tuple(item[3]) for item in fence.held]
            Path(request["originalDirectory"]).mkdir()
            with self.assertRaises(ValueError): fence.check()
            self.assertEqual([tuple(item[3]) for item in fence.held], expected)
        finally: fence.close()

    def test_actual_native_shape_timeout_and_ordered_selection_remain_unqualified(self):
        request = copy.deepcopy(self.request)
        request.update(registrationMode="after-the-fact", originalKind="test-without-building",
            questionID="native-timeout", selectors=["FieldEvidenceAppTests/Example/testFirst", "FieldEvidenceAppTests/Example/testSecond"])
        request["plannedArgv"] = ["xcodebuild", "test-without-building"] + ["-only-testing:" + x for x in request["selectors"]]
        request = self.launch_receipts(request)
        request["bindings"]["result"] = self.put("RESULT.json", {"questionID": "native-timeout", "exitCode": -15,
            "outerTimedOut": True, "trackedInputSHA256": request["bindings"]["sourceMap"]["sha256"]}, self.original)
        value, reference = self.prepare(request, "native-timeout.json", "local-development-recorded")
        self.assertEqual(value["spec"]["selectors"], request["selectors"])
        self.assertIsNone(value["tupleFacts"]["runtimeExecuted"])
        self.assertEqual(value["retentionStatus"], "DATA_ONLY_UNQUALIFIED")
        self.assertIn("manifest", value["missingRoles"])
        self.assertTrue(self.append(reference)["ledgerAppended"])
        bad = copy.deepcopy(request); bad["selectors"].reverse()
        with self.assertRaisesRegex(ValueError, "ordered argv selection"):
            NEW.local_request(bad)
        self.assertFalse(value["classification"]["gateQualification"])

    def test_empty_ledger_and_boolean_as_integer_authority_are_refused(self):
        value, reference = self.prepare()
        self.ledger_path.write_bytes(b"")
        with self.assertRaisesRegex(ValueError, "must not be empty"):
            NEW.local_append(reference, hashlib.sha256(b"").hexdigest())
        self.assertEqual(self.ledger_path.read_bytes(), b"")
        self.assertEqual(list(self.attempts.iterdir()), [])
        bad = copy.deepcopy(value); bad["classification"]["acceptance"] = 0
        with self.assertRaisesRegex(ValueError, "classification"):
            NEW.local_event(bad)

    def test_writable_fence_uses_readonly_real_ancestors_and_only_writable_regular_leaf(self):
        actual_open = os.open
        calls = []
        def observed_open(name, flags, *args, **kwargs):
            fd = actual_open(name, flags, *args, **kwargs)
            calls.append((name, flags, os.fstat(fd).st_mode))
            return fd
        fence = NEW.LocalFence()
        try:
            with mock.patch.object(NEW.os, "open", side_effect=observed_open):
                leaf = fence.open(self.ledger_path, writable=True)
            self.assertGreater(len(calls), 1)
            for name, flags, mode in calls[:-1]:
                self.assertTrue(stat.S_ISDIR(mode), name)
                self.assertEqual(flags & os.O_ACCMODE, os.O_RDONLY, name)
                self.assertFalse(flags & os.O_APPEND, name)
                self.assertTrue(flags & os.O_DIRECTORY, name)
            self.assertTrue(stat.S_ISREG(calls[-1][2]))
            self.assertEqual(calls[-1][1] & os.O_ACCMODE, os.O_RDWR)
            self.assertTrue(calls[-1][1] & os.O_APPEND)
            self.assertTrue(all(not item[4] for item in fence.held[:-1]))
            self.assertTrue(leaf[4])
            fence.check()
        finally:
            fence.close()

    def test_nested_float_overflow_refuses_before_candidate_or_append_effects(self):
        for spelling in (b"1e999", b"-1e999"):
            with self.subTest(spelling=spelling):
                for raw in (b'{"nested":[{"value":' + spelling + b'}]}',
                            b'[{"deep":{"value":' + spelling + b'}}]'):
                    with self.assertRaisesRegex(ValueError, "nonfinite"):
                        NEW.local_json(raw)
                raw = NEW.local_canonical(self.request)
                raw = raw[:-2] + b',"nested":{"value":' + spelling + b'}}\n'
                path = self.inputs / ("overflow-" + spelling.decode("ascii") + ".json")
                path.write_bytes(raw)
                output = self.packets / ("overflow-" + spelling.decode("ascii") + ".json")
                with self.assertRaisesRegex(ValueError, "nonfinite"):
                    NEW.local_prepare(self.ref(path), str(output), "local-development-registered")
                self.assertFalse(output.exists())
        value, reference = self.prepare(name="finite.json")
        event_raw = NEW.local_canonical(value)
        forged = self.inputs / "overflow-event.json"
        forged.write_bytes(event_raw[:-2] + b',"nested":{"value":1e999}}\n')
        with self.assertRaisesRegex(ValueError, "nonfinite"):
            self.append(self.ref(forged))
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])
        self.assertEqual(NEW.local_json(b'{"nested":[0.5,1e308,-1e308]}'),
                         {"nested": [0.5, 1e308, -1e308]})

    def test_same_spec_second_reservation_cannot_masquerade_as_actual_ledgered_event(self):
        first, first_ref = self.prepare(name="reservation-one.json")
        self.append(first_ref)
        before = self.ledger_path.read_bytes()
        with mock.patch.object(NEW, "now", return_value="2026-09-25T12:00:01+00:00"):
            second, second_ref = self.prepare(name="reservation-two.json")
        self.assertEqual(first["spec"], second["spec"])
        self.assertEqual(first["questionKey"], second["questionKey"])
        self.assertNotEqual(first_ref["sha256"], second_ref["sha256"])
        self.assertNotEqual(first["recordedAtUTC"], second["recordedAtUTC"])
        request = self.launch_receipts(self.request, second_ref)
        _, recorded = self.prepare(request, "recorded-second.json", "local-development-recorded")
        with self.assertRaisesRegex(ValueError, "actual ledgered registration"):
            self.append(recorded)
        self.assertEqual(self.ledger_path.read_bytes(), before)
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy + NEW.local_canonical(first))
        self.assertEqual([path.name for path in self.attempts.iterdir()],
            [first["questionKey"] + "-local-development-registered.json"])

    def test_noncanonical_captured_event_refuses_without_ledger_or_claim_effects(self):
        value, reference = self.prepare(name="canonical-event.json")
        path = self.inputs / "noncanonical-event.json"
        path.write_bytes((json.dumps(value, sort_keys=True, indent=2) + "\n").encode("utf-8"))
        self.assertEqual(NEW.local_json(path.read_bytes()), value)
        self.assertNotEqual(self.ref(path)["sha256"], reference["sha256"])
        with self.assertRaisesRegex(ValueError, "event exact canonical captured bytes"):
            self.append(self.ref(path))
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])

    def test_noncanonical_registration_refuses_before_recorded_candidate_creation(self):
        registration, reference = self.prepare(name="canonical-reservation.json")
        path = self.inputs / "noncanonical-reservation.json"
        path.write_bytes((json.dumps(registration, sort_keys=True, indent=2) + "\n").encode("utf-8"))
        raw_ref = self.ref(path)
        request = self.launch_receipts(self.request, raw_ref)
        output = self.recorded_packets / "noncanonical-reservation-recorded.json"
        with self.assertRaisesRegex(ValueError, "reservation exact canonical captured bytes"):
            self.prepare(request, output.name, "local-development-recorded")
        self.assertFalse(output.exists())
        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
        self.assertEqual(list(self.attempts.iterdir()), [])
        self.assertEqual(NEW.local_json(path.read_bytes()), registration)
        self.assertNotEqual(raw_ref["sha256"], reference["sha256"])

    def test_noncanonical_local_ledger_row_is_not_normalized_into_reservation_authority(self):
        registration, reference = self.prepare(name="local-row-reservation.json")
        self.append(reference)
        request = self.launch_receipts(self.request, reference)
        _, recorded = self.prepare(request, "local-row-recorded.json", "local-development-recorded")
        changed = self.legacy + (json.dumps(registration, sort_keys=True) + "\n").encode("ascii")
        self.assertNotEqual(changed, self.legacy + NEW.local_canonical(registration))
        self.ledger_path.write_bytes(changed)  # Disposable hostile prefix, never a real canonical ledger.
        claims = {path.name: path.read_bytes() for path in self.attempts.iterdir()}
        with self.assertRaisesRegex(ValueError, "local ledger row exact canonical bytes"):
            self.append(recorded)
        self.assertEqual(self.ledger_path.read_bytes(), changed)
        self.assertEqual({path.name: path.read_bytes() for path in self.attempts.iterdir()}, claims)

    def test_actual_allocated_candidate_and_claim_mode_or_replacement_refuse_before_write(self):
        actual_open, actual_close, actual_write = os.open, os.close, os.write
        for role in ("candidate", "claim"):
            for mutation in ("mode", "replacement"):
                with self.subTest(role=role, mutation=mutation):
                    request = copy.deepcopy(self.request)
                    request["questionID"] = "allocated-" + role + "-" + mutation
                    name = role + "-" + mutation + ".json"
                    if role == "candidate":
                        request_ref = self.put("allocation-request-" + name, request)
                        target = self.packets / name
                    else:
                        value, event_ref = self.prepare(request, name)
                        target = self.attempts / (value["questionKey"] + "-" + value["event"] + ".json")
                    created, writes = [], []
                    def hostile_open(path_name, flags, *args, **kwargs):
                        fd = actual_open(path_name, flags, *args, **kwargs)
                        if path_name == target.name and flags & os.O_CREAT and not created:
                            created.append(NEW.local_fact(os.fstat(fd)))
                            if mutation == "mode":
                                os.fchmod(fd, 0o644)
                            else:
                                os.unlink(path_name, dir_fd=kwargs["dir_fd"])
                                replacement = actual_open(path_name, flags, *args, **kwargs)
                                actual_close(replacement)
                        return fd
                    def observed_write(fd, raw):
                        writes.append((fd, len(raw)))
                        return actual_write(fd, raw)
                    with mock.patch.object(NEW.os, "open", side_effect=hostile_open), \
                            mock.patch.object(NEW.os, "write", side_effect=observed_write):
                        with self.assertRaisesRegex(ValueError, "allocated|one link"):
                            if role == "candidate":
                                NEW.local_prepare(request_ref, str(target), "local-development-registered")
                            else:
                                self.append(event_ref)
                    self.assertEqual(len(created), 1)
                    self.assertEqual(writes, [])
                    self.assertTrue(target.is_file())
                    self.assertEqual(target.read_bytes(), b"")
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
                    if mutation == "mode":
                        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o644)
                        self.assertEqual(target.stat().st_ino, created[0][1])
                    else:
                        self.assertNotEqual(target.stat().st_ino, created[0][1])
                    with self.assertRaises((ValueError, FileExistsError)):
                        if role == "candidate":
                            NEW.local_prepare(request_ref, str(target), "local-development-registered")
                        else:
                            self.append(event_ref)
                    self.assertEqual(target.read_bytes(), b"")
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_resulting_ledger_limit_refuses_before_claim_and_exact_boundary_preserves_prefix(self):
        value, reference = self.prepare(name="bounded-event.json")
        expected = self.legacy + NEW.local_canonical(value)
        before = self.ledger_path.read_bytes()
        with mock.patch.object(NEW, "LOCAL_LEDGER_LIMIT", len(expected) - 1):
            with self.assertRaisesRegex(ValueError, "resulting canonical ledger byte bound before claim"):
                self.append(reference)
        self.assertEqual(self.ledger_path.read_bytes(), before)
        self.assertEqual(list(self.attempts.iterdir()), [])
        with mock.patch.object(NEW, "LOCAL_LEDGER_LIMIT", len(expected)):
            result = self.append(reference)
        self.assertTrue(result["ledgerAppended"])
        self.assertEqual(self.ledger_path.read_bytes(), expected)
        self.assertTrue(self.ledger_path.read_bytes().startswith(before))
        self.assertEqual(len(list(self.attempts.iterdir())), 1)

    def test_crlf_registration_row_cannot_mint_canonical_reservation_identity(self):
        registration, reference = self.prepare(name="line-byte-reservation.json")
        self.append(reference)
        request = self.launch_receipts(self.request, reference)
        _, recorded = self.prepare(request, "line-byte-recorded.json", "local-development-recorded")
        canonical_row = NEW.local_canonical(registration)
        actual_row = canonical_row[:-1] + b"\r\n"
        self.assertEqual(NEW.local_json(actual_row), registration)
        self.assertNotEqual(hashlib.sha256(actual_row).hexdigest(), reference["sha256"])
        self.assertEqual(len(actual_row), reference["bytes"] + 1)
        changed = self.legacy + actual_row
        self.ledger_path.write_bytes(changed)  # Only this disposable hostile canonical-ledger fixture.
        claims = {path.name: path.read_bytes() for path in self.attempts.iterdir()}
        with self.assertRaisesRegex(ValueError, "local ledger row exact canonical bytes"):
            self.append(recorded)
        self.assertEqual(self.ledger_path.read_bytes(), changed)
        self.assertEqual({path.name: path.read_bytes() for path in self.attempts.iterdir()}, claims)
        self.assertEqual(len(claims), 1)
        self.assertEqual(Path(reference["path"]).read_bytes(), canonical_row)
        self.assertFalse((self.attempts / (registration["questionKey"] + "-local-development-recorded.json")).exists())
    def parent_projection_operation(self, role, label):
        request = copy.deepcopy(self.request)
        request["questionID"] = "parent-" + role + "-" + label
        name = role + "-" + label + ".json"
        if role == "candidate":
            reference = self.put("request-" + name, request)
            target = self.packets / name
            operation = lambda: NEW.local_prepare(reference, str(target), "local-development-registered")
        else:
            value, reference = self.prepare(request, name)
            target = self.attempts / (value["questionKey"] + "-" + value["event"] + ".json")
            operation = lambda: self.append(reference)
        return target, operation

    def test_candidate_and_claim_preserve_actual_plus_one_creation_parent_through_content(self):
        actual_writer, actual_write, actual_fstat = NEW.local_write_once, os.write, os.fstat
        for role in ("candidate", "claim"):
            with self.subTest(role=role):
                target, operation = self.parent_projection_operation(role, "positive")
                before = NEW.local_fact(target.parent.lstat())
                first_write, returned = [], []
                def observed_write(fd, raw):
                    if target.exists() and actual_fstat(fd).st_ino == target.lstat().st_ino and not first_write:
                        first_write.append(NEW.local_fact(target.parent.lstat()))
                    return actual_write(fd, raw)
                def observed_writer(path, raw):
                    result = actual_writer(path, raw)
                    returned.append(result)
                    return result
                with mock.patch.object(NEW, "local_write_once", side_effect=observed_writer), \
                        mock.patch.object(NEW.os, "write", side_effect=observed_write):
                    result = operation()
                self.assertEqual(len(returned), 1)
                leaf, creation_parent = returned[0]
                self.assertEqual(creation_parent[:5], before[:5])
                self.assertEqual(creation_parent[5], before[5] + 1)
                self.assertEqual(creation_parent[9], before[9])
                self.assertEqual(first_write, [creation_parent])
                self.assertEqual(NEW.local_fact(target.parent.lstat()), creation_parent)
                self.assertEqual(NEW.local_fact(target.lstat()), leaf)
                self.assertEqual(stat.S_IMODE(target.lstat().st_mode), 0o600)
                self.assertEqual(target.lstat().st_nlink, 1)
                if role == "candidate":
                    self.assertEqual(result["ledgerStatus"], "PENDING_APPEND")
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
                else:
                    self.assertTrue(result["ledgerAppended"])
                    self.assertTrue(self.ledger_path.read_bytes().startswith(self.legacy))
                self.assertFalse(result["classification"]["executionAuthority"])

    def test_candidate_and_claim_refuse_wrong_creation_link_delta_before_content(self):
        actual_open, actual_fstat, actual_write = os.open, os.fstat, os.write
        for role in ("candidate", "claim"):
            for delta in (0, 2):
                with self.subTest(role=role, delta=delta):
                    target, operation = self.parent_projection_operation(role, "links-" + str(delta))
                    before = NEW.local_fact(target.parent.lstat())
                    allocated, altered, writes = [], [], []
                    def observed_open(name, flags, *args, **kwargs):
                        fd = actual_open(name, flags, *args, **kwargs)
                        if name == target.name and flags & os.O_CREAT:
                            allocated.append(fd)
                        return fd
                    def wrong_parent_links(fd):
                        info = actual_fstat(fd)
                        if allocated and info.st_ino == before[1] and not altered:
                            real = NEW.local_fact(info)
                            self.assertEqual(real[5], before[5] + 1)
                            altered.append(real)
                            fields = {key: getattr(info, key) for key in ("st_dev", "st_ino", "st_mode",
                                "st_uid", "st_gid", "st_nlink", "st_size", "st_mtime_ns", "st_ctime_ns", "st_flags")}
                            fields["st_nlink"] = before[5] + delta
                            return SimpleNamespace(**fields)
                        return info
                    def observed_write(fd, raw):
                        writes.append(fd)
                        return actual_write(fd, raw)
                    with mock.patch.object(NEW.os, "open", side_effect=observed_open), \
                            mock.patch.object(NEW.os, "fstat", side_effect=wrong_parent_links), \
                            mock.patch.object(NEW.os, "write", side_effect=observed_write):
                        with self.assertRaisesRegex(ValueError, "actual exclusive allocation parent projection"):
                            operation()
                    self.assertEqual(len(allocated), 1)
                    self.assertEqual(len(altered), 1)
                    self.assertEqual(writes, [])
                    self.assertEqual(target.read_bytes(), b"")
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_candidate_and_claim_refuse_foreign_entry_at_exclusive_creation(self):
        actual_open, actual_write = os.open, os.write
        for role in ("candidate", "claim"):
            with self.subTest(role=role):
                target, operation = self.parent_projection_operation(role, "foreign")
                foreign = target.parent / (role + "-foreign-entry")
                created, writes = [], []
                def foreign_open(name, flags, *args, **kwargs):
                    fd = actual_open(name, flags, *args, **kwargs)
                    if name == target.name and flags & os.O_CREAT:
                        created.append(fd)
                        foreign.write_bytes(b"foreign disposable member")
                    return fd
                def observed_write(fd, raw):
                    writes.append(fd)
                    return actual_write(fd, raw)
                with mock.patch.object(NEW.os, "open", side_effect=foreign_open), \
                        mock.patch.object(NEW.os, "write", side_effect=observed_write):
                    with self.assertRaisesRegex(ValueError, "actual exclusive allocation parent projection"):
                        operation()
                self.assertEqual(len(created), 1)
                self.assertEqual(writes, [])
                self.assertEqual(target.read_bytes(), b"")
                self.assertEqual(foreign.read_bytes(), b"foreign disposable member")
                self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_candidate_and_claim_refuse_removed_prior_entry_at_exclusive_creation(self):
        actual_open, actual_write = os.open, os.write
        for role in ("candidate", "claim"):
            with self.subTest(role=role):
                target, operation = self.parent_projection_operation(role, "removed")
                prior = target.parent / (role + "-removed-prior")
                prior.write_bytes(b"old disposable member")
                created, writes = [], []
                def removed_open(name, flags, *args, **kwargs):
                    fd = actual_open(name, flags, *args, **kwargs)
                    if name == target.name and flags & os.O_CREAT:
                        created.append(fd)
                        prior.unlink()
                    return fd
                def observed_write(fd, raw):
                    writes.append(fd)
                    return actual_write(fd, raw)
                with mock.patch.object(NEW.os, "open", side_effect=removed_open), \
                        mock.patch.object(NEW.os, "write", side_effect=observed_write):
                    with self.assertRaisesRegex(ValueError, "actual exclusive allocation parent projection"):
                        operation()
                self.assertEqual(len(created), 1)
                self.assertEqual(writes, [])
                self.assertFalse(prior.exists())
                self.assertEqual(target.read_bytes(), b"")
                self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_candidate_and_claim_refuse_changed_prior_member_full_fact_at_creation(self):
        actual_open, actual_write = os.open, os.write
        for role in ("candidate", "claim"):
            with self.subTest(role=role):
                target, operation = self.parent_projection_operation(role, "prior-fact")
                prior = target.parent / (role + "-changed-prior")
                prior.write_bytes(b"old disposable member")
                original = NEW.local_fact(prior.lstat())
                created, writes = [], []
                def changed_open(name, flags, *args, **kwargs):
                    fd = actual_open(name, flags, *args, **kwargs)
                    if name == target.name and flags & os.O_CREAT:
                        created.append(fd)
                        os.chmod(prior, stat.S_IMODE(original[2]) ^ stat.S_IXUSR)
                    return fd
                def observed_write(fd, raw):
                    writes.append(fd)
                    return actual_write(fd, raw)
                with mock.patch.object(NEW.os, "open", side_effect=changed_open), \
                        mock.patch.object(NEW.os, "write", side_effect=observed_write):
                    with self.assertRaisesRegex(ValueError, "actual exclusive allocation parent projection"):
                        operation()
                self.assertEqual(len(created), 1)
                self.assertEqual(writes, [])
                self.assertNotEqual(NEW.local_fact(prior.lstat()), original)
                self.assertEqual(prior.read_bytes(), b"old disposable member")
                self.assertEqual(target.read_bytes(), b"")
                self.assertEqual(self.ledger_path.read_bytes(), self.legacy)

    def test_candidate_and_claim_refuse_late_parent_ctime_or_mode_after_file_fsync(self):
        actual_fsync, actual_fstat = os.fsync, os.fstat
        for role in ("candidate", "claim"):
            for mutation in ("ctime", "mode"):
                with self.subTest(role=role, mutation=mutation):
                    target, operation = self.parent_projection_operation(role, "late-" + mutation)
                    old_mode = stat.S_IMODE(target.parent.lstat().st_mode)
                    changed = []
                    def late_fsync(fd):
                        result = actual_fsync(fd)
                        if target.exists() and actual_fstat(fd).st_ino == target.lstat().st_ino and not changed:
                            creation = NEW.local_fact(target.parent.lstat())
                            os.chmod(target.parent, old_mode ^ stat.S_IWGRP)
                            if mutation == "ctime":
                                os.chmod(target.parent, old_mode)
                            changed.append((creation, NEW.local_fact(target.parent.lstat())))
                        return result
                    try:
                        with mock.patch.object(NEW.os, "fsync", side_effect=late_fsync):
                            with self.assertRaisesRegex(ValueError, "parent exact proved creation projection"):
                                operation()
                        self.assertEqual(len(changed), 1)
                        if mutation == "ctime":
                            self.assertEqual(changed[0][0][:8], changed[0][1][:8])
                            self.assertEqual(changed[0][0][9], changed[0][1][9])
                            self.assertNotEqual(changed[0][0][8], changed[0][1][8])
                        else:
                            self.assertNotEqual(changed[0][0][2], changed[0][1][2])
                        self.assertGreater(len(target.read_bytes()), 0)
                        self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
                    finally:
                        os.chmod(target.parent, old_mode)

    def test_candidate_and_claim_refuse_late_parent_flags_after_file_fsync(self):
        actual_fsync, actual_fstat = os.fsync, os.fstat
        for role in ("candidate", "claim"):
            with self.subTest(role=role):
                target, operation = self.parent_projection_operation(role, "late-flags")
                old_flags = target.parent.lstat().st_flags
                changed = []
                def late_fsync(fd):
                    result = actual_fsync(fd)
                    if target.exists() and actual_fstat(fd).st_ino == target.lstat().st_ino and not changed:
                        creation = NEW.local_fact(target.parent.lstat())
                        os.chflags(target.parent, old_flags ^ stat.UF_NODUMP)
                        changed.append((creation, NEW.local_fact(target.parent.lstat())))
                    return result
                try:
                    with mock.patch.object(NEW.os, "fsync", side_effect=late_fsync):
                        with self.assertRaisesRegex(ValueError, "parent exact proved creation projection"):
                            operation()
                    self.assertEqual(len(changed), 1)
                    self.assertNotEqual(changed[0][0][9], changed[0][1][9])
                    self.assertGreater(len(target.read_bytes()), 0)
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
                finally:
                    os.chflags(target.parent, old_flags)

    def test_outer_claim_refuses_drift_after_nested_writer_using_original_creation_parent(self):
        actual_writer = NEW.local_write_once
        for mutation in ("ctime", "mode", "flags"):
            with self.subTest(mutation=mutation):
                target, operation = self.parent_projection_operation("claim", "nested-" + mutation)
                original_mode = stat.S_IMODE(target.parent.lstat().st_mode)
                original_flags = target.parent.lstat().st_flags
                nested = []
                def late_nested_writer(path, raw):
                    leaf, creation = actual_writer(path, raw)
                    self.assertEqual(NEW.local_fact(target.parent.lstat()), creation)
                    if mutation == "flags":
                        os.chflags(target.parent, original_flags ^ stat.UF_NODUMP)
                    else:
                        os.chmod(target.parent, original_mode ^ stat.S_IWGRP)
                        if mutation == "ctime":
                            os.chmod(target.parent, original_mode)
                    nested.append((leaf, creation, NEW.local_fact(target.parent.lstat())))
                    return leaf, creation
                try:
                    with mock.patch.object(NEW, "local_write_once", side_effect=late_nested_writer):
                        with self.assertRaisesRegex(ValueError, "attempt directory exact original creation projection"):
                            operation()
                    self.assertEqual(len(nested), 1)
                    self.assertEqual(NEW.local_fact(target.lstat()), nested[0][0])
                    self.assertNotEqual(nested[0][1], nested[0][2])
                    if mutation == "ctime":
                        self.assertEqual(nested[0][1][:8], nested[0][2][:8])
                        self.assertEqual(nested[0][1][9], nested[0][2][9])
                        self.assertNotEqual(nested[0][1][8], nested[0][2][8])
                    self.assertGreater(len(target.read_bytes()), 0)
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
                    retained = target.read_bytes()
                    with self.assertRaisesRegex(ValueError, "consumed/uncertain"):
                        operation()
                    self.assertEqual(target.read_bytes(), retained)
                    self.assertEqual(self.ledger_path.read_bytes(), self.legacy)
                finally:
                    os.chflags(target.parent, original_flags)
                    os.chmod(target.parent, original_mode)

    def test_public_recorded_prepare_refuses_retained_registration_parent_without_mutation(self):
        registration, reference = self.prepare(name="same-parent-registration.json")
        request = self.launch_receipts(self.request, reference)
        request_ref = self.put("same-parent-recorded-request.json", request)
        output = self.packets / "same-parent-recorded.json"
        registration_path = Path(reference["path"])
        input_refs = [request_ref, reference] + [item for item in request["bindings"].values() if item is not None]
        before = {item["path"]: (NEW.local_fact(Path(item["path"]).lstat()), Path(item["path"]).read_bytes())
            for item in input_refs}
        parent = NEW.local_fact(self.packets.lstat())
        members = {path.name: NEW.local_fact(path.lstat()) for path in self.packets.iterdir()}
        ledger = self.ledger_path.read_bytes()
        with self.assertRaisesRegex(ValueError, "output parent must be distinct from retained input directories"):
            NEW.local_prepare(request_ref, str(output), "local-development-recorded")
        self.assertFalse(output.exists())
        self.assertEqual(NEW.local_fact(self.packets.lstat()), parent)
        self.assertEqual({path.name: NEW.local_fact(path.lstat()) for path in self.packets.iterdir()}, members)
        self.assertEqual({item["path"]: (NEW.local_fact(Path(item["path"]).lstat()), Path(item["path"]).read_bytes())
            for item in input_refs}, before)
        self.assertEqual(registration_path.read_bytes(), NEW.local_canonical(registration))
        self.assertEqual(self.ledger_path.read_bytes(), ledger)
        self.assertEqual(list(self.attempts.iterdir()), [])
        self.assertEqual(list(self.recorded_packets.iterdir()), [])

    def test_precreated_recorded_parent_preserves_actual_ledgered_registration_reference_and_input_facts(self):
        self.assertTrue(self.recorded_packets.is_dir())
        self.assertEqual(self.recorded_packets.parent, self.packets.parent)
        self.assertNotEqual(self.recorded_packets, self.packets)
        self.assertEqual(list(self.recorded_packets.iterdir()), [])
        registration, reference = self.prepare(name="separate-parent-registration.json")
        self.append(reference)
        request = self.launch_receipts(self.request, reference)
        request_ref = self.put("separate-parent-recorded-request.json", request)
        output = self.recorded_packets / "separate-parent-recorded.json"
        input_refs = [request_ref, reference] + [item for item in request["bindings"].values() if item is not None]
        before = {item["path"]: (NEW.local_fact(Path(item["path"]).lstat()), Path(item["path"]).read_bytes())
            for item in input_refs}
        registration_parent = NEW.local_fact(self.packets.lstat())
        registration_members = {path.name: NEW.local_fact(path.lstat()) for path in self.packets.iterdir()}
        ledger_before_record = self.ledger_path.read_bytes()
        value = NEW.local_prepare(request_ref, str(output), "local-development-recorded")
        recorded = self.ref(output)
        self.assertEqual(recorded["path"], str(output))
        self.assertEqual(NEW.local_json(value["requestBytes"].encode("utf-8"))["registration"], reference)
        self.assertEqual(NEW.local_json(Path(request["bindings"]["command"]["path"]).read_bytes())
            ["localDevelopmentRegistration"], {key: reference[key] for key in ("path", "sha256")})
        self.assertEqual(NEW.local_fact(self.packets.lstat()), registration_parent)
        self.assertEqual({path.name: NEW.local_fact(path.lstat()) for path in self.packets.iterdir()}, registration_members)
        self.assertEqual({item["path"]: (NEW.local_fact(Path(item["path"]).lstat()), Path(item["path"]).read_bytes())
            for item in input_refs}, before)
        self.assertEqual(self.ledger_path.read_bytes(), ledger_before_record)
        self.assertEqual(ledger_before_record, self.legacy + Path(reference["path"]).read_bytes())
        self.assertEqual(value["ledgerStatus"], "PENDING_APPEND")
        self.assertFalse(value["classification"]["executionAuthority"])
        result = self.append(recorded)
        self.assertTrue(result["ledgerAppended"])
        self.assertEqual(self.ledger_path.read_bytes(), ledger_before_record + NEW.local_canonical(value))
        self.assertEqual(Path(reference["path"]).read_bytes(), NEW.local_canonical(registration))
        self.assertEqual(hashlib.sha256(Path(reference["path"]).read_bytes()).hexdigest(), reference["sha256"])
        self.assertEqual(len(Path(reference["path"]).read_bytes()), reference["bytes"])
        self.assertEqual(NEW.local_fact(self.packets.lstat()), registration_parent)
        self.assertFalse(result["classification"]["acceptance"])
        self.assertFalse(result["classification"]["gateQualification"])

# END LOCAL DEVELOPMENT EVENT TESTS V1

class Phase1PayloadBirthIdentityTests(unittest.TestCase):
    """Disposable files plus explicit synthetic platform/flags/setter observations.

    The real birth helper, raw writes/snapshot and immutable transport predicates
    execute. No OS chflags, API request, hosted original or qualification occurs.
    """
    @contextlib.contextmanager
    def synthetic_birth(self, *, platform="darwin", initial_flags=0x20):
        gate = NEW.phase1_gates()
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary).resolve() / "owned"
            target.mkdir(mode=0o700)
            raw_path = target / "raw.zip"
            with raw_path.open("xb", buffering=0) as stream:
                original_identity = NEW.phase1_payload_identity
                inode = os.fstat(stream.fileno()).st_ino
                state = {"flags": initial_flags, "ctimeDelta": 0, "override": {},
                         "identityCalls": 0, "setterCalls": [], "events": [], "onIdentity": None}
                def identity(info):
                    value = original_identity(info)
                    if info.st_ino == inode and stat.S_ISREG(info.st_mode):
                        state["identityCalls"] += 1
                        if state["onIdentity"] is not None:
                            state["onIdentity"](state["identityCalls"])
                        value["flags"] = state["flags"]
                        value["ctime_ns"] += state["ctimeDelta"]
                        value.update(state["override"])
                    return value
                def setter(path, flags, *, follow_symlinks):
                    self.assertEqual(path, raw_path)
                    self.assertIs(follow_symlinks, False)
                    self.assertEqual(stream.tell(), 0)
                    self.assertEqual(os.fstat(stream.fileno()).st_size, 0)
                    self.assertEqual(flags, initial_flags | 0x40)
                    state["setterCalls"].append((path, flags, follow_symlinks))
                    state["events"].append("setter")
                    state["flags"] = flags
                    state["ctimeDelta"] = 1  # Explicit synthetic allowed metadata effect.
                    return None
                synthetic_os = SimpleNamespace(**vars(NEW.os))
                synthetic_os.chflags = setter
                synthetic_os.supports_follow_symlinks = {setter}
                synthetic_sys = SimpleNamespace(**vars(NEW.sys))
                synthetic_sys.platform = platform
                with mock.patch.object(NEW, "os", synthetic_os), mock.patch.object(NEW, "sys", synthetic_sys), \
                        mock.patch.object(NEW, "phase1_payload_identity", side_effect=identity):
                    yield {"gate": gate, "target": target, "raw": raw_path, "stream": stream, "state": state,
                           "os": synthetic_os, "setter": setter, "identity": identity, "originalIdentity": original_identity}
            self.assertTrue(stream.closed)

    def test_darwin_owned_empty_creation_is_configured_before_first_request_or_chunk(self):
        gate = NEW.phase1_gates()
        payload = b"synthetic bounded outer payload"
        artifact = {"id": 7, "digest": "sha256:" + hashlib.sha256(payload).hexdigest(), "size_in_bytes": 1}
        claim = {"runID": "123", "planSHA256": "A" * 64}
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            state = {"flags": 0x20, "inode": None, "ctimeDelta": 0, "events": [], "setterCalls": []}
            original_identity = NEW.phase1_payload_identity
            original_write = gate.write_immutable
            def identity(info):
                value = original_identity(info)
                if stat.S_ISREG(info.st_mode):
                    if state["inode"] is None:
                        state["inode"] = info.st_ino
                    if info.st_ino == state["inode"]:
                        value["flags"] = state["flags"]
                        value["ctime_ns"] += state["ctimeDelta"]
                return value
            def setter(path, flags, *, follow_symlinks):
                self.assertEqual(path.name, "raw.zip")
                self.assertEqual(path.parent.name, "000000")
                self.assertIs(follow_symlinks, False)
                self.assertEqual(path.stat().st_size, 0)
                self.assertEqual(flags, 0x60)
                self.assertFalse((path.parent / "request.json").exists())
                state["setterCalls"].append((path, flags, follow_symlinks))
                state["flags"], state["ctimeDelta"] = flags, 1
                state["events"].append("setter")
                return None
            def writer(path, raw):
                if path.name == "request.json":
                    self.assertEqual(state["events"], ["setter"])
                    self.assertEqual(json.loads(raw)["initialRawIdentity"]["flags"], 0x60)
                    self.assertEqual(json.loads(raw)["initialRawIdentity"]["size"], 0)
                    state["events"].append("request")
                elif path.name == "receipt.json":
                    self.assertEqual(state["events"], ["setter", "request", "chunk"])
                    state["events"].append("receipt")
                return original_write(path, raw)
            def chunks(identifier):
                self.assertEqual(identifier, artifact["id"])
                self.assertEqual(state["events"], ["setter", "request"])
                request = directory / "phase1-payload-transports/7/000000/request.json"
                self.assertEqual(json.loads(request.read_bytes())["initialRawIdentity"]["flags"], 0x60)
                state["events"].append("chunk")
                yield payload
            synthetic_os = SimpleNamespace(**vars(NEW.os))
            synthetic_os.chflags = setter
            synthetic_os.supports_follow_symlinks = {setter}
            synthetic_sys = SimpleNamespace(**vars(NEW.sys))
            synthetic_sys.platform = "darwin"
            with mock.patch.object(NEW, "os", synthetic_os), mock.patch.object(NEW, "sys", synthetic_sys), \
                    mock.patch.object(NEW, "phase1_payload_identity", side_effect=identity), \
                    mock.patch.object(gate, "write_immutable", side_effect=writer), \
                    mock.patch.object(NEW, "phase1_payload_chunks", side_effect=chunks):
                result = NEW.phase1_retain_payload(gate, directory, artifact, claim, False)
            self.assertEqual(NEW.PHASE1_PAYLOAD_DARWIN_CREATION_FLAG, 0x40)
            self.assertEqual(state["events"], ["setter", "request", "chunk", "receipt"])
            self.assertEqual(len(state["setterCalls"]), 1)
            self.assertEqual(result["transportStatus"], "COMPLETE")
            self.assertEqual(result["rawZIP"]["SHA256"], sha(payload))
            self.assertEqual((directory / result["rawZIP"]["path"]).read_bytes(), payload)
            self.assertEqual(len(list((directory / "phase1-payload-transports/7").iterdir())), 1)

    def test_non_darwin_preserves_all_ten_birth_fields_and_never_uses_setter(self):
        with self.synthetic_birth(platform="linux") as f:
            expected = f["identity"](os.fstat(f["stream"].fileno()))
            f["state"]["identityCalls"] = 0
            actual = NEW.phase1_payload_birth_identity(f["gate"], f["target"], f["raw"], f["stream"])
            self.assertEqual(actual, expected)
            self.assertEqual(len(actual), 10)
            self.assertEqual(f["state"]["setterCalls"], [])
        for field in ("flags", "ctime_ns"):
            with self.subTest(field=field), self.synthetic_birth(platform="linux") as f:
                def drift(call):
                    if call == 3:
                        if field == "flags":
                            f["state"]["flags"] ^= 0x40
                        else:
                            f["state"]["ctimeDelta"] = 1
                f["state"]["onIdentity"] = drift
                with self.assertRaisesRegex(f["gate"].Refused, "payload creation changed unexpected birth fields"):
                    NEW.phase1_payload_birth_identity(f["gate"], f["target"], f["raw"], f["stream"])
                self.assertEqual(f["state"]["setterCalls"], [])

    def test_missing_unsupported_throwing_and_non_none_setters_refuse_without_request(self):
        for role in ("missing", "noncallable", "unsupported", "throwing", "false", "zero", "true", "list"):
            with self.subTest(role=role), self.synthetic_birth() as f:
                invoked = []
                primary = OSError("synthetic setter failure")
                def setter(path, flags, *, follow_symlinks):
                    invoked.append((path, flags, follow_symlinks))
                    if role == "throwing":
                        raise primary
                    return {"false": False, "zero": 0, "true": True, "list": []}.get(role)
                if role == "missing":
                    del f["os"].chflags
                elif role == "noncallable":
                    f["os"].chflags = 7
                else:
                    f["os"].chflags = setter
                f["os"].supports_follow_symlinks = set() if role == "unsupported" else {setter}
                if role == "throwing":
                    with self.assertRaises(OSError) as caught:
                        NEW.phase1_payload_birth_identity(f["gate"], f["target"], f["raw"], f["stream"])
                    self.assertIs(caught.exception, primary)
                else:
                    expected = "payload Darwin creation setter actual return" if role in ("false", "zero", "true", "list") else \
                        "payload supported no-follow Darwin creation interface"
                    with self.assertRaisesRegex(f["gate"].Refused, expected):
                        NEW.phase1_payload_birth_identity(f["gate"], f["target"], f["raw"], f["stream"])
                self.assertEqual(len(invoked), 0 if role in ("missing", "noncallable", "unsupported") else 1)
                self.assertFalse((f["target"] / "request.json").exists())
                self.assertEqual(f["stream"].tell(), 0)

    def test_foreign_nonempty_substituted_or_unowned_births_refuse_before_setter(self):
        for role in ("foreign-path", "nonempty", "nonregular", "multiple-links", "dataless",
                     "named-inode", "public-directory", "foreign-uid", "wrong-stream-mode"):
            with self.subTest(role=role), self.synthetic_birth() as f:
                raw_path, stream = f["raw"], f["stream"]
                original_lstat = Path.lstat
                def named(path):
                    value = original_lstat(path)
                    if role == "named-inode" and path == f["raw"]:
                        fields = {name: getattr(value, name, 0) for name in
                            ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
                             "st_size", "st_mtime_ns", "st_ctime_ns", "st_flags")}
                        fields["st_ino"] += 1
                        return SimpleNamespace(**fields)
                    return value
                if role == "foreign-path":
                    raw_path = f["target"] / "other.zip"
                elif role == "nonempty":
                    f["stream"].write(b"owned test bytes")
                elif role == "nonregular":
                    f["state"]["override"]["mode"] = stat.S_IFDIR | 0o700
                elif role == "multiple-links":
                    f["state"]["override"]["nlink"] = 2
                elif role == "dataless":
                    f["state"]["flags"] |= 0x40000000
                elif role == "public-directory":
                    f["target"].chmod(0o755)
                elif role == "foreign-uid":
                    f["state"]["override"]["uid"] = os.geteuid() + 1
                elif role == "wrong-stream-mode":
                    stream = SimpleNamespace(mode="rb", name=str(raw_path))
                with mock.patch.object(Path, "lstat", new=named), self.assertRaises(f["gate"].Refused):
                    NEW.phase1_payload_birth_identity(f["gate"], f["target"], raw_path, stream)
                self.assertEqual(f["state"]["setterCalls"], [])
                self.assertFalse((f["target"] / "request.json").exists())

    def test_configured_named_held_and_eight_preserved_fields_and_exact_flags_remain_strict(self):
        fields = ("dev", "ino", "mode", "uid", "gid", "nlink", "size", "mtime_ns")
        for field in (*fields, "flags", "configured-named-inode"):
            with self.subTest(field=field), self.synthetic_birth() as f:
                birth = f["identity"](os.fstat(f["stream"].fileno()))
                f["state"]["identityCalls"] = 0
                original_setter = f["setter"]
                original_lstat = Path.lstat
                def setter(path, flags, *, follow_symlinks):
                    result = original_setter(path, flags, follow_symlinks=follow_symlinks)
                    if field == "flags":
                        f["state"]["flags"] ^= 0x80
                    elif field in fields:
                        f["state"]["override"][field] = birth[field] + 1
                    return result
                def named(path):
                    value = original_lstat(path)
                    if field == "configured-named-inode" and f["state"]["setterCalls"] and path == f["raw"]:
                        values = {name: getattr(value, name, 0) for name in
                            ("st_dev", "st_ino", "st_mode", "st_uid", "st_gid", "st_nlink",
                             "st_size", "st_mtime_ns", "st_ctime_ns", "st_flags")}
                        values["st_ino"] += 1
                        return SimpleNamespace(**values)
                    return value
                f["os"].chflags = setter
                f["os"].supports_follow_symlinks = {setter}
                expected = ("payload named/held configured birth" if field == "configured-named-inode" else
                            "payload exact configured creation flags" if field == "flags" else
                            "payload creation changed unexpected birth fields")
                with mock.patch.object(Path, "lstat", new=named), self.assertRaisesRegex(f["gate"].Refused, expected):
                    NEW.phase1_payload_birth_identity(f["gate"], f["target"], f["raw"], f["stream"])
                self.assertEqual(len(f["state"]["setterCalls"]), 1)
                self.assertEqual(f["stream"].tell(), 0)
                self.assertFalse((f["target"] / "request.json").exists())

    def test_every_ancestor_identity_field_stays_bound_after_configured_birth(self):
        for field in ("dev", "ino", "mode", "uid", "gid"):
            with self.subTest(field=field), self.synthetic_birth() as f:
                original = NEW.phase1_payload_ancestors
                calls = []
                def ancestors(gate, path):
                    value = original(gate, path)
                    calls.append(value)
                    if len(calls) == 2:
                        value[str(path)][field] += 1
                    return value
                with mock.patch.object(NEW, "phase1_payload_ancestors", side_effect=ancestors), \
                        self.assertRaisesRegex(f["gate"].Refused, "payload creation ancestor changed"):
                    NEW.phase1_payload_birth_identity(f["gate"], f["target"], f["raw"], f["stream"])
                self.assertEqual(len(calls), 2)
                self.assertEqual(len(f["state"]["setterCalls"]), 1)
                self.assertEqual(f["stream"].tell(), 0)
                self.assertFalse((f["target"] / "request.json").exists())

    def test_late_flags_still_refuse_writing_and_resume_without_replacement_receipt(self):
        gate = NEW.phase1_gates()
        payload = b"first-second"
        artifact = {"id": 9, "digest": "sha256:" + hashlib.sha256(payload).hexdigest(), "size_in_bytes": 1}
        claim = {"runID": "123", "planSHA256": "A" * 64}
        for when in ("writing", "resume"):
            with self.subTest(when=when), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary).resolve()
                state = {"flags": 0, "inode": None, "gets": 0}
                original_identity = NEW.phase1_payload_identity
                def identity(info):
                    value = original_identity(info)
                    if stat.S_ISREG(info.st_mode):
                        if state["inode"] is None:
                            state["inode"] = info.st_ino
                        if info.st_ino == state["inode"]:
                            value["flags"] = state["flags"]
                    return value
                def setter(path, flags, *, follow_symlinks):
                    self.assertIs(follow_symlinks, False)
                    self.assertEqual(path.name, "raw.zip")
                    self.assertEqual(flags, 0x40)
                    state["flags"] = flags
                    return None
                def chunks(identifier):
                    self.assertEqual(identifier, 9)
                    state["gets"] += 1
                    yield payload[:5]
                    if when == "writing":
                        state["flags"] ^= 0x80
                    yield payload[5:]
                synthetic_os = SimpleNamespace(**vars(NEW.os))
                synthetic_os.chflags = setter
                synthetic_os.supports_follow_symlinks = {setter}
                synthetic_sys = SimpleNamespace(**vars(NEW.sys))
                synthetic_sys.platform = "darwin"
                with mock.patch.object(NEW, "os", synthetic_os), mock.patch.object(NEW, "sys", synthetic_sys), \
                        mock.patch.object(NEW, "phase1_payload_identity", side_effect=identity), \
                        mock.patch.object(NEW, "phase1_payload_chunks", side_effect=chunks):
                    if when == "writing":
                        with self.assertRaisesRegex(gate.Refused, "payload raw inode changed while writing"):
                            NEW.phase1_retain_payload(gate, directory, artifact, claim, False)
                        target = directory / "phase1-payload-transports/9/000000"
                        self.assertTrue((target / "request.json").is_file())
                        self.assertFalse((target / "receipt.json").exists())
                    else:
                        result = NEW.phase1_retain_payload(gate, directory, artifact, claim, False)
                        self.assertEqual(result["transportStatus"], "COMPLETE")
                        target = directory / "phase1-payload-transports/9/000000"
                        preserved = {name: (target / name).read_bytes() for name in ("raw.zip", "request.json", "receipt.json")}
                        state["flags"] ^= 0x80
                        with self.assertRaisesRegex(gate.Refused, "payload owned inode substituted"):
                            NEW.phase1_retain_payload(gate, directory, artifact, claim, True)
                        self.assertEqual({name: (target / name).read_bytes() for name in preserved}, preserved)
                    self.assertEqual(state["gets"], 1)
                    self.assertEqual(sorted(path.name for path in target.parent.iterdir()), ["000000"])




class ColdCurrentCensusV2Tests(unittest.TestCase):
    """Actual census/qualifier functions; synthetic Source/API boundaries only.

    Counts describe disposable parser fixtures, never authentic test execution,
    a historical original's qualification, or current app coverage.
    """

    def fixture(self, method_count=3726, partition_count=33):
        identifiers = ["S%02d" % index for index in range(1, partition_count + 1)]
        methods = ["FieldEvidenceAppTests/CensusFixtureTests/testMethod%05d" % index
                   for index in range(method_count)]
        rows, cursor = [], 0
        for index, label in enumerate(identifiers):
            size = method_count // partition_count + (index < method_count % partition_count)
            rows.append({"id": label, "tier": "D50C", "estimatedSeconds": 1,
                         "selectors": methods[cursor:cursor + size]})
            cursor += size
        document = {"schema": "v23-coverage-partitions.v2", "sourceCensusHead": "a" * 40,
                    "generatedAtHead": "b" * 40, "partitions": rows, "sweepOrder": identifiers}
        raw = canonical(document)
        selected = {"tier": NEW.SHARED_PRODUCER_TIER, "unitTestSelectors": methods,
            "sharedCoverage": {"partitionsPath": NEW.SHARED_PARTITIONS_PATH,
                "partitionsSHA256": sha(raw), "partitionIDs": identifiers,
                "partitionID": None, "developmentOnly": True, "acceptance": False}}
        parts = {"partitionsPath": NEW.SHARED_PARTITIONS_PATH, "partitionsSHA256": sha(raw),
                 "partitionIDs": identifiers, "selectors": {row["id"]: row["selectors"] for row in rows}}
        plan = {"selection": NEW.COLD_SELECTION_ID, "head": "c" * 40, "tree": "d" * 40,
                "selectionSHA256": sha(canonical(selected)), "sources": {NEW.SHARED_PARTITIONS_PATH: sha(raw)}}
        return {"gate": NEW.cold_gates(), "plan": plan, "selected": selected,
                "dispatch": {"sharedPartitions": parts}, "committedRaw": raw}

    def committed_bytes(self, f, *args):
        self.assertEqual(args, ("show", f["plan"]["head"] + ":" + NEW.SHARED_PARTITIONS_PATH))
        return f["committedRaw"]

    def census(self, f):
        # Keep the actual shared_partitions function: the independent committed
        # bytes cannot be replaced by a dispatch-supplied expected dictionary.
        with mock.patch.object(NEW, "git_bytes", side_effect=lambda *args: self.committed_bytes(f, *args)):
            return NEW.cold_shared_census_v2(f["gate"], f["plan"], f["dispatch"], f["selected"])

    def rebind_synthetic_claim(self, f):
        # A self-consistent caller hash is deliberately insufficient authority.
        f["plan"]["selectionSHA256"] = sha(canonical(f["selected"]))

    def test_original_3716_current_3726_and_future_additive_census_use_their_committed_source(self):
        for methods, partitions in ((3716, 33), (3726, 33), (3726, 37), (3737, 34)):
            with self.subTest(methods=methods, partitions=partitions):
                f = self.fixture(methods, partitions)
                actual = self.census(f)
                self.assertEqual(actual, f["dispatch"]["sharedPartitions"])
                self.assertEqual(len(actual["partitionIDs"]), partitions)
                self.assertEqual(sum(len(values) for values in actual["selectors"].values()), methods)

    def test_missing_extra_duplicate_and_reordered_consumers_refuse_even_with_rebound_caller_hash(self):
        for variant in ("missing", "extra", "duplicate", "reordered"):
            with self.subTest(variant=variant):
                f = self.fixture()
                parts, selected = f["dispatch"]["sharedPartitions"], f["selected"]
                if variant == "missing":
                    removed = parts["partitionIDs"].pop()
                    del parts["selectors"][removed]
                elif variant == "extra":
                    parts["partitionIDs"].append("S34")
                    parts["selectors"]["S34"] = ["FieldEvidenceAppTests/CensusFixtureTests/testUncommitted"]
                elif variant == "duplicate":
                    parts["partitionIDs"].append(parts["partitionIDs"][0])
                else:
                    parts["partitionIDs"][0], parts["partitionIDs"][1] = parts["partitionIDs"][1], parts["partitionIDs"][0]
                selected["unitTestSelectors"] = [method for label in parts["partitionIDs"]
                                                 for method in parts["selectors"][label]]
                self.rebind_synthetic_claim(f)
                with self.assertRaises((ValueError, SystemExit)):
                    self.census(f)

    def test_missing_extra_duplicate_and_reordered_methods_refuse_even_with_rebound_caller_hash(self):
        for variant in ("missing", "extra", "duplicate", "reordered"):
            with self.subTest(variant=variant):
                f = self.fixture()
                parts = f["dispatch"]["sharedPartitions"]
                methods = parts["selectors"][parts["partitionIDs"][0]]
                if variant == "missing": methods.pop()
                elif variant == "extra": methods.append("FieldEvidenceAppTests/CensusFixtureTests/testUncommitted")
                elif variant == "duplicate": methods.append(methods[0])
                else: methods[0], methods[1] = methods[1], methods[0]
                f["selected"]["unitTestSelectors"] = [method for label in parts["partitionIDs"]
                                                      for method in parts["selectors"][label]]
                self.rebind_synthetic_claim(f)
                with self.assertRaises((ValueError, SystemExit)):
                    self.census(f)

    def test_resolved_digest_dispatch_source_digest_and_frozen_source_digest_drift_refuse(self):
        for variant in ("resolved", "dispatchSource", "frozenSource"):
            with self.subTest(variant=variant):
                f = self.fixture()
                if variant == "resolved": f["selected"]["unitTestSelectors"] = f["selected"]["unitTestSelectors"][:-1]
                elif variant == "dispatchSource": f["dispatch"]["sharedPartitions"]["partitionsSHA256"] = "E" * 64
                else: f["plan"]["sources"][NEW.SHARED_PARTITIONS_PATH] = "E" * 64
                with self.assertRaises((ValueError, SystemExit)):
                    self.census(f)

    def qualification_boundary(self, f, consumer_facts):
        """Stop after the actual archived assessment callback, before publication.

        Authenticated original/runtime readers are mocked boundaries here; this
        fixture must never be confused with their complete authentic evidence.
        The actual committed-census and qualification consumer guards run.
        """
        directory = Path("/synthetic-cold-census-original")
        request_path = Path("/synthetic-cold-census-request.json")
        manifest_raw = canonical({"syntheticTestOnly": True})
        reference = {"path": str(directory / "manifest.json"), "bytes": len(manifest_raw), "SHA256": sha(manifest_raw)}
        request = {"schema": "v23-cold-qualification-assessment-request.v2", "stage": "ASSESS_DATA_ONLY",
            "runID": 123, "head": f["plan"]["head"], "tree": f["plan"]["tree"],
            "manifest": reference, "priorAssessment": None, "independentReview": None}
        labels = f["dispatch"]["sharedPartitions"]["partitionIDs"]
        retained = {label: {"syntheticTestOnly": True, "retainedReadCloseRows": []} for label in labels}
        contract = {"syntheticTestOnly": True}
        data = {"schema": "v23-cold-payload-data-facts.v2", "status": "DATA_ONLY_UNQUALIFIED",
            "v1Data": {"declaredConclusion": "success", "rawProofProblems": [NEW.COLD_PAYLOAD_RECOMPUTATION_NOTE_V1],
                       "sourceSHA256": f["plan"]["sources"]}, "qualificationContract": contract,
            "emittedTransport": {"status": "DATA_BOUND_RECOMPUTED", "consumerFacts": consumer_facts},
            **{key: False for key in ("providerQualification", "acceptance", "gateQualification",
                                     "exactMainVerification", "releaseReady", "executionAuthority")}}
        controls = {request_path: canonical(request), directory / "artifacts.json": canonical({}),
                    directory / "jobs.json": canonical([]),
                    directory / "cold-emitted-retained-facts.json": canonical({"consumerFacts": retained})}
        def read(actual_gate, path, **kwargs):
            self.assertIs(actual_gate, f["gate"])
            return controls[Path(path)]
        class AssessmentBoundaryReached(Exception):
            pass
        def archived(actual_gate, actual_plan, operation):
            self.assertIs(actual_gate, f["gate"])
            self.assertEqual(actual_plan, f["plan"])
            operation(Path("/synthetic-committed-cold-source"))
            raise AssessmentBoundaryReached()
        context = (f["gate"], directory, f["dispatch"], f["plan"], {}, b"", b"", b"", f["selected"])
        with contextlib.ExitStack() as stack:
            for name, replacement in (("cold_gates", lambda: f["gate"]),
                    ("cold_v2_regular_bytes", read), ("cold_original_context", lambda *args: context),
                    ("cold_v2_assessment_inputs", lambda *args: (manifest_raw, canonical({}), {}, {}, {})),
                    ("api", lambda *args: {"status": "completed", "conclusion": "success"}),
                    ("cold_api_original", lambda *args: None), ("phase1_artifact_census", lambda *args: {}),
                    ("paginated", lambda *args: []), ("cold_v2_archived_call", archived),
                    ("cold_v2_source_module", lambda *args: {"qualification_contract_v2": lambda: contract,
                                                            "read_cold_payload_data_v2": lambda *args: data}),
                    ("git_bytes", lambda *args: self.committed_bytes(f, *args))):
                stack.enter_context(mock.patch.object(NEW, name, replacement))
            try:
                NEW.qualify_cold_v2(request_path)
            except AssessmentBoundaryReached:
                return
        self.fail("qualification fixture must stop at the assessment boundary")

    def test_actual_qualifier_accepts_complete_source_bound_consumer_sets_at_each_census(self):
        for methods, partitions in ((3716, 33), (3726, 33), (3726, 37), (3737, 34)):
            with self.subTest(methods=methods, partitions=partitions):
                f = self.fixture(methods, partitions)
                self.qualification_boundary(f, {label: {"syntheticTestOnly": True}
                    for label in f["dispatch"]["sharedPartitions"]["partitionIDs"]})

    def test_actual_qualifier_refuses_missing_extra_and_nonmapping_emitted_consumer_facts(self):
        for variant in ("missing", "extra", "list"):
            with self.subTest(variant=variant):
                f = self.fixture()
                facts = {label: {"syntheticTestOnly": True} for label in f["dispatch"]["sharedPartitions"]["partitionIDs"]}
                if variant == "missing": del facts["S33"]
                elif variant == "extra": facts["S34"] = {"syntheticTestOnly": True}
                else: facts = list(facts)
                with self.assertRaises(ValueError):
                    self.qualification_boundary(f, facts)

    def test_duplicate_emitted_consumer_keys_refuse_at_the_actual_control_decoder(self):
        f = self.fixture()
        with self.assertRaises(ValueError):
            NEW.cold_v2_decode(f["gate"], b'{"consumerFacts":{"S01":{},"S01":{}}}\n')


if __name__ == "__main__":
    unittest.main()
