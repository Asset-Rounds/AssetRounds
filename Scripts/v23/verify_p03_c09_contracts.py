#!/usr/bin/env python3
"""Fail-closed static verifier for provisional V23-P03-C09 tooling."""
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

sys.dont_write_bytecode = True
import p03_c09_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout.strip()


def load(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), f"BOM forbidden: {path}")
    duplicates: list[str] = []
    def pairs(rows: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in rows:
            if key in result:
                duplicates.append(key)
            result[key] = value
        return result
    value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    require(isinstance(value, dict) and not duplicates, f"invalid/duplicate JSON: {path}")
    return value


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def changed_paths(root: Path) -> set[str]:
    text = subprocess.run(["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
                          check=True, capture_output=True, text=True, encoding="utf-8").stdout
    paths: set[str] = set()
    for row in text.splitlines():
        if len(row) < 4:
            continue
        value = row[3:].replace("\\", "/")
        paths.update(part.strip() for part in value.split(" -> "))
    return paths


def sealed_change_paths(root: Path) -> set[str]:
    """Accept the hydrated base worktree or its one exact sealed candidate.

    Before commit, the implementation is represented by the base HEAD plus
    fenced working-tree changes. After commit, the worktree must be clean and
    HEAD must be the single-parent direct child of that same immutable base;
    the candidate's committed delta then becomes the evidence set.
    """
    head = git(root, "rev-parse", "HEAD")
    status_changes = changed_paths(root)
    if head == contracts.APP_BASE_HEAD:
        require(git(root, "show", "-s", "--format=%T", "HEAD") == contracts.APP_BASE_TREE,
                "application base tree differs")
        return status_changes

    parents = git(root, "show", "-s", "--format=%P", "HEAD").split()
    require(parents == [contracts.APP_BASE_HEAD],
            "application candidate is not the direct single-parent child of the fenced base")
    require(not status_changes, "application candidate worktree is not clean")
    output = git(root, "diff", "--name-only", "--no-renames",
                 f"{contracts.APP_BASE_HEAD}..{head}")
    return {line.replace("\\", "/") for line in output.splitlines() if line}


def independent_generation(root: Path) -> dict[str, bytes]:
    command = [sys.executable, "-B", str(root / contracts.SCRIPT_PATHS[1]), "--dump-json"]
    environment = dict(os.environ); environment["PYTHONDONTWRITEBYTECODE"] = "1"
    first = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True,
                           text=True, encoding="utf-8").stdout
    second = subprocess.run(command, cwd=root, env=environment, check=True, capture_output=True,
                            text=True, encoding="utf-8").stdout
    require(first == second, "independent subprocess generation differs")
    value = json.loads(first)
    return {path: base64.b64decode(raw, validate=True) for path, raw in value.items()}


def fixture_invariants(root: Path, value: dict[str, Any]) -> None:
    raw = (root / contracts.FIXTURE).read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf") and raw.endswith(b"\n"),
            "fixture must be BOM-free UTF-8 with a terminal LF")
    require(set(value) == {"schema", "schemaVersion", "fixedSeed", "workspaceID", "sourceRevision",
                           "bounds", "sourceKindMappings", "records", "queries", "hostileCases",
                           "smartViews", "crashMatrix", "recovery", "productionClosure", "privacy"},
            "fixture top-level closure differs")
    require(value["schema"] == "V21P03C09LocalSearchCorpusV1" and value["schemaVersion"] == 1 and
            value["fixedSeed"] == 230309 and value["sourceRevision"] == 42, "fixture identity differs")
    require(value["bounds"] == {"maximumResults": 100, "maximumSuggestions": 5,
            "scaleRecordCount": 10000, "maximumRebuildMilliseconds": 5000,
            "maximumQueryMilliseconds": 250, "maximumIndexBytes": 16777216,
            "maximumProjectionRows": 100000, "maximumProjectionRowsPerPage": 2500},
            "budget envelope differs")
    require(value["sourceKindMappings"] == contracts.SOURCE_KIND_MAPPINGS,
            "source-kind registration closure differs")
    require(len(value["records"]) == 6 and len({row["stableID"] for row in value["records"]}) == 6,
            "record identity closure differs")
    require({row["kind"] for row in value["records"]} == {"ASSET", "LOCATION", "WORK", "REPORT"},
            "source-kind coverage differs")
    require([row["id"] for row in value["queries"]] == ["exact-identity", "case-diacritic-nfd",
            "prefix-stable-tie", "recheck-filter", "report-failed", "rtl-bidi-controls-removed"],
            "query matrix differs")
    require([row["id"] for row in value["hostileCases"]] == ["index-stale", "index-ahead",
            "duplicate-result", "deleted-result", "short-typo", "bounded-typo", "privacy-canary",
            "ten-k-stall"], "hostile matrix differs")
    require([row["kind"] for row in value["smartViews"]] == contracts.SMART_VIEWS,
            "built-in smart-view order differs")
    require({row["boundary"] for row in value["crashMatrix"]} == {
            "AFTER_CANONICAL_COMMIT_BEFORE_INDEX_UPDATE", "AFTER_REBUILD_TEMP_WRITE_BEFORE_REPLACE",
            "AFTER_REPLACE_BEFORE_WATERMARK_RECEIPT"}, "crash matrix differs")
    require(value["recovery"] == {"dropDerivedIndex": True, "retainCanonicalRecords": True,
            "retainSavedSmartViews": True, "retainTransientQuery": False, "rebuildDeterministic": True},
            "recovery contract differs")
    require(value["productionClosure"] == {
            "sourceKindRegistrationCount": 13, "writerInvalidationSynchronous": True,
            "startupInvalidationSynchronous": True, "assetSiteCrashRetryMarkerOrdered": True,
            "orphanCleanupPurgesDerivedIndex": True,
            "typedCanonicalStableKeys": True,
            "sameSearchKindTypedIdentityCollisionSafe": True,
            "truthfulIncompleteStatusSemantics": True,
            "backupStaleRequiresOperationalProvider": True,
            "rebuildPublicationTokenRequired": True,
            "sameRevisionDeletionRaceCovered": True,
            "swiftDataProjectionSource": "SwiftDataSearchCanonicalProjectionSourceV1",
            "serviceSeam": "ProductionSearchServicesV1"}, "production closure differs")
    require(value["privacy"]["indexedFieldIDs"] == contracts.INDEXED_FIELDS and
            value["privacy"]["excludedFieldIDs"] == contracts.EXCLUDED_FIELDS and
            value["privacy"]["diagnosticsContainCustomerContent"] is False, "privacy registry differs")
    fenced = contracts.canonical(value)
    for token in (b"SECRET-SUPPORT-DRAFT-RAW-OCR",):
        require(token in fenced, "privacy canary missing")


