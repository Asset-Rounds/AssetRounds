#!/usr/bin/env python3
"""Deterministic language-neutral contracts for provisional Card 39."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C08"
TITLE = "Workspace-scoped pack-driven commands/queries and runner/finalizer/report/backup/delete/recovery integration"
APP_BASE_HEAD = "d6d61b81a9793f34f7c72d62dd333037b8b51968"
APP_BASE_TREE = "2be6a038fcd19247467c69105e2283dedb534e28"
COORDINATION_HEAD = "cf61d9e230c5a0f350d9bd4b1e2ca73c572ae003"
COORDINATION_TREE = "57e70906a7b64f31232b90965474f3ceec6fb2ba"
CONTEXT_DIGEST = "9727fa77756ca1512af153d68bdf69c9c09a1fac02261f3967aa691c62b6e547"
FENCE_DIGEST = "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6"
PREREQUISITE_DIGEST = "d6278c9e68c969a0c6023b86f0c8f70f6467d6a282872bc47d0284e8ee725041"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
INHERITED_BLOCK_DIGEST = "ca9a4d6b80db8de8a1b443ac82945fad787b21b94cb835182c7e51e9b4e3ef9a"
DOSSIER_DIGEST = "e51077f451b306467c057d6b490a620db085cd8713c3610989815669e4c27219"
REGISTER_ROW_DIGEST = "2cdf89a94441873cc6e15d983d0cae4e9f249212f17167882812e10511cee510"

PRODUCT_PATHS = [
    "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/PackFinalizationAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/PackFinalizationRecoveryAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
]
TEST_PATH = "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift"
FIXTURE = "FieldEvidenceAppTests/Fixtures/V21/Integration/V21P03C08PackLifecycleIntegrationCorpusV1.json"
SOURCE_PATHS = PRODUCT_PATHS + [TEST_PATH, FIXTURE]
SCRIPT_PATHS = [
    "Scripts/v23/p03_c08_contracts.py",
    "Scripts/v23/generate_p03_c08_contracts.py",
    "Scripts/v23/verify_p03_c08_contracts.py",
]
SCHEMA_PATH = "Scripts/v23/pack-lifecycle-integration.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C08PackLifecycleContractV1.json"
CLOSURE_PATH = "docs/design/v23/tooling/V23P03C08FeatureCommandQueryClosureReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C08-tooling-manifest.json"
GENERATED_PATHS = [SCHEMA_PATH, CONTRACT_PATH, CLOSURE_PATH, MANIFEST]
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]

EXISTING_PATHS = PRODUCT_PATHS[:8] + PRODUCT_PATHS[10:]
NEW_PATHS = [PRODUCT_PATHS[8], PRODUCT_PATHS[9], TEST_PATH, FIXTURE] + SCRIPT_PATHS + GENERATED_PATHS
EVIDENCE_IDS = [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]

RESERVED_OWNER_DEBTS = [
    "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
    "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift",
]
RESERVED_RAW_WRITE_DEBTS = RESERVED_OWNER_DEBTS[-2:]

# Exact frozen S10 reservation inventory from the hydrated fence. Keeping it here makes
# the disjointness proof independent of a mutable coordination checkout.
ACTIVE_S10_RESERVED_PATHS = [
    ".github/workflows/ios-ci-worker.yml", ".github/workflows/ios-ci.yml", "AGENTS.md",
    "FieldEvidenceApp.xcodeproj/project.pbxproj",
    "FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme",
    "FieldEvidenceApp/App/FieldEvidenceAppApp.swift", "FieldEvidenceApp/App/LaunchView.swift",
    "FieldEvidenceApp/DesignSystem/DesignTokens.swift", "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
    "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
    "FieldEvidenceApp/Features/Issues/IssueDetailView.swift", "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
    "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
    "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
    "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
    "FieldEvidenceApp/Features/Sample/PackSampleView.swift",
    "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
    "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
    "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
    "FieldEvidenceApp/Features/Signs/NewSignView.swift", "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
    "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
    "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
    "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
    "FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Default-1024.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted-1024.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsAccentTeal.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandCanvas.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-1x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-2x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-3x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-1x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-2x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-3x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsCheckpointGreen.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsDeepTeal.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsInk.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsSlate.colorset/Contents.json",
    "FieldEvidenceAppTests/S10_1BrandInventoryTests.swift", "FieldEvidenceAppTests/S10_2BrandComponentTests.swift",
    "FieldEvidenceAppTests/S10_3BrandMigrationTests.swift", "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift",
    "FieldEvidenceAppUITests/S10_1BrandInventoryUITests.swift", "FieldEvidenceAppUITests/S10_2BrandComponentUITests.swift",
    "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift", "Scripts/ci-selection.json",
    "Scripts/s10-4-segment-assembler.sh", "Scripts/s10-4-segment-plan.json", "Scripts/s10-4-shards.json",
    "Scripts/ui-smoke.sh", "docs/design/s10/authority/asset-manifest.json",
    "docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1",
    "docs/design/s10/s10-accessibility-common-tasks.json", "docs/design/s10/s10-activation.json",
    "docs/design/s10/s10-experience-validation.json", "docs/design/s10/s10-screen-state-inventory.json",
    "docs/design/s10/s10-stage-checkpoints.json", "docs/design/s10/s10-store-readiness.json",
    "docs/design/s10/s10-token-coverage.json", "docs/design/s10/s10-visual-regression.json",
    "docs/execution/CODEX_EXECUTION_CONTRACT_V4.md", "docs/execution/CURRENT_TASK.md",
    "docs/execution/HANDOFF.md", "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md", "docs/product/BUILD_PLAN_V4.md",
]

PACKAGES = ["ALTERNATE_PACK", "SHIPPING_SIGN_PACK"]
OPERATIONS = [
    "ACKNOWLEDGE", "ARCHIVE", "BACKUP", "CAPTURE", "COMPLETE", "DELETE", "ERASE",
    "EXPORT_OPEN", "FINALIZE", "QUERY", "RECOVER", "REPORT_PDF", "RESTORE",
]
RECOVERY_BOUNDARIES = [
    "AFTER_COMMAND_RECEIPT", "AFTER_FINALIZATION_WRITE", "AFTER_REPORT_WRITE",
    "BEFORE_COMMAND_RECEIPT", "BEFORE_FINALIZATION_WRITE", "BEFORE_REPORT_WRITE",
    "COMPETING_DELETE", "COMPETING_EXPORT", "COMPETING_FINALIZE",
]
FAILURE_CASES = [
    "AUTHORITY_CONSTRUCTION_DUPLICATE", "CROSS_WORKSPACE_READ", "CROSS_WORKSPACE_WRITE",
    "DUPLICATE_CONTAINER", "DUPLICATE_WRITER", "HARDCODED_PURPOSE_BRANCH", "INTERRUPTED_LIFECYCLE",
    "LEGACY_ARCHIVE_DRIFT", "LEGACY_REPORT_DRIFT", "OPTIONAL_FALLBACK_ADAPTER",
    "PARTIAL_LIFECYCLE", "UNRESOLVED_SCHEMA_REFERENCE",
]


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "prerequisiteDigest": PREREQUISITE_DIGEST, "s10ReservationDigest": S10_RESERVATION_DIGEST,
        "inheritedBlueprintBlockDigest": INHERITED_BLOCK_DIGEST,
        "dossierDigest": DOSSIER_DIGEST, "registerRowDigest": REGISTER_ROW_DIGEST,
    }


def source_rows(root: Path) -> list[dict[str, str]]:
    rows = []
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing source artifact: {relative}")
        rows.append({"path": relative, "sha256": digest(path.read_bytes())})
    return rows


def package_descriptors() -> list[dict[str, Any]]:
    return [
        {"packageID": "ALTERNATE_PACK", "purposeKey": "alternate", "shipping": False,
         "commandSet": OPERATIONS, "querySet": ["ACTIVITY", "EVIDENCE", "REPORT", "WORKSPACE"]},
        {"packageID": "SHIPPING_SIGN_PACK", "purposeKey": "sign", "shipping": True,
         "commandSet": OPERATIONS, "querySet": ["ACTIVITY", "EVIDENCE", "REPORT", "WORKSPACE"]},
    ]


def lifecycle_routes() -> list[dict[str, Any]]:
    owners = {
        "ACKNOWLEDGE": "CheckRunnerCoordinator", "ARCHIVE": "BackupExportService",
        "BACKUP": "BackupExportService", "CAPTURE": "FirstSignCoordinator",
        "COMPLETE": "CheckRunnerCoordinator", "DELETE": "WholeSignDeletionService",
        "ERASE": "EraseAllService", "EXPORT_OPEN": "BackupExportService",
        "FINALIZE": "PackFinalizationAdapterV1", "QUERY": "StoreSessionCoordinator",
        "RECOVER": "PackFinalizationRecoveryAdapterV1", "REPORT_PDF": "ReportRenderService",
        "RESTORE": "BackupRestoreService",
    }
    rows = []
    for package in PACKAGES:
        for operation in OPERATIONS:
            rows.append({
                "routeID": f"{package}.{operation}", "packageID": package, "operation": operation,
                "authorityOwner": owners[operation], "workspaceScoped": True,
                "commandOrQuery": "QUERY" if operation == "QUERY" else "COMMAND",
                "recoveryDisposition": "IDEMPOTENT_RESUME" if operation in {"FINALIZE", "RECOVER", "REPORT_PDF", "BACKUP", "RESTORE", "DELETE", "ERASE"} else "REPLAY_SAFE",
            })
    return rows


def pack_contract(root: Path) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C08PackLifecycleContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "packages": package_descriptors(), "routes": lifecycle_routes(),
        "workspaceIsolation": {
            "workspaceIDs": ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"],
            "crossWorkspaceReadsAllowed": False, "crossWorkspaceWritesAllowed": False,
            "queryWorkspaceBindingRequired": True, "commandWorkspaceBindingRequired": True,
        },
        "recoveryBoundaries": RECOVERY_BOUNDARIES, "failureCases": FAILURE_CASES,
        "persistentChangeMode": "CONTENT_ONLY", "schemaBehaviorDelta": False, "migrationBehaviorDelta": False,
        "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True, "downgradeDisposition": "FORWARD_FIX_ONLY",
        "sourceArtifacts": source_rows(root), "evidenceIDs": EVIDENCE_IDS,
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False, "hostedDispatchRan": False,
        "phase10PollingRan": False, "adoptionEnabled": False, "acceptanceEnabled": False,
        "acceptanceCredit": False, "releaseReady": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": digest(pretty(unsigned))}


def closure_receipt(root: Path) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C08FeatureCommandQueryClosureReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "scannedPaths": PRODUCT_PATHS,
        "reservedOwnerDebtPaths": RESERVED_OWNER_DEBTS,
        "reservedRawWriteDebtPaths": RESERVED_RAW_WRITE_DEBTS,
        "newDisjointFeatureRawWriteViolations": [], "newDisjointViewModelContextViolations": [],
        "newOptionalFallbackAdapterViolations": [], "duplicateWriterContainerAuthorityViolations": [],
        "unresolvedSchemaReferences": [], "digestDriftPaths": [],
        "provisionalZeroViolationClosureClaimed": False, "liveZeroViolationClosureAchieved": False,
        "staticDisjointScannerPassed": True, "s10FenceOverlapPaths": [],
        "requiresAcceptedS10_6Reconciliation": True, "evidenceIDs": EVIDENCE_IDS,
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False, "hostedDispatchRan": False,
        "phase10PollingRan": False, "adoptionEnabled": False, "acceptanceEnabled": False,
        "acceptanceCredit": False, "releaseReady": False, "releaseCredit": False,
        "sourceProjectionSHA256": digest(canonical(source_rows(root))),
    }
    return {**unsigned, "artifactDigest": digest(pretty(unsigned))}


def strict(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties,
            "required": required if required is not None else list(properties)}


def exact_array(values: list[Any]) -> dict[str, Any]:
    return {"type": "array", "prefixItems": [{"const": value} for value in values],
            "items": False, "minItems": len(values), "maxItems": len(values)}


def integration_schema(root: Path) -> dict[str, Any]:
    sha = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    false = {"const": False}
    authority_schema = strict({key: ({"const": value}) for key, value in authority().items()})
    source_row = strict({"path": {"type": "string", "minLength": 1}, "sha256": sha})
    package = strict({
        "packageID": {"enum": PACKAGES}, "purposeKey": {"enum": ["alternate", "sign"]},
        "shipping": {"type": "boolean"}, "commandSet": exact_array(OPERATIONS),
        "querySet": exact_array(["ACTIVITY", "EVIDENCE", "REPORT", "WORKSPACE"]),
    })
    route = strict({
        "routeID": {"type": "string", "pattern": "^(ALTERNATE_PACK|SHIPPING_SIGN_PACK)\\.[A-Z_]+$"},
        "packageID": {"enum": PACKAGES}, "operation": {"enum": OPERATIONS},
        "authorityOwner": {"type": "string", "minLength": 1, "maxLength": 128},
        "workspaceScoped": {"const": True}, "commandOrQuery": {"enum": ["COMMAND", "QUERY"]},
        "recoveryDisposition": {"enum": ["IDEMPOTENT_RESUME", "REPLAY_SAFE"]},
    })
    flags = {
        "verificationMode": {"const": "STATIC_ONLY"}, "nativeCompileRan": false,
        "hostedDispatchRan": false, "phase10PollingRan": false, "adoptionEnabled": false,
        "acceptanceEnabled": false, "acceptanceCredit": false, "releaseReady": false, "releaseCredit": false,
        "requiresAcceptedS10_6Reconciliation": {"const": True},
    }
    pack = strict({
        "schema": {"const": "V23P03C08PackLifecycleContractV1"}, "schemaVersion": {"const": 1},
        "cardID": {"const": CARD}, "title": {"const": TITLE}, "authority": {"$ref": "#/$defs/authority"},
        "packages": {"type": "array", "items": {"$ref": "#/$defs/package"}, "minItems": 2, "maxItems": 2,
                     "uniqueItems": True},
        "routes": {"type": "array", "items": {"$ref": "#/$defs/route"},
                   "minItems": len(PACKAGES) * len(OPERATIONS), "maxItems": len(PACKAGES) * len(OPERATIONS),
                   "uniqueItems": True},
        "workspaceIsolation": strict({
            "workspaceIDs": exact_array(["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"]),
            "crossWorkspaceReadsAllowed": false, "crossWorkspaceWritesAllowed": false,
            "queryWorkspaceBindingRequired": {"const": True}, "commandWorkspaceBindingRequired": {"const": True},
        }),
        "recoveryBoundaries": exact_array(RECOVERY_BOUNDARIES), "failureCases": exact_array(FAILURE_CASES),
        "persistentChangeMode": {"const": "CONTENT_ONLY"}, "schemaBehaviorDelta": false,
        "migrationBehaviorDelta": false, "backupBehaviorDelta": {"const": True},
        "restoreBehaviorDelta": {"const": True}, "deleteBehaviorDelta": {"const": True},
        "exportBehaviorDelta": {"const": True}, "downgradeDisposition": {"const": "FORWARD_FIX_ONLY"},
        "sourceArtifacts": {"type": "array", "items": {"$ref": "#/$defs/sourceRow"},
                            "minItems": len(SOURCE_PATHS), "maxItems": len(SOURCE_PATHS)},
        "evidenceIDs": exact_array(EVIDENCE_IDS), **flags, "artifactDigest": sha,
    })
    closure = strict({
        "schema": {"const": "V23P03C08FeatureCommandQueryClosureReceiptV1"}, "schemaVersion": {"const": 1},
        "cardID": {"const": CARD}, "authority": {"$ref": "#/$defs/authority"},
        "scannedPaths": exact_array(PRODUCT_PATHS), "reservedOwnerDebtPaths": exact_array(RESERVED_OWNER_DEBTS),
        "reservedRawWriteDebtPaths": exact_array(RESERVED_RAW_WRITE_DEBTS),
        "newDisjointFeatureRawWriteViolations": {"type": "array", "maxItems": 0},
        "newDisjointViewModelContextViolations": {"type": "array", "maxItems": 0},
        "newOptionalFallbackAdapterViolations": {"type": "array", "maxItems": 0},
        "duplicateWriterContainerAuthorityViolations": {"type": "array", "maxItems": 0},
        "unresolvedSchemaReferences": {"type": "array", "maxItems": 0},
        "digestDriftPaths": {"type": "array", "maxItems": 0},
        "provisionalZeroViolationClosureClaimed": false, "liveZeroViolationClosureAchieved": false,
        "staticDisjointScannerPassed": {"const": True}, "s10FenceOverlapPaths": {"type": "array", "maxItems": 0},
        "evidenceIDs": exact_array(EVIDENCE_IDS), **flags, "sourceProjectionSHA256": sha, "artifactDigest": sha,
    })
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/schemas/v23/pack-lifecycle-integration.schema.json",
        "title": "V23 P03 C08 pack lifecycle integration and closure receipt",
        "oneOf": [{"$ref": "#/$defs/packContract"}, {"$ref": "#/$defs/closureReceipt"}],
        "$defs": {"authority": authority_schema, "sourceRow": source_row, "package": package,
                  "route": route, "packContract": pack, "closureReceipt": closure},
    }


def sample_instances(root: Path) -> list[dict[str, Any]]:
    return [pack_contract(root), closure_receipt(root)]


def tooling_manifest(root: Path, generated_without_manifest: dict[str, bytes]) -> dict[str, Any]:
    artifacts = []
    for relative in MANIFEST_INPUT_PATHS:
        raw = generated_without_manifest.get(relative)
        if raw is None:
            path = root / relative
            if not path.is_file():
                raise ContractError(f"missing manifest input: {relative}")
            raw = path.read_bytes()
        artifacts.append({"path": relative, "sha256": digest(raw)})
    unsigned = {
        "schema": "V23P03C08ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE),
        "sourcePathCount": len(SOURCE_PATHS), "toolPathCount": len(TOOL_PATHS),
        "generatedArtifactCount": len(GENERATED_PATHS), "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "artifacts": artifacts, "activeS10ReservationPathCount": len(ACTIVE_S10_RESERVED_PATHS),
        "s10FenceOverlapPaths": sorted(set(PATH_FENCE) & set(ACTIVE_S10_RESERVED_PATHS)),
        "reservedOwnerDebtPaths": RESERVED_OWNER_DEBTS, "reservedRawWriteDebtPaths": RESERVED_RAW_WRITE_DEBTS,
        "evidenceIDs": EVIDENCE_IDS, "verificationMode": "STATIC_ONLY",
        "provisionalZeroViolationClosureClaimed": False, "nativeCompileRan": False,
        "hostedDispatchRan": False, "phase10PollingRan": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseReady": False,
        "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": digest(pretty(unsigned))}


def all_outputs(root: Path) -> dict[str, bytes]:
    schema = integration_schema(root)
    contract = pack_contract(root)
    closure = closure_receipt(root)
    partial = {SCHEMA_PATH: pretty(schema), CONTRACT_PATH: pretty(contract), CLOSURE_PATH: pretty(closure)}
    manifest = tooling_manifest(root, partial)
    return {**partial, MANIFEST: pretty(manifest)}
