#!/usr/bin/env python3
"""Fail-closed verifier for Card 52's static C15 contract lane."""

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

import p03_c15_contracts as contracts

# C14 is a read-only source of the frozen S10 reservation set.  It has no
# import-time writes and its guarded main is not entered here.
import verify_p03_c14_contracts as previous

S10_RESERVED_PATHS = frozenset(previous.S10_RESERVED_PATHS)


class DuplicateKey(ValueError):
    pass


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def _load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_keys)


def _git_value(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout.strip()


def _git_blob_exists(relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def _candidate_changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
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
        check=True, capture_output=True, text=True,
    ).stdout
    paths.extend(path.replace("\\", "/") for path in committed.splitlines() if path)
    return sorted(set(paths))


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], failures: list[str], label: str) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_manifest_row(row: dict[str, Any], relative: str, failures: list[str]) -> None:
    _assert(row.get("path") == relative, f"manifest row path:{relative}", failures)
    path = ROOT / relative
    if path.is_file():
        raw = path.read_bytes()
        _assert(row.get("state") in ("WORKTREE", "GENERATED"), f"manifest row state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"manifest row bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"manifest row digest:{relative}", failures)
        return
    if relative in contracts.EXISTING_PATHS:
        try:
            raw = contracts._git_blob(ROOT, relative)
        except subprocess.CalledProcessError:
            failures.append(f"manifest base blob:{relative}")
            return
        _assert(row.get("state") == "BASE_HEAD", f"manifest base state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"manifest base bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"manifest base digest:{relative}", failures)
        return
    _assert(relative in contracts.NEW_PATHS, f"manifest row outside fence:{relative}", failures)
    _assert(row.get("state") == "MISSING_NEW_PATH", f"manifest missing state:{relative}", failures)
    _assert(row.get("bytes") == 0 and row.get("sha256") == contracts.sha256_bytes(b""), f"manifest missing digest:{relative}", failures)


