#!/usr/bin/env python3
"""Verify C19's static corpus, path fence, and deterministic evidence artifacts."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c19_contracts as contracts


class DuplicateKey(ValueError):
    pass


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise DuplicateKey(key)
        value[key] = item
    return value


def _load(relative: str) -> dict[str, Any]:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_keys)


def _candidate_changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    paths: list[str] = []
    for line in status.splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))
    committed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    paths.extend(path.replace("\\", "/") for path in committed.splitlines() if path)
    return sorted(set(paths))


def _base_path_exists(relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], label: str, failures: list[str]) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(
        isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)),
        f"{label}:artifactDigest",
        failures,
    )


def _check_row(row: dict[str, Any], relative: str, rendered: dict[str, bytes], failures: list[str]) -> None:
    path = ROOT / relative
    _assert(row.get("path") == relative, f"row path:{relative}", failures)
    if relative in rendered:
        raw = rendered[relative]
        _assert(row.get("state") == "GENERATED", f"row generated state:{relative}", failures)
        _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row generated digest:{relative}", failures)
    elif path.is_file():
        raw = path.read_bytes()
        _assert(row.get("state") == "WORKTREE", f"row worktree state:{relative}", failures)
        _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row worktree digest:{relative}", failures)
    elif relative in contracts.EXISTING_PATHS:
        raw = contracts._git_blob(ROOT, relative)
        _assert(row.get("state") == "BASE_HEAD", f"row base state:{relative}", failures)
        _assert(row.get("bytes") == len(raw) and row.get("sha256") == contracts.sha256_bytes(raw), f"row base digest:{relative}", failures)
    else:
        _assert(row.get("state") == "MISSING_NEW_PATH", f"row missing state:{relative}", failures)
        _assert(row.get("bytes") == 0 and row.get("sha256") == contracts.sha256_bytes(b""), f"row missing digest:{relative}", failures)


def _check_test_methods(failures: list[str]) -> None:
    test_path = ROOT / "FieldEvidenceAppTests/V9_33MeasurementIntegrityTests.swift"
    if not test_path.is_file():
        return
    names = re.findall(r"\bfunc\s+(testV23P03C19[A-Z]\w*)\s*\(", test_path.read_text(encoding="utf-8"))
    _assert(tuple(names) == contracts.TEST_METHODS, f"test method selector mismatch: {names}", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--complete",
        action="store_true",
        help="require every C19 fence path to be changed; static-only mode permits pending implementation paths",
    )
    parser.add_argument("--json", action="store_true", help="emit machine-readable evidence")
    args = parser.parse_args()

    failures: list[str] = []
    changed = _candidate_changed_paths()
    unowned = sorted(set(changed) - set(contracts.PATH_FENCE))
    missing = sorted(set(contracts.PATH_FENCE) - set(changed))
    missing_required = sorted(set(contracts.PATH_FENCE) - set(changed))
    rendered: dict[str, bytes] = {}
    try:
        rendered = contracts.all_outputs(ROOT)
    except (OSError, subprocess.CalledProcessError, ValueError, TypeError) as error:
        failures.append(f"render:{error}")

    _assert(not unowned, "changed path outside full C19 fence", failures)
    if args.complete:
        _assert(not missing_required, "required implementation path missing from C19 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 112, "path fence count", failures)
    _assert(len(contracts.EXISTING_PATHS) == 98, "existing path count", failures)
    _assert(len(contracts.NEW_PATHS) == 14, "new path count", failures)
    _assert(len(set(contracts.PATH_FENCE)) == 112, "duplicate path fence", failures)
    _assert(contracts.PRIOR_FENCE_PROOF["overlapCount"] == 956, "prior overlap count", failures)
    _assert(sum(row["overlapCount"] for row in contracts.PRIOR_FENCE_OVERLAPS) == 956, "prior overlap row total", failures)
    _assert(not set(contracts.PATH_FENCE) & {".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml"}, "S10 workflow overlap", failures)
    _assert(not any("s10" in path.lower() or "phase10" in path.lower() for path in contracts.PATH_FENCE), "S10 path overlap", failures)
    for relative in contracts.EXISTING_PATHS:
        _assert(_base_path_exists(relative), f"existing path absent at BASE_HEAD:{relative}", failures)
    for relative in contracts.NEW_PATHS:
        _assert(not _base_path_exists(relative), f"new path existed at BASE_HEAD:{relative}", failures)

    try:
        schema = _load(contracts.SCHEMA_PATH)
        contract = _load(contracts.CONTRACT_PATH)
        evidence = _load(contracts.EVIDENCE_PATH)
        brand = _load(contracts.BRAND_PATH)
        manifest = _load(contracts.MANIFEST_PATH)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")
        schema = contract = evidence = brand = manifest = {}

    for relative, raw in rendered.items():
        path = ROOT / relative
        _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    if rendered:
        _assert(schema == contracts.schema_document(), "schema does not equal generated corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect", failures)
    _assert(schema.get("type") == "object" and schema.get("additionalProperties") is False, "schema strict root", failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, label, failures)
        _assert(all(value is False for value in document.get("statusFlags", {}).values()), f"{label}: status flag overclaim", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}: reconciliation flag", failures)

    authority = contract.get("authority", {})
    _assert(contract.get("artifact") == "V23P03C19MeasurementIntegrityContractV1", "contract artifact", failures)
    _assert(contract.get("cardID") == contracts.CARD and contract.get("status") == "PASS_STATIC_PROVISIONAL" and contract.get("verificationMode") == "STATIC_ONLY", "contract status", failures)
    _assert(authority.get("coordinationHead") == contracts.COORDINATION_HEAD and authority.get("coordinationTree") == contracts.COORDINATION_TREE, "contract coordination identity", failures)
    _assert(authority.get("contextDigest") == contracts.CONTEXT_DIGEST and authority.get("pathFenceDigest") == contracts.FENCE_DIGEST, "contract authority digests", failures)
    _assert(authority.get("coordinationCASSequence") == contracts.COORDINATION_CAS_SEQUENCE and authority.get("hydrationTransitionSequence") == contracts.HYDRATION_TRANSITION_SEQUENCE, "contract hydration sequence", failures)
    _assert(authority.get("hydrationTransitionDigest") == contracts.HYDRATION_TRANSITION_DIGEST, "contract hydration digest", failures)
    _assert(authority.get("allowedPathCount") == 112 and authority.get("existingPathCount") == 98 and authority.get("newPathCount") == 14, "contract path counts", failures)
    _assert(contract.get("directPrerequisiteEvidence", {}).get("ordinaryDirectEdgeCount") == 2, "contract prerequisite edges", failures)
    _assert(contract.get("requiredSemantics", {}).get("contractNames") == list(contracts.CONTRACT_NAMES), "contract type names", failures)
    _assert(contract.get("testMethods") == list(contracts.TEST_METHODS), "contract test selectors", failures)
    _assert(evidence.get("artifact") == "V23P03C19MeasurementIntegrityEvidenceReceiptV1" and evidence.get("result") == "PASS_STATIC_PROVISIONAL", "evidence result", failures)
    _assert(brand.get("artifact") == "V23P03C19BrandImpactManifestV1" and brand.get("s10FenceOverlapPaths") == [], "brand boundary", failures)
    _assert(manifest.get("artifact") == "V23P03C19ToolingManifestV1" and manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 112 and manifest.get("existingPathCount") == 98 and manifest.get("newPathCount") == 14 and manifest.get("sourceReferenceCount") == 98, "manifest counts", failures)
    _assert(manifest.get("s10FenceOverlapPaths") == [] and manifest.get("artifactSetDigest") == contracts.sha256_value(manifest.get("artifacts", [])), "manifest closure digest", failures)
    rows = manifest.get("artifacts", [])
    _assert(len(rows) == 111 and {row.get("path") for row in rows} == set(contracts.MANIFEST_INPUT_PATHS), "manifest rows", failures)
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("path"), str):
            _check_row(row, row["path"], rendered, failures)
    _check_test_methods(failures)

    result = "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL"
    payload = {
        "acceptance": False,
        "adoption": False,
        "cardID": contracts.CARD,
        "contextDigest": contracts.CONTEXT_DIGEST,
        "coordinationCASSequence": contracts.COORDINATION_CAS_SEQUENCE,
        "coordinationHead": contracts.COORDINATION_HEAD,
        "coordinationLedgerDigest": contracts.COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": contracts.COORDINATION_PROJECTION_DIGEST,
        "coordinationTree": contracts.COORDINATION_TREE,
        "existingPathCount": 98,
        "fenceDigest": contracts.FENCE_DIGEST,
        "hosted": False,
        "hydrationTransitionDigest": contracts.HYDRATION_TRANSITION_DIGEST,
        "hydrationTransitionSequence": contracts.HYDRATION_TRANSITION_SEQUENCE,
        "missingRequiredChangedPathCount": len(missing_required),
        "native": False,
        "newPathCount": 14,
        "missingAllowedPathCount": len(missing),
        "pathFenceCount": 112,
        "priorOverlapCount": 956,
        "release": False,
        "result": result,
        "s10FenceOverlapPaths": [],
        "sourceReferenceCount": 98,
        "unownedChangedPathCount": len(unowned),
    }
    if failures:
        payload["failures"] = failures
    print(json.dumps(payload, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
