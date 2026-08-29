#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C32."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C32"
TITLE = "Capability-gated assistance proposals, explicit review, acceptance mutation, and expiry"
REGISTER_ORDINAL = 71
BASE_HEAD = "6e1c6b1fc07d0a6a5886379b3aa2407844b6dc4a"
BASE_TREE = "943c09f17e948d2ebd212dbfeb090efb584b231e"
COORDINATION_HEAD = "01009bd3ed27babfd718d078c2bc24b47cbade29"
COORDINATION_TREE = "8531395d5468c157eccccc3cb047c9efedb0194f"
COORDINATION_CAS_SEQUENCE = 302
HYDRATION_REVISION = 1
PREREQUISITE_DIGEST = "ec0e665bf000b709837652776b1c7dcb2db54bbb9cca5b6a4e36df9e99922c11"
CONTEXT_DIGEST = "b704c099d91a8067ea066b0ce2b4d8a62e5bd9ac156ec14480dea9afb0827776"
FENCE_DIGEST = "8eee1494434e2bb6e82f7c86cf1d34595b76b86ba47c64b0367e0de65e68cdaa"
HYDRATION_TRANSITION_DIGEST = "493629c43c059919f4d01bbb5d62e4811dded9f335bb854e354b76ce20dc0933"
COORDINATION_LEDGER_DIGEST = "b677fda49e7859993988e08c9955289a4587597714be0f255dfcce244d48ad43"
COORDINATION_PROJECTION_DIGEST = "ce5614921210ac6c4b8aea8fb9f0b32ae47c5fb0027f0666037dd1406da5de92"
AUTHORIZED_OVERLAP_COUNT = 2753
UNAUTHORIZED_OVERLAP_COUNT = 0

SCHEMA_PATH = "Scripts/v23/assistance-proposal.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C32AssistanceProposalContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C32AssistanceProposalEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C32BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C32-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c32_contracts.py",
    "Scripts/v23/generate_p03_c32_contracts.py",
    "Scripts/v23/verify_p03_c32_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import p03_c31_contracts as _c31

EXISTING_PATHS = tuple(_c31.EXISTING_PATHS) + tuple(_c31.NEW_PATHS[:6])
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Assistance/AssistanceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssistancePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Assistance/AssistanceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Assistance/AssistanceLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_48AssistanceProposalTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Assistance/V22P03C32AssistanceProposalCorpusV1.json",
    *SCRIPT_PATHS,
    *GENERATED_PATHS,
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

CONTRACT_NAMES = (
    "AssistanceCapabilityReferenceV1",
    "AssistanceTargetV1",
    "AssistanceSourceReferenceV1",
    "AssistanceProposalV1",
    "AssistanceCapabilityPolicyV1",
    "AssistanceProposalEvaluationContextV1",
    "AssistanceProposalExpiryReasonV1",
    "AssistanceAcceptanceRequestV1",
    "AssistanceAcceptanceReceiptV1",
)
TEST_METHODS = (
    "testV23P03C32G01ProposalReviewAcceptanceUsesOneCanonicalMutation",
    "testV23P03C32A01RejectCancelExpireDeleteScratchAndPreserveManualText",
    "testV23P03C32H01StaleTargetsInvalidValuesAndForbiddenCapabilityPathsFailClosed",
    "testV23P03C32I01InterruptedAcceptanceRecoversIdempotentlyWithoutDirectWrites",
    "testV23P03C32R01RestoreReplayAndCapabilityRollbackRemainExact",
)
EXPIRY_TRIGGERS = (
    "TARGET_REVISION_CHANGED",
    "CAPABILITY_REVOKED",
    "PACKAGE_CHANGED",
    "DEFINITION_CHANGED",
    "TIMEOUT",
    "WORKSPACE_SWITCHED",
    "SOURCE_DELETED",
)
HOSTILE_CASES = (
    "PROPOSAL_AFTER_USER_EDIT",
    "CONFIDENCE_ABSENT_WHEN_REQUIRED",
    "CONFIDENCE_OUT_OF_RANGE",
    "WRONG_LOCALE",
    "WRONG_MODEL_VERSION",
    "SOURCE_REMOVED",
    "PERMISSION_REVOKED",
    "WORKSPACE_SWITCHED",
    "APP_KILLED_DURING_REVIEW",
    "TARGET_REVISION_STALE",
    "TYPED_VALUE_INVALID_FOR_FIELD",
)
FLAGS = {
    key: False
    for key in (
        "native",
        "hosted",
        "adoption",
        "acceptance",
        "release",
        "nativeAcceptance",
        "hostedAcceptance",
        "adoptionEvidence",
        "acceptanceCredit",
        "releaseReadiness",
        "phase10PollingDuringParallelExecution",
    )
}
PERSISTENCE_PINS_PENDING = False
PERSISTENCE: dict[str, Any] = {
    "schemaRelease": "ASSISTANCE_ACCEPTANCE_V1",
    "persistentSchemaVersion": 32,
    "recordsSchemaVersion": 31,
    "persistentKindLifecycleModelCount": 110,
    "durableFamilyCount": 1,
    "persistedFamilies": ["AssistanceAcceptanceReceiptRow"],
    "nonpersistentFamilies": ["AssistanceProposalV1", "AssistanceCapabilityScratchV1"],
    "mode": "NEW_SCHEMA_VERSION",
    "migrationRequired": True,
    "backupRestoreRequired": True,
    "cloneForkRequired": True,
    "deleteEraseRequired": True,
    "exportReportRequired": True,
    "searchRebuildRequired": True,
    "replayRequired": True,
    "interruptionRecoveryRequired": True,
    "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V32_WRITE",
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_paths(root: Path, *args: str) -> set[str]:
    output = subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True, text=True).stdout
    return {path.replace("\\", "/") for path in output.splitlines() if path}


