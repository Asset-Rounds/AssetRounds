#!/usr/bin/env python3
"""Hostile static verifier for the Card 27 observation/temporal tooling fence."""
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

from p02_c07_contracts import (
    APP_BASE_HEAD,
    APP_BASE_TREE,
    BASIS_DOC,
    BASIS_SCHEMA,
    CARD,
    CONTRACT_SCRIPT,
    CORPUS_DOC,
    CORPUS_SCHEMA,
    EVIDENCE_IDS,
    EXISTING_PATHS,
    FENCE_DIGEST,
    GENERATED_PATHS,
    GENERATOR_SCRIPT,
    LIFECYCLE_DOC,
    LIFECYCLE_SCHEMA,
    MANIFEST,
    MANIFEST_INPUT_PATHS,
    NEW_PATHS,
    OBSERVATION_BASIS_KINDS,
    OBSERVATION_SOURCE_KINDS,
    PATH_FENCE,
    PROHIBITED_TOKENS,
    SOURCE_PATHS,
    TEMPORAL_DOC,
    TEMPORAL_SCHEMA,
    TEST_METHODS,
    TIME_DISPOSITIONS,
    TOOL_PATHS,
    VERIFIER_SCRIPT,
    all_outputs,
    authority,
    basis_contract,
    corpus_contract,
    flags,
    lifecycle_contract,
    pretty,
    sha,
    source_bindings,
    temporal_contract,
)

