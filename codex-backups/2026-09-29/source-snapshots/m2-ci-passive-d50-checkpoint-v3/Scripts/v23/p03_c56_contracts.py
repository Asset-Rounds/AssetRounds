#!/usr/bin/env python3
"""Fail-closed tooling and sealed receipts for V23-P03-C56.

The C56 source lane owns the structured-voice implementation rows.  This
module owns only the deterministic schema/receipt projection and the static
checks which consume those rows.  Inherited paths are assembled from the
sealed C55 fence plus the exact C32/C36 provider slices; no coordination store
is read at runtime.
"""
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

CARD = "V23-P03-C56"
TITLE = "On-device StructuredVoiceProposalV1, deterministic grammar, source spans, ambiguity, expiry, and explicit field acceptance"
REGISTER_ORDINAL = 87

# Immutable C56 hydration authority supplied by the accepted coordination
# record.  The coordination checkout is intentionally never read.
BASE_HEAD = "dc59c04251eef2d6574a152b846c0cade2ab2caf"
BASE_TREE = "308c809d842a54bbfaf8fa3dfce6d5cd520ab54a"
COORDINATION_HEAD = "3226a4cf509a04ee62671f2f7f9db15141c7687a"
COORDINATION_TREE = "043ab79fdddf74b5e1b1929fdeb22951da40be7e"
COORDINATION_CAS_SEQUENCE = 368
CONTEXT_DIGEST = "c5b5b2c95e6f0cd01e7b9a716f67b5a3af5506699d838adbea7ebb1227e7f6b5"
FENCE_DIGEST = "e20dc754e933f82200f12aa5db7cb13d9322e71d0cdabbf6fb0320b77d40d5d3"
PREREQUISITE_DIGEST = "779fe8e8f0397e91b833d6f8dee95de2686bd6c5cad23f8cf5b08b86e8b92deb"
HYDRATION_TRANSITION_DIGEST = "e1c6ec725371d7b8ea694f7675aba3d96dfb8ef02e8e42deda34beb7324fdf04"
COORDINATION_LEDGER_DIGEST = "e95613ccc5c4874ef71dcf9e7f6190eff63aa764132742c77f3fb9e9762e8f86"
COORDINATION_PROJECTION_DIGEST = "96fb3474975d3aab33f3f898ab620e88920564c1dc4bf39b9f42eb91532ee491"

# The C56 dossier/register pins are filled from the immutable planning bytes
# below.  These are checked before rendering so a moving plan cannot be bound
# silently.
DOSSIER_SHA256 = "9da5798bf145b7d987c46457aaa872662959bba0aed1011e7d09701e4a059305"
DOSSIER_BYTES = 7178
REGISTER_ROW_SHA256 = "3edcf21659d666dcf32c1dada382c7e2744c94e205bd8973e49e96b2f1e498e0"
REGISTER_ROW_BYTES = 300
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217

EXPECTED_EXISTING_PATH_COUNT = 226
EXPECTED_NEW_PATH_COUNT = 14
EXPECTED_FENCE_PATH_COUNT = 240
AUTHORIZED_OVERLAP_COUNT = 4810
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 85
PRIOR_OWNED_PATH_COUNT = 1384
S10_RESERVED_PATH_COUNT = 86

SCHEMA_PATH = "Scripts/v23/structured-voice-proposal.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C56StructuredVoiceProposalContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C56StructuredVoiceProposalEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C56BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C56-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c56_contracts.py",
    "Scripts/v23/generate_p03_c56_contracts.py",
    "Scripts/v23/verify_p03_c56_contracts.py",
)
GENERATED_PATHS = (CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_PATHS)
GENERATED_INPUT_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH)

# The six C56 ownership rows are the only new product/test/fixture paths.
IMPLEMENTATION_PATHS: tuple[str, ...] = (
    "FieldEvidenceApp/Domain/VoiceStructuring/VoiceStructuringContractsV1.swift",
    "FieldEvidenceApp/Application/VoiceStructuring/VoiceStructuringServiceV1.swift",
    "FieldEvidenceApp/Application/VoiceStructuring/VoiceProposalReviewCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/VoiceStructuring/VoiceStructuringLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_64StructuredVoiceProposalTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/StructuredVoice/V22P03C56StructuredVoiceProposalCorpusV1.json",
)


