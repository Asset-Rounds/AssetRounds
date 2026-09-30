#!/usr/bin/env python3
"""Fail-closed static verifier for V23-P04-C03 tooling artifacts."""
from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p04_c03_contracts as contracts


def _run(arguments: list[str]) -> str:
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, check=True, env=env).stdout


def _cache_paths() -> list[str]:
    values: list[str] = []
    for path in (ROOT / "Scripts/v23").rglob("*"):
        if path.name == "__pycache__" or path.suffix == ".pyc":
            values.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    return sorted(values)


def _fresh_outputs() -> dict[str, bytes]:
    code = (
        "import base64,json,sys;sys.dont_write_bytecode=True;"
        "sys.path.insert(0,'Scripts/v23');import p04_c03_contracts as c;"
        "print(json.dumps({k:base64.b64encode(v).decode('ascii') for k,v in c.all_outputs(c.Path('.')).items()},sort_keys=True))"
    )
    raw = _run([sys.executable, "-B", "-c", code])
    return {key: base64.b64decode(value) for key, value in json.loads(raw).items()}


def _expected_manifest_rows(outputs: dict[str, bytes]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in contracts.MANIFEST_INPUT_PATHS:
        if path in outputs:
            data = outputs[path]
            rows.append({"path": path, "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest(), "status": "SEALED_TOOLING"})
        elif (ROOT / path).is_file():
            data = contracts.canonical_file_bytes(ROOT / path)
            rows.append({"path": path, "byteCount": len(data), "sha256": hashlib.sha256(data).hexdigest(), "status": "SEALED_TOOLING" if path in contracts.TOOLING_EDIT_PATHS else "SEALED_SOURCE"})
        else:
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
    return rows


def _verify_json_outputs(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    expected = set(contracts.OUTPUT_PATHS) | {contracts.MANIFEST_PATH}
    if set(outputs) != expected:
        failures.append("generated output set differs")
    for path in sorted(expected):
        try:
            json.loads(outputs[path].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
            failures.append(path + ":invalid JSON:" + str(exc))
    return failures


def _verify_manifest(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    try:
        manifest = json.loads(outputs[contracts.MANIFEST_PATH].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        expected_rows = _expected_manifest_rows(outputs)
        if manifest.get("files") != expected_rows:
            failures.append("manifest byte inventory differs")
        for key, expected in (("pathFence", list(contracts.PATH_FENCE)), ("existingPaths", list(contracts.EXISTING_PATHS)), ("newPaths", list(contracts.NEW_PATHS)), ("toolingEditPaths", list(contracts.TOOLING_EDIT_PATHS))):
            if manifest.get(key) != expected:
                failures.append("manifest " + key + " differs")
        for key, expected in (("existingPathCount", 288), ("newPathCount", 15), ("fencePathCount", 303), ("manifestInputCount", 302)):
            if manifest.get(key) != expected:
                failures.append("manifest " + key + " differs")
        if manifest.get("authority") != contracts.authority():
            failures.append("manifest authority differs")
        if manifest.get("finalHashesSealed") is not contracts.FINAL_HASHES_SEALED:
            failures.append("manifest finalHashesSealed differs")
        disposition = "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if contracts.FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"
        if manifest.get("hashDisposition") != disposition:
            failures.append("manifest hash disposition differs")
        if any(row.get("path") == contracts.MANIFEST_PATH for row in manifest.get("files", [])):
            failures.append("manifest self included")
        if contracts.FINAL_HASHES_SEALED:
            if manifest.get("artifactSetDigest") != hashlib.sha256(contracts.canonical(expected_rows)).hexdigest():
                failures.append("manifest artifact set digest differs")
            unsigned = dict(manifest)
            unsigned.pop("artifactDigest", None)
            if manifest.get("artifactDigest") != hashlib.sha256(contracts.pretty(unsigned)).hexdigest():
                failures.append("manifest artifact digest differs")
            if any(row.get("status") not in ("SEALED_SOURCE", "SEALED_TOOLING") or row.get("sha256") is None or row.get("byteCount") is None for row in manifest.get("files", [])):
                failures.append("sealed manifest contains pending row")
        elif manifest.get("artifactSetDigest") is not None or manifest.get("artifactDigest") is not None:
            failures.append("provisional manifest carries a sealed digest")
    except (KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        failures.append("manifest parse/validation:" + str(exc))
    return failures


def _verify_semantics(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    try:
        contract = json.loads(outputs[contracts.CONTRACT_PATH].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        evidence = json.loads(outputs[contracts.EVIDENCE_PATH].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        brand = json.loads(outputs[contracts.BRAND_PATH].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        schema = json.loads(outputs[contracts.SCHEMA_PATH].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
        expected_flags = {name: False for name in contracts.FLAGS}
        expected_lifecycle = dict(contracts.C03_LIFECYCLE)
        expected_persistence = contracts.PERSISTENCE
        schema_properties = schema.get("properties", {})
        for key, expected in (("playbookIDs", list(contracts.PLAYBOOK_IDS)), ("playbookCount", 7), ("eighthPlaybookForbidden", True), ("selectors", list(contracts.observed_selectors(ROOT))), ("visibleConditionClaim", "VISIBLE_CONDITIONS_ONLY"), ("comparisonIsProof", False), ("diagnosisClaimed", False), ("electricalCertification", False), ("safetyCertification", False), ("lifecycle", expected_lifecycle), ("persistence", expected_persistence), ("statusFlags", expected_flags)):
            if schema_properties.get(key, {}).get("const") != expected:
                failures.append("schema semantic field differs:" + key)
        if schema.get("additionalProperties") is not False:
            failures.append("schema must reject additional properties")
        semantics = contract.get("semantics", {})
        required_semantics = {
            "playbookIDs": list(contracts.PLAYBOOK_IDS), "playbookCount": 7,
            "eighthPlaybookForbidden": True, "visibleConditionClaim": "VISIBLE_CONDITIONS_ONLY",
            "comparisonIsProof": False, "diagnosisClaimed": False,
            "electricalCertification": False, "safetyCertification": False,
            "lifecycle": expected_lifecycle, "persistence": expected_persistence,
            "typedPose": "C37_SHARED_POSE_EDITOR_AXIS_FRAME_SOURCE_UNCERTAINTY_NOT_OBSERVED",
            "checkpointing": "C36_UNIVERSAL_CHECKPOINT_KILL_RESUME",
            "ui": "POST_S10_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT",
            "noNetworkCloudTelemetryAI": True, "noSecondEngineOrWriter": True,
        }
        for key, expected in required_semantics.items():
            if semantics.get(key) != expected:
                failures.append("contract semantic field differs:" + key)
        forbidden = set(semantics.get("forbiddenCapabilities", []))
        required_forbidden = {"DIAGNOSIS", "ELECTRICAL_CERTIFICATION", "SAFETY_CERTIFICATION", "NETWORK", "CLOUD", "TELEMETRY", "REMOTE_SYNC", "SECOND_ENGINE", "SECOND_WRITER"}
        if not required_forbidden <= forbidden:
            failures.append("contract forbidden capability closure differs")
        selectors = list(contracts.observed_selectors(ROOT))
        if len(selectors) != 5 or [selector[selector.index("C03") + 3:selector.index("C03") + 6] for selector in selectors] != list(contracts.SELECTOR_SUFFIXES):
            failures.append("source selector inventory differs")
        for value in (contract, evidence, brand):
            if value.get("statusFlags") != expected_flags or value.get("nativeCompileRan") is True or value.get("hostedDispatchEnabled") is True:
                failures.append("activation/native/hosted flags differ")
        for value in (evidence, brand):
            if value.get("uiAdoptionSkipped") is not True:
                failures.append("UI post-S10 adoption must remain skipped")
        if evidence.get("testSelectors") != selectors or evidence.get("evidenceIDs") != list(contracts.EVIDENCE_IDS):
            failures.append("evidence selector identifiers differ")
        if evidence.get("playbookIDs") != list(contracts.PLAYBOOK_IDS) or evidence.get("playbookCount") != 7 or evidence.get("eighthPlaybookForbidden") is not True:
            failures.append("evidence seven-playbook closure differs")
        if evidence.get("lifecycle") != expected_lifecycle or evidence.get("persistence") != expected_persistence:
            failures.append("evidence lifecycle/persistence closure differs")
        if brand.get("uiTestDisposition") != "EXPLICIT_POST_S10_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_AUTHORITY":
            failures.append("brand UI deferral differs")
        if brand.get("visibleConditionClaimsOnly") is not True or brand.get("networkOrTelemetryFlow") is not False:
            failures.append("brand visible-only/network closure differs")
    except (KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        failures.append("semantic artifact parse/validation:" + str(exc))
    return failures


def _verify_artifact_digests(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    for path in (contracts.CONTRACT_PATH, contracts.EVIDENCE_PATH, contracts.BRAND_PATH, contracts.MANIFEST_PATH):
        try:
            value = json.loads(outputs[path].decode("utf-8"), object_pairs_hook=contracts._strict_pairs)
            unsigned = dict(value)
            recorded = unsigned.pop("artifactDigest", None)
            expected = hashlib.sha256(contracts.pretty(unsigned)).hexdigest() if contracts.FINAL_HASHES_SEALED else None
            if recorded != expected:
                failures.append(path + ":artifact digest differs")
        except (KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
            failures.append(path + ":artifact digest parse:" + str(exc))
    return failures


def _hygiene_failures(changed: tuple[str, ...]) -> list[str]:
    failures: list[str] = []
    for relative in changed:
        target = ROOT / relative
        if not target.is_file():
            continue
        data = target.read_bytes()
        if data.startswith(b"\xef\xbb\xbf"):
            failures.append("UTF8 BOM:" + relative)
        if relative in contracts.TOOLING_EDIT_PATHS and data and not data.endswith(b"\n"):
            failures.append("missing final newline:" + relative)
    return failures


def verify(complete: bool = False) -> dict[str, Any]:
    failures: list[str] = []
    try:
        contracts.assert_scaffold(ROOT)
    except Exception as exc:
        failures.append("scaffold:" + str(exc))
    for path in contracts.SCRIPT_PATHS:
        target = ROOT / path
        if not target.is_file():
            failures.append("missing script:" + path)
            continue
        try:
            ast.parse(target.read_text(encoding="utf-8"), filename=path)
        except SyntaxError as exc:
            failures.append("AST:" + path + ":" + str(exc))
    status = contracts.source_status(ROOT)
    selectors = tuple(status.get("selectors", ()))
    if complete:
        try:
            selectors = contracts.assert_source_contracts(ROOT)
        except Exception as exc:
            failures.append("source:" + str(exc))
    outputs: dict[str, bytes] = {}
    try:
        outputs = contracts.all_outputs(ROOT)
        stale = [path for path, data in outputs.items() if not (ROOT / path).is_file() or (ROOT / path).read_bytes() != data]
        if stale:
            failures.append("stale generated outputs:" + ",".join(stale))
        failures.extend(_verify_json_outputs(outputs))
        failures.extend(_verify_manifest(outputs))
        failures.extend(_verify_semantics(outputs))
        failures.extend(_verify_artifact_digests(outputs))
    except Exception as exc:
        failures.append("outputs:" + str(exc))
    try:
        fresh = _fresh_outputs()
        if outputs and fresh != outputs:
            failures.append("fresh-process output differs")
    except Exception as exc:
        failures.append("fresh-process:" + str(exc))
    changed = contracts.observed_changed_paths(ROOT)
    changed_set = set(changed)
    fence_set = set(contracts.PATH_FENCE)
    new_set = set(contracts.NEW_PATHS)
    fenced_changed = sorted(changed_set & fence_set)
    unchanged_existing = sorted(set(contracts.EXISTING_PATHS) - changed_set)
    missing_new = sorted(new_set - changed_set)
    unowned = sorted(changed_set - fence_set)
    if unowned:
        failures.append("unowned changed paths:" + ",".join(unowned))
    if complete and missing_new:
        failures.append("incomplete C03 fence; missing changed new paths:" + ",".join(missing_new))
    if complete and not contracts.FINAL_HASHES_SEALED:
        failures.append("complete verification requires final hashes sealed")
    failures.extend(_hygiene_failures(changed))
    cache = _cache_paths()
    if cache:
        failures.append("bytecode/cache artifacts present")
    if contracts.FLAGS != {name: False for name in contracts.FLAGS}:
        failures.append("activation/native/hosted/adoption/acceptance/release flags are not all false")
    return {
        "cardID": contracts.CARD, "complete": complete,
        "result": "PASS_STATIC_SEALED" if not failures and contracts.FINAL_HASHES_SEALED else ("PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC"),
        "failures": failures, "sourceReady": bool(status["hydrated"]), "sourceMissing": status["missingPaths"],
        "selectors": list(selectors), "existingPathCount": len(contracts.EXISTING_PATHS), "newPathCount": len(contracts.NEW_PATHS),
        "fencePathCount": len(contracts.PATH_FENCE), "changedPathCount": len(changed), "fencedChangedPathCount": len(fenced_changed),
        "newChangedPathCount": len(new_set & changed_set), "unchangedExistingPathCount": len(unchanged_existing),
        "missingNewPathCount": len(missing_new), "unownedChangedPathCount": len(unowned),
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT, "manifestInputCount": len(contracts.MANIFEST_INPUT_PATHS),
        "manifestSelfExcluded": True, "finalHashesSealed": contracts.FINAL_HASHES_SEALED,
        "flagsAllFalse": all(value is False for value in contracts.FLAGS.values()), "cachePaths": cache,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = verify(args.complete)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2))
    else:
        print(result["result"] + ("; " + "; ".join(result["failures"]) if result["failures"] else ""))
    return 0 if not result["failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
