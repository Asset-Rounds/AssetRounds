#!/usr/bin/env python3
"""Static and hostile verification for V23-P01-C02 tooling/privacy artifacts."""
from __future__ import annotations
import ast, copy, json, os, re, subprocess, sys
from pathlib import Path
from typing import Any
from p01_c02_contracts import *

def load(path:Path)->Any:return json.loads(path.read_text(encoding="utf-8"))
def verify_digest(value:dict[str,Any])->None:
 body={k:v for k,v in value.items() if k!="artifactDigest"}
 if value.get("artifactDigest")!=sha(pretty(body)):raise ContractError("sealed digest differs")
def validate_schema(value:Any,schema:dict[str,Any],where:str="$")->None:
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
def reject(fn:Any)->None:
 try:fn()
 except (ContractError,ValueError,KeyError):return
 raise ContractError("hostile mutation passed")
def mutate(value:dict[str,Any],path:tuple[Any,...],replacement:Any)->dict[str,Any]:
 result=copy.deepcopy(value);target=result
 for key in path[:-1]:target=target[key]
 target[path[-1]]=replacement;return result
def git(root:Path,*args:str)->str:
 return subprocess.run(["git","-C",str(root),*args],check=True,capture_output=True,text=True,encoding="utf-8").stdout.strip()
def validate_repository(root:Path)->None:
 if git(root,"branch","--show-current")!="phase/v23-expansion":raise ContractError("branch differs")
 subprocess.run(["git","-C",str(root),"cat-file","-e",f"{BASE_HEAD}^{{commit}}"],check=True,capture_output=True)
 if git(root,"show","-s","--format=%T",BASE_HEAD)!=BASE_TREE:raise ContractError("base tree differs")
 head=git(root,"rev-parse","HEAD"); remote=git(root,"rev-parse","--verify","origin/phase/v23-expansion")
 if subprocess.run(["git","-C",str(root),"merge-base","--is-ancestor",BASE_HEAD,head],capture_output=True).returncode!=0:raise ContractError("base not ancestor")
 if head==BASE_HEAD and remote!=BASE_HEAD:raise ContractError("unsafe precommit remote")
 changed=set(git(root,"diff","--name-only",BASE_HEAD).splitlines())
 untracked=set(git(root,"ls-files","--others","--exclude-standard").splitlines())
 observed={p.replace("\\","/") for p in changed|untracked if p}
 if not set(TOOL_PATHS).issubset(observed) or not observed.issubset(set(FULL_FENCE)):
  raise ContractError(f"candidate paths outside/incomplete tooling fence: {sorted(observed)}")
def validate_sources(root:Path,artifact:dict[str,Any])->dict[str,int]:
 if artifact["sourceBindings"]!=source_bindings(root):raise ContractError("source bindings stale")
 for row in artifact["sourceBindings"]:
  item=root/row["path"]
  if sha(item.read_bytes())!=row["sha256"] or item.stat().st_size!=row["bytes"]:raise ContractError("source digest differs")
 required={
  PRODUCT_SOURCE_PATHS[0]:["ProtectedFilePolicyV1","OwnedFileKindV1","requiredFileProtection","applyAndVerify"],
  PRODUCT_SOURCE_PATHS[1]:["StoreGenerationFactory","current.json","retired.json","ModelContainer","model.sqlite"],
  PRODUCT_SOURCE_PATHS[2]:["BackupImportService","staging"],PRODUCT_SOURCE_PATHS[3]:["BackupRestoreService"],
  PRODUCT_SOURCE_PATHS[4]:["RestoreIntentStore"],PRODUCT_SOURCE_PATHS[5]:["DiagnosticsStore"],
  PRODUCT_SOURCE_PATHS[6]:["EvidenceBundleStore"],PRODUCT_SOURCE_PATHS[7]:["ReportRenderService"],
  PRODUCT_SOURCE_PATHS[8]:["FinalizationIntentStore"],PRODUCT_SOURCE_PATHS[9]:["EntitlementStore"],
  PRODUCT_SOURCE_PATHS[10]:["EraseIntentStore"],PRODUCT_SOURCE_PATHS[11]:["WholeSignDeletionService"],
  PRODUCT_SOURCE_PATHS[12]:["EraseAllService"]}
 for path,tokens in required.items():
  text=(root/path).read_text(encoding="utf-8")
  if any(token not in text for token in tokens):raise ContractError(f"source owner token differs: {path}")
 diagnostic=(root/READ_ONLY_CONSUMERS[0]["path"]).read_text(encoding="utf-8")
 if any(token not in diagnostic for token in ("DiagnosticExportV1","CanonicalJSONV1","app","counters","device","metricKit")):
  raise ContractError("S8.3 diagnostics allowlist source differs")
 if "BackupExportService" not in (root/READ_ONLY_CONSUMERS[1]["path"]).read_text(encoding="utf-8"):raise ContractError("external export delegate differs")
 if "ReportRecoveryService" not in (root/READ_ONLY_CONSUMERS[2]["path"]).read_text(encoding="utf-8"):raise ContractError("report recovery delegate differs")
 return {"fencedProductSourceCount":13,"readOnlyConsumerCount":3}