def _sealed_c55_fence() -> tuple[str, ...]:
    """Load the accepted C55 fence without reading coordination state."""
    path = Path(__file__).with_name("p03_c55_contracts.py")
    spec = importlib.util.spec_from_file_location("_sealed_p03_c55_contracts", path)
    if spec is None or spec.loader is None:
        raise ValueError("C55 tooling inventory unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    fence = tuple(module.PATH_FENCE)
    if len(fence) != 177 or len(set(fence)) != 177:
        raise ValueError("sealed C55 fence differs")
    return fence


# C36 is a provider slice rather than a new C56 owner.  Keep its exact
# hydrated order and include only rows not already present in the C55 fence.
_C36_PROVIDER_PATHS: tuple[str, ...] = (
    "FieldEvidenceApp/Infrastructure/Persistence/DeviceLifecycleCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift",
    "FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift",
    "FieldEvidenceApp/Infrastructure/Storage/StoragePreflightService.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreSchemaV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/LocalJobStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/JobScaleBudgetPolicyV1.swift",
    "FieldEvidenceAppTests/S3_1DraftSchemaTests.swift",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests.swift",
    "FieldEvidenceAppTests/S3_4ResumeRecoveryTests.swift",
    "FieldEvidenceAppTests/S3_5FailureIntegrityTests.swift",
    "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
    "FieldEvidenceAppTests/S7_4DraftAccessPolicyTests.swift",
    "FieldEvidenceAppTests/S7_5DataRightsIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_09ConcurrencyScaleTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
    "FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift",
    "FieldEvidenceApp/Application/Drafts/DraftRecoveryProjectionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftAutosaveSchedulerV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftAttachmentStagingAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Drafts/DraftCommitSagaRecoveryV1.swift",
    "FieldEvidenceAppTests/V9_30FieldDraftResilienceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Drafts/V21P03C36FieldDraftResilienceCorpusV1.json",
    "Scripts/v23/p03_c36_contracts.py",
    "Scripts/v23/generate_p03_c36_contracts.py",
    "Scripts/v23/verify_p03_c36_contracts.py",
    "Scripts/v23/field-draft-resilience.schema.json",
    "docs/design/v23/tooling/V23P03C36FieldDraftResilienceContractV1.json",
    "docs/design/v23/tooling/V23P03C36FieldDraftResilienceEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P03C36BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P03-C36-tooling-manifest.json",
)

# C32's complete implementation/tooling slice is consumed as an existing
# provider input by C56.  The C55 fence already contains the shared kernel;
# these are the fourteen C32-owned paths absent from it.
_C32_PROVIDER_PATHS: tuple[str, ...] = (
    "FieldEvidenceApp/Domain/Assistance/AssistanceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssistancePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Assistance/AssistanceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Assistance/AssistanceLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_48AssistanceProposalTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Assistance/V22P03C32AssistanceProposalCorpusV1.json",
    "Scripts/v23/p03_c32_contracts.py",
    "Scripts/v23/generate_p03_c32_contracts.py",
    "Scripts/v23/verify_p03_c32_contracts.py",
    "Scripts/v23/assistance-proposal.schema.json",
    "docs/design/v23/tooling/V23P03C32AssistanceProposalContractV1.json",
    "docs/design/v23/tooling/V23P03C32AssistanceProposalEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P03C32BrandImpactManifestV1.json",
    "docs/design/v23/tooling/V23-P03-C32-tooling-manifest.json",
)

_C55_FENCE = _sealed_c55_fence()
EXISTING_PATHS: tuple[str, ...] = _C55_FENCE + _C36_PROVIDER_PATHS + _C32_PROVIDER_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
CONTRACT_REFS = (
    "VoiceStructuringGrammarReleaseV1",
    "StructuredVoiceProposalV1",
    "VoiceProposalReviewPlanV1",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)
QUALITY_STATES = (
    "EXACT_EXPLICIT_GRAMMAR",
    "AMBIGUOUS_REQUIRES_MANUAL_ENTRY",
    "UNSUPPORTED",
)
CANONICAL_UNITS = (
    "EACH",
    "PERCENT",
    "MILLIMETER",
    "CENTIMETER",
    "METER",
    "INCH",
    "FOOT",
    "GRAM",
    "KILOGRAM",
    "OUNCE",
    "POUND",
    "MILLILITER",
    "LITER",
    "GALLON",
)
UNMATCHED_CLAUSE_REASONS = (
    "NO_EXPLICIT_GRAMMAR_MATCH",
    "MULTIPLE_EXPLICIT_GRAMMAR_MATCHES",
    "VALUE_OUTSIDE_CLOSED_GRAMMAR",
    "REJECTED_BY_FIELD_VALIDATION",
)
ALLOWED_PROPOSAL_FIELDS = (
    "NOTE_TEXT",
    "FINDING_TEXT",
    "ALLOWED_ENUM",
    "EXACT_NUMBER_AND_UNIT",
    "DURATION",
    "MATERIAL_DESCRIPTION_AND_QUANTITY",
)
PROPOSAL_LIFETIME_SECONDS = 30 * 60
P04_C45_CAPTURE_UI_RUNTIME_OWNERSHIP = (
    "capture",
    "review UI",
    "runtime route",
    "surface enrollment",
)
FORBIDDEN_INFERENCES = (
    "DIAGNOSIS",
    "COMPLIANCE",
    "SEVERITY",
    "IDENTITY",
    "PLACEMENT",
    "SCHEDULE",
    "EXACT_STOCK_BINDING",
    "STOCK_DECREMENT",
    "CANONICAL_COMMAND",
    "COMPLETION",
    "FINALIZATION",
)
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_VERSION",
    "WRITER_QUERY",
    "MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK",
    "IMPORT_EXPORT",
    "JOURNAL_REPLAY",
    "SEARCH_REBUILD",
    "REPORT_PROJECTION",
    "DELETE_ERASE",
    "RETENTION",
    "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX",
    "INTERRUPTION",
    "IDEMPOTENT_RECEIPTS",
)