def _check_corpus(failures: list[str]) -> None:
    corpus = contracts.CORPUS
    _assert(corpus.get("schema") == "V21P03C15WorkPacketManifestCorpusV1", "rich corpus schema", failures)
    _assert(corpus.get("schemaVersion") == 1 and corpus.get("cardID") == contracts.CARD, "rich corpus identity", failures)
    _assert(corpus.get("synthetic") is True and corpus.get("containsCustomerData") is False and corpus.get("containsSecrets") is False, "rich corpus synthetic boundary", failures)
    _assert(corpus.get("requiredContractNames") == list(contracts.CONTRACT_NAMES), "rich contract families", failures)
    _assert(corpus.get("subjectKinds") == list(contracts.SUBJECT_KINDS), "subject kinds", failures)
    _assert(corpus.get("itemKinds") == list(contracts.ITEM_KINDS), "item kinds", failures)
    _assert(corpus.get("creationBases") == list(contracts.CREATION_BASES), "creation bases", failures)
    _assert(corpus.get("releaseReasons") == list(contracts.RELEASE_REASONS), "release reasons", failures)
    _assert(corpus.get("replayDispositions") == list(contracts.REPLAY_DISPOSITIONS), "replay dispositions", failures)
    _assert(corpus.get("conflictKinds") == list(contracts.CONFLICT_KINDS), "conflict kinds", failures)
    persistence = corpus.get("persistence", {})
    _assert(persistence == contracts.PERSISTENCE, "persistence boundary", failures)
    _assert(persistence.get("schemaRelease") == "PERSISTENT_SCHEMA_V15_WORK_PACKET_COORDINATION", "schema V15", failures)
    _assert(persistence.get("recordSchemaVersion") == 14 and persistence.get("recordsSchemaVersion") == 14, "records schema 14", failures)
    _assert(persistence.get("predecessorSchemaVersion") == 14 and persistence.get("predecessorRecordSchemaVersion") == 13, "predecessor schema", failures)
    _assert(persistence.get("migration") == "EXACT_V14_TO_V15_COPY_ON_WRITE", "copy-on-write migration", failures)
    _assert(persistence.get("canonicalWriter") == "V23-P02-C01" and persistence.get("lifecycleOwner") == contracts.CARD, "writer/owner", failures)
    _assert(persistence.get("firstWriteEnrolled") is True and len(persistence.get("persistedFamilies", [])) == 5 and persistence.get("durableRowCount") == 5, "five durable families", failures)
    _assert(persistence.get("currentProjectionRows") == 0 and persistence.get("currentProjectionRowCount") == 0 and persistence.get("currentProjectionPersistence") == "NONPERSISTENT_REBUILD_ONLY", "nonpersistent current projection", failures)
    _assert(persistence.get("secondStore") is False and persistence.get("secondWriter") is False and persistence.get("accountStore") is False and persistence.get("cloudStore") is False, "store/writer boundary", failures)
    _assert(corpus.get("currentProjectionRows") == [] and corpus.get("currentProjectionPersistence") == "NONPERSISTENT_REBUILD_ONLY", "no current projection row", failures)
    _assert({row.get("reason") for row in corpus.get("releaseCases", [])} == set(contracts.RELEASE_REASONS), "release coverage", failures)
    _assert({row.get("disposition") for row in corpus.get("replayCases", [])} == set(contracts.REPLAY_DISPOSITIONS), "replay coverage", failures)
    _assert({row.get("kind") for row in corpus.get("conflictCases", [])} == set(contracts.CONFLICT_KINDS), "conflict coverage", failures)
    _assert(all(row.get("immutable") is True for key in ("manifestCases", "claimCases", "leaseCases", "releaseCases") for row in corpus.get(key, [])), "immutable durable cases", failures)
    _assert(all(row.get("enrolledBeforeFirstWrite") is True for row in corpus.get("lifecycleCoverage", [])), "lifecycle enrollment", failures)
    hostile_ids = {str(row.get("id")) for row in corpus.get("hostileCases", [])}
    for fragment in ("cross-workspace", "duplicate-packet", "divergent-same-id", "stale-expected-revision", "simultaneous-claim", "expired-lease", "reordered-history", "missing-result", "current-projection", "second-store", "second-writer", "account", "cloud", "delivery", "legal", "finalization"):
        _assert(any(fragment in case_id for case_id in hostile_ids), f"hostile case:{fragment}", failures)
    interruption_ids = {str(row.get("id")) for row in corpus.get("interruptionCases", [])}
    for fragment in ("migration", "mutation", "claim", "lease", "release", "handoff", "projection", "backup", "restore", "delete", "erase", "journal", "replay", "search", "report", "localization"):
        _assert(any(fragment in case_id for case_id in interruption_ids), f"interruption case:{fragment}", failures)
    recovery_ids = {str(row.get("id")) for row in corpus.get("recoveryCases", [])}
    for fragment in ("backup", "restore", "clone", "fork", "forward-fix", "delete", "erase", "journal", "replay", "search", "report", "immutable"):
        _assert(any(fragment in case_id for case_id in recovery_ids), f"recovery case:{fragment}", failures)
    _assert(corpus.get("claims") and all(value is False for value in corpus["claims"].values()), "rich claims false", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C15 fence path to be changed")
    parser.add_argument("--json", action="store_true", help="emit machine-readable result")
    args = parser.parse_args()
    failures: list[str] = []

    try:
        _assert(_git_value("rev-parse", contracts.BASE_HEAD) == contracts.BASE_HEAD, "base head missing", failures)
        _assert(_git_value("show", "-s", "--format=%T", contracts.BASE_HEAD) == contracts.BASE_TREE, "base tree drift", failures)
    except (OSError, subprocess.CalledProcessError) as error:
        failures.append(f"git authority:{error}")

    candidate_paths = _candidate_changed_paths()
    unowned_changed = sorted(set(candidate_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(candidate_paths))
    cache_paths = sorted(path for path in candidate_paths if "__pycache__" in path.split("/") or path.endswith((".pyc", ".pyo", ".DS_Store")))
    s10_overlap = sorted(set(contracts.PATH_FENCE) & S10_RESERVED_PATHS)
    _assert(not unowned_changed, "changed path outside full C15 fence", failures)
    _assert(not cache_paths, "cache artifact changed", failures)
    if args.complete:
        _assert(not missing_required_changed, "required changed path missing from full C15 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 86 and len(set(contracts.PATH_FENCE)) == 86, "exact 86-path fence", failures)
    _assert(len(contracts.EXISTING_PATHS) == 72 and len(contracts.NEW_PATHS) == 14, "path classification counts", failures)
    _assert(len(contracts.MANIFEST_INPUT_PATHS) == 85, "85 manifest inputs", failures)
    _assert(contracts.PATH_FENCE == contracts.EXISTING_PATHS + contracts.NEW_PATHS, "path classification/order", failures)
    _assert(contracts.FENCE_DIGEST == "a0b746c04bf9016ca5dd421ac95973065a066e6f53a30c347c94c747f9607308", "fence digest authority", failures)
    _assert(not s10_overlap, "S10 fence overlap", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(sum(row.get("overlapCount", 0) for row in contracts.PRIOR_FENCE_OVERLAPS) == 676, "prior overlap total", failures)
    _assert(len(contracts.PRIOR_FENCE_OVERLAPS) == 33 and contracts.PRIOR_FENCE_PROOF.get("fenceCount") == 52 and contracts.PRIOR_FENCE_PROOF.get("priorOwnedPathCount") == 869, "prior fence proof counts", failures)
    _assert(contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapCount") == 676 and contracts.PRIOR_FENCE_PROOF.get("unauthorizedOverlapCount") == 0, "prior fence authorization", failures)
    for relative in contracts.PATH_FENCE:
        _assert(_git_blob_exists(relative) is (relative in contracts.EXISTING_PATHS), f"BASE_HEAD existence:{relative}", failures)

    try:
        source_rows = contracts.source_artifacts(ROOT)
        authority_rows = contracts.authority_artifacts(ROOT)
        _assert(len(source_rows) == 72, "source reference count", failures)
        _assert([row.get("path") for row in source_rows] == list(contracts.SOURCE_REFERENCE_PATHS), "source path order", failures)
        _assert([row.get("path") for row in authority_rows] == list(contracts.AUTHORITY_REFERENCE_PATHS), "authority path order", failures)
        for row in source_rows + authority_rows:
            raw = contracts._git_blob(ROOT, row["path"])
            _assert(row["bytes"] == len(raw) and row["sha256"] == contracts.sha256_bytes(raw), f"source digest:{row['path']}", failures)
    except (OSError, subprocess.CalledProcessError, KeyError) as error:
        failures.append(f"source inventory:{error}")
        source_rows, authority_rows = [], []

    try:
        schema = _load(contracts.SCHEMA_PATH)
        contract = _load(contracts.CONTRACT_PATH)
        evidence = _load(contracts.EVIDENCE_PATH)
        brand = _load(contracts.BRAND_PATH)
        manifest = _load(contracts.MANIFEST_PATH)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")
        schema = contract = evidence = brand = manifest = {}

    try:
        expected = contracts.all_outputs(ROOT)
        for relative, raw in expected.items():
            path = ROOT / relative
            _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    except (OSError, json.JSONDecodeError, subprocess.CalledProcessError, TypeError, ValueError) as error:
        failures.append(f"deterministic generation:{error}")
        expected = {}

    _check_corpus(failures)
    _assert(schema == contracts.schema_document(), "schema does not equal generated C15 corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema" and schema.get("$id") == "https://assetrounds.invalid/v23/work-packet-manifest.schema.json" and schema.get("additionalProperties") is False, "schema strict root", failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, failures, label)
        _assert(document.get("verificationMode") == "STATIC_ONLY", f"{label}:mode", failures)
        _assert(document.get("authority") == contracts._authority(), f"{label}:authority", failures)
        _assert(document.get("statusFlags") == contracts._flags(), f"{label}:statusFlags", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation", failures)
        _assert(document.get("s10FenceOverlapPaths") == [] or document.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], f"{label}:S10 overlap", failures)

    _assert(contract.get("artifact") == "V23P03C15WorkPacketManifestContractV1" and contract.get("status") == "PASS_STATIC_PROVISIONAL", "contract identity/status", failures)
    _assert(contract.get("sourceProjection") == contracts.SOURCE_PROJECTION, "contract source projection", failures)
    _assert(contract.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and contract.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "contract prerequisite/order", failures)
    _assert(contract.get("sourceContract", {}).get("sourceArtifacts") == source_rows and contract.get("sourceContract", {}).get("authorityArtifacts") == authority_rows, "contract source rows", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "contract lifecycle", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS) and contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract path classification", failures)
    _assert(contract.get("pathEvidence", {}).get("manifestInputCount") == 85 and contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract path evidence", failures)
    _assert(contract.get("persistenceBoundary") == contracts.PERSISTENCE, "contract persistence boundary", failures)
    _assert(contract.get("corpusShape") == contracts.TEST_CORPUS_SHAPE, "contract fixture shape", failures)

    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL" and evidence.get("sourceProjection") == contracts.SOURCE_PROJECTION, "evidence result/projection", failures)
    _assert(evidence.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and evidence.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "evidence prerequisite/order", failures)
    _assert(evidence.get("pathEvidence") == contract.get("pathEvidence"), "evidence path evidence", failures)
    _assert(evidence.get("sourceContractDigest") == contracts.sha256_value(source_rows) and evidence.get("authorityArtifactDigest") == contracts.sha256_value(authority_rows), "evidence source digests", failures)
    _assert(evidence.get("persistenceBoundary") == contracts.PERSISTENCE, "evidence persistence", failures)
    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL" and brand.get("affectedSurfacePaths") == [], "brand static boundary", failures)
    _assert(brand.get("semanticStates") == list(contracts.ITEM_KINDS) + list(contracts.RELEASE_REASONS), "brand semantic states", failures)

    manifest_rows = manifest.get("artifacts", [])
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE) and manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST, "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 86 and manifest.get("manifestInputCount") == 85 and manifest.get("existingPathCount") == 72 and manifest.get("newPathCount") == 14, "manifest path counts", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE) and manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest allowed paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows and manifest.get("authorityArtifacts") == authority_rows, "manifest source rows", failures)
    _assert([row.get("path") for row in manifest_rows] == list(contracts.MANIFEST_INPUT_PATHS) and len(manifest_rows) == 85, "manifest input closure", failures)
    for row in manifest_rows:
        _check_manifest_row(row, row.get("path", ""), failures)
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(manifest_rows), "manifest artifact set digest", failures)
    _assert(manifest.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and manifest.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "manifest prerequisite/order", failures)
    _assert(manifest.get("persistenceBoundary") == contracts.PERSISTENCE, "manifest persistence", failures)
    _assert(manifest.get("priorFenceProof") == contracts.PRIOR_FENCE_PROOF and sum(row.get("overlapCount", 0) for row in manifest.get("priorFenceOverlaps", [])) == 676, "manifest prior overlap proof", failures)

    try:
        source_text = b"\n".join(contracts._git_blob(ROOT, path) for path in contracts.AUTHORITY_REFERENCE_PATHS).decode("utf-8")
        for token in contracts.SOURCE_CONTRACT_TOKENS:
            _assert(token in source_text, f"source contract token:{token}", failures)
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        failures.append(f"authority token source:{error}")

    fixture_path = ROOT / contracts.FIXTURE_PATH
    if fixture_path.is_file():
        try:
            _assert(_load(contracts.FIXTURE_PATH) == contracts.TEST_CORPUS_SHAPE, "fixture corpus shape equality", failures)
        except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
            failures.append(f"fixture load:{error}")
    else:
        _assert(False, "fixture missing", failures)

    current_text = "\n".join(
        (ROOT / path).read_text(encoding="utf-8", errors="replace")
        for path in contracts.NEW_PATHS
        if (ROOT / path).is_file() and path.endswith(".swift")
    )
    for symbol in (*contracts.CONTRACT_NAMES, "WorkPacketManifestCoordinatorV1", "WorkPacketManifestLifecycleAdapterV1"):
        _assert(symbol in current_text, f"required symbol:{symbol}", failures)
    _assert("WorkPacketManifestRow" in current_text and "WorkItemClaimRow" in current_text and "WorkLeaseRow" in current_text and "WorkReleaseRow" in current_text and "WorkHandoffRow" in current_text, "five persistence row symbols", failures)

    result: dict[str, Any] = {
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL",
        "cardID": contracts.CARD,
        "pathFenceCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "manifestInputCount": len(contracts.MANIFEST_INPUT_PATHS),
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "fenceDigest": contracts.FENCE_DIGEST,
        "baseHead": contracts.BASE_HEAD,
        "baseTree": contracts.BASE_TREE,
        "coordinationHead": contracts.COORDINATION_HEAD,
        "coordinationTree": contracts.COORDINATION_TREE,
        "contextDigest": contracts.CONTEXT_DIGEST,
        "prerequisiteDigest": contracts.PREREQUISITE_DIGEST,
        "unownedChangedPathCount": len(unowned_changed),
        "missingRequiredChangedPathCount": len(missing_required_changed),
        "cachePathCount": len(cache_paths),
        "s10FenceOverlapPaths": s10_overlap,
        "authorizedPriorOverlapCount": contracts.PRIOR_FENCE_PROOF["authorizedOverlapCount"],
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
