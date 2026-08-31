#!/usr/bin/env python3
"""Fail-closed static tooling for V23-P04-C02 Evidence Curation.

The Swift implementation and fixture rows are intentionally read-only inputs
to this lane.  The projections below keep the C02 boundary explicit: reviewed
evidence metadata and reversible derivatives may be persisted through the
incumbent metadata writer, while immutable originals, privacy redaction, and
report/audience authority remain owned by their existing providers.
"""
from __future__ import annotations

import ast
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
CARD = "V23-P04-C02"
TITLE = "Evidence selection, readable evidence-detail preview, comparison, reversible markup, and bounded sequence"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 90

# Hydration authority is an exact immutable object.  The coordination files
# are re-read on every process so a stale local projection fails closed.
BASE_HEAD = "6ecacf0b00a4a10c5591a41af360209475eb6545"
BASE_TREE = "90e8b905cc5270b931b562fc24b6e83f85ce33c6"
CANDIDATE_HEAD = BASE_HEAD
CANDIDATE_TREE = BASE_TREE
COORDINATION_HEAD = "64111b635de27d52ed8442508bed9f1c68c43ecd"
COORDINATION_TREE = "610fcd5677844011add15eb207e0ff1afdf4f116"
COORDINATION_ORIGIN_HEAD = COORDINATION_HEAD
COORDINATION_CAS_SEQUENCE = 394
HYDRATION_REVISION = 3
CONTEXT_DIGEST = "69b4a6c0aa7c6a30431d28dddc4542d4178bed5f5ba2a5fc36b8925fb7f14f89"
FENCE_DIGEST = "d978809591e63a7e74235a7e1029d546286aadc0bccdeed8bfb4ce2bb38d5768"
PREREQUISITE_DIGEST = "91d4406f39d6c4d6c39b1ff954c02e37c704374a6ca0c8146a5685c28e8d3ef6"
DEPENDENCY_CORRECTION_DIGEST = "d9b2d1467db9b319962f13a3f93887833b9448e4e5474e0554eb64e6c4685868"
HYDRATION_TRANSITION_DIGEST = "7cba14c59073c56e8928fd2a40d289af4f7b040e89beec6a2b458e6d69491489"
COORDINATION_LEDGER_DIGEST = "98324dee6c224fcce3fa2b81b6db4feb2da9846c810b972a63ffe904a6f24af9"
COORDINATION_PROJECTION_DIGEST = "4ac8cc51743528255fa8e12615b8f4cdd97041d1085b6b9c19035dd6e973d522"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

DOSSIER_SHA256 = "4b8a72b012c813ef5a4c302fdb9114805c396098491f73b857dbcc7dc46a07c1"
DOSSIER_BYTES = 7470
INHERITED_V21_BLOCK_SHA256 = "406387e5f3991e5b89a68ac573163ea123b33fa2f2c107f9d212909519281b17"
INHERITED_V21_BLOCK_BYTES = 10858
REGISTER_ROW_SHA256 = "d5ee6c271caa2ce34b8a891d32bf2a072231d7e298ce724fe5a4ae086bcac11c"
REGISTER_ROW_BYTES = 309
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217
REGISTER_ROW = (
    "| 90 | <a id=\"v23-p04-c02-register\"></a>[`V23-P04-C02`]"
    "(EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p04-c02) | Evidence selection, readable evidence-detail preview, comparison, reversible markup, and bounded sequence | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C24`, `V23-P04-C01` | `REFINED_WITHOUT_LOSS` |"
)

EXPECTED_EXISTING_PATH_COUNT = 243
EXPECTED_NEW_PATH_COUNT = 15
EXPECTED_FENCE_PATH_COUNT = 258
AUTHORIZED_OVERLAP_COUNT = 5279
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
PRIOR_FENCE_COUNT = 90
PRIOR_OWNED_PATH_COUNT = 1428
S10_RESERVED_PATH_COUNT = 86

IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Evidence/EvidenceCurationContractsV1.swift",
    "FieldEvidenceApp/Application/Evidence/EvidenceCurationCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Media/EvidenceDerivativeServiceV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/EvidenceCurationView.swift",
    "FieldEvidenceAppTests/V9_67EvidenceCurationTests.swift",
    "FieldEvidenceAppUITests/V23_P04_C02EvidenceCurationUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/EvidenceCuration/V22P04C02EvidenceCurationCorpusV1.json",
)
SCHEMA_PATH = "Scripts/v23/evidence-curation.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P04C02EvidenceCurationContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P04C02EvidenceCurationEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P04C02BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P04-C02-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p04_c02_contracts.py",
    "Scripts/v23/generate_p04_c02_contracts.py",
    "Scripts/v23/verify_p04_c02_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOLING_EDIT_PATHS = (*SCRIPT_PATHS, *GENERATED_PATHS)
# Exported for the verifier and for downstream static consumers.
OUTPUT_PATHS = GENERATED_PATHS
NEW_PATHS = (*IMPLEMENTATION_PATHS, *TOOLING_EDIT_PATHS)

_CONTEXT_RELATIVE = "contexts/V23-P04-C02-attempt-1/BootstrapCardContextV1.json"
_FENCE_RELATIVE = "contexts/V23-P04-C02-attempt-1/BootstrapPathFenceV1.json"
_TRANSITION_RELATIVE = "transitions/000394-V23-P04-C02-attempt-1-HYDRATING-to-HYDRATING-accepted-dependency-rebind.json"
_CORRECTION_RELATIVE = "receipts/V23-P04-C02-accepted-dependency-correction-C05-attempt-3-v3.json"
_LEDGER_RELATIVE = "state/BootstrapExecutionLedgerEnvelopeV1.json"
_PROJECTION_RELATIVE = "projections/ActiveWorkSetProjectionV1.json"

EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
EVIDENCE_ROLES = ("CONTEXT", "DETAIL", "BEFORE", "AFTER", "OTHER")
DIRECT_PREREQUISITES = ("V23-P03-C24", "V23-P04-C01")
JOURNEY_REFS = ("FJ15",)
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P04-C02).CONTRACTS",
    "EvidenceDetailCardProfileV1",
    "EvidenceDetailCardRenderReceiptV1",
    "FinalAudiencePrivacyConfirmationV1",
    "CompletedActivitySnapshotV1",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)
AGGREGATE_MEMBERSHIPS = (
    "AutonomousRequiredAcceptedSetV1", "P04ShippingSurfaceSetV1", "P04BrandClosureSetV1",
)
CONFORMANCE_SUBJECTS = ("P04ShippingSurfaceSetV1", "FJ15")
INVALIDATION_CONSUMERS = (
    "V23-P04-C03", "V23-P04-C10", "V23-P04-C11", "V23-P04-C20", "V23-P04-C25",
    "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR",
)
LIFECYCLE_COVERAGE = (
    "SCHEMA_VERSION", "WRITER_QUERY", "MIGRATION", "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK", "IMPORT_EXPORT", "JOURNAL_REPLAY", "SEARCH_REBUILD",
    "REPORT_PROJECTION", "DELETE_ERASE", "RETENTION", "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX", "INTERRUPTION", "IDEMPOTENT_RECEIPTS",
)
PERSISTENT_CHANGE_MODE = "CONTENT_ONLY_DERIVATIVES_EXISTING_METADATA_ASSOCIATIONS"
PERSISTENT_CONTRACT_SCHEMA = "EXISTING_EVIDENCE_METADATA_ASSOCIATION_SCHEMA"
PERSISTENT_ROW_TYPES = ("EvidenceAssociationV1", "ContentDerivativeProvenanceV1", "REVIEWED_EVIDENCE_METADATA_ASSOCIATION")
NONPERSISTENT_TYPES = (
    "EvidenceCurationSelectionV1", "EvidenceVersionPinnedPreviewV1", "EvidenceComparisonProjectionV1",
    "EvidenceReviewedMarkupPlanV1", "EvidenceSequencePlanV1", "EvidenceCurationOperationReceiptV1",
    "COMPARISON_OVERLAY", "PROCESSING_PROGRESS", "PRESENTATION_CLOCK", "CONTACT_SHEET_PREVIEW",
)
FLAGS = {name: False for name in (
    "activation", "native", "hosted", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalEvidence",
    "phase10PollingDuringParallelExecution",
)}

# Flip only after every C02 source/test/fixture row and all inherited inputs
# are stable.  Final authority has now reported the source set stable.
FINAL_HASHES_SEALED = True

