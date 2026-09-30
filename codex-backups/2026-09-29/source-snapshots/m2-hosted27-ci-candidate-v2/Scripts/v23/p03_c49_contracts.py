#!/usr/bin/env python3
"""Deterministic work-resource contract tooling for V23-P03-C49."""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

CARD = "V23-P03-C49"
TITLE = "Append-only manual duration, material, quantity, and direct-cost truth with optional stock references"
REGISTER_ORDINAL = 79
BASE_HEAD = "f968cab80d2f1b66b633c15d84f7ab50ad85d8b0"
BASE_TREE = "84c61b4b40e6c3a97de36e9fdcb8d8fba922cd78"
COORDINATION_HEAD = "4de3a951a7b96ae9dbb118ac24e951f304db1cf1"
COORDINATION_TREE = "bf06d7f59f0116674c58465ae249c560128798d5"
COORDINATION_CAS_SEQUENCE = 335
CONTEXT_DIGEST = "b20b0d9c7a25dc79aa0b0f270ea32afcf3c2d45cc45313ca8513434bc4684976"
FENCE_DIGEST = "1f98c92b714a1e4dbecc689efa070f53bbd679fbbc681e5f37da49bdda53d431"
PREREQUISITE_DIGEST = "f564bd037fc70b4a28b0a9fec08f782d7757d3ba719bafc462e19964badbcccf"
HYDRATION_TRANSITION_DIGEST = "2706b785d36ebb30733793fd1460fd6030c0dc3907f66095138a3b8a50c5876b"
COORDINATION_LEDGER_DIGEST = "227365f2c84f602ec0db663ec6068d669f43b8adf6a5bd0ce136a0b948a7d2d4"
COORDINATION_PROJECTION_DIGEST = "7d47a11ecb9d3fc2deeaff07b41f65204b795c8980dadab2934bdd823e3d4f54"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

DOSSIER_SHA256 = "c5e88d34bffbc53638519694e72e3dd248bdee57e9a131be464fb41a0c8889c9"
DOSSIER_BYTES = 7492
INHERITED_SHA256 = "a1e531e13222c3fe16b97c85819190e82c984dd89d4b7ce64146da99d74e86c0"
INHERITED_BYTES = 5555
REGISTER_ROW_SHA256 = "656e2afd580f67ef8eefb5f788e97ef8fd6294f7735b6485a1c236f511fc838a"
REGISTER_ROW_BYTES = 290
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217
ISO_LIST_ONE_PUBLISHED = "2026-01-01"
ISO_LIST_ONE_RAW_BYTES = 47463
ISO_LIST_ONE_SHA256 = "838dfb991648cf36df939edd5fe3811737962b75a32252847d239cedd1e291c9"
ISO_LIST_ONE_NUMERIC_MINOR_UNIT_CODE_COUNT = 165

SCHEMA_PATH = "Scripts/v23/work-resource.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C49WorkResourceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C49WorkResourceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C49BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C49-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c49_contracts.py",
    "Scripts/v23/generate_p03_c49_contracts.py",
    "Scripts/v23/verify_p03_c49_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/WorkResources/WorkResourceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkResourcePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/WorkResources/WorkResourceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/WorkResources/WorkResourceLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_56WorkResourceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/WorkResources/V22P03C49WorkResourceCorpusV1.json",
)

_C48_PATH = Path(__file__).with_name("p03_c48_contracts.py")
_C48_SHA256 = "fac66c67d973ada11e9281ce5361416a46c62f83afafe62652afb5693926ceae"


def _c48_existing() -> tuple[str, ...]:
    if not _C48_PATH.is_file() or hashlib.sha256(_C48_PATH.read_bytes()).hexdigest() != _C48_SHA256:
        raise ValueError("sealed C48 tooling inventory differs")
    spec = importlib.util.spec_from_file_location("_sealed_p03_c48_contracts", _C48_PATH)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load sealed C48 tooling inventory")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return tuple(module.EXISTING_PATHS) + tuple(module.IMPLEMENTATION_PATHS)


EXISTING_PATHS = _c48_existing()
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, *GENERATED_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
FLAGS = {name: False for name in (
    "native", "hosted", "physical", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "adoptionEvidence",
    "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution",
)}
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
LIFECYCLE_COVERAGE = (
    "MIGRATION", "BACKUP", "REPLACE_RESTORE", "CLONE_FORK", "JOURNAL_REPLAY",
    "SEARCH_REBUILD", "DELETE_ERASE", "REPORT_EXPORT", "COMPATIBILITY", "FORWARD_FIX",
)
EXCLUDED_CLAIMS = (
    "inventory", "timer", "payroll", "accounting", "tax", "markup", "estimate",
    "invoice", "currency conversion", "second writer", "ledger", "renderer",
)


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"


