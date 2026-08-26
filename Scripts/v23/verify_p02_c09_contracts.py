#!/usr/bin/env python3
"""Hostile static verifier for the Card 29 lifecycle coverage gate."""
from __future__ import annotations

import ast
import copy
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable

sys.dont_write_bytecode = True

import p02_c09_contracts as c


ROOT = Path(__file__).resolve().parents[2]
S10_RESERVATION = "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
FALSE_EVIDENCE_FLAGS = {
    "nativeCompileRan", "hostedDispatchEnabled", "hostedDispatchRan",
    "physicalEvidenceComplete", "adoptionEnabled", "acceptanceEnabled",
    "acceptanceCredit", "releaseReady", "releaseCredit",
    "phase10PollingDuringParallelExecution", "nativeOrHostedEvidenceClaimed",
    "acceptanceOrReleaseClaimed",
}
GAP_SETS = [
    "missingKindIDs", "duplicateKindIDs", "conflictingKindIDs", "unknownKindIDs",
    "ownershipGapKindIDs", "temporalConflictKindIDs", "backupRestoreGapKindIDs",
    "eraseGapKindIDs", "exportReportGapKindIDs", "searchAbsenceGapKindIDs",
    "rebuildDependencyGapKindIDs", "replayGapKindIDs", "unresolvedAuthorityKindIDs",
    "sourceDriftIDs",
]
REPORT_KIND_NAMES = {"ReportSnapshotV1", "reportPDF", "reportSnapshot"}
ERASE_ACTION_BY_CLASS = {
    "CANONICAL": "SUPPORTED",
    "IMMUTABLE": "IMMUTABLE",
    "DERIVED": "REBUILDABLE",
    "CONTENT": "CONTENT_MANAGED",
    "DECLARATION": "IMMUTABLE",
    "WIRE": "NOT_APPLICABLE",
    "NONPERSISTENT": "NOT_APPLICABLE",
}
ERASE_OBSERVED_BY_CLASS = {
    "CANONICAL": "REMOVED",
    "IMMUTABLE": "PRESERVED_IMMUTABLE",
    "DERIVED": "REBUILT_EMPTY",
    "CONTENT": "CLEARED_BY_DECLARED_OWNER",
    "DECLARATION": "PRESERVED_IMMUTABLE",
    "WIRE": "NOT_APPLICABLE",
    "NONPERSISTENT": "NOT_APPLICABLE",
}
PROVENANCE_PARTITION = {
    ("PRE_V23_BASELINE", 0): 54,
    ("V23_P01_C03", 16): 6,
    ("V23_P01_C04", 17): 1,
    ("V23_P01_C05", 18): 1,
    ("V23_P01_C06", 19): 3,
    ("V23_P02_C02", 22): 18,
    ("V23_P02_C04", 24): 4,
    ("V23_P02_C07", 27): 6,
    ("V23_P02_C08", 28): 7,
}
PROVENANCE_HISTORY_ANCHORS = {
    "PERSISTENT_MODEL:PersistentSchemaReleaseMarker": ("V23_P01_C03", 16, "989d73460e4614e3bbea6c1dc20a9da0a1e5f660"),
    "PROJECTION:StreamingArchiveIndexV1": ("V23_P01_C04", 17, "8e2536f42e6381412d22de302b013f606c2ec42f"),
    "JOURNAL:CurrentGenerationPointerV3": ("V23_P01_C05", 18, "417aec8af085ac4e01d4b73c822ba99511a14611"),
    "PERSISTENT_MODEL:DeletionLedgerRow": ("V23_P01_C06", 19, "e576a3ca91d597fff41d0f23209bab009ff8de6b"),
    "PERSISTENT_MODEL:EntityMutationRevisionRow": ("V23_P02_C02", 22, "e05839a52a93a367cf4b118974a45db0d47182d0"),
    "OWNED_FILE_CLASS:generationLeaseControl": ("V23_P02_C04", 24, "a6742867a235ad7cc4e4bc07f2b650cca82434cd"),
    "PERSISTENT_MODEL:ObservationAndTimeRow": ("V23_P02_C07", 27, "5f4259dc9d46090203d59273f0c35b1ab1ee6a0d"),
    "DIAGNOSTIC:DeviceOperationalSupportStoreV2": ("V23_P02_C08", 28, "c5aaa2a6b6f4a1c900e5743648b66252d19f5ef7"),
}
KNOWN_LATER_ORIGINS = {
    kind_id: (card, ordinal)
    for kind_id, (card, ordinal, _) in PROVENANCE_HISTORY_ANCHORS.items()
}


