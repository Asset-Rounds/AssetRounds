#!/usr/bin/env python3
"""Deterministic V23-P00-C08 experience and journey contracts."""

from __future__ import annotations

import json
import re
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any

from c07_contracts import (
    DEPENDENCY_DISPOSITION_DIGEST, GRAPH_DIGEST, OVERRIDE_RECEIPT_DIGEST,
    PACKAGE_DIGEST, REGISTER_DIGEST, RELATION_DIGEST, RESERVATION_DIGEST,
    SELECTOR_DIGEST, ContractError, load_reservation, pretty_bytes, seal,
    sha256_bytes, validate_frozen_authority,
)

CARD_ID = "V23-P00-C08"
BASE_HEAD = "e6bfa3dd047e15b71f132b76db2e358bc734bfb0"
BASE_TREE = "e333cf05f1256b2636f31c96cf1d74d323d61193"
CONTEXT_DIGEST = "970c8b15ad738c1969caa4e47d104a95600bee80dccd284284cc02fc0eb076db"
FENCE_DIGEST = "6a227a647dfd279cbd62edaa0501ff153e5ca5676260319aa7031e91b901ef1b"
PREREQUISITE_DIGEST = "4fd27cf40d362da2c7d170284618c0d6d0fb89c605f156283de152ae2de5f6e8"
LEDGER_DIGEST = "e37bcca5dcad00c80cb7b160ce100d0bef2cab15362f3450b56f0a1d9bcb7ca2"
LEDGER_CAS_SEQUENCE = 43
DOSSIER_DIGEST = "fd8fa7e7266b64dde5f01f2e978bbdbf8fb69dd42d09e2474457aecedce84a1a"
INHERITED_BLOCK_DIGEST = "446e9257fa36c2017d8a90dfffc953e50e4c2bac3626512adf6bdce390712ce9"
REGISTER_ROW_DIGEST = "463e84abc0629ce07e70454b75844a6f8d5817cd548793f832225a494463ec04"
PLANNING_AUTHORITY_IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
PLANNING_AUTHORITY_FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
C06_CONTEXT_DIGEST = "afbb364ed404d4fbd57ee66c5707c8f670a002b8d81cdc425cc6a0cfb3c53d60"
C06_FENCE_DIGEST = "ca49bcc135ddc270e18c42b808a804a6b1de71bb8a08647b32bccd3b1a9a6eca"
C06_PLATFORM_DIGEST = "ba548ef8cec1be0d290c300ebf88f10239640bc57e35841843aa4632d4bbed6b"
C06_TOOLING_DIGEST = "33e5f0043ab318261ec63ee92b0bc4360215e5fd7bd7ac279b647738b743198e"
C06_VERIFICATION_DIGEST = "77444d12c7a2bec4b09f16e96fcb70f8278805d58200a15cd8033263eb4d53b8"
C06_CHECKPOINT_DIGEST = "8bdd5bcee83c136496e1ca6bd4b2a9ec79719ecf002d6f8bca9b73d853fc03ee"

STATIC_SEAM_INVENTORY = [
    {"path": "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift",
     "seam": "PRODUCTION_COMPOSITION", "disposition": "STATIC_OBSERVATION_ONLY"},
    {"path": "FieldEvidenceApp/Domain/Feedback/FeedbackConfigurationV1.swift",
     "seam": "FEEDBACK_CONFIGURATION", "disposition": "STATIC_OBSERVATION_ONLY"},
    {"path": "FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift",
     "seam": "SYSTEM_HANDOFF_ADAPTER", "disposition": "STATIC_OBSERVATION_ONLY"},
    {"path": "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
     "seam": "PERSISTENCE_FACTORY", "disposition": "STATIC_OBSERVATION_ONLY"},
]
RESERVED_SHARED_DEFERRALS = [
    {"path": "FieldEvidenceApp/DesignSystem/DesignTokens.swift", "owner": "FROZEN_S10_SHARED_OWNER",
     "disposition": "DEFERRED_RESERVED_NO_POLLING_OR_MUTATION"},
    {"path": "FieldEvidenceApp/DesignSystem/WorklightComponents.swift", "owner": "FROZEN_S10_SHARED_OWNER",
     "disposition": "DEFERRED_RESERVED_NO_POLLING_OR_MUTATION"},
    {"path": "FieldEvidenceApp/Features/Shell/AppShellView.swift", "owner": "FROZEN_S10_SHARED_OWNER",
     "disposition": "DEFERRED_RESERVED_NO_POLLING_OR_MUTATION"},
    {"path": "FieldEvidenceApp/Features/Reports/ReportsRootView.swift", "owner": "FROZEN_S10_SHARED_OWNER",
     "disposition": "DEFERRED_RESERVED_NO_POLLING_OR_MUTATION"},
]