def observed_changed_paths(root: Path) -> set[str]:
    changed = _git_paths(root, "diff", "--name-only", f"{BASE_HEAD}..HEAD", "--")
    changed |= _git_paths(root, "diff", "--name-only", "--")
    changed |= _git_paths(root, "diff", "--cached", "--name-only", "--")
    changed |= _git_paths(root, "ls-files", "--others", "--exclude-standard")
    return changed


def _base_exists(root: Path, path: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{path}"], capture_output=True
    ).returncode == 0


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / "FieldEvidenceAppTests/V9_48AssistanceProposalTests.swift"
    if not path.is_file():
        return ()
    return tuple(
        re.findall(r"\bfunc\s+(testV23P03C32(?:G|A|H|I|R)\d{2}\w*)\s*\(", path.read_text(encoding="utf-8"))
    )


def require_source_ready(root: Path) -> None:
    required = NEW_PATHS[:6]
    missing = [path for path in required if not (root / path).is_file()]
    if missing:
        raise ValueError("C32 stable source absent:" + ",".join(missing))
    selectors = observed_selectors(root)
    if len(selectors) != 5 or set(selectors) != set(TEST_METHODS):
        raise ValueError("C32 exact G/A/H/I/R selectors differ")
    if PERSISTENCE_PINS_PENDING or PERSISTENCE["persistedFamilies"] != ["AssistanceAcceptanceReceiptRow"]:
        raise ValueError("C32 only durable family must be AssistanceAcceptanceReceiptRow")


def _tokens(root: Path, path: str, *tokens: str) -> str:
    target = root / path
    if not target.is_file():
        raise ValueError(f"C32 source absent:{path}")
    text = target.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"C32 source regression:{path}:" + ",".join(missing))
    return text


def assert_source_regressions(root: Path) -> None:
    require_source_ready(root)
    core = _tokens(
        root,
        "FieldEvidenceApp/Domain/Assistance/AssistanceContractsV1.swift",
        *CONTRACT_NAMES,
        "let capabilityID: String",
        "let version: String",
        "let localeIdentifier: String?",
        "let target: AssistanceTargetV1",
        "let value: ResponseValueV1",
        "let source: AssistanceSourceReferenceV1",
        "let createdAt: Date",
        "let expiresAt: Date",
        "let privacyClass: AssistancePrivacyClassV1",
        "let expectedRevision: WorkspaceExpectedRevisionV1",
        "let mutationID: MutationIDV1",
        "case targetRevisionChanged = \"TARGET_REVISION_CHANGED\"",
        "case capabilityRevoked = \"CAPABILITY_REVOKED\"",
        "case packageChanged = \"PACKAGE_CHANGED\"",
        "case definitionChanged = \"DEFINITION_CHANGED\"",
        "case timedOut = \"TIMED_OUT\"",
        "case workspaceChanged = \"WORKSPACE_CHANGED\"",
        "case sourceDeleted = \"SOURCE_DELETED\"",
        "durableRejectedCorpusCreated = false",
    )
    if re.search(r"\b(?:URLSession|NWConnection|OpenAI|Generative|Diagnosis|ComplianceSuggestion)\b", core):
        raise ValueError("C32 network/generative/diagnosis/compliance surface detected")
    models = _tokens(
        root,
        "FieldEvidenceApp/Domain/Models/AssistancePersistenceModelsV1.swift",
        "final class AssistanceAcceptanceReceiptRow",
        "persistentSchemaVersion = 32",
        "recordsSchemaVersion = 31",
        "durableModelCount = 1",
        "totalModelCount = 110",
        "proposalIsPersistent = false",
        "rejectedProposalCorpusIsPersistent = false",
    )
    if len(re.findall(r"@Model\s+final\s+class", models)) != 1 or "AssistanceProposal" in models:
        raise ValueError("C32 proposal persisted or durable row count differs")
    _tokens(
        root,
        "FieldEvidenceApp/Application/Assistance/AssistanceCoordinatorV1.swift",
        "expectedRevision",
        "mutationID",
        "accept",
        "reject",
        "cancel",
        "expire",
        "AssistanceProposalLifecycleV1",
    )
    _tokens(
        root,
        "FieldEvidenceApp/Infrastructure/Assistance/AssistanceLifecycleAdapterV1.swift",
        "AssistanceAcceptanceReceiptV1",
        "writer",
        "commit",
        "validate",
    )
    _tokens(root, "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift", "PersistentSchemaV32", "AssistanceAcceptanceReceiptRow.self")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "C32AssistancePackageValidationV1")
    _tokens(root, "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift", "validateAssistanceLifecycle")
    _tokens(root, "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift", "AssistanceSearchIsolationPolicyV1")
    _tokens(root, "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift", "C32")
    _tokens(root, "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "C32")
    _tokens(root, "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift", "C32")
    tests = _tokens(
        root,
        "FieldEvidenceAppTests/V9_48AssistanceProposalTests.swift",
        *TEST_METHODS,
        "XCTAssertThrowsError",
    )
    for token in (
        ".targetRevisionChanged",
        ".capabilityRevoked",
        ".packageChanged",
        ".timedOut",
        ".workspaceChanged",
        ".sourceDeleted",
        "scratchDeleted",
        "manualTextPreserved",
        "acceptedAssistanceReceipt",
        "wrongLocale",
    ):
        if token not in tests:
            raise ValueError("C32 required transition/hostile coverage regressed:" + token)
    corpus = json.loads(
        (root / "FieldEvidenceAppTests/Fixtures/V22/Assistance/V22P03C32AssistanceProposalCorpusV1.json").read_text(
            encoding="utf-8"
        )
    )
    if (
        corpus.get("proposalPersistenceDisposition") != "NONPERSISTENT"
        or corpus.get("durableFamilies") != ["AssistanceAcceptanceReceiptV1"]
        or corpus.get("persistentSchemaVersion") != 32
        or corpus.get("recordsSchemaVersion") != 31
        or corpus.get("expiryTriggers") != list(EXPIRY_TRIGGERS)
        or corpus.get("hostileCases") != list(HOSTILE_CASES)
        or corpus.get("lifecycle", {}).get("acceptanceReceipt") != "PERSISTENT_V32_RECORDS31"
        or corpus.get("invariants", {}).get("proposalNeverCanonical") is not True
        or corpus.get("invariants", {}).get("proposalNeverPersistent") is not True
        or corpus.get("invariants", {}).get("rejectedProposalCorpusRetained") is not False
    ):
        raise ValueError("C32 proposal/durable-family/schema corpus boundary differs")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (200, 14, 214) or len(set(PATH_FENCE)) != 214:
        raise ValueError("C32 fence must be unique 214=200+14")
    if any("s10" in path.lower() or "phase10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C32 S10 overlap")
    tree = subprocess.run(
        ["git", "-C", str(root), "show", "-s", "--format=%T", BASE_HEAD],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if tree != BASE_TREE:
        raise ValueError("C32 base tree differs")
    for path in EXISTING_PATHS:
        if not _base_exists(root, path):
            raise ValueError(f"existing absent at base:{path}")
    for path in NEW_PATHS:
        if _base_exists(root, path):
            raise ValueError(f"new existed at base:{path}")
    if AUTHORIZED_OVERLAP_COUNT != 2753 or UNAUTHORIZED_OVERLAP_COUNT != 0 or any(FLAGS.values()):
        raise ValueError("C32 authority proof differs")


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": REGISTER_ORDINAL,
        "title": TITLE,
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationRevision": HYDRATION_REVISION,
        "prerequisiteDigest": PREREQUISITE_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "allowedPathCount": 214,
        "existingPathCount": 200,
        "newPathCount": 14,
        "authorizedOverlapCount": 2753,
        "unauthorizedOverlapCount": 0,
        "directPrerequisiteCards": ["V23-P03-C26"],
        "nextCard": "V23-P03-C33",
        "digestPinsPending": PERSISTENCE_PINS_PENDING,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value))}


