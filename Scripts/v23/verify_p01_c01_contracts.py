#!/usr/bin/env python3
"""Static and hostile verification for V23-P01-C01 tooling and Swift contract."""
from __future__ import annotations
import ast, copy, json, os, re, subprocess, sys
from pathlib import Path
from typing import Any
from p01_c01_contracts import *

FULL_FENCE=SWIFT_PATHS+TOOL_PATHS
EXPECTED_LIFECYCLE={"persistence":"IMMUTABLE_SOURCE_AND_CANDIDATE_BOUND_CONTRACT",
 "supersession":"APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
 "successorTriggers":["SOURCE_CHANGE","SCHEMA_CHANGE","IDENTITY_TAXONOMY_CHANGE","FACTORY_CHANGE","EVIDENCE_CHANGE"],
 "interruption":"FAIL_CLOSED_NO_PARTIAL_ACCEPTANCE","recovery":"BYTE_EXACT_REGENERATION_OR_NEW_SUCCESSOR"}

def load(path:Path)->Any:return json.loads(path.read_text(encoding="utf-8"))
def verify_digest(value:dict[str,Any])->None:
 body={k:v for k,v in value.items() if k!="artifactDigest"}
 if value.get("artifactDigest")!=sha(pretty(body)):raise ContractError("sealed digest differs")
def validate_schema(value:Any,schema:dict[str,Any],where:str="$")->None:
 if "anyOf" in schema:
  for option in schema["anyOf"]:
   try:validate_schema(value,option,where);return
   except ContractError:pass
  raise ContractError(f"{where}: anyOf")
 if "const" in schema and value!=schema["const"]:raise ContractError(f"{where}: const")
 typ=schema.get("type");types={"object":dict,"array":list,"string":str,"integer":int,"boolean":bool,"null":type(None)}
 if typ and (not isinstance(value,types[typ]) or typ=="integer" and isinstance(value,bool)):raise ContractError(f"{where}: type")
 if isinstance(value,dict):
  props=schema.get("properties",{});missing=set(schema.get("required",[]))-set(value);extra=set(value)-set(props)
  if missing or schema.get("additionalProperties") is False and extra:raise ContractError(f"{where}: shape")
  for key,item in value.items():
   if key in props:validate_schema(item,props[key],f"{where}.{key}")
 if isinstance(value,list):
  if len(value)<schema.get("minItems",0) or len(value)>schema.get("maxItems",sys.maxsize):raise ContractError(f"{where}: count")
  for index,item_schema in enumerate(schema.get("prefixItems",[])):validate_schema(value[index],item_schema,f"{where}[{index}]")
 if isinstance(value,str):
  if len(value)<schema.get("minLength",0) or "pattern" in schema and re.fullmatch(schema["pattern"],value) is None:raise ContractError(f"{where}: string")
def reject(callable_value:Any)->None:
 try:callable_value()
 except (ContractError,ValueError):return
 raise ContractError("hostile mutation passed")
def section(text:str,start:str,end:str)->str:
 a=text.index(start);b=text.index(end,a);return text[a:b].rstrip()+"\n"
def validate_authority(root:Path,artifact:dict[str,Any])->None:
 if artifact["authority"]!=authority():raise ContractError("authority differs")
 blueprint=(root/"docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md").read_text(encoding="utf-8")
 dossier=section(blueprint,f"### {CARD} — Explicit VersionedSchema and stable WorkspaceID/EntityID/ReplicaID taxonomy",'<a id="v23-p01-c02"></a>')
 inherited=section(blueprint,"    ### V21-P01-C01 —","    ### V21-P01-C02 —")
 if sha(dossier.encode())!=DOSSIER_DIGEST or sha(inherited.encode())!=INHERITED_DIGEST:raise ContractError("source digest differs")
