#!/usr/bin/env python3
"""Fail-closed static verifier for provisional V23-P03-C08."""
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
import p03_c08_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def git(root: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(["git", "-C", str(root), *args], check=check, capture_output=True, text=True)
    return result.stdout.strip()


def load(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), f"BOM forbidden: {path}")
    duplicates: list[str] = []

    def pairs(rows: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in rows:
            if key in value:
                duplicates.append(key)
            value[key] = item
        return value

    result = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    require(not duplicates and isinstance(result, dict), f"invalid/duplicate JSON object: {path}")
    return result


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def resolve_local_ref(document: dict[str, Any], reference: Any, label: str) -> Any:
    require(isinstance(reference, str) and (reference == "#" or reference.startswith("#/")),
            f"nonlocal or malformed ref: {label}: {reference!r}")
    target: Any = document
    if reference == "#":
        return target
    for encoded in reference[2:].split("/"):
        token = unquote(encoded).replace("~1", "/").replace("~0", "~")
        if isinstance(target, dict):
            require(token in target, f"unresolved local ref: {label}: {reference}")
            target = target[token]
        elif isinstance(target, list):
            require(token.isdigit() and int(token) < len(target), f"unresolved local ref index: {label}: {reference}")
            target = target[int(token)]
        else:
            raise VerificationError(f"local ref traverses scalar: {label}: {reference}")
    return target


def audit_local_refs(document: dict[str, Any], label: str) -> int:
    resolved: set[str] = set()

    def audit(reference: Any, active: set[str]) -> None:
        target = resolve_local_ref(document, reference, label)
        assert isinstance(reference, str)
        resolved.add(reference)
        if reference in active:
            return
        for node in walk(target):
            if isinstance(node, dict) and "$ref" in node:
                audit(node["$ref"], active | {reference})

    for node in walk(document):
        if isinstance(node, dict) and "$ref" in node:
            audit(node["$ref"], set())
    return len(resolved)


def changed_paths(root: Path) -> set[str]:
    rows = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    return {row[3:].replace("\\", "/") for row in rows if len(row) >= 4}


def independently_generated(root: Path) -> dict[str, bytes]:
    command = [sys.executable, "-B", str(root / contracts.SCRIPT_PATHS[1]), "--dump-json"]
    environment = dict(os.environ)
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    first = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True, text=True)
    second = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True, text=True)
    require(first.stdout == second.stdout, "independent subprocess generation is not deterministic")
    return {path: base64.b64decode(value, validate=True) for path, value in json.loads(first.stdout).items()}


def added_lines(root: Path, relative: str) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(root), "diff", "--no-ext-diff", "--unified=0", contracts.APP_BASE_HEAD, "--", relative],
        check=True, capture_output=True, text=True,
    )
    return [line[1:] for line in result.stdout.splitlines() if line.startswith("+") and not line.startswith("+++")]


def scan_disjoint_changes(root: Path) -> dict[str, list[str]]:
    feature_raw: list[str] = []
    view_context: list[str] = []
    fallbacks: list[str] = []
    duplicates: list[str] = []
    purpose_branches: list[str] = []
    for relative in contracts.PRODUCT_PATHS:
        for line_number, line in enumerate(added_lines(root, relative), 1):
            compact = line.strip()
            label = f"{relative}:added-{line_number}"
            if "/Features/" in relative and re.search(r"\.(?:insert|delete|save)\s*\(", compact):
                feature_raw.append(label)
            if re.search(r"(?:@Environment\s*\(\s*\\\.modelContext\s*\)|\bModelContext\b)", compact) and relative.endswith("View.swift"):
                view_context.append(label)
            if re.search(r"\?\?\s*(?:try\??\s+)?WorkspaceWriterAdapterV1\s*\(", compact) or \
                    re.search(
                        r"\b(?:WorkspaceWriterV1|WorkspacePackageLifecycleDependenciesV1|"
                        r"WorkspacePackageLifecycleProfileRegistryV1)\s*\?",
                        compact,
                    ):
                fallbacks.append(label)
            if "ModelContainer(" in compact:
                duplicates.append(label)
            if "WorkspaceWriterV1(" in compact and relative != "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift":
                duplicates.append(label)
            if re.search(r"\b(?:class|struct|actor)\s+(?:WorkspaceWriter|WorkspaceQuery|MutationAuthority|PersistenceAuthority)\w*", compact) and relative not in {
                "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
                "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
                "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
            }:
                duplicates.append(label)
            if re.search(r"\b(?:if|switch|case)\b.*\b(?:purposeKey|purposeID|packID)\b.*(?:sign|SIGN)", compact):
                purpose_branches.append(label)
    return {
        "newDisjointFeatureRawWriteViolations": sorted(set(feature_raw)),
        "newDisjointViewModelContextViolations": sorted(set(view_context)),
        "newOptionalFallbackAdapterViolations": sorted(set(fallbacks)),
        "duplicateWriterContainerAuthorityViolations": sorted(set(duplicates)),
        "hardCodedPurposeBranchViolations": sorted(set(purpose_branches)),
    }


