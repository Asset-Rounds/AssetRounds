"""Reusable dispatch and sole collection for one V23 GitHub native original.

Owner-approved streamlined route (2026-09-24). It replaces per-run pinned
binder/dispatcher transitions. The committed workflow still enforces the
closed selection, exact parent/trees, budgets and evidence validation.
Checked in as Scripts/dev/v23-original.py; it runs from any checkout of the
repository (Windows or macOS) and resolves the repository root from its path.

Evidence root: $V23_EVIDENCE_ROOT when set (a local path; UNC is refused on
Windows), else C:/AssetRounds-v23-review-evidence on Windows and
~/AssetRounds-v23-review-evidence elsewhere. The ledger
(v23-original-ledger.jsonl), attempt records and per-run evidence live there.

  dispatch --selection ID [--kind development|gate]
                            exact pushed head. An exclusive attempt record is
                            created BEFORE the request, so no failure after it
                            can permit a second original for head+selection.
                            --kind is required for v23-dev-batch-no-index-d50,
                            v23-shared-coverage-d50x and v23-ui-batch-rui1. Other selections
                            defaults to gate. The kind is recorded in the
                            attempt record, dispatch.json and the ledger. A gate
                            original is refused when head+selection already has
                            any original of either kind.
  dispatch --selection ID --kind development --infra-retry-of RUN_ID --reason TEXT
                            development kind only (owner decision 2026-09-25):
                            at most ONE rerun per head+selection, after RUN_ID,
                            the recorded development original there, ended in
                            a collected, terminal failure whose summary proves a
                            setup, artifact or runner cause. Failed or
                            interrupted tests, compile errors, build/test or
                            toolchain-verification step failures, cancellations
                            and heads that have a gate run are never rerun.
  cancel --run RUN_ID --reason TEXT
                            recorded development kind only: an intent ledger
                            record, `gh run cancel` for the active ledgered
                            original, then a completion ledger record. The run
                            is still collected afterwards.
  collect  --run RUN_ID [--resume]
                            sole collector: waits for completion, retains
                            attempt-1 run/job metadata, logs zip and the one
                            named original artifact (digest-checked) with a
                            SHA-256 manifest, then writes summary.json.
  summarize --run RUN_ID    re-derives a summary from retained files only.

Parallel development runs (owner decision 16, 2026-09-25): a development
dispatch passes the workflow input v23_run_kind=development (a gate dispatch
passes nothing and keeps the workflow default, gate, so gate argv and groups are
unchanged); the head's workflow must declare that input. For the two per-head
routes (v23-dev-batch-no-index-d50 and v23-shared-coverage-d50x) the input adds
DEVELOPMENT_PER_HEAD_GROUP_TERM to the caller and worker concurrency groups. A
development original of one of those routes may run beside active development
originals of the SAME route at other heads only when, at the new head, the
ios-ci.yml concurrency group, every job that can run the route and every reusable
worker those jobs call (read from their `uses:`) carry that term, or the per-run
${{ github.run_id }}, outside YAML comments. Gate, unmarked and other-selection
originals keep the any-head refusal.

Shared-build route v23-shared-coverage-d50x (one run: shared-selection, one
build-only producer and one test-only consumer per plan partition):
  dispatch additionally binds the plan to the partitions file at the head. A gate
  (or any non-development) original requires ZERO other active runs (the run can
  occupy every macOS slot) and, while active, refuses every other dispatch. A
  development sweep runs only beside ledgered development runs at OTHER heads
  (their jobs queue for macOS slots; every budget clock starts on the runner),
  never beside a gate, unmarked or unknown run, and never beside any active run of
  its own head; while it is active, only development originals at other heads may
  be dispatched.
  collect paginates jobs and artifacts, retains and extracts the producer and
  every consumer artifact into artifacts/<producer|Sxx>, records the payload
  artifact's id/size/digest WITHOUT downloading it, and summarizes per-partition
  results, the coverage union and the producer/consumer payload bindings. Tests
  that fail never fail collection; integrity problems (a missing artifact of a
  completed job, an artifact digest mismatch, ambiguous job/artifact matching)
  are recorded in manifest.json and summary.json and then exit nonzero.
Every other selection keeps the single-job code path unchanged.

Development evidence only: never acceptance, provider qualification or release.
"""
import collections
import argparse
import datetime
import hashlib
import importlib.util
import io
import json
import os
import re
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import types
import zipfile
from pathlib import Path

REPO = "Asset-Rounds/AssetRounds"
BRANCH = "codex/v23-s10-integration-20260910"
WORKFLOW = "ios-ci.yml"
WORKFLOW_PATH = ".github/workflows/ios-ci.yml"
LANE = "github-xcode-26.6-acceptance"
PROVIDER = "github"
CONTRACT = "v23.integration.current-native.v1"
MAX_ACTIVE = 5
ACTIVE_STATUSES = ("queued", "in_progress", "waiting", "pending", "requested")
EVIDENCE_ROOT_VARIABLE = "V23_EVIDENCE_ROOT"


def evidence_root(environ=os.environ, os_name=os.name):
    """$V23_EVIDENCE_ROOT, else the historical Windows root or ~/AssetRounds-v23-review-evidence."""
    configured = environ.get(EVIDENCE_ROOT_VARIABLE)
    if configured:
        # UNC, device and extended-length roots would break the \\?\ extraction
        # paths and the create-once rename guarantees; require a local drive path.
        if os_name == "nt" and (configured[:2] in ("\\\\", "//", "\\/", "/\\")
                                or os.path.abspath(configured).startswith("\\\\")):
            raise SystemExit(f"{EVIDENCE_ROOT_VARIABLE}={configured!r}: UNC or device paths are not supported "
                             "on Windows; use a local drive path")
        return Path(os.path.abspath(os.path.expanduser(configured)))
    if os_name == "nt":
        return Path("C:/AssetRounds-v23-review-evidence")
    return Path(os.path.expanduser("~/AssetRounds-v23-review-evidence"))


EVIDENCE = evidence_root()
LEDGER = EVIDENCE / "v23-original-ledger.jsonl"
ATTEMPTS = EVIDENCE / "v23-original-attempts"
ROOT = Path(__file__).resolve().parents[2]

# Development routes (owner decision 2026-09-25): infrastructure reruns, cancellation
# and parallel batches. Merge and release gates are unchanged; never acceptance.
DEV_BATCH_SELECTION_ID = "v23-dev-batch-no-index-d50"
# Routes that serve both development sweeps and gates: every dispatch names its kind.
UI_BATCH_SELECTION_ID = "v23-ui-batch-rui1"
KIND_REQUIRED_SELECTIONS = (DEV_BATCH_SELECTION_ID, "v23-shared-coverage-d50x", UI_BATCH_SELECTION_ID)
KINDS = ("development", "gate")
DEVELOPMENT_TIERS = ("D30", "D50", "D40P", "D50C", "D90S")
# Development originals of these routes get per-head concurrency groups (owner decision 16).
PER_HEAD_SELECTIONS = (DEV_BATCH_SELECTION_ID, "v23-shared-coverage-d50x")
# The dispatch input that carries the kind to the workflow; declared with default gate.
RUN_KIND_INPUT = "v23_run_kind"
COMPILER_OBSERVATION_INPUT = "v23_d50_compiler_observation"
SWIFT_DRIVER_JOBS_TWO_INPUT = "v23_d50_swift_driver_jobs_two"
# The exact term the caller group, the route jobs' groups and their workers' groups must
# carry so that development originals at different heads get different groups. It reads
# the dispatch event (a called worker sees its caller's event), so a gate dispatch and
# every other selection evaluate it to ''.
DEVELOPMENT_PER_HEAD_GROUP_TERM = (
    "${{ github.event.inputs." + RUN_KIND_INPUT + " == 'development' && ("
    + " || ".join("github.event.inputs.native_selection_id == '%s'" % x for x in PER_HEAD_SELECTIONS)
    + ") && format('-development-{0}', github.sha) || '' }}")
# A group that names the run is unique per run, which is at least per head.
PER_RUN_GROUP_TERM = "${{ github.run_id }}"
MAX_REASON = 1000
# Infrastructure classification of the first failing step of each failing job.
TEST_STEP = "Run targeted tests"
NON_FAILING_STEP = ("success", "skipped", "neutral")
# "Verify pinned toolchain, shared scheme, and simulator" is deliberately absent:
# it also checks the project, scheme, Scripts files and `xcodebuild -list`, so its
# failure can reproduce from source, and its log does not identify a runner cause.
INFRA_SETUP_STEPS = frozenset({
    "Set up job", "Prepare evidence directory", "Check out the exact revision",
    "Verify setup budget before build",
    "Boot selected Simulator", "Await selected Simulator boot", "Download V23 shared coverage payload",
    "Recheck setup budget after V23 shared payload restore"})
INFRA_ARTIFACT_STEPS = frozenset({"Upload build evidence", "Upload V23 shared coverage payload"})
INFRA_RUNNER_STEPS = frozenset({"Remove owned isolated Simulator", "Post Check out the exact revision",
                                "Complete job"})

# Shared-build route, bound to the committed route source (b215af48): the
# producer/consumer job names come from ios-ci.yml (reusable caller name +
# " / verify"), the artifact names from the worker's upload-name expression.
SHARED_SELECTION_ID = "v23-shared-coverage-d50x"
SHARED_PARTITIONS_PATH = "Scripts/v23-coverage-partitions.json"
SHARED_PRODUCER_TIER = "D40P"
SHARED_MAX_PARTITIONS = 60
SHARED_MAX_PARTITION_METHODS = 500
SHARED_PARTITION_ID = re.compile(r"S[0-9]{2}")
SHARED_SELECTION_JOB = "Validate shared build selection and dependencies"
SHARED_PRODUCER_JOB = "V23 shared coverage producer \u00b7 build-for-testing (development only) / verify"
SHARED_CONSUMER_PREFIX = "V23 shared coverage consumer"
SHARED_CONSUMER_JOB = re.compile(r"V23 shared coverage consumer \u00b7 (S[0-9]{2}) \(development only\) / verify")
SHARED_MAX_JOBS = 500          # bound for paginated jobs.json (5 pages of 100)
SHARED_MAX_ARTIFACTS = 200     # bound for paginated artifacts.json (2 pages of 100)
PAGE_SIZE = 100
SHARED_BUILD_STEP = "Build unsigned simulator app"
SHARED_TEST_STEP = "Run targeted tests"
SHARED_RESTORE_STEP = "Verify and restore V23 shared coverage payload"
SHARED_UPLOAD_STEP = "Upload build evidence"
SHARED_PAYLOAD_UPLOAD_STEP = "Upload V23 shared coverage payload"
SHARED_BUILD_EVIDENCE = ("Build.xcresult", "build-smoke.log", "no-index-build-command.json")
SHARED_TEST_EVIDENCE = ("test-smoke.log", "UnitTests.xcresult", "unit-test-results.json")
SHARED_DELTA = "v23-shared-deriveddata-delta.json"
SHARED_DELTA_LISTED = 20
FINGERPRINT_PRODUCT_KEYS = ("productsTreeSHA256", "xctestrunSHA256", "entryCount")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def run(*argv):
    return subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, check=True,
                          encoding="utf-8", errors="replace").stdout


def retried(action, attempts=4):
    """Bounded retry for transient gh/API failures after the original exists."""
    for index in range(attempts):
        try:
            return action()
        except subprocess.CalledProcessError:
            if index == attempts - 1:
                raise
            time.sleep(15 * (index + 1))


def api(path):
    return json.loads(retried(lambda: run("gh", "api", path)))


def api_bytes(path):
    return retried(lambda: subprocess.run(["gh", "api", path], cwd=ROOT, capture_output=True,
                                          check=True).stdout)


def sha256(data):
    return hashlib.sha256(data).hexdigest().upper()


def write_new(path, value):
    """Evidence is written once; an existing record is never replaced."""
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def ledger():
    if not LEDGER.exists():
        return []
    return [json.loads(line) for line in LEDGER.read_text(encoding="utf-8").splitlines() if line.strip()]


def ledger_dispatches():
    """One line per dispatched original; action events carry an "event" key."""
    return [x for x in ledger() if "event" not in x]


def ledger_events():
    return [x for x in ledger() if "event" in x]


def append_ledger(entry):
    with LEDGER.open("a", encoding="utf-8", newline="\n") as stream:
        stream.write(json.dumps(entry, sort_keys=True) + "\n")


def development_route(selection, resolved):
    """True only for a development route whose resolved selection says so.

    The named routes must carry their developmentOnly/acceptance binding. Any
    other selection qualifies only when it or its binding declares
    developmentOnly: true (acceptance: false alone never counts), with a
    development tier, and nothing in it claims acceptance."""
    if not isinstance(resolved, dict) or (resolved.get("tier") not in DEVELOPMENT_TIERS
            and not (selection == UI_BATCH_SELECTION_ID and resolved.get("tier") == "RUI1")):
        return False
    bindings = [resolved] + [resolved[key] for key in ("devBatch", "sharedCoverage", "uiBatch")
                             if isinstance(resolved.get(key), dict)]
    if any(b.get("acceptance") is True or b.get("developmentOnly") is False for b in bindings):
        return False
    named = {DEV_BATCH_SELECTION_ID: "devBatch", SHARED_SELECTION_ID: "sharedCoverage",
             UI_BATCH_SELECTION_ID: "uiBatch"}
    if selection in named:
        binding = resolved.get(named[selection])
        return (isinstance(binding, dict) and binding.get("developmentOnly") is True
                and binding.get("acceptance") is False)
    return any(b.get("developmentOnly") is True for b in bindings)


def run_kind(selection, kind):
    """The declared run kind: required for the dual-use routes, else gate by default."""
    if kind is None:
        if selection in KIND_REQUIRED_SELECTIONS:
            raise SystemExit(f"--kind development|gate is required for {selection}: it serves both "
                             "development sweeps and gates")
        return "gate"
    if kind not in KINDS:
        raise SystemExit(f"--kind must be one of {KINDS}, not {kind!r}")
    return kind


def recorded_development(run_id):
    """(dispatch record, None) when RUN_ID is recorded as development in its ledger line
    and dispatch.json, else (record or None, why not). Unmarked runs are never development."""
    lines = [x for x in ledger_dispatches() if x.get("runID") == run_id]
    if len(lines) != 1:
        return None, f"run {run_id} is not a ledgered original"
    path = EVIDENCE / str(run_id) / "dispatch.json"
    if not path.is_file():
        return None, f"run {run_id} has no retained dispatch record"
    dispatched = json.loads(path.read_text(encoding="utf-8"))
    if any(key.startswith("phase1") for record in (lines[0], dispatched) for key in record):
        return dispatched, "Phase1 original intent is never development and cannot be cancelled or rerun"
    if ATTEMPTS.exists() and any((ATTEMPTS / (str(dispatched.get("head")) + "-" + purpose + "-"
            + str(dispatched.get("selection")) + ".json")).exists()
            for purpose in ("phase1-candidate-functional-v1", "phase1-exact-main-functional-v1")):
        return dispatched, "Phase1 consumed attempt cannot masquerade as a development original"
    kinds = (lines[0].get("kind"), dispatched.get("kind"))
    if kinds != ("development", "development"):
        return dispatched, (f"run {run_id} is not recorded as a development run (ledger/dispatch kind {kinds}); "
                            "gate, historical and unmarked runs are never cancelled or rerun")
    if not development_route(dispatched.get("selection"), dispatched.get("resolvedSelection")):
        return dispatched, f"run {run_id} was not dispatched as a development route"
    return dispatched, None


def yaml_scalar(raw):
    """A one-line YAML scalar without its comment; None when it cannot be read safely."""
    raw = raw.strip()
    if raw.startswith("'"):
        match = re.fullmatch(r"'((?:[^']|'')*)'\s*(?:#.*)?", raw)
        return match.group(1).replace("''", "'") if match else None
    if raw.startswith('"'):
        match = re.fullmatch(r'"((?:[^"\\]|\\.)*)"\s*(?:#.*)?', raw)
        return match.group(1) if match else None
    if not raw or raw.startswith(("|", ">", "#")):
        return None  # block scalars and empty values are not read
    return re.split(r"\s#", raw, maxsplit=1)[0].rstrip()


def concurrency_groups(text, indent):
    """Group expressions of every `concurrency:` key at this indentation (None if unreadable)."""
    lines = text.replace("\r\n", "\n").split("\n")
    pad, groups = " " * indent, []
    for index, line in enumerate(lines):
        match = re.fullmatch(re.escape(pad) + r"concurrency:(.*)", line)
        if not match:
            continue
        inline = match.group(1).strip()
        if inline and not inline.startswith("#"):
            groups.append(yaml_scalar(inline))  # shorthand: `concurrency: <group>`
            continue
        found = []
        for inner in lines[index + 1:]:
            if not inner.strip() or inner.lstrip().startswith("#"):
                continue
            if len(inner) - len(inner.lstrip(" ")) <= indent:
                break
            key = re.fullmatch(re.escape(pad) + r"  group:(.*)", inner)
            if key:
                found.append(yaml_scalar(key.group(1)))
        groups.append(found[0] if len(found) == 1 else None)
    return groups


def concurrency_group(text):
    """The single top-level concurrency group expression of a workflow, else None."""
    groups = concurrency_groups(text, 0)
    return groups[0] if len(groups) == 1 else None


def workflow_jobs(text):
    """{job id: job text} of the top-level `jobs:` mapping."""
    lines = text.replace("\r\n", "\n").split("\n")
    starts = [index for index, line in enumerate(lines) if re.fullmatch(r"jobs:\s*(?:#.*)?", line)]
    if len(starts) != 1:
        return {}
    jobs, current = {}, None
    for line in lines[starts[0] + 1:]:
        key = re.fullmatch(r"  ([A-Za-z_][A-Za-z0-9_-]*):\s*(?:#.*)?", line)
        if key:
            current = key.group(1)
            jobs[current] = []
        elif line and not line.startswith((" ", "#")):
            break
        elif current is not None:
            jobs[current].append(line)
    return {job: "\n".join(body) for job, body in jobs.items()}


def route_jobs(caller_text, selection):
    """{job: (job text, local reusable workflow path, "" or None)} for every caller job that can
    run SELECTION on LANE. A job is excluded only when its `if:` provably excludes it:
    it names execution lanes but not LANE, pins another selection, or excludes this one.
    The worker path is read from the job's `uses:`; "" marks an unreadable or non-local call."""
    found = {}
    for job, text in workflow_jobs(caller_text).items():
        condition = " ".join(yaml_scalar(x) or "" for x in re.findall(r"^    if:(.*)$", text, re.M))
        if "inputs.execution_lane" in condition and f"'{LANE}'" not in condition:
            continue
        if any(x != selection for x in re.findall(r"native_selection_id == '([^']+)'", condition)):
            continue
        if f"native_selection_id != '{selection}'" in condition:
            continue
        uses = [yaml_scalar(x) for x in re.findall(r"^    uses:(.*)$", text, re.M)]
        worker = None
        if uses:
            worker = uses[0][2:] if len(uses) == 1 and uses[0] and uses[0].startswith("./") else ""
        found[job] = (text, worker)
    return found


def per_head_group(group):
    """True when a group expression separates development originals of different heads."""
    return group is not None and (DEVELOPMENT_PER_HEAD_GROUP_TERM in group or PER_RUN_GROUP_TERM in group)


def per_head_concurrency_problems(head, caller_text, selection=DEV_BATCH_SELECTION_ID):
    """Why development originals of SELECTION at different heads would share a caller, job or
    worker concurrency group."""
    problems = []
    group = concurrency_group(caller_text)
    if group is None:
        problems.append(f"{WORKFLOW_PATH} has no single readable top-level concurrency group")
    elif not per_head_group(group):
        problems.append(f"{WORKFLOW_PATH} concurrency group does not include github.sha for {selection}")
    workers = set()
    for job, (text, worker) in sorted(route_jobs(caller_text, selection).items()):
        if not all(per_head_group(g) for g in concurrency_groups(text, 4)):
            problems.append(f"{WORKFLOW_PATH} job {job} concurrency group does not include github.sha "
                            f"for {selection}")
        if worker == "":
            problems.append(f"{WORKFLOW_PATH} job {job} calls a workflow that is not a readable local path")
        elif worker:
            workers.add(worker)
    if not workers:
        problems.append(f"{WORKFLOW_PATH} has no job that calls a worker for {selection} on {LANE}")
    for path in sorted(workers):
        text = git_bytes("show", f"{head}:{path}").decode("utf-8")
        group = concurrency_group(text)
        if group is None:
            problems.append(f"{path} has no single readable top-level concurrency group")
        elif not per_head_group(group):
            problems.append(f"{path} concurrency group does not include github.sha for {selection}")
        if not all(per_head_group(g) for g in concurrency_groups(text, 4)):
            problems.append(f"{path} job concurrency group does not include github.sha for {selection}")
    return problems


def dispatch_input_lines(text, name):
    """The body lines of one workflow_dispatch input (a unique 6-space key), else None."""
    lines = text.replace("\r\n", "\n").split("\n")
    starts = [index for index, line in enumerate(lines)
              if re.fullmatch("      " + re.escape(name) + r":\s*(?:#.*)?", line)]
    if len(starts) != 1:
        return None
    body = []
    for line in lines[starts[0] + 1:]:
        if line.strip() and not line.lstrip().startswith("#") and len(line) - len(line.lstrip(" ")) <= 6:
            break
        body.append(line)
    return body


