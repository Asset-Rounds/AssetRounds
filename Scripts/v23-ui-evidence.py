#!/usr/bin/env python3
"""Closed RUI1 selection, original attachment verification and human review package.

No generated package grants acceptance or human-review credit. The raw XCResult
export stays intact; verification joins its method ownership to the frozen state
catalogue and each test-authored image digest before presenting original bytes.
"""
import argparse
import hashlib
import html
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys

ROUTE = "v23-ui-batch-rui1"
PATH = "Scripts/v23-ui-batch.json"
CATALOGUE = "docs/design/v23/integration/phase1-critical-states.json"
UI_SOURCE = "FieldEvidenceAppUITests/V23Phase1CriticalStatesUITests.swift"
UNIT_SOURCE = "FieldEvidenceAppTests/V23PhaseGateTests.swift"
SUPPORT_SOURCE = "FieldEvidenceAppTests/V23ProductionFourRootShellTests.swift"
PROTOCOL_PATHS = ("Scripts/v23-ui-evidence.py", "Scripts/v23-ui-smoke.sh", PATH, CATALOGUE,
                  UI_SOURCE, UNIT_SOURCE, SUPPORT_SOURCE)
SCHEMA = "v23-ui-batch.v1"
UI_CLASS = "V23Phase1CriticalStatesUITests"
METHODS = ("test1MigratedS10StoreOpensFourTabShell", "test2SignReportAndApprovalResponseInShell",
           "test3SettingsAppLockAndCover")
UI = tuple("FieldEvidenceAppUITests/" + UI_CLASS + "/" + name for name in METHODS)
UNITS = tuple("FieldEvidenceAppTests/V23PhaseGateTests/" + name for name in (
    "testShippingGateEnablesNoGatedFeature", "testAllFeaturesGateEnablesEveryGatedFeature",
    "testEveryGatedFeatureBelongsToAPhaseLaterThanPhaseOne",
    "testBuiltInfoPlistClaimsNoEnvelopeDocumentTypeWhileEnvelopeOpenIsGated",
    "testBuiltCameraPurposeUsesTheAcceptedS10Wording", "testSystemDiscoveryIntentsAreUndiscoverableWhileGated",
    "testShippingShellShowsPhaseOneTodayAndCompletedWorkWithoutLaterPhaseSurfaces",
    "testAllFeaturesShellStillReachesEveryGatedSurfaceForTests"))
BUDGETS = (300, 1800, 900, 900, 3900)
BUDGET_KEYS = ("setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds",
               "uiTimeoutSeconds", "totalBudgetSeconds")
BINDING_KEYS = {"path", "sha256", "cataloguePath", "catalogueSHA256", "uiSourceSHA256",
                "unitSourceSHA256", "schema", "developmentOnly", "acceptance", "releaseReady"}
PNG = b"\x89PNG\r\n\x1a\n"
UUID = r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}"


def require(value, message):
    if not value:
        raise ValueError("invalid RUI1 evidence: " + message)


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def pairs(items):
    value = {}
    for key, item in items:
        require(key not in value, "duplicate JSON key")
        value[key] = item
    return value


def regular(path, limit=16 * 1024 * 1024):
    require(path.is_file() and not path.is_symlink() and 0 < path.stat().st_size <= limit,
            "bounded regular file: " + str(path))
    return path.read_bytes()


def read(path, limit=16 * 1024 * 1024):
    return json.loads(regular(path, limit), object_pairs_hook=pairs)


def load(root, relative, name):
    path = root / relative
    regular(path)
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def protocol_sources(root):
    return {path: sha(regular(root / path)) for path in PROTOCOL_PATHS}


