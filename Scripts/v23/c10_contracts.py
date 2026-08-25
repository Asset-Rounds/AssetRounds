#!/usr/bin/env python3
"""Deterministic V23-P00-C10 architecture and composition contracts."""

from __future__ import annotations

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
    digest,
    load_reservation,
    normalized,
    pretty_bytes,
    seal,
    sha256_bytes,
    validate_frozen_authority,
)


CARD_ID = "V23-P00-C10"
BASE_HEAD = "50c18e716575313097d1e6981ef3d444eac01ad4"
BASE_TREE = "307d5dfc0cc95f691185ad8366e3fb7e8dc448bf"
CONTEXT_DIGEST = "bc54f8887a6006669a74085c0ab88186dbf41266d5c4ece97727f48ad7ae7ee5"
BOOTSTRAP_FENCE_DIGEST = "f34d2e3ea8defd5ff7146a499b88e39c76b0a925c519bb524120a2542064d1cb"
PROVISIONAL_PREREQUISITE_DIGEST = "38c99ab22e9ee8193fb44e8ae9b66e1dc54ce9d7d54f348243c7d5ac41b824e8"
LEDGER_DIGEST = "3b628688db05bf9ba75673faed3bee8e71d4d82b9ac758b72f0d334025a37225"
LEDGER_CAS_SEQUENCE = 27
DOSSIER_DIGEST = "ac176edb8c0857be5c4b0db315c6237e849ecbac09f9bba254af757ab59dcb68"
C07_ALLOCATION_DIGEST = "a3974f7989a5efe5674af12e5d73710be06a87ac5c609a8dd504ee00c38d4a0a"
C07_MANIFEST_DIGEST = "1d339540d38e8378b861ef827713d0347197219b0d133c13a8b8de5949608619"

ROOT_PATH = "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift"
PORT_PATH = "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift"
ADAPTER_PATH = "FieldEvidenceApp/Infrastructure/System/SystemRuntimeAdapters.swift"
COORDINATOR_PATH = "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift"
COORDINATOR_CONTRACT_PATH = "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift"

SCHEMA_PATHS = [
    "Scripts/v23/production-composition-root.schema.json",
    "Scripts/v23/dependency-port-registry.schema.json",
    "Scripts/v23/architecture-fitness-receipt.schema.json",
    "Scripts/v23/architecture-boundary-manifest.schema.json",
    "Scripts/v23/architecture-debt-ledger.schema.json",
    "Scripts/v23/coordinator-decomposition-receipt.schema.json",
]
ARTIFACT_PATHS = [
    "docs/design/v23/tooling/ProductionCompositionRootV1.json",
    "docs/design/v23/tooling/DependencyPortRegistryV1.json",
    "docs/design/v23/tooling/ArchitectureFitnessReceiptV1.json",
    "docs/design/v23/tooling/ArchitectureBoundaryManifestV1.json",
    "docs/design/v23/tooling/ArchitectureDebtLedgerV1.json",
    "docs/design/v23/tooling/CoordinatorDecompositionReceiptV1.json",
]
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C10-tooling-manifest.json"
FENCED_PATHS = [
    ROOT_PATH,
    PORT_PATH,
    ADAPTER_PATH,
    COORDINATOR_CONTRACT_PATH,
    COORDINATOR_PATH,
    "Scripts/v23/c10_contracts.py",
    "Scripts/v23/generate_c10_contracts.py",
    "Scripts/v23/verify_c10_contracts.py",
    *SCHEMA_PATHS,
    *ARTIFACT_PATHS,
    MANIFEST_PATH,
]

EXTRACTED_SYMBOLS = [
    "CheckRunnerPreparation",
    "BeginDraftSubmission",
    "CheckRunnerCoordinatorError",
    "CheckOutcomeSelection",
    "ReviewEvidence",
    "FinalizationReview",
    "FinalizationIdentifiers",
    "FinalizationResult",
    "CapturePreparation",
    "CaptureCandidate",
    "CheckRunnerCoordinatorFailurePoint",
]


