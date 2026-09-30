#!/usr/bin/env python3
"""Deterministic V23-P01-C01 schema and identity contract."""
from __future__ import annotations
import hashlib, json, re
from pathlib import Path
from typing import Any

CARD="V23-P01-C01"
BASE_HEAD="f3c4a764ddaa0dd607b04fa1929c80620d3164aa"
BASE_TREE="d4b04d57475493511a8482563a7f1f981639c65a"
CONTEXT_DIGEST="7e182eeb0787008de8c3ebeb5b575d1138dda4c7c2be6198c41e1ae671b3377b"
FENCE_DIGEST="26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b"
PREREQUISITE_DIGEST="7c529255d7c23764ff050062fe0e509fa2c70131ca85cd4e022dfbf42841a82b"
DOSSIER_DIGEST="881d5f6b834c73ddfee3e645c133d86f2f01acdc4cb091c0f6ee8e8f1e6358af"
INHERITED_DIGEST="a590970b54dc229ffc0fc0825935e32465d716237be7cd4764caa5426f99353a"
C06={"cardID":"V23-P00-C06","candidateHead":"e6bfa3dd047e15b71f132b76db2e358bc734bfb0",
 "candidateTree":"e333cf05f1256b2636f31c96cf1d74d323d61193",
 "contextDigest":"afbb364ed404d4fbd57ee66c5707c8f670a002b8d81cdc425cc6a0cfb3c53d60",
 "pathFenceDigest":"ca49bcc135ddc270e18c42b808a804a6b1de71bb8a08647b32bccd3b1a9a6eca",
 "verificationReceiptDigest":"77444d12c7a2bec4b09f16e96fcb70f8278805d58200a15cd8033263eb4d53b8",
 "checkpointDigest":"8bdd5bcee83c136496e1ca6bd4b2a9ec79719ecf002d6f8bca9b73d853fc03ee",
 "platformScopeManifestDigest":"ba548ef8cec1be0d290c300ebf88f10239640bc57e35841843aa4632d4bbed6b",
 "platformScopeManifestFileSHA256":"cc94c682351116ecb7254ccd3a50a05af835fbebe2fd3f5873a0be7f103df0de",
 "toolingManifestDigest":"33e5f0043ab318261ec63ee92b0bc4360215e5fd7bd7ac279b647738b743198e",
 "toolingManifestFileSHA256":"9e969a4c3b7622d7b02086f41abfc723a53dc97aab619e9f769f500cebcab579",
 "nativeCompileComplete":False,"archiveInspectionComplete":False,"installedRuntimeClosureComplete":False,
 "releaseHookClosureComplete":False,"acceptanceCredit":False,"releaseCredit":False}
SWIFT_PATHS=["FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
 "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
 "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceIdentity.swift",
 "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift"]
SCHEMA_PATH="Scripts/v23/versioned-schema-identity.schema.json"
ARTIFACT_PATH="docs/design/v23/tooling/V23P01C01SchemaIdentityContractV1.json"
MANIFEST_PATH="docs/design/v23/tooling/V23-P01-C01-tooling-manifest.json"
TOOL_PATHS=["Scripts/v23/p01_c01_contracts.py","Scripts/v23/generate_p01_c01_contracts.py",
 "Scripts/v23/verify_p01_c01_contracts.py",SCHEMA_PATH,ARTIFACT_PATH,MANIFEST_PATH]
MODELS=[
 {"name":"Site","identity":"EntityID<Site>","references":[],"referenceStorageDisposition":"NONE","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_ORPHAN_SITE_IF_SELECTED_ASSET_WAS_LAST_SITE_ASSET"},
 {"name":"Asset","identity":"EntityID<Asset>","references":[{"field":"siteID","targetModel":"Site"}],"referenceStorageDisposition":"APPLICATION_GOVERNED_SCALAR_UUID","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_SELECTED_ASSET_AFTER_DEPENDENTS"},
 {"name":"WorkflowRecord","identity":"EntityID<WorkflowRecord>","references":[{"field":"assetID","targetModel":"Asset"},{"field":"packetID","targetModel":"Packet"},{"field":"issueID","targetModel":"Issue"},{"field":"parentRecordID","targetModel":"WorkflowRecord"},{"field":"recordRevisionRootID","targetModel":"WorkflowRecord"},{"field":"revisesRecordID","targetModel":"WorkflowRecord"},{"field":"evidenceSourceRecordID","targetModel":"WorkflowRecord"}],"referenceStorageDisposition":"APPLICATION_GOVERNED_SCALAR_UUID","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_SELECTED_ASSET_WORKFLOW_RECORDS"},
 {"name":"EvidenceFile","identity":"EntityID<EvidenceFile>","references":[{"field":"recordID","targetModel":"WorkflowRecord"}],"referenceStorageDisposition":"APPLICATION_GOVERNED_SCALAR_UUID","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_SELECTED_RECORD_EVIDENCE"},
 {"name":"Issue","identity":"EntityID<Issue>","references":[{"field":"assetID","targetModel":"Asset"},{"field":"openedByRecordID","targetModel":"WorkflowRecord"},{"field":"resolvedByRecordID","targetModel":"WorkflowRecord"}],"referenceStorageDisposition":"APPLICATION_GOVERNED_SCALAR_UUID","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_SELECTED_ASSET_ISSUES"},
 {"name":"Packet","identity":"EntityID<Packet>","references":[{"field":"stableRootID","targetModel":"Packet"},{"field":"currentRecordID","targetModel":"WorkflowRecord"}],"referenceStorageDisposition":"APPLICATION_GOVERNED_SCALAR_UUID","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_UNCOUNTED_PACKET_OR_TOMBSTONE_COUNTED_PACKET"},
 {"name":"Report","identity":"EntityID<Report>","references":[{"field":"packetID","targetModel":"Packet"},{"field":"sourceRecordID","targetModel":"WorkflowRecord"},{"field":"replacesReportID","targetModel":"Report"}],"referenceStorageDisposition":"APPLICATION_GOVERNED_SCALAR_UUID","swiftDataDeleteRuleDisposition":"NONE_NO_SWIFTDATA_RELATIONSHIP","applicationDeleteRuleOwner":"WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)","applicationDeleteDisposition":"DELETE_SELECTED_PACKET_REPORTS"}]