def validate_current(root:Path,artifact:dict[str,Any],privacy:dict[str,Any])->None:
 if artifact!=build_artifact(root) or privacy!=build_privacy(root):raise ContractError("generated semantics differ")
 if artifact["authority"]!=authority() or artifact["fullPathFence"]!=FULL_FENCE:raise ContractError("authority/fence differs")
 if len(FULL_FENCE)!=21 or len(set(FULL_FENCE))!=21 or artifact["authority"]["reservationOverlapCount"]!=0:raise ContractError("fence/reservation differs")
 if artifact["authority"]["authorizedPriorFenceOverlaps"]!=authority()["authorizedPriorFenceOverlaps"]:raise ContractError("overlap edges differ")
 if artifact["persistentChangeMode"]!="CONTENT_ONLY" or any(artifact["behavioralDelta"].values()):raise ContractError("behavior delta overclaim")
 matrix=artifact["ownedPathMatrix"]
 if matrix["backupIncluded"]!=INCLUDED or matrix["backupExcluded"]!=EXCLUDED or not matrix["closed"]:raise ContractError("owned path matrix differs")
 if [x["id"] for x in INCLUDED]!=["DURABLE_DATABASE","DURABLE_DATABASE_WAL","DURABLE_DATABASE_SHM","CURRENT_POINTER","RETIRED_POINTER","ORIGINAL_MEDIA","THUMBNAIL_MEDIA","REPORT_SNAPSHOT","REPORT_PDF"]:raise ContractError("included order differs")
 if any(row["backup"]!="INCLUDED" for row in INCLUDED) or any(row["backup"]!="EXCLUDED" for row in EXCLUDED):raise ContractError("backup disposition differs")
 if artifact["protectionLaw"]["recheckEvents"]!=RECHECK_EVENTS or artifact["protectionLaw"]["requiredProtection"]!="COMPLETE":raise ContractError("protection recheck law differs")
 if artifact["externalBackupDestination"]!={"owner":"BackupExportService","disposition":"EXTERNAL_PROVIDER_HANDOFF","appProtectionAttributeClaim":False,"providerDestinationEligibilityClaim":False}:raise ContractError("external handoff differs")
 if artifact["secretInventory"] or privacy["secretInventory"] or artifact["keychainUsage"]!="NONE" or privacy["keychainUsage"]!="NONE":raise ContractError("current secret inventory overclaims")
 if artifact["handlingClassDeclarations"]!=HANDLING_CLASSES or artifact["forbiddenSecretSurfaces"]!=FORBIDDEN_SECRET_SURFACES:raise ContractError("secret handling declarations differ")
 if privacy["diagnosticsAllowlist"]["sourceDigest"]!=artifact["sourceBindings"][13]["sha256"] or privacy["externalExportSource"]["sourceDigest"]!=artifact["sourceBindings"][14]["sha256"] or privacy["reportRecoverySource"]["sourceDigest"]!=artifact["sourceBindings"][15]["sha256"]:raise ContractError("read-only source binding differs")
 false_fields=("nativeCompileRan","hostedDispatchRan","physicalEvidenceComplete","adoptionEnabled","acceptanceEnabled","acceptanceCredit","releaseReady","releaseCredit","phase10PollingDuringParallelExecution")
 for item in (artifact,privacy):
  if any(item[k] for k in false_fields) or item["physicalLockedState"]!="REQUIRED_PENDING_OWNER" or not item["requiresAcceptedS10_6Reconciliation"]:raise ContractError("provisional flags overclaim")

