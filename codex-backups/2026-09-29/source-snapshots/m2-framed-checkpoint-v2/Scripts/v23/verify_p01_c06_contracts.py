#!/usr/bin/env python3
"""Hostile/static verification for V23-P01-C06 deterministic tooling."""
from __future__ import annotations

import ast
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

from p01_c06_contracts import (
    CARD,
    CONTRACT_ARTIFACT,
    CONTRACT_SCHEMA,
    DELETION_MODES,
    ERASE_PREPARATION_PROTOCOL,
    EVIDENCE_IDS,
    ERASE_PHASES,
    FAILURE_CASES,
    FIXTURE_PATH,
    FIXTURE_SCHEMA,
    FULL_FENCE,
    GRAPH_ARTIFACT,
    MANIFEST,
    REGISTERED_KINDS,
    REGISTERED_KIND_NAMES,
    SEMANTIC_SCOPE,
    SOURCE_PATHS,
    SOURCE_SPECS,
    TOOL_PATHS,
    ContractError,
    all_outputs,
    deletion_fixture,
    flags,
    pretty,
    sha,
    source_binding_complete,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load_canonical(root: Path, path: str) -> dict[str, Any]:
    data = (root / path).read_bytes()
    value = json.loads(data)
    require(isinstance(value, dict), f"{path}: root must be object")
    require(data == pretty(value), f"{path}: noncanonical JSON")
    return value


def verify_seal(value: dict[str, Any], path: str) -> None:
    payload = dict(value)
    observed = payload.pop("artifactDigest", None)
    require(isinstance(observed, str) and observed == sha(pretty(payload)), f"{path}: artifactDigest mismatch")


def _validate_schema(value: Any, schema: dict[str, Any], path: str = "$", root_schema: bool = True) -> None:
    """Small dependency-free subset sufficient for the generated strict schemas."""
    if "const" in schema:
        require(value == schema["const"], f"{path}: const mismatch")
    if "enum" in schema:
        require(value in schema["enum"], f"{path}: enum mismatch")
    expected_type = schema.get("type")
    if expected_type == "object":
        require(isinstance(value, dict), f"{path}: expected object")
        required = schema.get("required", [])
        require(all(key in value for key in required), f"{path}: required property missing")
        if schema.get("additionalProperties") is False:
            require(set(value) <= set(schema.get("properties", {})), f"{path}: additional property")
        for key, child in schema.get("properties", {}).items():
            if key in value:
                _validate_schema(value[key], child, f"{path}.{key}", False)
    elif expected_type == "array":
        require(isinstance(value, list), f"{path}: expected array")
        if "minItems" in schema:
            require(len(value) >= schema["minItems"], f"{path}: too few items")
        if "maxItems" in schema:
            require(len(value) <= schema["maxItems"], f"{path}: too many items")
        if schema.get("uniqueItems"):
            require(len({json.dumps(item, ensure_ascii=False, sort_keys=True) for item in value}) == len(value), f"{path}: duplicate item")
        prefix = schema.get("prefixItems", [])
        require(len(value) == len(prefix) if schema.get("items") is False else len(value) >= len(prefix), f"{path}: prefix length")
        for index, child in enumerate(prefix):
            _validate_schema(value[index], child, f"{path}[{index}]", False)
        if schema.get("items") not in (None, False):
            for index in range(len(prefix), len(value)):
                _validate_schema(value[index], schema["items"], f"{path}[{index}]", False)
    elif expected_type == "string":
        require(isinstance(value, str), f"{path}: expected string")
    elif expected_type == "integer":
        require(isinstance(value, int) and not isinstance(value, bool), f"{path}: expected integer")
    elif expected_type == "number":
        require(isinstance(value, (int, float)) and not isinstance(value, bool), f"{path}: expected number")
    elif expected_type == "boolean":
        require(isinstance(value, bool), f"{path}: expected boolean")
    elif expected_type == "null":
        require(value is None, f"{path}: expected null")
    pattern = schema.get("pattern")
    if pattern:
        require(isinstance(value, str) and re.fullmatch(pattern, value) is not None, f"{path}: pattern mismatch")


def _verify_authority(value: dict[str, Any], path: str) -> None:
    from p01_c06_contracts import authority

    require(value == authority(), f"{path}: corrected authority drift")


def _verify_flags(value: dict[str, Any], path: str) -> None:
    for key, expected in flags().items():
        require(value.get(key) is expected, f"{path}: unsafe {key}")


def _verify_source_bindings(root: Path, contract: dict[str, Any]) -> None:
    bindings = contract["sourceBindings"]
    require([row["path"] for row in bindings] == SOURCE_PATHS, "source binding ordering/fence drift")
    for row, (path, symbols) in zip(bindings, SOURCE_SPECS):
        require(row["path"] == path and row["requiredSymbols"] == symbols, f"{path}: source binding metadata drift")
        item = root / path
        if path == FIXTURE_PATH and not item.is_file():
            data = pretty(deletion_fixture())
        elif item.is_file():
            data = item.read_bytes()
        else:
            require(row["status"] == "PENDING" and row["bytes"] is None and row["sha256"] is None, f"{path}: missing source must be pending")
            require(row["missingSymbols"] == symbols, f"{path}: pending symbol list drift")
            continue
        text = data.decode("utf-8")
        missing = [symbol for symbol in symbols if symbol not in text]
        require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"{path}: source digest drift")
        require(row["missingSymbols"] == missing, f"{path}: missing symbol projection drift")
        require(row["status"] == ("BOUND" if not missing else "PENDING"), f"{path}: binding status drift")
    require(contract["sourceBindingComplete"] is source_binding_complete(bindings), "source binding completion drift")


def _verify_kind_registry(value: Any, path: str) -> None:
    require(value == REGISTERED_KINDS, f"{path}: registered kind registry drift")
    require([row["kind"] for row in value] == REGISTERED_KIND_NAMES, f"{path}: kind ordering drift")
    require("tag" not in {row["kind"] for row in value}, f"{path}: persistent Tag kind introduced")
    require(all("Tag" not in json.dumps(row, ensure_ascii=False) for row in value), f"{path}: dormant Tag entity introduced")


def _verify_fixture(fixture: dict[str, Any]) -> None:
    require(fixture == deletion_fixture(), "fixture is not the deterministic generated graph")
    _verify_authority(fixture["authority"], "fixture.authority")
    _verify_kind_registry(fixture["registeredKinds"], "fixture.registeredKinds")
    require(fixture["semanticScope"] == SEMANTIC_SCOPE, "fixture semantic scope drift")
    require(fixture["registeredKindPolicy"]["currentPersistentTagKindPresent"] is False, "fixture Tag policy weakened")
    require(fixture["registeredKindPolicy"]["dormantTagEntityAuthorized"] is False, "fixture dormant Tag policy weakened")
    require(fixture["deletionModes"] == DELETION_MODES and [row["mode"] for row in DELETION_MODES] == ["EMPTY_INSTALL", "REPLACE_EXISTING", "CLONE", "FORK"], "all deletion-wins modes required")
    require(fixture["erasePhases"] == ERASE_PHASES and fixture["erasePhases"][-1] == "cleanup_complete", "Erase phase ordering weakened")
    entries = fixture["afterDelete"]["ledgerEntries"]
    require(entries == sorted(entries, key=lambda row: (row["identity"]["kind"], row["identity"]["id"])), "ledger ordering is nondeterministic")
    require(len(entries) == len({(row["identity"]["kind"], row["identity"]["id"]) for row in entries}), "duplicate ledger identity")
    for entry in entries:
        require(set(entry) == {"schemaVersion", "identity", "deletedAt"}, "tombstone is not privacy-minimal")
        require(entry["schemaVersion"] == 2 and entry["identity"]["kind"] in REGISTERED_KIND_NAMES, "invalid tombstone identity")
        require(all(key not in entry for key in ("content", "payload", "label", "note", "photo", "snapshot", "pdf", "auditNarrative")), "personal tombstone content leaked")
    empty_site_ids = set(fixture["afterDelete"]["emptySiteIDs"])
    require(empty_site_ids and empty_site_ids <= {node["id"] for node in fixture["afterDelete"]["nodes"] if node["kind"] == "site"}, "empty Site not preserved")
    require(fixture["afterDelete"]["assetFileIDs"] == [], "orphan file cleanup did not finish in fixture")
    require({row["family"] for row in fixture["cases"]} == {"G01", "A01", "H01", "I01", "R01"}, "fixture evidence families incomplete")
    require(set(fixture["coverage"]["evidenceIDs"]) == set(EVIDENCE_IDS), "fixture evidence IDs incomplete")
    require(fixture["erasePreparation"] == ERASE_PREPARATION_PROTOCOL, "fixture erase-preparation protocol drift")
    require(all(fixture["coverage"][key] is True for key in ("allDeletionModes", "allCurrentlyRegisteredKinds", "privacyMinimalTombstones", "deletionWins", "eraseOnlyClearing", "emptySitePreserved", "orphanCleanupSeparated", "unknownKindFailClosed", "erasePreparationMarkerRecovery", "noIntentOrphanRecovery", "manifestFirstDiscard")), "fixture coverage weakened")


