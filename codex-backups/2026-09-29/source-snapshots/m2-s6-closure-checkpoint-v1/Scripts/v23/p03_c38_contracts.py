"""Static contract corpus and deterministic artifact builders for V23-P03-C38.

Card 46 owns only the static evidence lane.  This module intentionally keeps the
contract corpus independent of the future Swift implementation: it records the
required local-party, role, actor, qualification, signoff, and persistence
semantics without claiming native, hosted, adoption, acceptance, or release
evidence.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any, Iterable


CARD = "V23-P03-C38"
SCHEMA_VERSION = 1
BASE_HEAD = "21c5eb1112cb72669f7de6277fa6083766831d51"
BASE_TREE = "1c18d7cb6b72b35e48ea19115ad09cfbb5837c41"
FENCE_DIGEST = "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4"

# This is the frozen S10 reservation identity, carried as an opaque authority
# value.  No S10 file or path is read by this card's tooling.
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

SCHEMA_PATH = "Scripts/v23/party-accountability.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C38PartyAccountabilityContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C38PartyAccountabilityEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C38BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C38-tooling-manifest.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c38_contracts.py",
    "Scripts/v23/generate_p03_c38_contracts.py",
    "Scripts/v23/verify_p03_c38_contracts.py",
)

# The eight static-tool paths are the only files this work unit edits.  The
# complete hydrated Card 46 fence is kept separately below: the verifier must
# account for every product, test, fixture, and tooling path in that fence.
TOOL_PATHS = SCRIPT_PATHS + (
    SCHEMA_PATH,
    CONTRACT_PATH,
    EVIDENCE_PATH,
    BRAND_PATH,
    MANIFEST_PATH,
)

EXISTING_PATHS = (
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
)

NEW_PATHS = (
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/PartyAccountabilityPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Accountability/PartyAccountabilityCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Accountability/PartyAccountabilityLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_23PartyAccountabilityTests.swift",
    "FieldEvidenceAppUITests/V23_P03_C38PartyAccountabilityUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Accountability/V21P03C38PartyAccountabilityCorpusV1.json",
    *TOOL_PATHS,
)

PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

# Prior V23 fences which overlap the hydrated C38 fence.  The bootstrap proof
# records 252 authorized overlap edges across these prior fence identities;
# this compact projection preserves each card's identity, digest, and edge
# count without importing any prior card's ownership into Card 46.
PRIOR_FENCE_OVERLAPS = (
    {"cardID": "V23-P01-C01", "fenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "overlapCount": 3},
    {"cardID": "V23-P01-C02", "fenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "overlapCount": 3},
    {"cardID": "V23-P01-C03", "fenceDigest": "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "overlapCount": 6},
    {"cardID": "V23-P01-C04", "fenceDigest": "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "overlapCount": 2},
    {"cardID": "V23-P01-C05", "fenceDigest": "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "overlapCount": 10},
    {"cardID": "V23-P01-C06", "fenceDigest": "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "overlapCount": 15},
    {"cardID": "V23-P01-C07", "fenceDigest": "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "overlapCount": 3},
    {"cardID": "V23-P02-C01", "fenceDigest": "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "overlapCount": 5},
    {"cardID": "V23-P02-C02", "fenceDigest": "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "overlapCount": 22},
    {"cardID": "V23-P02-C03", "fenceDigest": "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "overlapCount": 17},
    {"cardID": "V23-P02-C04", "fenceDigest": "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "overlapCount": 6},
    {"cardID": "V23-P02-C05", "fenceDigest": "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "overlapCount": 6},
    {"cardID": "V23-P02-C06", "fenceDigest": "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "overlapCount": 2},
    {"cardID": "V23-P02-C07", "fenceDigest": "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "overlapCount": 24},
    {"cardID": "V23-P02-C08", "fenceDigest": "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "overlapCount": 2},
    {"cardID": "V23-P02-C09", "fenceDigest": "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "overlapCount": 5},
    {"cardID": "V23-P03-C06", "fenceDigest": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", "overlapCount": 5},
    {"cardID": "V23-P03-C08", "fenceDigest": "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "overlapCount": 7},
    {"cardID": "V23-P03-C09", "fenceDigest": "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "overlapCount": 35},
    {"cardID": "V23-P03-C11", "fenceDigest": "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "overlapCount": 5},
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "overlapCount": 28},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "overlapCount": 5},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "overlapCount": 36},
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 46,
    "priorOwnedPathCount": 776,
    "overlapCount": 252,
    "authorizedOverlapCount": 252,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_PartyAccountabilityG01TypedLocalAssertionsAndRoleHistory",
    "testV9_PartyAccountabilityA01ExternalEvidenceAndUnknownActorRemainLocal",
    "testV9_PartyAccountabilityH01UnknownKeysDigestsAndCrossWorkspaceReferencesFailClosed",
    "testV9_PartyAccountabilityI01InterruptedWriterRecoversEffectAndReceiptIdempotently",
    "testV9_PartyAccountabilityR01BackupRestoreSearchReportImportAndErasePreserveHistory",
)

# Existing, pinned source references are exactly the 48 existing paths in the
# hydrated fence.  Source bytes are read from immutable BASE_HEAD blobs, so
# unrelated working-tree implementation work is neither owned nor incorporated
# by this static lane.  The two authority documents are tracked separately.
SOURCE_REFERENCE_PATHS = EXISTING_PATHS

REQUIRED_CONTRACT_NAMES = (
    "ServicePartyReferenceV1",
    "SitePartyRoleEventV1",
    "LocalActorReferenceV1",
    "ActorSnapshotV1",
    "QualificationSnapshotV1",
    "SignoffDispositionV1",
    "SignoffSnapshotV1",
    "SignoffMethodV1",
    "SignoffIntentDisclosureReleaseV1",
    "SignoffRoleAssertionV1",
    "PARTIES_V1",
    "SITE_PARTY_ROLES_V1",
)

PARTY_KINDS = ("PERSON", "ORGANIZATION")
SITE_ROLE_KINDS = ("OWNER", "OPERATOR", "CLIENT", "SERVICE_PROVIDER", "CONTACT")
RESPONSIBILITY_KINDS = (
    "RECORDED_BY",
    "PERFORMED_BY",
    "OBSERVED_BY",
    "REVIEWED_BY",
    "VERIFIED_BY",
    "APPROVED_BY",
    "ACKNOWLEDGED_BY",
    "ASSIGNED_TO",
    "WITNESSED_BY",
)
QUALIFICATION_PROVENANCE = ("SELF_DECLARED", "IMPORTED_EXTERNAL_EVIDENCE")
SIGNOFF_DISPOSITIONS = (
    "RECORDED_LOCAL_ASSERTION",
    "EXTERNAL_EVIDENCE_ATTACHED",
    "NOT_RECORDED",
    "NOT_APPLICABLE",
)
SIGNOFF_METHODS = ("TYPED_NAME", "OPTIONAL_MARK")

LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V9_VERSIONED_IDENTITY",
    "WRITER_COMMAND_QUERY",
    "MIGRATION_AND_RECOVERY",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK_GENERATION",
    "IMPORT_EXPORT_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT",
    "DELETE_ERASE_RETENTION",
    "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON",
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
)

FORBIDDEN_CLAIMS = (
    "AUTHENTICATED_IDENTITY",
    "ACCOUNT_OR_LOGIN",
    "RBAC_OR_TEAM_DISPATCH",
    "REMOTE_VERIFICATION",
    "E_SIGNATURE",
    "CUSTOMER_PORTAL",
    "CRM_OR_CONTACT_SYNC",
    "CERTIFICATION",
    "HOSTED_BACKEND",
    "S10_RELEASE_OR_BRAND_APPROVAL",
)

SOURCE_CONTRACT_TOKENS = (
    "V23-P03-C38",
    "ServicePartyReferenceV1",
    "SitePartyRoleEventV1",
    "LocalActorReferenceV1",
    "QualificationSnapshotV1",
    "SignoffDispositionV1",
)

REQUIRED_BEHAVIORS = (
    {
        "id": "PARTY_IDENTITY",
        "contract": "ServicePartyReferenceV1",
        "requirement": "Stable local PartyID references a PERSON or ORGANIZATION and carries bounded display/profile provenance without becoming an account or contact-sync record.",
        "evidence": "C38-S01",
    },
    {
        "id": "SITE_ROLE_HISTORY",
        "contract": "SitePartyRoleEventV1",
        "requirement": "Append-only OWNER, OPERATOR, CLIENT, SERVICE_PROVIDER, and CONTACT role events bind SiteID and PartyID to effective intervals, source, supersession, and a receipt.",
        "evidence": "C38-S02",
    },
    {
        "id": "ACTOR_RESPONSIBILITY",
        "contract": "ActorSnapshotV1",
        "requirement": "Local actor references and snapshots use the closed responsibility vocabulary for recorded, performed, observed, reviewed, verified, approved, acknowledged, assigned, or witnessed work.",
        "evidence": "C38-S03",
    },
    {
        "id": "QUALIFICATION_CLAIMS",
        "contract": "QualificationSnapshotV1",
        "requirement": "Qualification claims retain declared scope, issuer, credential locator, effective and expiry bounds, and SELF_DECLARED or IMPORTED_EXTERNAL_EVIDENCE provenance without asserting external verification.",
        "evidence": "C38-S04",
    },
    {
        "id": "SIGNOFF_ASSERTIONS",
        "contract": "SignoffSnapshotV1",
        "requirement": "Signoff snapshots bind purpose, subject and revision, occurred and recorded timestamps, method, actor, optional qualification, disposition, and supersession.",
        "evidence": "C38-S05",
    },
    {
        "id": "SCHEMA_V9_PERSISTENCE",
        "contract": "PARTIES_V1",
        "requirement": "Versioned schema-v9 identity covers parties, site-role history, actors, qualifications, and signoffs with migration, downgrade or forward-fix, interruption, and recovery rules.",
        "evidence": "C38-L01",
    },
    {
        "id": "MUTATION_JOURNAL",
        "contract": "SignoffIntentDisclosureReleaseV1",
        "requirement": "Writer command/query mutations produce deterministic idempotent receipts and are represented in append-only journal, replay, checkpoint, and restore flows.",
        "evidence": "C38-L02",
    },
    {
        "id": "DELETE_ERASE",
        "contract": "SITE_PARTY_ROLES_V1",
        "requirement": "Delete and Erase semantics cover dependent role, actor, qualification, signoff, search, report, journal, and backup references under retention and orphan-cleanup rules.",
        "evidence": "C38-L03",
    },
    {
        "id": "SEARCH_REPORT_IMPORT",
        "contract": "SignoffRoleAssertionV1",
        "requirement": "Search and rebuild, report and deterministic open JSON, and import preview expose the same frozen local assertions without adding hosted or adoption claims.",
        "evidence": "C38-L04",
    },
    {
        "id": "STATIC_BOUNDARY",
        "contract": "V23-P03-C38",
        "requirement": "Card 46 emits static provisional contract evidence only; native, hosted, adoption, acceptance, and release outcomes remain false until later lifecycle reconciliation.",
        "evidence": "C38-B01",
    },
)

EVIDENCE_CASES = (
    {
        "id": "C38-S01",
        "kind": "SOURCE_CONTRACT",
        "assertion": "Pinned blueprint and foundation source contain the C38 party, role, actor, qualification, and signoff contract lineage.",
    },
    {
        "id": "C38-S02",
        "kind": "SEMANTIC_CLOSURE",
        "assertion": "Party kinds, site-role kinds, responsibility kinds, qualification provenance, signoff dispositions, and signoff methods are closed enumerations.",
    },
    {
        "id": "C38-L01",
        "kind": "LIFECYCLE_COVERAGE",
        "assertion": "Schema-v9, writer, migration, backup/restore, clone/fork, import preview, journal/replay, delete/Erase, search, report/open JSON, interruption, and receipts are enumerated.",
    },
    {
        "id": "C38-F01",
        "kind": "PATH_DIGEST_FENCE",
        "assertion": "Exactly the 63-path hydrated Card 46 fence is accounted for (48 existing and 15 new); the eight static-tool paths are the only files edited by this lane, with no S10 path overlap.",
    },
    {
        "id": "C38-B01",
        "kind": "STATIC_BOUNDARY",
        "assertion": "The result is PASS_STATIC_PROVISIONAL and all native, hosted, adoption, acceptance, and release flags are false.",
    },
)

CORPUS: dict[str, Any] = {
    "schema": "V23P03C38PartyAccountabilityCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "requiredContractNames": list(REQUIRED_CONTRACT_NAMES),
    "partyKinds": list(PARTY_KINDS),
    "siteRoleKinds": list(SITE_ROLE_KINDS),
    "responsibilityKinds": list(RESPONSIBILITY_KINDS),
    "qualificationProvenance": list(QUALIFICATION_PROVENANCE),
    "signoffDispositions": list(SIGNOFF_DISPOSITIONS),
    "signoffMethods": list(SIGNOFF_METHODS),
    "lifecycleDimensions": list(LIFECYCLE_DIMENSIONS),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "evidenceCases": list(EVIDENCE_CASES),
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_blob(root: Path, path: str) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(root), "show", f"{BASE_HEAD}:{path}"],
        check=True,
        capture_output=True,
    )
    return completed.stdout


def source_artifacts(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in SOURCE_REFERENCE_PATHS:
        raw = _git_blob(root, path)
        rows.append(
            {
                "path": path,
                "source": "BASE_HEAD_BLOB",
                "bytes": len(raw),
                "sha256": sha256_bytes(raw),
            }
        )
    return rows


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in AUTHORITY_REFERENCE_PATHS:
        raw = _git_blob(root, path)
        rows.append(
            {
                "path": path,
                "source": "BASE_HEAD_AUTHORITY_BLOB",
                "bytes": len(raw),
                "sha256": sha256_bytes(raw),
            }
        )
    return rows


def _schema_for_value(value: Any) -> dict[str, Any]:
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer"}
    if isinstance(value, str):
        return {"type": "string"}
    if isinstance(value, list):
        if not value:
            return {"type": "array", "items": {}}
        item_schemas = {canonical(_schema_for_value(item)) for item in value}
        if len(item_schemas) == 1:
            item_schema = json.loads(next(iter(item_schemas)).decode("utf-8"))
        else:
            item_schema = {"anyOf": [json.loads(item.decode("utf-8")) for item in sorted(item_schemas)]}
        result: dict[str, Any] = {"type": "array", "items": item_schema, "minItems": len(value), "maxItems": len(value)}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        properties = {key: _schema_for_value(value[key]) for key in sorted(value)}
        return {
            "type": "object",
            "additionalProperties": False,
            "properties": properties,
            "required": sorted(value),
        }
    raise TypeError(f"unsupported schema value: {type(value)!r}")


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update(
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://assetrounds.invalid/v23/party-accountability.schema.json",
            "title": "V23 P03 C38 Party Accountability Contract Corpus",
        }
    )
    return document


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "fenceDigest": FENCE_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "allowedPathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "persistentContractSchema": "PERSISTENT_SCHEMA_V9_PARTY_ACCOUNTABILITY",
        "schemaBehaviorDelta": True,
        "migrationBehaviorDelta": True,
        "backupBehaviorDelta": True,
        "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True,
        "restoreCompatibilityRequired": True,
        "deleteCompatibilityRequired": True,
        "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V9_WRITE",
        "uiSurfaceDelta": True,
        "brandSurfaceDelta": True,
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _flags() -> dict[str, bool]:
    return {
        "native": False,
        "hosted": False,
        "adoption": False,
        "acceptance": False,
        "release": False,
        "nativeAcceptance": False,
        "hostedAcceptance": False,
        "adoptionEvidence": False,
        "acceptanceCredit": False,
        "releaseReadiness": False,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "blueprintPath": AUTHORITY_REFERENCE_PATHS[0],
        "foundationPath": AUTHORITY_REFERENCE_PATHS[1],
        "sourceTokens": list(SOURCE_CONTRACT_TOKENS),
        "requiredContractNames": list(REQUIRED_CONTRACT_NAMES),
        "lineage": "REFINED_WITHOUT_LOSS",
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
    }


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    return _sealed(
        {
            "schema": "V23P03C38PartyAccountabilityContractV1",
            "artifact": "V23P03C38PartyAccountabilityContractV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "status": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "schemaArtifact": schema_row,
            "sourceContract": _source_contract(source_rows, authority_rows),
            "requiredSemantics": {
                "partyKinds": list(PARTY_KINDS),
                "siteRoleKinds": list(SITE_ROLE_KINDS),
                "responsibilityKinds": list(RESPONSIBILITY_KINDS),
                "qualificationProvenance": list(QUALIFICATION_PROVENANCE),
                "signoffDispositions": list(SIGNOFF_DISPOSITIONS),
                "signoffMethods": list(SIGNOFF_METHODS),
                "requiredBehaviors": list(REQUIRED_BEHAVIORS),
                "forbiddenClaims": list(FORBIDDEN_CLAIMS),
            },
            "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
            "pathEvidence": {
                "pathFence": list(PATH_FENCE),
                "fullFencePaths": list(FULL_FENCE_PATHS),
                "existingPaths": list(EXISTING_PATHS),
                "newPaths": list(NEW_PATHS),
                "fenceDigest": FENCE_DIGEST,
                "s10FenceOverlapPaths": [],
            },
            "evidenceIDs": list(EVIDENCE_IDS),
            "testMethods": list(TEST_METHODS),
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "evidenceCases": list(EVIDENCE_CASES),
            "sourceArtifacts": source_rows,
            "authorityArtifacts": authority_rows,
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )


def evidence_document(
    source_rows: list[dict[str, Any]],
    authority_rows: list[dict[str, Any]],
    schema_row: dict[str, Any],
    contract_row: dict[str, Any],
) -> dict[str, Any]:
    return _sealed(
        {
            "schema": "V23P03C38PartyAccountabilityEvidenceReceiptV1",
            "artifact": "V23P03C38PartyAccountabilityEvidenceReceiptV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "result": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "sourceContractDigest": sha256_value(source_rows),
            "authorityArtifactDigest": sha256_value(authority_rows),
            "schemaArtifact": schema_row,
            "contractArtifact": contract_row,
            "evidenceIDs": list(EVIDENCE_IDS),
            "testMethods": list(TEST_METHODS),
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "evidenceCases": list(EVIDENCE_CASES),
            "requiredSemanticsDigest": sha256_value(
                {
                    "partyKinds": list(PARTY_KINDS),
                    "siteRoleKinds": list(SITE_ROLE_KINDS),
                    "responsibilityKinds": list(RESPONSIBILITY_KINDS),
                    "qualificationProvenance": list(QUALIFICATION_PROVENANCE),
                    "signoffDispositions": list(SIGNOFF_DISPOSITIONS),
                    "signoffMethods": list(SIGNOFF_METHODS),
                    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
                    "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
                }
            ),
            "pathEvidence": {
                "pathFence": list(PATH_FENCE),
                "fullFencePaths": list(FULL_FENCE_PATHS),
                "pathFenceDigest": FENCE_DIGEST,
                "existingPaths": list(EXISTING_PATHS),
                "newPaths": list(NEW_PATHS),
                "sourceArtifacts": source_rows,
                "authorityArtifacts": authority_rows,
                "s10FenceOverlapPaths": [],
            },
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed(
        {
            "schema": "V23P03C38BrandImpactManifestV1",
            "artifact": "V23P03C38BrandImpactManifestV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "status": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
            "affectedSurfacePaths": [],
            "contractArtifact": contract_row,
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "s10FenceOverlapPaths": [],
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    """Return a deterministic row even while another fence owner is pending."""
    if relative in rendered:
        raw = rendered[relative]
        return {"path": relative, "state": "GENERATED", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    path = root / relative
    if path.is_file():
        raw = path.read_bytes()
        return {"path": relative, "state": "WORKTREE", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if relative in EXISTING_PATHS:
        raw = _git_blob(root, relative)
        return {"path": relative, "state": "BASE_HEAD", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    return {"path": relative, "state": "MISSING_NEW_PATH", "bytes": 0, "sha256": sha256_bytes(b"")}


def all_outputs(root: Path) -> dict[str, bytes]:
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}

    contract = contract_document(root, schema_row)
    contract_raw = pretty(contract)
    contract_row = {"path": CONTRACT_PATH, "bytes": len(contract_raw), "sha256": sha256_bytes(contract_raw)}

    evidence = evidence_document(source_rows, authority_rows, schema_row, contract_row)
    evidence_raw = pretty(evidence)
    evidence_row = {"path": EVIDENCE_PATH, "bytes": len(evidence_raw), "sha256": sha256_bytes(evidence_raw)}

    brand = brand_document(contract_row)
    brand_raw = pretty(brand)
    brand_row = {"path": BRAND_PATH, "bytes": len(brand_raw), "sha256": sha256_bytes(brand_raw)}

    rendered = {
        SCHEMA_PATH: schema_raw,
        CONTRACT_PATH: contract_raw,
        EVIDENCE_PATH: evidence_raw,
        BRAND_PATH: brand_raw,
    }

    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]

    manifest = _sealed(
        {
            "schema": "V23P03C38ToolingManifestV1",
            "artifact": "V23P03C38ToolingManifestV1",
            "cardID": CARD,
            "schemaVersion": SCHEMA_VERSION,
            "result": "PASS_STATIC_PROVISIONAL",
            "verificationMode": "STATIC_ONLY",
            "authority": _authority(),
            "baseHead": BASE_HEAD,
            "baseTree": BASE_TREE,
            "pathFence": list(PATH_FENCE),
            "fullFencePaths": list(FULL_FENCE_PATHS),
            "pathFenceDigest": FENCE_DIGEST,
            "pathFenceCount": len(PATH_FENCE),
            "allowedCreateOrReplacePaths": list(PATH_FENCE),
            "allowedDeletePaths": [],
            "allowedRenamePaths": [],
            "existingPathCount": len(EXISTING_PATHS),
            "newPathCount": len(NEW_PATHS),
            "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS),
            "sourceArtifacts": source_rows,
            "authorityArtifacts": authority_rows,
            "artifacts": manifest_rows,
            "artifactSetDigest": sha256_value(manifest_rows),
            "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
            "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
            "s10FenceOverlapPaths": [],
            "statusFlags": _flags(),
            "requiresAcceptedS10_6Reconciliation": True,
        }
    )
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered
