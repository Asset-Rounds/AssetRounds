#!/usr/bin/env python3
"""Deterministic V23-P00-C09 test-plan and UI-harness contracts."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any

from c07_contracts import (
    DEPENDENCY_DISPOSITION_DIGEST,
    GRAPH_DIGEST,
    OVERRIDE_RECEIPT_DIGEST,
    PACKAGE_DIGEST,
    REGISTER_DIGEST,
    RELATION_DIGEST,
    RESERVATION_DIGEST,
    SELECTOR_DIGEST,
    digest,
    load_reservation,
    normalized,
    pretty_bytes,
    seal,
    sha256_bytes,
    validate_frozen_authority,
)


CARD_ID = "V23-P00-C09"
BASE_HEAD = "506887f637679d2416657c99638069605e4ca918"
BASE_TREE = "50fe6f3696e7fd7675b4be1ae2f231cdb7c71a87"
CONTEXT_DIGEST = "46c382016f5600610d421abdcf4f5a3e486bc0d8c01e791c1b31d6d33513041c"
BOOTSTRAP_FENCE_DIGEST = "7138b44784ebe79a77e3bb243e6048f50d05b4ffd37cf74664bcdb800c54b36e"
PROVISIONAL_PREREQUISITE_DIGEST = "d44bd9940a710ba151ce21d5e9d5b746d9443dc6bf87d7f305f6ce50aae3b2a2"
LEDGER_DIGEST = "2e042673a4eb518e480cc12a03f1f09b61b3b752ae955bf2bbcb05341132398c"
LEDGER_CAS_SEQUENCE = 23
DOSSIER_DIGEST = "bc821da9b06681f3682e87a11900be0a6bb0e816c40262a11c040f26c9bf9cb9"
C07_ALLOCATION_DIGEST = "a3974f7989a5efe5674af12e5d73710be06a87ac5c609a8dd504ee00c38d4a0a"
C07_MANIFEST_DIGEST = "1d339540d38e8378b861ef827713d0347197219b0d133c13a8b8de5949608619"

UNIT_TARGET = {"containerPath": "container:FieldEvidenceApp.xcodeproj", "identifier": "A00000000000000000000031", "name": "FieldEvidenceAppTests"}
UI_TARGET = {"containerPath": "container:FieldEvidenceApp.xcodeproj", "identifier": "A00000000000000000000032", "name": "FieldEvidenceAppUITests"}
APP_TARGET = {"containerPath": "container:FieldEvidenceApp.xcodeproj", "identifier": "A00000000000000000000030", "name": "FieldEvidenceApp"}

PLAN_PATHS = [
    "TestPlans/V23-FastPR.xctestplan",
    "TestPlans/V23-ReleaseCandidate.xctestplan",
    "TestPlans/V23-StoreKitRegression.xctestplan",
    "TestPlans/V23-Sanitizers.xctestplan",
    "TestPlans/V23-DiagnosticSweep.xctestplan",
]
SCHEMA_PATHS = [
    "Scripts/v23/test-plan-release.schema.json",
    "Scripts/v23/ui-test-scenario.schema.json",
    "Scripts/v23/page-robot-registry.schema.json",
    "Scripts/v23/viewport-contract.schema.json",
    "Scripts/v23/source-lock-elimination-receipt.schema.json",
    "Scripts/v23/test-plan-acceptance-receipt.schema.json",
    "Scripts/v23/test-plan-enrollment-receipt.schema.json",
    "Scripts/v23/ui-test-scenario-digest.schema.json",
]
ARTIFACT_PATHS = [
    "docs/design/v23/tooling/TestPlanReleaseV1.json",
    "docs/design/v23/tooling/UITestScenarioV1.json",
    "docs/design/v23/tooling/PageRobotRegistryV1.json",
    "docs/design/v23/tooling/ViewportContractV1.json",
    "docs/design/v23/tooling/SourceLockEliminationReceiptV1.json",
    "docs/design/v23/tooling/TestPlanAcceptanceReceiptV1.json",
    "docs/design/v23/tooling/TestPlanEnrollmentReceiptV1.json",
    "docs/design/v23/tooling/UITestScenarioDigestV1.json",
]
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C09-tooling-manifest.json"
FENCED_PATHS = [
    "Scripts/v23/c09_contracts.py", "Scripts/v23/generate_c09_contracts.py", "Scripts/v23/verify_c09_contracts.py",
    *SCHEMA_PATHS, *PLAN_PATHS, *ARTIFACT_PATHS, MANIFEST_PATH,
]

PLAN_DEFINITIONS = [
    {"id": "FAST_PR", "path": PLAN_PATHS[0], "name": "V23 FastPR", "configurationID": "C0900000-0000-4000-8000-000000000001", "gating": True, "diagnostic": False, "targets": "FAST"},
    {"id": "RELEASE_CANDIDATE", "path": PLAN_PATHS[1], "name": "V23 ReleaseCandidate", "configurationID": "C0900000-0000-4000-8000-000000000002", "gating": True, "diagnostic": False, "targets": "ALL"},
    {"id": "STOREKIT_REGRESSION", "path": PLAN_PATHS[2], "name": "V23 StoreKitRegression", "configurationID": "C0900000-0000-4000-8000-000000000003", "gating": True, "diagnostic": False, "targets": "STOREKIT"},
    {"id": "SANITIZERS", "path": PLAN_PATHS[3], "name": "V23 Sanitizers", "configurationID": "C0900000-0000-4000-8000-000000000004", "gating": True, "diagnostic": False, "targets": "SANITIZERS"},
    {"id": "DIAGNOSTIC_SWEEP", "path": PLAN_PATHS[4], "name": "V23 DiagnosticSweep", "configurationID": "C0900000-0000-4000-8000-000000000005", "gating": False, "diagnostic": True, "targets": "ALL"},
]


class ContractError(ValueError):
    pass


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST, "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST, "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST, "bootstrapPathFenceDigest": BOOTSTRAP_FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PROVISIONAL_PREREQUISITE_DIGEST,
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "ledgerDigest": LEDGER_DIGEST, "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False, "acceptanceEnabled": False,
        "hostedDispatchEnabled": False, "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True, "releaseCredit": False,
    }


def validate_fence(root: Path) -> None:
    changed = subprocess.run(
        ["git", "-C", str(root), "diff", "--name-only", BASE_HEAD], check=True,
        capture_output=True, text=True, encoding="utf-8",
    ).stdout.splitlines()
    changed_set = {line.replace("\\", "/") for line in changed if line}
    if not changed_set <= set(FENCED_PATHS):
        raise ContractError(f"C09 out-of-fence delta: {sorted(changed_set - set(FENCED_PATHS))}")
    status = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"], check=True,
        capture_output=True, text=True, encoding="utf-8",
    ).stdout.splitlines()
    for line in status:
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C09 delete/rename outside contract: {line}")
        if raw.replace("\\", "/") not in FENCED_PATHS:
            raise ContractError(f"C09 untracked/out-of-fence path: {raw}")


def validate_c07_input(root: Path) -> list[dict[str, Any]]:
    allocation = json.loads((root / "docs/design/v23/tooling/V21C07RequirementAllocationV1.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C07-tooling-manifest.json").read_text(encoding="utf-8"))
    if allocation.get("artifactDigest") != C07_ALLOCATION_DIGEST or manifest.get("artifactDigest") != C07_MANIFEST_DIGEST:
        raise ContractError("C07 prerequisite contract artifact differs")
    rows = [row for row in allocation["rows"] if row["soleOwner"] == CARD_ID]
    if len(rows) != 11:
        raise ContractError("C09 must receive exactly 11 C07 allocation rows")
    return rows


def swift_test_inventory(root: Path, directory: str) -> list[dict[str, Any]]:
    rows = []
    for path in sorted((root / directory).glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        classes = re.findall(r"final\s+class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase", text)
        methods = re.findall(r"\bfunc\s+(test[A-Za-z0-9_]+)\s*\(", text)
        if len(classes) != 1:
            raise ContractError(f"expected one XCTestCase class: {path}")
        rows.append({"path": normalized(path, root), "className": classes[0], "testMethods": methods, "sourceSHA256": sha256_bytes(path.read_bytes())})
    return rows


def ui_identifiers(text: str) -> list[str]:
    return sorted(set(re.findall(r'"(s[0-9][A-Za-z0-9._-]+)"', text)))


def page_robot_rows(root: Path, ui_inventory: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for item in ui_inventory:
        source = (root / item["path"]).read_text(encoding="utf-8")
        rows.append({
            "robotID": item["className"].removesuffix("UITests") + "Robot",
            "legacyTestClass": item["className"], "sourcePath": item["path"],
            "semanticIdentifiers": ui_identifiers(source),
            "implementationDisposition": "REGISTRY_BOUND_ROBOT_EXTRACTION_DEFERRED",
        })
    return rows


def source_lock_findings(root: Path) -> list[dict[str, Any]]:
    patterns = [
        ("SOURCE_OCCURRENCE_COUNT_LOCK", re.compile(r"components\s*\(\s*separatedBy:.*?\)\.count\s*-\s*1")),
        ("PROJECT_SOURCE_TEXT_LOCK", re.compile(r"(?:project|source|releaseBytes|workflow)[A-Za-z0-9_]*\.contains\s*\(")),
        ("DIRECT_SOURCE_TEXT_LOCK", re.compile(r"\bscript(?:\.lowercased\(\))?\.contains\s*\(")),
        ("SOURCE_AGGREGATION_LOCK", re.compile(r"(?:applicationSwiftSource|allReleaseText|workflowText)\s*\(")),
    ]
    rows = []
    for directory in ("FieldEvidenceAppTests", "FieldEvidenceAppUITests"):
        for path in sorted((root / directory).glob("*.swift")):
            validator_parameter: str | None = None
            validator_brace_depth = 0
            for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                signature = re.search(
                    r"\bfunc\s+validate(?:Workflow|Source|Script|Project)[A-Za-z0-9_]*\s*\(\s*_\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*String",
                    line,
                )
                if signature:
                    validator_parameter = signature.group(1)
                    validator_brace_depth = 0
                for kind, pattern in patterns:
                    if pattern.search(line):
                        rows.append({
                            "path": normalized(path, root), "line": line_number, "kind": kind,
                            "evidenceSHA256": sha256_bytes(line.strip().encode()),
                            "disposition": "REQUIRES_SEMANTIC_MANIFEST_OR_PARSER_REPLACEMENT",
                        })
                if validator_parameter and re.search(
                    rf"\b{re.escape(validator_parameter)}(?:\.lowercased\(\))?\.contains\s*\(",
                    line,
                ):
                    rows.append({
                        "path": normalized(path, root), "line": line_number,
                        "kind": "SOURCE_VALIDATOR_TEXT_LOCK",
                        "evidenceSHA256": sha256_bytes(line.strip().encode()),
                        "disposition": "REQUIRES_SEMANTIC_MANIFEST_OR_PARSER_REPLACEMENT",
                    })
                if validator_parameter:
                    validator_brace_depth += line.count("{") - line.count("}")
                    if validator_brace_depth <= 0:
                        validator_parameter = None
    return rows


def target(value: dict[str, str], selected: list[str] | None = None) -> dict[str, Any]:
    row: dict[str, Any] = {"target": value}
    if selected:
        row["selectedTests"] = selected
    return row


def plan_json(definition: dict[str, Any]) -> dict[str, Any]:
    kind = definition["targets"]
    if kind == "FAST":
        targets = [target(UNIT_TARGET, ["S0LaunchTests", "S1PackTokenTests", "S2PersistenceLedgerTests", "S9_1ReleasePreflightTests"]), target(UI_TARGET, ["S0LaunchUITests"])]
        options: dict[str, Any] = {}
    elif kind == "STOREKIT":
        targets = [target(UNIT_TARGET, ["S7_1CommerceCoreTests", "S7_2PaywallPurchaseTests", "S7_3LifecycleRestoreTests", "S7_4DraftAccessPolicyTests", "S7_5DataRightsIntegrationTests"]), target(UI_TARGET, ["S7_2PaywallUITests", "S7_3LifecycleUITests", "S7_4AccessGateUITests", "S7_5LapseRightsUITests"])]
        options = {}
    elif kind == "SANITIZERS":
        targets = [target(UNIT_TARGET)]
        options = {"addressSanitizerEnabled": True, "undefinedBehaviorSanitizerEnabled": True}
    else:
        targets = [target(UNIT_TARGET), target(UI_TARGET)]
        options = {}
    return {
        "configurations": [{"id": definition["configurationID"], "name": "Default", "options": options}],
        "defaultOptions": {"targetForVariableExpansion": APP_TARGET},
        "testTargets": targets,
        "version": 1,
    }


def validate_plan_references(
    root: Path,
    plan_values: dict[str, dict[str, Any]],
    unit_inventory: list[dict[str, Any]],
    ui_inventory: list[dict[str, Any]],
) -> None:
    project_text = (root / "FieldEvidenceApp.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    for expected_target in (APP_TARGET, UNIT_TARGET, UI_TARGET):
        marker = f'{expected_target["identifier"]} /* {expected_target["name"]} */'
        if marker not in project_text:
            raise ContractError(f"test plan target is absent from the checked-in project: {marker}")
    class_names_by_target = {
        UNIT_TARGET["identifier"]: {row["className"] for row in unit_inventory},
        UI_TARGET["identifier"]: {row["className"] for row in ui_inventory},
    }
    for plan_path, plan in plan_values.items():
        for test_target in plan["testTargets"]:
            identifier = test_target["target"]["identifier"]
            if identifier not in class_names_by_target:
                raise ContractError(f"unknown test target in {plan_path}: {identifier}")
            selected = test_target.get("selectedTests", [])
            missing = sorted(set(selected) - class_names_by_target[identifier])
            if missing:
                raise ContractError(f"selected test classes are absent in {plan_path}: {missing}")


def scenario() -> dict[str, Any]:
    body = {
        "schema": "UITestScenarioV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority_binding(),
        "scenarioID": "c09.synthetic.empty-workspace.v1", "opaqueRunID": "c09_contract_0001",
        "sourceClassification": "SYNTHETIC_ONLY", "stateRecipe": "EMPTY_WORKSPACE",
        "fixtureDigests": [], "clock": {"initialUTC": "2026-01-14T20:02:03.000Z", "stepNanoseconds": 1000000},
        "idSeed": "c0900000000000000000000000000001", "faults": [],
        "viewport": {"deviceFamily": "IPHONE", "orientation": "PORTRAIT", "contentSizeCategory": "ACCESSIBILITY_XXXL"},
        "activationDisposition": "NOT_INSTALLED_PROVISIONAL_CONTRACT_ONLY",
        "acceptanceCredit": False, "releaseCredit": False,
    }
    return seal(body)


def common_schema(name: str, required: list[str], properties: dict[str, Any]) -> dict[str, Any]:
    digest_string = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    authority = {"type": "object", "additionalProperties": False, "required": list(authority_binding()), "properties": {
        key: ({"const": value} if not isinstance(value, dict) else {"type": "object", "additionalProperties": False, "required": list(value), "properties": {nested: {"const": nested_value} for nested, nested_value in value.items()}})
        for key, value in authority_binding().items()
    }}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": f"https://assetrounds.invalid/v23/{name}.schema.json",
        "title": name, "type": "object", "additionalProperties": False,
        "required": ["schema", "schemaVersion", "cardID", "authority", *required, "acceptanceCredit", "releaseCredit", "artifactDigest"],
        "properties": {
            "schema": {"const": name}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD_ID}, "authority": authority,
            **properties, "acceptanceCredit": {"const": False}, "releaseCredit": {"const": False}, "artifactDigest": digest_string,
        },
    }


def schemas() -> dict[str, dict[str, Any]]:
    string = {"type": "string", "minLength": 1}
    digest_string = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    array_string = {"type": "array", "items": string}
    plan_row = {"type": "object", "additionalProperties": False, "required": ["planID", "path", "sha256", "gating", "diagnosticOnly", "controllerLane", "enrollmentDisposition"], "properties": {
        "planID": string, "path": string, "sha256": digest_string, "gating": {"type": "boolean"}, "diagnosticOnly": {"type": "boolean"},
        "controllerLane": string, "enrollmentDisposition": {"const": "CHECKED_IN_UNENROLLED_RESERVED_SCHEME"},
    }}
    robot = {"type": "object", "additionalProperties": False, "required": ["robotID", "legacyTestClass", "sourcePath", "semanticIdentifiers", "implementationDisposition"], "properties": {
        "robotID": string, "legacyTestClass": string, "sourcePath": string, "semanticIdentifiers": array_string,
        "implementationDisposition": {"const": "REGISTRY_BOUND_ROBOT_EXTRACTION_DEFERRED"},
    }}
    finding = {"type": "object", "additionalProperties": False, "required": ["path", "line", "kind", "evidenceSHA256", "disposition"], "properties": {
        "path": string, "line": {"type": "integer", "minimum": 1}, "kind": string, "evidenceSHA256": digest_string,
        "disposition": {"const": "REQUIRES_SEMANTIC_MANIFEST_OR_PARSER_REPLACEMENT"},
    }}
    return {
        SCHEMA_PATHS[0]: common_schema("TestPlanReleaseV1", ["topologyOwner", "plans", "gatingPlanCount", "diagnosticPlanCount", "diagnosticCanAccept", "shardingDisposition"], {
            "topologyOwner": {"const": CARD_ID}, "plans": {"type": "array", "minItems": 5, "maxItems": 5, "items": plan_row},
            "gatingPlanCount": {"const": 4}, "diagnosticPlanCount": {"const": 1}, "diagnosticCanAccept": {"const": False}, "shardingDisposition": string,
        }),
        SCHEMA_PATHS[1]: common_schema("UITestScenarioV1", ["scenarioID", "opaqueRunID", "sourceClassification", "stateRecipe", "fixtureDigests", "clock", "idSeed", "faults", "viewport", "activationDisposition"], {
            "scenarioID": string, "opaqueRunID": {"type": "string", "pattern": "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"},
            "sourceClassification": {"const": "SYNTHETIC_ONLY"}, "stateRecipe": {"enum": ["EMPTY_WORKSPACE", "BOUNDED_SYNTHETIC_WORKSPACE"]},
            "fixtureDigests": {"type": "array", "maxItems": 32, "items": digest_string},
            "clock": {"type": "object", "additionalProperties": False, "required": ["initialUTC", "stepNanoseconds"], "properties": {"initialUTC": string, "stepNanoseconds": {"type": "integer", "minimum": 1}}},
            "idSeed": {"type": "string", "pattern": "^[0-9a-f]{32}$"}, "faults": {"type": "array", "maxItems": 8, "items": string},
            "viewport": {"type": "object", "additionalProperties": False, "required": ["deviceFamily", "orientation", "contentSizeCategory"], "properties": {"deviceFamily": {"const": "IPHONE"}, "orientation": {"enum": ["PORTRAIT", "LANDSCAPE"]}, "contentSizeCategory": string}},
            "activationDisposition": {"const": "NOT_INSTALLED_PROVISIONAL_CONTRACT_ONLY"},
        }),
        SCHEMA_PATHS[2]: common_schema("PageRobotRegistryV1", ["registryOwner", "legacyUITestClassCount", "robots", "identifierParityStatus", "robotImplementationStatus"], {
            "registryOwner": {"const": CARD_ID}, "legacyUITestClassCount": {"type": "integer", "minimum": 1},
            "robots": {"type": "array", "minItems": 1, "items": robot}, "identifierParityStatus": {"const": "INVENTORIED"},
            "robotImplementationStatus": {"const": "DEFERRED_NO_UNVALIDATED_SWIFT_ADDED"},
        }),
        SCHEMA_PATHS[3]: common_schema("ViewportContractV1", ["preconditionOrder", "requiredFacts", "strictAcceptanceFollowsPreconditions", "diagnosticGeometryNonAccepting", "nativeExecutionStatus"], {
            "preconditionOrder": {"const": ["SEMANTIC_ANCHOR", "VIEWPORT", "SAFE_AREA", "VISIBILITY", "REACHABILITY"]},
            "requiredFacts": array_string, "strictAcceptanceFollowsPreconditions": {"const": True},
            "diagnosticGeometryNonAccepting": {"const": True}, "nativeExecutionStatus": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"},
        }),
        SCHEMA_PATHS[4]: common_schema("SourceLockEliminationReceiptV1", ["scanRoots", "scanRuleDigest", "findings", "findingCount", "eliminationSatisfied", "disposition"], {
            "scanRoots": {"const": ["FieldEvidenceAppTests", "FieldEvidenceAppUITests"]}, "scanRuleDigest": digest_string,
            "findings": {"type": "array", "items": finding}, "findingCount": {"type": "integer", "minimum": 0},
            "eliminationSatisfied": {"const": False}, "disposition": {"const": "PROVISIONAL_FINDINGS_REMAIN"},
        }),
        SCHEMA_PATHS[5]: common_schema("TestPlanAcceptanceReceiptV1", ["planReleaseDigest", "scenarioDigest", "pageRobotRegistryDigest", "viewportContractDigest", "sourceLockReceiptDigest", "nativePlanDiscovery", "e2eSubstitutionPrevented", "disposition"], {
            "planReleaseDigest": digest_string, "scenarioDigest": digest_string, "pageRobotRegistryDigest": digest_string,
            "viewportContractDigest": digest_string, "sourceLockReceiptDigest": digest_string,
            "nativePlanDiscovery": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"}, "e2eSubstitutionPrevented": {"const": True},
            "disposition": {"const": "PROVISIONAL_NOT_ACCEPTABLE"},
        }),
        SCHEMA_PATHS[6]: common_schema("TestPlanEnrollmentReceiptV1", ["expectedPlanCount", "checkedInPlanCount", "enrolledPlanCount", "schemePath", "schemeReservedByS10", "controllerRoutingStatus", "disposition"], {
            "expectedPlanCount": {"const": 5}, "checkedInPlanCount": {"const": 5}, "enrolledPlanCount": {"const": 0},
            "schemePath": {"const": "FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme"},
            "schemeReservedByS10": {"const": True}, "controllerRoutingStatus": {"const": "DECLARED_NOT_ACTIVATED"},
            "disposition": {"const": "DEFERRED_ACCEPTED_S10_6_RECONCILIATION_REQUIRED"},
        }),
        SCHEMA_PATHS[7]: common_schema("UITestScenarioDigestV1", ["scenarioArtifactDigest", "canonicalization", "digestAlgorithm", "maximumEncodedBytes", "observedEncodedBytes", "arbitraryPathAllowed", "unknownFieldDisposition", "corruptDigestDisposition"], {
            "scenarioArtifactDigest": digest_string, "canonicalization": {"const": "UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE_V1"},
            "digestAlgorithm": {"const": "SHA256"}, "maximumEncodedBytes": {"const": 65536},
            "observedEncodedBytes": {"type": "integer", "minimum": 1}, "arbitraryPathAllowed": {"const": False},
            "unknownFieldDisposition": {"const": "REJECT"}, "corruptDigestDisposition": {"const": "REJECT"},
        }),
    }


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    validate_frozen_authority(root)
    validate_fence(root)
    allocation_rows = validate_c07_input(root)
    reservation = load_reservation(root)
    if set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C09 fence overlaps frozen S10 reservation")
    unit_inventory = swift_test_inventory(root, "FieldEvidenceAppTests")
    ui_inventory = swift_test_inventory(root, "FieldEvidenceAppUITests")
    robots = page_robot_rows(root, ui_inventory)
    locks = source_lock_findings(root)
    authority = authority_binding()
    plan_values = {definition["path"]: plan_json(definition) for definition in PLAN_DEFINITIONS}
    validate_plan_references(root, plan_values, unit_inventory, ui_inventory)
    plans = [{
        "planID": definition["id"], "path": definition["path"],
        "sha256": sha256_bytes(pretty_bytes(plan_values[definition["path"]])),
        "gating": definition["gating"], "diagnosticOnly": definition["diagnostic"],
        "controllerLane": definition["id"], "enrollmentDisposition": "CHECKED_IN_UNENROLLED_RESERVED_SCHEME",
    } for definition in PLAN_DEFINITIONS]
    plan_release = seal({
        "schema": "TestPlanReleaseV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "topologyOwner": CARD_ID, "plans": plans, "gatingPlanCount": 4, "diagnosticPlanCount": 1,
        "diagnosticCanAccept": False,
        "shardingDisposition": "CONTROLLER_LANE_BOUND; EXACT_SHARD_MANIFEST_ACTIVATION_DEFERRED_WITH_SCHEME_ENROLLMENT",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    scenario_value = scenario()
    robot_registry = seal({
        "schema": "PageRobotRegistryV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "registryOwner": CARD_ID, "legacyUITestClassCount": len(ui_inventory), "robots": robots,
        "identifierParityStatus": "INVENTORIED", "robotImplementationStatus": "DEFERRED_NO_UNVALIDATED_SWIFT_ADDED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    viewport = seal({
        "schema": "ViewportContractV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "preconditionOrder": ["SEMANTIC_ANCHOR", "VIEWPORT", "SAFE_AREA", "VISIBILITY", "REACHABILITY"],
        "requiredFacts": ["EXPECTED_SEMANTIC_IDENTIFIER", "IPHONE_VIEWPORT_BOUNDS", "SAFE_AREA_CONTAINMENT", "NONEMPTY_VISIBLE_FRAME", "ACTION_REACHABLE_WITH_BOUNDED_SCROLL", "MINIMUM_44_POINT_CONTROL_WHERE_APPLICABLE"],
        "strictAcceptanceFollowsPreconditions": True, "diagnosticGeometryNonAccepting": True,
        "nativeExecutionStatus": "NOT_RUN_HOSTED_DISPATCH_DISABLED", "acceptanceCredit": False, "releaseCredit": False,
    })
    scan_rules = [
        "SOURCE_OCCURRENCE_COUNT_LOCK", "PROJECT_SOURCE_TEXT_LOCK", "DIRECT_SOURCE_TEXT_LOCK",
        "SOURCE_AGGREGATION_LOCK", "SOURCE_VALIDATOR_TEXT_LOCK",
    ]
    source_lock = seal({
        "schema": "SourceLockEliminationReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "scanRoots": ["FieldEvidenceAppTests", "FieldEvidenceAppUITests"], "scanRuleDigest": digest(scan_rules),
        "findings": locks, "findingCount": len(locks), "eliminationSatisfied": False,
        "disposition": "PROVISIONAL_FINDINGS_REMAIN", "acceptanceCredit": False, "releaseCredit": False,
    })
    scenario_digest = seal({
        "schema": "UITestScenarioDigestV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "scenarioArtifactDigest": scenario_value["artifactDigest"],
        "canonicalization": "UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE_V1", "digestAlgorithm": "SHA256",
        "maximumEncodedBytes": 65536, "observedEncodedBytes": len(pretty_bytes(scenario_value)),
        "arbitraryPathAllowed": False, "unknownFieldDisposition": "REJECT", "corruptDigestDisposition": "REJECT",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    acceptance = seal({
        "schema": "TestPlanAcceptanceReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "planReleaseDigest": plan_release["artifactDigest"], "scenarioDigest": scenario_digest["artifactDigest"],
        "pageRobotRegistryDigest": robot_registry["artifactDigest"], "viewportContractDigest": viewport["artifactDigest"],
        "sourceLockReceiptDigest": source_lock["artifactDigest"], "nativePlanDiscovery": "NOT_RUN_HOSTED_DISPATCH_DISABLED",
        "e2eSubstitutionPrevented": True, "disposition": "PROVISIONAL_NOT_ACCEPTABLE",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    enrollment = seal({
        "schema": "TestPlanEnrollmentReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "expectedPlanCount": 5, "checkedInPlanCount": 5, "enrolledPlanCount": 0,
        "schemePath": "FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme",
        "schemeReservedByS10": True, "controllerRoutingStatus": "DECLARED_NOT_ACTIVATED",
        "disposition": "DEFERRED_ACCEPTED_S10_6_RECONCILIATION_REQUIRED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    outputs: dict[str, dict[str, Any]] = {}
    outputs.update(schemas())
    outputs.update(plan_values)
    outputs.update({
        ARTIFACT_PATHS[0]: plan_release, ARTIFACT_PATHS[1]: scenario_value,
        ARTIFACT_PATHS[2]: robot_registry, ARTIFACT_PATHS[3]: viewport,
        ARTIFACT_PATHS[4]: source_lock, ARTIFACT_PATHS[5]: acceptance,
        ARTIFACT_PATHS[6]: enrollment, ARTIFACT_PATHS[7]: scenario_digest,
    })
    if len(allocation_rows) != 11 or len(unit_inventory) < 1 or len(ui_inventory) != 32:
        raise ContractError("C09 prerequisite or test inventory count differs")
    return outputs


def build_manifest(root: Path) -> dict[str, Any]:
    paths = [path for path in FENCED_PATHS if path != MANIFEST_PATH]
    artifacts = []
    for relative in paths:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing C09 manifest artifact: {relative}")
        artifacts.append({"path": relative, "sha256": sha256_bytes(path.read_bytes())})
    return seal({
        "schema": "V23P00C09ToolingManifestV1", "schemaVersion": 1, "cardID": CARD_ID,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "authority": authority_binding(),
        "fencedPathCount": len(FENCED_PATHS), "artifacts": artifacts,
        "c07AllocationDigest": C07_ALLOCATION_DIGEST, "c07OwnedClauseCount": 11,
        "provisionalDisposition": "FIVE_PLANS_AND_STRICT_CONTRACT_TOOLING_CHECKED_IN; SCHEME_ENROLLMENT_ROBOT_EXTRACTION_AND_NATIVE_EXECUTION_DEFERRED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