def _verify_contract(contract: dict[str, Any], root: Path) -> None:
    require(contract["schema"] == "V23P01C06DeletionRightsContractV1" and contract["schemaVersion"] == 1 and contract["cardID"] == CARD, "contract identity drift")
    _verify_authority(contract["authority"], CONTRACT_ARTIFACT)
    _verify_flags(contract, CONTRACT_ARTIFACT)
    _verify_kind_registry(contract["registeredKinds"], "contract.registeredKinds")
    require(contract["semanticScope"] == SEMANTIC_SCOPE, "contract semantic scope drift")
    require(contract["registeredKindPolicy"]["currentPersistentTagKindPresent"] is False and contract["registeredKindPolicy"]["dormantTagEntityAuthorized"] is False, "contract Tag policy weakened")
    tombstone = contract["tombstonePolicy"]
    require(tombstone["deletionWins"] is True and tombstone["privacyMinimal"] is True and tombstone["retention"] == "INDEFINITE_UNTIL_VERIFIED_COMPLETE_ERASE", "deletion-wins/privacy policy weakened")
    require(tombstone["fields"] == ["schemaVersion", "identity", "deletedAt"], "tombstone fields expanded")
    require(all(field in tombstone["forbiddenFields"] for field in ("content", "label", "photo", "auditNarrative")), "tombstone forbidden field policy weakened")
    require(tombstone["containsPersonalContent"] is False and tombstone["containsAuditNarrative"] is False, "privacy-minimal ledger weakened")
    require(contract["deletionWinsModes"] == DELETION_MODES, "deletion mode matrix drift")
    clearing = contract["ledgerClearingPolicy"]
    require(clearing["authority"] == "VERIFIED_COMPLETE_ERASE_ONLY" and clearing["allowedPhases"] == ["cleanup_complete"], "ledger clearing authority widened")
    require(all(clearing[key] is False for key in ("ordinaryDeletionMayClear", "ageMayClear", "sizeMayClear", "versionMayClear", "orphanCleanupMayClear")), "non-Erase ledger clearing permitted")
    require(clearing["interruptedErasePreservesLedger"] is True, "interrupted Erase does not preserve ledger")
    empty_site = contract["emptySitePolicy"]
    require(empty_site["finalAssetDeletion"] == "PRESERVE_SITE" and empty_site["validAfterDeletion"] is True and empty_site["backupRestore"] == "PRESERVE_EMPTY_SITE" and empty_site["laterAssetCreation"] == "ALLOWED", "empty Site preservation weakened")
    require(empty_site["siteDeletion"] == "EXPLICIT_PREVIEWED_COMMAND_ONLY", "implicit Site deletion introduced")
    orphan = contract["orphanCleanupPolicy"]
    require(orphan["service"] == "OrphanFileCleanupService" and orphan["mayMutateDeletionLedger"] is False and orphan["authority"] == "SEPARATE_FROM_DELETION_LEDGER", "orphan cleanup/ledger authority coupled")
    erase = contract["eraseProtocol"]
    require(erase["phases"] == ERASE_PHASES and erase["clearsLedgerOnlyAfterComplete"] is True, "Erase-only protocol weakened")
    require(erase["preparation"] == ERASE_PREPARATION_PROTOCOL, "Erase preparation protocol drift")
    require([row["failure"] for row in contract["failureRecovery"]] == [row[0] for row in FAILURE_CASES], "failure matrix incomplete")
    require(contract["evidencePlan"]["evidenceIDs"] == EVIDENCE_IDS, "contract evidence IDs drift")
    _verify_source_bindings(root, contract)


