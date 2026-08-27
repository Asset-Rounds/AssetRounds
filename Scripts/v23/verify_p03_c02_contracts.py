#!/usr/bin/env python3
"""Hostile independent verifier for Card 33 package-release evidence.

This verifier does not call the generator to decide whether a result is valid.
It independently rechecks the closed fence, live Swift declarations, source
and fixture bindings, strict schema shape, seals, and semantic boundaries.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

import p03_c02_contracts as c


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def read(root: Path, relative: str) -> bytes:
    path = root / relative
    require(path.is_file(), f"missing fenced path: {relative}")
    return path.read_bytes()


def text(root: Path, relative: str) -> str:
    try:
        return read(root, relative).decode("utf-8")
    except UnicodeDecodeError as error:
        raise VerificationError(f"{relative}: non-UTF-8 input") from error


def load(root: Path, relative: str) -> dict[str, Any]:
    raw = read(root, relative)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{relative}: JSON root is not an object")
    require(raw == c.pretty(value), f"{relative}: JSON is not canonical pretty form")
    return value


def load_input_json(root: Path, relative: str) -> dict[str, Any]:
    raw = read(root, relative)
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{relative}: JSON root is not an object")
    return value


def verify_seal(value: dict[str, Any], label: str) -> None:
    observed = value.get("artifactDigest")
    require(isinstance(observed, str) and re.fullmatch(r"[0-9a-f]{64}", observed) is not None, f"{label}: malformed artifactDigest")
    body = dict(value)
    body.pop("artifactDigest")
    require(observed == c.sha(c.pretty(body)), f"{label}: artifactDigest mismatch")


def validate_instance(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "$ref" in schema:
        require(schema["$ref"].startswith("#/$defs/"), f"{path}: external schema reference")
        return
    if "anyOf" in schema:
        alternatives = schema["anyOf"]
        require(isinstance(alternatives, list) and alternatives, f"{path}: anyOf is empty")
        errors: list[str] = []
        for alternative in alternatives:
            try:
                validate_instance(value, alternative, path)
                return
            except VerificationError as error:
                errors.append(str(error))
        raise VerificationError(f"{path}: no anyOf alternative matched: {errors}")
    if "const" in schema:
        expected = schema["const"]
        require(type(value) is type(expected) and value == expected, f"{path}: const mismatch")
    if "pattern" in schema:
        require(isinstance(value, str) and re.fullmatch(schema["pattern"], value) is not None, f"{path}: pattern mismatch")
    if "enum" in schema:
        require(value in schema["enum"], f"{path}: enum mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(value, dict), f"{path}: object expected")
        props = schema.get("properties", {})
        require(set(value).issubset(props), f"{path}: additional property")
        require(set(schema.get("required", [])) <= set(value), f"{path}: required property missing")
        for key, child in props.items():
            if key in value:
                validate_instance(value[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(value, list), f"{path}: array expected")
        if "minItems" in schema:
            require(len(value) >= schema["minItems"], f"{path}: array below minimum")
        if "maxItems" in schema:
            require(len(value) <= schema["maxItems"], f"{path}: array above maximum")
        if "prefixItems" in schema:
            prefix = schema["prefixItems"]
            require(len(value) == len(prefix), f"{path}: array length differs")
            for index, child in enumerate(prefix):
                validate_instance(value[index], child, f"{path}[{index}]")
        elif schema.get("items") is not False:
            child = schema.get("items")
            require(isinstance(child, dict), f"{path}: array item schema missing")
            for index, item in enumerate(value):
                validate_instance(item, child, f"{path}[{index}]")
    elif kind == "string":
        require(isinstance(value, str), f"{path}: string expected")
    elif kind == "integer":
        require(isinstance(value, int) and not isinstance(value, bool), f"{path}: integer expected")
    elif kind == "boolean":
        require(isinstance(value, bool), f"{path}: boolean expected")
    elif kind == "null":
        require(value is None, f"{path}: null expected")
    elif kind is not None:
        raise VerificationError(f"{path}: unsupported schema type {kind!r}")


def verify_strict_schema(schema: dict[str, Any], label: str) -> None:
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema", f"{label}: wrong Draft 2020-12 URI")
    require(isinstance(schema.get("$id"), str) and schema["$id"].startswith("https://assetrounds.invalid/v23/"), f"{label}: wrong $id")
    require(isinstance(schema.get("title"), str) and schema["title"], f"{label}: missing title")

    def walk(node: Any, path: str) -> None:
        require(isinstance(node, dict), f"{label}{path}: schema node is not an object")
        if "$ref" in node:
            require(isinstance(node["$ref"], str) and node["$ref"].startswith("#/$defs/"), f"{label}{path}: unsafe schema reference")
            return
        if "anyOf" in node:
            alternatives = node["anyOf"]
            require(isinstance(alternatives, list) and len(alternatives) >= 2, f"{label}{path}: anyOf is not closed")
            for index, child in enumerate(alternatives):
                walk(child, f"{path}.anyOf[{index}]")
            return
        if node.get("type") == "object":
            props = node.get("properties")
            require(isinstance(props, dict), f"{label}{path}: properties missing")
            require(node.get("additionalProperties") is False, f"{label}{path}: object is open")
            required = node.get("required", [])
            require(isinstance(required, list) and len(required) == len(set(required)), f"{label}{path}: required list is invalid")
            require(set(required) <= set(props), f"{label}{path}: required/property closure differs")
            for key, child in props.items():
                walk(child, f"{path}.{key}")
        elif node.get("type") == "array":
            if "prefixItems" in node:
                require(node.get("items") is False, f"{label}{path}: tuple array is open")
                prefix = node.get("prefixItems")
                require(isinstance(prefix, list) and node.get("minItems") == node.get("maxItems") == len(prefix), f"{label}{path}: array is not exact")
                for index, child in enumerate(prefix):
                    walk(child, f"{path}[{index}]")
            else:
                items = node.get("items")
                require(isinstance(items, dict), f"{label}{path}: array item schema missing")
                minimum = node.get("minItems")
                maximum = node.get("maxItems")
                require(isinstance(minimum, int) and minimum >= 0, f"{label}{path}: array minimum missing")
                require(maximum is None or isinstance(maximum, int) and maximum >= minimum, f"{label}{path}: array maximum invalid")
                walk(items, f"{path}[]")
        elif "const" not in node and node.get("type") not in {"string", "integer", "boolean", "null"}:
            raise VerificationError(f"{label}{path}: unconstrained schema node")

    walk(schema, "$")
    definitions = schema.get("$defs", {})
    require(isinstance(definitions, dict), f"{label}: $defs is not an object")
    for name, definition in definitions.items():
        require(re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name) is not None, f"{label}: invalid $defs name")
        walk(definition, f"$.$defs.{name}")


def verify_domain_schemas(schemas: dict[str, dict[str, Any]]) -> None:
    titles = [schema.get("title") for schema in schemas.values()]
    ids = [schema.get("$id") for schema in schemas.values()]
    require(len(titles) == len(set(titles)) == 6, "domain schema titles are not unique")
    require(len(ids) == len(set(ids)) == 6, "domain schema IDs are not unique")
    for relative, title in c.SCHEMA_TITLES.items():
        schema = schemas[relative]
        require(schema.get("title") == title, f"{relative}: domain title differs")
        require(schema.get("$id") == f"https://assetrounds.invalid/v23/{title}.schema.json", f"{relative}: domain $id differs")
        props = schema.get("properties")
        required = schema.get("required")
        require(isinstance(props, dict) and set(props) == set(c.SCHEMA_PROPERTY_FIELDS[title]), f"{relative}: domain property shape differs")
        require(isinstance(required, list) and set(required) == set(c.SCHEMA_REQUIRED_FIELDS[title]), f"{relative}: required domain fields differ")
        require(schema.get("additionalProperties") is False, f"{relative}: domain schema is open")
    require(schemas[c.NODE_SCHEMA].get("description") == "TRUE_FALSE_UNKNOWN_DESTINATIONS_ARE_EXPLICIT_VALID_IDS_CONVERGENCE_ALLOWED", "node schema destination policy differs")


def enum_values(source: str, enum_name: str) -> list[str]:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\b[^{{]*\{{(.*?)\n\}}", source, re.S)
    require(match is not None, f"missing enum {enum_name}")
    values = re.findall(r"\bcase\s+[A-Za-z0-9_]+\s*=\s*\"([^\"]+)\"", match.group(1))
    require(values and len(values) == len(set(values)), f"invalid enum {enum_name}")
    return values


def case_names(source: str, enum_name: str) -> list[str]:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\b[^{{]*\{{(.*?)\n\}}", source, re.S)
    require(match is not None, f"missing enum {enum_name}")
    values = re.findall(r"\bcase\s+([A-Za-z0-9_]+)(?:\s*=|\s*$)", match.group(1), re.M)
    require(values and len(values) == len(set(values)), f"invalid cases {enum_name}")
    return values


def static_ints(source: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for name in c.EXPECTED_LIMITS:
        match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*([0-9][0-9_]*)", source)
        require(match is not None, f"missing grammar limit {name}")
        result[name] = int(match.group(1).replace("_", ""))
    return result


def static_string(source: str, name: str) -> str:
    match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*\"([^\"]+)\"", source)
    require(match is not None, f"missing static string {name}")
    return match.group(1)


def verify_fence(root: Path, manifest: dict[str, Any]) -> None:
    require(len(c.PATH_FENCE) == 24 and len(set(c.PATH_FENCE)) == 24, "Card33 fence is not exactly 24 unique paths")
    require(len(c.EXISTING_PATHS) == 2 and len(c.NEW_PATHS) == 22, "Card33 existing/new partition differs")
    require(len(c.TOOL_PATHS) == 15 and len(c.GENERATED_PATHS) == 12, "Card33 tooling partition differs")
    require(manifest.get("pathFence") == c.PATH_FENCE, "manifest fence differs")
    require(manifest.get("pathFenceCount") == 24, "manifest fence count differs")
    require(manifest.get("existingPaths") == c.EXISTING_PATHS, "manifest existing paths differ")
    require(manifest.get("sourcePaths") == c.SOURCE_PATHS and manifest.get("sourcePathCount") == 9, "manifest source paths differ")
    require(manifest.get("toolingPaths") == c.TOOL_PATHS and manifest.get("toolingPathCount") == 15, "manifest tooling paths differ")
    require(manifest.get("generatedPaths") == c.GENERATED_PATHS, "manifest generated paths differ")
    require(manifest.get("newPaths") == c.NEW_PATHS, "manifest new paths differ")
    fence = manifest.get("fenceProof")
    require(isinstance(fence, dict), "manifest fence proof missing")
    require(fence.get("baseHead") == c.APP_BASE_HEAD and fence.get("baseTree") == c.APP_BASE_TREE, "manifest app base differs")
    require(fence.get("pathFenceDigest") == c.FENCE_DIGEST, "manifest fence digest differs")
    require(fence.get("allowedPathCount") == 24 and fence.get("existingPathCount") == 2 and fence.get("newPathCount") == 22, "manifest fence counts differ")
    require(fence.get("priorFenceCount") == c.PRIOR_FENCE_COUNT and fence.get("priorOwnedPathCount") == c.PRIOR_OWNED_PATH_COUNT, "prior fence inventory differs")
    require(fence.get("priorFenceOverlapCount") == len(c.PRIOR_FENCE_OVERLAP_EDGES), "prior overlap count differs")
    require(fence.get("authorizedPriorFenceOverlapCount") == len(c.PRIOR_FENCE_OVERLAP_EDGES), "authorized prior overlap count differs")
    require(fence.get("unauthorizedPriorFenceOverlapCount") == 0, "unauthorized prior overlap is nonzero")
    require(fence.get("authorizedOverlapEdges") == c.PRIOR_FENCE_OVERLAP_EDGES, "authorized prior overlap edges differ")
    require(fence.get("activeS10Overlap") is False and fence.get("activeS10ReservationDigest") == c.S10_RESERVATION_DIGEST, "S10 reservation proof differs")
    rows = manifest.get("artifacts")
    require(isinstance(rows, list) and len(rows) == 23, "manifest must seal 23 non-manifest inputs")
    require([row.get("path") for row in rows] == c.MANIFEST_INPUT_PATHS, "manifest input order differs")
    for row in rows:
        relative = row.get("path")
        require(relative in c.MANIFEST_INPUT_PATHS, "manifest input path outside fence")
        data = read(root, relative)
        require(row.get("bytes") == len(data) and row.get("sha256") == c.sha(data), f"manifest input digest differs: {relative}")
    require(manifest.get("artifactCount") == 23 and manifest.get("pendingFencePaths") == [] and manifest.get("pendingArtifactCount") == 0, "manifest input completeness differs")
    require(manifest.get("artifactSetDigest") == c.sha(c.pretty(rows)), "manifest artifact set digest differs")


def verify_authority(value: dict[str, Any], label: str) -> None:
    require(value.get("authority") == c.authority(), f"{label}: authority differs")


def verify_common(value: dict[str, Any], label: str) -> None:
    verify_seal(value, label)
    verify_authority(value, label)
    require(value.get("schemaVersion") == 1 and value.get("cardID") == c.CARD, f"{label}: identity differs")
    require(value.get("persistentChangeMode") == "DECLARATION_ONLY", f"{label}: persistent mode differs")
    require(value.get("persistentContractSchema") == "KERNEL_CONTRACT_V1", f"{label}: persistent schema differs")
    require(value.get("downgradeDisposition") == "DORMANT_REVERT_ALLOWED", f"{label}: downgrade differs")
    for key in c.LIFECYCLE_DELTAS:
        require(value.get(key) is False, f"{label}: lifecycle delta is not false: {key}")
    for key, expected in c.flags().items():
        require(value.get(key) == expected, f"{label}: flag differs: {key}")
    require(value.get("provisionalKernelOnly") is True, f"{label}: provisional kernel flag differs")
    require(value.get("shippingBoundaryAdoption") == "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION", f"{label}: adoption boundary differs")
    require(value.get("noNewSwiftDataV6Entity") is True, f"{label}: V6 entity claim differs")
    require(value.get("evidenceIDs") == c.EVIDENCE_IDS, f"{label}: evidence IDs differ")


def verify_source_bindings(value: dict[str, Any], root: Path) -> None:
    rows = value.get("sourceBindings")
    require(isinstance(rows, list) and len(rows) == 9, "source binding count differs")
    seen: list[str] = []
    for row in rows:
        require(isinstance(row, dict), "source binding row is not an object")
        relative = row.get("path")
        require(relative in c.SOURCE_PATHS and relative not in seen, f"source binding path differs: {relative}")
        seen.append(relative)
        data = read(root, relative)
        require(row.get("bytes") == len(data) and row.get("sha256") == c.sha(data), f"source binding digest differs: {relative}")
        tokens = row.get("requiredTokens")
        symbols = row.get("symbols")
        require(isinstance(tokens, list) and tokens and all(isinstance(item, str) for item in tokens), f"{relative}: token list missing")
        require(isinstance(symbols, list) and symbols and all(isinstance(item, str) for item in symbols), f"{relative}: symbol list missing")
        raw = data.decode("utf-8").lower()
        for token in tokens:
            require(token.lower() in raw, f"{relative}: source token absent: {token}")
    require(seen == c.SOURCE_PATHS, "source binding order/coverage differs")


def verify_source_semantics(root: Path, manifest: dict[str, Any]) -> tuple[list[str], dict[str, Any]]:
    package = text(root, c.EXISTING_PATHS[0])
    bundled = text(root, c.EXISTING_PATHS[1])
    grammar = text(root, c.NEW_SOURCE_PATHS[0])
    definition = text(root, c.NEW_SOURCE_PATHS[1])
    validator = text(root, c.NEW_SOURCE_PATHS[2])
    release = text(root, c.NEW_SOURCE_PATHS[3])
    binding = text(root, c.NEW_SOURCE_PATHS[4])
    tests = text(root, c.NEW_SOURCE_PATHS[5])
    fixture = load_input_json(root, c.NEW_SOURCE_PATHS[6])

    require(static_string(package, "name") == "PACKAGE_REGISTRY_V2", "predecessor registry name differs")
    require(re.search(r"\bstatic\s+let\s+version\s*=\s*2", package) is not None, "predecessor registry version differs")
    require("InspectionPackageCanonicalCodecV2" in package and "InspectionPackageClosedCodingV2" in package, "predecessor strict codec missing")
    require(static_string(bundled, "source") == "BUNDLED_ONLY", "bundled source policy differs")
    require("runtimeDownloadsAllowed = false" in bundled and "InspectionPackageReleaseV1.makeDraft" in bundled, "bundled release bridge differs")

    require(enum_values(grammar, "WorkflowNodeKindV1") == c.NODE_KINDS, "workflow node enum differs")
    require(enum_values(grammar, "BranchPredicateKindV1") == c.PREDICATE_KINDS, "predicate enum differs")
    require(enum_values(grammar, "BranchTruthValueV1") == c.TRUTH_VALUES, "truth enum differs")
    require(enum_values(grammar, "FixedComparisonOperatorV1") == c.COMPARISON_OPERATORS, "comparison enum differs")
    require(case_names(grammar, "InspectionKernelFailureV1") == c.FAILURE_VALUES, "kernel failure enum differs")
    require(static_ints(grammar) == c.EXPECTED_LIMITS, "workflow limits differ")
    for token in ("WorkflowGrammarValidationV1", "validID", "BranchPredicateV1", "WorkflowBranchDestinationsV1", "values.allSatisfy(WorkflowGrammarValidationV1.validID)", "destination(for value: BranchTruthValueV1)"):
        require(token in grammar, f"grammar token missing: {token}")

    for source, tokens, label in [
        (definition, ("WorkflowNodeV1", "WorkflowDefinitionV1", "validateShape", "outgoingNodeIDs", "repeatBodyEntryNodeID", "maximumRepeatInstances"), "definition"),
        (validator, ("WorkflowGraphValidatorV1", "reachable", "cycle", "maximumEdgeCount", "maximumGraphDepth", "forwardPredicateReference", "unreachableNode", "missingTarget"), "validator"),
        (release, ("InspectionPackageReleaseV1", "packageReleaseID", "canonicalPackageBytes", "packageSHA256", "canonicalWorkflowBytes", "workflowSHA256", "DRAFT", "TESTED", "PUBLISHED", "InspectionPackageReleasePublisherV1", "makeDraft"), "release"),
        (binding, ("PackageReleaseBindingV1", "packageReleaseID", "packageSHA256", "canonicalPackageBytes", "validateResume", "hashMismatch", "makeDraft"), "binding"),
    ]:
        for token in tokens:
            require(token.lower() in source.lower(), f"{label} token missing: {token}")

    methods = re.findall(r"\bfunc\s+(testV9_12[A-Za-z0-9_]*)\s*\(", tests)
    require(len(methods) == 5 and len(set(methods)) == 5, f"expected exactly five V9_12 tests, found {methods}")
    families: list[str] = []
    for method in methods:
        match = re.fullmatch(r"testV9_12([GAHIR]01).*", method)
        require(match is not None, f"test method lacks evidence family: {method}")
        families.append(match.group(1))
    require(sorted(families) == sorted(c.EVIDENCE_FAMILIES), "V9_12 evidence family coverage differs")
    require(manifest.get("testMethods") == methods, "manifest test selectors differ")
    for token in ("XCTestCase", "XCTAssert", "XCTAssertThrowsError", "relaunch", "interruption", "fail"):
        require(token.lower() in tests.lower(), f"test evidence token missing: {token}")

    destinations = fixture.get("truthDestinations")
    require(isinstance(destinations, dict) and set(destinations) == {"TRUE", "FALSE", "UNKNOWN"}, "fixture truth destinations are incomplete")
    values = list(destinations.values())
    require(all(isinstance(value, str) and re.fullmatch(r"[a-z0-9._-]{1,128}", value) is not None for value in values), "fixture truth destinations are not explicit valid IDs")

    require(fixture.get("schema") == "V21P03C02WorkflowGraphCorpusV1" and fixture.get("schemaVersion") == 1 and fixture.get("testOnly") is True, "workflow corpus identity differs")
    require(sorted(fixture.get("nodeKinds", [])) == sorted(c.NODE_KINDS), "fixture node kinds differ")
    require(sorted(fixture.get("predicateKinds", [])) == sorted(c.PREDICATE_KINDS), "fixture predicate kinds differ")
    require(fixture.get("releaseStates") == c.RELEASE_STATUSES and fixture.get("bindingKinds") == sorted(c.BINDING_KINDS), "fixture release/binding states differ")
    require(fixture.get("interruptionBoundaries") == sorted(c.RELEASE_BOUNDARIES), "fixture interruption boundaries differ")
    require(fixture.get("failureDisposition") == "FAIL_CLOSED", "fixture failure disposition differs")
    require(fixture.get("negativeCases") == c.NEGATIVE_CASES, "fixture hostile cases differ")
    repeat = fixture.get("repeat")
    require(isinstance(repeat, dict), "fixture repeat containment is missing")
    require(sorted(repeat) == ["activitySequence", "instanceID", "multiNodeBodyIDs", "nestedBodyIDs", "nestedRepeatCount", "repeatNodeID", "stableOrder"], "fixture repeat keys differ")
    require(repeat.get("activitySequence") == ["ACTIVE", "INACTIVE_BY_PATH", "REACTIVATION_REVIEW_REQUIRED"], "fixture repeat activity sequence differs")
    require(repeat.get("instanceID") == "fixture.repeat.instance.0001" and repeat.get("repeatNodeID") == "node.repeat" and repeat.get("stableOrder") == 0, "fixture repeat identity differs")
    require(repeat.get("multiNodeBodyIDs") == ["node.body.entry", "node.body.exit", "node.body.interior"], "fixture multi-node repeat body differs")
    require(repeat.get("nestedBodyIDs") == ["node.inner.branch", "node.inner.exit", "node.inner.repeat", "node.outer.entry", "node.outer.exit"], "fixture nested repeat body differs")
    require(repeat.get("nestedRepeatCount") == 2, "fixture nested repeat count differs")
    fixture_blob = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    for marker in ("DRAFT", "ACTIVE", "COMPLETED", "BEFORE_VALIDATION", "AFTER_PUBLICATION_BEFORE_RECEIPT", "FAIL_CLOSED"):
        require(marker in fixture_blob, f"fixture marker missing: {marker}")

    forbidden = re.compile(r"URLSession|URLRequest|CloudKit|SwiftData|StoreKit|CKRecord|NWPathMonitor|https?://", re.I)
    for relative in c.NEW_SOURCE_PATHS[:5]:
        require(forbidden.search(text(root, relative)) is None, f"forbidden production integration token: {relative}")
    require("SignPack" not in grammar and "ShippingIlluminatedSignAdapter" not in grammar, "sign-specific dependency leaked into kernel grammar")
    require("SignPack" not in definition and "ShippingIlluminatedSignAdapter" not in definition, "sign-specific dependency leaked into workflow definition")
    return methods, fixture


def verify_semantic_documents(root: Path, docs: dict[str, dict[str, Any]], methods: list[str], fixture: dict[str, Any]) -> None:
    release = docs[c.RELEASE_DOC]
    release_value = release.get("release")
    require(isinstance(release_value, dict), "release contract missing release object")
    require(release_value.get("type") == "InspectionPackageReleaseV1", "release type differs")
    require(release_value.get("statuses") == c.RELEASE_STATUSES, "release statuses differ")
    require(release_value.get("immutablePublication") is True and release_value.get("draftTestPublishTransitions") is True, "release immutability differs")
    require(release_value.get("maximumCanonicalBytes") == 1_048_576, "release canonical bound differs")
    lifecycle = release_value.get("lifecycle")
    require(isinstance(lifecycle, dict) and lifecycle.get("mode") == "DECLARATION_ONLY" and lifecycle.get("schema") == "KERNEL_CONTRACT_V1", "release lifecycle differs")
    require(all(lifecycle.get(key) is False for key in ("migrationRequired", "backupRestoreRequired", "deleteEraseRequired", "exportReportRequired")), "release lifecycle delta differs")

    grammar = docs[c.GRAMMAR_DOC].get("grammar")
    require(isinstance(grammar, dict), "grammar contract missing")
    require(grammar.get("nodeKinds") == c.NODE_KINDS and grammar.get("predicateKinds") == c.PREDICATE_KINDS, "grammar values differ")
    require(grammar.get("truthValues") == c.TRUTH_VALUES and grammar.get("comparisonOperators") == c.COMPARISON_OPERATORS, "grammar operators differ")
    require(grammar.get("limits") == c.EXPECTED_LIMITS and grammar.get("unknownKindDisposition") == "FAIL_CLOSED", "grammar limits/policy differ")
    require(grammar.get("branchDestinations") == "TRUE_FALSE_UNKNOWN_DESTINATIONS_ARE_EXPLICIT_VALID_IDS_CONVERGENCE_ALLOWED", "grammar destination policy differs")
    require(grammar.get("truthResolution") == "ONE_TRUTH_VALUE_SELECTS_EXACTLY_ONE_DESTINATION", "grammar truth resolution differs")

    validation = docs[c.VALIDATION_DOC].get("validation")
    require(isinstance(validation, dict) and validation.get("validator") == "WorkflowGraphValidatorV1", "validator contract missing")
    require(validation.get("failureKinds") == c.FAILURE_VALUES, "validator failure kinds differ")
    require(validation.get("diagnosticsNeverAccept") is True and validation.get("invalidGraphDisposition") == "FAIL_CLOSED_WITH_NO_CANONICAL_PUBLICATION", "validator acceptance boundary differs")
    require(isinstance(docs[c.VALIDATION_DOC].get("hostileInputMatrix"), list) and len(docs[c.VALIDATION_DOC]["hostileInputMatrix"]) >= 8, "hostile validation matrix is weak")

    pinning = docs[c.PINNING_DOC].get("pinning")
    require(isinstance(pinning, dict) and pinning.get("bindingType") == "PackageReleaseBindingV1", "pinning contract missing")
    require(pinning.get("immutableStatuses") == ["TESTED", "PUBLISHED"], "immutable release statuses differ")
    require(pinning.get("amendmentRequiresNewReleaseID") is True and pinning.get("hashMismatchDisposition") == "FAIL_CLOSED", "pinning safety differs")
    interruption = pinning.get("interruption")
    require(isinstance(interruption, dict) and interruption.get("boundaries") == c.RELEASE_BOUNDARIES and interruption.get("partialPublicationAllowed") is False, "pinning interruption boundary differs")

    evidence = docs[c.EVIDENCE_DOC]
    rows = evidence.get("evidence")
    require(isinstance(rows, list) and len(rows) == 5, "evidence rows differ")
    require([row.get("evidenceID") for row in rows] == c.EVIDENCE_IDS, "evidence IDs differ")
    require([row.get("family") for row in rows] == list(c.EVIDENCE_FAMILIES), "evidence family order differs")
    require(evidence.get("testMethods") == methods, "evidence test methods differ")
    require(evidence.get("interruptionBoundaries") == c.RELEASE_BOUNDARIES, "evidence interruption boundaries differ")
    require([row.get("requiredOutcome") for row in rows] == [c.EVIDENCE_OUTCOMES[family] for family in c.EVIDENCE_FAMILIES], "evidence outcomes differ")
    fixture_value = evidence.get("fixture")
    require(isinstance(fixture_value, dict) and fixture_value.get("testOnly") is True and fixture_value.get("schemaVersion") == fixture.get("schemaVersion"), "fixture evidence differs")
    require(fixture_value.get("sourceSHA256") == c.sha(read(root, c.NEW_SOURCE_PATHS[6])), "fixture source digest differs")
    require(fixture_value.get("repeat") == fixture.get("repeat"), "fixture repeat evidence differs")
    brand = evidence.get("brandImpact")
    require(isinstance(brand, dict) and brand.get("manifestType") == "BrandImpactManifestV1" and brand.get("manifestCount") == 1, "brand impact receipt differs")
    require(brand.get("changedScreens") == [] and brand.get("changedStates") == [], "Card33 claims a UI delta")
    privacy = evidence.get("privacy")
    require(isinstance(privacy, dict) and all(value is False for value in privacy.values()), "privacy boundary differs")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        manifest = load(root, c.MANIFEST)
        verify_common(manifest, c.MANIFEST)
        verify_fence(root, manifest)
        schema_paths = [c.RELEASE_SCHEMA, c.DEFINITION_SCHEMA, c.NODE_SCHEMA, c.PREDICATE_SCHEMA, c.BINDING_SCHEMA, c.EVIDENCE_SCHEMA]
        schemas = {relative: load(root, relative) for relative in schema_paths}
        for relative, schema in schemas.items():
            verify_strict_schema(schema, relative)
        verify_domain_schemas(schemas)
        doc_paths = [c.RELEASE_DOC, c.GRAMMAR_DOC, c.VALIDATION_DOC, c.PINNING_DOC, c.EVIDENCE_DOC]
        docs = {relative: load(root, relative) for relative in doc_paths}
        for relative, document in docs.items():
            verify_common(document, relative)
            verify_source_bindings(document, root)
        methods, fixture = verify_source_semantics(root, manifest)
        verify_semantic_documents(root, docs, methods, fixture)
        # The manifest is also the independently checked summary, not merely a
        # list of hashes.
        require(manifest.get("strictSchemaCount") == 6 and manifest.get("contractDocumentCount") == 5, "manifest artifact class counts differ")
        require(manifest.get("declarationOnly") is True and manifest.get("privacyAllowlistOnly") is True and manifest.get("noNetwork") is True, "manifest boundary differs")
    except (VerificationError, OSError, UnicodeError, ValueError) as error:
        print(f"V23-P03-C02 hostile verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P03-C02 hostile static verification passed: 24 fence paths, 23 sealed inputs, 6 strict schemas, 5 evidence tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