class ContractError(ValueError):
    pass


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


def validate_fence(root: Path) -> None:
    changed = subprocess.run(
        ["git", "-C", str(root), "diff", "--name-only", BASE_HEAD],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout.splitlines()
    changed_set = {line.replace("\\", "/") for line in changed if line}
    if not changed_set <= set(FENCED_PATHS):
        raise ContractError(f"C10 out-of-fence delta: {sorted(changed_set - set(FENCED_PATHS))}")
    status = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout.splitlines()
    for line in status:
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C10 delete/rename outside contract: {line}")
        if raw.replace("\\", "/") not in FENCED_PATHS:
            raise ContractError(f"C10 untracked/out-of-fence path: {raw}")


def validate_c07_input(root: Path) -> list[dict[str, Any]]:
    allocation = json.loads((root / "docs/design/v23/tooling/V21C07RequirementAllocationV1.json").read_text(encoding="utf-8"))
    manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C07-tooling-manifest.json").read_text(encoding="utf-8"))
    if allocation.get("artifactDigest") != C07_ALLOCATION_DIGEST or manifest.get("artifactDigest") != C07_MANIFEST_DIGEST:
        raise ContractError("C07 prerequisite contract artifact differs")
    rows = [row for row in allocation["rows"] if row["soleOwner"] == CARD_ID]
    if len(rows) != 12 or len({row["atomicClauseID"] for row in rows}) != 12:
        raise ContractError("C10 must receive exactly 12 unique C07 allocation rows")
    return rows


def read_at_head(root: Path, head: str, relative: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), "show", f"{head}:{relative}"],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout


def top_level_symbols(text: str) -> list[str]:
    return re.findall(r"^(?:@[A-Za-z0-9_()]+\s*)*(?:final\s+)?(?:class|struct|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)", text, re.MULTILINE)


def validate_swift_delta(root: Path) -> dict[str, Any]:
    root_text = (root / ROOT_PATH).read_text(encoding="utf-8")
    port_text = (root / PORT_PATH).read_text(encoding="utf-8")
    adapter_text = (root / ADAPTER_PATH).read_text(encoding="utf-8")
    coordinator_text = (root / COORDINATOR_PATH).read_text(encoding="utf-8")
    contracts_text = (root / COORDINATOR_CONTRACT_PATH).read_text(encoding="utf-8")
    if root_text.count("final class ProductionCompositionRoot") != 1:
        raise ContractError("production composition root declaration differs")
    if "func makeSignWorkflow" not in root_text or "ServiceLocator" in root_text or "static let shared" in root_text:
        raise ContractError("composition root factory or singleton prohibition differs")
    if top_level_symbols(port_text) != ["ApplicationClock", "ApplicationIDSource"]:
        raise ContractError("application runtime port declarations differ")
    if top_level_symbols(adapter_text) != ["SystemApplicationClock", "SystemApplicationIDSource"]:
        raise ContractError("system runtime adapter declarations differ")
    contract_symbols = top_level_symbols(contracts_text)
    if contract_symbols != EXTRACTED_SYMBOLS:
        raise ContractError(f"coordinator contract extraction differs: {contract_symbols}")
    if set(EXTRACTED_SYMBOLS) & set(top_level_symbols(coordinator_text)):
        raise ContractError("extracted coordinator contracts remain duplicated")
    base_coordinator = read_at_head(root, BASE_HEAD, COORDINATOR_PATH)
    marker = "@MainActor\nfinal class CheckRunnerCoordinatorFailureInjection"
    if marker not in base_coordinator or marker not in coordinator_text:
        raise ContractError("coordinator parity marker is absent")
    if base_coordinator.split(marker, 1)[1] != coordinator_text.split(marker, 1)[1]:
        raise ContractError("coordinator behavior body changed during contract extraction")
    return {
        "rootText": root_text,
        "portText": port_text,
        "adapterText": adapter_text,
        "baseCoordinatorLineCount": len(base_coordinator.splitlines()),
        "currentCoordinatorLineCount": len(coordinator_text.splitlines()),
        "contractLineCount": len(contracts_text.splitlines()),
    }