def selection(root):
    raw = regular(root / PATH, 32768)
    value = json.loads(raw, object_pairs_hook=pairs)
    require(set(value) == {"schema", "question", "cataloguePath", "catalogueSHA256",
                           "unitTestSelectors", "uiTestSelectors"}, "manifest keys")
    require(value["schema"] == SCHEMA and value["cataloguePath"] == CATALOGUE,
            "manifest identity")
    require(isinstance(value["question"], str) and 1 <= len(value["question"]) <= 500
            and not re.search(r"[\x00-\x1f\x7f]", value["question"]), "manifest question")
    require(value["unitTestSelectors"] == list(UNITS) and value["uiTestSelectors"] == list(UI),
            "exact ordered methods")
    cat_raw = regular(root / CATALOGUE, 128 * 1024)
    require(value["catalogueSHA256"] == sha(cat_raw), "catalogue digest")
    catalogue = json.loads(cat_raw, object_pairs_hook=pairs)
    require(catalogue["schema"] == "V23Phase1CriticalStatesV1" and catalogue["schemaVersion"] == 1
            and catalogue["humanReviewRequired"] is True and catalogue["acceptanceCredit"] is False,
            "catalogue authority")
    require(catalogue["testFile"] == UI_SOURCE and catalogue["testClass"] == UI_CLASS
            and [m["name"] for m in catalogue["methods"]] == list(METHODS), "catalogue methods")
    states = catalogue["states"]
    require(len(states) == 27 and [s["order"] for s in states] == list(range(1, 28))
            and len({s["id"] for s in states}) == 27, "catalogue state census")
    for method, count in zip(METHODS, (7, 12, 8)):
        owned = [s for s in states if s["method"] == method]
        require(len(owned) == count and [s["orderInMethod"] for s in owned] == list(range(1, count + 1)),
                "catalogue method state order")
    generator = load(root, "Scripts/v23-selection-generator.py", "rui_generator")
    sources = {}
    for relative in (UNIT_SOURCE, UI_SOURCE, SUPPORT_SOURCE):
        code = generator._active_swift(generator._mask_swift_noncode(regular(root / relative).decode()))
        depths = generator._brace_depths(code)
        require(not any(depths[m.start()] == 0 for m in re.finditer(
            r"\b(?:class|struct|enum|protocol|typealias)\s+(?:XCTest|XCTestCase)\b", code)),
            "shadowed XCTest authority")
        sources[relative] = code
    for relative, class_name, expected_base, selectors in (
            (UNIT_SOURCE, "V23PhaseGateTests", "V23ProductionFourRootShellTestSupport", UNITS),
            (UI_SOURCE, UI_CLASS, "XCTestCase", UI)):
        code = sources[relative]
        names = [selector.split("/")[2] for selector in selectors]
        base, bodies = generator._class_bodies(code, class_name, names)
        require(base == expected_base, "closed XCTest inheritance")
        generator._verify_methods(bodies, class_name, names)
    support = sources[SUPPORT_SOURCE]
    base, _ = generator._class_bodies(support, "V23ProductionFourRootShellTestSupport")
    require(base == "XCTestCase", "unit support XCTest base")
    binding = {"path": PATH, "schema": SCHEMA, "sha256": sha(raw),
               "cataloguePath": CATALOGUE, "catalogueSHA256": sha(cat_raw),
               "uiSourceSHA256": sha(regular(root / UI_SOURCE)),
               "unitSourceSHA256": sha(regular(root / UNIT_SOURCE)),
               "developmentOnly": True, "acceptance": False, "releaseReady": False}
    return {"schemaVersion": 1, "taskID": "V23-INTEGRATION-20260910", "tier": "RUI1",
            "runUISmoke": True, **dict(zip(BUDGET_KEYS, BUDGETS)),
            "unitTestSelectors": list(UNITS), "uiTestSelectors": list(UI), "uiBatch": binding}


def validate_binding(value):
    require(type(value) is dict and set(value) == BINDING_KEYS, "selection binding keys")
    require(value["path"] == PATH and value["schema"] == SCHEMA and value["cataloguePath"] == CATALOGUE,
            "selection binding identity")
    require(all(type(value[k]) is str and re.fullmatch(r"[0-9A-F]{64}", value[k])
                for k in ("sha256", "catalogueSHA256", "uiSourceSHA256", "unitSourceSHA256")), "binding digests")
    require(value["developmentOnly"] is True and value["acceptance"] is False
            and value["releaseReady"] is False, "non-accepting classification")