FLAGS = {name: False for name in (
    "activation",
    "native",
    "hosted",
    "adoption",
    "acceptance",
    "release",
    "nativeAcceptance",
    "hostedAcceptance",
    "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

# Structured voice remains a nonpersistent proposal.  Accepted fields use the
# existing C36 draft checkpoint/writer authority; this card adds no model row,
# schema release, records release, second writer, search family, or report
# family.
PERSISTENCE = {
    "mode": "NONPERSISTENT_PROPOSAL_EXISTING_C36_DRAFT_ACCEPTANCE",
    "proposal": "NONPERSISTENT",
    "scratchAudio": "NONPERSISTENT_DELETE_ON_TERMINAL_DISPOSITION",
    "acceptedFieldCheckpoint": "P03-C36_EXISTING_DRAFT_CHECKPOINT_AND_WRITER",
    "persistentSchemaVersionUnchanged": True,
    "recordsSchemaVersionUnchanged": True,
    "durableFamilyCount": 0,
    "durableFamilies": [],
    "newPersistentModelCount": 0,
    "backup": "PROPOSAL_EXCLUDED_ACCEPTED_DRAFT_USES_EXISTING_C36_LIFECYCLE",
    "restore": "PROPOSAL_EXCLUDED_ACCEPTED_DRAFT_USES_EXISTING_C36_LIFECYCLE",
    "cloneFork": "PROPOSAL_INVALIDATED_DRAFT_AUTHORITY_REMAINS_C36",
    "importExport": "NO_PROPOSAL_EXPORT",
    "journalReplay": "NO_PROPOSAL_JOURNAL_ROW",
    "search": "EXCLUDED",
    "report": "EXCLUDED",
    "deleteErase": "SCRATCH_DELETED_PROPOSAL_DISCARDED",
    "retention": "NO_AUDIO_RETENTION",
}

FINAL_HASHES_SEALED = True


def canonical(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key:{key}")
        result[key] = value
    return result


def _json(root: Path, relative: str) -> dict[str, Any]:
    path = root / relative
    if not path.is_file():
        raise ValueError(f"source path absent:{relative}")
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError(f"JSON object required:{relative}")
    return value


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError(f"source path absent:{relative}")
    return path.read_text(encoding="utf-8")


def _valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-fA-F]{64}", value) is not None


def _authority_pins_ready() -> bool:
    heads = (BASE_HEAD, BASE_TREE, COORDINATION_HEAD, COORDINATION_TREE)
    digests = (
        CONTEXT_DIGEST,
        FENCE_DIGEST,
        PREREQUISITE_DIGEST,
        HYDRATION_TRANSITION_DIGEST,
        COORDINATION_LEDGER_DIGEST,
        COORDINATION_PROJECTION_DIGEST,
        DOSSIER_SHA256,
        REGISTER_ROW_SHA256,
        REGISTER_SECTION_SHA256,
    )
    return all(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value) for value in heads) and all(
        _valid_sha(value) for value in digests
    )


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"{label} missing:" + ",".join(missing))


