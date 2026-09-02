#!/usr/bin/env python3
"""Validate the isolated V30 development route; never grant native/final credit."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "docs/design/v30/"
SELECTION = PREFIX + "execution/V30_CI_SELECTION.json"
ROUTE = PREFIX + "execution/V30_PROVISIONAL_DEVELOPMENT_ROUTE_SELECTOR.json"
CONTRACT = PREFIX + "contracts/V30ProvisionalCIAndCheckpointContractV1.json"
AUTHORITY = PREFIX + "authority/V30PreS10ProvisionalImplementationAuthorityV1.json"
FENCES = PREFIX + "authority/V30PreS10PathFencesV1.json"
REF = "refs/heads/phase/v30-globalization"
REPOSITORY = "Asset-Rounds/AssetRounds"
FIELDS = ["setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds",
          "uiTimeoutSeconds", "totalBudgetSeconds"]
TIERS = {"N8": [300, 600, 900, 0, 2400], "P12": [300, 600, 900, 900, 3300],
         "F25": [300, 900, 1200, 1800, 4500]}


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def payload_digest(value):
    raw = {k: v for k, v in value.items() if k != "payloadDigest"}
    return sha((json.dumps(raw, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode())


def verify_adapter(path, expected_sha, source=None):
    """Undo only the issued selector adapter and prove all baseline bytes remain."""
    value = (ROOT / path).read_text(encoding="utf-8") if source is None else source
    require("Scripts/ci-selection.json" not in value, "inherited selector read")
    if path.endswith("ios-ci.yml"):
        additions = [
            '          test "$GITHUB_REPOSITORY" = "Asset-Rounds/AssetRounds"\n'
            '          test "$GITHUB_REF" = "refs/heads/phase/v30-globalization"\n'
            '          test "$GITHUB_EVENT_NAME" = "workflow_dispatch"\n',
            '          python3 -B Scripts/v30/validate_v30_provisional_ci_contract.py --hosted --dispatch-ui "$DISPATCH_RUN_UI_SMOKE" \\\n'
            '            | tee "$CI_ARTIFACT_DIR/v30-selection-validation.json"\n\n',
        ]
        for addition in additions:
            require(value.count(addition) == 1, "missing/duplicate workflow guard")
            value = value.replace(addition, "", 1)
        value = value.replace(".selector | exact_keys", "exact_keys")
        value = value.replace(".selector[$key] as $selectors", ".[$key] as $selectors")
        for key in ["runUISmoke", "taskID", "tier", *FIELDS]:
            value = value.replace("jq -r '.selector." + key, "jq -r '." + key)
    else:
        addition = '\npython3 -B Scripts/v30/validate_v30_provisional_ci_contract.py --hosted --dispatch-ui "${CI_RUN_UI_SMOKE:?}"\n'
        require(value.count(addition) == 1, "missing/duplicate helper guard")
        value = value.replace(addition, "", 1)
        value = value.replace(".selector.unitTestSelectors[]", ".unitTestSelectors[]")
        value = value.replace(".selector.uiTestSelectors[]", ".uiTestSelectors[]")
    value = value.replace(SELECTION, "Scripts/ci-selection.json")
    require(sha(value.encode()) == expected_sha, "non-adapter baseline change: " + path)


def validate_selection(value, task, fences, route_hash):
    keys = {"schemaVersion", "kind", "cardID", "cardTitle", "authorityID", "packageBinding",
            "mode", "selector", "hostedDispatchAllowed", "hostedDispatchUnlockCard",
            "windowsStaticChecksAllowed", "preS10FinalCredit", "reason", "payloadDigest",
            "branchRef", "developmentRouteSHA256"}
    require(set(value) == keys, "selection envelope fields")
    require(value["schemaVersion"] == "V30BootstrapPayloadV1" and value["kind"] == "V30CISelectionV1", "selection version")
    require(value["payloadDigest"] == payload_digest(value), "selection payload digest")
    require(value["branchRef"] == REF and value["developmentRouteSHA256"] == route_hash, "selection route binding")
    require(value["authorityID"] == task["authority"]["authorityID"] and value["packageBinding"] == task["authority"], "selection authority binding")
    require(value["cardID"] == task["cardID"] and value["cardTitle"] == task["title"], "selected card")
    require(value["preS10FinalCredit"] is False and value["windowsStaticChecksAllowed"] is True, "selection credit")
    require(value["hostedDispatchUnlockCard"] == "V30-P00-C05", "route hydration card")
    fence = next((r for r in fences["cards"] if r["cardID"] == value["cardID"]), None)
    require(fence is not None and task["fence"] == fence, "selected fence")
    require(task["payloadDigest"] == payload_digest(task), "task payload digest")
    require(task["executionEpoch"] == "PRE_S10_PROVISIONAL" and task["preS10FinalCredit"] is False, "task epoch/credit")
    require(all(x is False for x in task["credit"].values()), "task credit")
    require(value["selector"] == task["selector"], "task/selector disagreement")
    if value["mode"] == "WINDOWS_STATIC":
        require(value["selector"] is None and value["hostedDispatchAllowed"] is False, "static dispatch")
        return
    require(value["mode"] == "PROVISIONAL_DEVELOPMENT" and value["hostedDispatchAllowed"] is True, "development mode")
    selector = value["selector"]
    require(type(selector) is dict and set(selector) == {"schemaVersion", "taskID", "tier", "runUISmoke", "unitTestSelectors", "uiTestSelectors", *FIELDS}, "nested selector fields")
    require(type(selector["schemaVersion"]) is int and selector["schemaVersion"] == 1, "nested version")
    require(selector["taskID"] == value["cardID"], "nested task")
    require(selector["tier"] in TIERS, "tier")
    require(all(type(selector[k]) is int for k in FIELDS), "integer watchdogs")
    require([selector[k] for k in FIELDS] == TIERS[selector["tier"]], "watchdog values")
    ui = selector["tier"] != "N8"
    require(selector["runUISmoke"] is ui, "tier/UI mismatch")
    for key, bundle, minimum in [("unitTestSelectors", "FieldEvidenceAppTests", 1),
                                  ("uiTestSelectors", "FieldEvidenceAppUITests", int(ui))]:
        items = selector[key]
        require(type(items) is list and all(type(x) is str for x in items), "selector list")
        require(len(items) >= minimum and len(set(items)) == len(items), "selector cardinality")
        if key == "uiTestSelectors":
            require(len(items) == int(ui), "bounded UI selector")
        classes = set()
        for entry in fence["allowedPaths"]:
            path = entry["path"]
            if path.startswith(bundle + "/") and path.endswith(".swift") and (ROOT / path).is_file():
                classes.update(re.findall(r"\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\s*:", (ROOT / path).read_text(encoding="utf-8")))
        for item in items:
            match = re.fullmatch(re.escape(bundle) + r"/([A-Za-z_][A-Za-z0-9_]*)", item)
            require(match is not None and match[1] in classes, "selector outside current fenced test class")


def validate(hosted=False, dispatch_ui=None):
    authority, fences, contract, route = map(read, [AUTHORITY, FENCES, CONTRACT, ROUTE])
    require(authority["authorityID"] == "ASSETROUNDS-V30-PRE-S10-20260902-R2" and authority["authorityContentDigest"] == "ab585279a32cb8e53b5656af6efb264a85ced24116ace3b1de9f56a14f19cec6", "external authority")
    require(contract["authorityID"] == authority["authorityID"] and contract["authorityContentDigest"] == authority["authorityContentDigest"], "contract authority")
    require(contract["finalCredit"] is False and contract["nativeDiagnosticsAreAcceptance"] is False, "contract credit")
    require(contract["selectorPath"] == SELECTION and contract["workflowPath"] == authority["ci"]["workflowPath"], "route paths")
    require(contract["repository"] == REPOSITORY and contract["branchRef"] == REF and contract["tiers"] == TIERS, "route identity or watchdogs")
    require(route == {"kind": "V30ProvisionalDevelopmentRouteSelectorV1", "authorityID": authority["authorityID"], "authorityContentDigest": authority["authorityContentDigest"], "contractPath": CONTRACT, "contractSHA256": sha((ROOT / CONTRACT).read_bytes()), "repository": REPOSITORY, "branchRef": REF, "workflowPath": ".github/workflows/ios-ci.yml", "selectorPath": SELECTION, "optionalDiagnostics": True, "finalCredit": False}, "development route seal")
    for item in contract["files"]:
        require(sha((ROOT / item["path"]).read_bytes()) == item["sha256"], "route file changed: " + item["path"])
    card5 = next(x for x in fences["cards"] if x["cardID"] == "V30-P00-C05")
    expected = {x["path"]: x for x in card5["allowedPaths"]}
    require({x["path"] for x in contract["frozenSourceBindings"]} == set(authority["ci"]["isolatedRouteWriterPaths"]) and len(contract["frozenSourceBindings"]) == 3, "frozen source set")
    require({x["path"] for x in contract["files"]} == set(authority["ci"]["isolatedRouteWriterPaths"]) | {"Scripts/build-smoke.sh", "Scripts/run-with-timeout.sh", "Scripts/ci-selection.json"} and len(contract["files"]) == 6, "route file set")
    for item in contract["frozenSourceBindings"]:
        fence = expected[item["path"]]
        require(item["blobOID"] == fence["expectedBBlobOID"] and item["sha256"] == fence["expectedBSHA256"], "frozen source binding")
        verify_adapter(item["path"], fence["expectedBSHA256"])
        if item["path"] in card5["s10SharedPaths"]:
            require(item["overlapTuple"] in card5["preAuthorizedOverlapTuples"] and item["overlapTuple"] in authority["pathFenceAuthority"]["s10SharedReconciliationTuples"], "shared path tuple")
        else:
            require(item["overlapTuple"] is None, "unexpected overlap tuple")
    task = json.loads((ROOT / (PREFIX + "execution/V30_CURRENT_TASK.md")).read_text(encoding="utf-8").split("```json", 1)[1].split("```", 1)[0])
    selection = read(SELECTION)
    validate_selection(selection, task, fences, sha((ROOT / ROUTE).read_bytes()))
    if hosted:
        require(selection["hostedDispatchAllowed"] is True, "hosted diagnostics disabled")
        require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY and os.environ.get("GITHUB_REF") == REF and os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "hosted repository/ref/event")
        head = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        require(re.fullmatch("[0-9a-f]{40}", os.environ.get("GITHUB_SHA", "")) and os.environ["GITHUB_SHA"] == head, "hosted exact head")
        require(dispatch_ui == str(selection["selector"]["runUISmoke"]).lower(), "dispatch UI disagreement")
        require(all(os.environ.get(key) == value for key, value in contract["environment"].items()), "hosted pinned environment")
    return {"result": "PASS", "cardID": selection["cardID"], "mode": selection["mode"], "nativeCredit": False, "finalCredit": False}


def self_test():
    validate()
    value = read(SELECTION)
    task = json.loads((ROOT / (PREFIX + "execution/V30_CURRENT_TASK.md")).read_text(encoding="utf-8").split("```json", 1)[1].split("```", 1)[0])
    fences = read(FENCES)
    route_hash = sha((ROOT / ROUTE).read_bytes())
    # Re-seal malformed vectors to ensure semantic checks, not only hashes, reject them.
    cases = {
        "wrong ref": lambda x: x.update(branchRef="refs/heads/main"),
        "final credit": lambda x: x.update(preS10FinalCredit=True),
        "wrong route": lambda x: x.update(developmentRouteSHA256="0" * 64),
        "wrong authority": lambda x: x.update(authorityID="unissued"),
        "unknown field": lambda x: x.update(acceptance=True),
        "wrong card": lambda x: x.update(cardID="V30-P05-C01"),
        "disabled hosted with selector": lambda x: x.update(hostedDispatchAllowed=False),
        "altered watchdog": lambda x: x["selector"].update(totalBudgetSeconds=9999),
        "integer boolean": lambda x: x["selector"].update(runUISmoke=0),
        "wrong nested task": lambda x: x["selector"].update(taskID="V30-P00-C04"),
        "broad unit suite": lambda x: x["selector"].update(unitTestSelectors=["FieldEvidenceAppTests"]),
        "unfenced class": lambda x: x["selector"].update(unitTestSelectors=["FieldEvidenceAppTests/UnissuedTests"]),
        "UI in N8": lambda x: x["selector"].update(uiTestSelectors=["FieldEvidenceAppUITests/UnissuedTests"]),
    }
    for name, mutate in cases.items():
        altered, context = copy.deepcopy(value), copy.deepcopy(task)
        mutate(altered)
        altered["payloadDigest"] = payload_digest(altered)
        context["selector"] = altered["selector"]
        context["payloadDigest"] = payload_digest(context)
        try:
            validate_selection(altered, context, fences, route_hash)
        except ValueError:
            continue
        raise ValueError("admitted malformed vector: " + name)
    contract = read(CONTRACT)
    workflow = ".github/workflows/ios-ci.yml"
    expected_sha = next(x["sha256"] for x in contract["frozenSourceBindings"] if x["path"] == workflow)
    source = (ROOT / workflow).read_text(encoding="utf-8")
    corruptions = {
        "changed Xcode": source.replace("Xcode_26.6.app", "Xcode_26.5.app"),
        "changed watchdog": source.replace('timeout-minutes: 90', 'timeout-minutes: 120'),
        "removed ref guard": source.replace('          test "$GITHUB_REF" = "refs/heads/phase/v30-globalization"\n', ''),
        "inherited selector read": source.replace(SELECTION, "Scripts/ci-selection.json"),
        "weakened artifact gate": source.replace("if-no-files-found: error", "if-no-files-found: warn"),
    }
    for name, source in corruptions.items():
        try:
            verify_adapter(workflow, expected_sha, source)
        except ValueError:
            continue
        raise ValueError("admitted adapter corruption: " + name)
    return {"result": "PASS", "rejectedCases": list(cases), "rejectedAdapterChanges": list(corruptions), "nativeCredit": False, "finalCredit": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--hosted", action="store_true")
    parser.add_argument("--dispatch-ui", choices=["true", "false"])
    args = parser.parse_args()
    try:
        require(not (args.self_test and args.hosted), "self-test cannot claim hosted verification")
        print(json.dumps(self_test() if args.self_test else validate(args.hosted, args.dispatch_ui), indent=2))
    except (ValueError, KeyError, IndexError, TypeError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit("FAIL: " + str(error))