BLUEPRINT = "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"
FOUNDATION = "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md"
BLUEPRINT_DIGEST = "fb3cb3b55e60062e574444b57ddc075345053c396c9da1b2c5e5350f2aeae2a2"
FOUNDATION_DIGEST = "f7d4ac03f066d85771526c195152ab6e17c32c2a9dee98248c3bfa8813456980"
SCHEMA_PATHS = [
    "Scripts/v23/premium-experience-policy.schema.json",
    "Scripts/v23/common-task-journey-release.schema.json",
    "Scripts/v23/common-task-journey-receipt.schema.json",
    "Scripts/v23/feature-end-to-end-journey-release.schema.json",
    "Scripts/v23/feature-end-to-end-journey-receipt.schema.json",
    "Scripts/v23/owner-physical-journey-release.schema.json",
    "Scripts/v23/owner-physical-journey-receipt.schema.json",
    "Scripts/v23/journey-evidence-layer.schema.json",
    "Scripts/v23/interaction-acceptance-receipt.schema.json",
]
ARTIFACT_PATHS = [
    "docs/design/v23/tooling/PremiumExperiencePolicyV1.json",
    "docs/design/v23/tooling/CommonTaskJourneyReleaseV2.json",
    "docs/design/v23/tooling/CommonTaskJourneyReceiptV2.json",
    "docs/design/v23/tooling/FeatureEndToEndJourneyReleaseV1.json",
    "docs/design/v23/tooling/FeatureEndToEndJourneyReceiptV1.json",
    "docs/design/v23/tooling/OwnerPhysicalJourneyReleaseV1.json",
    "docs/design/v23/tooling/OwnerPhysicalJourneyReceiptV1.json",
    "docs/design/v23/tooling/JourneyEvidenceLayerV2.json",
    "docs/design/v23/tooling/InteractionAcceptanceReceiptV2.json",
]
MANIFEST_PATH = "docs/design/v23/tooling/V23-P00-C08-tooling-manifest.json"
FENCED_PATHS = [
    "Scripts/v23/c08_contracts.py", "Scripts/v23/generate_c08_contracts.py",
    "Scripts/v23/verify_c08_contracts.py", *SCHEMA_PATHS, *ARTIFACT_PATHS, MANIFEST_PATH,
]

PRINCIPLES = ["CLARITY", "IMMEDIACY", "CONTINUITY", "RECOVERY", "RESTRAINT"]
EVIDENCE_LAYERS = ["AUTOMATED_SEMANTIC", "UNCOACHED_PILOT", "OWNER_EXTERNAL_EFFECT"]
EXPECTED_HIG_COUNTS = {
    "APPLICABLE": 65, "DEFERRED_OUTSIDE_V21": 6,
    "NOT_APPLICABLE_WITH_RATIONALE": 76, "PLATFORM_HANDLED": 10,
}
INHERITED_CONTRACTS = [
    "PremiumExperiencePolicyV1", "PlatformAppearanceProfileV1", "NativeComponentDispositionV1",
    "LiquidGlassUsageManifestV1", "ToolbarActionInventoryV1", "SearchPlacementDispositionV1",
    "ContentPatternCatalogV1", "InteractionRecipeV1", "FeedbackSemanticV1", "MotionRoleV1",
    "HapticRoleV1", "FocusTraversalPolicyV1", "FormInteractionPolicyV1",
    "ValidationFocusDispositionV1", "LoadingFeedbackPolicyV1", "LoadingOperationTokenV1",
    "CommonTaskJourneyReleaseV1", "JourneyEvidenceLayerV1", "CommonJourneyCoverageDispositionV1",
    "InteractionContinuityBaselineV1", "NavigationChangeDispositionV1", "UpgradeExperienceReceiptV1",
    "PerformanceEvidenceTierV1", "PerceivedPerformanceBudgetV1",
    "CriticalJourneyPerformanceManifestV1", "InteractionAcceptanceReceiptV1",
]

INHERITED_SEMANTICS = {
    "outcome": "ONE_SHARED_TESTABLE_PREMIUM_EXPERIENCE_POLICY_AND_DETERMINISTIC_ACCEPTANCE_HARNESS",
    "policyOwnership": [
        "NATIVE_ADAPTATION", "TASK_CONTINUITY", "CONTENT_AND_FEEDBACK_TRUTH",
        "FOCUS_AND_INPUT", "MOTION_AND_HAPTICS", "LOADING", "PERCEIVED_PERFORMANCE",
    ],
    "lifecycle": {
        "policyCatalogJourneyReleases": "IMMUTABLE_BUNDLED_INPUTS_APPEND_SUCCESSOR",
        "runtimeInventoryMeasurementScreenshotTraceReceipt": "BUILD_BOUND_EVIDENCE_NOT_WORKSPACE_RECORD",
        "releaseTestSupport": "PHYSICALLY_ABSENT",
        "customerDataOrCanonicalMutation": "NONE",
        "rollback": "REVERT_UNACCEPTED_POLICY_OR_HARNESS_DELTA_WHEN_SAFE",
        "forwardFix": "APPEND_SUCCESSOR_AND_REPROVE_AFFECTED_CONSUMERS",
    },
    "hostileCases": [
        "RAPID_DOUBLE_TAP", "COMPLETION_AFTER_ROUTE_WORKSPACE_OR_REVISION_CHANGE",
        "CANCELLATION_RACES_RECEIPT", "RECEIPT_SUCCEEDS_READBACK_FAILS",
        "BACKGROUND_DURING_FEEDBACK", "HAPTIC_PREFERENCE_OFF", "HAPTIC_RUNTIME_NO_OP",
        "UNSAFE_CAPTURE_CONTEXT", "REDUCE_MOTION_PLUS_REDUCE_TRANSPARENCY",
        "KEYBOARD_AT_AX5_RTL", "EXTERNAL_KEYBOARD", "VOICEOVER_FOCUS_INVALIDATION",
        "SYSTEM_SHEET_INTERRUPTION", "NATIVE_BAR_APPEARANCE_CHANGE", "UNSUPPORTED_OR_BETA_API",
        "LOW_POWER_OR_THERMAL_PRESSURE", "MAXIMUM_DATA_OR_MEDIA", "CORRUPT_PRIOR_ROUTE_FIXTURE",
        "CUSTOM_GLASS_OBSCURES_CONTRAST", "CURRENT_PLATFORM_ACTION_BECOMES_MENU_ONLY",
    ],
    "interruptionPoints": [
        "BEFORE_ACKNOWLEDGEMENT", "AFTER_ACKNOWLEDGEMENT", "DURING_DETERMINATE_WORK",
        "DURING_INDETERMINATE_WORK", "AT_RECEIPT", "AT_READBACK", "DURING_FOCUS_TRANSITION",
        "DURING_MEASUREMENT_CAPTURE",
    ],
    "recovery": [
        "RELAUNCH_OWNS_DURABLE_STATE_AND_SAFE_ROUTE", "NO_REPEATED_SUCCESS_OR_DUPLICATE_ACTION",
        "NO_FABRICATED_MEASUREMENT", "IDENTICAL_FIXTURE_AND_SIGNPOST_SEMANTICS_DETERMINISTIC",
        "MEASURED_VARIANCE_BOUNDED", "PROFILE_BUDGET_OR_CATALOG_CHANGE_APPENDS_SUCCESSOR",
        "ACCEPTED_EVIDENCE_AND_HISTORIC_ARTIFACTS_IMMUTABLE",
    ],
    "hardStops": [
        "UNMET_DEPENDENCY", "OVERLAPPING_UNOWNED_S10_WORK",
        "MATERIAL_OWNER_DECISION_WITHOUT_CONSERVATIVE_NATIVE_FALLBACK",
        "MISSING_STABLE_TOOLCHAIN_OR_RUNTIME", "RELEASE_TEST_SUPPORT_LEAKAGE",
        "NONCORRECTABLE_MISSING_ACCEPTANCE_AUTHORITY",
    ],
    "futureTrigger": "NONE",
}


def authority_binding() -> dict[str, Any]:
    return {
        "attemptID": 1, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "candidateBinding": "EXTERNAL_EXACT_HEAD_AND_TREE_RECEIPT_REQUIRED",
        "packageDigest": PACKAGE_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST, "registerRowDigest": REGISTER_ROW_DIGEST,
        "planningAuthorityImpactDigest": PLANNING_AUTHORITY_IMPACT_DIGEST,
        "planningAuthorityFacetDigest": PLANNING_AUTHORITY_FACET_DIGEST,
        "canonicalRegisterDigest": REGISTER_DIGEST, "directGraphDigest": GRAPH_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST, "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "ownerOverrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "bootstrapContextDigest": CONTEXT_DIGEST, "bootstrapPathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "directPrerequisite": {
            "cardID": "V23-P00-C06", "contextDigest": C06_CONTEXT_DIGEST,
            "fenceDigest": C06_FENCE_DIGEST, "verificationDigest": C06_VERIFICATION_DIGEST,
            "checkpointDigest": C06_CHECKPOINT_DIGEST, "platformArtifactDigest": C06_PLATFORM_DIGEST,
            "toolingManifestDigest": C06_TOOLING_DIGEST, "predecessorCandidateHead": BASE_HEAD,
            "predecessorCandidateTree": BASE_TREE, "releaseTestSupportAbsent": False,
        },
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "ledgerDigest": LEDGER_DIGEST, "ledgerCASSequence": LEDGER_CAS_SEQUENCE,
        "phase10PollingDuringParallelExecution": False, "acceptanceEnabled": False,
        "hostedDispatchEnabled": False, "adoptionEnabled": False,
        "requiresAcceptedS10_6Reconciliation": True, "releaseCredit": False,
    }


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          capture_output=True, text=True, encoding="utf-8").stdout


def validate_fence(root: Path) -> None:
    if len(FENCED_PATHS) != 22 or len(set(FENCED_PATHS)) != 22:
        raise ContractError("C08 fence must contain exactly 22 unique paths")
    reservation = load_reservation(root)
    if set(FENCED_PATHS) & set(reservation["reservedPaths"]):
        raise ContractError("C08 tooling overlaps frozen Phase10 ownership")
    changed = {p.replace("\\", "/") for p in git(root, "diff", "--name-only", BASE_HEAD).splitlines() if p}
    if not changed <= set(FENCED_PATHS):
        raise ContractError(f"C08 out-of-fence delta: {sorted(changed - set(FENCED_PATHS))}")
    for line in git(root, "status", "--porcelain=v1", "--untracked-files=all").splitlines():
        code, raw = line[:2], line[3:]
        if " -> " in raw or "D" in code or "R" in code:
            raise ContractError(f"C08 delete/rename is forbidden: {line}")
        if raw.replace("\\", "/") not in FENCED_PATHS:
            raise ContractError(f"C08 out-of-fence work: {raw}")


def section(text: str, start: str, end: str) -> str:
    begin = text.index(start)
    finish = text.index(end, begin)
    return text[begin:finish].rstrip() + "\n"


def rows_from_table(value: str, expected_columns: int) -> list[list[str]]:
    rows = []
    for line in value.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or stripped.startswith("|---"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) != expected_columns or cells[0] in (
            "ID", "Stable ID", "Apple category / leaf topic",
        ):
            continue
        cells = [cell[1:-1] if len(cell) >= 2 and cell.startswith("`") and cell.endswith("`") else cell
                 for cell in cells]
        rows.append(cells)
    return rows