def command(artifact, environment):
    e = environment
    require(e.get("CI_DESTINATION") == "platform=iOS Simulator,id=" + e.get("CI_SIMULATOR_UDID", ""),
            "destination")
    require((e.get("PROJECT_PATH"), e.get("SCHEME"), e.get("CONFIGURATION"), e.get("CODE_SIGNING_ALLOWED"))
            == ("FieldEvidenceApp.xcodeproj", "FieldEvidenceApp", "Debug", "NO"), "configuration")
    return ["xcodebuild", "-project", e["PROJECT_PATH"], "-scheme", e["SCHEME"],
            "-configuration", "Debug", "-destination", e["CI_DESTINATION"],
            "-derivedDataPath", str(PurePosixPath(e["RUNNER_TEMP"]) / "FieldEvidenceDerivedData"),
            "-resultBundlePath", str(artifact / "UISmoke.xcresult"),
            "-parallel-testing-enabled", "NO", "-test-iterations", "1",
            *["-only-testing:" + s for s in UI], "CODE_SIGNING_ALLOWED=NO", "test-without-building"]


def artifact_leaf(root, name):
    require(type(name) is str and re.fullmatch(r"[A-Za-z0-9_. -]{1,240}", name)
            and name not in (".", ".."), "safe attachment basename")
    path = root / name
    require(path.resolve().parent == root.resolve(), "attachment confinement")
    return path


def attachments(root, artifact, admission, selected):
    require(selected == selection(root), "selected manifest/source binding")
    require(admission.get("selectionID") == ROUTE
            and admission.get("selectionSHA256") == sha(canonical(selected)), "admission selection")
    catalogue = read(root / CATALOGUE)
    export = artifact / "rui1-original-attachments"
    require(export.is_dir() and not export.is_symlink(), "original attachment directory")
    manifest = read(export / "manifest.json")
    require(type(manifest) is list and len(manifest) == 3, "three original method attachment groups")
    expected = {(s["method"], "P1 state " + s["id"]): (s, "png") for s in catalogue["states"]}
    expected.update({(s["method"], "P1 ax " + s["id"]): (s, "json") for s in catalogue["states"]})
    found, files, methods = {}, {"manifest.json"}, set()
    for group in manifest:
        require(type(group) is dict, "attachment group")
        identifier = group.get("testIdentifier", "").removesuffix("()")
        require(identifier in [UI_CLASS + "/" + m for m in METHODS] and identifier not in methods,
                "exact unique method ownership")
        methods.add(identifier)
        method = identifier.split("/")[1]
        require(type(group.get("attachments")) is list, "method attachments")
        for entry in group["attachments"]:
            require(type(entry) is dict and entry.get("isAssociatedWithFailure") is False,
                    "non-failure original attachment")
            name = entry.get("suggestedHumanReadableName")
            require(type(name) is str, "attachment name")
            matches = [(key, pair) for key, pair in expected.items() if key[0] == method
                       and re.fullmatch(re.escape(key[1]) + r"(?:_\d+_" + UUID + r"\." + pair[1] + ")?", name)]
            require(len(matches) == 1, "catalogue attachment ownership/name")
            key, (state, extension) = matches[0]
            require(key not in found, "duplicate state/audit")
            filename = entry.get("exportedFileName")
            path = artifact_leaf(export, filename)
            require(filename.endswith("." + extension) and filename not in files, "unique attachment file")
            files.add(filename)
            found[key] = (path, regular(path))
    require(set(found) == set(expected), "complete state/audit census")
    require({p.name for p in export.iterdir()} == files, "exact exported file census")
    rows = []
    for state in catalogue["states"]:
        method, state_id = state["method"], state["id"]
        png_path, png = found[(method, "P1 state " + state_id)]
        audit_path, raw = found[(method, "P1 ax " + state_id)]
        audit = json.loads(raw, object_pairs_hook=pairs)
        require(type(audit) is dict and set(audit) == {"schemaVersion", "stateID", "testName",
                "ordinalInMethod", "pngSHA256", "pngByteCount", "auditTypes", "issuesFailTest",
                "humanReviewRequired", "issueCount", "issues", "auditError", "applicationFrame"}, "audit keys")
        names = {"-[FieldEvidenceAppUITests." + UI_CLASS + " " + method + "]",
                 "-[" + UI_CLASS + " " + method + "]"}
        require(audit["schemaVersion"] == 1 and audit["stateID"] == state_id and audit["testName"] in names
                and type(audit["ordinalInMethod"]) is int and audit["ordinalInMethod"] == state["orderInMethod"],
                "audit state/method/order")
        require(png.startswith(PNG) and len(png) > 8 and audit["pngSHA256"] == sha(png).lower()
                and type(audit["pngByteCount"]) is int and audit["pngByteCount"] == len(png), "original PNG binding")
        require(audit["auditTypes"] == ["contrast", "dynamicType", "textClipped"]
                and audit["issuesFailTest"] is True and audit["humanReviewRequired"] is True
                and type(audit["issueCount"]) is int and audit["issueCount"] == 0
                and audit["issues"] == [] and audit["auditError"] is None, "strict completed zero-issue audit")
        rows.append({"stateID": state_id, "method": method, "order": state["order"],
                     "image": str(png_path.relative_to(artifact)), "imageSHA256": sha(png),
                     "audit": str(audit_path.relative_to(artifact)), "auditSHA256": sha(raw)})
    return rows