def main()->int:
 root=Path(__file__).resolve().parents[2];validate_repository(root);checks=5
 expected=build_outputs(root)
 for rel,value in expected.items():
  if not (root/rel).is_file() or (root/rel).read_bytes()!=pretty(value):raise ContractError(f"generated output differs: {rel}")
  checks+=1
 artifact=load(root/ARTIFACT_PATH);privacy=load(root/PRIVACY_PATH);schema=load(root/SCHEMA_PATH)
 validate_schema(artifact,schema);verify_digest(artifact);verify_digest(privacy);validate_current(root,artifact,privacy);checks+=15
 counts=validate_sources(root,artifact);checks+=18
 for path in TOOL_PATHS[:3]:ast.parse((root/path).read_text(encoding="utf-8"),filename=path);checks+=1
 hostiles=0
 mutations=[
  (("authority","baseHead"),"0"*40),(("authority","contextDigest"),"0"*64),(("authority","pathFenceDigest"),"0"*64),
  (("authority","provisionalPrerequisiteDigest"),"0"*64),(("authority","registerRowDigest"),"0"*64),
  (("authority","dossierDigest"),"0"*64),(("authority","inheritedV21BlockDigest"),"0"*64),
  (("authority","facetManifestDigest"),"0"*64),(("authority","selectorManifestDigest"),"0"*64),
  (("authority","relationManifestDigest"),"0"*64),(("authority","impactManifestDigest"),"0"*64),
  (("authority","reservationOverlapCount"),1),(("authority","directPrerequisites"),["V23-P00-C08"]),
  (("fullPathFence",),FULL_FENCE[:-1]),(("persistentChangeMode",),"SCHEMA_CHANGE"),(("behavioralDelta","backupFormat"),True),
  (("ownedPathMatrix","backupIncluded"),INCLUDED[:-1]),(("ownedPathMatrix","backupExcluded"),EXCLUDED[:-1]),
  (("ownedPathMatrix","closed"),False),(("ownedPathMatrix","unknownDisposition"),"ALLOW"),
  (("protectionLaw","requiredProtection"),"NONE"),(("protectionLaw","recheckEvents"),RECHECK_EVENTS[:-1]),
  (("protectionLaw","physicalLockedVerification"),"PASS"),(("externalBackupDestination","disposition"),"APP_OWNED"),
  (("externalBackupDestination","appProtectionAttributeClaim"),True),(("secretInventory",),[{"secret":"invented"}]),
  (("handlingClassDeclarations",),HANDLING_CLASSES[:-1]),(("forbiddenSecretSurfaces",),FORBIDDEN_SECRET_SURFACES[:-1]),
  (("keychainUsage",),"USED"),(("nativeCompileRan",),True),(("hostedDispatchRan",),True),
  (("physicalEvidenceComplete",),True),(("adoptionEnabled",),True),(("acceptanceEnabled",),True),
  (("acceptanceCredit",),True),(("releaseReady",),True),(("releaseCredit",),True),
  (("requiresAcceptedS10_6Reconciliation",),False),(("phase10PollingDuringParallelExecution",),True),
  (("sourceBindings",0,"sha256"),"0"*64),(("lifecycle","recovery"),"IGNORE_STALE")]
 for path,replacement in mutations:
  hostile=mutate(artifact,path,replacement);reject(lambda value=hostile:validate_current(root,value,privacy));hostiles+=1
 privacy_mutations=[
  (("secretInventory",),[{"secret":"invented"}]),(("keychainUsage",),"USED"),
  (("diagnosticsAllowlist","sourceDigest"),"0"*64),(("externalExportSource","sourceDigest"),"0"*64),
  (("reportRecoverySource","sourceDigest"),"0"*64),(("appProtectionAttributeClaimForExternalDestination",),True)]
 for path,replacement in privacy_mutations:
  hostile=mutate(privacy,path,replacement);reject(lambda value=hostile:validate_current(root,artifact,value));hostiles+=1
 extra=copy.deepcopy(artifact);extra["extra"]=1;reject(lambda:validate_schema(extra,schema));hostiles+=1
 bad=copy.deepcopy(artifact);bad["artifactDigest"]="0"*64;reject(lambda:verify_digest(bad));hostiles+=1
 checks+=hostiles+3
 manifest=load(root/MANIFEST_PATH)
 if manifest!=build_manifest(root) or manifest["artifactCount"]!=6 or manifest["pathFence"]!=TOOL_PATHS or manifest["fullCardFence"]!=FULL_FENCE:raise ContractError("manifest differs")
 verify_digest(manifest)
 for row in manifest["artifacts"]:
  if sha((root/row["path"]).read_bytes())!=row["sha256"]:raise ContractError("manifest hash differs")
 checks+=4
 run=subprocess.run([sys.executable,"-B",str(root/"Scripts/v23/generate_p01_c02_contracts.py"),"--check","--root",str(root)],check=True,capture_output=True,text=True,env={**os.environ,"PYTHONDONTWRITEBYTECODE":"1"})
 if "PASS V23-P01-C02 generated=4 check=True" not in run.stdout:raise ContractError("generator check differs")
 checks+=1
 print(json.dumps({"result":"PASS","cardID":CARD,"checks":checks,"hostileMutationCount":hostiles,
  "backupIncludedClassCount":len(INCLUDED),"backupExcludedClassCount":len(EXCLUDED),"secretInventoryCount":0,
  "handlingClassCount":len(HANDLING_CLASSES),**counts,"nativeCompileRan":False,"hostedDispatchRan":False,
  "physicalEvidenceComplete":False,"physicalLockedState":"REQUIRED_PENDING_OWNER","adoptionEnabled":False,
  "acceptanceCredit":False,"releaseReady":False,"releaseCredit":False,"requiresAcceptedS10_6Reconciliation":True,
  "phase10PollingDuringParallelExecution":False},sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