def pretty(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_text(root, relative), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + relative)
    return value


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(["git", "cat-file", "-e", f"{BASE_HEAD}:{relative}"], cwd=root,
                          capture_output=True).returncode == 0


def _git_blob(root: Path, relative: str) -> bytes:
    result = subprocess.run(["git", "show", f"{BASE_HEAD}:{relative}"], cwd=root, capture_output=True)
    if result.returncode:
        raise ValueError("base blob absent:" + relative)
    return result.stdout


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    result = set()
    for raw in subprocess.run(["git", "diff", "--name-only", BASE_HEAD, "--"], cwd=root,
                              check=True, capture_output=True, text=True).stdout.splitlines():
        if raw.strip():
            result.add(raw.strip().replace("\\", "/"))
    for raw in subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=root,
                              check=True, capture_output=True, text=True).stdout.splitlines():
        if raw.strip():
            result.add(raw.strip().replace("\\", "/"))
    return tuple(sorted(result))


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"{label} missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I | re.S) is None]
    if missing:
        raise ValueError(f"{label} missing patterns:" + ",".join(missing))


def _assert_sources(root: Path) -> None:
    contracts = _text(root, IMPLEMENTATION_PATHS[0])
    models = _text(root, IMPLEMENTATION_PATHS[1])
    coordinator = _text(root, IMPLEMENTATION_PATHS[2])
    lifecycle = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    fixture = _json(root, IMPLEMENTATION_PATHS[5])

    _require_tokens(contracts, (
        "WorkResourceEntryV1", "ManualDurationV1", "ExactDecimalQuantityV1", "ExactMoneyAmountV1",
        "LocalPartReferenceSnapshotV1", "WORK_PACKET", "CORRECTIVE_WORK", "SUPERSEDED", "VOIDED",
        "WorkspaceWriterV1",
    ), "C49 contracts")
    registry = _iso_registry(contracts)
    _require_patterns(contracts, (
        r"1\s*\.\.\.?\s*10_?080", r"scale\s*[^\n]{0,100}3", r"50", r"ISO.?4217",
        r"workspace", r"expectedRevision", r"ActorSnapshotV1", r"recordedAt",
    ), "C49 contract bounds")
    if re.search(r"\b(Float|Double)\b", contracts + models):
        raise ValueError("C49 exact arithmetic uses Float/Double")
    all_source = "\n".join((contracts, models, coordinator, lifecycle))
    source_and_tests = all_source + "\n" + tests
    _require_tokens(models, ("ManualWorkResourceRecordRow", "canonicalData", "appendOnlyHistory", "WorkResourceMutationReceiptV1"), "C49 persistence")
    _require_tokens(coordinator, ("expectedRevision", "append", "supersedesEntryID", "void", "commitWorkResource"), "C49 coordinator")
    _require_patterns(source_and_tests, (r"zero.?write|read.?only|preview", r"internal.?only|customer.?safe|external", r"formula|control"), "C49 privacy/export")
    _require_tokens(all_source, (
        "validateMigration", "snapshotForBackup", "func restore", "func clone", "func fork", "func delete",
        "func erase", "rebuildSearch", "func search", "func report", "func export",
        "forwardFixPreservesReleasedCanonicalRows", "directCostTotalsRemainSeparateByCurrency",
        "WorkResourceMaterialTotalV1",
    ), "C49 lifecycle")
    _require_patterns(all_source, (r"expectedRevision\.addingReportingOverflow", r"materials\.count\s*<=\s*50", r"description.*unit"), "C49 lifecycle semantics")
    _require_patterns(tests, (r"test[^\n]*G01", r"test[^\n]*A01", r"test[^\n]*H01", r"test[^\n]*I01", r"test[^\n]*R01"), "C49 evidence tests")
    _require_tokens(tests, (
        "ManualDurationV1(minutes: 0)", "ManualDurationV1(minutes: 10_081)",
        "ExactDecimalQuantityV1(mantissa: 0, scale: 0)", "ExactDecimalQuantityV1(mantissa: Int64.max, scale: 3)",
        "ExactMoneyAmountV1(mantissa: 0", "ExactMoneyAmountV1(mantissa: -1", "fifty + [",
        "C49WorkResourceProjectionFailureV1", ".arithmeticOverflow", "MutationJournalFailureInjectionV1",
        "C49WorkResourceRecoveryBoundaryV1", "C49WorkResourceRestoreIdentityPolicyV1",
        "V37BackupWorkResourceRecordV1", "WorkResourceBackupSnapshotV1",
        "C49WorkResourceReportProjectionV1", "C49WorkResourceSearchBoundaryV1",
        "C49WorkResourceDiagnosticBoundaryV1", "C49FormulaSafeCSVV1",
        "testV23P03C49CurrentHeadProjectionNeverDoubleCountsReferencedPredecessor",
        "testV23P03C49G01PinnedISO4217ListOneUniverseAndMinorUnitScales",
        'for code in ["BHD", "KWD"]', 'minorUnitScale: 3',
        'for code in ["CLF", "UYW"]', 'minorUnitScale: 4',
        'iso4217ListOnePublished, "2026-01-01"', 'iso4217ListOneRawByteCount, 47_463',
        ISO_LIST_ONE_SHA256, 'iso4217ListOneNumericMinorUnitCodeCount, 165',
    ), "C49 tests")
    encoded = canonical(fixture).decode()
    _require_tokens(encoded, EVIDENCE_IDS, "C49 fixture evidence")
    _require_tokens(encoded, (
        '"appendOnly":true', '"directCostVisibility":"INTERNAL_ONLY"', '"liveInventoryReference":false',
        '"mixedCurrencyAggregation":false', '"durationMinutes":[1,10080]',
        '"materialLineCount":50', '"mantissa":9223372036854775807',
        '"DIRECT_COST_CUSTOMER_LEAKAGE"', '"DIVERGENT_SAME_MUTATION_QUARANTINED"',
        '"REPLACE_RESTORE_PRESERVES_CANONICAL_BYTES"', '"CLONE_REBINDS_WORKSPACE"',
        '"FORK_REBINDS_WORKSPACE"', '"ERASE_REMOVES_ALL"', '"formulaPrefixes"',
    ), "C49 fixture")
    forbidden = re.compile(r"\b(payroll|invoice|tax calculation|markup calculation|live timer|background timer|currency conversion)\b", re.I)
    for label, body in (("contracts", contracts), ("models", models), ("coordinator", coordinator), ("lifecycle", lifecycle)):
        # Unsupported terms may occur only as explicit denials.
        for match in forbidden.finditer(body):
            window = body[max(0, match.start() - 240):match.end() + 120].lower()
            if re.search(r"\b(no|not|unsupported|excluded|never)\b", window) is None:
                raise ValueError(f"C49 unsupported claim in {label}:{match.group(0)}")