def original_results(artifact):
    """Bind every raw result member before upload; recheck the same inventory after extraction."""
    def scan_error(error):
        raise error

    bundles, total, count = {}, 0, 0
    for name in ("Build.xcresult", "UnitTests.xcresult", "UISmoke.xcresult"):
        bundle = artifact / name
        require(bundle.is_dir() and not bundle.is_symlink(), "raw original result bundle: " + name)
        regular(bundle / "Info.plist")
        files, directories = [], []
        for current, dirs, names in os.walk(bundle, followlinks=False, onerror=scan_error):
            dirs.sort()
            for leaf in dirs + sorted(names):
                path = Path(current) / leaf
                info = path.lstat()
                require(not path.is_symlink(), "raw result symlink")
                relative = path.relative_to(bundle).as_posix()
                count += 1
                require(count <= 100_000, "bounded raw result census")
                if stat.S_ISDIR(info.st_mode):
                    directories.append(relative)
                    continue
                require(stat.S_ISREG(info.st_mode), "regular raw result member")
                total += info.st_size
                require(total <= 4 * 1024**3, "bounded raw result bytes")
                digest = hashlib.sha256()
                with path.open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(block)
                files.append({"path": relative, "bytes": info.st_size, "sha256": digest.hexdigest().upper()})
        require(any(item["path"] != "Info.plist" and item["bytes"] > 0 for item in files),
                "raw result payload missing")
        bundles[name] = {"directories": sorted(directories), "files": sorted(files, key=lambda x: x["path"])}
    return bundles


def retained_environment(argv):
    require(type(argv) is list and len(argv) == 22 and all(type(x) is str for x in argv),
            "closed command argument census")
    derived, result = PurePosixPath(argv[10]), PurePosixPath(argv[12])
    require(re.fullmatch(r"platform=iOS Simulator,id=" + UUID, argv[8])
            and derived.is_absolute() and result.is_absolute()
            and ".." not in derived.parts and ".." not in result.parts
            and result.name == "UISmoke.xcresult", "original runner command paths")
    environment = {"PROJECT_PATH": "FieldEvidenceApp.xcodeproj", "SCHEME": "FieldEvidenceApp",
                   "CONFIGURATION": "Debug", "CODE_SIGNING_ALLOWED": "NO", "CI_DESTINATION": argv[8],
                   "CI_SIMULATOR_UDID": argv[8].removeprefix("platform=iOS Simulator,id="),
                   "RUNNER_TEMP": str(derived.parent), "CI_ARTIFACT_DIR": str(result.parent)}
    require(argv == command(result.parent, environment), "exact retained no-rebuild UI command")
    environment.update(CI_NATIVE_CREATED_SIMULATOR_UDID=environment["CI_SIMULATOR_UDID"],
                       NATIVE_PRIOR_JOB_STATUS="success")
    return environment, result.parent


