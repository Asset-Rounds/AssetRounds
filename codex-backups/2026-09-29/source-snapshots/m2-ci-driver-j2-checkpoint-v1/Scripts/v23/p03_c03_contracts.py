#!/usr/bin/env python3
"""Deterministic Card 34 typed-response and exact-measurement contracts.

The nine repository inputs are the source of truth.  This module only derives
sealed JSON projections from those inputs; it does not provide a second copy
of the Swift response implementation.  The generator and hostile verifier use
the same canonical byte rules so a changed source, fixture, path fence, or
authority value is visible rather than silently accepted.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P03-C03"
TITLE = "Closed typed responses, exact fixed-point/unit semantics, and repeat identity"
ORDINAL = 34

# Values are the immutable Card 34 bootstrap authority.  They intentionally
# remain local constants: hosted verification must not depend on a mutable
# coordination checkout being present.
COORDINATION_HEAD = "80c631478b99e9ef09bc376c188ab6c8481e9875"
COORDINATION_TREE = "3553b4399ebc914d392f58ef75cb800f6d7a7a43"
APP_BASE_HEAD = "a875778e6900f4513b9c1a56069a174d06f29dfc"
APP_BASE_TREE = "c550b5c0ccbeee3f0d7c48ed54f58d7e44aef257"
COORDINATION_CAS_SEQUENCE = 144
COORDINATION_LEDGER_DIGEST = "61b2734c119325136fe8cf00cfbf807fcda0ba5b9bae786a67e44a8da3bf48f8"
HYDRATION_PROJECTION_DIGEST = "f46ef2dbcc35675a4a240565d694827a3231b58a6c476baae1b2d80fd96d1729"
CONTEXT_DIGEST = "21227e12d0713af5dd8ebca71e6117a171c59b8c96acd41002ad5c862e170aa0"
FENCE_DIGEST = "8e424c0e0718d8df4127a2034744f1a347f14c3aed23f684cc0c0c4f6b525bf6"
PREREQUISITE_DIGEST = "362e0bcefbe84aaacc803784d3295fe928554155992bac272ece84f0a6a432de"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_LENGTH = 44_217
REGISTER_ROW_DIGEST = "26d44aaa6bd20ad7ebab0c3bef3d874ba57b6c29e30fd180fee3d4d0c4994bf1"
REGISTER_ROW_LENGTH = 274
DOSSIER_DIGEST = "ea72d3483ee79f78d2dea348cb94b26f219c6c9a4cfc44af704e9fa46e5e94ca"
DOSSIER_LENGTH = 7_073
INHERITED_DIGEST = "b7c7d8238f8f81c0067040e1ab68731a468b4e323f3d0ef31b89719f24d9937d"
INHERITED_LENGTH = 6_879
FOUNDATION_REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DIRECT_GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_MANIFEST_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_MANIFEST_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_MANIFEST_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DISPOSITION_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_MANIFEST_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p03-c03-contracts-v1"
GENERATOR_SEED = 230303

CONTRACT_SCRIPT = "Scripts/v23/p03_c03_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p03_c03_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p03_c03_contracts.py"
RESPONSE_SCHEMA = "Scripts/v23/response-value.schema.json"
FIELD_SCHEMA = "Scripts/v23/response-field-definition.schema.json"
DECIMAL_SCHEMA = "Scripts/v23/exact-decimal.schema.json"
UNIT_SCHEMA = "Scripts/v23/unit-definition.schema.json"
MEASUREMENT_SCHEMA = "Scripts/v23/exact-measurement.schema.json"
EVIDENCE_SCHEMA = "Scripts/v23/typed-response-evidence-receipt.schema.json"
RESPONSE_DOC = "docs/design/v23/tooling/V23P03C03ResponseValueContractV1.json"
MEASUREMENT_DOC = "docs/design/v23/tooling/V23P03C03ExactMeasurementContractV1.json"
REPEAT_DOC = "docs/design/v23/tooling/V23P03C03RepeatResponseIdentityContractV1.json"
LEGACY_DOC = "docs/design/v23/tooling/V23P03C03LegacySignResponseMappingContractV1.json"
EVIDENCE_DOC = "docs/design/v23/tooling/V23P03C03TypedResponseEvidenceReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C03-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowDefinitionV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGraphValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/ShippingIlluminatedSignAdapterV1.swift",
]
NEW_SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/InspectionKernel/ResponseValueV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ExactMeasurementSemanticsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ResponseFieldDefinitionV1.swift",
    "FieldEvidenceAppTests/V9_13TypedResponseTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/InspectionKernel/V21P03C03TypedResponseCorpusV1.json",
]
SOURCE_PATHS = EXISTING_PATHS + NEW_SOURCE_PATHS
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    RESPONSE_SCHEMA,
    FIELD_SCHEMA,
    DECIMAL_SCHEMA,
    UNIT_SCHEMA,
    MEASUREMENT_SCHEMA,
    EVIDENCE_SCHEMA,
    RESPONSE_DOC,
    MEASUREMENT_DOC,
    REPEAT_DOC,
    LEGACY_DOC,
    EVIDENCE_DOC,
    MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
GENERATED_PATHS = TOOL_PATHS[3:]
NEW_PATHS = NEW_SOURCE_PATHS + TOOL_PATHS

EVIDENCE_FAMILIES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in EVIDENCE_FAMILIES]
EVIDENCE_OUTCOMES = {
    "G01": "CLOSED_TYPED_RESPONSE_UNION_AND_EXACT_CANONICAL_BYTES_VALIDATE",
    "A01": "EXACT_FIXED_POINT_UNIT_DIMENSION_RANGE_PRECISION_AND_UNKNOWN_SEMANTICS_REMAIN_CLOSED",
    "H01": "REPEAT_RESPONSE_IDENTITY_REORDER_RESUME_AND_COLLISION_SEMANTICS_REMAIN_CLOSED",
    "I01": "INTERRUPTED_RESPONSE_REGISTRY_PUBLICATION_EXPOSES_ZERO_OR_COMPLETE_RESULT",
    "R01": "LEGACY_SIGN_RESPONSE_PARITY_AND_DORMANT_PATH_RECOVERY_PRESERVE_BINDING",
}

RESPONSE_KINDS = [
    "NO_VALUE",
    "NOT_APPLICABLE",
    "BOOLEAN",
    "TRI_STATE",
    "SINGLE_OPTION",
    "MULTIPLE_OPTIONS",
    "TEXT",
    "LOCAL_DATE",
    "LOCAL_TIME",
    "INSTANT",
    "DURATION",
    "INTEGER",
    "DECIMAL",
    "MEASUREMENT",
    "ENTITY_REFERENCE",
    "CONTENT_REFERENCE",
]
TRI_STATE_VALUES = ["TRUE", "FALSE", "UNKNOWN"]
RESPONSE_CASES = [
    "noValue",
    "notApplicable",
    "boolean",
    "triState",
    "singleOption",
    "multipleOptions",
    "text",
    "localDate",
    "localTime",
    "instant",
    "duration",
    "integer",
    "decimal",
    "measurement",
    "entityReference",
    "contentReference",
]
RESPONSE_FAILURES = [
    "invalidValue",
    "unknownKind",
    "incompatibleVersion",
    "limitExceeded",
    "arithmeticOverflow",
    "precisionLoss",
    "unsupportedUnit",
    "dimensionMismatch",
    "rangeViolation",
    "cardinalityViolation",
    "duplicateIdentity",
    "hashMismatch",
    "invalidTransition",
    "publicationInterrupted",
]
MEASUREMENT_DIMENSIONS = [
    "DIMENSIONLESS",
    "LENGTH",
    "ILLUMINANCE",
    "DURATION",
    "TEMPERATURE",
]
ROUNDING_DISPOSITIONS = [
    "EXACT",
    "NEAREST_TOWARD_ZERO",
    "NEAREST_AWAY_FROM_ZERO",
    "TIE_EVEN_UNCHANGED",
    "TIE_EVEN_ADJUSTED",
]
MEASUREMENT_SOURCES = [
    "MANUAL_ENTRY",
    "INSTRUMENT_OBSERVED",
    "IMPORTED",
    "DERIVED",
]
UNIT_IDS = [
    "1",
    "Cel",
    "K",
    "[degF]",
    "[fc_i]",
    "[ft_i]",
    "[in_i]",
    "cm",
    "h",
    "lx",
    "m",
    "min",
    "mm",
    "ms",
    "s",
]
ACTIVITY_VALUES = ["ACTIVE", "INACTIVE_BY_PATH", "REACTIVATION_REVIEW_REQUIRED"]
LIFECYCLE_DELTAS = [
    "schemaBehaviorDelta",
    "migrationBehaviorDelta",
    "backupBehaviorDelta",
    "restoreBehaviorDelta",
    "deleteBehaviorDelta",
    "exportBehaviorDelta",
]
EXPECTED_LIMITS = {
    "maximumTextUTF8Bytes": 4_096,
    "maximumOptionCount": 128,
    "maximumResponseCount": 128,
    "maximumDecimalScale": 9,
    "maximumIdentifierUTF8Bytes": 128,
    "maximumCanonicalBytes": 1_048_576,
}

# The prior four overlaps are authority, not merely counts.  Keep all bound
# evidence fields so a stale or substituted predecessor cannot pass a hostile
# verification.
PRIOR_FENCE_COUNT = 34
PRIOR_OWNED_PATH_COUNT = 550
PRIOR_FENCE_OVERLAP_EDGES = [
    {
        "path": EXISTING_PATHS[3],
        "priorCardID": "V23-P03-C01",
        "priorFenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3",
        "disposition": "EXTEND_C01_SHIPPING_ADAPTER_WITH_PURE_LEGACY_SIGN_RESPONSE_PARITY_MAPPING_PRESERVING_CLOSED_REGISTRY_CANONICAL_PACKAGE_BYTES_AND_ZERO_SIGN_BRANCH_IN_KERNEL",
        "boundEvidence": {
            "cardID": "V23-P03-C01",
            "attemptID": 1,
            "candidateHead": "76039ad7d48f04f11f19937ed623dd28b12ea49a",
            "candidateTree": "80418a317e75216c8ccc26d7acba5c6cce293d1d",
            "contextDigest": "4221ebc43e391f9b81cad953b9ab2f4c188da324e6c434a92efb2687f941a028",
            "pathFenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3",
            "verificationReceiptDigest": "49665b4d712469087dd81f9aec9c95279e24b54405251a82bd93540c6c4bcfb2",
            "checkpointDigest": "d4500fb867fe334245f83dc8de20267af377aa30ad41ebfdc60c650f951f49be",
        },
    },
    {
        "path": EXISTING_PATHS[1],
        "priorCardID": "V23-P03-C02",
        "priorFenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba",
        "disposition": "EXTEND_C02_FIELD_ID_DECLARATIONS_WITH_C03_CLOSED_RESPONSE_FIELD_DESCRIPTORS_PRESERVING_CANONICAL_PACKAGE_RELEASE_HASH_BINDING",
        "boundEvidence": {
            "cardID": "V23-P03-C02",
            "attemptID": 1,
            "candidateHead": "a875778e6900f4513b9c1a56069a174d06f29dfc",
            "candidateTree": "c550b5c0ccbeee3f0d7c48ed54f58d7e44aef257",
            "contextDigest": "3c238ced11eeffb0b7eb93f968c0e6fc7df555f64e45154bf43b696f25cf5cac",
            "pathFenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba",
            "verificationReceiptDigest": "6ee99bdab7d80ffd36802c3ab891f0409cc881d8942ae4470d9b94f18cca9ff2",
            "checkpointDigest": "d1dc917dc07987153b1e7a94dea9578742f978ffbc812acdbb2d8ea19cf1264c",
        },
    },
    {
        "path": EXISTING_PATHS[0],
        "priorCardID": "V23-P03-C02",
        "priorFenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba",
        "disposition": "EXTEND_C02_CLOSED_WORKFLOW_FACT_AND_REPEAT_SEMANTICS_WITH_C03_TYPED_RESPONSE_AND_STABLE_REPEAT_RESPONSE_IDENTITY_PRESERVING_NODE_PREDICATE_AND_LIMIT_CONTRACTS",
        "boundEvidence": {
            "cardID": "V23-P03-C02",
            "attemptID": 1,
            "candidateHead": "a875778e6900f4513b9c1a56069a174d06f29dfc",
            "candidateTree": "c550b5c0ccbeee3f0d7c48ed54f58d7e44aef257",
            "contextDigest": "3c238ced11eeffb0b7eb93f968c0e6fc7df555f64e45154bf43b696f25cf5cac",
            "pathFenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba",
            "verificationReceiptDigest": "6ee99bdab7d80ffd36802c3ab891f0409cc881d8942ae4470d9b94f18cca9ff2",
            "checkpointDigest": "d1dc917dc07987153b1e7a94dea9578742f978ffbc812acdbb2d8ea19cf1264c",
        },
    },
    {
        "path": EXISTING_PATHS[2],
        "priorCardID": "V23-P03-C02",
        "priorFenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba",
        "disposition": "EXTEND_C02_GRAPH_VALIDATION_WITH_C03_TYPE_RANGE_CARDINALITY_AND_REPEAT_RESPONSE_VALIDATION_PRESERVING_CYCLE_DOMINANCE_AND_OUTGOING_CARDINALITY_RULES",
        "boundEvidence": {
            "cardID": "V23-P03-C02",
            "attemptID": 1,
            "candidateHead": "a875778e6900f4513b9c1a56069a174d06f29dfc",
            "candidateTree": "c550b5c0ccbeee3f0d7c48ed54f58d7e44aef257",
            "contextDigest": "3c238ced11eeffb0b7eb93f968c0e6fc7df555f64e45154bf43b696f25cf5cac",
            "pathFenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba",
            "verificationReceiptDigest": "6ee99bdab7d80ffd36802c3ab891f0409cc881d8942ae4470d9b94f18cca9ff2",
            "checkpointDigest": "d1dc917dc07987153b1e7a94dea9578742f978ffbc812acdbb2d8ea19cf1264c",
        },
    },
]


class ContractError(ValueError):
    """Raised when Card 34 input or authority cannot form a truthful contract."""


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def canonical(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def _read(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise ContractError(f"missing fenced input: {relative}")
    try:
        return path.read_bytes()
    except OSError as error:
        raise ContractError(f"cannot read fenced input: {relative}: {error}") from error


def _text(root: Path, relative: str) -> str:
    try:
        return _read(root, relative).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError(f"non-UTF-8 input: {relative}") from error


def _json(root: Path, relative: str) -> dict[str, Any]:
    try:
        value = json.loads(_read(root, relative))
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid JSON input {relative}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"JSON input is not an object: {relative}")
    return value


def _require_tokens(root: Path, relative: str, tokens: list[str]) -> str:
    text = _text(root, relative)
    lowered = text.lower()
    missing = [token for token in tokens if token.lower() not in lowered]
    if missing:
        raise ContractError(f"{relative}: required source tokens absent: {missing}")
    return text


def _enum_body(text: str, enum_name: str) -> str:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\b[^{{]*\{{(.*?)\n\}}", text, re.S)
    if match is None:
        raise ContractError(f"missing Swift enum: {enum_name}")
    return match.group(1)


def _swift_enum_values(text: str, enum_name: str) -> list[str]:
    values = re.findall(r"\bcase\s+[A-Za-z0-9_]+\s*=\s*\"([^\"]+)\"", _enum_body(text, enum_name))
    if not values or len(values) != len(set(values)):
        raise ContractError(f"invalid Swift enum values: {enum_name}")
    return values


def _swift_case_names(text: str, enum_name: str) -> list[str]:
    body = _enum_body(text, enum_name)
    values = re.findall(r"^\s{4}case\s+([A-Za-z_][A-Za-z0-9_]*)", body, re.M)
    if not values or len(values) != len(set(values)):
        raise ContractError(f"invalid Swift enum cases: {enum_name}")
    return values


def _static_int(text: str, name: str) -> int:
    match = re.search(
        rf"\bstatic\s+let\s+{re.escape(name)}(?:\s*:\s*[^=]+)?\s*=\s*(-?[0-9][0-9_]*)",
        text,
    )
    if match is None:
        raise ContractError(f"missing static integer: {name}")
    return int(match.group(1).replace("_", ""))


def _static_string(text: str, name: str) -> str:
    match = re.search(
        rf"\bstatic\s+let\s+{re.escape(name)}(?:\s*:\s*[^=]+)?\s*=\s*\"([^\"]+)\"",
        text,
    )
    if match is None:
        raise ContractError(f"missing static string: {name}")
    return match.group(1)


def _test_methods(root: Path) -> list[str]:
    text = _text(root, NEW_SOURCE_PATHS[3])
    methods = re.findall(r"\bfunc\s+(testV9_13[A-Za-z0-9_]*)\s*\(", text)
    if len(methods) != 5 or len(methods) != len(set(methods)):
        raise ContractError(f"expected exactly five V9_13 methods, found {methods}")
    families: list[str] = []
    for method in methods:
        match = re.fullmatch(r"testV9_13([GAHIR]01)[A-Za-z0-9_]*", method)
        if match is None:
            raise ContractError(f"test method lacks evidence family: {method}")
        families.append(match.group(1))
    if families != list(EVIDENCE_FAMILIES):
        raise ContractError(f"V9_13 evidence families/order differ: {methods}")
    return methods


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "uiSurfaceDelta": False,
        "brandSurfaceDelta": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": ORDINAL,
        "title": TITLE,
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "lineageSource": "V21-P03-C03",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "registerSectionDigest": REGISTER_SECTION_DIGEST,
        "registerSectionLength": REGISTER_SECTION_LENGTH,
        "registerRowDigest": REGISTER_ROW_DIGEST,
        "registerRowLength": REGISTER_ROW_LENGTH,
        "dossierDigest": DOSSIER_DIGEST,
        "dossierLength": DOSSIER_LENGTH,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "inheritedV21BlockLength": INHERITED_LENGTH,
        "foundationRegisterDigest": FOUNDATION_REGISTER_DIGEST,
        "directGraphDigest": DIRECT_GRAPH_DIGEST,
        "facetManifestDigest": FACET_MANIFEST_DIGEST,
        "selectorManifestDigest": SELECTOR_MANIFEST_DIGEST,
        "relationManifestDigest": RELATION_MANIFEST_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "impactManifestDigest": IMPACT_MANIFEST_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "directPrerequisites": ["V23-P03-C02"],
        "invalidationConsumers": [
            "V23-P03-C04",
            "V23-P04-C27:STATE_INVENTORY",
            "V23-P04-C29:EXACT_CANDIDATE",
            "V23-P05-C01:RELEASE_SELECTOR",
        ],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def common_fields(schema_name: str) -> dict[str, Any]:
    return {
        "schema": schema_name,
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "persistentChangeMode": "DECLARATION_ONLY",
        "persistentContractSchema": "KERNEL_RESPONSE_V1",
        "migrationRequired": False,
        "backupRestoreRequired": False,
        "deleteEraseRequired": False,
        "exportReportRequired": False,
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "backupBehaviorDelta": False,
        "restoreBehaviorDelta": False,
        "deleteBehaviorDelta": False,
        "exportBehaviorDelta": False,
        "evidenceIDs": EVIDENCE_IDS,
        "provisionalKernelOnly": True,
        "shippingBoundaryAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
        "noNewSwiftDataV6Entity": True,
        **flags(),
    }


def _response_projection(root: Path) -> dict[str, Any]:
    text = _require_tokens(
        root,
        NEW_SOURCE_PATHS[0],
        [
            "ResponseValueKindV1",
            "ResponseValueV1",
            "ResponseTriStateV1",
            "ResponseLocalDateV1",
            "ResponseLocalTimeV1",
            "ResponseInstantV1",
            "ResponseDurationV1",
            "ResponseEntityReferenceV1",
            "ResponseContentReferenceIDV1",
            "ResponseValueCanonicalCodecV1",
            "ResponseClosedCodingV1",
            "requireExact",
            "maximumTextUTF8Bytes",
            "maximumOptionCount",
            "maximumCanonicalBytes",
        ],
    )
    kinds = _swift_enum_values(text, "ResponseValueKindV1")
    tri_state = _swift_enum_values(text, "ResponseTriStateV1")
    cases = _swift_case_names(text, "ResponseValueV1")
    if kinds != RESPONSE_KINDS or tri_state != TRI_STATE_VALUES or cases != RESPONSE_CASES:
        raise ContractError("closed response union declarations differ")
    limits = {
        "maximumTextUTF8Bytes": _static_int(text, "maximumTextUTF8Bytes"),
        "maximumOptionCount": _static_int(text, "maximumOptionCount"),
        "maximumCanonicalBytes": _static_int(text, "maximumCanonicalBytes"),
    }
    if limits != {key: EXPECTED_LIMITS[key] for key in limits}:
        raise ContractError(f"response limits differ: {limits}")
    return {
        "type": "ResponseValueV1",
        "kindType": "ResponseValueKindV1",
        "kinds": kinds,
        "cases": cases,
        "triStateValues": tri_state,
        "payloadRule": "EXACTLY_ONE_TAG_PAYLOAD_OR_KIND_ONLY_NO_ARBITRARY_JSON",
        "closedEncoding": "KIND_PLUS_KIND_SPECIFIC_PAYLOAD_EXACT_KEYS",
        "collectionRule": "SORTED_UNIQUE_BOUNDED_OPTION_IDS",
        "limits": limits,
        "canonicalCodec": "ResponseValueCanonicalCodecV1",
        "canonicalRules": [
            "SORTED_KEYS",
            "WITHOUT_ESCAPING_SLASHES",
            "ROUND_TRIP_BYTE_EQUALITY",
            "NO_FLOATING_POINT_CANONICAL_PERSISTENCE",
            "MAXIMUM_CANONICAL_BYTES_1048576",
        ],
        "sourceSHA256": sha(text.encode("utf-8")),
    }


def _measurement_projection(root: Path) -> dict[str, Any]:
    text = _require_tokens(
        root,
        NEW_SOURCE_PATHS[1],
        [
            "ResponseContractFailureV1",
            "ExactDecimalV1",
            "ExactRationalV1",
            "MeasurementDimensionV1",
            "UnitDefinitionV1",
            "KernelUnitRegistryV1",
            "policyVersion",
            "ExactUnitConverterV1",
            "TiesToEvenRoundingDispositionV1",
            "ExactRoundingReceiptV1",
            "ExactMeasurementV1",
            "MeasurementSourceV1",
            "TIES_TO_EVEN_V1",
            "canonicalScale",
            "multiplier",
            "offset",
            "arithmeticOverflow",
            "precisionLoss",
            "ResponseIdentifierValidationV1",
            "maximumUTF8Bytes",
        ],
    )
    dimensions = _swift_enum_values(text, "MeasurementDimensionV1")
    rounding = _swift_enum_values(text, "TiesToEvenRoundingDispositionV1")
    sources = _swift_enum_values(text, "MeasurementSourceV1")
    units = re.findall(r"\bunit\(\"([^\"]+)\"", text)
    if dimensions != MEASUREMENT_DIMENSIONS:
        raise ContractError(f"measurement dimensions differ: {dimensions}")
    if rounding != ROUNDING_DISPOSITIONS or sources != MEASUREMENT_SOURCES:
        raise ContractError("measurement rounding/source enum differs")
    if sorted(units) != UNIT_IDS or len(units) != len(set(units)):
        raise ContractError(f"unit allowlist differs: {units}")
    policy = _static_string(text, "policyVersion")
    if policy != "KERNEL_UNIT_POLICY_V1":
        raise ContractError(f"unit policy differs: {policy}")
    scale = _static_int(text, "maximumScale")
    identifier_bytes = _static_int(text, "maximumUTF8Bytes")
    if scale != EXPECTED_LIMITS["maximumDecimalScale"] or identifier_bytes != EXPECTED_LIMITS["maximumIdentifierUTF8Bytes"]:
        raise ContractError("decimal or identifier bound differs")
    return {
        "type": "ExactMeasurementV1",
        "decimalType": "ExactDecimalV1",
        "rationalType": "ExactRationalV1",
        "dimensions": dimensions,
        "unitIDs": units,
        "unitPolicyVersion": policy,
        "roundingDispositions": rounding,
        "measurementSources": sources,
        "conversion": "EXACT_RATIONAL_OR_AFFINE_SIGNED_FIXED_POINT",
        "roundingPolicy": "TIES_TO_EVEN_V1",
        "overflowDisposition": "FAIL_CLOSED_ARITHMETIC_OVERFLOW",
        "precisionDisposition": "FAIL_CLOSED_PRECISION_LOSS",
        "canonicalStorage": "ENTERED_MANTISSA_SCALE_UNIT_AND_CANONICAL_MANTISSA_SCALE_UNIT_WITH_RECEIPT",
        "noFloatPersistence": True,
        "decimalMaximumScale": scale,
        "identifierMaximumUTF8Bytes": identifier_bytes,
        "sourceSHA256": sha(text.encode("utf-8")),
    }


def _field_projection(root: Path) -> dict[str, Any]:
    text = _require_tokens(
        root,
        NEW_SOURCE_PATHS[2],
        [
            "ResponseCardinalityV1",
            "ResponseFieldDefinitionV1",
            "RepeatResponseBindingV1",
            "BoundResponseValueV1",
            "ResponseFieldValidatorV1",
            "validateCollection",
            "KernelResponseRegistryV1",
            "KernelResponseRegistryPublicationReceiptV1",
            "KernelResponseRegistryCanonicalCodecV1",
            "KernelResponseRegistryPublisherV1",
            "KernelResponseLifecycleV1",
            "stableIdentity",
            "packageReleaseID",
            "workflowSHA256",
            "allowedOptionIDs",
            "maximumPrecisionScale",
            "maximumUncertaintyCanonical",
            "repeatNodeID",
            "allowedEntityKindIDs",
            "REACTIVATION_REVIEW_REQUIRED",
            "ZERO_OR_COMPLETE",
            "EXACT_CANONICAL_BYTES_ADOPTION",
        ],
    )
    maximum_responses = _static_int(text, "maximumResponses")
    if maximum_responses != EXPECTED_LIMITS["maximumResponseCount"]:
        raise ContractError(f"response cardinality bound differs: {maximum_responses}")
    field_keys = [
        "schemaVersion",
        "fieldID",
        "packageReleaseID",
        "workflowSHA256",
        "valueKind",
        "cardinality",
        "allowsNotApplicable",
        "allowsUnknownTriState",
        "maximumTextUTF8Bytes",
        "allowedOptionIDs",
        "minimumNumericValue",
        "maximumNumericValue",
        "measurementDimension",
        "allowedUnitIDs",
        "maximumPrecisionScale",
        "maximumUncertaintyCanonical",
        "repeatNodeID",
        "allowedEntityKindIDs",
    ]
    for key in field_keys:
        if key not in text:
            raise ContractError(f"field definition coding key absent: {key}")
    return {
        "type": "ResponseFieldDefinitionV1",
        "fieldKeys": field_keys,
        "cardinalityType": "ResponseCardinalityV1",
        "maximumResponses": maximum_responses,
        "requiredBindings": ["fieldID", "packageReleaseID", "workflowSHA256", "valueKind", "cardinality"],
        "rangeBinding": "KIND_REQUIREDNESS_CARDINALITY_TEXT_OPTION_NUMERIC_DIMENSION_UNIT_PRECISION_UNCERTAINTY",
        "repeatBindingType": "RepeatResponseBindingV1",
        "responseBindingType": "BoundResponseValueV1",
        "registryType": "KernelResponseRegistryV1",
        "interruption": "ZERO_OR_COMPLETE",
        "idempotentReceipt": "EXACT_CANONICAL_BYTES_ADOPTION",
        "sourceSHA256": sha(text.encode("utf-8")),
    }


def _workflow_projection(root: Path) -> dict[str, Any]:
    grammar = _require_tokens(
        root,
        EXISTING_PATHS[0],
        [
            "WorkflowNodeKindV1",
            "BranchPredicateV1",
            "WorkflowFactValueV1",
            "ResponseValueV1",
            "RepeatInstanceStateV1",
            "WorkflowPathActivityV1",
            "WorkflowGrammarLimitsV1",
            "maximumRepeatCount",
            "destination(for value: BranchTruthValueV1)",
            "KernelClosedCodingV1",
        ],
    )
    definition = _require_tokens(
        root,
        EXISTING_PATHS[1],
        [
            "WorkflowNodeV1",
            "WorkflowDefinitionV1",
            "ResponseFieldDefinitionV1",
            "validateResponseFieldDefinitions",
            "packageReleaseID",
            "workflowSHA256",
            "declaredFieldIDs",
        ],
    )
    validator = _require_tokens(
        root,
        EXISTING_PATHS[2],
        [
            "WorkflowGraphValidatorV1",
            "responseFieldDefinitions",
            "repeat",
            "computeDominators",
            "cycle",
            "forwardPredicateReference",
        ],
    )
    adapter = _require_tokens(
        root,
        EXISTING_PATHS[3],
        [
            "ShippingIlluminatedSignAdapterV1",
            "ShippingIlluminatedSignParityReceiptV1",
            "inspectionPackage",
            "signPack",
            "outcomeDisplays",
            "issueLabels",
            "couldNotVerifyReasons",
            "acknowledgements",
            "parityReceipt",
            "exactParity",
        ],
    )
    # These source surfaces are pure declarations/adapters.  A network or
    # persistence integration token would be a product-scope violation.
    forbidden = re.compile(
        r"URLSession|URLRequest|CloudKit|SwiftData|StoreKit|CKRecord|NWPathMonitor|https?://|UserDefaults",
        re.I,
    )
    for relative in EXISTING_PATHS + NEW_SOURCE_PATHS[:3]:
        if forbidden.search(_text(root, relative)):
            raise ContractError(f"forbidden integration token in fenced source: {relative}")
    if "ShippingIlluminatedSignAdapter" in grammar or "SignPack" in grammar:
        raise ContractError("sign-specific adapter leaked into neutral workflow grammar")
    return {
        "workflowGrammarSHA256": sha(grammar.encode("utf-8")),
        "workflowDefinitionSHA256": sha(definition.encode("utf-8")),
        "workflowGraphValidatorSHA256": sha(validator.encode("utf-8")),
        "shippingAdapterSHA256": sha(adapter.encode("utf-8")),
        "branchTruthValues": TRI_STATE_VALUES,
        "repeatActivities": ACTIVITY_VALUES,
        "responseFieldValidation": "TYPE_RANGE_CARDINALITY_AND_REPEAT_BINDING_BEFORE_ACCEPTANCE",
        "adapterBoundary": "PURE_LEGACY_SIGN_MAPPING_NO_NEUTRAL_KERNEL_SIGN_BRANCH",
        "forbiddenIntegration": "NO_NETWORK_NO_PERSISTENCE_NO_REMOTE_PACKAGE_NO_TELEMETRY",
    }


def _fixture_projection(root: Path) -> dict[str, Any]:
    fixture = _json(root, NEW_SOURCE_PATHS[4])
    if (
        fixture.get("schema") != "V21P03C03TypedResponseCorpusV1"
        or fixture.get("schemaVersion") != 1
        or fixture.get("testOnly") is not True
    ):
        raise ContractError("typed-response fixture identity differs")
    blob = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    markers = [
        "NO_VALUE",
        "NOT_APPLICABLE",
        "MEASUREMENT",
        "KERNEL_UNIT_POLICY_V1",
        "TIE_EVEN_UNCHANGED",
        "ACTIVE",
        "INACTIVE_BY_PATH",
        "REACTIVATION_REVIEW_REQUIRED",
        "FAIL_CLOSED",
    ]
    missing = [marker for marker in markers if marker not in blob]
    if missing:
        raise ContractError(f"typed-response fixture markers absent: {missing}")
    return {
        "schema": fixture["schema"],
        "schemaVersion": fixture["schemaVersion"],
        "testOnly": fixture["testOnly"],
        "topLevelKeys": sorted(fixture),
        "responseKinds": fixture.get("responseKinds", RESPONSE_KINDS),
        "measurementDimensions": fixture.get("measurementDimensions", MEASUREMENT_DIMENSIONS),
        "unitIDs": fixture.get("unitIDs", UNIT_IDS),
        "roundingDispositions": fixture.get("roundingDispositions", ROUNDING_DISPOSITIONS),
        "repeatActivities": fixture.get("repeatActivities", ACTIVITY_VALUES),
        "requiredMarkers": markers,
        "sourceSHA256": sha(_read(root, NEW_SOURCE_PATHS[4])),
        "canonicalSHA256": sha(canonical(fixture)),
    }


def _test_projection(root: Path, methods: list[str]) -> dict[str, Any]:
    text = _text(root, NEW_SOURCE_PATHS[3])
    tokens = [
        "XCTestCase",
        "XCTAssert",
        "XCTAssertThrowsError",
        "ResponseValueV1",
        "ExactMeasurementV1",
        "ResponseFieldDefinitionV1",
        "RepeatResponseBindingV1",
        "interruption",
        "relaunch",
        "fail",
    ]
    missing = [token for token in tokens if token.lower() not in text.lower()]
    if missing:
        raise ContractError(f"{NEW_SOURCE_PATHS[3]}: evidence markers absent: {missing}")
    data = _read(root, NEW_SOURCE_PATHS[3])
    return {
        "path": NEW_SOURCE_PATHS[3],
        "methods": methods,
        "families": list(EVIDENCE_FAMILIES),
        "bytes": len(data),
        "sha256": sha(data),
    }


def _source_projection(root: Path) -> dict[str, Any]:
    response = _response_projection(root)
    measurement = _measurement_projection(root)
    field = _field_projection(root)
    workflow = _workflow_projection(root)
    return {
        "response": response,
        "measurement": measurement,
        "fieldDefinition": field,
        "workflowAndAdapter": workflow,
        "sourceCount": len(SOURCE_PATHS),
    }


def source_bindings(root: Path, methods: list[str], fixture: dict[str, Any]) -> list[dict[str, Any]]:
    rows = [
        (
            EXISTING_PATHS[0],
            "workflow-grammar-response-bridge",
            ["WorkflowNodeKindV1", "WorkflowFactValueV1", "ResponseValueV1", "RepeatInstanceStateV1"],
            ["BranchPredicateV1", "WorkflowGrammarLimitsV1", "maximumRepeatCount", "KernelClosedCodingV1"],
        ),
        (
            EXISTING_PATHS[1],
            "workflow-definition-field-binding",
            ["WorkflowNodeV1", "WorkflowDefinitionV1", "ResponseFieldDefinitionV1"],
            ["validateResponseFieldDefinitions", "packageReleaseID", "workflowSHA256", "declaredFieldIDs"],
        ),
        (
            EXISTING_PATHS[2],
            "workflow-graph-response-validation",
            ["WorkflowGraphValidatorV1"],
            ["responseFieldDefinitions", "computeDominators", "forwardPredicateReference"],
        ),
        (
            EXISTING_PATHS[3],
            "shipping-legacy-response-adapter",
            ["ShippingIlluminatedSignAdapterV1", "ShippingIlluminatedSignParityReceiptV1"],
            ["inspectionPackage", "signPack", "outcomeDisplays", "issueLabels", "couldNotVerifyReasons", "acknowledgements", "parityReceipt", "exactParity"],
        ),
        (
            NEW_SOURCE_PATHS[0],
            "closed-response-union",
            ["ResponseValueKindV1", "ResponseValueV1", "ResponseValueCanonicalCodecV1"],
            RESPONSE_KINDS + ["ResponseClosedCodingV1", "requireExact", "maximumTextUTF8Bytes", "maximumOptionCount"],
        ),
        (
            NEW_SOURCE_PATHS[1],
            "exact-measurement-semantics",
            ["ExactDecimalV1", "ExactRationalV1", "KernelUnitRegistryV1", "ExactUnitConverterV1", "ExactMeasurementV1"],
            UNIT_IDS + ["TIES_TO_EVEN_V1", "canonicalScale", "arithmeticOverflow", "precisionLoss", "noFloatPersistence"],
        ),
        (
            NEW_SOURCE_PATHS[2],
            "response-field-and-repeat-contracts",
            ["ResponseFieldDefinitionV1", "RepeatResponseBindingV1", "BoundResponseValueV1", "KernelResponseRegistryV1"],
            ["stableIdentity", "allowedOptionIDs", "maximumPrecisionScale", "maximumUncertaintyCanonical", "repeatNodeID", "ZERO_OR_COMPLETE"],
        ),
        (
            NEW_SOURCE_PATHS[3],
            "evidence-tests",
            methods,
            ["XCTestCase", "XCTAssert", "XCTAssertThrowsError", "ResponseValueV1", "ExactMeasurementV1", "interruption", "relaunch", "fail"],
        ),
        (
            NEW_SOURCE_PATHS[4],
            "typed-response-corpus",
            ["schema", "schemaVersion", "testOnly"],
            fixture["requiredMarkers"],
        ),
    ]
    result: list[dict[str, Any]] = []
    for relative, owner, symbols, tokens in rows:
        text = _text(root, relative)
        lowered = text.lower()
        missing = [token for token in tokens if token.lower() not in lowered]
        if missing:
            raise ContractError(f"{relative}: source binding tokens absent: {missing}")
        data = _read(root, relative)
        result.append({
            "path": relative,
            "owner": owner,
            "symbols": symbols,
            "requiredTokens": tokens,
            "bytes": len(data),
            "sha256": sha(data),
        })
    return result


def _common_contract(schema_name: str, root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    return {
        **common_fields(schema_name),
        "sourceProjection": source,
        "fixtureProjection": fixture,
        "testMethods": methods,
        "sourceBindings": source_bindings(root, methods, fixture),
    }


def response_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C03ResponseValueContractV1", root, source, methods, fixture)
    value.update({
        "response": {
            "type": "ResponseValueV1",
            "kinds": RESPONSE_KINDS,
            "triStateValues": TRI_STATE_VALUES,
            "closedUnion": True,
            "kindSpecificExactPayload": True,
            "noArbitraryJSON": True,
            "noEAV": True,
            "maximumCanonicalBytes": EXPECTED_LIMITS["maximumCanonicalBytes"],
            "maximumTextUTF8Bytes": EXPECTED_LIMITS["maximumTextUTF8Bytes"],
            "maximumOptionCount": EXPECTED_LIMITS["maximumOptionCount"],
            "canonicalCodec": "ResponseValueCanonicalCodecV1",
            "unknownKindDisposition": "FAIL_CLOSED",
            "malformedPayloadDisposition": "FAIL_CLOSED",
        },
        "kernelBoundary": {
            "declarationOnly": True,
            "noCanonicalUserWrite": True,
            "noNetwork": True,
            "noProductionCapture": True,
            "noFloatingPointPersistence": True,
        },
    })
    return value


def measurement_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C03ExactMeasurementContractV1", root, source, methods, fixture)
    value.update({
        "measurement": {
            "type": "ExactMeasurementV1",
            "decimalType": "ExactDecimalV1",
            "rationalType": "ExactRationalV1",
            "dimensions": MEASUREMENT_DIMENSIONS,
            "unitIDs": UNIT_IDS,
            "unitPolicyVersion": "KERNEL_UNIT_POLICY_V1",
            "conversion": "EXACT_RATIONAL_OR_AFFINE",
            "roundingPolicy": "TIES_TO_EVEN_V1",
            "roundingDispositions": ROUNDING_DISPOSITIONS,
            "measurementSources": MEASUREMENT_SOURCES,
            "maximumScale": EXPECTED_LIMITS["maximumDecimalScale"],
            "enteredAndCanonicalRetained": True,
            "roundingReceiptRequired": True,
            "overflowDisposition": "FAIL_CLOSED",
            "dimensionMismatchDisposition": "FAIL_CLOSED",
            "unsupportedUnitDisposition": "FAIL_CLOSED",
            "precisionLossDisposition": "FAIL_CLOSED",
            "noFloatPersistence": True,
        },
        "lifecycle": {
            "mode": "DECLARATION_ONLY",
            "schema": "KERNEL_RESPONSE_V1",
            "migrationRequired": False,
            "backupRestoreRequired": False,
            "deleteEraseRequired": False,
            "exportReportRequired": False,
            "downgrade": "DORMANT_REVERT_ALLOWED",
        },
    })
    return value


def repeat_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C03RepeatResponseIdentityContractV1", root, source, methods, fixture)
    value.update({
        "repeatIdentity": {
            "type": "RepeatResponseBindingV1",
            "stableFields": ["repeatInstanceID", "repeatNodeID", "stableOrder", "packageReleaseID", "workflowSHA256"],
            "activityValues": ACTIVITY_VALUES,
            "stableResponseIdentity": "FIELD_ID_PLUS_REPEAT_INSTANCE_ID",
            "pathInactivation": "INACTIVE_BY_PATH",
            "reactivation": "REACTIVATION_REVIEW_REQUIRED",
            "completionAndReporting": "ACTIVE_ONLY",
            "reorderSafe": True,
            "resumeSafe": True,
            "archiveExportSafe": True,
            "bindingMismatchDisposition": "FAIL_CLOSED_HASH_MISMATCH",
            "duplicateIdentityDisposition": "FAIL_CLOSED",
        },
        "responseFieldBinding": {
            "type": "BoundResponseValueV1",
            "definitionType": "ResponseFieldDefinitionV1",
            "collectionValidator": "ResponseFieldValidatorV1.validateCollection",
            "canonicalOrder": "STABLE_ORDER_THEN_STABLE_IDENTITY",
        },
    })
    return value


def legacy_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C03LegacySignResponseMappingContractV1", root, source, methods, fixture)
    value.update({
        "legacyMapping": {
            "adapter": "ShippingIlluminatedSignAdapterV1",
            "sourcePackage": "SignPack.illuminatedSignV1",
            "mappingMode": "PURE_ADAPTER_ONLY",
            "preservedSemantics": [
                "OUTCOME_DISPLAYS",
                "ISSUE_LABELS",
                "COULD_NOT_VERIFY_REASONS",
                "ACKNOWLEDGEMENTS",
                "REFERENCE_SEMANTICS",
            ],
            "parityReceipt": "ShippingIlluminatedSignParityReceiptV1",
            "exactParityRequired": True,
            "neutralKernelSignBranch": False,
            "canonicalPackageBytesChanged": False,
            "shippingAdoption": "DEFERRED_UNTIL_ACCEPTED_S10_6_RECONCILIATION",
        },
        "prohibited": ["SIGN_BRANCH_IN_NEUTRAL_KERNEL", "NEW_SIGN_SCHEMA", "REMOTE_PACKAGE", "NETWORK", "CUSTOMER_DATA"],
    })
    return value


def evidence_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C03TypedResponseEvidenceReceiptV1", root, source, methods, fixture)
    value.update({
        "evidence": [
            {
                "evidenceID": evidence_id,
                "family": family,
                "testMethod": method,
                "requiredOutcome": EVIDENCE_OUTCOMES[family],
            }
            for evidence_id, family, method in zip(EVIDENCE_IDS, EVIDENCE_FAMILIES, methods)
        ],
        "hostileCases": [
            "UNKNOWN_RESPONSE_KIND",
            "EXTRA_OR_MISSING_KIND_PAYLOAD",
            "UNSORTED_OR_DUPLICATE_OPTIONS",
            "TEXT_LIMIT_EXCEEDED",
            "DECIMAL_SCALE_OR_ARITHMETIC_OVERFLOW",
            "UNSUPPORTED_UNIT",
            "DIMENSION_MISMATCH",
            "ROUNDING_RECEIPT_TAMPER",
            "FIELD_KIND_OR_RANGE_MISMATCH",
            "DUPLICATE_REPEAT_RESPONSE_IDENTITY",
            "REPEAT_BINDING_HASH_MISMATCH",
            "LEGACY_MAPPING_PARITY_DRIFT",
        ],
        "interruptionBoundaries": [
            "BEFORE_VALIDATION",
            "AFTER_VALIDATION_BEFORE_PUBLICATION",
            "AFTER_PUBLICATION_BEFORE_RECEIPT",
        ],
        "interruptionPolicy": {
            "deterministic": True,
            "idempotent": True,
            "partialAcceptedState": False,
            "zeroOrCompleteValidatedResult": True,
            "relaunchContinuation": "RECONSTRUCT_OR_ADOPT_EXACT_CANONICAL_BYTES_OR_FAIL_CLOSED",
        },
        "fixture": fixture,
        "brandImpact": {
            "manifestType": "BrandImpactManifestV1",
            "manifestCount": 1,
            "changedScreens": [],
            "changedStates": [],
            "affectedConsumers": [
                "V23-P03-C03",
                "V23-P03-C04",
                "V23-P04-C27:STATE_INVENTORY",
                "V23-P04-C29:EXACT_CANDIDATE",
                "V23-P05-C01:RELEASE_SELECTOR",
            ],
            "completenessRationale": "Kernel declarations, pure adapter mapping, and test-only corpus add no UI, project metadata, launch composition, or brand asset.",
        },
        "privacy": {
            "customerDataInContracts": False,
            "customerDataInFixtures": False,
            "networkTransport": False,
            "userAuthoredCode": False,
            "secretsInArtifacts": False,
            "productionMeasurementCapture": False,
        },
    })
    return value


def _string_schema(*, pattern: str | None = None, enum: list[str] | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "string"}
    if pattern is not None:
        result["pattern"] = pattern
    if enum is not None:
        result["enum"] = list(enum)
    return result


def _integer_schema(*, minimum: int | None = None, maximum: int | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "integer"}
    if minimum is not None:
        result["minimum"] = minimum
    if maximum is not None:
        result["maximum"] = maximum
    return result


def _nullable(inner: dict[str, Any]) -> dict[str, Any]:
    return {"anyOf": [inner, {"type": "null"}]}


def _array(item: dict[str, Any], *, minimum: int = 0, maximum: int | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "array", "items": item, "minItems": minimum}
    if maximum is not None:
        result["maxItems"] = maximum
    return result


def _object(properties: dict[str, dict[str, Any]], required: list[str]) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": list(required),
        "properties": properties,
    }


def _domain_schema(title: str, shape: dict[str, Any], definitions: dict[str, Any] | None = None) -> dict[str, Any]:
    result = dict(shape)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{title}.schema.json",
        "title": title,
    })
    if definitions:
        result["$defs"] = definitions
    return result


_ID_PATTERN = r"^[A-Za-z0-9._\[\]-]{1,128}$"
_SHA_PATTERN = r"^[0-9a-f]{64}$"


def _decimal_shape() -> dict[str, Any]:
    return _object(
        {"mantissa": {"type": "integer"}, "scale": _integer_schema(minimum=0, maximum=9)},
        ["mantissa", "scale"],
    )


def _rational_shape() -> dict[str, Any]:
    return _object(
        {"numerator": {"type": "integer"}, "denominator": _integer_schema(minimum=1)},
        ["numerator", "denominator"],
    )


def _response_schema() -> dict[str, Any]:
    payloads: list[tuple[str, dict[str, Any] | None]] = [
        ("NO_VALUE", None),
        ("NOT_APPLICABLE", {"reasonID": _string_schema(pattern=_ID_PATTERN)}),
        ("BOOLEAN", {"boolean": {"type": "boolean"}}),
        ("TRI_STATE", {"triState": _string_schema(enum=TRI_STATE_VALUES)}),
        ("SINGLE_OPTION", {"optionID": _string_schema(pattern=_ID_PATTERN)}),
        ("MULTIPLE_OPTIONS", {"optionIDs": _array(_string_schema(pattern=_ID_PATTERN), minimum=1, maximum=128)}),
        ("TEXT", {"text": _string_schema()}),
        ("LOCAL_DATE", {"localDate": _object({"year": _integer_schema(minimum=1, maximum=9_999), "month": _integer_schema(minimum=1, maximum=12), "day": _integer_schema(minimum=1, maximum=31)}, ["year", "month", "day"])}),
        ("LOCAL_TIME", {"localTime": _object({"hour": _integer_schema(minimum=0, maximum=23), "minute": _integer_schema(minimum=0, maximum=59), "second": _integer_schema(minimum=0, maximum=59), "millisecond": _integer_schema(minimum=0, maximum=999)}, ["hour", "minute", "second", "millisecond"])}),
        ("INSTANT", {"instant": _object({"epochMilliseconds": {"type": "integer"}}, ["epochMilliseconds"])}),
        ("DURATION", {"duration": _object({"milliseconds": _integer_schema(minimum=0)}, ["milliseconds"])}),
        ("INTEGER", {"integer": {"type": "integer"}}),
        ("DECIMAL", {"decimal": {"$ref": "#/$defs/ExactDecimalV1"}}),
        ("MEASUREMENT", {"measurement": {"$ref": "#/$defs/ExactMeasurementV1"}}),
        ("ENTITY_REFERENCE", {"entityReference": _object({"entityKindID": _string_schema(pattern=_ID_PATTERN), "entityID": _string_schema(pattern=_ID_PATTERN)}, ["entityKindID", "entityID"])}),
        ("CONTENT_REFERENCE", {"contentReference": _object({"rawValue": _string_schema(pattern=_ID_PATTERN)}, ["rawValue"])}),
    ]
    variants = []
    for kind, payload in payloads:
        properties: dict[str, dict[str, Any]] = {"kind": {"const": kind}}
        required = ["kind"]
        if payload:
            properties.update(payload)
            required.extend(payload)
        variants.append(_object(properties, required))
    return _domain_schema(
        "ResponseValueV1",
        {"anyOf": variants},
        {
            "ExactDecimalV1": _decimal_shape(),
            "ExactMeasurementV1": _object({"schemaVersion": {"const": 1}, "enteredValue": {"$ref": "#/$defs/ExactDecimalV1"}, "enteredUnitID": _string_schema(pattern=_ID_PATTERN), "canonicalValue": {"$ref": "#/$defs/ExactDecimalV1"}, "canonicalUnitID": _string_schema(pattern=_ID_PATTERN), "dimension": _string_schema(enum=MEASUREMENT_DIMENSIONS), "precisionScale": _integer_schema(minimum=0, maximum=9), "uncertaintyCanonical": _nullable({"$ref": "#/$defs/ExactDecimalV1"}), "source": _string_schema(enum=MEASUREMENT_SOURCES), "captureMethodID": _string_schema(pattern=_ID_PATTERN), "conversionPolicyVersion": {"const": "KERNEL_UNIT_POLICY_V1"}, "roundingReceipt": {"$ref": "#/$defs/ExactRoundingReceiptV1"}}, ["schemaVersion", "enteredValue", "enteredUnitID", "canonicalValue", "canonicalUnitID", "dimension", "precisionScale", "uncertaintyCanonical", "source", "captureMethodID", "conversionPolicyVersion", "roundingReceipt"]),
            "ExactRoundingReceiptV1": _object({"schemaVersion": {"const": 1}, "policy": {"const": "TIES_TO_EVEN_V1"}, "sourceNumerator": {"type": "integer"}, "sourceDenominator": _integer_schema(minimum=1), "targetScale": _integer_schema(minimum=0, maximum=9), "truncatedMantissa": {"type": "integer"}, "remainder": {"type": "integer"}, "roundedMantissa": {"type": "integer"}, "disposition": _string_schema(enum=ROUNDING_DISPOSITIONS)}, ["schemaVersion", "policy", "sourceNumerator", "sourceDenominator", "targetScale", "truncatedMantissa", "remainder", "roundedMantissa", "disposition"]),
        },
    )


def _field_schema() -> dict[str, Any]:
    properties = {
        "schemaVersion": {"const": 1},
        "fieldID": _string_schema(pattern=_ID_PATTERN),
        "packageReleaseID": _string_schema(pattern=_SHA_PATTERN),
        "workflowSHA256": _string_schema(pattern=_SHA_PATTERN),
        "valueKind": _string_schema(enum=RESPONSE_KINDS),
        "cardinality": _object({"minimum": _integer_schema(minimum=0, maximum=128), "maximum": _integer_schema(minimum=0, maximum=128)}, ["minimum", "maximum"]),
        "allowsNotApplicable": {"type": "boolean"},
        "allowsUnknownTriState": {"type": "boolean"},
        "maximumTextUTF8Bytes": _nullable(_integer_schema(minimum=0, maximum=4_096)),
        "allowedOptionIDs": _array(_string_schema(pattern=_ID_PATTERN), maximum=128),
        "minimumNumericValue": _nullable({"$ref": "#/$defs/ExactDecimalV1"}),
        "maximumNumericValue": _nullable({"$ref": "#/$defs/ExactDecimalV1"}),
        "measurementDimension": _nullable(_string_schema(enum=MEASUREMENT_DIMENSIONS)),
        "allowedUnitIDs": _array(_string_schema(pattern=_ID_PATTERN), maximum=len(UNIT_IDS)),
        "maximumPrecisionScale": _nullable(_integer_schema(minimum=0, maximum=9)),
        "maximumUncertaintyCanonical": _nullable({"$ref": "#/$defs/ExactDecimalV1"}),
        "repeatNodeID": _nullable(_string_schema(pattern=_ID_PATTERN)),
        "allowedEntityKindIDs": _array(_string_schema(pattern=_ID_PATTERN), maximum=128),
    }
    return _domain_schema(
        "ResponseFieldDefinitionV1",
        _object(properties, list(properties)),
        {"ExactDecimalV1": _decimal_shape()},
    )


def _decimal_schema() -> dict[str, Any]:
    return _domain_schema("ExactDecimalV1", _decimal_shape())


def _unit_schema() -> dict[str, Any]:
    return _domain_schema(
        "UnitDefinitionV1",
        _object({"unitID": _string_schema(pattern=_ID_PATTERN), "dimension": _string_schema(enum=MEASUREMENT_DIMENSIONS), "canonicalUnitID": _string_schema(pattern=_ID_PATTERN), "multiplier": {"$ref": "#/$defs/ExactRationalV1"}, "offset": {"$ref": "#/$defs/ExactRationalV1"}, "canonicalScale": _integer_schema(minimum=0, maximum=9)}, ["unitID", "dimension", "canonicalUnitID", "multiplier", "offset", "canonicalScale"]),
        {"ExactRationalV1": _rational_shape()},
    )


def _measurement_schema() -> dict[str, Any]:
    return _domain_schema(
        "ExactMeasurementV1",
        _object({"schemaVersion": {"const": 1}, "enteredValue": {"$ref": "#/$defs/ExactDecimalV1"}, "enteredUnitID": _string_schema(pattern=_ID_PATTERN), "canonicalValue": {"$ref": "#/$defs/ExactDecimalV1"}, "canonicalUnitID": _string_schema(pattern=_ID_PATTERN), "dimension": _string_schema(enum=MEASUREMENT_DIMENSIONS), "precisionScale": _integer_schema(minimum=0, maximum=9), "uncertaintyCanonical": _nullable({"$ref": "#/$defs/ExactDecimalV1"}), "source": _string_schema(enum=MEASUREMENT_SOURCES), "captureMethodID": _string_schema(pattern=_ID_PATTERN), "conversionPolicyVersion": {"const": "KERNEL_UNIT_POLICY_V1"}, "roundingReceipt": {"$ref": "#/$defs/ExactRoundingReceiptV1"}}, ["schemaVersion", "enteredValue", "enteredUnitID", "canonicalValue", "canonicalUnitID", "dimension", "precisionScale", "uncertaintyCanonical", "source", "captureMethodID", "conversionPolicyVersion", "roundingReceipt"]),
        {"ExactDecimalV1": _decimal_shape(), "ExactRoundingReceiptV1": _object({"schemaVersion": {"const": 1}, "policy": {"const": "TIES_TO_EVEN_V1"}, "sourceNumerator": {"type": "integer"}, "sourceDenominator": _integer_schema(minimum=1), "targetScale": _integer_schema(minimum=0, maximum=9), "truncatedMantissa": {"type": "integer"}, "remainder": {"type": "integer"}, "roundedMantissa": {"type": "integer"}, "disposition": _string_schema(enum=ROUNDING_DISPOSITIONS)}, ["schemaVersion", "policy", "sourceNumerator", "sourceDenominator", "targetScale", "truncatedMantissa", "remainder", "roundedMantissa", "disposition"])},
    )


def _evidence_schema() -> dict[str, Any]:
    evidence_row = _object(
        {
            "evidenceID": _string_schema(pattern=r"^V23-P03-C03-[GAHIR]01$"),
            "family": _string_schema(enum=list(EVIDENCE_FAMILIES)),
            "testMethod": _string_schema(pattern=r"^testV9_13[GAHIR]01[A-Za-z0-9_]+$"),
            "requiredOutcome": _string_schema(),
        },
        ["evidenceID", "family", "testMethod", "requiredOutcome"],
    )
    fixture = _object(
        {
            "schema": {"const": "V21P03C03TypedResponseCorpusV1"},
            "schemaVersion": {"const": 1},
            "testOnly": {"const": True},
            "topLevelKeys": _array(_string_schema(), minimum=1, maximum=64),
            "responseKinds": _array(_string_schema(enum=RESPONSE_KINDS), minimum=16, maximum=16),
            "measurementDimensions": _array(_string_schema(enum=MEASUREMENT_DIMENSIONS), minimum=5, maximum=5),
            "unitIDs": _array(_string_schema(pattern=_ID_PATTERN), minimum=len(UNIT_IDS), maximum=len(UNIT_IDS)),
            "roundingDispositions": _array(_string_schema(enum=ROUNDING_DISPOSITIONS), minimum=5, maximum=5),
            "repeatActivities": _array(_string_schema(enum=ACTIVITY_VALUES), minimum=3, maximum=3),
            "requiredMarkers": _array(_string_schema(), minimum=9, maximum=9),
            "sourceSHA256": _string_schema(pattern=_SHA_PATTERN),
            "canonicalSHA256": _string_schema(pattern=_SHA_PATTERN),
        },
        ["schema", "schemaVersion", "testOnly", "topLevelKeys", "responseKinds", "measurementDimensions", "unitIDs", "roundingDispositions", "repeatActivities", "requiredMarkers", "sourceSHA256", "canonicalSHA256"],
    )
    privacy = _object({
        "customerDataInContracts": {"const": False},
        "customerDataInFixtures": {"const": False},
        "networkTransport": {"const": False},
        "userAuthoredCode": {"const": False},
        "secretsInArtifacts": {"const": False},
        "productionMeasurementCapture": {"const": False},
    }, ["customerDataInContracts", "customerDataInFixtures", "networkTransport", "userAuthoredCode", "secretsInArtifacts", "productionMeasurementCapture"])
    brand = _object({
        "manifestType": {"const": "BrandImpactManifestV1"},
        "manifestCount": {"const": 1},
        "changedScreens": _array(_string_schema(), maximum=0),
        "changedStates": _array(_string_schema(), maximum=0),
        "affectedConsumers": _array(_string_schema(), minimum=5, maximum=5),
        "completenessRationale": _string_schema(),
    }, ["manifestType", "manifestCount", "changedScreens", "changedStates", "affectedConsumers", "completenessRationale"])
    return _domain_schema(
        "TypedResponseEvidenceReceiptV1",
        _object({
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD},
            "evidence": _array(evidence_row, minimum=5, maximum=5),
            "testMethods": _array(_string_schema(pattern=r"^testV9_13[GAHIR]01[A-Za-z0-9_]+$"), minimum=5, maximum=5),
            "interruptionBoundaries": _array(_string_schema(enum=["BEFORE_VALIDATION", "AFTER_VALIDATION_BEFORE_PUBLICATION", "AFTER_PUBLICATION_BEFORE_RECEIPT"]), minimum=3, maximum=3),
            "fixture": fixture,
            "brandImpact": brand,
            "privacy": privacy,
        }, ["schemaVersion", "cardID", "evidence", "testMethods", "interruptionBoundaries", "fixture", "brandImpact", "privacy"]),
    )


SCHEMA_TITLES = {
    RESPONSE_SCHEMA: "ResponseValueV1",
    FIELD_SCHEMA: "ResponseFieldDefinitionV1",
    DECIMAL_SCHEMA: "ExactDecimalV1",
    UNIT_SCHEMA: "UnitDefinitionV1",
    MEASUREMENT_SCHEMA: "ExactMeasurementV1",
    EVIDENCE_SCHEMA: "TypedResponseEvidenceReceiptV1",
}


def _artifact_rows(root: Path, generated: dict[str, bytes]) -> tuple[list[dict[str, Any]], list[str]]:
    rows: list[dict[str, Any]] = []
    pending: list[str] = []
    for relative in MANIFEST_INPUT_PATHS:
        data = generated.get(relative)
        if data is None:
            path = root / relative
            if not path.is_file():
                pending.append(relative)
                continue
            data = path.read_bytes()
        rows.append({"path": relative, "bytes": len(data), "sha256": sha(data)})
    return rows, pending


def tooling_manifest(root: Path, generated: dict[str, bytes], source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    rows, pending = _artifact_rows(root, generated)
    return seal({
        **common_fields("V23-P03-C03-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE,
        "pathFenceCount": len(PATH_FENCE),
        "existingPaths": EXISTING_PATHS,
        "newPaths": NEW_PATHS,
        "sourcePaths": SOURCE_PATHS,
        "sourcePathCount": len(SOURCE_PATHS),
        "toolingPaths": TOOL_PATHS,
        "toolingPathCount": len(TOOL_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows,
        "artifactCount": len(rows),
        "pendingFencePaths": pending,
        "pendingArtifactCount": len(pending),
        "artifactSetDigest": sha(pretty(rows)),
        "fenceProof": {
            "baseHead": APP_BASE_HEAD,
            "baseTree": APP_BASE_TREE,
            "pathFenceDigest": FENCE_DIGEST,
            "allowedPathCount": 24,
            "existingPathCount": 4,
            "newPathCount": 20,
            "priorFenceCount": PRIOR_FENCE_COUNT,
            "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
            "priorFenceOverlapCount": len(PRIOR_FENCE_OVERLAP_EDGES),
            "authorizedPriorFenceOverlapCount": len(PRIOR_FENCE_OVERLAP_EDGES),
            "unauthorizedPriorFenceOverlapCount": 0,
            "authorizedOverlapEdges": PRIOR_FENCE_OVERLAP_EDGES,
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "activeS10ReservationDigest": S10_RESERVATION_DIGEST,
            "activeS10Overlap": False,
        },
        "sourceProjection": source,
        "fixtureProjection": fixture,
        "testMethods": methods,
        "evidenceIDs": EVIDENCE_IDS,
        "strictSchemaCount": 6,
        "contractDocumentCount": 5,
        "privacyAllowlistOnly": True,
        "noNetwork": True,
        "noRuntimeDownloads": True,
        "noNewSwiftDataV6Entity": True,
        "declarationOnly": True,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "provisional": True,
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    if len(PATH_FENCE) != 24 or len(set(PATH_FENCE)) != 24:
        raise ContractError("Card 34 path fence must contain exactly 24 unique paths")
    methods = _test_methods(root)
    source = _source_projection(root)
    fixture = _fixture_projection(root)
    _test_projection(root, methods)
    # Validate all nine fenced source rows before any generated bytes are
    # returned.  This prevents a partial set of apparently healthy contracts.
    source_bindings(root, methods, fixture)
    generated: dict[str, bytes] = {
        RESPONSE_SCHEMA: pretty(_response_schema()),
        FIELD_SCHEMA: pretty(_field_schema()),
        DECIMAL_SCHEMA: pretty(_decimal_schema()),
        UNIT_SCHEMA: pretty(_unit_schema()),
        MEASUREMENT_SCHEMA: pretty(_measurement_schema()),
        EVIDENCE_SCHEMA: pretty(_evidence_schema()),
        RESPONSE_DOC: pretty(seal(response_contract(root, source, methods, fixture))),
        MEASUREMENT_DOC: pretty(seal(measurement_contract(root, source, methods, fixture))),
        REPEAT_DOC: pretty(seal(repeat_contract(root, source, methods, fixture))),
        LEGACY_DOC: pretty(seal(legacy_contract(root, source, methods, fixture))),
        EVIDENCE_DOC: pretty(seal(evidence_contract(root, source, methods, fixture))),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated, source, methods, fixture))
    return generated
