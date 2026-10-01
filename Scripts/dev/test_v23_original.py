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
        # The caller and ordinary worker carry the exact term once; the slim worker names the run.
        worker = read_workflow(WORKER_PATH)
        for text in (caller, worker):
            group = NEW.concurrency_group(text)
            self.assertIn("native_selection_id", group)
            self.assertTrue(group.endswith(TERM), group)
            self.assertEqual(text.count(TERM), 1)
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


if __name__ == "__main__":
    unittest.main()