def validate_schema(root: Path, schema: dict[str, Any], fixture: dict[str, Any]) -> int:
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema" and
            schema.get("$id") == "https://assetrounds.invalid/schemas/v23/local-search-smart-view.schema.json" and
            schema.get("$ref") == "#/$defs/corpus", "schema identity/dialect differs")
    refs = 0
    for node in walk(schema):
        if isinstance(node, dict):
            if "$ref" in node:
                refs += 1
                require(isinstance(node["$ref"], str) and node["$ref"].startswith("#/$defs/"),
                        "schema has non-local ref")
                require(node["$ref"].split("/")[-1] in schema["$defs"], "schema has unresolved ref")
            if node.get("type") == "object" and "properties" in node:
                require(node.get("additionalProperties") is False or node is schema["$defs"]["fields"],
                        "open object shape in strict schema")
    require(schema["$defs"]["fields"]["additionalProperties"]["type"] == ["string", "null"],
            "bounded map value schema differs")
    positives = [fixture]
    negatives: list[tuple[str, dict[str, Any]]] = []
    for label, mutate in (
        ("UNKNOWN_TOP_LEVEL", lambda x: x.update({"unknown": True})),
        ("FUTURE_VERSION", lambda x: x.update({"schemaVersion": 2})),
        ("OVER_SCALE", lambda x: x["bounds"].update({"scaleRecordCount": 10001})),
        ("OPEN_RECORD", lambda x: x["records"][0].update({"hidden": "secret"})),
        ("MISSING_PRIVACY", lambda x: x.pop("privacy")),
        ("UNKNOWN_KIND", lambda x: x["records"][0].update({"kind": "MEDIA"})),
    ):
        candidate = copy.deepcopy(fixture); mutate(candidate); negatives.append((label, candidate))
    assembly = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/JsonSchema.Net.dll"
    require(assembly.is_file() and sha256(assembly.read_bytes()) ==
            "1243dc7749d37818beadf8967c3963082ba00efe05877e3f180346e9f56007a0",
            "pinned offline JsonSchema.Net unavailable or differs")
    with tempfile.TemporaryDirectory(prefix="v23-p03-c09-schema-") as temporary:
        folder = Path(temporary); rows = []
        for index, (label, instance, expected) in enumerate(
                [("POSITIVE", positives[0], True)] + [(label, value, False) for label, value in negatives]):
            path = folder / f"instance-{index}.json"; path.write_bytes(contracts.pretty(instance))
            rows.append({"label": label, "instance": str(path), "expected": expected})
        index_path = folder / "index.json"; index_path.write_bytes(contracts.pretty({
            "schema": str((root / contracts.SCHEMA_PATH).resolve()), "rows": rows}))
        quote = lambda value: "'" + str(value).replace("'", "''") + "'"
        script = (f"Add-Type -Path {quote(assembly)};$o=[Json.Schema.EvaluationOptions]::new();"
                  f"$i=Get-Content -LiteralPath {quote(index_path)} -Raw|ConvertFrom-Json;"
                  "$sn=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $i.schema -Raw));"
                  "$mr=[Json.Schema.MetaSchemas]::Draft202012.Evaluate($sn,$o);if(-not $mr.IsValid){throw 'meta'};"
                  "$s=[Json.Schema.JsonSchema]::FromFile($i.schema);foreach($x in $i.rows){"
                  "$n=[System.Text.Json.Nodes.JsonNode]::Parse((Get-Content -LiteralPath $x.instance -Raw));"
                  "$r=$s.Evaluate($n,$o);if($r.IsValid -ne [bool]$x.expected){throw $x.label}};'PASS'")
        result = subprocess.run(["pwsh", "-NoProfile", "-Command", script], capture_output=True,
                                text=True, encoding="utf-8")
        require(result.returncode == 0 and result.stdout.strip().endswith("PASS"),
                f"schema meta/instance validation failed: {result.stderr.strip()}")
    return refs + len(positives) + len(negatives)


