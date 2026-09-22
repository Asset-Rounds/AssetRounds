#!/usr/bin/env python3
"""Compile an explicit ContractManifestV1 root to JSON Schema Draft 2020-12.

This validates manifest grammar, not the authenticity or completeness of a
production catalog. Schema annotations describe codec obligations that ordinary
JSON Schema validators cannot enforce (including NFC and exact UTF-8 byte limits).
No source instance, integer, or captured Date is converted or rounded.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
import unicodedata
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

sys.dont_write_bytecode = True

INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1
UINT64_MAX = (1 << 64) - 1
DOUBLE_MAX = sys.float_info.max
DIALECT = "https://json-schema.org/draft/2020-12/schema"
KINDS = {"BASE64_BYTES", "STRING", "PRESERVED_STRING", "STRING_MAP", "INTEGER", "UNSIGNED_INTEGER", "BOOLEAN",
         "UTC_INSTANT", "REFERENCE_DATE_SECONDS", "SHA256", "OBJECT", "ARRAY", "ENUM"}
POLICIES = {"REJECT", "PRESERVE"}
FIELD_REQUIRED = {"fieldID", "jsonName", "kind", "required", "nullable", "ordered", "uniqueItems"}
FIELD_OPTIONAL = {"arrayElementKind", "referencedTypeID", "minimumInteger", "maximumInteger",
                  "minimumUnsignedInteger", "maximumUnsignedInteger", "maximumUTF8Bytes", "maximumItems",
                  "maximumKeyUTF8Bytes"}
TIME_ENCODINGS = {1: "UTC_RFC3339_MILLISECONDS_Z",
                  2: "PER_FIELD_UTC_RFC3339_MILLISECONDS_Z_OR_FINITE_APPLE_REFERENCE_SECONDS"}
STRING_NORMALIZATIONS = {
    1: "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED",
    2: "PER_FIELD_NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED_OR_PRESERVED_SOURCE_UNICODE",
}


class ContractError(ValueError):
    """Invalid input; generation must leave an existing output untouched."""


def repository_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/v23/p03_c06_contracts.py").is_file():
            return parent
    raise ContractError("repository text-shape implementation is absent")


def text_shape(maximum_bytes: int | None = None) -> dict[str, Any]:
    # Deliberately reuse the published string shape without editing that compiler
    # or claiming its annotations establish complete codec conformance.
    module_path = str(repository_root() / "Scripts/v23")
    sys.path.insert(0, module_path)
    try:
        from p03_c06_contracts import text_shape as published_text_shape
        return published_text_shape(maximum_bytes)
    finally:
        sys.path.remove(module_path)


def preserved_text_shape(maximum_bytes: int | None = None) -> dict[str, Any]:
    # Do not project the unrelated STRING normalization/control exclusions onto
    # genuine source text. Nonempty/trimmed requirements belong to each source
    # contract; this scalar supplies neither a minimum length nor a transform.
    result: dict[str, Any] = {"type": "string", "x_assetrounds_stringNormalization": "PRESERVE_SOURCE_UNICODE"}
    if maximum_bytes is not None:
        result.update({"maxLength": maximum_bytes, "x_assetrounds_maximumUTF8Bytes": maximum_bytes,
                       "x_assetrounds_maxLengthSemantics": "SOUND_CODE_POINT_CEILING_NOT_UTF8_BYTE_PARITY"})
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def record(value: Any, required: set[str], optional: set[str], label: str) -> dict[str, Any]:
    require(isinstance(value, dict), f"{label}: expected object")
    require(required <= value.keys() <= required | optional, f"{label}: missing or unknown metadata")
    require(all(item is not None for item in value.values()), f"{label}: explicit null metadata")
    return value


def integer(value: Any, minimum: int, maximum: int, label: str) -> None:
    require(type(value) is int and minimum <= value <= maximum, f"{label}: invalid integer")


def boolean(value: Any, label: str) -> None:
    require(type(value) is bool, f"{label}: expected boolean")


def choice(value: Any, choices: set[str], label: str) -> None:
    require(type(value) is str and value in choices, f"{label}: unknown value")


def identifier(value: Any, label: str) -> None:
    require(type(value) is str and re.fullmatch(r"[a-z0-9._-]{1,128}", value) is not None,
            f"{label}: invalid identity")


def valid_text(value: Any, label: str) -> None:
    require(type(value) is str and bool(value), f"{label}: expected nonempty string")
    try:
        byte_count = len(value.encode("utf-8"))
    except UnicodeEncodeError as error:
        raise ContractError(f"{label}: invalid Unicode scalar") from error
    require(byte_count <= 128 and unicodedata.normalize("NFC", value) == value,
            f"{label}: invalid enum text")
    # Match SnapshotProjectionValidationV1.validText, including its exact scalar
    # checks. The existing schema text annotations retain their stated limits.
    for char in value:
        scalar = ord(char)
        require(not (scalar < 0x20 or 0x7F <= scalar <= 0x9F or
                     0x202A <= scalar <= 0x202E or 0x2066 <= scalar <= 0x2069 or
                     scalar & 0xFFFF in {0xFFFE, 0xFFFF}), f"{label}: forbidden scalar")


def sequence(value: Any, label: str, *, nonempty: bool = False) -> list[Any]:
    require(isinstance(value, list) and (not nonempty or bool(value)), f"{label}: invalid array")
    return value


def sorted_unique(values: list[Any], label: str) -> None:
    require(values == sorted(values) and len(values) == len(set(values)), f"{label}: unordered or duplicate")


def validate_field(value: Any, schema_version: int) -> None:
    field = record(value, FIELD_REQUIRED, FIELD_OPTIONAL, "field")
    identifier(field["fieldID"], "fieldID")
    require(type(field["jsonName"]) is str and
            re.fullmatch(r"[A-Za-z0-9_]{1,128}", field["jsonName"]) is not None,
            "jsonName: invalid name")
    choice(field["kind"], KINDS, "kind")
    for key in ("required", "nullable", "ordered", "uniqueItems"):
        boolean(field[key], key)
    require(not field["nullable"] or field["required"], "nullable requires required")
    kind = field["kind"]
    for key in ("minimumInteger", "maximumInteger"):
        if key in field:
            integer(field[key], INT64_MIN, INT64_MAX, key)
            require(kind == "INTEGER", f"{key}: wrong kind")
    for key in ("minimumUnsignedInteger", "maximumUnsignedInteger"):
        if key in field:
            integer(field[key], 0, UINT64_MAX, key)
            require(kind == "UNSIGNED_INTEGER", f"{key}: wrong kind")
    for lower, upper in (("minimumInteger", "maximumInteger"),
                         ("minimumUnsignedInteger", "maximumUnsignedInteger")):
        if lower in field and upper in field:
            require(field[lower] <= field[upper], f"{lower}: bounds reversed")
    if "maximumUTF8Bytes" in field:
        integer(field["maximumUTF8Bytes"], 1, INT64_MAX, "maximumUTF8Bytes")
        require(kind in {"STRING", "BASE64_BYTES", "PRESERVED_STRING", "STRING_MAP"}, "maximumUTF8Bytes: wrong kind")
    if "maximumKeyUTF8Bytes" in field:
        integer(field["maximumKeyUTF8Bytes"], 1, INT64_MAX, "maximumKeyUTF8Bytes")
        require(kind == "STRING_MAP", "maximumKeyUTF8Bytes: wrong kind")
    if "referencedTypeID" in field:
        identifier(field["referencedTypeID"], "referencedTypeID")
    if kind == "ARRAY":
        require("arrayElementKind" in field and "maximumItems" in field,
                "array: missing element kind or maximumItems")
        choice(field["arrayElementKind"], KINDS - {"ARRAY", "STRING_MAP"}, "arrayElementKind")
        integer(field["maximumItems"], 1, INT64_MAX, "maximumItems")
        effective_kind = field["arrayElementKind"]
    else:
        require("arrayElementKind" not in field and not field["ordered"] and not field["uniqueItems"],
                "nonarray: array metadata")
        if kind == "STRING_MAP" and "maximumItems" in field:
            integer(field["maximumItems"], 1, INT64_MAX, "maximumItems")
        else:
            require("maximumItems" not in field, "nonarray/nonmap: maximumItems metadata")
        effective_kind = kind
    require((effective_kind in {"OBJECT", "ENUM"}) == ("referencedTypeID" in field),
            "field: missing or forbidden reference")
    if schema_version == 1:
        require(effective_kind not in {"UNSIGNED_INTEGER", "REFERENCE_DATE_SECONDS", "PRESERVED_STRING", "STRING_MAP"} and
                "minimumUnsignedInteger" not in field and "maximumUnsignedInteger" not in field and
                "maximumKeyUTF8Bytes" not in field,
                "schema 1: extended scalar metadata")


def validate_registry(value: Any) -> None:
    registry = record(value, {"schemaVersion", "registryID", "registryVersion", "sections"}, set(), "registry")
    integer(registry["schemaVersion"], 1, 1, "registry.schemaVersion")
    identifier(registry["registryID"], "registryID")
    integer(registry["registryVersion"], 1, INT64_MAX, "registryVersion")
    sections = sequence(registry["sections"], "sections", nonempty=True)
    seen: set[str] = set()
    required: set[str] = set()
    for index, value in enumerate(sections):
        section = record(value, {"sectionID", "version", "required", "supportedFormats", "privacyClass",
                                 "requiresHeading", "requiresTextAlternative", "order"}, set(), "section")
        identifier(section["sectionID"], "sectionID")
        require(section["sectionID"] not in seen, "duplicate sectionID")
        seen.add(section["sectionID"])
        integer(section["version"], 1, INT64_MAX, "section.version")
        integer(section["order"], index, index, "section.order")
        for key in ("required", "requiresHeading", "requiresTextAlternative"):
            boolean(section[key], f"section.{key}")
        if section["required"]:
            required.add(section["sectionID"])
        formats = sequence(section["supportedFormats"], "supportedFormats", nonempty=True)
        for item in formats:
            choice(item, {"PDF", "OPEN_JSON", "STRUCTURED_TEXT", "FORMULA_SAFE_CSV", "MEDIA", "MANIFEST"},
                   "supportedFormats")
        sorted_unique(formats, "supportedFormats")
        choice(section["privacyClass"], {"MANDATORY_PUBLIC_TRUTH", "AUDIENCE_SAFE", "INTERNAL_ONLY"}, "privacyClass")
    require({"identity", "limitations", "provenance", "supersession", "manifest"} <= required,
            "registry: missing required report section")


def validate_manifest(value: Any) -> dict[str, Any]:
    manifest = record(value, {"schemaVersion", "manifestID", "manifestVersion", "persistentContractSchema", "codec",
                              "compatibility", "objects", "enums", "reportSectionRegistry"}, set(), "manifest")
    integer(manifest["schemaVersion"], 1, 2, "schemaVersion")
    version = manifest["schemaVersion"]
    identifier(manifest["manifestID"], "manifestID")
    integer(manifest["manifestVersion"], 1, INT64_MAX, "manifestVersion")
    require(manifest["persistentContractSchema"] == "KERNEL_SNAPSHOT_V1", "unsupported persistentContractSchema")
    expected_codec = {
        "codecVersion": version, "canonicalJSON": "UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE",
        "integerEncoding": "BASE10_INTEGER_NO_EXPONENT", "timeEncoding": TIME_ENCODINGS[version],
        "nullEncoding": "EXPLICIT_NULL_ONLY_WHEN_REQUIRED_NULLABLE", "binaryEncoding": "RFC4648_BASE64_PADDED",
        "stringNormalization": STRING_NORMALIZATIONS[version], "formatAssertion": False,
    }
    codec = record(manifest["codec"], set(expected_codec), set(), "codec")
    integer(codec["codecVersion"], version, version, "codecVersion")
    boolean(codec["formatAssertion"], "formatAssertion")
    require(codec == expected_codec, "unsupported codec rules")
    compatibility = record(manifest["compatibility"], {"minimumReaderVersion", "maximumReaderVersion",
                            "unknownObjectFields", "publishedVersionsImmutable"}, set(), "compatibility")
    integer(compatibility["minimumReaderVersion"], version, INT64_MAX, "minimumReaderVersion")
    integer(compatibility["maximumReaderVersion"], compatibility["minimumReaderVersion"], INT64_MAX, "maximumReaderVersion")
    choice(compatibility["unknownObjectFields"], POLICIES, "unknownObjectFields")
    require(compatibility["publishedVersionsImmutable"] is True, "publishedVersionsImmutable must be true")
    objects = sequence(manifest["objects"], "objects", nonempty=True)
    enums = sequence(manifest["enums"], "enums")
    for value in objects:
        obj = record(value, {"typeID", "version", "unknownFieldPolicy", "fields"}, set(), "object")
        identifier(obj["typeID"], "object.typeID")
        integer(obj["version"], 1, INT64_MAX, "object.version")
        choice(obj["unknownFieldPolicy"], POLICIES, "unknownFieldPolicy")
        fields = sequence(obj["fields"], "fields")
        require(bool(fields) or (version == 2 and obj["unknownFieldPolicy"] == "REJECT"),
                "empty object requires schema 2 and REJECT policy")
        for field in fields:
            validate_field(field, version)
        sorted_unique([field["fieldID"] for field in fields], "fieldID")
        names = [field["jsonName"] for field in fields]
        require(len(names) == len(set(names)), "duplicate jsonName")
    for value in enums:
        enum = record(value, {"typeID", "version", "policy", "knownValues"}, {"knownIntegerValues"}, "enum")
        identifier(enum["typeID"], "enum.typeID")
        integer(enum["version"], 1, INT64_MAX, "enum.version")
        choice(enum["policy"], {"CLOSED", "PRESERVE_UNKNOWN"}, "enum.policy")
        values = sequence(enum["knownValues"], "knownValues")
        if "knownIntegerValues" in enum:
            require(version == 2, "integer enum requires schema 2")
            require(not values and enum["policy"] == "CLOSED", "integer enum requires empty knownValues and CLOSED policy")
            integers = sequence(enum["knownIntegerValues"], "knownIntegerValues", nonempty=True)
            for item in integers:
                integer(item, INT64_MIN, INT64_MAX, "knownIntegerValues")
            sorted_unique(integers, "knownIntegerValues")
        else:
            require(bool(values), "string enum requires nonempty knownValues")
            for item in values:
                valid_text(item, "knownValues")
            sorted_unique(values, "knownValues")
    object_ids = [obj["typeID"] for obj in objects]
    enum_ids = [enum["typeID"] for enum in enums]
    sorted_unique(object_ids, "object typeID")
    sorted_unique(enum_ids, "enum typeID")
    require(set(object_ids).isdisjoint(enum_ids), "object/enum identity collision")
    for obj in objects:
        for field in obj["fields"]:
            kind = field.get("arrayElementKind", field["kind"])
            if kind in {"OBJECT", "ENUM"}:
                require(field["referencedTypeID"] in (object_ids if kind == "OBJECT" else enum_ids),
                        "unresolved or wrong-kind reference")
    validate_registry(manifest["reportSectionRegistry"])
    return manifest


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def compile_product_schema(manifest: dict[str, Any], root_type_id: str, schema_id: str) -> dict[str, Any]:
    manifest = validate_manifest(manifest)
    identifier(root_type_id, "root_type_id")
    require(type(schema_id) is str, "schema_id: expected URI")
    parsed = urlsplit(schema_id)
    require(bool(parsed.scheme) and bool(parsed.path or parsed.netloc) and not parsed.fragment and
            not any(char.isspace() or ord(char) < 0x20 for char in schema_id), "schema_id: expected absolute URI without fragment")
    objects = {obj["typeID"]: obj for obj in manifest["objects"]}
    require(root_type_id in objects, "root_type_id: absent object root")

    def scalar(kind: str, field: dict[str, Any]) -> dict[str, Any]:
        if kind == "STRING":
            return text_shape(field.get("maximumUTF8Bytes"))
        if kind == "PRESERVED_STRING":
            return preserved_text_shape(field.get("maximumUTF8Bytes"))
        if kind == "STRING_MAP":
            result: dict[str, Any] = {
                "type": "object", "propertyNames": preserved_text_shape(field.get("maximumKeyUTF8Bytes")),
                "additionalProperties": preserved_text_shape(field.get("maximumUTF8Bytes")),
            }
            if "maximumItems" in field:
                result["maxProperties"] = field["maximumItems"]
            return result
        if kind == "BASE64_BYTES":
            result: dict[str, Any] = {"type": "string", "minLength": 4, "contentEncoding": "base64",
                                     "pattern": r"^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"}
            if "maximumUTF8Bytes" in field:
                maximum = field["maximumUTF8Bytes"]
                result.update({"maxLength": ((maximum + 2) // 3) * 4,
                               "x_assetrounds_maximumDecodedBytes": maximum,
                               "x_assetrounds_maximumEncodedUTF8Bytes": ((maximum + 2) // 3) * 4})
            return result
        if kind == "BOOLEAN":
            return {"type": "boolean"}
        if kind == "UTC_INSTANT":
            return {"type": "string", "pattern": r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"}
        if kind == "SHA256":
            return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        if kind == "INTEGER":
            result = {"type": "integer"}
            if "minimumInteger" in field:
                result["minimum"] = field["minimumInteger"]
            if "maximumInteger" in field:
                result["maximum"] = field["maximumInteger"]
            return result
        if kind == "UNSIGNED_INTEGER":
            return {"type": "integer", "minimum": field.get("minimumUnsignedInteger", 0),
                    "maximum": field.get("maximumUnsignedInteger", UINT64_MAX),
                    "x_assetrounds_integerEncoding": "BASE10_INTEGER_NO_EXPONENT",
                    "x_assetrounds_integerRepresentation": "UINT64_EXACT_NO_FLOAT_CONVERSION"}
        if kind == "REFERENCE_DATE_SECONDS":
            return {"type": "number", "minimum": -DOUBLE_MAX, "maximum": DOUBLE_MAX,
                    "x_assetrounds_timeEpoch": "2001-01-01T00:00:00Z", "x_assetrounds_timeUnit": "SECONDS",
                    "x_assetrounds_numberRepresentation": "FINITE_IEEE754_BINARY64",
                    "x_assetrounds_timeRounding": "NONE"}
        return {"$ref": f"#/$defs/{field['referencedTypeID']}"}

    def object_shape(obj: dict[str, Any]) -> dict[str, Any]:
        properties: dict[str, Any] = {}
        required = []
        for field in obj["fields"]:
            if field["kind"] == "ARRAY":
                value = {"type": "array", "maxItems": field["maximumItems"],
                         "items": scalar(field["arrayElementKind"], field), "x_assetrounds_ordered": field["ordered"]}
                if field["uniqueItems"]:
                    value["uniqueItems"] = True
            else:
                value = scalar(field["kind"], field)
            if field["nullable"]:
                value = {"anyOf": [value, {"type": "null"}]}
            properties[field["jsonName"]] = value
            if field["required"]:
                required.append(field["jsonName"])
        return {"type": "object", "additionalProperties": obj["unknownFieldPolicy"] == "PRESERVE",
                "properties": properties, "required": sorted(required),
                "x_assetrounds_unknownFieldPolicy": obj["unknownFieldPolicy"]}

    definitions = {obj["typeID"]: object_shape(obj) for obj in manifest["objects"]}
    for enum in manifest["enums"]:
        if "knownIntegerValues" in enum:
            value = {"type": "integer", "enum": enum["knownIntegerValues"], "x_assetrounds_enumPolicy": enum["policy"]}
        elif enum["policy"] == "CLOSED":
            value = {"type": "string", "x_assetrounds_enumPolicy": enum["policy"]}
            value["enum"] = enum["knownValues"]
        else:
            value = {"type": "string", "x_assetrounds_enumPolicy": enum["policy"]}
            value["x_assetrounds_knownValues"] = enum["knownValues"]
        definitions[enum["typeID"]] = value
    limitations = [
        "NFC, all Unicode noncharacters, exact UTF-8 and decoded-byte ceilings require codec validation.",
        "UTC_INSTANT pattern checks shape, not calendar validity; ordered arrays need semantic validation.",
        "PRESERVE permits unknown values; a validator cannot prove a reader retains those bytes.",
        "JSON Schema integer semantics do not enforce JSON lexical spelling or exact-number host parsing.",
        "Cross-field invariants and authentic production catalog completeness require independent validation.",
    ]
    if manifest["schemaVersion"] == 2:
        limitations[0] = (
            "STRING NFC/noncharacter rules and exact UTF-8/decoded-byte ceilings need codec validation; "
            "PRESERVED_STRING and STRING_MAP preserve source Unicode without NFC/control exclusions. "
            "Source-specific nonempty/trimmed rules require separate semantic validation."
        )
    return {"$schema": DIALECT, "$id": schema_id, "$ref": f"#/$defs/{root_type_id}", "$defs": definitions,
            "x_assetrounds_rootTypeID": root_type_id, "x_assetrounds_manifestID": manifest["manifestID"],
            "x_assetrounds_manifestVersion": manifest["manifestVersion"],
            "x_assetrounds_manifestSchemaVersion": manifest["schemaVersion"],
            "x_assetrounds_manifestCanonicalSHA256": hashlib.sha256(canonical_bytes(manifest)).hexdigest(),
            "x_assetrounds_codec": manifest["codec"], "x_assetrounds_compatibility": manifest["compatibility"],
            "x_assetrounds_productManifestDerived": True,
            "x_assetrounds_validationScope": "MANIFEST_GRAMMAR_AND_SCHEMA_SHAPE_NOT_PRODUCTION_CATALOG_ADMISSION",
            "x_assetrounds_validationLimitations": limitations}


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _float(token: str) -> float:
    value = float(token)
    require(math.isfinite(value), "nonfinite JSON number")
    return value


def _constant(token: str) -> None:
    raise ContractError(f"nonfinite JSON constant: {token}")


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_pairs,
                      parse_float=_float, parse_constant=_constant)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--root-type-id", required=True)
    parser.add_argument("--schema-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args(argv)
    try:
        require(arguments.manifest.resolve() != arguments.output.resolve(), "output must differ from source manifest")
        schema = compile_product_schema(load_manifest(arguments.manifest), arguments.root_type_id, arguments.schema_id)
        output = canonical_bytes(schema) + b"\n"
        arguments.output.write_bytes(output)
        print(json.dumps({"schemaID": arguments.schema_id, "rootTypeID": arguments.root_type_id,
                          "schemaSHA256": hashlib.sha256(output).hexdigest(), "bytes": len(output)}, sort_keys=True))
        return 0
    except (OSError, UnicodeError, RecursionError, ValueError) as error:
        print(f"contract generation failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
