#!/usr/bin/env python3
"""Deterministic, read-only validation for the external AssetRounds V30 R2 package.

This validator does not inspect or mutate an installed repository. It validates only
the external package directory and frozen values supplied for the V30 handoff.
"""

from __future__ import annotations

import hashlib
import json
import argparse
import re
import stat
import sys
from pathlib import Path, PureWindowsPath
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parent
ARCH = ROOT / "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md"
FOUNDATION = ROOT / "EXPANSION_V30_FOUNDATION_PLAN.md"
HANDOFF = ROOT / "EXPANSION_V30_HANDOFF.md"
PROMPT = ROOT / "NEXT_CODEX_SESSION_PROMPT.md"
AUTH = ROOT / "V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json"
MANIFEST = ROOT / "V30_PACKAGE_MANIFEST.json"
CARD_REGISTER = ROOT / "V30_CARD_REGISTER.json"
GRAPH = ROOT / "V30_DIRECT_DEPENDENCY_GRAPH.json"
LOCALE_REGISTRY = ROOT / "V30_LOCALE_REGISTRY.json"
V24_PROJECTION = ROOT / "V30_V24_DISPOSITION_PROJECTION.json"

GENERATOR_FILES = (
    "generate_v30_machine_artifacts.py",
    "generate_v30_path_fences.py",
    "generate_v30_authority.py",
    "generate_v30_bootstrap_payloads.py",
    "generate_v30_manifest.py",
)
VALIDATOR_FILE = "validate_v30_package.py"
HUMAN_FILES = (
    "EXPANSION_V30_FOUNDATION_PLAN.md",
    "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md",
    "EXPANSION_V30_HANDOFF.md",
    "NEXT_CODEX_SESSION_PROMPT.md",
)
MACHINE_FILES = (
    "V30_CARD_REGISTER.json",
    "V30_DIRECT_DEPENDENCY_GRAPH.json",
    "V30_LOCALE_REGISTRY.json",
    "V30_V24_DISPOSITION_PROJECTION.json",
    "V30_PRE_S10_PATH_FENCES.json",
)
BOOTSTRAP_FILES = (
    "V30_CARD_001_CONTEXT.json",
    "V30_CARD_001_FENCE.json",
    "V30_CARD_001_CURRENT_TASK.md",
    "V30_CARD_001_CI_SELECTION.json",
    "V30_EXECUTION_HANDOFF_GENESIS.md",
    "V30_PROVISIONAL_LEDGER_GENESIS.json",
    "V30_PROVISIONAL_LEDGER_PROJECTION.json",
)
AUTHORITY_FILES = ("V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json",)
# Bind every package file except the manifest itself. An unreviewed helper or a
# silently omitted validator is a hard failure.
EXPECTED_MANIFEST_FILES = HUMAN_FILES + GENERATOR_FILES + (VALIDATOR_FILE,) + MACHINE_FILES + AUTHORITY_FILES + BOOTSTRAP_FILES
EXPECTED_PACKAGE_FILES = EXPECTED_MANIFEST_FILES + ("V30_PACKAGE_MANIFEST.json",)

CARD_RE = re.compile(
    r"^\|\s*(\d+)\s*\|\s*(V30-P\d{2}-C\d{2})\s+—\s*(.*?)\s*\|\s*"
    r"([A-Z_]+)\s*\|\s*\[([^\]]*)\]\s*\|"
)
APPENDIX_RE = re.compile(
    r"^\|\s*(\d+)\s*\|.*?\|\s*"
    r"(INCORPORATED_WITH_PROVENANCE|REJECTED_WITH_RATIONALE|DEFERRED_UNCHANGED)\s*\|"
)
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
CARD_ID_RE = re.compile(r"^V30-P\d{2}-C\d{2}$")
VALID_CLASSES = {
    "FOUNDATION",
    "IMPLEMENTATION",
    "VERIFICATION",
    "INTEGRATION",
    "OWNER_ACTION",
    "VALIDATE_NEXT",
    "DEFER",
    "MONITOR",
}
EXPECTED_CLASS_COUNTS = {
    "FOUNDATION": 11,
    "IMPLEMENTATION": 26,
    "VERIFICATION": 7,
    "INTEGRATION": 5,
    "OWNER_ACTION": 3,
    "VALIDATE_NEXT": 1,
    "DEFER": 1,
    "MONITOR": 1,
}
EXPECTED_LOCALES = ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
EXPECTED_NEXT_WAVE = ["pt-BR", "fil", "ar", "fr", "fr-CA", "ru", "pl", "hi", "id", "ja", "tr", "ht"]
EXPECTED_V24_SHA = "370c378bbb3b567c465d217111e8de3342581916e260b234a32511e807c01d94"
EXPECTED_V23_HEAD = "acbfb68355f903fe98638b6ef22e4814e7b48328"
EXPECTED_V23_TREE = "47e17fae6b73dccd5029ccf4ac7cca659196f225"
EXPECTED_V23_PACKAGE_DIGEST = "99a2719885ad1abfb8cf5d49c6b2099754bb0ba4b5d27fcbae06476aad507570"
EXPECTED_COORD_HEAD = "51ef2b3d970a25b4c83df8c8238609316e37034e"
EXPECTED_COORD_TREE = "060c83c3d1489fc011b1c921f6c85bec2b074478"
EXPECTED_COORD_SEQUENCE = 626
EXPECTED_COORD_LEDGER = "973090852e843e895125bea8da87c7e1689611c46d8219a70c1749be49398067"
EXPECTED_COORD_PROJECTION = "cf57849e8f7c245d38fd21a39da5938d10e13c9aca3976a71b7d3a3ee401f12d"
EXPECTED_S10_RESERVATION_RAW_SHA = "9f7c27431271728d167731d4af806c7449447dfbcc8bf46778102e2f9a89b576"
EXPECTED_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
EXPECTED_S10_PATH_COUNT = 86