def validate_fence(root:Path)->None:
 if len(FULL_FENCE)!=10 or len(set(FULL_FENCE))!=10:raise ContractError("fence cardinality")
 def git(*args:str)->str:return subprocess.run(["git","-C",str(root),*args],check=True,capture_output=True,text=True,encoding="utf-8").stdout.strip()
 if git("branch","--show-current")!="phase/v23-expansion":raise ContractError("branch differs")
 subprocess.run(["git","-C",str(root),"cat-file","-e",f"{BASE_HEAD}^{{commit}}"],check=True,capture_output=True)
 if git("show","-s","--format=%T",BASE_HEAD)!=BASE_TREE:raise ContractError("base object/tree differs")
 head=git("rev-parse","HEAD")
 if subprocess.run(["git","-C",str(root),"merge-base","--is-ancestor",BASE_HEAD,head],capture_output=True).returncode!=0:
  raise ContractError("base is not ancestor of candidate")
 if subprocess.run(["git","-C",str(root),"merge-base","--is-ancestor",C06["candidateHead"],head],capture_output=True).returncode!=0:
  raise ContractError("C06 candidate is not ancestor")
 remote=git("rev-parse","--verify","origin/phase/v23-expansion")
 committed={p.replace("\\","/") for p in git("diff","--name-only",f"{BASE_HEAD}..{head}").splitlines() if p}
 worktree=set()
 status_output=subprocess.run(["git","-C",str(root),"status","--porcelain=v1","--untracked-files=all"],
                              check=True,capture_output=True,text=True,encoding="utf-8").stdout
 for line in status_output.splitlines():
  if not line:continue
  if " -> " in line[3:] or "D" in line[:2] or "R" in line[:2]:raise ContractError("delete/rename forbidden")
  worktree.add(line[3:].replace("\\","/"))
 if committed|worktree!=set(FULL_FENCE):raise ContractError(f"candidate union differs: {sorted(committed|worktree)}")
 if head==BASE_HEAD:
  if remote!=BASE_HEAD or committed or worktree!=set(FULL_FENCE):raise ContractError("unsafe precommit repository state")
 else:
  if git("rev-parse","HEAD^")!=BASE_HEAD or remote!=head or committed!=set(FULL_FENCE) or worktree:
   raise ContractError("unsafe postpush single-card repository state")
def validate_c06(root:Path)->None:
 expected=[
  ("docs/design/v23/tooling/V23PlatformScopeManifestV1.json",C06["platformScopeManifestDigest"],C06["platformScopeManifestFileSHA256"]),
  ("docs/design/v23/tooling/V23-P00-C06-tooling-manifest.json",C06["toolingManifestDigest"],C06["toolingManifestFileSHA256"])]
 for relative,semantic,file_digest in expected:
  path=root/relative
  if not path.is_file() or sha(path.read_bytes())!=file_digest or load(path).get("artifactDigest")!=semantic:
   raise ContractError(f"installed C06 artifact differs: {relative}")