def swift_inventory(root: Path) -> dict[str, Any]:
    construction_pattern = re.compile(r"\b([A-Z][A-Za-z0-9]*(?:Service|Coordinator|Store|Adapter|Engine|Repository|Manager))\s*\(")
    model_context_pattern = re.compile(r"\bModelContext\b")
    debt_patterns = {
        "directDateConstruction": re.compile(r"\bDate\s*\(\s*\)"),
        "directUUIDConstruction": re.compile(r"\bUUID\s*\(\s*\)"),
        "uncheckedSendable": re.compile(r"@unchecked\s+Sendable"),
        "nonisolatedUnsafe": re.compile(r"nonisolated\s*\(\s*unsafe\s*\)"),
        "detachedTask": re.compile(r"\bTask\.detached\b"),
        "processInfo": re.compile(r"\bProcessInfo\.(?:processInfo\.)?(?:arguments|environment)\b"),
    }
    constructions: list[dict[str, Any]] = []
    model_contexts: list[dict[str, Any]] = []
    debt_findings: list[dict[str, Any]] = []
    hotspots: list[dict[str, Any]] = []
    for path in sorted((root / "FieldEvidenceApp").rglob("*.swift")):
        relative = normalized(path, root)
        lines = path.read_text(encoding="utf-8").splitlines()
        hotspots.append({"path": relative, "lineCount": len(lines)})
        for line_number, line in enumerate(lines, 1):
            for match in construction_pattern.finditer(line):
                constructions.append({"path": relative, "line": line_number, "symbol": match.group(1)})
            if model_context_pattern.search(line):
                model_contexts.append({"path": relative, "line": line_number})
            for kind, pattern in debt_patterns.items():
                if pattern.search(line):
                    debt_findings.append({"path": relative, "line": line_number, "kind": kind})
    feature_constructions = [row for row in constructions if row["path"].startswith("FieldEvidenceApp/Features/")]
    return {
        "constructions": constructions,
        "featureConstructions": feature_constructions,
        "modelContextReferences": model_contexts,
        "debtFindings": debt_findings,
        "hotspots": sorted(hotspots, key=lambda row: (-row["lineCount"], row["path"])),
    }


def common_schema(name: str, required: list[str], properties: dict[str, Any]) -> dict[str, Any]:
    digest_string = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    authority = {
        "type": "object",
        "additionalProperties": False,
        "required": list(authority_binding()),
        "properties": {
            key: (
                {"const": value}
                if not isinstance(value, dict)
                else {
                    "type": "object",
                    "additionalProperties": False,
                    "required": list(value),
                    "properties": {nested: {"const": nested_value} for nested, nested_value in value.items()},
                }
            )
            for key, value in authority_binding().items()
        },
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{name}.schema.json",
        "title": name,
        "type": "object",
        "additionalProperties": False,
        "required": ["schema", "schemaVersion", "cardID", "authority", *required, "acceptanceCredit", "releaseCredit", "artifactDigest"],
        "properties": {
            "schema": {"const": name},
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD_ID},
            "authority": authority,
            **properties,
            "acceptanceCredit": {"const": False},
            "releaseCredit": {"const": False},
            "artifactDigest": digest_string,
        },
    }


