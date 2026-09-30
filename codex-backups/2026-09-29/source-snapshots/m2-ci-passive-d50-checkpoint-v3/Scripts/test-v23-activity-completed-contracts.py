#!/usr/bin/env python3
"""Real CLI regressions for manifest grammar and independent schema validation.

The small synthetic catalog tests compiler mechanics only. It is deliberately
not presented as the completed-file production catalog or Swift runtime evidence.
"""
from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
COMPILER = Path(__file__).resolve().parent / "v23/activity_completed_contracts.py"
ROOT = next(parent for parent in Path(__file__).resolve().parents
            if (parent / "Scripts/v21-contracts/portable-contract-validator.lock.json").is_file())
LEGACY = ROOT / "FieldEvidenceAppTests/Fixtures/V23/Activities/V23P03C06LegacyContractManifestV1.json"
# Source-provided exact legacy pin (kept explicit, not obtained from this compiler).
LEGACY_SHA = "b142747430f74fc3b2d0b403f9e60bcf08d3ba49f5e1249a2790d95eb0a3643c"
LEGACY_SCHEMA_SHA = "a639fb24b44bed6c62194b772cbac0d39531f64b871c8ce260bcadcb41d12085"
LOCK_SHA = "69e23865c4114792f9f62d2eab73a06ed85623e01e68c96fcccb79dfdb913862"
VALIDATOR_SHA = "7a6ce17a71e55933a121e60ee11c373b77720f33eddc9d55d4597c19452f0173"
SCHEMA_ID = "https://schemas.assetrounds.local/tests/completed-contract-mechanics/schema"
UINT64_MAX = 18446744073709551615
DOUBLE_MAX = 1.7976931348623157e308


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_python(path: Path, *arguments: Any) -> subprocess.CompletedProcess[str]:
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    return subprocess.run([sys.executable, "-B", str(path), *(str(arg) for arg in arguments)],
                          cwd=ROOT, env=environment, text=True, encoding="utf-8", capture_output=True, timeout=45)


def field(name: str, kind: str, **extra: Any) -> dict[str, Any]:
    return {"fieldID": name, "jsonName": name, "kind": kind, "required": True,
            "nullable": False, "ordered": False, "uniqueItems": False, **extra}


def synthetic_manifest() -> dict[str, Any]:
    # Authentic top-level codec/registry facts are reused; the synthetic type
    # graph below is explicitly unrelated to production completed-file admission.
    manifest = json.loads(LEGACY.read_bytes())
    manifest["schemaVersion"] = 2
    manifest["manifestID"] = "compiler-mechanics-v2"
    manifest["manifestVersion"] = 2
    manifest["codec"]["codecVersion"] = 2
    manifest["codec"]["timeEncoding"] = "PER_FIELD_UTC_RFC3339_MILLISECONDS_Z_OR_FINITE_APPLE_REFERENCE_SECONDS"
    manifest["codec"]["stringNormalization"] = "PER_FIELD_NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED_OR_PRESERVED_SOURCE_UNICODE"
    manifest["compatibility"]["minimumReaderVersion"] = 2
    manifest["compatibility"]["maximumReaderVersion"] = 2
    manifest["objects"] = [
        {"typeID": "child-v1", "version": 1, "unknownFieldPolicy": "PRESERVE",
         "fields": [field("flag", "BOOLEAN")]},
        {"typeID": "mechanics-root-v1", "version": 1, "unknownFieldPolicy": "REJECT", "fields": [
            field("blob", "BASE64_BYTES", maximumUTF8Bytes=2),
            field("bounded", "UNSIGNED_INTEGER", minimumUnsignedInteger=9007199254740993,
                  maximumUnsignedInteger=18446744073709551614),
            field("child", "OBJECT", referencedTypeID="child-v1"),
            field("closed", "ENUM", referencedTypeID="closed-v1"),
            field("date", "REFERENCE_DATE_SECONDS"),
            field("digest", "SHA256"),
            field("instant", "UTC_INSTANT"),
            field("items", "ARRAY", arrayElementKind="UNSIGNED_INTEGER", maximumItems=3,
                  uniqueItems=True, ordered=True),
            field("maybe", "STRING", nullable=True, maximumUTF8Bytes=4),
            field("open", "ENUM", referencedTypeID="open-v1"),
            field("optional", "STRING", required=False, maximumUTF8Bytes=4),
            field("revision", "UNSIGNED_INTEGER"),
            field("signed", "INTEGER", minimumInteger=-9223372036854775808, maximumInteger=9223372036854775807),
            field("text", "STRING", maximumUTF8Bytes=4),
        ]},
    ]
    manifest["enums"] = [
        {"typeID": "closed-v1", "version": 1, "policy": "CLOSED", "knownValues": ["A", "B"]},
        {"typeID": "open-v1", "version": 1, "policy": "PRESERVE_UNKNOWN", "knownValues": ["A", "B"]},
    ]
    return manifest


def instance() -> dict[str, Any]:
    return {"blob": "YWI=", "bounded": 9007199254740993, "child": {"flag": True},
            "closed": "A", "date": 123456789.12345679, "digest": "a" * 64,
            "instant": "2001-01-01T00:00:00.000Z", "items": [0, UINT64_MAX],
            "maybe": None, "open": "FUTURE", "revision": UINT64_MAX,
            "signed": -9223372036854775808, "text": "café"}


def preserved_manifest() -> dict[str, Any]:
    manifest = synthetic_manifest()
    fields = manifest["objects"][1]["fields"]
    fields.extend([
        field("preserved", "PRESERVED_STRING", maximumUTF8Bytes=4),
        field("reasons", "STRING_MAP", maximumKeyUTF8Bytes=256, maximumUTF8Bytes=512),
        field("textarray", "ARRAY", arrayElementKind="PRESERVED_STRING", maximumItems=4),
    ])
    fields.sort(key=lambda item: item["fieldID"])
    return manifest


def preserved_instance() -> dict[str, Any]:
    return {**instance(), "preserved": "a\u0000b", "reasons": {"e\u0301\t": "reason\u0000e\u0301"},
            "textarray": ["e\u0301", "text\u0001", "\u202a"]}


class ActivityCompletedContractCLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if sha(LEGACY) != LEGACY_SHA:
            raise AssertionError("genuine V1 fixture pin differs")
        lock_path = ROOT / "Scripts/v21-contracts/portable-contract-validator.lock.json"
        if sha(lock_path) != LOCK_SHA:
            raise AssertionError("portable validator lock pin differs")
        cls.validator = ROOT / "Scripts/v21-contracts/portable_contract_validator_v1.py"
        if sha(cls.validator) != VALIDATOR_SHA:
            raise AssertionError("portable validator implementation pin differs")
        # Exercise the existing exact-file/registry/reference checker, then use
        # the separate existing validator executable for every schema assertion.
        checked = run_python(ROOT / "Scripts/v21-contracts/check-portable-contract-lock.py")
        if checked.returncode != 0 or not json.loads(checked.stdout)["valid"]:
            raise AssertionError(checked.stdout + checked.stderr)

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="completed-contract-cli-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.manifest_path = self.directory / "manifest.json"
        self.output = self.directory / "unrelated-output-filename.json"

    def generate(self, manifest: dict[str, Any] | None = None, *, root: str = "mechanics-root-v1",
                 schema_id: str = SCHEMA_ID, raw: bytes | None = None, expected: int = 0) -> dict[str, Any] | None:
        data = raw if raw is not None else json.dumps(manifest or synthetic_manifest(), ensure_ascii=False).encode("utf-8")
        self.manifest_path.write_bytes(data)
        result = run_python(COMPILER, "--manifest", self.manifest_path, "--root-type-id", root,
                            "--schema-id", schema_id, "--output", self.output)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        if expected:
            self.assertIn("contract generation failed", result.stderr)
            return None
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["schemaSHA256"], sha(self.output))
        self.assertEqual(receipt["bytes"], self.output.stat().st_size)
        return json.loads(self.output.read_bytes())

    def validate(self, value: Any = None, *, meta_only: bool = False, expected: bool = True,
                 raw: bytes | None = None) -> dict[str, Any]:
        arguments: list[Any] = ["--schema", self.output]
        if meta_only:
            arguments.append("--meta-only")
        else:
            path = self.directory / "instance.json"
            path.write_bytes(raw if raw is not None else json.dumps(value, allow_nan=False).encode("utf-8"))
            arguments.extend(["--instance", path])
        result = run_python(self.validator, *arguments)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt["valid"], expected, receipt)
        self.assertEqual(result.returncode == 0, expected, result.stderr)
        if "metaSchema" in receipt:
            self.assertTrue(receipt["metaSchema"]["valid"], receipt)
        return receipt

    def mutate_field(self, name: str, **changes: Any) -> dict[str, Any]:
        manifest = synthetic_manifest()
        item = next(item for item in manifest["objects"][1]["fields"] if item["jsonName"] == name)
        item.update(changes)
        return manifest

    def test_real_cli_determinism_explicit_root_id_and_meta_schema(self) -> None:
        schema = self.generate()
        first = self.output.read_bytes()
        receipt1 = self.validate(instance())
        self.generate()
        self.assertEqual(first, self.output.read_bytes())
        self.assertEqual(receipt1, self.validate(instance()))
        self.validate(meta_only=True)
        self.assertEqual(schema["$id"], SCHEMA_ID)
        self.assertEqual(schema["$ref"], "#/$defs/mechanics-root-v1")
        self.assertEqual(set(schema["$defs"]), {"child-v1", "mechanics-root-v1", "closed-v1", "open-v1"})
        self.assertIn("NOT_PRODUCTION_CATALOG_ADMISSION", schema["x_assetrounds_validationScope"])
        child = self.generate(root="child-v1", schema_id="https://schemas.assetrounds.local/tests/explicit-child")
        self.assertEqual(child["$ref"], "#/$defs/child-v1")
        self.validate({"flag": False, "future": 1})

    def test_genuine_published_v1_fixture_compiles_without_source_rewrite(self) -> None:
        before = LEGACY.read_bytes()
        manifest = json.loads(before)
        root = manifest["objects"][0]["typeID"]
        schema = self.generate(manifest, root=root)
        self.validate(meta_only=True)
        self.assertEqual(schema["x_assetrounds_manifestSchemaVersion"], 1)
        self.assertEqual(schema["x_assetrounds_codec"]["codecVersion"], 1)
        self.assertEqual(sha(self.output), LEGACY_SCHEMA_SHA)
        self.assertEqual(LEGACY.read_bytes(), before)
        self.assertEqual(sha(LEGACY), LEGACY_SHA)

    def test_exact_uint64_bounds_and_adjacent_large_values(self) -> None:
        schema = self.generate()
        fields = schema["$defs"]["mechanics-root-v1"]["properties"]
        self.assertEqual(fields["revision"]["minimum"], 0)
        self.assertEqual(fields["revision"]["maximum"], 18446744073709551615)
        self.assertIs(type(fields["revision"]["maximum"]), int)
        self.assertEqual(fields["bounded"]["minimum"], 9007199254740993)
        self.assertEqual(fields["bounded"]["maximum"], 18446744073709551614)
        self.assertIn(b'"maximum":18446744073709551615', self.output.read_bytes())
        for value in [0, 9007199254740992, 9007199254740993, 9223372036854775808, UINT64_MAX]:
            with self.subTest(valid_uint=value):
                current = instance()
                current["revision"] = value
                self.validate(current)
        for value in [-1, UINT64_MAX + 1, True, False, "18446744073709551615", 1.5, 1.0]:
            with self.subTest(invalid_uint=value):
                current = instance()
                current["revision"] = value
                self.validate(current, expected=False)
        for value, expected in [(9007199254740992, False), (9007199254740993, True),
                                (UINT64_MAX - 1, True), (UINT64_MAX, False)]:
            current = instance()
            current["bounded"] = value
            self.validate(current, expected=expected)

    def test_reference_seconds_preserve_fractions_epoch_and_finite_range(self) -> None:
        schema = self.generate()
        date = schema["$defs"]["mechanics-root-v1"]["properties"]["date"]
        self.assertEqual(date["x_assetrounds_timeEpoch"], "2001-01-01T00:00:00Z")
        self.assertEqual(date["x_assetrounds_timeRounding"], "NONE")
        self.assertEqual(date["minimum"], -1.7976931348623157e308)
        self.assertEqual(date["maximum"], 1.7976931348623157e308)
        self.assertNotIn("multipleOf", date)
        for seconds in [-DOUBLE_MAX, -123456789.12345679, -0.125, 0, 0.12345678901234568, DOUBLE_MAX]:
            with self.subTest(seconds=seconds):
                current = instance()
                current["date"] = seconds
                self.validate(current)
        for seconds in [True, "2001-01-01T00:00:00Z", None]:
            current = instance()
            current["date"] = seconds
            self.validate(current, expected=False)
        raw = json.dumps(instance()).encode("utf-8")
        for token in [b"1e309", b"-1e309", b"NaN", b"Infinity", b"-Infinity"]:
            self.validate(raw=raw.replace(b"123456789.12345679", token), expected=False)

    def test_per_definition_preserve_and_closed_policies(self) -> None:
        schema = self.generate()
        self.assertFalse(schema["$defs"]["mechanics-root-v1"]["additionalProperties"])
        self.assertTrue(schema["$defs"]["child-v1"]["additionalProperties"])
        self.assertNotIn("enum", schema["$defs"]["open-v1"])
        current = instance()
        current["child"]["future"] = {"retained": [None, 1, "value"]}
        self.validate(current)
        current["future"] = 1
        self.validate(current, expected=False)
        current = instance()
        current["closed"] = "FUTURE"
        self.validate(current, expected=False)
        current["closed"] = "A"
        current["open"] = 42
        self.validate(current, expected=False)
        # The compatibility policy is metadata; it cannot override a local policy.
        manifest = synthetic_manifest()
        manifest["compatibility"]["unknownObjectFields"] = "PRESERVE"
        self.generate(manifest)
        current = instance()
        current["future"] = 1
        self.validate(current, expected=False)

    def test_integer_enum_emits_exact_rotation_values_and_array_references(self) -> None:
        manifest = synthetic_manifest()
        manifest["enums"][0].update(knownValues=[], knownIntegerValues=[0, 90, 180, 270])
        schema = self.generate(manifest)
        shape = schema["$defs"]["closed-v1"]
        self.assertEqual(shape["type"], "integer")
        self.assertEqual(shape["enum"], [0, 90, 180, 270])
        self.assertEqual(shape["x_assetrounds_enumPolicy"], "CLOSED")
        self.assertTrue(all(type(value) is int for value in shape["enum"]))
        first = self.output.read_bytes()
        self.generate(manifest)
        self.assertEqual(first, self.output.read_bytes())
        for value in [0, 90, 180, 270]:
            current = instance()
            current["closed"] = value
            self.validate(current)
        for value in [1, -90, 360, "90", True, None, 90.0, 90.5]:
            current = instance()
            current["closed"] = value
            self.validate(current, expected=False)
        items = manifest["objects"][1]["fields"][7]
        items.update(arrayElementKind="ENUM", referencedTypeID="closed-v1")
        self.generate(manifest)
        current = instance()
        current.update(closed=90, items=[0, 90, 270])
        self.validate(current)
        current["items"] = [360]
        self.validate(current, expected=False)

    def test_integer_enum_preserves_int64_extremes_and_values_above_binary64_precision(self) -> None:
        manifest = synthetic_manifest()
        values = [-9223372036854775808, 9007199254740993, 9223372036854775807]
        manifest["enums"][0].update(knownValues=[], knownIntegerValues=values)
        schema = self.generate(manifest)
        self.assertEqual(schema["$defs"]["closed-v1"]["enum"], values)
        self.assertIn(b'"enum":[-9223372036854775808,9007199254740993,9223372036854775807]', self.output.read_bytes())
        for value in values:
            current = instance()
            current["closed"] = value
            self.validate(current)
        for value in [-9223372036854775809, 9007199254740992, 9007199254740994, 9223372036854775808]:
            current = instance()
            current["closed"] = value
            self.validate(current, expected=False)

    def test_integer_enum_rejects_mixed_null_noninteger_unordered_or_open_metadata(self) -> None:
        for values in [None, [], [False], [True], [1.0], [1.5], [None], ["1"],
                       [-9223372036854775809], [9223372036854775808], [0, 0], [90, 0]]:
            with self.subTest(values=values):
                manifest = synthetic_manifest()
                manifest["enums"][0].update(knownValues=[], knownIntegerValues=values)
                self.generate(manifest, expected=2)
        for extra in [{"knownValues": ["A"]}, {"knownValues": [0]}, {"knownValues": None},
                      {"policy": "PRESERVE_UNKNOWN"}, {"unknownIntegerValues": [1]}]:
            manifest = synthetic_manifest()
            manifest["enums"][0].update(knownValues=[], knownIntegerValues=[0, 90])
            manifest["enums"][0].update(extra)
            self.generate(manifest, expected=2)
        manifest = synthetic_manifest()
        manifest["enums"][0]["knownIntegerValues"] = [0, 90]
        del manifest["enums"][0]["knownValues"]
        self.generate(manifest, expected=2)
        manifest = synthetic_manifest()
        manifest["enums"][0].update(knownValues=[], knownIntegerValues=[0, 90])
        raw = json.dumps(manifest).encode("utf-8")
        self.generate(raw=raw.replace(b'"knownIntegerValues": [0, 90]',
                                     b'"knownIntegerValues": [0, 90], "knownIntegerValues": [0, 90]'), expected=2)
        self.generate(raw=raw.replace(b'"knownIntegerValues": [0, 90]',
                                     b'"knownIntegerValues": [0, 9e1]'), expected=2)

    def test_closed_schema2_empty_object_accepts_only_empty_payload(self) -> None:
        manifest = synthetic_manifest()
        manifest["objects"][0].update(fields=[], unknownFieldPolicy="REJECT")
        schema = self.generate(manifest)
        child = schema["$defs"]["child-v1"]
        self.assertEqual(child["type"], "object")
        self.assertEqual(child["properties"], {})
        self.assertEqual(child["required"], [])
        self.assertIs(child["additionalProperties"], False)
        current = instance()
        current["child"] = {}
        self.validate(current)
        for value in [{"unexpected": None}, None, [], "", False]:
            current["child"] = value
            self.validate(current, expected=False)
        self.generate(manifest, root="child-v1")
        self.validate({})
        self.validate({"unexpected": {}}, expected=False)

    def test_schema1_integer_enums_and_empty_objects_and_schema2_open_empty_objects_rejected(self) -> None:
        legacy = json.loads(LEGACY.read_bytes())
        manifest = copy.deepcopy(legacy)
        manifest["enums"][0].update(knownValues=[], knownIntegerValues=[0, 90, 180, 270])
        self.generate(manifest, root=manifest["objects"][0]["typeID"], expected=2)
        for policy in ["REJECT", "PRESERVE"]:
            manifest = copy.deepcopy(legacy)
            manifest["objects"][0].update(fields=[], unknownFieldPolicy=policy)
            self.generate(manifest, root=manifest["objects"][0]["typeID"], expected=2)
        manifest = synthetic_manifest()
        manifest["objects"][0].update(fields=[], unknownFieldPolicy="PRESERVE")
        self.generate(manifest, expected=2)
        # Absence of both enum value vocabularies is never an empty numeric enum.
        manifest = synthetic_manifest()
        manifest["enums"][0]["knownValues"] = []
        self.generate(manifest, expected=2)

    def test_nullability_arrays_and_existing_scalar_rules(self) -> None:
        schema = self.generate()
        text = schema["$defs"]["mechanics-root-v1"]["properties"]["text"]
        self.assertTrue(text["x_assetrounds_requiresNFC"])
        self.assertEqual(text["x_assetrounds_maximumUTF8Bytes"], 4)
        self.assertEqual(text["x_assetrounds_maxLengthSemantics"], "SOUND_CODE_POINT_CEILING_NOT_UTF8_BYTE_PARITY")
        for key, value in [("maybe", "okay"), ("items", []), ("signed", 9223372036854775807)]:
            current = instance()
            current[key] = value
            self.validate(current)
        for key, value in [("optional", None), ("revision", None), ("items", [1, 1]),
                           ("items", [0, 1, 2, 3]), ("items", [-1]), ("items", [True]),
                           ("blob", "not-base64"), ("blob", ""), ("blob", "YWJjZA=="),
                           ("text", "longer"), ("text", "a\u0001b"), ("text", ""),
                           ("digest", "A" * 64), ("instant", "2001-01-01"),
                           ("signed", -9223372036854775809), ("signed", 9223372036854775808)]:
            with self.subTest(key=key, value=value):
                current = instance()
                current[key] = value
                self.validate(current, expected=False)
        current = instance()
        del current["maybe"]
        self.validate(current, expected=False)

    def test_schema_limitations_remain_explicit_instead_of_false_parity(self) -> None:
        schema = self.generate()
        self.assertTrue(any("NFC" in item for item in schema["x_assetrounds_validationLimitations"]))
        # Demonstrate the independent validator's limits: annotations alone do
        # not reject decomposed NFC, 8 UTF-8 bytes in four code points, or a
        # decoded three-byte payload whose encoded length equals a two-byte one.
        for key, value in [("text", "e\u0301"), ("text", "éééé"), ("blob", "YWJj")]:
            current = instance()
            current[key] = value
            self.validate(current)

    def test_preserved_strings_keep_source_unicode_without_inherited_constraints(self) -> None:
        schema = self.generate(preserved_manifest())
        shape = schema["$defs"]["mechanics-root-v1"]["properties"]["preserved"]
        self.assertEqual(shape["type"], "string")
        self.assertEqual(shape["maxLength"], 4)
        self.assertEqual(shape["x_assetrounds_maximumUTF8Bytes"], 4)
        self.assertEqual(shape["x_assetrounds_stringNormalization"], "PRESERVE_SOURCE_UNICODE")
        for keyword in ["pattern", "minLength", "x_assetrounds_requiresNFC", "x_assetrounds_forbiddenUnicodeScalarClasses"]:
            self.assertNotIn(keyword, shape)
        for value in ["", "e\u0301", "a\u0000b", "\u202a", "\ufdd0", "😀", "éééé"]:
            with self.subTest(value=value):
                current = preserved_instance()
                current["preserved"] = value
                self.validate(current)
        for value in ["12345", True, None, 1, {}]:
            current = preserved_instance()
            current["preserved"] = value
            self.validate(current, expected=False)
        current = preserved_instance()
        current["textarray"] = ["e\u0301\u0001", "arbitrary source text" * 64]
        self.validate(current)
        for value in [[True], [None], ["1", "2", "3", "4", "5"]]:
            current["textarray"] = value
            self.validate(current, expected=False)

    def test_string_maps_preserve_keys_values_and_have_no_implied_count_cap(self) -> None:
        schema = self.generate(preserved_manifest())
        shape = schema["$defs"]["mechanics-root-v1"]["properties"]["reasons"]
        self.assertEqual(shape["type"], "object")
        self.assertEqual(shape["propertyNames"]["maxLength"], 256)
        self.assertEqual(shape["propertyNames"]["x_assetrounds_maximumUTF8Bytes"], 256)
        self.assertEqual(shape["additionalProperties"]["maxLength"], 512)
        self.assertEqual(shape["additionalProperties"]["x_assetrounds_maximumUTF8Bytes"], 512)
        for keyword in ["maxProperties", "minProperties", "required"]:
            self.assertNotIn(keyword, shape)
        for item in [shape["propertyNames"], shape["additionalProperties"]]:
            self.assertNotIn("pattern", item)
            self.assertNotIn("x_assetrounds_requiresNFC", item)
        for reasons in [{}, {"x" * 256: "y" * 512}, {"e\u0301\u0000": "value\t\u202a"},
                        {str(index): "reason" for index in range(300)}]:
            current = preserved_instance()
            current["reasons"] = reasons
            self.validate(current)
        for reasons in [{"x" * 257: "value"}, {"key": "y" * 513}, {"key": None},
                        {"key": True}, {"key": 42}, {"key": {}}, [], None]:
            current = preserved_instance()
            current["reasons"] = reasons
            self.validate(current, expected=False)

    def test_string_map_optional_bounds_and_explicit_count_cap(self) -> None:
        manifest = preserved_manifest()
        reason = next(item for item in manifest["objects"][1]["fields"] if item["jsonName"] == "reasons")
        del reason["maximumKeyUTF8Bytes"]
        del reason["maximumUTF8Bytes"]
        schema = self.generate(manifest)
        shape = schema["$defs"]["mechanics-root-v1"]["properties"]["reasons"]
        self.assertNotIn("maxLength", shape["propertyNames"])
        self.assertNotIn("maxLength", shape["additionalProperties"])
        self.assertNotIn("maxProperties", shape)
        current = preserved_instance()
        current["reasons"] = {"x" * 257: "y" * 513}
        self.validate(current)
        reason["maximumItems"] = 1
        schema = self.generate(manifest)
        self.assertEqual(schema["$defs"]["mechanics-root-v1"]["properties"]["reasons"]["maxProperties"], 1)
        self.validate(current)
        current["reasons"]["second"] = "reason"
        self.validate(current, expected=False)
        current["reasons"] = {}
        self.validate(current)

    def test_preserved_string_map_wrong_metadata_and_bounds_rejected(self) -> None:
        cases = []
        for kind in ["STRING_MAP", "PRESERVED_STRING"]:
            forbidden = [
                {"referencedTypeID": "child-v1"}, {"arrayElementKind": "STRING"},
                {"minimumInteger": 0}, {"maximumInteger": 1},
                {"minimumUnsignedInteger": 0}, {"maximumUnsignedInteger": 1},
                {"ordered": True}, {"uniqueItems": True},
            ]
            if kind == "PRESERVED_STRING":
                forbidden += [{"maximumKeyUTF8Bytes": 1}, {"maximumItems": 1}]
            for extra in forbidden:
                cases.append(self.mutate_field("text", kind=kind, **extra))
        for key in ["maximumKeyUTF8Bytes", "maximumUTF8Bytes", "maximumItems"]:
            for value in [None, 0, -1, True, 1.0, 9223372036854775808]:
                cases.append(self.mutate_field("text", kind="STRING_MAP", **{key: value}))
        for name in ["revision", "text", "date", "items", "child"]:
            cases.append(self.mutate_field(name, maximumKeyUTF8Bytes=1))
        cases.append(self.mutate_field("items", arrayElementKind="STRING_MAP"))
        cases.append(self.mutate_field("items", arrayElementKind="PRESERVED_STRING", maximumUTF8Bytes=1))
        for index, manifest in enumerate(cases):
            with self.subTest(index=index):
                self.generate(manifest, expected=2)

    def test_preserved_kinds_key_metadata_and_new_codec_are_schema2_only(self) -> None:
        legacy = json.loads(LEGACY.read_bytes())
        for item in [field("value", "PRESERVED_STRING"), field("value", "STRING_MAP"),
                     field("value", "STRING_MAP", maximumKeyUTF8Bytes=256),
                     field("value", "STRING", maximumKeyUTF8Bytes=256),
                     field("value", "ARRAY", arrayElementKind="PRESERVED_STRING", maximumItems=1)]:
            manifest = copy.deepcopy(legacy)
            manifest["objects"][0]["fields"] = [item]
            self.generate(manifest, root=manifest["objects"][0]["typeID"], expected=2)
        manifest = synthetic_manifest()
        manifest["codec"]["stringNormalization"] = "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED"
        self.generate(manifest, expected=2)
        manifest = copy.deepcopy(legacy)
        manifest["codec"]["stringNormalization"] = synthetic_manifest()["codec"]["stringNormalization"]
        self.generate(manifest, root=manifest["objects"][0]["typeID"], expected=2)

    def test_unknown_metadata_at_every_record_boundary_is_rejected(self) -> None:
        for path in [(), ("codec",), ("compatibility",), ("objects", 0), ("objects", 1, "fields", 0),
                     ("enums", 0), ("reportSectionRegistry",), ("reportSectionRegistry", "sections", 0)]:
            with self.subTest(path=path):
                manifest = synthetic_manifest()
                target = manifest
                for part in path:
                    target = target[part]
                target["unknown"] = True
                self.generate(manifest, expected=2)

    def test_missing_required_and_explicit_null_metadata_is_rejected(self) -> None:
        for path in [("schemaVersion",), ("codec", "timeEncoding"), ("compatibility", "maximumReaderVersion"),
                     ("objects", 1, "fields", 0, "required"), ("enums", 0, "policy"),
                     ("reportSectionRegistry", "registryVersion")]:
            for null in [False, True]:
                with self.subTest(path=path, null=null):
                    manifest = synthetic_manifest()
                    target = manifest
                    for part in path[:-1]:
                        target = target[part]
                    if null:
                        target[path[-1]] = None
                    else:
                        del target[path[-1]]
                    self.generate(manifest, expected=2)
        for key in ["minimumInteger", "maximumInteger", "minimumUnsignedInteger", "maximumUnsignedInteger",
                    "maximumUTF8Bytes", "maximumItems", "arrayElementKind", "referencedTypeID"]:
            self.generate(self.mutate_field("revision", **{key: None}), expected=2)

    def test_duplicate_keys_at_root_and_nested_boundary_are_rejected(self) -> None:
        raw = json.dumps(synthetic_manifest()).encode("utf-8")
        for duplicate in [raw.replace(b'"schemaVersion": 2', b'"schemaVersion": 2, "schemaVersion": 2', 1),
                          raw.replace(b'"maximumUnsignedInteger": 18446744073709551614',
                                      b'"maximumUnsignedInteger": 0, "maximumUnsignedInteger": 18446744073709551614', 1)]:
            self.generate(raw=duplicate, expected=2)

    def test_numeric_metadata_rejects_bool_float_exponent_overflow_and_wrong_kind(self) -> None:
        for value in [True, 1.0, -1, 18446744073709551616, "1"]:
            self.generate(self.mutate_field("revision", minimumUnsignedInteger=value), expected=2)
        for changes in [{"minimumUnsignedInteger": 2, "maximumUnsignedInteger": 1},
                        {"minimumInteger": 0}, {"maximumUTF8Bytes": 2}, {"maximumItems": 1},
                        {"ordered": True}, {"uniqueItems": True}, {"required": 1}]:
            self.generate(self.mutate_field("revision", **changes), expected=2)
        for value in [True, 1.0, -9223372036854775809, 9223372036854775808]:
            self.generate(self.mutate_field("signed", minimumInteger=value), expected=2)
        for name, change in [("date", {"minimumInteger": 0}), ("date", {"maximumUnsignedInteger": 1}),
                             ("text", {"maximumUTF8Bytes": 0}), ("optional", {"nullable": True}),
                             ("signed", {"minimumInteger": 2, "maximumInteger": 1}),
                             ("revision", {"referencedTypeID": "child-v1"})]:
            self.generate(self.mutate_field(name, **change), expected=2)
        raw = json.dumps(synthetic_manifest()).encode("utf-8")
        for token in [b"9.007199254740993e15", b"1e400", b"NaN", b"Infinity"]:
            self.generate(raw=raw.replace(b"9007199254740993", token), expected=2)

    def test_version_codec_and_reader_incompatibility_rejected(self) -> None:
        for path, value in [(('schemaVersion',), 3), (('schemaVersion',), True),
                            (('codec', 'codecVersion'), 1), (('codec', 'codecVersion'), True),
                            (('codec', 'formatAssertion'), 0), (('codec', 'formatAssertion'), True),
                            (('codec', 'timeEncoding'), "UTC_RFC3339_MILLISECONDS_Z"),
                            (('compatibility', 'minimumReaderVersion'), 1),
                            (('compatibility', 'maximumReaderVersion'), 1),
                            (('compatibility', 'publishedVersionsImmutable'), 1),
                            (('persistentContractSchema',), "FUTURE")]:
            manifest = synthetic_manifest()
            target = manifest
            for part in path[:-1]:
                target = target[part]
            target[path[-1]] = value
            self.generate(manifest, expected=2)
        legacy = json.loads(LEGACY.read_bytes())
        for kind in ["UNSIGNED_INTEGER", "REFERENCE_DATE_SECONDS"]:
            for as_array in [False, True]:
                manifest = copy.deepcopy(legacy)
                item = field("extension", kind)
                if as_array:
                    item = field("extension", "ARRAY", arrayElementKind=kind, maximumItems=1)
                manifest["objects"][0]["fields"] = [item]
                self.generate(manifest, root=manifest["objects"][0]["typeID"], expected=2)

    def test_reference_closure_root_and_array_shape_rejected(self) -> None:
        for name, changes in [("child", {"referencedTypeID": "missing-v1"}),
                               ("child", {"referencedTypeID": "closed-v1"}),
                               ("closed", {"referencedTypeID": "child-v1"}),
                               ("items", {"arrayElementKind": "OBJECT"}),
                               ("items", {"arrayElementKind": "ARRAY"}),
                               ("items", {"arrayElementKind": "FUTURE"}),
                               ("items", {"maximumItems": 0}), ("items", {"maximumItems": True}),
                               ("items", {"minimumUnsignedInteger": 0})]:
            self.generate(self.mutate_field(name, **changes), expected=2)
        for key in ["referencedTypeID"]:
            manifest = synthetic_manifest()
            del manifest["objects"][1]["fields"][2][key]
            self.generate(manifest, expected=2)
        for key in ["arrayElementKind", "maximumItems"]:
            manifest = synthetic_manifest()
            del manifest["objects"][1]["fields"][7][key]
            self.generate(manifest, expected=2)
        self.generate(root="absent-v1", expected=2)
        self.generate(root="closed-v1", expected=2)
        self.generate(schema_id="relative/schema.json", expected=2)
        self.generate(schema_id=SCHEMA_ID + "#fragment", expected=2)

    def test_closed_recursive_graph_and_referenced_array_elements_compile(self) -> None:
        manifest = synthetic_manifest()
        child = manifest["objects"][0]
        child["fields"].append(field("next", "OBJECT", referencedTypeID="child-v1", required=False))
        for kind, reference, values in [
            ("OBJECT", "child-v1", [{"flag": True, "next": {"flag": False}}]),
            ("ENUM", "closed-v1", ["A", "B"]),
            ("REFERENCE_DATE_SECONDS", None, [-0.125, 123456789.12345679]),
        ]:
            with self.subTest(kind=kind):
                selected = copy.deepcopy(manifest)
                items = selected["objects"][1]["fields"][7]
                items["arrayElementKind"] = kind
                if reference is not None:
                    items["referencedTypeID"] = reference
                self.generate(selected)
                current = instance()
                current["items"] = values
                self.validate(current)
                current["items"] = [True]
                self.validate(current, expected=False)

    def test_identity_ordering_and_registry_validation(self) -> None:
        cases = []
        for key in ["objects", "enums"]:
            manifest = synthetic_manifest()
            manifest[key].reverse()
            cases.append(manifest)
            manifest = synthetic_manifest()
            manifest[key].insert(0, copy.deepcopy(manifest[key][0]))
            cases.append(manifest)
        manifest = synthetic_manifest()
        manifest["enums"][0]["typeID"] = "child-v1"
        cases.append(manifest)
        for changes in [{"fieldID": "Revision"}, {"fieldID": "x/y"}, {"jsonName": "bad-name"},
                        {"fieldID": "signed"}, {"jsonName": "text"}, {"kind": "FUTURE"}]:
            cases.append(self.mutate_field("revision", **changes))
        for known in [["B", "A"], ["A", "A"], [], ["e\u0301"], ["A\u0000"], [None]]:
            manifest = synthetic_manifest()
            manifest["enums"][0]["knownValues"] = known
            cases.append(manifest)
        for changes in [{"order": 10}, {"required": False}, {"privacyClass": "UNKNOWN"},
                        {"supportedFormats": ["PDF", "OPEN_JSON"]}, {"version": True}]:
            manifest = synthetic_manifest()
            manifest["reportSectionRegistry"]["sections"][0].update(changes)
            cases.append(manifest)
        for index, manifest in enumerate(cases):
            with self.subTest(index=index):
                self.generate(manifest, expected=2)

    def test_valid_grammar_does_not_inherit_old_filename_identity_restrictions(self) -> None:
        manifest = synthetic_manifest()
        manifest["objects"][0]["typeID"] = "child._v1"
        manifest["objects"][1]["fields"][2]["referencedTypeID"] = "child._v1"
        manifest["objects"][0]["fields"][0]["jsonName"] = "0_flag"
        self.generate(manifest)
        current = instance()
        current["child"] = {"0_flag": True}
        self.validate(current)

    def test_rejected_input_does_not_replace_an_existing_output(self) -> None:
        sentinel = b"existing output remains owned\n"
        self.output.write_bytes(sentinel)
        self.generate(self.mutate_field("revision", maximumUnsignedInteger=UINT64_MAX + 1), expected=2)
        self.assertEqual(self.output.read_bytes(), sentinel)
        raw = json.dumps(synthetic_manifest()).encode("utf-8")
        self.manifest_path.write_bytes(raw)
        result = run_python(COMPILER, "--manifest", self.manifest_path, "--root-type-id", "mechanics-root-v1",
                            "--schema-id", SCHEMA_ID, "--output", self.manifest_path)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.manifest_path.read_bytes(), raw)


if __name__ == "__main__":
    unittest.main(verbosity=2)
