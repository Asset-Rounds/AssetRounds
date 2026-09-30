#!/usr/bin/env python3
"""Deterministic Card 33 package-release and workflow-grammar contracts.

The module is intentionally source-derived.  The two predecessor package
files, the five kernel declarations, the V9_12 evidence test, and its corpus
are all fenced inputs.  Generated JSON is a sealed projection of those bytes;
no handwritten count or claimed implementation status is accepted in place
of a missing or contradictory input.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True


CARD = "V23-P03-C02"
TITLE = "Immutable package release and exact finite workflow-node, branch, predicate, and repeat grammar"
ORDINAL = 33

# Exact values from the committed Card 33 coordination hydration.
COORDINATION_HEAD = "710bee763bbc98b323d7c6c3d8b79c5124a4b5bb"
COORDINATION_TREE = "1b15a4dd0870f8a8d83d0fbeabe654ccc7d1b543"
APP_BASE_HEAD = "76039ad7d48f04f11f19937ed623dd28b12ea49a"
APP_BASE_TREE = "80418a317e75216c8ccc26d7acba5c6cce293d1d"
COORDINATION_CAS_SEQUENCE = 140
COORDINATION_LEDGER_DIGEST = "ae2c41c95a677ed6984a9d1f4964ee91229da8796008844d6a86df3e7b09cf23"
HYDRATION_PROJECTION_DIGEST = "03d5143ae59a79430fbbd508aa1b948768a989bb5fcfdfc1dae870409500b227"
CONTEXT_DIGEST = "3c238ced11eeffb0b7eb93f968c0e6fc7df555f64e45154bf43b696f25cf5cac"
FENCE_DIGEST = "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba"
PREREQUISITE_DIGEST = "3e8602995e4e0ef35abd72c0b56fbd274b377bd1739afb5317c63caee0b40d91"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_LENGTH = 44_217
REGISTER_ROW_DIGEST = "b1ebc559d01849908f82f944073dbbb62fa16ff67cf1e032acbb4c3fd2b3e3e3"
DOSSIER_DIGEST = "bd917763a48633bc4d33a21749ada804ad0406e269e3ad06168ea10d823205d7"
DOSSIER_LENGTH = 7_101
INHERITED_DIGEST = "97946a92ee5dec964b2f4a88df62ff05f413c852f7e44338ff184016234bb243"
INHERITED_LENGTH = 7_062
FOUNDATION_REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DIRECT_GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_MANIFEST_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_MANIFEST_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_MANIFEST_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DISPOSITION_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_MANIFEST_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

GENERATOR_VERSION = "p03-c02-contracts-v1"
GENERATOR_SEED = 230302

CONTRACT_SCRIPT = "Scripts/v23/p03_c02_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p03_c02_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p03_c02_contracts.py"
RELEASE_SCHEMA = "Scripts/v23/inspection-package-release.schema.json"
DEFINITION_SCHEMA = "Scripts/v23/workflow-definition.schema.json"
NODE_SCHEMA = "Scripts/v23/workflow-node.schema.json"
PREDICATE_SCHEMA = "Scripts/v23/branch-predicate.schema.json"
BINDING_SCHEMA = "Scripts/v23/package-release-binding.schema.json"
EVIDENCE_SCHEMA = "Scripts/v23/workflow-graph-evidence-receipt.schema.json"
RELEASE_DOC = "docs/design/v23/tooling/V23P03C02InspectionPackageReleaseContractV1.json"
GRAMMAR_DOC = "docs/design/v23/tooling/V23P03C02WorkflowGrammarContractV1.json"
VALIDATION_DOC = "docs/design/v23/tooling/V23P03C02WorkflowGraphValidationContractV1.json"
PINNING_DOC = "docs/design/v23/tooling/V23P03C02PackageReleasePinningContractV1.json"
EVIDENCE_DOC = "docs/design/v23/tooling/V23P03C02WorkflowGraphEvidenceReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C02-tooling-manifest.json"

EXISTING_PATHS = [
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
]
NEW_SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowDefinitionV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGraphValidatorV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    "FieldEvidenceAppTests/V9_12WorkflowGraphTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/InspectionKernel/V21P03C02WorkflowGraphCorpusV1.json",
]
SOURCE_PATHS = EXISTING_PATHS + NEW_SOURCE_PATHS
TOOL_PATHS = [
    CONTRACT_SCRIPT,
    GENERATOR_SCRIPT,
    VERIFIER_SCRIPT,
    RELEASE_SCHEMA,
    DEFINITION_SCHEMA,
    NODE_SCHEMA,
    PREDICATE_SCHEMA,
    BINDING_SCHEMA,
    EVIDENCE_SCHEMA,
    RELEASE_DOC,
    GRAMMAR_DOC,
    VALIDATION_DOC,
    PINNING_DOC,
    EVIDENCE_DOC,
    MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
GENERATED_PATHS = TOOL_PATHS[3:]
NEW_PATHS = NEW_SOURCE_PATHS + TOOL_PATHS

# The C02 fence intentionally extends two C01-owned package surfaces.  Keep
# the complete, independently auditable edge rows in the generated manifest;
# the counts alone are not sufficient evidence that the overlap was
# authorized.
PRIOR_FENCE_COUNT = 33
PRIOR_OWNED_PATH_COUNT = 528
PRIOR_FENCE_OVERLAP_EDGES = [
    {
        "path": EXISTING_PATHS[0],
        "priorCardID": "V23-P03-C01",
        "priorFenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3",
        "disposition": "EXTEND_C01_CANONICAL_PACKAGE_AND_BUNDLED_REGISTRY_WITH_IMMUTABLE_RELEASE_AND_FINITE_WORKFLOW_BINDING_WHILE_PRESERVING_C01_SCHEMA2_BYTES_CLOSED_REGISTRY_AND_SIGN_PARITY",
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
        "priorCardID": "V23-P03-C01",
        "priorFenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3",
        "disposition": "EXTEND_C01_CANONICAL_PACKAGE_AND_BUNDLED_REGISTRY_WITH_IMMUTABLE_RELEASE_AND_FINITE_WORKFLOW_BINDING_WHILE_PRESERVING_C01_SCHEMA2_BYTES_CLOSED_REGISTRY_AND_SIGN_PARITY",
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
]

EVIDENCE_FAMILIES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in EVIDENCE_FAMILIES]
EVIDENCE_OUTCOMES = {
    "G01": "VALIDATED_IMMUTABLE_PACKAGE_RELEASE_AND_CLOSED_FINITE_WORKFLOW_GRAMMAR",
    "A01": "CYCLE_COUNT_DEPTH_PREDICATE_UNKNOWN_AND_MISSING_INPUTS_FAIL_CLOSED",
    "H01": "PUBLISHED_RELEASE_IS_IMMUTABLE_AND_TRANSITION_OR_HASH_TAMPERING_FAILS_CLOSED",
    "I01": "EVERY_PUBLICATION_BOUNDARY_RELAUNCHES_TO_ZERO_OR_COMPLETE_VALIDATED_RELEASE",
    "R01": "RELEASE_BINDING_RESUME_AND_DORMANT_REVERT_PRESERVE_EXACT_BYTES_AND_RECEIPTS",
}

NODE_KINDS = [
    "SECTION",
    "INSTRUCTION",
    "FACT",
    "EVIDENCE_REQUEST",
    "BRANCH",
    "REPEAT_GROUP",
    "REVIEW",
    "TERMINAL",
]
PREDICATE_KINDS = [
    "EXISTS",
    "IS_KNOWN",
    "EQUALS",
    "IN_SET",
    "COMPARE_FIXED",
    "NOT",
    "ALL",
    "ANY",
]
TRUTH_VALUES = ["TRUE", "FALSE", "UNKNOWN"]
COMPARISON_OPERATORS = [
    "LESS_THAN",
    "LESS_THAN_OR_EQUAL",
    "EQUAL",
    "GREATER_THAN_OR_EQUAL",
    "GREATER_THAN",
]
FAILURE_VALUES = [
    "invalidValue",
    "unknownKind",
    "limitExceeded",
    "duplicateIdentity",
    "missingTarget",
    "missingFieldID",
    "forwardPredicateReference",
    "unreachableNode",
    "cycleDetected",
    "invalidCardinality",
    "incompatibleVersion",
    "hashMismatch",
    "immutableRelease",
    "invalidTransition",
    "releaseNotFound",
    "publicationInterrupted",
]
RELEASE_STATUSES = ["DRAFT", "TESTED", "PUBLISHED"]
BINDING_KINDS = ["DRAFT", "ACTIVE", "COMPLETED", "AMENDMENT", "EXPORT"]
RELEASE_BOUNDARIES = [
    "BEFORE_VALIDATION",
    "AFTER_VALIDATION_BEFORE_PUBLICATION",
    "AFTER_PUBLICATION_BEFORE_RECEIPT",
]
NEGATIVE_CASES = [
    "COUNT_LIMIT",
    "CYCLE",
    "DEPTH_LIMIT",
    "FIELD_COUNT_LIMIT",
    "FORWARD_PREDICATE_REFERENCE",
    "MISSING_FIELD_ID",
    "MISSING_TARGET",
    "NESTED_REPEAT_ESCAPE",
    "PREDICATE_DEPTH_LIMIT",
    "REPEAT_BODY_ESCAPE",
    "REPEAT_BODY_OUTSIDE_ENTRY",
    "UNKNOWN_NODE_KIND",
    "UNKNOWN_PREDICATE_KIND",
]
LIFECYCLE_DELTAS = [
    "schemaBehaviorDelta",
    "migrationBehaviorDelta",
    "backupBehaviorDelta",
    "restoreBehaviorDelta",
    "deleteBehaviorDelta",
    "exportBehaviorDelta",
]
EXPECTED_LIMITS = {
    "maximumNodeCount": 128,
    "maximumEdgeCount": 384,
    "maximumFieldCount": 128,
    "maximumGraphDepth": 32,
    "maximumBranchCount": 32,
    "maximumPredicateDepth": 8,
    "maximumPredicateOperands": 16,
    "maximumSetOperandCount": 32,
    "maximumRepeatCount": 32,
    "maximumTotalExecutions": 4_096,
    "maximumIDBytes": 128,
}


class ContractError(ValueError):
    """Raised when a Card 33 source or generated contract is not truthful."""


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
        raise ContractError(f"non-UTF-8 source input: {relative}") from error


def _json(root: Path, relative: str) -> dict[str, Any]:
    try:
        value = json.loads(_read(root, relative))
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid JSON input {relative}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"JSON input is not an object: {relative}")
    return value


def _require_text_tokens(root: Path, relative: str, tokens: list[str]) -> str:
    text = _text(root, relative)
    lowered = text.lower()
    missing = [token for token in tokens if token.lower() not in lowered]
    if missing:
        raise ContractError(f"{relative}: required source tokens absent: {missing}")
    return text


def _enum_body(text: str, enum_name: str) -> str:
    match = re.search(
        rf"\benum\s+{re.escape(enum_name)}\b[^{{]*\{{(.*?)\n\}}",
        text,
        re.S,
    )
    if match is None:
        raise ContractError(f"missing Swift enum: {enum_name}")
    return match.group(1)


def _swift_enum_values(text: str, enum_name: str) -> list[str]:
    body = _enum_body(text, enum_name)
    values = re.findall(r"\bcase\s+[A-Za-z0-9_]+\s*=\s*\"([^\"]+)\"", body)
    if not values:
        raise ContractError(f"Swift enum has no raw values: {enum_name}")
    if len(values) != len(set(values)):
        raise ContractError(f"duplicate Swift enum values: {enum_name}")
    return values


def _swift_case_names(text: str, enum_name: str) -> list[str]:
    body = _enum_body(text, enum_name)
    names = re.findall(r"\bcase\s+([A-Za-z0-9_]+)(?:\s*=|\s*$)", body, re.M)
    if not names:
        raise ContractError(f"Swift enum has no cases: {enum_name}")
    if len(names) != len(set(names)):
        raise ContractError(f"duplicate Swift enum cases: {enum_name}")
    return names


def _static_ints(text: str, names: list[str]) -> dict[str, int]:
    result: dict[str, int] = {}
    for name in names:
        match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*([0-9][0-9_]*)", text)
        if match is None:
            raise ContractError(f"missing Swift limit: {name}")
        result[name] = int(match.group(1).replace("_", ""))
    return result


def _static_bool(text: str, name: str) -> bool:
    match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*(true|false)", text)
    if match is None:
        raise ContractError(f"missing Swift boolean: {name}")
    return match.group(1) == "true"


def _static_string(text: str, name: str) -> str:
    match = re.search(rf"\bstatic\s+let\s+{re.escape(name)}\s*=\s*\"([^\"]+)\"", text)
    if match is None:
        raise ContractError(f"missing Swift string: {name}")
    return match.group(1)


def _test_methods(root: Path) -> list[str]:
    text = _text(root, NEW_SOURCE_PATHS[5])
    methods = re.findall(r"\bfunc\s+(testV9_12[A-Za-z0-9_]*)\s*\(", text)
    if len(methods) != 5 or len(set(methods)) != 5:
        raise ContractError(f"expected exactly five V9_12 methods, found {methods}")
    families: list[str] = []
    for method in methods:
        match = re.fullmatch(r"testV9_12([GAHIR]01).*", method)
        if match is None:
            raise ContractError(f"test method lacks a G/A/H/I/R family: {method}")
        families.append(match.group(1))
    if sorted(families) != sorted(EVIDENCE_FAMILIES):
        raise ContractError(f"V9_12 evidence families differ: {methods}")
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
        "lineage": "REFINED_WITHOUT_LOSS",
        "lineageSource": "V21-P03-C02",
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
        "directPrerequisites": ["V23-P03-C01"],
        "invalidationConsumers": [
            "V23-P03-C03",
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
        "persistentContractSchema": "KERNEL_CONTRACT_V1",
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


def _grammar_projection(root: Path) -> dict[str, Any]:
    grammar = _require_text_tokens(
        root,
        NEW_SOURCE_PATHS[0],
        [
            "InspectionKernelFailureV1",
            "WorkflowNodeKindV1",
            "BranchPredicateKindV1",
            "BranchTruthValueV1",
            "FixedComparisonOperatorV1",
            "BranchPredicateV1",
            "WorkflowBranchDestinationsV1",
            "values.allSatisfy(WorkflowGrammarValidationV1.validID)",
            "destination(for value: BranchTruthValueV1)",
            "WorkflowGrammarLimitsV1",
            "WorkflowGrammarValidationV1",
            "CaseIterable",
            "maximumNodeCount",
            "maximumEdgeCount",
            "maximumFieldCount",
            "maximumGraphDepth",
            "maximumBranchCount",
            "maximumPredicateDepth",
            "maximumPredicateOperands",
            "maximumSetOperandCount",
            "maximumRepeatCount",
            "maximumTotalExecutions",
            "maximumIDBytes",
            "validID",
        ],
    )
    failure_cases = _swift_case_names(grammar, "InspectionKernelFailureV1")
    if failure_cases != FAILURE_VALUES:
        raise ContractError(f"kernel failure cases differ: {failure_cases}")
    node_values = _swift_enum_values(grammar, "WorkflowNodeKindV1")
    predicate_values = _swift_enum_values(grammar, "BranchPredicateKindV1")
    truth_values = _swift_enum_values(grammar, "BranchTruthValueV1")
    comparison_values = _swift_enum_values(grammar, "FixedComparisonOperatorV1")
    if node_values != NODE_KINDS:
        raise ContractError(f"workflow node kinds differ: {node_values}")
    if predicate_values != PREDICATE_KINDS:
        raise ContractError(f"predicate kinds differ: {predicate_values}")
    if truth_values != TRUTH_VALUES:
        raise ContractError(f"branch truth values differ: {truth_values}")
    if comparison_values != COMPARISON_OPERATORS:
        raise ContractError(f"comparison operators differ: {comparison_values}")
    limits = _static_ints(grammar, list(EXPECTED_LIMITS))
    if limits != EXPECTED_LIMITS:
        raise ContractError(f"workflow grammar limits differ: {limits}")
    return {
        "failureKinds": failure_cases,
        "nodeKinds": node_values,
        "predicateKinds": predicate_values,
        "truthValues": truth_values,
        "comparisonOperators": comparison_values,
        "limits": limits,
        "identifierRule": "NONEMPTY_LOWERCASE_ASCII_DASH_DOT_UNDERSCORE_WITHIN_MAXIMUM_ID_BYTES",
        "predicateRule": "KIND_SPECIFIC_EXACT_FIELDS_AND_RECURSIVE_DEPTH_BOUNDED_OPERANDS",
        "branchRule": "TRUE_FALSE_UNKNOWN_DESTINATIONS_ARE_EXPLICIT_VALID_IDS_CONVERGENCE_ALLOWED",
        "truthResolution": "ONE_TRUTH_VALUE_SELECTS_EXACTLY_ONE_DESTINATION",
        "repeatRule": "BOUNDED_REPEAT_GROUP_WITH_EXPLICIT_BODY_ENTRY_EXIT_AND_MAXIMUM_INSTANCES",
    }


def _release_projection(root: Path) -> dict[str, Any]:
    release = _require_text_tokens(
        root,
        NEW_SOURCE_PATHS[3],
        [
            "InspectionPackageReleaseV1",
            "InspectionPackageReleaseStateV1",
            "packageReleaseID",
            "canonicalPackageBytes",
            "packageID",
            "packageContentVersion",
            "packageSHA256",
            "canonicalWorkflowBytes",
            "workflowSHA256",
            "validate",
            "makeDraft",
            "InspectionPackageReleasePublisherV1",
            "InspectionPackageReleaseCanonicalCodecV1",
            "DRAFT",
            "TESTED",
            "PUBLISHED",
        ],
    )
    release_states = _swift_enum_values(release, "InspectionPackageReleaseStateV1")
    if release_states != RELEASE_STATUSES:
        raise ContractError(f"release states differ: {release_states}")
    return {
        "type": "InspectionPackageReleaseV1",
        "statuses": release_states,
        "requiredBindings": [
            "packageReleaseID",
            "packageID",
            "packageContentVersion",
            "packageSHA256",
            "canonicalPackageBytes",
            "workflowSHA256",
            "canonicalWorkflowBytes",
        ],
        "canonicalCodec": "InspectionPackageReleaseCanonicalCodecV1",
        "canonicalRules": [
            "UTF8",
            "SORTED_KEYS",
            "WITHOUT_ESCAPING_SLASHES",
            "NO_FLOATING_POINT",
            "MAXIMUM_CANONICAL_BYTES_1048576",
            "ROUND_TRIP_BYTE_EQUALITY",
        ],
        "immutableAfterPublication": True,
        "draftTestPublishTransitions": True,
        "releaseSourceDigest": sha(release.encode("utf-8")),
    }


def _binding_projection(root: Path) -> dict[str, Any]:
    binding = _require_text_tokens(
        root,
        NEW_SOURCE_PATHS[4],
        [
            "PackageReleaseBindingV1",
            "PackageReleaseBindingKindV1",
            "PackageReleaseBindingCanonicalCodecV1",
            "validateResume",
            "packageReleaseID",
            "packageContentVersion",
            "packageSHA256",
            "canonicalPackageBytes",
            "workflowSHA256",
            "canonicalWorkflowBytes",
            "makeDraft",
            "DRAFT",
            "ACTIVE",
            "COMPLETED",
            "AMENDMENT",
            "EXPORT",
        ],
    )
    kinds = _swift_enum_values(binding, "PackageReleaseBindingKindV1")
    if kinds != BINDING_KINDS:
        raise ContractError(f"binding kinds differ: {kinds}")
    return {
        "type": "PackageReleaseBindingV1",
        "kinds": kinds,
        "requiredFields": [
            "schemaVersion",
            "bindingID",
            "kind",
            "packageReleaseID",
            "packageID",
            "packageContentVersion",
            "packageSHA256",
            "canonicalPackageBytes",
            "workflowSHA256",
            "canonicalWorkflowBytes",
        ],
        "resumeValidation": "EXACT_PUBLISHED_RELEASE_ID_PACKAGE_BYTES_AND_WORKFLOW_BYTES",
        "changedOrUnknownReleaseDisposition": "FAIL_CLOSED",
        "canonicalCodec": "PackageReleaseBindingCanonicalCodecV1",
        "sourceDigest": sha(binding.encode("utf-8")),
    }


def _source_projection(root: Path) -> dict[str, Any]:
    package = _require_text_tokens(
        root,
        EXISTING_PATHS[0],
        [
            "InspectionPackageV2",
            "InspectionPackageCanonicalCodecV2",
            "InspectionPackageCompatibilityValidatorV2",
            "InspectionPackageLifecycleV2",
            "InspectionPackageClosedCodingV2",
            "PACKAGE_REGISTRY_V2",
            "DECLARATION_ONLY",
            "DORMANT_REVERT_ALLOWED",
            "canonical",
            "sortedKeys",
            "withoutEscapingSlashes",
            "requireExactKeys",
            "CaseIterable",
            "allCases",
            "InspectionPackageFailureV2",
        ],
    )
    bundled = _require_text_tokens(
        root,
        EXISTING_PATHS[1],
        [
            "BundledInspectionPackageRegistryV2",
            "BUNDLED_ONLY",
            "runtimeDownloadsAllowed",
            "shippingDraftRelease",
            "InspectionPackageReleaseV1.makeDraft",
            "InspectionPackageRegistryPublisherV2.publish",
        ],
    )
    definition = _require_text_tokens(
        root,
        NEW_SOURCE_PATHS[1],
        [
            "WorkflowNodeV1",
            "WorkflowDefinitionV1",
            "validateShape",
            "outgoingNodeIDs",
            "repeatBodyEntryNodeID",
            "maximumRepeatInstances",
            "schemaVersion",
            "Sendable",
        ],
    )
    validator = _require_text_tokens(
        root,
        NEW_SOURCE_PATHS[2],
        [
            "WorkflowGraphValidatorV1",
            "validate",
            "reachable",
            "cycle",
            "maximumEdgeCount",
            "maximumGraphDepth",
            "forwardPredicateReference",
            "unreachableNode",
            "missingTarget",
        ],
    )
    binding = _require_text_tokens(
        root,
        NEW_SOURCE_PATHS[4],
        [
            "PackageReleaseBindingV1",
            "PackageReleaseBindingKindV1",
            "PackageReleaseBindingCanonicalCodecV1",
            "validateResume",
            "packageReleaseID",
            "packageContentVersion",
            "packageSHA256",
            "canonicalPackageBytes",
            "workflowSHA256",
            "canonicalWorkflowBytes",
            "makeDraft",
            "DRAFT",
            "ACTIVE",
            "COMPLETED",
            "AMENDMENT",
            "EXPORT",
        ],
    )
    grammar = _grammar_projection(root)
    release = _release_projection(root)
    binding_projection = _binding_projection(root)
    # Keep these byte digests in the generated evidence even when a source
    # implementation stores canonical payloads as Data rather than a DTO.
    return {
        "predecessorPackageContractSHA256": sha(package.encode("utf-8")),
        "predecessorBundledRegistrySHA256": sha(bundled.encode("utf-8")),
        "workflowDefinitionSHA256": sha(definition.encode("utf-8")),
        "workflowGraphValidatorSHA256": sha(validator.encode("utf-8")),
        "packageReleaseBindingSHA256": sha(binding.encode("utf-8")),
        "packageReleaseBinding": binding_projection,
        "grammar": grammar,
        "release": release,
        "kernelFailureKinds": grammar["failureKinds"],
        "sourceCount": len(SOURCE_PATHS),
    }


def _fixture_projection(root: Path) -> dict[str, Any]:
    fixture = _json(root, NEW_SOURCE_PATHS[6])
    expected_keys = [
        "bindingKinds",
        "failureDisposition",
        "interruptionBoundaries",
        "limits",
        "negativeCases",
        "nodeKinds",
        "olderResume",
        "predicateKinds",
        "releaseStates",
        "repeat",
        "schema",
        "schemaVersion",
        "testOnly",
        "truthDestinations",
        "workflowID",
    ]
    if sorted(fixture) != expected_keys:
        raise ContractError(f"workflow graph corpus keys differ: {sorted(fixture)}")
    if (
        fixture.get("schema") != "V21P03C02WorkflowGraphCorpusV1"
        or fixture.get("schemaVersion") != 1
        or fixture.get("testOnly") is not True
        or fixture.get("failureDisposition") != "FAIL_CLOSED"
        or fixture.get("nodeKinds") != sorted(NODE_KINDS)
        or fixture.get("predicateKinds") != sorted(PREDICATE_KINDS)
        or fixture.get("releaseStates") != RELEASE_STATUSES
        or fixture.get("bindingKinds") != sorted(BINDING_KINDS)
        or fixture.get("interruptionBoundaries") != sorted(RELEASE_BOUNDARIES)
        or fixture.get("negativeCases") != NEGATIVE_CASES
    ):
        raise ContractError("workflow graph corpus closed values differ")
    limits = fixture.get("limits")
    expected_fixture_limits = {key: value for key, value in EXPECTED_LIMITS.items() if key != "maximumIDBytes"}
    if limits != expected_fixture_limits:
        raise ContractError("workflow graph corpus limits differ")
    destinations = fixture.get("truthDestinations")
    repeat = fixture.get("repeat")
    expected_repeat_keys = [
        "activitySequence", "instanceID", "multiNodeBodyIDs", "nestedBodyIDs",
        "nestedRepeatCount", "repeatNodeID", "stableOrder",
    ]
    if not isinstance(repeat, dict) or sorted(repeat) != expected_repeat_keys:
        raise ContractError("workflow graph corpus repeat fixture keys differ")
    if (
        repeat.get("activitySequence") != ["ACTIVE", "INACTIVE_BY_PATH", "REACTIVATION_REVIEW_REQUIRED"]
        or repeat.get("instanceID") != "fixture.repeat.instance.0001"
        or repeat.get("multiNodeBodyIDs") != ["node.body.entry", "node.body.exit", "node.body.interior"]
        or repeat.get("nestedBodyIDs") != ["node.inner.branch", "node.inner.exit", "node.inner.repeat", "node.outer.entry", "node.outer.exit"]
        or repeat.get("nestedRepeatCount") != 2
        or repeat.get("repeatNodeID") != "node.repeat"
        or repeat.get("stableOrder") != 0
    ):
        raise ContractError("workflow graph corpus repeat containment differs")
    if not isinstance(fixture.get("olderResume"), dict) or not isinstance(repeat, dict) or not isinstance(destinations, dict):
        raise ContractError("workflow graph corpus nested fixtures are missing")
    if set(destinations) != {"TRUE", "FALSE", "UNKNOWN"} or not all(
        isinstance(value, str) and re.fullmatch(r"[a-z0-9._-]{1,128}", value) is not None
        for value in destinations.values()
    ):
        raise ContractError("workflow graph corpus truth destinations are not explicit valid IDs")
    required_markers = ["DRAFT", "ACTIVE", "COMPLETED", "BEFORE_VALIDATION", "AFTER_PUBLICATION_BEFORE_RECEIPT", "FAIL_CLOSED", "NESTED_REPEAT_ESCAPE"]
    return {
        "schemaVersion": fixture["schemaVersion"],
        "schema": fixture["schema"],
        "testOnly": fixture["testOnly"],
        "topLevelKeys": expected_keys,
        "nodeKinds": fixture["nodeKinds"],
        "predicateKinds": fixture["predicateKinds"],
        "releaseStates": fixture["releaseStates"],
        "bindingKinds": fixture["bindingKinds"],
        "interruptionBoundaries": fixture["interruptionBoundaries"],
        "negativeCases": fixture["negativeCases"],
        "limits": limits,
        "repeat": repeat,
        "truthDestinations": {key: destinations[key] for key in ("TRUE", "FALSE", "UNKNOWN")},
        "truthResolution": "ONE_TRUTH_VALUE_SELECTS_EXACTLY_ONE_DESTINATION",
        "sha256": sha(_read(root, NEW_SOURCE_PATHS[6])),
        "canonicalSHA256": sha(canonical(fixture)),
        "requiredMarkers": required_markers,
    }


def _test_projection(root: Path, methods: list[str]) -> dict[str, Any]:
    text = _text(root, NEW_SOURCE_PATHS[5])
    markers = [
        "XCTestCase",
        "XCTAssert",
        "XCTAssertThrowsError",
        "WorkflowGraphValidatorV1",
        "InspectionPackageReleaseV1",
        "PackageReleaseBindingV1",
        "relaunch",
        "interruption",
        "fail",
    ]
    missing = [marker for marker in markers if marker.lower() not in text.lower()]
    if missing:
        raise ContractError(f"{NEW_SOURCE_PATHS[5]}: evidence markers absent: {missing}")
    return {
        "path": NEW_SOURCE_PATHS[5],
        "methods": methods,
        "families": list(EVIDENCE_FAMILIES),
        "bytes": len(_read(root, NEW_SOURCE_PATHS[5])),
        "sha256": sha(_read(root, NEW_SOURCE_PATHS[5])),
    }


def source_bindings(root: Path, methods: list[str], fixture: dict[str, Any]) -> list[dict[str, Any]]:
    rows = [
        (
            EXISTING_PATHS[0],
            "predecessor-package-contract",
            ["InspectionPackageV2", "InspectionPackageCanonicalCodecV2", "InspectionPackageLifecycleV2"],
            ["PACKAGE_REGISTRY_V2", "DECLARATION_ONLY", "DORMANT_REVERT_ALLOWED", "requireExactKeys", "allCases"],
        ),
        (
            EXISTING_PATHS[1],
            "bundled-registry-release-bridge",
            ["BundledInspectionPackageRegistryV2", "InspectionPackageReleaseV1.makeDraft"],
            ["BUNDLED_ONLY", "runtimeDownloadsAllowed", "InspectionPackageRegistryPublisherV2.publish", "shippingDraftRelease"],
        ),
        (
            NEW_SOURCE_PATHS[0],
            "workflow-grammar",
            ["InspectionKernelFailureV1", "WorkflowNodeKindV1", "BranchPredicateKindV1", "BranchPredicateV1", "WorkflowGrammarLimitsV1"],
            NODE_KINDS + PREDICATE_KINDS + TRUTH_VALUES + COMPARISON_OPERATORS + list(EXPECTED_LIMITS) + ["values.allSatisfy(WorkflowGrammarValidationV1.validID)", "destination(for value: BranchTruthValueV1)"],
        ),
        (
            NEW_SOURCE_PATHS[1],
            "workflow-definition",
            ["WorkflowNodeV1", "WorkflowDefinitionV1"],
            ["validateShape", "outgoingNodeIDs", "repeatBodyEntryNodeID", "maximumRepeatInstances", "schemaVersion"],
        ),
        (
            NEW_SOURCE_PATHS[2],
            "workflow-graph-validator",
            ["WorkflowGraphValidatorV1"],
            ["reachable", "cycle", "maximumEdgeCount", "maximumGraphDepth", "forwardPredicateReference", "unreachableNode", "missingTarget"],
        ),
        (
            NEW_SOURCE_PATHS[3],
            "immutable-package-release",
            ["InspectionPackageReleaseV1"],
            ["packageReleaseID", "canonicalPackageBytes", "packageSHA256", "canonicalWorkflowBytes", "DRAFT", "TESTED", "PUBLISHED", "InspectionPackageReleasePublisherV1"],
        ),
        (
            NEW_SOURCE_PATHS[4],
            "package-release-binding",
            ["PackageReleaseBindingV1"],
            ["packageReleaseID", "packageSHA256", "canonicalPackageBytes", "validateResume", "hashMismatch", "makeDraft"],
        ),
        (
            NEW_SOURCE_PATHS[5],
            "evidence-tests",
            methods,
            ["XCTestCase", "XCTAssert", "XCTAssertThrowsError", "WorkflowGraphValidatorV1", "relaunch", "interruption", "fail"],
        ),
        (
            NEW_SOURCE_PATHS[6],
            "workflow-graph-corpus",
            ["schemaVersion"],
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


def release_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C02InspectionPackageReleaseContractV1", root, source, methods, fixture)
    value.update({
        "release": {
            "type": "InspectionPackageReleaseV1",
            "statuses": RELEASE_STATUSES,
            "identityFields": ["packageReleaseID", "packageID", "packageContentVersion", "workflowSHA256"],
            "canonicalFields": ["canonicalPackageBytes", "packageSHA256", "canonicalWorkflowBytes", "workflowSHA256"],
            "immutablePublication": True,
            "draftTestPublishTransitions": True,
            "packageAndWorkflowMustBeValidatedTogether": True,
            "unknownVersionDisposition": "FAIL_CLOSED",
            "changedPackageDisposition": "FAIL_CLOSED",
            "futureReleaseDisposition": "FAIL_CLOSED",
            "maximumCanonicalBytes": 1_048_576,
            "canonicalCodec": "InspectionPackageReleaseCanonicalCodecV1",
            "canonicalRules": ["SORTED_KEYS", "WITHOUT_ESCAPING_SLASHES", "ROUND_TRIP_BYTE_EQUALITY", "NO_FLOATING_POINT"],
            "lifecycle": {
                "mode": "DECLARATION_ONLY",
                "schema": "KERNEL_CONTRACT_V1",
                "migrationRequired": False,
                "backupRestoreRequired": False,
                "deleteEraseRequired": False,
                "exportReportRequired": False,
                "downgrade": "DORMANT_REVERT_ALLOWED",
            },
        },
        "kernelBoundary": {
            "packageNeutral": True,
            "noArbitraryScript": True,
            "noCodeBuilder": True,
            "noGenericJSONEAV": True,
            "noRemotePackageOrMarketplace": True,
            "noCustomerDataInPackageDeclarations": True,
        },
    })
    return value


def grammar_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C02WorkflowGrammarContractV1", root, source, methods, fixture)
    grammar = source["grammar"]
    value.update({
        "grammar": {
            "nodeKinds": grammar["nodeKinds"],
            "predicateKinds": grammar["predicateKinds"],
            "truthValues": grammar["truthValues"],
            "comparisonOperators": grammar["comparisonOperators"],
            "limits": grammar["limits"],
            "nodeShapeValidation": "KIND_SPECIFIC_EXACT_OPTIONAL_FIELDS_AND_OUTGOING_CARDINALITY",
            "predicateValidation": "KIND_SPECIFIC_EXACT_FIELDS_RECURSIVE_DEPTH_AND_OPERAND_LIMITS",
            "branchDestinations": "TRUE_FALSE_UNKNOWN_DESTINATIONS_ARE_EXPLICIT_VALID_IDS_CONVERGENCE_ALLOWED",
            "truthResolution": "ONE_TRUTH_VALUE_SELECTS_EXACTLY_ONE_DESTINATION",
            "repeatGroups": "EXPLICIT_ENTRY_EXIT_BOUNDED_INSTANCES_AND_TOTAL_EXECUTIONS",
            "deterministicOrdering": ["SORTED_NODE_ID", "SORTED_DECLARED_FIELD_ID", "SORTED_SET_OPERANDS"],
            "idRule": grammar["identifierRule"],
            "unknownKindDisposition": "FAIL_CLOSED",
            "unknownFieldDisposition": "FAIL_CLOSED",
            "duplicateIdentityDisposition": "FAIL_CLOSED",
            "missingTargetDisposition": "FAIL_CLOSED",
            "forwardReferenceDisposition": "FAIL_CLOSED",
        },
        "failureKinds": grammar["failureKinds"],
    })
    return value


def validation_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C02WorkflowGraphValidationContractV1", root, source, methods, fixture)
    value.update({
        "validation": {
            "validator": "WorkflowGraphValidatorV1",
            "order": [
                "SCHEMA_VERSION",
                "WORKFLOW_ID_AND_ENTRY",
                "UNIQUE_NODE_IDENTITIES",
                "DECLARED_FIELDS_AND_REFERENCES",
                "TARGET_EXISTENCE",
                "PREDICATE_FORWARD_REFERENCE",
                "REACHABILITY",
                "EDGE_AND_DEPTH_LIMITS",
                "ACYCLIC_OUTSIDE_BOUNDED_REPEAT",
                "NODE_SHAPE_AND_BRANCH_DESTINATIONS",
                "TOTAL_EXECUTION_BOUND",
            ],
            "graphProperties": [
                "DECLARED_ENTRY_REACHABLE",
                "NO_UNKNOWN_NODE_KIND",
                "NO_MISSING_TARGET",
                "NO_UNBOUNDED_CYCLE",
                "REPEAT_BODY_EXIT_IS_EXPLICIT",
            ],
            "failureKinds": FAILURE_VALUES,
            "diagnosticsNeverAccept": True,
            "invalidGraphDisposition": "FAIL_CLOSED_WITH_NO_CANONICAL_PUBLICATION",
            "validGraphDisposition": "COMPLETE_VALIDATED_IMMUTABLE_GRAPH",
        },
        "hostileInputMatrix": [
            "UNKNOWN_NODE_KIND",
            "DUPLICATE_NODE_ID",
            "MISSING_TARGET",
            "UNREACHABLE_NODE",
            "FORWARD_PREDICATE_REFERENCE",
            "CYCLE_OUTSIDE_REPEAT",
            "INVALID_NODE_CARDINALITY",
            "PREDICATE_DEPTH_OR_OPERAND_LIMIT",
            "REPEAT_TOTAL_EXECUTION_LIMIT",
            "UNKNOWN_FIELD_OR_OPTION",
        ],
    })
    return value


def pinning_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C02PackageReleasePinningContractV1", root, source, methods, fixture)
    value.update({
        "pinning": {
            "bindingType": "PackageReleaseBindingV1",
            "identity": ["packageReleaseID", "packageID", "packageContentVersion", "packageSHA256", "canonicalPackageBytes"],
            "workflowIdentity": ["workflowSHA256", "canonicalWorkflowBytes"],
            "statusTransitions": [
                "DRAFT_TO_TESTED",
                "TESTED_TO_PUBLISHED",
            ],
            "immutableStatuses": ["TESTED", "PUBLISHED"],
            "amendmentRequiresNewReleaseID": True,
            "hashMismatchDisposition": "FAIL_CLOSED",
            "changedBytesDisposition": "FAIL_CLOSED",
            "unknownOrFutureVersionDisposition": "FAIL_CLOSED",
            "olderReleaseResume": "EXACT_IMMUTABLE_BYTES_AND_HASH_REQUIRED",
            "publicationReceipt": "REQUIRED_AFTER_EFFECT_AND_CANONICAL_READBACK",
            "interruption": {
                "boundaries": RELEASE_BOUNDARIES,
                "partialPublicationAllowed": False,
                "relaunchDisposition": "RECONSTRUCT_OR_ADOPT_EXACT_RELEASE_OR_FAIL_CLOSED",
            },
        },
    })
    return value


def evidence_contract(root: Path, source: dict[str, Any], methods: list[str], fixture: dict[str, Any]) -> dict[str, Any]:
    value = _common_contract("V23P03C02WorkflowGraphEvidenceReceiptV1", root, source, methods, fixture)
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
            "UNKNOWN_NODE_KIND",
            "DUPLICATE_NODE_ID",
            "MISSING_TARGET",
            "UNREACHABLE_NODE",
            "FORWARD_PREDICATE_REFERENCE",
            "CYCLE_OUTSIDE_BOUNDED_REPEAT",
            "INVALID_CARDINALITY",
            "LIMIT_EXCEEDED",
            "UNKNOWN_RELEASE_VERSION",
            "RELEASE_HASH_MISMATCH",
            "CHANGED_IMMUTABLE_PACKAGE_BYTES",
            "PARTIAL_PUBLICATION_AFTER_INTERRUPTION",
        ],
        "interruptionBoundaries": RELEASE_BOUNDARIES,
        "interruptionPolicy": {
            "deterministic": True,
            "idempotent": True,
            "partialAcceptedState": False,
            "zeroOrCompleteValidatedResult": True,
            "relaunchContinuation": "RECONSTRUCT_OR_ADOPT_OR_FAIL_CLOSED",
        },
        "fixture": {
            "path": NEW_SOURCE_PATHS[6],
            "schemaVersion": fixture["schemaVersion"],
            "topLevelKeys": fixture["topLevelKeys"],
            "sourceSHA256": fixture["sha256"],
            "canonicalSHA256": fixture["canonicalSHA256"],
            "requiredMarkers": fixture["requiredMarkers"],
            "repeat": fixture["repeat"],
            "testOnly": True,
        },
        "brandImpact": {
            "manifestType": "BrandImpactManifestV1",
            "manifestCount": 1,
            "changedScreens": [],
            "changedStates": [],
            "affectedConsumers": [
                "V23-P03-C02",
                "V23-P03-C03",
                "V23-P04-C27:STATE_INVENTORY",
                "V23-P04-C29:EXACT_CANDIDATE",
                "V23-P05-C01:RELEASE_SELECTOR",
            ],
            "completenessRationale": "Kernel declarations and test fixtures add no UI, project metadata, launch composition, or brand asset; the closed consumer set is explicit.",
        },
        "privacy": {
            "customerDataInContracts": False,
            "customerDataInWorkflowDeclarations": False,
            "networkTransport": False,
            "userAuthoredCode": False,
            "secretsInArtifacts": False,
        },
    })
    return value


def _strict(value: Any, key: str = "") -> dict[str, Any]:
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {name: _strict(child, name) for name, child in value.items()},
        }
    if isinstance(value, list):
        return {
            "type": "array",
            "minItems": len(value),
            "maxItems": len(value),
            "prefixItems": [_strict(item) for item in value],
            "items": False,
        }
    if key == "artifactDigest" or key.lower().endswith("digest") or key.lower().endswith("sha256"):
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"const": value}
    if isinstance(value, int):
        return {"const": value}
    if isinstance(value, str):
        return {"const": value}
    raise ContractError(f"unsupported schema value at {key}: {type(value).__name__}")


def _schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{title}.schema.json",
        "title": title,
    })
    return result


SCHEMA_TITLES = {
    RELEASE_SCHEMA: "InspectionPackageReleaseV1",
    DEFINITION_SCHEMA: "WorkflowDefinitionV1",
    NODE_SCHEMA: "WorkflowNodeV1",
    PREDICATE_SCHEMA: "BranchPredicateV1",
    BINDING_SCHEMA: "PackageReleaseBindingV1",
    EVIDENCE_SCHEMA: "WorkflowGraphEvidenceReceiptV1",
}
SCHEMA_PROPERTY_FIELDS = {
    "InspectionPackageReleaseV1": [
        "schemaVersion", "packageReleaseID", "packageID", "packageContentVersion",
        "packageSHA256", "canonicalPackageBytes", "workflowSHA256", "canonicalWorkflowBytes", "state",
    ],
    "WorkflowDefinitionV1": ["schemaVersion", "workflowID", "entryNodeID", "declaredFieldIDs", "nodes"],
    "WorkflowNodeV1": [
        "nodeID", "kind", "localizationKey", "fieldID", "evidencePurposeID", "predicate",
        "branchDestinations", "repeatBodyEntryNodeID", "repeatBodyExitNodeID", "maximumRepeatInstances",
        "outgoingNodeIDs",
    ],
    "BranchPredicateV1": ["kind", "fieldID", "optionID", "optionIDs", "comparison", "fixedValue", "operands"],
    "PackageReleaseBindingV1": [
        "schemaVersion", "bindingID", "kind", "packageReleaseID", "packageID", "packageContentVersion",
        "packageSHA256", "canonicalPackageBytes", "workflowSHA256", "canonicalWorkflowBytes",
    ],
    "WorkflowGraphEvidenceReceiptV1": [
        "schemaVersion", "cardID", "evidence", "testMethods", "interruptionBoundaries", "fixture",
        "brandImpact", "privacy",
    ],
}
SCHEMA_REQUIRED_FIELDS = {
    "InspectionPackageReleaseV1": SCHEMA_PROPERTY_FIELDS["InspectionPackageReleaseV1"],
    "WorkflowDefinitionV1": SCHEMA_PROPERTY_FIELDS["WorkflowDefinitionV1"],
    "WorkflowNodeV1": ["nodeID", "kind", "outgoingNodeIDs"],
    "BranchPredicateV1": ["kind", "optionIDs", "operands"],
    "PackageReleaseBindingV1": SCHEMA_PROPERTY_FIELDS["PackageReleaseBindingV1"],
    "WorkflowGraphEvidenceReceiptV1": SCHEMA_PROPERTY_FIELDS["WorkflowGraphEvidenceReceiptV1"],
}

_ID_PATTERN = r"^[a-z0-9._-]{1,128}$"
_SHA_PATTERN = r"^[0-9a-f]{64}$"


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


def _nullable_schema(inner: dict[str, Any]) -> dict[str, Any]:
    return {"anyOf": [inner, {"type": "null"}]}


def _array_schema(item: dict[str, Any], *, minimum: int = 0, maximum: int | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "array", "items": item, "minItems": minimum}
    if maximum is not None:
        result["maxItems"] = maximum
    return result


def _object_schema(properties: dict[str, dict[str, Any]], required: list[str]) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": list(required),
        "properties": properties,
    }


def _domain_schema(title: str, shape: dict[str, Any], *, definitions: dict[str, Any] | None = None) -> dict[str, Any]:
    result = dict(shape)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{title}.schema.json",
        "title": title,
    })
    if definitions:
        result["$defs"] = definitions
    return result


def _branch_destinations_schema() -> dict[str, Any]:
    return _object_schema(
        {
            "trueNodeID": _string_schema(pattern=_ID_PATTERN),
            "falseNodeID": _string_schema(pattern=_ID_PATTERN),
            "unknownNodeID": _string_schema(pattern=_ID_PATTERN),
        },
        ["trueNodeID", "falseNodeID", "unknownNodeID"],
    )


def _predicate_shape(reference: str = "#/$defs/BranchPredicateV1") -> dict[str, Any]:
    return _object_schema(
        {
            "kind": _string_schema(enum=PREDICATE_KINDS),
            "fieldID": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "optionID": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "optionIDs": _array_schema(_string_schema(pattern=_ID_PATTERN), maximum=EXPECTED_LIMITS["maximumSetOperandCount"]),
            "comparison": _nullable_schema(_string_schema(enum=COMPARISON_OPERATORS)),
            "fixedValue": _nullable_schema(_integer_schema()),
            "operands": _array_schema({"$ref": reference}, maximum=EXPECTED_LIMITS["maximumPredicateOperands"]),
        },
        ["kind", "optionIDs", "operands"],
    )


def _node_shape(predicate_reference: str = "#/$defs/BranchPredicateV1") -> dict[str, Any]:
    branch_destinations = _nullable_schema(_branch_destinations_schema())
    branch_destinations["description"] = "TRUE_FALSE_UNKNOWN_DESTINATIONS_ARE_EXPLICIT_VALID_IDS_CONVERGENCE_ALLOWED"
    return _object_schema(
        {
            "nodeID": _string_schema(pattern=_ID_PATTERN),
            "kind": _string_schema(enum=NODE_KINDS),
            "localizationKey": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "fieldID": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "evidencePurposeID": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "predicate": _nullable_schema({"$ref": predicate_reference}),
            "branchDestinations": branch_destinations,
            "repeatBodyEntryNodeID": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "repeatBodyExitNodeID": _nullable_schema(_string_schema(pattern=_ID_PATTERN)),
            "maximumRepeatInstances": _nullable_schema(_integer_schema(minimum=1, maximum=EXPECTED_LIMITS["maximumRepeatCount"])),
            "outgoingNodeIDs": _array_schema(_string_schema(pattern=_ID_PATTERN), maximum=3),
        },
        ["nodeID", "kind", "outgoingNodeIDs"],
    )


def _release_schema() -> dict[str, Any]:
    return _domain_schema(
        SCHEMA_TITLES[RELEASE_SCHEMA],
        _object_schema(
            {
                "schemaVersion": {"const": 1},
                "packageReleaseID": _string_schema(pattern=_SHA_PATTERN),
                "packageID": _string_schema(pattern=_ID_PATTERN),
                "packageContentVersion": {"const": 1},
                "packageSHA256": _string_schema(pattern=_SHA_PATTERN),
                "canonicalPackageBytes": _string_schema(),
                "workflowSHA256": _string_schema(pattern=_SHA_PATTERN),
                "canonicalWorkflowBytes": _string_schema(),
                "state": _string_schema(enum=RELEASE_STATUSES),
            },
            SCHEMA_REQUIRED_FIELDS["InspectionPackageReleaseV1"],
        ),
    )


def _definition_schema() -> dict[str, Any]:
    return _domain_schema(
        SCHEMA_TITLES[DEFINITION_SCHEMA],
        _object_schema(
            {
                "schemaVersion": {"const": 1},
                "workflowID": _string_schema(pattern=_ID_PATTERN),
                "entryNodeID": _string_schema(pattern=_ID_PATTERN),
                "declaredFieldIDs": _array_schema(_string_schema(pattern=_ID_PATTERN), maximum=EXPECTED_LIMITS["maximumFieldCount"]),
                "nodes": _array_schema({"$ref": "#/$defs/WorkflowNodeV1"}, maximum=EXPECTED_LIMITS["maximumNodeCount"]),
            },
            SCHEMA_REQUIRED_FIELDS["WorkflowDefinitionV1"],
        ),
        definitions={
            "BranchPredicateV1": _predicate_shape(),
            "WorkflowNodeV1": _node_shape(),
        },
    )


def _node_schema() -> dict[str, Any]:
    result = _domain_schema(
        SCHEMA_TITLES[NODE_SCHEMA],
        _node_shape(),
        definitions={"BranchPredicateV1": _predicate_shape()},
    )
    result["description"] = "TRUE_FALSE_UNKNOWN_DESTINATIONS_ARE_EXPLICIT_VALID_IDS_CONVERGENCE_ALLOWED"
    return result


def _predicate_schema() -> dict[str, Any]:
    return _domain_schema(
        SCHEMA_TITLES[PREDICATE_SCHEMA],
        _predicate_shape(),
        definitions={"BranchPredicateV1": _predicate_shape()},
    )


def _binding_schema() -> dict[str, Any]:
    return _domain_schema(
        SCHEMA_TITLES[BINDING_SCHEMA],
        _object_schema(
            {
                "schemaVersion": {"const": 1},
                "bindingID": _string_schema(pattern=_ID_PATTERN),
                "kind": _string_schema(enum=BINDING_KINDS),
                "packageReleaseID": _string_schema(pattern=_SHA_PATTERN),
                "packageID": _string_schema(pattern=_ID_PATTERN),
                "packageContentVersion": {"const": 1},
                "packageSHA256": _string_schema(pattern=_SHA_PATTERN),
                "canonicalPackageBytes": _string_schema(),
                "workflowSHA256": _string_schema(pattern=_SHA_PATTERN),
                "canonicalWorkflowBytes": _string_schema(),
            },
            SCHEMA_REQUIRED_FIELDS["PackageReleaseBindingV1"],
        ),
    )


def _evidence_schema() -> dict[str, Any]:
    evidence_row = _object_schema(
        {
            "evidenceID": _string_schema(pattern=r"^V23-P03-C02-[GAHIR]01$"),
            "family": _string_schema(enum=list(EVIDENCE_FAMILIES)),
            "testMethod": _string_schema(pattern=r"^testV9_12[GAHIR]01[A-Za-z0-9_]+$"),
            "requiredOutcome": _string_schema(),
        },
        ["evidenceID", "family", "testMethod", "requiredOutcome"],
    )
    repeat = _object_schema(
        {
            "activitySequence": _array_schema(_string_schema(enum=["ACTIVE", "INACTIVE_BY_PATH", "REACTIVATION_REVIEW_REQUIRED"]), minimum=3, maximum=3),
            "instanceID": _string_schema(pattern=_ID_PATTERN),
            "multiNodeBodyIDs": _array_schema(_string_schema(pattern=_ID_PATTERN), minimum=3, maximum=3),
            "nestedBodyIDs": _array_schema(_string_schema(pattern=_ID_PATTERN), minimum=5, maximum=5),
            "nestedRepeatCount": {"const": 2},
            "repeatNodeID": _string_schema(pattern=_ID_PATTERN),
            "stableOrder": {"const": 0},
        },
        ["activitySequence", "instanceID", "multiNodeBodyIDs", "nestedBodyIDs", "nestedRepeatCount", "repeatNodeID", "stableOrder"],
    )
    fixture = _object_schema(
        {
            "path": _string_schema(),
            "schemaVersion": {"const": 1},
            "topLevelKeys": _array_schema(_string_schema(), maximum=15),
            "sourceSHA256": _string_schema(pattern=_SHA_PATTERN),
            "canonicalSHA256": _string_schema(pattern=_SHA_PATTERN),
            "requiredMarkers": _array_schema(_string_schema(), maximum=7),
            "repeat": repeat,
            "testOnly": {"const": True},
        },
        ["path", "schemaVersion", "topLevelKeys", "sourceSHA256", "canonicalSHA256", "requiredMarkers", "repeat", "testOnly"],
    )
    brand = _object_schema(
        {
            "manifestType": {"const": "BrandImpactManifestV1"},
            "manifestCount": {"const": 1},
            "changedScreens": _array_schema(_string_schema(), maximum=0),
            "changedStates": _array_schema(_string_schema(), maximum=0),
            "affectedConsumers": _array_schema(_string_schema(), maximum=5),
            "completenessRationale": _string_schema(),
        },
        ["manifestType", "manifestCount", "changedScreens", "changedStates", "affectedConsumers", "completenessRationale"],
    )
    privacy = _object_schema(
        {
            "customerDataInContracts": {"const": False},
            "customerDataInWorkflowDeclarations": {"const": False},
            "networkTransport": {"const": False},
            "userAuthoredCode": {"const": False},
            "secretsInArtifacts": {"const": False},
        },
        ["customerDataInContracts", "customerDataInWorkflowDeclarations", "networkTransport", "userAuthoredCode", "secretsInArtifacts"],
    )
    return _domain_schema(
        SCHEMA_TITLES[EVIDENCE_SCHEMA],
        _object_schema(
            {
                "schemaVersion": {"const": 1},
                "cardID": {"const": CARD},
                "evidence": _array_schema(evidence_row, minimum=5, maximum=5),
                "testMethods": _array_schema(_string_schema(), minimum=5, maximum=5),
                "interruptionBoundaries": _array_schema(_string_schema(enum=RELEASE_BOUNDARIES), minimum=3, maximum=3),
                "fixture": fixture,
                "brandImpact": brand,
                "privacy": privacy,
            },
            SCHEMA_REQUIRED_FIELDS["WorkflowGraphEvidenceReceiptV1"],
        ),
    )


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
        **common_fields("V23-P03-C02-tooling-manifest"),
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
            "existingPathCount": 2,
            "newPathCount": 22,
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
    methods = _test_methods(root)
    source = _source_projection(root)
    fixture = _fixture_projection(root)
    # Build source rows once so every contract and the manifest sees identical
    # bytes, while source_bindings still performs fail-closed token checks.
    source_bindings(root, methods, fixture)
    release = seal(release_contract(root, source, methods, fixture))
    grammar = seal(grammar_contract(root, source, methods, fixture))
    validation = seal(validation_contract(root, source, methods, fixture))
    pinning = seal(pinning_contract(root, source, methods, fixture))
    evidence = seal(evidence_contract(root, source, methods, fixture))
    generated: dict[str, bytes] = {
        RELEASE_SCHEMA: pretty(_release_schema()),
        DEFINITION_SCHEMA: pretty(_definition_schema()),
        NODE_SCHEMA: pretty(_node_schema()),
        PREDICATE_SCHEMA: pretty(_predicate_schema()),
        BINDING_SCHEMA: pretty(_binding_schema()),
        EVIDENCE_SCHEMA: pretty(_evidence_schema()),
        RELEASE_DOC: pretty(release),
        GRAMMAR_DOC: pretty(grammar),
        VALIDATION_DOC: pretty(validation),
        PINNING_DOC: pretty(pinning),
        EVIDENCE_DOC: pretty(evidence),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated, source, methods, fixture))
    return generated
