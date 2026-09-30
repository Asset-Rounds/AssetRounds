#!/usr/bin/env python3
"""Deterministic V23-P00-C12 Swift-language-mode closure preparation."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
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
    ContractError,
    load_reservation,
    pretty_bytes,
    seal,
    sha256_bytes,
    validate_frozen_authority,
)


CARD_ID = "V23-P00-C12"
BASE_HEAD = "71aa71fe2c907d18a437f7461661e80344c66d6c"
BASE_TREE = "fc961a2217bb5b2a0044f3ff12edce0950ba9bf2"
CONTEXT_DIGEST = "e549afb029c183733eab5514345ad49cfda954fa9dc2842574faa9511fa69d81"
BOOTSTRAP_FENCE_DIGEST = "c23d8f566b104f8ebc4cf2192d5c06e447621f72871fb43811e59972a53d9b6d"
HYDRATED_SPEC_DIGEST = "5b175ba7d5b1a57b602fefb7317254d26d0b488d04653788f80e6bebe7c9cac1"
HYDRATED_FENCE_DIGEST = "6c931af2a42159eea196c467041c91b46c4cf1cdd2c2a32f2051ed69e7ee7194"
PROVISIONAL_PREREQUISITE_DIGEST = "cef1217f81665a3cb0cd22eb1d8d20f9b906f975465a07298132c01f6e2e7517"
LEDGER_DIGEST = "3c64f735a59ed5b83a5a3f25aa546fa369967e35db340fdb77b48836742a0f80"
LEDGER_CAS_SEQUENCE = 35
DOSSIER_DIGEST = "04ce1ab8d61a59434cc2bbf2410e885c4f6a15a49556874c12dfb1644895c5b5"
C07_ALLOCATION_DIGEST = "a3974f7989a5efe5674af12e5d73710be06a87ac5c609a8dd504ee00c38d4a0a"
C07_MANIFEST_DIGEST = "1d339540d38e8378b861ef827713d0347197219b0d133c13a8b8de5949608619"

PROJECT_PATH = "FieldEvidenceApp.xcodeproj/project.pbxproj"
SCHEMA_PATH = "Scripts/v23/swift-language-mode-closure-receipt.schema.json"
ARTIFACT_PATH = "docs/design/v23/tooling/SwiftLanguageModeClosureReceiptV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C12-tooling-manifest.json"
FENCED_PATHS = [
    "Scripts/v23/c12_contracts.py",
    "Scripts/v23/generate_c12_contracts.py",
    "Scripts/v23/verify_c12_contracts.py",
    SCHEMA_PATH,
    ARTIFACT_PATH,
    MANIFEST_PATH,
]

TARGET_CONFIGURATIONS = [
    ("FieldEvidenceApp", "Debug", "A00000000000000000000062"),
    ("FieldEvidenceApp", "Release", "A00000000000000000000063"),
    ("FieldEvidenceAppTests", "Debug", "A00000000000000000000064"),
    ("FieldEvidenceAppTests", "Release", "A00000000000000000000065"),
    ("FieldEvidenceAppUITests", "Debug", "A00000000000000000000066"),
    ("FieldEvidenceAppUITests", "Release", "A00000000000000000000067"),
]
HOSTILE_PATTERNS = {
    "uncheckedSendable": re.compile(r"@unchecked\s+Sendable\b"),
    "nonisolatedUnsafe": re.compile(r"nonisolated\s*\(\s*unsafe\s*\)"),
    "detachedTask": re.compile(r"\bTask\s*\.\s*detached\b"),
    "preconcurrency": re.compile(r"@preconcurrency\b"),
    "assumeIsolated": re.compile(r"\bMainActor\s*\.\s*assumeIsolated\b"),
}


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST,
        "bootstrapPathFenceDigest": BOOTSTRAP_FENCE_DIGEST,
        "hydratedSpecDigest": HYDRATED_SPEC_DIGEST,
        "hydratedPathFenceDigest": HYDRATED_FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PROVISIONAL_PREREQUISITE_DIGEST,
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "ledgerDigest": LEDGER_DIGEST,
        "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceEnabled": False,
        "hostedDispatchEnabled": False,
        "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "releaseCredit": False,
    }


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout


def validate_fence(root: Path) -> None:
    reservation = load_reservation(root)
    if len(FENCED_PATHS) != 6 or len(set(FENCED_PATHS)) != 6:
        raise ContractError("C12 fence cardinality differs")
    if set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C12 tooling fence overlaps frozen Phase10 ownership")
    required_reserved = {
        PROJECT_PATH,
        ".github/workflows/ios-ci.yml",
        "Scripts/ci-selection.json",
    }
    if not required_reserved <= set(reservation["reservedPaths"]):
        raise ContractError("C12 required native closure paths are not frozen as recorded")
    changed = {
        line.replace("\\", "/")
        for line in git(root, "diff", "--name-only", BASE_HEAD).splitlines()
        if line
    }
    if not changed <= set(FENCED_PATHS):
        raise ContractError(f"C12 out-of-fence delta: {sorted(changed - set(FENCED_PATHS))}")
    status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    for line in status.splitlines():
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C12 contains delete or rename: {line}")
        if raw.replace("\\", "/") not in FENCED_PATHS:
            raise ContractError(f"C12 contains untracked/out-of-fence work: {raw}")


def configuration_block(project: str, object_id: str) -> str:
    pattern = re.compile(
        rf"^\t\t{re.escape(object_id)} /\* [^*]+ \*/ = \{{\n(.*?)(?=^\t\t[A-F0-9]+ /\*|^/\* End XCBuildConfiguration section \*/)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(project)
    if not match:
        raise ContractError(f"missing XCBuildConfiguration {object_id}")
    return match.group(1)


def configuration_list_ids(project: str, target: str) -> list[str]:
    marker = f'/* Build configuration list for PBXNativeTarget "{target}" */ = {{'
    start = project.find(marker)
    if start < 0:
        raise ContractError(f"missing target configuration list: {target}")
    block = project[start:project.find("\n\t\t};", start)]
    return re.findall(r"\b(A[0-9A-F]{23}) /\* (?:Debug|Release) \*/", block)


def target_matrix(root: Path) -> list[dict[str, Any]]:
    project = (root / PROJECT_PATH).read_text(encoding="utf-8")
    expected_by_target: dict[str, list[str]] = {}
    rows = []
    for target, configuration, object_id in TARGET_CONFIGURATIONS:
        expected_by_target.setdefault(target, []).append(object_id)
        block = configuration_block(project, object_id)
        name = re.search(r"\n\t\t\tname = ([^;]+);", "\n" + block)
        swift = re.search(r"\n\t\t\t\tSWIFT_VERSION = ([^;]+);", "\n" + block)
        if not name or name.group(1) != configuration or not swift:
            raise ContractError(f"target/configuration mapping differs: {target}/{configuration}")
        rows.append({
            "target": target,
            "configuration": configuration,
            "buildConfigurationObjectID": object_id,
            "currentSwiftVersion": swift.group(1),
            "requiredSwiftVersion": "6.0",
            "projectPath": PROJECT_PATH,
            "projectPathReservedByActiveS10": True,
            "nativeProofStatus": "NOT_RUN_RESERVED_PROJECT_AND_HOSTED_WORKFLOW",
        })
    for target, expected in expected_by_target.items():
        if configuration_list_ids(project, target) != expected:
            raise ContractError(f"target configuration membership differs: {target}")
    if project.count("SWIFT_VERSION = 5.0;") != 6:
        raise ContractError("expected exactly six current Swift 5 target/configuration settings")
    return rows


def read_at_base(root: Path, relative: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return result.stdout if result.returncode == 0 else ""


def hostile_counts(root: Path, *, baseline: bool) -> dict[str, int]:
    paths = sorted(
        path.relative_to(root).as_posix()
        for path in (root / "FieldEvidenceApp").rglob("*.swift")
        if path.is_file()
    )
    counts = {name: 0 for name in HOSTILE_PATTERNS}
    for relative in paths:
        source = read_at_base(root, relative) if baseline else (root / relative).read_text(encoding="utf-8")
        for name, pattern in HOSTILE_PATTERNS.items():
            counts[name] += len(pattern.findall(source))
    return counts


def validate_c07_allocation(root: Path) -> list[dict[str, Any]]:
    allocation = json.loads((root / "docs/design/v23/tooling/V21C07RequirementAllocationV1.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C07-tooling-manifest.json").read_text(encoding="utf-8"))
    if allocation.get("artifactDigest") != C07_ALLOCATION_DIGEST or manifest.get("artifactDigest") != C07_MANIFEST_DIGEST:
        raise ContractError("C07 prerequisite artifacts differ")
    rows = [row for row in allocation["rows"] if row["soleOwner"] == CARD_ID]
    if len(rows) != 6 or len({row["atomicClauseID"] for row in rows}) != 6:
        raise ContractError("C12 must own exactly six unique C07 clauses")
    return rows


def prerequisite_bindings(root: Path) -> dict[str, Any]:
    c09 = json.loads((root / "docs/design/v23/tooling/V23-P00-C09-tooling-manifest.json").read_text(encoding="utf-8"))
    c11 = json.loads((root / "docs/design/v23/tooling/V23-P00-C11-tooling-manifest.json").read_text(encoding="utf-8"))
    c11_closure = json.loads((root / "docs/design/v23/tooling/ConcurrencyClosureReceiptV1.json").read_text(encoding="utf-8"))
    c11_platform = json.loads((root / "docs/design/v23/tooling/PlatformAdapterConcurrencyReceiptV1.json").read_text(encoding="utf-8"))
    if c11_closure["closureSatisfied"] or c11_platform["nativeCompileRan"]:
        raise ContractError("C11 prerequisite overclaims native concurrency closure")
    return {
        "C09ToolingManifestDigest": c09["artifactDigest"],
        "C11ToolingManifestDigest": c11["artifactDigest"],
        "C11ConcurrencyClosureDigest": c11_closure["artifactDigest"],
        "C11PlatformAdapterDigest": c11_platform["artifactDigest"],
        "C11StaticContractStatus": c11_closure["staticContractStatus"],
        "C11NativeCompileRan": c11_platform["nativeCompileRan"],
    }


def validate_receipt_semantics(
    receipt: dict[str, Any],
    reservation: dict[str, Any],
    expected_prerequisites: dict[str, Any],
) -> None:
    matrix = receipt["targetConfigurationMatrix"]
    expected_pairs = [(target, configuration) for target, configuration, _ in TARGET_CONFIGURATIONS]
    if [(row["target"], row["configuration"]) for row in matrix] != expected_pairs:
        raise ContractError("C12 target/configuration matrix is missing, extra, or reordered")
    if any(row["currentSwiftVersion"] != "5.0" or row["requiredSwiftVersion"] != "6.0" for row in matrix):
        raise ContractError("C12 Swift mode matrix differs")
    if PROJECT_PATH not in reservation["reservedPaths"] or set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C12 reservation or fence disposition differs")
    if receipt["prerequisiteBindings"] != expected_prerequisites:
        raise ContractError("C12 prerequisite binding differs")
    baseline = receipt["unsafeBoundaryRatchet"]["baselineCounts"]
    candidate = receipt["unsafeBoundaryRatchet"]["candidateCounts"]
    if candidate != baseline:
        raise ContractError("C12 introduced unsafe concurrency debt")
    if receipt["languageModeClosureSatisfied"] or receipt["nativeCompileRan"] or receipt["nativeTestsRan"]:
        raise ContractError("C12 receipt overclaims Swift 6 closure")
    if receipt["acceptanceCredit"] or receipt["releaseCredit"]:
        raise ContractError("C12 receipt grants forbidden credit")


def build_artifact(root: Path) -> dict[str, Any]:
    validate_frozen_authority(root)
    validate_fence(root)
    matrix = target_matrix(root)
    baseline = hostile_counts(root, baseline=True)
    candidate = hostile_counts(root, baseline=False)
    rows = validate_c07_allocation(root)
    prerequisites = prerequisite_bindings(root)
    reservation = load_reservation(root)
    artifact = seal({
        "schema": "SwiftLanguageModeClosureReceiptV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "authority": authority_binding(),
        "project": {
            "path": PROJECT_PATH,
            "sha256": sha256_bytes((root / PROJECT_PATH).read_bytes()),
            "reservedByActiveS10": True,
            "targetCount": 3,
            "targetConfigurationCount": 6,
            "currentSwiftVersionSettingCount": 6,
        },
        "targetConfigurationMatrix": matrix,
        "c07AllocatedClauseIDs": [row["atomicClauseID"] for row in rows],
        "c07AllocatedClauseCount": len(rows),
        "prerequisiteBindings": prerequisites,
        "unsafeBoundaryRatchet": {
            "baselineCounts": baseline,
            "candidateCounts": candidate,
            "newUncheckedCount": candidate["uncheckedSendable"] - baseline["uncheckedSendable"],
            "newUnsafeIsolationCount": candidate["nonisolatedUnsafe"] - baseline["nonisolatedUnsafe"],
            "newDetachedTaskCount": candidate["detachedTask"] - baseline["detachedTask"],
            "newPreconcurrencyCount": candidate["preconcurrency"] - baseline["preconcurrency"],
            "status": "PASS_NO_C12_PRODUCT_SOURCE_DELTA",
        },
        "platformAdapterReproof": {
            "mailBoundarySource": "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift",
            "c11PlatformAdapterDigest": prerequisites["C11PlatformAdapterDigest"],
            "staticReproofStatus": "PASS_BOUND_TO_C11_EXACT_ARTIFACT",
            "nativeCallbackEvidenceStatus": "NOT_RUN_HOSTED_DISPATCH_DISABLED",
        },
        "requiredReproofFamilies": {
            "architecture": "DEFERRED_NATIVE_EXACT_CANDIDATE",
            "lifecycle": "DEFERRED_NATIVE_EXACT_CANDIDATE",
            "interruption": "DEFERRED_NATIVE_EXACT_CANDIDATE",
            "performance": "DEFERRED_NATIVE_EXACT_CANDIDATE",
            "releaseHook": "DEFERRED_NATIVE_EXACT_CANDIDATE",
        },
        "nativeCompilerDisposition": "NOT_RUN_PROJECT_WORKFLOW_AND_SELECTOR_RESERVED_BY_ACTIVE_S10",
        "swift6DiagnosticCount": None,
        "nativeCompileRan": False,
        "nativeTestsRan": False,
        "languageModeClosureSatisfied": False,
        "staticPreparationStatus": "PASS_EXACT_SIX_CONFIGURATION_GAP_INVENTORIED",
        "provisionalDisposition": "TARGETED_STATIC_PREPARATION_NOT_SWIFT6_CLOSURE_NOT_ACCEPTABLE",
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
    validate_receipt_semantics(artifact, reservation, prerequisites)
    return artifact


def build_schema(artifact: dict[str, Any]) -> dict[str, Any]:
    def kind(value: Any) -> str:
        if isinstance(value, bool): return "boolean"
        if isinstance(value, int): return "integer"
        if isinstance(value, str): return "string"
        if isinstance(value, list): return "array"
        if isinstance(value, dict): return "object"
        if value is None: return "null"
        raise ContractError(f"unsupported schema type: {type(value)}")
    properties = {}
    for key, value in artifact.items():
        if key in ("schema", "schemaVersion", "cardID", "authority", "acceptanceCredit", "releaseCredit"):
            properties[key] = {"const": value}
        elif key == "artifactDigest":
            properties[key] = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        else:
            properties[key] = {"type": kind(value)}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/SwiftLanguageModeClosureReceiptV1.schema.json",
        "title": "SwiftLanguageModeClosureReceiptV1",
        "type": "object",
        "additionalProperties": False,
        "required": list(artifact.keys()),
        "properties": properties,
    }


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    artifact = build_artifact(root)
    return {SCHEMA_PATH: build_schema(artifact), ARTIFACT_PATH: artifact}


def build_manifest(root: Path) -> dict[str, Any]:
    artifacts = []
    for relative in FENCED_PATHS:
        if relative == MANIFEST_PATH:
            continue
        path = root / relative
        if not path.is_file():
            raise ContractError(f"C12 manifest input missing: {relative}")
        artifacts.append({
            "path": relative,
            "sha256": sha256_bytes(path.read_bytes()),
            "bytes": path.stat().st_size,
        })
    return seal({
        "schema": "V23P00C12ToolingManifestV1",
        "schemaVersion": 1,
        "cardID": CARD_ID,
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "authority": authority_binding(),
        "pathFence": FENCED_PATHS,
        "artifacts": artifacts,
        "artifactCount": len(artifacts),
        "nativeCompileRan": False,
        "phase10PollingDuringParallelExecution": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
    })