def _require_one_of(text: str, alternatives: Iterable[str], label: str) -> None:
    if not any(token in text for token in alternatives):
        raise ValueError(f"{label} missing alternatives:" + ",".join(alternatives))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.IGNORECASE | re.DOTALL) is None]
    if missing:
        raise ValueError(f"{label} missing patterns:" + ",".join(missing))


def _git_paths(root: Path, *arguments: str) -> set[str]:
    output = subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return {line.strip().replace("\\", "/") for line in output.splitlines() if line.strip()}


def observed_changed_paths(root: Path) -> set[str]:
    changed = _git_paths(root, "diff", "--name-only", BASE_HEAD, "--")
    changed |= _git_paths(root, "diff", "--cached", "--name-only", "--")
    changed |= _git_paths(root, "ls-files", "--others", "--exclude-standard")
    return changed


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    return {
        "hydrated": len(IMPLEMENTATION_PATHS) == 6,
        "requiredPathCount": 6,
        "presentPaths": [path for path in IMPLEMENTATION_PATHS if path not in missing],
        "missingPaths": missing,
    }


def observed_selectors(root: Path) -> tuple[str, ...]:
    if len(IMPLEMENTATION_PATHS) < 5 or not (root / IMPLEMENTATION_PATHS[4]).is_file():
        return ()
    text = (root / IMPLEMENTATION_PATHS[4]).read_text(encoding="utf-8")
    return tuple(re.findall(r"\b(?:func|private\s+func)\s+(testV23P03C56(?:G|A|H|I|R)\d{2}\w*)\s*\(", text))


def _assert_exact_selectors(tests: str) -> tuple[str, ...]:
    selectors = tuple(re.findall(r"\b(?:func|private\s+func)\s+(testV23P03C56(?:G|A|H|I|R)\d{2}\w*)\s*\(", tests))
    if len(selectors) != 5 or tuple(selector[13:16] for selector in selectors) != SELECTOR_SUFFIXES:
        raise ValueError("C56 requires exactly five ordered G/A/H/I/R selectors")
    if len(set(selectors)) != 5:
        raise ValueError("C56 selectors must be unique")
    return selectors