def source_contracts(root: Path) -> dict[str, Any]:
    blueprint_bytes = (root / BLUEPRINT).read_bytes()
    foundation_bytes = (root / FOUNDATION).read_bytes()
    if sha256_bytes(blueprint_bytes) != BLUEPRINT_DIGEST or sha256_bytes(foundation_bytes) != FOUNDATION_DIGEST:
        raise ContractError("C08 pinned planning source digest differs")
    blueprint = blueprint_bytes.decode("utf-8")
    foundation = foundation_bytes.decode("utf-8")
    common_rows = rows_from_table(section(blueprint, "### 6.1 CommonTaskJourneyReleaseV2", "### 6.2 FeatureEndToEndJourneyReleaseV1"), 3)
    feature_rows = rows_from_table(section(blueprint, "### 6.2 FeatureEndToEndJourneyReleaseV1", "## 7. Canonical dossier schema"), 3)
    hig_rows = rows_from_table(section(foundation, "    ## 19. Complete current Apple HIG applicability matrix", "    ## 20. Planning completion and implementation acceptance"), 15)
    if len(common_rows) != 14 or [row[0].split("_")[0] for row in common_rows] != [f"J{i:02d}" for i in range(1, 15)]:
        raise ContractError("C08 J01-J14 source authority differs")
    if len(feature_rows) != 17 or [row[0] for row in feature_rows] != [f"FJ{i:02d}" for i in range(1, 18)]:
        raise ContractError("C08 FJ01-FJ17 source authority differs")
    counts = dict(sorted(Counter(row[3] for row in hig_rows).items()))
    if len(hig_rows) != 157 or counts != EXPECTED_HIG_COUNTS:
        raise ContractError(f"C08 HIG matrix differs: rows={len(hig_rows)} counts={counts}")
    return {
        "common": [{"id": row[0], "startAndPath": row[1], "successEndpoint": row[2]} for row in common_rows],
        "feature": [{"id": row[0], "journey": row[1], "requiredEndToEndOutcome": row[2]} for row in feature_rows],
        "hig": [{
            "topic": row[0], "sourceAndObservedUpdate": row[1], "snapshot": row[2],
            "disposition": row[3], "surfacesAndJourneys": row[4], "owner": row[5],
            "repoEvidenceOrGap": row[6], "refinementOrRationale": row[7], "brandImpact": row[8],
            "affectedConsumers": row[9], "minimumRuntime": row[10], "latestStableRuntime": row[11],
            "accessibility": row[12], "acceptanceEvidence": row[13], "ownerOnlyEvidence": row[14],
        } for row in hig_rows],
        "higCounts": counts,
    }


def common_fields(schema: str) -> dict[str, Any]:
    return {
        "schema": schema, "schemaVersion": 1, "cardID": CARD_ID,
        "authority": authority_binding(), "lifecycle": {
            "persistence": "NONPERSISTENT_IMMUTABLE_BUNDLED_POLICY_OR_BUILD_BOUND_EVIDENCE",
            "supersession": "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_EVIDENCE",
            "customerData": "NONE", "interruption": "FAIL_CLOSED_NO_PARTIAL_ACCEPTANCE",
            "recovery": "DETERMINISTIC_REGENERATION_OR_SUCCESSOR_RECEIPT",
        },
    }


def seal_artifact(value: dict[str, Any]) -> dict[str, Any]:
    value.update({"acceptanceCredit": False, "releaseCredit": False})
    return seal(value)


def not_run_rows(ids: list[str], required: str) -> list[dict[str, Any]]:
    return [{"id": value, "memberDigest": "", "requiredEvidence": [required],
             "startingFixture": None, "typedRoute": None, "semanticPath": None,
             "publicUIActions": [], "checkpoints": [], "branches": [], "successEndpoint": None,
             "cancelBehavior": None, "backBehavior": None, "focusBehavior": None,
             "fallbackBehavior": None, "accessibilityEvidence": [],
             "startingFixtureResult": "NOT_RUN", "pathResult": "NOT_RUN",
             "checkpointResult": "NOT_RUN", "branchResult": "NOT_RUN",
             "endpointResult": "NOT_RUN", "cancelResult": "NOT_RUN", "backResult": "NOT_RUN",
             "focusResult": "NOT_RUN", "fallbackResult": "NOT_RUN",
             "accessibilityResult": "NOT_RUN", "artifacts": [], "result": "NOT_RUN",
             "blocksAcceptance": True} for value in ids]


def member_digest(member: dict[str, Any]) -> str:
    return sha256_bytes(pretty_bytes(member))


def common_members(rows: list[dict[str, str]]) -> list[dict[str, Any]]:
    members = []
    for row in rows:
        external = row["id"].startswith(("J12_", "J13_"))
        layers = ["AUTOMATED_SEMANTIC", "OWNER_EXTERNAL_EFFECT"] if external else [
            "AUTOMATED_SEMANTIC", "UNCOACHED_PILOT"]
        members.append({
            "id": row["id"], "taskIdentity": row["id"],
            "typedRoute": "REQUIRED_CONSUMER_ENROLLMENT",
            "startingFixture": row["startAndPath"].split(" → ", 1)[0],
            "semanticPath": row["startAndPath"], "visiblePrimaryAction": "REQUIRED",
            "safeResumeAnchor": "REQUIRED_CONSUMER_ENROLLMENT",
            "accessibilityIdentity": "REQUIRED_CONSUMER_ENROLLMENT",
            "checkpoints": "REQUIRED_CONSUMER_ENROLLMENT",
            "branches": "REQUIRED_CONSUMER_ENROLLMENT",
            "successEndpoint": row["successEndpoint"], "cancelBehavior": "REQUIRED",
            "backBehavior": "REQUIRED", "focusBehavior": "REQUIRED",
            "fallbackBehavior": "REQUIRED", "requiredEvidenceLayers": layers,
            "consumerEnrollment": "REQUIRED_BEFORE_CONSUMER_ACCEPTANCE",
        })
    return members