REGRESSION_TEST_BINDINGS=[
 {"path":"FieldEvidenceAppTests/S2PersistenceLedgerTests.swift","method":"testBootstrapPersistsReleasesAndReopensTheExactGenerationLedger","result":"NOT_RUN"},
 {"path":"FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift","method":"testValidReadyReportRemainsByteIdenticalAndTerminal","result":"NOT_RUN"},
 {"path":"FieldEvidenceAppTests/S6_2BackupExportTests.swift","method":"testCanonicalFixturesAndExportedBundleTypeDeclaration","result":"NOT_RUN"},
 {"path":"FieldEvidenceAppTests/S6_3BackupValidationTests.swift","method":"testGoldenMixedPackageStagesValidatesAndRecomputesSummary","result":"NOT_RUN"}]

class ContractError(ValueError): pass
def pretty(value:Any)->bytes:return (json.dumps(value,ensure_ascii=False,sort_keys=True,indent=2)+"\n").encode()
def sha(value:bytes)->str:return hashlib.sha256(value).hexdigest()
def seal(value:dict[str,Any])->dict[str,Any]:
 result=dict(value);result["artifactDigest"]=sha(pretty(value));return result
def authority()->dict[str,Any]:
 return {"branch":"phase/v23-expansion","baseHead":BASE_HEAD,"baseTree":BASE_TREE,"contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,
  "provisionalPrerequisiteDigest":PREREQUISITE_DIGEST,"dossierDigest":DOSSIER_DIGEST,
  "inheritedV21BlockDigest":INHERITED_DIGEST,"directPrerequisite":C06,
  "deterministicEvidenceIDs":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")],
  "executionMode":"PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION","acceptedS10_6BaselineDigest":None,
  "nativeCompileRan":False,"hostedDispatchRan":False,"adoptionEnabled":False,"acceptanceEnabled":False,
  "acceptanceCredit":False,"releaseCredit":False,"requiresAcceptedS10_6Reconciliation":True,
  "phase10PollingDuringParallelExecution":False}
def lifecycle()->dict[str,Any]:
 return {"persistence":"IMMUTABLE_SOURCE_AND_CANDIDATE_BOUND_CONTRACT","supersession":"APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
  "successorTriggers":["SOURCE_CHANGE","SCHEMA_CHANGE","IDENTITY_TAXONOMY_CHANGE","FACTORY_CHANGE","EVIDENCE_CHANGE"],
  "interruption":"FAIL_CLOSED_NO_PARTIAL_ACCEPTANCE","recovery":"BYTE_EXACT_REGENERATION_OR_NEW_SUCCESSOR"}