def swift_checks(root: Path) -> None:
    source = (root / contracts.TEST_PATH).read_text(encoding="utf-8")
    methods = re.findall(r"\bfunc\s+(testV9_19(?:G01|A01|H01|I01|R01)[A-Za-z0-9_]*)\s*\(", source)
    require(methods == contracts.TEST_METHODS, f"exact five Swift tests differ: {methods}")
    require(".Type = SwiftDataSearchCanonicalProjectionSourceV1.self" not in source and
            ".Type = ProductionSearchServicesV1.self" not in source,
            "type-reference-only production evidence is forbidden")
    behavioral_patterns = (
        r"let productionSource = try SwiftDataSearchCanonicalProjectionSourceV1\(",
        r"let productionContainer = try makeProductionSearchContainer\(\"ten-thousand\"\)",
        r"for index in 0\.\.<10_000 \{\s*productionContext\.insert\(Asset\(",
        r"while canonicalOffset < 10_000 \{.*productionSource\.searchProjectionPage\(",
        r"XCTAssertEqual\(canonicalOffset, 10_000\)",
        r"XCTAssertEqual\(projectedRows, 30_000\)",
        r"XCTAssertLessThanOrEqual\(page\.records\.count, 2_500\)",
        r"productionRevisionBox\.value = try source\(revision: 8\).*"
        r"XCTAssertEqual\(error, \.sourceChangedDuringRebuild\)",
        r"collisionContext\.insert\(workflowRecord\(id: collisionID\)\).*"
        r"collisionContext\.insert\(Issue\(.*WorkspaceEntityIdentityV1\(kind: \.workflowRecord.*"
        r"WorkspaceEntityIdentityV1\(kind: \.issue",
        r"sourceStableID,\s*try WorkspaceEntityIdentityV1\(kind: \.asset, id: scaleUUID\(0\)\)\.stableKey",
        r"FixedOperationalStatusProvider\(identities:.*operationalStatusProvider: staleProvider",
        r"unknownProvider.*XCTAssertEqual\(error, \.invalidContext\)",
        r"let stalePublicationToken = await reloaded\.publicationToken\(\).*"
        r"publicationToken: stalePublicationToken.*XCTAssertEqual\(error, \.staleMutation\)",
        r"let raceSource = SameRevisionDeletionRaceSource\(.*"
        r"let racedRebuilder = try SearchIndexRebuildCoordinatorV1\(.*"
        r"XCTAssertEqual\(raceDiscardCount, 1\)",
        r"postDeleteProjection\.records\.map\(\\\.sourceStableID\), \[\"post-delete-survivor\"\]",
        r"rebuildStaging\(publicationToken: guardedToken\).*"
        r"saveRebuildStaging\(.*publicationToken: guardedToken.*"
        r"clearRebuildStaging\(publicationToken: guardedToken\)",
        r"state-draft.*state-open.*state-pending.*state-incomplete.*state-recheck.*state-progress",
    )
    for pattern in behavioral_patterns:
        require(re.search(pattern, source, re.S) is not None,
                f"behavioral SwiftData XCTest evidence missing: {pattern}")
    for token in ("V21P03C09LocalSearchCorpusV1", "SearchIndexReconciliationV1", "SavedSmartViewDescriptorV1",
                  "SearchIndexRebuildCoordinatorV1", "LocalSearchIndexStoreV1", "10_000", "100_000",
                  "incompatibleFormatDropAndRebuild", "deletingStableIDs", "SearchSessionStateV1",
                  "SwiftDataSearchCanonicalProjectionSourceV1", "ProductionSearchServicesV1", "privacy"):
        require(token.lower() in source.lower(), f"Swift evidence seam missing: {token}")
    search_source = "\n".join((root / path).read_text(encoding="utf-8") for path in contracts.NEW_PRODUCT_PATHS)
    for token in ("SearchableFieldRegistryV1", "SearchQueryPlanV1", "SearchSuggestionV1",
                  "SearchResultContextV1", "SearchSessionStateV1", "SavedSmartViewDescriptorV1",
                  "SearchIndexProjectionV1", "SearchIndexRebuildCoordinatorV1"):
        require(token in search_source, f"required search contract/owner missing: {token}")
    for forbidden in ("URL" + "Session", "Cloud" + "Kit", "Fire" + "base", "signed" + "URL",
                      "service" + "Credential", "raw" + "OCR"):
        require(forbidden not in search_source, f"forbidden remote/privacy scope symbol: {forbidden}")

    rebuild = (root / "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift").read_text(
        encoding="utf-8")
    for token in ("exactSearchableFieldCount", "maximumCanonicalRecords", "maximumProjectionRowsPerPage",
                  "SwiftDataSearchCanonicalProjectionSourceV1", "ProductionSearchServicesV1",
                  "SearchOperationalStatusProvidingV1", "backupStaleCanonicalIdentities",
                  "WorkspaceEntityIdentityV1", "kind: .workflowRecord", "kind: .issue",
                  "FetchDescriptor<Asset>()", "FetchDescriptor<Site>()", "FetchDescriptor<WorkflowRecord>()",
                  "FetchDescriptor<Issue>()", "FetchDescriptor<Report>()"):
        require(token in rebuild, f"production projection closure missing: {token}")
    require("static let maximumProjectionRowsPerPage = pageSize" in rebuild and
            "let projectionRowCapacity = Self.maximumCanonicalRecords" in rebuild and
            "* SearchContractLimitsV1.exactSearchableFieldCount" in rebuild,
            "canonical/projection scale separation differs")
    require("let publicationToken = await store.publicationToken()" in rebuild and
            "publicationToken: publicationToken" in rebuild and
            "discardCachedSearchProjectionSnapshot()" in rebuild and
            "catch {\n            await source.discardCachedSearchProjectionSnapshot()" in rebuild and
            "staleIdentities.isSubset(of: knownIdentities)" in rebuild,
            "publication/operational-status fail-closed closure differs")
    coordinator = (root / "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift").read_text(
        encoding="utf-8")
    for token in ('["draft", "open", "pending", "incomplete"]',
                  '["completed", "resolved", "ready", "failed"]',
                  'statusTerms.contains("recheck")', 'statusTerms.contains("progress")'):
        require(token in coordinator, f"truthful incomplete semantics missing: {token}")
    local_store = (root / "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift").read_text(
        encoding="utf-8")
    require("func publicationToken() -> SearchIndexPublicationTokenV1" in local_store and
            "withGuardedPublication" in local_store and "withInvalidation" in local_store and
            "func rebuildStaging(\n        publicationToken:" in local_store and
            "func saveRebuildStaging(\n        checkpoint:" in local_store and
            "func clearRebuildStaging(\n        operationID:" in local_store,
            "derived-index publication fence differs")

    session = (root / "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift").read_text(
        encoding="utf-8")
    require("synchronouslyInvalidateAfterCanonicalCommit" in session and
            re.search(r"synchronouslyDropProjection\(.*?let binding = try Self\.makeWriter", session, re.S),
            "startup/writer synchronous invalidation closure differs")
    orphan = (root / "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift").read_text(
        encoding="utf-8")
    require(orphan.count("try purgeDerivedSearchProjection()") == 2 and
            orphan.count("func purgeDerivedSearchProjection() throws") == 1,
            "orphan purge call-site closure differs")
    generation = (root / "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift").read_text(
        encoding="utf-8")
    marker_order = re.search(
        r"FetchDescriptor<Site>\(\).*FetchDescriptor<Asset>\(\).*requireV7Marker", generation, re.S)
    require(marker_order is not None, "asset/site crash-retry marker ordering differs")


