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
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

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

WORKFLOW_TEXT = ("          - v23-dev-batch-no-index-d50\n          - v23-shared-coverage-d50x\n"
                 "          - c36-round-item-completion-no-index-build30m\n")
DEV = "v23-dev-batch-no-index-d50"
ORDINARY_D30 = "c36-round-item-completion-no-index-build30m"
WORKER_PATH = ".github/workflows/ios-ci-worker.yml"
FIXTURE_DISPATCH = json.loads((FIXTURE / "dispatch.json").read_text(encoding="utf-8"))
FIXTURE_RUN = json.loads((FIXTURE / "run.json").read_text(encoding="utf-8"))
DEV_HEAD, DEV_PARENT = FIXTURE_DISPATCH["head"], FIXTURE_DISPATCH["parent"]
DEV_PLAN = FIXTURE_DISPATCH["resolvedSelection"]
OTHER_HEAD = "e" * 40
TERM = "${{ inputs.native_selection_id == 'v23-dev-batch-no-index-d50' && format('-{0}', github.sha) || '' }}"
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
            "  getmac-shard:\n    if: ${{ inputs.execution_lane == 'getmac-xcode-26.6-development-only' }}\n"
            "    uses: ./.github/workflows/ios-ci-worker.yml\n")


def worker_text(per_head=True, group=None, job_group=None):
    group = group if group is not None else "v23-github-${{ inputs.native_selection_id }}" + (TERM if per_head else "")
    job_concurrency = "" if job_group is None else f"    concurrency:\n      group: {job_group}\n"
    return (f"name: worker\non:\n  workflow_call:\n\nconcurrency:\n  group: {group}\n  cancel-in-progress: false\n\n"
            "jobs:\n  verify:\n    runs-on: macos-26\n" + job_concurrency)


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
            with self.subTest(status):
                harness = DispatchHarness(NEW, self.root, NEW.SHARED_SELECTION_ID,
                                          active=[{"id": 11, "status": status}])
                with self.assertRaises(SystemExit) as caught:
                    harness.dispatch(kind="development")
                self.assertIn("requires zero other active runs", str(caught.exception))
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
        kwargs.setdefault("workers", {WORKER_PATH: worker_text()})
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
                "caller job": {"workflow": caller_text(job_group="dev-${{ github.run_id }} # " + TERM)},
                "worker job": {"workers": {WORKER_PATH: worker_text(job_group="verify-x #" + TERM)}},
                "comment line": {"workflow": caller_text(per_head=False).replace(
                    "\nconcurrency:\n", "\nconcurrency:\n  # group: x" + TERM + "\n")}}.items():
            with self.subTest(label):
                self.assert_parallel_refused(self.harness(**kwargs), "does not include github.sha")

    def test_quoted_and_job_level_groups_with_the_term_are_accepted(self):
        harness = self.harness(workflow=caller_text(group='"v23-${{ inputs.native_selection_id }}' + TERM + '"',
                                                    job_group="dev-" + TERM + "  # per head"),
                               workers={WORKER_PATH: worker_text(job_group="verify-" + TERM)})
        harness.dispatch(kind="development")
        self.assertTrue(harness.dispatched)

    def test_committed_workflows_decide_whether_dev_batches_may_overlap(self):
        caller = read_workflow(NEW.WORKFLOW_PATH)
        jobs = NEW.dev_batch_jobs(caller)
        self.assertEqual({job: worker for job, (_, worker) in jobs.items() if worker}, {"github-shard": WORKER_PATH})
        worker = read_workflow(WORKER_PATH)
        groups = [NEW.concurrency_group(text) for text in (caller, worker)]
        for group in groups:
            self.assertIsNotNone(group)
            self.assertIn("native_selection_id", group)
        harness = self.harness(workflow=caller, workers={WORKER_PATH: worker})
        if all(TERM in group for group in groups):
            harness.dispatch(kind="development")
            self.assertTrue(harness.dispatched)
        else:
            self.assert_parallel_refused(harness, "needs per-head concurrency groups")

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
        self.assertEqual(NEW.DEV_BATCH_PER_HEAD_GROUP_TERM, TERM)


if __name__ == "__main__":
    unittest.main()