def _iso_registry(contracts: str) -> dict[str, int]:
    match = re.search(r"iso4217MinorScales\s*:\s*\[String:\s*Int\]\s*=\s*\[(.*?)\n\s*\]", contracts, re.S)
    if match is None:
        raise ValueError("C49 ISO registry declaration absent")
    pairs = re.findall(r'"([A-Z]{3})"\s*:\s*([0-9]+)', match.group(1))
    registry = {code: int(scale) for code, scale in pairs}
    if len(pairs) != len(registry) or len(registry) != ISO_LIST_ONE_NUMERIC_MINOR_UNIT_CODE_COUNT:
        raise ValueError("C49 ISO registry cardinality or duplicate")
    if "N.A." in match.group(1) or any(scale < 0 or scale > 4 for scale in registry.values()):
        raise ValueError("C49 ISO registry nonnumeric or invalid scale")
    expected = {"BHD": 3, "KWD": 3, "CLF": 4, "UYW": 4}
    if {code: registry.get(code) for code in expected} != expected:
        raise ValueError("C49 ISO registry concrete scale pins")
    _require_tokens(contracts, (
        f'iso4217ListOnePublished="{ISO_LIST_ONE_PUBLISHED}"',
        "iso4217ListOneRawByteCount=47_463",
        f'iso4217ListOneSHA256="{ISO_LIST_ONE_SHA256}"',
        "iso4217ListOneNumericMinorUnitCodeCount=165",
    ), "C49 ISO source pins")
    return dict(sorted(registry.items()))


