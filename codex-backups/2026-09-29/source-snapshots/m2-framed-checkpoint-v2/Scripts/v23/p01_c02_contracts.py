#!/usr/bin/env python3
"""Deterministic V23-P01-C02 owned-file protection and privacy contracts."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

CARD = "V23-P01-C02"
BASE_HEAD = "fd303030608600443c8a0151f8f93c27e5cc928e"
BASE_TREE = "cb5f5fc41379e61ed51dc1b3890ad55c63e98433"
COORDINATION_HYDRATION_HEAD = "86d6325f6eef5b7cae880f314fdc72aa67d6e3b7"
CONTEXT_DIGEST = "156b0f066a284225ee2a7a569d70b57d8495427f45660c29efc308e3e09eaaee"
FENCE_DIGEST = "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809"
PREREQUISITE_DIGEST = "927b5353927db5fd57d22973f31e3b7e5ecb4381f91e680dfc0f8b537881cef4"
REGISTER_ROW_DIGEST = "03010bdab18420ecc5ddd2f4b9ebc17b2af7722753253340379c3742ac813d6c"
DOSSIER_DIGEST = "c1995aa55b9acb0543d7c533d7ae3c37eab766c45861e5941ad48f73d0c341ba"
INHERITED_DIGEST = "e3d5f770500dca343d53dd22c87bdefa54e74e6e5ad172f31e20bcca38478482"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

FULL_FENCE = [
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/RestoreIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticsStore.swift",
    "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Commerce/EntitlementStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceAppTests/V9_02FileAuthorityTests.swift",
    "docs/privacy/V23P01C02OwnedFilePrivacyInventoryV1.json",
    "Scripts/v23/p01_c02_contracts.py",
    "Scripts/v23/generate_p01_c02_contracts.py",
    "Scripts/v23/verify_p01_c02_contracts.py",
    "Scripts/v23/owned-file-protection.schema.json",
    "docs/design/v23/tooling/V23P01C02OwnedFileProtectionContractV1.json",
    "docs/design/v23/tooling/V23-P01-C02-tooling-manifest.json",
]
PRODUCT_SOURCE_PATHS = FULL_FENCE[0:13]
READ_ONLY_CONSUMERS = [
    {"path":"FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
     "role":"S8_3_DIAGNOSTICS_ALLOWLIST_SOURCE_BOUND_READ_ONLY_CONSUMER"},
    {"path":"FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
     "role":"EXTERNAL_BACKUP_EXPORT_DELEGATE_SOURCE_BOUND_READ_ONLY_CONSUMER"},
    {"path":"FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
     "role":"REPORT_RECOVERY_SOURCE_BOUND_READ_ONLY_CONSUMER"},
]
SCHEMA_PATH = "Scripts/v23/owned-file-protection.schema.json"
ARTIFACT_PATH = "docs/design/v23/tooling/V23P01C02OwnedFileProtectionContractV1.json"
PRIVACY_PATH = "docs/privacy/V23P01C02OwnedFilePrivacyInventoryV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P01-C02-tooling-manifest.json"
TOOL_PATHS = ["Scripts/v23/p01_c02_contracts.py", "Scripts/v23/generate_p01_c02_contracts.py",
              "Scripts/v23/verify_p01_c02_contracts.py", SCHEMA_PATH, ARTIFACT_PATH, MANIFEST_PATH, PRIVACY_PATH]

INCLUDED = [
    {"id":"DURABLE_DATABASE","pathClass":"FieldEvidenceData/generations/<GenerationID>/model.sqlite","owner":"StoreGenerationFactory","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"DURABLE_DATABASE_WAL","pathClass":"FieldEvidenceData/generations/<GenerationID>/model.sqlite-wal","owner":"StoreGenerationFactory","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"DURABLE_DATABASE_SHM","pathClass":"FieldEvidenceData/generations/<GenerationID>/model.sqlite-shm","owner":"StoreGenerationFactory","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"CURRENT_POINTER","pathClass":"FieldEvidenceData/current.json","owner":"StoreGenerationFactory","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"RETIRED_POINTER","pathClass":"FieldEvidenceData/retired.json","owner":"StoreGenerationFactory","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"ORIGINAL_MEDIA","pathClass":"FieldEvidenceMedia/originals/<EvidenceID>","owner":"EvidenceBundleStore","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"THUMBNAIL_MEDIA","pathClass":"FieldEvidenceMedia/thumbnails/<EvidenceID>","owner":"EvidenceBundleStore","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"REPORT_SNAPSHOT","pathClass":"FieldEvidenceReports/snapshots/<ReportID>","owner":"ReportRenderService","backup":"INCLUDED","protection":"COMPLETE"},
    {"id":"REPORT_PDF","pathClass":"FieldEvidenceReports/pdfs/<ReportID>.pdf","owner":"ReportRenderService","backup":"INCLUDED","protection":"COMPLETE"},
]
EXCLUDED = [
    {"id":"RESTORE_IMPORT_STAGING","pathClass":"FieldEvidenceRestore/**","owner":"BackupImportService+BackupRestoreService","backup":"EXCLUDED","reason":"RECREATABLE_OR_UNTRUSTED_STAGING"},
    {"id":"JOURNALS_CHECKPOINTS_REPLAY_TEMP","pathClass":"**/{journal,checkpoint,replay,temp,next}*","owner":"IntentStores+recovery services","backup":"EXCLUDED","reason":"TRANSIENT_RECOVERY_STATE"},
    {"id":"DIAGNOSTICS","pathClass":"FieldEvidenceDiagnostics/**","owner":"DiagnosticsStore","backup":"EXCLUDED","reason":"RECREATABLE_SECRET_FREE_SUPPORT_STATE"},
    {"id":"ENTITLEMENT_CACHE","pathClass":"FieldEvidenceCommerce/**","owner":"EntitlementStore","backup":"EXCLUDED","reason":"PROVIDER_DERIVED_FACTS_NOT_PORTABLE_AUTHORITY"},
    {"id":"CACHES_SCRATCH","pathClass":"**/{cache,caches,scratch,tmp}/**","owner":"ALL_OWNERS","backup":"EXCLUDED","reason":"RECREATABLE_NON_DURABLE_STATE"},
]
HANDLING_CLASSES = [
    {"id":"REVIEW_BEARER_CAPABILITY","allowedResidency":"EXACT_PROTECTED_TRANSFERABLE_REQUEST_ARTIFACT_ONLY","persistence":"ONLY_WHEN_REAL_FEATURE_CREATES_EXACT_ARTIFACT","keychain":False},
    {"id":"PASSPHRASE","allowedResidency":"MEMORY_ONLY","persistence":"FORBIDDEN","keychain":False},
    {"id":"DERIVED_KEY","allowedResidency":"MEMORY_ONLY","persistence":"FORBIDDEN","keychain":False},
]
FORBIDDEN_SECRET_SURFACES = ["LOGS","DIAGNOSTICS","SEARCH","SPOTLIGHT","ACCESSIBILITY","REPORTS","SCREENSHOTS","SUPPORT","MARKETING","MEASUREMENT"]
RECHECK_EVENTS = ["INITIAL_CREATE","AFTER_SAVE","AFTER_ATOMIC_REPLACE","AFTER_MIGRATION","AFTER_RESTORE","AFTER_COPY"]


class ContractError(ValueError): pass
def pretty(value: Any) -> bytes: return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)+"\n").encode()
def sha(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def seal(value: dict[str, Any]) -> dict[str, Any]:
    result=dict(value); result["artifactDigest"]=sha(pretty(value)); return result
def source_bindings(root: Path) -> list[dict[str, Any]]:
    rows=[]
    for path in PRODUCT_SOURCE_PATHS:
        item=root/path
        if not item.is_file(): raise ContractError(f"missing product source: {path}")
        rows.append({"path":path,"role":"FENCED_PRODUCT_SOURCE","sha256":sha(item.read_bytes()),"bytes":item.stat().st_size})
    for row in READ_ONLY_CONSUMERS:
        item=root/row["path"]
        if not item.is_file(): raise ContractError(f"missing read-only consumer: {row['path']}")
        rows.append({**row,"sha256":sha(item.read_bytes()),"bytes":item.stat().st_size,"mutationAuthorized":False})
    return rows
def authority() -> dict[str, Any]:
    return {"branch":"phase/v23-expansion","baseHead":BASE_HEAD,"baseTree":BASE_TREE,
      "coordinationHydrationHead":COORDINATION_HYDRATION_HEAD,"contextDigest":CONTEXT_DIGEST,
      "pathFenceDigest":FENCE_DIGEST,"provisionalPrerequisiteDigest":PREREQUISITE_DIGEST,
      "registerRowDigest":REGISTER_ROW_DIGEST,"dossierDigest":DOSSIER_DIGEST,"inheritedV21BlockDigest":INHERITED_DIGEST,
      "facetManifestDigest":FACET_DIGEST,"selectorManifestDigest":SELECTOR_DIGEST,"relationManifestDigest":RELATION_DIGEST,
      "impactManifestDigest":IMPACT_DIGEST,"frozenS10ReservationDigest":RESERVATION_DIGEST,
      "reservationOverlapCount":0,"authorizedPriorFenceOverlaps":[
       {"path":FULL_FENCE[1],"cardID":"V23-P01-C01","disposition":"DIRECT_INVALIDATION_AND_REPROOF"},
       {"path":FULL_FENCE[12],"cardID":"V23-P00-C11","disposition":"ARCHITECTURE_CONCURRENCY_TARGETED_REPROOF"}],
      "directPrerequisites":["V23-P01-C01"],"lineage":"REFINED_WITHOUT_LOSS",
      "deterministicEvidenceIDs":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")],
      "executionMode":"PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION","acceptedS10_6BaselineDigest":None}
def lifecycle() -> dict[str, Any]:
    return {"persistence":"IMMUTABLE_SOURCE_BOUND_CONTRACT","supersession":"APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
      "successorTriggers":["SOURCE_CHANGE","PATH_CLASS_CHANGE","PROTECTION_POLICY_CHANGE","BACKUP_ELIGIBILITY_CHANGE","SECRET_INVENTORY_CHANGE","EVIDENCE_CHANGE"],
      "interruption":"FAIL_CLOSED_NO_PARTIAL_ACCEPTANCE","recovery":"REGENERATE_FROM_CURRENT_SOURCES_OR_ISSUE_SUCCESSOR"}
def flags() -> dict[str, Any]:
    return {"nativeCompileRan":False,"hostedDispatchRan":False,"physicalEvidenceComplete":False,
      "physicalLockedState":"REQUIRED_PENDING_OWNER","adoptionEnabled":False,"acceptanceEnabled":False,
      "acceptanceCredit":False,"releaseReady":False,"releaseCredit":False,
      "requiresAcceptedS10_6Reconciliation":True,"phase10PollingDuringParallelExecution":False}
def build_artifact(root: Path) -> dict[str, Any]:
    return seal({"schema":"V23P01C02OwnedFileProtectionContractV1","schemaVersion":1,"cardID":CARD,
      "authority":authority(),"fullPathFence":FULL_FENCE,"sourceBindings":source_bindings(root),
      "persistentChangeMode":"CONTENT_ONLY","behavioralDelta":{"schema":False,"migration":False,
       "backupFormat":False,"restore":False,"delete":False,"export":False},
      "ownedPathMatrix":{"backupIncluded":INCLUDED,"backupExcluded":EXCLUDED,"closed":True,
       "unknownDisposition":"FAIL_CLOSED_UNTIL_EXPLICITLY_CLASSIFIED"},
      "protectionLaw":{"requiredProtection":"COMPLETE","allCurrentAndStagedOwnedPathClassesRequired":True,
       "recheckEvents":RECHECK_EVENTS,"metadataOnlyCheckInsufficient":True,"physicalLockedVerification":"REQUIRED_PENDING_OWNER"},
      "externalBackupDestination":{"owner":"BackupExportService","disposition":"EXTERNAL_PROVIDER_HANDOFF",
       "appProtectionAttributeClaim":False,"providerDestinationEligibilityClaim":False},
      "secretInventory":[],"secretInventoryCompleteness":"NO_REAL_CURRENT_SECRET_OBSERVED_SOURCE_BOUND_EMPTY",
      "handlingClassDeclarations":HANDLING_CLASSES,"forbiddenSecretSurfaces":FORBIDDEN_SECRET_SURFACES,
      "keychainUsage":"NONE","readOnlyConsumers":READ_ONLY_CONSUMERS,"lifecycle":lifecycle(),**flags()})
def build_privacy(root: Path) -> dict[str, Any]:
    bindings=source_bindings(root)
    return seal({"schema":"V23P01C02OwnedFilePrivacyInventoryV1","schemaVersion":1,"cardID":CARD,
      "authority":authority(),"sourceBindingDigest":sha(pretty(bindings)),"ownedPathMatrix":{"backupIncluded":INCLUDED,"backupExcluded":EXCLUDED},
      "externalProviderHandoff":"EXTERNAL_PROVIDER_HANDOFF","appProtectionAttributeClaimForExternalDestination":False,
      "secretInventory":[],"handlingClassDeclarations":HANDLING_CLASSES,"forbiddenSecretSurfaces":FORBIDDEN_SECRET_SURFACES,
      "diagnosticsAllowlist":{"contract":"S8.3","sourcePath":READ_ONLY_CONSUMERS[0]["path"],"sourceDigest":bindings[13]["sha256"],"mutationAuthorized":False},
      "externalExportSource":{"sourcePath":READ_ONLY_CONSUMERS[1]["path"],"sourceDigest":bindings[14]["sha256"],"mutationAuthorized":False},
      "reportRecoverySource":{"sourcePath":READ_ONLY_CONSUMERS[2]["path"],"sourceDigest":bindings[15]["sha256"],"mutationAuthorized":False},
      "keychainUsage":"NONE","lifecycle":lifecycle(),**flags()})
def structural(value: Any, key: str="") -> dict[str, Any]:
    if key in ("schema","schemaVersion","cardID"): return {"const":value}
    if value is None: return {"type":"null"}
    if isinstance(value,bool): return {"type":"boolean"}
    if isinstance(value,int): return {"type":"integer","minimum":0}
    if isinstance(value,str):
        if key.endswith("Digest") or key=="sha256": return {"type":"string","pattern":"^[0-9a-f]{64}$"}
        if key in ("baseHead","baseTree","coordinationHydrationHead"): return {"type":"string","pattern":"^[0-9a-f]{40}$"}
        return {"type":"string","minLength":1}
    if isinstance(value,list): return {"type":"array","minItems":len(value),"maxItems":len(value),"prefixItems":[structural(x,key) for x in value],"items":False}
    if isinstance(value,dict): return {"type":"object","additionalProperties":False,"required":list(value),"properties":{k:structural(v,k) for k,v in value.items()}}
    raise ContractError(key)
def build_schema(root: Path) -> dict[str, Any]:
    artifact=build_artifact(root)
    return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/owned-file-protection.schema.json","title":artifact["schema"],**structural(artifact)}
def build_outputs(root: Path) -> dict[str, dict[str, Any]]:
    return {SCHEMA_PATH:build_schema(root),ARTIFACT_PATH:build_artifact(root),PRIVACY_PATH:build_privacy(root)}
def build_manifest(root: Path) -> dict[str, Any]:
    rows=[]
    for path in TOOL_PATHS:
        if path==MANIFEST_PATH: continue
        item=root/path
        if not item.is_file(): raise ContractError(f"missing manifest input: {path}")
        rows.append({"path":path,"sha256":sha(item.read_bytes()),"bytes":item.stat().st_size})
    return seal({"schema":"V23P01C02ToolingManifestV1","schemaVersion":1,"cardID":CARD,"authority":authority(),
      "pathFence":TOOL_PATHS,"fullCardFence":FULL_FENCE,"artifacts":rows,"artifactCount":len(rows),"lifecycle":lifecycle(),**flags()})