def receipt_rows(members: list[dict[str, Any]], required: str) -> list[dict[str, Any]]:
    rows = not_run_rows([member["id"] for member in members], required)
    for row, member in zip(rows, members):
        row["memberDigest"] = member_digest(member)
        row["requiredEvidence"] = member.get("requiredEvidenceLayers", [required])
        row["evidenceLayerResults"] = [
            {"layer": layer, "result": "NOT_RUN", "artifactReferences": []}
            for layer in row["requiredEvidence"]
        ]
    return rows


def build_artifacts(root: Path) -> dict[str, dict[str, Any]]:
    validate_frozen_authority(root)
    validate_fence(root)
    sources = source_contracts(root)
    c06 = json.loads((root / "docs/design/v23/tooling/V23PlatformScopeManifestV1.json").read_text(encoding="utf-8"))
    c06_manifest = json.loads((root / "docs/design/v23/tooling/V23-P00-C06-tooling-manifest.json").read_text(encoding="utf-8"))
    if c06["artifactDigest"] != C06_PLATFORM_DIGEST or c06_manifest["artifactDigest"] != C06_TOOLING_DIGEST:
        raise ContractError("C08 C06 artifact binding differs")
    blocker = c06["releaseTestSupportBlocker"]
    if blocker["releaseAbsenceSatisfied"]:
        raise ContractError("C08 expected the retained C07 Release-support blocker")
    reservation = load_reservation(root)
    reserved = set(reservation["reservedPaths"])
    if any(not (root / row["path"]).is_file() or row["path"] in reserved for row in STATIC_SEAM_INVENTORY):
        raise ContractError("C08 static seam inventory is missing or reserved")
    if any(not (root / row["path"]).is_file() or row["path"] not in reserved for row in RESERVED_SHARED_DEFERRALS):
        raise ContractError("C08 shared-owner deferral is missing or not reserved")

    common = common_members(sources["common"])
    feature = sources["feature"]

    policy_laws = {
        "ownershipBoundary": {
            "appOwned": "S10_BRANDED_CONTENT_AND_SEMANTICS",
            "systemOwned": "NATIVE_PLATFORM_CHROME_PRESENTATION_AND_ADAPTATION",
            "unknownOrCustomOwnership": "FAIL_CLOSED",
        },
        "nativeComponentLaw": {
            "systemComponentsDefault": True,
            "customExceptionRequiredFields": ["SYSTEM_INSUFFICIENCY", "ACCESSIBILITY_PARITY",
                                               "OLDER_RUNTIME_FALLBACK", "CONSUMER_SET", "REMOVAL_TEST"],
            "unregisteredCustomControl": "FORBIDDEN",
        },
        "materialGlassLaw": {
            "prohibited": ["CONTENT_LAYER_GLASS", "DECORATIVE_GLASS", "STACKED_GLASS",
                           "DUPLICATE_BAR_BACKGROUND", "BLANKET_S10_MATERIAL_OVERRIDE", "BACKPORTED_GLASS"],
            "nativeChromeAdapts": True, "appContentRemainsS10Branded": True,
        },
        "actionAndSearchLaw": {
            "maximumAppAuthoredToolbarGroupsBeforeNativeOverflow": 3,
            "systemItemsExcludedFromGroupCount": True, "dominantTaskActionCount": 1,
            "searchDispositionCardinalityPerSearchableSurface": 1,
            "closedSearchDispositionsInclude": "NO_SEARCH_WITH_RATIONALE",
            "gestureOnlyRequiredAction": "FORBIDDEN", "minimumAppAuthoredTargetPoints": 44,
            "maximumAcknowledgementMilliseconds": 100,
        },
        "contentFeedbackTruthLaw": {
            "successRequires": ["DURABLE_RECEIPT", "CANONICAL_READBACK"],
            "forbiddenOptimisticClaims": ["SAVED", "COMPLETE", "SENT", "DELIVERED", "VERIFIED", "SECURE", "APPROVED"],
            "feedbackParity": ["VISIBLE_TEXT_OR_ICON", "ASSISTIVE_TECHNOLOGY"],
        },
        "focusAndFormLaw": {
            "multiErrorSummaryAnnouncementCount": 1, "firstInvalidFocusMoveCount": 1,
            "backgroundRefreshMayResetFocus": False,
            "profiles": ["KEYBOARD", "SAFE_AREA", "RTL", "EXTERNAL_KEYBOARD", "VOICEOVER",
                         "VOICE_CONTROL", "SWITCH_CONTROL", "DYNAMIC_TYPE_AX5"],
        },
        "loadingTokenLaw": {
            "states": ["RUNNING", "STALLED", "CANCELLED", "SUCCEEDED", "FAILED", "SUPERSEDED"],
            "requiredTransitions": ["ACKNOWLEDGEMENT", "HEARTBEAT", "STALL", "RETRY_SUCCESSOR",
                                    "CANCELLATION", "LATE_EFFECT_RECONCILIATION", "STALE_UI_FENCING"],
            "duplicateEffect": "FORBIDDEN", "staleSuccess": "FORBIDDEN",
        },
        "motionHapticLaw": {
            "purposefulAndOptional": True, "normalReduceMotionSemanticParity": True,
            "hapticOnlyMeaning": "FORBIDDEN", "systemMotionAndControlsFirst": True,
            "physicalSensationOrOSSettingClaim": "FORBIDDEN",
            "hapticMatrix": ["APP_PREFERENCE_ON", "APP_PREFERENCE_OFF", "RUNTIME_AVAILABLE",
                             "RUNTIME_NO_OP", "BACKGROUND", "RETRY", "UNSAFE_CAPTURE_CONTEXT"],
        },
        "performanceLaw": {
            "tiers": ["AUTOMATED_SIMULATOR_REGRESSION", "OWNER_PHYSICAL_RELEASE"],
            "measuredRepetitions": 20, "additionalBatchMaximum": 10,
            "additionalBatchConditionPercent": 5, "gateStatistic": "P95", "zeroHangsRequired": True,
            "maximumIsDiagnosticExceptHang": True, "ambiguousAfterThirty": "INCONCLUSIVE_BLOCKED",
            "missingBaseline": "USE_ABSOLUTE_CEILING_AND_FREEZE_FIRST_ACCEPTED_SUCCESSOR_BASELINE",
        },
        "staticScanners": ["UNAUTHORIZED_CUSTOM_TAB_SEARCH_OR_BAR_OWNER", "UNREGISTERED_MATERIAL_PATH",
                           "UNREGISTERED_MOTION_PATH", "UNREGISTERED_HAPTIC_PATH", "RELEASE_TEST_SPY",
                           "SUCCESS_BEFORE_RECEIPT", "MISSING_COMMON_JOURNEY_REGISTRATION",
                           "MISSING_CONTENT_PATTERN_REGISTRATION"],
        "releaseExclusion": ["TEST_SPIES", "SCENARIO_FLAGS", "PERFORMANCE_FIXTURE_DATA",
                             "CUSTOM_HAPTIC_ENGINE", "UNREGISTERED_INTERACTION_PATH"],
        "deferrals": [
            {"evidence": "DUAL_RUNTIME_NATIVE_SEMANTIC_PARITY", "owner": "HOSTED_ACCEPTANCE", "status": "NOT_RUN"},
            {"evidence": "OWNER_PHYSICAL_RELEASE", "owner": "V23-P05-C02_OWNER_GATE", "status": "NOT_RUN"},
            {"evidence": "FEATURE_JOURNEY_IMPLEMENTATION", "owner": "DECLARED_P02_P04_P05_CONSUMERS", "status": "NOT_RUN"},
            {"evidence": "RELEASE_ARCHIVE_EXCLUSION", "owner": "C07_RELEASE_SUPPORT_BLOCKER_THEN_HOSTED_ACCEPTANCE", "status": "NOT_RUN"},
            {"evidence": "ACCEPTED_S10_6_BASELINE", "owner": "RECONCILIATION_AUTHORITY", "status": "NOT_RUN"},
        ],
    }

    policy = seal_artifact({**common_fields("PremiumExperiencePolicyV1"),
        "principles": PRINCIPLES, "premiumMeaning": "INTERNAL_ACCEPTANCE_TARGET_NOT_PAID_MODE_OR_PUBLIC_CLAIM",
        "higSnapshot": {"observationDate": "2026-08-22", "rowCount": 157,
                        "topLevelCategoryCount": 6, "intermediateComponentCategoryCount": 8,
                        "taxonomyNodeCount": 171, "dispositionCounts": sources["higCounts"],
                        "rows": sources["hig"], "currentness": "PLANNING_SNAPSHOT_STATIC_ONLY_RECHECK_NOT_RUN"},
        "inheritedContractClosure": [{"contract": name, "disposition": "PRESERVED_IN_STATIC_POLICY_RELEASE",
                                      "nativeEvidence": "NOT_RUN"} for name in INHERITED_CONTRACTS],
        "inheritedSemantics": INHERITED_SEMANTICS,
        "laws": policy_laws,
        "acceptanceHarness": {
            "evidenceIDs": ["V23-P00-C08-G01", "V23-P00-C08-A01", "V23-P00-C08-H01",
                            "V23-P00-C08-I01", "V23-P00-C08-R01"],
            "runtimeProfiles": ["MINIMUM_IOS_18", "LATEST_ACCEPTED_STABLE_SHIPPING_RUNTIME"],
            "dualRuntimeSemanticParity": "NOT_RUN", "betaRuntimeAcceptance": "FORBIDDEN",
            "releaseArchiveExclusion": "NOT_RUN_C07_BLOCKER_RETAINED",
        },
        "prohibitions": ["SECOND_DESIGN_SYSTEM", "HIG_CERTIFICATION_OR_PUBLIC_CLAIM",
                         "PAID_PREMIUM_MODE", "CUSTOM_NAVIGATION_OR_TAB_SHELL", "PIXEL_LOCK_NATIVE_UI",
                         "ANALYTICS_OR_SESSION_REPLAY", "NATIVE_IPAD_SCOPE"],
        "currentSeamObservation": {"mode": "STATIC_NONRESERVED_SOURCE_OBSERVATION_ONLY",
                                   "inventory": STATIC_SEAM_INVENTORY,
                                   "reservedSharedOwnerDeferrals": RESERVED_SHARED_DEFERRALS,
                                   "acceptedS10Baseline": "NOT_FABRICATED_RECONCILIATION_REQUIRED",
                                   "productMutation": False},
    })
    common_release = seal_artifact({**common_fields("CommonTaskJourneyReleaseV2"),
        "orderedMembers": common, "memberCount": 14,
        "frozenSemantics": ["TYPED_ROUTE", "TASK_IDENTITY", "VISIBLE_PRIMARY_ACTION", "SAFE_RESUME_ANCHOR",
                            "ACCESSIBILITY_IDENTITY", "STARTING_FIXTURE", "CHECKPOINTS_BRANCHES_ENDPOINT",
                            "CANCEL_BACK_FOCUS_FALLBACK"], "pixelsFrozen": False,
    })
    feature_release = seal_artifact({**common_fields("FeatureEndToEndJourneyReleaseV1"),
        "orderedMembers": feature, "memberCount": 17,
        "publicUIActionRequired": True, "directStateSetupOnlyForPreconditions": True,
        "receiptBindingContract": {
            "requiredPerMember": ["STARTING_FIXTURE", "PUBLIC_UI_ACTIONS", "CHECKPOINTS", "BRANCHES",
                                  "SUCCESS_ENDPOINT", "ACCESSIBILITY_EVIDENCE", "FALLBACK_BEHAVIOR",
                                  "ARTIFACT_REFERENCES", "EVIDENCE_LAYER_RESULTS"],
            "concreteRouteIdentifiers": "REQUIRED_CONSUMER_ENROLLMENT_NO_INVENTED_IMPLEMENTATION",
            "zeroMissingMembers": True,
        },
    })
    owner_release = seal_artifact({**common_fields("OwnerPhysicalJourneyReleaseV1"),
        "commonJourneyRequirements": {"uncoached": [row["id"] for row in common if not row["id"].startswith(("J12_", "J13_"))],
                                      "ownerExternalEffect": ["J12_PURCHASE_RESTORE", "J13_DELETE_ERASE"]},
        "featureJourneyIDs": [row["id"] for row in feature],
        "physicalSystemFamilies": ["AUTHENTICATION", "CAMERA_SCAN", "AUDIO_SPEECH",
                                   "PRINTING_SHARE_CANCELLATION", "FIELD_USABILITY"],
        "enrollmentStatus": "NOT_RUN_OWNER_GATE",
    })
    layers = seal_artifact({**common_fields("JourneyEvidenceLayerV2"),
        "layers": EVIDENCE_LAYERS,
        "closedResults": ["PASS", "FAIL", "STOPPED_SAFETY", "NOT_RUN", "NOT_APPLICABLE_WITH_RATIONALE"],
        "requiredLayerNotRunBlocks": True, "automatedSemanticStatus": "NOT_RUN",
        "uncoachedPilotStatus": "NOT_RUN", "ownerExternalEffectStatus": "NOT_RUN",
    })
    common_receipt = seal_artifact({**common_fields("CommonTaskJourneyReceiptV2"),
        "candidateHead": None, "candidateTree": None,
        "releaseDigest": common_release["artifactDigest"],
        "memberDigests": [member_digest(member) for member in common],
        "journeys": receipt_rows(common, "AUTOMATED_SEMANTIC"),
        "zeroMissingMembers": True, "evidenceStatus": "NOT_RUN", "receiptSatisfied": False,
    })
    feature_receipt = seal_artifact({**common_fields("FeatureEndToEndJourneyReceiptV1"),
        "candidateHead": None, "candidateTree": None,
        "releaseDigest": feature_release["artifactDigest"],
        "memberDigests": [member_digest(member) for member in feature],
        "journeys": receipt_rows(feature, "AUTOMATED_SEMANTIC"),
        "zeroMissingMembers": True, "evidenceStatus": "NOT_RUN", "receiptSatisfied": False,
    })
    owner_receipt = seal_artifact({**common_fields("OwnerPhysicalJourneyReceiptV1"),
        "candidateHead": None, "candidateTree": None,
        "releaseDigest": owner_release["artifactDigest"],
        "commonReleaseDigest": common_release["artifactDigest"],
        "featureReleaseDigest": feature_release["artifactDigest"],
        "commonMemberDigests": [member_digest(member) for member in common],
        "featureMemberDigests": [member_digest(member) for member in feature],
        "commonJourneys": receipt_rows(common, "OWNER_PHYSICAL_OR_EXTERNAL_EFFECT"),
        "featureJourneys": receipt_rows(feature, "OWNER_PHYSICAL_RELEASE"),
        "evidenceStatus": "NOT_RUN_REQUIRED_PENDING_OWNER", "receiptSatisfied": False,
    })
    interaction = seal_artifact({**common_fields("InteractionAcceptanceReceiptV2"),
        "candidateHead": None, "candidateTree": None,
        "policyDigest": policy["artifactDigest"], "commonReleaseDigest": common_release["artifactDigest"],
        "commonReceiptDigest": common_receipt["artifactDigest"], "featureReleaseDigest": feature_release["artifactDigest"],
        "featureReceiptDigest": feature_receipt["artifactDigest"], "ownerPhysicalReleaseDigest": owner_release["artifactDigest"],
        "ownerPhysicalReceiptDigest": owner_receipt["artifactDigest"], "journeyEvidenceLayerDigest": layers["artifactDigest"],
        "nativeEvidence": "NOT_RUN", "dualRuntimeSemanticParity": "NOT_RUN",
        "performanceEvidence": {"simulator": "NOT_RUN", "ownerPhysical": "NOT_RUN_REQUIRED_PENDING_OWNER",
                                "repeatRule": "20_PLUS_AT_MOST_ONE_BATCH_OF_10_WITHIN_5_PERCENT_NOISE_BAND",
                                "p95GateEvaluated": False, "zeroHangProof": "NOT_RUN"},
        "archiveReleaseExclusion": "NOT_RUN_C07_BLOCKER_RETAINED",
        "releaseTestSupportBlocker": blocker, "acceptedS10Baseline": "NOT_FABRICATED_RECONCILIATION_REQUIRED",
        "acceptedS10BaselineDigest": None, "acceptanceEnabled": False, "adoptionEnabled": False,
        "archiveInspectionComplete": False, "installedRuntimeClosureComplete": False,
        "releaseHookClosureComplete": False, "releaseTestSupportAbsent": False,
        "nativeCompileRan": False, "hostedDispatchRan": False,
        "interactionAcceptanceSatisfied": False, "releaseReady": False,
    })
    artifacts = [policy, common_release, common_receipt, feature_release, feature_receipt,
                 owner_release, owner_receipt, layers, interaction]
    return dict(zip(ARTIFACT_PATHS, artifacts))