def assert_scaffold(root: Path) -> None:
    if len(EXISTING_PATHS) != 131 or len(NEW_PATHS) != 14 or len(PATH_FENCE) != 145:
        raise ValueError("C49 fence cardinality")
    if len(set(PATH_FENCE)) != len(PATH_FENCE):
        raise ValueError("C49 duplicate fence path")
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C49 new path exists at base")
    if any(not _base_exists(root, path) for path in EXISTING_PATHS):
        raise ValueError("C49 existing path absent at base")
    for path in SCRIPT_PATHS:
        ast.parse(_text(root, path), filename=path)
    if any(FLAGS.values()):
        raise ValueError("C49 provisional flag true")
    _assert_sources(root)


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "directPrerequisites": ["V23-P03-C25"],
    }


def schema_document(root: Path) -> dict[str, Any]:
    registry = _iso_registry(_text(root, IMPLEMENTATION_PATHS[0]))
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "urn:assetrounds:v23:p03:c49:work-resource:v1",
        "title": "WorkResourceEntryV1",
        "type": "object", "additionalProperties": False,
        "required": [
            "schemaVersion", "entryID", "workspaceID", "subject", "actor", "materials", "visibility",
            "disposition", "recordedAt", "expectedRevision", "revision", "mutationID", "entrySHA256",
        ],
        "properties": {
            "schemaVersion": {"const": 1}, "entryID": {"$ref": "#/$defs/uuid"},
            "workspaceID": {"$ref": "#/$defs/workspaceID"}, "subject": {"$ref": "#/$defs/subject"},
            "actor": {"$ref": "#/$defs/actorSnapshot"}, "duration": {"$ref": "#/$defs/duration"},
            "materials": {"type": "array", "maxItems": 50, "items": {"$ref": "#/$defs/material"}},
            "directCost": {"$ref": "#/$defs/directCost"},
            "visibility": {"enum": ["INTERNAL_ONLY", "CUSTOMER_SAFE"]},
            "disposition": {"enum": ["ACTIVE", "SUPERSEDED", "VOIDED_WITH_REASON", "REVERSED"]},
            "voidReason": {"$ref": "#/$defs/longText"}, "recordedAt": {"type": "number"},
            "expectedRevision": {"type": "integer", "minimum": 0, "maximum": 18446744073709551615},
            "revision": {"type": "integer", "minimum": 1, "maximum": 18446744073709551615},
            "supersedesEntryID": {"$ref": "#/$defs/uuid"}, "supersedesEntrySHA256": {"$ref": "#/$defs/digest"},
            "mutationID": {"$ref": "#/$defs/uuid"}, "entrySHA256": {"$ref": "#/$defs/digest"},
        },
        "allOf": [
            {"anyOf": [{"required": ["duration"]}, {"properties": {"materials": {"minItems": 1}}}, {"required": ["directCost"]}]},
            {"if": {"properties": {"expectedRevision": {"const": 0}}, "required": ["expectedRevision"]},
             "then": {"not": {"anyOf": [{"required": ["supersedesEntryID"]}, {"required": ["supersedesEntrySHA256"]}]}},
             "else": {"required": ["supersedesEntryID", "supersedesEntrySHA256"]}},
            {"if": {"properties": {"disposition": {"const": "VOIDED_WITH_REASON"}}, "required": ["disposition"]},
             "then": {"required": ["voidReason"]}, "else": {"not": {"required": ["voidReason"]}}},
        ],
        "$defs": {
            "uuid": {"type": "string", "format": "uuid", "not": {"const": "00000000-0000-0000-0000-000000000000"}},
            "digest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "shortText": {"type": "string", "minLength": 1, "maxLength": 160, "pattern": "^[^\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]+$"},
            "unitText": {"type": "string", "minLength": 1, "maxLength": 24, "pattern": "^[^\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]+$"},
            "longText": {"type": "string", "minLength": 1, "maxLength": 1024, "pattern": "^[^\\u0000-\\u001f\\u007f\\u202a-\\u202e\\u2066-\\u2069]+$"},
            "workspaceID": {"type": "object", "additionalProperties": False, "required": ["rawValue"], "properties": {"rawValue": {"$ref": "#/$defs/uuid"}}},
            "subject": {"type": "object", "additionalProperties": False,
                "required": ["workspaceID", "kind", "subjectID", "subjectRevision", "subjectSHA256"],
                "properties": {"workspaceID": {"$ref": "#/$defs/workspaceID"}, "kind": {"enum": ["WORK_PACKET", "CORRECTIVE_WORK"]},
                    "subjectID": {"$ref": "#/$defs/uuid"}, "subjectRevision": {"type": "integer", "minimum": 1, "maximum": 18446744073709551615}, "subjectSHA256": {"$ref": "#/$defs/digest"}}},
            "localActor": {"type": "object", "additionalProperties": False,
                "required": ["schemaVersion", "actorReferenceID", "workspaceID", "displayName"],
                "properties": {"schemaVersion": {"const": 1}, "actorReferenceID": {"$ref": "#/$defs/uuid"}, "workspaceID": {"$ref": "#/$defs/workspaceID"},
                    "partyID": {"$ref": "#/$defs/uuid"}, "displayName": {"$ref": "#/$defs/shortText"}}},
            "actorSnapshot": {"type": "object", "additionalProperties": False,
                "required": ["schemaVersion", "snapshotID", "workspaceID", "actor", "responsibility", "displayNameAtTime", "capturedAt", "snapshotSHA256"],
                "properties": {"schemaVersion": {"const": 1}, "snapshotID": {"$ref": "#/$defs/uuid"}, "workspaceID": {"$ref": "#/$defs/workspaceID"},
                    "actor": {"$ref": "#/$defs/localActor"}, "responsibility": {"enum": ["RECORDED_BY", "PERFORMED_BY", "OBSERVED_BY", "REVIEWED_BY", "VERIFIED_BY", "APPROVED_BY", "ACKNOWLEDGED_BY", "ASSIGNED_TO", "WITNESSED_BY"]},
                    "displayNameAtTime": {"$ref": "#/$defs/shortText"}, "capturedAt": {"type": "number"}, "snapshotSHA256": {"$ref": "#/$defs/digest"}}},
            "duration": {"type": "object", "additionalProperties": False, "required": ["minutes"], "properties": {"minutes": {"type": "integer", "minimum": 1, "maximum": 10080}}},
            "decimal": {"type": "object", "additionalProperties": False, "required": ["mantissa", "scale"],
                "properties": {"mantissa": {"type": "integer", "minimum": 1, "maximum": 9223372036854775807}, "scale": {"type": "integer", "minimum": 0, "maximum": 3}}},
            "money": {"type": "object", "additionalProperties": False, "required": ["mantissa", "currencyCode", "minorUnitScale"],
                "properties": {"mantissa": {"type": "integer", "minimum": 1, "maximum": 9223372036854775807}},
                "oneOf": [{"properties": {"currencyCode": {"const": code}, "minorUnitScale": {"const": scale}}, "required": ["currencyCode", "minorUnitScale"]} for code, scale in registry.items()]},
            "localPartReference": {"type": "object", "additionalProperties": False, "required": ["partID", "partRevision", "partSHA256", "displayName"],
                "properties": {"partID": {"$ref": "#/$defs/uuid"}, "partRevision": {"type": "integer", "minimum": 1, "maximum": 18446744073709551615}, "partSHA256": {"$ref": "#/$defs/digest"}, "displayName": {"$ref": "#/$defs/shortText"}}},
            "material": {"type": "object", "additionalProperties": False,
                "required": ["lineID", "description", "quantity"],
                "properties": {"lineID": {"$ref": "#/$defs/uuid"}, "description": {"$ref": "#/$defs/shortText"}, "quantity": {"$ref": "#/$defs/decimal"}, "unit": {"$ref": "#/$defs/unitText"}, "localPartReference": {"$ref": "#/$defs/localPartReference"}}},
            "directCost": {"type": "object", "additionalProperties": False, "required": ["amount"],
                "properties": {"amount": {"$ref": "#/$defs/money"}, "note": {"$ref": "#/$defs/longText"}}},
        },
    }