def validate_swift(root:Path)->dict[str,int]:
 for path in SWIFT_PATHS:
  if not (root/path).is_file():raise ContractError(f"Swift contract path absent: {path}")
 schemas=(root/SWIFT_PATHS[1]).read_text(encoding="utf-8")
 identity=(root/SWIFT_PATHS[2]).read_text(encoding="utf-8")
 factory=(root/SWIFT_PATHS[0]).read_text(encoding="utf-8")
 tests=(root/SWIFT_PATHS[3]).read_text(encoding="utf-8")
 for token in ("PersistentSchemaV1","PersistentSchemaV2","VersionedSchema","Schema.Version(1, 0, 0)","Schema.Version(2, 0, 0)"):
  if token not in schemas:raise ContractError(f"schema descriptor missing {token}")
 for model in [row["name"] for row in MODELS]:
  if schemas.count(f"{model}.self")!=1:raise ContractError(f"seven-model catalog registration differs: {model}")
 if schemas.count("PersistentModelCatalog.models")!=2:raise ContractError("V1/V2 do not share the exact seven-model catalog")
 for model in MODELS:
  for reference in model["references"]:
   field=reference["field"];target=reference["targetModel"]
   target_case=target[0].lower()+target[1:]
   if f'field: "{field}"' not in schemas or f"targetModel: .{target_case}" not in schemas:
    raise ContractError(f"field-target reference differs: {model['name']}.{field}->{target}")
  if model["applicationDeleteRuleOwner"] not in schemas or model["applicationDeleteDisposition"] not in {
   "DELETE_ORPHAN_SITE_IF_SELECTED_ASSET_WAS_LAST_SITE_ASSET","DELETE_SELECTED_ASSET_AFTER_DEPENDENTS",
   "DELETE_SELECTED_ASSET_WORKFLOW_RECORDS","DELETE_SELECTED_RECORD_EVIDENCE","DELETE_SELECTED_ASSET_ISSUES",
   "DELETE_UNCOUNTED_PACKET_OR_TOMBSTONE_COUNTED_PACKET","DELETE_SELECTED_PACKET_REPORTS"}:
   raise ContractError("application delete owner/disposition differs")
 delete_cases={
  "DELETE_ORPHAN_SITE_IF_SELECTED_ASSET_WAS_LAST_SITE_ASSET":"deleteOrphanSiteIfSelectedAssetWasLastSiteAsset",
  "DELETE_SELECTED_ASSET_AFTER_DEPENDENTS":"deleteSelectedAssetAfterDependents",
  "DELETE_SELECTED_ASSET_WORKFLOW_RECORDS":"deleteSelectedAssetWorkflowRecords",
  "DELETE_SELECTED_RECORD_EVIDENCE":"deleteSelectedRecordEvidence",
  "DELETE_SELECTED_ASSET_ISSUES":"deleteSelectedAssetIssues",
  "DELETE_UNCOUNTED_PACKET_OR_TOMBSTONE_COUNTED_PACKET":"deleteUncountedPacketOrTombstoneCountedPacket",
  "DELETE_SELECTED_PACKET_REPORTS":"deleteSelectedPacketReports"}
 for model in MODELS:
  if f'.{delete_cases[model["applicationDeleteDisposition"]]}' not in schemas:
   raise ContractError(f"PersistentSchemas delete disposition absent: {model['name']}")
 for token in ("WorkspaceID","EntityID","ReplicaID","UUID","RawRepresentable","Hashable","Sendable"):
  if token not in identity:raise ContractError(f"identity taxonomy missing {token}")
 identity_code=re.sub(r"/\*.*?\*/","",identity,flags=re.S)
 identity_code=re.sub(r"//[^\n]*","",identity_code)
 forbidden_authority_patterns=(
  r"\bUIDevice\s*\.\s*current\s*\.\s*identifierForVendor\b",
  r"\b(?:account|tenant|server|hardware|device)(?:ID|Identifier)\b",
  r"\b(?:struct|class|enum|typealias)\s+(?:Account|Tenant|Server|Hardware|Device)(?:ID|Identifier)\b",
 )
 if any(re.search(pattern,identity_code,re.I) for pattern in forbidden_authority_patterns):
  raise ContractError("identity taxonomy gained forbidden authority API/declaration/field")
 if factory.count("cloudKitDatabase: .none")!=1 or "cloudKitDatabase: .automatic" in factory or "cloudKitDatabase: .private" in factory:
  raise ContractError("sole factory explicit-none law differs")
 migration_bindings=re.findall(r"migrationPlan:\s*([A-Za-z0-9_.]+)",factory)
 if "PersistentSchemaV2" in factory or migration_bindings!=["nil"]:raise ContractError("V2/migration activated")
 if ("StorePointerSchemaRegistry.requireCurrent" not in factory or "StorePointerSchemaRegistry.requireRetired" not in factory or
     factory.index("StorePointerSchemaRegistry.requireCurrent(current.schemaVersion)")>factory.index("makeContainer(at: modelStoreURL)")):
  raise ContractError("pointer version is not rejected before store open")
 production=[]
 for path in (root/"FieldEvidenceApp").rglob("*.swift"):
  text=path.read_text(encoding="utf-8")
  if "ModelContainer(" in text:production.append(path.relative_to(root).as_posix())
 if production!=[SWIFT_PATHS[0]]:raise ContractError(f"ModelContainer production ownership differs: {production}")
 required_tests=("PersistentSchemaV1","PersistentSchemaV2","WorkspaceID","SiteID","AssetID","ReplicaID","destination","schemaVersion","cloudKitDatabase")
 if any(token not in tests for token in required_tests):raise ContractError("static Swift tests omit contract boundary")
 if ("WholeSignDeletionRule + WholeSignDeletionService.apply(plan:rows:)" not in tests or
     "WholeSignDeletionRule.makePlan(" not in tests or "modelContext.delete(" not in tests or
     "applicationDeleteDisposition" not in tests):raise ContractError("Swift tests do not bind application delete owner/service")
 forbidden=("CloudKit","CKSyncEngine","ModelConfiguration.CloudKitDatabase.private","PersistentSchemaV2.self,")
 if any(token in schemas+identity for token in forbidden):raise ContractError("forbidden migration/cloud/sync scope appeared")
 for binding in REGRESSION_TEST_BINDINGS:
  path=root/binding["path"]
  if not path.is_file() or re.search(rf"func\s+{re.escape(binding['method'])}\s*\(",path.read_text(encoding="utf-8")) is None:
   raise ContractError(f"regression test binding absent: {binding['path']}::{binding['method']}")
  if binding["result"]!="NOT_RUN":raise ContractError("regression test result overclaimed")
 return {"registeredModelCount":7,"schemaDescriptorCount":2,"identityKindCount":3,"swiftPathCount":4,"regressionTestBindingCount":4}