RESULT_VALUES = ["PASS", "FAIL", "STOPPED_SAFETY", "NOT_RUN", "NOT_APPLICABLE_WITH_RATIONALE"]
STATUS_VALUES = [*RESULT_VALUES, "NOT_RUN_REQUIRED_PENDING_OWNER", "INCONCLUSIVE_BLOCKED",
                 "ACCEPTED", "BLOCKED", "REQUIRED", "FORBIDDEN", "SATISFIED"]


def structural_schema(value: Any, key: str = "") -> dict[str, Any]:
    """Build a closed structural schema without freezing receipt evidence values."""
    if key in ("schema", "schemaVersion", "cardID"):
        return {"const": value}
    if value is None:
        if key in ("candidateHead", "candidateTree"):
            return {"anyOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9a-f]{40}$"}]}
        if key.endswith("Digest"):
            return {"anyOf": [{"type": "null"}, {"type": "string", "pattern": "^[0-9a-f]{64}$"}]}
        if key in ("startingFixture", "typedRoute", "semanticPath", "successEndpoint",
                   "cancelBehavior", "backBehavior", "focusBehavior", "fallbackBehavior"):
            return {"anyOf": [{"type": "null"}, {"type": "string", "minLength": 1}]}
        return {"type": "null"}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer", "minimum": 0}
    if isinstance(value, str):
        if key.endswith("Digest"):
            return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        if key in ("baseHead", "baseTree"):
            return {"type": "string", "pattern": "^[0-9a-f]{40}$"}
        lowered = key.lower()
        if key == "result" or lowered.endswith("result") or lowered.endswith("status") or key in (
            "nativeEvidence", "dualRuntimeSemanticParity", "archiveReleaseExclusion",
            "acceptedS10Baseline", "automatedSemanticStatus", "uncoachedPilotStatus",
            "ownerExternalEffectStatus", "simulator", "ownerPhysical", "zeroHangProof",
        ):
            return {"type": "string", "enum": sorted(set(STATUS_VALUES + [value]))}
        return {"type": "string", "minLength": 1}
    if isinstance(value, list):
        if key in ("artifacts", "artifactReferences", "publicUIActions", "checkpoints", "branches",
                   "accessibilityEvidence"):
            return {"type": "array", "items": {"type": "string", "minLength": 1}}
        return {"type": "array", "minItems": len(value), "maxItems": len(value),
                "prefixItems": [structural_schema(item, key) for item in value], "items": False}
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "required": list(value),
                "properties": {name: structural_schema(item, name) for name, item in value.items()}}
    raise ContractError(f"unsupported schema value for {key}")