def _sealed(body: dict[str, Any]) -> dict[str, Any]:
    body = dict(body)
    body["artifactDigest"] = sha256_bytes(canonical(body))
    return body


def contract_document(root: Path) -> dict[str, Any]:
    registry = _iso_registry(_text(root, IMPLEMENTATION_PATHS[0]))
    return _sealed({
        "schema": "V23P03C49WorkResourceContractV1", "schemaVersion": 1, "cardID": CARD, "title": TITLE,
        "authority": authority(), "appendOnlyTruth": "MANUAL_DURATION_MATERIAL_QUANTITY_AND_DIRECT_COST_WITH_SOURCE_PROVENANCE",
        "optionalStockReference": "LOCAL_PART_REFERENCE_SNAPSHOT_ONLY",
        "states": ["ACTIVE", "SUPERSEDED", "VOIDED_WITH_REASON", "REVERSED"], "subjects": ["WORK_PACKET", "CORRECTIVE_WORK"],
        "lifecycleCoverage": list(LIFECYCLE_COVERAGE), "unsupportedClaims": list(EXCLUDED_CLAIMS),
        "privacy": {"default": "INTERNAL_ONLY", "externalRelease": "EXPLICIT_PROFILE_AND_PREVIEW", "csv": "FORMULA_AND_CONTROL_NEUTRAL"},
        "aggregation": {"currenciesRemainSeparate": True, "materialKey": ["exactDescription", "exactUnit"]},
        "iso4217ListOne": {
            "published": ISO_LIST_ONE_PUBLISHED, "rawByteCount": ISO_LIST_ONE_RAW_BYTES,
            "rawSHA256": ISO_LIST_ONE_SHA256, "numericMinorUnitCodeCount": len(registry),
            "nonNumericMinorUnitDisposition": "N.A. EXCLUDED",
            "registryDigest": sha256_bytes(canonical(registry)),
            "concreteScalePins": {"BHD": 3, "KWD": 3, "CLF": 4, "UYW": 4},
        },
        "constructorInvariantsBeyondJSONSchema": [
            "workspaceID equals subject.workspaceID, actor.workspaceID, and actor.actor.workspaceID",
            "actor.actor.displayName equals actor.displayNameAtTime and both actor digests validate",
            "revision equals expectedRevision plus one without UInt64 overflow",
            "material lineID values are unique and stored in canonical lineID order",
            "entrySHA256 equals the canonical constructor-basis digest",
            "successor predecessor ID and SHA bind the exact prior entry; clone/fork supplies the mapped predecessor SHA",
            "recordedAt and capturedAt decode as finite canonical millisecond dates",
            "all UUID values are nonzero and all hashes are lowercase SHA-256",
        ],
        "downgradeDisposition": "FORWARD_FIX_PRESERVE_APPEND_ONLY_WORK_RESOURCE_ROWS_AND_CANONICAL_RECEIPTS",
        "statusFlags": FLAGS,
    })