def validate_json_schema_net(root: Path, positives: list[dict[str, Any]]) -> int:
    assembly = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/JsonSchema.Net.dll"
    require(assembly.is_file(), "pinned offline JsonSchema.Net assembly unavailable")
    require(digest(assembly.read_bytes()) == "1243dc7749d37818beadf8967c3963082ba00efe05877e3f180346e9f56007a0",
            "pinned offline JsonSchema.Net digest differs")
    negatives: list[tuple[str, dict[str, Any]]] = []
    value = copy.deepcopy(positives[1]); value["provisionalZeroViolationClosureClaimed"] = True
    negatives.append(("ZERO_CLOSURE_MISCLAIM", value))
    value = copy.deepcopy(positives[1]); value["reservedOwnerDebtPaths"].pop()
    negatives.append(("MISSING_RESERVED_OWNER", value))
    value = copy.deepcopy(positives[1]); value["reservedRawWriteDebtPaths"].pop()
    negatives.append(("MISSING_RAW_WRITE_DEBT", value))
    value = copy.deepcopy(positives[1]); value["acceptanceCredit"] = True
    negatives.append(("ACCEPTANCE_CREDIT", value))
    value = copy.deepcopy(positives[0]); value["workspaceIsolation"]["crossWorkspaceWritesAllowed"] = True
    negatives.append(("CROSS_WORKSPACE_WRITE", value))
    value = copy.deepcopy(positives[0]); value["routes"].append(value["routes"][0]); value["routes"].pop(1)
    negatives.append(("DUPLICATE_ROUTE", value))
    value = copy.deepcopy(positives[0]); value["packages"][0]["unexpected"] = True
    negatives.append(("OPEN_NESTED_OBJECT", value))
    with tempfile.TemporaryDirectory(prefix="v23-p03-c08-schema-") as temporary:
        temp = Path(temporary)
        schema_path = (root / contracts.SCHEMA_PATH).resolve()
        rows: list[dict[str, Any]] = []
        for index, instance in enumerate(positives):
            target = temp / f"positive-{index}.json"
            target.write_bytes(contracts.pretty(instance))
            rows.append({"label": f"POSITIVE_{index}", "instance": str(target.resolve()), "expected": True})
        for index, (label, instance) in enumerate(negatives):
            target = temp / f"negative-{index}.json"
            target.write_bytes(contracts.pretty(instance))
            rows.append({"label": label, "instance": str(target.resolve()), "expected": False})
        index_path = temp / "index.json"
        index_path.write_bytes(contracts.pretty({"rows": rows, "schema": str(schema_path)}))
        quote = lambda path: "'" + str(path).replace("'", "''") + "'"
        script = (
            f"Add-Type -Path {quote(assembly)}; $o=[Json.Schema.EvaluationOptions]::new(); "
            f"$i=Get-Content -LiteralPath {quote(index_path)} -Raw|ConvertFrom-Json; "
            "$sn=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $i.schema -Raw));"
            "$mr=[Json.Schema.MetaSchemas]::Draft202012.Evaluate($sn,$o);if(-not $mr.IsValid){throw 'meta'};"
            "$s=[Json.Schema.JsonSchema]::FromFile($i.schema);foreach($x in $i.rows){"
            "$n=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $x.instance -Raw));"
            "$r=$s.Evaluate($n,$o);if($r.IsValid -ne [bool]$x.expected){throw ('instance '+$x.label)}};'PASS'"
        )
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], capture_output=True, text=True)
        require(result.returncode == 0 and result.stdout.strip().endswith("PASS"),
                f"pinned schema validation failed: {result.stderr.strip()}")
    return len(positives) + len(negatives)


def verify(root: Path) -> dict[str, Any]:
    require(git(root, "rev-parse", "HEAD") == contracts.APP_BASE_HEAD, "application base head differs")
    require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE, "application base tree differs")
    require(len(contracts.PATH_FENCE) == 30 and len(set(contracts.PATH_FENCE)) == 30, "exact 30-path fence differs")
    require(contracts.PATH_FENCE == contracts.SOURCE_PATHS + contracts.TOOL_PATHS, "path-fence partition/order differs")
    require(len(contracts.SOURCE_PATHS) == 23 and len(contracts.TOOL_PATHS) == 7, "source/tool count differs")
    require(len(contracts.EXISTING_PATHS) == 19 and len(contracts.NEW_PATHS) == 11, "existing/new count differs")
    require(set(contracts.EXISTING_PATHS).isdisjoint(contracts.NEW_PATHS), "existing/new inventories overlap")
    require(set(contracts.EXISTING_PATHS) | set(contracts.NEW_PATHS) == set(contracts.PATH_FENCE), "existing/new closure differs")
    require(changed_paths(root) == set(contracts.PATH_FENCE), "full changed-path fence differs")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")
        exists = subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{contracts.APP_BASE_HEAD}:{relative}"], capture_output=True)
        require((exists.returncode == 0) == (relative in contracts.EXISTING_PATHS), f"base existence differs: {relative}")
    require(len(contracts.ACTIVE_S10_RESERVED_PATHS) == 86 and len(set(contracts.ACTIVE_S10_RESERVED_PATHS)) == 86,
            "frozen S10 reservation inventory differs")
    require(not (set(contracts.PATH_FENCE) & set(contracts.ACTIVE_S10_RESERVED_PATHS)), "S10 fence overlap detected")
    require(len(contracts.RESERVED_OWNER_DEBTS) == 10 and len(contracts.RESERVED_RAW_WRITE_DEBTS) == 2 and
            set(contracts.RESERVED_RAW_WRITE_DEBTS).issubset(contracts.RESERVED_OWNER_DEBTS), "reserved debt inventory differs")
    caches = [path for path in root.rglob("*") if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")]
    require(not caches, f"Python cache leaked: {caches}")

    fixture_path = root / contracts.FIXTURE
    fixture = load(fixture_path)
    require(fixture_path.read_bytes() == contracts.canonical(fixture) + b"\n", "fixture is not canonical compact JSON plus LF")
    require(fixture["packages"] == contracts.PACKAGES and fixture["lifecycleOperations"] == contracts.OPERATIONS,
            "fixture package/operation inventory differs")
    require(fixture["recoveryBoundaries"] == contracts.RECOVERY_BOUNDARIES and fixture["failureCases"] == contracts.FAILURE_CASES,
            "fixture recovery/failure inventory differs")
    require(fixture["workspaceIDs"] == ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"],
            "two-workspace fixture differs")
    require(fixture["reservedOwnerDebtPaths"] == contracts.RESERVED_OWNER_DEBTS and
            fixture["reservedRawWriteDebtPaths"] == contracts.RESERVED_RAW_WRITE_DEBTS and
            fixture["provisionalZeroViolationClosureClaimed"] is False, "fixture debt/claim posture differs")
    require(fixture["evidenceIDs"] == contracts.EVIDENCE_IDS and len(fixture["evidenceIDs"]) == 5, "exact evidence IDs differ")

    first = contracts.all_outputs(root)
    second = contracts.all_outputs(root)
    require(first == second and len(first) == 4 and set(first) == set(contracts.GENERATED_PATHS), "in-process generation differs")
    require(independently_generated(root) == first, "independent subprocess generation differs")
    for relative, expected in first.items():
        require((root / relative).read_bytes() == expected, f"stale generated artifact: {relative}")

    schema = load(root / contracts.SCHEMA_PATH)
    require(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "schema dialect differs")
    require(schema["$id"] == "https://assetrounds.invalid/schemas/v23/pack-lifecycle-integration.schema.json", "schema id differs")
    reference_count = audit_local_refs(schema, contracts.SCHEMA_PATH)
    require(reference_count >= 6, f"schema reference closure unexpectedly weak: {reference_count}")
    for node in walk(schema):
        if isinstance(node, dict) and node.get("type") == "object" and "properties" in node:
            require(node.get("additionalProperties") is False, "open object shape in strict schema")
    positives = contracts.sample_instances(root)
    sample_count = validate_json_schema_net(root, positives)

    contract = load(root / contracts.CONTRACT_PATH)
    closure = load(root / contracts.CLOSURE_PATH)
    for relative, value in ((contracts.CONTRACT_PATH, contract), (contracts.CLOSURE_PATH, closure)):
        unsigned = dict(value); seal = unsigned.pop("artifactDigest")
        require(seal == digest(contracts.pretty(unsigned)), f"artifact seal differs: {relative}")
        require(value["authority"] == contracts.authority(), f"authority differs: {relative}")
        for flag in ("nativeCompileRan", "hostedDispatchRan", "phase10PollingRan", "adoptionEnabled",
                     "acceptanceEnabled", "acceptanceCredit", "releaseReady", "releaseCredit"):
            require(value[flag] is False, f"forbidden claim {flag}: {relative}")
    require([row["packageID"] for row in contract["packages"]] == contracts.PACKAGES, "package ordering differs")
    routes = contract["routes"]
    expected_route_ids = [f"{package}.{operation}" for package in contracts.PACKAGES for operation in contracts.OPERATIONS]
    require([row["routeID"] for row in routes] == expected_route_ids and len(routes) == 26, "closed route inventory differs")
    require(all(row["routeID"] == f'{row["packageID"]}.{row["operation"]}' and row["workspaceScoped"] is True for row in routes),
            "route identity/workspace binding differs")
    require(closure["reservedOwnerDebtPaths"] == contracts.RESERVED_OWNER_DEBTS and
            closure["reservedRawWriteDebtPaths"] == contracts.RESERVED_RAW_WRITE_DEBTS and
            closure["provisionalZeroViolationClosureClaimed"] is False and
            closure["liveZeroViolationClosureAchieved"] is False, "closure debt/posture differs")

    scan = scan_disjoint_changes(root)
    for key, findings in scan.items():
        require(not findings, f"fail-closed source scan {key}: {findings}")
        if key in closure:
            require(closure[key] == findings, f"closure scanner projection differs: {key}")
    methods = re.findall(r"func\s+(testV9_18(?:G01|A01|H01|I01|R01)[A-Za-z0-9_]*)\s*\(",
                         (root / contracts.TEST_PATH).read_text(encoding="utf-8"))
    require(len(methods) == 5 and len(set(methods)) == 5, f"exact five named test methods differ: {methods}")

    tooling = load(root / contracts.MANIFEST)
    unsigned = dict(tooling); seal = unsigned.pop("artifactDigest")
    require(seal == digest(contracts.pretty(unsigned)), "tooling manifest seal differs")
    require(tooling["pathFence"] == contracts.PATH_FENCE and tooling["pathFenceCount"] == 30, "manifest fence differs")
    require(tooling["sourcePathCount"] == 23 and tooling["toolPathCount"] == 7 and
            tooling["generatedArtifactCount"] == 4 and tooling["manifestInputCount"] == 29, "manifest counts differ")
    expected_artifacts = []
    for relative in contracts.MANIFEST_INPUT_PATHS:
        expected_artifacts.append({"path": relative, "sha256": digest((root / relative).read_bytes())})
    require(tooling["artifacts"] == expected_artifacts, "manifest artifact/digest closure differs")
    require(tooling["s10FenceOverlapPaths"] == [] and tooling["activeS10ReservationPathCount"] == 86,
            "manifest S10 disjointness differs")

    fenced_text = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.PATH_FENCE)
    forbidden = [
        "URL" + "Session", "Cloud" + "Kit", "Fire" + "base", "signed" + "URL", "service" + "Credential",
        "Test" + "Flight", "App" + "Store", r"nativeCompileRan\s*[:=]\s*true",
        r"hostedDispatchRan\s*[:=]\s*true", r"phase10PollingRan\s*[:=]\s*true",
        r"adoptionEnabled\s*[:=]\s*true", r"acceptanceCredit\s*[:=]\s*true",
        r"releaseCredit\s*[:=]\s*true", r"provisionalZeroViolationClosureClaimed\s*[:=]\s*true",
    ]
    for pattern in forbidden:
        require(re.search(pattern, fenced_text, re.I) is None, f"forbidden full-fence claim/token: {pattern}")
    return {
        "cardID": contracts.CARD, "result": "PASS", "verificationMode": "STATIC_ONLY",
        "pathFenceCount": 30, "sourcePathCount": 23, "toolPathCount": 7,
        "generatedArtifactCount": 4, "schemaReferenceCount": reference_count,
        "schemaSampleCount": sample_count, "packageCount": 2, "routeCount": 26,
        "workspaceCount": 2, "reservedOwnerDebtCount": 10, "reservedRawWriteDebtCount": 2,
        "evidenceIDCount": 5, "provisionalZeroViolationClosureClaimed": False,
        "nativeCompileRan": False, "hostedDispatchRan": False, "phase10PollingRan": False,
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseReady": False, "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C08 static verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