def run_kind_input_declared(text):
    """True when the workflow declares the kind input: a choice of exactly the kinds, default gate."""
    body = dispatch_input_lines(text, RUN_KIND_INPUT)
    if body is None:
        return False
    keys = {}
    for line in body:
        match = re.fullmatch(r"        ([A-Za-z_-]+):(.*)", line)
        if match:
            keys[match.group(1)] = yaml_scalar(match.group(2))
    options = [yaml_scalar(match.group(1)) for match in (re.fullmatch(r"          - (.*)", line) for line in body)
               if match]
    return (keys.get("type") == "choice" and keys.get("default") == "gate" and "options" in keys
            and sorted(options) == sorted(KINDS))


def default_false_boolean_input_declared(text, name):
    """An experiment opt-in must be a default-false boolean on the dispatched workflow."""
    body = dispatch_input_lines(text, name)
    if body is None:
        return False
    keys = {}
    for line in body:
        match = re.fullmatch(r"        ([A-Za-z_-]+):(.*)", line)
        if match:
            keys[match.group(1)] = yaml_scalar(match.group(2))
    return keys.get("type") == "boolean" and keys.get("default") == "false"


def compiler_observation_input_declared(text):
    return default_false_boolean_input_declared(text, COMPILER_OBSERVATION_INPUT)


def runs_for(head):
    return api(f"repos/{REPO}/actions/runs?head_sha={head}&per_page=100")["workflow_runs"]


def resolve_selection(head, selection):
    """Resolve the closed selection with the committed resolver at the exact head."""
    with tempfile.TemporaryDirectory(prefix="v23-select-") as directory:
        tree = subprocess.run(["git", "archive", "--format=tar", head], cwd=ROOT, capture_output=True,
                              check=True).stdout
        with tarfile.open(fileobj=io.BytesIO(tree)) as archive:
            archive.extractall(directory, filter="data")
        output = Path(directory) / "selected.json"
        environment = dict(os.environ, GITHUB_WORKSPACE=directory, NATIVE_SELECTION_ID=selection,
                           CI_NATIVE_ACCEPTANCE_CONTRACT=CONTRACT)
        subprocess.run([sys.executable, "-B", "Scripts/v23-native-ci.py", "select", "--output", str(output)],
                       cwd=directory, env=environment, check=True)
        data = output.read_bytes()
    return json.loads(data), sha256(data)


def git_bytes(*argv):
    return subprocess.run(["git", *argv], cwd=ROOT, capture_output=True, check=True).stdout


def preflight_compiler_observation_source(head, resolved_sha, swift_driver_jobs_two):
    """Refuse a source-pinned experiment before any attempt or workflow effect."""
    timing_relative = "Scripts/v23-compiler-timing.py"
    timing_path = ROOT / timing_relative
    try:
        # The dispatcher must not trust an uncommitted local admission function.
        committed_timing = git_bytes("show", f"{head}:{timing_relative}")
        if timing_path.read_bytes() != committed_timing:
            raise ValueError("dirty observer admission code")
        timing = types.ModuleType("v23_compiler_timing_dispatch")
        exec(compile(committed_timing, str(timing_path), "exec"), timing.__dict__)
        git = lambda *args: git_bytes(*args)
        name = timing.development_configuration_name(swift_driver_jobs_two, git)
        profile_relative = "Scripts/" + name
        profile_path = ROOT / profile_relative
        committed_profile = git_bytes("show", f"{head}:{profile_relative}")
        if profile_path.read_bytes() != committed_profile:
            raise ValueError("dirty observer source profile")
        profile = timing.validate_configuration(json.loads(
            committed_profile.decode("utf-8"), object_pairs_hook=timing.unique_pairs))
        if swift_driver_jobs_two != (profile["schemaVersion"] in (8, 9)):
            raise ValueError("wrong experiment profile")
        selected = git_bytes("show", f"{head}:Scripts/ci-selection.json")
        mapping = git_bytes("show", f"{head}:Scripts/ci-selection-map.json")
        timing.admit_development_source(
            profile, git, selected, mapping, resolved_sha, expected_head=head)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        # Do not serialize a local path or subprocess command into an evidence record.
        raise SystemExit("compiler observation source preflight refused") from error


def shared_partitions(head, plan):
    """Bind the resolved plan to the exact partitions file at the head.

    The committed resolver already validated the file against the checkout's
    runnable methods; this records the per-partition lists the collector needs
    and refuses a plan that is not the producer plan of exactly this file."""
    raw = git_bytes("show", f"{head}:{SHARED_PARTITIONS_PATH}")
    value = json.loads(raw.decode("utf-8"))
    binding = plan.get("sharedCoverage")
    problems = []
    if not isinstance(binding, dict):
        raise SystemExit("shared plan has no sharedCoverage binding")
    identifiers = binding.get("partitionIDs")
    if (plan.get("tier") != SHARED_PRODUCER_TIER or binding.get("partitionID") is not None
            or binding.get("developmentOnly") is not True or binding.get("acceptance") is not False
            or binding.get("partitionsPath") != SHARED_PARTITIONS_PATH):
        problems.append("resolved selection is not the development-only producer plan")
    if binding.get("partitionsSHA256") != sha256(raw):
        problems.append("partitions file digest differs from the plan binding")
    if (not isinstance(identifiers, list) or not 1 <= len(identifiers) <= SHARED_MAX_PARTITIONS
            or len(set(identifiers)) != len(identifiers)
            or not all(isinstance(x, str) and SHARED_PARTITION_ID.fullmatch(x) for x in identifiers)):
        raise SystemExit(f"shared plan partition IDs are invalid: {problems}")
    by_id = {p.get("id"): p.get("selectors") for p in value.get("partitions", [])}
    if value.get("sweepOrder") != identifiers or set(by_id) != set(identifiers) \
            or len(value.get("partitions", [])) != len(identifiers):
        problems.append("partition IDs/sweep order differ from the plan binding")
    else:
        if not all(isinstance(s, list) and 1 <= len(s) <= SHARED_MAX_PARTITION_METHODS for s in by_id.values()):
            problems.append("a partition has an out-of-bounds method count")
        ordered = [s for identifier in identifiers for s in by_id[identifier]]
        if ordered != plan.get("unitTestSelectors") or len(set(ordered)) != len(ordered):
            problems.append("plan selectors are not the disjoint sweep-order union of the partitions")
    if problems:
        raise SystemExit("shared plan binding refused: " + "; ".join(problems))
    return {"partitionsPath": SHARED_PARTITIONS_PATH, "partitionsSHA256": binding["partitionsSHA256"],
            "partitionIDs": list(identifiers), "selectors": {x: list(by_id[x]) for x in identifiers}}


def infra_failure_classification(summary, jobs, run_id, head, selection):
    """(refusals, causes) for an infrastructure rerun of one collected original.

    Fail closed. Failed or interrupted tests, compile errors and any run that did
    not conclude "failure" refuse. Each failing job's first failing step must be
    a setup, artifact or runner step; once that job's tests executed, only an
    artifact or runner step. A failed job with no failing step is a runner
    failure. Anything else (build, test, validation or budget steps) refuses."""
    identity = (summary.get("runID"), summary.get("head"), summary.get("selection"))
    if identity != (run_id, head, selection):
        return [f"summary identity {identity} is not {(run_id, head, selection)}"], []
    refusals, causes = [], []
    if summary.get("conclusion") != "failure":
        refusals.append(f"run concluded {summary.get('conclusion')!r}; only a failed run can be an "
                        "infrastructure failure")
    build = summary.get("build") if isinstance(summary.get("build"), dict) else {}
    if build.get("swiftErrors"):
        refusals.append(f"{build['swiftErrors']} Swift compile errors: a source failure")
    tests = summary.get("tests") if isinstance(summary.get("tests"), dict) else {}
    failed = sorted(k for k, v in tests.items() if v.get("result") in ("Failed", "Interrupted"))
    if failed:
        refusals.append(f"the test phase ran and {len(failed)} tests failed or were interrupted "
                        f"(first {failed[0]}): a test failure, not infrastructure")
    steps = summary.get("steps") if isinstance(summary.get("steps"), list) else []
    executed = any(v.get("result") != "NotStarted" for v in tests.values())
    if summary.get("route") == "shared-build":
        executed_jobs = {(entry.get("job") or {}).get("name")
                         for entry in (summary.get("partitions") or {}).values()
                         if any(k != "NotStarted" for k in (entry.get("counts") or {}))}
    else:
        executed_jobs = {s.get("job") for s in steps if s.get("step") == TEST_STEP} if executed else set()
    if executed and (not executed_jobs or None in executed_jobs):
        refusals.append("tests executed but are not attributable to a job; cannot prove an infrastructure cause")
    first = {}
    for step in steps:
        if step.get("conclusion") not in NON_FAILING_STEP:
            first.setdefault(step.get("job"), step)
    for job, step in first.items():
        name, after_tests = step.get("step"), job in executed_jobs
        category = ("artifact" if name in INFRA_ARTIFACT_STEPS else "runner" if name in INFRA_RUNNER_STEPS
                    else "setup" if name in INFRA_SETUP_STEPS and not after_tests else None)
        if category is not None:
            causes.append({"job": job, "step": name, "conclusion": step.get("conclusion"), "category": category})
        elif name == TEST_STEP:
            refusals.append(f"{job}: the test phase started and failed ({step.get('conclusion')}): "
                            "a test failure, not infrastructure")
        else:
            allowed = "artifact or runner step after its tests executed" if after_tests \
                else "setup, artifact or runner step"
            refusals.append(f"{job}: first failing step {name!r} ({step.get('conclusion')}) is not a {allowed}")
    for job in jobs:
        if job.get("conclusion") == "failure" and job.get("name") not in first:
            causes.append({"job": job.get("name"), "step": None, "conclusion": "failure", "category": "runner"})
    if not causes and not refusals:
        refusals.append("no failing step or failed job proves a setup, artifact or runner failure")
    return refusals, causes


def infra_retry_admission(head, selection, resolved, resolved_sha, run_id, reason, kind):
    """Refuse unless RUN_ID is the recorded development original here, collected, terminal and
    infrastructure-failed, and head+selection has no gate or unmarked original and no rerun yet."""
    if kind != "development":
        raise SystemExit("an infrastructure rerun is a development run; it needs --kind development")
    if not development_route(selection, resolved):
        raise SystemExit(f"--infra-retry-of is only for development routes; {selection} is not one")
    here = [x for x in ledger_dispatches() if (x.get("head"), x.get("selection")) == (head, selection)]
    if run_id not in [x.get("runID") for x in here]:
        raise SystemExit(f"run {run_id} is not a ledgered original of {selection} at {head}")
    other = sorted(x.get("runID") for x in here if x.get("kind") != "development")
    if other:
        raise SystemExit(f"{selection} at {head} has gate or unmarked originals {other}; "
                         "a development rerun is never dispatched beside them")
    retry_path = ATTEMPTS / f"{head}-{selection}.infra-retry.json"
    earlier = sorted(x.get("runID") for x in here if "infraRetryOf" in x)
    if earlier or retry_path.exists() or any(ATTEMPTS.glob(f"{head}-{selection}.infra-retry*.json")):
        raise SystemExit(f"{selection} at {head} already had its one infrastructure rerun {earlier}; "
                         "never a second")
    if here[-1].get("runID") != run_id:
        raise SystemExit(f"run {run_id} is not the latest original of {selection} at {head} "
                         f"(latest {here[-1].get('runID')}); only the latest may be rerun")
    if any(e.get("runID") == run_id and str(e.get("event", "")).startswith("cancel") for e in ledger_events()):
        raise SystemExit(f"run {run_id} was cancelled through this ledger; a cancelled run is never rerun")
    dispatched, why = recorded_development(run_id)
    if why:
        raise SystemExit(why)
    directory = EVIDENCE / str(run_id)
    if dispatched.get("resolvedSelectionSHA256") != resolved_sha:
        raise SystemExit(f"{selection} resolves differently at {head} than it did for run {run_id}")
    observed = api(f"repos/{REPO}/actions/runs/{run_id}")
    check_identity(observed, dispatched)
    if observed.get("status") != "completed":
        raise SystemExit(f"run {run_id} is {observed.get('status')}, not terminal; wait for it and collect it")
    summary_path = directory / "summary.json"
    if not (directory / "manifest.json").is_file() or not summary_path.is_file() \
            or not (directory / "jobs.json").is_file():
        raise SystemExit(f"run {run_id} is not collected; collect --run {run_id} and audit it first")
    summary = json.loads(summary_path.read_text(encoding="utf-8"))
    jobs = json.loads((directory / "jobs.json").read_text(encoding="utf-8")).get("jobs", [])
    refusals, causes = infra_failure_classification(summary, jobs, run_id, head, selection)
    if refusals:
        raise SystemExit(f"run {run_id} is not an infrastructure failure: " + "; ".join(refusals))
    return retry_path, {"infraRetryOf": run_id, "infraRetryReason": reason,
                        "infraRetryEvidence": {"summarySHA256": sha256(summary_path.read_bytes()),
                                               "conclusion": summary.get("conclusion"), "causes": causes}}