def verify(root, artifact, admission, selected, native, environment=None, *, command_artifact=None):
    require(admission.get("rui1ProtocolSources") == protocol_sources(root), "RUI1 admitted source closure")
    rows = attachments(root, artifact, admission, selected)
    actual = native.executed_methods(read(artifact / "ui-test-results.json"), list(UI),
                                    "FieldEvidenceAppUITests", "UI test bundle")
    receipt = read(artifact / "rui1-command.json")
    require(set(receipt) == {"schema", "head", "runID", "runAttempt", "admissionSHA256", "argv",
                            "runnerEnvironment", "acceptance", "releaseReady"}, "command receipt keys")
    require(receipt["schema"] == "v23-rui1-command.v1"
            and all(receipt[k] == admission[k] for k in ("head", "runID", "runAttempt"))
            and receipt["admissionSHA256"] == sha(native.canonical(admission))
            and receipt["runnerEnvironment"] == {"TEST_RUNNER_V23_P1_AX_AUDIT_STRICT": "1"}
            and receipt["acceptance"] is False and receipt["releaseReady"] is False, "command binding")
    argv = receipt["argv"]
    retained_environment(argv)
    if environment is not None:
        require(receipt["argv"] == command(artifact if command_artifact is None else command_artifact, environment),
                "exact no-rebuild UI command")
    final = regular(artifact / "ui-final.png")
    require(final == regular(artifact / rows[-1]["image"]), "explicit last catalogue state alias")
    return {"schema": "v23-rui1-review.v1", "head": admission["head"], "runID": admission["runID"],
            "runAttempt": admission["runAttempt"], "selectionSHA256": admission["selectionSHA256"],
            "catalogueSHA256": selected["uiBatch"]["catalogueSHA256"], "uiMethods": actual,
            "attachmentManifestSHA256": sha(regular(artifact / "rui1-original-attachments/manifest.json")),
            "commandSHA256": sha(regular(artifact / "rui1-command.json")),
            "originalResults": original_results(artifact),
            "states": rows, "strictAccessibility": True, "humanReviewRequired": True,
            "humanReviewCompleted": False, "providerQualification": False,
            "acceptance": False, "releaseReady": False}


def review_page(root, artifact, proof, prefix=""):
    catalogue = read(root / CATALOGUE)
    parts = ['<!doctype html><meta charset="utf-8"><title>Phase 1 owner review</title>',
             '<h1>Phase 1 — owner review required</h1><p>No human approval or acceptance is recorded.</p>',
             '<p>Head ' + html.escape(proof["head"]) + ' · original run ' + html.escape(proof["runID"]) + '</p>']
    for state, row in zip(catalogue["states"], proof["states"]):
        parts += ['<section><h2>' + html.escape(state["id"] + ' — ' + state["title"]) + '</h2>',
                  '<p>' + html.escape(state["expectedBehavior"]) + '</p>',
                  '<img style="max-width:480px;width:100%" src="' + html.escape(prefix + row["image"], quote=True) + '" alt="' + html.escape(state["title"], quote=True) + '">',
                  '<ul>' + ''.join('<li>☐ ' + html.escape(x) + '</li>' for x in state["reviewChecks"]) + '</ul>',
                  '<p><a href="' + html.escape(prefix + row["audit"], quote=True) + '">Original accessibility audit</a> · PNG SHA-256 ' + row["imageSHA256"] + '</p></section>']
    return '\n'.join(parts).encode()


def write_new(path, data):
    with path.open("xb") as output:
        output.write(data)