def _row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    data = rendered[path] if path in rendered else (root / path).read_bytes()
    return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data)}


def evidence_document(root: Path, contract: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C49WorkResourceEvidenceReceiptV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "contractDigest": contract["artifactDigest"], "evidenceIDs": list(EVIDENCE_IDS),
        "sourceProjection": {
            "dossier": {"sha256": DOSSIER_SHA256, "byteCount": DOSSIER_BYTES},
            "inherited": {"sha256": INHERITED_SHA256, "byteCount": INHERITED_BYTES},
            "registerRow": {"sha256": REGISTER_ROW_SHA256, "byteCount": REGISTER_ROW_BYTES},
            "registerSection": {"sha256": REGISTER_SECTION_SHA256, "byteCount": REGISTER_SECTION_BYTES},
            "journeyID": "FJ06",
        },
        "sourceArtifacts": [_row(root, path, {}) for path in IMPLEMENTATION_PATHS],
        "verification": {"exactArithmetic": True, "appendOnly": True, "lifecycle": list(LIFECYCLE_COVERAGE), "privacySecretExclusion": True},
        "iso4217ListOne": {"published": ISO_LIST_ONE_PUBLISHED, "rawByteCount": ISO_LIST_ONE_RAW_BYTES,
            "rawSHA256": ISO_LIST_ONE_SHA256, "numericMinorUnitCodeCount": ISO_LIST_ONE_NUMERIC_MINOR_UNIT_CODE_COUNT,
            "nonNumericMinorUnitDisposition": "N.A. EXCLUDED", "concreteScalePins": {"BHD": 3, "KWD": 3, "CLF": 4, "UYW": 4}},
        "statusFlags": FLAGS,
    })


def brand_document(contract: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C49BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
        "contractDigest": contract["artifactDigest"], "brandSurfaceDelta": True, "uiSurfaceDelta": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "requiresS10_6Reconciliation": True,
        "shippingBrandClaimAuthorized": False, "statusFlags": FLAGS,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    schema = schema_document(root)
    contract = contract_document(root)
    evidence = evidence_document(root, contract)
    brand = brand_document(contract)
    rendered = {SCHEMA_PATH: pretty(schema), CONTRACT_PATH: pretty(contract), EVIDENCE_PATH: pretty(evidence), BRAND_PATH: pretty(brand)}
    manifest = _sealed({
        "schema": "V23P03C49ToolingManifestV1", "schemaVersion": 1, "cardID": CARD, "authority": authority(),
        "existingPathCount": 131, "newPathCount": 14, "fencePathCount": 145,
        "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0, "s10ReservationOverlapCount": 0,
        "s10ReservedPathCount": 86, "s10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "artifacts": [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS], "statusFlags": FLAGS,
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered
