"""Verify Card 51's static corpus, exact fence, and sealed evidence."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import p03_c14_contracts as contracts


class DuplicateKey(ValueError):
    pass


def _no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def _load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"), object_pairs_hook=_no_duplicate_keys)


def _candidate_changed_paths() -> list[str]:
    status = subprocess.run(
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths: list[str] = []
    for line in status.splitlines():
        if not line:
            continue
        path = line[3:]
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))
    committed = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", contracts.BASE_HEAD, "--"],
        check=True, capture_output=True, text=True,
    ).stdout
    paths.extend(path.replace("\\", "/") for path in committed.splitlines() if path)
    return sorted(set(paths))


def _git_value(*args: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *args], check=True, capture_output=True, text=True).stdout.strip()


def _base_path_exists(relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(ROOT), "cat-file", "-e", f"{contracts.BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def _assert(condition: bool, message: str, failures: list[str]) -> None:
    if not condition:
        failures.append(message)


def _check_sealed(document: dict[str, Any], failures: list[str], label: str) -> None:
    digest = document.get("artifactDigest")
    body = {key: value for key, value in document.items() if key != "artifactDigest"}
    _assert(isinstance(digest, str) and digest == contracts.sha256_bytes(contracts.pretty(body)), f"{label}:artifactDigest", failures)


def _check_manifest_row(row: dict[str, Any], relative: str, failures: list[str]) -> None:
    _assert(row.get("path") == relative, f"manifest row path:{relative}", failures)
    path = ROOT / relative
    if path.is_file():
        raw = path.read_bytes()
        _assert(row.get("state") in ("WORKTREE", "GENERATED"), f"manifest row state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"manifest row bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"manifest row digest:{relative}", failures)
        return
    if relative in contracts.EXISTING_PATHS:
        raw = contracts._git_blob(ROOT, relative)
        _assert(row.get("state") == "BASE_HEAD", f"manifest base state:{relative}", failures)
        _assert(row.get("bytes") == len(raw), f"manifest base bytes:{relative}", failures)
        _assert(row.get("sha256") == contracts.sha256_bytes(raw), f"manifest base digest:{relative}", failures)
        return
    _assert(relative in contracts.NEW_PATHS, f"manifest row outside fence:{relative}", failures)
    _assert(row.get("state") == "MISSING_NEW_PATH", f"manifest missing state:{relative}", failures)
    _assert(row.get("bytes") == 0 and row.get("sha256") == contracts.sha256_bytes(b""), f"manifest missing digest:{relative}", failures)


S10_RESERVED_PATHS = frozenset((
    ".github/workflows/ios-ci-worker.yml", ".github/workflows/ios-ci.yml", "AGENTS.md",
    "FieldEvidenceApp.xcodeproj/project.pbxproj", "FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme",
    "FieldEvidenceApp/App/FieldEvidenceAppApp.swift", "FieldEvidenceApp/App/LaunchView.swift",
    "FieldEvidenceApp/DesignSystem/DesignTokens.swift", "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift", "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift", "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift", "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
    "FieldEvidenceApp/Features/Issues/IssueDetailView.swift", "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
    "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift", "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift", "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift", "FieldEvidenceApp/Features/Sample/PackSampleView.swift",
    "FieldEvidenceApp/Features/Settings/BackupExportView.swift", "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift", "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift", "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
    "FieldEvidenceApp/Features/Signs/NewSignView.swift", "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
    "FieldEvidenceApp/Features/Signs/SignsRootView.swift", "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
    "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift", "FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift", "FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift",
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
    "Scripts/s10-4-segment-assembler.sh", "Scripts/s10-4-segment-plan.json", "Scripts/s10-4-shards.json", "Scripts/ui-smoke.sh",
    "docs/design/s10/authority/asset-manifest.json", "docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip",
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
))


def _check_corpus(failures: list[str]) -> None:
    corpus = contracts.CORPUS
    _assert(corpus.get("schema") == "V21P03C14ReviewAndCorrectiveActionCorpusV1", "corpus schema", failures)
    _assert(corpus.get("schemaVersion") == 1 and corpus.get("cardID") == contracts.CARD, "corpus identity", failures)
    _assert(corpus.get("synthetic") is True and corpus.get("containsCustomerData") is False and corpus.get("containsSecrets") is False, "corpus synthetic boundary", failures)
    persistence = corpus.get("persistence", {})
    _assert(persistence.get("schemaRelease") == "PERSISTENT_SCHEMA_V14_REVIEW_AND_CORRECTIVE_ACTION", "persistence schema release", failures)
    _assert(persistence.get("recordSchemaVersion") == 13 and persistence.get("recordsSchemaVersion") == 13 and persistence.get("predecessorSchemaVersion") == 13 and persistence.get("predecessorRecordSchemaVersion") == 12, "persistence records 13", failures)
    _assert(persistence.get("migration") == "EXACT_V13_TO_V14_COPY_ON_WRITE", "persistence migration", failures)
    _assert(persistence.get("canonicalWriter") == "V23-P02-C01" and persistence.get("lifecycleOwner") == contracts.CARD, "persistence writer/owner", failures)
    _assert(len(persistence.get("persistedFamilies", [])) == 5 and persistence.get("durableRowCount") == 5, "five durable rows", failures)
    _assert(persistence.get("currentProjectionRows") == 0 and persistence.get("currentProjectionRowCount") == 0 and persistence.get("currentProjectionPersistence") == "NONPERSISTENT_REBUILD_ONLY", "nonpersistent current projection", failures)
    _assert(persistence.get("secondStore") is False and persistence.get("secondWriter") is False and persistence.get("accountStore") is False and persistence.get("cloudStore") is False, "store/writer boundary", failures)
    _assert(corpus.get("currentProjectionRows") == [] and corpus.get("currentProjectionPersistence") == "NONPERSISTENT_REBUILD_ONLY", "no current projection row", failures)
    _assert({row.get("toState") for row in corpus.get("reviewTransitions", [])} == set(contracts.REVIEW_STATES) - {"DRAFT"}, "review state coverage", failures)
    _assert({row.get("kind") for row in corpus.get("reviewDispositions", [])} == {"CHANGES_REQUESTED", "ACCEPTED"}, "disposition coverage", failures)
    _assert({row.get("state") for row in corpus.get("correctiveActionEvents", [])} == set(contracts.ACTION_STATES), "corrective state coverage", failures)
    _assert(all(row.get("writes") == 0 for row in corpus.get("dispositionPreviews", [])), "zero-write previews", failures)
    _assert(all(row.get("immutable") is True for row in corpus.get("immutableHistories", [])), "immutable history", failures)
    _assert(all(row.get("enrolledBeforeFirstWrite") is True for row in corpus.get("lifecycleCoverage", [])), "lifecycle enrollment", failures)
    hostile_ids = {str(row.get("id")) for row in corpus.get("hostileCases", [])}
    for fragment in ("cross-workspace", "undeclared-transition", "stale", "missing-closure", "wrong-verifier", "history-rewrite", "current-projection", "second-store", "second-writer", "account", "cloud", "delivery", "legal", "finalization"):
        _assert(any(fragment in case_id for case_id in hostile_ids), f"hostile case:{fragment}", failures)
    interruption_ids = {str(row.get("id")) for row in corpus.get("interruptionCases", [])}
    for fragment in ("migration", "writer", "transition", "projection", "backup", "restore", "delete", "replay", "search", "report"):
        _assert(any(fragment in case_id for case_id in interruption_ids), f"interruption case:{fragment}", failures)
    recovery_ids = {str(row.get("id")) for row in corpus.get("recoveryCases", [])}
    for fragment in ("backup", "clone", "forward-fix", "journal", "search", "report", "delete", "released", "immutable"):
        _assert(any(fragment in case_id for case_id in recovery_ids), f"recovery case:{fragment}", failures)
    _assert(corpus.get("claims") and all(value is False for value in corpus["claims"].values()), "claims false", failures)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--complete", action="store_true", help="require every C14 fence path to be changed")
    parser.add_argument("--json", action="store_true", help="emit machine-readable result")
    args = parser.parse_args()

    failures: list[str] = []
    try:
        _assert(_git_value("rev-parse", contracts.BASE_HEAD) == contracts.BASE_HEAD, "base head missing", failures)
        _assert(_git_value("rev-parse", f"{contracts.BASE_HEAD}^{{tree}}") == contracts.BASE_TREE, "base tree drift", failures)
    except (OSError, subprocess.CalledProcessError) as error:
        failures.append(f"git authority:{error}")

    candidate_paths = _candidate_changed_paths()
    unowned_changed = sorted(set(candidate_paths) - set(contracts.PATH_FENCE))
    missing_required_changed = sorted(set(contracts.PATH_FENCE) - set(candidate_paths))
    cache_paths = sorted(path for path in candidate_paths if "__pycache__" in path.split("/") or path.endswith((".pyc", ".pyo", ".DS_Store")))
    s10_overlap = sorted(set(contracts.PATH_FENCE) & S10_RESERVED_PATHS)
    _assert(not unowned_changed, "changed path outside full C14 fence", failures)
    _assert(not cache_paths, "cache artifact changed", failures)
    if args.complete:
        _assert(not missing_required_changed, "required changed path missing from full C14 fence", failures)
    _assert(len(contracts.PATH_FENCE) == 111 and len(set(contracts.PATH_FENCE)) == 111, "exact 111-path fence", failures)
    _assert(len(contracts.EXISTING_PATHS) == 97 and len(contracts.NEW_PATHS) == 14, "path classification counts", failures)
    _assert(len(contracts.MANIFEST_INPUT_PATHS) == 110, "110 manifest inputs", failures)
    _assert(contracts.PATH_FENCE == contracts.EXISTING_PATHS + contracts.NEW_PATHS, "path classification/order", failures)
    _assert(contracts.FENCE_DIGEST == "ba02fb62b37fcf10416c474cfaa366d5a2ec8f6785ca10a581fd940b6643a2d3", "fence digest authority", failures)
    _assert(not s10_overlap, "S10 fence overlap", failures)
    _assert(not set(contracts.TOOL_PATHS) & set(contracts.SOURCE_REFERENCE_PATHS), "tool/source overlap", failures)
    _assert(sum(row.get("overlapCount", 0) for row in contracts.PRIOR_FENCE_OVERLAPS) == 634, "prior overlap total", failures)
    _assert(len(contracts.PRIOR_FENCE_OVERLAPS) == 33 and contracts.PRIOR_FENCE_PROOF.get("fenceCount") == 51 and contracts.PRIOR_FENCE_PROOF.get("priorOwnedPathCount") == 851, "prior fence proof counts", failures)
    _assert(contracts.PRIOR_FENCE_PROOF.get("authorizedOverlapCount") == 634 and contracts.PRIOR_FENCE_PROOF.get("unauthorizedOverlapCount") == 0, "prior fence authorization", failures)
    for relative in contracts.PATH_FENCE:
        _assert(_base_path_exists(relative) is (relative in contracts.EXISTING_PATHS), f"BASE_HEAD existence:{relative}", failures)

    try:
        source_rows = contracts.source_artifacts(ROOT)
        authority_rows = contracts.authority_artifacts(ROOT)
        _assert(len(source_rows) == 97, "source reference count", failures)
        for row in source_rows:
            raw = contracts._git_blob(ROOT, row["path"])
            _assert(row["bytes"] == len(raw) and row["sha256"] == contracts.sha256_bytes(raw), f"source digest:{row['path']}", failures)
    except (OSError, subprocess.CalledProcessError) as error:
        failures.append(f"source inventory:{error}")
        source_rows, authority_rows = [], []

    try:
        schema = _load(contracts.SCHEMA_PATH)
        contract = _load(contracts.CONTRACT_PATH)
        evidence = _load(contracts.EVIDENCE_PATH)
        brand = _load(contracts.BRAND_PATH)
        manifest = _load(contracts.MANIFEST_PATH)
    except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
        failures.append(f"json load:{error}")
        schema = contract = evidence = brand = manifest = {}

    try:
        expected = contracts.all_outputs(ROOT)
        for relative, raw in expected.items():
            path = ROOT / relative
            _assert(path.is_file() and path.read_bytes() == raw, f"deterministic artifact:{relative}", failures)
    except (OSError, json.JSONDecodeError, subprocess.CalledProcessError, TypeError, ValueError) as error:
        failures.append(f"deterministic generation:{error}")
        expected = {}

    _check_corpus(failures)
    _assert(schema == contracts.schema_document(), "schema does not equal generated C14 corpus schema", failures)
    _assert(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema" and schema.get("additionalProperties") is False, "schema strict root", failures)
    for label, document in (("contract", contract), ("evidence", evidence), ("brand", brand), ("manifest", manifest)):
        _check_sealed(document, failures, label)
        _assert(document.get("verificationMode") == "STATIC_ONLY", f"{label}:mode", failures)
        _assert(document.get("authority") == contracts._authority(), f"{label}:authority", failures)
        _assert(document.get("statusFlags") == contracts._flags(), f"{label}:statusFlags", failures)
        _assert(document.get("requiresAcceptedS10_6Reconciliation") is True, f"{label}:reconciliation", failures)
        _assert(document.get("s10FenceOverlapPaths") == [] or document.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], f"{label}:S10 overlap", failures)

    _assert(contract.get("artifact") == "V23P03C14ReviewAndCorrectiveActionContractV1" and contract.get("status") == "PASS_STATIC_PROVISIONAL", "contract identity/status", failures)
    _assert(contract.get("sourceProjection") == contracts.SOURCE_PROJECTION, "contract source projection", failures)
    _assert(contract.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and contract.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "contract prerequisite/order", failures)
    _assert(contract.get("sourceContract", {}).get("sourceArtifacts") == source_rows and contract.get("sourceContract", {}).get("authorityArtifacts") == authority_rows, "contract source rows", failures)
    _assert(contract.get("requiredLifecycle") == list(contracts.LIFECYCLE_DIMENSIONS), "contract lifecycle", failures)
    _assert(contract.get("pathEvidence", {}).get("pathFence") == list(contracts.PATH_FENCE), "contract path fence", failures)
    _assert(contract.get("pathEvidence", {}).get("existingPaths") == list(contracts.EXISTING_PATHS) and contract.get("pathEvidence", {}).get("newPaths") == list(contracts.NEW_PATHS), "contract path classification", failures)
    _assert(contract.get("pathEvidence", {}).get("manifestInputCount") == 110 and contract.get("pathEvidence", {}).get("s10FenceOverlapPaths") == [], "contract path evidence", failures)
    _assert(contract.get("persistenceBoundary") == contracts.PERSISTENCE, "contract persistence boundary", failures)

    _assert(evidence.get("result") == "PASS_STATIC_PROVISIONAL" and evidence.get("sourceProjection") == contracts.SOURCE_PROJECTION, "evidence result/projection", failures)
    _assert(evidence.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and evidence.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "evidence prerequisite/order", failures)
    _assert(evidence.get("pathEvidence") == contract.get("pathEvidence"), "evidence path evidence", failures)
    _assert(evidence.get("sourceContractDigest") == contracts.sha256_value(source_rows) and evidence.get("authorityArtifactDigest") == contracts.sha256_value(authority_rows), "evidence source digests", failures)
    _assert(evidence.get("persistenceBoundary") == contracts.PERSISTENCE, "evidence persistence", failures)
    _assert(brand.get("status") == "PASS_STATIC_PROVISIONAL" and brand.get("affectedSurfacePaths") == [], "brand static boundary", failures)

    manifest_rows = manifest.get("artifacts", [])
    _assert(manifest.get("result") == "PASS_STATIC_PROVISIONAL", "manifest result", failures)
    _assert(manifest.get("pathFence") == list(contracts.PATH_FENCE) and manifest.get("pathFenceDigest") == contracts.FENCE_DIGEST, "manifest fence", failures)
    _assert(manifest.get("pathFenceCount") == 111 and manifest.get("manifestInputCount") == 110 and manifest.get("existingPathCount") == 97 and manifest.get("newPathCount") == 14, "manifest path counts", failures)
    _assert(manifest.get("allowedCreateOrReplacePaths") == list(contracts.PATH_FENCE) and manifest.get("allowedDeletePaths") == [] and manifest.get("allowedRenamePaths") == [], "manifest allowed paths", failures)
    _assert(manifest.get("sourceArtifacts") == source_rows and manifest.get("authorityArtifacts") == authority_rows, "manifest source rows", failures)
    _assert([row.get("path") for row in manifest_rows] == list(contracts.MANIFEST_INPUT_PATHS) and len(manifest_rows) == 110, "manifest input closure", failures)
    for row in manifest_rows:
        _check_manifest_row(row, row.get("path", ""), failures)
    _assert(manifest.get("artifactSetDigest") == contracts.sha256_value(manifest_rows), "manifest artifact set digest", failures)
    _assert(manifest.get("directPrerequisiteEvidence") == contracts.DIRECT_PREREQUISITE_EVIDENCE and manifest.get("orderingAuthority") == contracts.ORDERING_AUTHORITY, "manifest prerequisite/order", failures)
    _assert(manifest.get("persistenceBoundary") == contracts.PERSISTENCE, "manifest persistence", failures)
    try:
        source_text = b"\n".join(contracts._git_blob(ROOT, path) for path in contracts.AUTHORITY_REFERENCE_PATHS).decode("utf-8")
        for token in contracts.SOURCE_CONTRACT_TOKENS:
            _assert(token in source_text, f"source contract token:{token}", failures)
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError) as error:
        failures.append(f"authority token source:{error}")

    fixture_path = ROOT / contracts.FIXTURE_PATH
    if fixture_path.is_file():
        try:
            _assert(_load(contracts.FIXTURE_PATH) == contracts.TEST_CORPUS_SHAPE, "fixture corpus shape equality", failures)
        except (OSError, json.JSONDecodeError, DuplicateKey, TypeError, ValueError) as error:
            failures.append(f"fixture load:{error}")

    result: dict[str, Any] = {
        "result": "PASS_STATIC_PROVISIONAL" if not failures else "FAIL_STATIC_PROVISIONAL",
        "cardID": contracts.CARD,
        "pathFenceCount": len(contracts.PATH_FENCE),
        "existingPathCount": len(contracts.EXISTING_PATHS),
        "newPathCount": len(contracts.NEW_PATHS),
        "manifestInputCount": len(contracts.MANIFEST_INPUT_PATHS),
        "sourceReferenceCount": len(contracts.SOURCE_REFERENCE_PATHS),
        "fenceDigest": contracts.FENCE_DIGEST,
        "baseHead": contracts.BASE_HEAD,
        "baseTree": contracts.BASE_TREE,
        "coordinationHead": contracts.COORDINATION_HEAD,
        "coordinationTree": contracts.COORDINATION_TREE,
        "contextDigest": contracts.CONTEXT_DIGEST,
        "prerequisiteDigest": contracts.PREREQUISITE_DIGEST,
        "unownedChangedPathCount": len(unowned_changed),
        "missingRequiredChangedPathCount": len(missing_required_changed),
        "cachePathCount": len(cache_paths),
        "s10FenceOverlapPaths": s10_overlap,
        "authorizedPriorOverlapCount": contracts.PRIOR_FENCE_PROOF["authorizedOverlapCount"],
        "native": False,
        "hosted": False,
        "adoption": False,
        "acceptance": False,
        "release": False,
    }
    if failures:
        result["failures"] = failures
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
