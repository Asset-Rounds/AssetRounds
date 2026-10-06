#!/usr/bin/env python3
"""Closed Phase 1 prospective gate plans. Stage A: registration, never gate credit.

No network, Git mutation, dispatch, qualification or approval implementation lives
here. A structurally valid plan declares an intended question; it proves no tests,
cold qualification, human review or physical protection. Activation remains closed
until the worker, collector and prerequisite verifiers have independent review.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat


SCHEMA = "v23-phase1-functional-gate-plan.v1"
REGISTRATION_SCHEMA = "v23-phase1-functional-gate-registration.v1"
CANDIDATE = "phase1-candidate-functional-v1"
EXACT_MAIN = "phase1-exact-main-functional-v1"
INTEGRATION_REF = "refs/heads/codex/v23-s10-integration-20260910"
PURPOSE_REFS = {CANDIDATE: INTEGRATION_REF, EXACT_MAIN: "refs/heads/main"}
BASE_MAIN = "b1d04ae5e684aa9c6807af655089efa1df8a7ed6"
SHARED = "v23-shared-coverage-d50x"
RUI1 = "v23-ui-batch-rui1"
SELECTIONS = (SHARED, RUI1)
REPOSITORY = "Asset-Rounds/AssetRounds"
PENDING = "PENDING_RAW_PROOF_AND_INDEPENDENT_REVIEW"
DECISION = "docs/design/v23/integration/PHASE1_SIMULATOR_FUNCTIONAL_GATE_DECISION_20260926.md"
DIAGNOSTIC = "docs/design/v23/integration/SIMULATOR_FILE_PROTECTION_DIAGNOSTIC.json"
POLICIES = {
    DECISION: "7FCAA0670436DD0FDEB3E3FF907B7DC68E3FD60BC1D375CA7D11A0B80749E523",
    DIAGNOSTIC: "4CE71CA43D961CF8A1318DA882BBA8989179700AB5202E5CE191185CFC0E44E0",
}
CATALOGUE = "docs/design/v23/integration/phase1-critical-states.json"
PARTITIONS = "Scripts/v23-coverage-partitions.json"
COLLECTOR = "Scripts/dev/v23-original.py"
# Exact source closure is also bound by the Git tree. No caller-selected paths.
SOURCES = (
    "Scripts/v23-phase1-gates.py", COLLECTOR, "Scripts/v23-native-ci.py",
    "Scripts/dev/v23-retained-payload.py",
    ".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml",
    ".github/workflows/ios-ci-shared-worker.yml", "Scripts/v23-shared-worker.sh",
    "Scripts/v23-ui-evidence.py", "Scripts/v23-ui-smoke.sh", "Scripts/v23-ui-batch.json",
    "Scripts/ci-selection-map.json", "Scripts/ci-selection.json", "Scripts/ci-worker-selection.jq",
    "Scripts/v23-selection-generator.py", "Scripts/v23-selection-manifest.json",
    "Scripts/build-smoke.sh", "Scripts/test-smoke.sh", "Scripts/ui-smoke.sh",
    "Scripts/run-with-timeout.sh", "Scripts/validate-required-evidence.sh",
    "Scripts/s10-4-build-payload.py", PARTITIONS, CATALOGUE, DECISION, DIAGNOSTIC,
)
ROUTE = {
    "repository": REPOSITORY, "workflow": ".github/workflows/ios-ci.yml",
    "executionLane": "github-xcode-26.6-acceptance", "provider": "github",
    "runnerLabel": "macos-26", "configuration": "Debug", "runAttempt": 1,
    "xcode": "26.6", "xcodeBuild": "17F113", "sdk": "26.5", "sdkBuild": "23F81a",
    "simulator": "iPhone 17", "runtime": "iOS 26.2", "runtimeBuild": "23C54",
    "budgets": {"D40P": [300, 2400, 0, 0, 3000], "D50C": [300, 0, 3000, 0, 3600],
                "D90S": [300, 0, 5400, 0, 6000], "RUI1": [300, 1800, 900, 900, 3900]},
    "rui1JobMinutes": 90,
}
CLASSIFICATION = {
    "functionalQualification": PENDING, "simulatorProtection": "UNSUPPORTED",
    "physicalProtection": "UNVERIFIED/DEFERRED", "physicalProtectionReleaseBlocker": True,
    "countsAsPerKindProtectionSuccess": False, "providerQualification": False,
    "acceptance": False, "releaseReady": False,
}
MAX_PLAN_BYTES = 32768
PLAN_INPUT = "v23_phase1_gate_plan"
EVENT_SCHEMA = "v23-phase1-original-event-binding.v1"
MAX_EVENT_BYTES = 1024 * 1024
PLAN_KEYS = {"schema", "purpose", "ref", "head", "tree", "baseMain", "selection",
             "selectionSHA256", "orderedUnitMethodsSHA256", "orderedUIMethodsSHA256",
             "sources", "policies", "route", "classification", "requestedAtUTC", "collector"}


class Refused(ValueError):
    """An explicitly named fail-closed admission or registration error."""


def require(value, message):
    if not value:
        raise Refused("Phase1 gate: " + message)


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
                       allow_nan=False) + "\n").encode("utf-8")


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def digest(value):
    return type(value) is str and re.fullmatch(r"[0-9A-F]{64}", value) is not None


def object_pairs(items):
    out = {}
    for key, value in items:
        require(key not in out, "duplicate JSON key " + key)
        out[key] = value
    return out


def decode(raw, limit=MAX_PLAN_BYTES):
    require(type(raw) is bytes and 0 < len(raw) <= limit, "bounded plan bytes")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=object_pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(Refused("nonfinite JSON")))
    except (ValueError, UnicodeError) as error:
        raise Refused("Phase1 gate: invalid JSON: " + str(error)) from error
    require(canonical(value) == raw, "noncanonical plan bytes")
    return value


def exact(value, expected, message):
    # JSON booleans and integers must not compare equal through Python's bool/int alias.
    require(canonical(value) == canonical(expected), message)


def validate_plan(value):
    if type(value) is dict and value.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return validate_plan_v2(value)
    require(type(value) is dict and set(value) == PLAN_KEYS, "closed plan keys")
    require(value["schema"] == SCHEMA, "plan schema")
    require(type(value["purpose"]) is str and value["purpose"] in PURPOSE_REFS, "closed purpose")
    require(value["ref"] == PURPOSE_REFS[value["purpose"]], "purpose/ref mismatch")
    for key in ("head", "tree"):
        require(type(value[key]) is str and re.fullmatch(r"[0-9a-f]{40}", value[key]), key + " identity")
    require(value["head"] != BASE_MAIN and value["baseMain"] == BASE_MAIN, "Phase1 main baseline")
    require(type(value["selection"]) is str and value["selection"] in SELECTIONS, "closed selection")
    for key in ("selectionSHA256", "orderedUnitMethodsSHA256", "orderedUIMethodsSHA256"):
        require(digest(value[key]), key + " digest")
    require(type(value["sources"]) is dict and set(value["sources"]) == set(SOURCES)
            and all(digest(v) for v in value["sources"].values()), "closed source closure")
    exact(value["policies"], POLICIES, "approved policy bytes")
    require(all(value["sources"][p] == h for p, h in POLICIES.items()), "source/policy mismatch")
    exact(value["route"], ROUTE, "pinned route and budgets")
    exact(value["classification"], CLASSIFICATION, "pending-only classification")
    exact(value["collector"], {"path": COLLECTOR, "sha256": value["sources"][COLLECTOR]},
          "sole collector implementation")
    stamp = value["requestedAtUTC"]
    require(type(stamp) is str and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", stamp),
            "UTC timestamp")
    try:
        parsed_stamp = datetime.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise Refused("Phase1 gate: invalid UTC timestamp") from error
    require(parsed_stamp >= datetime.datetime(2026, 9, 26), "predates owner decision 24")
    return value


def parse_plan(raw):
    return validate_plan(decode(raw))


def plan_from_event(raw):
    """Read original GitHub event bytes; empty plan retains the legacy route.

    This parses data, not authorization. A valid envelope still cannot dispatch
    or qualify an original until its root attempt and API identity are verified.
    GitHub's event JSON need not use our canonical serialization.
    """
    require(type(raw) is bytes and 0 < len(raw) <= MAX_EVENT_BYTES, "bounded original event")
    try:
        event = json.loads(raw.decode("utf-8"), object_pairs_hook=object_pairs)
    except (UnicodeError, ValueError) as error:
        raise Refused("Phase1 gate: original event JSON: " + str(error)) from error
    require(type(event) is dict, "original event object")
    inputs = event.get("inputs", {})
    require(type(inputs) is dict, "original dispatch inputs")
    encoded = inputs.get(PLAN_INPUT, "")
    require(type(encoded) is str, "original plan input string")
    cold_encoded = inputs.get("v23_cold_original_plan", "")
    require(type(cold_encoded) is str and not (encoded and cold_encoded), "simultaneous cold and gate plans")
    return (None if encoded == "" else parse_plan(encoded.encode("utf-8"))), event


def bind_original_event(raw, environment, *, head, tree, resolved_bytes, sources):
    """Pure worker/collector binding. No source, run or human trust is synthesized.

    The native caller must supply independently read checkout/selection/source
    facts; the sole collector must supply authenticated API run identity and its
    preregistered plan before relying on this returned pending binding.
    """
    plan, event = plan_from_event(raw)
    if plan is None:
        return None
    e, inputs = environment, event["inputs"]
    require(e.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "original dispatch event")
    require(e.get("GITHUB_REPOSITORY") == REPOSITORY
            and type(event.get("repository")) is dict
            and event["repository"].get("full_name") == REPOSITORY, "original event repository")
    require(e.get("GITHUB_REF") == plan["ref"]
            and event.get("ref") in (plan["ref"], plan["ref"].removeprefix("refs/heads/")),
            "original event ref")
    require(e.get("GITHUB_SHA") == head == plan["head"] and tree == plan["tree"], "original event head/tree")
    require(e.get("GITHUB_RUN_ATTEMPT") == "1" and type(e.get("GITHUB_RUN_ID")) is str
            and re.fullmatch(r"[1-9][0-9]*", e["GITHUB_RUN_ID"]), "original event attempt/run")
    workflow_ref = REPOSITORY + "/" + ROUTE["workflow"] + "@" + plan["ref"]
    require(e.get("GITHUB_WORKFLOW_REF") == workflow_ref
            and e.get("GITHUB_WORKFLOW_SHA") == head, "original workflow source")
    require(inputs.get("v23_run_kind") == "gate"
            and inputs.get("native_selection_id") == plan["selection"]
            and inputs.get("execution_lane") == ROUTE["executionLane"], "original event kind/selection/lane")
    require(inputs.get("run_ui_smoke") == ("true" if plan["selection"] == RUI1 else "false"),
            "original event UI intent")
    rebuilt = make_plan(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
                        resolved_bytes=resolved_bytes, sources=sources, requested_at=plan["requestedAtUTC"])
    exact(plan, rebuilt, "original event committed source/selection")
    return {"schema": EVENT_SCHEMA, "plan": plan, "planSHA256": sha(canonical(plan)),
            "originalEventSHA256": sha(raw), "repository": REPOSITORY, "ref": plan["ref"],
            "head": head, "tree": tree, "workflowRef": workflow_ref, "workflowSHA": head,
            "runID": e["GITHUB_RUN_ID"], "runAttempt": "1", "kind": "gate",
            "selection": plan["selection"], "functionalQualification": PENDING}


def verify_collected_event(binding, *, registered_plan_bytes, original_event_bytes, api_run,
                           tree, resolved_bytes, sources):
    """Bind retained input to an existing root registration and authenticated API facts.

    This is one necessary check, never complete collector/qualification admission.
    The caller must additionally verify exclusive attempt, sole claim, artifact
    provenance, all raw proof and genuine review provenance.
    """
    require(type(binding) is dict and binding.get("schema") == EVENT_SCHEMA, "retained event schema")
    plan = parse_plan(registered_plan_bytes)
    exact(binding.get("plan"), plan, "retained event differs from registered plan")
    require(binding.get("planSHA256") == sha(registered_plan_bytes)
            and binding.get("originalEventSHA256") == sha(original_event_bytes), "retained event bytes")
    original_plan, _ = plan_from_event(original_event_bytes)
    exact(original_plan, plan, "original event differs from registered plan")
    require(type(api_run) is dict and type(api_run.get("id")) is int and api_run["id"] > 0
            and type(api_run.get("run_attempt")) is int and api_run["run_attempt"] == 1,
            "authenticated API original")
    require((api_run.get("head_sha"), api_run.get("head_branch"), api_run.get("event"), api_run.get("path"))
            == (plan["head"], plan["ref"].removeprefix("refs/heads/"), "workflow_dispatch", ROUTE["workflow"]),
            "authenticated API identity")
    require(binding.get("runID") == str(api_run["id"]) and binding.get("runAttempt") == "1"
            and binding.get("head") == plan["head"] and binding.get("ref") == plan["ref"],
            "retained run/attempt/ref/head")
    exact(binding.get("functionalQualification"), PENDING, "retained pending status")
    expected = bind_original_event(original_event_bytes, {
        "GITHUB_EVENT_NAME": api_run["event"], "GITHUB_REPOSITORY": REPOSITORY,
        "GITHUB_REF": "refs/heads/" + api_run["head_branch"], "GITHUB_SHA": api_run["head_sha"],
        "GITHUB_RUN_ID": str(api_run["id"]), "GITHUB_RUN_ATTEMPT": str(api_run["run_attempt"]),
        "GITHUB_WORKFLOW_REF": REPOSITORY + "/" + api_run["path"] + "@" + plan["ref"],
        "GITHUB_WORKFLOW_SHA": api_run["head_sha"],
    }, head=api_run["head_sha"], tree=tree, resolved_bytes=resolved_bytes, sources=sources)
    exact(binding, expected, "complete retained event binding")
    return {"planSHA256": sha(registered_plan_bytes), "originalEventSHA256": sha(original_event_bytes),
            "runID": str(api_run["id"]), "runAttempt": "1", "functionalQualification": PENDING}


def make_plan(*, purpose, head, tree, selection, resolved_bytes, sources, requested_at):
    """Create pending intent from exact source facts, never a qualification receipt."""
    selected = decode(resolved_bytes, limit=4 * 1024 * 1024)
    require(type(selected) is dict, "resolved selection object")
    for field in ("unitTestSelectors", "uiTestSelectors"):
        require(type(selected.get(field)) is list and all(type(x) is str for x in selected[field]),
                "ordered selectors")
    require(type(purpose) is str and purpose in PURPOSE_REFS, "closed purpose")
    return validate_plan({
        "schema": SCHEMA, "purpose": purpose, "ref": PURPOSE_REFS[purpose], "head": head,
        "tree": tree, "baseMain": BASE_MAIN, "selection": selection,
        "selectionSHA256": sha(resolved_bytes),
        "orderedUnitMethodsSHA256": sha(canonical(selected["unitTestSelectors"])),
        "orderedUIMethodsSHA256": sha(canonical(selected["uiTestSelectors"])),
        "sources": dict(sources), "policies": dict(POLICIES), "route": json.loads(canonical(ROUTE)),
        "classification": dict(CLASSIFICATION), "requestedAtUTC": requested_at,
        "collector": {"path": COLLECTOR, "sha256": sources[COLLECTOR]},
    })


def bind_facts(plan, *, head, tree, integration_head, main_head, resolved_bytes, sources):
    if type(plan) is dict and plan.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return bind_facts_v2(plan, head=head, tree=tree, integration_head=integration_head, main_head=main_head, resolved_bytes=resolved_bytes, sources=sources)
    validate_plan(plan)
    require(head == plan["head"] == integration_head and tree == plan["tree"], "frozen checkout/ref/tree")
    require(main_head == (BASE_MAIN if plan["purpose"] == CANDIDATE else head), "main moved or wrong phase")
    rebuilt = make_plan(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
                        resolved_bytes=resolved_bytes, sources=sources, requested_at=plan["requestedAtUTC"])
    exact(plan, rebuilt, "committed source/selection binding")


def original_key(plan):
    validate_plan(plan)
    return (plan["head"], plan["purpose"], plan["selection"])


def original_stem(plan):
    return "-".join(original_key(plan))


def conflicting_originals(plan, records, attempt_names):
    if type(plan) is dict and plan.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return conflicting_originals_v2(plan, records, attempt_names)
    """Conservative legacy collisions; a closed name alone never authorizes reuse.

    Cross-purpose separation is only a mathematical key here. Verifying the prior
    candidate original and its prerequisites is a mandatory later admission step.
    Development and unknown records collide with both purposes.
    """
    head, purpose, selection = original_key(plan)
    conflicts, bound_candidates = [], 0
    for record in records:
        require(type(record) is dict, "malformed historical ledger record")
        if "event" in record:
            continue
        if (record.get("head"), record.get("selection")) != (head, selection):
            continue
        other = record.get("phase1Purpose")
        if (record.get("kind") != "gate" or type(other) is not str or other not in PURPOSE_REFS or other == purpose
                or purpose != EXACT_MAIN):
            conflicts.append("ledger:" + str(record.get("runID", "unknown")))
        else:
            # A purported Phase1 entry must bind the closed plan; arbitrary purpose
            # strings attached to old ledger entries cannot create an exemption.
            try:
                prior = parse_plan(record.get("phase1PlanBytes", "").encode("utf-8"))
                require(original_key(prior) == (head, other, selection), "prior plan key")
                require(record.get("phase1PlanSHA256") == sha(canonical(prior)), "prior plan hash")
                require(record.get("phase1RegistrationSchema") == REGISTRATION_SCHEMA, "prior registration")
                bound_candidates += 1
            except (Refused, AttributeError):
                conflicts.append("unbound-ledger:" + str(record.get("runID", "unknown")))
    legacy_prefix = head + "-" + selection
    own = original_stem(plan)
    other = head + "-" + (EXACT_MAIN if purpose == CANDIDATE else CANDIDATE) + "-" + selection
    for name in attempt_names:
        require(type(name) is str and Path(name).name == name, "attempt basename")
        if name.startswith(legacy_prefix) or name.startswith(own):
            conflicts.append("attempt:" + name)
        elif name.startswith(head + "-") and selection in name:
            if not (purpose == EXACT_MAIN and bound_candidates == 1 and name == other + ".json"):
                conflicts.append("ambiguous-attempt:" + name)
    if bound_candidates > 1:
        conflicts.append("multiple candidate originals")
    return conflicts


ATTEMPT_SCHEMA = "v23-phase1-original-attempt.v2"
DISCOVERY_SCHEMA = "v23-phase1-original-discovery.v1"
MAX_ATTEMPT_BYTES = 8 * 1024 * 1024
MAX_ORIGINAL_RUNS = 1000
ACTIVE_RUN_STATUSES = ("queued", "in_progress", "waiting", "pending", "requested")


def dispatch_inputs(plan):
    if type(plan) is dict and plan.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return dispatch_inputs_v2(plan)
    validate_plan(plan)
    require(plan["purpose"] == CANDIDATE, "candidate-only attempt lifecycle")
    return {"execution_lane": ROUTE["executionLane"], "native_selection_id": plan["selection"],
            "run_ui_smoke": "true" if plan["selection"] == RUI1 else "false",
            "s10_4_shard_id": "none", "s10_4_minimum_core_smoke_id": "none",
            "s10_4_shared_segment_id": "none", "s10_4_shared_payload_run_id": "",
            "s10_4_segment_source_run_ids": "", "v23_run_kind": "gate",
            PLAN_INPUT: canonical(plan).decode("utf-8")}


def verify_attempt_inputs(attempt, original_event_raw):
    if type(attempt) is dict and attempt.get("schema") == ATTEMPT_SCHEMA_V3:
        plan, event = plan_from_event_v2(original_event_raw)
        require(plan is not None and canonical(plan).decode("utf-8") == attempt["planBytes"], "V3 original event attempt plan")
        requested_bytes = canonical(dispatch_inputs_v2(plan)).decode("utf-8")
        require(type(attempt["inputBytes"]) is str and attempt["inputBytes"] == requested_bytes,
                "V3 actual complete requested13 bytes preserved")
        validate_received_inputs_v2(event["inputs"], plan)
        return {"originalEventSHA256": sha(original_event_raw), "inputSHA256": sha(attempt["inputBytes"].encode("utf-8"))}
    plan, event = plan_from_event(original_event_raw)
    require(plan is not None and canonical(plan).decode("utf-8") == attempt["planBytes"], "original event attempt plan")
    require(canonical(event["inputs"]).decode("utf-8") == attempt["inputBytes"], "original event exact requested inputs")
    return {"originalEventSHA256": sha(original_event_raw), "inputSHA256": sha(attempt["inputBytes"].encode("utf-8"))}


def dispatch_argv(plan, workflow_id):
    dispatch_inputs(plan)
    require(type(workflow_id) is int and workflow_id > 0, "workflow API identity")
    return ["gh", "workflow", "run", str(workflow_id), "--repo", REPOSITORY,
            "--ref", plan["ref"].removeprefix("refs/heads/"), "--json"]


def validate_run_census(value, *, head=None):
    require(type(value) is dict and set(value) == {"total_count", "workflow_runs"}, "closed run census")
    count, rows = value["total_count"], value["workflow_runs"]
    require(type(count) is int and 0 <= count <= MAX_ORIGINAL_RUNS and type(rows) is list
            and len(rows) == count, "complete bounded run census")
    identifiers = []
    for row in rows:
        require(type(row) is dict and type(row.get("id")) is int and row["id"] > 0, "run census identity")
        require(head is None or row.get("head_sha") == head, "run census head")
        identifiers.append(row["id"])
    require(len(set(identifiers)) == len(identifiers), "duplicate run census IDs")
    return sorted(identifiers)


def validate_ref_observations(value, plan):
    if type(plan) is dict and plan.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return validate_ref_observations_v2(value, plan)
    require(type(value) is dict and set(value) == {"integration", "main"}, "closed ref observations")
    for key, ref, head in (("integration", INTEGRATION_REF, plan["head"]),
                           ("main", "refs/heads/main", BASE_MAIN)):
        row = value[key]
        require(type(row) is dict and row.get("ref") == ref and type(row.get("object")) is dict
                and row["object"].get("type") == "commit" and row["object"].get("sha") == head,
                "authenticated " + key + " ref moved")


def validate_attempt(value, plan, registration_raw):
    """Closed root record, not authentication of caller-supplied API dictionaries.

    Actual fixed-endpoint capture belongs to the dormant dispatcher. Collection
    rechecks these bytes, the live original and exact worker inputs separately.
    """
    if type(plan) is dict and plan.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return validate_attempt_v2(value, plan, registration_raw)
    validate_plan(plan)
    require(plan["purpose"] == CANDIDATE, "candidate-only attempt lifecycle")
    keys = {"schema", "planBytes", "planSHA256", "registrationSHA256", "collectorSHA256", "collectorID",
            "workflowID", "repositoryID", "knownRunIDs", "requestedAtUTC", "integrationHead", "mainHead",
            "inputBytes", "argv", "observations", "ledgerBytes", "attemptNames"}
    require(type(value) is dict and set(value) == keys and value["schema"] == ATTEMPT_SCHEMA,
            "closed consumed attempt v2")
    exact(decode(registration_raw), {"schema": REGISTRATION_SCHEMA, "plan": plan,
          "planSHA256": sha(canonical(plan)), "dispatchEnabled": False, "functionalQualification": PENDING},
          "attempt pending registration")
    require(value["planBytes"] == canonical(plan).decode("utf-8")
            and value["planSHA256"] == sha(canonical(plan))
            and value["registrationSHA256"] == sha(registration_raw)
            and value["collectorSHA256"] == plan["sources"][COLLECTOR]
            and value["integrationHead"] == plan["head"] and value["mainHead"] == BASE_MAIN,
            "attempt frozen plan/source/registration")
    require(type(value["collectorID"]) is str and re.fullmatch(r"[0-9a-f]{32}", value["collectorID"]),
            "sole collector identity")
    validate_plan(dict(plan, requestedAtUTC=value["requestedAtUTC"]))
    require(value["requestedAtUTC"] >= plan["requestedAtUTC"], "attempt predates registration intent")
    exact(value["argv"], dispatch_argv(plan, value["workflowID"]), "exact dispatch argv")
    require(value["inputBytes"] == canonical(dispatch_inputs(plan)).decode("utf-8"), "exact dispatch input bytes")
    observations = value["observations"]
    require(type(observations) is dict and set(observations) == {"repository", "workflow", "refs", "headRuns", "activeRuns"},
            "closed predispatch observations")
    repository, workflow = observations["repository"], observations["workflow"]
    require(type(repository) is dict and repository.get("full_name") == REPOSITORY
            and type(repository.get("id")) is int and repository["id"] > 0
            and type(value["repositoryID"]) is int and value["repositoryID"] == repository["id"],
            "authenticated repository identity")
    require(type(workflow) is dict and type(workflow.get("id")) is int and workflow["id"] == value["workflowID"]
            and workflow.get("path") == ROUTE["workflow"] and workflow.get("state") == "active", "active original workflow")
    validate_ref_observations(observations["refs"], plan)
    identifiers = validate_run_census(observations["headRuns"], head=plan["head"])
    exact(value["knownRunIDs"], identifiers, "known original census")
    active = observations["activeRuns"]
    require(type(active) is dict and set(active) == set(ACTIVE_RUN_STATUSES), "closed active-run census")
    # Conservative candidate gates never overlap another active original. This
    # does not alter any development capacity or concurrency behavior.
    for status in ACTIVE_RUN_STATUSES:
        require(not validate_run_census(active[status]), "candidate gate requires no active original")
    require(type(value["ledgerBytes"]) is str, "retained original ledger bytes")
    try:
        records = [json.loads(line, object_pairs_hook=object_pairs,
                   parse_constant=lambda _: (_ for _ in ()).throw(Refused("nonfinite ledger")))
                   for line in value["ledgerBytes"].splitlines() if line.strip()]
    except (ValueError, UnicodeError) as error:
        raise Refused("Phase1 gate: invalid retained ledger") from error
    require(all(type(row) is dict for row in records), "ledger objects")
    originals = [row for row in records if "event" not in row]
    require(all(type(row.get("runID")) is int and row["runID"] > 0 for row in originals), "ledger original IDs")
    known = [row["runID"] for row in originals]
    require(len(known) == len(set(known)) and set(identifiers) <= set(known), "unknown or duplicate ledger originals")
    by_id = {row["runID"]: row for row in originals}
    require(all(by_id[identifier].get("head") == plan["head"] for identifier in identifiers),
            "known ledger original head")
    names = value["attemptNames"]
    require(type(names) is list and all(type(x) is str for x in names) and names == sorted(set(names)),
            "complete attempt-name census")
    require(not conflicting_originals(plan, records, names), "consumed or historical question collision")
    require(len(canonical(value)) <= MAX_ATTEMPT_BYTES, "bounded consumed attempt")
    return value


def make_attempt(plan, registration_raw, *, collector_id, requested_at, observations, ledger_bytes, attempt_names):
    if type(plan) is dict and plan.get('schema') == ACTIVATION_PLAN_SCHEMA:
        return make_attempt_v2(plan, registration_raw, collector_id=collector_id, requested_at=requested_at, observations=observations, ledger_bytes=ledger_bytes, attempt_names=attempt_names)
    value = {"schema": ATTEMPT_SCHEMA, "planBytes": canonical(plan).decode("utf-8"),
             "planSHA256": sha(canonical(plan)), "registrationSHA256": sha(registration_raw),
             "collectorSHA256": plan["sources"][COLLECTOR], "collectorID": collector_id,
             "workflowID": observations["workflow"]["id"], "repositoryID": observations["repository"]["id"],
             "knownRunIDs": validate_run_census(observations["headRuns"], head=plan["head"]),
             "requestedAtUTC": requested_at, "integrationHead": plan["head"], "mainHead": BASE_MAIN,
             "inputBytes": canonical(dispatch_inputs(plan)).decode("utf-8"),
             "argv": dispatch_argv(plan, observations["workflow"]["id"]), "observations": observations,
             "ledgerBytes": ledger_bytes, "attemptNames": attempt_names}
    return validate_attempt(value, plan, registration_raw)


def durable_directory(path):
    path = Path(path)
    require(path.parent.is_dir() and not path.parent.is_symlink(), "regular directory parent")
    path.mkdir(exist_ok=True)
    require(path.is_dir() and not path.is_symlink(), "regular durable directory")
    if os.name != "nt":
        fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def write_immutable(path, raw):
    """Create and fsync before effects. Any partial record still consumes its key.

    Root controls the evidence tree; a failed/partial exclusive write is never
    replaced. This is durable record creation, not hostile-filesystem isolation.
    """
    require(type(raw) is bytes and 0 < len(raw) <= MAX_ATTEMPT_BYTES, "bounded immutable bytes")
    path = Path(path)
    require(path.parent.is_dir() and not path.parent.is_symlink(), "regular immutable parent")
    with path.open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    if os.name != "nt":
        fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    return path


def regular_bytes(path, limit=MAX_PLAN_BYTES):
    path = Path(path)
    before = path.lstat()
    require(not stat.S_ISLNK(before.st_mode), "symlink input")
    require(stat.S_ISREG(before.st_mode), "regular input")
    with path.open("rb") as stream:
        opened = os.fstat(stream.fileno())
        require(stat.S_ISREG(opened.st_mode) and (before.st_dev, before.st_ino) == (opened.st_dev, opened.st_ino),
                "input identity changed")
        value = stream.read(limit + 1)
    require(len(value) <= limit, "bounded input")
    return value


def register_candidate(plan, directory):
    """Exclusive pending intent. Does not consume an original or permit dispatch.

    The enclosing directory is a dedicated local evidence directory controlled by
    root. Existing/corrupt reservations are never replaced or silently repaired.
    """
    validate_plan(plan)
    require(plan["purpose"] == CANDIDATE, "exact-main prerequisites are not implemented")
    directory = Path(directory)
    require(not directory.is_symlink(), "symlink registration directory")
    directory.mkdir(parents=True, exist_ok=True)
    require(directory.is_dir(), "registration directory")
    target = directory / (original_stem(plan) + ".json")
    record = {"schema": REGISTRATION_SCHEMA, "plan": plan, "planSHA256": sha(canonical(plan)),
              "dispatchEnabled": False, "functionalQualification": PENDING}
    try:
        with target.open("xb") as stream:
            stream.write(canonical(record))
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError as error:
        raise Refused("Phase1 gate: registration already exists; inspect, never replace") from error
    return target, record


def refuse_dispatch():
    raise Refused("Phase1 gate: dispatch disabled until worker, collection, qualification and "
                  "exact-main prerequisite verification are implemented and independently reviewed")


REVIEW_SCHEMA = "v23-phase1-review-provenance.v1"
REVIEW_REQUEST_SCHEMA = "v23-phase1-review-request.v1"
REVIEW_PENDING = "PROVENANCE_RECORDED_PENDING"
REVIEW_SUBJECTS = ("shared-cold-original", "rui1-cold-original", "candidate-integration", "owner-critical-states")
MAX_REVIEW_BYTES = 2 * 1024 * 1024
REVIEW_TRUST = "Root must verify actual source messages and identity/independence; hashes bind bytes only."


def review_text(value, label, limit=4096):
    require(type(value) is str and bool(value.strip()) and len(value.encode("utf-8")) <= limit
            and "\x00" not in value, "review " + label)


def review_timestamp(value):
    require(type(value) is str and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", value), "review timestamp")
    try:
        datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise Refused("review calendar timestamp") from error


def validate_review_request(value, *, test_only=False):
    """Validate declarations and byte references, never the truth of a speaker."""
    require(type(test_only) is bool and type(value) is dict and set(value) == {
        "schema", "testOnly", "subject", "reportedDisposition", "head", "tree", "originals", "gallery",
        "messageSHA256", "contextSHA256", "messageReference", "conversationReference", "messageTimestampUTC",
        "speakerReference", "reviewer"}, "closed review request")
    require(value["schema"] == REVIEW_REQUEST_SCHEMA and type(value["testOnly"]) is bool
            and value["testOnly"] == test_only, "test-only provenance cannot enter real records")
    require(type(value["subject"]) is str and value["subject"] in REVIEW_SUBJECTS, "closed review subject")
    require(type(value["reportedDisposition"]) is str and value["reportedDisposition"] in
            ("approve", "changes-requested", "pending"), "reported review disposition")
    for key in ("head", "tree"):
        require(type(value[key]) is str and re.fullmatch(r"[0-9a-f]{40}", value[key]), "review " + key)
    for key in ("messageSHA256", "contextSHA256"):
        require(digest(value[key]), "review byte digest")
    for key in ("messageReference", "conversationReference", "speakerReference"):
        review_text(value[key], key)
    review_timestamp(value["messageTimestampUTC"])
    originals = value["originals"]
    count = 2 if value["subject"] == "candidate-integration" else 1
    require(type(originals) is list and len(originals) == count, "review original subject census")
    for item in originals:
        require(type(item) is dict and set(item) == {"runID", "manifestSHA256"}
                and type(item["runID"]) is int and item["runID"] > 0 and digest(item["manifestSHA256"]),
                "review original identity")
    require([i["runID"] for i in originals] == sorted({i["runID"] for i in originals}), "review unique ordered originals")
    if value["subject"] == "owner-critical-states":
        require(value["reviewer"] is None, "owner review is not a model review")
        gallery = value["gallery"]
        require(type(gallery) is dict and set(gallery) == {"catalogueSHA256", "proofSHA256", "presentationSHA256",
                "checklistSHA256", "attachmentsSHA256"} and all(digest(v) for v in gallery.values()), "owner bundle digests")
    else:
        require(value["gallery"] is None, "gallery only for owner subject")
        reviewer = value["reviewer"]
        require(type(reviewer) is dict and set(reviewer) == {"model", "effort", "authorReference", "independenceReference"},
                "reviewer source references")
        for key in reviewer:
            review_text(reviewer[key], key)
        # Reported strings are retained facts, not proof of independence or model identity.
    require(len(canonical(value)) <= MAX_REVIEW_BYTES, "review request bound")
    return value


def make_review_record(request, message, context, bindings, *, index, previous, captured_at, test_only=False):
    validate_review_request(request, test_only=test_only)
    require(type(index) is int and 0 <= index < 1000 and (previous is None if index == 0 else digest(previous)),
            "review history position")
    review_timestamp(captured_at)
    require(captured_at >= request["messageTimestampUTC"], "review capture precedes message")
    texts = []
    for raw, name in ((message, "message"), (context, "context")):
        require(type(raw) is bytes and 0 < len(raw) <= 512 * 1024 and sha(raw) == request[name + "SHA256"],
                "review " + name + " bytes")
        try:
            text = raw.decode("utf-8")
        except UnicodeError as error:
            raise Refused("review UTF8 bytes") from error
        review_text(text, name, 512 * 1024)
        texts.append(text)
    value = {"schema": REVIEW_SCHEMA, "index": index, "previousSHA256": previous,
             "capturedAtUTC": captured_at, "request": request, "messageUTF8": texts[0], "contextUTF8": texts[1],
             "bindings": bindings, "status": REVIEW_PENDING, "trustBoundary": REVIEW_TRUST,
             "functionalQualification": PENDING, "acceptance": False, "releaseReady": False}
    require(len(canonical(value)) <= MAX_REVIEW_BYTES, "review record bound")
    return value


def review_pending_assessment(head, records):
    """Report all recorded dispositions without selecting an approval or resolving conflict."""
    subjects = {s: [] for s in REVIEW_SUBJECTS}
    for item in records:
        request = item["request"]
        require(request["head"] == head and item["status"] == REVIEW_PENDING, "review assessment scope")
        subjects[request["subject"]].append({"recordSHA256": sha(canonical(item)),
            "reportedDisposition": request["reportedDisposition"], "testOnly": request["testOnly"]})
    return {"schema": "v23-phase1-review-pending-assessment.v1", "head": head, "subjects": subjects,
            "retainedOriginals": [{"recordSHA256": sha(canonical(item)), "originals": item["bindings"]["originals"]}
                                  for item in records],
            "declaredIndependenceGaps": [sha(canonical(item)) for item in records
                if item["request"]["reviewer"] is not None and item["request"]["speakerReference"]
                    == item["request"]["reviewer"]["authorReference"]],
            "missingSubjects": [s for s, items in subjects.items() if not items],
            "unresolvedSubjects": [s for s, items in subjects.items() if len(items) > 1
                or any(i["reportedDisposition"] != "approve" for i in items)],
            "status": REVIEW_PENDING, "functionalQualification": PENDING,
            "pendingPredicates": ["genuine source-message and independence verification",
                "complete cold/raw proof and qualification lifecycle", "fresh current authority before admission"],
            "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED",
            "physicalProtectionReleaseBlocker": True, "acceptance": False,
            "providerQualification": False, "releaseReady": False, "trustBoundary": REVIEW_TRUST}


# Additive Phase1 V2 bindings. V1 plans, raw proofs and provenance remain pending.
ACTIVATION_PLAN_SCHEMA = "v23-phase1-functional-gate-plan.v2"
EVENT_SCHEMA_V2 = "v23-phase1-original-event-binding.v2"
REGISTRATION_SCHEMA_V2 = "v23-phase1-functional-gate-registration.v2"
ATTEMPT_SCHEMA_V3 = "v23-phase1-original-attempt.v3"
CHAIN_SCHEMA_V2 = "v23-phase1-retained-worker-chain.v2"
FUNCTIONAL_SCHEMA_V2 = "v23-phase1-functional-qualification.v2"
COLD_PREREQUISITE_KEYS_V2 = {"runID", "assessmentSHA256", "manifestSHA256", "reviewSHA256"}
STRONGER_CLAIMS_V2 = {"totalPolicyCallCountProven": False,
    "exhaustiveKernelProcessCohortProven": False,
    "perPIDDescriptorRetirementProven": False, "exactCheckpointRepeatProven": False}
COLD_STRONGER_CLAIMS_V2 = {"totalPolicyCallCounts": "UNPROVEN",
    "exhaustiveAppKernelLifetimeCohorts": "UNPROVEN", "perPIDDescriptorRetirement": "UNPROVEN",
    "exactRepeatCounts": "UNPROVEN"}
FUNCTIONAL_SCOPE_V2 = "QUALIFIED_PHASE1_SIMULATOR_FUNCTIONAL_V2"


def reference_v2(value, *, raw_stream=False):
    """A typed byte reference is binding DATA, never speaker or gate authority."""
    hash_key = "sha256" if raw_stream else "SHA256"
    require(type(value) is dict and set(value) == {"path", "bytes", hash_key}, "V2 closed reference")
    name = value["path"]
    require(type(name) is str and name and "\x00" not in name and "\\" not in name
            and Path(name).is_absolute() and str(Path(name)) == name
            and all(part not in ("", ".", "..") for part in name.split("/")[1:]), "V2 canonical reference path")
    require(type(value["bytes"]) is int and (value["bytes"] >= 0 if raw_stream else value["bytes"] > 0)
            and (raw_stream or value["bytes"] <= 32 * 1024 * 1024)
            and digest(value[hash_key]), "V2 actual reference bytes/hash")
    return value


def validate_plan_v2(value):
    require(type(value) is dict and set(value) == PLAN_KEYS | {"coldPrerequisite"}
            and value["schema"] == ACTIVATION_PLAN_SCHEMA, "closed activation V2 plan")
    # An explicit, nonmutating projection reuses the complete V1 policy/route checks.
    base = {key: value[key] for key in PLAN_KEYS}
    base["schema"] = SCHEMA
    validate_plan(base)
    prerequisite = value["coldPrerequisite"]
    require(type(prerequisite) is dict and set(prerequisite) == COLD_PREREQUISITE_KEYS_V2
            and type(prerequisite["runID"]) is int and prerequisite["runID"] > 0
            and all(digest(prerequisite[key]) for key in COLD_PREREQUISITE_KEYS_V2 - {"runID"}),
            "closed cold prerequisite descriptor; digest declarations are not review authority")
    return value


def make_plan_v2(*, purpose, head, tree, selection, resolved_bytes, sources, requested_at, cold_prerequisite):
    base = make_plan(purpose=purpose, head=head, tree=tree, selection=selection,
        resolved_bytes=resolved_bytes, sources=sources, requested_at=requested_at)
    return validate_plan_v2({**base, "schema": ACTIVATION_PLAN_SCHEMA,
                             "coldPrerequisite": dict(cold_prerequisite)})


def plan_from_event_v2(raw):
    require(type(raw) is bytes and 0 < len(raw) <= MAX_EVENT_BYTES, "V2 finite original event bytes")
    try:
        event = json.loads(raw.decode("utf-8"), object_pairs_hook=object_pairs,
                           parse_constant=lambda _: (_ for _ in ()).throw(Refused("nonfinite original event")))
    except (ValueError, UnicodeError) as error:
        raise Refused("Phase1 gate: invalid original event") from error
    require(type(event) is dict, "V2 original event object")
    inputs = event.get("inputs")
    require(inputs is None or type(inputs) is dict, "V2 original event inputs")
    supplied = inputs.get(PLAN_INPUT) if inputs is not None else None
    cold_supplied = inputs.get("v23_cold_original_plan", "") if inputs is not None else ""
    require(type(cold_supplied) is str and not (supplied and cold_supplied), "V2 simultaneous cold and gate plans")
    if supplied in (None, ""):
        return None, event
    require(type(supplied) is str and len(supplied.encode("utf-8")) <= MAX_PLAN_BYTES,
            "V2 finite original plan input")
    plan = validate_plan_v2(decode(supplied.encode("utf-8")))
    require(canonical(plan).decode("utf-8") == supplied, "V2 canonical original plan bytes")
    return plan, event


def bind_original_event_v2(raw, environment, *, head, tree, resolved_bytes, sources):
    plan, event = plan_from_event_v2(raw)
    if plan is None:
        return None
    e, inputs = environment, event["inputs"]
    validate_received_inputs_v2(inputs, plan)
    require(e.get("GITHUB_EVENT_NAME") == "workflow_dispatch" and e.get("GITHUB_REPOSITORY") == REPOSITORY
            and type(event.get("repository")) is dict and event["repository"].get("full_name") == REPOSITORY,
            "V2 original dispatch repository")
    require(e.get("GITHUB_REF") == plan["ref"]
            and event.get("ref") in (plan["ref"], plan["ref"].removeprefix("refs/heads/")), "V2 original ref")
    require(e.get("GITHUB_SHA") == head == plan["head"] and tree == plan["tree"], "V2 original head/tree")
    require(e.get("GITHUB_RUN_ATTEMPT") == "1" and type(e.get("GITHUB_RUN_ID")) is str
            and re.fullmatch(r"[1-9][0-9]*", e["GITHUB_RUN_ID"]), "V2 original run/attempt")
    workflow_ref = REPOSITORY + "/" + ROUTE["workflow"] + "@" + plan["ref"]
    require(e.get("GITHUB_WORKFLOW_REF") == workflow_ref and e.get("GITHUB_WORKFLOW_SHA") == head,
            "V2 original workflow Source")
    require(inputs.get("v23_run_kind") == "gate" and inputs.get("native_selection_id") == plan["selection"]
            and inputs.get("execution_lane") == ROUTE["executionLane"]
            and inputs.get("run_ui_smoke") == ("true" if plan["selection"] == RUI1 else "false"),
            "V2 original kind/selection/lane/UI")
    rebuilt = make_plan_v2(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
        resolved_bytes=resolved_bytes, sources=sources, requested_at=plan["requestedAtUTC"],
        cold_prerequisite=plan["coldPrerequisite"])
    exact(plan, rebuilt, "V2 original committed Source/selection")
    return {"schema": EVENT_SCHEMA_V2, "plan": plan, "planSHA256": sha(canonical(plan)),
        "originalEventSHA256": sha(raw), "repository": REPOSITORY, "ref": plan["ref"],
        "head": head, "tree": tree, "workflowRef": workflow_ref, "workflowSHA": head,
        "runID": e["GITHUB_RUN_ID"], "runAttempt": "1", "kind": "gate", "selection": plan["selection"],
        "functionalQualification": PENDING}


def verify_collected_event_v2(binding, *, registered_plan_bytes, original_event_bytes, api_run,
                              tree, resolved_bytes, sources):
    require(type(binding) is dict and binding.get("schema") == EVENT_SCHEMA_V2, "V2 retained event schema")
    plan = validate_plan_v2(decode(registered_plan_bytes))
    exact(binding.get("plan"), plan, "V2 retained registered plan")
    require(binding.get("planSHA256") == sha(registered_plan_bytes)
            and binding.get("originalEventSHA256") == sha(original_event_bytes), "V2 retained event raw bytes")
    require(type(api_run) is dict and type(api_run.get("id")) is int and api_run["id"] > 0
            and type(api_run.get("run_attempt")) is int and api_run["run_attempt"] == 1,
            "V2 authenticated API original")
    require((api_run.get("head_sha"), api_run.get("head_branch"), api_run.get("event"), api_run.get("path"))
            == (plan["head"], plan["ref"].removeprefix("refs/heads/"), "workflow_dispatch", ROUTE["workflow"]),
            "V2 authenticated API identity")
    expected = bind_original_event_v2(original_event_bytes, {
        "GITHUB_EVENT_NAME": api_run["event"], "GITHUB_REPOSITORY": REPOSITORY, "GITHUB_REF": plan["ref"],
        "GITHUB_SHA": api_run["head_sha"], "GITHUB_RUN_ID": str(api_run["id"]),
        "GITHUB_RUN_ATTEMPT": str(api_run["run_attempt"]),
        "GITHUB_WORKFLOW_REF": REPOSITORY + "/" + ROUTE["workflow"] + "@" + plan["ref"],
        "GITHUB_WORKFLOW_SHA": api_run["head_sha"]}, head=api_run["head_sha"], tree=tree,
        resolved_bytes=resolved_bytes, sources=sources)
    exact(binding, expected, "V2 complete retained event binding")
    return {"planSHA256": sha(registered_plan_bytes), "originalEventSHA256": sha(original_event_bytes),
            "runID": str(api_run["id"]), "runAttempt": "1", "functionalQualification": PENDING}


def bind_facts_v2(plan, *, head, tree, integration_head, main_head, resolved_bytes, sources):
    validate_plan_v2(plan)
    require(head == plan["head"] == integration_head and tree == plan["tree"], "V2 frozen checkout/ref/tree")
    require(main_head == (BASE_MAIN if plan["purpose"] == CANDIDATE else head), "V2 main moved/wrong purpose")
    exact(plan, make_plan_v2(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
        resolved_bytes=resolved_bytes, sources=sources, requested_at=plan["requestedAtUTC"],
        cold_prerequisite=plan["coldPrerequisite"]), "V2 committed Source/selection binding")


def validate_ref_observations_v2(value, plan):
    validate_plan_v2(plan)
    require(type(value) is dict and set(value) == {"integration", "main"}, "V2 closed ref observations")
    for key, ref, head in (("integration", INTEGRATION_REF, plan["head"]),
                          ("main", "refs/heads/main", BASE_MAIN if plan["purpose"] == CANDIDATE else plan["head"])):
        row = value[key]
        require(type(row) is dict and row.get("ref") == ref and type(row.get("object")) is dict
                and row["object"].get("type") == "commit" and row["object"].get("sha") == head,
                "V2 authenticated ref moved: " + key)


def dispatch_inputs_v2(plan):
    validate_plan_v2(plan)
    return {"execution_lane": ROUTE["executionLane"], "native_selection_id": plan["selection"],
        "run_ui_smoke": "true" if plan["selection"] == RUI1 else "false", "s10_4_shard_id": "none",
        "s10_4_minimum_core_smoke_id": "none", "s10_4_shared_segment_id": "none",
        "s10_4_shared_payload_run_id": "", "s10_4_segment_source_run_ids": "", "v23_run_kind": "gate",
        "v23_d50_compiler_observation": "false", "v23_d50_swift_driver_jobs_two": "false",
        "v23_cold_original_plan": "",
        PLAN_INPUT: canonical(plan).decode("utf-8")}


def validate_received_inputs_v2(received, plan):
    """Compare the two exact received shapes without rewriting either input.

    GitHub may omit precisely the three requested empty string defaults. Every
    nonempty/false/none-profile value remains an actual closed string equality.
    The complete requested bytes and original received event bytes stay separate.
    This shape comparison is DATA, never an original or qualification grant.
    """
    requested = dispatch_inputs_v2(plan)
    omitted = {"s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids", "v23_cold_original_plan"}
    require(type(received) is dict and all(type(key) is str for key in received)
            and all(type(value) is str for value in received.values()),
            "V2 closed received input string types")
    keys = set(received)
    require(len(requested) == 13 and all(type(value) is str for value in requested.values())
            and omitted <= set(requested) and all(requested[key] == "" for key in omitted),
            "V2 actual complete requested13 and exact empty default profile")
    if keys == set(requested):
        exact(received, requested, "V2 complete received inputs equal requested13")
        return "COMPLETE_13"
    require(keys == set(requested) - omitted, "V2 only simultaneous omission of exactly three empty defaults")
    exact(received, {key: value for key, value in requested.items() if key not in omitted},
          "V2 received10 preserves every complete requested nonempty value")
    return "OMITTED_EMPTY_DEFAULTS_10"


def conflicting_originals_v2(plan, records, attempt_names):
    validate_plan_v2(plan)
    head, purpose, selection = original_key(plan)
    conflicts, candidates = [], 0
    for row in records:
        require(type(row) is dict, "V2 historical ledger row")
        if "event" in row or (row.get("head"), row.get("selection")) != (head, selection):
            continue
        if purpose == EXACT_MAIN and row.get("kind") == "gate" and row.get("phase1Purpose") == CANDIDATE:
            try:
                previous = validate_plan_v2(decode(row.get("phase1PlanBytes", "").encode("utf-8")))
                require(original_key(previous) == (head, CANDIDATE, selection)
                        and row.get("phase1PlanSHA256") == sha(canonical(previous))
                        and row.get("phase1RegistrationSchema") == REGISTRATION_SCHEMA_V2,
                        "V2 prior candidate declaration")
                candidates += 1
            except (Refused, AttributeError):
                conflicts.append("unbound-candidate:" + str(row.get("runID", "unknown")))
        else:
            conflicts.append("ledger:" + str(row.get("runID", "unknown")))
    own = original_stem(plan)
    candidate = head + "-" + CANDIDATE + "-" + selection
    for name in attempt_names:
        require(type(name) is str and Path(name).name == name, "V2 attempt basename")
        if name.startswith(head + "-" + selection) or name.startswith(own):
            conflicts.append("attempt:" + name)
        elif name.startswith(head + "-") and selection in name:
            if not (purpose == EXACT_MAIN and candidates == 1 and name in (candidate + ".json", candidate + ".discovery")):
                conflicts.append("ambiguous-attempt:" + name)
    if candidates > 1:
        conflicts.append("multiple candidate originals")
    return conflicts


def registration_record_v2(plan, cold_binding):
    validate_plan_v2(plan)
    require(type(cold_binding) is dict and set(cold_binding) == {"assessment", "manifest", "review"},
            "V2 exact actual cold control references")
    for reference in cold_binding.values():
        reference_v2(reference)
    exact({"assessmentSHA256": cold_binding["assessment"]["SHA256"],
           "manifestSHA256": cold_binding["manifest"]["SHA256"],
           "reviewSHA256": cold_binding["review"]["SHA256"]},
          {key: plan["coldPrerequisite"][key] for key in COLD_PREREQUISITE_KEYS_V2 - {"runID"}},
          "V2 cold descriptor/control byte association")
    return {"schema": REGISTRATION_SCHEMA_V2, "plan": plan, "planSHA256": sha(canonical(plan)),
        "coldBinding": cold_binding, "dispatchEnabled": False, "functionalQualification": PENDING}


def validate_attempt_v2(value, plan, registration_raw):
    validate_plan_v2(plan)
    keys = {"schema", "planBytes", "planSHA256", "registrationSHA256", "collectorSHA256", "collectorID",
        "workflowID", "repositoryID", "knownRunIDs", "requestedAtUTC", "integrationHead", "mainHead",
        "inputBytes", "argv", "observations", "ledgerBytes", "attemptNames"}
    require(type(value) is dict and set(value) == keys and value["schema"] == ATTEMPT_SCHEMA_V3,
            "closed V2 consumed attempt")
    registration = decode(registration_raw)
    exact(registration, registration_record_v2(plan, registration.get("coldBinding")), "V2 pending registration")
    require(value["planBytes"] == canonical(plan).decode("utf-8") and value["planSHA256"] == sha(canonical(plan))
            and value["registrationSHA256"] == sha(registration_raw)
            and value["collectorSHA256"] == plan["sources"][COLLECTOR]
            and value["integrationHead"] == plan["head"]
            and value["mainHead"] == (BASE_MAIN if plan["purpose"] == CANDIDATE else plan["head"]),
            "V2 consumed Source/head/registration")
    require(type(value["collectorID"]) is str and re.fullmatch(r"[0-9a-f]{32}", value["collectorID"]), "V2 collector identity")
    validate_plan_v2(dict(plan, requestedAtUTC=value["requestedAtUTC"]))
    require(value["requestedAtUTC"] >= plan["requestedAtUTC"], "V2 attempt predates reservation")
    require(type(value["workflowID"]) is int and value["workflowID"] > 0, "V2 workflow ID")
    exact(value["argv"], ["gh", "workflow", "run", str(value["workflowID"]), "--repo", REPOSITORY,
          "--ref", plan["ref"].removeprefix("refs/heads/"), "--json"], "V2 original argv")
    require(value["inputBytes"] == canonical(dispatch_inputs_v2(plan)).decode("utf-8"), "V2 exact dispatch inputs")
    observations = value["observations"]
    require(type(observations) is dict and set(observations) == {"repository", "workflow", "refs", "headRuns", "activeRuns"},
            "V2 complete current observations")
    repository, workflow = observations["repository"], observations["workflow"]
    require(type(repository) is dict and repository.get("full_name") == REPOSITORY
            and type(repository.get("id")) is int and repository["id"] > 0
            and type(value["repositoryID"]) is int and value["repositoryID"] == repository["id"], "V2 current repository")
    require(type(workflow) is dict and type(workflow.get("id")) is int and workflow["id"] == value["workflowID"]
            and workflow.get("path") == ROUTE["workflow"] and workflow.get("state") == "active", "V2 active workflow")
    validate_ref_observations_v2(observations["refs"], plan)
    identifiers = validate_run_census(observations["headRuns"], head=plan["head"])
    exact(value["knownRunIDs"], identifiers, "V2 original known-run census")
    active = observations["activeRuns"]
    require(type(active) is dict and set(active) == set(ACTIVE_RUN_STATUSES), "V2 active census")
    for status in ACTIVE_RUN_STATUSES:
        require(not validate_run_census(active[status]), "V2 gate requires no active original")
    require(type(value["ledgerBytes"]) is str, "V2 actual ledger bytes")
    try:
        rows = [json.loads(line, object_pairs_hook=object_pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(Refused("V2 nonfinite ledger")))
            for line in value["ledgerBytes"].splitlines() if line.strip()]
    except (ValueError, UnicodeError) as error:
        raise Refused("Phase1 gate: V2 invalid retained ledger") from error
    require(all(type(row) is dict for row in rows), "V2 ledger objects")
    originals = [row for row in rows if "event" not in row]
    require(all(type(row.get("runID")) is int and row["runID"] > 0 for row in originals), "V2 ledger IDs")
    known = [row["runID"] for row in originals]
    require(len(known) == len(set(known)) and set(identifiers) <= set(known), "V2 unknown/duplicate original")
    by_id = {row["runID"]: row for row in originals}
    require(all(by_id[identifier].get("head") == plan["head"] for identifier in identifiers), "V2 ledger head")
    names = value["attemptNames"]
    require(type(names) is list and all(type(name) is str for name in names) and names == sorted(set(names)),
            "V2 complete attempt census")
    require(not conflicting_originals_v2(plan, rows, names), "V2 consumed/historical question collision")
    require(len(canonical(value)) <= MAX_ATTEMPT_BYTES, "V2 finite consumed attempt")
    return value


def make_attempt_v2(plan, registration_raw, *, collector_id, requested_at, observations, ledger_bytes, attempt_names):
    value = {"schema": ATTEMPT_SCHEMA_V3, "planBytes": canonical(plan).decode("utf-8"),
        "planSHA256": sha(canonical(plan)), "registrationSHA256": sha(registration_raw),
        "collectorSHA256": plan["sources"][COLLECTOR], "collectorID": collector_id,
        "workflowID": observations["workflow"]["id"], "repositoryID": observations["repository"]["id"],
        "knownRunIDs": validate_run_census(observations["headRuns"], head=plan["head"]),
        "requestedAtUTC": requested_at, "integrationHead": plan["head"],
        "mainHead": BASE_MAIN if plan["purpose"] == CANDIDATE else plan["head"],
        "inputBytes": canonical(dispatch_inputs_v2(plan)).decode("utf-8"),
        "argv": ["gh", "workflow", "run", str(observations["workflow"]["id"]), "--repo", REPOSITORY,
                 "--ref", plan["ref"].removeprefix("refs/heads/"), "--json"],
        "observations": observations, "ledgerBytes": ledger_bytes, "attemptNames": attempt_names}
    return validate_attempt_v2(value, plan, registration_raw)


def validate_chain_v2(value, plan, resolved):
    """Check recomputed fact bindings, never authenticate an offline supplied proof."""
    validate_plan_v2(plan)
    keys = {"schema", "status", "runID", "planSHA256", "workers", "executionProof", "emittedTransportV2",
            "strongerClaims", "functionalQualification", "acceptance", "providerQualification", "releaseReady", "executionAuthority"}
    require(type(value) is dict and set(value) == keys and value["schema"] == CHAIN_SCHEMA_V2
            and value["status"] == "RECOMPUTED_PHASE1_FUNCTIONAL_FACTS_DATA_ONLY"
            and type(value["runID"]) is int and value["runID"] > 0
            and value["planSHA256"] == sha(canonical(plan)) and value["functionalQualification"] == PENDING
            and all(value[key] is False for key in ("acceptance", "providerQualification", "releaseReady", "executionAuthority")),
            "V2 actual chain DATA scope")
    exact(value["strongerClaims"], STRONGER_CLAIMS_V2, "V2 separately unproven stronger claims")
    require(type(resolved) is dict and type(resolved.get("unitTestSelectors")) is list
            and type(resolved.get("uiTestSelectors")) is list
            and sha(canonical(resolved)) == plan["selectionSHA256"], "V2 exact canonical resolved selection")
    labels = ["producer"] + resolved["sharedCoverage"]["partitionIDs"] if plan["selection"] == SHARED else ["rui1"]
    require(len(labels) == len(set(labels)) and type(value["workers"]) is dict
            and set(value["workers"]) == set(labels) and type(value["emittedTransportV2"]) is dict
            and set(value["emittedTransportV2"]) == set(labels), "V2 complete worker/transport census")
    execution = value["executionProof"]
    require(type(execution) is dict and execution.get("status") == "RETAINED_EXECUTION_FACTS_VERIFIED"
            and execution.get("problems") == [] and type(execution.get("jobs")) is dict
            and type(execution.get("workers")) is dict and set(execution["jobs"]) == set(labels)
            and set(execution["workers"]) == set(labels), "V2 complete actual execution proof")
    require(plan["selection"] != SHARED or type(execution.get("payload")) is dict,
            "V2 shared actual payload/extraction/no-rebuild execution proof")
    units = []
    phase_keys = {"contextSHA256", "forwardingReceiptSHA256", "durableProofSHA256", "bindingSHA256",
                  "raw", "streams", "transportStatusSHA256", "emittedBoundary"}
    for label in labels:
        worker = value["workers"][label]
        require(type(worker) is dict and type(worker.get("executedUnitMethods")) is list
                and all(type(name) is str for name in worker["executedUnitMethods"]), "V2 actual executed method rows")
        units.extend(worker["executedUnitMethods"])
        transport = value["emittedTransportV2"][label]
        require(type(transport) is dict and set(transport) == {"role", "partitionID", "phases"}, "V2 closed emitted worker")
        expected_role = "producer" if label == "producer" else ("rui1" if label == "rui1" else "consumer")
        require(transport["role"] == expected_role and transport["partitionID"] == (label if expected_role == "consumer" else None),
                "V2 emitted role/partition")
        phases = transport["phases"]
        expected_phases = set() if label == "producer" else ({"unit", "ui"} if label == "rui1" else {"unit"})
        require(type(phases) is dict and set(phases) == expected_phases, "V2 complete emitted execution phases")
        for phase_name, phase in phases.items():
            require(type(phase) is dict and set(phase) == phase_keys
                    and phase["emittedBoundary"] == "SEALED_COMPLETE_EMITTED_TRANSPORT"
                    and all(digest(phase[key]) for key in phase_keys - {"raw", "streams", "emittedBoundary"}),
                    "V2 complete sealed emitted phase binding")
            raw = phase["raw"]
            require(type(raw) is dict and set(raw) == {"path", "bytes", "sha256"}
                and raw["path"] == "phase1-emitted-durable-original-" + phase_name + "/EMITTED.jsonl"
                and type(raw["bytes"]) is int and raw["bytes"] >= 0 and digest(raw["sha256"]),
                "V2 actual retained emitted raw path/byte/hash; zero requires authentic sealed producer proof")
            streams = phase["streams"]
            require(type(streams) is list and len(streams) <= 64, "V2 emitted stream census bound")
            identifiers = []
            for stream in streams:
                require(type(stream) is dict and set(stream) == {"streamID", "bytes", "sha256", "lastCommittedSequence"}
                        and type(stream["streamID"]) is str
                        and re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", stream["streamID"])
                        and type(stream["bytes"]) is int and stream["bytes"] > 0 and digest(stream["sha256"])
                        and type(stream["lastCommittedSequence"]) is int
                        and 0 < stream["lastCommittedSequence"] <= 100000,
                        "V2 actual complete emitted stream rows")
                identifiers.append(stream["streamID"])
            require(len(identifiers) == len(set(identifiers)), "V2 duplicate emitted stream")
    require(len(units) == len(set(units)) and set(units) == set(resolved["unitTestSelectors"]),
            "V2 every required executed unit method; counts cannot rescue missing methods")
    return {"status": "VERIFIED_BINDINGS_DATA_ONLY", "functionalQualification": PENDING,
            "gateQualification": False, "acceptance": False, "releaseReady": False, "executionAuthority": False}


def make_functional_assessment_v2(plan, *, run_id, manifest, chain, cold_binding, gallery):
    """Actual-caller byte bindings awaiting genuine independent source review."""
    validate_plan_v2(plan)
    require(type(run_id) is int and run_id > 0, "V2 assessment original ID")
    for value in (manifest, chain):
        reference_v2(value)
    registration_record_v2(plan, cold_binding)
    require(gallery is None if plan["selection"] == SHARED else type(gallery) is dict,
            "V2 RUI1 actual qualified gallery required")
    if gallery is not None:
        require(set(gallery) == {"catalogueSHA256", "proofSHA256", "presentationSHA256",
                "checklistSHA256", "attachmentsSHA256"} and all(digest(v) for v in gallery.values()),
                "V2 closed actual gallery byte bindings")
    return {"schema": FUNCTIONAL_SCHEMA_V2, "status": "ACTUAL_FUNCTIONAL_DATA_READY_REVIEW_PENDING",
        "runID": run_id, "runAttempt": 1, "head": plan["head"], "tree": plan["tree"],
        "purpose": plan["purpose"], "selection": plan["selection"], "planSHA256": sha(canonical(plan)),
        "sourceSHA256": plan["sources"], "manifest": manifest, "chain": chain, "coldBinding": cold_binding,
        "gallery": gallery, "strongerClaims": dict(STRONGER_CLAIMS_V2), "independentReview": None,
        "trustBoundary": "ROOT_GENUINE_SOURCE_MESSAGES_AND_INDEPENDENCE_REQUIRED",
        "functionalQualification": PENDING, "simulatorProtection": "UNSUPPORTED",
        "countsAsPerKindProtectionSuccess": False, "physicalProtection": "UNVERIFIED/DEFERRED",
        "physicalProtectionReleaseBlocker": True, "providerQualification": False,
        "acceptance": False, "releaseReady": False, "executionAuthority": False}


def validate_functional_review_v2(value, *, pending_reference, pending, message, context):
    """Check Root's genuinely received review binding; byte hashes cannot prove a speaker."""
    keys = {"schema", "subject", "verdict", "reviewer", "actualModel", "actualReasoningEffort",
            "independentNonauthor", "readOnly", "assessment", "manifest", "chain", "head", "tree",
            "runID", "runAttempt", "purpose", "selection", "planSHA256", "sourceSHA256", "message",
            "context", "executionAuthority", "acceptance", "releaseReady", "providerQualification"}
    require(type(value) is dict and set(value) == keys
        and value["schema"] == "root.faithful.received.phase1-functional-original-review.v2"
        and value["subject"] == ("shared-cold-original" if pending["selection"] == SHARED else "rui1-cold-original")
        and value["verdict"] == "PASS_BOUNDED_ACTUAL_PHASE1_SIMULATOR_FUNCTIONAL_ORIGINAL_V2"
        and type(value["reviewer"]) is str and re.fullmatch(r"/root/[a-z0-9_]+", value["reviewer"])
        and value["actualModel"] == "gpt-6.1-sol" and value["actualReasoningEffort"] == "xhigh"
        and value["independentNonauthor"] is True and value["readOnly"] is True
        and all(value[key] is False for key in ("executionAuthority", "acceptance", "releaseReady", "providerQualification")),
        "V2 genuinely received independent original review scope")
    reference_v2(pending_reference)
    exact(value["assessment"], pending_reference, "V2 review pending assessment bytes")
    for key in ("manifest", "chain", "head", "tree", "runID", "runAttempt", "purpose", "selection", "planSHA256", "sourceSHA256"):
        exact(value[key], pending[key], "V2 review exact " + key)
    for key, raw in (("message", message), ("context", context)):
        reference_v2(value[key])
        require(type(raw) is bytes and len(raw) == value[key]["bytes"] and sha(raw) == value[key]["SHA256"],
                "V2 genuine retained review " + key)
        try:
            require(bool(raw.decode("utf-8").strip()), "V2 nonempty source " + key)
        except UnicodeError as error:
            raise Refused("Phase1 gate: V2 review UTF8") from error
    return value