def verify_generated(root: Path) -> None:
    outputs = contracts.all_outputs(root)
    require(outputs == contracts.all_outputs(root) and independent_generation(root) == outputs,
            "generator is not deterministic")
    for relative, expected in outputs.items():
        require((root / relative).read_bytes() == expected, f"stale generated artifact: {relative}")
    contract = load(root / contracts.CONTRACT_PATH); evidence = load(root / contracts.EVIDENCE_PATH)
    manifest = load(root / contracts.MANIFEST)
    for relative, value in ((contracts.CONTRACT_PATH, contract), (contracts.EVIDENCE_PATH, evidence),
                            (contracts.MANIFEST, manifest)):
        unsigned = dict(value); seal = unsigned.pop("artifactDigest")
        require(seal == sha256(contracts.pretty(unsigned)), f"artifact seal differs: {relative}")
        require(value["authority"] == contracts.authority(), f"artifact authority differs: {relative}")
        for flag in ("nativeCompileRan", "hostedDispatchEnabled", "phase10PollingDuringParallelExecution",
                     "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit"):
            require(value[flag] is False, f"forbidden evidence claim {flag}: {relative}")
    require(contract["pathFence"] == contracts.PATH_FENCE and contract["testMethods"] == contracts.TEST_METHODS and
            contract["evidenceIDs"] == contracts.EVIDENCE_IDS, "contract fence/test projection differs")
    require([{"fieldID": row["fieldID"], "sourceKind": row["sourceKind"]}
             for row in contract["searchableFieldRegistry"]] == contracts.SOURCE_KIND_MAPPINGS and
            contract["budgets"]["maximumProjectionRows"] == 100000 and
            contract["budgets"]["maximumProjectionRowsPerPage"] == 2500 and
            contract["productionClosure"]["sourceKindRegistrationCount"] == 13,
            "contract source-kind/scale/production closure differs")
    changed_existing = contracts.changed_existing_paths(root)
    require(evidence["checks"] == contracts.CHECKS and evidence["s10FenceOverlapPaths"] == [] and
            evidence["changedExistingAuthorityPaths"] == changed_existing and
            evidence["unchangedAuthorityPathCount"] == 46 - len(changed_existing) and
            evidence["pathFenceCount"] == 60, "evidence closure differs")
    require(manifest["pathFence"] == contracts.PATH_FENCE and manifest["existingPaths"] == contracts.EXISTING_PATHS and
            manifest["newPaths"] == contracts.NEW_PATHS and manifest["pathFenceCount"] == 60 and
            manifest["existingPathCount"] == 46 and manifest["newPathCount"] == 14 and
            manifest["changedExistingAuthorityPaths"] == changed_existing and
            manifest["unchangedAuthorityPathCount"] == 46 - len(changed_existing) and
            manifest["sourcePathCount"] == 53 and manifest["toolPathCount"] == 7 and
            manifest["manifestInputCount"] == 59 and manifest["s10FenceOverlapPaths"] == [],
            "manifest inventory differs")
    require([row["path"] for row in manifest["artifacts"]] == contracts.MANIFEST_INPUT_PATHS and
            manifest["artifactSetDigest"] == sha256(contracts.canonical(manifest["artifacts"])),
            "manifest artifact ordering/set seal differs")
    for row in manifest["artifacts"]:
        raw = outputs.get(row["path"], (root / row["path"]).read_bytes())
        require(row == contracts.artifact(row["path"], raw), f"manifest digest differs: {row['path']}")


def verify(root: Path) -> dict[str, Any]:
    require(len(contracts.PATH_FENCE) == len(set(contracts.PATH_FENCE)) == 60 and
            len(contracts.EXISTING_PATHS) == 46 and len(contracts.NEW_PATHS) == 14 and
            len(contracts.SOURCE_PATHS) == 53 and len(contracts.TOOL_PATHS) == 7,
            "corrected path fence counts differ")
    require(contracts.PATH_FENCE == contracts.SOURCE_PATHS + contracts.TOOL_PATHS and
            set(contracts.EXISTING_PATHS).isdisjoint(contracts.NEW_PATHS) and
            set(contracts.EXISTING_PATHS) | set(contracts.NEW_PATHS) == set(contracts.PATH_FENCE),
            "path fence partition differs")
    actual_changes = sealed_change_paths(root)
    require(actual_changes and actual_changes.issubset(set(contracts.PATH_FENCE)),
            f"changed paths escape corrected 60-path fence: {sorted(actual_changes - set(contracts.PATH_FENCE))}")
    require(set(contracts.NEW_PATHS).issubset(actual_changes), "new-path artifact closure is incomplete")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")
        existed = subprocess.run(["git", "-C", str(root), "cat-file", "-e",
                                  f"{contracts.APP_BASE_HEAD}:{relative}"], capture_output=True).returncode == 0
        require(existed == (relative in contracts.EXISTING_PATHS), f"base existence differs: {relative}")
    require(len(contracts.ACTIVE_S10_RESERVED_PATHS) == len(set(contracts.ACTIVE_S10_RESERVED_PATHS)) == 86 and
            not (set(contracts.PATH_FENCE) & set(contracts.ACTIVE_S10_RESERVED_PATHS)),
            "active S10 reservation overlap/inventory differs")
    require(not [path for path in root.rglob("*") if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")],
            "Python cache leaked")
    fixture = load(root / contracts.FIXTURE); fixture_invariants(root, fixture)
    sample_count = validate_schema(root, load(root / contracts.SCHEMA_PATH), fixture)
    swift_checks(root); verify_generated(root)
    return {"result": "PASS", "cardID": contracts.CARD, "verificationMode": "STATIC_ONLY",
            "pathFenceCount": 60, "existingPathCount": 46, "newPathCount": 14,
            "schemaValidationCount": sample_count, "evidenceIDCount": 5,
            "nativeCompileRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False,
            "acceptanceCredit": False, "releaseCredit": False,
            "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True}


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C09 static verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