def phase1_gates():
    """Load the isolated contract only for the new prospective Phase1 commands."""
    spec = importlib.util.spec_from_file_location("v23_phase1_gates", ROOT / "Scripts/v23-phase1-gates.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def preregister_phase1(plan_path):
    """Retain an exact-source candidate intent; Stage A cannot dispatch or qualify it.

    All source facts come from the pushed commit, not the working tree. A future
    dispatcher must recheck this reservation, every original and all prerequisites.
    Registration does not consume an original attempt or grant acceptance credit.
    """
    gate = phase1_gates()
    try:
        plan = gate.parse_plan(gate.regular_bytes(plan_path))
        gate.require(plan["purpose"] == gate.CANDIDATE, "exact-main prerequisites are not implemented")
        run("git", "fetch", "--quiet", "origin", BRANCH, "main")
        head = run("git", "rev-parse", "HEAD").strip()
        remote = run("git", "rev-parse", f"origin/{BRANCH}").strip()
        main_head = run("git", "rev-parse", "origin/main").strip()
        tree = run("git", "rev-parse", f"{head}^{{tree}}").strip()
        resolved, resolved_sha = resolve_selection(head, plan["selection"])
        selected_bytes = gate.canonical(resolved)
        gate.require(gate.sha(selected_bytes) == resolved_sha, "resolver bytes/digest")
        sources = {path: gate.sha(git_bytes("show", f"{head}:{path}")) for path in gate.SOURCES}
        gate.bind_facts(plan, head=head, tree=tree, integration_head=remote, main_head=main_head,
                        resolved_bytes=selected_bytes, sources=sources)
        # The registrar itself must be the exact source it records, not newer local
        # tooling making a promise on behalf of an older commit.
        for path in (gate.COLLECTOR, "Scripts/v23-phase1-gates.py"):
            gate.require(gate.sha(gate.regular_bytes(ROOT / path, limit=4 * 1024 * 1024)) == sources[path],
                         "registrar differs from frozen source")
        attempts = [p.name for p in ATTEMPTS.iterdir()] if ATTEMPTS.exists() else []
        conflicts = gate.conflicting_originals(plan, ledger(), attempts)
        gate.require(not conflicts, "original collision: " + "; ".join(conflicts))
        # Unknown remote originals are never inferred harmless from their names.
        known = {entry["runID"] for entry in ledger_dispatches()}
        unknown = [record["id"] for record in runs_for(head) if record["id"] not in known]
        gate.require(not unknown, "unledgered originals: " + str(unknown))
        target, record = gate.register_candidate(plan, EVIDENCE / "v23-phase1-plans")
    except gate.Refused as error:
        raise SystemExit(str(error)) from error
    print(json.dumps({"path": str(target), "planSHA256": record["planSHA256"],
                      "dispatchEnabled": False, "functionalQualification": gate.PENDING}, indent=2))
    return record


def phase1_timestamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def phase1_run_census(gate, query, captured=None):
    """Actual bounded API pagination; no first-page or malformed-ID exemption."""
    rows, total = [], None
    separator = "&" if "?" in query else "?"
    for page in range(1, -(-gate.MAX_ORIGINAL_RUNS // PAGE_SIZE) + 1):
        endpoint = f"{query}{separator}per_page={PAGE_SIZE}&page={page}"
        value = api(endpoint)
        if captured is not None:
            captured.append({"endpoint": endpoint, "response": value})
        gate.require(type(value) is dict, "run census API object")
        count, batch = value.get("total_count"), value.get("workflow_runs")
        gate.require(type(count) is int and 0 <= count <= gate.MAX_ORIGINAL_RUNS
                     and (total is None or count == total), "run census bounded stable total")
        total = count
        gate.require(type(batch) is list and len(batch) <= PAGE_SIZE, "run census bounded page")
        rows.extend(batch)
        gate.require(len(rows) <= total, "run census overcollection")
        if len(rows) == total:
            result = {"total_count": total, "workflow_runs": rows}
            gate.validate_run_census(result)
            return result
        gate.require(bool(batch), "run census incomplete page")
    raise gate.Refused("Phase1 gate: run census page bound")


def phase1_ref_observations():
    return {"integration": api(f"repos/{REPO}/git/ref/heads/{BRANCH}"),
            "main": api(f"repos/{REPO}/git/ref/heads/main")}


def phase1_frozen_candidate(gate, plan, *, discovery=False):
    gate.require(plan["purpose"] == gate.CANDIDATE, "candidate-only lifecycle")
    run("git", "fetch", "--quiet", "origin", BRANCH, "main")
    head = run("git", "rev-parse", "HEAD").strip()
    tree = run("git", "rev-parse", head + "^{tree}").strip()
    integration = run("git", "rev-parse", "origin/" + BRANCH).strip()
    main_head = run("git", "rev-parse", "origin/main").strip()
    gate.require(run("git", "diff", "--cached", "--name-only").strip() == "", "real index is not empty")
    selected, selected_sha = resolve_selection(head, plan["selection"])
    gate.require(selected_sha == gate.sha(gate.canonical(selected)), "resolver original bytes")
    sources = {p: gate.sha(git_bytes("show", f"{head}:{p}")) for p in gate.SOURCES}
    if discovery:
        # A moved remote ref is retained by discovery below, not an excuse to
        # replace the frozen local source or lose the uncertainty observation.
        gate.require(head == plan["head"] and tree == plan["tree"], "frozen discovery source")
        gate.exact(gate.make_plan(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
            resolved_bytes=gate.canonical(selected), sources=sources, requested_at=plan["requestedAtUTC"]),
            plan, "frozen discovery source/selection")
    else:
        gate.bind_facts(plan, head=head, tree=tree, integration_head=integration, main_head=main_head,
                        resolved_bytes=gate.canonical(selected), sources=sources)
    for p in (gate.COLLECTOR, "Scripts/v23-phase1-gates.py"):
        gate.require(gate.sha(gate.regular_bytes(ROOT / p, limit=4 * 1024 * 1024)) == sources[p],
                     "lifecycle implementation differs from frozen source")
    registration = gate.regular_bytes(EVIDENCE / "v23-phase1-plans" / (gate.original_stem(plan) + ".json"))
    return selected, registration


def phase1_lifecycle_directory(gate, plan):
    return ATTEMPTS / (gate.original_stem(plan) + ".discovery")


def phase1_request_receipt(gate, attempt, result=None, error=None):
    return {"schema": "v23-phase1-request-outcome.v1", "attemptSHA256": gate.sha(gate.canonical(attempt)),
            "argvSHA256": gate.sha(gate.canonical(attempt["argv"])),
            "inputSHA256": gate.sha(attempt["inputBytes"].encode("utf-8")),
            "completedAtUTC": phase1_timestamp(), "exitCode": result.returncode if result is not None else None,
            "stdoutHex": result.stdout.hex() if result is not None else "",
            "stderrHex": result.stderr.hex() if result is not None else "",
            "error": type(error).__name__ if error is not None else None}


def phase1_validate_request(gate, attempt, receipt):
    gate.require(type(receipt) is dict and set(receipt) == {"schema", "attemptSHA256", "argvSHA256", "inputSHA256",
        "completedAtUTC", "exitCode", "stdoutHex", "stderrHex", "error"}, "closed request outcome")
    gate.require(receipt["schema"] == "v23-phase1-request-outcome.v1"
        and receipt["attemptSHA256"] == gate.sha(gate.canonical(attempt))
        and receipt["argvSHA256"] == gate.sha(gate.canonical(attempt["argv"]))
        and receipt["inputSHA256"] == gate.sha(attempt["inputBytes"].encode("utf-8")), "request command/input binding")
    plan = gate.parse_plan(attempt["planBytes"].encode("utf-8"))
    gate.validate_plan(dict(plan, requestedAtUTC=receipt["completedAtUTC"]))
    gate.require(receipt["completedAtUTC"] >= attempt["requestedAtUTC"]
        and (receipt["exitCode"] is None or type(receipt["exitCode"]) is int)
        and all(type(receipt[k]) is str and re.fullmatch(r"(?:[0-9a-f]{2})*", receipt[k]) for k in ("stdoutHex", "stderrHex"))
        and (receipt["error"] is None or type(receipt["error"]) is str), "request outcome fields")
    return receipt["exitCode"] == 0 and receipt["error"] is None


def phase1_discovery_state(gate, plan, attempt, snapshot, receipt, prior):
    """Derive attribution from retained observations; never authorize another call.

    An unresolved history does not prohibit a future independently reviewed
    attribution mechanism. This stage provides no such mechanism and no reset.
    """
    problems, identifier = [], None
    if receipt is None or not phase1_validate_request(gate, attempt, receipt):
        problems.append("request outcome unconfirmed; exact preauthorized original attribution remains due")
    if any(x["status"] == "ATTRIBUTION_PENDING" for x in prior):
        problems.append("prior attribution gap requires independent resolution outside this stage")
    gate.require(type(snapshot) is dict and set(snapshot) == {"refs", "headRuns", "directRun", "error", "runPages", "repository", "transportFailure"},
                 "closed discovery snapshot")
    pages = snapshot["runPages"]
    gate.require(type(pages) is list and len(pages) <= -(-gate.MAX_ORIGINAL_RUNS // PAGE_SIZE), "discovery page capture bound")
    for index, page in enumerate(pages, 1):
        gate.require(type(page) is dict and set(page) == {"endpoint", "response"}
            and page["endpoint"] == f"repos/{REPO}/actions/runs?head_sha={plan['head']}&per_page={PAGE_SIZE}&page={index}",
            "discovery original page endpoint")
    gate.require(type(snapshot["transportFailure"]) is bool
        and (not snapshot["transportFailure"] or type(snapshot["error"]) is str), "discovery transport observation")
    if snapshot["error"] is not None:
        gate.require(type(snapshot["error"]) is str, "failed discovery observation")
        problems.append("discovery capture failed: " + snapshot["error"])
    try:
        repository = snapshot["repository"]
        gate.require(type(repository) is dict and repository.get("full_name") == REPO
            and type(repository.get("id")) is int and repository["id"] == attempt["repositoryID"],
            "current repository identity changed/unavailable")
        gate.validate_ref_observations(snapshot["refs"], plan)
        gate.require(bool(pages), "complete discovery page captures")
        captured_rows, total = [], snapshot["headRuns"].get("total_count")
        for index, page in enumerate(pages):
            value = page["response"]
            gate.require(type(value) is dict and type(value.get("total_count")) is int
                and value["total_count"] == total and type(value.get("workflow_runs")) is list
                and len(value["workflow_runs"]) <= PAGE_SIZE, "captured discovery page")
            captured_rows.extend(value["workflow_runs"])
            gate.require(index == len(pages)-1 or (value["workflow_runs"] and len(captured_rows) < total),
                         "captured discovery page order/completion")
        gate.exact(snapshot["headRuns"], {"total_count": total, "workflow_runs": captured_rows}, "complete captured run census")
        ids = gate.validate_run_census(snapshot["headRuns"], head=plan["head"])
        gate.require(set(attempt["knownRunIDs"]) <= set(ids), "known original disappeared")
        fresh = sorted(set(ids) - set(attempt["knownRunIDs"]))
        gate.require(len(fresh) <= 1, "multiple new originals")
        if fresh:
            identifier = fresh[0]
            row = next(x for x in snapshot["headRuns"]["workflow_runs"] if x["id"] == identifier)
            phase1_api_original(gate, row, identifier, plan, attempt)
            phase1_api_original(gate, snapshot["directRun"], identifier, plan, attempt)
        else:
            gate.require(snapshot["directRun"] is None, "unexpected direct original")
        previous_ids = {x["runID"] for x in prior if x["runID"] is not None}
        gate.require(not previous_ids or previous_ids == {identifier}, "previously observed original changed/disappeared")
    except (ValueError, TypeError, KeyError, AttributeError) as error:
        problems.append(str(error)[:1000])
    return ("ATTRIBUTION_PENDING" if problems else "DISCOVERED_PENDING_PROOF" if identifier else "AWAITING_ORIGINAL"), identifier, problems


def phase1_read_lifecycle(gate, plan, attempt):
    directory = phase1_lifecycle_directory(gate, plan)
    gate.require(directory.is_dir() and not directory.is_symlink(), "regular discovery directory")
    names = sorted(p.name for p in directory.iterdir())
    request = None
    if "request.json" in names:
        request = gate.decode(gate.regular_bytes(directory / "request.json", limit=gate.MAX_ATTEMPT_BYTES), limit=gate.MAX_ATTEMPT_BYTES)
        phase1_validate_request(gate, attempt, request)
        names.remove("request.json")
    gate.require(len(names) <= 1000 and names == ["%06d.json" % i for i in range(len(names))],
                 "complete append-only discovery census")
    previous, entries, retained_bytes = None, [], 0
    for index, name in enumerate(names):
        raw = gate.regular_bytes(directory / name, limit=gate.MAX_ATTEMPT_BYTES)
        retained_bytes += len(raw)
        gate.require(retained_bytes <= 64 * 1024 * 1024, "aggregate discovery retention bound")
        item = gate.decode(raw, limit=gate.MAX_ATTEMPT_BYTES)
        gate.require(type(item) is dict and set(item) == {"schema", "attemptSHA256", "index", "previousSHA256",
            "observedAtUTC", "requestSHA256", "snapshot", "status", "runID", "problems"}, "closed discovery entry")
        gate.require(item["schema"] == gate.DISCOVERY_SCHEMA and type(item["index"]) is int and item["index"] == index
            and item["previousSHA256"] == previous and item["attemptSHA256"] == gate.sha(gate.canonical(attempt))
            and item["requestSHA256"] == (gate.sha(gate.canonical(request)) if request is not None else None),
            "discovery immutable attempt/request chain")
        gate.validate_plan(dict(plan, requestedAtUTC=item["observedAtUTC"]))
        gate.require(item["observedAtUTC"] >= (entries[-1]["observedAtUTC"] if entries else attempt["requestedAtUTC"]),
                     "discovery time order")
        state, identifier, problems = phase1_discovery_state(gate, plan, attempt, item["snapshot"], request, entries)
        gate.exact([item["status"], item["runID"], item["problems"]], [state, identifier, problems], "derived discovery state")
        entries.append(item)
        previous = gate.sha(raw)
    anchors = [x for x in ledger_events() if x.get("event") == "phase1-discovery"
               and x.get("attemptSHA256") == gate.sha(gate.canonical(attempt))]
    expected = [{"event": "phase1-discovery", "attemptSHA256": gate.sha(gate.canonical(attempt)),
                 "index": x["index"], "discoverySHA256": gate.sha(gate.canonical(x))} for x in entries]
    gate.exact(anchors, expected, "complete ledger-anchored discovery history")
    return request, entries


def phase1_append_ledger(gate, value):
    with LEDGER.open("ab") as stream:
        stream.write(gate.canonical(value)); stream.flush(); os.fsync(stream.fileno())


def phase1_record_discovery(gate, plan, attempt, snapshot):
    request, entries = phase1_read_lifecycle(gate, plan, attempt)
    gate.require(len(entries) < 1000, "discovery record bound")
    state, identifier, problems = phase1_discovery_state(gate, plan, attempt, snapshot, request, entries)
    value = {"schema": gate.DISCOVERY_SCHEMA, "attemptSHA256": gate.sha(gate.canonical(attempt)), "index": len(entries),
        "previousSHA256": gate.sha(gate.canonical(entries[-1])) if entries else None, "observedAtUTC": phase1_timestamp(),
        "requestSHA256": gate.sha(gate.canonical(request)) if request is not None else None,
        "snapshot": snapshot, "status": state, "runID": identifier, "problems": problems}
    gate.write_immutable(phase1_lifecycle_directory(gate, plan) / ("%06d.json" % len(entries)), gate.canonical(value))
    phase1_append_ledger(gate, {"event": "phase1-discovery", "attemptSHA256": value["attemptSHA256"],
                              "index": value["index"], "discoverySHA256": gate.sha(gate.canonical(value))})
    return value


def phase1_dispatch_record(gate, plan, attempt, selected, entry):
    identifier = entry["runID"]
    record = {"phase1DispatchSchema": "v23-phase1-dispatch.v1", "runID": identifier, "runAttempt": 1, "head": plan["head"], "ref": plan["ref"], "selection": plan["selection"],
        "kind": "gate", "lane": LANE, "requestedAtUTC": attempt["requestedAtUTC"],
        "url": f"https://github.com/{REPO}/actions/runs/{identifier}", "argv": attempt["argv"],
        "resolvedSelection": selected, "resolvedSelectionSHA256": plan["selectionSHA256"],
        "phase1Purpose": plan["purpose"], "phase1PlanBytes": attempt["planBytes"], "phase1PlanSHA256": attempt["planSHA256"],
        "phase1RegistrationSHA256": attempt["registrationSHA256"], "phase1RegistrationSchema": gate.REGISTRATION_SCHEMA,
        "phase1AttemptSHA256": gate.sha(gate.canonical(attempt)), "phase1DiscoverySHA256": gate.sha(gate.canonical(entry)),
        "functionalQualification": gate.PENDING, "acceptance": False, "releaseReady": False}
    if plan["selection"] == SHARED_SELECTION_ID:
        record["sharedPartitions"] = shared_partitions(plan["head"], selected)
    return record


def phase1_capture_original(gate, plan, attempt):
    """Fixed-endpoint live observations shared by discovery and collection.

    Retain partial pages and independent successful responses after a failed
    census. They are diagnostic observations, never complete attribution.
    """
    captured, errors, transport = [], [], []
    def capture(label, action):
        try:
            return action()
        except (ValueError, OSError, subprocess.CalledProcessError) as error:
            errors.append(label + ": " + type(error).__name__ + ": " + str(error)[:1000])
            transport.append(isinstance(error, (OSError, subprocess.CalledProcessError)))
            return None
    repository = capture("repository", lambda: api(f"repos/{REPO}"))
    census = capture("head census", lambda: phase1_run_census(gate, f"repos/{REPO}/actions/runs?head_sha={plan['head']}", captured))
    fresh = [] if census is None else sorted(set(gate.validate_run_census(census)) - set(attempt["knownRunIDs"]))
    direct = capture("direct original", lambda: api(f"repos/{REPO}/actions/runs/{fresh[0]}")) if len(fresh) == 1 else None
    refs = {"integration": capture("integration ref", lambda: api(f"repos/{REPO}/git/ref/heads/{BRANCH}")),
            "main": capture("main ref", lambda: api(f"repos/{REPO}/git/ref/heads/main"))}
    return {"repository": repository, "headRuns": census, "directRun": direct, "refs": refs,
            "error": "; ".join(errors) if errors else None, "runPages": captured, "transportFailure": any(transport)}


def phase1_discover_original(gate, plan, attempt, selected):
    snapshot = phase1_capture_original(gate, plan, attempt)
    entry = phase1_record_discovery(gate, plan, attempt, snapshot)
    if entry["status"] != "DISCOVERED_PENDING_PROOF":
        raise gate.Refused("Phase1 gate: " + entry["status"] + "; consumed attempt; only discovery continuation, never redispatch")
    identifier = entry["runID"]
    record = phase1_dispatch_record(gate, plan, attempt, selected, entry)
    directory = EVIDENCE / str(identifier)
    directory.mkdir(exist_ok=True)
    gate.require(directory.is_dir() and not directory.is_symlink(), "regular discovered original directory")
    path = directory / "dispatch.json"
    if path.exists():
        # A continuation never rewrites the original discovery binding.
        existing = gate.decode(gate.regular_bytes(path, limit=gate.MAX_ATTEMPT_BYTES), limit=gate.MAX_ATTEMPT_BYTES)
        _, history = phase1_read_lifecycle(gate, plan, attempt)
        gate.require(any(gate.sha(gate.canonical(x)) == existing.get("phase1DiscoverySHA256")
            and x["status"] == "DISCOVERED_PENDING_PROOF" and x["runID"] == identifier for x in history), "original discovery binding")
        record["phase1DiscoverySHA256"] = existing["phase1DiscoverySHA256"]
        gate.exact(existing, record, "immutable discovered original")
    else:
        gate.write_immutable(path, gate.canonical(record))
    prior = [row for row in ledger_dispatches() if row.get("runID") == identifier]
    if prior:
        gate.require(len(prior) == 1, "duplicate discovered ledger original")
        gate.exact(prior[0], record, "existing discovered ledger original")
    else:
        phase1_append_ledger(gate, record)
    return record


def phase1_candidate_lifecycle(plan_path, *, selection=None, kind=None, infra_retry_of=None, reason=None, discover=False):
    """Dormant candidate caller. Existing dispatch and this entry both refuse.

    Tests replace the refusal only inside synthetic protocol fixtures. Neither
    the public command nor importing and invoking this caller can dispatch now.
    """
    gate = phase1_gates()
    gate.refuse_dispatch()
    plan = gate.parse_plan(gate.regular_bytes(plan_path))
    gate.require((selection is None or selection == plan["selection"]) and kind in (None, "gate")
        and infra_retry_of is None and reason is None, "candidate gate inputs; no retry or alternate kind")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    gate.require(not EVIDENCE.is_symlink(), "regular root evidence directory")
    lock = EVIDENCE / "phase1-dispatch-active"
    lock.mkdir()
    try:
        selected, registration = phase1_frozen_candidate(gate, plan, discovery=discover)
        gate.durable_directory(ATTEMPTS)
        target = ATTEMPTS / (gate.original_stem(plan) + ".json")
        if discover:
            attempt = gate.decode(gate.regular_bytes(target, limit=gate.MAX_ATTEMPT_BYTES), limit=gate.MAX_ATTEMPT_BYTES)
            gate.validate_attempt(attempt, plan, registration)
            gate.durable_directory(phase1_lifecycle_directory(gate, plan))
        else:
            # A failed/partial earlier consumed file is never read as permission
            # to try again. The exclusive write below is the final race check.
            gate.require(not os.path.lexists(target), "attempt already consumed; never redispatch")
            observations = {"repository": api(f"repos/{REPO}"),
                "workflow": api(f"repos/{REPO}/actions/workflows/{WORKFLOW}"),
                "activeRuns": {status: phase1_run_census(gate, f"repos/{REPO}/actions/runs?status={status}")
                               for status in gate.ACTIVE_RUN_STATUSES},
                "headRuns": phase1_run_census(gate, f"repos/{REPO}/actions/runs?head_sha={plan['head']}"),
                "refs": phase1_ref_observations()}
            ledger_raw = gate.regular_bytes(LEDGER, limit=gate.MAX_ATTEMPT_BYTES) if LEDGER.exists() else b""
            names = sorted(p.name for p in ATTEMPTS.iterdir())
            attempt = gate.make_attempt(plan, registration, collector_id=os.urandom(16).hex(),
                requested_at=phase1_timestamp(), observations=observations, ledger_bytes=ledger_raw.decode("utf-8"), attempt_names=names)
            gate.write_immutable(target, gate.canonical(attempt))
            directory = phase1_lifecycle_directory(gate, plan)
            gate.durable_directory(directory)
            try:
                result = subprocess.run(attempt["argv"], input=attempt["inputBytes"].encode("utf-8"),
                                        cwd=ROOT, capture_output=True, check=False)
                receipt = phase1_request_receipt(gate, attempt, result=result)
            except (OSError, subprocess.SubprocessError) as error:
                receipt = phase1_request_receipt(gate, attempt, error=error)
            gate.write_immutable(directory / "request.json", gate.canonical(receipt))
        return phase1_discover_original(gate, plan, attempt, selected)
    finally:
        lock.rmdir()


def dispatch(selection, kind=None, infra_retry_of=None, reason=None, phase1_plan=None,
             compiler_observation=False, swift_driver_jobs_two=False):
    if phase1_plan is not None:
        if compiler_observation or swift_driver_jobs_two:
            raise SystemExit("compiler experiments are development-only, never a Phase1 gate input")
        # Deliberately before all network, attempt or ledger effects. Registering
        # intent is not activation of the incomplete Phase1 gate path.
        gate = phase1_gates()
        try:
            gate.refuse_dispatch()
            return phase1_candidate_lifecycle(phase1_plan, selection=selection, kind=kind,
                                             infra_retry_of=infra_retry_of, reason=reason)
        except gate.Refused as error:
            raise SystemExit(str(error)) from error
    kind = run_kind(selection, kind)
    if compiler_observation and (kind != "development" or selection != DEV_BATCH_SELECTION_ID):
        raise SystemExit("compiler observation requires explicit development D50 selection")
    if swift_driver_jobs_two and not compiler_observation:
        raise SystemExit("Swift driver two-job experiment requires explicit compiler observation")
    if infra_retry_of is not None:
        reason = (reason or "").strip()
        if not reason:
            raise SystemExit("--infra-retry-of requires a non-empty --reason")
        if len(reason) > MAX_REASON:
            raise SystemExit(f"--reason exceeds {MAX_REASON} characters")
        if kind != "development":
            raise SystemExit("an infrastructure rerun is a development run; it needs --kind development")
    elif reason is not None:
        raise SystemExit("--reason is only accepted with --infra-retry-of")
    run("git", "fetch", "--quiet", "origin", BRANCH)
    head = run("git", "rev-parse", "HEAD").strip()
    remote = run("git", "rev-parse", f"origin/{BRANCH}").strip()
    if head != remote:
        raise SystemExit(f"local HEAD {head} is not the pushed branch head {remote}")
    if subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=ROOT).returncode != 0:
        raise SystemExit("real index is not empty")
    parent = run("git", "rev-parse", f"{head}^").strip()
    workflow = run("git", "show", f"{head}:{WORKFLOW_PATH}")
    if not re.search(r"^\s*- " + re.escape(selection) + r"\s*$", workflow, re.M):
        raise SystemExit(f"selection {selection} is not a workflow choice at {head}")
    if kind == "development" and not run_kind_input_declared(workflow):
        raise SystemExit(f"a development original passes {RUN_KIND_INPUT}=development, but {WORKFLOW_PATH} at "
                         f"{head} does not declare that choice input (gate|development, default gate)")
    if compiler_observation and not compiler_observation_input_declared(workflow):
        raise SystemExit("the exact workflow does not declare default-false compiler observation")
    if swift_driver_jobs_two and not default_false_boolean_input_declared(
            workflow, SWIFT_DRIVER_JOBS_TWO_INPUT):
        raise SystemExit("the exact workflow does not declare default-false Swift driver experiment")
    resolved, resolved_sha = resolve_selection(head, selection)
    if kind == "development" and not development_route(selection, resolved):
        raise SystemExit(f"--kind development is only for development routes; {selection} is not one")
    if compiler_observation:
        preflight_compiler_observation_source(head, resolved_sha, swift_driver_jobs_two)
    shared = selection == SHARED_SELECTION_ID
    partitions = shared_partitions(head, resolved) if shared else None
    if kind == "gate":
        # A gate original is the first and only original of its head+selection.
        prior = sorted(x.get("runID") for x in ledger_dispatches()
                       if (x.get("head"), x.get("selection")) == (head, selection))
        requested = [p.name for p in [ATTEMPTS / f"{head}-{selection}.json",
                                      *ATTEMPTS.glob(f"{head}-{selection}.infra-retry*.json")] if p.exists()]
        if prior or requested:
            raise SystemExit(f"a gate original of {selection} at {head} is refused: this head+selection already "
                             f"has originals {prior} / attempt records {requested}")
    retry_path, retry = (infra_retry_admission(head, selection, resolved, resolved_sha, infra_retry_of, reason, kind)
                         if infra_retry_of is not None else (None, None))
    ledgered = {x["runID"] for x in ledger_dispatches()}
    before = runs_for(head)
    unknown = [x["id"] for x in before if x["id"] not in ledgered]
    if unknown:
        raise SystemExit(f"runs at this head not dispatched by this ledger {unknown}; audit them first")
    active = [x for status in ACTIVE_STATUSES
              for x in api(f"repos/{REPO}/actions/runs?status={status}&per_page=100")["workflow_runs"]]
    if len(active) >= MAX_ACTIVE:
        raise SystemExit(f"{len(active)} active runs; capacity is {MAX_ACTIVE}")
    dispatches = ledger_dispatches()
    by_run = {x["runID"]: x for x in dispatches}
    selection_by_run = {x["runID"]: x["selection"] for x in dispatches}

    def active_head(run):
        return run.get("head_sha") or by_run.get(run["id"], {}).get("head")

    def development_run(run):
        return by_run.get(run["id"], {}).get("kind") == "development"
    # Development originals of the per-head routes carry the head in their concurrency groups.
    parallel = (kind == "development" and selection in PER_HEAD_SELECTIONS
                and development_route(selection, resolved))
    if shared and not parallel and active:
        # One shared run can hold all MAX_ACTIVE macOS slots (producer, then 5 consumers).
        raise SystemExit(f"{len(active)} active runs {sorted(x['id'] for x in active)}; "
                         f"{SHARED_SELECTION_ID} requires zero other active runs of any selection")
    if shared and active:
        # A development sweep shares macOS slots only with ledgered development runs at other
        # heads: their jobs queue, and every budget clock starts on the runner.
        foreign = sorted(x["id"] for x in active if not development_run(x))
        if foreign:
            raise SystemExit(f"active runs {foreign} are not ledgered development runs; a development "
                             f"{SHARED_SELECTION_ID} sweep runs only beside development runs at other heads")
        here = sorted(x["id"] for x in active if active_head(x) in (head, None))
        if here:
            raise SystemExit(f"runs {here} are active at this head (or at an unknown head); "
                             f"{SHARED_SELECTION_ID} never overlaps another run of its head")
    same = [x for x in active if selection_by_run.get(x["id"]) == selection]
    if same:
        # Without the development per-head term the committed concurrency groups are per
        # selection ID, not per head, so a second original of the same selection would queue
        # or cancel the first. Only a development original of a per-head route may run beside
        # development originals of that route, at a different head whose caller, job and
        # worker groups add the head.
        if not parallel or not all(development_run(x) for x in same):
            raise SystemExit("this selection is active (at any head); wait for its terminal audited result")
        heads = {active_head(x) for x in same}
        if head in heads or None in heads:
            raise SystemExit(f"{selection} is active at this head (runs {sorted(x['id'] for x in same)}); "
                             "wait for its terminal audited result")
        problems = per_head_concurrency_problems(head, workflow, selection)
        if problems:
            raise SystemExit(f"{selection} is active at another head; a parallel original needs per-head "
                             "concurrency groups at this head: " + "; ".join(problems))
    sweeps = [x for x in active if selection_by_run.get(x["id"]) == SHARED_SELECTION_ID]
    if not shared and sweeps:
        # An active shared run can occupy every macOS slot. A gate or unmarked sweep admits no
        # other original; a development sweep admits only development originals at other heads.
        if kind != "development" or not all(development_run(x) for x in sweeps):
            raise SystemExit(f"{SHARED_SELECTION_ID} is active; no other selection may be dispatched until "
                             "its terminal audited result")
        if any(active_head(x) in (head, None) for x in sweeps):
            raise SystemExit(f"{SHARED_SELECTION_ID} is active at this head (or at an unknown head); no other "
                             "original of this head may be dispatched until its terminal audited result")
    ATTEMPTS.mkdir(parents=True, exist_ok=True)
    attempt_path = retry_path or ATTEMPTS / f"{head}-{selection}.json"
    argv = ["gh", "workflow", "run", WORKFLOW, "--repo", REPO, "--ref", BRANCH,
            "-f", "execution_lane=" + LANE, "-f", "native_selection_id=" + selection,
            "-f", "run_ui_smoke=" + ("true" if selection == UI_BATCH_SELECTION_ID else "false"),
            "-f", "s10_4_shard_id=none",
            "-f", "s10_4_minimum_core_smoke_id=none", "-f", "s10_4_shared_segment_id=none"]
    if kind == "development":
        # A gate passes nothing: the workflow default (gate) keeps its argv and groups unchanged.
        argv += ["-f", f"{RUN_KIND_INPUT}=development"]
    if compiler_observation:
        argv += ["-f", f"{COMPILER_OBSERVATION_INPUT}=true"]
    if swift_driver_jobs_two:
        argv += ["-f", f"{SWIFT_DRIVER_JOBS_TWO_INPUT}=true"]
    attempt = {"head": head, "parent": parent, "selection": selection, "argv": argv,
               "knownRunIDs": sorted(x["id"] for x in before),
               "requestedAtUTC": now(), "resolvedSelectionSHA256": resolved_sha, "kind": kind}
    if compiler_observation:
        attempt["compilerObservation"] = True
    if swift_driver_jobs_two:
        attempt["swiftDriverJobsTwo"] = True
    attempt.update(retry or {})
    try:
        write_new(attempt_path, attempt)
    except FileExistsError:
        raise SystemExit(f"{attempt_path} exists: this " + ("infrastructure rerun" if retry else "head+selection")
                         + " was already requested; never duplicate")
    known = {x["id"] for x in before}
    subprocess.run(argv, cwd=ROOT, check=True)
    new = []
    for _ in range(60):
        time.sleep(6)
        try:
            observed = runs_for(head)
        except subprocess.CalledProcessError:
            continue
        new = [x for x in observed if x["id"] not in known and x["event"] == "workflow_dispatch"
               and x["path"] == WORKFLOW_PATH and x["head_branch"] == BRANCH and x["run_attempt"] == 1]
        if new:
            break
    if len(new) != 1:
        raise SystemExit(f"new original not uniquely observed ({[x['id'] for x in new]}); the attempt record "
                         f"{attempt_path} blocks any repeat. Inspect Actions and record the run manually.")
    record = {"runID": new[0]["id"], "head": head, "parent": parent, "selection": selection, "lane": LANE,
              "requestedAtUTC": json.loads(attempt_path.read_text(encoding="utf-8"))["requestedAtUTC"],
              "url": new[0]["html_url"], "argv": argv, "resolvedSelection": resolved,
              "resolvedSelectionSHA256": resolved_sha, "acceptance": False, "releaseReady": False, "kind": kind}
    if compiler_observation:
        record["compilerObservation"] = True
        record["attemptName"] = attempt_path.name
    if swift_driver_jobs_two:
        record["swiftDriverJobsTwo"] = True
    if shared:
        record["sharedPartitions"] = partitions
    record.update(retry or {})
    directory = EVIDENCE / str(record["runID"])
    directory.mkdir(parents=True, exist_ok=False)
    write_new(directory / "dispatch.json", record)
    ledger_entry = {k: record[k] for k in ("runID", "head", "parent", "selection", "url", "requestedAtUTC", "kind")
                    + (("infraRetryOf", "infraRetryReason") if retry else ())}
    if compiler_observation:
        ledger_entry["compilerObservation"] = True
    if swift_driver_jobs_two:
        ledger_entry["swiftDriverJobsTwo"] = True
    append_ledger(ledger_entry)
    print(json.dumps({k: v for k, v in record.items() if k not in ("resolvedSelection", "sharedPartitions")},
                     indent=2))


def publish_file(temporary, path):
    """Move a complete temporary file to path, refusing an existing target on every platform."""
    if os.name == "nt":
        os.rename(temporary, path)  # Windows rename refuses an existing target.
        return
    try:
        os.link(temporary, path)  # POSIX rename would silently replace; link refuses.
    except FileExistsError:
        raise
    except OSError:
        if os.path.lexists(path):
            raise FileExistsError(path)
        os.rename(temporary, path)
        return
    os.unlink(temporary)


def save_bytes(path, data):
    """Create-once via a temporary file, so a crash never leaves a truncated record."""
    temporary = path.with_name(path.name + ".partial")
    temporary.write_bytes(data)
    publish_file(temporary, path)


def check_identity(observed, dispatched):
    expected = (dispatched["runID"], dispatched["head"], BRANCH, "workflow_dispatch", WORKFLOW_PATH, 1)
    actual = (observed["id"], observed["head_sha"], observed["head_branch"], observed["event"],
              observed["path"], observed["run_attempt"])
    if actual != expected:
        raise SystemExit(f"run identity changed {actual} != {expected}; inspect before collecting")


def check_compiler_observation_record(dispatched):
    """Bind an opted-in development original to its immutable request and ledger."""
    requested = dispatched.get("compilerObservation", False)
    jobs_two = dispatched.get("swiftDriverJobsTwo", False)
    if type(requested) is not bool or type(jobs_two) is not bool:
        raise SystemExit("compiler observation dispatch field is not boolean")
    if jobs_two and not requested:
        raise SystemExit("Swift driver experiment requires compiler observation")
    originals = [line for line in ledger_dispatches() if line.get("runID") == dispatched.get("runID")]
    if not requested:
        if any(line.get("compilerObservation") is True or line.get("swiftDriverJobsTwo") is True
               for line in originals):
            raise SystemExit("compiler observation ledger/dispatch downgrade")
        names = []
        if isinstance(dispatched.get("attemptName"), str):
            names.append(dispatched["attemptName"])
        if (isinstance(dispatched.get("head"), str) and
                dispatched.get("selection") == DEV_BATCH_SELECTION_ID):
            stem = dispatched["head"] + "-" + dispatched["selection"]
            canonical_names = (stem + ".json", stem + ".infra-retry.json")
            if "attemptName" in dispatched and dispatched["attemptName"] not in canonical_names:
                raise SystemExit("compiler observation noncanonical attempt name")
            names.extend(canonical_names)
        for name in sorted(set(names)):
            if not re.fullmatch(r"[a-f0-9]{40}-[A-Za-z0-9-]+(?:\.infra-retry)?\.json", name):
                raise SystemExit("compiler observation attempt name")
            path = ATTEMPTS / name
            if path.is_file():
                attempt = json.loads(path.read_text(encoding="utf-8"))
                if (attempt.get("requestedAtUTC") == dispatched.get("requestedAtUTC") and
                        (attempt.get("compilerObservation") is True or
                         attempt.get("swiftDriverJobsTwo") is True)):
                    raise SystemExit("compiler observation attempt/dispatch downgrade")
        return False  # Historical missing flags agree across retained records.
    if (dispatched.get("kind"), dispatched.get("selection"), dispatched.get("acceptance"),
            dispatched.get("releaseReady")) != ("development", DEV_BATCH_SELECTION_ID, False, False):
        raise SystemExit("compiler observation cannot be attributed to a gate or other route")
    name = dispatched.get("attemptName")
    if not isinstance(name, str) or not re.fullmatch(r"[a-f0-9]{40}-v23-dev-batch-no-index-d50(?:\.infra-retry)?\.json", name):
        raise SystemExit("compiler observation attempt name")
    attempt = json.loads((ATTEMPTS / name).read_text(encoding="utf-8"))
    terms = ("head", "parent", "selection", "kind", "resolvedSelectionSHA256", "argv")
    if (attempt.get("compilerObservation") is not True or
            attempt.get("swiftDriverJobsTwo", False) is not jobs_two or
            any(attempt.get(key) != dispatched.get(key) for key in terms) or
            attempt.get("requestedAtUTC") != dispatched.get("requestedAtUTC") or
            attempt["argv"].count(f"{COMPILER_OBSERVATION_INPUT}=true") != 1 or
            attempt["argv"].count(f"{SWIFT_DRIVER_JOBS_TWO_INPUT}=true") != int(jobs_two)):
        raise SystemExit("compiler observation attempt/dispatch mismatch")
    if (len(originals) != 1 or originals[0].get("compilerObservation") is not True or any(
            originals[0].get(key) != dispatched.get(key)
            for key in ("head", "parent", "selection", "kind", "requestedAtUTC")) or
            originals[0].get("swiftDriverJobsTwo", False) is not jobs_two):
        raise SystemExit("compiler observation ledger/dispatch mismatch")
    return True


def collect(run_id, resume):
    directory = EVIDENCE / str(run_id)
    dispatched = json.loads((directory / "dispatch.json").read_text(encoding="utf-8"))
    check_compiler_observation_record(dispatched)
    if any(key.startswith("phase1") for key in dispatched):
        return collect_phase1(run_id, resume)
    claim = directory / "collector.claim.json"
    if resume:
        if not claim.exists() or (directory / "manifest.json").exists():
            raise SystemExit("resume requires an existing claim and no manifest")
    else:
        write_new(claim, {"runID": run_id, "claimedAtUTC": now(), "collector": Path(__file__).name,
                          "collectorSHA256": sha256(Path(__file__).read_bytes())})
    monitor = directory / "monitor.jsonl"
    previous = None
    while True:
        try:
            observed = api(f"repos/{REPO}/actions/runs/{run_id}")
        except subprocess.CalledProcessError as error:
            with monitor.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({"at": now(), "observationError": str(error)[:300]}) + "\n")
            time.sleep(60)
            continue
        check_identity(observed, dispatched)
        state = (observed["status"], observed["conclusion"])
        if state != previous:
            with monitor.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps({"at": now(), "status": state[0], "conclusion": state[1]}) + "\n")
            previous = state
        if observed["status"] == "completed":
            break
        time.sleep(60)
    if dispatched["selection"] == SHARED_SELECTION_ID:
        return collect_shared(run_id, directory, dispatched, observed)

    def once(name, producer):
        path = directory / name
        if not path.exists():
            data = producer()
            save_bytes(path, data if isinstance(data, bytes) else
                       (json.dumps(data, indent=2, sort_keys=True) + "\n").encode("utf-8"))
        return path

    once("run.json", lambda: observed)
    once("jobs.json", lambda: api(f"repos/{REPO}/actions/runs/{run_id}/attempts/1/jobs?per_page=100"))
    once("run-logs.zip", lambda: api_bytes(f"repos/{REPO}/actions/runs/{run_id}/attempts/1/logs"))
    artifacts = json.loads(once("artifacts.json", lambda: api(
        f"repos/{REPO}/actions/runs/{run_id}/artifacts?per_page=100")).read_text(encoding="utf-8"))
    expected_name = f"ios-ci-native-{PROVIDER}-{dispatched['selection']}-{run_id}-1"
    named = [a for a in artifacts["artifacts"] if a["name"] == expected_name]
    notes = []
    if len(artifacts["artifacts"]) != 1 or len(named) != 1:
        notes.append(f"expected exactly one artifact named {expected_name}; observed "
                     f"{[a['name'] for a in artifacts['artifacts']]}")
    if len(named) == 1 and not named[0]["expired"]:
        artifact = named[0]
        archive = once(f"artifact-{artifact['id']}.zip",
                       lambda: api_bytes(f"repos/{REPO}/actions/artifacts/{artifact['id']}/zip"))
        digest = "sha256:" + sha256(archive.read_bytes()).lower()
        if artifact.get("digest") and artifact["digest"] != digest:
            raise SystemExit(f"artifact digest mismatch {artifact['digest']} != {digest}")
        if not (directory / "artifact").exists():
            extract(archive, directory / "artifact")
    if not (directory / "run-logs").exists():
        extract(directory / "run-logs.zip", directory / "run-logs")
    check_identity(api(f"repos/{REPO}/actions/runs/{run_id}"), dispatched)
    if dispatched["selection"] == UI_BATCH_SELECTION_ID:
        collect_ui_review(directory, dispatched, observed, notes)
    walk_root = Path("\\\\?\\" + str(directory.resolve())) if os.name == "nt" else directory
    manifest = {p.relative_to(walk_root).as_posix(): sha256(p.read_bytes())
                for p in sorted(walk_root.rglob("*")) if p.is_file()
                and (p != walk_root / "manifest.json" if dispatched["selection"] == UI_BATCH_SELECTION_ID
                     else p.name != "manifest.json")
                and (not (p.parent == walk_root and p.name.startswith("summary"))
                     if dispatched["selection"] == UI_BATCH_SELECTION_ID else not p.name.startswith("summary"))}
    write_new(directory / "manifest.json", {"runID": run_id, "files": manifest, "notes": notes, "atUTC": now()})
    summary = summarize(run_id)
    print(json.dumps({k: v for k, v in summary.items() if k not in ("tests", "steps")}, indent=2))
    for key, value in summary["tests"].items():
        print(value["result"], value["seconds"], key)
    if dispatched["selection"] == UI_BATCH_SELECTION_ID and observed["conclusion"] == "success" \
            and not summary["ownerReview"]["verifiedOriginals"]:
        raise SystemExit("RUI1 original validation failed; originals and manifest retained, no owner review package")


def phase1_original_context(run_id, *, retention_only=False):
    """Root-owned immutable records plus exact Git bytes, before any API action.

    Root's evidence directory is the trust boundary. These records are created
    before dispatch, not recovered from a worker's claimed purpose. C1 does not
    create them; the new dispatch path remains unconditionally disabled.
    """
    gate = phase1_gates()
    gate.require(type(run_id) is int and run_id > 0, "collection original run ID")
    directory = EVIDENCE / str(run_id)
    gate.require(directory.is_dir() and not directory.is_symlink(), "root original directory")
    raw = gate.regular_bytes(directory / "dispatch.json", limit=4 * 1024 * 1024)
    dispatched = gate.decode(raw, limit=4 * 1024 * 1024)
    plan = gate.parse_plan(dispatched.get("phase1PlanBytes", "").encode("utf-8"))
    gate.require(plan["purpose"] == gate.CANDIDATE, "exact-main collection prerequisites remain disabled")
    gate.require((dispatched.get("kind"), dispatched.get("head"), dispatched.get("ref"),
                  dispatched.get("selection"), dispatched.get("phase1Purpose"), dispatched.get("runAttempt"))
                 == ("gate", plan["head"], plan["ref"], plan["selection"], plan["purpose"], 1)
                 and type(dispatched.get("runAttempt")) is int
                 and type(dispatched.get("runID")) is int and dispatched["runID"] == run_id,
                 "root original kind/head/ref/purpose/attempt")
    stem = gate.original_stem(plan)
    registration_raw = gate.regular_bytes(EVIDENCE / "v23-phase1-plans" / (stem + ".json"))
    registration = gate.decode(registration_raw)
    gate.exact(registration, {"schema": gate.REGISTRATION_SCHEMA, "plan": plan,
        "planSHA256": gate.sha(gate.canonical(plan)), "dispatchEnabled": False,
        "functionalQualification": gate.PENDING}, "root preregistered pending intent")
    attempt_raw = gate.regular_bytes(ATTEMPTS / (stem + ".json"), limit=gate.MAX_ATTEMPT_BYTES)
    attempt = gate.decode(attempt_raw, limit=gate.MAX_ATTEMPT_BYTES)
    gate.validate_attempt(attempt, plan, registration_raw)
    gate.require(attempt["planSHA256"] == dispatched.get("phase1PlanSHA256")
        and attempt["registrationSHA256"] == dispatched.get("phase1RegistrationSHA256")
        and gate.sha(attempt_raw) == dispatched.get("phase1AttemptSHA256")
        and dispatched.get("phase1RegistrationSchema") == gate.REGISTRATION_SCHEMA
        and attempt["requestedAtUTC"] == dispatched.get("requestedAtUTC")
        and run_id not in attempt["knownRunIDs"], "root predispatch registration/attempt binding")
    request, history = phase1_read_lifecycle(gate, plan, attempt)
    # Retention may continue for the historically bound selected original after
    # current uniqueness is lost. This never admits attribution or acceptance.
    gate.require(type(retention_only) is bool, "explicit retention context")
    gate.require(history and (retention_only or (history[-1]["status"] == "DISCOVERED_PENDING_PROOF"
        and history[-1]["runID"] == run_id)) and any(gate.sha(gate.canonical(x)) == dispatched.get("phase1DiscoverySHA256")
                and x["status"] == "DISCOVERED_PENDING_PROOF" and x["runID"] == run_id for x in history),
        "attributed original discovery required")
    sources = {p: gate.sha(git_bytes("show", f"{plan['head']}:{p}")) for p in gate.SOURCES}
    gate.exact(sources, plan["sources"], "root frozen source closure")
    gate.require(run("git", "rev-parse", plan["head"] + "^{tree}").strip() == plan["tree"], "root frozen Git tree")
    resolved, resolved_sha = resolve_selection(plan["head"], plan["selection"])
    gate.require(resolved_sha == plan["selectionSHA256"] == dispatched.get("resolvedSelectionSHA256"),
                 "root original resolved selection")
    if plan["selection"] == SHARED_SELECTION_ID:
        gate.exact(dispatched.get("sharedPartitions"), shared_partitions(plan["head"], resolved),
                   "root exact committed partition census")
    gate.exact(gate.make_plan(purpose=plan["purpose"], head=plan["head"], tree=plan["tree"],
        selection=plan["selection"], resolved_bytes=gate.canonical(resolved), sources=sources,
        requested_at=plan["requestedAtUTC"]), plan, "root recomputed exact plan")
    bound_discovery = next(x for x in history if gate.sha(gate.canonical(x)) == dispatched["phase1DiscoverySHA256"])
    gate.exact(dispatched, phase1_dispatch_record(gate, plan, attempt, resolved, bound_discovery),
               "closed original dispatch writer/reader schema")
    gate.require(attempt["collectorSHA256"] == sources[gate.COLLECTOR]
        == gate.sha(gate.regular_bytes(Path(__file__), limit=4 * 1024 * 1024)), "sole exact-source collector")
    same_question = [entry for entry in ledger_dispatches()
                     if (entry.get("head"), entry.get("selection")) == (plan["head"], plan["selection"])]
    gate.require(len(same_question) == 1 and all(same_question[0].get(key) == dispatched.get(key)
        for key in ("runID", "kind", "head", "selection", "phase1Purpose", "phase1PlanBytes", "phase1PlanSHA256",
                    "phase1RegistrationSchema", "phase1AttemptSHA256", "phase1DiscoverySHA256")), "sole preregistered ledger original")
    other_attempts = [p.name for p in ATTEMPTS.iterdir() if p.name not in (stem + ".json", stem + ".discovery")]
    gate.require(not gate.conflicting_originals(plan, [], other_attempts), "ambiguous historical original attempts")
    return gate, directory, dispatched, plan, attempt, raw, registration_raw, attempt_raw, resolved


def phase1_api_original(gate, value, run_id, plan, attempt):
    """Validate only responses fetched by this caller from the fixed repo endpoint."""
    gate.require(type(value) is dict and type(value.get("id")) is int and value["id"] == run_id
        and type(value.get("run_attempt")) is int and value["run_attempt"] == 1
        and type(value.get("workflow_id")) is int and value["workflow_id"] == attempt["workflowID"]
        and (value.get("head_sha"), value.get("head_branch"), value.get("path"), value.get("event"))
            == (plan["head"], plan["ref"].removeprefix("refs/heads/"), WORKFLOW_PATH, "workflow_dispatch")
        and value.get("repository", {}).get("full_name") == REPO
        and value.get("head_repository", {}).get("full_name") == REPO
        and type(value.get("repository", {}).get("id")) is int and value["repository"]["id"] > 0
        and type(value.get("head_repository", {}).get("id")) is int
        and value.get("head_repository", {}).get("id") == value["repository"]["id"] == attempt["repositoryID"],
        "authenticated repository/run/attempt origin")
    created = value.get("created_at")
    gate.require(type(created) is str and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", created),
                 "authenticated original creation time")
    gate.require(datetime.datetime.fromisoformat(created.replace("Z", "+00:00"))
        >= datetime.datetime.fromisoformat(attempt["requestedAtUTC"].replace("Z", "+00:00")),
        "original predates consumed attempt")
    return value


def phase1_zip_extract(gate, archive, target):
    """Stricter prospective gate transport, leaving the legacy extractor exact."""
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        gate.require(0 < len(entries) <= 100000 and sum(e.file_size for e in entries) <= 4 * 1024 ** 3,
                     "complete evidence ZIP bound")
        seen, files = set(), set()
        for entry in entries:
            name = entry.filename.rstrip("/") if entry.is_dir() else entry.filename
            gate.require(name and "\\" not in name and not name.startswith("/") and ":" not in name
                and all(p not in ("", ".", "..") for p in name.split("/")) and "\x00" not in name,
                "evidence ZIP path")
            folded = name.casefold()
            gate.require(folded not in seen, "evidence ZIP duplicate/case collision")
            seen.add(folded)
            mode = entry.external_attr >> 16
            gate.require(stat.S_IFMT(mode) in (0, stat.S_IFDIR if entry.is_dir() else stat.S_IFREG),
                         "evidence ZIP nonregular member")
            if not entry.is_dir():
                files.add(folded)
        gate.require(not any("/".join(name.split("/")[:i]) in files for name in seen
                             for i in range(1, len(name.split("/")))), "evidence ZIP file ancestor")
    extract(archive, target)


def phase1_artifact_census(gate, path):
    """Retain every bounded API member, including invalid/ambiguous originals.

    The legacy paginator rejects duplicate IDs before the gate collector can
    preserve independent safe artifacts. Here only the complete page envelope
    is admitted; member identity/origin/digest is checked by collect_phase1.
    No malformed or duplicate member gains identity or evidence credit.
    """
    items, total = [], None
    for page in range(1, -(-SHARED_MAX_ARTIFACTS // PAGE_SIZE) + 1):
        value = api(f"{path}?per_page={PAGE_SIZE}&page={page}")
        gate.require(type(value) is dict, "artifact census API object")
        count = value.get("total_count")
        gate.require(type(count) is int and 0 <= count <= SHARED_MAX_ARTIFACTS,
                     "artifact census total_count bound")
        gate.require(total is None or count == total, "artifact census total_count changed")
        total = count
        batch = value.get("artifacts")
        gate.require(type(batch) is list and len(batch) <= PAGE_SIZE, "artifact census bounded page")
        items.extend(batch)
        gate.require(len(items) <= total, "artifact census exceeds total_count")
        if len(items) == total:
            return {"artifacts": items, "total_count": total}
        gate.require(bool(batch), "artifact census incomplete empty page")
    raise gate.Refused("artifact census exceeds bounded page count")


def collect_phase1(run_id, resume):
    """Actual API/retention caller; complete functional proof remains INCOMPLETE.

    No dispatch/rerun/cancel, provider qualification or human approval is performed.
    A failed or partial original keeps its claim and every fetched original byte.
    """
    gate, directory, dispatched, plan, attempt, dispatch_raw, registration_raw, attempt_raw, resolved = phase1_original_context(run_id, retention_only=True)
    claim_value = {"schema": "v23-phase1-sole-collector.v1", "runID": run_id, "runAttempt": 1,
        "collectorID": attempt["collectorID"], "collectorSHA256": attempt["collectorSHA256"],
        "planSHA256": attempt["planSHA256"], "attemptSHA256": gate.sha(attempt_raw),
        "dispatchSHA256": gate.sha(dispatch_raw), "registrationSHA256": gate.sha(registration_raw)}
    claim = directory / "collector.claim.json"
    gate.require(not (directory / "manifest.json").exists(), "completed original is immutable")
    if resume:
        gate.exact(gate.decode(gate.regular_bytes(claim)), claim_value, "same sole collector claim on resume")
    else:
        with claim.open("xb") as stream:
            stream.write(gate.canonical(claim_value)); stream.flush(); os.fsync(stream.fileno())
    lock = directory / "phase1-collector-active"
    lock.mkdir(mode=0o700)  # A crashed owner leaves this lock closed for root inspection.
    authority_lock = EVIDENCE / "phase1-dispatch-active"
    authority_locked, collection_ended = False, False
    collection_observations = []
    notes = ["INCOMPLETE: qualification lifecycle and independent cold review remain disabled"]
    transport_problems = []
    try:
        authority_lock.mkdir()  # Serializes the shared append-only discovery writer.
        authority_locked = True
        def retain(name, raw):
            path = directory / name
            if path.exists() or path.is_symlink():
                gate.require(gate.regular_bytes(path, limit=4 * 1024 ** 3) == raw, "retained original changed: " + name)
            else:
                with path.open("xb") as stream:
                    stream.write(raw); stream.flush(); os.fsync(stream.fileno())
            return path
        def fetch_json(name, endpoint):
            value = api(endpoint)
            retain(name, gate.canonical(value))
            return value
        def observe_collection(phase):
            nonlocal collection_ended
            entry = phase1_record_discovery(gate, plan, attempt, phase1_capture_original(gate, plan, attempt))
            observations = directory / "phase1-collection-observations"
            gate.durable_directory(observations)
            value = {"schema": "v23-phase1-collection-observation.v1", "phase": phase,
                     "claimSHA256": gate.sha(gate.canonical(claim_value)), "entry": entry,
                     "discoverySHA256": gate.sha(gate.canonical(entry)), "status": "INCOMPLETE"}
            gate.write_immutable(observations / ("%06d.json" % entry["index"]), gate.canonical(value))
            collection_observations.append(value)
            if entry["status"] != "DISCOVERED_PENDING_PROOF" or entry["runID"] != run_id:
                notes.append("collection " + phase + " attribution: " + entry["status"] + "; " + "; ".join(entry["problems"]))
            if entry["snapshot"]["transportFailure"]:
                transport_problems.append("collection " + phase + " census transport unresolved")
            if phase != "begin": collection_ended = True
        def attribution():
            return {"status": "DISCOVERED_PENDING_PROOF" if collection_ended and all(
                v["entry"]["status"] == "DISCOVERED_PENDING_PROOF" and v["entry"]["runID"] == run_id
                for v in collection_observations) else "ATTRIBUTION_PENDING",
                "retentionOnly": True, "observations": [v["discoverySHA256"] for v in collection_observations]}
        observe_collection("begin")
        base = f"repos/{REPO}/actions/runs/{run_id}"
        observed = api(base)
        phase1_api_original(gate, observed, run_id, plan, attempt)
        if observed.get("status") != "completed":
            with (directory / "phase1-monitor.jsonl").open("ab") as stream:
                stream.write(gate.canonical(observed)); stream.flush(); os.fsync(stream.fileno())
            raise gate.Refused("Phase1 original is not completed; resume the same sole claim after completion")
        retain("run.json", gate.canonical(observed))
        original = fetch_json("run-attempt-1.json", base + "/attempts/1")
        phase1_api_original(gate, original, run_id, plan, attempt)
        gate.require(observed.get("status") == original.get("status") == "completed", "original must be completed before collection")
        # Retain original logs before downstream artifact validation can fail.
        logs = retain("run-logs.zip", api_bytes(base + "/attempts/1/logs"))
        if not (directory / "run-logs").exists():
            phase1_zip_extract(gate, logs, directory / "run-logs")
        else:
            with tempfile.TemporaryDirectory(prefix="phase1-logs-") as temporary:
                comparison = Path(temporary) / "original"
                phase1_zip_extract(gate, logs, comparison)
                gate.require(phase1_file_manifest(directory / "run-logs") == phase1_file_manifest(comparison),
                             "retained extracted run logs changed")
        workflow = fetch_json("workflow.json", f"repos/{REPO}/actions/workflows/{attempt['workflowID']}")
        gate.require(type(workflow.get("id")) is int and workflow["id"] == attempt["workflowID"] and workflow.get("path") == WORKFLOW_PATH,
                     "authenticated original workflow")
        jobs = paginated(base + "/attempts/1/jobs", "jobs", SHARED_MAX_JOBS)
        retain("jobs.json", gate.canonical(jobs))
        gate.require(all(type(j.get("id")) is int and j["id"] > 0 and type(j.get("run_id")) is int and j["run_id"] == run_id
            and type(j.get("run_attempt")) is int and j["run_attempt"] == 1
            and j.get("head_sha") == plan["head"] and j.get("status") == "completed" for j in jobs["jobs"]),
            "authenticated job original/attempt/head")
        listing = phase1_artifact_census(gate, base + "/artifacts")
        retain("artifacts.json", gate.canonical(listing))
        (directory / "phase1-job-logs").mkdir(exist_ok=True)
        gate.require((directory / "phase1-job-logs").is_dir() and not (directory / "phase1-job-logs").is_symlink(),
                     "regular job-log retention directory")
        for job in jobs["jobs"]:
            # Job IDs came from the authenticated attempt1 endpoint above.
            # Fixed job-log endpoints avoid trusting archive folder labels.
            if job.get("conclusion") == "skipped" and not job.get("steps"):
                continue
            try:
                raw = api_bytes(f"repos/{REPO}/actions/jobs/{job['id']}/logs")
            except (OSError, subprocess.CalledProcessError) as error:
                transport_problems.append("job %d log transport: %s" % (job["id"], type(error).__name__))
                continue
            try:
                gate.require(type(raw) is bytes and 0 < len(raw) <= 256 * 1024 * 1024,
                             "complete original job log bound")
                retain("phase1-job-logs/%d.log" % job["id"], raw)
            except (ValueError, OSError, subprocess.CalledProcessError) as error:
                notes.append("job %d log unavailable (%s): %s" %
                             (job["id"], type(error).__name__, str(error)[:1000]))
        if observed.get("conclusion") != "success" or original.get("conclusion") != "success":
            notes.append("original execution did not succeed")
        if plan["selection"] == SHARED_SELECTION_ID:
            partitions = shared_partitions_for(dispatched)["partitionIDs"]
            names = shared_artifact_names(run_id, plan["head"], partitions)
            expected = {names["producer"]: "producer", **{v: k for k, v in names["consumers"].items()}}
            payload_name = names["payload"]
        else:
            expected = {f"ios-ci-native-{PROVIDER}-{plan['selection']}-{run_id}-1": "rui1"}
            payload_name = None
        artifacts = listing["artifacts"]
        artifact_names = [a.get("name") for a in artifacts if type(a) is dict]
        duplicate_names = {name for name in artifact_names if type(name) is str and artifact_names.count(name) > 1}
        duplicate_ids = {a.get("id") for a in artifacts if type(a) is dict and type(a.get("id")) is int
                         and sum(type(b) is dict and b.get("id") == a["id"] for b in artifacts) > 1}
        if duplicate_names or duplicate_ids:
            notes.append("duplicate artifact name or ID census")
        wanted = set(expected) | ({payload_name} if payload_name else set())
        if len(artifact_names) != len(artifacts) or set(name for name in artifact_names if type(name) is str) != wanted:
            notes.append("missing or unexpected artifact census")
        proof_artifacts = {}
        (directory / "artifacts").mkdir(exist_ok=True)
        gate.require((directory / "artifacts").is_dir() and not (directory / "artifacts").is_symlink(),
                     "regular artifact retention directory")
        for artifact_index, artifact in enumerate(artifacts):
            try:
                gate.require(type(artifact) is dict, "authenticated artifact object")
                identifier = artifact.get("id")
                name = artifact.get("name")
                gate.require(type(name) is str and name not in duplicate_names
                             and type(identifier) is int and identifier not in duplicate_ids,
                             "unambiguous artifact identity")
                gate.require(type(identifier) is int and identifier > 0 and type(name) is str,
                             "authenticated artifact identity")
                origin = artifact.get("workflow_run")
                gate.require(type(origin) is dict and type(origin.get("id")) is int and origin["id"] == run_id
                    and origin.get("head_sha") == plan["head"]
                    and origin.get("head_branch") == plan["ref"].removeprefix("refs/heads/")
                    and type(origin.get("repository_id")) is int and type(origin.get("head_repository_id")) is int
                    and origin.get("repository_id") == observed["repository"]["id"]
                    and origin.get("head_repository_id") == observed["head_repository"]["id"], "authenticated artifact run/head/ref")
                digest = artifact.get("digest")
                gate.require(type(digest) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", digest)
                    and type(artifact.get("expired")) is bool and type(artifact.get("size_in_bytes")) is int
                    and 0 < artifact["size_in_bytes"] <= 4 * 1024 ** 3, "authenticated artifact digest/size")
                if artifact["expired"]:
                    notes.append("expired artifact " + name)
                    continue
                if name == payload_name:
                    proof_artifacts["payload"] = {"id": identifier, "digest": digest, "downloaded": False}
                    continue
                if name not in expected:
                    continue
                try:
                    raw = api_bytes(f"repos/{REPO}/actions/artifacts/{identifier}/zip")
                except (OSError, subprocess.CalledProcessError) as error:
                    transport_problems.append("artifact %d transport: %s" % (identifier, type(error).__name__))
                    continue
                archive = retain(f"artifact-{identifier}.zip", raw)
                gate.require("sha256:" + sha256(archive.read_bytes()).lower() == digest, "authenticated artifact ZIP digest")
                label = expected[name]
                target = directory / "artifacts" / label
                # C1 resume never trusts an earlier extracted tree: compare it against
                # a fresh extraction of the immutable authenticated archive below.
                if not target.exists():
                    phase1_zip_extract(gate, archive, target)
                else:
                    with tempfile.TemporaryDirectory(prefix="phase1-extract-") as temporary:
                        comparison = Path(temporary) / "original"
                        phase1_zip_extract(gate, archive, comparison)
                        gate.require(phase1_file_manifest(target) == phase1_file_manifest(comparison),
                                     "retained extracted artifact changed")
                proof_artifacts[label] = {"id": identifier, "digest": digest, "downloaded": True}
            except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
                # The invalid original still blocks proof. Continue retaining
                # other independently authenticated originals; never extract an
                # unauthenticated/invalid ZIP or let one bad member hide others.
                notes.append("artifact[%d] refused (%s): %s" %
                             (artifact_index, type(error).__name__, str(error)[:1000]))
        input_bindings = {}
        for label in expected.values():
            if not proof_artifacts.get(label, {}).get("downloaded"):
                continue
            try:
                event_raw = gate.regular_bytes(directory / "artifacts" / label / "phase1-original-event.json", limit=gate.MAX_EVENT_BYTES)
                input_bindings[label] = gate.verify_attempt_inputs(attempt, event_raw)
            except (ValueError, OSError) as error:
                notes.append("worker " + label + " original dispatch input binding: " + str(error)[:1000])
        def retain_partial():
            # No final manifest/checker output is sealed while an original's
            # transport is unresolved. Resume revalidates the same claim and
            # originals; this never retries or frees an execution question.
            partials = directory / "phase1-collection-partials"
            partials.mkdir(exist_ok=True)
            retained = phase1_file_manifest(partials)
            gate.require(sorted(retained) == ["%06d.json" % i for i in range(len(retained))]
                         and len(retained) < 1000, "closed collection partial history")
            partial = {"schema": "v23-phase1-collection-partial.v1", "status": "INCOMPLETE", "runID": run_id,
                       "runAttempt": 1, "planSHA256": attempt["planSHA256"], "problems": notes + transport_problems,
                       "originalAttribution": attribution(), "artifacts": proof_artifacts, "retainedFiles": phase1_file_manifest(directory),
                       "functionalQualification": gate.PENDING, "acceptance": False, "releaseReady": False}
            retain("phase1-collection-partials/%06d.json" % len(retained), gate.canonical(partial))
            raise SystemExit("Phase1 transport INCOMPLETE; safe originals retained; resume the same sole collector claim")
        if transport_problems:
            observe_collection("end-partial")
            retain_partial()
        retain("phase1-registration.json", registration_raw)
        retain("phase1-attempt.json", attempt_raw)
        request = retain("phase1-chain-request.json", gate.canonical({"schema": "v23-phase1-retained-chain-request.v1",
            "runID": run_id, "planSHA256": attempt["planSHA256"]}))
        checker_log, chain_bytes = b"", None
        with tempfile.TemporaryDirectory(prefix="phase1-exact-source-") as temporary:
            with tarfile.open(fileobj=io.BytesIO(git_bytes("archive", "--format=tar", plan["head"]))) as archive:
                archive.extractall(temporary, filter="data")
            for relative, digest in plan["sources"].items():
                gate.require(gate.sha(gate.regular_bytes(Path(temporary) / relative, limit=32 * 1024 * 1024)) == digest,
                             "exact archived collection source")
            command = [sys.executable, "-B", "Scripts/v23-native-ci.py", "phase1-retained-chain",
                       "--phase1-request", str(request.resolve())]
            try:
                checked = subprocess.run(command, cwd=temporary, capture_output=True, timeout=180)
                checker_log = checked.stdout + checked.stderr
                if checked.returncode:
                    notes.append("exact-source retained worker chain failed; see phase1-chain-check.log")
                else:
                    chain = json.loads(checked.stdout, object_pairs_hook=gate.object_pairs)
                    gate.require(chain.get("schema") == "v23-phase1-retained-worker-chain.v1"
                        and chain.get("runID") == run_id and chain.get("planSHA256") == attempt["planSHA256"]
                        and chain.get("status") == "INCOMPLETE" and chain.get("functionalQualification") == gate.PENDING,
                        "retained worker chain cannot self-qualify")
                    chain_bytes = gate.canonical(chain)
                    notes.extend("retained execution: " + p for p in chain.get("executionProof", {}).get("problems", []))
            except subprocess.TimeoutExpired as error:
                checker_log = (error.stdout or b"") + (error.stderr or b"") + b"\nretained checker timeout\n"
                notes.append("exact-source retained worker chain timed out")
        checker_observations = directory / "phase1-checker-observations"
        gate.durable_directory(checker_observations)
        retain("phase1-checker-observations/%06d.log" % collection_observations[0]["entry"]["index"], checker_log)
        final = fetch_json("run-after-collection.json", base)
        phase1_api_original(gate, final, run_id, plan, attempt)
        gate.require(final.get("status") == "completed" and final.get("conclusion") == observed.get("conclusion"),
                     "original changed during collection")
        final_artifacts = phase1_artifact_census(gate, base + "/artifacts")
        retain("artifacts-after-collection.json", gate.canonical(final_artifacts))
        if gate.canonical(final_artifacts) != gate.canonical(listing):
            notes.append("artifact API census changed during collection")
        observe_collection("end")
        if transport_problems:
            retain_partial()
        retain("phase1-chain-check.log", checker_log)
        if chain_bytes is not None:
            retain("phase1-retained-worker-chain.json", chain_bytes)
        request_outcome, discovery_history = phase1_read_lifecycle(gate, plan, attempt)
        retain("phase1-lifecycle.json", gate.canonical({"request": request_outcome, "history": discovery_history}))
        proof = {"schema": "v23-phase1-raw-proof.v1", "status": "INCOMPLETE", "runID": run_id,
            "runAttempt": 1, "planSHA256": attempt["planSHA256"], "head": plan["head"], "tree": plan["tree"],
            "originalAttribution": attribution(), "artifacts": proof_artifacts, "dispatchInputBindings": input_bindings, "problems": notes, "functionalQualification": gate.PENDING,
            "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED",
            "physicalProtectionReleaseBlocker": True, "acceptance": False, "providerQualification": False,
            "releaseReady": False}
        retain("phase1-raw-proof.json", gate.canonical(proof))
        manifest = {"schema": "v23-phase1-original-manifest.v1", "runID": run_id, "runAttempt": 1,
                    "files": phase1_file_manifest(directory), "rawProofSHA256": gate.sha(gate.canonical(proof))}
        retain("manifest.json", gate.canonical(manifest))
        print(json.dumps(proof, indent=2, sort_keys=True))
        raise SystemExit("Phase1 original retained; raw proof INCOMPLETE; no functional qualification")
    finally:
        try:
            if collection_observations and not collection_ended:
                observe_collection("end-exception")
        finally:
            if authority_locked: authority_lock.rmdir()
            lock.rmdir()


def phase1_file_manifest(directory):
    """Complete regular-file closure; every scan/stat/read error fails closed."""
    gate = phase1_gates()
    root_info = directory.lstat()
    gate.require(stat.S_ISDIR(root_info.st_mode), "manifest root")
    out, pending = {}, [(directory, root_info)]
    while pending:
        current, expected = pending.pop()
        current_info = current.lstat()
        gate.require(stat.S_ISDIR(current_info.st_mode) and
                     (current_info.st_dev, current_info.st_ino) == (expected.st_dev, expected.st_ino),
                     "manifest directory changed")
        # Path.rglob suppresses directory-scan OSError. Explicit scandir must
        # propagate an unreadable child instead of returning a partial census.
        with os.scandir(current) as scan:
            entries = sorted(scan, key=lambda entry: entry.name)
        for entry in entries:
            path = current / entry.name
            info = path.lstat()
            gate.require(not stat.S_ISLNK(info.st_mode), "manifest symlink")
            if stat.S_ISDIR(info.st_mode):
                pending.append((path, info))
                continue
            gate.require(stat.S_ISREG(info.st_mode) and len(out) < 100000, "manifest file census")
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                opened = os.fstat(stream.fileno())
                gate.require(stat.S_ISREG(opened.st_mode)
                    and (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns)
                    == (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns), "manifest file changed before read")
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
                after = os.fstat(stream.fileno())
                gate.require((after.st_size, after.st_mtime_ns) == (info.st_size, info.st_mtime_ns),
                             "manifest file changed during read")
            out[path.relative_to(directory).as_posix()] = digest.hexdigest().upper()
    return dict(sorted(out.items()))


def collect_ui_review(directory, dispatched, observed, notes):
    """Recheck original bytes using the exact dispatched head, never the live checkout.

    Failed or incomplete originals remain retained. A package is produced only
    after all screenshot/audit/outcome and source bindings pass; it records no
    owner approval, provider qualification or acceptance.
    """
    if observed["conclusion"] != "success":
        notes.append("RUI1 original failed: no verified owner review package")
        return
    if notes:
        notes.append("RUI1 artifact census invalid: no verified owner review package")
        return
    artifact = directory / "artifact"
    selected = artifact / "ci-selection.selected.json"
    if not selected.is_file() or sha256(selected.read_bytes()) != dispatched["resolvedSelectionSHA256"]:
        notes.append("RUI1 selected input differs from dispatch: no verified owner review package")
        return
    with tempfile.TemporaryDirectory(prefix="v23-rui-review-") as temporary:
        with tarfile.open(fileobj=io.BytesIO(git_bytes("archive", "--format=tar", dispatched["head"]))) as archive:
            archive.extractall(temporary, filter="data")
        completed = subprocess.run([sys.executable, "-B", "Scripts/v23-ui-evidence.py", "collect",
            "--root", temporary, "--artifact", str(artifact.resolve()), "--expected-head", dispatched["head"],
            "--expected-run", str(observed["id"]), "--review-output", str((directory / "owner-review.html").resolve())],
            cwd=temporary, capture_output=True)
        save_bytes(directory / "rui1-collection.log", completed.stdout + completed.stderr)
        if completed.returncode:
            notes.append("RUI1 original validation failed: see rui1-collection.log; no review or acceptance credit")
            return
        proof = json.loads(completed.stdout)
        write_new(directory / "rui1-collected-review.json", proof)


def extract(archive, target):
    """Extract into a temporary sibling, then rename, so resume never trusts a partial tree."""
    temporary = target.with_name(target.name + ".partial")
    if temporary.exists():
        raise SystemExit(f"{temporary} exists from an interrupted extraction; remove it after inspection")
    if os.name == "nt":
        # xcresult diagnostics exceed MAX_PATH; use extended-length paths.
        temporary = Path("\\\\?\\" + str(temporary.resolve()))
        target = Path("\\\\?\\" + str(target.resolve()))
    with zipfile.ZipFile(archive) as bundle:
        members = bundle.infolist()
        if len(members) > 100_000 or sum(m.file_size for m in members) > 4 * 1024 ** 3:
            raise SystemExit(f"{archive.name} exceeds extraction limits")
        for member in members:
            # Extended-length paths are not normalized by resolve(); reject
            # traversal, absolute and drive-qualified names explicitly.
            name = member.filename.replace("\\", "/")
            if (not name or name.startswith("/") or re.match(r"^[A-Za-z]:", name)
                    or ".." in name.split("/")):
                raise SystemExit(f"unsafe archive member {member.filename}")
            destination = (target / member.filename).resolve()
            if not destination.is_relative_to(target.resolve()):
                raise SystemExit(f"unsafe archive member {member.filename}")
        bundle.extractall(temporary)
    if os.name != "nt" and os.path.lexists(target):
        # POSIX rename would replace an empty directory; never replace retained evidence.
        raise SystemExit(f"{target} exists; extraction never replaces retained evidence")
    os.rename(temporary, target)


CASE = re.compile(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (started|passed|failed|skipped)"
                  r"(?: \(([\d.]+) seconds\))?")
ERROR = re.compile(r"error: -\[(\w+)\.(\w+) (\w+)\] : (.*)$")
TIMING = re.compile(r"V23_PROTECTED_FILE_TIMING_V1 (.*)$")
NAMED_DIAGNOSTIC = re.compile(r"\bV23_[A-Z0-9_]*(?:_DIAGNOSIS|_ERROR|_FAILURE)\b.*")


def test_lines(directory):
    """Prefer the retained test log; otherwise the targeted-test step job log."""
    log = directory / "artifact" / "test-smoke.log"
    if log.exists():
        return log, False
    candidates = sorted((directory / "run-logs").rglob("*Run targeted tests.txt"))
    return (candidates[0], True) if candidates else (None, True)


def parse_test_log(log, selected):
    """Per-test results for the selected methods from one xcodebuild test log."""
    results = {s: {"result": "NotStarted", "seconds": None, "failures": [], "lines": 0} for s in selected}
    unselected, timings, diagnostics = set(), [], []
    if log is not None:
        with log.open(encoding="utf-8", errors="replace") as stream:
            for line in stream:
                match = CASE.search(line)
                if match:
                    key = f"{match.group(1)}/{match.group(2)}/{match.group(3)}"
                    if key not in results:
                        unselected.add(key)
                        continue
                    state = match.group(4)
                    results[key]["lines"] += 1
                    results[key]["result"] = {"started": "Interrupted", "passed": "Passed",
                                              "failed": "Failed", "skipped": "Skipped"}[state]
                    if match.group(5):
                        results[key]["seconds"] = float(match.group(5))
                    continue
                match = ERROR.search(line)
                if match:
                    key = f"{match.group(1)}/{match.group(2)}/{match.group(3)}"
                    if key in results and len(results[key]["failures"]) < 5:
                        results[key]["failures"].append(match.group(4)[:400])
                    continue
                match = TIMING.search(line.strip())
                if match:
                    timings.append(dict(pair.split("=", 1) for pair in match.group(1).split() if "=" in pair))
                    continue
                match = NAMED_DIAGNOSTIC.search(line)
                if match and len(diagnostics) < 200:
                    diagnostics.append(match.group(0)[:800])
    return results, unselected, timings, diagnostics


def build_facts(build_text):
    return {"succeeded": "** TEST BUILD SUCCEEDED **" in build_text or "** BUILD SUCCEEDED **" in build_text,
            "swiftErrors": len(set(re.findall(r"^.*\.swift:\d+:\d+: error:.*$", build_text, re.M))),
            "swiftWarnings": len(set(re.findall(r"^.*\.swift:\d+:\d+: warning:.*$", build_text, re.M)))}


def summarize(run_id):
    directory = EVIDENCE / str(run_id)
    dispatched = json.loads((directory / "dispatch.json").read_text(encoding="utf-8"))
    requested_compiler_observation = check_compiler_observation_record(dispatched)
    if dispatched["selection"] == SHARED_SELECTION_ID:
        return summarize_shared(run_id, directory, dispatched)
    selected_path = directory / "artifact" / "ci-selection.selected.json"
    selection = (json.loads(selected_path.read_text(encoding="utf-8")) if selected_path.exists()
                 else dispatched["resolvedSelection"])
    selection_source = "artifact" if selected_path.exists() else "dispatch-resolved"
    selection_matches_dispatch = (sha256(selected_path.read_bytes()) == dispatched.get("resolvedSelectionSHA256")
                                  if selected_path.exists() else None)
    selected = selection["unitTestSelectors"]
    log, from_job_log = test_lines(directory)
    results, unselected, timings, diagnostics = parse_test_log(log, selected)
    if dispatched["selection"] == UI_BATCH_SELECTION_ID:
        ui_log = directory / "artifact" / "ui-smoke.log"
        if not ui_log.is_file():
            candidates = sorted((directory / "run-logs").rglob("*Run task-authorized UI smoke.txt"))
            ui_log = candidates[0] if candidates else None
        ui_results, ui_unselected, ui_timings, ui_diagnostics = parse_test_log(ui_log, selection["uiTestSelectors"])
        results.update(ui_results)
        unselected.update(ui_unselected)
        timings.extend(ui_timings)
        diagnostics.extend(ui_diagnostics)
    duplicated = sorted(k for k, v in results.items() if v["lines"] > 2)
    structured = {}
    results_path = directory / "artifact" / "unit-test-results.json"
    if results_path.exists() and results_path.stat().st_size:
        structured = {"available": True, "bytes": results_path.stat().st_size}
    build_log = directory / "artifact" / "build-smoke.log"
    build_text = build_log.read_text(encoding="utf-8", errors="replace") if build_log.exists() else ""
    observation_path = directory / "artifact" / "v23-compiler-timing" / "events.jsonl"
    if (not requested_compiler_observation and dispatched.get("selection") == DEV_BATCH_SELECTION_ID
            and observation_path.exists()):
        raise SystemExit("unrequested D50 compiler observation artifact")
    jobs = json.loads((directory / "jobs.json").read_text(encoding="utf-8"))
    run_record = json.loads((directory / "run.json").read_text(encoding="utf-8"))
    steps = [{"job": job["name"], "step": step["name"], "conclusion": step["conclusion"],
              "startedAt": step.get("started_at"), "completedAt": step.get("completed_at")}
             for job in jobs["jobs"] for step in job.get("steps", []) if step["conclusion"] != "skipped"]
    counts = {}
    for value in results.values():
        counts[value["result"]] = counts.get(value["result"], 0) + 1
    summary = {"runID": run_id, "head": run_record["head_sha"], "parent": dispatched.get("parent"),
               "selection": dispatched["selection"], "conclusion": run_record["conclusion"],
               "tier": selection["tier"], "selectionSource": selection_source,
               "selectionMatchesDispatch": selection_matches_dispatch,
               "budgets": {k: selection[k] for k in ("setupArtifactTimeoutSeconds", "buildTimeoutSeconds",
                                                    "testTimeoutSeconds", "uiTimeoutSeconds", "totalBudgetSeconds")},
               "artifactMissing": not (directory / "artifact").exists(),
               "resultsFromJobLog": from_job_log, "structuredResults": structured or {"available": False},
               "build": build_facts(build_text),
               "counts": counts, "tests": results, "unselectedTestLines": sorted(unselected),
               "duplicatedTestLines": duplicated, "protectedFileTiming": timings[-60:],
               "namedDiagnostics": diagnostics, "devBatch": selection.get("devBatch"),
               "steps": steps, "acceptance": False, "releaseReady": False, "atUTC": now()}
    if requested_compiler_observation:
        summary["compilerObservation"] = {"requested": True,
            "eventsRetained": observation_path.is_file(),
            "developmentOnly": True, "acceptance": False,
            "swiftDriverJobsTwo": dispatched.get("swiftDriverJobsTwo", False)}
    if dispatched["selection"] == UI_BATCH_SELECTION_ID:
        summary["uiBatch"] = selection.get("uiBatch")
        summary["ownerReview"] = {"verifiedOriginals": (directory / "rui1-collected-review.json").is_file(),
                                  "humanReviewCompleted": False, "acceptance": False}
    target = directory / "summary.json"
    if target.exists():
        target = directory / f"summary-{int(time.time())}.json"
    write_new(target, summary)
    return summary


# --------------------------------------------------------------------------
# Shared-build route (v23-shared-coverage-d50x): collection and summary.
# --------------------------------------------------------------------------

BUDGET_KEYS = ("setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds",
               "uiTimeoutSeconds", "totalBudgetSeconds")


def retain_once(directory, name, producer):
    """Create-once retention, as the single-job collector's closure does."""
    path = directory / name
    if not path.exists():
        data = producer()
        save_bytes(path, data if isinstance(data, bytes) else
                   (json.dumps(data, indent=2, sort_keys=True) + "\n").encode("utf-8"))
    return path


def paginated(path, key, limit):
    """Every item of a paginated Actions listing, bound-checked, in the one-page shape."""
    items, total, page, max_pages = [], None, 0, -(-limit // PAGE_SIZE)
    while True:
        page += 1
        if page > max_pages:
            raise SystemExit(f"{path}: more than {max_pages} pages")
        value = api(f"{path}?per_page={PAGE_SIZE}&page={page}")
        count = value.get("total_count")
        if type(count) is not int or not 0 <= count <= limit:
            raise SystemExit(f"{path}: total_count {count!r} outside 0..{limit}")
        if total is None:
            total = count
        elif count != total:
            raise SystemExit(f"{path}: total_count changed during pagination ({total} -> {count})")
        batch = value.get(key)
        if not isinstance(batch, list) or len(batch) > PAGE_SIZE:
            raise SystemExit(f"{path}: page {page} is not a bounded {key} list")
        items.extend(batch)
        if len(items) >= total or not batch:
            break
    if len(items) != total:
        raise SystemExit(f"{path}: collected {len(items)} {key} but total_count is {total}")
    identifiers = [item.get("id") for item in items]
    if len(set(identifiers)) != len(identifiers):
        raise SystemExit(f"{path}: duplicate {key} ids across pages")
    return {key: items, "total_count": total}


def shared_partitions_for(dispatched):
    """The dispatch-recorded partition lists (re-derived from Git for older dispatch records)."""
    recorded = dispatched.get("sharedPartitions")
    if recorded is not None:
        return recorded
    return shared_partitions(dispatched["head"], dispatched["resolvedSelection"])


def shared_artifact_names(run_id, head, partition_ids):
    prefix = f"ios-ci-native-{PROVIDER}-{SHARED_SELECTION_ID}"
    return {"producer": f"{prefix}-producer-{run_id}-1",
            "consumers": {x: f"{prefix}-consumer-{x}-{run_id}-1" for x in partition_ids},
            "payload": f"v23-shared-payload-{run_id}-1-{head}"}


def match_shared_artifacts(artifacts, run_id, head, partition_ids):
    """Exact-name matching only; anything else is reported as unexpected."""
    names = shared_artifact_names(run_id, head, partition_ids)
    by_name = collections.defaultdict(list)
    for artifact in artifacts:
        by_name[artifact["name"]].append(artifact)
    problems = [f"artifact name {name} is listed {len(found)} times"
                for name, found in sorted(by_name.items()) if len(found) > 1]

    def pick(name):
        found = by_name.get(name, [])
        return found[0] if len(found) == 1 else None
    expected = {names["producer"], names["payload"], *names["consumers"].values()}
    return {"names": names, "producer": pick(names["producer"]), "payload": pick(names["payload"]),
            "consumers": {x: pick(name) for x, name in names["consumers"].items()},
            "unexpected": sorted(name for name in by_name if name not in expected), "problems": problems}


def match_shared_jobs(jobs, partition_ids):
    """Classify jobs by exact name; a consumer job's partition comes from its name."""
    selection, producer, consumers = [], [], collections.defaultdict(list)
    placeholders, other, problems = [], [], []
    for job in jobs:
        name = job.get("name", "")
        match = SHARED_CONSUMER_JOB.fullmatch(name)
        if name == SHARED_SELECTION_JOB:
            selection.append(job)
        elif name == SHARED_PRODUCER_JOB:
            producer.append(job)
        elif match:
            consumers[match.group(1)].append(job)
        elif name.startswith(("V23 shared coverage producer", SHARED_CONSUMER_PREFIX)):
            # A skipped reusable caller is listed once, unexpanded and without " / verify".
            placeholders.append(job)
            if job.get("conclusion") != "skipped":
                problems.append(f"unmatched shared job {name!r} concluded {job.get('conclusion')}")
        else:
            other.append(job)
    for label, found in (("shared-selection", selection), ("producer", producer)):
        if len(found) > 1:
            problems.append(f"{len(found)} {label} jobs")
    problems += [f"{len(found)} consumer jobs for {x}" for x, found in sorted(consumers.items()) if len(found) > 1]
    unknown = sorted(set(consumers) - set(partition_ids))
    if unknown:
        problems.append(f"consumer jobs for partitions outside the plan {unknown}")
    if sum(len(found) for found in consumers.values()) > SHARED_MAX_PARTITIONS:
        problems.append(f"more than {SHARED_MAX_PARTITIONS} consumer jobs")
    return {"selection": selection[0] if len(selection) == 1 else None,
            "producer": producer[0] if len(producer) == 1 else None,
            "consumers": {x: found[0] for x, found in consumers.items() if len(found) == 1 and x in partition_ids},
            "placeholders": placeholders, "other": other, "problems": problems}


def job_step(job, name):
    found = [s for s in (job or {}).get("steps", []) if s.get("name") == name]
    return found[0] if len(found) == 1 else None


def requires_artifact(job):
    """A completed job whose evidence upload ran successfully (or that succeeded) must have its artifact."""
    if job is None or job.get("status") != "completed":
        return False
    upload = job_step(job, SHARED_UPLOAD_STEP)
    return job.get("conclusion") == "success" or (upload is not None and upload.get("conclusion") == "success")


def seconds_between(start, end):
    if not start or not end:
        return None
    parse = lambda value: datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return (parse(end) - parse(start)).total_seconds()


def step_seconds(job, name):
    found = job_step(job, name)
    if found is None or found.get("conclusion") in (None, "skipped"):
        return None
    return seconds_between(found.get("started_at"), found.get("completed_at"))


def job_timing(job):
    if job is None:
        return None
    ran = job.get("conclusion") != "skipped"
    return {"id": job.get("id"), "name": job.get("name"), "status": job.get("status"),
            "conclusion": job.get("conclusion"), "runnerName": job.get("runner_name"),
            "queueSeconds": seconds_between(job.get("created_at"), job.get("started_at")) if ran else None,
            "runSeconds": seconds_between(job.get("started_at"), job.get("completed_at")) if ran else None,
            "buildSeconds": step_seconds(job, SHARED_BUILD_STEP),
            "restoreSeconds": step_seconds(job, SHARED_RESTORE_STEP),
            "testSeconds": step_seconds(job, SHARED_TEST_STEP)}


def job_log_name(name):
    """The logs zip names a job's folder and file after the job with '/' (path-unsafe) replaced by '_'."""
    return re.sub(r'[/\\:*?"<>|]', "_", name)


def shared_test_log(directory, artifact_dir, job):
    """The partition's own test log: its artifact first, else only its own job's logs, by job name."""
    if artifact_dir is not None and (artifact_dir / "test-smoke.log").is_file():
        return artifact_dir / "test-smoke.log", "artifact"
    if job is None:
        return None, None
    logs = directory / "run-logs"
    folder = logs / job_log_name(job["name"])
    steps = sorted(p for p in folder.iterdir() if p.name.endswith("_" + SHARED_TEST_STEP + ".txt")) \
        if folder.is_dir() else []
    if len(steps) == 1:
        return steps[0], "job-step-log"
    whole = re.compile(r"[0-9]+_" + re.escape(job_log_name(job["name"])) + r"\.txt")
    files = sorted(p for p in logs.iterdir() if whole.fullmatch(p.name)) if logs.is_dir() else []
    if len(files) == 1:
        return files[0], "job-log"
    return None, None


def read_json_file(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def file_sha(path):
    return sha256(path.read_bytes()) if path.is_file() else None


def artifact_state(directory, label, name, artifact, job):
    """Retention facts for one evidence artifact and its integrity problems."""
    state = {"name": name, "listed": artifact is not None, "id": None, "sizeInBytes": None, "expired": None,
             "apiDigest": None, "zipDigest": None, "retained": False, "digestMatches": None,
             "extracted": False, "required": requires_artifact(job)}
    if artifact is None:
        return state, ([f"{label}: missing artifact {name} of completed job ({job.get('conclusion')})"]
                       if state["required"] else [])
    state.update(id=artifact["id"], sizeInBytes=artifact.get("size_in_bytes"), expired=artifact.get("expired"),
                 apiDigest=artifact.get("digest"))
    archive = directory / f"artifact-{artifact['id']}.zip"
    state["retained"] = archive.is_file()
    if not state["retained"]:
        return state, ([f"{label}: artifact {name} was not retained (expired={artifact.get('expired')})"]
                       if state["required"] or not artifact.get("expired") else [])
    state["zipDigest"] = "sha256:" + sha256(archive.read_bytes()).lower()
    state["digestMatches"] = not artifact.get("digest") or artifact["digest"] == state["zipDigest"]
    state["extracted"] = (directory / "artifacts" / label).is_dir()
    if not state["digestMatches"]:
        return state, [f"{label}: artifact digest mismatch {artifact.get('digest')} != {state['zipDigest']}"]
    return state, ([] if state["extracted"] else [f"{label}: artifact {name} retained but not extracted"])


def admission_facts(admission, role, partition_id, run_id, head, plan_sha, payload_name):
    if not isinstance(admission, dict):
        return {"present": False, "planSHA256Matches": None, "bindingMatches": None}
    binding = admission.get("sharedCoverage") if isinstance(admission.get("sharedCoverage"), dict) else {}
    return {"present": True, "planSHA256Matches": binding.get("planSHA256") == plan_sha,
            "bindingMatches": (binding.get("role"), binding.get("partitionID"), binding.get("payloadArtifactName"),
                               admission.get("selectionID"), admission.get("head"), str(admission.get("runID")),
                               str(admission.get("runAttempt")))
            == (role, partition_id, payload_name, SHARED_SELECTION_ID, head, str(run_id), "1")}


def canonical_json(value):
    """The route's canonical evidence bytes (canonical() in Scripts/v23-native-ci.py)."""
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def delta_facts(adir, after, partition_id):
    """The DerivedData delta record against the after fingerprint's summary of it."""
    path = adir / SHARED_DELTA
    summary = (after or {}).get("derivedDataDelta")
    facts = {"present": path.is_file(), "sha256": None, "sha256Matches": None, "canonical": None,
             "countsMatch": None, "addedCount": None, "changedCount": None, "removedCount": None,
             "addedPaths": [], "compileEvidence": None, "partitionMatches": None, "classification": None,
             "failed": []}
    if not facts["present"]:
        return facts
    data = path.read_bytes()
    facts["sha256"] = sha256(data)
    try:
        value = json.loads(data.decode("utf-8"))
    except ValueError:
        value = None
    value = value if isinstance(value, dict) else {}
    facts["sha256Matches"] = (isinstance(summary, dict) and summary.get("path") == SHARED_DELTA
                              and summary.get("sha256") == facts["sha256"])
    facts["canonical"] = bool(value) and data == canonical_json(value)
    counts = {key: value.get(key) for key in ("addedCount", "changedCount", "removedCount")}
    facts.update(counts)
    facts["countsMatch"] = (isinstance(summary, dict) and all(type(v) is int for v in counts.values())
                            and all(summary.get(key) == v for key, v in counts.items()))
    added = value.get("added") if isinstance(value.get("added"), list) else []
    facts["addedPaths"] = [item.get("path") for item in added[:SHARED_DELTA_LISTED] if isinstance(item, dict)]
    facts["compileEvidence"] = value.get("compileEvidence")
    facts["partitionMatches"] = value.get("partitionID") == partition_id
    facts["classification"] = (value.get("developmentOnly"), value.get("acceptance")) == (True, False)
    facts["failed"] = [name for name, ok in (
        ("sha256", facts["sha256Matches"]), ("canonical", facts["canonical"]), ("counts", facts["countsMatch"]),
        ("compileEvidence", facts["compileEvidence"] == []), ("partition", facts["partitionMatches"]),
        ("classification", facts["classification"])) if not ok]
    return facts


def consumer_payload_facts(adir, reference, partition_id):
    """Restore receipt, before/after fingerprints and DerivedData delta against the producer receipt."""
    restore = read_json_file(adir / "v23-shared-restore.json")
    metadata_sha = file_sha(adir / "v23-shared-payload.json")
    archive = (restore or {}).get("archive") or {}
    facts = {"present": isinstance(restore, dict), "archiveSHA256": archive.get("sha256"),
             "archiveBytes": archive.get("bytes"), "metadataSHA256": (restore or {}).get("metadataSHA256"),
             "metadataFileSHA256": metadata_sha, "restoreSeconds": (restore or {}).get("restoreSeconds"),
             "matchesProducer": None}
    if facts["present"] and reference is not None:
        facts["matchesProducer"] = (
            (facts["archiveSHA256"], facts["archiveBytes"], facts["metadataSHA256"], metadata_sha,
             restore.get("productsTreeSHA256"), restore.get("xctestrunSHA256"), restore.get("payloadArtifactName"))
            == (reference["archiveSHA256"], reference["archiveBytes"], reference["metadataSHA256"],
                reference["metadataSHA256"], reference["productsTreeSHA256"], reference["xctestrunSHA256"],
                reference["payloadArtifactName"]))
    fingerprints, raw = {}, {}
    for phase in ("before", "after"):
        value = read_json_file(adir / f"v23-shared-fingerprint-{phase}.json")
        if not isinstance(value, dict):
            fingerprints[phase] = {"present": False, "matchesProducer": None}
            continue
        raw[phase] = value
        fingerprints[phase] = {
            "present": True, "productsTreeSHA256": value.get("productsTreeSHA256"),
            "xctestrunSHA256": value.get("xctestrunSHA256"), "entryCount": value.get("entryCount"),
            "partitionMatches": value.get("partitionID") == partition_id,
            "selfReportedMatch": value.get("matchesProducer"),
            "buildEvidence": value.get("buildEvidence"), "error": value.get("error"),
            "matchesProducer": None if reference is None else (
                value.get("phase") == phase and value.get("matchesProducer") is True
                and value.get("partitionID") == partition_id
                and value.get("buildEvidence") == [] and value.get("error") is None
                and (value.get("productsTreeSHA256"), value.get("xctestrunSHA256"))
                == (reference["productsTreeSHA256"], reference["xctestrunSHA256"]))}
    if "after" in raw:
        before = raw.get("before")
        fingerprints["after"]["selfReportedMatchesBefore"] = raw["after"].get("matchesBefore")
        fingerprints["after"]["matchesBefore"] = (
            raw["after"].get("matchesBefore") is True and before is not None
            and all(raw["after"].get(key) == before.get(key) for key in FINGERPRINT_PRODUCT_KEYS))
    build_evidence = [name for name in SHARED_BUILD_EVIDENCE if (adir / name).exists()]
    return facts, fingerprints, build_evidence, delta_facts(adir, raw.get("after"), partition_id)


def summarize_producer(directory, job, state, names, run_id, head, plan_sha, checks):
    producer = {"job": job_timing(job), "artifact": state, "selectionMatchesDispatch": None,
                "admission": admission_facts(None, None, None, None, None, None, None),
                "build": {"succeeded": None, "swiftErrors": None, "swiftWarnings": None, "logPresent": False},
                "testEvidence": [], "receipt": None}
    producer["build"].update(stepConclusion=(job_step(job, SHARED_BUILD_STEP) or {}).get("conclusion"),
                             stepSeconds=step_seconds(job, SHARED_BUILD_STEP))
    if not state["extracted"] or not state["digestMatches"]:
        return producer, None
    pdir = directory / "artifacts" / "producer"
    build_log = pdir / "build-smoke.log"
    if build_log.is_file():
        producer["build"].update(build_facts(build_log.read_text(encoding="utf-8", errors="replace")),
                                 logPresent=True)
    producer["testEvidence"] = [name for name in SHARED_TEST_EVIDENCE if (pdir / name).exists()]
    if producer["testEvidence"]:
        checks.append(f"producer: test evidence present {producer['testEvidence']}")
    selected = pdir / "ci-selection.selected.json"
    producer["selectionMatchesDispatch"] = file_sha(selected) == plan_sha if selected.is_file() else None
    if producer["selectionMatchesDispatch"] is False:
        checks.append("producer: selected plan differs from the dispatch-resolved plan")
    producer["admission"] = admission_facts(read_json_file(pdir / "native-admission.json"), "producer", None,
                                            run_id, head, plan_sha, names["payload"])
    if producer["admission"]["present"] and not (producer["admission"]["planSHA256Matches"]
                                                 and producer["admission"]["bindingMatches"]):
        checks.append("producer: admission record differs from the dispatched plan/run/payload binding")
    receipt = read_json_file(pdir / "v23-shared-payload-receipt.json")
    metadata_sha = file_sha(pdir / "v23-shared-payload.json")
    if not isinstance(receipt, dict) or metadata_sha is None:
        checks.append("producer: payload receipt or metadata missing; consumer payload bindings unverified")
        return producer, None
    archive = receipt.get("archive") or {}
    metadata = read_json_file(pdir / "v23-shared-payload.json") or {}
    reference = {"archiveSHA256": archive.get("sha256"), "archiveBytes": archive.get("bytes"),
                 "metadataSHA256": receipt.get("metadataSHA256"),
                 "productsTreeSHA256": receipt.get("productsTreeSHA256"),
                 "xctestrunSHA256": receipt.get("xctestrunSHA256"),
                 "payloadArtifactName": receipt.get("payloadArtifactName")}
    consistent = (receipt.get("metadataSHA256") == metadata_sha
                  and receipt.get("productsTreeSHA256") == (metadata.get("products") or {}).get("treeSHA256")
                  and receipt.get("xctestrunSHA256") == (metadata.get("products") or {}).get("xctestrunSHA256")
                  and receipt.get("payloadArtifactName") == names["payload"]
                  and (receipt.get("head"), str(receipt.get("runID")), str(receipt.get("runAttempt")))
                  == (head, str(run_id), "1")
                  and (receipt.get("developmentOnly"), receipt.get("acceptance")) == (True, False))
    producer["receipt"] = dict(reference, metadataFileSHA256=metadata_sha, consistent=consistent)
    if not consistent:
        checks.append("producer: payload receipt is inconsistent with its metadata, run or payload name")
    return producer, reference


def build_shared_summary(run_id, directory, dispatched):
    plan = dispatched["resolvedSelection"]
    plan_sha = dispatched.get("resolvedSelectionSHA256")
    partitions = shared_partitions_for(dispatched)
    ids = partitions["partitionIDs"]
    head = dispatched["head"]
    run_record = json.loads((directory / "run.json").read_text(encoding="utf-8"))
    jobs = json.loads((directory / "jobs.json").read_text(encoding="utf-8"))["jobs"]
    artifacts = json.loads((directory / "artifacts.json").read_text(encoding="utf-8"))["artifacts"]
    matched = match_shared_artifacts(artifacts, run_id, head, ids)
    found = match_shared_jobs(jobs, ids)
    names = matched["names"]
    integrity = matched["problems"] + found["problems"]
    checks = []

    # The payload artifact is recorded from the listing only; it is never downloaded.
    payload = matched["payload"]
    payload_record = None if payload is None else {
        "name": payload["name"], "id": payload["id"], "sizeInBytes": payload.get("size_in_bytes"),
        "digest": payload.get("digest"), "expired": payload.get("expired"),
        "downloaded": (directory / f"artifact-{payload['id']}.zip").exists()}
    if payload_record and payload_record["downloaded"]:
        integrity.append("payload artifact zip is present in the evidence; it must never be downloaded")
    upload = job_step(found["producer"], SHARED_PAYLOAD_UPLOAD_STEP)
    if payload is None and upload is not None and upload.get("conclusion") == "success":
        integrity.append(f"payload artifact {names['payload']} is not listed although the producer uploaded it")

    state, problems = artifact_state(directory, "producer", names["producer"], matched["producer"],
                                     found["producer"])
    integrity += problems
    producer, reference = summarize_producer(directory, found["producer"], state, names, run_id, head,
                                             plan_sha, checks)
    if found["producer"] is not None and found["producer"].get("conclusion") == "success" \
            and len(found["consumers"]) != len(ids):
        checks.append(f"{len(found['consumers'])} consumer jobs for {len(ids)} plan partitions")

    owner = {s: x for x in ids for s in partitions["selectors"][x]}
    tests = {s: {"result": "NotStarted", "seconds": None, "failures": [], "lines": 0, "partition": owner.get(s)}
             for s in plan["unitTestSelectors"]}
    declared_all, declared_from = [], {"artifact": 0, "dispatch": 0}
    timings, diagnostics, unselected = [], [], set()
    consumer_tier = consumer_budgets = None
    consumer_tiers = {}  # tier -> budgets, from each executed selection (D50C, D90S solo)
    entries = {}
    for pid in ids:
        job = found["consumers"].get(pid)
        state, problems = artifact_state(directory, pid, names["consumers"][pid], matched["consumers"][pid], job)
        integrity += problems
        adir = directory / "artifacts" / pid if state["extracted"] and state["digestMatches"] else None
        expected = partitions["selectors"][pid]
        entry = {"status": "NoJob" if job is None else (job.get("conclusion") if job.get("status") == "completed"
                                                         else job.get("status")),
                 "job": job_timing(job), "artifact": state, "methods": len(expected),
                 "selectionSource": "dispatch", "selectionMatchesDispatch": None,
                 "admission": admission_facts(None, None, None, None, None, None, None),
                 "restore": None, "fingerprints": None, "buildEvidence": None, "afterBuildEvidence": None,
                 "derivedDataDelta": None}
        declared = expected
        if adir is not None:
            selection = read_json_file(adir / "ci-selection.selected.json")
            if isinstance(selection, dict) and isinstance(selection.get("unitTestSelectors"), list):
                declared = selection["unitTestSelectors"]
                binding = selection.get("sharedCoverage") if isinstance(selection.get("sharedCoverage"), dict) else {}
                entry["selectionSource"] = "artifact"
                entry["selectionMatchesDispatch"] = (
                    declared == expected and binding.get("partitionID") == pid
                    and binding.get("partitionIDs") == ids
                    and binding.get("partitionsSHA256") == partitions["partitionsSHA256"])
                if not entry["selectionMatchesDispatch"]:
                    checks.append(f"{pid}: executed selection differs from the dispatched partition")
                if consumer_budgets is None:
                    consumer_tier = selection.get("tier")
                    consumer_budgets = {k: selection.get(k) for k in BUDGET_KEYS}
                consumer_tiers.setdefault(str(selection.get("tier")), {k: selection.get(k) for k in BUDGET_KEYS})
            entry["admission"] = admission_facts(read_json_file(adir / "native-admission.json"), "consumer", pid,
                                                 run_id, head, plan_sha, names["payload"])
            if entry["admission"]["present"] and not (entry["admission"]["planSHA256Matches"]
                                                      and entry["admission"]["bindingMatches"]):
                checks.append(f"{pid}: admission record differs from the dispatched plan/run/payload binding")
            (entry["restore"], entry["fingerprints"], entry["buildEvidence"],
             entry["derivedDataDelta"]) = consumer_payload_facts(adir, reference, pid)
            entry["afterBuildEvidence"] = entry["fingerprints"]["after"].get("buildEvidence")
            if not entry["restore"]["present"]:
                checks.append(f"{pid}: restore receipt missing")
            elif entry["restore"]["matchesProducer"] is False:
                checks.append(f"{pid}: restore archive/metadata differ from the producer receipt")
            for phase, value in entry["fingerprints"].items():
                if not value["present"]:
                    checks.append(f"{pid}: fingerprint {phase} missing")
                elif value["matchesProducer"] is False:
                    checks.append(f"{pid}: fingerprint {phase} differs from the producer or partition "
                                  "or shows build evidence")
            if entry["fingerprints"]["after"].get("matchesBefore") is False:
                checks.append(f"{pid}: fingerprint after does not match before (matchesBefore/products/entryCount)")
            delta = entry["derivedDataDelta"]
            if not delta["present"]:
                checks.append(f"{pid}: DerivedData delta missing")
            elif delta["failed"]:
                checks.append(f"{pid}: DerivedData delta fails {delta['failed']}")
            if entry["buildEvidence"]:
                checks.append(f"{pid}: consumer build evidence present {entry['buildEvidence']}")
        declared_from[entry["selectionSource"]] += 1
        declared_all.extend(declared)
        log, source = shared_test_log(directory, adir, job)
        results, extra_lines, partition_timings, partition_diagnostics = parse_test_log(log, declared)
        counts = collections.Counter(value["result"] for value in results.values())
        structured = adir / "unit-test-results.json" if adir is not None else None
        entry.update(
            logSource=source, resultsFromJobLog=source in ("job-step-log", "job-log"),
            counts=dict(sorted(counts.items())),
            seconds=round(sum(value["seconds"] or 0 for value in results.values()), 3),
            failures={k: v["failures"] for k, v in results.items() if v["result"] == "Failed"},
            interrupted=sorted(k for k, v in results.items() if v["result"] == "Interrupted"),
            namedDiagnostics=partition_diagnostics[:50], namedDiagnosticCount=len(partition_diagnostics),
            protectedFileTiming=partition_timings[-20:], unselectedTestLines=sorted(extra_lines),
            duplicatedTestLines=sorted(k for k, v in results.items() if v["lines"] > 2),
            structuredResults=({"available": True, "bytes": structured.stat().st_size}
                               if structured is not None and structured.is_file() and structured.stat().st_size
                               else {"available": False}))
        for key, value in results.items():
            if owner.get(key) == pid:
                tests[key] = dict(value, partition=pid)
        timings += partition_timings
        diagnostics += [f"{pid}: {line}" for line in partition_diagnostics]
        unselected |= extra_lines
        entries[pid] = entry

    counter = collections.Counter(declared_all)
    plan_selectors = plan["unitTestSelectors"]
    plan_set = set(plan_selectors)
    dispatch_union = [s for x in ids for s in partitions["selectors"][x]]
    coverage = {"planSelectors": len(plan_selectors), "partitionCount": len(ids),
                "declaredSelectors": len(declared_all), "declaredFrom": declared_from,
                "missing": [s for s in plan_selectors if counter[s] == 0],
                "duplicates": sorted(s for s, c in counter.items() if c > 1),
                "extra": sorted(s for s in counter if s not in plan_set),
                "dispatchPartitionsExact": sorted(dispatch_union) == sorted(plan_selectors)
                and len(set(dispatch_union)) == len(dispatch_union)}
    coverage["exact"] = (not (coverage["missing"] or coverage["duplicates"] or coverage["extra"])
                         and len(plan_set) == len(plan_selectors) and coverage["dispatchPartitionsExact"])
    coverage["executed"] = sum(1 for value in tests.values() if value["result"] != "NotStarted")
    coverage["notExecuted"] = len(tests) - coverage["executed"]
    if not coverage["exact"]:
        checks.append(f"coverage union is not exactly the plan: {len(coverage['missing'])} missing, "
                      f"{len(coverage['duplicates'])} duplicate, {len(coverage['extra'])} extra")

    counts = dict(sorted(collections.Counter(value["result"] for value in tests.values()).items()))
    statuses = dict(sorted(collections.Counter(entries[x]["status"] for x in ids).items()))
    shared_jobs = [found["selection"], found["producer"], *found["consumers"].values()]
    job_records = {"total": len(jobs),
                   "selection": job_timing(found["selection"]), "producer": job_timing(found["producer"]),
                   "consumers": {x: job_timing(found["consumers"].get(x)) for x in ids},
                   "placeholders": [{"name": j.get("name"), "conclusion": j.get("conclusion")}
                                    for j in found["placeholders"]],
                   "otherNonSkipped": sorted(j.get("name", "") for j in found["other"]
                                             if j.get("conclusion") != "skipped"),
                   "runnerSeconds": round(sum(job_timing(j)["runSeconds"] or 0 for j in shared_jobs
                                              if j is not None), 3),
                   "elapsedSeconds": seconds_between(run_record.get("run_started_at"), run_record.get("updated_at"))}
    steps = [{"job": job["name"], "step": step["name"], "conclusion": step["conclusion"],
              "startedAt": step.get("started_at"), "completedAt": step.get("completed_at")}
             for job in jobs for step in job.get("steps", []) if step["conclusion"] != "skipped"]
    missing_artifacts = [x for x in ["producer", *ids]
                         if not (producer["artifact"] if x == "producer"
                                 else entries[x]["artifact"])["extracted"]]
    if len(consumer_tiers) > 1:
        # Mixed consumer tiers (owner decision 16): name every tier and its budgets.
        consumer_tier, consumer_budgets = sorted(consumer_tiers), dict(sorted(consumer_tiers.items()))
    return {"runID": run_id, "head": run_record["head_sha"], "parent": dispatched.get("parent"),
            "selection": dispatched["selection"], "conclusion": run_record["conclusion"], "route": "shared-build",
            "tier": {"producer": plan.get("tier"), "consumer": consumer_tier},
            "budgets": {"producer": {k: plan.get(k) for k in BUDGET_KEYS}, "consumer": consumer_budgets},
            "selectionSource": "artifact" if producer["selectionMatchesDispatch"] is not None else "dispatch-resolved",
            "selectionMatchesDispatch": producer["selectionMatchesDispatch"],
            "planSHA256": plan_sha, "partitionsSHA256": partitions["partitionsSHA256"], "partitionIDs": ids,
            "artifactMissing": bool(missing_artifacts), "artifactsNotExtracted": missing_artifacts,
            "resultsFromJobLog": sorted(x for x in ids if entries[x]["resultsFromJobLog"]),
            "build": producer["build"], "producer": producer, "payloadArtifact": payload_record,
            "partitions": {x: entries[x] for x in ids}, "partitionStatuses": statuses,
            "coverage": coverage, "jobs": job_records, "counts": counts, "tests": tests,
            "unselectedTestLines": sorted(unselected),
            "duplicatedTestLines": sorted(k for k, v in tests.items() if v["lines"] > 2),
            "protectedFileTiming": timings[-60:], "namedDiagnostics": diagnostics[:200], "devBatch": None,
            "unexpectedArtifacts": matched["unexpected"],
            "integrity": {"ok": not integrity, "problems": integrity},
            "sharedChecks": {"ok": not checks, "problems": checks},
            "steps": steps, "acceptance": False, "releaseReady": False, "atUTC": now()}


def write_summary(directory, summary):
    target = directory / "summary.json"
    if target.exists():
        target = directory / f"summary-{int(time.time())}.json"
    write_new(target, summary)
    return summary


def summarize_shared(run_id, directory, dispatched):
    return write_summary(directory, build_shared_summary(run_id, directory, dispatched))


def printable(summary):
    if summary.get("route") != "shared-build":
        return {k: v for k, v in summary.items() if k not in ("tests", "steps")}
    compact = {k: v for k, v in summary.items()
               if k not in ("tests", "steps", "partitions", "producer", "jobs", "coverage")}
    compact["coverage"] = {k: (len(v) if isinstance(v, list) else v) for k, v in summary["coverage"].items()}
    compact["producerBuild"] = summary["producer"]["build"]
    return compact


def collect_shared(run_id, directory, dispatched, observed):
    """Sole collector for one shared-build original: every evidence artifact, never the payload."""
    ids = shared_partitions_for(dispatched)["partitionIDs"]
    retain_once(directory, "run.json", lambda: observed)
    retain_once(directory, "jobs.json", lambda: paginated(
        f"repos/{REPO}/actions/runs/{run_id}/attempts/1/jobs", "jobs", SHARED_MAX_JOBS))
    retain_once(directory, "run-logs.zip", lambda: api_bytes(f"repos/{REPO}/actions/runs/{run_id}/attempts/1/logs"))
    artifacts = json.loads(retain_once(directory, "artifacts.json", lambda: paginated(
        f"repos/{REPO}/actions/runs/{run_id}/artifacts", "artifacts", SHARED_MAX_ARTIFACTS)).read_text(encoding="utf-8"))
    matched = match_shared_artifacts(artifacts["artifacts"], run_id, dispatched["head"], ids)
    (directory / "artifacts").mkdir(exist_ok=True)
    for label, artifact in [("producer", matched["producer"])] + [(x, matched["consumers"][x]) for x in ids]:
        if artifact is None or artifact.get("expired"):
            continue
        archive = retain_once(directory, f"artifact-{artifact['id']}.zip",
                              lambda identifier=artifact["id"]: api_bytes(
                                  f"repos/{REPO}/actions/artifacts/{identifier}/zip"))
        digest = "sha256:" + sha256(archive.read_bytes()).lower()
        if artifact.get("digest") and artifact["digest"] != digest:
            continue  # never extracted; the summary records the integrity failure
        if not (directory / "artifacts" / label).exists():
            extract(archive, directory / "artifacts" / label)
    if not (directory / "run-logs").exists():
        extract(directory / "run-logs.zip", directory / "run-logs")
    check_identity(api(f"repos/{REPO}/actions/runs/{run_id}"), dispatched)
    summary = build_shared_summary(run_id, directory, dispatched)
    walk_root = Path("\\\\?\\" + str(directory.resolve())) if os.name == "nt" else directory
    manifest = {p.relative_to(walk_root).as_posix(): sha256(p.read_bytes())
                for p in sorted(walk_root.rglob("*")) if p.is_file()
                and not (p.parent == walk_root and (p.name == "manifest.json" or p.name.startswith("summary")))}
    notes = summary["integrity"]["problems"] + [f"unexpected artifact {name}" for name in matched["unexpected"]]
    write_new(directory / "manifest.json", {"runID": run_id, "files": manifest, "notes": notes, "atUTC": now()})
    write_summary(directory, summary)
    print(json.dumps(printable(summary), indent=2))
    for pid, entry in summary["partitions"].items():
        job = entry["job"] or {}
        print(pid, entry["status"], entry["counts"], "test", job.get("testSeconds"), "log", entry["logSource"])
    for key, value in summary["tests"].items():
        if value["result"] != "Passed":
            print(value["result"], value["seconds"], value["partition"], key)
    if not summary["integrity"]["ok"]:
        raise SystemExit("integrity problems (all evidence retained; manifest and summary written): "
                         + "; ".join(summary["integrity"]["problems"][:20]))
    return summary


def cancel(run_id, reason):
    """Cancel one active original recorded as development; ledger intent before, completion after.

    The run keeps its dispatch record and is collected as usual afterwards."""
    reason = (reason or "").strip()
    if not reason:
        raise SystemExit("cancel requires a non-empty --reason")
    if len(reason) > MAX_REASON:
        raise SystemExit(f"--reason exceeds {MAX_REASON} characters")
    dispatched, why = recorded_development(run_id)
    if why:
        raise SystemExit(f"cancel is only for recorded development runs: {why}")
    if any(e.get("event") == "cancel-complete" and e.get("runID") == run_id and e.get("exitCode") == 0
           for e in ledger_events()):
        raise SystemExit(f"run {run_id} was already cancelled through this ledger; wait for it and collect it")
    observed = api(f"repos/{REPO}/actions/runs/{run_id}")
    check_identity(observed, dispatched)
    if observed.get("status") not in ACTIVE_STATUSES:
        raise SystemExit(f"run {run_id} is {observed.get('status')}, not active; nothing to cancel")
    argv = ["gh", "run", "cancel", str(run_id), "--repo", REPO]
    base = {"runID": run_id, "head": dispatched["head"], "selection": dispatched["selection"],
            "kind": "development", "url": dispatched.get("url")}
    append_ledger(dict(base, event="cancel-intent", reason=reason, statusBefore=observed.get("status"),
                       argv=argv, requestedAtUTC=now()))
    try:
        result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
                                errors="replace")
        code, error = result.returncode, ((result.stderr or "") + (result.stdout or "")).strip()[-500:]
    except OSError as caught:
        code, error = None, str(caught)[-500:]
    completion = dict(base, event="cancel-complete", exitCode=code, completedAtUTC=now())
    if code != 0:
        completion["error"] = error
    append_ledger(completion)
    if code != 0:
        raise SystemExit(f"gh run cancel failed ({code}); recorded in the ledger: {error}")
    print(json.dumps(completion, indent=2, sort_keys=True))
    return completion



def phase1_review_root(gate, head, *, test_only=False, create=False):
    gate.require(type(head) is str and re.fullmatch(r"[0-9a-f]{40}", head), "review head path")
    gate.require(type(test_only) is bool, "explicit review fixture mode")
    marker = EVIDENCE / ".phase1-test-only"
    if test_only:
        gate.require(gate.regular_bytes(marker) == b"SYNTHETIC PROTOCOL FIXTURES ONLY\n", "marked fixture evidence root")
    else:
        gate.require(not marker.exists() and not marker.is_symlink(), "test-only evidence root is not real provenance")
    parent = EVIDENCE / "v23-phase1-reviews"
    directory = parent / head
    if create:
        gate.durable_directory(parent)
        gate.durable_directory(directory)
    for path in (EVIDENCE, parent, directory):
        if path.exists() or path.is_symlink():
            gate.require(stat.S_ISDIR(path.lstat().st_mode), "regular review directory")
    return directory


def phase1_review_gallery(gate, directory, plan, run_id):
    """Bind actual verified RUI1 presentation bytes; never assert human viewing."""
    artifact = directory / "artifacts/rui1"
    proof_raw = gate.regular_bytes(artifact / "rui1-review.json", limit=gate.MAX_REVIEW_BYTES)
    proof = gate.decode(proof_raw, limit=gate.MAX_REVIEW_BYTES)
    presentation = gate.regular_bytes(artifact / "rui1-review.html", limit=gate.MAX_REVIEW_BYTES)
    catalogue = git_bytes("show", f"{plan['head']}:{gate.CATALOGUE}")
    gate.require(gate.sha(catalogue) == plan["sources"][gate.CATALOGUE], "review frozen catalogue")
    # Run the real existing verifier from the exact frozen source closure. This
    # verifies a machine-generated gallery, not any human or independent approval.
    with tempfile.TemporaryDirectory(prefix="phase1-review-source-") as temporary:
        with tarfile.open(fileobj=io.BytesIO(git_bytes("archive", "--format=tar", plan["head"]))) as archive:
            archive.extractall(temporary, filter="data")
        for relative, digest in plan["sources"].items():
            gate.require(gate.sha(gate.regular_bytes(Path(temporary) / relative, limit=32 * 1024 * 1024)) == digest,
                         "review exact checker source")
        command = [sys.executable, "-B", "Scripts/v23-ui-evidence.py", "collect", "--root", temporary,
                   "--artifact", str(artifact.resolve()), "--expected-head", plan["head"], "--expected-run", str(run_id)]
        checked = subprocess.run(command, cwd=temporary, capture_output=True, timeout=180)
        gate.require(checked.returncode == 0, "review RUI1 checker failed: " + repr(checked.stderr[-2000:]))
        gate.require(len(checked.stdout) <= gate.MAX_REVIEW_BYTES, "review checker output bound")
        gate.exact(json.loads(checked.stdout, object_pairs_hook=gate.object_pairs), proof, "review verified RUI1 proof")
    gate.require(proof.get("head") == plan["head"] and proof.get("runID") == str(run_id)
                 and proof.get("runAttempt") == "1" and proof.get("selectionSHA256") == plan["selectionSHA256"]
                 and proof.get("catalogueSHA256") == gate.sha(catalogue)
                 and proof.get("humanReviewCompleted") is False, "review gallery original identity")
    # The original verifier checks exact state coverage, image/audit digests and
    # generated HTML. Retain a digest of every referenced attachment as a bundle.
    attachments = {}
    for state in proof["states"]:
        for key in ("image", "audit"):
            name = state[key]
            gate.require(type(name) is str and name and "\\" not in name and not Path(name).is_absolute()
                         and all(p not in ("", ".", "..") for p in name.split("/")), "review attachment path")
            digest = gate.sha(gate.regular_bytes(artifact / name, limit=64 * 1024 * 1024))
            gate.require(digest == state[key + "SHA256"] and name not in attachments, "review attachment bytes")
            attachments[name] = digest
    return {"catalogueSHA256": gate.sha(catalogue), "proofSHA256": gate.sha(proof_raw),
            "presentationSHA256": gate.sha(presentation), "checklistSHA256": gate.sha(presentation),
            "attachmentsSHA256": gate.sha(gate.canonical(attachments))}


def phase1_review_bindings(gate, request):
    """Read exact historical originals. This is not a current API authority check."""
    originals, plans, gallery = [], [], None
    for expected in request["originals"]:
        context = phase1_original_context(expected["runID"], retention_only=True)
        _, directory, dispatched, plan, attempt, dispatch_raw, registration_raw, attempt_raw, _ = context
        gate.require((plan["head"], plan["tree"]) == (request["head"], request["tree"]), "review exact candidate")
        gate.require(gate.sha(gate.regular_bytes(ROOT / "Scripts/v23-phase1-gates.py", limit=4 * 1024 * 1024))
                     == plan["sources"]["Scripts/v23-phase1-gates.py"], "review registrar exact contract source")
        raw = gate.regular_bytes(directory / "manifest.json", limit=32 * 1024 * 1024)
        gate.require(gate.sha(raw) == expected["manifestSHA256"], "review expected original manifest")
        manifest = gate.decode(raw, limit=32 * 1024 * 1024)
        gate.require(type(manifest) is dict and set(manifest) == {"schema", "runID", "runAttempt", "files", "rawProofSHA256"}
                     and manifest["schema"] == "v23-phase1-original-manifest.v1", "review original manifest schema")
        gate.exact([manifest["runID"], manifest["runAttempt"]], [expected["runID"], 1], "review manifest original")
        before = phase1_file_manifest(directory)
        gate.require(before.pop("manifest.json") == gate.sha(raw), "review manifest changed during census")
        gate.exact(before, manifest["files"], "review complete sealed original census")
        proof_raw = gate.regular_bytes(directory / "phase1-raw-proof.json", limit=gate.MAX_REVIEW_BYTES)
        proof = gate.decode(proof_raw, limit=gate.MAX_REVIEW_BYTES)
        gate.require(gate.sha(proof_raw) == manifest["rawProofSHA256"], "review raw proof digest")
        gate.exact([proof.get(k) for k in ("schema", "runID", "runAttempt", "head", "tree", "planSHA256",
                     "status", "functionalQualification", "acceptance", "releaseReady")],
                   ["v23-phase1-raw-proof.v1", expected["runID"], 1, plan["head"], plan["tree"], attempt["planSHA256"],
                    "INCOMPLETE", gate.PENDING, False, False], "review pending raw original binding")
        gate.exact([proof.get(k) for k in ("simulatorProtection", "physicalProtection",
            "physicalProtectionReleaseBlocker", "providerQualification")],
            ["UNSUPPORTED", "UNVERIFIED/DEFERRED", True, False], "review separate protection status")
        claim_raw = gate.regular_bytes(directory / "collector.claim.json")
        gate.exact(gate.decode(claim_raw), {"schema": "v23-phase1-sole-collector.v1", "runID": expected["runID"],
            "runAttempt": 1, "collectorID": attempt["collectorID"], "collectorSHA256": attempt["collectorSHA256"],
            "planSHA256": attempt["planSHA256"], "attemptSHA256": gate.sha(attempt_raw),
            "dispatchSHA256": gate.sha(dispatch_raw), "registrationSHA256": gate.sha(registration_raw)}, "review sole claim")
        if request["subject"] == "owner-critical-states":
            gate.require(plan["selection"] == gate.RUI1, "owner RUI1 original")
            gallery = phase1_review_gallery(gate, directory, plan, expected["runID"])
            gate.exact(gallery, request["gallery"], "review expected presented bundle")
        after = phase1_file_manifest(directory)
        gate.require(after.pop("manifest.json") == gate.sha(raw), "review manifest changed after binding")
        gate.exact(after, before, "review original changed while binding")
        originals.append({**expected, "selection": plan["selection"], "planSHA256": attempt["planSHA256"],
            "attemptSHA256": gate.sha(attempt_raw), "registrationSHA256": gate.sha(registration_raw),
            "dispatchSHA256": gate.sha(dispatch_raw), "discoverySHA256": dispatched["phase1DiscoverySHA256"],
            "claimSHA256": gate.sha(claim_raw), "rawProofSHA256": gate.sha(proof_raw),
            "rawProofStatus": proof["status"], "originalAttribution": proof["originalAttribution"]})
        plans.append(plan)
    selections = sorted(p["selection"] for p in plans)
    needed = {"shared-cold-original": [gate.SHARED], "rui1-cold-original": [gate.RUI1],
              "owner-critical-states": [gate.RUI1], "candidate-integration": sorted(gate.SELECTIONS)}[request["subject"]]
    gate.exact(selections, needed, "review subject original selections")
    gate.require(all(p["sources"] == plans[0]["sources"] and p["policies"] == plans[0]["policies"] for p in plans),
                 "review common frozen source and policy")
    return {"originals": originals, "sources": plans[0]["sources"], "policies": plans[0]["policies"], "gallery": gallery}


def phase1_read_reviews(gate, head, *, test_only=False):
    directory = phase1_review_root(gate, head, test_only=test_only)
    names = sorted(p.name for p in directory.iterdir()) if directory.exists() else []
    gate.require(len(names) <= 1000 and names == ["%06d.json" % i for i in range(len(names))], "closed review history census")
    census = phase1_file_manifest(directory) if directory.exists() else {}
    gate.exact(sorted(census), names, "regular review history files")
    entries, previous, retained = [], None, 0
    for index, name in enumerate(names):
        raw = gate.regular_bytes(directory / name, limit=gate.MAX_REVIEW_BYTES)
        gate.require(gate.sha(raw) == census[name], "review history changed during read")
        retained += len(raw)
        gate.require(retained <= 64 * 1024 * 1024, "review history aggregate bound")
        value = gate.decode(raw, limit=gate.MAX_REVIEW_BYTES)
        gate.require(type(value) is dict and set(value) == {"schema", "index", "previousSHA256", "capturedAtUTC",
            "request", "messageUTF8", "contextUTF8", "bindings", "status", "trustBoundary",
            "functionalQualification", "acceptance", "releaseReady"}, "closed review record")
        request = gate.validate_review_request(value["request"], test_only=test_only)
        gate.require(request["head"] == head, "review history head")
        gate.require(type(value["messageUTF8"]) is str and type(value["contextUTF8"]) is str, "review retained UTF8")
        expected = gate.make_review_record(request, value["messageUTF8"].encode(), value["contextUTF8"].encode(),
            phase1_review_bindings(gate, request), index=index, previous=previous,
            captured_at=value["capturedAtUTC"], test_only=test_only)
        gate.exact(value, expected, "review derived immutable record")
        gate.require(not entries or value["capturedAtUTC"] >= entries[-1]["capturedAtUTC"], "review capture order")
        entries.append(value)
        previous = gate.sha(raw)
    # Use duplicate-key-aware parsing for the new authority boundary. Preserve
    # generic legacy ledger behavior elsewhere, including development callers.
    raw_ledger = gate.regular_bytes(LEDGER, limit=64 * 1024 * 1024) if LEDGER.exists() else b""
    rows = [json.loads(line, object_pairs_hook=gate.object_pairs) for line in raw_ledger.splitlines() if line.strip()]
    gate.require(all(type(row) is dict for row in rows), "review ledger object census")
    anchors = [row for row in rows if row.get("event") == "phase1-review" and row.get("head") == head]
    gate.exact(anchors, [{"event": "phase1-review", "head": head, "index": i,
        "reviewSHA256": gate.sha(gate.canonical(value)), "testOnly": test_only} for i, value in enumerate(entries)],
        "complete ledger-anchored review history")
    gate.exact(phase1_file_manifest(directory) if directory.exists() else {}, census, "review history changed after read")
    return entries


def register_phase1_review(request_path, message_path, context_path, *, test_only=False):
    """Factual local capture only. No speaker authentication, approval or API call."""
    gate = phase1_gates()
    request_raw = gate.regular_bytes(request_path, limit=gate.MAX_REVIEW_BYTES)
    request = gate.validate_review_request(gate.decode(request_raw, limit=gate.MAX_REVIEW_BYTES), test_only=test_only)
    message = gate.regular_bytes(message_path, limit=512 * 1024)
    context = gate.regular_bytes(context_path, limit=512 * 1024)
    directory = phase1_review_root(gate, request["head"], test_only=test_only, create=True)
    lock = EVIDENCE / "phase1-dispatch-active"
    lock.mkdir()  # Serializes reviews with original discovery/collection writers.
    try:
        entries = phase1_read_reviews(gate, request["head"], test_only=test_only)
        gate.require(not any(item["request"] == request for item in entries), "duplicate review request; never replace")
        value = gate.make_review_record(request, message, context, phase1_review_bindings(gate, request),
            index=len(entries), previous=gate.sha(gate.canonical(entries[-1])) if entries else None,
            captured_at=phase1_timestamp(), test_only=test_only)
        # Detect input replacement before persistence. Root controls this local
        # tree; this is binding verification, not hostile-filesystem isolation.
        for path, raw in ((request_path, request_raw), (message_path, message), (context_path, context)):
            gate.require(gate.regular_bytes(path, limit=gate.MAX_REVIEW_BYTES) == raw, "review source bytes changed")
        gate.write_immutable(directory / ("%06d.json" % len(entries)), gate.canonical(value))
        phase1_append_ledger(gate, {"event": "phase1-review", "head": request["head"], "index": len(entries),
            "reviewSHA256": gate.sha(gate.canonical(value)), "testOnly": test_only})
        entries = phase1_read_reviews(gate, request["head"], test_only=test_only)
        result = gate.review_pending_assessment(request["head"], entries)
        print(json.dumps(result, indent=2, sort_keys=True))
        return result
    finally:
        lock.rmdir()


def assess_phase1_reviews(head, *, test_only=False):
    gate = phase1_gates()
    phase1_review_root(gate, head, test_only=test_only)
    lock = EVIDENCE / "phase1-dispatch-active"
    lock.mkdir()
    try:
        result = gate.review_pending_assessment(head, phase1_read_reviews(gate, head, test_only=test_only))
        print(json.dumps(result, indent=2, sort_keys=True))
        return result
    finally:
        lock.rmdir()


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    dispatch_parser = commands.add_parser("dispatch")
    dispatch_parser.add_argument("--selection", required=True)
    dispatch_parser.add_argument("--kind", choices=KINDS,
                                 help="required for " + " and ".join(KIND_REQUIRED_SELECTIONS)
                                 + "; other selections default to gate")
    dispatch_parser.add_argument("--compiler-observation", action="store_true",
                                 help="explicit development D50 passive compiler observation at the reviewed pin")
    dispatch_parser.add_argument("--swift-driver-jobs-two", action="store_true",
                                 help="explicit development D50 Swift driver -j 2 experiment with passive observation")
    dispatch_parser.add_argument("--infra-retry-of", type=int, metavar="RUN_ID",
                                 help="--kind development only: the one rerun of this head+selection "
                                 "after RUN_ID's infrastructure failure")
    dispatch_parser.add_argument("--reason", help="required with --infra-retry-of")
    dispatch_parser.add_argument("--phase1-plan", metavar="PATH",
                                 help="reserved Phase1 contract; dispatch is disabled pending implementation/review")
    register_parser = commands.add_parser("preregister-phase1")
    register_parser.add_argument("--plan", type=Path, required=True,
                                 help="canonical pending candidate plan; no dispatch or gate credit")
    discovery_parser = commands.add_parser("discover-phase1")
    discovery_parser.add_argument("--plan", type=Path, required=True, help="disabled pending lifecycle review; never redispatch")
    review_parser = commands.add_parser("register-phase1-review", help="retain genuine source-message bytes; always pending")
    review_parser.add_argument("--request", type=Path, required=True)
    review_parser.add_argument("--message", type=Path, required=True)
    review_parser.add_argument("--context", type=Path, required=True)
    commands.add_parser("assess-phase1-reviews", help="report missing provenance; never qualify").add_argument("--head", required=True)
    collect_parser = commands.add_parser("collect")
    collect_parser.add_argument("--run", type=int, required=True)
    collect_parser.add_argument("--resume", action="store_true")
    commands.add_parser("summarize").add_argument("--run", type=int, required=True)
    cancel_parser = commands.add_parser("cancel")
    cancel_parser.add_argument("--run", type=int, required=True)
    cancel_parser.add_argument("--reason", required=True)
    args = parser.parse_args()
    if args.command == "dispatch" and (args.infra_retry_of is None) != (args.reason is None):
        parser.error("--infra-retry-of and --reason must be given together")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if args.command == "dispatch":
        dispatch(args.selection, args.kind, args.infra_retry_of, args.reason, args.phase1_plan,
                 args.compiler_observation, args.swift_driver_jobs_two)
    elif args.command == "preregister-phase1":
        preregister_phase1(args.plan)
    elif args.command == "discover-phase1":
        phase1_candidate_lifecycle(args.plan, discover=True)
    elif args.command == "register-phase1-review":
        register_phase1_review(args.request, args.message, args.context)
    elif args.command == "assess-phase1-reviews":
        assess_phase1_reviews(args.head)
    elif args.command == "collect":
        collect(args.run, args.resume)
    elif args.command == "cancel":
        cancel(args.run, args.reason)
    else:
        summary = summarize(args.run)
        print(json.dumps(printable(summary), indent=2))


if __name__ == "__main__":
    sys.exit(main())