def _fixture_text(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def _assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if not status["hydrated"]:
        raise ValueError("C56 exact six hydrated implementation paths unresolved")
    if status["missingPaths"]:
        raise ValueError("C56 source lanes missing:" + ",".join(status["missingPaths"]))

    source_text = "\n".join(_text(root, path) for path in IMPLEMENTATION_PATHS[:4])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    fixture = _json(root, IMPLEMENTATION_PATHS[5])
    fixture_text = _fixture_text(fixture)

    _require_tokens(
        source_text,
        CONTRACT_REFS[:3] + (
            "VoiceStructuringGrammarRegistryV1",
            "VoiceStructuredUnitV1",
            "VoiceStructuringResolutionV1",
        ),
        "C56 closed contract declarations",
    )
    _require_tokens(
        source_text,
        (
            "schemaVersion",
            "VoiceProposalContextV1",
            "AssistanceCapabilityReferenceV1",
            "AssistanceSourceReferenceV1",
            "transcriptSHA256",
            "proposalSHA256",
        ),
        "C56 assistance/context extension",
    )
    _require_tokens(
        source_text,
        (
            "VoiceTranscriptUTF8SpanV1",
            "sourceSpan",
            "VoiceStructuringLimitsV1.transcriptSHA256",
            "contentSHA256",
            "rawTranscriptSHA256",
        ),
        "C56 raw spans and source digest",
    )
    _require_tokens(
        source_text,
        (
            "VoiceStructuredProposalAuthenticatingV1",
            "validateDeterministicProposal",
            "rebuiltData",
            "proposalData",
            "VoiceStructuringCanonicalCodecV1",
        ),
        "C56 deterministic authenticator",
    )
    _require_tokens(
        source_text,
        (
            "VoiceUnmatchedClauseV1",
            "unmatchedClauses",
            "noExplicitGrammarMatch",
            "multipleExplicitGrammarMatches",
            "valueOutsideClosedGrammar",
            "rejectedByFieldValidation",
        ),
        "C56 unmatched topology",
    )
    _require_tokens(source_text, ("accept", "edit", "reject"), "C56 explicit field review")
    _require_one_of(
        source_text + fixture_text + tests,
        ("manual", "MANUAL"),
        "C56 manual fallback",
    )
    _require_tokens(source_text, ("VoiceStructuringServiceV1", "VoiceProposalReviewCoordinatorV1"), "C56 source owners")
    _require_tokens(
        source_text,
        (
            "VoiceStructuringNonpersistentLifecycleV1",
            "persistentFamilyCount = 0",
            "canonicalWritePermitted = false",
            "backupSearchReportJournalEnrollmentPermitted = false",
            "scratchDeletedAfterReviewExpiryOrCancellation = true",
            "reusesAssistanceContextAndLifecycleAuthority = true",
            "directAssistanceProposalPayloadPermitted = false",
        ),
        "C56 nonpersistent boundary",
    )
    _require_tokens(
        source_text,
        (
            "trustedSnapshot",
            "VoiceProposalTrustedSnapshotV1",
            "revalidate",
            "discardVoiceProposalScratch",
            "VoiceProposalTerminalBindingV1",
        ),
        "C56 callback and scratch ownership",
    )
    _require_tokens(
        source_text,
        (
            "VoiceProposalDraftCheckpointFrontierV1",
            "VoiceProposalDraftCheckpointUpdateV1",
            "VoiceProposalDraftCheckpointResultV1",
            "VoiceProposalDraftCheckpointBridgeV1",
            "expectedDraftRevision",
            "expectedBaseCanonicalRevision",
            "expectedCheckpointSHA256",
            "mutationID",
            "predecessor",
            "successor",
            "registeredCodec",
            "existingReviewedVoiceField",
            "applyReviewedVoiceField",
            "validateReviewedVoiceFieldApplication",
        ),
        "C56 C36 checkpoint CAS/codec bridge",
    )
    _require_patterns(
        source_text,
        (
            r"(?:maximumLifetime|lifetime)[^\n]{0,64}30\s*\*\s*60",
            r"expiresAt\s*=|expiresAt:",
            r"expectedDraftRevision\.addingReportingOverflow",
            r"mutation\.expectedRevision\s*==\s*update\.expectedDraftRevision",
            r"registeredCodec\s*==\s*update\.predecessor\.codec",
        ),
        "C56 bounded expiry and C36 CAS",
    )
    _require_tokens(
        source_text,
        (
            "VoiceProposalReviewCoordinatorFailureV1",
            "divergentProposalReplay",
            "divergentFieldReplay",
            "activeProposalLimitExceeded",
            "staleGeneration",
            "generationRevoked",
            "activeProposalLimitExceeded",
            "maximumTerminalEntries",
            "terminalOrder",
            "handleWorkspaceEraseOrReset",
            "cleanupInFlight",
        ),
        "C56 reset replay and cleanup",
    )
    _require_one_of(source_text, ("scratch", "Scratch", "SCRATCH"), "C56 scratch boundary")
    _require_one_of(source_text, ("delete", "discard", "cleanup", "DELETED"), "C56 scratch deletion")
    _require_tokens(source_text, QUALITY_STATES, "C56 quality states")
    _require_tokens(fixture_text, (CARD, *EVIDENCE_IDS, *QUALITY_STATES), "C56 fixture contract")
    selectors = _assert_exact_selectors(tests)
    _require_tokens(tests, EVIDENCE_IDS, "C56 evidence selector IDs")

    allowed_lower = source_text.lower() + fixture_text.lower()
    for field in ("note", "finding", "enum", "unit", "duration", "material", "quantity"):
        if field not in allowed_lower:
            raise ValueError(f"C56 allowed field missing:{field}")
    forbidden_alternatives = {
        "diagnosis": ("diagnosis",),
        "compliance": ("compliant", "noncompliant", "compliance"),
        "severity": ("severity",),
        "identity": ("asset id", "identity"),
        "placement": ("placement", "location"),
        "schedule": ("schedule",),
        "stock": ("stock",),
        "canonical command": ("canonical command", "canonical mutation"),
        "completion": ("complete", "completion"),
        "finalization": ("finalize", "finalization"),
    }
    for forbidden, alternatives in forbidden_alternatives.items():
        if not any(token in allowed_lower for token in alternatives):
            raise ValueError(f"C56 forbidden-inference declaration missing:{forbidden}")

    _require_tokens(
        source_text,
        ("capture/UI runtime", "audio runtime", "canonical writer"),
        "C56 P04-C45 capture/UI/runtime boundary",
    )
    # Capture, permissions, and audio runtime are a later P04-C45 surface;
    # this C56 lane must not introduce a network or generative fallback.
    if re.search(r"\b(?:URLSession|URLRequest|URLComponents|NWConnection|WebSocket|CloudKit|CKContainer|Alamofire)\b", source_text):
        raise ValueError("C56 network fallback symbols present")
    if re.search(r"\b(?:OpenAI|AppleIntelligence|GenerativeModel|LLM|remoteModel|downloadModel)\b", source_text, re.IGNORECASE):
        raise ValueError("C56 generative/download fallback symbols present")
    return selectors


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    return _assert_source_contracts(root)


def require_source_ready(root: Path) -> tuple[str, ...]:
    return _assert_source_contracts(root)


def assert_scaffold(root: Path) -> None:
    if len(EXISTING_PATHS) != EXPECTED_EXISTING_PATH_COUNT or len(IMPLEMENTATION_PATHS) != 6:
        raise ValueError(
            "C56 hydrated fence unresolved: expected 226 existing paths and six implementation paths"
        )
    if len(NEW_PATHS) != EXPECTED_NEW_PATH_COUNT or len(PATH_FENCE) != EXPECTED_FENCE_PATH_COUNT:
        raise ValueError("C56 fence cardinality differs")
    if len(set(PATH_FENCE)) != EXPECTED_FENCE_PATH_COUNT:
        raise ValueError("C56 fence contains duplicate paths")
    if NEW_PATHS != (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS):
        raise ValueError("C56 new-path ordering differs")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C56 fence contains Phase10/S10 path")
    if AUTHORIZED_OVERLAP_COUNT != 4810 or UNAUTHORIZED_OVERLAP_COUNT != 0:
        raise ValueError("C56 overlap authority differs")
    if not _authority_pins_ready():
        raise ValueError("C56 coordination/dossier pins unresolved")
    if any(not _base_exists(root, path) for path in EXISTING_PATHS):
        raise ValueError("C56 inherited fence path absent from base")
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C56 new path already exists at base")


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "dossierSHA256": DOSSIER_SHA256,
        "dossierByteCount": DOSSIER_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "registerOrdinal": REGISTER_ORDINAL,
        "directPrerequisiteCards": ["V23-P03-C32"],
        "contractProviderCards": ["V23-P03-C32", "V23-P03-C36"],
        "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT,
        "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
    }