class VerificationError(AssertionError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def read(relative: str) -> str:
    path = ROOT / relative
    require(path.is_file(), f"missing file: {relative}")
    return path.read_text(encoding="utf-8")


def load(relative: str) -> Any:
    try:
        return json.loads(read(relative))
    except json.JSONDecodeError as error:
        raise VerificationError(f"{relative}: invalid JSON: {error}") from error


def verify_seal(document: dict[str, Any], label: str) -> None:
    digest = document.get("artifactDigest")
    require(isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
            f"{label}: invalid artifactDigest")
    body = dict(document)
    body.pop("artifactDigest")
    require(digest == c.sha(c.pretty(body)), f"{label}: artifactDigest mismatch")


def validate_instance(instance: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema:
        expected = schema["const"]
        require(type(instance) is type(expected) and instance == expected, f"{path}: const mismatch")
    if "enum" in schema:
        require(instance in schema["enum"], f"{path}: enum mismatch")
    kind = schema.get("type")
    if kind == "object":
        require(isinstance(instance, dict), f"{path}: expected object")
        properties = schema.get("properties", {})
        require(set(schema.get("required", [])).issubset(instance), f"{path}: missing required key")
        if schema.get("additionalProperties") is False:
            require(set(instance).issubset(properties), f"{path}: additional property")
        for key, child in properties.items():
            if key in instance:
                validate_instance(instance[key], child, f"{path}.{key}")
    elif kind == "array":
        require(isinstance(instance, list), f"{path}: expected array")
        require(schema.get("minItems", 0) <= len(instance) <= schema.get("maxItems", len(instance)),
                f"{path}: array bounds")
        prefix = schema.get("prefixItems", [])
        for index, child in enumerate(prefix):
            require(index < len(instance), f"{path}: missing prefix item")
            validate_instance(instance[index], child, f"{path}[{index}]")
        if schema.get("items") is False:
            require(len(instance) == len(prefix), f"{path}: additional item")
    elif kind == "string":
        require(isinstance(instance, str), f"{path}: expected string")
        if "pattern" in schema:
            require(re.fullmatch(schema["pattern"], instance) is not None, f"{path}: pattern mismatch")
    elif kind == "integer":
        require(isinstance(instance, int) and not isinstance(instance, bool), f"{path}: expected integer")
    elif kind == "boolean":
        require(isinstance(instance, bool), f"{path}: expected boolean")
    elif kind == "null":
        require(instance is None, f"{path}: expected null")
    elif kind is not None:
        raise VerificationError(f"{path}: unsupported schema type {kind!r}")


def verify_strict_schema(schema: dict[str, Any], label: str) -> None:
    require(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema",
            f"{label}: schema draft differs")

    def walk(node: Any, path: str) -> None:
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            properties = node.get("properties", {})
            require(node.get("additionalProperties") is False, f"{label}{path}: object is open")
            require(set(node.get("required", [])) == set(properties),
                    f"{label}{path}: required/property closure differs")
            for key, child in properties.items():
                walk(child, f"{path}.{key}")
        elif node.get("type") == "array":
            require(node.get("items") is False, f"{label}{path}: array is open")
            require(node.get("minItems") == node.get("maxItems") == len(node.get("prefixItems", [])),
                    f"{label}{path}: array bounds differ")
            for index, child in enumerate(node.get("prefixItems", [])):
                walk(child, f"{path}[{index}]")

    walk(schema, "$")


def verify_with_jsonschema(instance: Any, schema: dict[str, Any], label: str) -> None:
    try:
        import jsonschema  # type: ignore[import-not-found]
    except ImportError:
        return
    try:
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(instance)
    except jsonschema.exceptions.ValidationError as error:
        raise VerificationError(f"{label}: jsonschema validation failed: {error.message}") from error
    except jsonschema.exceptions.SchemaError as error:
        raise VerificationError(f"{label}: invalid Draft 2020-12 schema: {error.message}") from error


def walk_flags(value: Any, label: str) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in FALSE_EVIDENCE_FLAGS:
                expected = child.get("const") if isinstance(child, dict) and "const" in child else child
                require(expected is False, f"{label}: {key} overclaims evidence")
            if key == "requiresAcceptedS10_6Reconciliation":
                expected = child.get("const") if isinstance(child, dict) and "const" in child else child
                require(expected is True, f"{label}: S10.6 reconciliation is not required")
            walk_flags(child, label)
    elif isinstance(value, list):
        for child in value:
            walk_flags(child, label)


def swift_block(source: str, marker: str) -> str:
    start = source.find(marker)
    require(start >= 0, f"missing Swift declaration: {marker}")
    brace = source.find("{", start)
    require(brace >= 0, f"missing Swift body: {marker}")
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:index]
    raise VerificationError(f"unterminated Swift declaration: {marker}")


def enum_raw_values(source: str, enum_name: str) -> list[str]:
    block = swift_block(source, f"enum {enum_name}")
    return re.findall(r"\bcase\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*\"([^\"]+)\"", block)


def plain_enum_cases(source: str, enum_name: str) -> list[str]:
    block = swift_block(source, f"enum {enum_name}")
    values: list[str] = []
    for line in block.splitlines():
        match = re.match(r"\s*case\s+(.+?)\s*$", line)
        if match:
            values.extend(part.strip().split("(")[0] for part in match.group(1).split(","))
    return values


def catalog_array(source: str, name: str) -> list[str]:
    match = re.search(rf"static\s+let\s+{re.escape(name)}(?:\s*:\s*[^=]+)?\s*=\s*\[(.*?)\n\s*\]", source, re.S)
    require(match is not None, f"missing catalog array: {name}")
    return re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', match.group(1))


def schema_models(source: str, version: int, cache: dict[int, list[str]] | None = None) -> list[str]:
    cache = {} if cache is None else cache
    if version in cache:
        return cache[version]
    block = swift_block(source, f"enum PersistentSchemaV{version}:")
    model_match = re.search(r"static\s+var\s+models[^\{]*\{(.*?)\n\s*\}", block, re.S)
    require(model_match is not None, f"PersistentSchemaV{version}: missing models")
    body = model_match.group(1)
    parent = re.search(r"PersistentSchemaV(\d+)\.models", body)
    values = schema_models(source, int(parent.group(1)), cache) if parent else []
    if "PersistentModelCatalog.models" in body:
        catalog = swift_block(source, "enum PersistentModelCatalog")
        values += re.findall(r"modelType:\s*([A-Za-z_][A-Za-z0-9_]*)\.self", catalog)
    values += [name for name in re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\.self\b", body)
               if not name.startswith("PersistentSchemaV")]
    cache[version] = values
    return values


def independent_universe() -> dict[str, Any]:
    catalog_source = read(c.EXISTING_PATHS[2])
    fields: dict[str, dict[str, Any]] = {}
    kind_ids: list[str] = []
    counts: dict[str, int] = {}
    for name, category in c.UNIVERSE_CATEGORIES:
        names = catalog_array(catalog_source, name)
        require(len(names) == len(set(names)), f"{name}: duplicate catalog name")
        ids = [f"{category}:{value}" for value in names]
        fields[name] = {"category": category, "names": names, "count": len(names), "kindIDs": ids}
        kind_ids.extend(ids)
        counts[category] = counts.get(category, 0) + len(names)
    require(len(kind_ids) == len(set(kind_ids)), "catalog universe contains duplicate kind IDs")

    schema_names = schema_models(read(c.EXISTING_PATHS[3]), 5)
    require(len(schema_names) == 14 and set(schema_names) == set(fields["persistentModelNames"]["names"]),
            "PersistentSchemaV5 model universe differs from current catalog")
    file_cases = plain_enum_cases(read(c.EXISTING_PATHS[4]), "OwnedFileKindV1")
    require(len(file_cases) == 24 and set(file_cases) == set(fields["ownedFileClassNames"]["names"]),
            "OwnedFileKindV1 24-case universe differs from current catalog")
    return {
        "fields": fields,
        "kindIDs": sorted(kind_ids),
        "kindCount": len(kind_ids),
        "categoryCounts": counts,
        "schemaNames": schema_names,
        "ownedFileCases": file_cases,
    }


def independent_compiler_provenance(universe: dict[str, Any]) -> dict[str, tuple[str, int]]:
    compiler = read(c.NEW_SOURCE_PATHS[1])
    block = swift_block(compiler, "static let laterTemporalOrigins")
    origins = {
        name: (card, int(ordinal))
        for name, card, ordinal in re.findall(
            r'let\s+(c\d+)\s*=\s*TemporalOriginV1\(card:\s*"([^"]+)",\s*ordinal:\s*(\d+)\)',
            block,
        )
    }
    require(set(origins.values()) == set(PROVENANCE_PARTITION) - {("PRE_V23_BASELINE", 0)},
            "compiler temporal origin declarations differ from accepted card chronology")
    later: dict[str, tuple[str, int]] = {}
    groups = re.findall(r"\((c\d+),\s*\[(.*?)\]\)", block, re.S)
    require(len(groups) == 8, "compiler temporal provenance does not contain eight later groups")
    for variable, members in groups:
        require(variable in origins, f"compiler temporal group uses unknown origin {variable}")
        kind_ids = re.findall(r'"([A-Z_]+:[^"]+)"', members)
        require(kind_ids, f"compiler temporal group {variable} is empty")
        for kind_id in kind_ids:
            require(kind_id not in later, f"compiler temporal provenance duplicates {kind_id}")
            later[kind_id] = origins[variable]
    require(len(later) == 46 and set(later).issubset(universe["kindIDs"]),
            "compiler later temporal provenance is not exact 46 in-universe kinds")
    result = {
        kind_id: later.get(kind_id, ("PRE_V23_BASELINE", 0))
        for kind_id in universe["kindIDs"]
    }
    counts: dict[tuple[str, int], int] = {}
    for origin in result.values():
        counts[origin] = counts.get(origin, 0) + 1
    require(counts == PROVENANCE_PARTITION,
            f"compiler provenance partition differs: {counts}")
    require(len(set(result.values())) == 9,
            "compiler provenance collapsed to uniform placeholder values")
    for kind_id, origin in KNOWN_LATER_ORIGINS.items():
        require(result.get(kind_id) == origin,
                f"compiler provenance differs for {kind_id}")
    require("laterTemporalOrigins[kindID] ?? baselineTemporalOrigin" in compiler,
            "compiler temporal provenance lacks exhaustive baseline completion")
    require("laterTemporalOrigins.count == 46" in compiler
            and "durableKindIDs.count == 65" in compiler
            and "result.count == kindIDs.count" in compiler,
            "compiler temporal provenance lacks exhaustive count guards")
    return result


def independent_durable_kind_ids(kind_ids: list[str]) -> list[str]:
    durable_categories = {"PERSISTENT_MODEL", "OWNED_FILE_CLASS", "JOURNAL"}
    durable_exceptions = {
        "PROJECTION:ReportSnapshotV1",
        "PROJECTION:entityMutationRevision",
        "PROJECTION:workspaceMutationState",
        "DIAGNOSTIC:DeviceOperationalSupportStoreV2",
        "DIAGNOSTIC:ScratchDataLeaseStoreV1",
        "DIAGNOSTIC:diagnosticCounters",
    }
    result = sorted(kind_id for kind_id in kind_ids
                    if kind_id.split(":", 1)[0] in durable_categories
                    or kind_id in durable_exceptions)
    require(len(result) == 65 and len(set(kind_ids) - set(result)) == 35,
            "independently derived durable/no-write split is not 65/35")
    return result


def verify_tooling_provenance(
    projection: dict[str, Any],
    universe: dict[str, Any],
    provenance: dict[str, tuple[str, int]],
    label: str,
) -> None:
    rows = projection.get("rows")
    require(isinstance(rows, list) and len(rows) == 100,
            f"{label}: tooling provenance is not exact 100 rows")
    require([row.get("kindID") for row in rows] == universe["kindIDs"],
            f"{label}: tooling provenance is not exact sorted universe")
    require(len({row["kindID"] for row in rows}) == 100,
            f"{label}: duplicate tooling provenance kind")
    durable_ids = independent_durable_kind_ids(universe["kindIDs"])
    observed_durable: list[str] = []
    for row in rows:
        kind_id = row["kindID"]
        card, ordinal = provenance[kind_id]
        require((row.get("representationSourceCard"), row.get("representationSourceOrdinal"))
                == (card, ordinal), f"{label}: wrong provenance for {kind_id}")
        temporal = row.get("temporalEvidence")
        require(isinstance(temporal, dict), f"{label}: missing temporal evidence for {kind_id}")
        require((temporal.get("representationSourceCard"),
                 temporal.get("representationSourceOrdinal")) == (card, ordinal),
                f"{label}: nested provenance differs for {kind_id}")
        durable = kind_id in durable_ids
        require(row.get("durableRepresentationWrite") is durable,
                f"{label}: durable-write classification differs for {kind_id}")
        if durable:
            observed_durable.append(kind_id)
            require(temporal.get("disposition") == "PREEXISTING_BOUND_FORWARD_FIX"
                    and temporal.get("firstWriteVersion") == card
                    and temporal.get("firstWriteOrdinal") == ordinal
                    and temporal.get("forwardFixVersion") == "V23_P02_C09"
                    and temporal.get("forwardFixOrdinal") == 29,
                    f"{label}: durable chronology differs for {kind_id}")
        else:
            require(temporal.get("disposition") == "NONPERSISTENT_NO_CANONICAL_WRITE"
                    and temporal.get("firstWriteVersion") == "NOT_APPLICABLE"
                    and temporal.get("firstWriteOrdinal") == 0
                    and temporal.get("forwardFixVersion") == "NOT_APPLICABLE"
                    and temporal.get("forwardFixOrdinal") == 0,
                    f"{label}: no-write chronology differs for {kind_id}")
        require(temporal.get("lifecycleEnrollmentVersion") == "V23_P02_C09"
                and temporal.get("lifecycleEnrollmentOrdinal") == 29,
                f"{label}: enrollment chronology differs for {kind_id}")
        body = dict(row)
        digest = body.pop("rowDigest", None)
        require(digest == c.sha(c.canonical(body)),
                f"{label}: row digest differs for {kind_id}")
    require(observed_durable == durable_ids
            and projection.get("durableFirstWriteKindIDs") == durable_ids
            and projection.get("durableFirstWriteCount") == 65,
            f"{label}: tooling durable-write set differs")
    require(projection.get("rowCount") == 100
            and projection.get("originPartitionCounts") == {
                f"{card}@{ordinal}": count
                for (card, ordinal), count in PROVENANCE_PARTITION.items()
            }
            and projection.get("uniformPlaceholderRejected") is True,
            f"{label}: provenance counts/uniform-placeholder policy differs")
    partition = projection.get("originPartition")
    require(isinstance(partition, list) and len(partition) == 9,
            f"{label}: origin partition is not exact nine groups")
    flattened: dict[str, tuple[str, int]] = {}
    for group in partition:
        origin = (group["representationSourceCard"], group["representationSourceOrdinal"])
        require(group["kindCount"] == len(group["kindIDs"])
                == PROVENANCE_PARTITION[origin],
                f"{label}: origin partition count differs for {origin}")
        for kind_id in group["kindIDs"]:
            require(kind_id not in flattened, f"{label}: duplicate partition kind {kind_id}")
            flattened[kind_id] = origin
    require(flattened == provenance,
            f"{label}: exhaustive tooling/compiler provenance differs")
    expected_source_paths = sorted([
        c.EXISTING_PATHS[0], c.EXISTING_PATHS[1], c.EXISTING_PATHS[2],
        c.EXISTING_PATHS[3], c.NEW_SOURCE_PATHS[0], c.NEW_SOURCE_PATHS[1],
        c.NEW_SOURCE_PATHS[2], c.NEW_SOURCE_PATHS[3],
    ])
    expected_source_rows = []
    for relative in expected_source_paths:
        data = (ROOT / relative).read_bytes()
        expected_source_rows.append({
            "path": relative, "bytes": len(data), "sha256": c.sha(data),
        })
    require(projection.get("sourceDigestRows") == expected_source_rows
            and projection.get("sourceDigestSetDigest") == c.sha(c.canonical(expected_source_rows)),
            f"{label}: temporal provenance source digest set differs")
    canonical_members = sorted("|".join([
        row["kindID"],
        row["temporalEvidence"]["evidenceID"],
        str(row["temporalEvidence"]["evidenceVersion"]),
        row["temporalEvidence"]["disposition"],
        row["temporalEvidence"]["representationSourceCard"],
        str(row["temporalEvidence"]["representationSourceOrdinal"]),
        row["temporalEvidence"]["firstWriteVersion"],
        str(row["temporalEvidence"]["firstWriteOrdinal"]),
        row["temporalEvidence"]["lifecycleEnrollmentVersion"],
        str(row["temporalEvidence"]["lifecycleEnrollmentOrdinal"]),
        row["temporalEvidence"]["forwardFixVersion"],
        str(row["temporalEvidence"]["forwardFixOrdinal"]),
    ]) for row in rows)
    require(projection.get("temporalRegistryCanonicalDigest")
            == c.sha(c.canonical(canonical_members)),
            f"{label}: temporal registry canonical digest differs")
    require(projection.get("acceptedTemporalUniverseDigest")
            == c.sha(c.canonical(universe["kindIDs"])),
            f"{label}: accepted temporal universe digest differs")
    require(projection.get("crossCardAnchors") == [
        {
            "kindID": kind_id, "card": card, "ordinal": ordinal,
            "commit": commit, "required": True,
        }
        for kind_id, (card, ordinal, commit) in PROVENANCE_HISTORY_ANCHORS.items()
    ], f"{label}: selected cross-card provenance anchors differ")


def verify_source_bindings() -> None:
    bindings = c.source_bindings()
    require(len(bindings) == len(c.SOURCE_PATHS) == 9, "source-binding count differs")
    require([row["path"] for row in bindings] == c.SOURCE_PATHS, "source-binding path order differs")
    require(len({row["path"] for row in bindings}) == 9, "duplicate source binding")
    for binding in bindings:
        text = read(binding["path"])
        require(binding["owner"].strip() != "", f"{binding['path']}: empty owner")
        for token in binding["requiredTokens"]:
            require(token in text, f"{binding['path']}: missing bound token {token}")


def verify_path_fence() -> None:
    require(len(c.PATH_FENCE) == len(set(c.PATH_FENCE)) == 24, "path fence is not 24 unique paths")
    require(c.PATH_FENCE == c.EXISTING_PATHS + c.NEW_PATHS, "path fence partition/order differs")
    for relative in c.PATH_FENCE:
        require((ROOT / relative).is_file(), f"current fence path is missing: {relative}")
        result = subprocess.run(
            ["git", "-C", str(ROOT), "cat-file", "-e", f"{c.APP_BASE_HEAD}:{relative}"],
            capture_output=True,
        )
        expected_at_base = relative in c.EXISTING_PATHS
        require((result.returncode == 0) is expected_at_base,
                f"base-head existing/new disposition differs: {relative}")
    require(len(c.EXISTING_PATHS) == 5 and len(c.NEW_PATHS) == 19,
            "path fence is not 5 existing + 19 new")

    reservation = load(S10_RESERVATION)
    reserved = reservation.get("reservedPaths")
    require(isinstance(reserved, list) and len(reserved) == len(set(reserved)) == 86,
            "active S10 reservation is not 86 unique paths")
    require(reservation.get("reservedPathCount") == 86
            and reservation.get("contentDigest") == c.S10_RESERVATION_DIGEST,
            "active S10 reservation seal/count differs")
    require(set(c.PATH_FENCE).isdisjoint(reserved), "Card29 fence overlaps active S10 ownership")


def verify_provenance_history_anchors() -> None:
    """Bind one representative from every post-baseline origin to Git history."""
    for kind_id, (card, ordinal, commit) in PROVENANCE_HISTORY_ANCHORS.items():
        ancestry = subprocess.run(
            ["git", "-C", str(ROOT), "merge-base", "--is-ancestor", commit, c.APP_BASE_HEAD],
            capture_output=True, text=True, encoding="utf-8",
        )
        require(ancestry.returncode == 0,
                f"history anchor {card}@{ordinal} is not in the accepted Card29 base")
        change = subprocess.run(
            ["git", "-C", str(ROOT), "show", "--format=", "--unified=0", commit,
             "--", "FieldEvidenceApp"],
            capture_output=True, text=True, encoding="utf-8",
        )
        require(change.returncode == 0, f"cannot inspect history anchor {commit}")
        stable_name = kind_id.split(":", 1)[1]
        require(any(
            line.startswith("+") and not line.startswith("+++") and stable_name in line
            for line in change.stdout.splitlines()
        ), f"history anchor {card}@{ordinal} does not introduce {kind_id}")


def verify_fixture_value(
    fixture: dict[str, Any],
    universe: dict[str, Any] | None = None,
    provenance: dict[str, tuple[str, int]] | None = None,
) -> None:
    require(set(fixture) == c._fixture_shape(), "fixture top-level closure differs")
    require(fixture["schemaVersion"] == 1, "fixture schema version differs")
    require(fixture["fixtureIdentity"] == "V21-P02-C09-PERSISTENT-KIND-LIFECYCLE-COVERAGE-CORPUS-V1",
            "fixture identity differs")
    authority = fixture["authority"]
    require(authority == {
        "cardID": c.CARD, "contextDigest": c.CONTEXT_DIGEST,
        "pathFenceDigest": c.FENCE_DIGEST,
        "provisionalUntil": "ACCEPTED_S10_6_RECONCILIATION",
    }, "fixture authority differs")
    require(fixture["universeSources"] == c.FIXTURE_UNIVERSE_SOURCES, "fixture universe sources differ")
    declared = fixture["declaredKindIDs"]
    require(isinstance(declared, list) and len(declared) == 100,
            "fixture declaredKindIDs is not exact 100")
    require(declared == sorted(declared) and len(declared) == len(set(declared)),
            "fixture declaredKindIDs is not sorted and unique")
    if universe is not None:
        require(declared == universe["kindIDs"],
                "fixture declaredKindIDs differs from independently derived universe")
    temporal_rows = fixture["temporalProvenance"]
    require(isinstance(temporal_rows, list) and len(temporal_rows) == 100,
            "fixture temporalProvenance is not exact 100")
    row_ids = [row.get("kindID") for row in temporal_rows]
    require(row_ids == sorted(row_ids) and len(row_ids) == len(set(row_ids)) == 100,
            "fixture temporalProvenance is not sorted and unique")
    require(all(set(row) == {
        "kindID", "representationSourceCard", "representationSourceOrdinal"
    } for row in temporal_rows), "fixture temporal provenance row shape differs")
    fixture_provenance = {
        row["kindID"]: (row["representationSourceCard"], row["representationSourceOrdinal"])
        for row in temporal_rows
    }
    counts: dict[tuple[str, int], int] = {}
    for origin in fixture_provenance.values():
        counts[origin] = counts.get(origin, 0) + 1
    require(counts == PROVENANCE_PARTITION,
            "fixture provenance partition/chronology differs")
    require(len(set(fixture_provenance.values())) == len(PROVENANCE_PARTITION),
            "fixture provenance uses uniform placeholder values")
    for kind_id, origin in KNOWN_LATER_ORIGINS.items():
        require(fixture_provenance.get(kind_id) == origin,
                f"fixture provenance differs for {kind_id}")
    if provenance is not None:
        require(fixture_provenance == provenance,
                "fixture provenance differs from exhaustive compiler provenance")
    durable = fixture["durableFirstWriteKindIDs"]
    require(isinstance(durable, list) and durable == sorted(durable)
            and len(durable) == len(set(durable)) == 65,
            "fixture durableFirstWriteKindIDs is not exact sorted unique 65")
    require(set(durable).issubset(declared) and len(set(declared) - set(durable)) == 35,
            "fixture durable/no-write split is not exact 65/35")
    require(durable == independent_durable_kind_ids(declared),
            "fixture durable first-write set differs from independent storage rules")
    require(fixture["classifications"] == c.FIXTURE_CLASSIFICATIONS, "fixture classifications differ")
    require(fixture["handlingActions"] == c.FIXTURE_HANDLING_ACTIONS, "fixture handling actions differ")
    require(fixture["lifecycleDimensions"] == c.FIXTURE_LIFECYCLE_DIMENSIONS
            and len(fixture["lifecycleDimensions"]) == 28, "fixture action closure differs")
    require(fixture["representativePolicies"] == c.FIXTURE_REPRESENTATIVE_POLICIES,
            "fixture representative policies differ")
    require(fixture["hostileCases"] == c.HOSTILE_CASES, "fixture hostile cases differ")
    require(fixture["interruptionBoundaries"] == c.INTERRUPTION_BOUNDARIES,
            "fixture interruption boundaries differ")
    require(fixture["compatibilityCases"] == c.COMPATIBILITY_CASES,
            "fixture compatibility cases differ")
    require(fixture["eraseExpectations"] == {
        "erasableSurvivorCount": 0, "orphanCount": 0,
        "immutableTruthPreserved": True, "usesOneGlobalDestructiveRule": False,
    }, "fixture Erase expectations differ")
    require(fixture["brandImpact"] == {
        "changedScreens": [], "changedStates": [],
        "affectedConsumers": ["V23-P02-C10", "V23-P03-C01"], "manifestCount": 1,
    }, "fixture brand impact differs")
    require(fixture["expectedAudit"] == {
        "missingCount": 0, "duplicateCount": 0, "conflictingCount": 0, "unknownCount": 0,
    }, "fixture expected audit differs")


def verify_tests() -> None:
    source = read(c.NEW_SOURCE_PATHS[2])
    methods = sorted(set(re.findall(r"\bfunc\s+(testV9_13[A-Za-z0-9_]*)\s*\(", source)))
    require(methods == sorted(c.TEST_METHODS) and len(methods) == 5,
            f"exact five V9_13 tests differ: {methods}")
    for family, method in zip(("G01", "A01", "H01", "I01", "R01"), c.TEST_METHODS):
        require(family in method and method in source, f"missing {family} evidence method")
    require("XCTAssertThrowsError" in source and "auditErase" in source
            and "PersistentLifecyclePolicySuccessorReceiptV1" in source,
            "V9_13 hostile/recovery evidence is not substantive")

    a01 = swift_block(source, "func testV9_13A01")
    require(r"catalog.descriptors.map(\.kindClassification.rawValue)" in a01
            and "for descriptor in catalog.descriptors" in a01
            and "switch descriptor.kindClassification" in a01
            and "Set(corpus.classifications)" in a01,
            "A01 does not classify every runtime descriptor")
    for token in (".canonical", ".immutable", ".derived", ".content",
                  ".declaration", ".wire", ".nonpersistent"):
        require(token in a01, f"A01 omits lifecycle classification {token}")
    require(all(name in a01 for name in REPORT_KIND_NAMES)
            and "try policy.localization, .supported" in a01
            and "try policy.accessibility, .supported" in a01,
            "A01 does not assert report localization/accessibility dispositions")

    h01 = swift_block(source, "func testV9_13H01")
    hostile_constructions = {
        "BACKUP_WITHOUT_RESTORE": ("backupWithoutRestore", ".semanticBackup", ".replaceRestore"),
        "DENIED_KIND_ENTERS_EXPORT": ("deniedExportLeak", ".export", ".denied"),
        "DENIED_KIND_ENTERS_REPORT": ("deniedExportLeak", ".report", ".supported"),
        "DUPLICATE_KIND": ("catalog.descriptors + [firstDescriptor]",),
        "DUPLICATE_OWNER": ("currentImplementationOwner: firstDescriptor.declarationOwner",),
        "ERASE_DESTROYS_IMMUTABLE_TRUTH": ("destructiveImmutableErase", ".immutable"),
        "ERASE_LEAVES_ERASABLE_ORPHAN": ("completeEraseObservations.dropFirst()",),
        "MISSING_KIND": ("Array(catalog.descriptors.dropFirst())",),
        "OWNER_IMPLEMENTATION_CONFLICT": ("declarationOwner: firstDescriptor.declarationOwner",),
        "TEMPORALLY_IMPOSSIBLE_WRITER": ("driftedTemporal", 'forwardFixVersion: "V23_P02_C10"'),
        "MISSING_TEMPORAL_PROVENANCE": (
            'sourceEvidence.filter { $0.sourceID != temporalSource.sourceID }',
        ),
        "DUPLICATE_TEMPORAL_PROVENANCE": ("sourceEvidence + [temporalSource]",),
        "WRONG_LATER_CARD_PROVENANCE": ("wrongLaterCard", 'representationSourceCard: "V23_P02_C08"'),
        "IMPOSSIBLE_TEMPORAL_CHRONOLOGY": (
            "lifecycleEnrollmentOrdinal: temporal.firstWriteOrdinal",
        ),
        "UNKNOWN_ACTION": ("UNKNOWN_FUTURE_ACTION",),
        "UNKNOWN_CLASSIFICATION": ("UNKNOWN_FUTURE_CLASS",),
        "UNKNOWN_POLICY_VERSION": ("schemaVersion: 2",),
    }
    require(set(hostile_constructions) == set(c.HOSTILE_CASES),
            "verifier hostile construction map differs from contract")
    for hostile, tokens in hostile_constructions.items():
        require(all(token in h01 for token in tokens),
                f"H01 lacks substantive construction for {hostile}")

    i01 = swift_block(source, "func testV9_13I01")
    boundary_cases = enum_raw_values(
        read(c.NEW_SOURCE_PATHS[0]), "PersistentLifecycleInterruptionPointV1"
    )
    require(boundary_cases == c.INTERRUPTION_BOUNDARIES and len(boundary_cases) == 4,
            "production interruption boundary enum is not exact four")
    require("for (descriptorIndex, descriptor) in catalog.descriptors.enumerated()" in i01
            and "for (boundaryIndex, boundary) in boundaries.enumerated()" in i01
            and "Set(PersistentKindStorageDispositionV1.allCases.map" in i01
            and "Set(PersistentKindClassificationV1.allCases.map" in i01
            and "PersistentLifecycleRecoveryReceiptV1(" in i01
            and i01.count("PersistentLifecycleReceiptPublicationV1.publishOrAdopt") >= 2,
            "I01 does not execute four boundaries across production descriptors/classes")

    r01 = swift_block(source, "func testV9_13R01")
    erase_helper = swift_block(source, "nonisolated static func independentEraseDisposition")
    require("Self.independentEraseDisposition" in r01,
            "R01 does not use its independent Erase oracle")
    require("expectedEraseDisposition" not in erase_helper
            and "auditErase" not in erase_helper
            and "switch descriptor.kindClassification" in erase_helper
            and ".immutableContentManager" in erase_helper,
            "R01 Erase oracle is self-confirming or omits content authority")


def verify_runtime_semantics(universe: dict[str, Any]) -> None:
    registry = read(c.NEW_SOURCE_PATHS[0])
    compiler = read(c.NEW_SOURCE_PATHS[1])
    classes = enum_raw_values(registry, "PersistentKindClassificationV1")
    require(set(classes) == set(c.CLASSIFICATIONS) and len(classes) == len(set(classes)) == 7,
            "runtime lifecycle classification enum is not exact seven")
    descriptor = swift_block(registry, "struct PersistentKindDescriptorV1")
    for field in ("kindClassification", "replicationClassification", "temporalEvidence"):
        require(re.search(rf"\blet\s+{field}\s*:", descriptor) is not None,
                f"runtime descriptor omits {field}")
    require("let kindClassification = kindClassification(registration)" in compiler
            and "kindClassification: kindClassification" in compiler,
            "catalog does not classify every generated descriptor")
    classifier = swift_block(compiler, "static func kindClassification")
    require(all(f".{name.lower()}" in classifier for name in c.CLASSIFICATIONS),
            "runtime descriptor classifier cannot emit all seven lifecycle classes")

    temporal = swift_block(registry, "struct PersistentKindTemporalEvidenceV1")
    for field in ("firstWriteVersion", "lifecycleEnrollmentVersion", "forwardFixVersion",
                  "firstWriteOrdinal", "lifecycleEnrollmentOrdinal", "forwardFixOrdinal"):
        require(re.search(rf"\blet\s+{field}\s*:", temporal) is not None,
                f"temporal evidence omits {field}")
    compile_coverage = swift_block(registry, "static func compileCoverage")
    require("var conflicting = Set<String>()" in compile_coverage
            and "var temporalConflicts = Set<String>()" in compile_coverage
            and "ownershipGapKindIDs: conflicting.sorted()" in compile_coverage
            and "temporalConflictKindIDs: temporalConflicts.sorted()" in compile_coverage,
            "temporal coverage gap is not independently derived from revision conflict")
    require("descriptor.temporalEvidence" in compile_coverage
            and "forwardFixVersion != \"V23_P02_C09\"" in compile_coverage,
            "compileCoverage omits temporal enrollment/forward-fix validation")

    erase_switch = swift_block(registry, "static func expectedEraseDisposition")
    for token in ("case .canonical: return .removed",
                  "case .immutable, .declaration: return .preservedImmutable",
                  "case .derived: return .rebuiltEmpty",
                  "case .wire: return .notApplicable",
                  "case .content:", "return .clearedByDeclaredOwner",
                  "case .nonpersistent: return .notApplicable"):
        require(token in erase_switch, f"runtime Erase classification mapping omits {token}")
    erase_profiles = {row["classification"]: row for row in c.ERASE_PROFILES}
    require(set(erase_profiles) == set(c.CLASSIFICATIONS)
            and len(c.ERASE_PROFILES) == len(erase_profiles) == 7,
            "generated Erase profiles do not cover exact seven classes")
    for name in c.CLASSIFICATIONS:
        require(erase_profiles[name] == {
            "classification": name,
            "actionDisposition": ERASE_ACTION_BY_CLASS[name],
            "observedDisposition": ERASE_OBSERVED_BY_CLASS[name],
        }, f"generated Erase profile differs for {name}")

    report_names_literal = re.search(
        r"let isUserVisibleHistoricOutput\s*=\s*\[(.*?)\]\.contains",
        compiler, re.S,
    )
    require(report_names_literal is not None
            and set(re.findall(r'\"([^\"]+)\"', report_names_literal.group(1))) == REPORT_KIND_NAMES,
            "runtime report artifact presentation-kind set differs")
    require(".localization: isUserVisibleHistoricOutput ? .supported : .notApplicable" in compiler
            and ".accessibility: isUserVisibleHistoricOutput ? .supported : .notApplicable" in compiler
            and "? .localizedFrozenHistoricProjection : .frozenDataNoPresentation" in compiler
            and "? .accessibleFrozenHistoricProjection : .frozenDataNoPresentation" in compiler,
            "report artifact localization/accessibility dispositions are not emitted")
    require(len(universe["kindIDs"]) == 100, "runtime-derived universe is not exact 100")


def verify_compatibility_sources() -> None:
    schemas = read(c.EXISTING_PATHS[3])
    compatibility = read(c.EXISTING_PATHS[0])
    combined = schemas + "\n" + compatibility
    require("Schema.Version(5, 0, 0)" in schemas and "PersistentSchemaV5" in schemas,
            "current store is not V5")
    require("archive1-backup4-persistent5-records4" in compatibility,
            "backup4/persistent5/records4 compatibility tuple missing")
    require('"snapshot2"' in compatibility, "snapshot2 compatibility missing")
    require("PersistentSchemaV6" not in combined and "SwiftDataV6" not in combined
            and "SwiftDataV6Entity" not in combined, "Card29 invents V6")
    require("PersistentLifecycleContractReleaseV1" in schemas
            and "PersistentLifecycleContractReleaseRegistryV1" in schemas,
            "versioned lifecycle-policy contract release missing")


def verify_contracts(
    universe: dict[str, Any],
    provenance: dict[str, tuple[str, int]],
) -> dict[str, dict[str, Any]]:
    documents = {
        "persistent": load(c.PERSISTENT_KIND_DOC),
        "handling": load(c.DATA_HANDLING_DOC),
        "coverage": load(c.COVERAGE_DOC),
        "compatibility": load(c.COMPATIBILITY_DOC),
        "hostile": load(c.HOSTILE_DOC),
        "audit": load(c.AUDIT_DOC),
    }
    schema_pairs = [
        (c.PERSISTENT_KIND_SCHEMA, documents["persistent"]),
        (c.PERSISTENT_LIFECYCLE_SCHEMA, c.lifecycle_policy_contract(ROOT)),
        (c.DATA_HANDLING_SCHEMA, documents["handling"]),
        (c.COVERAGE_SCHEMA, documents["coverage"]),
        (c.AUDIT_SCHEMA, documents["audit"]),
    ]
    for schema_path, instance in schema_pairs:
        schema = load(schema_path)
        verify_strict_schema(schema, schema_path)
        walk_flags(schema, schema_path)
        validate_instance(instance, schema, schema_path)
        verify_with_jsonschema(instance, schema, schema_path)
    for label, document in documents.items():
        verify_seal(document, label)
        walk_flags(document, label)
        require(document.get("cardID") == c.CARD and document.get("authority") == c.authority(),
                f"{label}: authority differs")
    lifecycle = c.lifecycle_policy_contract(ROOT)
    verify_seal(lifecycle, "lifecycle")
    walk_flags(lifecycle, "lifecycle")

    persistent = documents["persistent"]
    require(persistent["universe"]["kindIDs"] == universe["kindIDs"], "persistent universe differs")
    require(persistent["universe"]["sourceArrays"] == universe["fields"], "source arrays differ")
    require(persistent["actionMatrix"]["actions"] == c.LIFECYCLE_ACTIONS
            and persistent["actionMatrix"]["closedActionCount"] == 28,
            "persistent action matrix differs")
    require(persistent["ownership"]["temporallyImpossibleWriterRejected"] is True
            and persistent["ownership"]["conflictingOwnerRejected"] is True,
            "owner/writer hostile policy differs")
    require(persistent["prohibitions"]["swiftDataV6EntityAdded"] is False
            and persistent["prohibitions"]["oneGlobalDestructiveRule"] is False,
            "persistent prohibition differs")
    verify_tooling_provenance(
        persistent["temporalProvenance"], universe, provenance, "persistent contract"
    )

    require(lifecycle["policy"]["actionFields"] == c.LIFECYCLE_ACTIONS
            and lifecycle["policy"]["actionMatrix"] == c.LIFECYCLE_ACTIONS
            and len(lifecycle["policy"]["actionFields"]) == 28,
            "lifecycle action closure differs")
    require(lifecycle["universeBinding"]["kindIDs"] == universe["kindIDs"],
            "lifecycle universe differs")
    verify_tooling_provenance(
        lifecycle["temporalProvenance"], universe, provenance, "lifecycle contract"
    )

    handling = documents["handling"]
    require(handling["universeBinding"]["kindIDs"] == universe["kindIDs"],
            "handling universe differs")
    require(handling["erase"] == {
        "erasableSurvivorCount": 0, "orphanCount": 0,
        "immutableTruthPreserved": True, "usesOneGlobalDestructiveRule": False,
        "unknownKindFailsClosed": True,
    }, "handling Erase closure differs")
    require(handling["policy"]["unknownPolicyFailsClosed"] is True
            and handling["policy"]["ownerRequiredCannotBePersisted"] is True,
            "handling unknown/owner-required policy differs")

    coverage = documents["coverage"]
    manifest = coverage["manifest"]
    for key in ("universeKindIDs", "descriptorKindIDs", "lifecyclePolicyKindIDs",
                "dataHandlingPolicyKindIDs"):
        require(manifest[key] == universe["kindIDs"], f"coverage {key} differs")
    require(coverage["gapSets"] == GAP_SETS, "coverage gap-set declaration differs")
    require(all(manifest[key] == [] for key in GAP_SETS[:4]) and manifest["isComplete"] is True,
            "coverage manifest is incomplete")
    require(manifest["kindCountDerived"] == len(universe["kindIDs"])
            and manifest["noHandwrittenCountAuthority"] is True,
            "coverage uses handwritten count authority")
    registry_source = read(c.NEW_SOURCE_PATHS[0])
    compiler_source = read(c.NEW_SOURCE_PATHS[1])
    for gap in GAP_SETS:
        require(gap in registry_source, f"runtime coverage manifest omits gap: {gap}")
    require("PersistentKindLifecycleRegistryV1.compileCoverage" in compiler_source
            and "coverageManifest" in compiler_source,
            "runtime compiler does not delegate complete gap derivation to the registry")
    is_complete = swift_block(registry_source, "struct LifecycleCoverageManifestV1")
    require(all(f"{gap}.isEmpty" in is_complete for gap in GAP_SETS),
            "runtime isComplete does not close every gap set")

    compatibility = documents["compatibility"]
    require(compatibility["schema"]["currentStoreVersion"] == "V5"
            and compatibility["schema"]["newSwiftDataV6Entity"] is False,
            "compatibility store schema differs")
    require(compatibility["backupRestore"]["currentBackupTuple"]
            == "archive1-backup4-persistent5-records4", "compatibility backup tuple differs")
    require(compatibility["policyHistory"] == {
        "preActivationInterruption": "DISCARD_STAGING",
        "postActivationInterruption": "APPEND_VERSIONED_SUCCESSOR_AND_FORWARD_FIX",
        "rewritesReleasedRecords": False, "rewritesReceipts": False,
        "rewritesTombstones": False,
    }, "compatibility forward-fix semantics differ")

    hostile = documents["hostile"]
    require(hostile["hostileCases"] == c.HOSTILE_CASES
            and hostile["interruptionBoundaries"] == c.INTERRUPTION_BOUNDARIES
            and hostile["compatibilityCases"] == c.COMPATIBILITY_CASES,
            "hostile matrix differs")
    require([row["testMethod"] for row in hostile["evidence"]] == c.TEST_METHODS
            and [row["evidenceID"] for row in hostile["evidence"]] == c.EVIDENCE_IDS,
            "hostile evidence mapping differs")

    audit = documents["audit"]
    require(audit["coverageManifestDigest"] == coverage["artifactDigest"],
            "audit does not bind coverage manifest")
    require(audit["audit"] == {
        "missingCount": 0, "duplicateCount": 0, "conflictingCount": 0,
        "unknownCount": 0, "orphanedOwnerCount": 0, "stalePolicyRevisionCount": 0,
        "complete": True, "exactHeadDerived": True, "handwrittenCountAuthority": False,
    }, "audit closure differs")
    brand = audit["brandImpactManifest"]
    require(brand.get("schema") == "BrandImpactManifestV1", "brand manifest type differs")
    verify_seal(brand, "brand impact")
    count = sum(1 for node in recursive_dicts(audit) if node.get("schema") == "BrandImpactManifestV1")
    require(count == audit["brandImpact"]["manifestCount"] == 1, "brand impact is not exactly one")
    require(audit["brandImpact"]["digest"] == brand["artifactDigest"], "brand impact digest differs")
    require(brand["changedScreens"] == [] and brand["changedStates"] == []
            and brand["affectedConsumers"] == ["V23-P02-C10", "V23-P03-C01"],
            "brand impact closure differs")
    return {**documents, "lifecycle": lifecycle}


def recursive_dicts(value: Any) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    if isinstance(value, dict):
        result.append(value)
        for child in value.values():
            result.extend(recursive_dicts(child))
    elif isinstance(value, list):
        for child in value:
            result.extend(recursive_dicts(child))
    return result


def verify_manifest_value(
    manifest: dict[str, Any],
    check_files: bool = True,
    universe: dict[str, Any] | None = None,
    provenance: dict[str, tuple[str, int]] | None = None,
) -> None:
    verify_seal(manifest, "tooling manifest")
    require(manifest["pathFence"] == c.PATH_FENCE and manifest["pathFenceCount"] == 24,
            "manifest path fence differs")
    require(manifest["existingPaths"] == c.EXISTING_PATHS and len(c.EXISTING_PATHS) == 5,
            "manifest existing partition differs")
    require(manifest["newPaths"] == c.NEW_PATHS and len(c.NEW_PATHS) == 19,
            "manifest new partition differs")
    require(manifest["sourcePaths"] == c.SOURCE_PATHS and manifest["sourcePathCount"] == 9,
            "manifest source partition differs")
    require(manifest["toolingPaths"] == c.TOOL_PATHS and manifest["toolingPathCount"] == 15,
            "manifest tooling partition differs")
    require(manifest["generatedPaths"] == c.GENERATED_PATHS and len(c.GENERATED_PATHS) == 12,
            "manifest generated paths differ")
    require(manifest["pendingFencePaths"] == [] and manifest["pendingArtifactCount"] == 0,
            "manifest retains pending artifacts")
    rows = manifest["artifacts"]
    require(len(rows) == manifest["artifactCount"] == len(c.MANIFEST_INPUT_PATHS) == 23,
            "manifest artifact count differs")
    require([row["path"] for row in rows] == c.MANIFEST_INPUT_PATHS,
            "manifest artifact path closure differs")
    require(len({row["path"] for row in rows}) == len(rows), "manifest has duplicate artifact paths")
    if check_files:
        for row in rows:
            path = ROOT / row["path"]
            require(path.is_file(), f"manifest input missing: {row['path']}")
            data = path.read_bytes()
            require(row["bytes"] == len(data) and row["sha256"] == c.sha(data),
                    f"manifest input seal differs: {row['path']}")
    require(manifest["artifactSetDigest"] == c.sha(c.pretty(rows)), "manifest artifact-set digest differs")
    fence = manifest["fenceProof"]
    require(fence["baseHead"] == c.APP_BASE_HEAD and fence["baseTree"] == c.APP_BASE_TREE
            and fence["pathFenceDigest"] == c.FENCE_DIGEST,
            "manifest base/fence authority differs")
    require(fence["priorFenceOverlapCount"] == fence["authorizedPriorFenceOverlapCount"] == 17
            and fence["unauthorizedPriorFenceOverlapCount"] == 0,
            "manifest prior-overlap proof differs")
    require(fence["allowedDeletePaths"] == [] and fence["allowedRenamePaths"] == []
            and fence["activeS10ReservationDigest"] == c.S10_RESERVATION_DIGEST
            and fence["activeS10Overlap"] is False,
            "manifest S10/delete/rename fence differs")
    require(manifest["noNewSwiftDataV6Entity"] is True
            and manifest["persistentContractSchema"] == "PERSISTENT_LIFECYCLE_POLICY_V1",
            "manifest lifecycle schema boundary differs")
    if universe is not None and provenance is not None:
        verify_tooling_provenance(
            manifest["universeDerivation"]["temporalProvenance"],
            universe,
            provenance,
            "tooling manifest",
        )
    walk_flags(manifest, "tooling manifest")


def verify_generated() -> None:
    expected = c.all_outputs(ROOT)
    require(list(expected) == c.GENERATED_PATHS, "generated output path order differs")
    for relative, payload in expected.items():
        path = ROOT / relative
        require(path.is_file(), f"missing generated artifact: {relative}")
        require(path.read_bytes() == payload, f"stale generated artifact: {relative}")
        require(path.read_bytes() == c.pretty(load(relative)), f"noncanonical JSON: {relative}")


def expect_failure(operation: Callable[[], None], label: str) -> None:
    try:
        operation()
    except (VerificationError, KeyError, TypeError, ValueError):
        return
    raise VerificationError(f"hostile tamper accepted: {label}")


def verify_hostile_tampers(
    documents: dict[str, dict[str, Any]],
    universe: dict[str, Any],
    provenance: dict[str, tuple[str, int]],
) -> None:
    schema = copy.deepcopy(load(c.PERSISTENT_KIND_SCHEMA))
    schema["additionalProperties"] = True
    expect_failure(lambda: verify_strict_schema(schema, "tampered schema"), "open schema")

    changed = copy.deepcopy(documents["lifecycle"])
    changed["policy"]["actionFields"][0] = "UNKNOWN_ACTION"
    expect_failure(lambda: validate_instance(changed, load(c.PERSISTENT_LIFECYCLE_SCHEMA)),
                   "unknown lifecycle action")
    changed = copy.deepcopy(documents["coverage"])
    changed["manifest"]["universeKindIDs"].append("UNKNOWN:Kind")
    expect_failure(lambda: validate_instance(changed, load(c.COVERAGE_SCHEMA)), "unknown kind")
    changed = copy.deepcopy(documents["persistent"])
    changed["artifactDigest"] = "0" * 64
    expect_failure(lambda: verify_seal(changed, "tampered artifact"), "artifact self digest")

    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture.pop("hostileCases")
    expect_failure(lambda: verify_fixture_value(fixture), "fixture omission")
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["lifecycleDimensions"][0] = "UNKNOWN_ACTION"
    expect_failure(lambda: verify_fixture_value(fixture), "fixture unknown action")
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["declaredKindIDs"].pop()
    expect_failure(lambda: verify_fixture_value(fixture), "fixture declared kind removal")
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["declaredKindIDs"].append("UNKNOWN:AddedKind")
    expect_failure(lambda: verify_fixture_value(fixture), "fixture declared kind addition")
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["temporalProvenance"].pop()
    expect_failure(
        lambda: verify_fixture_value(fixture, universe, provenance),
        "fixture missing temporal provenance",
    )
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["temporalProvenance"].append(copy.deepcopy(fixture["temporalProvenance"][0]))
    expect_failure(
        lambda: verify_fixture_value(fixture, universe, provenance),
        "fixture duplicate temporal provenance",
    )
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    for row in fixture["temporalProvenance"]:
        row["representationSourceCard"] = "PRE_V23_BASELINE"
        row["representationSourceOrdinal"] = 0
    expect_failure(
        lambda: verify_fixture_value(fixture, universe, provenance),
        "fixture uniform temporal placeholder",
    )
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    observation = next(row for row in fixture["temporalProvenance"]
                       if row["kindID"] == "PERSISTENT_MODEL:ObservationAndTimeRow")
    observation["representationSourceCard"] = "V23_P02_C08"
    observation["representationSourceOrdinal"] = 28
    expect_failure(
        lambda: verify_fixture_value(fixture, universe, provenance),
        "fixture wrong later-card provenance",
    )
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["temporalProvenance"][0]["representationSourceOrdinal"] = 29
    expect_failure(
        lambda: verify_fixture_value(fixture, universe, provenance),
        "fixture impossible provenance chronology",
    )
    fixture = copy.deepcopy(load(c.NEW_SOURCE_PATHS[3]))
    fixture["durableFirstWriteKindIDs"].pop()
    expect_failure(
        lambda: verify_fixture_value(fixture, universe, provenance),
        "fixture durable first-write omission",
    )
    changed = copy.deepcopy(documents["persistent"]["temporalProvenance"])
    changed["rows"].pop()
    expect_failure(
        lambda: verify_tooling_provenance(changed, universe, provenance, "tampered tooling"),
        "tooling provenance omission",
    )
    changed = copy.deepcopy(documents["persistent"]["temporalProvenance"])
    changed["rows"].append(copy.deepcopy(changed["rows"][0]))
    expect_failure(
        lambda: verify_tooling_provenance(changed, universe, provenance, "tampered tooling"),
        "tooling provenance duplication",
    )
    changed = copy.deepcopy(documents["persistent"]["temporalProvenance"])
    row = next(item for item in changed["rows"]
               if item["kindID"] == "DIAGNOSTIC:DeviceOperationalSupportStoreV2")
    row["representationSourceCard"] = "V23_P02_C07"
    row["representationSourceOrdinal"] = 27
    expect_failure(
        lambda: verify_tooling_provenance(changed, universe, provenance, "tampered tooling"),
        "tooling wrong-card provenance",
    )
    changed = copy.deepcopy(documents["persistent"]["temporalProvenance"])
    changed["sourceDigestRows"][0]["sha256"] = "0" * 64
    expect_failure(
        lambda: verify_tooling_provenance(changed, universe, provenance, "tampered tooling"),
        "tooling provenance source digest",
    )
    changed = copy.deepcopy(documents["persistent"]["temporalProvenance"])
    changed["temporalRegistryCanonicalDigest"] = "f" * 64
    expect_failure(
        lambda: verify_tooling_provenance(changed, universe, provenance, "tampered tooling"),
        "tooling temporal registry digest",
    )

    manifest = copy.deepcopy(load(c.MANIFEST))
    manifest["artifacts"][0]["sha256"] = "f" * 64
    expect_failure(lambda: verify_manifest_value(manifest, check_files=False), "manifest row digest")
    manifest = copy.deepcopy(load(c.MANIFEST))
    manifest["artifacts"].pop()
    manifest_body = dict(manifest)
    manifest_body.pop("artifactDigest")
    manifest["artifactDigest"] = c.sha(c.pretty(manifest_body))
    expect_failure(lambda: verify_manifest_value(manifest, check_files=False), "manifest omission")
    manifest = copy.deepcopy(load(c.MANIFEST))
    manifest["artifactSetDigest"] = "a" * 64
    manifest_body = dict(manifest)
    manifest_body.pop("artifactDigest")
    manifest["artifactDigest"] = c.sha(c.pretty(manifest_body))
    expect_failure(lambda: verify_manifest_value(manifest, check_files=False), "artifact-set digest")

    binding = c.source_bindings()[0]
    source = read(binding["path"])
    token = binding["requiredTokens"][0]
    require(token in source, "source tamper precondition differs")
    tampered = source.replace(token, "")
    expect_failure(lambda: require(token in tampered, "bound source token omitted"), "source omission")


def verify_scripts_parse() -> None:
    for relative in (c.CONTRACT_SCRIPT, c.GENERATOR_SCRIPT, c.VERIFIER_SCRIPT):
        try:
            ast.parse(read(relative), filename=relative)
        except SyntaxError as error:
            raise VerificationError(f"{relative}: syntax error: {error}") from error


def verify_generator_check() -> None:
    result = subprocess.run(
        [sys.executable, "-B", str(ROOT / c.GENERATOR_SCRIPT), "--check", "--root", str(ROOT)],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
    )
    require(result.returncode == 0, f"generator --check failed: {result.stdout}{result.stderr}")
    require(result.stdout.strip() == f"Card29 verified {len(c.GENERATED_PATHS)} deterministic artifacts",
            "generator --check output differs")


def main() -> int:
    try:
        verify_scripts_parse()
        verify_path_fence()
        verify_provenance_history_anchors()
        verify_generator_check()
        verify_generated()
        universe = independent_universe()
        provenance = independent_compiler_provenance(universe)
        require(len(c.LIFECYCLE_ACTIONS) == 28, "contract action count is not 28")
        action_values = enum_raw_values(read(c.NEW_SOURCE_PATHS[0]), "PersistentLifecycleActionV1")
        require(action_values == c.LIFECYCLE_ACTIONS and len(action_values) == 28,
                "Swift lifecycle action enum differs")
        verify_runtime_semantics(universe)
        verify_source_bindings()
        verify_compatibility_sources()
        verify_fixture_value(load(c.NEW_SOURCE_PATHS[3]), universe, provenance)
        verify_tests()
        documents = verify_contracts(universe, provenance)
        manifest = load(c.MANIFEST)
        verify_manifest_value(manifest, universe=universe, provenance=provenance)
        generated_universe = manifest["universeDerivation"]
        require(generated_universe["kindIDs"] == universe["kindIDs"]
                and generated_universe["sourceArrays"] == universe["fields"]
                and generated_universe["categoryCounts"] == universe["categoryCounts"],
                "manifest universe derivation differs")
        require(generated_universe["duplicateKindIDs"] == []
                and generated_universe["fixtureUniverseMismatch"] == []
                and generated_universe["noHandwrittenCountAuthority"] is True,
                "manifest universe gaps differ")
        verify_hostile_tampers(documents, universe, provenance)
    except VerificationError as error:
        print(f"FAIL Card29 hostile static verification: {error}", file=sys.stderr)
        return 1
    manifest = load(c.MANIFEST)
    print(
        "V23-P02-C09 hostile static verification passed: "
        f"{manifest['pathFenceCount']} fence paths, {manifest['artifactCount']} sealed inputs, "
        "5 strict schemas, 28 lifecycle actions, 5 evidence tests"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