def build_artifact()->dict[str,Any]:
 return seal({"schema":"V23P01C01SchemaIdentityContractV1","schemaVersion":1,"cardID":CARD,"authority":authority(),
  "schemaDescriptors":[{"name":"PersistentSchemaV1","version":[1,0,0],"status":"CURRENT_ACTIVE","registeredModels":[m["name"] for m in MODELS]},
   {"name":"PersistentSchemaV2","version":[2,0,0],"status":"DORMANT_DESCRIPTOR_ONLY","registeredModels":[m["name"] for m in MODELS]}],
  "activeSchema":"PersistentSchemaV1","dormantSchema":"PersistentSchemaV2","migrationPlan":"NONE_V2_NOT_ACTIVATED",
  "modelRegistration":MODELS,
  "identityTaxonomy":[
   {"name":"WorkspaceID","representation":"UUID","scope":"STABLE_NON_PERSON_WORKSPACE","distinctFrom":["EntityID","ReplicaID","GenerationID","MutationID","CheckpointID","AccountID","ServerID"]},
   {"name":"EntityID<Model>","representation":"UUID","scope":"GLOBALLY_COLLISION_RESISTANT_TYPED_ENTITY","distinctFrom":["WorkspaceID","ReplicaID","GenerationID","MutationID","CheckpointID","AccountID","ServerID"]},
   {"name":"ReplicaID","representation":"UUID","scope":"RANDOM_NON_HARDWARE_INSTALLATION","distinctFrom":["WorkspaceID","EntityID","GenerationID","MutationID","CheckpointID","AccountID","ServerID"]}],
  "restoreIdentityLaw":{"scope":"DECLARATION_ONLY_NO_PERSISTED_REPLICA_STATE","workspace":"NO_NEW_PERSISTED_WORKSPACE_ID_STATE",
   "entities":"NO_MODEL_FIELD_MIGRATION","replica":"DESTINATION_MINT_FUNCTION_REJECTS_SOURCE_AND_DISALLOWED_IDS",
   "runtimeRetentionImplemented":False,"persistedReplicaIDImplemented":False,"sourceReplicaImport":"FORBIDDEN",
   "backupRestoreBehavior":"UNCHANGED"},
  "preOpenVersionLaw":{"pointerValidation":"BEFORE_SQLITE_OR_MODELCONTAINER_OPEN","unknownFutureVersion":"REJECT_DATA_POINTER_INVALID",
   "missingOrNoncanonical":"REJECT_DATA_POINTER_INVALID","supportedSchemaVersion":1},
  "storeFactoryLaw":{"soleProductionFactory":"StoreGenerationFactory.makeContainer","configurationName":"FieldEvidenceV1",
   "cloudKitDatabase":"NONE_EXPLICIT","defaultOrConvenienceConstruction":"FORBIDDEN","automaticOrPrivateCloudKit":"FORBIDDEN"},
  "preservation":{"existingModelFields":"UNCHANGED","backupRestoreContract":"UNCHANGED",
   "reportContract":"UNCHANGED","persistenceWriterContract":"UNCHANGED","newUserVisibleFields":False},
  "regressionTestBindings":REGRESSION_TEST_BINDINGS,"regressionTestExecution":"NOT_RUN",
  "exclusions":["MIGRATION_IMPLEMENTATION","PERSISTENT_SCHEMA_V2_ACTIVATION","CLOUDKIT","REMOTE_SYNC","ACCOUNTS_AUTH_TENANCY","NEW_USER_VISIBLE_FIELDS"],
  "staticSwiftPaths":SWIFT_PATHS,"lifecycle":lifecycle(),"nativeCompileRan":False,"hostedDispatchRan":False,
  "adoptionEnabled":False,"acceptanceEnabled":False,"acceptanceCredit":False,"releaseReady":False,"releaseCredit":False,
  "requiresAcceptedS10_6Reconciliation":True,"phase10PollingDuringParallelExecution":False})
def structural(value:Any,key:str="")->dict[str,Any]:
 if key in ("schema","schemaVersion","cardID"):return {"const":value}
 if value is None:return {"anyOf":[{"type":"null"},{"type":"string","pattern":"^[0-9a-f]{64}$"}]}
 if isinstance(value,bool):return {"type":"boolean"}
 if isinstance(value,int):return {"type":"integer","minimum":0}
 if isinstance(value,str):
  if key.endswith("Digest"):return {"type":"string","pattern":"^[0-9a-f]{64}$"}
  if key in ("baseHead","baseTree","candidateHead","candidateTree"):return {"type":"string","pattern":"^[0-9a-f]{40}$"}
  return {"type":"string","minLength":1}
 if isinstance(value,list):return {"type":"array","minItems":len(value),"maxItems":len(value),"prefixItems":[structural(x,key) for x in value],"items":False}
 if isinstance(value,dict):return {"type":"object","additionalProperties":False,"required":list(value),"properties":{k:structural(v,k) for k,v in value.items()}}
 raise ContractError(key)
def build_schema(artifact:dict[str,Any])->dict[str,Any]:
 return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/versioned-schema-identity.schema.json","title":artifact["schema"],**structural(artifact)}
def build_outputs()->dict[str,dict[str,Any]]:
 artifact=build_artifact();return {SCHEMA_PATH:build_schema(artifact),ARTIFACT_PATH:artifact}
def build_manifest(root:Path)->dict[str,Any]:
 rows=[]
 for path in TOOL_PATHS:
  if path==MANIFEST_PATH:continue
  item=root/path
  if not item.is_file():raise ContractError(f"missing manifest input: {path}")
  rows.append({"path":path,"sha256":sha(item.read_bytes()),"bytes":item.stat().st_size})
 return seal({"schema":"V23P01C01ToolingManifestV1","schemaVersion":1,"cardID":CARD,"authority":authority(),
  "pathFence":TOOL_PATHS,"artifacts":rows,"artifactCount":len(rows),"nativeCompileRan":False,"hostedDispatchRan":False,
  "adoptionEnabled":False,"acceptanceEnabled":False,"acceptanceCredit":False,"releaseReady":False,"releaseCredit":False,
  "requiresAcceptedS10_6Reconciliation":True,"phase10PollingDuringParallelExecution":False})