def validate_current(artifact:dict[str,Any])->None:
 if artifact!=build_artifact():raise ContractError("artifact semantic bytes differ")
 if artifact["schemaDescriptors"][0]["registeredModels"]!=[m["name"] for m in MODELS] or artifact["schemaDescriptors"][1]["status"]!="DORMANT_DESCRIPTOR_ONLY":raise ContractError("schema descriptors differ")
 if artifact["modelRegistration"]!=MODELS or len(artifact["modelRegistration"])!=7:raise ContractError("model mapping differs")
 if artifact["lifecycle"]!=EXPECTED_LIFECYCLE:raise ContractError("lifecycle differs")
 restore=artifact["restoreIdentityLaw"]
 if (restore!={"scope":"DECLARATION_ONLY_NO_PERSISTED_REPLICA_STATE","workspace":"NO_NEW_PERSISTED_WORKSPACE_ID_STATE",
      "entities":"NO_MODEL_FIELD_MIGRATION","replica":"DESTINATION_MINT_FUNCTION_REJECTS_SOURCE_AND_DISALLOWED_IDS",
      "runtimeRetentionImplemented":False,"persistedReplicaIDImplemented":False,"sourceReplicaImport":"FORBIDDEN",
      "backupRestoreBehavior":"UNCHANGED"} or artifact["regressionTestBindings"]!=REGRESSION_TEST_BINDINGS or
      artifact["regressionTestExecution"]!="NOT_RUN"):
  raise ContractError("declaration-only restore/regression semantics differ")
 false_fields=("nativeCompileRan","hostedDispatchRan","adoptionEnabled","acceptanceEnabled","acceptanceCredit","releaseReady","releaseCredit","phase10PollingDuringParallelExecution")
 if any(artifact[key] for key in false_fields) or not artifact["requiresAcceptedS10_6Reconciliation"]:raise ContractError("provisional contract overclaims")