def _common() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "title": TITLE,
        "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "statusFlags": FLAGS,
        "provisional": not FINAL_HASHES_SEALED,
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


def semantics(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "contractRefs": list(CONTRACT_REFS),
        "journeyRefs": ["FJ14"],
        "grammar": "VERSIONED_CLOSED_DETERMINISTIC_ON_DEVICE",
        "closedGrammarRegistry": {
            "type": "VoiceStructuringGrammarRegistryV1",
            "exactRegisteredReleaseTupleRequired": True,
            "callerGrammarInjectionPermitted": False,
            "maximumGrammarReleases": 32,
        },
        "canonicalUnits": {
            "type": "VoiceStructuredUnitV1",
            "closed": True,
            "codes": list(CANONICAL_UNITS),
        },
        "allowedProposalFields": list(ALLOWED_PROPOSAL_FIELDS),
        "qualityStates": list(QUALITY_STATES),
        "sourceSpansRequired": True,
        "rawSpanEncoding": "UTF8_START_LENGTH_BOUND_TO_TRANSCRIPT",
        "transcriptSourceDigest": "SHA256_RAW_UTF8_BOUND_TO_CONTEXT_SOURCE",
        "unmatchedClauseTopology": {
            "type": "VoiceUnmatchedClauseV1",
            "requiredForUnmatchedInput": True,
            "sortedByUTF8SpanAndOccurrenceID": True,
            "reasons": list(UNMATCHED_CLAUSE_REASONS),
        },
        "deterministicAuthenticator": {
            "protocol": "VoiceStructuredProposalAuthenticatingV1",
            "rebuildAndCanonicalCompare": True,
            "proposalDigestCompare": True,
            "rawTranscriptSourceDigestCompare": True,
        },
        "ambiguityIsManualOnly": True,
        "targetFixedAtCapture": True,
        "everyFieldUnverifiedUntilIndividuallyAcceptedOrEdited": True,
        "unsupportedCapabilityManualFallback": True,
        "speechConfidenceIsInformationalOnly": True,
        "maximumProposalLifetimeSeconds": PROPOSAL_LIFETIME_SECONDS,
        "captureUIRuntimeOwnership": "V23-P04-C45",
        "c56OwnsCaptureUIRuntime": False,
        "p04C45OwnsCaptureUIRuntime": True,
        "audioScratchOnlyAndDeleted": True,
        "forbiddenInferences": list(FORBIDDEN_INFERENCES),
        "noCanonicalCommandOrAutomaticMutation": True,
        "noCloudOrGenerativeFallback": True,
        "lifecycleCoverage": list(LIFECYCLE_DIMENSIONS),
        "acceptedFieldUsesExistingC36DraftWriter": True,
        "c36CheckpointCASCodecProof": {
            "frontierReadBeforeEachReview": True,
            "expectedDraftRevision": True,
            "expectedBaseCanonicalRevision": True,
            "expectedCheckpointSHA256": True,
            "mutationID": True,
            "predecessorAndSuccessorReadBack": True,
            "registeredCodecRequired": True,
            "overflowRejected": True,
            "receiptValidated": True,
            "singleExistingC36WriterBoundary": True,
        },
        "resetReplayCleanup": {
            "workspaceEraseReset": True,
            "generationRevocation": True,
            "proposalReplayDigestBound": True,
            "fieldReplayDigestBound": True,
            "activeProposalCap": 128,
            "terminalReplayCap": 256,
            "sequentialScratchCleanup": True,
        },
        "nonpersistentLifecycle": {
            "durableFamilyCount": 0,
            "canonicalWritePermitted": False,
            "backupSearchReportJournalEnrollmentPermitted": False,
            "scratchDeletedAfterReviewExpiryOrCancellation": True,
            "directAssistanceProposalPayloadPermitted": False,
        },
        "selectors": list(selectors),
        "prohibitedP04C45Ownership": list(P04_C45_CAPTURE_UI_RUNTIME_OWNERSHIP),
    }


