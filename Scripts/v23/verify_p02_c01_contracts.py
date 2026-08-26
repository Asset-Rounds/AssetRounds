#!/usr/bin/env python3
"""Hostile, schema, seal, and closure verifier for V23-P02-C01."""
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

from p02_c01_contracts import (
    BOUNDARY_DOC, BOUNDARY_SCHEMA, CARD, C02_RESERVED, COMMAND_KINDS,
    CONTRACT_SCRIPT, DIRECT_WRITERS, EVIDENCE_IDS, FENCED_SWIFT_PATHS,
    FIXTURE, GENERATED_PATHS, GENERATOR_SCRIPT, MANIFEST,
    MANIFEST_INPUT_PATHS, OPERATIONAL_COMMAND_KINDS,
    PREVIEW_ONLY_COMMAND_KINDS, REVERSAL_DOC, REVERSAL_SCHEMA, TOOL_PATHS,
    VERIFIER_SCRIPT, WRITER_DOC, WRITER_SCHEMA,
    ContractError, all_outputs, authority, boundary_contract, flags,
    idempotency_contract, mutation_fixture, pretty, reversal_contract,
    revision_contract, sha, writer_contract,
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def load(root: Path, path: str) -> dict[str, Any]:
    data = (root / path).read_bytes()
    value = json.loads(data)
    require(isinstance(value, dict), f"{path}: root must be object")
    require(data == pretty(value), f"{path}: JSON must be canonical pretty form")
    return value


def verify_seal(value: dict[str, Any], path: str) -> None:
    payload = dict(value)
    observed = payload.pop("artifactDigest", None)
    require(isinstance(observed, str) and observed == sha(pretty(payload)), f"{path}: artifactDigest mismatch")


def verify_authority_digests(value: dict[str, Any], path: str) -> None:
    authority_value = value.get("authority")
    require(isinstance(authority_value, dict), f"{path}: authority missing")
    for key, item in authority_value.items():
        if key.endswith("Digest") or key.endswith("SHA256"):
            require(
                isinstance(item, str)
                and len(item) == 64
                and re.fullmatch(r"[0-9a-f]{64}", item) is not None,
                f"{path}: malformed authority digest {key}",
            )


def validate(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        require(value == schema["const"], f"{path}: const mismatch")
    if "enum" in schema:
        require(value in schema["enum"], f"{path}: enum mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(value, dict), f"{path}: expected object")
        required = schema.get("required", [])
        require(all(key in value for key in required), f"{path}: missing required property")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            require(set(value) <= set(properties), f"{path}: additional property")
        for key, child in properties.items():
            if key in value:
                validate(value[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(value, list), f"{path}: expected array")
        require(len(value) >= schema.get("minItems", 0), f"{path}: too few items")
        require(len(value) <= schema.get("maxItems", len(value)), f"{path}: too many items")
        if schema.get("uniqueItems"):
            require(len({json.dumps(item, sort_keys=True) for item in value}) == len(value), f"{path}: duplicate item")
        prefix = schema.get("prefixItems", [])
        require(len(value) >= len(prefix), f"{path}: prefix item missing")
        for index, child in enumerate(prefix):
            validate(value[index], child, f"{path}[{index}]")
        child = schema.get("items")
        if child is False:
            require(len(value) == len(prefix), f"{path}: additional array item")
        elif isinstance(child, dict):
            for index in range(len(prefix), len(value)):
                validate(value[index], child, f"{path}[{index}]")
    elif kind == "string":
        require(isinstance(value, str), f"{path}: expected string")
    elif kind == "integer":
        require(isinstance(value, int) and not isinstance(value, bool), f"{path}: expected integer")
    elif kind == "boolean":
        require(isinstance(value, bool), f"{path}: expected boolean")
    if "pattern" in schema:
        require(isinstance(value, str) and re.fullmatch(schema["pattern"], value), f"{path}: pattern mismatch")


def verify_flags(value: dict[str, Any], path: str) -> None:
    for key, expected in flags().items():
        require(value.get(key) is expected, f"{path}: unsafe flag {key}")
    require(value.get("provisional") is True, f"{path}: provisional flag missing")


def verify_writer(value: dict[str, Any]) -> None:
    require(value == writer_contract(), "writer contract drift")
    require(value["authority"] == authority(), "writer authority drift")
    verify_flags(value, WRITER_DOC)
    require(value["writer"]["instanceCardinality"] == "EXACTLY_ONE_PER_ACTIVE_WORKSPACE_GENERATION", "sole writer weakened")
    require(value["writer"]["commands"] == COMMAND_KINDS, "closed command registry drift")
    require(value["writer"]["operationalCommands"] == OPERATIONAL_COMMAND_KINDS, "operational command registry drift")
    require(value["writer"]["previewOnlyCommands"] == PREVIEW_ONLY_COMMAND_KINDS, "preview-only command registry drift")
    require(value["writer"]["previewOnlyDisposition"] == "TYPED_SEMANTIC_PLAN_ONLY_PRODUCTION_ADAPTER_REJECTS", "preview-only command activated")
    require(
        sorted(value["writer"]["operationalCommands"] + value["writer"]["previewOnlyCommands"])
        == COMMAND_KINDS,
        "writer command partitions do not close",
    )
    require(value["revisionContract"] == revision_contract(), "revision contract drift")
    require(value["idempotencyContract"] == idempotency_contract(), "idempotency contract drift")
    require(value["revisionContract"]["durableSequenceClaimed"] is False, "C01 claimed durable revisions")
    require(value["idempotencyContract"]["durableReplayClaimed"] is False, "C01 claimed durable replay")
    reservation = value["c02Reservation"]
    require(reservation["owner"] == "V23-P02-C02" and reservation["activationAllowed"] is False, "C02 reservation weakened")
    require(reservation["reservedArtifacts"] == C02_RESERVED, "C02 reserved artifact drift")


def verify_reversal(value: dict[str, Any]) -> None:
    require(value == reversal_contract(), "reversal contract drift")
    verify_flags(value, REVERSAL_DOC)
    require(value["closedCommandKinds"] == COMMAND_KINDS, "reversal command registry drift")
    require(value["previewOnlyCommandKinds"] == PREVIEW_ONLY_COMMAND_KINDS, "reversal preview-only registry drift")
    require([row["commandKind"] for row in value["registry"]] == COMMAND_KINDS, "reversal row ordering drift")
    require({row["classification"] for row in value["registry"]} == {"REVERSIBLE", "COMPENSATABLE", "IRREVERSIBLE"}, "reversal classification incomplete")
    require(value["unknownCommandDisposition"] == "FAIL_CLOSED_IRREVERSIBLE", "unknown reversal permissive")
    require(value["activation"] == {"previewOnly": True, "commitEnabled": False, "basisPersistenceEnabled": False, "receiptPersistenceEnabled": False, "activationOwner": "V23-P02-C02"}, "reversal activated early")
    require(value["preview"]["eligibilityBasis"] == "GRAPH_AND_REVISION_NOT_TIME_ONLY", "time-only reversal introduced")
    require(value["preview"]["unboundedPreimageAllowed"] is False, "unbounded reversal preimage allowed")
    archive = next(
        row
        for row in value["registry"]
        if row["commandKind"] == "archive_entities_preview_compensation"
    )
    require(
        archive == {
            "commandKind": "archive_entities_preview_compensation",
            "classification": "COMPENSATABLE",
            "reason": "APPEND_SEMANTIC_SUCCESSOR_ONLY",
            "previewAvailable": True,
            "commitActive": False,
        },
        "archive preview command contract drift",
    )


def verify_boundary(value: dict[str, Any]) -> None:
    require(value == boundary_contract(), "boundary contract drift")
    verify_flags(value, BOUNDARY_DOC)
    require(value["closureClaimed"] is False, "provisional tooling falsely claims closure")
    rows = value["reservedDeferredDirectWriters"]
    require([(row["path"], row["symbol"], row["role"]) for row in rows] == DIRECT_WRITERS, "direct writer inventory drift")
    require(all(row["closureClaimed"] is False for row in rows), "direct writer falsely closed")
    require([row["disposition"] for row in rows[:2]] == ["FENCED_CANDIDATE_REBIND_IMPLEMENTED_STATIC_ONLY"] * 2, "fenced rebinding disposition drift")
    require(all(row["disposition"] == "RESERVED_DEFERRED_TO_RECONCILIATION_OR_ACCEPTED_SUBAUTHORITY" for row in rows[2:]), "deferred writer disposition drift")
    require(value["requiredClosure"]["productionFeatureOwnedInsertSaveDeleteRemaining"] == 0, "closure target weakened")
    observed = value["observedProvisionalBoundary"]
    require(observed["productionFeatureOwnedInsertSaveDeleteRemaining"] == 2, "provisional remaining feature writers understated")
    require(observed["reservedFeatureDirectWritePaths"] == ["FieldEvidenceApp/Features/Issues/WorkCoordinator.swift", "FieldEvidenceApp/Features/Shell/AppShellView.swift"], "reserved feature writer inventory drift")
    require(observed["acceptanceBlockedUntilReconciliation"] is True, "provisional boundary accepted early")
    absence = value["c02AbsenceProof"]
    require(absence["reservedNames"] == C02_RESERVED, "C02 absence names drift")
    require(all(absence[key] is False for key in ("durableEnvelopeSchemaPresent", "durableReceiptSchemaPresent", "durableReversalBasisPresent", "durableReplayOrQuarantinePresent")), "C02 artifact activated")


def verify_fixture(value: dict[str, Any]) -> None:
    require(value == mutation_fixture(), "mutation vector fixture drift")
    verify_flags(value, FIXTURE)
    require(value["synthetic"] is True and value["containsCustomerData"] is False and value["containsSecrets"] is False, "fixture privacy declaration weakened")
    require(value["commandDigest"] != value["changedCommandDigest"], "changed-input hostile vector collapsed")
    families = {row["evidenceFamily"] for row in value["vectors"]}
    require(families == {"G01", "A01", "H01", "I01", "R01"}, "evidence family vectors incomplete")
    require(value["c02ArtifactsPresent"] == [] and value["c02ReservedNames"] == C02_RESERVED, "fixture activates C02 artifacts")


def verify_manifest(value: dict[str, Any], root: Path) -> None:
    verify_seal(value, MANIFEST)
    verify_flags(value, MANIFEST)
    require(value["authority"] == authority(), "manifest authority drift")
    require(value["pathFence"] == TOOL_PATHS and value["toolingPathCount"] == len(TOOL_PATHS), "tool path fence drift")
    require(value["generatedPaths"] == GENERATED_PATHS, "generated path list drift")
    require(value["boundaryClosureClaimed"] is False and value["c02ArtifactsActivated"] is False, "manifest false acceptance")
    rows = value["artifacts"]
    require([row["path"] for row in rows] == MANIFEST_INPUT_PATHS, "artifact ordering drift")
    require(value["artifactCount"] == len(rows), "artifact count drift")
    require(
        set(GENERATED_PATHS) - {MANIFEST} <= {row["path"] for row in rows},
        "generated artifact omitted from manifest binding",
    )
    for row in rows:
        data = (root / row["path"]).read_bytes()
        require(row["bytes"] == len(data) and row["sha256"] == sha(data), f"{row['path']}: manifest binding drift")
    require(value["artifactSetDigest"] == sha(pretty(rows)), "artifact set digest mismatch")


def hostile_checks(writer: dict[str, Any], reversal: dict[str, Any], boundary: dict[str, Any], fixture: dict[str, Any]) -> None:
    candidates = []
    item = copy.deepcopy(writer); item["writer"]["instanceCardinality"] = "MANY"; candidates.append(("writer", item))
    item = copy.deepcopy(writer); item["idempotencyContract"]["durableReplayClaimed"] = True; candidates.append(("writer", item))
    item = copy.deepcopy(reversal); item["activation"]["commitEnabled"] = True; candidates.append(("reversal", item))
    item = copy.deepcopy(reversal); item["unknownCommandDisposition"] = "ALLOW"; candidates.append(("reversal", item))
    item = copy.deepcopy(boundary); item["closureClaimed"] = True; candidates.append(("boundary", item))
    item = copy.deepcopy(boundary); item["reservedDeferredDirectWriters"] = item["reservedDeferredDirectWriters"][:-1]; candidates.append(("boundary", item))
    item = copy.deepcopy(fixture); item["containsCustomerData"] = True; candidates.append(("fixture", item))
    functions = {"writer": verify_writer, "reversal": verify_reversal, "boundary": verify_boundary, "fixture": verify_fixture}
    for kind, candidate in candidates:
        rejected = False
        try:
            functions[kind](candidate)
        except ContractError:
            rejected = True
        require(rejected, f"hostile {kind} mutation accepted")


def verify_scripts(root: Path) -> None:
    for path in (CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT):
        ast.parse((root / path).read_text(encoding="utf-8"), filename=path)
    result = subprocess.run(
        [sys.executable, "-B", str(root / GENERATOR_SCRIPT), "--check", "--root", str(root)],
        cwd=root, capture_output=True, text=True,
    )
    require(result.returncode == 0, f"generator --check failed: {result.stderr.strip()}")
    require("verified 8 generated artifacts" in result.stdout, "generator output drift")


def verify_swift_candidate(root: Path) -> None:
    paths = {
        "contracts": "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
        "writer": "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
        "adapter": "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
        "session": "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
        "composition": "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift",
        "first_sign": "FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift",
        "check_runner": "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
        "work": "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
        "shell": "FieldEvidenceApp/Features/Shell/AppShellView.swift",
        "tests": "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    }
    source = {key: (root / path).read_text(encoding="utf-8") for key, path in paths.items()}
    required_tokens = {
        "contracts": ["struct MutationIDV1", "enum WorkspaceCommandV1", "protocol WorkspaceQueryClientV1", "struct MutationBoundaryClosureReceiptV1", "enum MutationReversalPolicyRegistryV1", "struct SemanticReversalPlanV1", "writerInstanceID"],
        "writer": ["final class WorkspaceWriterV1", "func execute(", "func invalidate()", "wrongWriterInstance", "maximumRememberedMutationCount"],
        "adapter": ["final class WorkspaceWriterAdapterV1", "func createFirstSign(", "func createCheckDraft(", "func acceptCheckEvidence(", "func updateSiteTimeZone("],
        "session": ["private(set) var workspaceWriter: WorkspaceWriterV1", "workspaceWriter.invalidate()", "workspaceQueryClient"],
        "composition": ["workspaceWriter: WorkspaceWriterV1", "workspaceWriter: workspaceWriter", "fileAuthority: fileAuthority"],
    }
    for key, tokens in required_tokens.items():
        require(all(token in source[key] for token in tokens), f"{paths[key]}: required writer binding missing")

    direct_write = re.compile(r"\bmodelContext\.(?:insert|save|delete)\s*\(")
    direct_authority = re.compile(r"\b(?:Date|UUID)\s*\(\s*\)")
    for key in ("first_sign", "check_runner"):
        require(not direct_write.search(source[key]), f"{paths[key]}: unreserved direct mutation remains")
        require(not direct_authority.search(source[key]), f"{paths[key]}: nondeterministic authority remains")
    require(direct_write.search(source["work"]) is not None, "reserved WorkCoordinator bypass disappeared without reconciliation")
    require(direct_write.search(source["shell"]) is not None, "reserved AppShellView bypass disappeared without reconciliation")
    require(source["session"].count("WorkspaceWriterV1(") == 1, "StoreSessionCoordinator must install one writer factory")
    command_kind_match = re.search(
        r"enum\s+WorkspaceCommandKindV1\s*:[^{]+\{(?P<body>.*?)\n\}",
        source["contracts"],
        re.DOTALL,
    )
    require(command_kind_match is not None, "Swift command-kind registry missing")
    swift_command_kinds = re.findall(
        r'^\s*case\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*"([^"]+)"\s*$',
        command_kind_match.group("body"),
        re.MULTILINE,
    )
    require(
        len(swift_command_kinds) == len(set(swift_command_kinds))
        and set(swift_command_kinds) == set(COMMAND_KINDS),
        f"Swift command-kind set differs: {swift_command_kinds}",
    )
    require(
        'case archiveEntities = "archive_entities_preview_compensation"' in source["contracts"],
        "Swift preview-only archive command missing",
    )
    require(
        re.search(r"(?:case\s+)?\.archiveEntities\s*:\s*\n\s*throw\s+WorkspaceMutationFailureV1\.unsupportedCommand", source["adapter"])
        is not None,
        "production adapter does not reject preview-only archive command",
    )
    test_methods = re.findall(r"func (testV9_08(?:G01|A01|H01|I01|R01)[A-Za-z0-9_]*)\s*\(", source["tests"])
    require(len(test_methods) == 5 and len(set(test_methods)) == 5, "exact five V9_08 evidence tests required")
    fenced_swift = {
        path: (root / path).read_text(encoding="utf-8")
        for path in FENCED_SWIFT_PATHS
    }
    for reserved in C02_RESERVED:
        token = re.compile(rf"\b{re.escape(reserved)}\b")
        offenders = [path for path, text in fenced_swift.items() if token.search(text)]
        require(not offenders, f"C02 artifact named early: {reserved}: {offenders}")


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        expected = all_outputs(root)
        for path, data in expected.items():
            require((root / path).is_file() and (root / path).read_bytes() == data, f"stale generated artifact: {path}")
        writer = load(root, WRITER_DOC)
        reversal = load(root, REVERSAL_DOC)
        boundary = load(root, BOUNDARY_DOC)
        fixture = load(root, FIXTURE)
        manifest = load(root, MANIFEST)
        for value, path in ((writer, WRITER_DOC), (reversal, REVERSAL_DOC), (boundary, BOUNDARY_DOC), (fixture, FIXTURE)):
            verify_seal(value, path)
            verify_authority_digests(value, path)
        validate(writer, load(root, WRITER_SCHEMA))
        validate(reversal, load(root, REVERSAL_SCHEMA))
        validate(boundary, load(root, BOUNDARY_SCHEMA))
        verify_writer(writer)
        verify_reversal(reversal)
        verify_boundary(boundary)
        verify_fixture(fixture)
        verify_manifest(manifest, root)
        require(writer["evidenceIDs"] == reversal["evidenceIDs"] == boundary["evidenceIDs"] == manifest["evidenceIDs"] == EVIDENCE_IDS, "evidence ID closure drift")
        hostile_checks(writer, reversal, boundary, fixture)
        verify_scripts(root)
        verify_swift_candidate(root)
    except (ContractError, OSError, UnicodeError, json.JSONDecodeError, KeyError, TypeError, ValueError, SyntaxError, subprocess.SubprocessError) as error:
        print(f"V23-P02-C01 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P02-C01 strict schemas, hostile contracts, and canonical manifest closure verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