def collected_review(root, artifact, native, expected_head, expected_run):
    admission = read(artifact / "native-admission.json")
    selected = read(artifact / "ci-selection.selected.json")
    require(all(admission.get(k) == v for k, v in native.source_binding(root).items()),
            "committed native protocol/source binding")
    proof = verify(root, artifact, admission, selected, native)
    require(proof["head"] == expected_head and proof["runID"] == expected_run
            and proof["runAttempt"] == "1", "collector original identity")
    require(read(artifact / "rui1-review.json") == proof, "worker review proof")
    require(regular(artifact / "rui1-review.html") == review_page(root, artifact, proof), "review presentation")
    checkpoint = read(artifact / "native-checkpoint.json")
    environment, original_artifact = retained_environment(read(artifact / "rui1-command.json")["argv"])
    verified = native.verify_checkpoint(root, artifact, admission, selected, environment,
                                        retained_command_artifact=original_artifact)
    require(checkpoint == verified, "complete retained native checkpoint binding")
    require(admission.get("runnerProvider") == "github" and admission.get("runnerLabel") == "macos-26"
            and all(checkpoint.get(k) is False for k in
                    ("acceptance", "releaseReady", "providerQualification", "humanReviewComplete")),
            "pinned non-accepting checkpoint")
    return proof


def run(root, artifact):
    native = load(root, "Scripts/v23-native-ci.py", "rui_native")
    selected, record = native.selected_input(root, os.environ)
    require(record["selectionID"] == ROUTE and selected == selection(root), "UI route selection")
    require(os.environ.get("CI_SELECTION_PATH") == str(artifact / "ci-selection.selected.json")
            and read(artifact / "ci-selection.selected.json") == selected, "worker selected file")
    admission = read(artifact / "native-admission.json")
    require(admission["head"] == os.environ.get("GITHUB_SHA") and admission["runAttempt"] == "1",
            "UI original head")
    args = command(artifact, os.environ)
    for name in ("UISmoke.xcresult", "rui1-original-attachments", "rui1-command.json", "ui-final.png",
                 "ui-test-results.json", "rui1-review.json", "rui1-review.html"):
        require(not os.path.lexists(artifact / name), "fresh UI evidence: " + name)
    runner = {"TEST_RUNNER_V23_P1_AX_AUDIT_STRICT": "1"}
    require(not any(k.startswith("TEST_RUNNER_V23_P1_") or k == "V23_P1_AX_AUDIT_STRICT"
                    for k in os.environ), "caller UI audit overrides")
    write_new(artifact / "rui1-command.json", canonical({"schema": "v23-rui1-command.v1",
        **{k: admission[k] for k in ("head", "runID", "runAttempt")},
        "admissionSHA256": sha(native.canonical(admission)), "argv": args, "runnerEnvironment": runner,
        "acceptance": False, "releaseReady": False}))
    status = subprocess.run(args, env=dict(os.environ, **runner)).returncode
    result = artifact / "UISmoke.xcresult"
    # Retain failed originals too; extraction never changes the XCTest exit status.
    if result.is_dir():
        exported = subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                                   "--output-path", str(artifact / "rui1-original-attachments")]).returncode
        with (artifact / "ui-test-results.json").open("xb") as stream:
            outcomes = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path",
                                       str(result), "--compact"], stdout=stream).returncode
    else:
        exported = outcomes = 1
    if status:
        raise SystemExit(status)
    require(exported == 0 and outcomes == 0, "original UI export failed")
    rows = attachments(root, artifact, admission, selected)
    write_new(artifact / "ui-final.png", regular(artifact / rows[-1]["image"]))
    proof = verify(root, artifact, admission, selected, native, os.environ)
    write_new(artifact / "rui1-review.json", canonical(proof))
    write_new(artifact / "rui1-review.html", review_page(root, artifact, proof))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "collect"))
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--artifact", type=Path, default=os.environ.get("CI_ARTIFACT_DIR"))
    parser.add_argument("--expected-head")
    parser.add_argument("--expected-run")
    parser.add_argument("--review-output", type=Path)
    options = parser.parse_args()
    if options.action == "run":
        run(options.root.resolve(), options.artifact)
    else:
        root, artifact = options.root.resolve(), options.artifact
        native = load(root, "Scripts/v23-native-ci.py", "rui_native")
        proof = collected_review(root, artifact, native, options.expected_head, options.expected_run)
        if options.review_output is not None:
            require(artifact.resolve() == options.review_output.parent.resolve() / "artifact",
                    "review output relative original directory")
            write_new(options.review_output, review_page(root, artifact, proof, "artifact/"))
        print(json.dumps(proof, sort_keys=True))
