#!/usr/bin/env python3
"""Deterministic, dependency-free JSON Schema Draft 2020-12 validator.

This test-support tool intentionally has no network client and resolves references
only from the lock-provided in-memory registry.  It implements the validation and
applicator vocabulary used by the V23 P03-C06 contract schemas, plus the keyword
surface needed to validate those schemas against the official 2020-12 meta-schema.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urldefrag, urljoin, urlparse


DRAFT_ROOT_URI = "https://json-schema.org/draft/2020-12/schema"
LOCK_RELATIVE_PATH = "Scripts/v21-contracts/portable-contract-validator.lock.json"
MAX_JSON_BYTES = 16 * 1024 * 1024
MAX_JSON_DEPTH = 256
MAX_JSON_NODES = 1_000_000


class PortableContractError(ValueError):
    """Fail-closed tool/configuration/decoder error."""


def _duplicate_rejecting_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise PortableContractError(f"duplicate JSON object key: {key!r}")
        value[key] = item
    return value


def _reject_nonfinite(token: str) -> None:
    raise PortableContractError(f"non-finite JSON number is forbidden: {token}")


def _bounded_shape(value: Any) -> None:
    nodes = 0
    stack: list[tuple[Any, int]] = [(value, 0)]
    while stack:
        current, depth = stack.pop()
        nodes += 1
        if nodes > MAX_JSON_NODES:
            raise PortableContractError("JSON node limit exceeded")
        if depth > MAX_JSON_DEPTH:
            raise PortableContractError("JSON nesting limit exceeded")
        if isinstance(current, dict):
            stack.extend((item, depth + 1) for item in current.values())
        elif isinstance(current, list):
            stack.extend((item, depth + 1) for item in current)


def strict_loads(data: bytes, label: str = "JSON document") -> Any:
    if len(data) > MAX_JSON_BYTES:
        raise PortableContractError(f"{label} exceeds {MAX_JSON_BYTES} bytes")
    try:
        text = data.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise PortableContractError(f"{label} is not strict UTF-8") from error
    try:
        value = json.loads(
            text,
            object_pairs_hook=_duplicate_rejecting_object,
            parse_constant=_reject_nonfinite,
        )
    except (json.JSONDecodeError, PortableContractError) as error:
        raise PortableContractError(f"{label} decode failed: {error}") from error
    _bounded_shape(value)
    return value


def strict_load(path: Path) -> Any:
    if not path.is_file():
        raise PortableContractError(f"missing JSON document: {path}")
    return strict_loads(path.read_bytes(), str(path))


def canonical_json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def repository_root(script: Path | None = None) -> Path:
    origin = (script or Path(__file__)).resolve()
    root = origin.parents[2]
    if not (root / "Scripts" / "v23").is_dir():
        raise PortableContractError(f"repository root not found from {origin}")
    return root


def load_lock(root: Path) -> dict[str, Any]:
    value = strict_load(root / LOCK_RELATIVE_PATH)
    if not isinstance(value, dict):
        raise PortableContractError("portable validator lock is not an object")
    if value.get("schema") != "PortableContractValidatorLockV1" or value.get("schemaVersion") != 1:
        raise PortableContractError("portable validator lock schema identity differs")
    return value


def load_registry(root: Path, lock: dict[str, Any]) -> dict[str, Any]:
    registry_rows = lock.get("officialMetaSchema", {}).get("registry")
    if not isinstance(registry_rows, list) or not registry_rows:
        raise PortableContractError("lock has no official meta-schema registry")
    registry: dict[str, Any] = {}
    paths: set[str] = set()
    for row in registry_rows:
        if not isinstance(row, dict) or set(row) != {"uri", "path"}:
            raise PortableContractError("invalid meta-schema registry row")
        uri, relative = row["uri"], row["path"]
        if not isinstance(uri, str) or not isinstance(relative, str):
            raise PortableContractError("meta-schema registry values must be strings")
        if uri in registry or relative in paths:
            raise PortableContractError("duplicate meta-schema registry URI or path")
        document = strict_load(root / relative)
        if not isinstance(document, dict) or document.get("$id") != uri:
            raise PortableContractError(f"meta-schema identity differs: {relative}")
        registry[uri] = document
        paths.add(relative)
    if DRAFT_ROOT_URI not in registry:
        raise PortableContractError("Draft 2020-12 root meta-schema is absent")
    return registry


def _pointer_token(value: str) -> str:
    return value.replace("~", "~0").replace("/", "~1")


def _join_pointer(pointer: str, token: str | int) -> str:
    return pointer + "/" + _pointer_token(str(token))


def _resolve_pointer(document: Any, fragment: str) -> tuple[Any, str]:
    if fragment in ("", None):
        return document, ""
    if not fragment.startswith("/"):
        stack: list[Any] = [document]
        while stack:
            current = stack.pop()
            if isinstance(current, dict):
                if current.get("$anchor") == fragment or current.get("$dynamicAnchor") == fragment:
                    return current, f"#{fragment}"
                stack.extend(reversed(list(current.values())))
            elif isinstance(current, list):
                stack.extend(reversed(current))
        raise PortableContractError(f"unresolved schema anchor: #{fragment}")
    current = document
    for raw in fragment[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(current, dict) and token in current:
            current = current[token]
        elif isinstance(current, list) and token.isdigit() and int(token) < len(current):
            current = current[int(token)]
        else:
            raise PortableContractError(f"unresolved schema JSON pointer: #{fragment}")
    return current, fragment


@dataclass(frozen=True, order=True)
class ValidationIssue:
    instance_path: str
    schema_uri: str
    schema_path: str
    result_class: str
    detail: str

    def as_dict(self) -> dict[str, str]:
        return {
            "instancePath": self.instance_path,
            "schemaPath": self.schema_path,
            "schemaURI": self.schema_uri,
            "resultClass": self.result_class,
            "detail": self.detail,
        }


class Draft202012Validator:
    def __init__(self, registry: dict[str, Any], assert_formats: bool = False):
        self.registry = dict(registry)
        self.assert_formats = assert_formats
        self.dynamic_root_uri = DRAFT_ROOT_URI

    def register(self, schema: Any, fallback_uri: str) -> str:
        if not isinstance(schema, (dict, bool)):
            raise PortableContractError("schema must be an object or boolean")
        uri = schema.get("$id", fallback_uri) if isinstance(schema, dict) else fallback_uri
        if not isinstance(uri, str) or not uri:
            raise PortableContractError("schema identity must be a non-empty string")
        absolute, fragment = urldefrag(uri)
        if fragment:
            raise PortableContractError("schema root $id may not contain a non-empty fragment")
        self.registry[absolute] = schema
        return absolute

    def _resolve(self, reference: str, base_uri: str, dynamic: bool = False) -> tuple[Any, str, str]:
        if dynamic and reference == "#meta":
            resource_uri, fragment = self.dynamic_root_uri, "meta"
        else:
            absolute = urljoin(base_uri, reference)
            resource_uri, fragment = urldefrag(absolute)
        if resource_uri not in self.registry:
            raise PortableContractError(f"reference is not in the sealed registry: {reference}")
        target, pointer = _resolve_pointer(self.registry[resource_uri], fragment)
        return target, resource_uri, pointer

    def audit_references(self, schema_uri: str) -> list[ValidationIssue]:
        root = self.registry.get(schema_uri)
        if root is None:
            raise PortableContractError(f"schema is not registered: {schema_uri}")
        issues: list[ValidationIssue] = []
        stack: list[tuple[Any, str, str]] = [(root, schema_uri, "")]
        while stack:
            value, base_uri, path = stack.pop()
            if isinstance(value, dict):
                next_base = base_uri
                identifier = value.get("$id")
                if isinstance(identifier, str):
                    next_base = urldefrag(urljoin(base_uri, identifier))[0]
                for keyword in ("$ref", "$dynamicRef"):
                    reference = value.get(keyword)
                    if isinstance(reference, str):
                        try:
                            self._resolve(reference, next_base, keyword == "$dynamicRef")
                        except PortableContractError as error:
                            issues.append(ValidationIssue("", base_uri, _join_pointer(path, keyword), "REFERENCE_UNRESOLVED", str(error)))
                for key, child in reversed(list(value.items())):
                    stack.append((child, next_base, _join_pointer(path, key)))
            elif isinstance(value, list):
                for index in range(len(value) - 1, -1, -1):
                    stack.append((value[index], base_uri, _join_pointer(path, index)))
        return sorted(set(issues))

    def validate(self, instance: Any, schema_uri: str, dynamic_root_uri: str | None = None) -> dict[str, Any]:
        if schema_uri not in self.registry:
            raise PortableContractError(f"schema is not registered: {schema_uri}")
        self.dynamic_root_uri = dynamic_root_uri or schema_uri
        issues: list[ValidationIssue] = []
        self._evaluate(instance, self.registry[schema_uri], "", schema_uri, "", schema_uri, issues)
        unique = sorted(set(issues))
        return {"valid": not unique, "errors": [issue.as_dict() for issue in unique]}

    @staticmethod
    def _matches_type(value: Any, expected: str) -> bool:
        if expected == "null":
            return value is None
        if expected == "boolean":
            return isinstance(value, bool)
        if expected == "object":
            return isinstance(value, dict)
        if expected == "array":
            return isinstance(value, list)
        if expected == "string":
            return isinstance(value, str)
        if expected == "integer":
            return isinstance(value, int) and not isinstance(value, bool)
        if expected == "number":
            return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
        return False

    @staticmethod
    def _same(left: Any, right: Any) -> bool:
        return canonical_json(left) == canonical_json(right)

    @staticmethod
    def _issue(
        issues: list[ValidationIssue], instance_path: str, schema_uri: str,
        schema_path: str, keyword: str, result_class: str, detail: str,
    ) -> None:
        issues.append(ValidationIssue(instance_path, schema_uri, _join_pointer(schema_path, keyword), result_class, detail))

    def _branch_valid(self, instance: Any, schema: Any, ip: str, su: str, sp: str, base: str) -> bool:
        temporary: list[ValidationIssue] = []
        self._evaluate(instance, schema, ip, su, sp, base, temporary)
        return not temporary

    def _evaluate(
        self, instance: Any, schema: Any, instance_path: str, schema_uri: str,
        schema_path: str, base_uri: str, issues: list[ValidationIssue],
    ) -> None:
        if schema is True:
            return
        if schema is False:
            self._issue(issues, instance_path, schema_uri, schema_path, "$false", "FALSE_SCHEMA", "boolean false schema rejects every instance")
            return
        if not isinstance(schema, dict):
            self._issue(issues, instance_path, schema_uri, schema_path, "$schema", "SCHEMA_INVALID", "schema is neither object nor boolean")
            return

        identifier = schema.get("$id")
        if isinstance(identifier, str):
            base_uri = urldefrag(urljoin(base_uri, identifier))[0]

        for keyword, dynamic in (("$ref", False), ("$dynamicRef", True)):
            if keyword in schema:
                reference = schema[keyword]
                if not isinstance(reference, str):
                    self._issue(issues, instance_path, schema_uri, schema_path, keyword, "REFERENCE_INVALID", "reference must be a string")
                else:
                    try:
                        target, target_uri, target_path = self._resolve(reference, base_uri, dynamic)
                    except PortableContractError as error:
                        self._issue(issues, instance_path, schema_uri, schema_path, keyword, "REFERENCE_UNRESOLVED", str(error))
                    else:
                        self._evaluate(instance, target, instance_path, target_uri, target_path, target_uri, issues)

        expected = schema.get("type")
        if expected is not None:
            types = expected if isinstance(expected, list) else [expected]
            if not types or not all(isinstance(item, str) for item in types):
                self._issue(issues, instance_path, schema_uri, schema_path, "type", "SCHEMA_INVALID", "type must be a string or non-empty string array")
                return
            if not any(self._matches_type(instance, item) for item in types):
                self._issue(issues, instance_path, schema_uri, schema_path, "type", "TYPE_MISMATCH", f"expected {types!r}")
                return

        if "const" in schema and not self._same(instance, schema["const"]):
            self._issue(issues, instance_path, schema_uri, schema_path, "const", "CONST_MISMATCH", "instance differs from const")
        if "enum" in schema:
            choices = schema["enum"]
            if not isinstance(choices, list) or not any(self._same(instance, item) for item in choices):
                self._issue(issues, instance_path, schema_uri, schema_path, "enum", "ENUM_MISMATCH", "instance is not an allowed enum value")

        for keyword in ("allOf",):
            branches = schema.get(keyword)
            if isinstance(branches, list):
                for index, branch in enumerate(branches):
                    self._evaluate(instance, branch, instance_path, schema_uri, _join_pointer(_join_pointer(schema_path, keyword), index), base_uri, issues)
        for keyword, required_count in (("anyOf", None), ("oneOf", 1)):
            branches = schema.get(keyword)
            if isinstance(branches, list):
                passed = sum(self._branch_valid(instance, branch, instance_path, schema_uri, _join_pointer(_join_pointer(schema_path, keyword), index), base_uri) for index, branch in enumerate(branches))
                if (keyword == "anyOf" and passed == 0) or (keyword == "oneOf" and passed != required_count):
                    result = "ANY_OF_NO_MATCH" if keyword == "anyOf" else "ONE_OF_MATCH_COUNT"
                    self._issue(issues, instance_path, schema_uri, schema_path, keyword, result, f"matching branch count: {passed}")
        if "not" in schema and self._branch_valid(instance, schema["not"], instance_path, schema_uri, _join_pointer(schema_path, "not"), base_uri):
            self._issue(issues, instance_path, schema_uri, schema_path, "not", "NOT_SCHEMA_MATCHED", "instance matched forbidden schema")
        if "if" in schema:
            condition = self._branch_valid(instance, schema["if"], instance_path, schema_uri, _join_pointer(schema_path, "if"), base_uri)
            branch_name = "then" if condition else "else"
            if branch_name in schema:
                self._evaluate(instance, schema[branch_name], instance_path, schema_uri, _join_pointer(schema_path, branch_name), base_uri, issues)

        if isinstance(instance, dict):
            self._evaluate_object(instance, schema, instance_path, schema_uri, schema_path, base_uri, issues)
        elif isinstance(instance, list):
            self._evaluate_array(instance, schema, instance_path, schema_uri, schema_path, base_uri, issues)
        elif isinstance(instance, str):
            self._evaluate_string(instance, schema, instance_path, schema_uri, schema_path, issues)
        elif isinstance(instance, (int, float)) and not isinstance(instance, bool):
            self._evaluate_number(instance, schema, instance_path, schema_uri, schema_path, issues)

    def _evaluate_object(self, value: dict[str, Any], schema: dict[str, Any], ip: str, su: str, sp: str, base: str, issues: list[ValidationIssue]) -> None:
        required = schema.get("required", [])
        if isinstance(required, list):
            for name in required:
                if isinstance(name, str) and name not in value:
                    self._issue(issues, _join_pointer(ip, name), su, sp, "required", "REQUIRED_PROPERTY_MISSING", f"missing property: {name}")
        for keyword, comparison, result in (("minProperties", lambda n, x: n < x, "MIN_PROPERTIES"), ("maxProperties", lambda n, x: n > x, "MAX_PROPERTIES")):
            limit = schema.get(keyword)
            if isinstance(limit, int) and comparison(len(value), limit):
                self._issue(issues, ip, su, sp, keyword, result, f"property count {len(value)} violates {limit}")

        matched: set[str] = set()
        properties = schema.get("properties")
        if isinstance(properties, dict):
            for name, subschema in properties.items():
                if name in value:
                    matched.add(name)
                    self._evaluate(value[name], subschema, _join_pointer(ip, name), su, _join_pointer(_join_pointer(sp, "properties"), name), base, issues)
        patterns = schema.get("patternProperties")
        if isinstance(patterns, dict):
            for pattern, subschema in patterns.items():
                try:
                    expression = re.compile(pattern)
                except re.error:
                    self._issue(issues, ip, su, sp, "patternProperties", "SCHEMA_INVALID_REGEX", f"invalid pattern: {pattern}")
                    continue
                for name, item in value.items():
                    if expression.search(name):
                        matched.add(name)
                        self._evaluate(item, subschema, _join_pointer(ip, name), su, _join_pointer(_join_pointer(sp, "patternProperties"), pattern), base, issues)
        if "propertyNames" in schema:
            for name in value:
                self._evaluate(name, schema["propertyNames"], _join_pointer(ip, name), su, _join_pointer(sp, "propertyNames"), base, issues)

        additional = schema.get("additionalProperties", True)
        for name in sorted(set(value) - matched):
            if additional is False:
                self._issue(issues, _join_pointer(ip, name), su, sp, "additionalProperties", "ADDITIONAL_PROPERTY_FORBIDDEN", f"unexpected property: {name}")
            elif isinstance(additional, (dict, bool)):
                self._evaluate(value[name], additional, _join_pointer(ip, name), su, _join_pointer(sp, "additionalProperties"), base, issues)

        dependencies = schema.get("dependentRequired")
        if isinstance(dependencies, dict):
            for trigger, names in dependencies.items():
                if trigger in value and isinstance(names, list):
                    for name in names:
                        if isinstance(name, str) and name not in value:
                            self._issue(issues, _join_pointer(ip, name), su, sp, "dependentRequired", "DEPENDENT_PROPERTY_MISSING", f"{trigger} requires {name}")
        dependent_schemas = schema.get("dependentSchemas")
        if isinstance(dependent_schemas, dict):
            for trigger, subschema in dependent_schemas.items():
                if trigger in value:
                    self._evaluate(value, subschema, ip, su, _join_pointer(_join_pointer(sp, "dependentSchemas"), trigger), base, issues)

    def _evaluate_array(self, value: list[Any], schema: dict[str, Any], ip: str, su: str, sp: str, base: str, issues: list[ValidationIssue]) -> None:
        for keyword, comparison, result in (("minItems", lambda n, x: n < x, "MIN_ITEMS"), ("maxItems", lambda n, x: n > x, "MAX_ITEMS")):
            limit = schema.get(keyword)
            if isinstance(limit, int) and comparison(len(value), limit):
                self._issue(issues, ip, su, sp, keyword, result, f"item count {len(value)} violates {limit}")
        if schema.get("uniqueItems") is True:
            encoded = [canonical_json(item) for item in value]
            if len(encoded) != len(set(encoded)):
                self._issue(issues, ip, su, sp, "uniqueItems", "UNIQUE_ITEMS", "array items are not unique")
        prefix = schema.get("prefixItems")
        consumed = 0
        if isinstance(prefix, list):
            consumed = min(len(prefix), len(value))
            for index in range(consumed):
                self._evaluate(value[index], prefix[index], _join_pointer(ip, index), su, _join_pointer(_join_pointer(sp, "prefixItems"), index), base, issues)
        items = schema.get("items")
        if isinstance(items, (dict, bool)):
            for index in range(consumed, len(value)):
                self._evaluate(value[index], items, _join_pointer(ip, index), su, _join_pointer(sp, "items"), base, issues)
        if "contains" in schema:
            matches = sum(self._branch_valid(item, schema["contains"], _join_pointer(ip, index), su, _join_pointer(sp, "contains"), base) for index, item in enumerate(value))
            minimum = schema.get("minContains", 1)
            maximum = schema.get("maxContains")
            if isinstance(minimum, int) and matches < minimum:
                self._issue(issues, ip, su, sp, "contains", "CONTAINS_MATCH_COUNT", f"contains matches {matches}, minimum {minimum}")
            if isinstance(maximum, int) and matches > maximum:
                self._issue(issues, ip, su, sp, "contains", "CONTAINS_MATCH_COUNT", f"contains matches {matches}, maximum {maximum}")

    def _evaluate_string(self, value: str, schema: dict[str, Any], ip: str, su: str, sp: str, issues: list[ValidationIssue]) -> None:
        for keyword, comparison, result in (("minLength", lambda n, x: n < x, "MIN_LENGTH"), ("maxLength", lambda n, x: n > x, "MAX_LENGTH")):
            limit = schema.get(keyword)
            if isinstance(limit, int) and comparison(len(value), limit):
                self._issue(issues, ip, su, sp, keyword, result, f"length {len(value)} violates {limit}")
        pattern = schema.get("pattern")
        if isinstance(pattern, str):
            try:
                matches = re.search(pattern, value) is not None
            except re.error:
                self._issue(issues, ip, su, sp, "pattern", "SCHEMA_INVALID_REGEX", "schema pattern is invalid")
            else:
                if not matches:
                    self._issue(issues, ip, su, sp, "pattern", "PATTERN_MISMATCH", "string does not match pattern")
        if self.assert_formats and isinstance(schema.get("format"), str):
            format_name = schema["format"]
            valid = True
            if format_name == "uri":
                parsed = urlparse(value)
                valid = bool(parsed.scheme) and not any(character.isspace() for character in value)
            elif format_name == "uri-reference":
                valid = not any(character.isspace() for character in value)
            elif format_name == "regex":
                try:
                    re.compile(value)
                except re.error:
                    valid = False
            if not valid:
                self._issue(issues, ip, su, sp, "format", "FORMAT_MISMATCH", f"invalid {format_name}")
        if schema.get("contentEncoding") == "base64":
            try:
                raw = value.encode("ascii", errors="strict")
                decoded = base64.b64decode(raw, validate=True)
                valid = base64.b64encode(decoded) == raw
            except (UnicodeEncodeError, binascii.Error, ValueError):
                valid = False
            if not valid:
                self._issue(issues, ip, su, sp, "contentEncoding", "CONTENT_ENCODING_INVALID", "string is not canonical base64")

    def _evaluate_number(self, value: int | float, schema: dict[str, Any], ip: str, su: str, sp: str, issues: list[ValidationIssue]) -> None:
        rules = (
            ("minimum", lambda number, limit: number < limit, "MINIMUM"),
            ("maximum", lambda number, limit: number > limit, "MAXIMUM"),
            ("exclusiveMinimum", lambda number, limit: number <= limit, "EXCLUSIVE_MINIMUM"),
            ("exclusiveMaximum", lambda number, limit: number >= limit, "EXCLUSIVE_MAXIMUM"),
        )
        for keyword, comparison, result in rules:
            limit = schema.get(keyword)
            if isinstance(limit, (int, float)) and not isinstance(limit, bool) and comparison(value, limit):
                self._issue(issues, ip, su, sp, keyword, result, f"value {value} violates {limit}")
        multiple = schema.get("multipleOf")
        if isinstance(multiple, (int, float)) and not isinstance(multiple, bool) and multiple > 0:
            quotient = value / multiple
            if not math.isclose(quotient, round(quotient), rel_tol=1e-12, abs_tol=1e-12):
                self._issue(issues, ip, su, sp, "multipleOf", "MULTIPLE_OF", f"value is not a multiple of {multiple}")


def validate_schema_against_official_meta(schema: Any, registry: dict[str, Any], fallback_uri: str) -> dict[str, Any]:
    validator = Draft202012Validator(registry, assert_formats=True)
    target_uri = validator.register(schema, fallback_uri)
    reference_issues = validator.audit_references(target_uri)
    result = validator.validate(schema, DRAFT_ROOT_URI, dynamic_root_uri=DRAFT_ROOT_URI)
    errors = sorted(reference_issues + [ValidationIssue(
        row["instancePath"], row["schemaURI"], row["schemaPath"], row["resultClass"], row["detail"]
    ) for row in result["errors"]])
    return {"valid": not errors, "errors": [error.as_dict() for error in errors]}


def validate_instance(instance: Any, schema: Any, registry: dict[str, Any], fallback_uri: str) -> dict[str, Any]:
    validator = Draft202012Validator(registry, assert_formats=False)
    target_uri = validator.register(schema, fallback_uri)
    reference_issues = validator.audit_references(target_uri)
    if reference_issues:
        return {"valid": False, "errors": [issue.as_dict() for issue in reference_issues]}
    return validator.validate(instance, target_uri)


def _emit(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False))


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", type=Path, required=True)
    parser.add_argument("--instance", type=Path)
    parser.add_argument("--meta-only", action="store_true")
    arguments = parser.parse_args(list(argv) if argv is not None else None)
    try:
        root = repository_root()
        lock = load_lock(root)
        registry = load_registry(root, lock)
        schema = strict_load(arguments.schema.resolve())
        meta = validate_schema_against_official_meta(schema, registry, arguments.schema.resolve().as_uri())
        result: dict[str, Any] = {"metaSchema": meta}
        if not arguments.meta_only:
            if arguments.instance is None:
                raise PortableContractError("--instance is required unless --meta-only is used")
            instance = strict_load(arguments.instance.resolve())
            result["instance"] = validate_instance(instance, schema, registry, arguments.schema.resolve().as_uri())
        result["valid"] = meta["valid"] and result.get("instance", {"valid": True})["valid"]
        _emit(result)
        return 0 if result["valid"] else 1
    except PortableContractError as error:
        _emit({"valid": False, "toolError": str(error)})
        return 2


if __name__ == "__main__":
    sys.exit(main())
