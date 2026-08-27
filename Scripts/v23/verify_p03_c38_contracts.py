"""Verify Card 46's static contract corpus, path fence, and evidence receipt."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c38_contracts as contracts


class DuplicateKey(ValueError):
    pass


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def _load(relative: str) -> dict[str, Any]:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_keys)


def _git_status_paths() -> list[str]:
    output = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    paths: list[str] = []
    for line in output.splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))
    return sorted(set(paths))


def _base_path_exists(relative: str) -> bool:
    probe = subprocess.run(
        ["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"],
        capture_output=True,
    )
    return probe.returncode == 0


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], failures: list[str], label: str) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_row(row: dict[str, Any], relative: str, failures: list[str]) -> None:
    if not relative:
        failures.append("row path is empty")
        return
    path = ROOT / relative
    _assert(row.get("path") == relative, f"row path:{relative}", failures)
    if path.is_file():
        raw = path.read_bytes()
        _assert(row.get("bytes") == len(raw), f"row bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"row digest:{relative}", failures)
        return
    if relative in contracts.EXISTING_PATHS:
        raw = contracts._git_blob(ROOT, relative)
        _assert(row.get("state") == "BASE_HEAD", f"row state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"row bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"row digest:{relative}", failures)
        return
    _assert(relative in contracts.NEW_PATHS, f"row outside fence:{relative}", failures)
    _assert(row.get("state") == "MISSING_NEW_PATH", f"row state:{relative}", failures)
    _assert(row.get("bytes") == 0 and row.get("sha256") == contracts.sha256_bytes(b""), f"row missing digest:{relative}", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="retain machine-readable output; default is the same")
    parser.parse_args()

    failures: list[str] = []
    status_paths = _git_status_paths()
    unowned_changed = sorted(set(status_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(status_paths))

    _assert(not unowned_changed, "changed path outside full C38 fence", failures)
    _assert(not missing_required_changed, "required changed path missing from full C38 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 63, "path fence count", failures)
    _assert(len(contracts.EXISTING_PATHS) == 48, "existing path count", failures)
    _assert(len(contracts.NEW_PATHS) == 15, "new path count", failures)
    _assert(tuple(contracts.EXISTING_PATHS + contracts.NEW_PATHS) == tuple(contracts.PATH_FENCE), "path classification", failures)
    _assert(contracts.FENCE_DIGEST == "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "fence digest authority", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(
        all("s10" not in path.lower() and "phase10" not in path.lower() for path in contracts.PATH_FENCE),
        "S10 path overlap",
        failures,
    )
    for relative in contracts.PATH_FENCE:
        if relative in contracts.EXISTING_PATHS:
            _assert(_base_path_exists(relative), f"existing path absent at BASE_HEAD:{relative}", failures)
        else:
            _assert(not _base_path_exists(relative), f"new path existed at BASE_HEAD:{relative}", failures)

    source_rows = contracts.source_artifacts(ROOT)
    for row in source_rows:
        _assert(_base_path_exists(row["path"]), f"missing source at BASE_HEAD:{row['path']}", failures)
        base_raw = contracts._git_blob(ROOT, row["path"])
        _assert(row["bytes"] == len(base_raw), f"source bytes:{row['path']}", failures)
        _assert(row["sha256"] == contracts.sha256_bytes(base_raw), f"source digest:{row['path']}", failures)
    authority_rows = contracts.authority_artifacts(ROOT)

    try:
        schema = _load(contracts.SCHEMA_PATH)
        contract = _load(contracts.CONTRACT_PATH)
        evidence = _load(contracts.EVIDENCE_PATH)
        brand = _load(contracts.BRAND_PATH)
        manifest = _load(contracts.MANIFEST_PATH)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")
        schema = contract = evidence = brand = manifest = {}

    expected = contracts.all_outputs(ROOT)
    for relative, raw in expected.items():
        path = ROOT / relative
        _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)

    _assert(schema == contracts.schema_document(), "schema does not equal generated corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", "schema dialect", failures)
    _assert(schema.get("type") == "object" and schema.get("additionalProperties") is False, "schema strict root", failures)

    _check_sealed(contract, failures, "contract")
    _check_sealed(evidence, failures, "evidence")
    _check_sealed(brand, failures, "brand")
    _check_sealed(manifest, failures, "manifest")

    _assert(contract.get("artifact") == "V23P03C38PartyAccountabilityContractV1", "contract artifact", failures)
    _assert(contract.get("status") == "PASS_STATIC_PROVISIONAL", "contract status", failures)
    _assert(contract.get("verificationMode") == "STATIC_ONLY", "contract mode", failures)
    _assert(contract.get("sourceArtifacts") == source_rows, "contract source rows", failures)
    _assert(contract.get("authorityArtifacts") == authority_rows, "contract authority rows", failures)
    _assert(contract.get("authority", {}).get("pathFenceDigest") == contracts.FENCE_DIGEST, "contract authority fence digest", failures)
    _assert(contract.get("authority", {}).get("allowedPathCount") == 63, "contract authority path count", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "lifecycle coverage", failures)
    _assert(contract.get("requiredSemantics", {}).get("partyKinds") == list(contracts.PARTY_KINDS), "party semantics", failures)
    _assert(contract.get("requiredSemantics", {}).get("siteRoleKinds") == list(contracts.SITE_ROLE_KINDS), "role semantics", failures)
    _assert(contract.get("requiredSemantics", {}).get("responsibilityKinds") == list(contracts.RESPONSIBILITY_KINDS), "actor semantics", failures)
    _assert(contract.get("requiredSemantics", {}).get("qualificationProvenance") == list(contracts.QUALIFICATION_PROVENANCE), "qualification semantics", failures)
    _assert(contract.get("requiredSemantics", {}).get("signoffDispositions") == list(contracts.SIGNOFF_DISPOSITIONS), "signoff semantics", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("fullFencePaths") == list(contracts.FULL_FENCE_PATHS), "contract full fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS), "contract existing paths", failures)
    _assert(contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract new paths", failures)
    _assert(contract.get("pathEvidence", {}).get("fenceDigest") == contracts.FENCE_DIGEST, "contract path fence digest", failures)
    _assert(contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract S10 overlap", failures)

    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL", "evidence result", failures)
    _assert(evidence.get("verificationMode") == "STATIC_ONLY", "evidence mode", failures)
    _assert(evidence.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "evidence path fence", failures)
    _assert(evidence.get("pathEvidence", {}).get("fullFencePaths") == list(contracts.FULL_FENCE_PATHS), "evidence full fence", failures)
    _assert(evidence.get("pathEvidence", {}).get("pathFenceDigest") == contracts.FENCE_DIGEST, "evidence path fence digest", failures)
    _assert(evidence.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS), "evidence existing paths", failures)
    _assert(evidence.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "evidence new paths", failures)
    _assert(evidence.get("pathEvidence", {}).get("sourceArtifacts") == source_rows, "evidence source rows", failures)
    _assert(evidence.get("pathEvidence", {}).get("authorityArtifacts") == authority_rows, "evidence authority rows", failures)
    _assert(evidence.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "evidence S10 overlap", failures)

    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL", "brand status", failures)
    _assert(brand.get("verificationMode") == "STATIC_ONLY", "brand mode", failures)
    _assert(brand.get("affectedSurfacePaths") == [], "brand shipping surfaces", failures)
    _assert(brand.get("s10FenceOverlapPaths") == [], "brand S10 overlap", failures)

    manifest_rows = manifest.get("artifacts", [])
    expected_manifest_paths = list(contracts.MANIFEST_INPUT_PATHS)
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE), "manifest path fence", failures)
    _assert(manifest.get("fullFencePaths") == list(contracts.FULL_FENCE_PATHS), "manifest full fence", failures)
    _assert(manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST, "manifest path fence digest", failures)
    _assert(manifest.get("pathFenceCount") == 63, "manifest fence count", failures)
    _assert(manifest.get("existingPathCount") == 48 and manifest.get("newPathCount") == 15, "manifest classification", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE), "manifest allowed paths", failures)
    _assert(manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest delete/rename paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows, "manifest source rows", failures)
    _assert(manifest.get("authorityArtifacts") == authority_rows, "manifest authority rows", failures)
    _assert([row.get("path") for row in manifest_rows] == expected_manifest_paths, "manifest artifact paths", failures)
    for row in manifest_rows:
        _check_row(row, row.get("path", ""), failures)

    all_documents = (contract, evidence, brand, manifest)
    for label, document in zip(("contract", "evidence", "brand", "manifest"), all_documents):
        flags = document.get("statusFlags")
        _assert(isinstance(flags, dict), f"{label}:statusFlags", failures)
        for key in ("native", "hosted", "adoption", "acceptance", "release"):
            _assert(flags.get(key) is False, f"{label}:{key} flag", failures)
        for key in ("nativeAcceptance", "hostedAcceptance", "adoptionEvidence", "acceptanceCredit", "releaseReadiness"):
            _assert(flags.get(key) is False, f"{label}:{key} flag", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation gate", failures)

    source_text = b"\n".join(contracts._git_blob(ROOT, path) for path in contracts.AUTHORITY_REFERENCE_PATHS).decode("utf-8")
    for token in contracts.SOURCE_CONTRACT_TOKENS:
        _assert(token in source_text, f"source contract token:{token}", failures)

    result: dict[str, Any] = {
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL",
        "cardID": contracts.CARD,
        "pathFenceCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "fenceDigest": contracts.FENCE_DIGEST,
        "unownedChangedPathCount": len(unowned_changed),
        "missingRequiredChangedPathCount": len(missing_required_changed),
        "s10FenceOverlapPaths": [],
        "native": False,
        "hosted": False,
        "adoption": False,
        "acceptance": False,
        "release": False,
    }
    if failures:
        result["failures"] = failures
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
