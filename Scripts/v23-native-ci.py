#!/usr/bin/env python3
"""Closed V23 native admission and factual evidence checks, not a CI scheduler.

The incumbent workflow owns native commands, budgets, credentials and uploads.
This module has no API client and never dispatches, retries or promotes a run.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


CONTRACT = "v23.integration.current-native.v1"
TASK = "V23-INTEGRATION-20260910"
REPOSITORY = "Asset-Rounds/AssetRounds"
REFS = {"refs/heads/codex/v23-s10-integration-20260910", "refs/heads/main"}
LANES = {
    "github-xcode-26.6-acceptance": ("github", "macos-26"),
    "bitrise-build-hub-xcode-26.6-acceptance": ("bitrise", "bitrise-runner-Asset Roundddd"),
}
TIERS = {"N8": (300, 600, 900, 0, 2400), "P12": (300, 600, 900, 900, 3300),
         "F25": (300, 900, 1200, 1800, 4500)}
BUDGET_KEYS = ("setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds",
               "uiTimeoutSeconds", "totalBudgetSeconds")
PROTOCOL_PATHS = (
    ".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml",
    "Scripts/v23-native-ci.py", "Scripts/build-smoke.sh", "Scripts/test-smoke.sh",
    "Scripts/ui-smoke.sh", "Scripts/run-with-timeout.sh",
    "Scripts/validate-required-evidence.sh",
)
SELECTION_MAP_PATH = "Scripts/ci-selection-map.json"
DEFAULT_SELECTION_ID = "default-132"


def require(condition, message):
    if not condition:
        raise ValueError("invalid V23 native evidence: " + message)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def read_json(path):
    require(path.is_file() and not path.is_symlink(), "missing or unsafe JSON file")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)


def sha256(data):
    return hashlib.sha256(data).hexdigest().upper()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def validate_selection(selection):
    require(isinstance(selection, dict), "selection object")
    require(set(selection) == {"schemaVersion", "taskID", "tier", "runUISmoke",
                              "unitTestSelectors", "uiTestSelectors", *BUDGET_KEYS}, "selection keys")
    require(type(selection["schemaVersion"]) is int and selection["schemaVersion"] == 1, "schema")
    require(selection["taskID"] == TASK and selection["tier"] in TIERS, "task/tier")
    require(all(type(selection[key]) is int for key in BUDGET_KEYS), "integer budgets")
    require(tuple(selection[key] for key in BUDGET_KEYS) == TIERS[selection["tier"]], "budgets")
    ui = selection["tier"] != "N8"
    require(type(selection["runUISmoke"]) is bool and selection["runUISmoke"] == ui, "UI/tier")
    for key, bundle in (("unitTestSelectors", "FieldEvidenceAppTests"),
                        ("uiTestSelectors", "FieldEvidenceAppUITests")):
        selectors = selection[key]
        require(isinstance(selectors, list) and all(isinstance(x, str) for x in selectors), key)
        require(len(selectors) == len(set(selectors)), "duplicate selectors")
        require(all(re.fullmatch(re.escape(bundle) + r"/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+", x)
                    for x in selectors), "exact native method selectors")
    require(bool(selection["unitTestSelectors"]), "no unit methods")
    require(len(selection["uiTestSelectors"]) == int(ui), "UI method count")


def selection_class(selector):
    parts = selector.split("/")
    require(len(parts) == 3 and parts[0] == "FieldEvidenceAppTests", "unit selector class")
    return parts[1]


def resolve_selection(default, selection_map, selection_id):
    """Resolve a closed N8 partition from the checked-in default selection.

    The map cannot carry selectors or paths.  It may only name complete XCTest
    classes already present in the default selection, so it cannot become an
    out-of-band selector override.
    """
    validate_selection(default)
    require(isinstance(selection_map, dict), "selection map object")
    require(set(selection_map) == {"schemaVersion", "taskID", "defaultSelectionID", "groups"},
            "selection map keys")
    require(selection_map["schemaVersion"] == 1 and selection_map["taskID"] == TASK,
            "selection map identity")
    require(selection_map["defaultSelectionID"] == DEFAULT_SELECTION_ID, "selection map default")
    require(isinstance(selection_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", selection_id),
            "selection ID")
    groups = selection_map["groups"]
    require(isinstance(groups, list) and len(groups) == 15, "selection group count")
    defaults = set(default["unitTestSelectors"])
    default_classes = {selection_class(item) for item in defaults}
    covered = set()
    ids = set()
    resolved = {}
    for group in groups:
        require(isinstance(group, dict) and set(group) == {"id", "classes", "methodCount"},
                "selection group shape")
        group_id, classes, count = group["id"], group["classes"], group["methodCount"]
        require(isinstance(group_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", group_id)
                and group_id != DEFAULT_SELECTION_ID and group_id not in ids, "selection group ID")
        require(isinstance(classes, list) and classes and all(isinstance(item, str) and
                re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*Tests", item) for item in classes)
                and len(classes) == len(set(classes)), "selection group classes")
        require(set(classes) <= default_classes, "selection group contains unselected class")
        require(type(count) is int and count > 0, "selection group count value")
        members = [item for item in default["unitTestSelectors"] if selection_class(item) in classes]
        require(len(members) == count and members, "selection group members")
        member_set = set(members)
        require(not (covered & member_set), "overlapping selection group")
        covered.update(member_set)
        ids.add(group_id)
        derived = dict(default)
        derived["unitTestSelectors"] = members
        validate_selection(derived)
        resolved[group_id] = derived
    require(covered == defaults, "selection groups must cover default exactly")
    if selection_id == DEFAULT_SELECTION_ID:
        return default
    require(selection_id in resolved, "unknown selection ID")
    return resolved[selection_id]


def selected_input(root, environment):
    """Return the exact default or closed mapped selection for this execution."""
    default = read_json(root / "Scripts/ci-selection.json")
    selection_id = environment.get("NATIVE_SELECTION_ID", DEFAULT_SELECTION_ID)
    enabled = (environment.get("CI_NATIVE_ACCEPTANCE_CONTRACT") == CONTRACT
               or environment.get("SHARED_LANE") in LANES)
    if not enabled:
        require(selection_id == DEFAULT_SELECTION_ID, "selection ID outside ordinary route")
        return default, {"selectionID": DEFAULT_SELECTION_ID,
                         "selectionSHA256": sha256(canonical(default)), "selectionMapSHA256": ""}
    selection_map = read_json(root / SELECTION_MAP_PATH)
    selected = resolve_selection(default, selection_map, selection_id)
    return selected, {"selectionID": selection_id, "selectionSHA256": sha256(canonical(selected)),
                      "selectionMapSHA256": sha256((root / SELECTION_MAP_PATH).read_bytes())}


def admission(selection, environment, checkout_head, stage, selection_record=None):
    """Validate actual source inputs. Return None only for unchanged legacy routes."""
    e = environment
    if selection_record is None:
        selection_record = {"selectionID": DEFAULT_SELECTION_ID,
                            "selectionSHA256": sha256(canonical(selection)), "selectionMapSHA256": ""}
    require(stage in ("dispatch", "worker"), "admission stage")
    if stage == "dispatch":
        lane = e.get("SHARED_LANE", "")
        if selection.get("taskID") != TASK and lane != "bitrise-build-hub-xcode-26.6-acceptance":
            return None
        require(lane in LANES, "integration lane")
        provider, label = LANES[lane]
        fields = {
            "SHARED_SHARD": "none", "SHARED_SEGMENT": "none", "SMOKE_ID": "none",
            "SHARED_SOURCE_RUN": "", "SHARED_SOURCE_MAP": "",
        }
        ui = e.get("SHARED_UI")
    else:
        contract = e.get("CI_NATIVE_ACCEPTANCE_CONTRACT", "none")
        if contract == "none" and selection.get("taskID") != TASK:
            return None
        require(contract == CONTRACT, "worker contract")
        provider, label = e.get("CI_RUNNER_PROVIDER"), e.get("CI_RUNNER_LABEL")
        lanes = [name for name, binding in LANES.items() if binding == (provider, label)]
        require(len(lanes) == 1, "provider/label")
        lane = lanes[0]
        fields = {
            "DISPATCH_S10_4_SHARD_ID": "none", "DISPATCH_S10_4_SEGMENT_ID": "none",
            "DISPATCH_S10_4_EXECUTION_ROLE": "independent", "DISPATCH_S10_4_PILOT_MODE": "false",
            "DISPATCH_S10_4_UNIT_ONLY": "false", "DISPATCH_S10_4_PAYLOAD_ARTIFACT_NAME": "",
            "DISPATCH_S10_4_DIAGNOSTIC_PROBE_ID": "none",
            "DISPATCH_S10_4_DIAGNOSTIC_EXECUTION_LANE": "none",
            "CI_S10_4_SHARED_BUILD_MODE": "none", "CI_S10_4_SHARED_PAYLOAD_RUN_ID": "",
            "WORKER_S10_4_MINIMUM_SEGMENT_ID": "none", "WORKER_S10_4_SHARED_MATRIX_ID": "",
            "WORKER_S10_4_MINIMUM_CORE_SMOKE_ID": "none", "WORKER_S10_4_SEGMENT_SOURCE_RUN_IDS": "",
        }
        ui = e.get("DISPATCH_RUN_UI_SMOKE")
    validate_selection(selection)
    if stage == "worker" and e.get("CI_NATIVE_ACCEPTANCE_CONTRACT") == CONTRACT:
        require(e.get("DISPATCH_NATIVE_SELECTION_ID") == selection_record["selectionID"],
                "dispatcher selection ID")
        require(e.get("DISPATCH_NATIVE_SELECTION_SHA256") == selection_record["selectionSHA256"],
                "dispatcher selection digest")
        require(e.get("DISPATCH_NATIVE_SELECTION_MAP_SHA256") == selection_record["selectionMapSHA256"],
                "dispatcher selection map digest")
    require(all(e.get(key) == value for key, value in fields.items()), "foreign execution inputs")
    require(ui == str(selection["runUISmoke"]).lower(), "dispatch UI selection")
    require(e.get("GITHUB_REPOSITORY") == REPOSITORY, "repository")
    require(e.get("GITHUB_REF") in REFS, "ref")
    require(e.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "event")
    head = e.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[0-9a-f]{40}", head) is not None and checkout_head == head, "exact checkout head")
    require(all(re.fullmatch(r"[1-9][0-9]*", e.get(key, ""))
                for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT")), "original run identity")
    return {"contractID": CONTRACT, "taskID": TASK, "repository": REPOSITORY,
            "ref": e["GITHUB_REF"], "head": head, "runID": e["GITHUB_RUN_ID"],
            "runAttempt": e["GITHUB_RUN_ATTEMPT"], "executionLane": lane,
            "runnerProvider": provider, "runnerLabel": label, **selection_record}


def executed_methods(result, expected, bundle, bundle_type):
    """Read original xcresult test nodes; never deduplicate or count skipped tests."""
    require(isinstance(result, dict) and isinstance(result.get("testNodes"), list), "native test tree")
    observed = []
    bundles = []

    def walk(node, current_bundle=None):
        require(isinstance(node, dict), "native test node")
        children = node.get("children", [])
        require(isinstance(children, list), "native test children")
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            require(node.get("nodeType") == bundle_type and node.get("name") == bundle, "native bundle")
            current_bundle = bundle
            bundles.append(bundle)
        if node.get("nodeType") == "Test Case":
            require(current_bundle == bundle and not children, "leaf native case ownership")
            identifier = node.get("nodeIdentifier")
            require(isinstance(identifier, str), "native identifier")
            identifier = re.sub(r"\(\)$", "", identifier)
            if not identifier.startswith(bundle + "/"):
                identifier = bundle + "/" + identifier
            require(node.get("result") == "Passed", "native case did not pass")
            observed.append(identifier)
        else:
            for child in children:
                walk(child, current_bundle)

    for node in result["testNodes"]:
        walk(node)
    require(bundles == [bundle], "exactly one native bundle")
    require(len(observed) == len(set(observed)), "duplicate native methods")
    require(sorted(observed) == sorted(expected) and observed, "exact executed method set")
    return sorted(observed)


def key_values(path):
    require(path.is_file() and not path.is_symlink(), "missing fact file")
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        require(bool(separator) and bool(key), "fact line")
        pairs.append((key, value))
    return unique_pairs(pairs)


def source_binding(root):
    sources = {}
    for relative in PROTOCOL_PATHS:
        path = root / relative
        require(path.is_file() and not path.is_symlink(), "protocol source")
        sources[relative] = sha256(path.read_bytes())
    selection_map = root / SELECTION_MAP_PATH
    require(selection_map.is_file() and not selection_map.is_symlink(), "selection map source")
    return {"protocolSources": sources, "protocolSHA256": sha256(canonical(sources)),
            "selectorSHA256": sha256((root / "Scripts/ci-selection.json").read_bytes()),
            "selectionMapSHA256": sha256(selection_map.read_bytes())}


def verify_checkpoint(root, artifact, record, selection, environment):
    require(environment.get("NATIVE_PRIOR_JOB_STATUS") == "success", "earlier job failure")
    require(read_json(artifact / "native-admission.json") == record, "admission changed")
    selected_artifact = artifact / "ci-selection.selected.json"
    require(selected_artifact.is_file() and not selected_artifact.is_symlink()
            and selected_artifact.read_bytes() == canonical(selection), "selected artifact binding")
    if record["selectionMapSHA256"]:
        selection_map = artifact / "ci-selection-map.json"
        require(selection_map.is_file() and not selection_map.is_symlink()
                and sha256(selection_map.read_bytes()) == record["selectionMapSHA256"],
                "selection map artifact binding")
    provider = key_values(artifact / "runner-provider.txt")
    require(provider.get("provider") == record["runnerProvider"]
            and provider.get("label") == record["runnerLabel"], "observed provider")
    require(provider.get("runner_architecture") == "ARM64"
            and provider.get("uname_architecture") == "arm64", "architecture")
    expected_dir = ("/Applications/Xcode-26.6.0.app/Contents/Developer"
                    if record["runnerProvider"] == "bitrise"
                    else "/Applications/Xcode_26.6.app/Contents/Developer")
    require(provider.get("developer_dir") == expected_dir, "resolved developer directory")
    require((artifact / "xcode-version.txt").read_text().splitlines()
            == ["Xcode 26.6", "Build version 17F113"], "observed Xcode")
    sdk = key_values(artifact / "native-sdk.txt")
    require(sdk == {"sdk": "iphonesimulator", "version": "26.5", "build": "23F81a"}, "observed SDK")
    simulator = key_values(artifact / "simulator-selection.txt")
    require((simulator.get("runtime"), simulator.get("runtime_build"), simulator.get("name"))
            == ("iOS 26.2", "23C54", "iPhone 17"), "observed Simulator")
    require(simulator.get("initial_state") == "Shutdown"
            and simulator.get("udid") == environment.get("CI_NATIVE_CREATED_SIMULATOR_UDID"),
            "fresh owned Simulator")
    units = executed_methods(read_json(artifact / "unit-test-results.json"),
                             selection["unitTestSelectors"], "FieldEvidenceAppTests", "Unit test bundle")
    ui = []
    if selection["runUISmoke"]:
        ui = executed_methods(read_json(artifact / "ui-test-results.json"),
                              selection["uiTestSelectors"], "FieldEvidenceAppUITests", "UI test bundle")
        screenshot = artifact / "ui-final.png"
        require(screenshot.is_file() and not screenshot.is_symlink()
                and screenshot.stat().st_size > 8, "native UI screenshot")
        with screenshot.open("rb") as stream:
            require(stream.read(8) == b"\x89PNG\r\n\x1a\n", "native UI PNG")
    else:
        require(not any((artifact / name).exists() for name in
                        ("UISmoke.xcresult", "ui-test-results.json", "ui-final.png", "ui-smoke.log")),
                "unexpected UI evidence")
    if record["runnerProvider"] == "bitrise":
        require(provider.get("macos_product_version") == "26.6.1", "Bitrise OS")
        for name in ("bitrise-build-cache-cli-verification.txt", "bitrise-build-cache-wrapper-paths.txt"):
            path = artifact / name
            require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0, "cache provenance")
        activation = (artifact / "bitrise-build-cache-activation.log").read_text().splitlines()
        require(activation.count("benchmark_phase=established") > 0
                and activation.count("benchmark_phase=established") == activation.count("activation_exit=0")
                and activation.count("cache=true") == activation.count("activation_exit=0")
                and activation.count("cache_push=true") == activation.count("activation_exit=0"), "cache activation")
    return {**record, "recordType": "validated-native-checkpoint", "executedUnitMethods": units,
            "executedUIMethods": ui, "simulator": simulator, "provider": provider, "sdk": sdk,
            "wholeAppAcceptance": False, "humanReviewComplete": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("admit", "verify", "select"))
    parser.add_argument("--stage", choices=("dispatch", "worker"), default="worker")
    parser.add_argument("--output")
    args = parser.parse_args()
    root = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    selection, selection_record = selected_input(root, os.environ)
    if args.command == "select":
        require(args.output is not None, "selection output")
        output = Path(args.output)
        require(output.parent.is_dir() and not output.exists() and not output.is_symlink(), "selection output path")
        output.write_bytes(canonical(selection))
        return
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    record = admission(selection, os.environ, head, args.stage, selection_record)
    if args.stage == "dispatch":
        require(args.command == "admit", "dispatch command")
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write("native_acceptance_contract=" + (CONTRACT if record else "none") + "\n")
            if record:
                stream.write("native_selection_id=" + record["selectionID"] + "\n")
                stream.write("native_selection_sha256=" + record["selectionSHA256"] + "\n")
                stream.write("native_selection_map_sha256=" + record["selectionMapSHA256"] + "\n")
        return
    if record is None:
        return
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--"], cwd=root, check=True, stdout=subprocess.DEVNULL)
    record.update(source_binding(root))
    record["gitTree"] = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    artifact = Path(os.environ["CI_ARTIFACT_DIR"])
    require(artifact.is_dir() and not artifact.is_symlink(), "artifact directory")
    name = "native-admission.json"
    if args.command == "verify":
        record = verify_checkpoint(root, artifact, record, selection, os.environ)
        name = "native-checkpoint.json"
    with (artifact / name).open("xb") as stream:
        stream.write(canonical(record))


if __name__ == "__main__":
    main()