ROOT = Path(__file__).resolve().parents[2]


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def load(relative: str) -> Any:
    path = ROOT / relative
    require(path.is_file(), f"missing artifact: {relative}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error


def verify_seal(document: dict[str, Any], name: str) -> None:
    digest = document.get("artifactDigest")
    require(
        isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
        f"{name}: missing/invalid artifactDigest",
    )
    body = dict(document)
    del body["artifactDigest"]
    require(digest == sha(pretty(body)), f"{name}: artifactDigest mismatch")


def verify_flags(document: dict[str, Any], name: str) -> None:
    for key, expected in flags().items():
        require(document.get(key) is expected, f"{name}: flag {key} is not {expected!r}")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        expected = schema["const"]
        require(type(instance) is type(expected) and instance == expected, f"{path}: const mismatch")
    if "enum" in schema:
        require(instance in schema["enum"], f"{path}: enum mismatch")
    kind = schema.get("type")
    if kind == "null":
        require(instance is None, f"{path}: expected null")
    elif kind == "object":
        require(isinstance(instance, dict), f"{path}: expected object")
        required = schema.get("required", [])
        require(set(required).issubset(instance), f"{path}: missing required key")
        if schema.get("additionalProperties") is False:
            require(set(instance).issubset(schema.get("properties", {})), f"{path}: additional property")
        for key, child in schema.get("properties", {}).items():
            if key in instance:
                validate_instance(instance[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(instance, list), f"{path}: expected array")
        require(
            schema.get("minItems", 0) <= len(instance) <= schema.get("maxItems", len(instance)),
            f"{path}: array bounds",
        )
        prefix = schema.get("prefixItems", [])
        require(len(instance) >= len(prefix), f"{path}: missing prefix item")
        for index, child in enumerate(prefix):
            validate_instance(instance[index], child, f"{path}[{index}]")
        if schema.get("items") is False:
            require(len(instance) <= len(prefix), f"{path}: additional item")
    elif kind == "string":
        require(isinstance(instance, str), f"{path}: expected string")
        pattern = schema.get("pattern")
        if pattern:
            require(re.fullmatch(pattern, instance) is not None, f"{path}: pattern mismatch")
    elif kind == "integer":
        require(isinstance(instance, int) and not isinstance(instance, bool), f"{path}: expected integer")
    elif kind == "boolean":
        require(isinstance(instance, bool), f"{path}: expected boolean")
    elif kind is not None:
        raise VerificationError(f"{path}: unsupported schema type {kind!r}")


def verify_strict_schema(schema_document: dict[str, Any], name: str) -> None:
    require(
        schema_document.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
        f"{name}: not Draft 2020-12",
    )
    require(schema_document.get("type") == "object", f"{name}: root is not an object")
    require(schema_document.get("additionalProperties") is False, f"{name}: root is not exact-key")

    def walk(node: Any, location: str) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            require(node.get("additionalProperties") is False, f"{name}{location}: object is not sealed")
            require(
                set(node.get("required", [])) == set(node.get("properties", {})),
                f"{name}{location}: required/property closure differs",
            )
            for key, child in node.get("properties", {}).items():
                walk(child, f"{location}.{key}")
        elif node.get("type") == "array":
            require(node.get("items") is False, f"{name}{location}: array permits extension")
            require(
                node.get("minItems") == node.get("maxItems"),
                f"{name}{location}: array is not fixed length",
            )
            for index, child in enumerate(node.get("prefixItems", [])):
                walk(child, f"{location}[{index}]")

    walk(schema_document, "$")


def verify_generated() -> None:
    expected = all_outputs(ROOT)
    require(list(expected) == GENERATED_PATHS, "generated path order differs")
    for relative, data in expected.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated artifact: {relative}")
        require(path.read_bytes() == data, f"stale generated artifact: {relative}")
        require(path.read_bytes() == pretty(load(relative)), f"{relative}: noncanonical pretty JSON")


def verify_common(document: dict[str, Any], name: str, schema_path: str) -> None:
    verify_seal(document, name)
    verify_flags(document, name)
    require(document.get("cardID") == CARD, f"{name}: card identity mismatch")
    require(document.get("authority") == authority(), f"{name}: authority mismatch")
    require(document.get("evidenceIDs") == EVIDENCE_IDS, f"{name}: evidence IDs mismatch")
    encoded = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    for token in PROHIBITED_TOKENS:
        if token in encoded:
            require(token in document.get("prohibitedTokens", []), f"{name}: prohibited token escaped list: {token}")
    validate_instance(document, load(schema_path), name)


def verify_basis_contract(document: dict[str, Any]) -> None:
    verify_common(document, "basis", BASIS_SCHEMA)
    require(document["persistentChangeMode"] == "NEW_SCHEMA_VERSION", "basis persistent mode differs")
    require(document["schemaBehaviorDelta"] is True and document["migrationBehaviorDelta"] is True, "basis schema delta differs")
    basis = document["basis"]
    require(basis["schemaVersion"] == 1, "basis schema version differs")
    require(basis["kindEnum"] == OBSERVATION_BASIS_KINDS, "basis kind closure differs")
    require(basis["sourceKindEnum"] == OBSERVATION_SOURCE_KINDS, "basis source closure differs")
    require(basis["limitationMaximumCount"] == 16 and basis["methodMaximumUTF8Bytes"] == 128, "basis bounds differ")
    require(basis["sourceReferenceMaximumUTF8Bytes"] == 512 and basis["limitationMaximumUTF8Bytes"] == 2048, "basis text bounds differ")
    require(basis["sourceRules"]["DIRECTLY_OBSERVED"] == ["OBSERVER"], "direct source rule differs")
    require(basis["sourceRules"]["REPORTED"] == ["REPORTED_PARTY", "UNKNOWN"], "reported source rule differs")
    require(basis["sourceRules"]["INFERRED"] == ["RECORD", "UNKNOWN"], "inferred source rule differs")
    require(
        basis["outcomeIndependent"] is True
        and basis["confidenceFieldPresent"] is False
        and basis["directObservationMayBeManufacturedByMigration"] is False
        and basis["unknownIsExplicit"] is True,
        "basis certainty boundary differs",
    )
    codec = basis["canonicalCodec"]
    require(
        codec == {
            "type": "ObservationAndTimeCodecV1",
            "representation": "Data",
            "sortedKeys": True,
            "withoutEscapingSlashes": True,
            "dateEncoding": "millisecondsSince1970",
            "maximumEncodedValueBytes": 32768,
        },
        "basis codec boundary differs",
    )
    migration = document["legacyMigration"]
    require(migration["completeLegacyDisposition"] == "UNVERIFIABLE", "complete legacy disposition differs")
    require(migration["partialLegacyDisposition"] == "UNKNOWN", "partial legacy disposition differs")
    require(migration["retainsLegacyColumns"] is True and migration["inventsDirectObservation"] is False, "legacy migration is unsafe")


def verify_temporal_contract(document: dict[str, Any]) -> None:
    verify_common(document, "temporal", TEMPORAL_SCHEMA)
    require(document["persistentChangeMode"] == "NEW_SCHEMA_VERSION", "temporal persistent mode differs")
    temporal = document["temporal"]
    require(temporal["schemaVersion"] == 1, "temporal schema version differs")
    require(temporal["dispositionEnum"] == TIME_DISPOSITIONS, "temporal disposition closure differs")
    require(
        temporal["fields"] == [
            "occurredAtUTC", "recordedAtUTC", "localDate", "localTime",
            "utcOffsetSeconds", "ianaTimeZoneIdentifier", "localTimeDisposition",
        ],
        "temporal field closure differs",
    )
    require(
        temporal["validation"] == [
            "finiteDate",
            "localDateAndLocalTimeArePaired",
            "ISO8601CivilDate",
            "ISO8601CivilTime",
            "capturedUTCOffsetSecondsWithinInclusivePlusOrMinus64800",
            "nonEmptyTrimmedControlFreeTimeZoneIdentifier",
            "timeZoneIdentifierUTF8ByteCountAtMost255",
        ],
        "temporal validation semantics differ",
    )
    require(temporal["offsetInclusiveRange"] == [-64800, 64800], "temporal offset bound differs")
    require(temporal["timeZoneIdentifierMaximumUTF8Bytes"] == 255, "temporal zone bound differs")
    require(
        temporal["liveCreation"] == {
            "method": "wallTimeRecord(timeZone:)",
            "derivesCurrentOffsetAndDST": True,
            "capturesZoneOffsetAndDisposition": True,
        },
        "temporal live derivation differs",
    )
    require(
        temporal["durableValidation"] == {
            "usesCapturedTuple": True,
            "reopensTimeZoneDatabase": False,
            "rederivesOffsetOrDST": False,
        },
        "temporal durable validation reopens TZDB",
    )
    require(temporal["causalOrdering"] == "FORBIDDEN" and temporal["durationMeasurement"] == "FORBIDDEN", "wall clock escaped causal authority")
    require(document["monotonicSeparation"]["persistedMonotonicTicks"] is False, "monotonic ticks became persistent")


def verify_lifecycle_contract(document: dict[str, Any]) -> None:
    verify_common(document, "lifecycle", LIFECYCLE_SCHEMA)
    require(document["persistentContractSchema"] == "ObservationAndTimeSchemaV1", "lifecycle schema identity differs")
    require(
        all(document[key] is True for key in (
            "schemaBehaviorDelta", "migrationBehaviorDelta", "backupBehaviorDelta",
            "restoreBehaviorDelta", "deleteBehaviorDelta", "exportBehaviorDelta",
            "backupCompatibilityRequired", "restoreCompatibilityRequired",
            "deleteCompatibilityRequired", "exportCompatibilityRequired",
        )),
        "lifecycle compatibility closure differs",
    )
    require(document["downgradeDisposition"] == "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION", "downgrade policy differs")
    lifecycle = document["lifecycle"]
    require(lifecycle["migration"]["legacyCouldNotVerify"] == "LOSSLESS_TO_UNVERIFIABLE_OR_UNKNOWN", "legacy migration lifecycle differs")
    require(lifecycle["migration"]["directObservationFabrication"] is False, "migration fabricates observation")
    require(lifecycle["canonicalMutation"]["writer"] == "WorkspaceWriterAdapterV1", "canonical writer differs")
    require(lifecycle["canonicalMutation"]["effectBeforeReceipt"] is True, "effect/receipt order differs")
    require(lifecycle["canonicalMutation"]["partialObservationOrTemporalBytes"] is False, "partial durable bytes permitted")
    require(
        lifecycle["interruptionBoundaries"] == [
            "afterEffectBeforeReceipt",
            "afterReceiptBeforeSave",
            "afterSaveBeforeReturn",
        ],
        "interruption boundary closure differs",
    )
    require(
        lifecycle["portable"] == {
            "backup": "ROUND_TRIP_CANONICAL_OBSERVATION_AND_TEMPORAL_BYTES",
            "replaceRestore": "REBUILD_FROM_CANONICAL_INCOMPLETE_INTENTS",
            "clone": "PRESERVE_CANONICAL_BYTES_WITH_NEW_GENERATION_ID",
            "fork": "PRESERVE_CANONICAL_BYTES_WITH_EXPLICIT_FORK_IDENTITY",
            "export": "INCLUDE_CANONICAL_OBSERVATION_AND_TEMPORAL_BYTES",
            "import": "VALIDATE_AND_QUARANTINE_UNSUPPORTED_OR_MALFORMED_BYTES",
            "journalReplay": "REPLAY_IDEMPOTENTLY_WITH_SAME_CANONICAL_BYTES",
            "report": "RENDER_CAPTURED_BASIS_AND_TEMPORAL_CONTEXT",
            "delete": "REMOVE_EMBEDDED_VALUES_ATOMICALLY_WITH_CANONICAL_DELETE",
            "erase": "REMOVE_EMBEDDED_VALUES_ATOMICALLY_WITH_CANONICAL_ERASE",
        },
        "portable lifecycle differs",
    )
    require(document["sourceBindings"] == source_bindings(), "lifecycle source binding closure differs")
    s10 = document["s10Exclusions"]
    require(
        s10 == {
            "phase10PollingDuringParallelExecution": False,
            "nativeEvidence": False,
            "hostedEvidence": False,
            "physicalEvidence": False,
            "adoptionEnabled": False,
            "acceptanceEnabled": False,
            "releaseReady": False,
            "requiresAcceptedS10_6Reconciliation": True,
        },
        "S10 exclusion boundary differs",
    )


def verify_corpus_contract(document: dict[str, Any]) -> None:
    verify_common(document, "corpus", CORPUS_SCHEMA)
    require(document["fixtureTopLevelFields"] == [
        "schemaVersion", "fixtureIdentity", "basisKinds", "outcomes", "golden",
        "alternate", "hostileTimeCases", "interruptionBoundaries",
        "legacyCouldNotVerify", "portableLifecycle", "unsupportedSchemaVersion",
    ], "fixture top-level field closure differs")
    require(document["fixtureRequiredBasisKinds"] == [
        "directly_observed", "reported_by_person", "inferred",
        "not_observed", "unverifiable", "unknown",
    ], "fixture basis cases differ")
    require(document["fixtureRequiredOutcomes"] == ["compliant", "noncompliant", "unknown"], "fixture outcomes differ")
    require(document["fixtureRequiredHostileTimeCaseIDs"] == [
        "fall-fold-first", "fall-fold-second", "spring-gap", "unknown-zone", "wall-clock-rollback",
    ], "fixture hostile cases differ")
    require(document["fixtureRequiredPortableLifecycle"] == [
        "backup", "replace_restore", "clone", "fork", "export", "import", "journal_replay", "delete", "erase",
    ], "fixture lifecycle cases differ")
    require(document["exactFiveTestMethods"] is True and document["fixtureGeneratedByTooling"] is False, "corpus acceptance boundary differs")
    require([item["testMethod"] for item in document["evidence"]] == TEST_METHODS, "exact five evidence mapping differs")
    require(document["requiredCoverage"] == corpus_contract()["requiredCoverage"], "coverage families differ")
    require(len(document["executableEvidence"]) == 6 and document["hostileFailClosed"] is True, "executable hostile evidence differs")
    require(document["fixtureLegacyMigration"]["directObservationFabricated"] is False, "legacy fixture fabricates observation")
    require(document["lifecycle"]["noPersistedMonotonicTicks"] is True and document["lifecycle"]["noCausalWallClockOrdering"] is True, "corpus permits unsafe time semantics")


def verify_contracts() -> None:
    verify_basis_contract(load(BASIS_DOC))
    verify_temporal_contract(load(TEMPORAL_DOC))
    verify_lifecycle_contract(load(LIFECYCLE_DOC))
    verify_corpus_contract(load(CORPUS_DOC))


def verify_manifest() -> None:
    manifest = load(MANIFEST)
    verify_seal(manifest, MANIFEST)
    verify_flags(manifest, MANIFEST)
    require(manifest["authority"] == authority(), "manifest authority differs")
    require(manifest["pathFence"] == PATH_FENCE and manifest["pathFenceCount"] == 50 and len(set(PATH_FENCE)) == 50, "exact 50-path fence differs")
    require(manifest["existingPaths"] == EXISTING_PATHS and manifest["newPaths"] == NEW_PATHS, "path disposition differs")
    require(manifest["sourcePaths"] == SOURCE_PATHS and manifest["sourcePathCount"] == 38, "source closure differs")
    require(manifest["toolingPaths"] == TOOL_PATHS and manifest["toolingPathCount"] == 12, "tooling closure differs")
    require(manifest["generatedPaths"] == GENERATED_PATHS, "generated closure differs")
    require(
        manifest["artifactCount"] == 49
        and [item["path"] for item in manifest["artifacts"]] == MANIFEST_INPUT_PATHS,
        "sealed input closure differs",
    )
    require(manifest["artifactSetDigest"] == sha(pretty(manifest["artifacts"])), "artifact set digest differs")
    fence = manifest["fenceProof"]
    require(
        fence["baseHead"] == APP_BASE_HEAD
        and fence["baseTree"] == APP_BASE_TREE
        and fence["pathFenceDigest"] == FENCE_DIGEST
        and fence["allowedDeletePaths"] == []
        and fence["allowedRenamePaths"] == [],
        "manifest fence boundary differs",
    )
    require(
        fence["priorFenceOverlapCount"] == 108
        and fence["authorizedPriorFenceOverlapCount"] == 108
        and fence["unauthorizedPriorFenceOverlapCount"] == 0
        and fence["activeS10Overlap"] is False,
        "manifest overlap proof differs",
    )
    for item in manifest["artifacts"]:
        path = ROOT / item["path"]
        require(path.is_file(), f"sealed input missing: {item['path']}")
        data = path.read_bytes()
        require((item["bytes"], item["sha256"]) == (len(data), sha(data)), f"sealed input hash mismatch: {item['path']}")


def require_tokens(relative: str, tokens: list[str]) -> str:
    path = ROOT / relative
    require(path.is_file(), f"missing fenced source: {relative}")
    text = path.read_text(encoding="utf-8")
    for token in tokens:
        require(token in text, f"{relative}: missing source token {token!r}")
    return text


def verify_sources() -> None:
    bindings = load(LIFECYCLE_DOC)["sourceBindings"]
    require(len(bindings) == len(SOURCE_PATHS) and [item["path"] for item in bindings] == SOURCE_PATHS, "source binding closure differs")
    source_texts = {
        binding["path"]: require_tokens(binding["path"], binding["requiredTokens"])
        for binding in bindings
    }
    test_text = source_texts[SOURCE_PATHS[36]]
    require([method for method in TEST_METHODS if f"func {method}(" in test_text] == TEST_METHODS, "exact five Card27 test methods missing")
    require(test_text.count("func testV9_11") == 5, "Card27 test family contains an extra or missing test")
    require("nonisolated(unsafe)" not in test_text, "unsafe concurrency escape in Card27 tests")

    fixture = load(SOURCE_PATHS[37])
    corpus = load(CORPUS_DOC)
    require(list(fixture) == corpus["fixtureTopLevelFields"], "fixture byte shape differs")
    require(fixture["schemaVersion"] == 1 and fixture["fixtureIdentity"] == corpus["fixtureIdentity"], "fixture identity differs")
    require(fixture["basisKinds"] == corpus["fixtureRequiredBasisKinds"], "fixture basis kind vector differs")
    require(fixture["outcomes"] == corpus["fixtureRequiredOutcomes"], "fixture outcome vector differs")
    require([item["id"] for item in fixture["hostileTimeCases"]] == corpus["fixtureRequiredHostileTimeCaseIDs"], "fixture hostile case vector differs")
    require(fixture["interruptionBoundaries"] == corpus["fixtureRequiredInterruptionBoundaries"], "fixture interruption vector differs")
    require(fixture["portableLifecycle"] == corpus["fixtureRequiredPortableLifecycle"], "fixture portable lifecycle differs")
    require(fixture["legacyCouldNotVerify"] == {
        "outcomeKey": "could_not_verify",
        "reasonKey": "required_view_obstructed",
        "reasonDisplaySnapshot": "Required view is blocked",
        "reasonRegistryVersion": "cnv.reason.en-US.v1",
        "expectedBasisKind": "unverifiable",
        "expectedMethod": "unknown",
        "expectedSourceReference": None,
    }, "fixture legacy migration vector differs")
    require(fixture["unsupportedSchemaVersion"] == 2147483647, "fixture unsupported schema vector differs")

    model_text = source_texts[SOURCE_PATHS[28]]
    require("struct ObservationBasisV1" in model_text and "struct TemporalContextV1" in model_text, "core observation/time types missing")
    require("ObservationAndTimeCodecV1" in model_text and "ObservationAndTimeLegacyMigrationV1" in model_text, "core codec/migration missing")
    require("maximumEncodedValueBytes = 32 * 1_024" in model_text and "sortedKeys" in model_text and "millisecondsSince1970" in model_text, "canonical codec bounds differ")
    require("case directlyObserved = \"DIRECTLY_OBSERVED\"" in model_text and "case reported = \"REPORTED\"" in model_text, "basis raw cases differ")
    require("case ambiguousFold = \"AMBIGUOUS_FOLD\"" in model_text and "case nonexistentGap = \"NONEXISTENT_GAP\"" in model_text, "temporal raw cases differ")

    mutation_text = source_texts[SOURCE_PATHS[5]]
    require("pre-ObservationAndTimeSchemaV1" in mutation_text and "observationBasis" in mutation_text and "temporalContext" in mutation_text, "mutation compatibility bridge missing")
    writer_text = source_texts[SOURCE_PATHS[10]]
    require("ObservationAndTimeCodecV1.encode" in writer_text and "observationBasisData" in writer_text and "temporalContextData" in writer_text, "writer codec integration missing")
    migration_text = source_texts[SOURCE_PATHS[8]]
    require("inventedDirectObservation" in migration_text and "legacy" in migration_text, "migration receipt safety missing")
    portable = "\n".join(source_texts.values())
    for token in ("ObservationBasisV1", "TemporalContextV1", "backup", "restore", "export", "delete", "erase", "replay"):
        require(token in portable, f"portable lifecycle source evidence missing: {token}")


def verify_hostile_rejection() -> None:
    basis = load(BASIS_DOC)
    schema_document = load(BASIS_SCHEMA)
    mutations = []
    extra = copy.deepcopy(basis)
    extra["unexpected"] = True
    mutations.append(extra)
    missing = copy.deepcopy(basis)
    del missing["basis"]
    mutations.append(missing)
    changed = copy.deepcopy(basis)
    changed["basis"]["kindEnum"][0] = "OUTCOME_DERIVED"
    mutations.append(changed)
    bad_digest = copy.deepcopy(basis)
    bad_digest["artifactDigest"] = "z" * 64
    for index, mutation in enumerate(mutations):
        try:
            validate_instance(mutation, schema_document)
        except VerificationError:
            continue
        raise VerificationError(f"hostile basis mutation accepted: {index}")
    try:
        verify_seal(bad_digest, "hostile-basis")
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile sealed basis accepted")

    temporal = load(TEMPORAL_DOC)
    temporal_schema = load(TEMPORAL_SCHEMA)
    unsafe = copy.deepcopy(temporal)
    unsafe["temporal"]["durableValidation"]["reopensTimeZoneDatabase"] = True
    try:
        validate_instance(unsafe, temporal_schema)
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile temporal TZDB mutation accepted")

    corpus = load(CORPUS_DOC)
    corpus_schema = load(CORPUS_SCHEMA)
    hostile = copy.deepcopy(corpus)
    hostile["requiredCoverage"]["G01"][0] = "OUTCOME_INFERRED"
    try:
        validate_instance(hostile, corpus_schema)
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile corpus coverage mutation accepted")

    manifest = load(MANIFEST)
    hostile_manifest = copy.deepcopy(manifest)
    hostile_manifest["pathFence"][0] = "outside/fence"
    try:
        verify_seal(hostile_manifest, "hostile-manifest")
    except VerificationError:
        pass
    else:
        raise VerificationError("hostile manifest fence mutation accepted")


def verify_python_and_generator() -> None:
    for relative in (CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT):
        ast.parse((ROOT / relative).read_text(encoding="utf-8"), filename=relative)
    result = subprocess.run(
        [sys.executable, "-B", str(ROOT / GENERATOR_SCRIPT), "--check", "--root", str(ROOT)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    require(result.returncode == 0, f"generator --check failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    try:
        verify_generated()
        for path in (BASIS_SCHEMA, TEMPORAL_SCHEMA, LIFECYCLE_SCHEMA, CORPUS_SCHEMA):
            verify_strict_schema(load(path), path)
        verify_contracts()
        verify_manifest()
        verify_sources()
        verify_hostile_rejection()
        verify_python_and_generator()
    except (VerificationError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"V23-P02-C07 verification failed: {error}", file=sys.stderr)
        return 1
    print("V23-P02-C07 hostile static verification passed: 50 fence paths, 49 sealed inputs, 4 strict schemas, 5 evidence tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