def qualify_functional_v2(pending, *, pending_reference, review_reference, review, message, context):
    validate_functional_review_v2(review, pending_reference=pending_reference, pending=pending,
                                  message=message, context=context)
    reference_v2(review_reference)
    require(review_reference["SHA256"] == sha(canonical(review)), "V2 review canonical raw digest")
    require(pending["status"] == "ACTUAL_FUNCTIONAL_DATA_READY_REVIEW_PENDING"
            and pending["functionalQualification"] == PENDING and pending["independentReview"] is None,
            "V2 only current pending original DATA may qualify")
    return {**pending, "status": "ROOT_REVIEWED_PHASE1_SIMULATOR_FUNCTIONAL_ORIGINAL_V2",
        "functionalQualification": FUNCTIONAL_SCOPE_V2, "independentReview": review_reference,
        "pendingAssessment": pending_reference,
        "trustBoundary": "ROOT_GENUINE_SOURCE_REVIEW_BOUND_FUNCTIONAL_ONLY_NO_EXECUTION_OR_RELEASE_AUTHORITY"}


def validate_genuine_candidate_review_v2(value, record, record_reference, *, message, context):
    """Two existing owner/integration subjects; no synthetic or model substitute for owner review."""
    keys = {"schema", "subject", "verdict", "reviewRecord", "head", "tree", "originals", "gallery",
        "reviewer", "actualModel", "actualReasoningEffort", "independentNonauthor", "readOnly", "humanOwner",
        "message", "context", "executionAuthority", "acceptance", "releaseReady", "providerQualification"}
    require(type(value) is dict and set(value) == keys
        and value["schema"] == "root.faithful.received.phase1-candidate-review.v2"
        and value["subject"] in ("candidate-integration", "owner-critical-states")
        and value["verdict"] == "APPROVE_PHASE1_FROZEN_CANDIDATE_V2"
        and all(value[key] is False for key in ("executionAuthority", "acceptance", "releaseReady", "providerQualification")),
        "V2 actual candidate review subject/scope")
    request = validate_review_request(record["request"], test_only=False)
    require(request["subject"] == value["subject"] and request["reportedDisposition"] == "approve"
        and record["status"] == REVIEW_PENDING and record["functionalQualification"] == PENDING,
        "V2 preserve V1 pending provenance and approving actual message")
    reference_v2(record_reference)
    exact(value["reviewRecord"], record_reference, "V2 exact provenance record")
    for key in ("head", "tree", "originals", "gallery"):
        exact(value[key], request[key], "V2 exact candidate review " + key)
    owner = value["subject"] == "owner-critical-states"
    if owner:
        require(value["humanOwner"] is True and value["reviewer"] is None and value["actualModel"] is None
            and value["actualReasoningEffort"] is None and value["independentNonauthor"] is None
            and value["readOnly"] is None, "V2 genuine human owner review; no model substitute")
    else:
        require(value["humanOwner"] is False and type(value["reviewer"]) is str
            and re.fullmatch(r"/root/[a-z0-9_]+", value["reviewer"])
            and value["actualModel"] == "gpt-6.1-sol" and value["actualReasoningEffort"] == "xhigh"
            and value["independentNonauthor"] is True and value["readOnly"] is True,
            "V2 genuine independent integration reviewer")
        exact((request["reviewer"]["model"], request["reviewer"]["effort"]),
              (value["actualModel"], value["actualReasoningEffort"]), "V2 actual integration model/effort provenance")
        require(request["speakerReference"] != request["reviewer"]["authorReference"], "V2 integration author cannot approve")
    for key, raw in (("message", message), ("context", context)):
        reference_v2(value[key])
        require(type(raw) is bytes and len(raw) == value[key]["bytes"] and sha(raw) == value[key]["SHA256"]
            == request[key + "SHA256"] and raw == record[key + "UTF8"].encode("utf-8"),
            "V2 exact genuinely received " + key)
    return value


# A separate development question; these schemas never enter PURPOSE_REFS.
COLD_SELECTION = "v23-cold-shared-original-v1"
COLD_PURPOSE = "cold-shared-route-development-v1"
COLD_PLAN_INPUT = "v23_cold_original_plan"
COLD_SCHEMA = "v23-cold-shared-development-intent.v1"
COLD_EVENT_SCHEMA = "v23-cold-shared-original-event-binding.v1"
COLD_REGISTRATION_SCHEMA = "v23-cold-shared-registration.v1"
COLD_ATTEMPT_SCHEMA = "v23-cold-shared-original-attempt.v1"
COLD_DISCOVERY_SCHEMA = "v23-cold-shared-original-discovery.v1"
COLD_PENDING = "PENDING"
COLD_PLAN_KEYS = PLAN_KEYS | {"kind"}
COLD_CLASSIFICATION = {**CLASSIFICATION, "functionalQualification": COLD_PENDING,
                       "developmentOnly": True, "status": "INCOMPLETE"}

def validate_cold_plan(value):
    require(type(value) is dict and set(value) == COLD_PLAN_KEYS, "closed plan keys")
    require(value["schema"] == COLD_SCHEMA, "plan schema")
    require(value["purpose"] == COLD_PURPOSE and value["kind"] == "development", "closed purpose")
    require(value["ref"] == INTEGRATION_REF, "purpose/ref mismatch")
    for key in ("head", "tree"):
        require(type(value[key]) is str and re.fullmatch(r"[0-9a-f]{40}", value[key]), key + " identity")
    require(value["head"] != BASE_MAIN and value["baseMain"] == BASE_MAIN, "Phase1 main baseline")
    require(value["selection"] == COLD_SELECTION, "closed selection")
    for key in ("selectionSHA256", "orderedUnitMethodsSHA256", "orderedUIMethodsSHA256"):
        require(digest(value[key]), key + " digest")
    require(type(value["sources"]) is dict and set(value["sources"]) == set(SOURCES)
            and all(digest(v) for v in value["sources"].values()), "closed source closure")
    exact(value["policies"], POLICIES, "approved policy bytes")
    require(all(value["sources"][p] == h for p, h in POLICIES.items()), "source/policy mismatch")
    exact(value["route"], ROUTE, "pinned route and budgets")
    exact(value["classification"], COLD_CLASSIFICATION, "pending-only classification")
    exact(value["collector"], {"path": COLLECTOR, "sha256": value["sources"][COLLECTOR]},
          "sole collector implementation")
    stamp = value["requestedAtUTC"]
    require(type(stamp) is str and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", stamp),
            "UTC timestamp")
    try:
        parsed_stamp = datetime.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise Refused("Phase1 gate: invalid UTC timestamp") from error
    require(parsed_stamp >= datetime.datetime(2026, 9, 26), "predates owner decision 24")
    return value



def parse_cold_plan(raw):
    return validate_cold_plan(decode(raw))


def cold_plan_from_event(raw):
    _, event = plan_from_event(raw)
    encoded = event.get("inputs", {}).get(COLD_PLAN_INPUT, "")
    require(type(encoded) is str, "cold original input string")
    require(not (encoded and event["inputs"].get(PLAN_INPUT, "")), "simultaneous cold and gate plans")
    return (None if encoded == "" else parse_cold_plan(encoded.encode("utf-8"))), event


def make_cold_plan(*, head, tree, resolved_bytes, sources, requested_at,
                   purpose=COLD_PURPOSE, selection=COLD_SELECTION):
    """Create pending intent from exact source facts, never a qualification receipt."""
    selected = decode(resolved_bytes, limit=4 * 1024 * 1024)
    require(type(selected) is dict, "resolved selection object")
    for field in ("unitTestSelectors", "uiTestSelectors"):
        require(type(selected.get(field)) is list and all(type(x) is str for x in selected[field]),
                "ordered selectors")
    require(purpose == COLD_PURPOSE and selection == COLD_SELECTION, "closed purpose")
    shared = selected.get("sharedCoverage")
    require(type(shared) is dict and shared.get("partitionID", "MISSING") is None
            and shared.get("partitionsPath") == PARTITIONS
            and shared.get("partitionsSHA256") == sources[PARTITIONS]
            and shared.get("developmentOnly") is True and shared.get("acceptance") is False
            and selected.get("tier") == "D40P" and selected.get("runUISmoke") is False
            and selected["uiTestSelectors"] == []
            and len(selected["unitTestSelectors"]) == len(set(selected["unitTestSelectors"])) > 0,
            "cold exact shared producer plan")
    return validate_cold_plan({
        "schema": COLD_SCHEMA, "purpose": purpose, "ref": INTEGRATION_REF, "kind": "development", "head": head,
        "tree": tree, "baseMain": BASE_MAIN, "selection": selection,
        "selectionSHA256": sha(resolved_bytes),
        "orderedUnitMethodsSHA256": sha(canonical(selected["unitTestSelectors"])),
        "orderedUIMethodsSHA256": sha(canonical(selected["uiTestSelectors"])),
        "sources": dict(sources), "policies": dict(POLICIES), "route": json.loads(canonical(ROUTE)),
        "classification": dict(COLD_CLASSIFICATION), "requestedAtUTC": requested_at,
        "collector": {"path": COLLECTOR, "sha256": sources[COLLECTOR]},
    })



def bind_cold_facts(plan, *, head, tree, integration_head, main_head, resolved_bytes, sources):
    validate_cold_plan(plan)
    require(head == plan["head"] == integration_head and tree == plan["tree"], "frozen checkout/ref/tree")
    require(main_head == BASE_MAIN, "main moved or wrong phase")
    rebuilt = make_cold_plan(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
                        resolved_bytes=resolved_bytes, sources=sources, requested_at=plan["requestedAtUTC"])
    exact(plan, rebuilt, "committed source/selection binding")



def cold_received_inputs_match_v2(received, requested):
    """Compare two closed received shapes without rewriting event/request bytes.

    v2 admits the complete request or the measured simultaneous omission of
    exactly three declared empty-string defaults. No subset or supplied profile
    is accepted; callers derive requested from cold_dispatch_inputs(plan).
    """
    omitted = {"s10_4_segment_source_run_ids", "s10_4_shared_payload_run_id", PLAN_INPUT}
    retained = {"execution_lane", "native_selection_id", "run_ui_smoke", "s10_4_shard_id",
                "s10_4_minimum_core_smoke_id", "s10_4_shared_segment_id", "v23_run_kind",
                "v23_d50_compiler_observation", "v23_d50_swift_driver_jobs_two", COLD_PLAN_INPUT}
    if type(received) is not dict or type(requested) is not dict or set(requested) != omitted | retained:
        return False
    if any(type(value) is not str for value in requested.values()) or any(requested[key] != "" for key in omitted):
        return False
    if set(received) != set(requested) and set(received) != retained:
        return False
    return all(type(received[key]) is str and received[key] == requested[key] for key in received)


