#!/usr/bin/env python3
"""Deterministic Card 38 kernel-persistence contracts and strict schemas."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C07"
APP_BASE_HEAD = "8dcf404725f5b1f9ab630d2f16e445013efec036"
APP_BASE_TREE = "ba11541ee75791a70012c4daadcac003207483ed"
COORDINATION_HEAD = "bc860cfdcc6324b564e516227fec7ef457983df4"
COORDINATION_TREE = "a8a805cdb206f7d735bb28ce2e910ac5f93ccd85"
COORDINATION_CAS_SEQUENCE = 159
COORDINATION_LEDGER_DIGEST = "21369eb529183399fcc8fcb68a186d1b4882321ab2bd3ce39e08e8f344e3fa34"
CONTEXT_DIGEST = "bdac7237c4ebb9fea666b321f153a4f9fe00ede6c298e69cf93be439c5c5b13d"
FENCE_DIGEST = "3f6a36f8794c159c24c26ec06506bff77a2d998df3cf04a5b8b06bb1d56e8264"
PREREQUISITE_DIGEST = "e1b5c4142e87c5503d4d75d845ab0d2741f49e0eaa4e7e9d5b88c33777398913"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Models/KernelPersistenceV4Contracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelPersistenceV4Schema.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelPersistenceV4Migration.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelRecordRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceAppTests/V9_17KernelPersistenceTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Persistence/V21P03C07KernelPersistenceCorpusV1.json",
]
SCRIPT_PATHS = ["Scripts/v23/p03_c07_contracts.py", "Scripts/v23/generate_p03_c07_contracts.py", "Scripts/v23/verify_p03_c07_contracts.py"]
SCHEMA_PATHS = [
    "Scripts/v23/kernel-persistence-v4.schema.json",
    "Scripts/v23/kernel-record-mapping-registry.schema.json",
    "Scripts/v23/kernel-migration-receipt.schema.json",
    "Scripts/v23/kernel-lifecycle-registry.schema.json",
    "Scripts/v23/kernel-lifecycle-trace.schema.json",
    "Scripts/v23/kernel-persistence-evidence.schema.json",
]
CONTRACT_PATHS = [
    "docs/design/v23/tooling/V23P03C07KernelPersistenceContractV1.json",
    "docs/design/v23/tooling/V23P03C07KernelMappingRegistryContractV1.json",
    "docs/design/v23/tooling/V23P03C07KernelMigrationContractV1.json",
    "docs/design/v23/tooling/V23P03C07KernelLifecycleContractV1.json",
    "docs/design/v23/tooling/V23P03C07KernelPersistenceEvidenceReceiptV1.json",
]
MANIFEST = "docs/design/v23/tooling/V23-P03-C07-tooling-manifest.json"
FIXTURE = SOURCE_PATHS[-1]
GENERATED_PATHS = SCHEMA_PATHS + CONTRACT_PATHS + [MANIFEST]
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
EVIDENCE_IDS = [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]

BASELINE_RECORD_KINDS = [
    "Asset", "DeletionLedgerRow", "EntityMutationRevisionRow", "EvidenceFile", "Issue",
    "MutationQuarantineRow", "MutationReceiptRow", "ObservationAndTimeRow", "Packet",
    "PersistentSchemaReleaseMarker", "Report", "Site", "WorkflowRecord", "WorkspaceMutationStateRow",
]
V4_BOUND_RECORD_KINDS = [
    "CompletedActivitySnapshotV1", "ContentReferenceV1", "ContractSchemaDerivationReceiptV1",
    "ControlledAmendmentSupersessionV1", "OpenJSONSchemaProjectionV1",
]
RECORD_KINDS = sorted(BASELINE_RECORD_KINDS + V4_BOUND_RECORD_KINDS)

RELATIONSHIPS = sorted([
    ("Asset.siteID", "Asset", "Site", "REQUIRED"),
    ("CompletedActivitySnapshotV1.supersedesSnapshotID", "CompletedActivitySnapshotV1", "CompletedActivitySnapshotV1", "OPTIONAL"),
    ("ControlledAmendmentSupersessionV1.originalSnapshotID", "ControlledAmendmentSupersessionV1", "CompletedActivitySnapshotV1", "REQUIRED"),
    ("ControlledAmendmentSupersessionV1.successorSnapshotID", "ControlledAmendmentSupersessionV1", "CompletedActivitySnapshotV1", "REQUIRED"),
    ("EvidenceFile.recordID", "EvidenceFile", "WorkflowRecord", "REQUIRED"),
    ("Issue.assetID", "Issue", "Asset", "REQUIRED"),
    ("Issue.openedByRecordID", "Issue", "WorkflowRecord", "REQUIRED"),
    ("Issue.resolvedByRecordID", "Issue", "WorkflowRecord", "OPTIONAL"),
    ("Packet.currentRecordID", "Packet", "WorkflowRecord", "OPTIONAL"),
    ("Packet.stableRootID", "Packet", "Packet", "REQUIRED"),
    ("Report.packetID", "Report", "Packet", "REQUIRED"),
    ("Report.replacesReportID", "Report", "Report", "OPTIONAL"),
    ("Report.sourceRecordID", "Report", "WorkflowRecord", "REQUIRED"),
    ("WorkflowRecord.assetID", "WorkflowRecord", "Asset", "REQUIRED"),
    ("WorkflowRecord.evidenceSourceRecordID", "WorkflowRecord", "WorkflowRecord", "OPTIONAL"),
    ("WorkflowRecord.issueID", "WorkflowRecord", "Issue", "OPTIONAL"),
    ("WorkflowRecord.packetID", "WorkflowRecord", "Packet", "OPTIONAL"),
    ("WorkflowRecord.parentRecordID", "WorkflowRecord", "WorkflowRecord", "OPTIONAL"),
    ("WorkflowRecord.recordRevisionRootID", "WorkflowRecord", "WorkflowRecord", "OPTIONAL"),
    ("WorkflowRecord.revisesRecordID", "WorkflowRecord", "WorkflowRecord", "OPTIONAL"),
], key=lambda row: row[0])

MIGRATION_STAGES = [
    "STAGING", "STAGED", "VALIDATING", "VALIDATED", "ACTIVE", "DISCARDED", "FORWARD_FIX_REQUIRED",
]
LIFECYCLE_OPERATIONS = [
    "ARCHIVE", "BACKUP", "CLONE", "DELETE", "ERASE", "EXPORT", "FORK", "JOURNAL_REPLAY",
    "ORPHAN_CLEANUP", "RESTORE", "SEARCH_REBUILD",
]
LIFECYCLE_REQUIREMENTS = sorted([
    "ARCHIVE", "BACKUP", "CANONICAL_MUTATION", "CLASSIFICATION", "CLONE", "CONFLICT_POLICY",
    "CONTROLLED_AMENDMENT", "DELETE", "ERASE", "EXPORT", "FORK", "MUTATION_ENVELOPE",
    "MUTATION_RECEIPT", "ORPHAN_CLEANUP", "READ_RECOVERY", "REBUILD", "REPLAY",
    "REPLICATION_POLICY", "RESTORE", "SEARCH", "SYNC_CLASSIFICATION", "WRITER_REGISTRATION",
])
MIGRATION_FAILURE_CASES = [
    "DOWNGRADE_AFTER_WRITE", "FUTURE_VERSION", "MIGRATION_INTERRUPTION", "OLD_BINARY_OPEN",
    "UNKNOWN_RECORD_KIND", "UNMAPPED_RELATIONSHIP",
]
LIFECYCLE_FAILURE_CASES = [
    "ARCHIVE_OMISSION", "DELETE_ERASE_LEAK", "OLD_ARCHIVE_RESURRECTION", "ORPHAN_REMAINS",
    "UNKNOWN_RECORD_KIND", "UNMAPPED_RELATIONSHIP",
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
    return {"appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE, "coordinationHead": COORDINATION_HEAD,
            "coordinationTree": COORDINATION_TREE, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
            "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "contextDigest": CONTEXT_DIGEST,
            "fenceDigest": FENCE_DIGEST, "prerequisiteDigest": PREREQUISITE_DIGEST,
            "s10ReservationDigest": S10_RESERVATION_DIGEST}


def record_descriptors() -> list[dict[str, Any]]:
    declaration = {"OpenJSONSchemaProjectionV1"}
    immutable = {"CompletedActivitySnapshotV1", "ContentReferenceV1"}
    receipt = {"ContractSchemaDerivationReceiptV1", "ControlledAmendmentSupersessionV1", "DeletionLedgerRow",
               "EntityMutationRevisionRow", "MutationReceiptRow"}
    operational = {"MutationQuarantineRow", "PersistentSchemaReleaseMarker", "WorkspaceMutationStateRow"}
    records = []
    for kind in RECORD_KINDS:
        if kind in declaration:
            classification = "DORMANT_CONTRACT_DECLARATION"
        elif kind in immutable:
            classification = "IMMUTABLE_CONTENT_METADATA"
        elif kind in receipt:
            classification = "APPEND_ONLY_RECEIPT"
        elif kind in operational:
            classification = "RECOVERY_JOURNAL" if kind == "MutationQuarantineRow" else "DEVICE_LOCAL_OPERATIONAL"
        else:
            classification = "CANONICAL_WORKSPACE"
        if kind in {"Site", "ContractSchemaDerivationReceiptV1", "OpenJSONSchemaProjectionV1"}:
            delete_rule = "PRESERVE_UNLESS_EXPLICIT"
        elif kind == "Asset": delete_rule = "DELETE_AFTER_DEPENDENTS"
        elif kind == "Packet": delete_rule = "TOMBSTONE_WHEN_COUNTED"
        elif kind == "DeletionLedgerRow": delete_rule = "APPEND_ERASE_ONLY"
        elif kind in {"EntityMutationRevisionRow", "MutationQuarantineRow", "MutationReceiptRow",
                      "PersistentSchemaReleaseMarker", "WorkspaceMutationStateRow"}: delete_rule = "CLEAR_ON_ERASE"
        else: delete_rule = "DELETE_WITH_OWNER"
        records.append({
            "kind": kind, "classification": classification, "deleteRule": delete_rule,
            "requirements": LIFECYCLE_REQUIREMENTS,
            "canonicalMutationEffectID": "kernel-v4-effect-" + kind.lower(),
            "contentReferenceMapped": kind in {"CompletedActivitySnapshotV1", "EvidenceFile", "ContentReferenceV1"},
            "controlledAmendmentMapped": kind in {"CompletedActivitySnapshotV1", "ControlledAmendmentSupersessionV1", "Report"},
        })
    return records


def relationship_descriptors() -> list[dict[str, Any]]:
    delete_rules = {
        "Asset.siteID": "DELETE_AFTER_DEPENDENTS", "EvidenceFile.recordID": "DELETE_WITH_OWNER",
        "Issue.assetID": "DELETE_WITH_OWNER", "Report.packetID": "DELETE_WITH_OWNER",
        "WorkflowRecord.assetID": "DELETE_WITH_OWNER",
    }
    return [{"kind": f"{source}.{rid.split('.', 1)[1]}->{target}", "source": source,
             "fieldName": rid.split('.', 1)[1], "target": target, "optional": cardinality == "OPTIONAL",
             "scalarUUID": True, "deleteRule": delete_rules.get(rid, "PRESERVE_UNLESS_EXPLICIT")}
            for rid, source, target, cardinality in RELATIONSHIPS]


def mapping_registry() -> dict[str, Any]:
    values = {
        "CANONICAL_WORKSPACE": ("WORKSPACE_TRANSACTION", "REPLICATED_CANONICAL", "EXACT_REVISION_MANUAL", "BOUNDED_CANONICAL_FIELDS",
            "CANONICAL_SOURCE", "CANONICAL_MUTATION_ENVELOPE", "IDEMPOTENT_CANONICAL_MUTATION", "CANONICAL_PORTABLE"),
        "IMMUTABLE_CONTENT_METADATA": ("IMMUTABLE_CONTENT_WRITER", "IMMUTABLE_CONTENT", "IMMUTABLE_IDENTITY", "BOUNDED_CANONICAL_FIELDS",
            "CANONICAL_SOURCE", "NOT_APPLICABLE", "IMMUTABLE_HISTORY", "IMMUTABLE_HISTORY_PORTABLE"),
        "APPEND_ONLY_RECEIPT": ("APPEND_ONLY_RECEIPT_WRITER", "APPEND_ONLY_HISTORY", "STABLE_ID_APPEND_UNION", "EXCLUDED",
            "CANONICAL_SOURCE", "IMMUTABLE_EFFECT_RECEIPT", "IMMUTABLE_HISTORY", "IMMUTABLE_HISTORY_PORTABLE"),
        "DEVICE_LOCAL_OPERATIONAL": ("DEVICE_LOCAL_OPERATIONAL_WRITER", "LOCAL_ONLY", "LOCAL_AUTHORITY", "EXCLUDED",
            "CANONICAL_SOURCE", "NOT_APPLICABLE", "NOT_APPLICABLE", "EXCLUDED"),
        "RECOVERY_JOURNAL": ("RECOVERY_JOURNAL_WRITER", "RECOVERY_ONLY", "RECOVERY_STATE_MACHINE", "EXCLUDED",
            "REPLAY_JOURNAL", "OPERATION_RECOVERY", "RECOVERY_STATE_MACHINE", "EXCLUDED"),
        "DORMANT_CONTRACT_DECLARATION": ("DORMANT_CONTRACT_WRITER", "EXCLUDED_DORMANT", "NOT_APPLICABLE", "EXCLUDED",
            "REBUILD_FROM_CANONICAL_DEPENDENCIES", "NOT_APPLICABLE", "REBUILD_PROJECTION", "READ_ONLY_CONTRACT_PROJECTION"),
    }
    record_registrations = []
    mutation_registrations = []
    effect_dispositions = {"CANONICAL_WORKSPACE": "CANONICAL_WORKSPACE_EFFECT",
        "IMMUTABLE_CONTENT_METADATA": "IMMUTABLE_APPEND_EFFECT", "APPEND_ONLY_RECEIPT": "APPEND_ONLY_RECEIPT_EFFECT",
        "DEVICE_LOCAL_OPERATIONAL": "LOCAL_OPERATIONAL_EFFECT", "RECOVERY_JOURNAL": "RECOVERY_JOURNAL_EFFECT",
        "DORMANT_CONTRACT_DECLARATION": "DORMANT_NO_RUNTIME_EFFECT"}
    for descriptor in record_descriptors():
        writer, sync, conflict, search, rebuild, journal, replay, export = values[descriptor["classification"]]
        record_registrations.append({"descriptor": descriptor, "writer": writer, "syncClassification": sync,
            "replication": "EXCLUDED_NO_TRANSPORT", "conflict": conflict, "search": search, "rebuild": rebuild,
            "journal": journal, "replay": replay, "openExport": export})
        mutation_registrations.append({"kind": descriptor["kind"], "mutationEnvelopeTypeID": "MutationEnvelopeV1",
            "effectID": descriptor["canonicalMutationEffectID"],
            "effectDisposition": effect_dispositions[descriptor["classification"]],
            "receiptTypeID": "KernelMutationReceiptV4", "expectedRevisionRequired": True,
            "durableReceiptRequired": True, "effectBeforeReceiptRecovery": True})
    relationships = relationship_descriptors()
    registry_material = {"recordRegistrations": record_registrations,
                         "mutationRegistrations": mutation_registrations,
                         "relationships": relationships}
    return {"schemaVersion": 1, "registryID": "kernel-record-mapping-registry-v4", "registryVersion": 4,
            "schemaID": "KERNEL_PERSISTENCE_V4", "closedWorld": True, "unknownKindDisposition": "REJECT",
            **registry_material,
            "recordRegistryCanonicalDigest": digest(canonical(record_registrations)),
            "mutationRegistryCanonicalDigest": digest(canonical(mutation_registrations)),
            "canonicalDigest": digest(canonical(registry_material))}


def migration_plan() -> dict[str, Any]:
    transitions = ["STAGING->STAGED", "STAGED->VALIDATING", "VALIDATING->VALIDATED", "VALIDATED->ACTIVE",
                   "PREACTIVATION->DISCARDED", "ACTIVE_WITH_PUBLICATION_OR_WRITE->FORWARD_FIX_REQUIRED"]
    return {"schemaVersion": 1, "migrationID": "kernel-persistence-v3-to-v4", "sourceSchemaVersion": 3,
            "targetSchemaVersion": 4, "staged": True, "atomicActivation": True,
            "unknownRecordDisposition": "REJECT", "duplicateRecordDisposition": "REJECT",
            "preActivationRollback": "DISCARD_STAGING", "postWriteRecovery": "FORWARD_FIX_READ_EXPORT_ONLY",
            "phases": MIGRATION_STAGES, "transitions": transitions}


def migration_receipt() -> dict[str, Any]:
    zero = digest(b"")
    staged = [{"kind": kind, "sourceCount": 0, "stagedCount": 0, "batchDigest": zero} for kind in RECORD_KINDS]
    material = {"migrationID": "kernel-persistence-v3-to-v4", "sourceSchemaVersion": 3, "targetSchemaVersion": 4,
                "sourceStoreDigest": zero, "phase": "VALIDATED", "stagedRecords": staged,
                "stagedRelationshipKinds": [row["kind"] for row in relationship_descriptors()],
                "stagingDigest": zero, "schemaDescriptorDigest": persistence_descriptor()["descriptorDigest"],
                "archiveManifestDigest": zero, "exportManifestDigest": zero,
                "published": False, "canonicalV4WriteObserved": False}
    return {"checkpointID": digest(canonical(material)), **material}


def lifecycle_registry() -> dict[str, Any]:
    registrations = mapping_registry()["recordRegistrations"]
    backup_routes = {
        "CANONICAL_WORKSPACE": ("INCLUDE_CANONICAL", "REPLACE_CANONICAL", "REBIND_WORKSPACE", "REBIND_WORKSPACE_AND_LINEAGE", "CANONICAL_PORTABLE"),
        "IMMUTABLE_CONTENT_METADATA": ("INCLUDE_IMMUTABLE_HISTORY", "RESTORE_IMMUTABLE_IDENTITY", "REBIND_WORKSPACE", "REBIND_WORKSPACE_AND_LINEAGE", "IMMUTABLE_HISTORY_PORTABLE"),
        "APPEND_ONLY_RECEIPT": ("INCLUDE_IMMUTABLE_HISTORY", "RESTORE_APPEND_ONLY_HISTORY", "PRESERVE", "PRESERVE", "IMMUTABLE_HISTORY_PORTABLE"),
        "DEVICE_LOCAL_OPERATIONAL": ("INCLUDE_OPERATIONAL_CHECKPOINT", "RESET_LOCAL_OPERATIONAL", "REGENERATE_LOCAL", "REGENERATE_LOCAL", "EXCLUDED"),
        "RECOVERY_JOURNAL": ("INCLUDE_OPERATIONAL_CHECKPOINT", "REPLAY_RECOVERY_CHECKPOINT", "REGENERATE_LOCAL", "REGENERATE_LOCAL", "EXCLUDED"),
        "DORMANT_CONTRACT_DECLARATION": ("EXCLUDE_DORMANT_DECLARATION", "REBUILD_CONTRACT_PROJECTION", "NOT_APPLICABLE", "NOT_APPLICABLE", "READ_ONLY_CONTRACT_PROJECTION"),
    }
    delete_map = {"PRESERVE_UNLESS_EXPLICIT": "EXPLICIT_ONLY", "DELETE_AFTER_DEPENDENTS": "DELETE_AFTER_DEPENDENTS",
        "DELETE_WITH_OWNER": "DELETE_WITH_OWNER", "TOMBSTONE_WHEN_COUNTED": "TOMBSTONE_PRESERVING_HISTORY",
        "APPEND_ERASE_ONLY": "PRESERVE_UNTIL_ERASE", "CLEAR_ON_ERASE": "PRESERVE_UNTIL_ERASE"}
    erase_map = {"CANONICAL_WORKSPACE": "CLEAR_CANONICAL_AND_HISTORY", "IMMUTABLE_CONTENT_METADATA": "CLEAR_CANONICAL_AND_HISTORY",
        "APPEND_ONLY_RECEIPT": "CLEAR_CANONICAL_AND_HISTORY", "DEVICE_LOCAL_OPERATIONAL": "CLEAR_LOCAL_OPERATIONAL_STATE",
        "RECOVERY_JOURNAL": "CLEAR_RECOVERY_STATE", "DORMANT_CONTRACT_DECLARATION": "REBUILD_EMPTY_PROJECTION"}
    entries = []
    for registration in registrations:
        descriptor = registration["descriptor"]; kind = descriptor["kind"]; classification = descriptor["classification"]
        archive, restore, clone, fork, export = backup_routes[classification]
        orphan = "REMOVE_OWNED_BYTES_WHEN_UNREFERENCED" if kind in {"ContentReferenceV1", "EvidenceFile"} else (
            "REMOVE_DERIVED_PROJECTION" if classification == "DORMANT_CONTRACT_DECLARATION" else "PRESERVE_CANONICAL_RECORD")
        has_tombstone = descriptor["deleteRule"] in {"TOMBSTONE_WHEN_COUNTED", "APPEND_ERASE_ONLY"}
        entries.append({"kind": kind, "archive": archive, "backup": archive, "restore": restore, "clone": clone,
            "fork": fork, "openExport": export, "deleteRule": descriptor["deleteRule"],
            "deletion": delete_map[descriptor["deleteRule"]], "orphanCleanup": orphan,
            "erase": erase_map[classification], "clearsTombstonesOnDelete": False,
            "clearsTombstonesOnErase": has_tombstone, "search": registration["search"],
            "rebuild": registration["rebuild"], "journal": registration["journal"], "replay": registration["replay"],
            "interruption": "SAME_COMPLETE_EFFECT_AND_RECEIPT_OR_NO_EFFECT"})
    return {"schemaVersion": 1, "registryID": "kernel-lifecycle-registry-v4", "registryVersion": 4,
            "schemaID": "KERNEL_PERSISTENCE_V4", "recordKindCount": len(entries), "entries": entries,
            "backupArchiveRestoreComplete": True, "deleteEraseComplete": True, "openExportComplete": True,
            "searchRebuildReplayComplete": True}


def lifecycle_trace() -> dict[str, Any]:
    events = []
    sequence = 0
    for operation in LIFECYCLE_OPERATIONS:
        for kind in RECORD_KINDS:
            events.append({"sequence": sequence, "operation": operation, "kindID": kind,
                           "disposition": "STATIC_DECLARED", "idempotencyKey": f"{operation.lower()}.{kind}"})
            sequence += 1
    return {"schemaVersion": 1, "traceID": "kernel-lifecycle-static-trace-v4", "schemaID": "KERNEL_PERSISTENCE_V4",
            "operations": LIFECYCLE_OPERATIONS, "events": events, "result": "STATIC_DECLARED",
            "nativeExecutionRan": False, "hostedExecutionRan": False}


def persistence_descriptor() -> dict[str, Any]:
    records = record_descriptors(); relationships = relationship_descriptors()
    material = {"schemaID": "KERNEL_PERSISTENCE_V4", "schemaVersion": 4, "predecessorSchemaVersion": 3,
                "runtimePosture": "DORMANT_STATIC_UNTIL_S10_6", "integrationOwner": "V23-P10-C06",
                "records": records, "relationships": relationships, "migrationRequired": True,
                "backupRestoreRequired": True, "deleteEraseRequired": True, "exportRequired": True,
                "activationEnabled": False}
    return {**material, "descriptorDigest": digest(canonical(material))}


def strict_object(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties,
            "required": sorted(properties) if required is None else sorted(required)}


def text(maximum: int = 256) -> dict[str, Any]:
    return {"type": "string", "minLength": 1, "maxLength": maximum,
            "pattern": r"^[^\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069\ufffe\uffff]*$",
            "x_assetrounds_maximumUTF8Bytes": maximum, "x_assetrounds_requiresNFC": True,
            "x_assetrounds_noncharacterPolicy": "REJECT_ALL_UNICODE_NONCHARACTERS"}


def enum_shape(values: list[str]) -> dict[str, Any]:
    return {"type": "string", "enum": values}


def array(items: dict[str, Any], maximum: int, *, minimum: int = 0, unique: bool = False) -> dict[str, Any]:
    value: dict[str, Any] = {"type": "array", "minItems": minimum, "maxItems": maximum, "items": items}
    if unique: value["uniqueItems"] = True
    return value


def schema_root(title: str, slug: str, shape: dict[str, Any], defs: dict[str, Any] | None = None) -> dict[str, Any]:
    result = dict(shape)
    result.update({"$schema": "https://json-schema.org/draft/2020-12/schema",
                   "$id": f"https://schemas.assetrounds.local/v23/p03/c07/{slug}/v1", "title": title,
                   "x_assetrounds_cardID": CARD, "x_assetrounds_staticOnly": True})
    if defs: result["$defs"] = defs
    return result


def schema_shapes() -> dict[str, dict[str, Any]]:
    sha = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    record_kind = enum_shape(RECORD_KINDS)
    relationship = strict_object({"kind": enum_shape([row[0].split(".", 1)[0] + "." + row[0].split(".", 1)[1] + "->" + row[2] for row in RELATIONSHIPS]),
        "source": record_kind, "fieldName": text(160), "target": record_kind, "optional": {"type": "boolean"},
        "scalarUUID": {"const": True}, "deleteRule": enum_shape(["DELETE_AFTER_DEPENDENTS", "DELETE_WITH_OWNER", "PRESERVE_UNLESS_EXPLICIT"])})
    record = strict_object({"kind": record_kind,
        "classification": enum_shape(["APPEND_ONLY_RECEIPT", "CANONICAL_WORKSPACE", "DEVICE_LOCAL_OPERATIONAL",
            "DORMANT_CONTRACT_DECLARATION", "IMMUTABLE_CONTENT_METADATA", "RECOVERY_JOURNAL"]),
        "deleteRule": enum_shape(["APPEND_ERASE_ONLY", "CLEAR_ON_ERASE", "DELETE_AFTER_DEPENDENTS", "DELETE_WITH_OWNER",
            "PRESERVE_UNLESS_EXPLICIT", "TOMBSTONE_WHEN_COUNTED"]),
        "requirements": {"const": LIFECYCLE_REQUIREMENTS}, "canonicalMutationEffectID": text(160),
        "contentReferenceMapped": {"type": "boolean"}, "controlledAmendmentMapped": {"type": "boolean"}})
    mutation_registration = strict_object({"kind": record_kind, "mutationEnvelopeTypeID": {"const": "MutationEnvelopeV1"},
        "effectID": text(160), "effectDisposition": enum_shape(["APPEND_ONLY_RECEIPT_EFFECT", "CANONICAL_WORKSPACE_EFFECT",
            "DORMANT_NO_RUNTIME_EFFECT", "IMMUTABLE_APPEND_EFFECT", "LOCAL_OPERATIONAL_EFFECT", "RECOVERY_JOURNAL_EFFECT"]),
        "receiptTypeID": {"const": "KernelMutationReceiptV4"}, "expectedRevisionRequired": {"const": True},
        "durableReceiptRequired": {"const": True}, "effectBeforeReceiptRecovery": {"const": True}})
    record_registration = strict_object({"descriptor": {"$ref": "#/$defs/record"},
        "writer": enum_shape(["APPEND_ONLY_RECEIPT_WRITER", "DEVICE_LOCAL_OPERATIONAL_WRITER", "DORMANT_CONTRACT_WRITER",
            "IMMUTABLE_CONTENT_WRITER", "RECOVERY_JOURNAL_WRITER", "WORKSPACE_TRANSACTION"]),
        "syncClassification": enum_shape(["APPEND_ONLY_HISTORY", "EXCLUDED_DORMANT", "IMMUTABLE_CONTENT", "LOCAL_ONLY",
            "RECOVERY_ONLY", "REPLICATED_CANONICAL"]), "replication": {"const": "EXCLUDED_NO_TRANSPORT"},
        "conflict": enum_shape(["EXACT_REVISION_MANUAL", "IMMUTABLE_IDENTITY", "LOCAL_AUTHORITY", "NOT_APPLICABLE",
            "RECOVERY_STATE_MACHINE", "STABLE_ID_APPEND_UNION"]),
        "search": enum_shape(["BOUNDED_CANONICAL_FIELDS", "EXCLUDED"]),
        "rebuild": enum_shape(["CANONICAL_SOURCE", "NOT_APPLICABLE", "REBUILD_FROM_CANONICAL_DEPENDENCIES", "REPLAY_JOURNAL"]),
        "journal": enum_shape(["CANONICAL_MUTATION_ENVELOPE", "IMMUTABLE_EFFECT_RECEIPT", "NOT_APPLICABLE", "OPERATION_RECOVERY"]),
        "replay": enum_shape(["IDEMPOTENT_CANONICAL_MUTATION", "IMMUTABLE_HISTORY", "NOT_APPLICABLE", "REBUILD_PROJECTION", "RECOVERY_STATE_MACHINE"]),
        "openExport": enum_shape(["CANONICAL_PORTABLE", "EXCLUDED", "IMMUTABLE_HISTORY_PORTABLE", "READ_ONLY_CONTRACT_PROJECTION"] )})
    mapping_shape = strict_object({"schemaVersion": {"const": 1}, "registryID": {"const": "kernel-record-mapping-registry-v4"},
        "registryVersion": {"const": 4}, "schemaID": {"const": "KERNEL_PERSISTENCE_V4"}, "closedWorld": {"const": True},
        "unknownKindDisposition": {"const": "REJECT"},
        "recordRegistrations": array({"$ref": "#/$defs/recordRegistration"}, len(RECORD_KINDS), minimum=len(RECORD_KINDS), unique=True),
        "mutationRegistrations": array({"$ref": "#/$defs/mutationRegistration"}, len(RECORD_KINDS), minimum=len(RECORD_KINDS), unique=True),
        "relationships": array({"$ref": "#/$defs/relationship"}, len(RELATIONSHIPS), minimum=len(RELATIONSHIPS), unique=True),
        "recordRegistryCanonicalDigest": sha, "mutationRegistryCanonicalDigest": sha, "canonicalDigest": sha})
    mapping_schema = schema_root("KernelRecordMappingRegistryV4", "kernel-record-mapping-registry", mapping_shape,
                                 {"record": record, "relationship": relationship, "mutationRegistration": mutation_registration,
                                  "recordRegistration": record_registration})
    staged_record = strict_object({"kind": record_kind, "sourceCount": {"type": "integer", "minimum": 0},
        "stagedCount": {"type": "integer", "minimum": 0}, "batchDigest": sha})
    plan = strict_object({"schemaVersion": {"const": 1}, "migrationID": {"const": "kernel-persistence-v3-to-v4"},
        "sourceSchemaVersion": {"const": 3}, "targetSchemaVersion": {"const": 4},
        "staged": {"const": True}, "atomicActivation": {"const": True}, "unknownRecordDisposition": {"const": "REJECT"},
        "duplicateRecordDisposition": {"const": "REJECT"}, "preActivationRollback": {"const": "DISCARD_STAGING"},
        "postWriteRecovery": {"const": "FORWARD_FIX_READ_EXPORT_ONLY"},
        "phases": {"const": MIGRATION_STAGES}, "transitions": array(text(), 6, minimum=6, unique=True)})
    receipt_properties = {"checkpointID": sha, "migrationID": text(160), "sourceSchemaVersion": {"const": 3},
        "targetSchemaVersion": {"const": 4}, "sourceStoreDigest": sha, "phase": enum_shape(MIGRATION_STAGES),
        "stagedRecords": array({"$ref": "#/$defs/stagedRecord"}, len(RECORD_KINDS), unique=True),
        "stagedRelationshipKinds": array(enum_shape([row["kind"] for row in relationship_descriptors()]), len(RELATIONSHIPS), unique=True),
        "stagingDigest": sha, "schemaDescriptorDigest": sha, "archiveManifestDigest": sha, "exportManifestDigest": sha,
        "published": {"type": "boolean"}, "canonicalV4WriteObserved": {"type": "boolean"}}
    receipt = strict_object(receipt_properties, [key for key in receipt_properties if key not in
        {"stagingDigest", "schemaDescriptorDigest", "archiveManifestDigest", "exportManifestDigest"}])
    receipt["allOf"] = [{"if": {"properties": {"phase": {"const": "VALIDATED"}}, "required": ["phase"]},
        "then": {"required": ["stagingDigest", "schemaDescriptorDigest", "archiveManifestDigest", "exportManifestDigest"],
                 "properties": {"published": {"const": False}, "canonicalV4WriteObserved": {"const": False}}}}]
    migration_schema = schema_root("KernelMigrationReceiptV4", "kernel-migration-receipt", receipt,
                                   {"stagedRecord": staged_record, "migrationPlan": plan})
    lifecycle_entry = strict_object({"kind": record_kind,
        "archive": enum_shape(["EXCLUDE_DORMANT_DECLARATION", "INCLUDE_CANONICAL", "INCLUDE_IMMUTABLE_HISTORY", "INCLUDE_OPERATIONAL_CHECKPOINT"]),
        "backup": enum_shape(["EXCLUDE_DORMANT_DECLARATION", "INCLUDE_CANONICAL", "INCLUDE_IMMUTABLE_HISTORY", "INCLUDE_OPERATIONAL_CHECKPOINT"]),
        "restore": enum_shape(["REBUILD_CONTRACT_PROJECTION", "REPLACE_CANONICAL", "REPLAY_RECOVERY_CHECKPOINT",
            "RESET_LOCAL_OPERATIONAL", "RESTORE_APPEND_ONLY_HISTORY", "RESTORE_IMMUTABLE_IDENTITY"]),
        "clone": enum_shape(["NOT_APPLICABLE", "PRESERVE", "REBIND_WORKSPACE", "REGENERATE_LOCAL"]),
        "fork": enum_shape(["NOT_APPLICABLE", "PRESERVE", "REBIND_WORKSPACE_AND_LINEAGE", "REGENERATE_LOCAL"]),
        "openExport": enum_shape(["CANONICAL_PORTABLE", "EXCLUDED", "IMMUTABLE_HISTORY_PORTABLE", "READ_ONLY_CONTRACT_PROJECTION"]),
        "deleteRule": enum_shape(["APPEND_ERASE_ONLY", "CLEAR_ON_ERASE", "DELETE_AFTER_DEPENDENTS", "DELETE_WITH_OWNER",
            "PRESERVE_UNLESS_EXPLICIT", "TOMBSTONE_WHEN_COUNTED"]),
        "deletion": enum_shape(["DELETE_AFTER_DEPENDENTS", "DELETE_WITH_OWNER", "EXPLICIT_ONLY", "PRESERVE_UNTIL_ERASE", "TOMBSTONE_PRESERVING_HISTORY"]),
        "orphanCleanup": enum_shape(["PRESERVE_CANONICAL_RECORD", "REMOVE_DERIVED_PROJECTION", "REMOVE_OWNED_BYTES_WHEN_UNREFERENCED"]),
        "erase": enum_shape(["CLEAR_CANONICAL_AND_HISTORY", "CLEAR_LOCAL_OPERATIONAL_STATE", "CLEAR_RECOVERY_STATE", "REBUILD_EMPTY_PROJECTION"]),
        "clearsTombstonesOnDelete": {"const": False}, "clearsTombstonesOnErase": {"type": "boolean"},
        "search": enum_shape(["BOUNDED_CANONICAL_FIELDS", "EXCLUDED"]),
        "rebuild": enum_shape(["CANONICAL_SOURCE", "NOT_APPLICABLE", "REBUILD_FROM_CANONICAL_DEPENDENCIES", "REPLAY_JOURNAL"]),
        "journal": enum_shape(["CANONICAL_MUTATION_ENVELOPE", "IMMUTABLE_EFFECT_RECEIPT", "NOT_APPLICABLE", "OPERATION_RECOVERY"]),
        "replay": enum_shape(["IDEMPOTENT_CANONICAL_MUTATION", "IMMUTABLE_HISTORY", "NOT_APPLICABLE", "REBUILD_PROJECTION", "RECOVERY_STATE_MACHINE"]),
        "interruption": {"const": "SAME_COMPLETE_EFFECT_AND_RECEIPT_OR_NO_EFFECT"}})
    lifecycle_shape = strict_object({"schemaVersion": {"const": 1}, "registryID": {"const": "kernel-lifecycle-registry-v4"},
        "registryVersion": {"const": 4}, "schemaID": {"const": "KERNEL_PERSISTENCE_V4"},
        "recordKindCount": {"const": len(RECORD_KINDS)},
        "entries": array({"$ref": "#/$defs/entry"}, len(RECORD_KINDS), minimum=len(RECORD_KINDS), unique=True),
        "backupArchiveRestoreComplete": {"const": True}, "deleteEraseComplete": {"const": True},
        "openExportComplete": {"const": True}, "searchRebuildReplayComplete": {"const": True}})
    lifecycle_schema = schema_root("KernelLifecycleRegistryV4", "kernel-lifecycle-registry", lifecycle_shape,
                                   {"entry": lifecycle_entry})
    trace_event = strict_object({"sequence": {"type": "integer", "minimum": 0}, "operation": enum_shape(LIFECYCLE_OPERATIONS),
        "kindID": record_kind, "disposition": {"const": "STATIC_DECLARED"}, "idempotencyKey": text()})
    trace_shape = strict_object({"schemaVersion": {"const": 1}, "traceID": text(), "schemaID": {"const": "KERNEL_PERSISTENCE_V4"},
        "operations": {"const": LIFECYCLE_OPERATIONS},
        "events": array({"$ref": "#/$defs/event"}, len(RECORD_KINDS)*len(LIFECYCLE_OPERATIONS), minimum=len(RECORD_KINDS)*len(LIFECYCLE_OPERATIONS), unique=True),
        "result": {"const": "STATIC_DECLARED"}, "nativeExecutionRan": {"const": False}, "hostedExecutionRan": {"const": False}})
    trace_schema = schema_root("KernelLifecycleTraceV4", "kernel-lifecycle-trace", trace_shape, {"event": trace_event})
    descriptor_shape = strict_object({"schemaID": {"const": "KERNEL_PERSISTENCE_V4"}, "schemaVersion": {"const": 4},
        "predecessorSchemaVersion": {"const": 3}, "runtimePosture": {"const": "DORMANT_STATIC_UNTIL_S10_6"},
        "integrationOwner": {"const": "V23-P10-C06"},
        "records": array({"$ref": "#/$defs/record"}, len(RECORD_KINDS), minimum=len(RECORD_KINDS), unique=True),
        "relationships": array({"$ref": "#/$defs/relationship"}, len(RELATIONSHIPS), minimum=len(RELATIONSHIPS), unique=True),
        "migrationRequired": {"const": True}, "backupRestoreRequired": {"const": True},
        "deleteEraseRequired": {"const": True}, "exportRequired": {"const": True},
        "activationEnabled": {"const": False}, "descriptorDigest": sha})
    descriptor_schema = schema_root("KernelPersistenceV4", "kernel-persistence-v4", descriptor_shape,
                                    {"record": record, "relationship": relationship,
                                     "mutationRegistration": mutation_registration,
                                     "recordRegistration": record_registration, "mappingRegistry": mapping_shape,
                                     "stagedRecord": staged_record, "migrationPlan": plan, "entry": lifecycle_entry,
                                     "lifecycleRegistry": lifecycle_shape})
    artifact = strict_object({"path": text(512), "sha256": sha})
    evidence_shape = strict_object({"schemaVersion": {"const": 1}, "receiptID": {"const": "v23-p03-c07-static-receipt"},
        "cardID": {"const": CARD}, "fixtureSHA256": sha, "sourceArtifacts": array(artifact, 9, minimum=9, unique=True),
        "evidenceIDs": {"const": EVIDENCE_IDS}, "result": {"const": "PASS"}, "verificationMode": {"const": "STATIC_ONLY"},
        "nativeCompileRan": {"const": False}, "hostedDispatchRan": {"const": False}, "hostedDispatchEnabled": {"const": False},
        "adoptionEnabled": {"const": False}, "acceptanceEnabled": {"const": False}, "acceptanceCredit": {"const": False},
        "releaseReady": {"const": False}, "releaseCredit": {"const": False},
        "requiresAcceptedS10_6Reconciliation": {"const": True}})
    evidence_schema = schema_root("V23P03C07KernelPersistenceEvidenceReceiptV1", "kernel-persistence-evidence", evidence_shape)
    return dict(zip(SCHEMA_PATHS, [descriptor_schema, mapping_schema, migration_schema, lifecycle_schema, trace_schema, evidence_schema]))


def base_document(schema: str) -> dict[str, Any]:
    return {"schema": schema, "schemaVersion": 1, "cardID": CARD, "authority": authority(),
            "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "KERNEL_PERSISTENCE_V4",
            "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION", "verificationMode": "STATIC_ONLY",
            "nativeCompileRan": False, "hostedDispatchRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False,
            "acceptanceEnabled": False, "acceptanceCredit": False, "releaseReady": False, "releaseCredit": False,
            "requiresAcceptedS10_6Reconciliation": True}


def seal(document: dict[str, Any]) -> dict[str, Any]:
    result = dict(document); result["artifactDigest"] = digest(pretty(result)); return result


def contract_documents(root: Path) -> dict[str, dict[str, Any]]:
    missing = [path for path in SOURCE_PATHS if not (root / path).is_file()]
    if missing: raise ContractError(f"source artifacts not ready for sealing: {missing}")
    fixture_bytes = (root / FIXTURE).read_bytes()
    persistence = base_document("V23P03C07KernelPersistenceContractV1")
    persistence.update({"descriptor": persistence_descriptor(), "recordKinds": RECORD_KINDS,
                        "invariants": ["CLOSED_RECORD_AND_RELATIONSHIP_WORLD", "V3_TO_V4_STAGED_ATOMIC_ACTIVATION",
                            "OLD_BINARY_REJECTS_V4", "FUTURE_VERSION_REJECTED", "NO_GENERIC_EAV_OR_BLOB_ESCAPE"]})
    mapping = base_document("V23P03C07KernelMappingRegistryContractV1")
    mapping.update({"registry": mapping_registry(), "writerRegistryComplete": True, "syncRegistryComplete": True,
                    "replicationRegistryComplete": True, "conflictRegistryComplete": True, "mutationReceiptRegistryComplete": True})
    migration = base_document("V23P03C07KernelMigrationContractV1")
    migration.update({"plan": migration_plan(), "staticReceipt": migration_receipt(),
                      "failureCases": MIGRATION_FAILURE_CASES})
    lifecycle = base_document("V23P03C07KernelLifecycleContractV1")
    lifecycle.update({"registry": lifecycle_registry(), "trace": lifecycle_trace(),
                      "failureCases": LIFECYCLE_FAILURE_CASES})
    evidence = {"schemaVersion": 1, "receiptID": "v23-p03-c07-static-receipt", "cardID": CARD,
                "fixtureSHA256": digest(fixture_bytes),
                "sourceArtifacts": [{"path": path, "sha256": digest((root / path).read_bytes())} for path in SOURCE_PATHS],
                "evidenceIDs": EVIDENCE_IDS, "result": "PASS", "verificationMode": "STATIC_ONLY",
                "nativeCompileRan": False, "hostedDispatchRan": False, "hostedDispatchEnabled": False,
                "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
                "releaseReady": False, "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True}
    return {CONTRACT_PATHS[0]: seal(persistence), CONTRACT_PATHS[1]: seal(mapping), CONTRACT_PATHS[2]: seal(migration),
            CONTRACT_PATHS[3]: seal(lifecycle), CONTRACT_PATHS[4]: evidence}


def sample_instances(root: Path) -> dict[str, dict[str, Any]]:
    documents = contract_documents(root)
    return {SCHEMA_PATHS[0]: persistence_descriptor(), SCHEMA_PATHS[1]: mapping_registry(),
            SCHEMA_PATHS[2]: migration_receipt(), SCHEMA_PATHS[3]: lifecycle_registry(),
            SCHEMA_PATHS[4]: lifecycle_trace(), SCHEMA_PATHS[5]: documents[CONTRACT_PATHS[4]]}


def all_outputs(root: Path) -> dict[str, bytes]:
    outputs = {path: pretty(value) for path, value in schema_shapes().items()}
    outputs.update({path: pretty(value) for path, value in contract_documents(root).items()})
    materialized = {path: outputs[path] if path in outputs else (root / path).read_bytes() for path in MANIFEST_INPUT_PATHS}
    rows = [{"path": path, "bytes": len(materialized[path]), "sha256": digest(materialized[path])} for path in MANIFEST_INPUT_PATHS]
    tooling = {"schema": "V23P03C07ToolingManifestV1", "schemaVersion": 1, "cardID": CARD, "authority": authority(),
               "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE), "existingPaths": [], "newPaths": PATH_FENCE,
               "sourcePathCount": len(SOURCE_PATHS), "toolPathCount": len(TOOL_PATHS), "artifactCount": len(rows),
               "pendingArtifactCount": 0, "artifacts": rows, "artifactSetDigest": digest(canonical(rows)),
               "verificationMode": "STATIC_ONLY", "nativeCompileRan": False, "hostedDispatchRan": False,
               "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
               "releaseReady": False, "releaseCredit": False, "requiresAcceptedS10_6Reconciliation": True}
    tooling["artifactDigest"] = digest(pretty(tooling))
    outputs[MANIFEST] = pretty(tooling)
    if set(outputs) != set(GENERATED_PATHS): raise ContractError("generated output inventory differs")
    return outputs