def schema_document() -> dict[str, Any]:
    transition_matrix = [
        {"action": "ACCEPT", "proposalDisposition": "REMOVED", "scratchDisposition": "DELETED", "canonicalMutationCount": 1, "durableAcceptanceReceiptCount": 1},
        {"action": "REJECT", "proposalDisposition": "REMOVED", "scratchDisposition": "DELETED", "canonicalMutationCount": 0, "durableAcceptanceReceiptCount": 0},
        {"action": "CANCEL", "proposalDisposition": "REMOVED", "scratchDisposition": "DELETED", "canonicalMutationCount": 0, "durableAcceptanceReceiptCount": 0},
        {"action": "EXPIRE", "proposalDisposition": "REMOVED", "scratchDisposition": "DELETED", "canonicalMutationCount": 0, "durableAcceptanceReceiptCount": 0},
    ]
    recovery = {
        "effectBeforeReceipt": "RECOVER_SAME_ACCEPTED_EFFECT_AND_RECEIPT",
        "receiptBeforeEffect": "FORBIDDEN",
        "retryMutationID": "RETURNS_SAME_RECEIPT",
        "relaunchDuringReview": "EXPIRE_AND_DELETE_SCRATCH",
        "userEnteredText": "PRESERVED_INDEPENDENTLY",
    }
    lifecycle = {
        "proposal": "NONPERSISTENT",
        "scratch": "NONPERSISTENT_DELETE_ON_TERMINAL_DISPOSITION",
        "acceptanceReceipt": "PERSISTENT_V32_RECORDS31",
        "backup": "ACCEPTANCE_RECEIPT_ONLY",
        "restore": "ACCEPTANCE_RECEIPT_ONLY",
        "search": "EXCLUDED",
        "report": "EXCLUDED",
        "diagnostics": "BOUNDED_COUNTS_ONLY",
        "replication": "ACCEPTED_CANONICAL_EFFECT_ONLY",
        "deleteErase": "WORKSPACE_SCOPED_RECEIPT_REMOVAL",
    }
    invariants = {
        "proposalNeverCanonical": True,
        "proposalNeverPersistent": True,
        "proposalNeverBackedUp": True,
        "proposalNeverSearched": True,
        "proposalNeverReported": True,
        "noDirectMutation": True,
        "explicitReviewRequired": True,
        "expectedRevisionRequired": True,
        "manualPathEquivalent": True,
        "capabilitiesRollbackIndependently": True,
        "noSharedGlobalConfidenceThreshold": True,
        "noHiddenNetworkFallback": True,
        "noDiagnosisOrComplianceSuggestion": True,
        "rejectedProposalCorpusRetained": False,
    }
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/assistance-proposal.schema.json",
        "title": "V23 P03 C32 Assistance Proposal Corpus",
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C32AssistanceProposalCorpusV1"},
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD},
            "persistentSchemaVersion": {"const": 32},
            "recordsSchemaVersion": {"const": 31},
            "proposalPersistenceDisposition": {"const": "NONPERSISTENT"},
            "durableFamilies": {"const": ["AssistanceAcceptanceReceiptV1"]},
            "requiredContractNames": {"const": list(CONTRACT_NAMES)},
            "evidenceIDs": {"const": [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]},
            "capabilities": {
                "type": "array",
                "minItems": 4,
                "uniqueItems": True,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "id": {"type": "string", "minLength": 1},
                        "version": {"type": "string", "minLength": 1},
                        "locale": {"type": "string", "minLength": 1},
                        "modelVersion": {"type": "string", "minLength": 1},
                        "permission": {"type": "string", "minLength": 1},
                        "manualFallback": {"const": "MANUAL_TYPED_FIELD_ENTRY"},
                    },
                    "required": ["id", "version", "locale", "modelVersion", "permission", "manualFallback"],
                },
            },
            "typedValueCases": {
                "type": "array",
                "minItems": 8,
                "uniqueItems": True,
                "items": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "kind": {"type": "string", "minLength": 1},
                        "value": {"type": "string"},
                        "unit": {"type": "string", "minLength": 1},
                        "description": {"type": "string", "minLength": 1},
                    },
                    "required": ["kind", "value"],
                },
            },
            "transitionMatrix": {"const": transition_matrix},
            "expiryTriggers": {"const": list(EXPIRY_TRIGGERS)},
            "hostileCases": {"const": list(HOSTILE_CASES)},
            "recovery": {"const": recovery},
            "lifecycle": {"const": lifecycle},
            "invariants": {"const": invariants},
            "statusFlags": {"type": "object", "additionalProperties": {"const": False}},
        },
        "required": [
            "schema",
            "schemaVersion",
            "cardID",
            "persistentSchemaVersion",
            "recordsSchemaVersion",
            "proposalPersistenceDisposition",
            "durableFamilies",
            "requiredContractNames",
            "evidenceIDs",
            "capabilities",
            "typedValueCases",
            "transitionMatrix",
            "expiryTriggers",
            "hostileCases",
            "recovery",
            "lifecycle",
            "invariants",
            "statusFlags",
        ],
    }


def contract_document(root: Path) -> dict[str, Any]:
    assert_source_regressions(root)
    semantics = {
        "contractNames": list(CONTRACT_NAMES),
        "fiveSelectors": list(observed_selectors(root)),
        "proposalAndCapabilityScratchAreNonpersistent": True,
        "acceptanceReceiptIsOnlyDurableFamily": True,
        "explicitReviewBeforeOneCanonicalMutation": True,
        "expectedRevisionAndMutationIDBound": True,
        "effectBeforeReceiptRecoveryIsIdempotent": True,
        "rejectCancelExpireDeleteScratchWithoutCorpus": True,
        "manualUserTextAndFallbackRemainIndependent": True,
        "allSixExpirySourcesAreCovered": True,
        "capabilitiesAreIndependentlyEnabledLocalizedAndRolledBack": True,
        "typedValueSourceLocalePrivacyAndVersionChecksFailClosed": True,
        "noDirectWriteAutomaticMergeOrRejectedAnalytics": True,
        "noNetworkFallbackGenerativeDiagnosisOrComplianceSuggestion": True,
        "backupRestoreCloneForkDeleteEraseExportSearchReplayClosure": True,
    }
    return _sealed(
        {
            "schema": "V23P03C32AssistanceProposalContractV1",
            "schemaVersion": 1,
            "authority": authority(),
            "persistence": PERSISTENCE,
            "requiredSemantics": semantics,
        }
    )


def evidence_document(root: Path) -> dict[str, Any]:
    contract = contract_document(root)
    return _sealed(
        {
            "schema": "V23P03C32AssistanceProposalEvidenceReceiptV1",
            "schemaVersion": 1,
            "cardID": CARD,
            "evidenceIDs": [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")],
            "testSelectors": list(observed_selectors(root)),
            "requiredSemanticsDigest": sha256_value(contract["requiredSemantics"]),
            "proposalPersistenceDisposition": "NONPERSISTENT",
            "durableFamilies": ["AssistanceAcceptanceReceiptV1"],
            "statusFlags": FLAGS,
        }
    )


def brand_document() -> dict[str, Any]:
    return _sealed(
        {
            "schema": "V23P03C32BrandImpactManifestV1",
            "schemaVersion": 1,
            "cardID": CARD,
            "uiSurfaceDelta": False,
            "brandSurfaceDelta": True,
            "nativeIPadSurface": False,
            "telemetry": False,
            "networkProcessing": False,
            "generativeDiagnosis": False,
            "statusFlags": FLAGS,
        }
    )


def _row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    raw = rendered[path] if path in rendered else (root / path).read_bytes()
    return {"path": path, "sha256": sha256_bytes(raw), "byteCount": len(raw)}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_source_regressions(root)
    rendered = {
        SCHEMA_PATH: pretty(schema_document()),
        CONTRACT_PATH: pretty(contract_document(root)),
        EVIDENCE_PATH: pretty(evidence_document(root)),
        BRAND_PATH: pretty(brand_document()),
    }
    rows = [_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    rendered[MANIFEST_PATH] = pretty(
        _sealed(
            {
                "schema": "V23P03C32ToolingManifestV1",
                "schemaVersion": 1,
                "authority": authority(),
                "pathFence": list(PATH_FENCE),
                "pathFenceCount": 214,
                "existingPathCount": 200,
                "newPathCount": 14,
                "authorizedOverlapCount": 2753,
                "unauthorizedOverlapCount": 0,
                "artifacts": rows,
                "artifactSetDigest": sha256_value(rows),
                "statusFlags": FLAGS,
            }
        )
    )
    return rendered