def schema_document(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "$id": "https://assetrounds.invalid/v23/structured-voice-proposal.schema.json",
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "title": TITLE,
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P03C56StructuredVoiceProposalCorpusV1"},
            "schemaVersion": {"const": 1},
            "cardID": {"const": CARD},
            "contractRefs": {"const": list(CONTRACT_REFS)},
            "journeyRefs": {"const": ["FJ14"]},
            "evidenceIDs": {"const": list(EVIDENCE_IDS)},
            "selectors": {"const": list(selectors)},
            "qualityStates": {"const": list(QUALITY_STATES)},
            "allowedProposalFields": {"const": list(ALLOWED_PROPOSAL_FIELDS)},
            "forbiddenInferences": {"const": list(FORBIDDEN_INFERENCES)},
            "maximumProposalLifetimeSeconds": {"const": PROPOSAL_LIFETIME_SECONDS},
            "captureUIRuntimeOwnership": {"const": "V23-P04-C45"},
            "c56OwnsCaptureUIRuntime": {"const": False},
            "p04C45OwnsCaptureUIRuntime": {"const": True},
            "persistence": {"const": PERSISTENCE},
            "statusFlags": {"type": "object", "additionalProperties": {"const": False}},
            "provisional": {"const": not FINAL_HASHES_SEALED},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED},
        },
        "required": [
            "schema", "schemaVersion", "cardID", "contractRefs", "journeyRefs",
            "evidenceIDs", "selectors", "qualityStates", "allowedProposalFields",
            "forbiddenInferences", "maximumProposalLifetimeSeconds", "captureUIRuntimeOwnership",
            "c56OwnsCaptureUIRuntime", "p04C45OwnsCaptureUIRuntime", "persistence", "statusFlags",
            "provisional", "finalHashesSealed",
        ],
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    if not FINAL_HASHES_SEALED:
        return {**value, "artifactDigest": None}
    return {**value, "artifactDigest": sha256_bytes(pretty(value))}