def cold_dispatch_input_difference(raw, actual, expected):
    """Bounded refusal detail only; fingerprints never replace original inputs."""
    def value_facts(value):
        facts = {"type": type(value).__name__}
        try:
            encoded = canonical(value)
        except (TypeError, ValueError, OverflowError, RecursionError) as error:
            facts["canonicalEncodingError"] = type(error).__name__
        else:
            facts.update(canonicalBytes=len(encoded), canonicalSHA256=sha(encoded))
        return facts

    missing = sorted(set(expected) - set(actual))
    extra = sorted(set(actual) - set(expected))
    extra_facts = []
    for key in extra[:16]:
        encoded = canonical(key)
        extra_facts.append({"keyPrefix": key[:64], "canonicalBytes": len(encoded),
                            "canonicalSHA256": sha(encoded)})
    changed = [{"key": key, "actual": value_facts(actual[key]),
                "expected": value_facts(expected[key])}
               for key in sorted(set(actual) & set(expected)) if actual[key] != expected[key]]
    detail = {"schema": "v23-cold-dispatch-input-difference-diagnostic.v1",
              "originalEvent": {"bytes": len(raw), "SHA256": sha(raw)},
              "valueEncoding": "canonical JSON: sorted compact ASCII plus LF",
              "missingKeys": missing, "extraKeyCount": len(extra), "extraKeyFacts": extra_facts,
              "extraKeyDetailsComplete": len(extra) <= 16, "changedValues": changed}
    encoded = canonical(detail)
    require(len(encoded) <= 16 * 1024, "bounded cold input difference diagnostic")
    return "cold dispatch input difference: " + encoded.decode("ascii").rstrip("\n")


