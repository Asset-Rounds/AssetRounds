#!/usr/bin/env python3
"""Static/import verifier for the V23-P03-C55 complete hydrated fence."""
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

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c55_contracts as contracts


def _run(command: list[str]) -> str:
    return subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True).stdout


def _fresh_outputs() -> dict[str, bytes]:
    # A fresh interpreter catches accidental module-global nondeterminism and
    # also proves the import path works without generating bytecode caches.
    child = (
        "import base64,json,sys;sys.dont_write_bytecode=True;"
        "sys.path.insert(0,'Scripts/v23');import p03_c55_contracts as c;"
        "o=c.all_outputs(c.Path.cwd());"
        "print(json.dumps({p:base64.b64encode(v).decode('ascii') for p,v in sorted(o.items())},sort_keys=True))"
    )
    first = json.loads(_run([sys.executable, "-B", "-c", child]))
    second = json.loads(_run([sys.executable, "-B", "-c", child]))
    if first != second:
        raise ValueError("C55 fresh-process generation differs")
    return {path: base64.b64decode(value, validate=True) for path, value in first.items()}


def _changed_paths() -> set[str]:
    changed: set[str] = set()
    for command in (
        ["git", "diff", "--name-only", contracts.BASE_HEAD, "--"],
        ["git", "diff", "--cached", "--name-only", "--"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        changed.update(_run(command).split())
    return {path.replace("\\", "/") for path in changed if path.strip()}


def _cache_paths() -> list[str]:
    cache: list[str] = []
    scripts = ROOT / "Scripts" / "v23"
    for path in scripts.rglob("*"):
        if path.name == "__pycache__" or path.suffix == ".pyc":
            cache.append(str(path.relative_to(ROOT)).replace("\\", "/"))
    return sorted(cache)


def _verify_manifest(outputs: dict[str, bytes]) -> list[str]:
    failures: list[str] = []
    try:
        manifest = json.loads(outputs[contracts.MANIFEST_PATH])
        rows = manifest["files"]
        if [row.get("path") for row in rows] != list(contracts.MANIFEST_INPUT_PATHS):
            failures.append("manifest input path order differs")
            return failures
        if manifest.get("manifestInputCount") != len(contracts.MANIFEST_INPUT_PATHS):
            failures.append("manifest input count differs")
        if manifest.get("pathFenceCount") != len(contracts.PATH_FENCE):
            failures.append("manifest path fence count differs")
        expected_rows: list[dict[str, object]] = []
        for path in contracts.MANIFEST_INPUT_PATHS:
            data = outputs[path] if path in contracts.GENERATED_INPUT_PATHS else (ROOT / path).read_bytes()
            expected_rows.append({
                "path": path,
                "status": "SEALED_TOOLING" if path in contracts.TOOLING_EDIT_PATHS else "SEALED_SOURCE",
                "byteCount": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            })
        if rows != expected_rows:
            failures.append("manifest byte inventory differs")
        if manifest.get("sourceLaneRows") != [row for row in expected_rows if row["path"] in contracts.IMPLEMENTATION_PATHS]:
            failures.append("manifest source lane inventory differs")
        if manifest.get("finalHashesSealed") is not True:
            failures.append("manifest final hashes are not sealed")
        if manifest.get("hashDisposition") != "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED":
            failures.append("manifest hash disposition differs")
        if manifest.get("artifactDigest") != hashlib.sha256(contracts.canonical(expected_rows)).hexdigest():
            failures.append("manifest artifact digest differs")
    except Exception as error:
        failures.append("manifest verification:" + str(error))
    return failures


def _verify_artifact_semantics(outputs: dict[str, bytes]) -> list[str]:
    """Verify the newly landed C55 fields and all non-activation flags."""
    failures: list[str] = []
    try:
        contract = json.loads(outputs[contracts.CONTRACT_PATH])
        evidence = json.loads(outputs[contracts.EVIDENCE_PATH])
        schema = json.loads(outputs[contracts.SCHEMA_PATH])
        expected = {
            "dualPhysicalAndStreamPostImages": True,
            "nativeProjectedWorkspaceClosure": True,
            "partLocationOnlyExternalBaselines": True,
            "activeRev1CloneFork": True,
            "materializeBeforeInsert": True,
            "nilStreamExternalProjection": True,
            "terminalIdentityBoundIncludesWorkResourceSuccessors": True,
            "snapshotRowCap": contracts.C55_SNAPSHOT_ROW_CAP,
            "terminalIdentityCap": contracts.C55_TERMINAL_IDENTITY_CAP,
        }
        expected_restore_identity = {
            "freshC55Disposition": contracts.C55_FRESH_DESTINATION_IDENTITY_DISPOSITION,
            "freshC55EmptyInstallOrReplaceExisting": True,
            "freshC55ResetsSequence": True,
            "freshC55PreservesEveryTerminalRow": True,
            "freshC55ExternalProjectionOnlyPartAndLocation": True,
            "cloneForkDisposition": contracts.C55_CLONE_FORK_IDENTITY_DISPOSITION,
            "cloneForkDropsNonCatalogStock": True,
            "sameReplicaReplaceDisposition": contracts.C55_SAME_REPLICA_IDENTITY_DISPOSITION,
        }
        semantics = contract.get("semantics", {})
        static_checks = evidence.get("staticChecks", {})
        for key, value in expected.items():
            if semantics.get(key) != value:
                failures.append("contract semantic differs:" + key)
            if static_checks.get(key) != value:
                failures.append("evidence static check differs:" + key)
        if semantics.get("restoreIdentity") != expected_restore_identity:
            failures.append("contract restore identity semantics differ")
        for key, value in expected_restore_identity.items():
            if static_checks.get(key) != value:
                failures.append("evidence restore identity check differs:" + key)

        expected_flags = dict(contracts.FLAGS)
        for path in (contracts.CONTRACT_PATH, contracts.EVIDENCE_PATH, contracts.BRAND_PATH, contracts.MANIFEST_PATH):
            document = contract if path == contracts.CONTRACT_PATH else (
                evidence if path == contracts.EVIDENCE_PATH else json.loads(outputs[path])
            )
            if document.get("statusFlags") != expected_flags:
                failures.append("status flags differ:" + path)
            if document.get("finalHashesSealed") is not True:
                failures.append("final hashes are not sealed:" + path)
        if evidence.get("acceptanceEligible") is not False:
            failures.append("evidence acceptance flag is not false")
        if evidence.get("nativeCompileRan") is not False:
            failures.append("evidence native flag is not false")
        if evidence.get("hostedDispatchEnabled") is not False:
            failures.append("evidence hosted flag is not false")

        semantic_schema = schema.get("$defs", {}).get("semantics", {})
        required = set(semantic_schema.get("required", ()))
        properties = semantic_schema.get("properties", {})
        for key, value in expected.items():
            if key not in required:
                failures.append("schema semantic is not required:" + key)
            if properties.get(key, {}).get("const") != value:
                failures.append("schema semantic differs:" + key)
        if "restoreIdentity" not in required:
            failures.append("schema semantic is not required:restoreIdentity")
        restore_schema = properties.get("restoreIdentity", {})
        if restore_schema.get("type") != "object":
            failures.append("schema restore identity type differs")
        restore_required = set(restore_schema.get("required", ()))
        restore_properties = restore_schema.get("properties", {})
        for key, value in expected_restore_identity.items():
            if key not in restore_required:
                failures.append("schema restore identity is not required:" + key)
            if restore_properties.get(key, {}).get("const") != value:
                failures.append("schema restore identity differs:" + key)
        if schema.get("properties", {}).get("finalHashesSealed", {}).get("const") is not True:
            failures.append("schema final hashes are not sealed")
    except Exception as error:
        failures.append("artifact semantic verification:" + str(error))
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--complete", action="store_true", help="require source-ready complete fence")
    parser.add_argument("--json", action="store_true", help="emit structured result")
    args = parser.parse_args()

    failures: list[str] = []
    outputs: dict[str, bytes] = {}
    source = contracts.source_status(ROOT)
    source_checks: dict[str, object] = {"status": source}

    try:
        contracts.assert_scaffold(ROOT)
        for path in contracts.SCRIPT_PATHS:
            ast.parse((ROOT / path).read_text(encoding="utf-8"), filename=path)
        missing = contracts.assert_source_contracts(ROOT)
        source_checks["missingPaths"] = list(missing)
        source_checks["sourceReady"] = not missing
        outputs = contracts.all_outputs(ROOT)
    except Exception as error:
        failures.append(str(error))

    missing_fence = [path for path in contracts.PATH_FENCE if not (ROOT / path).is_file()]
    if missing_fence:
        failures.append("missing fence path:" + ",".join(missing_fence))
    for path, expected in outputs.items():
        target = ROOT / path
        if not target.is_file():
            failures.append("artifact absent:" + path)
        elif target.read_bytes() != expected:
            failures.append("artifact differs:" + path)

    try:
        changed = _changed_paths()
    except Exception as error:
        changed = set()
        failures.append("changed-path inventory:" + str(error))
    cache = _cache_paths()
    if cache:
        failures.append("python cache:" + ",".join(cache))

    fence_changed = changed & set(contracts.PATH_FENCE)
    unowned = changed - set(contracts.PATH_FENCE)
    missing_new_changes = set(contracts.NEW_PATHS) - changed
    unchanged_existing = set(contracts.EXISTING_PATHS) - changed
    if args.complete:
        if unowned:
            failures.append("unowned changed path:" + ",".join(sorted(unowned)))
        if missing_new_changes:
            failures.append("new fence path not changed:" + ",".join(sorted(missing_new_changes)))
        if source["missingPaths"]:
            failures.append("source lanes unresolved:" + ",".join(source["missingPaths"]))
        try:
            fresh = _fresh_outputs()
            if outputs and fresh != outputs:
                failures.append("fresh-process generation is nondeterministic")
        except Exception as error:
            failures.append("fresh-process generation:" + str(error))
        failures.extend(_verify_manifest(outputs))
        if outputs:
            failures.extend(_verify_artifact_semantics(outputs))
    else:
        # The dry lane intentionally does not reject absent product rows; it
        # rejects only malformed present rows.  The missing list remains in
        # the result and acceptanceEligible is always false.
        try:
            fresh = _fresh_outputs()
            if outputs and fresh != outputs:
                failures.append("fresh-process generation is nondeterministic")
        except Exception as error:
            failures.append("fresh-process generation:" + str(error))

    if failures:
        result_status = "FAIL"
    elif source["missingPaths"]:
        result_status = "PROVISIONAL_MISSING_SOURCE"
    else:
        result_status = "PASS_STATIC_PROVISIONAL"
    result = {
        "cardID": contracts.CARD,
        "result": result_status,
        "complete": args.complete,
        "acceptanceEligible": False,
        "staticVerificationComplete": result_status == "PASS_STATIC_PROVISIONAL" and args.complete,
        "sourceReady": not bool(source["missingPaths"]),
        "missingSourcePaths": source["missingPaths"],
        "presentSourcePaths": source["presentPaths"],
        "sourceChecks": source_checks,
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "fencePathCount": len(contracts.PATH_FENCE),
        "toolingEditPathCount": len(contracts.TOOLING_EDIT_PATHS),
        "changedPathCount": len(changed),
        "fenceChangedPathCount": len(fence_changed),
        "unchangedExistingPathCount": len(unchanged_existing),
        "missingNewChangedPathCount": len(missing_new_changes),
        "unownedChangedPathCount": len(unowned),
        "missingFencePathCount": len(missing_fence),
        "pythonCachePathCount": len(cache),
        "priorFenceCount": contracts.PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": contracts.PRIOR_OWNED_PATH_COUNT,
        "authorizedOverlapCount": contracts.AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": contracts.UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": contracts.S10_RESERVATION_OVERLAP_COUNT,
        "s10ReservedPathCount": contracts.S10_RESERVED_PATH_COUNT,
        "flagsAllFalse": not any(contracts.FLAGS.values()),
        "finalHashesSealed": result_status == "PASS_STATIC_PROVISIONAL",
        "failures": failures,
    }
    print(json.dumps(result, indent=2, sort_keys=True) if args.json else "C55 verifier " + result_status)
    if result_status == "PASS_STATIC_PROVISIONAL":
        return 0
    if result_status == "PROVISIONAL_MISSING_SOURCE" and not args.complete:
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