def _source_projection(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {
        "implementationPaths": list(IMPLEMENTATION_PATHS),
        "presentPaths": status["presentPaths"],
        "missingPaths": status["missingPaths"],
        "selectors": list(selectors),
        "sourceSemanticsInspected": bool(status["hydrated"] and not status["missingPaths"]),
    }


def contract_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C56StructuredVoiceProposalContractV1",
        "schemaVersion": 1,
        **_common(),
        "contractRefs": list(CONTRACT_REFS),
        "journeyRefs": ["FJ14"],
        "directPrerequisites": ["V23-P03-C32"],
        "contractProviders": ["V23-P03-C32", "V23-P03-C36"],
        "semantics": semantics(selectors),
        "persistence": PERSISTENCE,
        "sourceProjection": _source_projection(root, selectors),
    })


def evidence_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "focus": ["exact grammar", "bounded fields", "source spans", "C36 draft checkpoint handoff"]},
        {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "focus": ["locale", "number/unit", "duration", "manual fallback"]},
        {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "focus": ["ambiguity", "unsupported capability", "forbidden inference", "stale target"]},
        {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "focus": ["cancel callback", "process kill", "scratch cleanup", "P04-C45 audio route boundary"]},
        {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "focus": ["expiry", "relaunch", "Erase", "C36 checkpoint and writer recovery"]},
    ]
    return _sealed({
        "schema": "V23P03C56StructuredVoiceProposalEvidenceReceiptV1",
        "schemaVersion": 1,
        **_common(),
        "cases": cases,
        "testSelectors": list(selectors),
        "journey": "FJ14",
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "sourceProjection": _source_projection(root, selectors),
    })


def brand_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C56BrandImpactManifestV1",
        "schemaVersion": 1,
        **_common(),
        "uiSurfaceDelta": False,
        "brandSurfaceDelta": False,
        "iPhoneNativeOnly": True,
        "nativeIPadSurface": False,
        "onDeviceRecognitionOnly": True,
        "microphoneAudioRetention": False,
        "networkOrTelemetryFlow": False,
        "generativeModelOrCloudFallback": False,
        "automaticCanonicalMutation": False,
        "customerIdentityVerified": False,
        "deliveryOrLegalSignatureClaimed": False,
        "captureUIRuntimeOwnership": "V23-P04-C45",
        "c56OwnsCaptureUIRuntime": False,
        "p04C45OwnsCaptureUIRuntime": True,
        "prohibitedP04C45Ownership": list(P04_C45_CAPTURE_UI_RUNTIME_OWNERSHIP),
        "sourceProjection": _source_projection(root, selectors),
    })


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    data = rendered[path] if path in rendered else (root / path).read_bytes()
    return {
        "path": path,
        "byteCount": len(data),
        "sha256": sha256_bytes(data),
        "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE",
    }


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    selectors = require_source_ready(root)
    if not FINAL_HASHES_SEALED:
        raise ValueError("C56 final sealing held until source/test lanes are stable")
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: pretty(schema_document(selectors)),
        CONTRACT_PATH: pretty(contract_document(root, selectors)),
        EVIDENCE_PATH: pretty(evidence_document(root, selectors)),
        BRAND_PATH: pretty(brand_document(root, selectors)),
    }
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "schema": "V23P03C56ToolingManifestV1",
        "schemaVersion": 1,
        **_common(),
        "pathFence": list(PATH_FENCE),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW_PATHS),
        "toolingEditPaths": list(TOOLING_EDIT_PATHS),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "fencePathCount": len(PATH_FENCE),
        "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED",
        "files": rows,
        "artifactSetDigest": sha256_bytes(canonical(rows)),
        "sourceProjection": _source_projection(root, selectors),
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def _self_parse() -> None:
    for path in SCRIPT_PATHS:
        source_path = Path(__file__).with_name(Path(path).name)
        if source_path.is_file():
            ast.parse(source_path.read_text(encoding="utf-8"), filename=path)


if __name__ == "__main__":
    _self_parse()
    print(json.dumps({
        "cardID": CARD,
        "sourceReady": False,
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "fencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "newPathCount": EXPECTED_NEW_PATH_COUNT,
    }, sort_keys=True))
