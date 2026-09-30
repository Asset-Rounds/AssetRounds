#!/usr/bin/env python3
"""Fail-closed static verifier for provisional V23-P03-C07."""
from __future__ import annotations

import base64
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import unquote

sys.dont_write_bytecode = True
import p03_c07_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition: raise VerificationError(message)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout.strip()


def load(path: Path) -> dict[str, Any]:
    raw = path.read_bytes(); require(not raw.startswith(b"\xef\xbb\xbf"), f"BOM forbidden: {path}")
    duplicates: list[str] = []
    def pairs(rows: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in rows:
            if key in value: duplicates.append(key)
            value[key] = item
        return value
    result = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    require(not duplicates and isinstance(result, dict), f"invalid/duplicate JSON object: {path}")
    return result


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values(): yield from walk(child)
    elif isinstance(value, list):
        for child in value: yield from walk(child)


def resolve_local_ref(document: dict[str, Any], reference: Any, label: str) -> Any:
    require(isinstance(reference, str) and (reference == "#" or reference.startswith("#/")),
            f"nonlocal or malformed ref: {label}: {reference!r}")
    target: Any = document
    if reference == "#": return target
    for encoded in reference[2:].split("/"):
        token = unquote(encoded).replace("~1", "/").replace("~0", "~")
        if isinstance(target, dict):
            require(token in target, f"unresolved local ref: {label}: {reference}")
            target = target[token]
        elif isinstance(target, list):
            require(token.isdigit() and int(token) < len(target),
                    f"unresolved local ref index: {label}: {reference}")
            target = target[int(token)]
        else:
            raise VerificationError(f"local ref traverses scalar: {label}: {reference}")
    return target


def audit_local_refs(document: dict[str, Any], label: str) -> int:
    resolved: set[str] = set()

    def audit_reference(reference: Any, active: set[str]) -> None:
        target = resolve_local_ref(document, reference, label)
        assert isinstance(reference, str)
        resolved.add(reference)
        if reference in active: return
        for node in walk(target):
            if isinstance(node, dict) and "$ref" in node:
                audit_reference(node["$ref"], active | {reference})

    for node in walk(document):
        if isinstance(node, dict) and "$ref" in node:
            audit_reference(node["$ref"], set())
    return len(resolved)


def changed_paths(root: Path) -> set[str]:
    return {row[3:].replace("\\", "/") for row in git(root, "status", "--porcelain=v1", "--untracked-files=all").splitlines() if len(row) >= 4}


def independently_generated(root: Path) -> dict[str, bytes]:
    command = [sys.executable, "-B", str(root / contracts.SCRIPT_PATHS[1]), "--dump-json"]
    environment = dict(os.environ); environment["PYTHONDONTWRITEBYTECODE"] = "1"
    first = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True, text=True)
    second = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True, text=True)
    require(first.stdout == second.stdout, "independent subprocess generation is not deterministic")
    return {path: base64.b64decode(value, validate=True) for path, value in json.loads(first.stdout).items()}