def schemas() -> dict[str, dict[str, Any]]:
    string = {"type": "string", "minLength": 1}
    string_array = {"type": "array", "items": string, "uniqueItems": True}
    object_array = {"type": "array", "items": {"type": "object"}}
    integer = {"type": "integer", "minimum": 0}
    return {
        SCHEMA_PATHS[0]: common_schema("ProductionCompositionRootV1", ["rootPath", "rootType", "factory", "constructedSymbols", "runtimePorts", "rootDeclarationCount", "installationStatus", "singletonProhibited", "serviceLocatorProhibited"], {
            "rootPath": {"const": ROOT_PATH}, "rootType": {"const": "ProductionCompositionRoot"}, "factory": {"const": "makeSignWorkflow"},
            "constructedSymbols": string_array, "runtimePorts": string_array, "rootDeclarationCount": {"const": 1},
            "installationStatus": {"const": "ROOT_IMPLEMENTED_WIRING_DEFERRED_RESERVED_APP_AND_FEATURE_ROOTS"},
            "singletonProhibited": {"const": True}, "serviceLocatorProhibited": {"const": True},
        }),
        SCHEMA_PATHS[1]: common_schema("DependencyPortRegistryV1", ["applicationOwner", "ports", "platformAdapters", "microModuleCount", "stableValueTypeAbstractionCount", "remainingBoundaryDisposition"], {
            "applicationOwner": {"const": CARD_ID}, "ports": object_array, "platformAdapters": object_array,
            "microModuleCount": {"const": 0}, "stableValueTypeAbstractionCount": {"const": 0}, "remainingBoundaryDisposition": string,
        }),
        SCHEMA_PATHS[2]: common_schema("ArchitectureFitnessReceiptV1", ["compositionRootDigest", "portRegistryDigest", "boundaryManifestDigest", "debtLedgerDigest", "coordinatorReceiptDigest", "staticVerificationStatus", "nativeCompileStatus", "goldenParityStatus", "provisionalDisposition"], {
            "compositionRootDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "portRegistryDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "boundaryManifestDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "debtLedgerDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
            "coordinatorReceiptDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"}, "staticVerificationStatus": {"const": "PASS"},
            "nativeCompileStatus": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"}, "goldenParityStatus": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"},
            "provisionalDisposition": {"const": "TARGETED_STATIC_GREEN_NOT_ACCEPTABLE"},
        }),
        SCHEMA_PATHS[3]: common_schema("ArchitectureBoundaryManifestV1", ["logicalLayers", "allowedDirections", "constructionOwner", "featureConstructionFindings", "modelContextReferenceFindings", "boundarySatisfied", "physicalTargetExtractionDisposition"], {
            "logicalLayers": string_array, "allowedDirections": string_array, "constructionOwner": {"const": ROOT_PATH},
            "featureConstructionFindings": object_array, "modelContextReferenceFindings": object_array,
            "boundarySatisfied": {"const": False}, "physicalTargetExtractionDisposition": {"const": "DEFERRED_NO_MEASURED_BUILD_BENEFIT"},
        }),
        SCHEMA_PATHS[4]: common_schema("ArchitectureDebtLedgerV1", ["ratchetKinds", "findings", "findingCounts", "hotspots", "newForbiddenDebtCount", "debtBaselineSatisfied", "disposition"], {
            "ratchetKinds": string_array, "findings": object_array, "findingCounts": {"type": "object"}, "hotspots": object_array,
            "newForbiddenDebtCount": {"const": 0}, "debtBaselineSatisfied": {"const": True}, "disposition": {"const": "BASELINE_CAPTURED_NO_C10_FORBIDDEN_GROWTH"},
        }),
        SCHEMA_PATHS[5]: common_schema("CoordinatorDecompositionReceiptV1", ["coordinatorPath", "contractPath", "extractedSymbols", "baseCoordinatorLineCount", "currentCoordinatorLineCount", "contractLineCount", "behaviorBodyParity", "nativeGoldenParity", "structuralExtractionSatisfied"], {
            "coordinatorPath": {"const": COORDINATOR_PATH}, "contractPath": {"const": COORDINATOR_CONTRACT_PATH},
            "extractedSymbols": {"const": EXTRACTED_SYMBOLS}, "baseCoordinatorLineCount": integer, "currentCoordinatorLineCount": integer,
            "contractLineCount": integer, "behaviorBodyParity": {"const": "EXACT_FROM_FAILURE_INJECTION_MARKER_THROUGH_EOF"},
            "nativeGoldenParity": {"const": "NOT_RUN_HOSTED_DISPATCH_DISABLED"}, "structuralExtractionSatisfied": {"const": True},
        }),
    }


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    validate_frozen_authority(root)
    validate_fence(root)
    allocation_rows = validate_c07_input(root)
    reservation = load_reservation(root)
    if set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C10 fence overlaps frozen S10 reservation")
    swift = validate_swift_delta(root)
    inventory = swift_inventory(root)
    authority = authority_binding()

    constructed = [
        "CheckRunnerCoordinator", "FirstSignCoordinator", "ReportDeliveryCoordinator",
        "ReportHistoryCoordinator", "StoragePreflightService", "WholeSignDeletionService", "WorkCoordinator",
    ]
    root_artifact = seal({
        "schema": "ProductionCompositionRootV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "rootPath": ROOT_PATH, "rootType": "ProductionCompositionRoot", "factory": "makeSignWorkflow",
        "constructedSymbols": constructed, "runtimePorts": ["ApplicationClock", "ApplicationIDSource"],
        "rootDeclarationCount": 1, "installationStatus": "ROOT_IMPLEMENTED_WIRING_DEFERRED_RESERVED_APP_AND_FEATURE_ROOTS",
        "singletonProhibited": True, "serviceLocatorProhibited": True, "acceptanceCredit": False, "releaseCredit": False,
    })
    port_registry = seal({
        "schema": "DependencyPortRegistryV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "applicationOwner": CARD_ID,
        "ports": [
            {"port": "ApplicationClock", "path": PORT_PATH, "volatility": "WALL_CLOCK_AND_DETERMINISTIC_TEST_TIME"},
            {"port": "ApplicationIDSource", "path": PORT_PATH, "volatility": "IDENTITY_GENERATION_AND_DETERMINISTIC_TEST_IDS"},
        ],
        "platformAdapters": [
            {"adapter": "SystemApplicationClock", "port": "ApplicationClock", "path": ADAPTER_PATH},
            {"adapter": "SystemApplicationIDSource", "port": "ApplicationIDSource", "path": ADAPTER_PATH},
        ],
        "microModuleCount": 0, "stableValueTypeAbstractionCount": 0,
        "remainingBoundaryDisposition": "PERSISTENCE_REPORTING_COMMERCE_MEDIA_AND_PLATFORM_PORT_MIGRATION_DEFERRED_WITH_EXISTING_BEHAVIOR_BEHIND_ROOT",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    boundary = seal({
        "schema": "ArchitectureBoundaryManifestV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "logicalLayers": ["APP_COMPOSITION", "APP_UI", "APPLICATION", "DOMAIN_CORE", "PLATFORM_INFRASTRUCTURE"],
        "allowedDirections": ["APP_UI_TO_APPLICATION", "APPLICATION_TO_DOMAIN_CORE", "PLATFORM_INFRASTRUCTURE_TO_APPLICATION_PORTS", "APP_COMPOSITION_TO_ALL_ASSEMBLED_LAYERS"],
        "constructionOwner": ROOT_PATH, "featureConstructionFindings": inventory["featureConstructions"],
        "modelContextReferenceFindings": inventory["modelContextReferences"], "boundarySatisfied": False,
        "physicalTargetExtractionDisposition": "DEFERRED_NO_MEASURED_BUILD_BENEFIT",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    finding_counts: dict[str, int] = {}
    for row in inventory["debtFindings"]:
        finding_counts[row["kind"]] = finding_counts.get(row["kind"], 0) + 1
    c10_new_forbidden = [
        row for row in inventory["debtFindings"]
        if row["path"] in {ROOT_PATH, PORT_PATH, ADAPTER_PATH, COORDINATOR_CONTRACT_PATH}
        and row["kind"] in {"processInfo", "uncheckedSendable", "nonisolatedUnsafe", "detachedTask"}
    ]
    debt = seal({
        "schema": "ArchitectureDebtLedgerV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "ratchetKinds": ["DIRECT_DATE", "DIRECT_UUID", "FEATURE_MODELCONTEXT", "FEATURE_CONCRETE_CONSTRUCTION", "PROCESS_INFO", "UNCHECKED_SENDABLE", "NONISOLATED_UNSAFE", "TASK_DETACHED", "OVERSIZED_HOTSPOT"],
        "findings": inventory["debtFindings"], "findingCounts": finding_counts,
        "hotspots": inventory["hotspots"][:25], "newForbiddenDebtCount": len(c10_new_forbidden),
        "debtBaselineSatisfied": len(c10_new_forbidden) == 0,
        "disposition": "BASELINE_CAPTURED_NO_C10_FORBIDDEN_GROWTH",
        "acceptanceCredit": False, "releaseCredit": False,
    })
    coordinator = seal({
        "schema": "CoordinatorDecompositionReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "coordinatorPath": COORDINATOR_PATH, "contractPath": COORDINATOR_CONTRACT_PATH,
        "extractedSymbols": EXTRACTED_SYMBOLS, "baseCoordinatorLineCount": swift["baseCoordinatorLineCount"],
        "currentCoordinatorLineCount": swift["currentCoordinatorLineCount"], "contractLineCount": swift["contractLineCount"],
        "behaviorBodyParity": "EXACT_FROM_FAILURE_INJECTION_MARKER_THROUGH_EOF",
        "nativeGoldenParity": "NOT_RUN_HOSTED_DISPATCH_DISABLED", "structuralExtractionSatisfied": True,
        "acceptanceCredit": False, "releaseCredit": False,
    })
    fitness = seal({
        "schema": "ArchitectureFitnessReceiptV1", "schemaVersion": 1, "cardID": CARD_ID, "authority": authority,
        "compositionRootDigest": root_artifact["artifactDigest"], "portRegistryDigest": port_registry["artifactDigest"],
        "boundaryManifestDigest": boundary["artifactDigest"], "debtLedgerDigest": debt["artifactDigest"],
        "coordinatorReceiptDigest": coordinator["artifactDigest"], "staticVerificationStatus": "PASS",
        "nativeCompileStatus": "NOT_RUN_HOSTED_DISPATCH_DISABLED", "goldenParityStatus": "NOT_RUN_HOSTED_DISPATCH_DISABLED",
        "provisionalDisposition": "TARGETED_STATIC_GREEN_NOT_ACCEPTABLE", "acceptanceCredit": False, "releaseCredit": False,
    })
    if len(allocation_rows) != 12 or debt["newForbiddenDebtCount"] != 0:
        raise ContractError("C10 allocation or forbidden-debt ratchet differs")
    outputs = schemas()
    outputs.update({
        ARTIFACT_PATHS[0]: root_artifact,
        ARTIFACT_PATHS[1]: port_registry,
        ARTIFACT_PATHS[2]: fitness,
        ARTIFACT_PATHS[3]: boundary,
        ARTIFACT_PATHS[4]: debt,
        ARTIFACT_PATHS[5]: coordinator,
    })
    return outputs


def build_manifest(root: Path) -> dict[str, Any]:
    paths = [path for path in FENCED_PATHS if path != MANIFEST_PATH]
    artifacts = []
    for relative in paths:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing C10 manifest artifact: {relative}")
        artifacts.append({"path": relative, "sha256": sha256_bytes(path.read_bytes())})
    return seal({
        "schema": "V23P00C10ToolingManifestV1", "schemaVersion": 1, "cardID": CARD_ID,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "authority": authority_binding(),
        "fencedPathCount": len(FENCED_PATHS), "artifacts": artifacts,
        "c07AllocationDigest": C07_ALLOCATION_DIGEST, "c07OwnedClauseCount": 12,
        "provisionalDisposition": "COMPOSITION_ROOT_PORTS_AND_STRUCTURAL_DECOMPOSITION_IMPLEMENTED; ROOT_WIRING_NATIVE_COMPILE_GOLDEN_PARITY_AND_FULL_BOUNDARY_CLOSURE_DEFERRED",
        "acceptanceCredit": False, "releaseCredit": False,
    })
