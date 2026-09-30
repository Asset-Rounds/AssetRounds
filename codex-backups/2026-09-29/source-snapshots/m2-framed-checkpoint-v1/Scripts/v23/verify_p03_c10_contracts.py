#!/usr/bin/env python3
"""Fail-closed static verifier for provisional V23-P03-C10."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
import p03_c10_contracts as contracts


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), f"JSON root must be object: {path}")
    return value


def git_changes(root: Path) -> set[str]:
    rows = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True, encoding="utf-8",
    ).stdout.splitlines()
    return {row[3:].replace("\\", "/") for row in rows if len(row) >= 4}


def strict_schema(schema: dict[str, Any], expected_id: str) -> None:
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
            "schema dialect differs")
    require(schema.get("$id") == expected_id, "schema identity differs")
    for node in walk(schema):
        if isinstance(node, dict) and node.get("type") == "object" and "properties" in node:
            require(node.get("additionalProperties") is False, "open object shape in strict schema")


def walk(value: Any):
    yield value
    if isinstance(value, dict):
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def strip_swift_comments(source: str) -> str:
    """Remove Swift comments while preserving strings, newlines, and token positions."""
    result = list(source)
    index = 0
    block_depth = 0
    in_string = False
    escaped = False
    while index < len(source):
        if block_depth:
            if source.startswith("/*", index):
                result[index:index + 2] = "  "
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                result[index:index + 2] = "  "
                block_depth -= 1
                index += 2
            else:
                if source[index] not in "\r\n":
                    result[index] = " "
                index += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif source[index] == "\\":
                escaped = True
            elif source[index] == '"':
                in_string = False
            index += 1
            continue
        if source[index] == '"':
            in_string = True
            index += 1
        elif source.startswith("//", index):
            end = source.find("\n", index)
            if end < 0:
                end = len(source)
            for offset in range(index, end):
                result[offset] = " "
            index = end
        elif source.startswith("/*", index):
            result[index:index + 2] = "  "
            block_depth = 1
            index += 2
        else:
            index += 1
    require(block_depth == 0 and not in_string, "unterminated Swift comment or string")
    return "".join(result)


def reject_unreachable_swift(block: str, label: str) -> None:
    patterns = (
        r"\bif\s+(?:false|!\s*true|0\s*==\s*1|1\s*==\s*0)\s*\{",
        r"\bwhile\s+(?:false|!\s*true)\s*\{",
        r"\bguard\s+(?:false|!\s*true)\b",
        r"(?m)^\s*#if\s+(?:false|0)\b",
        r"\bXCTAssertTrue\s*\(\s*true\s*\)",
        r"\bXCTAssertFalse\s*\(\s*false\s*\)",
        r"\bXCTAssertEqual\s*\(\s*(true|false)\s*,\s*\1\s*\)",
    )
    require(not any(re.search(pattern, block) for pattern in patterns),
            f"explicit unreachable/self-certifying Swift branch: {label}")


def swift_function_blocks(source: str, name: str) -> list[str]:
    """Return top-level type-member function blocks without pretending to compile Swift."""
    members = list(re.finditer(
        r"(?m)^    (?:(?:private|fileprivate|internal|public|static|class|final|nonisolated)\s+)*"
        r"func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
        source,
    ))
    blocks = []
    for index, member in enumerate(members):
        if member.group(1) != name:
            continue
        end = members[index + 1].start() if index + 1 < len(members) else len(source)
        blocks.append(source[member.start():end])
    return blocks


def require_swift_function(
    source: str, name: str, fragments: tuple[str, ...], label: str,
) -> str:
    blocks = swift_function_blocks(source, name)
    require(bool(blocks), f"missing Swift function: {name}")
    matching = [block for block in blocks if all(fragment in block for fragment in fragments)]
    require(bool(matching), f"{label} function wiring differs: {name}")
    reject_unreachable_swift(matching[0], label)
    return matching[0]


def swift_string_inventory(source: str, declaration: str, terminator: str = "\n    ]") -> set[str]:
    start = source.find(declaration)
    require(start >= 0, f"missing Swift declaration: {declaration}")
    end = source.find(terminator, start)
    require(end >= 0, f"unterminated Swift declaration: {declaration}")
    return set(re.findall(r'"([A-Z][A-Z0-9_]+)"', source[start:end]))


def fixture_checks(root: Path) -> None:
    values = [load(root / path) for path in contracts.FIXTURE_PATHS]
    checklist, measurement, graph, corpus = values
    serialized = [contracts.canonical(value) for value in values]
    require(len(set(serialized)) == 4, "fixture artifacts are not structurally distinct")
    require(checklist != measurement,
            "the two lifecycle fixture packages are not structurally distinct")
    combined = b"\n".join(serialized).upper()
    for token in contracts.LIFECYCLE + contracts.FAULTS:
        require(token.encode() in combined, f"fixture closure missing: {token}")
    require(checklist.get("shapeID") == "CHECKLIST_BRANCHING_EVIDENCE_FIRST" and
            measurement.get("shapeID") == "MEASUREMENT_REPEAT_LOOP_RECHECK",
            "exact structurally distinct fixture shapes differ")
    expected_pairs = list(zip(contracts.TEST_METHODS, contracts.EVIDENCE_IDS))
    graph_nodes = graph.get("nodes", [])
    graph_node_ids = {row["id"] for row in graph_nodes}
    require(len(graph_nodes) == len(graph_node_ids), "scenario graph node identities repeat")
    graph_bindings = {row["selector"]: row for row in graph.get("selectorBindings", [])}
    g01_binding = graph_bindings.get(contracts.TEST_METHODS[0])
    require(g01_binding is not None, "scenario graph lacks G01 lifecycle binding")
    observed_boundary_sets = []
    for shape, manifest in (("CHECKLIST", checklist), ("MEASUREMENT_REPEAT", measurement)):
        faults = manifest["faultInjections"]
        boundaries = [row["boundary"] for row in faults]
        observed_boundary_sets.append(set(boundaries))
        require(len(boundaries) == len(set(boundaries)) == 53,
                "fixture production fault boundary identities are not exact/unique")
        require(set(row["faultClass"] for row in faults) == set(contracts.FAULTS),
                "fixture exact fault-class inventory differs")
        for required_class in contracts.REQUIRED_FAULT_CLASSES:
            rows = [row for row in faults if row["faultClass"] == required_class]
            require(rows and all(row["selectors"] and row["evidenceIDs"] for row in rows),
                    f"required fault class lacks selector/evidence coverage: {required_class}")
        require([row["action"] for row in manifest["lifecycleTransitions"]] ==
                contracts.LIFECYCLE_TRACES[shape], f"fixture chronological lifecycle trace differs: {shape}")
        require(sorted(len(row["replicas"]) for row in manifest["replicaSchedules"]) == [2, 3] and
                all(row["replayCount"] == 2 for row in manifest["replicaSchedules"]),
                "two/three-replica replay-twice closure differs")
        release = manifest["releaseAbsence"]
        require(release["testOnly"] is True and release["shippingAdoptionEnabled"] is False and
                release["nativeCompileRan"] is False and release["hostedDispatchRan"] is False and
                release["acceptanceCredit"] is False and release["releaseCredit"] is False and
                release["requiresAcceptedS10_6Reconciliation"] is True,
                "fixture Release-absence/provisional flags differ")
        bindings = [(row["selector"], row["evidenceID"]) for row in manifest["evidenceBindings"]]
        require(bindings == expected_pairs and len(bindings) == len(set(bindings)) == 5,
                "fixture selector/evidence pairs differ or repeat")
        full_lifecycle_rows = [row for row in manifest["evidenceBindings"]
                               if "FULL_LIFECYCLE" in row["covers"]]
        require(len(full_lifecycle_rows) == 1 and
                full_lifecycle_rows[0]["selector"] == contracts.TEST_METHODS[0] and
                full_lifecycle_rows[0]["evidenceID"] == contracts.EVIDENCE_IDS[0],
                "fixture full-lifecycle evidence must bind exactly G01")
        prefix = "c-" if shape == "CHECKLIST" else "m-"
        lifecycle_node_ids = set()
        for transition in manifest["lifecycleTransitions"]:
            matches = [node for node in graph_nodes
                       if node["id"].startswith(prefix)
                       and node["phase"] == transition["action"]
                       and node["adapter"] == transition["adapter"]
                       and node["persistentConsumers"] == transition["persistentConsumers"]
                       and node["brandState"] == transition["brandState"]]
            require(bool(matches),
                    f"manifest transition lacks exact scenario-graph node: {shape}/{transition['action']}")
            lifecycle_node_ids.update(node["id"] for node in matches)
        require(lifecycle_node_ids.issubset(set(g01_binding["nodeIDs"])),
                f"G01 graph binding omits exact lifecycle nodes: {shape}")
    expected_boundaries = set(contracts.PRODUCTION_FAULT_BOUNDARIES)
    require(len(expected_boundaries) == 53 and observed_boundary_sets == [expected_boundaries, expected_boundaries],
            "manifest boundary sets differ from exact productionFaultIdentities keys")
    require(graph.get("schema") == "V21P03C10KernelConformanceScenarioGraphV1" and
            len(graph.get("selectorBindings", [])) == 5 and
            all(row.get("changedUI") is False for row in graph.get("brandStates", [])),
            "scenario selector/evidence/brand closure differs")
    graph_pairs = [(row["selector"], row["evidenceID"]) for row in graph["selectorBindings"]]
    require(graph_pairs == expected_pairs and len(graph_pairs) == len(set(graph_pairs)) == 5,
            "graph selector/evidence pairs differ or repeat")
    covered_nodes = set().union(*(set(row["nodeIDs"]) for row in graph["selectorBindings"]))
    covered_boundaries = set().union(*(set(row["boundaries"]) for row in graph["selectorBindings"]))
    node_ids = graph_node_ids
    edge_boundaries = {row["boundary"] for row in graph["edges"] if row["boundary"] != "NONE"}
    require(covered_nodes == node_ids, "not every graph node has selector/evidence coverage")
    require(covered_boundaries == edge_boundaries,
            "not every concrete graph edge boundary has selector/evidence coverage")
    require(edge_boundaries == expected_boundaries,
            "scenario graph does not carry every exact production boundary")
    covered_consumers = set().union(*(set(row["persistentConsumers"]) for row in graph["nodes"]
                                      if row["id"] in covered_nodes))
    covered_brands = {row["brandState"] for row in graph["nodes"] if row["id"] in covered_nodes}
    require(covered_consumers == {row["id"] for row in graph["persistentConsumers"]},
            "not every persistent consumer has selector/evidence coverage")
    require(covered_brands == {row["id"] for row in graph["brandStates"]},
            "not every brand state has selector/evidence coverage")
    case_ids = {row["id"] for row in corpus.get("cases", [])}
    require({"positive-check-v1", "positive-measurement-v1", "unknown-schema-version",
             "unknown-top-level-field", "unknown-closed-enum"}.issubset(case_ids) and
            all(row.get("goldenUTF8Hex") for row in corpus["cases"]),
            "portable golden/version/field/enum corpus closure differs")


def portable_validation_checks(root: Path) -> None:
    portable_root = root / "Scripts/v21-contracts"
    sys.path.insert(0, str(portable_root))
    try:
        import portable_contract_validator_v1 as portable
        lock = portable.load_lock(root)
        registry = portable.load_registry(root, lock)
        fixture_schema = load(root / contracts.FIXTURE_SCHEMA_PATH)
        contract_schema = load(root / contracts.CONTRACT_SCHEMA_PATH)
        for relative, schema in ((contracts.FIXTURE_SCHEMA_PATH, fixture_schema),
                                 (contracts.CONTRACT_SCHEMA_PATH, contract_schema)):
            result = portable.validate_schema_against_official_meta(
                schema, registry, (root / relative).resolve().as_uri())
            require(result["valid"], f"official Draft 2020-12 meta-validation failed: {relative}")
        for relative in contracts.FIXTURE_PATHS:
            result = portable.validate_instance(
                load(root / relative), fixture_schema, registry,
                (root / contracts.FIXTURE_SCHEMA_PATH).resolve().as_uri())
            require(result["valid"], f"fixture schema validation failed: {relative}: {result['errors'][:1]}")
        portable_envelope = {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://assetrounds.invalid/schemas/v23/kernel-portable-envelope-v1.json",
            **fixture_schema["$defs"]["portableEnvelope"],
        }
        meta = portable.validate_schema_against_official_meta(
            portable_envelope, registry, portable_envelope["$id"])
        require(meta["valid"], "portable envelope schema is not Draft 2020-12 meta-valid")
        corpus = load(root / contracts.FIXTURE_PATHS[3])
        for row in corpus["cases"]:
            instance = json.loads(row["input"])
            first = portable.validate_instance(instance, portable_envelope, registry, portable_envelope["$id"])
            second = portable.validate_instance(instance, portable_envelope, registry, portable_envelope["$id"])
            require(portable.canonical_json(first) == portable.canonical_json(second),
                    f"C10 portable result is not deterministic: {row['id']}")
            expected_valid = row["expectedClass"] == "ACCEPTED"
            require(first["valid"] is expected_valid,
                    f"C10 portable classification differs: {row['id']}")
            if expected_valid:
                require(row["instancePath"] == row["schemaPath"] == "" and not first["errors"],
                        f"accepted C10 portable path contract differs: {row['id']}")
            else:
                require(first["errors"], f"rejected C10 portable case lacks stable error: {row['id']}")
                error = first["errors"][0]
                require(error["instancePath"] == row["instancePath"] and
                        error["schemaPath"] == row["schemaPath"],
                        f"C10 portable stable instance/schema path differs: {row['id']}: {error}")
        cross_kind_hostile = [
            {"schema": "KernelPortableEnvelopeV1", "schemaVersion": 1, "kind": "CHECK",
             "payload": {"id": "check-001", "status": "OPEN", "value": "1.0", "unit": "mm"}},
            {"schema": "KernelPortableEnvelopeV1", "schemaVersion": 1, "kind": "MEASUREMENT",
             "payload": {"id": "measurement-001", "status": "COMPLETE", "value": "1.0", "unit": "mm", "label": "x"}},
            {"schema": "KernelPortableEnvelopeV1", "schemaVersion": 1, "kind": "MEASUREMENT",
             "payload": {"id": "measurement-001", "status": "COMPLETE"}},
        ]
        for index, instance in enumerate(cross_kind_hostile):
            result = portable.validate_instance(instance, portable_envelope, registry, portable_envelope["$id"])
            require(result["valid"] is False and result["errors"],
                    f"portable kind-closed payload hostile case accepted: {index}")
        generated_contract = load(root / contracts.CONTRACT_PATH)
        result = portable.validate_instance(
            generated_contract, contract_schema, registry,
            (root / contracts.CONTRACT_SCHEMA_PATH).resolve().as_uri())
        require(result["valid"], f"generated contract schema validation failed: {result['errors'][:1]}")
    finally:
        sys.path.remove(str(portable_root))

    for relative in ("Scripts/v21-contracts/check-portable-contract-lock.py",
                     "Scripts/v21-contracts/run-portable-contracts.py"):
        result = subprocess.run([sys.executable, "-B", str(root / relative)], cwd=root,
                                capture_output=True, text=True, encoding="utf-8")
        require(result.returncode == 0, f"portable command failed: {relative}: {result.stderr.strip()}")
        payload = json.loads(result.stdout)
        require(payload.get("valid") is True, f"portable command did not report valid: {relative}")
        if relative.endswith("run-portable-contracts.py"):
            require(payload.get("networkFetchCount") == 0 and
                    payload.get("deterministicReplayMatched") is True and
                    payload.get("allExpectationsMatched") is True,
                    "portable C06-derived corpus/meta-schema closure differs")


def swift_checks(root: Path) -> None:
    source = strip_swift_comments(
        (root / contracts.SWIFT_TEST_PATH).read_text(encoding="utf-8")
    )
    harness = strip_swift_comments(
        (root / "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift")
        .read_text(encoding="utf-8")
    )
    methods = re.findall(r"\bfunc\s+(testV9_20(?:G01|A01|H01|I01|R01)[A-Za-z0-9_]*)\s*\(", source)
    require(methods == contracts.TEST_METHODS, f"exact five Swift tests differ: {methods}")

    g01 = require_swift_function(source, contracts.TEST_METHODS[0], (
        "loadManifest(.checklist)", "loadManifest(.measurementRepeat)",
        "PortableContractValidatorAdapterV1(toolLock: lock)",
        "adapter.validate($0)", "portableValidationReceipts", "networkFetchCount",
        "for (shape, manifest) in", "exerciseFullLifecycle(shape: shape)",
        "XCTAssertEqual(trace.executedActions, expectedActions)",
        "XCTAssertTrue(trace.erasedWorkspaceIsEmpty)",
    ), "G01 full lifecycle and portable parity")
    require(g01.count("exerciseFullLifecycle(shape: shape)") == 1,
            "G01 lifecycle driver must execute once per shape loop")

    a01 = require_swift_function(source, contracts.TEST_METHODS[1], (
        "productionFaultIdentities.keys", "XCTAssertEqual(boundaries.count, 53)",
        "exerciseProductionFaultBoundaries(boundaries.sorted())",
        "XCTAssertEqual(receipts.count, 53)", "receipt.visibleFailure",
        "receipt.operationAttempted", "receipt.recoveryOperation",
        "receipt.coldRecoverySucceeded", "receipt.noPartialAuthority",
        "receipt.residualIntentCount", "receipt.orphanPathCount",
    ), "A01 exact production boundary execution")
    for family in ("FINALIZATION_", "WORK_", "REPORT_", "JOURNAL_",
                   "RESTORE_", "DELETE_", "ERASE_", "SEARCH_"):
        require(f'"{family}"' in a01, f"A01 omits production family: {family}")

    h01 = require_swift_function(source, contracts.TEST_METHODS[2], (
        "PortableContractToolLockReaderV1.read", "XCTAssertFalse(lock.networkFetchAllowed)",
        "$0.releaseAbsence.testOnly", "!$0.releaseAbsence.shippingAdoptionEnabled",
        "!$0.releaseAbsence.acceptanceCredit", "!$0.releaseAbsence.releaseCredit",
        "Bundle.main.url(forResource:", "XCTAssertNil", "adapter.validate($0)",
        'exerciseSearchFaultBoundary(boundary)', '"SEARCH_CANCELLATION"', '"SEARCH_STALE"',
        'text.contains("KernelConformance")', 'text.contains("PortableContract")',
        "_isDebugAssertConfiguration()", "Bundle.main.executableURL", "Data(marker.utf8)",
        "requiresAcceptedS10_6Reconciliation",
        '"KernelConformanceProductionHarnessV1"',
        '"BackupRestoreFailureInjection"', '"EraseAllFailureInjection"',
        '"WorkCoordinatorFailureInjection"', '"ReportRenderFailureInjection"',
        '"ReportRecoveryFailureInjection"', '"WholeSignDeletionFailureInjection"',
        '"FinalizationIntentStoreFailureInjection"', '"FinalizationServiceFailureInjection"',
    ), "H01 hostile corpus, cold recovery, and release absence")
    require(h01.count("XCTAssertNil(Bundle.main.url") == 1,
            "H01 fixture bundle-absence loop differs")

    i01 = require_swift_function(source, contracts.TEST_METHODS[3], (
        "binding.boundaries", "durable.sorted()", "firstReceipts", "secondReceipts",
        "XCTAssertEqual(firstReceipts, secondReceipts)", "receipt.visibleFailure",
        "receipt.coldRecoverySucceeded", "receipt.noPartialAuthority",
        "receipt.residualIntentCount", "receipt.orphanPathCount",
    ), "I01 deterministic two-pass durable recovery")
    require(i01.count("exerciseProductionFaultBoundaries(durable.sorted())") == 2,
            "I01 must execute the durable boundary matrix exactly twice")

    r01 = require_swift_function(source, contracts.TEST_METHODS[4], (
        '"two-replica-golden"', '"three-replica-adversarial"',
        "KernelConformanceFixtureShapeV1.allCases", "for schedule in [twoReplica, threeReplica]",
        "exerciseReplicaSchedule(", "shape: shape", "firstRunReplicaProjectionCount",
        "secondRunReplicaProjectionCount", "firstRun.canonicalSnapshotSHA256",
        "firstRun.tombstoneStableKeys", "firstRun.unresolvedConflictSHA256",
        "firstRun.contentDispositionSHA256", "firstRun.contentDependencyIDs",
        "firstRun.observedMutationIDs", "exerciseCompatibilityAndBounds()",
        "unknownBatchVersionRejected", "unknownBatchFieldRejected",
        "unknownConflictRuleRejected", "unknownConflictVersionRejected",
        "unknownRegisteredCodecRejected", "noncanonicalCodecRejected",
        "observedMaximumPageItems", "observedMaximumPageBytes", "scaleMaximumResidentBytes",
        "exerciseRendererReconciliation()", "renderer.pdfReopened",
        "renderer.openJSONReopened", "renderer.structuredTextReopened",
        "renderer.repeatRenderByteIdentical", "renderer.zeroOrCompleteBoundaryCount",
        "renderer.retryByteIdentical", "renderer.legacySnapshotRoundTrip",
        "renderer.oldProfileRendered", "renderer.hostileTextRejectionCount",
        "renderer.privacyCanaryRejected", "renderer.unsupportedAccessibilityClaimRejected",
        "renderer.declaredHostileCaseRejectionCount",
        "renderer.privacyCanaryRejectionCount",
        "renderer.originalAmendedSupersededReconciled",
        "renderer.originalHistoricalBytesImmutable",
        "replay.postConvergence.recoveryCompleted",
    ), "R01 shape-aware 2x2 replay, compatibility, and renderer reconciliation")

    declared = swift_string_inventory(
        harness, "static let productionFaultIdentities: [String: String] = ["
    )
    executed = swift_string_inventory(
        harness, "static let productionExecutedFaultBoundaries: Set<String> = ["
    )
    expected = set(contracts.PRODUCTION_FAULT_BOUNDARIES)
    require(declared == executed == expected and len(expected) == 53,
            "Swift declared/executed production boundary inventories differ from exact 53")

    dispatch = require_swift_function(harness, "exerciseProductionFaultBoundary", (
        "Self.productionExecutedFaultBoundaries.contains(boundary)",
        'boundary.hasPrefix("FINALIZATION_")', "exerciseFinalizationFaultBoundary(boundary)",
        'boundary.hasPrefix("WORK_")', "exerciseWorkFaultBoundary(boundary)",
        'boundary.hasPrefix("REPORT_")', "exerciseReportFaultBoundary(boundary)",
        'boundary.hasPrefix("JOURNAL_")', "exerciseJournalFaultBoundary(boundary)",
        'boundary.hasPrefix("RESTORE_")', "exerciseRestoreFaultBoundary(boundary)",
        'boundary.hasPrefix("DELETE_")', "exerciseDeleteFaultBoundary(boundary)",
        'boundary.hasPrefix("ERASE_")', "exerciseEraseFaultBoundary(boundary)",
        'boundary.hasPrefix("SEARCH_")', "exerciseSearchFaultBoundary(boundary)",
    ), "production family dispatch")
    require(dispatch.count("boundary.hasPrefix(") == 8,
            "production boundary dispatcher must have exactly eight family branches")
    require_swift_function(harness, "exerciseProductionFaultBoundaries", (
        "Set(boundaries).count == boundaries.count", "for boundary in boundaries.sorted()",
        "exerciseProductionFaultBoundary(boundary)",
    ), "production boundary matrix dispatch")

    require_swift_function(harness, "exerciseFullLifecycle", (
        "Self.profile(for: shape)", "validationRegistry.resolve", "createFirstSign(",
        "exercisePackageLifecycle(", "ReportProjectionRegistryV2().validate()",
        "prepareProductionArchive()", "exerciseArchiveRestoreRoundTrip()",
        "rebuildSearchProjectionIfNeeded()", "deleteFirstAssetThroughProductionService(",
        "eraseWorkspaceThroughProductionService(", "relaunchCanonicalSession()",
        "actions.count == KernelConformanceFixtureHarnessV1.requiredLifecycle.count",
        "actions.filter { $0 == action }.count == 1", "executedActions: actions",
    ), "shape-aware production lifecycle")
    full_lifecycle = require_swift_function(harness, "exerciseFullLifecycle", (
        "exercisePackageLifecycle(", "profile: validationProfile",
    ), "single-root shape-aware lifecycle")
    require(full_lifecycle.count("exercisePackageLifecycle(") == 1 and
            "work-recheck" not in full_lifecycle and "nested.filter" not in full_lifecycle,
            "full lifecycle must not graft actions from a second harness/profile")
    require_swift_function(harness, "alternatePackage", (
        'key: "work_context"', 'key: "resolved"', 'key: "issue_still_visible"',
        'key: "original_resolved_different_issue"',
        "contentVersion: package.contentVersion + 1",
    ), "alternate package carries its own work/recheck lifecycle")
    require_swift_function(harness, "exercisePackageLifecycle", (
        "CheckRunnerCoordinator(", "beginCheck(", "prepareReview(",
        "StoreGenerationFactory(applicationSupportURL: activeApplicationSupportURL)",
        "coordinator = try StoreSessionCoordinator(validatingSession: session)",
        "beginOrResumeDraft(",
        "resumedDraft.id == persistedDraftID", "resumedEvidenceCount == 2",
        'actions.append("RESUME")', 'requireValue(runner, "check-runner").finalize(',
        "WorkCoordinator(", "PackFinalizationRecoveryAdapterV1(",
        "runner = nil", "dependencies = nil", "await Task.yield()",
        "recheckPreparation.draftID", "resumedRecheck.id == recheckPreparation.draftID",
    ), "persisted CheckRunner resume and lifecycle recovery")

    require_swift_function(harness, "verifiedSearchFaultReceipt", (
        "LocalSearchIndexStoreV1(applicationSupportURL: searchRoot)",
        "coldStore.revision()", "coldStore.projection(for: revision, registry: registry)",
        "coldStore.rebuildStaging()", "exactRevision", "exactRecords",
        "second.disposition == .current", "staging == nil",
        "guard coldRecoverySucceeded, noPartialAuthority",
    ), "cold search recovery proof")
    require_swift_function(harness, "replayReplicaSchedule", (
        "shape: KernelConformanceFixtureShapeV1", "$0.replayCount == 2",
        'runLabel: "first-', 'runLabel: "second-',
        "firstNormalized == secondNormalized", "postConvergence: post",
    ), "fresh replay-twice schedule")
    require_swift_function(harness, "exerciseCompatibilityAndBounds", (
        "ChangeJournalLimitsV1(", "node.journal.page(after: cursor)",
        "decodeMutationRejected(", "decodeCanonicalPolicyMutationRejected(",
        "unknownRegisteredCodecIsRejected()", "ReplicationCodecV1(",
        "for index in 0..<c11.scaleItemCount", "residentMaximum <= c11.scaleMaximumResidentBytes",
    ), "compatibility and inherited bounds")
    require_swift_function(harness, "exerciseRendererReconciliation", (
        'formats == ["OPEN_JSON", "PDF", "STRUCTURED_TEXT"]',
        'corpus["inheritedAcceptanceTests"]',
        'corpus["hostileCases"]', 'corpus["privacyCanaries"]',
        "ReportProjectionRegistryV2()", "DeterministicPDFRendererV1.reopen",
        "DeterministicOpenJSONRendererV1.reopen", "reopenStructuredText",
        "firstBundle == secondBundle", "ReportProjectionPublicationBoundaryV1.allCases",
        "recoveringFrom: boundary", "retryFromZero == firstBundle",
        "pdfProjection == bundle.semanticProjection",
        "openProjection == bundle.semanticProjection",
        "textProjection == bundle.semanticProjection",
        "bundle.pdf.semanticSHA256 == bundle.openJSON.semanticSHA256",
        "bundle.openJSON.semanticSHA256 == bundle.structuredText.semanticSHA256",
        'FieldEvidenceAppTests/Fixtures/S3_3ReportSnapshotV1.json',
        "ReportSnapshotEncoderV1().decode", "legacySnapshotRoundTrip:",
        '"hostile-control"', '"hostile-bidi"', '"hostile-noncharacter"',
        '"hostile-byte-bound"', "hostileTextRejectionCount == hostileValues.count",
        'with: "PRIVATE-CANARY-NOTE"', "privacyCanaryRejected",
        "blockedPrivacyCanaries == Set(privacyCanaries)",
        "Set(hostileCaseResults.keys) == Set(hostileCaseIDs)",
        "hostileCaseResults.values.allSatisfy",
        "taggedPDFAccessibilityEvidence: true", "unsupportedAccessibilityClaimRejected",
        "CompletedActivitySnapshotChainV1.validate", "priorSnapshot: fixture.snapshot",
        "originalHistoricalBytesImmutable", "originalAmendedSupersededReconciled",
        "WorkspacePackageLifecycleCompatibilityV1.shippingProfile()",
        'snapshotID: "snapshot-old-profile"', "oldProfileRendered",
    ), "full inherited C06 renderer and compatibility reconciliation")
    require_swift_function(harness, "exercisePostConvergenceLifecycle", (
        "BackupExportService(", "BackupRestoreService(",
        "rebuildSearchProjectionIfNeeded()", "WholeSignDeletionService(",
        "EraseAllService(", "reopenedAfterErase", "StoreSessionCoordinator(validatingSession:",
        "DeletionLedgerStore(context: reopenedContext).snapshot() == .empty",
        "recoveryCompleted: recoveryCompleted",
    ), "post-convergence durable recovery")

    forbidden = (
        "consumeFaultInjection", "consumeFaultBoundary", "exerciseDeclaredFaultBoundary",
        "simulateFaultBoundary", "selfCertified", "hardcodedSuccess",
        "coldRecoverySucceeded: true", "noPartialAuthority: true",
        "recoveryCompleted: true", "executedActions: expectedActions",
        "Array(Set(actions)).sorted()",
    )
    require(not [token for token in forbidden if token in harness],
            "removed/dead/self-certifying harness entry point or literal returned")


def generated_checks(root: Path) -> None:
    outputs = contracts.all_outputs(root)
    require(outputs == contracts.all_outputs(root), "generation is not deterministic")
    for relative, raw in outputs.items():
        require((root / relative).read_bytes() == raw, f"stale generated artifact: {relative}")
        value = load(root / relative)
        unsigned = dict(value)
        seal = unsigned.pop("artifactDigest")
        require(seal == contracts.sha256(contracts.pretty(unsigned)), f"artifact seal differs: {relative}")
        require(value["authority"] == contracts.authority(), f"authority differs: {relative}")
        for flag in ("nativeCompileRan", "hostedDispatchEnabled", "phase10PollingDuringParallelExecution",
                     "adoptionEnabled", "acceptanceEnabled", "acceptanceCredit", "releaseCredit"):
            require(value[flag] is False, f"forbidden true claim {flag}: {relative}")
        require(value["requiresAcceptedS10_6Reconciliation"] is True,
                f"S10.6 reconciliation flag differs: {relative}")
    contract = json.loads(outputs[contracts.CONTRACT_PATH])
    require(contract["pathFence"] == contracts.PATH_FENCE and contract["existingPaths"] == [] and
            contract["newPaths"] == contracts.PATH_FENCE, "contract fence partition differs")
    require(contract["fixturePolicy"]["packageCount"] == 2 and
            contract["fixturePolicy"]["structurallyDistinct"] is True and
            contract["fixturePolicy"]["productionBundleRegistryOrUI"] is False,
            "fixture policy differs")
    require(contract["lifecycleTransitions"] == contracts.LIFECYCLE and
            contract["lifecycleTraces"] == contracts.LIFECYCLE_TRACES and
            contract["faultClasses"] == contracts.FAULTS, "lifecycle/fault closure differs")
    require(contract["convergence"]["replicaCounts"] == [2, 3] and
            contract["convergence"]["replaysPerSchedule"] == 2 and
            contract["convergence"]["comparisonSets"] == contracts.NORMALIZED_CONVERGENCE_SETS and
            contract["convergence"]["localJournalByteOrderCompared"] is False,
            "convergence closure differs")
    manifest = json.loads(outputs[contracts.MANIFEST_PATH])
    require([row["path"] for row in manifest["artifacts"]] == contracts.MANIFEST_INPUT_PATHS and
            manifest["artifactSetDigest"] == contracts.sha256(contracts.canonical(manifest["artifacts"])),
            "tooling manifest inventory seal differs")
    evidence = json.loads(outputs[contracts.EVIDENCE_PATH])
    receipts = evidence["portableValidationReceipts"]
    require(receipts == contracts.portable_validation_receipts(root) and
            receipts["networkFetchCount"] == 0 and receipts["deterministicReplayMatched"] is True and
            len(receipts["cases"]) == len({row["caseID"] for row in receipts["cases"]}) == 10 and
            all(row["deterministicReplayMatched"] is True for row in receipts["cases"]),
            "independently observed portable validation receipts differ")


def verify(root: Path) -> dict[str, Any]:
    require(len(contracts.PATH_FENCE) == len(set(contracts.PATH_FENCE)) == 29,
            "path fence must contain exactly 29 unique paths")
    require(len(contracts.SOURCE_PATHS) == 25 and len(contracts.OUTPUT_PATHS) == 4,
            "source/generated partition differs")
    require(not set(contracts.SOURCE_PATHS) & set(contracts.OUTPUT_PATHS), "path partition overlaps")
    require(len(contracts.ACTIVE_S10_RESERVED_PATHS) ==
            len(set(contracts.ACTIVE_S10_RESERVED_PATHS)) == 86 and
            not (set(contracts.PATH_FENCE) & set(contracts.ACTIVE_S10_RESERVED_PATHS)),
            "active S10 reservation inventory/overlap differs")
    for relative in contracts.PATH_FENCE:
        require((root / relative).is_file(), f"missing fenced path: {relative}")
        existed = subprocess.run(["git", "-C", str(root), "cat-file", "-e",
                                  f"{contracts.APP_BASE_HEAD}:{relative}"], capture_output=True).returncode == 0
        require(not existed, f"create-only path existed at base: {relative}")
    changes = git_changes(root)
    require(changes == set(contracts.PATH_FENCE),
            f"changed path set differs from exact 29-path fence: {sorted(changes ^ set(contracts.PATH_FENCE))}")
    fixture_checks(root)
    strict_schema(load(root / contracts.FIXTURE_SCHEMA_PATH),
                  "https://assetrounds.invalid/schemas/v23/kernel-conformance-fixture.schema.json")
    strict_schema(load(root / contracts.CONTRACT_SCHEMA_PATH),
                  "https://assetrounds.invalid/schemas/v23/kernel-conformance-contract.schema.json")
    swift_checks(root)
    generated_checks(root)
    portable_validation_checks(root)
    require(not [path for path in root.rglob("*") if path.name == "__pycache__" or path.suffix in (".pyc", ".pyo")],
            "Python cache leaked")
    return {
        "result": "PASS", "cardID": contracts.CARD, "verificationMode": "STATIC_ONLY",
        "pathFenceCount": 29, "existingPathCount": 0, "newPathCount": 29,
        "evidenceIDCount": 5, "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    try:
        result = verify(root)
    except (VerificationError, contracts.ContractError, OSError, UnicodeError, ValueError,
            subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"V23-P03-C10 static verification failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