def main()->int:
 root=Path(__file__).resolve().parents[2];validate_fence(root);validate_c06(root);checks=4
 expected=build_outputs()
 for rel,value in expected.items():
  if not (root/rel).is_file() or (root/rel).read_bytes()!=pretty(value):raise ContractError(f"generated output differs: {rel}")
  checks+=1
 artifact=load(root/ARTIFACT_PATH);schema=load(root/SCHEMA_PATH)
 validate_schema(artifact,schema);verify_digest(artifact);validate_authority(root,artifact);validate_current(artifact);checks+=12
 swift_counts=validate_swift(root);checks+=18
 for path in TOOL_PATHS[:3]:ast.parse((root/path).read_text(encoding="utf-8"),filename=path);checks+=1
 hostiles=0
 mutations=[
  (("schemaDescriptors",1,"status"),"CURRENT_ACTIVE"),(("activeSchema",),"PersistentSchemaV2"),
  (("migrationPlan",),"SchemaMigrationPlan"),(("modelRegistration",),artifact["modelRegistration"][:-1]),
  (("identityTaxonomy",0,"scope"),"PERSON_ACCOUNT"),(("restoreIdentityLaw","replica"),"PRESERVE_SOURCE_REPLICA"),
  (("preOpenVersionLaw","pointerValidation"),"AFTER_SQLITE_OPEN"),(("storeFactoryLaw","cloudKitDatabase"),"AUTOMATIC"),
  (("preservation","existingModelFields"),"CHANGED"),(("nativeCompileRan",),True),(("hostedDispatchRan",),True),
  (("adoptionEnabled",),True),(("acceptanceEnabled",),True),(("acceptanceCredit",),True),
  (("releaseReady",),True),(("releaseCredit",),True),(("requiresAcceptedS10_6Reconciliation",),False),
  (("phase10PollingDuringParallelExecution",),True),(("authority","contextDigest"),"0"*64),
  (("authority","branch"),"main"),(("authority","baseHead"),"0"*40),
  (("authority","directPrerequisite","cardID"),"V23-P00-C08"),
  (("restoreIdentityLaw","runtimeRetentionImplemented"),True),
  (("restoreIdentityLaw","persistedReplicaIDImplemented"),True),
  (("regressionTestBindings",),artifact["regressionTestBindings"][:-1]),
  (("modelRegistration",1,"references",0,"targetModel"),"Report"),
  (("modelRegistration",1,"applicationDeleteRuleOwner"),"UnknownOwner"),
  (("modelRegistration",1,"applicationDeleteDisposition"),"DELETE_SELECTED_PACKET_REPORTS"),
  (("modelRegistration",1,"referenceStorageDisposition"),"NONE"),
  (("lifecycle","recovery"),"REWRITE")]
 for path,replacement in mutations:
  hostile=copy.deepcopy(artifact);target=hostile
  for part in path[:-1]:target=target[part]
  target[path[-1]]=replacement;reject(lambda value=hostile:validate_current(value));hostiles+=1
 extra=copy.deepcopy(artifact);extra["extra"]=1;reject(lambda:validate_schema(extra,schema));hostiles+=1
 bad=copy.deepcopy(artifact);bad["artifactDigest"]="0"*64;reject(lambda:verify_digest(bad));hostiles+=1
 regenerated=build_artifact()
 if pretty(regenerated)!=pretty(artifact):raise ContractError("interruption regeneration differs")
 checks+=len(mutations)+4
 manifest=load(root/MANIFEST_PATH)
 if manifest!=build_manifest(root) or manifest["artifactCount"]!=5 or manifest["pathFence"]!=TOOL_PATHS:raise ContractError("manifest differs")
 verify_digest(manifest)
 for row in manifest["artifacts"]:
  if sha((root/row["path"]).read_bytes())!=row["sha256"]:raise ContractError("manifest hash differs")
 checks+=4
 run=subprocess.run([sys.executable,"-B",str(root/"Scripts/v23/generate_p01_c01_contracts.py"),"--check","--root",str(root)],check=True,capture_output=True,text=True,env={**os.environ,"PYTHONDONTWRITEBYTECODE":"1"})
 if "PASS V23-P01-C01 generated=3 check=True" not in run.stdout:raise ContractError("generator check differs")
 checks+=1
 print(json.dumps({"result":"PASS","cardID":CARD,"checks":checks,"hostileMutationCount":hostiles,**swift_counts,
  "nativeCompileRan":False,"hostedDispatchRan":False,"adoptionEnabled":False,"acceptanceCredit":False,
  "releaseReady":False,"releaseCredit":False,"requiresAcceptedS10_6Reconciliation":True,
  "phase10PollingDuringParallelExecution":False},sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