def validate_json_schema_net(root: Path, fixture: dict[str, Any]) -> int:
    assembly = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/JsonSchema.Net.dll"
    require(assembly.is_file(), "pinned offline JsonSchema.Net assembly unavailable")
    require(digest(assembly.read_bytes()) == "1243dc7749d37818beadf8967c3963082ba00efe05877e3f180346e9f56007a0",
            "pinned JsonSchema.Net digest differs")
    positives = contracts.sample_instances(root)
    require(set(positives) == set(contracts.SCHEMA_PATHS), "positive sample inventory differs")
    negatives: list[tuple[str, str, dict[str, Any]]] = []
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[0]]); value["activationEnabled"] = True
    negatives.append(("ACTIVATION_ENABLED", contracts.SCHEMA_PATHS[0], value))
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[1]]); value["recordRegistrations"][0]["descriptor"]["kind"] = "UnknownKind"
    negatives.append(("UNKNOWN_RECORD_KIND", contracts.SCHEMA_PATHS[1], value))
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[1]]); value["mutationRegistrations"].pop()
    negatives.append(("MISSING_MUTATION_REGISTRATION", contracts.SCHEMA_PATHS[1], value))
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[1]]); value["recordRegistrations"][0]["mutation"] = value["mutationRegistrations"][0]
    negatives.append(("NESTED_MUTATION_FORBIDDEN", contracts.SCHEMA_PATHS[1], value))
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[1]]); value["relationships"].pop()
    negatives.append(("MISSING_RELATIONSHIP", contracts.SCHEMA_PATHS[1], value))
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[2]]); value["sourceSchema"] = "KERNEL_PERSISTENCE_V5"
    negatives.append(("FUTURE_VERSION", contracts.SCHEMA_PATHS[2], value))
    value = copy.deepcopy(positives[contracts.SCHEMA_PATHS[3]]); value["entries"].append(value["entries"][0])
    negatives.append(("DUPLICATE_LIFECYCLE_KIND", contracts.SCHEMA_PATHS[3], value))
    with tempfile.TemporaryDirectory(prefix="v23-p03-c07-schema-") as temporary:
        temp = Path(temporary); rows: list[dict[str, Any]] = []
        for index, (schema_path, instance) in enumerate(positives.items()):
            target = temp / f"positive-{index}.json"; target.write_bytes(contracts.pretty(instance))
            rows.append({"label": f"POSITIVE_{index}", "schema": str((root/schema_path).resolve()),
                         "instance": str(target.resolve()), "expected": True})
        for index, (label, schema_path, instance) in enumerate(negatives):
            target = temp / f"negative-{index}.json"; target.write_bytes(contracts.pretty(instance))
            rows.append({"label": label, "schema": str((root/schema_path).resolve()),
                         "instance": str(target.resolve()), "expected": False})
        index_path = temp / "index.json"; index_path.write_bytes(contracts.pretty({"rows": rows,
            "schemas": [str((root/path).resolve()) for path in contracts.SCHEMA_PATHS]}))
        quote = lambda path: "'" + str(path.resolve()).replace("'", "''") + "'"
        script = (f"Add-Type -Path {quote(assembly)}; $o=[Json.Schema.EvaluationOptions]::new(); "
            f"$i=Get-Content -LiteralPath {quote(index_path)} -Raw|ConvertFrom-Json; "
            "foreach($p in $i.schemas){$n=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $p -Raw));"
            "$r=[Json.Schema.MetaSchemas]::Draft202012.Evaluate($n,$o);if(-not $r.IsValid){throw ('meta '+$p)}};"
            "foreach($x in $i.rows){$s=[Json.Schema.JsonSchema]::FromFile($x.schema);"
            "$n=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $x.instance -Raw));$r=$s.Evaluate($n,$o);"
            "if($r.IsValid -ne [bool]$x.expected){throw ('instance '+$x.label)}};'PASS'")
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], capture_output=True, text=True)
        require(result.returncode == 0 and result.stdout.strip().endswith("PASS"),
                f"pinned schema validation failed: {result.stderr.strip()}")
    return len(positives) + len(negatives)