def _verify_graph_manifest(graph: dict[str, Any], root: Path, fixture: dict[str, Any]) -> None:
    require(graph["schema"] == "V23P01C06DeletionGraphManifestV1" and graph["cardID"] == CARD, "graph manifest identity drift")
    _verify_authority(graph["authority"], GRAPH_ARTIFACT)
    _verify_flags(graph, GRAPH_ARTIFACT)
    require(graph["fixtureBinding"] == {"path": FIXTURE_PATH, "bytes": len(pretty(fixture)), "sha256": sha(pretty(fixture))}, "fixture binding drift")
    _verify_kind_registry(graph["registeredKinds"], "graph.registeredKinds")
    require(graph["semanticScope"] == SEMANTIC_SCOPE, "graph semantic scope drift")
    require(graph["deletionModes"] == DELETION_MODES and graph["erasePhases"] == ERASE_PHASES, "graph policy drift")
    require({row["family"] for row in graph["evidenceCases"]} == {"G01", "A01", "H01", "I01", "R01"}, "graph evidence families incomplete")
    require(graph["evidenceIDs"] == EVIDENCE_IDS and graph["coverage"] == fixture["coverage"], "graph coverage drift")
    require(graph["fullCardFence"] == FULL_FENCE and graph["sourceBindingComplete"] == load_canonical(root, CONTRACT_ARTIFACT)["sourceBindingComplete"], "graph source/fence drift")


def _verify_manifest(manifest: dict[str, Any], root: Path) -> None:
    require(manifest["schema"] == "V23P01C06ToolingManifestV1" and manifest["cardID"] == CARD, "tooling manifest identity drift")
    _verify_authority(manifest["authority"], MANIFEST)
    _verify_flags(manifest, MANIFEST)
    require(manifest["pathFence"] == TOOL_PATHS and manifest["toolingPathCount"] == len(TOOL_PATHS), "tool path fence drift")
    require(manifest["fullCardFence"] == FULL_FENCE and len(FULL_FENCE) == len(set(FULL_FENCE)) == 38, "exact 38-path fence required")
    rows = manifest["artifacts"]
    require([row["path"] for row in rows] == TOOL_PATHS[:-1] and manifest["artifactCount"] == len(TOOL_PATHS) - 1, "artifact row ordering/count drift")
    for row in rows:
        data = (root / row["path"]).read_bytes()
        require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"{row['path']}: artifact binding drift")
    require(manifest["artifactSetDigest"] == sha(pretty(rows)), "artifact set digest drift")
    require(manifest["sourceBindingCount"] == len(SOURCE_PATHS), "source binding count drift")
    require(manifest["evidenceIDs"] == EVIDENCE_IDS, "manifest evidence IDs drift")


def _verify_source_semantics(root: Path) -> None:
    # Static checks are intentionally narrow: they protect the card's hostile
    # invariants without prescribing unrelated implementation details.
    ledger = root / SOURCE_PATHS[0]
    if ledger.is_file():
        text = ledger.read_text(encoding="utf-8")
        require("DeletionRecordKindV2" in text and "DeletionIdentityV2" in text and "DeletionLedgerEntryV2" in text, "ledger typed identity missing")
        require("case tag" not in text and "final class Tag" not in text, "Tag kind/entity introduced")
    models = root / SOURCE_PATHS[4]
    if models.is_file():
        text = models.read_text(encoding="utf-8")
        require(re.search(r"@Model\s+(?:final\s+)?class\s+Tag\b", text) is None, "dormant Tag entity introduced")
    restore = root / SOURCE_PATHS[1]
    if restore.is_file():
        text = restore.read_text(encoding="utf-8")
        require("currentOnlyTombstones" in text and "incomingPackets" in text and "contentDeletedAt" in text, "restore deletion-wins union missing")
    orphan = root / SOURCE_PATHS[15]
    if orphan.is_file():
        text = orphan.read_text(encoding="utf-8")
        require("OrphanFileCleanupService" in text and "cleanup" in text, "orphan cleanup service missing")