# C02 may consume the accepted C05 correction only through its sealed
# dependency receipt.  These pins are deliberately separate from the C02
# hydration pins: C05 owns canonical metadata persistence and its writer
# receipt, while C02 owns only the review/derivative boundary.
ACCEPTED_C05_PROVIDER = {
    "cardID": "V23-P03-C05",
    "attemptID": 3,
    "candidateHead": "6ecacf0b00a4a10c5591a41af360209475eb6545",
    "candidateTree": "90e8b905cc5270b931b562fc24b6e83f85ce33c6",
    "checkpointDigest": "a8cf15ae39d602b5bdf51b34c616ab963d27dfb639032d90bcbf551da589998f",
    "verificationReceiptDigest": "4242cbf7a081977fbba91011c32567c2bd187a684800e7ff5a9119dcc6109bf2",
    "contextDigest": "148ea188dd2add6ea8bcce6cf2caa0e01dd1a6d10d5395cf552ff1bb3775fc44",
    "pathFenceDigest": "8ca993b5f491de9520c1b38a25f1c0021fcc84ec10f9f4c8b37ad183f7942524",
    "role": "ACCEPTED_DEPENDENCY_CORRECTION_PROVIDER",
}

C05_PERSISTENT_SCHEMA_VERSION = 43
C05_RECORDS_SCHEMA_VERSION = 42
C05_DURABLE_MODEL_COUNT = 2
C05_ACTIVE_MODEL_COUNT = 144
C05_DURABLE_ROWS = (
    "EvidenceAssociationEventRowV1",
    "EvidenceSequenceRevisionRowV1",
)
C05_DURABLE_FAMILIES = (
    "EVIDENCE_ASSOCIATION_EVENT",
    "EVIDENCE_SEQUENCE_REVISION",
)
C05_PERSISTENT_CONTRACT_SCHEMA = "EVIDENCE_METADATA_V1_V43_RECORDS42"
C05_PERSISTENCE_MODE = "PERSISTENT_CANONICAL_EVIDENCE_METADATA_AND_SUCCESSOR_SEQUENCE"
C05_BACKUP_RESTORE = "CANONICAL_V4_RECORDS42_FULL_REPLACE_RESTORE"
C05_JOURNAL_REPLAY = "MUTATION_RECEIPT_AND_SUCCESSOR_REPLAY"
C05_SEARCH_REPORT = "DERIVED_ONLY_REBUILT_FROM_CANONICAL_ROWS"
C05_DELETE_ERASE = "APPEND_ONLY_HISTORY_UNTIL_WORKSPACE_ERASE"
C02_DERIVATIVE_BYTE_MODE = "CONTENT_ONLY"
C02_PLAN_PROJECTION_PERSISTENCE = "NONPERSISTENT"
C02_LIFECYCLE = (
    ("persistence", "CONTENT_ONLY"),
    ("plansAndProjectionsAreNonpersistent", True),
    ("schema", "INCUMBENT_CONTENT_AUTHORITY_AND_C05_V43_METADATA"),
    ("migration", "C05_METADATA_AUTHORITY"),
    ("backupRestore", "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"),
    ("cloneFork", "INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"),
    ("journalReplay", "C05_METADATA_WRITER_REPLAY_AND_DETERMINISTIC_REPROJECTION"),
    ("searchRebuild", "NOT_APPLICABLE"),
    ("deleteErase", "REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES"),
    ("exportReport", "REQUIRED_VIA_INCUMBENT_CONTENT_C05_METADATA_AND_REPORT_AUTHORITIES"),
    ("comparisonIsProof", False),
    ("createsContentStore", False),
)

_PROVIDER_ARTIFACTS = {
    "V23-P03-C05": {
        "required": True,
        "facet": "EVIDENCE_METADATA_CANONICAL_WRITER_AND_RECEIPT",
        "pathFenceDigest": ACCEPTED_C05_PROVIDER["pathFenceDigest"],
        "candidateHead": ACCEPTED_C05_PROVIDER["candidateHead"],
        "candidateTree": ACCEPTED_C05_PROVIDER["candidateTree"],
        "checkpointDigest": ACCEPTED_C05_PROVIDER["checkpointDigest"],
        "contextDigest": ACCEPTED_C05_PROVIDER["contextDigest"],
        "verificationReceiptDigest": ACCEPTED_C05_PROVIDER["verificationReceiptDigest"],
        "contracts": (
            "EvidenceMetadataPersistenceEnrollmentV1",
            "EvidenceAssociationEventRowV1",
            "EvidenceSequenceRevisionRowV1",
            "EvidenceMetadataMutationV1",
            "EvidenceMetadataMutationReceiptV1",
        ),
        "paths": (
            "FieldEvidenceApp/Domain/Models/EvidenceMetadataPersistenceModelsV1.swift",
            "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
            "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
            "Scripts/v23/p03_c05_contracts.py",
            "Scripts/v23/generate_p03_c05_contracts.py",
            "Scripts/v23/verify_p03_c05_contracts.py",
            "Scripts/v23/content-reference.schema.json",
            "Scripts/v23/content-locator.schema.json",
            "Scripts/v23/content-manifest.schema.json",
            "Scripts/v23/evidence-association.schema.json",
            "Scripts/v23/content-derivative-provenance.schema.json",
            "Scripts/v23/content-evidence-receipt.schema.json",
            "docs/design/v23/tooling/V23P03C05ContentReferenceContractV1.json",
            "docs/design/v23/tooling/V23P03C05ContentLocatorManifestContractV1.json",
            "docs/design/v23/tooling/V23P03C05EvidenceAssociationContractV1.json",
            "docs/design/v23/tooling/V23P03C05DerivativeProvenanceContractV1.json",
            "docs/design/v23/tooling/V23P03C05ContentEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23-P03-C05-tooling-manifest.json",
        ),
    },
    "V23-P03-C24": {
        "required": True,
        "pathFenceDigest": "08bd1b6091d22d234eaa18beac3d99d29540a3bdf00c4f91e01f5265f1d9346a",
        "candidateHead": "d0c7c8a48e235e783627495ccba6b0e168e9b34e",
        "candidateTree": "9f759030a7154c38ade62ce9a3273f4b33ebf18d",
        "checkpointDigest": "df8810b379eb79164d7ee67c00044951a2552cf46643c333063cdba159f0325e",
        "contextDigest": "496ad67ebdeac22bd55a7675048ae54a1a297a3f83f401a5971eccc8e12d33ba",
        "verificationReceiptDigest": "b0903dfa37fefa29f61cb304d5119d41805e19f4b4c741a164c8e7834ab00b5f",
        "contracts": (
            "AccessibleDocumentSemanticTreeV1", "AccessibleDocumentAssessmentReceiptV1",
            "AccessibleDocumentPublicationBindingV1", "AccessibleDocumentNodeV1",
            "AccessibleDocumentCoordinatorV1",
        ),
        "paths": (
            "Scripts/v23/p03_c24_contracts.py", "Scripts/v23/generate_p03_c24_contracts.py",
            "Scripts/v23/verify_p03_c24_contracts.py", "Scripts/v23/accessible-document.schema.json",
            "docs/design/v23/tooling/V23P03C24AccessibleDocumentContractV1.json",
            "docs/design/v23/tooling/V23P03C24AccessibleDocumentEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23P03C24BrandImpactManifestV1.json",
            "docs/design/v23/tooling/V23-P03-C24-tooling-manifest.json",
        ),
    },
    "V23-P04-C01": {
        "required": True,
        "pathFenceDigest": "f59c7d2d98907aed26492f3a06d6de52ce1436790ddfda9da157689346d0a706",
        "candidateHead": "c5078bb34e04869121c55081c7e3da1ca4728936",
        "candidateTree": "5795a04e18cbb1ae9741700ee9f316a92ffadba1",
        "checkpointDigest": "778d726cb3893cfdc80e1f8c2f2769c9649e0d57d62e802d2f7c2c675fdd982a",
        "contextDigest": "e032c21cd95df0074537a163bb3c57fd280dbaed0e375efa612673357d069425",
        "verificationReceiptDigest": "e22dc14b2130fd7780a6e105715bde2bc3806eac6f2412c6422baf0da901753c",
        "contracts": ("RecoveryCenterProjectionV1", "RecoverabilityVerificationReceiptV1"),
        "paths": (
            "Scripts/v23/p04_c01_contracts.py", "Scripts/v23/generate_p04_c01_contracts.py",
            "Scripts/v23/verify_p04_c01_contracts.py", "Scripts/v23/recovery-center.schema.json",
            "docs/design/v23/tooling/V23P04C01RecoveryCenterContractV1.json",
            "docs/design/v23/tooling/V23P04C01RecoveryCenterEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23P04C01BrandImpactManifestV1.json",
            "docs/design/v23/tooling/V23-P04-C01-tooling-manifest.json",
        ),
    },
    "V23-P03-C06": {
        "required": True,
        "facet": "EVIDENCE_DETAIL_AUTHORITY",
        "pathFenceDigest": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2",
        "candidateHead": "8dcf404725f5b1f9ab630d2f16e445013efec036",
        "candidateTree": "ba11541ee75791a70012c4daadcac003207483ed",
        "checkpointDigest": "481fb8e84af1e3b47dfcf8717449ea0e2e91ff30f3335e8cca9a2d662031fe40",
        "contextDigest": "1058e2792a104f74af0a43844467482a7abb29a99da129c8e0be92b6ea0f922d",
        "verificationReceiptDigest": "57d9dec65fa7e75f5408763d6d10c5f94022489560881d71c6787bcf3e0e4383",
        "contracts": (
            "EvidenceDetailCardProfileV1", "EvidenceDetailCardRenderReceiptV1",
            "FinalAudiencePrivacyConfirmationV1", "CompletedActivitySnapshotV1",
        ),
        "paths": (
            "Scripts/v23/p03_c06_contracts.py", "Scripts/v23/generate_p03_c06_contracts.py",
            "Scripts/v23/verify_p03_c06_contracts.py",
            "Scripts/v23/completed-activity-snapshot.schema.json",
            "Scripts/v23/evidence-detail-card-profile.schema.json",
            "Scripts/v23/evidence-detail-card-render-receipt.schema.json",
            "Scripts/v23/final-audience-privacy-confirmation.schema.json",
            "Scripts/v23/contract-manifest.schema.json",
            "Scripts/v23/report-projection-evidence.schema.json",
            "docs/design/v23/tooling/V23P03C06CompletedSnapshotContractV1.json",
            "docs/design/v23/tooling/V23P03C06EvidenceDetailCardContractV1.json",
            "docs/design/v23/tooling/V23P03C06ContractManifestV1.json",
            "docs/design/v23/tooling/V23P03C06ProjectionContractV1.json",
            "docs/design/v23/tooling/V23P03C06ProjectionEvidenceReceiptV1.json",
            "docs/design/v23/tooling/V23-P03-C06-tooling-manifest.json",
        ),
    },
}


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