def bind_cold_original_event(raw, environment, *, head, tree, resolved_bytes, sources):
    """Pure worker/collector binding. No source, run or human trust is synthesized.

    The native caller must supply independently read checkout/selection/source
    facts; the sole collector must supply authenticated API run identity and its
    preregistered plan before relying on this returned pending binding.
    """
    plan, event = cold_plan_from_event(raw)
    if plan is None:
        return None
    e, inputs = environment, event["inputs"]
    require(e.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "original dispatch event")
    require(e.get("GITHUB_REPOSITORY") == REPOSITORY
            and type(event.get("repository")) is dict
            and event["repository"].get("full_name") == REPOSITORY, "original event repository")
    require(e.get("GITHUB_REF") == plan["ref"]
            and event.get("ref") in (plan["ref"], plan["ref"].removeprefix("refs/heads/")),
            "original event ref")
    require(e.get("GITHUB_SHA") == head == plan["head"] and tree == plan["tree"], "original event head/tree")
    require(e.get("GITHUB_RUN_ATTEMPT") == "1" and type(e.get("GITHUB_RUN_ID")) is str
            and re.fullmatch(r"[1-9][0-9]*", e["GITHUB_RUN_ID"]), "original event attempt/run")
    workflow_ref = REPOSITORY + "/" + ROUTE["workflow"] + "@" + plan["ref"]
    require(e.get("GITHUB_WORKFLOW_REF") == workflow_ref
            and e.get("GITHUB_WORKFLOW_SHA") == head, "original workflow source")
    require(inputs.get("v23_run_kind") == "development"
            and inputs.get("native_selection_id") == plan["selection"]
            and inputs.get("execution_lane") == ROUTE["executionLane"], "original event kind/selection/lane")
    require(inputs.get("run_ui_smoke") == "false",
            "original event UI intent")
    expected_inputs = cold_dispatch_inputs(plan)
    try:
        require(cold_received_inputs_match_v2(inputs, expected_inputs), "closed cold original dispatch inputs")
    except Refused as primary:
        try:
            primary.add_note(cold_dispatch_input_difference(raw, inputs, expected_inputs))
        except BaseException as diagnostic_error:
            try:
                primary.add_note("cold input diagnostic failed: " + type(diagnostic_error).__name__)
            except BaseException:
                pass  # Diagnostic/observer failure never replaces the admission refusal.
        raise
    rebuilt = make_cold_plan(purpose=plan["purpose"], head=head, tree=tree, selection=plan["selection"],
                        resolved_bytes=resolved_bytes, sources=sources, requested_at=plan["requestedAtUTC"])
    exact(plan, rebuilt, "original event committed source/selection")
    return {"schema": COLD_EVENT_SCHEMA, "plan": plan, "planSHA256": sha(canonical(plan)),
            "originalEventSHA256": sha(raw), "repository": REPOSITORY, "ref": plan["ref"],
            "head": head, "tree": tree, "workflowRef": workflow_ref, "workflowSHA": head,
            "runID": e["GITHUB_RUN_ID"], "runAttempt": "1", "kind": "development",
            "selection": plan["selection"], "functionalQualification": COLD_PENDING, "status": "INCOMPLETE",
            "developmentOnly": True, "providerQualification": False, "acceptance": False, "releaseReady": False}



def verify_cold_collected_event(binding, *, registered_plan_bytes, original_event_bytes, api_run,
                           tree, resolved_bytes, sources):
    """Bind retained input to an existing root registration and authenticated API facts.

    This is one necessary check, never complete collector/qualification admission.
    The caller must additionally verify exclusive attempt, sole claim, artifact
    provenance, all raw proof and genuine review provenance.
    """
    require(type(binding) is dict and binding.get("schema") == COLD_EVENT_SCHEMA, "retained event schema")
    plan = parse_cold_plan(registered_plan_bytes)
    exact(binding.get("plan"), plan, "retained event differs from registered plan")
    require(binding.get("planSHA256") == sha(registered_plan_bytes)
            and binding.get("originalEventSHA256") == sha(original_event_bytes), "retained event bytes")
    original_plan, _ = cold_plan_from_event(original_event_bytes)
    exact(original_plan, plan, "original event differs from registered plan")
    require(type(api_run) is dict and type(api_run.get("id")) is int and api_run["id"] > 0
            and type(api_run.get("run_attempt")) is int and api_run["run_attempt"] == 1,
            "authenticated API original")
    require((api_run.get("head_sha"), api_run.get("head_branch"), api_run.get("event"), api_run.get("path"))
            == (plan["head"], plan["ref"].removeprefix("refs/heads/"), "workflow_dispatch", ROUTE["workflow"]),
            "authenticated API identity")
    require(binding.get("runID") == str(api_run["id"]) and binding.get("runAttempt") == "1"
            and binding.get("head") == plan["head"] and binding.get("ref") == plan["ref"],
            "retained run/attempt/ref/head")
    exact(binding.get("functionalQualification"), COLD_PENDING, "retained pending status")
    expected = bind_cold_original_event(original_event_bytes, {
        "GITHUB_EVENT_NAME": api_run["event"], "GITHUB_REPOSITORY": REPOSITORY,
        "GITHUB_REF": "refs/heads/" + api_run["head_branch"], "GITHUB_SHA": api_run["head_sha"],
        "GITHUB_RUN_ID": str(api_run["id"]), "GITHUB_RUN_ATTEMPT": str(api_run["run_attempt"]),
        "GITHUB_WORKFLOW_REF": REPOSITORY + "/" + api_run["path"] + "@" + plan["ref"],
        "GITHUB_WORKFLOW_SHA": api_run["head_sha"],
    }, head=api_run["head_sha"], tree=tree, resolved_bytes=resolved_bytes, sources=sources)
    exact(binding, expected, "complete retained event binding")
    return {"planSHA256": sha(registered_plan_bytes), "originalEventSHA256": sha(original_event_bytes),
            "runID": str(api_run["id"]), "runAttempt": "1", "kind": "development",
            "functionalQualification": COLD_PENDING, "status": "INCOMPLETE",
            "developmentOnly": True, "providerQualification": False, "acceptance": False, "releaseReady": False}