def reusable_schema(artifact: dict[str, Any]) -> dict[str, Any]:
    body = structural_schema(artifact)
    return {"$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": f"https://assetrounds.invalid/v23/{artifact['schema']}.schema.json",
            "title": artifact["schema"], **body}


def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    artifacts = build_artifacts(root)
    schemas = {schema: reusable_schema(artifacts[artifact])
               for schema, artifact in zip(SCHEMA_PATHS, ARTIFACT_PATHS)}
    return {**schemas, **artifacts}


def build_manifest(root: Path) -> dict[str, Any]:
    rows = []
    for relative in FENCED_PATHS:
        if relative == MANIFEST_PATH:
            continue
        path = root / relative
        if not path.is_file():
            raise ContractError(f"C08 manifest input missing: {relative}")
        rows.append({"path": relative, "sha256": sha256_bytes(path.read_bytes()), "bytes": path.stat().st_size})
    return seal({"schema": "V23P00C08ToolingManifestV1", "schemaVersion": 1, "cardID": CARD_ID,
                 "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "authority": authority_binding(),
                 "pathFence": FENCED_PATHS, "artifacts": rows, "artifactCount": len(rows),
                 "nativeCompileRan": False, "hostedDispatchRan": False,
                 "phase10PollingDuringParallelExecution": False, "acceptanceCredit": False,
                 "releaseReady": False, "releaseCredit": False})