_CANONICAL_TEXT_SUFFIXES = frozenset({
    ".csv", ".entitlements", ".json", ".md", ".pbxproj", ".plist", ".ps1",
    ".py", ".sh", ".strings", ".swift", ".toml", ".txt", ".xcstrings",
    ".xcscheme", ".yaml", ".yml",
})


def canonical_file_bytes(path: Path) -> bytes:
    """Return checkout-independent bytes for evidence hashing.

    Git may materialize repository text with CRLF on Windows even though the
    canonical blob uses LF. Evidence hashes bind the textual artifact, not a
    checkout's line-ending policy. Binary artifacts remain byte-exact.
    """
    data = path.read_bytes()
    if path.suffix.lower() in _CANONICAL_TEXT_SUFFIXES:
        return data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return data


def _valid_sha(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def _coordination_root() -> Path:
    candidates = (Path(r"C:\AssetRounds-v23-coordination"), ROOT.parent / "AssetRounds-v23-coordination")
    for candidate in candidates:
        if (candidate / _FENCE_RELATIVE).is_file():
            return candidate
    raise ValueError("C02 coordination fence is unavailable")


def _coordination_json(relative: str) -> dict[str, Any]:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ValueError("C02 coordination input is unavailable:" + relative)
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("C02 coordination object required:" + relative)
    return value


def _sealed_field(value: dict[str, Any], field: str) -> str:
    unsigned = {key: item for key, item in value.items() if key != field}
    return sha256_bytes((json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8"))


def _load_hydrated_paths() -> tuple[tuple[str, ...], tuple[str, ...]]:
    context = _coordination_json(_CONTEXT_RELATIVE)
    fence = _coordination_json(_FENCE_RELATIVE)
    if context.get("cardID") != CARD or context.get("contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C02 context digest/card mismatch")
    if fence.get("cardID") != CARD or fence.get("fenceDigest") != FENCE_DIGEST:
        raise ValueError("C02 path fence digest/card mismatch")
    if _sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ValueError("C02 context seal differs")
    if _sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ValueError("C02 fence seal differs")
    existing = tuple(fence.get("existingPaths", ()))
    hydrated_new = tuple(fence.get("newPaths", ()))
    allowed = tuple(fence.get("allowedCreateOrReplacePaths", ()))
    if len(existing) != EXPECTED_EXISTING_PATH_COUNT or len(set(existing)) != len(existing):
        raise ValueError("C02 existing path fence cardinality differs")
    expected_allowed = (*existing[:-1], *hydrated_new, existing[-1])
    if hydrated_new != NEW_PATHS or allowed != expected_allowed:
        raise ValueError("C02 hydrated new-path ordering differs")
    if tuple(context.get("existingPaths", ())) != existing or tuple(context.get("newPaths", ())) != hydrated_new:
        raise ValueError("C02 context/fence path sets differ")
    if context.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST:
        raise ValueError("C02 context prerequisite digest differs")
    if tuple(context.get("directPrerequisites", ())) != DIRECT_PREREQUISITES:
        raise ValueError("C02 direct prerequisites differ")
    reserved = tuple(fence.get("activeS10ReservedPaths", ()))
    if fence.get("frozenS10ReservationDigest") != FROZEN_S10_RESERVATION_DIGEST or len(reserved) != S10_RESERVED_PATH_COUNT or set(existing + hydrated_new) & set(reserved):
        raise ValueError("C02 S10 reservation or overlap differs")
    return existing, hydrated_new


EXISTING_PATHS, _HYDRATED_NEW_PATHS = _load_hydrated_paths()
# The corrected C05 provider path was appended to the inherited existing list,
# while the coordination allowed-path order keeps C02's fifteen new paths
# before that appended provider model.  PATH_FENCE mirrors that authoritative
# create/replace order.
PATH_FENCE = (*EXISTING_PATHS[:-1], *NEW_PATHS, EXISTING_PATHS[-1])
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_text(root, relative), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + relative)
    return value


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    lower = text.lower()
    missing = [token for token in tokens if token.lower() not in lower]
    if missing:
        raise ValueError(label + " missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I | re.S) is None]
    if missing:
        raise ValueError(label + " missing patterns:" + ",".join(missing))


def _git(root: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


_BASE_PATH_CACHE: frozenset[str] | None = None


def _base_exists(root: Path, relative: str) -> bool:
    global _BASE_PATH_CACHE
    if _BASE_PATH_CACHE is None:
        listing = subprocess.run(["git", "ls-tree", "-r", "--name-only", BASE_HEAD], cwd=root, check=True, capture_output=True, text=True).stdout
        _BASE_PATH_CACHE = frozenset(line.strip().replace("\\", "/") for line in listing.splitlines() if line.strip())
    return relative in _BASE_PATH_CACHE


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed: set[str] = set()
    for command in (("diff", "--name-only", BASE_HEAD, "--"), ("diff", "--cached", "--name-only", "--"), ("ls-files", "--others", "--exclude-standard")):
        result = subprocess.run(["git", *command], cwd=root, check=True, capture_output=True, text=True)
        changed.update(line.strip().replace("\\", "/") for line in result.stdout.splitlines() if line.strip())
    return tuple(sorted(changed))


def _candidate_identity(root: Path) -> None:
    if _git(root, "show", "-s", "--format=%T", CANDIDATE_HEAD) != CANDIDATE_TREE:
        raise ValueError("C02 candidate tree differs from accepted base")
    observed_head = _git(root, "rev-parse", "HEAD")
    if observed_head != BASE_HEAD and not subprocess.run(["git", "merge-base", "--is-ancestor", BASE_HEAD, observed_head], cwd=root).returncode == 0:
        raise ValueError("C02 candidate is not a descendant of accepted base")


def _assert_coordination_state() -> None:
    coordination = _coordination_root()
    if _git(coordination, "rev-parse", "HEAD") != COORDINATION_HEAD or _git(coordination, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE:
        raise ValueError("C02 coordination HEAD/tree differs")
    origin = _git(coordination, "ls-remote", "origin", "refs/heads/main").split()
    if not origin or origin[0] != COORDINATION_ORIGIN_HEAD:
        raise ValueError("C02 coordination origin/main differs")
    context = _coordination_json(_CONTEXT_RELATIVE)
    providers = context.get("acceptedDependencyCorrectionProviders")
    if providers != [ACCEPTED_C05_PROVIDER]:
        raise ValueError("C02 accepted C05 dependency provider differs")
    if context.get("contextDigest") != CONTEXT_DIGEST or context.get("pathFenceDigest") != FENCE_DIGEST:
        raise ValueError("C02 current context bindings differ")
    correction = _coordination_json(_CORRECTION_RELATIVE)
    if correction.get("receiptDigest") != DEPENDENCY_CORRECTION_DIGEST or _sealed_field(correction, "receiptDigest") != DEPENDENCY_CORRECTION_DIGEST:
        raise ValueError("C02 dependency correction receipt seal differs")
    for key, expected in (
        ("cardID", CARD),
        ("attemptID", 1),
        ("hydrationRevision", HYDRATION_REVISION),
        ("contextDigest", CONTEXT_DIGEST),
        ("fenceDigest", FENCE_DIGEST),
        ("existingPathCount", EXPECTED_EXISTING_PATH_COUNT),
        ("newPathCount", EXPECTED_NEW_PATH_COUNT),
        ("allowedPathCount", EXPECTED_FENCE_PATH_COUNT),
        ("authorizedPriorFenceOverlapCount", AUTHORIZED_OVERLAP_COUNT),
        ("unauthorizedPriorFenceOverlapCount", UNAUTHORIZED_OVERLAP_COUNT),
        ("reservationOverlapCount", S10_RESERVATION_OVERLAP_COUNT),
        ("acceptedDependencyCorrectionProvider", ACCEPTED_C05_PROVIDER),
    ):
        if correction.get(key) != expected:
            raise ValueError("C02 dependency correction field differs:" + key)
    if any(correction.get(key) is not False for key in (
        "nativeCompileRan", "hostedDispatchEnabled", "releaseCredit", "acceptanceCredit",
    )):
        raise ValueError("C02 dependency correction claims activation")
    transition = _coordination_json(_TRANSITION_RELATIVE)
    if transition.get("sequence") != COORDINATION_CAS_SEQUENCE or transition.get("transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C02 hydration transition differs")
    if _sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ValueError("C02 hydration transition seal differs")
    if (
        transition.get("contextDigest") != CONTEXT_DIGEST
        or transition.get("pathFenceDigest") != FENCE_DIGEST
        or transition.get("provisionalPrerequisiteDigest") != PREREQUISITE_DIGEST
        or transition.get("correctionDigest") != DEPENDENCY_CORRECTION_DIGEST
        or transition.get("candidateHead") != ACCEPTED_C05_PROVIDER["candidateHead"]
        or transition.get("candidateTree") != ACCEPTED_C05_PROVIDER["candidateTree"]
    ):
        raise ValueError("C02 transition bindings differ")
    ledger = _coordination_json(_LEDGER_RELATIVE)
    projection = _coordination_json(_PROJECTION_RELATIVE)
    if ledger.get("casSequence") != COORDINATION_CAS_SEQUENCE or ledger.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST:
        raise ValueError("C02 ledger authority differs")
    if projection.get("ledgerDigest") != COORDINATION_LEDGER_DIGEST or projection.get("projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ValueError("C02 projection authority differs")
    if _sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST or _sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ValueError("C02 ledger/projection seals differ")


def _assert_design_slices(root: Path) -> None:
    blueprint = _text(root, "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md")
    plan = _text(root, "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md")
    start = blueprint.index('<a id="v23-p04-c02"></a>')
    end = blueprint.index('<a id="v23-p04-c03"></a>', start)
    dossier = blueprint[start:end].rstrip() + "\n"
    inherited_start = blueprint.index("    ### V21-P04-C02 —")
    inherited_end = blueprint.index("    ### V21-P04-C03 —", inherited_start)
    inherited = blueprint[inherited_start:inherited_end].rstrip() + "\n"
    row = next(line for line in plan.splitlines() if line.startswith("| 90 |")) + "\n"
    for label, value, expected_bytes, expected_sha in (
        ("dossier", dossier, DOSSIER_BYTES, DOSSIER_SHA256),
        ("inherited", inherited, INHERITED_V21_BLOCK_BYTES, INHERITED_V21_BLOCK_SHA256),
        ("register row", row, REGISTER_ROW_BYTES, REGISTER_ROW_SHA256),
    ):
        data = value.encode("utf-8")
        if (len(data), sha256_bytes(data)) != (expected_bytes, expected_sha):
            raise ValueError("C02 design slice differs:" + label)


def source_status(root: Path) -> dict[str, Any]:
    missing = [path for path in IMPLEMENTATION_PATHS if not (root / path).is_file()]
    present = [path for path in IMPLEMENTATION_PATHS if path not in missing]
    selectors = observed_selectors(root)
    return {
        "requiredPathCount": len(IMPLEMENTATION_PATHS), "presentPathCount": len(present),
        "missingPathCount": len(missing), "presentPaths": present, "missingPaths": missing,
        "selectors": list(selectors), "hydrated": not missing,
    }


def observed_selectors(root: Path) -> tuple[str, ...]:
    path = root / IMPLEMENTATION_PATHS[4]
    if not path.is_file():
        return ()
    text = path.read_text(encoding="utf-8")
    return tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C02(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", text))


def _assert_exact_selectors(tests: str) -> tuple[str, ...]:
    selectors = tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C02(?:G|A|H|I|R)\d{2}[A-Za-z0-9_]*)\s*\(", tests))
    if len(selectors) != 5 or tuple(selector[13:16] for selector in selectors) != SELECTOR_SUFFIXES or len(set(selectors)) != 5:
        raise ValueError("C02 requires exactly five ordered G/A/H/I/R selectors")
    return selectors


def _assert_provider_source_slices(root: Path) -> None:
    paths = (
        "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
        "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
        "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
        "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift",
    )
    available = "\n".join(_text(root, path) for path in paths if (root / path).is_file())
    _require_tokens(
        available,
        ("EvidenceDetailCardProfileV1", "EvidenceDetailCardRenderReceiptV1", "FinalAudiencePrivacyConfirmationV1", "CompletedActivitySnapshotV1"),
        "C06 evidence-detail provider source slices",
    )


def _assert_c24_c01_prerequisite_slices(root: Path) -> None:
    paths = (
        "FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift",
        "FieldEvidenceApp/Domain/Recovery/RecoveryCenterContractsV1.swift",
    )
    available = "\n".join(_text(root, path) for path in paths if (root / path).is_file())
    _require_tokens(available, ("AccessibleDocument", "RecoveryCenterProjectionV1"), "C24/C01 prerequisite source slices")


def _assert_existing_content_authority_slices(root: Path) -> None:
    paths = (
        "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
        "FieldEvidenceApp/Domain/Models/EvidenceMetadataPersistenceModelsV1.swift",
        "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
        "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift",
        "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
        "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
        "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift",
    )
    available = "\n".join(_text(root, path) for path in paths if (root / path).is_file())
    _require_tokens(
        available,
        (
            "WorkspaceWriterV1", "EvidenceMetadataMutationV1", "EvidenceMetadataMutationReceiptV1",
            "EvidenceMetadataPersistenceEnrollmentV1", "EvidenceAssociationV1", "ContentReferenceV1",
            "ContentDerivativeProvenanceV1", "EvidenceBundleStore",
        ),
        "existing content/metadata authority source slices",
    )


def _assert_c05_metadata_source_slices(root: Path) -> None:
    metadata = _text(root, "FieldEvidenceApp/Domain/Models/EvidenceMetadataPersistenceModelsV1.swift")
    writer = _text(root, "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift")
    receipt = _text(root, "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift")
    association = _text(root, "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift")
    _require_tokens(
        metadata,
        (
            "EvidenceMetadataPersistenceEnrollmentV1", "schemaVersion = 43", "recordsSchemaVersion = 42",
            "durableModelCount = 2", "totalSchemaModelCount = 144", "EVIDENCE_ASSOCIATION_EVENT",
            "EVIDENCE_SEQUENCE_REVISION", "EvidenceAssociationEventRowV1", "EvidenceSequenceRevisionRowV1",
            "canonicalData", "EvidenceMetadataCanonicalCodecV1", "func value()",
        ),
        "C05 metadata persistence source",
    )
    _require_tokens(
        writer,
        (
            "WorkspaceWriterV1", "func commitEvidenceMetadata", "EvidenceMetadataMutationReceiptV1",
            "persistedEvidenceMetadataEffectMatches", "evidenceMetadataReceipt", "journalStore",
            "receipt(mutationID:", "mutationReceipt",
        ),
        "C05 production WorkspaceWriter receipt source",
    )
    _require_tokens(
        receipt,
        (
            "extension EvidenceMetadataMutationV1", "mutationPostImages", "evidenceAssociationEvent",
            "evidenceSequenceRevision", "EvidenceMetadataMutationReceiptV1", "affectedIdentities",
            "concurrencyIdentities", "sorted",
        ),
        "C05 mutation receipt topology",
    )
    _require_tokens(
        association,
        (
            "EvidenceCurationPolicyV1", "EvidenceSequenceItemV1", "EvidenceRoleV1", "EvidenceReviewedCaptionV1",
            "EvidenceAccessibilityDescriptionV1", "role", "caption", "accessibilityDescription",
            "ordinal", "orderedItems", "sequenceID", "predecessor", "sequenceSHA256",
            "EvidenceMetadataCanonicalCodecV1", 'case context = "CONTEXT"', 'detail = "DETAIL"',
            'before = "BEFORE"', 'after = "AFTER"', 'other = "OTHER"',
        ),
        "C05 role/caption/order/accessibility/sequence source",
    )
    _require_patterns(
        association,
        (
            r"orderedItems\.map\(\\\.ordinal\)\s*==\s*Array\(0\.\.\<orderedItems\.count\)",
            r"orderedItems\.allSatisfy\(\{.*caption\.text.*maximumCaptionBytes.*accessibilityDescription",
            r"func\s+validateSuccessor\(of\s+prior",
            r"predecessor\s*==\s*\(try\s+prior\.reference\)",
            r"EvidenceMetadataCanonicalCodecV1\.sha256",
        ),
        "C05 exact metadata ordering and successor source",
    )


def _assert_fixture_contract(fixture: dict[str, Any]) -> None:
    if fixture.get("schema") != "V22P04C02EvidenceCurationCorpusV1" or fixture.get("schemaVersion") != 1:
        raise ValueError("C02 fixture schema identity differs")
    if fixture.get("cardID") != CARD or fixture.get("ordinal") != REGISTER_ORDINAL or fixture.get("contentMode") != "CONTENT_ONLY":
        raise ValueError("C02 fixture card/content identity differs")
    selectors = fixture.get("selectors")
    if not isinstance(selectors, list) or [item.get("id") for item in selectors if isinstance(item, dict)] != list(EVIDENCE_SUFFIXES):
        raise ValueError("C02 fixture selector order differs")
    for suffix, item in zip(EVIDENCE_SUFFIXES, selectors):
        if not isinstance(item, dict) or item.get("selector") != f"{CARD}-{suffix}" or item.get("tier") != {"G01": "GOLDEN", "A01": "ALTERNATE", "H01": "HOSTILE", "I01": "INTERRUPTION", "R01": "RECOVERY"}[suffix]:
            raise ValueError("C02 fixture selector row differs:" + suffix)
    limits = fixture.get("limits")
    expected_limits = {"maximumSelectionCount": 32, "maximumComparisonCount": 2, "maximumAnnotations": 64, "maximumAnnotationTextBytes": 1024, "maximumSequenceFrames": 16, "maximumContactSheetColumns": 4, "maximumSourceBytes": 1073741824, "maximumTotalSourceBytes": 2147483648}
    if limits != expected_limits:
        raise ValueError("C02 fixture limits differ")
    comparison = fixture.get("comparison")
    if not isinstance(comparison, dict) or comparison.get("modes") != ["SIDE_BY_SIDE", "ADVISORY_OVERLAY"] or comparison.get("comparisonIsProof") is not False or "not proof" not in str(comparison.get("advisoryText", "")).lower():
        raise ValueError("C02 fixture comparison boundary differs")
    privacy = fixture.get("privacy")
    if not isinstance(privacy, dict) or privacy.get("originalRole") != "IMMUTABLE_ORIGINAL" or privacy.get("derivativeRole") != "DERIVATIVE" or privacy.get("transformBeforeMarkup") is not True or privacy.get("confirmationRequiresExactBytes") is not True or privacy.get("detectorPass") != "PASS" or privacy.get("detectorBlock") != "BLOCKED":
        raise ValueError("C02 fixture privacy boundary differs")
    lifecycle = fixture.get("lifecycle")
    if lifecycle != dict(C02_LIFECYCLE):
        raise ValueError("C02 fixture lifecycle boundary differs")
    hostile = fixture.get("hostileCases")
    if not isinstance(hostile, list) or not {"wrong-workspace", "duplicate-reference", "privacy-before-markup", "markup-changes-source", "sequence-over-limit", "divergent-replay"}.issubset(hostile):
        raise ValueError("C02 fixture hostile cases incomplete")
    for key, expected in (
        ("c05MetadataPersistence", c05_metadata_persistence()),
        ("plansAndProjectionsPersistence", C02_PLAN_PROJECTION_PERSISTENCE),
        ("derivativeByteMode", C02_DERIVATIVE_BYTE_MODE),
        ("bundleDecoding", "EXACT_NO_ADDITIONAL_PROPERTIES"),
        ("binaryRendering", {"requiredMediaType": "image/png", "contactSheetBytesRequired": True, "jsonOnlyRenderingForbidden": True}),
    ):
        if key in fixture and fixture.get(key) != expected:
            raise ValueError("C02 fixture boundary differs:" + key)
    if fixture.get("uiAdoptionEnabled") is not False:
        raise ValueError("C02 fixture UI adoption is not disabled")


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    status = source_status(root)
    if status["missingPaths"]:
        raise ValueError("C02 source lanes missing:" + ",".join(status["missingPaths"]))
    contract = _text(root, IMPLEMENTATION_PATHS[0])
    coordinator = _text(root, IMPLEMENTATION_PATHS[1])
    derivative = _text(root, IMPLEMENTATION_PATHS[2])
    view = _text(root, IMPLEMENTATION_PATHS[3])
    tests = _text(root, IMPLEMENTATION_PATHS[4])
    ui_tests = _text(root, IMPLEMENTATION_PATHS[5])
    fixture = _json(root, IMPLEMENTATION_PATHS[6])
    localization = _text(root, "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift")
    accessibility = _text(root, "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift")
    localization_catalog = _text(root, "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift")
    localizable = _json(root, "FieldEvidenceApp/Resources/Localizable.xcstrings")
    fixture_text = json.dumps(fixture, ensure_ascii=False, sort_keys=True)
    _assert_fixture_contract(fixture)
    _require_tokens(contract, (
        "EvidenceSequenceV1",
        "EvidenceCurationLifecycleV1", "plansAndProjectionsAreNonpersistent",
        "EvidenceDetailCardProfileV1", "EvidenceDetailCardRenderReceiptV1",
        "FinalAudiencePrivacyConfirmationV1", "CompletedActivitySnapshotV1",
        "immutable", "original", "derivative", "transform", "source",
        "comparison", "contact", "flicker", "EvidenceAnnotationActionV1", "supersedesAnnotationID",
        "metadataReceipt", "canonicalMutationReceiptSHA256", "EvidenceMetadataMutationReceiptV1",
        "EvidenceSequenceItemV1", "ordinal", "orderedItems",
    ), "C02 evidence-curation contract")
    _require_patterns(contract, (
        r"validate",
        r"source[^\n]{0,120}(?:sha|digest|identity)", r"transform[^\n]{0,120}(?:sha|digest|identity)",
        r"maximumSelectionCount\s*=\s*32", r"maximumComparisonCount\s*=\s*2",
        r"maximumAnnotations\s*=\s*64", r"maximumSequenceFrames\s*=\s*16",
        r"maximumContactSheetColumns\s*=\s*4", r"comparisonIsProof\s*=\s*false",
        r"createsContentStore\s*=\s*false",
        r"persistence\s*=\s*[\"']CONTENT_ONLY[\"']",
        r"schema\s*=\s*[\"']INCUMBENT_CONTENT_AUTHORITY_AND_C05_V43_METADATA[\"']",
        r"migration\s*=\s*[\"']C05_METADATA_AUTHORITY[\"']",
        r"backupRestore\s*=\s*[\"']REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES[\"']",
        r"cloneFork\s*=\s*[\"']INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES[\"']",
        r"journalReplay\s*=\s*[\"']C05_METADATA_WRITER_REPLAY_AND_DETERMINISTIC_REPROJECTION[\"']",
        r"searchRebuild\s*=\s*[\"']NOT_APPLICABLE[\"']",
        r"deleteErase\s*=\s*[\"']REQUIRED_VIA_INCUMBENT_CONTENT_AND_C05_METADATA_AUTHORITIES[\"']",
        r"exportReport\s*=\s*[\"']REQUIRED_VIA_INCUMBENT_CONTENT_C05_METADATA_AND_REPORT_AUTHORITIES[\"']",
        r"WorkspaceMutationCanonicalV1\.sha256", r"EvidenceCurationOperationReceiptV1",
        r"state\s*=\s*\.interrupted", r"replayDiverged",
        r"ContentClosedCodingV1\.requireExact", r"CodingKeys.*snapshot",
        r"EvidenceDetailPreviewBundleV1",
    ), "C02 evidence-curation closure")
    _require_tokens(coordinator, (
        "EvidenceCurationCoordinatorV1",
        "EvidenceSequenceV1", "EvidenceDetailPreviewBundleV1", "eligibleSelection", "previews", "reviewedMarkup",
        "sequence", "replay", "EvidenceAssociationLedgerV1", "contentResolver",
    ), "C02 coordinator ownership")
    _require_tokens(derivative, (
        "EvidenceDerivativeServiceV1", "EvidenceDerivativePlanV1", "EvidenceDerivativePublicationCommandV1",
        "EvidenceCurationDerivativeResultV1", "EvidenceDerivativePublicationReceiptV1",
        "EvidenceDerivativeCancellationV1", "EvidenceDerivativePublicationMarkerV1",
        "source", "transform", "original", "derivative", "markup", "sequence",
        "renderDeterministically", "publish", "publishOrAdoptEvidenceDerivative", "associationHistory",
        "WorkspaceWriter", "commitEvidenceMetadata", "EvidenceMetadataMutationV1", "EvidenceMetadataMutationReceiptV1",
        "postImages", "affectedIdentities", "concurrencyIdentities",
        "createsContentStore", "mutatesOriginalBytes",
        "privacyTransformPrecedesMarkup", "usesNetworkOrDiagnosis",
    ), "C02 derivative service")
    _require_patterns(derivative, (
        r"mediaType\s*==\s*[\"']image/png[\"']",
        r"(?:pngSignature|pngHeader|PNG_SIGNATURE|0x89.{0,80}0x50.{0,80}0x4[eE].{0,80}0x47)",
        r"contact[Ss]heet.{0,180}(?:Data|bytes|render)",
        r"(?:rendered|derivative)Bytes\.count",
    ), "C02 binary derivative publication")
    if re.search(r"derivative\.mediaType\s*==\s*[\"']application/json[\"']", derivative, re.I):
        raise ValueError("C02 derivative publication is JSON-only")
    _require_tokens(view, (
        "EvidenceCurationView", "EvidenceRoleV1", "caption", "accessibility",
        "onRetake", "onRemoveFromWork", "onMoveEarlier", "onMoveLater",
        "retakeReviewRequired", "removeHistoryDisclosure",
        "comparison", "markup", "arrow", "circle", "contact", "flicker",
    ), "C02 curation view")
    _require_tokens(localization, (
        "EvidenceCurationLocalizationKeyV1", 'case retake = "evidence.curation.item.retake"',
        'case retakeReviewRequired = "evidence.curation.item.retake.review_required"',
        'case removeFromWork = "evidence.curation.item.remove_from_work"',
        'case removeHistoryDisclosure = "evidence.curation.item.remove_history_disclosure"',
        'case moveEarlier = "evidence.curation.item.move_earlier"',
        'case moveLater = "evidence.curation.item.move_later"',
        "Retake stages a new original", "Immutable evidence history remains", "Move earlier", "Move later",
    ), "C02 retake/remove/move localization")
    _require_tokens(accessibility, (
        "EvidenceCurationAccessibilityIDV1", "retakeAndRemovalEffectsAreDisclosed",
        "accessibleMoveControlsAreAvailable", "evidence-curation.retake",
        "evidence-curation.remove-from-work", "evidence-curation.move-earlier", "evidence-curation.move-later",
    ), "C02 retake/remove/move accessibility")
    _require_tokens(localization_catalog, (
        "evidenceCurationEnglish", "evidenceCurationLocalized", "evidenceCurationRegistry",
    ), "C02 bundled localization catalog")
    required_localizable = {
        "evidence.curation.item.retake": "Retake evidence",
        "evidence.curation.item.retake.review_required": "Retake stages a new original and requires review of the caption and accessibility description for the new pixels.",
        "evidence.curation.item.remove_from_work": "Remove from this work/report",
        "evidence.curation.item.remove_history_disclosure": "Immutable evidence history remains. If this evidence is required, completion returns to incomplete.",
        "evidence.curation.item.move_earlier": "Move earlier",
        "evidence.curation.item.move_later": "Move later",
    }
    strings = localizable.get("strings")
    if not isinstance(strings, dict):
        raise ValueError("C02 Localizable catalog strings missing")
    for key, expected in required_localizable.items():
        try:
            observed = strings[key]["localizations"]["en"]["stringUnit"]["value"]
        except (KeyError, TypeError):
            raise ValueError("C02 Localizable entry missing:" + key)
        if observed != expected:
            raise ValueError("C02 Localizable English value differs:" + key)
    selectors = _assert_exact_selectors(tests)
    _require_tokens(tests, (
        "EvidenceCurationCoordinatorV1", "EvidenceSequenceV1", "EvidenceSequenceItemV1",
        "EvidenceMetadataMutationV1", "EvidenceMetadataMutationReceiptV1",
        "EvidenceDerivativePublicationCommandV1", "role", "caption", "accessibilityDescription",
        "ordinal", "orderedItems", "IHDR", "IDAT", "IEND", "acTL",
    ), "C02 evidence tests")
    _require_tokens(ui_tests, (CARD, "UIAdoptionPendingPostS10", "XCTSkip", "evidence-curation"), "C02 UI deferral test")
    _require_tokens(fixture_text, (CARD, *EVIDENCE_IDS, "hostileCases", "sequence", "markup", "comparison", "source", "transform"), "C02 fixture")
    source = "\n".join((contract, coordinator, derivative, view, tests, ui_tests))
    if re.search(r"\b(?:URLSession|URLRequest|CloudKit|CKContainer|WebSocket|NWConnection|TelemetryClient|CoreML|OpenAI|upload)\b", source, re.I):
        raise ValueError("C02 network/cloud/AI/telemetry/upload symbols present")
    _assert_provider_source_slices(root)
    _assert_c24_c01_prerequisite_slices(root)
    _assert_existing_content_authority_slices(root)
    _assert_c05_metadata_source_slices(root)
    return selectors


def _authority_pins_ready() -> bool:
    refs = (BASE_HEAD, BASE_TREE, CANDIDATE_HEAD, CANDIDATE_TREE, COORDINATION_HEAD, COORDINATION_ORIGIN_HEAD, COORDINATION_TREE)
    digests = (
        CONTEXT_DIGEST, FENCE_DIGEST, PREREQUISITE_DIGEST, HYDRATION_TRANSITION_DIGEST,
        COORDINATION_LEDGER_DIGEST, COORDINATION_PROJECTION_DIGEST, FROZEN_S10_RESERVATION_DIGEST,
        DOSSIER_SHA256, INHERITED_V21_BLOCK_SHA256, REGISTER_ROW_SHA256, REGISTER_SECTION_SHA256,
    )
    return all(re.fullmatch(r"[0-9a-f]{40}", value) for value in refs) and all(_valid_sha(value) for value in digests)


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE), len(set(PATH_FENCE))) != (EXPECTED_EXISTING_PATH_COUNT, EXPECTED_NEW_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT, EXPECTED_FENCE_PATH_COUNT):
        raise ValueError("C02 fence cardinality or uniqueness differs")
    if NEW_PATHS != _HYDRATED_NEW_PATHS:
        raise ValueError("C02 new-path ordering differs from hydrated fence")
    if any("phase10" in path.lower() or "/s10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C02 fence contains Phase10/S10 path")
    if not _authority_pins_ready() or AUTHORIZED_OVERLAP_COUNT != 5279 or UNAUTHORIZED_OVERLAP_COUNT != 0 or S10_RESERVATION_OVERLAP_COUNT != 0:
        raise ValueError("C02 authority pins or overlap counts unresolved")
    if _git(root, "show", "-s", "--format=%T", BASE_HEAD) != BASE_TREE:
        raise ValueError("C02 app base tree differs")
    _candidate_identity(root)
    _assert_coordination_state()
    _assert_design_slices(root)
    missing_base = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing_base:
        raise ValueError("C02 inherited fence path absent from base:" + ",".join(missing_base))
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C02 new path already exists at accepted base")


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "candidateHead": CANDIDATE_HEAD, "candidateTree": CANDIDATE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationOriginHead": COORDINATION_ORIGIN_HEAD, "coordinationTree": COORDINATION_TREE, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "dependencyCorrectionDigest": DEPENDENCY_CORRECTION_DIGEST, "hydrationRevision": HYDRATION_REVISION,
        "acceptedDependencyProvider": ACCEPTED_C05_PROVIDER,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "dossierSHA256": DOSSIER_SHA256, "dossierByteCount": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256, "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "registerOrdinal": REGISTER_ORDINAL, "directPrerequisiteCards": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS), "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT, "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
    }


def _common() -> dict[str, Any]:
    return {
        "cardID": CARD, "title": TITLE, "authority": authority(), "evidenceIDs": list(EVIDENCE_IDS),
        "statusFlags": FLAGS, "provisional": not FINAL_HASHES_SEALED, "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


def provider_artifacts(root: Path) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for card, metadata in _PROVIDER_ARTIFACTS.items():
        files: list[dict[str, Any]] = []
        for path in metadata["paths"]:
            target = root / path
            if target.is_file():
                data = canonical_file_bytes(target)
                files.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_PROVIDER"})
            else:
                if FINAL_HASHES_SEALED and metadata["required"]:
                    raise ValueError("cannot seal missing provider input:" + path)
                files.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_PROVIDER"})
        result.append({
            "providerCardID": card, "required": metadata["required"], "capability": metadata.get("facet"),
            "pathFenceDigest": metadata["pathFenceDigest"], "candidateHead": metadata["candidateHead"],
            "candidateTree": metadata["candidateTree"], "checkpointDigest": metadata["checkpointDigest"],
            "contextDigest": metadata["contextDigest"], "verificationReceiptDigest": metadata["verificationReceiptDigest"],
            "contracts": list(metadata["contracts"]), "paths": list(metadata["paths"]), "files": files,
            "allFilesPresent": all(item["sha256"] is not None for item in files), "fallback": None,
        })
    return result


def c05_metadata_persistence() -> dict[str, Any]:
    return {
        "mode": C05_PERSISTENCE_MODE,
        "persistentContractSchema": C05_PERSISTENT_CONTRACT_SCHEMA,
        "persistentSchemaVersion": C05_PERSISTENT_SCHEMA_VERSION,
        "recordsSchemaVersion": C05_RECORDS_SCHEMA_VERSION,
        "activeModelCount": C05_ACTIVE_MODEL_COUNT,
        "durableModelCount": C05_DURABLE_MODEL_COUNT,
        "durableRows": list(C05_DURABLE_ROWS),
        "durableFamilies": list(C05_DURABLE_FAMILIES),
        "backupRestore": C05_BACKUP_RESTORE,
        "journalReplay": C05_JOURNAL_REPLAY,
        "searchReport": C05_SEARCH_REPORT,
        "deleteErase": C05_DELETE_ERASE,
        "canonicalWriterReceipt": "EvidenceMetadataMutationReceiptV1",
    }


def semantics(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "curation": "EXPLICIT_REFERENCE_ELIGIBILITY_SELECTION_REVIEWED_ROLE_CAPTION_ORDER_AND_ACCESSIBILITY_DESCRIPTION",
        "roles": list(EVIDENCE_ROLES), "closedRoleCount": len(EVIDENCE_ROLES),
        "comparison": "IMMUTABLE_SIDE_BY_SIDE_AND_TRANSPARENT_ADVISORY_OVERLAY_NEVER_CAUSAL_OR_COMPLIANCE_PROOF",
        "markup": "REVERSIBLE_ARROW_CIRCLE_TEXT_DERIVATIVES_NEVER_MUTATE_ORIGINAL",
        "sequence": "BOUNDED_FLICKER_AND_DETERMINISTIC_CONTACT_SHEET",
        "retakeRemove": "STAGED_DISCARD_OR_POST_PROMOTION_SUCCESSOR_ASSOCIATION_WITH_HISTORY_RETAINED",
        "originals": {"byteForByteImmutable": True, "derivativesBindSourceAndTransform": True, "sourceMutation": False},
        "persistence": "CONTENT_ONLY_DERIVATIVES_EXISTING_C05_METADATA_WRITER_NO_SECOND_WRITER",
        "persistentChangeMode": PERSISTENT_CHANGE_MODE, "persistentContractSchema": PERSISTENT_CONTRACT_SCHEMA,
        "persistentRowTypes": list(PERSISTENT_ROW_TYPES), "nonpersistentTypes": list(NONPERSISTENT_TYPES),
        "persistentWriterOwner": "V23-P03-C05", "lifecycleEnrollmentOwner": "V23-P02-C09",
        "lifecycle": dict(C02_LIFECYCLE),
        "c05MetadataPersistence": c05_metadata_persistence(),
        "plansAndProjectionsPersistence": C02_PLAN_PROJECTION_PERSISTENCE,
        "derivativeByteMode": C02_DERIVATIVE_BYTE_MODE,
        "bundleDecoding": "EXACT_NO_ADDITIONAL_PROPERTIES",
        "binaryRendering": {
            "requiredMediaType": "image/png",
            "contactSheetBytesRequired": True,
            "jsonOnlyRenderingForbidden": True,
        },
        "actualDeletion": "V21-P01-C06_AND_V21-P03-C05_GOVERNED_WORK_NOT_C02",
        "privacy": "C20_SOLE_REDACTION_AUTHORITY_FINAL_AUDIENCE_CONFIRMATION_REQUIRED",
        "lifecycleCoverage": list(LIFECYCLE_COVERAGE), "schemaBehaviorDelta": False, "migrationBehaviorDelta": False,
        "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupRestoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True,
        "report": "FREEZES_REVIEWED_ROLE_CAPTION_ORDER_ACCESSIBILITY_AND_SOURCE_DERIVATIVE_BINDINGS",
        "ownership": "NO_SECOND_WRITER_RENDERER_IMPORTER_PRIVACY_REDACTION_OR_REPORT_AUTHORITY",
        "noNetworkCloudTelemetryAI": True, "noAutomaticCaptionTruth": True, "noUnboundedMedia": True,
        "journeyRefs": list(JOURNEY_REFS), "selectors": list(selectors),
        "ui": "POST_S10_ADOPTION_SKIP_NO_RESERVED_COMPOSITION_EDIT",
        "forbiddenCapabilities": ["SECOND_WRITER", "SECOND_RENDERER", "NETWORK", "CLOUD", "TELEMETRY", "AI_DIAGNOSIS", "AUTO_CAPTION_TRUTH", "UNBOUNDED_MEDIA"],
    }


def _source_rows(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in IMPLEMENTATION_PATHS:
        target = root / path
        if target.is_file():
            data = canonical_file_bytes(target)
            rows.append({"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_SOURCE"})
        else:
            rows.append({"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"})
    return rows


def _source_projection(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    status = source_status(root)
    return {
        "implementationPaths": list(IMPLEMENTATION_PATHS), "presentPaths": status["presentPaths"], "missingPaths": status["missingPaths"],
        "selectors": list(selectors), "sourceSemanticsInspected": bool(status["hydrated"] and not status["missingPaths"]),
        "sourceRows": _source_rows(root), "registerRows": [REGISTER_ROW], "dossierSHA256": DOSSIER_SHA256, "dossierByteCount": DOSSIER_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256, "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256, "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "aggregateAcceptanceMemberships": list(AGGREGATE_MEMBERSHIPS), "conformanceSubjects": list(CONFORMANCE_SUBJECTS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS), "canonicalSuccessor": {"cardID": "V23-P04-C03", "registerOrdinal": 91},
        "lifecycle": dict(C02_LIFECYCLE),
        "c05MetadataPersistence": c05_metadata_persistence(),
        "plansAndProjectionsPersistence": C02_PLAN_PROJECTION_PERSISTENCE,
        "derivativeByteMode": C02_DERIVATIVE_BYTE_MODE,
        "bundleDecoding": "EXACT_NO_ADDITIONAL_PROPERTIES",
        "binaryRendering": {"requiredMediaType": "image/png", "contactSheetBytesRequired": True, "jsonOnlyRenderingForbidden": True},
        "providerContractSlices": [
            {"providerCardID": "V23-P03-C05", "facet": "EVIDENCE_METADATA_CANONICAL_WRITER_AND_RECEIPT", "pathFenceDigest": _PROVIDER_ARTIFACTS["V23-P03-C05"]["pathFenceDigest"], "contracts": list(_PROVIDER_ARTIFACTS["V23-P03-C05"]["contracts"])},
            {"providerCardID": "V23-P03-C06", "facet": "EVIDENCE_DETAIL_AUTHORITY", "pathFenceDigest": _PROVIDER_ARTIFACTS["V23-P03-C06"]["pathFenceDigest"], "contracts": list(_PROVIDER_ARTIFACTS["V23-P03-C06"]["contracts"])},
        ],
    }


def schema_document(selectors: tuple[str, ...]) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/evidence-curation.schema.json",
        "title": TITLE, "type": "object", "additionalProperties": False,
        "properties": {
            "schema": {"const": "V22P04C02EvidenceCurationCorpusV1"}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
            "evidenceIDs": {"const": list(EVIDENCE_IDS)}, "selectors": {"const": list(selectors)},
            "evidenceRoles": {"const": list(EVIDENCE_ROLES)}, "closedRoleCount": {"const": len(EVIDENCE_ROLES)},
            "contractRefs": {"const": list(CONTRACT_REFS)}, "journeyRefs": {"const": list(JOURNEY_REFS)},
            "persistentChangeMode": {"const": PERSISTENT_CHANGE_MODE}, "persistentContractSchema": {"const": PERSISTENT_CONTRACT_SCHEMA},
            "persistentRowTypes": {"const": list(PERSISTENT_ROW_TYPES)}, "nonpersistentTypes": {"const": list(NONPERSISTENT_TYPES)},
            "lifecycle": {"const": dict(C02_LIFECYCLE)},
            "c05MetadataPersistence": {"const": c05_metadata_persistence()},
            "plansAndProjectionsPersistence": {"const": C02_PLAN_PROJECTION_PERSISTENCE},
            "derivativeByteMode": {"const": C02_DERIVATIVE_BYTE_MODE},
            "bundleDecoding": {"const": "EXACT_NO_ADDITIONAL_PROPERTIES"},
            "binaryRendering": {"const": {"requiredMediaType": "image/png", "contactSheetBytesRequired": True, "jsonOnlyRenderingForbidden": True}},
            "contentMode": {"const": "CONTENT_ONLY"}, "comparisonIsProof": {"const": False}, "createsContentStore": {"const": False},
            "finalHashesSealed": {"const": FINAL_HASHES_SEALED}, "provisional": {"const": not FINAL_HASHES_SEALED},
            "hostileCases": {"type": "array", "items": {"type": "string"}, "maxItems": 64},
            "sequenceBound": {"type": "integer", "minimum": 1, "maximum": 16},
        },
        "required": ["schema", "schemaVersion", "cardID", "evidenceIDs", "selectors", "evidenceRoles", "closedRoleCount", "contractRefs", "journeyRefs", "persistentChangeMode", "persistentContractSchema", "persistentRowTypes", "nonpersistentTypes", "lifecycle", "c05MetadataPersistence", "plansAndProjectionsPersistence", "derivativeByteMode", "bundleDecoding", "binaryRendering", "contentMode", "comparisonIsProof", "createsContentStore", "finalHashesSealed", "provisional"],
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    return {**value, "artifactDigest": sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None}


def contract_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C02EvidenceCurationContractV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "directPrerequisites": list(DIRECT_PREREQUISITES), "contractRefs": list(CONTRACT_REFS), "journeyRefs": list(JOURNEY_REFS),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS), "semantics": semantics(selectors),
        "sourceProjection": _source_projection(root, selectors), "providerArtifacts": provider_artifacts(root),
    })


def evidence_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    cases = [
        {"evidenceID": EVIDENCE_IDS[0], "kind": "GOLDEN", "focus": ["explicit eligibility and reviewed role/caption/order/accessibility", "readable detail preview", "required source and derivative bindings", "C05 canonical metadata writer receipt"], "selectorSuffix": "G01"},
        {"evidenceID": EVIDENCE_IDS[1], "kind": "ALTERNATE", "focus": ["immutable side-by-side comparison", "transparent advisory overlay", "C20 privacy confirmation remains authoritative"], "selectorSuffix": "A01"},
        {"evidenceID": EVIDENCE_IDS[2], "kind": "HOSTILE", "focus": ["wrong reference, duplicate, wrong order, missing bytes", "extra preview-bundle fields are rejected", "original cannot be mutated", "markup cannot become redaction or compliance proof"], "selectorSuffix": "H01"},
        {"evidenceID": EVIDENCE_IDS[3], "kind": "INTERRUPTION", "focus": ["bounded processing/flicker/contact sheet PNG bytes", "cancel/retry leaves no partial accepted association", "low storage/background/relaunch"], "selectorSuffix": "I01"},
        {"evidenceID": EVIDENCE_IDS[4], "kind": "RECOVERY", "focus": ["staged and promoted Retake/Remove", "history-retaining successor", "backup/restore/delete/Erase/report closure"], "selectorSuffix": "R01"},
    ]
    return _sealed({
        "schema": "V23P04C02EvidenceCurationEvidenceReceiptV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "cases": cases, "testSelectors": list(selectors), "journey": "FJ15", "evidenceRoles": list(EVIDENCE_ROLES),
        "comparisonDisposition": "ADVISORY_ONLY", "markupDisposition": "DERIVATIVE_ONLY_SOURCE_UNCHANGED",
        "boundedSequence": {"flicker": True, "deterministicContactSheet": True, "maxItems": 16},
        "lifecycle": dict(C02_LIFECYCLE),
        "c05MetadataPersistence": c05_metadata_persistence(),
        "plansAndProjectionsPersistence": C02_PLAN_PROJECTION_PERSISTENCE,
        "derivativeByteMode": C02_DERIVATIVE_BYTE_MODE,
        "bundleDecoding": "EXACT_NO_ADDITIONAL_PROPERTIES",
        "binaryRendering": {"requiredMediaType": "image/png", "contactSheetBytesRequired": True, "jsonOnlyRenderingForbidden": True},
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "uiAdoptionSkipped": True, "sourceProjection": _source_projection(root, selectors), "providerArtifacts": provider_artifacts(root),
    })


def brand_document(root: Path, selectors: tuple[str, ...]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P04C02BrandImpactManifestV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "iPhoneNativeOnly": True, "nativeIPadSurface": False,
        "onDeviceOnly": True, "uiTestDisposition": "EXPLICIT_POST_S10_ADOPTION_SKIP_NO_RESERVED_APP_COMPOSITION_AUTHORITY",
        "adoptionSkipped": True, "uiAdoptionSkipped": True, "networkOrTelemetryFlow": False, "customerIdentityVerified": False,
        "deliveryOrLegalSignatureClaimed": False, "privacyRedactionOwnedByC20": True,
        "originalBytePreservationRequired": True, "derivativeMarkupOnly": True, "accessibilityAndLocalizationRequired": True,
        "lifecycle": dict(C02_LIFECYCLE),
        "c05MetadataPersistence": c05_metadata_persistence(),
        "plansAndProjectionsPersistence": C02_PLAN_PROJECTION_PERSISTENCE,
        "derivativeByteMode": C02_DERIVATIVE_BYTE_MODE,
        "bundleDecoding": "EXACT_NO_ADDITIONAL_PROPERTIES",
        "binaryRendering": {"requiredMediaType": "image/png", "contactSheetBytesRequired": True, "jsonOnlyRenderingForbidden": True},
        "sourceProjection": _source_projection(root, selectors),
    })


def _manifest_row(root: Path, path: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if path in rendered:
        data = rendered[path]
        return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_TOOLING"}
    target = root / path
    if not target.is_file():
        if FINAL_HASHES_SEALED:
            raise ValueError("cannot seal missing fence input:" + path)
        return {"path": path, "byteCount": None, "sha256": None, "status": "PENDING_SOURCE"}
    data = canonical_file_bytes(target)
    return {"path": path, "byteCount": len(data), "sha256": sha256_bytes(data), "status": "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE"}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    status = source_status(root)
    selectors = assert_source_contracts(root) if status["hydrated"] else observed_selectors(root)
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: pretty(schema_document(selectors)),
        CONTRACT_PATH: pretty(contract_document(root, selectors)),
        EVIDENCE_PATH: pretty(evidence_document(root, selectors)),
        BRAND_PATH: pretty(brand_document(root, selectors)),
    }
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest_base = {
        "schema": "V23P04C02ToolingManifestV1", "schemaVersion": SCHEMA_VERSION, **_common(),
        "pathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS),
        "toolingEditPaths": list(TOOLING_EDIT_PATHS), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "fencePathCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
        "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED",
        "files": rows, "artifactSetDigest": sha256_bytes(canonical(rows)) if FINAL_HASHES_SEALED else None,
        "sourceProjection": _source_projection(root, selectors), "providerArtifacts": provider_artifacts(root),
    }
    rendered[MANIFEST_PATH] = pretty(_sealed(manifest_base))
    return rendered


def _self_parse() -> None:
    for path in SCRIPT_PATHS:
        local = ROOT / path
        if local.is_file():
            ast.parse(local.read_text(encoding="utf-8"), filename=path)


if __name__ == "__main__":
    _self_parse()
    print(json.dumps({"cardID": CARD, "sourceReady": source_status(ROOT)["hydrated"], "finalHashesSealed": FINAL_HASHES_SEALED, "fencePathCount": EXPECTED_FENCE_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT}, sort_keys=True))