def cold_original_key(plan):
    validate_cold_plan(plan)
    return (plan["head"], COLD_PURPOSE, COLD_SELECTION)


def cold_original_stem(plan):
    return "-".join(cold_original_key(plan))


def cold_conflicting_originals(plan, records, attempt_names):
    head, _, selection = cold_original_key(plan)
    conflicts = []
    for record in records:
        require(type(record) is dict, "malformed cold ledger record")
        if "event" not in record and record.get("head") == head and (
                record.get("selection") == selection or any(str(k).startswith("cold") for k in record)):
            conflicts.append("ledger:" + str(record.get("runID", "unknown")))
    for name in attempt_names:
        require(type(name) is str and Path(name).name == name, "cold attempt basename")
        if name.startswith(head + "-") and (selection in name or COLD_PURPOSE in name):
            conflicts.append("attempt:" + name)
    return conflicts


def cold_dispatch_inputs(plan):
    validate_cold_plan(plan)
    return {"execution_lane": ROUTE["executionLane"], "native_selection_id": COLD_SELECTION,
            "run_ui_smoke": "false", "s10_4_shard_id": "none", "s10_4_minimum_core_smoke_id": "none",
            "s10_4_shared_segment_id": "none", "s10_4_shared_payload_run_id": "",
            "s10_4_segment_source_run_ids": "", "v23_run_kind": "development",
            "v23_d50_compiler_observation": "false", "v23_d50_swift_driver_jobs_two": "false",
            PLAN_INPUT: "", COLD_PLAN_INPUT: canonical(plan).decode("utf-8")}


def cold_dispatch_argv(plan, workflow_id):
    cold_dispatch_inputs(plan)
    require(type(workflow_id) is int and workflow_id > 0, "cold workflow API identity")
    return ["gh", "workflow", "run", str(workflow_id), "--repo", REPOSITORY,
            "--ref", INTEGRATION_REF.removeprefix("refs/heads/"), "--json"]


def verify_cold_attempt_inputs(attempt, original_event_raw):
    plan, event = cold_plan_from_event(original_event_raw)
    require(plan is not None and canonical(plan).decode("utf-8") == attempt["planBytes"], "cold original intent")
    expected_inputs = cold_dispatch_inputs(plan)
    require(canonical(expected_inputs).decode("utf-8") == attempt["inputBytes"]
            and cold_received_inputs_match_v2(event["inputs"], expected_inputs), "cold exact requested inputs")
    return {"originalEventSHA256": sha(original_event_raw), "inputSHA256": sha(attempt["inputBytes"].encode("utf-8"))}


def validate_cold_attempt(value, plan, registration_raw):
    """Closed root record, not authentication of caller-supplied API dictionaries.

    Actual fixed-endpoint capture belongs to the dormant dispatcher. Collection
    rechecks these bytes, the live original and exact worker inputs separately.
    """
    validate_cold_plan(plan)
    require(plan["purpose"] == COLD_PURPOSE, "candidate-only attempt lifecycle")
    keys = {"schema", "planBytes", "planSHA256", "registrationSHA256", "collectorSHA256", "collectorID",
            "workflowID", "repositoryID", "knownRunIDs", "requestedAtUTC", "integrationHead", "mainHead",
            "inputBytes", "argv", "observations", "ledgerBytes", "attemptNames"}
    require(type(value) is dict and set(value) == keys and value["schema"] == COLD_ATTEMPT_SCHEMA,
            "closed consumed attempt v2")
    exact(decode(registration_raw), {"schema": COLD_REGISTRATION_SCHEMA, "plan": plan,
          "planSHA256": sha(canonical(plan)), "dispatchEnabled": False, "functionalQualification": COLD_PENDING},
          "attempt pending registration")
    require(value["planBytes"] == canonical(plan).decode("utf-8")
            and value["planSHA256"] == sha(canonical(plan))
            and value["registrationSHA256"] == sha(registration_raw)
            and value["collectorSHA256"] == plan["sources"][COLLECTOR]
            and value["integrationHead"] == plan["head"] and value["mainHead"] == BASE_MAIN,
            "attempt frozen plan/source/registration")
    require(type(value["collectorID"]) is str and re.fullmatch(r"[0-9a-f]{32}", value["collectorID"]),
            "sole collector identity")
    validate_cold_plan(dict(plan, requestedAtUTC=value["requestedAtUTC"]))
    require(value["requestedAtUTC"] >= plan["requestedAtUTC"], "attempt predates registration intent")
    exact(value["argv"], cold_dispatch_argv(plan, value["workflowID"]), "exact dispatch argv")
    require(value["inputBytes"] == canonical(cold_dispatch_inputs(plan)).decode("utf-8"), "exact dispatch input bytes")
    observations = value["observations"]
    require(type(observations) is dict and set(observations) == {"repository", "workflow", "refs", "headRuns", "activeRuns"},
            "closed predispatch observations")
    repository, workflow = observations["repository"], observations["workflow"]
    require(type(repository) is dict and repository.get("full_name") == REPOSITORY
            and type(repository.get("id")) is int and repository["id"] > 0
            and type(value["repositoryID"]) is int and value["repositoryID"] == repository["id"],
            "authenticated repository identity")
    require(type(workflow) is dict and type(workflow.get("id")) is int and workflow["id"] == value["workflowID"]
            and workflow.get("path") == ROUTE["workflow"] and workflow.get("state") == "active", "active original workflow")
    validate_ref_observations(observations["refs"], plan)
    identifiers = validate_run_census(observations["headRuns"], head=plan["head"])
    exact(value["knownRunIDs"], identifiers, "known original census")
    active = observations["activeRuns"]
    require(type(active) is dict and set(active) == set(ACTIVE_RUN_STATUSES), "closed active-run census")
    active_ids = [identifier for status in ACTIVE_RUN_STATUSES for identifier in validate_run_census(active[status])]
    require(len(active_ids) == len(set(active_ids)) < 5, "cold shared-family active capacity")
    require(type(value["ledgerBytes"]) is str, "retained original ledger bytes")
    try:
        records = [json.loads(line, object_pairs_hook=object_pairs,
                   parse_constant=lambda _: (_ for _ in ()).throw(Refused("nonfinite ledger")))
                   for line in value["ledgerBytes"].splitlines() if line.strip()]
    except (ValueError, UnicodeError) as error:
        raise Refused("Phase1 gate: invalid retained ledger") from error
    require(all(type(row) is dict for row in records), "ledger objects")
    originals = [row for row in records if "event" not in row]
    require(all(type(row.get("runID")) is int and row["runID"] > 0 for row in originals), "ledger original IDs")
    known = [row["runID"] for row in originals]
    require(len(known) == len(set(known)) and set(identifiers) <= set(known), "unknown or duplicate ledger originals")
    by_id = {row["runID"]: row for row in originals}
    require(all(by_id[identifier].get("head") == plan["head"] for identifier in identifiers),
            "known ledger original head")
    for status, census in active.items():
        for row in census["workflow_runs"]:
            recorded = by_id.get(row["id"], {})
            require(row.get("status") == status and recorded.get("kind") == "development"
                    and recorded.get("head") == row.get("head_sha")
                    and type(row.get("head_sha")) is str and row["head_sha"] != plan["head"]
                    and row.get("run_attempt") == 1 and type(row.get("run_attempt")) is int
                    and row.get("path") == ROUTE["workflow"] and row.get("event") == "workflow_dispatch"
                    and not any(str(key).startswith("phase1") for key in recorded),
                    "cold shared-family active gate, unknown, unmarked or same-head original")
    names = value["attemptNames"]
    require(type(names) is list and all(type(x) is str for x in names) and names == sorted(set(names)),
            "complete attempt-name census")
    require(not cold_conflicting_originals(plan, records, names), "consumed or historical question collision")
    require(len(canonical(value)) <= MAX_ATTEMPT_BYTES, "bounded consumed attempt")
    return value



def make_cold_attempt(plan, registration_raw, *, collector_id, requested_at, observations, ledger_bytes, attempt_names):
    value = {"schema": COLD_ATTEMPT_SCHEMA, "planBytes": canonical(plan).decode("utf-8"),
             "planSHA256": sha(canonical(plan)), "registrationSHA256": sha(registration_raw),
             "collectorSHA256": plan["sources"][COLLECTOR], "collectorID": collector_id,
             "workflowID": observations["workflow"]["id"], "repositoryID": observations["repository"]["id"],
             "knownRunIDs": validate_run_census(observations["headRuns"], head=plan["head"]),
             "requestedAtUTC": requested_at, "integrationHead": plan["head"], "mainHead": BASE_MAIN,
             "inputBytes": canonical(cold_dispatch_inputs(plan)).decode("utf-8"),
             "argv": cold_dispatch_argv(plan, observations["workflow"]["id"]), "observations": observations,
             "ledgerBytes": ledger_bytes, "attemptNames": attempt_names}
    return validate_cold_attempt(value, plan, registration_raw)



def register_cold(plan, directory):
    validate_cold_plan(plan)
    durable_directory(directory)
    target = Path(directory) / (cold_original_stem(plan) + ".json")
    record = {"schema": COLD_REGISTRATION_SCHEMA, "plan": plan, "planSHA256": sha(canonical(plan)),
              "dispatchEnabled": False, "functionalQualification": COLD_PENDING}
    write_immutable(target, canonical(record))
    return target, record


class ColdContract:
    """Dedicated helper interface; never turns cold DATA into a gate envelope."""
    CANDIDATE = COLD_PURPOSE
    REGISTRATION_SCHEMA = COLD_REGISTRATION_SCHEMA
    ATTEMPT_SCHEMA = COLD_ATTEMPT_SCHEMA
    DISCOVERY_SCHEMA = COLD_DISCOVERY_SCHEMA
    EVENT_SCHEMA = COLD_EVENT_SCHEMA
    PENDING = COLD_PENDING
    SOURCES, COLLECTOR = SOURCES, COLLECTOR
    MAX_PLAN_BYTES, MAX_EVENT_BYTES = MAX_PLAN_BYTES, MAX_EVENT_BYTES
    MAX_ATTEMPT_BYTES, MAX_ORIGINAL_RUNS = MAX_ATTEMPT_BYTES, MAX_ORIGINAL_RUNS
    ACTIVE_RUN_STATUSES = ACTIVE_RUN_STATUSES
    Refused = Refused
    require, exact, canonical = staticmethod(require), staticmethod(exact), staticmethod(canonical)
    sha, decode, object_pairs = staticmethod(sha), staticmethod(decode), staticmethod(object_pairs)
    digest = staticmethod(digest)
    regular_bytes, durable_directory = staticmethod(regular_bytes), staticmethod(durable_directory)
    write_immutable = staticmethod(write_immutable)
    parse_plan, validate_plan, make_plan = staticmethod(parse_cold_plan), staticmethod(validate_cold_plan), staticmethod(make_cold_plan)
    bind_facts, original_stem = staticmethod(bind_cold_facts), staticmethod(cold_original_stem)
    conflicting_originals = staticmethod(cold_conflicting_originals)
    validate_attempt, make_attempt = staticmethod(validate_cold_attempt), staticmethod(make_cold_attempt)
    validate_run_census, validate_ref_observations = staticmethod(validate_run_census), staticmethod(validate_ref_observations)
    verify_attempt_inputs = staticmethod(verify_cold_attempt_inputs)
    verify_collected_event = staticmethod(verify_cold_collected_event)
    register_candidate = staticmethod(register_cold)