def verify(root: Path) -> dict[str, Any]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD, "application base head differs")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE, "application base tree differs")
    require(len(contracts.PATH_FENCE) == 24 and len(set(contracts.PATH_FENCE)) == 24, "exact 24-path fence differs")
    require(contracts.PATH_FENCE == contracts.SOURCE_PATHS + contracts.TOOL_PATHS, "path fence partition/order differs")
    require(len(contracts.SOURCE_PATHS) == 9 and len(contracts.TOOL_PATHS) == 15, "source/tool counts differ")
    require(changed_paths(root) == set(contracts.PATH_FENCE), "full changed-path fence differs")
    for relative in contracts.PATH_FENCE:
        require((root/relative).is_file(), f"missing fenced path: {relative}")
        exists = subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{relative}"], capture_output=True)
        require(exists.returncode != 0, f"all-new path existed at base: {relative}")
    caches = [path for path in root.rglob("*") if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")]
    require(not caches, f"Python cache leaked: {caches}")
    first = contracts.all_outputs(root); second = contracts.all_outputs(root)
    require(first == second and len(first) == 12 and set(first) == set(contracts.GENERATED_PATHS), "in-process generation differs")
    require(independently_generated(root) == first, "independent subprocess output differs")
    for relative, expected in first.items(): require((root/relative).read_bytes() == expected, f"stale artifact: {relative}")
    fixture_path = root/contracts.FIXTURE; fixture = load(fixture_path)
    require(fixture_path.read_bytes() == contracts.canonical(fixture) + b"\n", "fixture is not canonical compact JSON plus LF")
    require(fixture["recordKinds"] == contracts.RECORD_KINDS and len(fixture["recordKinds"]) == 19, "exact record inventory differs")
    expected_relationships = [f"{source}.{rid.split('.',1)[1]}->{target}" for rid, source, target, _ in contracts.RELATIONSHIPS]
    require(fixture["relationshipKinds"] == expected_relationships and len(expected_relationships) == 20, "exact relationship inventory differs")
    require(fixture["migrationBoundaries"] == contracts.MIGRATION_STAGES and fixture["lifecycleOperations"] == contracts.LIFECYCLE_OPERATIONS,
            "migration/lifecycle corpus differs")
    require(fixture["evidenceIDs"] == contracts.EVIDENCE_IDS and len(fixture["evidenceIDs"]) == 5, "exact evidence IDs differ")
    schemas = {path: load(root/path) for path in contracts.SCHEMA_PATHS}
    reference_counts: dict[str, int] = {}
    for relative, schema in schemas.items():
        require(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", f"dialect differs: {relative}")
        require(schema["type"] == "object" and schema["additionalProperties"] is False, f"root not strict: {relative}")
        for node in walk(schema):
            if isinstance(node, dict) and node.get("type") == "object" and "properties" in node:
                require(node.get("additionalProperties") is False, f"nested object not strict: {relative}")
        reference_counts[relative] = audit_local_refs(schema, relative)
    require(reference_counts[contracts.SCHEMA_PATHS[0]] > 0 and
            reference_counts[contracts.SCHEMA_PATHS[1]] > 0 and
            reference_counts[contracts.SCHEMA_PATHS[2]] > 0 and
            reference_counts[contracts.SCHEMA_PATHS[3]] > 0 and
            reference_counts[contracts.SCHEMA_PATHS[4]] > 0,
            f"expected schema reference closure differs: {reference_counts}")
    sample_count = validate_json_schema_net(root, fixture)
    descriptor = contracts.persistence_descriptor(); require(descriptor["schemaVersion"] == 4 and
        descriptor["runtimePosture"] == "DORMANT_STATIC_UNTIL_S10_6" and descriptor["activationEnabled"] is False,
        "dormant V4 schema descriptor differs")
    require(len(descriptor["records"]) == 19 and len(descriptor["relationships"]) == 20, "descriptor closure differs")
    mapping = contracts.mapping_registry(); require(len(mapping["recordRegistrations"]) == 19 and
        len(mapping["mutationRegistrations"]) == 19 and mapping["closedWorld"] is True and
        mapping["unknownKindDisposition"] == "REJECT", "mapping registry closure differs")
    records = mapping["recordRegistrations"]; mutations = mapping["mutationRegistrations"]
    require(all(row["replication"] == "EXCLUDED_NO_TRANSPORT" and "mutation" not in row for row in records),
            "record registry shape/replication differs")
    require([row["descriptor"]["kind"] for row in records] == contracts.RECORD_KINDS and
            [row["kind"] for row in mutations] == contracts.RECORD_KINDS,
            "record/mutation registry kind closure differs")
    require(all(mutation["kind"] == record["descriptor"]["kind"] and
        mutation["effectID"] == record["descriptor"]["canonicalMutationEffectID"] and
        mutation["expectedRevisionRequired"] is True and mutation["durableReceiptRequired"] is True and
        mutation["effectBeforeReceiptRecovery"] is True for record, mutation in zip(records, mutations)),
        "mutation envelope/effect/receipt registry closure differs")
    registry_material = {"recordRegistrations": records, "mutationRegistrations": mutations,
                         "relationships": mapping["relationships"]}
    require(mapping["recordRegistryCanonicalDigest"] == digest(contracts.canonical(records)) and
            mapping["mutationRegistryCanonicalDigest"] == digest(contracts.canonical(mutations)) and
            mapping["canonicalDigest"] == digest(contracts.canonical(registry_material)),
            "separate registry digest closure differs")
    migration = contracts.migration_plan(); require(migration["staged"] and migration["atomicActivation"] and
        migration["preActivationRollback"] == "DISCARD_STAGING" and migration["postWriteRecovery"] == "FORWARD_FIX_READ_EXPORT_ONLY",
        "migration/rollback boundary differs")
    lifecycle = contracts.lifecycle_registry(); require(lifecycle["recordKindCount"] == 19 and len(lifecycle["entries"]) == 19 and
        all(row["clearsTombstonesOnDelete"] is False for row in lifecycle["entries"]) and
        sum(row["clearsTombstonesOnErase"] is True for row in lifecycle["entries"]) == 2,
        "Erase-only tombstone lifecycle differs")
    require({"UNKNOWN_RECORD_KIND", "UNMAPPED_RELATIONSHIP"}.issubset(fixture["declaredFailureCases"]),
            "hostile fixture failure coverage differs")
    migration_contract = load(root/contracts.CONTRACT_PATHS[2])
    lifecycle_contract = load(root/contracts.CONTRACT_PATHS[3])
    require(migration_contract["failureCases"] == contracts.MIGRATION_FAILURE_CASES and
            lifecycle_contract["failureCases"] == contracts.LIFECYCLE_FAILURE_CASES and
            {"UNKNOWN_RECORD_KIND", "UNMAPPED_RELATIONSHIP"}.issubset(migration_contract["failureCases"]) and
            {"UNKNOWN_RECORD_KIND", "UNMAPPED_RELATIONSHIP"}.issubset(lifecycle_contract["failureCases"]),
            "migration/lifecycle hostile failure coverage differs")
    methods = re.findall(r"func\s+(testV9_17(?:G01|A01|H01|I01|R01)[A-Za-z0-9_]*)\s*\(",
                         (root/contracts.SOURCE_PATHS[7]).read_text(encoding="utf-8"))
    require(len(methods) == 5 and len(set(methods)) == 5, f"exact five named test methods differ: {methods}")
    fenced_text = "\n".join((root/path).read_text(encoding="utf-8") for path in contracts.PATH_FENCE)
    forbidden = ["URL"+"Session", "Cloud"+"Kit", "Fire"+"base", "signed"+"URL", "service"+"Credential",
        "Test"+"Flight", "App"+"Store", r"nativeCompileRan\s*[:=]\s*true", r"hostedDispatchRan\s*[:=]\s*true",
        r"adoptionEnabled\s*[:=]\s*true", r"acceptanceCredit\s*[:=]\s*true", r"releaseCredit\s*[:=]\s*true"]
    for pattern in forbidden: require(re.search(pattern, fenced_text, re.I) is None, f"forbidden full-fence claim/token: {pattern}")
    for relative in contracts.CONTRACT_PATHS[:4]:
        value = load(root/relative); unsigned = dict(value); seal = unsigned.pop("artifactDigest")
        require(seal == digest(contracts.pretty(unsigned)) and value["authority"] == contracts.authority(), f"contract seal/authority differs: {relative}")
        for flag in ("nativeCompileRan", "hostedDispatchRan", "hostedDispatchEnabled", "adoptionEnabled", "acceptanceEnabled",
                     "acceptanceCredit", "releaseReady", "releaseCredit"):
            require(value[flag] is False, f"forbidden claim {flag}: {relative}")
    evidence = load(root/contracts.CONTRACT_PATHS[4]); require(evidence["evidenceIDs"] == contracts.EVIDENCE_IDS and
        evidence["result"] == "PASS" and evidence["verificationMode"] == "STATIC_ONLY", "evidence receipt differs")
    require(evidence["sourceArtifacts"] == [{"path": path, "sha256": digest((root/path).read_bytes())} for path in contracts.SOURCE_PATHS],
            "source evidence closure differs")
    tooling = load(root/contracts.MANIFEST); unsigned = dict(tooling); seal = unsigned.pop("artifactDigest")
    require(seal == digest(contracts.pretty(unsigned)) and tooling["pathFence"] == contracts.PATH_FENCE and tooling["pathFenceCount"] == 24,
            "tooling manifest seal/fence differs")
    require(tooling["artifactCount"] == 23 and len(tooling["artifacts"]) == 23 and tooling["pendingArtifactCount"] == 0,
            "tooling artifact closure differs")
    return {"result": "PASS", "verificationMode": "STATIC_ONLY", "cardID": contracts.CARD, "pathFenceCount": 24,
        "strictSchemaCount": 6, "sampleValidationCount": sample_count, "recordKindCount": 19, "relationshipKindCount": 20,
        "evidenceIDCount": 5, "nativeCompileRan": False, "hostedDispatchRan": False, "adoptionEnabled": False,
        "acceptanceCredit": False, "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True}


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try: result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C07 verification failed: {error}", file=sys.stderr); return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":"))); return 0


if __name__ == "__main__":
    raise SystemExit(main())