def _hostile_mutation_checks(contract: dict[str, Any], fixture: dict[str, Any], graph: dict[str, Any], manifest: dict[str, Any]) -> None:
    """Exercise representative hostile mutations against independent guards."""
    def guard(c: dict[str, Any], f: dict[str, Any], g: dict[str, Any], m: dict[str, Any]) -> None:
        require(c["authority"] == contract["authority"], "authority mutation accepted")
        require(c["tombstonePolicy"]["privacyMinimal"] is True and c["ledgerClearingPolicy"]["authority"] == "VERIFIED_COMPLETE_ERASE_ONLY", "privacy/Erase mutation accepted")
        require(c["orphanCleanupPolicy"]["mayMutateDeletionLedger"] is False, "orphan mutation accepted")
        require(f["registeredKinds"] == REGISTERED_KINDS and f["coverage"]["emptySitePreserved"] is True, "fixture mutation accepted")
        require(g["fullCardFence"] == FULL_FENCE and g["evidenceIDs"] == EVIDENCE_IDS, "graph mutation accepted")
        require(m["pathFence"] == TOOL_PATHS and len(m["fullCardFence"]) == 38, "manifest mutation accepted")

    mutations = []
    c = copy.deepcopy(contract); c["tombstonePolicy"]["privacyMinimal"] = False; mutations.append((c, fixture, graph, manifest))
    c = copy.deepcopy(contract); c["ledgerClearingPolicy"]["authority"] = "ORDINARY_DELETE"; mutations.append((c, fixture, graph, manifest))
    c = copy.deepcopy(contract); c["orphanCleanupPolicy"]["mayMutateDeletionLedger"] = True; mutations.append((c, fixture, graph, manifest))
    f = copy.deepcopy(fixture); f["registeredKinds"].append({"kind": "tag"}); mutations.append((contract, f, graph, manifest))
    f = copy.deepcopy(fixture); f["coverage"]["emptySitePreserved"] = False; mutations.append((contract, f, graph, manifest))
    g = copy.deepcopy(graph); g["fullCardFence"] = g["fullCardFence"][:-1]; mutations.append((contract, fixture, g, manifest))
    m = copy.deepcopy(manifest); m["pathFence"] = list(reversed(m["pathFence"])); mutations.append((contract, fixture, graph, m))
    for candidate in mutations:
        rejected = False
        try:
            guard(*candidate)
        except ContractError:
            rejected = True
        require(rejected, "hostile mutation was accepted")


def _verify_scripts(root: Path) -> None:
    for path in TOOL_PATHS[:3]:
        source = (root / path).read_text(encoding="utf-8")
        ast.parse(source, filename=path)
    generator = root / TOOL_PATHS[1]
    result = subprocess.run([sys.executable, "-B", str(generator), "--check", "--root", str(root)], cwd=root, capture_output=True, text=True)
    require(result.returncode == 0, f"generator --check failed: {result.stderr.strip()}")
    require("verified 6 generated artifacts" in result.stdout, "generator verification output drift")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        expected = all_outputs(root)
        for path, data in expected.items():
            require((root / path).is_file() and (root / path).read_bytes() == data, f"stale generated artifact: {path}")
        contract = load_canonical(root, CONTRACT_ARTIFACT)
        fixture = load_canonical(root, FIXTURE_PATH)
        graph = load_canonical(root, GRAPH_ARTIFACT)
        manifest = load_canonical(root, MANIFEST)
        contract_schema = load_canonical(root, CONTRACT_SCHEMA)
        fixture_schema = load_canonical(root, FIXTURE_SCHEMA)
        verify_seal(contract, CONTRACT_ARTIFACT)
        verify_seal(fixture, FIXTURE_PATH)
        verify_seal(graph, GRAPH_ARTIFACT)
        verify_seal(manifest, MANIFEST)
        _validate_schema(contract, contract_schema, CONTRACT_ARTIFACT)
        _validate_schema(fixture, fixture_schema, FIXTURE_PATH)
        _verify_contract(contract, root)
        _verify_fixture(fixture)
        _verify_graph_manifest(graph, root, fixture)
        _verify_manifest(manifest, root)
        _verify_source_semantics(root)
        _hostile_mutation_checks(contract, fixture, graph, manifest)
        _verify_scripts(root)
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError, ValueError, SyntaxError, subprocess.SubprocessError) as error:
        print(f"V23-P01-C06 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P01-C06 hostile static contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