class AuditError(RuntimeError):
    """A fail-closed package validation error."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AuditError(message)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def canonical_json_lf(value: Any) -> bytes:
    return canonical_json(value) + b"\n"


def digest_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def digest_json_lf(value: Any) -> str:
    return hashlib.sha256(canonical_json_lf(value)).hexdigest()


def load_text(path: Path) -> str:
    raw = path.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), f"{path.name}: UTF-8 BOM")
    require(b"\r" not in raw, f"{path.name}: CR/CRLF present")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AuditError(f"{path.name}: invalid UTF-8: {exc}") from exc
    require(text.endswith("\n"), f"{path.name}: missing final LF")
    require(all(line == line.rstrip(" \t") for line in text.splitlines()), f"{path.name}: trailing whitespace")
    return text


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(load_text(path))
    except json.JSONDecodeError as exc:
        raise AuditError(f"{path.name}: invalid JSON: {exc}") from exc
    require(isinstance(value, dict), f"{path.name}: top-level object required")
    return value


def require_hex(value: Any, label: str) -> str:
    require(isinstance(value, str) and HEX64_RE.fullmatch(value) is not None, f"{label}: SHA-256 hex required")
    return value


def require_string(value: Any, label: str) -> str:
    require(isinstance(value, str) and value != "", f"{label}: non-empty string required")
    require("<" not in value and ">" not in value, f"{label}: placeholder marker")
    return value


def require_string_list(value: Any, label: str, *, exact: list[str] | None = None) -> list[str]:
    require(isinstance(value, list), f"{label}: list required")
    require(all(isinstance(item, str) and item for item in value), f"{label}: string list required")
    require(all("<" not in item and ">" not in item for item in value), f"{label}: placeholder marker")
    if exact is not None:
        require(value == exact, f"{label}: expected {exact!r}, got {value!r}")
    return value


def section(text: str, start: str, end: str) -> str:
    start_index = text.find(start)
    require(start_index >= 0, f"missing section {start}")
    end_index = text.find(end, start_index + len(start))
    require(end_index >= 0, f"missing section {end}")
    return text[start_index:end_index]


def parse_cards(text: str) -> tuple[list[dict[str, Any]], set[tuple[str, str]]]:
    graph = section(text, "## 21. Closed 55-card graph", "## 22. Graph invariants and topological checks")
    rows: list[dict[str, Any]] = []
    for line in graph.splitlines():
        match = CARD_RE.match(line)
        if not match:
            continue
        deps = [item.strip() for item in match.group(5).split(",") if item.strip()]
        rows.append({
            "ordinal": int(match.group(1)),
            "cardID": match.group(2),
            "title": match.group(3),
            "class": match.group(4),
            "dependencies": deps,
        })

    require(len(rows) == 55, f"card count {len(rows)} != 55")
    require([row["ordinal"] for row in rows] == list(range(1, 56)), "bad ordinals")
    ids = [row["cardID"] for row in rows]
    require(len(set(ids)) == 55, "duplicate card ID")
    require(all(CARD_ID_RE.fullmatch(card_id) for card_id in ids), "malformed card ID")
    ordinal_by_id = {row["cardID"]: row["ordinal"] for row in rows}
    edge_pairs: set[tuple[str, str]] = set()
    for row in rows:
        require(row["class"] in VALID_CLASSES, f"bad class {row['class']}")
        for dep in row["dependencies"]:
            require(dep in ordinal_by_id, f"{row['cardID']}: unknown dependency {dep}")
            require(ordinal_by_id[dep] < row["ordinal"], f"{row['cardID']}: non-lower dependency {dep}")
            pair = (dep, row["cardID"])
            require(pair not in edge_pairs, f"duplicate edge {pair}")
            edge_pairs.add(pair)
    require(len(edge_pairs) == 107, f"edge count {len(edge_pairs)} != 107")

    counts = {key: 0 for key in VALID_CLASSES}
    for row in rows:
        counts[row["class"]] += 1
    require(counts == EXPECTED_CLASS_COUNTS, f"class counts differ: {counts}")

    incoming = {card_id: 0 for card_id in ids}
    outgoing: dict[str, list[str]] = {card_id: [] for card_id in ids}
    for dep, consumer in edge_pairs:
        outgoing[dep].append(consumer)
        incoming[consumer] += 1
    ready = [card_id for card_id in ids if incoming[card_id] == 0]
    visited = 0
    while ready:
        node = ready.pop()
        visited += 1
        for consumer in outgoing[node]:
            incoming[consumer] -= 1
            if incoming[consumer] == 0:
                ready.append(consumer)
    require(visited == 55, "graph cycle")
    return rows, edge_pairs


def validate_appendix(text: str, card_ids: set[str]) -> list[dict[str, Any]]:
    appendix = section(text, "## Appendix A — V24 normative-requirement disposition matrix", "### Appendix A.1 Deterministic machine projection")
    rows: list[dict[str, Any]] = []
    for line in appendix.splitlines():
        match = APPENDIX_RE.match(line)
        if match:
            rows.append({"ordinal": int(match.group(1)), "disposition": match.group(2), "line": line})
    require(len(rows) == 97, f"V24 disposition rows {len(rows)} != 97")
    require([row["ordinal"] for row in rows] == list(range(1, 98)), "V24 disposition ordinals")
    for row in rows:
        for target in re.findall(r"V30-(P\d{2}-C\d{2})", row["line"]):
            require(f"V30-{target}" in card_ids, f"Appendix row {row['ordinal']}: bad target {target}")
    return rows


def _manifest_records(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    files = manifest.get("files")
    require(isinstance(files, list), "manifest files list")
    records: list[dict[str, Any]] = []
    seen: set[str] = set()
    for record in files:
        require(isinstance(record, dict), "manifest file record object")
        relative = record.get("path")
        digest = record.get("sha256")
        byte_count = record.get("bytes")
        require(isinstance(relative, str) and relative, "manifest path")
        require("\\" not in relative and not relative.startswith(("/", "./")), f"manifest path form {relative}")
        require(".." not in Path(relative).parts, f"manifest path escape {relative}")
        require(relative in EXPECTED_MANIFEST_FILES, f"unreviewed manifest path {relative}")
        require(relative not in seen, f"duplicate manifest path {relative}")
        seen.add(relative)
        require(relative != MANIFEST.name, "manifest self-hash forbidden")
        require_hex(digest, f"manifest {relative} sha256")
        require(isinstance(byte_count, int) and byte_count >= 0, f"manifest {relative} bytes")
        path = ROOT / relative
        require(path.is_file(), f"missing manifest file {relative}")
        require(byte_count == path.stat().st_size, f"byte count mismatch {relative}")
        require(sha256(path) == digest, f"hash mismatch {relative}")
        records.append({"path": relative, "sha256": digest, "bytes": byte_count})
    require(set(seen) == set(EXPECTED_MANIFEST_FILES), "manifest file set mismatch")
    require([record["path"] for record in records] == sorted(seen), "manifest file order must be lexical")
    return records


def expected_install_map() -> dict[str, str]:
    """Return the reviewed source-to-install map used by P00 installation.

    The external authority owns the exact destination strings.  These are the
    canonical package projections emitted by the authority generator; no fresh
    task may infer a destination from a directory or a card range.
    """

    mapping: dict[str, str] = {
        "EXPANSION_V30_FOUNDATION_PLAN.md": "docs/design/v30/EXPANSION_V30_FOUNDATION_PLAN.md",
        "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md": "docs/design/v30/EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md",
        "EXPANSION_V30_HANDOFF.md": "docs/design/v30/EXPANSION_V30_HANDOFF.md",
        "NEXT_CODEX_SESSION_PROMPT.md": "docs/design/v30/NEXT_CODEX_SESSION_PROMPT.md",
        "V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json": "docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json",
        "V30_PACKAGE_MANIFEST.json": "docs/design/v30/authority/V30PackageManifestV1.json",
        "V30_CARD_REGISTER.json": "docs/design/v30/authority/V30CardRegisterV1.json",
        "V30_DIRECT_DEPENDENCY_GRAPH.json": "docs/design/v30/authority/V30DirectDependencyGraphV1.json",
        "V30_LOCALE_REGISTRY.json": "docs/design/v30/authority/V30LocaleRegistryV1.json",
        "V30_V24_DISPOSITION_PROJECTION.json": "docs/design/v30/authority/V30V24DispositionProjectionV1.json",
        "V30_PRE_S10_PATH_FENCES.json": "docs/design/v30/authority/V30PreS10PathFencesV1.json",
    }
    for name in GENERATOR_FILES + (VALIDATOR_FILE,):
        mapping[name] = f"Scripts/v30/{name}"
    for name in BOOTSTRAP_FILES:
        # These are inert external support copies. G3 alone materializes active
        # current-task/selector/ledger projections under the execution namespace.
        mapping[name] = f"docs/design/v30/authority/bootstrap/{name}"
    return mapping


def validate_source_install_records(raw: Any, label: str) -> dict[str, str]:
    require(isinstance(raw, list), f"{label} list")
    actual: dict[str, str] = {}
    for record in raw:
        require(isinstance(record, dict) and set(record) == {"source", "installPath"}, f"{label} record object")
        source = record.get("source")
        destination = record.get("installPath")
        require(isinstance(source, str) and source in EXPECTED_PACKAGE_FILES, f"{label} source {source!r}")
        require(source not in actual, f"duplicate {label} source {source}")
        require(isinstance(destination, str) and destination, f"{label} destination {source}")
        require("\\" not in destination and ".." not in Path(destination).parts, f"{label} destination path form {destination}")
        require(not destination.startswith(("/", "./")), f"{label} destination path root {destination}")
        actual[source] = destination
    require(set(actual) == set(EXPECTED_PACKAGE_FILES), f"{label} source set mismatch")
    require(len({*actual.values()}) == len(actual), f"{label} duplicate destination")
    return actual


def validate_source_to_install_map(manifest: dict[str, Any]) -> None:
    actual = validate_source_install_records(manifest.get("sourceToInstallMap"), "manifest sourceToInstallMap")
    require(actual == expected_install_map(), "manifest sourceToInstallMap mismatch")


def validate_manifest() -> tuple[dict[str, Any], list[dict[str, Any]]]:
    manifest = load_json(MANIFEST)
    require(manifest.get("schema") == "V30PackageManifestV1", "manifest schema")
    require(manifest.get("schemaVersion") == 1, "manifest schemaVersion")
    require(manifest.get("packageRevision") == "R2", "manifest package revision")
    require(manifest.get("digestScheme") == "V30CanonicalJSONSHA256LFV1", "manifest digest scheme")
    require_string(manifest.get("authorityID"), "manifest authorityID")
    require_hex(manifest.get("authorityContentDigest"), "manifest authority content digest")
    repository = manifest.get("repository")
    require(repository == {"name": "AssetRounds", "remoteURL": "https://github.com/Asset-Rounds/AssetRounds.git"}, "manifest repository")
    frozen_v23 = manifest.get("frozenV23")
    require(frozen_v23 == {"head": EXPECTED_V23_HEAD, "tree": EXPECTED_V23_TREE}, "manifest V23 binding")
    frozen_coordination = manifest.get("frozenCoordination")
    require(frozen_coordination == {"head": EXPECTED_COORD_HEAD, "tree": EXPECTED_COORD_TREE, "sequence": EXPECTED_COORD_SEQUENCE}, "manifest coordination binding")
    require(manifest.get("cardCount") == 55, "manifest cardCount")
    require(manifest.get("edgeCount") == 107, "manifest edgeCount")
    require(manifest.get("initialLocaleCount") == 6, "manifest initialLocaleCount")
    require(manifest.get("v24DispositionCount") == 97, "manifest v24DispositionCount")
    require_hex(manifest.get("packageDigest"), "manifest packageDigest")
    records = _manifest_records(manifest)
    expected_digest_input = [{key: record[key] for key in ("path", "sha256", "bytes")} for record in records]
    require(manifest["packageDigest"] == digest_json_lf(expected_digest_input), "manifest packageDigest")
    human_records = [record for record in records if record["path"] in HUMAN_FILES]
    structural_records = [
        record for record in records
        if record["path"] in {
            "V30_CARD_REGISTER.json",
            "V30_DIRECT_DEPENDENCY_GRAPH.json",
            "V30_LOCALE_REGISTRY.json",
            "V30_V24_DISPOSITION_PROJECTION.json",
        }
    ]
    require(len(human_records) == len(HUMAN_FILES), "manifest human projection record count")
    require(len(structural_records) == 4, "manifest structural projection record count")
    require_hex(manifest.get("humanPackageDigest"), "manifest humanPackageDigest")
    require_hex(manifest.get("structuralProjectionDigest"), "manifest structuralProjectionDigest")
    require(manifest["humanPackageDigest"] == digest_json_lf(human_records), "manifest humanPackageDigest")
    require(manifest["structuralProjectionDigest"] == digest_json_lf(structural_records), "manifest structuralProjectionDigest")
    validate_source_to_install_map(manifest)
    return manifest, records


def _require_exact_fields(value: dict[str, Any], fields: Iterable[str], label: str) -> None:
    missing = [field for field in fields if field not in value]
    require(not missing, f"{label}: missing fields {missing}")


def validate_authority(manifest: dict[str, Any]) -> dict[str, Any]:
    authority = load_json(AUTH)
    require(authority.get("schema") == "V30PreS10ProvisionalImplementationAuthorityV1", "authority schema")
    require(authority.get("schemaVersion") == 1, "authority schemaVersion")
    require(authority.get("digestScheme") == "V30CanonicalJSONSHA256LFV1", "authority digest scheme")
    identity = authority.get("authority")
    require(isinstance(identity, dict), "authority identity")
    authority_id = require_string(identity.get("id"), "authority id")
    require(authority.get("authorityID") == authority_id, "top-level authority ID")
    require(authority_id == manifest.get("authorityID"), "manifest authority ID")
    require(authority.get("installationRequestID") == authority_id + "/INSTALL", "installation request ID")
    require(authority.get("bootstrapRequestIDs") == {
        "installation": authority_id + "/INSTALL",
        "coordinationGenesis": authority_id + "/G3-GENESIS",
        "activationReceipt": authority_id + "/G3-ACTIVATION",
        "productSelectionProjection": authority_id + "/G3-PROJECTIONS",
        "cardSelection": authority_id + "/G3-SELECT-CARD-001",
    }, "bootstrap request IDs")
    require(identity.get("activation") == "OWNER_USER_MESSAGE_REQUIRED_AT_ACTIVATION", "authority activation")
    require("owner" in identity.get("ownerInvocationRule", "").lower(), "authority owner invocation")
    require("V30PostS10ReconciliationAuthorityV1" in identity.get("postS10Requirement", ""), "post-S10 authority name")
    content_digest = require_hex(authority.get("authorityContentDigest"), "authorityContentDigest")
    digest_payload = dict(authority)
    digest_payload.pop("authorityContentDigest", None)
    require(content_digest == digest_json_lf(digest_payload), "authorityContentDigest")
    require(manifest.get("authorityContentDigest") == content_digest, "manifest/authority content digest")

    repository = authority.get("repository")
    require(isinstance(repository, dict), "authority repository")
    require(repository.get("name") == "AssetRounds", "repository name")
    require(repository.get("remoteURL") == "https://github.com/Asset-Rounds/AssetRounds.git", "repository remote")

    frozen = authority.get("frozenV23")
    require(isinstance(frozen, dict), "frozenV23")
    require(frozen.get("worktree") == r"C:\AssetRounds-v23-expansion", "V23 worktree")
    require(frozen.get("branch") == "phase/v23-expansion", "V23 branch")
    require(frozen.get("head") == EXPECTED_V23_HEAD, "V23 head")
    require(frozen.get("tree") == EXPECTED_V23_TREE, "V23 tree")
    require(frozen.get("packageDigest") == EXPECTED_V23_PACKAGE_DIGEST, "V23 package digest")
    require(frozen.get("cardCount") == 146 and frozen.get("edgeCount") == 230, "V23 graph counts")
    require(frozen.get("unfinishedCards") == [135, 136, 141, 146], "V23 unfinished cards")

    coordination = authority.get("frozenCoordination")
    require(isinstance(coordination, dict), "frozen coordination")
    require(coordination.get("worktree") == r"C:\AssetRounds-v23-coordination", "coordination worktree")
    require(coordination.get("branch") == "main", "coordination branch")
    require(coordination.get("remoteURL") == "https://github.com/Asset-Rounds/AssetRounds-v23-coordination.git", "coordination remote")
    require(coordination.get("head") == EXPECTED_COORD_HEAD, "coordination head")
    require(coordination.get("tree") == EXPECTED_COORD_TREE, "coordination tree")
    require(coordination.get("sequence") == EXPECTED_COORD_SEQUENCE, "coordination sequence")
    require(coordination.get("ledgerDigest") == EXPECTED_COORD_LEDGER, "coordination ledger")
    require(coordination.get("projectionDigest") == EXPECTED_COORD_PROJECTION, "coordination projection")
    require(coordination.get("readOnly") is True, "coordination read-only")

    isolation = authority.get("phase10Isolation")
    require(isinstance(isolation, dict), "phase10Isolation")
    require(isolation.get("forbiddenWorktree") == r"C:\AssetRounds", "forbidden worktree")
    require(isolation.get("mode") == "NO_READ_NO_WRITE_NO_POLL", "isolation mode")
    operations = require_string_list(isolation.get("forbiddenOperations"), "Phase 10 forbidden operations")
    require(set(operations) == {"read", "enumerate", "status", "diff", "log", "build", "test", "fetch", "poll", "process", "mutate"}, "Phase 10 forbidden operation set")
    require(isolation.get("reservationArtifact") == r"C:\AssetRounds-v23-expansion\docs\design\v23\foundation\ActiveS10OwnershipReservationV1.json", "reservation path")
    require(isolation.get("reservationRawSHA256") == EXPECTED_S10_RESERVATION_RAW_SHA, "reservation raw SHA")
    require(isolation.get("reservedPathsDigest") == EXPECTED_S10_RESERVATION_DIGEST, "reservation digest")
    require(isolation.get("reservedPathCount") == EXPECTED_S10_PATH_COUNT, "reserved path count")
    reserved = require_string_list(isolation.get("reservedPaths"), "reserved paths")
    require(len(reserved) == EXPECTED_S10_PATH_COUNT and len(set(reserved)) == EXPECTED_S10_PATH_COUNT, "reserved paths uniqueness")
    require(all(not item.startswith(("C:\\", "/", "..")) for item in reserved), "reserved path must be repository-relative")

    execution = authority.get("provisionalExecution")
    require(isinstance(execution, dict), "provisionalExecution")
    require(execution.get("branch") == "phase/v30-globalization", "V30 branch")
    require(execution.get("worktree") == r"C:\AssetRounds-v30-globalization", "V30 worktree")
    require(execution.get("baseHead") == EXPECTED_V23_HEAD and execution.get("baseTree") == EXPECTED_V23_TREE, "V30 base")
    require(execution.get("plannedPreS10OrdinalRange") == [1, 37], "planned pre-S10 range")
    require(execution.get("eligibleOrdinalRange") == [1, 37], "eligible range")
    require(execution.get("postS10LockedOrdinalRange") == [38, 55], "locked range")
    require(execution.get("initialCard") == "V30-P00-C01", "initial card")
    require(execution.get("terminalPreS10State") == "PROVISIONAL_CHECKPOINTED", "terminal pre-S10 state")
    require("only" in execution.get("cardSelectionLaw", "").lower() and "conflict_hold" in execution.get("cardSelectionLaw", "").lower(), "card selection law")
    allowed_git = require_string_list(execution.get("allowedGitOperations"), "allowed Git operations")
    require("non-force-push-only-phase-v30-globalization" in allowed_git, "non-force push operation")
    forbidden_git = require_string_list(execution.get("forbiddenGitOperations"), "forbidden Git operations")
    require(set(forbidden_git) >= {"main-mutation", "phase10-ref-mutation", "v23-ref-mutation", "force-push", "merge-commit", "wholesale-merge", "history-rewrite"}, "forbidden Git operation set")
    require(all("force" not in item.lower() or item.lower() == "non-force-push-only-phase-v30-globalization" for item in allowed_git), "force Git operation")

    ci = authority.get("ci")
    require(isinstance(ci, dict), "authority CI")
    require(ci.get("route") == "TASK_NAMED_GITHUB_ACTIONS_MACOS_ONLY", "authority CI route")
    require(ci.get("preS10IsDevelopmentEvidence") is True and ci.get("preS10IsAcceptance") is False, "authority CI provisional status")
    require(ci.get("selectionMustBePinned") is True and ci.get("hostedDispatchBeforeRoutePinned") is False, "authority CI selector law")
    require(ci.get("workflowPath") == ".github/workflows/ios-ci.yml", "authority CI workflow path")
    require(ci.get("branchRef") == "refs/heads/phase/v30-globalization", "authority CI branch ref")
    require(ci.get("selectorPath") == "docs/design/v30/execution/V30_CI_SELECTION.json", "authority CI selector path")
    require(ci.get("selectorObjectKey") == "selector", "authority CI selector object key")
    require(ci.get("routeHydrationCard") == "V30-P00-C05", "authority CI route hydration card")
    require(ci.get("isolatedRouteWriterPaths") == [
        ".github/workflows/ios-ci.yml",
        "Scripts/test-smoke.sh",
        "Scripts/ui-smoke.sh",
    ], "authority CI isolated route writer paths")
    require(ci.get("inheritedSelectorReadOnly") == "Scripts/ci-selection.json", "authority CI inherited selector")
    require(ci.get("optionalPreS10Diagnostics") is True, "authority CI optional diagnostics")
    route_law = require_string(ci.get("routeLaw"), "authority CI route law")
    route_law_lower = route_law.lower()
    require("only card 5" in route_law_lower and "three pre-issued frozen-b" in route_law_lower, "authority CI route law scope")
    require("v30 typed selector" in route_law_lower and "phase 10" in route_law_lower, "authority CI route law isolation")
    require("final acceptance" in route_law_lower, "authority CI route law credit")
    unavailable_route = require_string(ci.get("unavailableRouteDisposition"), "authority CI unavailable route disposition")
    unavailable_lower = unavailable_route.lower()
    require("not_executed_no_native_credit" in unavailable_lower and "final native qualification" in unavailable_lower, "authority CI unavailable route law")

    require("provisionalCoordination" not in authority and "executionProjections" not in authority, "legacy authority field")
    ledger = authority.get("provisionalLedger")
    require(isinstance(ledger, dict), "provisionalLedger")
    _require_exact_fields(
        ledger,
        (
            "namespace", "locator", "externalWorktree", "externalRef", "expectedAtActivation", "expectedOldRef",
            "singleWriter", "compareAndSwap", "canonicalCoordinationWrite", "genesisImportsSequence", "casSequence",
            "ledgerID", "requestIDNamespace", "initialWriterGeneration", "initialSequence", "refCreationExpectedOld",
            "genesisExpectedOldRef", "genesisExpectedLedger", "bootstrapRefLaw", "bootstrapAllowedPaths",
            "runtimeMutablePaths", "activationReceiptPath", "cardSelectionReceiptPath", "receiptLaw", "eventLaw",
        ),
        "provisionalLedger",
    )
    require(ledger.get("namespace") == "V30PreS10ProvisionalLedgerV1", "provisional ledger namespace")
    require_string(ledger.get("locator"), "provisional ledger locator")
    require(ledger.get("externalWorktree") == r"C:\AssetRounds-v30-globalization-coordination", "provisional ledger worktree")
    require(ledger.get("externalRef") == "refs/heads/coord/v30-globalization-provisional", "provisional ledger ref")
    require(ledger.get("expectedAtActivation") == "ABSENT", "provisional ledger expected-at-activation")
    require(ledger.get("expectedOldRef") == "ABSENT", "provisional ledger expected old ref")
    require(ledger.get("singleWriter") is True, "provisional ledger single writer")
    require(ledger.get("compareAndSwap") is True, "provisional ledger CAS")
    require(ledger.get("canonicalCoordinationWrite") is False, "canonical V23 coordination must remain read-only")
    require(ledger.get("provisionalCoordinationWrite") is True, "isolated provisional coordination write")
    require(ledger.get("canonicalMainUntouched") is True, "canonical coordination main untouched")
    require(ledger.get("baseHead") == EXPECTED_COORD_HEAD and ledger.get("baseTree") == EXPECTED_COORD_TREE, "provisional coordination base")
    require(ledger.get("remoteURL") == "https://github.com/Asset-Rounds/AssetRounds-v23-coordination.git", "provisional coordination remote")
    require(ledger.get("genesisImportsSequence") == EXPECTED_COORD_SEQUENCE, "provisional ledger predecessor sequence")
    require(ledger.get("expectedSequence") == "ABSENT" and ledger.get("expectedLedgerDigest") == "ABSENT" and ledger.get("expectedProjectionDigest") == "ABSENT", "provisional ledger expected-absent values")
    require(ledger.get("casSequence") == ["G3_COORDINATION_GENESIS_EXPECTED_ABSENT", "G3_ACTIVATION_RECEIPT_APPEND", "G3_PRODUCT_SELECTION_PROJECTION_COMMIT_EXPECTED_OLD_PRODUCT_REF", "G3_LATER_COORDINATION_CARD_1_SELECTION_BINDING_PRODUCT_PROJECTION_COMMIT"], "provisional ledger CAS sequence")
    require(ledger.get("g3ProductMaterializationCount") == 6, "G3 product projection count")
    require(ledger.get("ledgerID") == authority_id + "/PROVISIONAL-LEDGER", "provisional ledger ID")
    require(ledger.get("requestIDNamespace") == authority_id, "provisional ledger request namespace")
    require(ledger.get("initialWriterGeneration") == 1 and ledger.get("initialSequence") == 0, "provisional ledger initial state")
    require(ledger.get("refCreationExpectedOld") == "ABSENT", "provisional ledger ref creation expected old")
    require(ledger.get("genesisExpectedOldRef") == EXPECTED_COORD_HEAD, "provisional ledger genesis expected old ref")
    require(ledger.get("genesisExpectedLedger") == "ABSENT", "provisional ledger genesis expected ledger")
    expected_bootstrap_paths = [
        "docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json",
        "docs/design/v30/execution/receipts/V30_G3_ACTIVATION_RECEIPT.json",
        "docs/design/v30/execution/receipts/V30_G3_CARD_001_SELECTION_RECEIPT.json",
    ]
    require(ledger.get("bootstrapAllowedPaths") == expected_bootstrap_paths, "provisional ledger bootstrap paths")
    require(ledger.get("runtimeMutablePaths") == [expected_bootstrap_paths[0]], "provisional ledger runtime mutable paths")
    require(ledger.get("activationReceiptPath") == expected_bootstrap_paths[1], "provisional ledger activation receipt path")
    require(ledger.get("cardSelectionReceiptPath") == expected_bootstrap_paths[2], "provisional ledger card selection receipt path")
    bootstrap_ref_law = require_string(ledger.get("bootstrapRefLaw"), "provisional ledger bootstrap ref law")
    require("expected-absent" in bootstrap_ref_law.lower() and "frozen coordination head" in bootstrap_ref_law.lower(), "provisional ledger bootstrap ref law semantics")
    receipt_law = require_string(ledger.get("receiptLaw"), "provisional ledger receipt law")
    require("append-only" in receipt_law.lower() and "request id" in receipt_law.lower(), "provisional ledger receipt law semantics")
    event_law = require_string(ledger.get("eventLaw"), "provisional ledger event law")
    require("request" in event_law.lower() and "mismatch" in event_law.lower(), "provisional ledger event law semantics")

    ordering = authority.get("ordering")
    require(isinstance(ordering, dict), "authority ordering")
    require(ordering.get("cardRange") == [1, 55], "authority card range")
    require(ordering.get("preS10ExecutableRange") == [1, 37], "authority executable range")
    require(ordering.get("postS10RequiresExternalAuthority") is True, "authority post-S10 ordering")
    require(ordering.get("skipCards") is False and ordering.get("reorderCards") is False, "authority ordering law")
    require(ordering.get("samePhaseAutopilot") is True, "authority same-phase autopilot")
    require("immediate graph successor" in ordering.get("samePhaseAutopilotLaw", "").lower(), "authority successor law")

    current_task = authority.get("currentTask")
    require(isinstance(current_task, dict), "currentTask")
    _require_exact_fields(current_task, ("path", "selectorPath", "handoffPath", "inheritedPaths", "initialCardID"), "currentTask")
    require(current_task.get("path") == "docs/design/v30/execution/V30_CURRENT_TASK.md", "V30 current-task path")
    require(current_task.get("selectorPath") == "docs/design/v30/execution/V30_CI_SELECTION.json", "V30 selector path")
    require(current_task.get("handoffPath") == "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md", "V30 handoff path")
    require(current_task.get("inheritedPaths") == ["docs/execution/CURRENT_TASK.md", "docs/product/BUILD_PLAN_V4.md", "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md"], "V30 inherited paths")
    require(current_task.get("initialCardID") == "V30-P00-C01", "V30 initial card")
    for path in (current_task["path"], current_task["selectorPath"], current_task["handoffPath"]):
        _expanded_repo_path(path, "currentTask path")

    shared_rule = authority.get("sharedPathRule")
    require(isinstance(shared_rule, dict), "shared path rule")
    require(shared_rule.get("tupleSchema") == ["cardID", "path", "expectedBBlobOID", "expectedBSHA256", "boundedPurpose", "writerLane", "reconciliationObligation"], "shared tuple schema")
    require(shared_rule.get("proseCannotExpandAuthority") is True, "shared prose authority")
    require(shared_rule.get("unfencedOrUntupledDisposition") == "CONFLICT_HOLD", "shared conflict disposition")
    require(shared_rule.get("preS10FinalCreditForSharedPath") is False, "shared path credit")

    post_s10 = authority.get("postS10Reconciliation")
    require(isinstance(post_s10, dict), "postS10Reconciliation")
    require(post_s10.get("requiredAuthoritySchema") == "V30PostS10ReconciliationAuthorityV1", "post-S10 schema")
    require(post_s10.get("branch") == "phase/v30-globalization-reconciliation", "reconciliation branch")
    require(post_s10.get("worktree") == r"C:\AssetRounds-v30-globalization-reconciliation", "reconciliation worktree")
    require(post_s10.get("sourceLineages") == ["B=frozen-v23", "P=frozen-terminal-provisional-v30", "S=accepted-post-phase10-v23-main"], "reconciliation lineages")
    require(post_s10.get("requiresExternalAuthority") is True, "reconciliation external authority")
    require(post_s10.get("wholesaleProvisionalMerge") is False, "wholesale merge law")
    require(post_s10.get("replayCardRange") == [1, 37], "reconciliation replay range")
    require_string(post_s10.get("trigger"), "reconciliation trigger")
    require("phase 10.6" in post_s10["trigger"].lower() or "phase_10_6" in post_s10["trigger"].lower(), "reconciliation trigger semantics")
    require_string(post_s10.get("selectableAfterTrigger"), "reconciliation next selectable card")
    require("lineages" not in post_s10 and "wholesaleMergeForbidden" not in post_s10, "legacy reconciliation field")

    credit = authority.get("creditPolicy")
    require(isinstance(credit, dict), "credit policy")
    for key in ("preS10FinalCredit", "provisionalCIIsAcceptance", "canonicalAcceptance", "postS10Credit", "mainMutationBeforeP07C01"):
        require(credit.get(key) is False, f"credit policy {key}")

    source_map = validate_source_install_records(authority.get("sourceToInstallMap"), "authority sourceToInstallMap")
    require(set(source_map) == set(EXPECTED_PACKAGE_FILES), "authority sourceToInstallMap file set")
    require("materializationMap" not in authority, "ambiguous legacy materialization map")
    require(manifest.get("sourceToInstallMap") == authority.get("sourceToInstallMap"), "manifest/authority sourceToInstallMap mismatch")

    require("supportArtifactHashes" not in authority, "legacy support artifact field")
    core = authority.get("coreArtifactHashes")
    require(isinstance(core, list), "coreArtifactHashes list")
    core_names = ("EXPANSION_V30_FOUNDATION_PLAN.md", "EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md", "EXPANSION_V30_HANDOFF.md", *MACHINE_FILES, *GENERATOR_FILES, VALIDATOR_FILE)
    require([item.get("source") for item in core if isinstance(item, dict)] == list(core_names), "core artifact source order")
    require(len(core) == len(core_names), "core artifact count")
    for item, name in zip(core, core_names):
        require(isinstance(item, dict) and set(item) == {"source", "sha256", "bytes"}, f"core artifact record {name}")
        require(item.get("source") == name, f"core artifact source {name}")
        require_hex(item.get("sha256"), f"core artifact {name} SHA")
        require(isinstance(item.get("bytes"), int) and item["bytes"] >= 0, f"core artifact {name} bytes")
        path = ROOT / name
        require(path.is_file(), f"core artifact missing {name}")
        require(item["sha256"] == sha256(path) and item["bytes"] == path.stat().st_size, f"core artifact binding {name}")

    fence_authority = authority.get("pathFenceAuthority")
    require(isinstance(fence_authority, dict), "pathFenceAuthority")
    require(fence_authority.get("sourcePath") == "V30_PRE_S10_PATH_FENCES.json", "path-fence authority source")
    require_hex(fence_authority.get("sha256"), "path-fence authority SHA")
    require(fence_authority.get("cardCount") == 37, "path-fence authority card count")
    require(fence_authority.get("proseOrCardCannotExpandOverlap") is True, "path-fence authority prose law")
    tuples = fence_authority.get("s10SharedReconciliationTuples")
    require(isinstance(tuples, list), "path-fence authority tuples")
    tuple_keys = {"boundedPurpose", "cardID", "expectedBBlobOID", "expectedBSHA256", "path", "reconciliationObligation", "writerLane"}
    for index, tuple_record in enumerate(tuples):
        require(isinstance(tuple_record, dict) and set(tuple_record) == tuple_keys, f"authority tuple {index}")
        require(CARD_ID_RE.fullmatch(tuple_record["cardID"]) is not None, f"authority tuple card {index}")
        _expanded_repo_path(tuple_record["path"], f"authority tuple path {index}")
        require(isinstance(tuple_record["expectedBBlobOID"], str) and re.fullmatch(r"[0-9a-f]{40}", tuple_record["expectedBBlobOID"]) is not None, f"authority tuple blob {index}")
        require_hex(tuple_record["expectedBSHA256"], f"authority tuple SHA {index}")
        for key in ("boundedPurpose", "writerLane", "reconciliationObligation"):
            require_string(tuple_record.get(key), f"authority tuple {key} {index}")
    require("s10SharedReconciliationTuples" not in authority, "legacy top-level S10 tuples")

    bootstrap = authority.get("bootstrapMaterializationMap")
    require(isinstance(bootstrap, dict), "bootstrapMaterializationMap")
    require(set(bootstrap) == set(BOOTSTRAP_FILES), "bootstrap materialization source set")
    expected_active = {
        "V30_CARD_001_CONTEXT.json": ("docs/design/v30/execution/contexts/V30-P00-C01-attempt-1.json", "PRODUCT_BRANCH"),
        "V30_CARD_001_FENCE.json": ("docs/design/v30/execution/fences/V30-P00-C01-attempt-1.json", "PRODUCT_BRANCH"),
        "V30_CARD_001_CURRENT_TASK.md": ("docs/design/v30/execution/V30_CURRENT_TASK.md", "PRODUCT_BRANCH"),
        "V30_CARD_001_CI_SELECTION.json": ("docs/design/v30/execution/V30_CI_SELECTION.json", "PRODUCT_BRANCH"),
        "V30_EXECUTION_HANDOFF_GENESIS.md": ("docs/design/v30/execution/V30_EXECUTION_HANDOFF.md", "PRODUCT_BRANCH"),
        "V30_PROVISIONAL_LEDGER_PROJECTION.json": ("docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json", "PRODUCT_BRANCH"),
        "V30_PROVISIONAL_LEDGER_GENESIS.json": ("refs/heads/coord/v30-globalization-provisional:docs/design/v30/execution/V30_PROVISIONAL_LEDGER.json", "SEPARATE_COORDINATION_REPOSITORY"),
    }
    for name, expected in expected_active.items():
        item = bootstrap.get(name)
        require(isinstance(item, dict) and set(item) == {"installedSource", "materializedPath", "target"}, f"bootstrap materialization record {name}")
        require(item.get("installedSource") == source_map[name], f"bootstrap installed source {name}")
        require((item.get("materializedPath"), item.get("target")) == expected, f"bootstrap materialization target {name}")
    require(bootstrap != source_map, "bootstrap map must remain distinct from source map")
    return authority


def _register_card_values(register: dict[str, Any]) -> list[dict[str, Any]]:
    cards = register.get("cards")
    require(isinstance(cards, list), "card register cards list")
    require(len(cards) == 55, "card register count")
    return cards


def validate_card_register(card_rows: list[dict[str, Any]], edge_pairs: set[tuple[str, str]]) -> dict[str, Any]:
    register = load_json(CARD_REGISTER)
    require(register.get("schema") == "V30CardRegisterV1", "card register schema")
    require(register.get("cardCount") == 55 and register.get("edgeCount") == 107, "card register counts")
    source = register.get("source")
    require(isinstance(source, dict), "card register source")
    require(source.get("blueprintPath") == ARCH.name, "card register blueprint source")
    require(source.get("section") == "## 21. Closed 55-card graph", "card register source section")
    require(source.get("blueprintSha256") == sha256(ARCH), "card register blueprint SHA")
    cards = _register_card_values(register)
    by_id = {row["cardID"]: row for row in card_rows}
    require(len({card.get("cardID") for card in cards}) == 55, "card register duplicate IDs")
    for expected, actual in zip(card_rows, cards):
        require(isinstance(actual, dict), "card register row object")
        require(actual.get("ordinal") == expected["ordinal"], f"card register ordinal {expected['ordinal']}")
        require(actual.get("cardID") == expected["cardID"], f"card register ID {expected['ordinal']}")
        require(actual.get("title") == expected["title"], f"card register title {expected['cardID']}")
        require(actual.get("class") == expected["class"], f"card register class {expected['cardID']}")
        require(actual.get("directPrerequisites") == expected["dependencies"], f"card register prerequisites {expected['cardID']}")
        require_string(actual.get("outcome"), f"card register outcome {expected['cardID']}")
        ordinal = expected["ordinal"]
        expected_epoch = "PRE_S10_PROVISIONAL" if ordinal <= 37 else "POST_S10_RECONCILIATION" if ordinal <= 43 else "FINAL_ACCEPTANCE" if ordinal <= 50 else "POST_ACCEPTANCE"
        require(actual.get("executionEpoch") == expected_epoch, f"card register epoch {expected['cardID']}")
        if ordinal <= 37:
            require(actual.get("planningStatus") == "PRE_S10_PROVISIONAL_ELIGIBLE", f"card register planning status {expected['cardID']}")
        else:
            require(actual.get("planningStatus") == "POST_S10_NOT_SELECTABLE", f"card register planning status {expected['cardID']}")
        require(actual.get("preS10FinalCredit") is False, f"card register credit {expected['cardID']}")
    require(set(by_id) == {card["cardID"] for card in cards}, "card register key set")
    register_edges = register.get("edges")
    if register_edges is not None:
        require(isinstance(register_edges, list), "card register edges list")
        parsed = {(edge.get("from"), edge.get("to")) for edge in register_edges if isinstance(edge, dict)}
        require(parsed == edge_pairs and len(register_edges) == 107, "card register edges")
    return register


def validate_graph(edge_pairs: set[tuple[str, str]], card_rows: list[dict[str, Any]]) -> dict[str, Any]:
    graph = load_json(GRAPH)
    require(graph.get("schema") == "V30DirectDependencyGraphV1", "graph schema")
    require(graph.get("cardCount") == 55 and graph.get("edgeCount") == 107, "graph counts")
    source = graph.get("source")
    require(isinstance(source, dict), "graph source")
    require(source.get("blueprintPath") == ARCH.name, "graph blueprint source")
    require(source.get("section") == "## 21. Closed 55-card graph", "graph source section")
    require(source.get("blueprintSha256") == sha256(ARCH), "graph blueprint SHA")
    edges = graph.get("edges")
    require(isinstance(edges, list) and len(edges) == 107, "graph edges")
    parsed: list[tuple[str, str]] = []
    for edge in edges:
        require(isinstance(edge, dict), "graph edge object")
        source, target = edge.get("from"), edge.get("to")
        require(isinstance(source, str) and isinstance(target, str), "graph edge IDs")
        require((source, target) in edge_pairs, f"graph unbound edge {(source, target)}")
        parsed.append((source, target))
    require(len(set(parsed)) == 107 and set(parsed) == edge_pairs, "graph edge set")
    ids = [row["cardID"] for row in card_rows]
    # The graph artifact is an edge projection, not a second source of card
    # rows.  Derive the topological proof from its exact edge set so a stale
    # optional order/flag cannot mask a cycle or an unbound edge.
    incoming = {card_id: 0 for card_id in ids}
    outgoing: dict[str, list[str]] = {card_id: [] for card_id in ids}
    for source, target in parsed:
        require(source in incoming and target in incoming, f"graph unknown endpoint {(source, target)}")
        incoming[target] += 1
        outgoing[source].append(target)
    ready = [card_id for card_id in ids if incoming[card_id] == 0]
    topological: list[str] = []
    while ready:
        node = ready.pop()
        topological.append(node)
        for target in outgoing[node]:
            incoming[target] -= 1
            if incoming[target] == 0:
                ready.append(target)
    require(len(topological) == len(ids), "graph cycle")
    require(set(topological) == set(ids), "graph topological coverage")
    # The blueprint is the authoritative stable order.  Every edge must move
    # strictly forward in that order; this also rejects a graph that is merely
    # acyclic but disagrees with the closed card sequence.
    ordinal = {card_id: index for index, card_id in enumerate(ids)}
    require(all(ordinal[source] < ordinal[target] for source, target in parsed), "graph edge order")
    if "topologicalOrder" in graph:
        require(graph["topologicalOrder"] == ids, "graph topological order")
    if "acyclic" in graph:
        require(graph["acyclic"] is True, "graph acyclic flag")
    return graph


def validate_locales() -> dict[str, Any]:
    registry = load_json(LOCALE_REGISTRY)
    require(registry.get("schema") == "V30LocaleRegistryV1", "locale registry schema")
    require(registry.get("storefrontPolicy") == "UNITED_STATES_ONLY", "locale storefront policy")
    require(registry.get("projectJurisdiction") == "US", "locale jurisdiction")
    require(registry.get("storefrontCountries") == ["US"], "locale storefront countries")
    require(registry.get("completeBinaryLocalizationIDs") == EXPECTED_LOCALES, "complete locale cohort")
    initial_rows = registry.get("initialLocales")
    require(isinstance(initial_rows, list) and len(initial_rows) == 6, "initial locale rows")
    initial = []
    for row in initial_rows:
        require(isinstance(row, dict), "initial locale row")
        require_string(row.get("id"), "initial locale id")
        require_string_list(row.get("formattingProfiles"), f"formatting profiles {row['id']}")
        require_string(row.get("language"), f"locale language {row['id']}")
        require_string(row.get("metadataLanguage"), f"locale metadata language {row['id']}")
        require_string(row.get("script"), f"locale script {row['id']}")
        initial.append(row["id"])
    require(initial == EXPECTED_LOCALES, "initial locale cohort")
    require(registry.get("initialLocales") == initial_rows, "initial locale row stability")
    next_wave = require_string_list(registry.get("nextWaveLocaleIDs"), "next-wave locales")
    require(next_wave == EXPECTED_NEXT_WAVE, "next-wave locale order")
    require(registry.get("nextWaveOrder") == EXPECTED_NEXT_WAVE, "next-wave order")
    require(registry.get("nextWaveLocaleIDs") == EXPECTED_NEXT_WAVE, "next-wave IDs")
    require(registry.get("completeBinaryLocalizationIDs") == EXPECTED_LOCALES, "complete locale IDs")
    policy = registry.get("selectionPolicy")
    require(isinstance(policy, dict), "locale selection policy")
    require(policy.get("systemFirst") is True, "system-first locale policy")
    require(policy.get("applePreferredLanguages") is True and policy.get("applePerAppLanguage") is True, "Apple language policy")
    require(policy.get("defaultLanguage") == "en", "locale default language")
    require(policy.get("fallbackChain") == ["exactLocale", "baseLanguage", "en"], "fallback chain")
    require(policy.get("unsupportedLanguageFallback") == "en", "unsupported locale fallback")
    require(policy.get("inAppPicker") == "SETTINGS_DISCOVERY_ONLY", "in-app picker policy")
    require(policy.get("languageDoesNotSelectJurisdiction") is True and policy.get("regionDoesNotSelectLanguage") is True, "locale/jurisdiction separation")
    source = registry.get("source")
    require(isinstance(source, dict), "locale source")
    require(source.get("blueprintPath") == ARCH.name, "locale blueprint source")
    require(source.get("blueprintSha256") == sha256(ARCH), "locale blueprint SHA")
    return registry


def validate_v24_projection(card_ids: set[str]) -> dict[str, Any]:
    projection = load_json(V24_PROJECTION)
    require(projection.get("schema") == "V30V24DispositionProjectionV1", "V24 projection schema")
    require(projection.get("v24SourcePath") == r"C:\Users\palat\OneDrive\Desktop\ASSETROUNDS_V24_GLOBALIZATION_FOUNDATION_BLUEPRINT.md", "V24 source path")
    require(projection.get("v24SourceSha256") == EXPECTED_V24_SHA, "V24 source SHA")
    require(projection.get("recordCount") == 97, "V24 record count")
    records = projection.get("records")
    require(isinstance(records, list) and len(records) == 97, "V24 projection records")
    require(projection.get("noCredit") is True, "V24 noCredit")
    seen: set[int] = set()
    valid_dispositions = {"INCORPORATED_WITH_PROVENANCE", "REJECTED_WITH_RATIONALE", "DEFERRED_UNCHANGED"}
    for record in records:
        require(isinstance(record, dict), "V24 record object")
        ordinal = record.get("sourceOrdinal")
        require(isinstance(ordinal, int) and ordinal not in seen, "V24 record ordinal")
        seen.add(ordinal)
        require(1 <= ordinal <= 97, "V24 record ordinal range")
        require(record.get("disposition") in valid_dispositions, f"V24 disposition {ordinal}")
        require(record.get("noCredit") is True, f"V24 record noCredit {ordinal}")
        require_string(record.get("sourceAnchor"), f"V24 source anchor {ordinal}")
        require_string(record.get("canonicalRequirement"), f"V24 requirement {ordinal}")
        require_string(record.get("targetText"), f"V24 target {ordinal}")
        targets = record.get("v30Targets")
        require(isinstance(targets, list), f"V24 targets {ordinal}")
        for target in targets:
            require(isinstance(target, str) and target in card_ids, f"V24 target {ordinal}: {target}")
    require(seen == set(range(1, 98)), "V24 projection ordinal coverage")
    return projection


def _expanded_repo_path(value: Any, label: str) -> str:
    require(isinstance(value, str) and value, f"{label}: path required")
    require(not value.startswith(("/", "./")) and not value.endswith("/"), f"{label}: path root")
    require("\\" not in value and "//" not in value, f"{label}: path separator")
    require(not any(token in value for token in ("*", "?", "[", "]", "{", "}")), f"{label}: range/glob shorthand")
    require(".." not in Path(value).parts, f"{label}: path escape")
    return value


def validate_path_fences(card_rows: list[dict[str, Any]], authority: dict[str, Any]) -> dict[str, Any]:
    fences = load_json(ROOT / "V30_PRE_S10_PATH_FENCES.json")
    require(fences.get("schema") == "V30PreS10PathFencesV1", "path-fence schema")
    require(fences.get("schemaVersion") == 1, "path-fence schemaVersion")
    authority_id = authority["authority"]["id"]
    require(fences.get("authorityID") == authority_id, "path-fence authority ID")
    base = fences.get("base")
    require(isinstance(base, dict), "path-fence base")
    require(base.get("branch") == "phase/v23-expansion", "path-fence base branch")
    require(base.get("head") == EXPECTED_V23_HEAD and base.get("tree") == EXPECTED_V23_TREE, "path-fence base pin")
    require(base.get("worktree") == r"C:\AssetRounds-v23-expansion", "path-fence base worktree")
    cards = fences.get("cards")
    require(isinstance(cards, list) and len(cards) == 37, "path-fence card count")
    require(fences.get("cardCount") == 37, "path-fence declared card count")

    reserved = authority["phase10Isolation"]["reservedPaths"]
    require(isinstance(reserved, list) and len(reserved) == EXPECTED_S10_PATH_COUNT, "path-fence reservation input")
    forbidden_inherited = {
        "docs/execution/CURRENT_TASK.md",
        "docs/execution/HANDOFF.md",
        "Scripts/ci-selection.json",
    }
    common_execution = [
        "docs/design/v30/execution/V30_CURRENT_TASK.md",
        "docs/design/v30/execution/V30_CI_SELECTION.json",
        "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json",
        "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
    ]
    common_execution_set = set(common_execution)
    expected_writer_order = [row["cardID"] for row in card_rows[:37]]
    serialized = fences.get("serializedSharedPaths")
    require(isinstance(serialized, list) and serialized, "path-fence serialized shared paths")
    serialized_records: dict[str, dict[str, Any]] = {}
    serialized_paths: list[str] = []
    for index, item in enumerate(serialized):
        require(isinstance(item, dict), "path-fence serialized shared record")
        require(set(item) == {"path", "rationale", "writerLane", "writerOrder"}, "path-fence serialized shared fields")
        path = _expanded_repo_path(item.get("path"), f"path-fence serialized shared path {index}")
        require(path not in serialized_records, f"duplicate serialized shared path {path}")
        require(path not in forbidden_inherited, f"serialized inherited path {path}")
        rationale = require_string(item.get("rationale"), f"serialized rationale {path}")
        writer_lane = require_string(item.get("writerLane"), f"serialized writer lane {path}")
        writer_order = item.get("writerOrder")
        require(isinstance(writer_order, list) and writer_order, f"serialized writer order {path}")
        require(all(isinstance(card_id, str) and card_id in expected_writer_order for card_id in writer_order), f"serialized writer IDs {path}")
        require(len(set(writer_order)) == len(writer_order), f"serialized writer order duplicates {path}")
        ordinal_by_id = {card_id: ordinal for ordinal, card_id in enumerate(expected_writer_order, start=1)}
        require(writer_order == sorted(writer_order, key=ordinal_by_id.__getitem__), f"serialized writer order is not ordinal {path}")
        if path in common_execution_set:
            require(writer_lane == "V30_PROVISIONAL_SINGLE_WRITER", f"common execution writer lane {path}")
            require(writer_order == expected_writer_order, f"common execution writer order {path}")
        else:
            require(writer_lane == "V30-PRE-S10-ORDINAL-SERIALIZED-EXISTING-SEAM", f"product seam writer lane {path}")
            require(len(writer_order) >= 2, f"product seam must have multiple owners {path}")
            require(not path.startswith("docs/design/v30/execution/"), f"product seam in active V30 execution namespace {path}")
        serialized_records[path] = item
        serialized_paths.append(path)
    require(serialized_paths[: len(common_execution)] == common_execution, "common execution serialized order")
    require(set(serialized_paths[: len(common_execution)]) == common_execution_set, "common execution serialized set")
    product_serialized_paths = set(serialized_paths[len(common_execution):])
    require(serialized_paths[len(common_execution):] == sorted(product_serialized_paths), "product serialized path order")
    all_allowed: dict[str, list[str]] = {}
    existing_blobs: dict[str, tuple[str, str]] = {}
    path_classifications: dict[str, str] = {}
    path_records: dict[str, list[dict[str, Any]]] = {}
    for expected, card in zip(card_rows[:37], cards):
        require(isinstance(card, dict), "path-fence card object")
        for field in ("ordinal", "cardID", "title", "class", "directPrerequisites", "status", "allowedPaths", "s10SharedPaths", "preAuthorizedOverlapTuples"):
            require(field in card, f"path-fence {expected['cardID']}: missing {field}")
        require(card["ordinal"] == expected["ordinal"] and card["cardID"] == expected["cardID"], f"path-fence card identity {expected['cardID']}")
        require(card["title"] == expected["title"] and card["class"] == expected["class"], f"path-fence card metadata {expected['cardID']}")
        require(card["directPrerequisites"] == expected["dependencies"], f"path-fence prerequisites {expected['cardID']}")
        require(card["status"] == "PRE_S10_PROVISIONAL_ELIGIBLE", f"path-fence eligibility {expected['cardID']}")
        allowed = card["allowedPaths"]
        require(isinstance(allowed, list) and allowed, f"path-fence allowed paths {expected['cardID']}")
        seen_card: set[str] = set()
        for index, item in enumerate(allowed):
            require(isinstance(item, dict), f"path-fence record {expected['cardID']}[{index}]")
            require(set(item) == {"classification", "expectedBBlobOID", "expectedBSHA256", "path", "purpose", "serializedSharedPath"}, f"path-fence record fields {expected['cardID']}[{index}]")
            path = _expanded_repo_path(item["path"], f"path-fence {expected['cardID']}[{index}]")
            require(path not in seen_card, f"path-fence duplicate {expected['cardID']} {path}")
            require(path not in forbidden_inherited, f"path-fence inherited active path {path}")
            seen_card.add(path)
            all_allowed.setdefault(path, []).append(expected["cardID"])
            path_records.setdefault(path, []).append(item)
            require(isinstance(item["purpose"], str) and item["purpose"], f"path-fence purpose {path}")
            require(isinstance(item["serializedSharedPath"], bool), f"path-fence serialized flag {path}")
            classification = item["classification"]
            if classification == "EXPECTED_ABSENT_NEW_PATH":
                require(item["expectedBBlobOID"] is None and item["expectedBSHA256"] is None, f"path-fence absent binding {path}")
            elif classification == "EXISTING_BLOB":
                oid = item["expectedBBlobOID"]
                require(isinstance(oid, str) and re.fullmatch(r"[0-9a-f]{40}", oid) is not None, f"path-fence blob OID {path}")
                digest = require_hex(item["expectedBSHA256"], f"path-fence blob SHA {path}")
                previous = existing_blobs.get(path)
                require(previous is None or previous == (oid, digest), f"path-fence repeated frozen-B binding mismatch {path}")
                existing_blobs[path] = (oid, digest)
            else:
                raise AuditError(f"unknown path-fence classification {classification}")
            previous_classification = path_classifications.get(path)
            require(previous_classification is None or previous_classification == classification, f"path-fence repeated classification mismatch {path}")
            path_classifications[path] = classification
            expected_serialized = path in common_execution_set or path in product_serialized_paths
            if expected_serialized:
                require(item["serializedSharedPath"] is True, f"shared path not serialized {path}")
            else:
                require(item["serializedSharedPath"] is False, f"exclusive path marked shared {path}")
        shared_paths = card["s10SharedPaths"]
        require(isinstance(shared_paths, list), f"path-fence S10 paths {expected['cardID']}")
        require(all(isinstance(path, str) and path in seen_card for path in shared_paths), f"path-fence S10 path coverage {expected['cardID']}")
        require(set(shared_paths) == {path for path in seen_card if path in reserved}, f"path-fence reserved intersection {expected['cardID']}")
        tuples = card["preAuthorizedOverlapTuples"]
        require(isinstance(tuples, list), f"path-fence tuples {expected['cardID']}")
        tuple_keys = {"boundedPurpose", "cardID", "expectedBBlobOID", "expectedBSHA256", "path", "reconciliationObligation", "writerLane"}
        tuple_paths: set[str] = set()
        for tuple_record in tuples:
            require(isinstance(tuple_record, dict) and set(tuple_record) == tuple_keys, f"path-fence tuple fields {expected['cardID']}")
            tuple_path = _expanded_repo_path(tuple_record.get("path"), f"path-fence tuple path {expected['cardID']}")
            require(tuple_record.get("cardID") == expected["cardID"], f"path-fence tuple owner {expected['cardID']}")
            require(tuple_path in set(shared_paths), f"path-fence tuple not in shared paths {expected['cardID']}")
            require(tuple_path not in tuple_paths, f"path-fence duplicate tuple {expected['cardID']} {tuple_path}")
            tuple_paths.add(tuple_path)
            matching = next(item for item in allowed if item["path"] == tuple_path)
            require(matching["classification"] == "EXISTING_BLOB", f"path-fence tuple requires frozen B blob {tuple_path}")
            require(tuple_record["expectedBBlobOID"] == matching["expectedBBlobOID"], f"path-fence tuple B blob mismatch {tuple_path}")
            require(tuple_record["expectedBSHA256"] == matching["expectedBSHA256"], f"path-fence tuple B SHA mismatch {tuple_path}")
            require(all(isinstance(tuple_record[key], str) and tuple_record[key] for key in ("boundedPurpose", "writerLane", "reconciliationObligation")), f"path-fence tuple semantics {tuple_path}")
        require(tuple_paths == set(shared_paths), f"path-fence tuple coverage {expected['cardID']}")
        require([tuple_record["path"] for tuple_record in tuples] == shared_paths, f"path-fence tuple order {expected['cardID']}")

    conflict_hold_ids = [card["cardID"] for card in cards if card.get("status") == "CONFLICT_HOLD"]
    tuple_count = sum(len(card["preAuthorizedOverlapTuples"]) for card in cards)
    shared_path_count = sum(len(card["s10SharedPaths"]) for card in cards)
    per_card_counts = [
        {
            "cardID": card["cardID"],
            "existingBlobCount": sum(item["classification"] == "EXISTING_BLOB" for item in card["allowedPaths"]),
            "expectedAbsentNewPathCount": sum(item["classification"] == "EXPECTED_ABSENT_NEW_PATH" for item in card["allowedPaths"]),
            "s10SharedPathCount": len(card["s10SharedPaths"]),
        }
        for card in cards
    ]
    summary = fences.get("summary")
    require(summary == {
        "conflictHoldCardIDs": conflict_hold_ids,
        "executableCardCount": len(cards) - len(conflict_hold_ids),
        "perCardPathCounts": per_card_counts,
        "preAuthorizedOverlapTupleCount": tuple_count,
        "s10SharedPathCount": shared_path_count,
        "serializedExistingProductPathCount": len(product_serialized_paths),
        "uniqueAllowedPathCount": len(all_allowed),
    }, "path-fence summary")
    require(existing_blobs, "path-fence must bind at least one frozen B blob")
    literal_inventory = fences.get("frozenBTextBearingLiteralInventory")
    require(isinstance(literal_inventory, dict), "path-fence frozen-B literal inventory")
    require(literal_inventory.get("cardID") == "V30-P02-C01", "path-fence literal inventory card")
    require_string(literal_inventory.get("detectionBasis"), "path-fence literal inventory basis")
    inventory_paths = literal_inventory.get("paths")
    require(isinstance(inventory_paths, list) and inventory_paths, "path-fence literal inventory paths")
    normalized_inventory = [_expanded_repo_path(path, "path-fence literal inventory path") for path in inventory_paths]
    require(len(normalized_inventory) == len(set(normalized_inventory)), "path-fence literal inventory duplicates")
    require(literal_inventory.get("pathCount") == len(normalized_inventory), "path-fence literal inventory count")
    card_one = next(card for card in cards if card["cardID"] == "V30-P02-C01")
    card_one_paths = {item["path"] for item in card_one["allowedPaths"]}
    require(set(normalized_inventory).issubset(card_one_paths), "path-fence literal inventory not card-fenced")
    require(all(path_records[path][0]["classification"] == "EXISTING_BLOB" for path in normalized_inventory), "path-fence literal inventory must bind frozen B")
    actual_multi_owner_paths = {path for path, owners in all_allowed.items() if len(owners) > 1}
    require(common_execution_set.issubset(actual_multi_owner_paths), "common execution paths are not fully shared")
    actual_product_multi_owner_paths = actual_multi_owner_paths - common_execution_set
    require(actual_product_multi_owner_paths == product_serialized_paths, "serialized product seam coverage")
    ordinal_by_id = {card_id: ordinal for ordinal, card_id in enumerate(expected_writer_order, start=1)}
    ci_existing_b = {
        ".github/workflows/ios-ci.yml": ("bade6a6442bd77a6c15eaefa70726b1efc1b3c73", "bcd64e2a42752d28844435241b5abfca911d04190375cbbdbfc10b45acba97d7"),
        "Scripts/test-smoke.sh": ("25376fea96a73214ed0abe72d5a547def0ed8f3a", "0462448692b4b128e98a3ff4772b1c3dc14d7b5409be8743b9c39e435195c36b"),
        "Scripts/ui-smoke.sh": ("a1d29aeb3e4a10dcd518d0627af2b351a904481c", "6304a318ee046b6b19f4fddc43bb143f9b21e8150b9d332e449b87a0182d4cdb"),
    }
    for path, owners in all_allowed.items():
        if path.startswith(".github/"):
            require(path in {".github/workflows/ios-ci.yml"}, f"path-fence workflow outside Card 5 whitelist {path}")
        if path in ci_existing_b:
            require(owners == ["V30-P00-C05"], f"path-fence CI path owner {path}")
            records = path_records[path]
            require(all(item["classification"] == "EXISTING_BLOB" for item in records), f"path-fence CI path must bind frozen B {path}")
            require(all((item["expectedBBlobOID"], item["expectedBSHA256"]) == ci_existing_b[path] for item in records), f"path-fence CI frozen-B binding {path}")
            require(all(item["serializedSharedPath"] is False for item in records), f"path-fence CI path serialization {path}")
    card_five = next(card for card in cards if card["cardID"] == "V30-P00-C05")
    require(set(card_five["s10SharedPaths"]) == {".github/workflows/ios-ci.yml", "Scripts/ui-smoke.sh"}, "path-fence Card 5 CI S10 tuple paths")
    require("Scripts/test-smoke.sh" not in set(card_five["s10SharedPaths"]), "path-fence Card 5 test-smoke S10 overlap")
    for path, owners in all_allowed.items():
        if path in common_execution_set:
            require(owners == expected_writer_order, f"common execution writer order {path}")
            require(all(item["classification"] == "EXPECTED_ABSENT_NEW_PATH" for item in path_records[path]), f"common execution must be new {path}")
            continue
        if path in product_serialized_paths:
            record = serialized_records[path]
            require(record["writerOrder"] == owners, f"serialized product writer order {path}")
            require(record["writerOrder"] == sorted(record["writerOrder"], key=ordinal_by_id.__getitem__), f"serialized product ordinal order {path}")
            require(all(item["classification"] == "EXISTING_BLOB" for item in path_records[path]), f"serialized product seam must be frozen B {path}")
            require(all(item["serializedSharedPath"] is True for item in path_records[path]), f"serialized product seam marker {path}")
            continue
        require(len(owners) == 1, f"unserialized multi-card path {path}")
        require(path not in serialized_records, f"single-owner path is declared serialized {path}")
        require(path_records[path][0]["serializedSharedPath"] is False, f"single-owner path marker {path}")
    overlap_paths = {path for path in all_allowed if path in reserved}
    require(overlap_paths == {path for card in cards for path in card["s10SharedPaths"]}, "path-fence S10 intersection")

    require(set(serialized_records) == common_execution_set | actual_product_multi_owner_paths, "serialized path closure")
    for path, item in serialized_records.items():
        require(isinstance(item.get("rationale"), str) and item["rationale"], f"serialized rationale {path}")
        require(item.get("writerLane") == ("V30_PROVISIONAL_SINGLE_WRITER" if path in common_execution_set else "V30-PRE-S10-ORDINAL-SERIALIZED-EXISTING-SEAM"), f"serialized writer lane {path}")
        require(item.get("writerOrder") == (expected_writer_order if path in common_execution_set else all_allowed[path]), f"serialized writer order {path}")

    rules = fences.get("fenceRules")
    require(isinstance(rules, dict), "path-fence rules")
    require(rules.get("forbiddenInheritedMutationPaths") == ["docs/execution/CURRENT_TASK.md", "docs/execution/HANDOFF.md", "Scripts/ci-selection.json"], "path-fence inherited paths")
    require(not forbidden_inherited.intersection(all_allowed), "path-fence contains inherited active path")
    require("C:\\AssetRounds is NO_READ_NO_WRITE_NO_POLL" in rules.get("phase10CheckoutRule", ""), "path-fence no-poll rule")
    s10_overlap_rule = require_string(rules.get("s10OverlapRule"), "path-fence overlap rule")
    s10_overlap_rule_lower = s10_overlap_rule.lower()
    require("s10-reserved path" in s10_overlap_rule_lower and "exact" in s10_overlap_rule_lower and "tuple" in s10_overlap_rule_lower and "replay" in s10_overlap_rule_lower, "path-fence overlap rule")

    immutable = fences.get("immutableBootstrapAuthorityPaths")
    require(isinstance(immutable, list) and immutable, "path-fence immutable authority paths")
    require(all(item.get("classification") == "EXPECTED_ABSENT_NEW_PATH_AT_B_READ_ONLY_AFTER_EXTERNAL_INSTALL" for item in immutable), "path-fence immutable classifications")
    immutable_names = {item.get("path") for item in immutable}
    require(all(isinstance(path, str) and path and "\\" not in path and ".." not in Path(path).parts for path in immutable_names), "path-fence immutable path form")
    source_map = validate_source_install_records(authority.get("sourceToInstallMap"), "authority sourceToInstallMap")
    immutable_sources = AUTHORITY_FILES + ("V30_PACKAGE_MANIFEST.json",) + HUMAN_FILES + MACHINE_FILES
    expected_immutable = {source_map[source] for source in immutable_sources}
    require(immutable_names == expected_immutable, "path-fence immutable authority set")
    fence_authority = authority.get("pathFenceAuthority")
    require(isinstance(fence_authority, dict), "authority path-fence binding")
    require(fence_authority.get("sha256") == sha256(ROOT / "V30_PRE_S10_PATH_FENCES.json"), "authority/path-fence SHA")
    authority_tuples = fence_authority.get("s10SharedReconciliationTuples")
    fence_tuples = [tuple_record for card in cards for tuple_record in card["preAuthorizedOverlapTuples"]]
    require(authority_tuples == fence_tuples, "authority/path-fence tuple binding")
    reservation_meta = fences.get("s10Reservation")
    require(reservation_meta == {
        "contentDigest": EXPECTED_S10_RESERVATION_DIGEST,
        "rawSHA256": EXPECTED_S10_RESERVATION_RAW_SHA,
        "reservedPathCount": 86,
        "sourcePath": "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json",
    }, "path-fence reservation metadata")
    return fences


def bootstrap_payload_digest(value: dict[str, Any]) -> str:
    projected = dict(value)
    projected.pop("payloadDigest", None)
    pretty = json.dumps(projected, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return hashlib.sha256(pretty.encode("utf-8")).hexdigest()


def validate_bootstrap_payloads(fences: dict[str, Any], authority: dict[str, Any]) -> dict[str, Any]:
    authority_id = authority["authority"]["id"]
    fence_path = ROOT / "V30_PRE_S10_PATH_FENCES.json"
    request_ids = authority.get("bootstrapRequestIDs")
    require(request_ids == {
        "installation": authority_id + "/INSTALL",
        "coordinationGenesis": authority_id + "/G3-GENESIS",
        "activationReceipt": authority_id + "/G3-ACTIVATION",
        "productSelectionProjection": authority_id + "/G3-PROJECTIONS",
        "cardSelection": authority_id + "/G3-SELECT-CARD-001",
    }, "bootstrap authority request IDs")
    ledger_authority = authority.get("provisionalLedger")
    require(isinstance(ledger_authority, dict), "bootstrap provisional ledger authority")
    required_ledger_fields = (
        "ledgerID", "requestIDNamespace", "initialWriterGeneration", "initialSequence", "externalRef",
        "refCreationExpectedOld", "genesisExpectedOldRef", "genesisExpectedLedger", "bootstrapAllowedPaths",
        "runtimeMutablePaths", "activationReceiptPath", "cardSelectionReceiptPath",
    )
    require(all(field in ledger_authority for field in required_ledger_fields), "bootstrap provisional ledger authority fields")
    binding = {
        "authorityContentDigest": authority["authorityContentDigest"],
        "authorityFileSHA256": sha256(AUTH),
        "pathFenceFileSHA256": sha256(fence_path),
        "installationRequestID": authority.get("installationRequestID"),
        "bootstrapRequestIDs": request_ids,
        "provisionalLedger": {field: ledger_authority[field] for field in required_ledger_fields},
    }

    def common(value: dict[str, Any], label: str) -> None:
        require(value.get("schemaVersion") == "V30BootstrapPayloadV1", f"{label} schemaVersion")
        require(value.get("authorityID") == authority_id, f"{label} authority ID")
        require(value.get("installationRequestID") == binding["installationRequestID"], f"{label} installation request ID")
        require(value.get("bootstrapRequestIDs") == binding["bootstrapRequestIDs"], f"{label} bootstrap request IDs")
        require(value.get("cardID") == "V30-P00-C01", f"{label} card ID")
        require(value.get("cardTitle") == "Provisional authority and isolated-lane validation", f"{label} card title")
        require(value.get("preS10FinalCredit") is False, f"{label} credit")
        require(value.get("phase10Access") == "FORBIDDEN_NO_READ_NO_WRITE_NO_POLL", f"{label} Phase 10 access")
        require(value.get("frozenV23") == {"branch": "phase/v23-expansion", "head": EXPECTED_V23_HEAD, "tree": EXPECTED_V23_TREE}, f"{label} V23 binding")
        require(value.get("frozenV23Coordination") == {
            "head": EXPECTED_COORD_HEAD,
            "tree": EXPECTED_COORD_TREE,
            "sequence": EXPECTED_COORD_SEQUENCE,
            "ledgerDigest": EXPECTED_COORD_LEDGER,
            "projectionDigest": EXPECTED_COORD_PROJECTION,
        }, f"{label} coordination binding")
        require(value.get("provisionalExecution") == {"branch": "phase/v30-globalization", "worktree": r"C:\AssetRounds-v30-globalization"}, f"{label} provisional execution")
        require(value.get("materializationTargets") == {
            "context": "docs/design/v30/execution/contexts/V30-P00-C01-attempt-1.json",
            "fence": "docs/design/v30/execution/fences/V30-P00-C01-attempt-1.json",
            "currentTask": "docs/design/v30/execution/V30_CURRENT_TASK.md",
            "ciSelection": "docs/design/v30/execution/V30_CI_SELECTION.json",
            "executionHandoff": "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md",
            "provisionalLedgerProjection": "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json",
        }, f"{label} materialization targets")
        require(value.get("packageBinding") == binding, f"{label} package binding")
        require(value.get("payloadDigest") == bootstrap_payload_digest(value), f"{label} payloadDigest")

    context = load_json(ROOT / "V30_CARD_001_CONTEXT.json")
    common(context, "Card 1 context")
    require(context.get("kind") == "V30CardContextV1", "Card 1 context kind")
    require(context.get("directPrerequisites") == [], "Card 1 context prerequisites")
    require("no product work" in context.get("outcome", "").lower(), "Card 1 context outcome")
    require(context.get("activeTaskPath") == "docs/design/v30/execution/V30_CURRENT_TASK.md", "Card 1 context task path")
    require(context.get("fencePath") == "docs/design/v30/execution/fences/V30-P00-C01-attempt-1.json", "Card 1 context fence path")
    expected_card_one_paths = [item["path"] for item in fences["cards"][0]["allowedPaths"]]
    require(context.get("allowedPaths") == expected_card_one_paths, "Card 1 context allowed paths")
    require(context.get("allowedPathCount") == len(expected_card_one_paths), "Card 1 context allowed path count")
    require(context.get("selectorPath") == "docs/design/v30/execution/V30_CI_SELECTION.json", "Card 1 context selector path")
    require(context.get("executionHandoffPath") == "docs/design/v30/execution/V30_EXECUTION_HANDOFF.md", "Card 1 context handoff path")
    require(context.get("inheritedExecutionPaths") == ["docs/execution/CURRENT_TASK.md", "docs/product/BUILD_PLAN_V4.md", "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md"], "Card 1 inherited paths")
    require(context.get("inheritedExecutionPathsDisposition") == "FROZEN_READ_ONLY_PREDECESSOR_EVIDENCE", "Card 1 inherited path disposition")

    fence = load_json(ROOT / "V30_CARD_001_FENCE.json")
    common(fence, "Card 1 fence")
    require(fence.get("kind") == "V30CardPathFenceV1", "Card 1 fence kind")
    source = fence.get("source")
    require(isinstance(source, dict), "Card 1 fence source")
    require(source.get("path") == fence_path.name, "Card 1 fence source path")
    require(source.get("sha256") == sha256(fence_path), "Card 1 fence source SHA")
    source_card = source.get("sourceCardFence")
    require(source_card == fences["cards"][0], "Card 1 source fence binding")
    expected_records = fences["cards"][0]["allowedPaths"]
    require(fence.get("allowedPaths") == [item["path"] for item in expected_records], "Card 1 allowed path projection")
    require(fence.get("allowedPathRecords") == expected_records, "Card 1 allowed path records")
    require(fence.get("s10SharedPaths") == fences["cards"][0]["s10SharedPaths"], "Card 1 S10 paths")
    require(fence.get("s10SharedPathRecords") == [], "Card 1 S10 records")
    require(fence.get("forbiddenPaths") == [r"C:\AssetRounds"], "Card 1 forbidden paths")
    require("No read, write, status, build, test, Git, or process inspection" in fence.get("forbiddenOperation", ""), "Card 1 forbidden operation")

    ci = load_json(ROOT / "V30_CARD_001_CI_SELECTION.json")
    common(ci, "Card 1 CI selection")
    require(ci.get("kind") == "V30CISelectionV1", "Card 1 CI kind")
    require(ci.get("mode") == "DISABLED_STATIC_PREFLIGHT", "Card 1 CI mode")
    require(ci.get("hostedDispatchAllowed") is False, "Card 1 hosted dispatch")
    require(ci.get("hostedDispatchUnlockCard") == "V30-P00-C05", "Card 1 hosted unlock")
    require(ci.get("windowsStaticChecksAllowed") is True, "Card 1 Windows checks")
    require(ci.get("selector") is None, "Card 1 selector")
    require("no hosted route is pinned before Card 5" in ci.get("reason", ""), "Card 1 CI reason")

    current_task = load_text(ROOT / "V30_CARD_001_CURRENT_TASK.md")
    require("V30CurrentTaskV1" in current_task, "Card 1 current-task schema")
    require(f"Authority ID: `{authority_id}`" in current_task, "Card 1 current-task authority")
    require("Card: `V30-P00-C01 — Provisional authority and isolated-lane validation`" in current_task, "Card 1 current-task identity")
    require("## Exact allowed paths" in current_task, "Card 1 current-task exact path section")
    current_task_paths: list[str] = []
    in_path_section = False
    for line in current_task.splitlines():
        if line == "## Exact allowed paths":
            in_path_section = True
            continue
        if in_path_section and line.startswith("## "):
            break
        if in_path_section and line.startswith("- `") and line.endswith("`"):
            current_task_paths.append(line[3:-1])
    require(current_task_paths == expected_card_one_paths, "Card 1 current-task exact path projection")
    require(f"Exact Card 1 fence: `{context['fencePath']}`." in current_task, "Card 1 current-task fence binding")
    require("Scripts/ci-selection.json" in current_task and "frozen read-only predecessor evidence" in current_task, "Card 1 current-task inherited selector law")

    projection = load_json(ROOT / "V30_PROVISIONAL_LEDGER_PROJECTION.json")
    require(projection.get("schemaVersion") == "V30ProvisionalLedgerProjectionV1", "ledger projection schema")
    require(projection.get("kind") == "PRODUCT_BRANCH_READ_ONLY_PROJECTION", "ledger projection kind")
    require(projection.get("authorityID") == authority_id, "ledger projection authority ID")
    require(projection.get("canonicalLedgerExternal") is True, "ledger projection external ledger distinction")
    require(projection.get("projectionTarget") == "docs/design/v30/execution/V30_PROVISIONAL_LEDGER_PROJECTION.json", "ledger projection target")
    source_genesis = projection.get("sourceGenesis")
    require(isinstance(source_genesis, dict), "ledger projection source genesis")
    require(source_genesis.get("file") == "V30_PROVISIONAL_LEDGER_GENESIS.json", "ledger projection genesis file")
    expected_genesis_coordination = {
        "branch": "coord/v30-globalization-provisional",
        "worktree": r"C:\AssetRounds-v30-globalization-coordination",
        "externalRef": binding["provisionalLedger"]["externalRef"],
        "expectedRef": binding["provisionalLedger"]["refCreationExpectedOld"],
        "genesisExpectedOldRef": binding["provisionalLedger"]["genesisExpectedOldRef"],
        "expectedLedgerDigest": binding["provisionalLedger"]["genesisExpectedLedger"],
        "expectedAbsent": True,
        "canonicalLedgerExternal": True,
    }
    require(source_genesis.get("coordination") == expected_genesis_coordination, "ledger projection coordination")
    require(source_genesis.get("sequence") == binding["provisionalLedger"]["initialSequence"], "ledger projection genesis sequence")
    require(projection.get("installationRequestID") == binding["installationRequestID"], "ledger projection installation request ID")
    require(projection.get("productProjectionRequestID") == binding["bootstrapRequestIDs"]["productSelectionProjection"], "ledger projection request ID")
    require(projection.get("selectedCard") is None and projection.get("creditedCards") == [], "ledger projection selection")
    require(projection.get("preS10FinalCredit") is False, "ledger projection credit")
    require(projection.get("writeDisposition", "").startswith("READ_ONLY_PROJECTION;"), "ledger projection write disposition")
    require(projection.get("packageBinding") == binding, "ledger projection binding")
    require(projection.get("payloadDigest") == bootstrap_payload_digest(projection), "ledger projection payloadDigest")

    genesis = load_json(ROOT / "V30_PROVISIONAL_LEDGER_GENESIS.json")
    require(genesis.get("schemaVersion") == "V30ProvisionalExecutionLedgerV1", "ledger genesis schema")
    require(genesis.get("kind") == "EXPECTED_ABSENT_G3_COORDINATION_LEDGER_GENESIS", "ledger genesis kind")
    require(genesis.get("authorityID") == authority_id, "ledger genesis authority ID")
    require(genesis.get("installationRequestID") == binding["installationRequestID"], "ledger genesis installation request ID")
    require(genesis.get("requestID") == binding["bootstrapRequestIDs"]["coordinationGenesis"], "ledger genesis request ID")
    require(genesis.get("ledgerID") == binding["provisionalLedger"]["ledgerID"], "ledger genesis ledger ID")
    require(genesis.get("requestIDNamespace") == binding["provisionalLedger"]["requestIDNamespace"], "ledger genesis request namespace")
    genesis_coordination = genesis.get("coordination")
    require(genesis_coordination == source_genesis.get("coordination"), "ledger genesis coordination")
    require(genesis_coordination.get("expectedAbsent") is True and genesis_coordination.get("canonicalLedgerExternal") is True, "ledger genesis expected absent")
    require(genesis.get("sequence") == binding["provisionalLedger"]["initialSequence"] and genesis.get("writerGeneration") == binding["provisionalLedger"]["initialWriterGeneration"], "ledger genesis sequence")
    require(genesis.get("state") == "GENESIS_PRE_SELECTION", "ledger genesis state")
    require(genesis.get("selectedCard") is None and genesis.get("creditedCards") == [], "ledger genesis selection")
    require(genesis.get("preS10FinalCredit") is False, "ledger genesis credit")
    require(genesis.get("previousLedgerDigest") is None, "ledger genesis previous digest")
    require(genesis.get("events") == [] and genesis.get("requestResults") == [], "ledger genesis empty events")
    require(genesis.get("bootstrapAllowedPaths") == binding["provisionalLedger"]["bootstrapAllowedPaths"], "ledger genesis bootstrap paths")
    require(genesis.get("runtimeMutablePaths") == binding["provisionalLedger"]["runtimeMutablePaths"], "ledger genesis runtime mutable paths")
    require(genesis.get("receiptMetadata") == {
        "activationRequestID": binding["bootstrapRequestIDs"]["activationReceipt"],
        "activationReceiptPath": binding["provisionalLedger"]["activationReceiptPath"],
        "selectionRequestID": binding["bootstrapRequestIDs"]["cardSelection"],
        "selectionReceiptPath": binding["provisionalLedger"]["cardSelectionReceiptPath"],
        "productProjectionRequestID": binding["bootstrapRequestIDs"]["productSelectionProjection"],
    }, "ledger genesis receipt metadata")
    require(genesis.get("frozenV23Observations") == {
        "branch": "phase/v23-expansion", "head": EXPECTED_V23_HEAD, "tree": EXPECTED_V23_TREE,
    }, "ledger genesis V23 observations")
    require(genesis.get("frozenV23CoordinationObservations") == {
        "head": EXPECTED_COORD_HEAD, "tree": EXPECTED_COORD_TREE, "sequence": EXPECTED_COORD_SEQUENCE,
        "ledgerDigest": EXPECTED_COORD_LEDGER, "projectionDigest": EXPECTED_COORD_PROJECTION,
    }, "ledger genesis coordination observations")
    require(genesis.get("packageBinding") == binding, "ledger genesis binding")
    require(genesis.get("payloadDigest") == bootstrap_payload_digest(genesis), "ledger genesis payloadDigest")
    require(source_genesis.get("payloadDigest") == genesis.get("payloadDigest"), "ledger projection/genesis digest binding")

    handoff_bytes = load_text(ROOT / "V30_EXECUTION_HANDOFF_GENESIS.md")
    require("V30ExecutionHandoffGenesisV1" in handoff_bytes, "bootstrap handoff schema")
    require(f"Authority ID: `{authority_id}`" in handoff_bytes, "bootstrap handoff authority")
    require(f"Authority content digest: `{authority['authorityContentDigest']}`" in handoff_bytes, "bootstrap handoff digest")
    require(f"Card-1 path-fence SHA-256: `{sha256(fence_path)}`" in handoff_bytes, "bootstrap handoff fence digest")
    require("Pre-S10 final credit: `false`" in handoff_bytes and "Entries: none" in handoff_bytes, "bootstrap handoff zero-credit/empty")
    return {"context": context, "fence": fence, "ci": ci, "projection": projection, "genesis": genesis}


def validate_docs(
    architecture: str,
    card_rows: list[dict[str, Any]],
    edge_pairs: set[tuple[str, str]],
    appendix_rows: list[dict[str, Any]],
) -> None:
    for path in (FOUNDATION, HANDOFF, PROMPT):
        text = load_text(path)
        require("<" not in text and ">" not in text, f"{path.name}: placeholder marker")
    require("## 21. Closed 55-card graph" in architecture, "architecture card section")
    require("## Appendix A — V24 normative-requirement disposition matrix" in architecture, "architecture V24 appendix")
    require("V30PreS10ProvisionalImplementationAuthorityV1" in architecture, "architecture authority name")
    require("V30_PACKAGE_MANIFEST.json" in architecture, "architecture manifest name")
    require("C:\\AssetRounds" in architecture, "architecture Phase 10 forbidden path")
    architecture_lower = architecture.lower()
    require("phase 10" in architecture_lower and "poll" in architecture_lower and "forbidden" in architecture_lower, "architecture no-poll policy")
    require("S10_SHARED_RECONCILIATION_REQUIRED" in architecture, "architecture shared-path label")
    require("has no final implementation, acceptance" in architecture_lower and "successor credit" in architecture_lower, "architecture zero-credit law")
    require("one current card" in architecture.lower(), "architecture one-current-card law")
    require("CORRECTION_REQUIRED" in architecture and "correctionOf" in architecture, "architecture correction law")
    require("phase/v30-globalization-reconciliation" in architecture, "architecture reconciliation branch")
    require("owner reports Phase 10.6 complete" in architecture or "OWNER_REPORTS_PHASE_10_6_COMPLETE" in architecture, "architecture post-S10 trigger")
    require("no range shorthand" in architecture.lower(), "architecture no-range-shorthand law")
    require("fully expanded repository-relative files" in architecture.lower(), "architecture expanded-path law")
    require("graph-enumerated 37-card pre-s10" in architecture_lower, "architecture pre-S10 cohort descriptor")
    require("graph-enumerated 18-card post-s10" in architecture_lower, "architecture post-S10 cohort descriptor")
    require(len(card_rows[:37]) == 37 and len(card_rows[37:]) == 18, "graph cohort cardinality")
    require(len(card_rows) == 55 and len(edge_pairs) == 107 and len(appendix_rows) == 97, "document structural counts")

    # The handoff and prompt must carry safety-critical phrases themselves, not
    # merely rely on the machine authority.
    handoff = load_text(HANDOFF)
    prompt = load_text(PROMPT)
    for text, label in ((handoff, "handoff"), (prompt, "prompt")):
        require("C:\\AssetRounds" in text, f"{label}: Phase 10 forbidden path")
        require("Phase 10" in text and "do not" in text.lower(), f"{label}: no-poll rule")
        text_lower = text.lower()
        require("37" in text and "graph-enumerated" in text_lower and "pre-s10" in text_lower, f"{label}: pre-S10 cohort descriptor")
        require("18" in text and "graph-enumerated" in text_lower and "post-s10" in text_lower, f"{label}: post-S10 cohort descriptor")
        require("credit" in text_lower and ("no final" in text_lower or "final credit available before reconciliation: false" in text_lower), f"{label}: zero-credit law")
        require("V30-P00-C01" in text, f"{label}: initial card")
    require("I am the owner and I authorize" in prompt, "owner prompt authority")
    require("Do not check whether Phase 10.6 is done" in prompt, "no-poll prompt")


def _reject_reparse_components(path: Path, label: str) -> None:
    """Reject symlink/junction/reparse components before any file is opened."""
    require(path.is_absolute(), f"{label}: absolute path required")
    parts = path.parts
    require(parts and path.anchor == parts[0], f"{label}: unsupported path anchor")
    current = Path(path.anchor)
    for component in parts[1:]:
        current = current / component
        try:
            info = current.lstat()
        except FileNotFoundError:
            # A missing component makes every later component unavailable; the
            # caller will issue the exact missing-file failure without probing
            # an alternate path.
            return
        except OSError as exc:
            raise AuditError(f"{label}: cannot inspect path component {current}: {exc}") from exc
        require(not current.is_symlink(), f"{label}: symlink/reparse component {current}")
        is_junction = getattr(current, "is_junction", None)
        require(not callable(is_junction) or not is_junction(), f"{label}: junction/reparse component {current}")
        attributes = getattr(info, "st_file_attributes", 0)
        reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
        require(not attributes & reparse_flag, f"{label}: reparse component {current}")


def _authorized_installed_root(installed_root: Path) -> Path:
    """Accept only the named V30 product worktree, using a lexical gate first."""
    requested = PureWindowsPath(str(installed_root))
    authorized = PureWindowsPath(r"C:\AssetRounds-v30-globalization")
    # This comparison is intentionally before is_dir/lstat/resolve/read: the
    # optional readback mode may never be pointed at the active app checkout,
    # one of its descendants, or an arbitrary staging directory.
    require(requested.is_absolute() and ".." not in requested.parts and requested == authorized, "installed-root must be exactly C:\\AssetRounds-v30-globalization")
    canonical = Path(str(requested))
    _reject_reparse_components(canonical, "installed-root")
    require(canonical.is_dir(), f"installed root is not a directory: {canonical}")
    return canonical


def validate_installed_root(installed_root: Path, manifest: dict[str, Any], records: list[dict[str, Any]]) -> None:
    """Read back only the exact mapped files from a G2 installation root.

    The external package remains the source of truth.  This optional mode does
    not enumerate the installed repository and does not run any generator; it
    checks only the destinations named by the validated source-to-install map.
    """
    resolved_root = _authorized_installed_root(installed_root)

    source_map = validate_source_install_records(manifest.get("sourceToInstallMap"), "installed sourceToInstallMap")
    by_source = {record["path"]: record for record in records}
    require(set(by_source) == set(EXPECTED_MANIFEST_FILES), "installed manifest record set")
    for source, destination in sorted(source_map.items()):
        candidate = resolved_root / Path(destination)
        _reject_reparse_components(candidate, f"installed destination {destination}")
        require(candidate.is_file(), f"installed mapped file missing: {destination}")
        raw = candidate.read_bytes()
        load_text(candidate)
        if source == MANIFEST.name:
            expected_sha = sha256(MANIFEST)
            expected_bytes = MANIFEST.stat().st_size
        else:
            record = by_source.get(source)
            require(record is not None, f"installed source absent from manifest records: {source}")
            expected_sha = record["sha256"]
            expected_bytes = record["bytes"]
        require(len(raw) == expected_bytes, f"installed byte count mismatch: {source}")
        require(hashlib.sha256(raw).hexdigest() == expected_sha, f"installed hash mismatch: {source}")


def validate_package_files() -> None:
    # Validate the complete exact package set before loading semantic artifacts.
    actual = {path.name for path in ROOT.iterdir() if path.is_file()}
    require(actual == set(EXPECTED_PACKAGE_FILES), f"package directory file set mismatch: {sorted(actual ^ set(EXPECTED_PACKAGE_FILES))}")
    for name in EXPECTED_PACKAGE_FILES:
        load_text(ROOT / name)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate the external V30 package. The package is flat for generation, "
            "while installed Scripts/v30 and docs/design/v30 copies are immutable "
            "provenance; pass --installed-root for exact G2 readback only."
        )
    )
    parser.add_argument(
        "--installed-root",
        type=Path,
        metavar="PATH",
        help="optionally verify only the exact mapped files under this installed V30 root; never C:\\AssetRounds",
    )
    args = parser.parse_args()
    validate_package_files()
    architecture = load_text(ARCH)
    card_rows, edge_pairs = parse_cards(architecture)
    card_ids = {row["cardID"] for row in card_rows}
    appendix_rows = validate_appendix(architecture, card_ids)
    manifest, records = validate_manifest()
    authority = validate_authority(manifest)
    validate_card_register(card_rows, edge_pairs)
    validate_graph(edge_pairs, card_rows)
    validate_locales()
    validate_v24_projection(card_ids)
    fences = validate_path_fences(card_rows, authority)
    validate_bootstrap_payloads(fences, authority)
    validate_docs(architecture, card_rows, edge_pairs, appendix_rows)
    if args.installed_root is not None:
        validate_installed_root(args.installed_root, manifest, records)

    result = {
        "result": "PASS",
        "cards": len(card_rows),
        "edges": len(edge_pairs),
        "v24DispositionRows": len(appendix_rows),
        "initialLocales": EXPECTED_LOCALES,
        "nextWaveLocales": EXPECTED_NEXT_WAVE,
        "authorityID": authority["authority"]["id"],
        "manifestFileCount": len(records),
        "manifestSha256": sha256(MANIFEST),
        "packageDigest": manifest["packageDigest"],
        "installedRootChecked": str(args.installed_root) if args.installed_root is not None else None,
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AuditError as exc:
        print(json.dumps({"result": "FAIL", "reason": str(exc)}, sort_keys=True))
        raise SystemExit(1)
