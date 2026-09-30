#!/usr/bin/env python3
"""Fail-closed static tooling contracts for V23-P04-C05."""
from __future__ import annotations
import ast, hashlib, json, os, re, subprocess, sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]; CARD="V23-P04-C05"; TITLE="RoundSession expected/visited/deferred completeness, schema, state machine, and interruption recovery"; ORDINAL=93
BASE_HEAD="1e8c1677c728bf0284fab8a5ec56d05c60e4569f"; BASE_TREE="c6ed43e0ec81a5aa918c6f44f115abdc0ea2da9a"; COORD_HEAD="5113779caf0b172558fd6353b204c91c2731cb83"; COORD_TREE="2091cce9c748d3accad53a1ed45cbe1c68335760"; SEQUENCE=406
CONTEXT="0da6087d34e3145e7516435c5458bae772f288c7646b70c941f0a905d0694667"; FENCE="1bf82731526fa55f0f91c53f30a38cea7b246ef1c23ee93c7e4cb1c7398bab31"; PREREQUISITE="0e38ca0608ec7a05a42950067c0e06907ed3d89ffe838ba6eb93b6096d6c33ef"; TRANSITION="ed2c77b7c7ba08ba2d1ba26b6dcf1796c2ed25ba359f1f4dae1ecb5c6ba3a201"; LEDGER="db30a4b53c92c792f3177ce9ce75ff4986d688c2e570a70f522283bc3de82780"; PROJECTION="ecbd9c5b2bc21bbce3b6909afffbd8210f02cb6627257094e3025c25db8a57f5"
SOURCE_PINS={"dossierUTF8Length":7302,"dossierSHA256":"08d1f049f78f4c87b202950f66838bdf83a41681c30db30d56ce2e21401dba16","inheritedV21BlockUTF8Length":7704,"inheritedV21BlockSHA256":"5597a5c732bf39d54ca79726b8fda0489be7e944648eaa3284194a505fd4731f","registerRowUTF8Length":298,"registerRowSHA256":"ffa09098c32e7200890104c36dcaacc8b2f2344b73f8d688428442f0ba8f39c0","registerSectionUTF8Length":44217,"registerSectionSHA256":"3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"}
IMPLEMENTATION_PATHS=("FieldEvidenceApp/Domain/Rounds/RoundSessionContractsV1.swift","FieldEvidenceApp/Domain/Models/RoundSessionPersistenceModelsV1.swift","FieldEvidenceApp/Application/Rounds/RoundSessionCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Rounds/RoundSessionLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_70RoundSessionStateTests.swift","FieldEvidenceAppTests/Fixtures/V22/Rounds/V22P04C05RoundSessionCorpusV1.json")
SCHEMA_PATH="Scripts/v23/round-session.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P04C05RoundSessionContractV1.json"; EVIDENCE_PATH="docs/design/v23/tooling/V23P04C05RoundSessionEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P04C05BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P04-C05-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p04_c05_contracts.py","Scripts/v23/generate_p04_c05_contracts.py","Scripts/v23/verify_p04_c05_contracts.py"); GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH); TOOLING_EDIT_PATHS=(*SCRIPT_PATHS,*GENERATED_PATHS); NEW_PATHS=(*IMPLEMENTATION_PATHS,*TOOLING_EDIT_PATHS); OUTPUT_PATHS=GENERATED_PATHS; EVIDENCE_SUFFIXES=("G01","A01","H01","I01","R01"); EVIDENCE_IDS=tuple(f"{CARD}-{x}" for x in EVIDENCE_SUFFIXES); FINAL_HASHES_SEALED=True
FLAGS={x:False for x in ("activation","native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}; TEXT={".json",".py",".swift",".md",".xcstrings",".plist",".schema"}
def strict(pairs):
 d={}
 for k,v in pairs:
  if k in d:raise ValueError("duplicate JSON key:"+k)
  d[k]=v
 return d
def pretty(v):return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def sha(b):return hashlib.sha256(b).hexdigest()
def file_bytes(p):
 b=p.read_bytes();return b.replace(b"\r\n",b"\n").replace(b"\r",b"\n") if p.suffix.lower() in TEXT else b
def git(root,*a):return subprocess.run(["git",*a],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
def coord():
 for p in (Path(r"C:\AssetRounds-v23-coordination"),ROOT.parent/"AssetRounds-v23-coordination"):
  if (p/"contexts/V23-P04-C05-attempt-1/BootstrapCardContextV1.json").is_file():return p
 raise ValueError("C05 coordination unavailable")
def cjson(rel):return json.loads((coord()/rel).read_text(encoding="utf-8"),object_pairs_hook=strict)
def hydrate():
 c=cjson("contexts/V23-P04-C05-attempt-1/BootstrapCardContextV1.json");f=cjson("contexts/V23-P04-C05-attempt-1/BootstrapPathFenceV1.json")
 if (c.get("contextDigest"),f.get("fenceDigest"),c.get("provisionalPrerequisiteDigest"))!=(CONTEXT,FENCE,PREREQUISITE):raise ValueError("C05 coordination digest differs")
 e=tuple(c.get("existingPaths",()));n=tuple(c.get("newPaths",()));a=tuple(f.get("allowedCreateOrReplacePaths",()))
 if n!=NEW_PATHS or a!=e+n or len(e)!=333 or len(n)!=14 or len(a)!=347 or len(set(a))!=347:raise ValueError("C05 hydrated path fence differs")
 proof=f.get("priorFenceProof",{})
 if proof.get("authorizedOverlapCount")!=6557 or proof.get("unauthorizedOverlapCount")!=0 or set(a)&set(f.get("activeS10ReservedPaths",())):raise ValueError("C05 overlap/S10 differs")
 return e,n
EXISTING_PATHS,_HYDRATED_NEW=hydrate();PATH_FENCE=EXISTING_PATHS+_HYDRATED_NEW;MANIFEST_INPUT_PATHS=tuple(x for x in PATH_FENCE if x!=MANIFEST_PATH)
def source_status(root):
 missing=[x for x in IMPLEMENTATION_PATHS if not(root/x).is_file()];return {"hydrated":not missing,"missingPaths":missing,"presentPaths":[x for x in IMPLEMENTATION_PATHS if x not in missing]}
def selectors(root):
 p=root/IMPLEMENTATION_PATHS[4];return tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C05(?:G|A|H|I|R)01[A-Za-z0-9_]*)\s*\(",p.read_text(encoding="utf-8"))) if p.is_file() else ()
def assert_scaffold(root):
 if git(root,"show","-s","--format=%T",BASE_HEAD)!=BASE_TREE:raise ValueError("C05 app base differs")
 q=coord()
 if (git(q,"rev-parse","HEAD"),git(q,"show","-s","--format=%T","HEAD"),git(q,"rev-parse","origin/main"))!=(COORD_HEAD,COORD_TREE,COORD_HEAD):raise ValueError("C05 coordination identity differs")
 if len(PATH_FENCE)!=347 or PATH_FENCE!=EXISTING_PATHS+_HYDRATED_NEW:raise ValueError("C05 exact path ordering differs")
def assert_source_contracts(root):
 s=source_status(root)
 if s["missingPaths"]:raise ValueError("C05 source missing:"+",".join(s["missingPaths"]))
 text="\n".join((root/x).read_text(encoding="utf-8") for x in IMPLEMENTATION_PATHS[:4]);tests=(root/IMPLEMENTATION_PATHS[4]).read_text(encoding="utf-8");fixture=json.loads((root/IMPLEMENTATION_PATHS[5]).read_text(encoding="utf-8"),object_pairs_hook=strict);combined=(text+tests+json.dumps(fixture)).lower()
 for token in ("round_session_v1","expected","visited","completed","inaccessible","skipped","deferred","migration","backup","restore","clone","fork","import","export","report","journal","replay","search","rebuild","delete","erase","streaming","archive","network"):
  if token not in combined:raise ValueError("C05 semantic source proof missing:"+token)
 persistence_paths=("FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift","FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift","FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift")
 persistence="".join((root/x).read_text(encoding="utf-8") for x in persistence_paths).replace(" ","").replace("\n","")
 for mechanism in ("PersistentSchemaV45","RoundSessionRevisionRowV1","models.count==146","currentRecordsSchemaVersion=44","kindIDs.count==364","laterTemporalOrigins.count==301","durableKindIDs.count==179"):
  if mechanism not in persistence:raise ValueError("C05 persistence mechanism missing:"+mechanism)
 found=selectors(root);prefix="testV23P04C05"
 if len(found)!=5 or tuple(x[len(prefix):len(prefix)+3] for x in found)!=EVIDENCE_SUFFIXES:raise ValueError("C05 exact five selectors differ")
 return found
def authority():return {"cardID":CARD,"registerOrdinal":ORDINAL,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORD_HEAD,"coordinationTree":COORD_TREE,"coordinationSequence":SEQUENCE,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"prerequisiteDigest":PREREQUISITE,"hydrationTransitionDigest":TRANSITION,"coordinationLedgerDigest":LEDGER,"coordinationProjectionDigest":PROJECTION,"sourcePins":SOURCE_PINS,"existingPathCount":333,"newPathCount":14,"fencePathCount":347,"authorizedOverlapCount":6557,"unauthorizedOverlapCount":0,"s10ReservationOverlapCount":0,"finalHashesSealed":FINAL_HASHES_SEALED}
def common():return {"cardID":CARD,"title":TITLE,"authority":authority(),"evidenceIDs":list(EVIDENCE_IDS),"statusFlags":FLAGS,"nativeCompileRan":False,"hostedDispatchEnabled":False,"adoptionEnabled":False,"acceptanceEnabled":False,"releaseCredit":False,"physicalEvidenceComplete":False,"requiresAcceptedS10_6Reconciliation":True,"finalHashesSealed":FINAL_HASHES_SEALED,"provisional":not FINAL_HASHES_SEALED}
def source_rows(root):return [{"path":x,"byteCount":len(file_bytes(root/x)) if (root/x).is_file() else None,"sha256":sha(file_bytes(root/x)) if (root/x).is_file() else None,"status":"SEALED_SOURCE" if (root/x).is_file() else "PENDING_SOURCE"} for x in IMPLEMENTATION_PATHS]
def sealed(v):return {**v,"artifactDigest":sha(pretty(v)) if FINAL_HASHES_SEALED else None}
def outputs(root):
 assert_scaffold(root);s=source_status(root);sel=assert_source_contracts(root) if s["hydrated"] else selectors(root);semantics={"persistentFamily":"ROUND_SESSION_V1","schemaVersion":45,"models":146,"records":44,"lifecycleCatalog":{"total":364,"laterOrigins":301,"durable":179},"selectors":list(sel),"evidenceIDs":list(EVIDENCE_IDS),"counts":["EXPECTED","VISITED","COMPLETED","INACCESSIBLE","SKIPPED","DEFERRED"],"stateMachine":"LEGAL_BOUNDED_ORDERED_ROUND_ITEMS","closeout":"BLOCK_UNDISPOSITIONED_EXPECTED_ITEMS","interruption":"IDEMPOTENT_JOURNAL_RETRY_AND_RESUME","lifecycle":["MIGRATION","BACKUP","RESTORE","CLONE","FORK","IMPORT","EXPORT","REPORT","JOURNAL","REPLAY","SEARCH","REBUILD","DELETE","ERASE","STREAMING_ARCHIVE"],"absent":["ROUTE_AUTOMATION","QR","RECURRENCE","DUE","REMINDER","NETWORK","TEAM_DISPATCH"],"ui":"NO_UI_C05_C07_OWNS_SURFACE","allExistingProfilesRemainOff":True}
 schema={"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/round-session.schema.json","type":"object","additionalProperties":False,"properties":{"schema":{"const":"ROUND_SESSION_V1"},"schemaVersion":{"const":45},"cardID":{"const":CARD},"selectors":{"const":list(sel)},"statusFlags":{"const":FLAGS},"semantics":{"const":semantics}},"required":["schema","schemaVersion","cardID","selectors","statusFlags","semantics"]}
 contract=sealed({"schema":"V23P04C05RoundSessionContractV1","schemaVersion":1,**common(),"semantics":semantics,"sourceRows":source_rows(root)})
 evidence=sealed({"schema":"V23P04C05RoundSessionEvidenceReceiptV1","schemaVersion":1,**common(),"testSelectors":list(sel),"cases":[{"evidenceID":x,"selectorSuffix":y} for x,y in zip(EVIDENCE_IDS,EVIDENCE_SUFFIXES)],"semantics":semantics})
 brand=sealed({"schema":"V23P04C05BrandImpactManifestV1","schemaVersion":1,**common(),"iPhoneNativeOnly":True,"nativeIPadSurface":False,"uiAdoptionSkipped":True,"networkOrTelemetryFlow":False,"semantics":semantics})
 rendered={SCHEMA_PATH:pretty(schema),CONTRACT_PATH:pretty(contract),EVIDENCE_PATH:pretty(evidence),BRAND_PATH:pretty(brand)};rows=[]
 for x in MANIFEST_INPUT_PATHS:
  b=rendered.get(x) if x in rendered else (file_bytes(root/x) if(root/x).is_file() else None);rows.append({"path":x,"byteCount":len(b) if b is not None else None,"sha256":sha(b) if b is not None else None,"status":"SEALED_TOOLING" if x in rendered or x in TOOLING_EDIT_PATHS and b is not None else ("SEALED_SOURCE" if b is not None else "PENDING_SOURCE")})
 manifest=sealed({"schema":"V23-P04-C05-tooling-manifest","schemaVersion":1,**common(),"pathFence":list(PATH_FENCE),"existingPaths":list(EXISTING_PATHS),"newPaths":list(NEW_PATHS),"toolingEditPaths":list(TOOLING_EDIT_PATHS),"files":rows,"manifestInputCount":len(rows),"hashDisposition":"SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"});rendered[MANIFEST_PATH]=pretty(manifest);return rendered
if __name__=="__main__":assert_scaffold(ROOT);print(json.dumps({"cardID":CARD,"fencePathCount":len(PATH_FENCE),"sourceReady":source_status(ROOT)["hydrated"],"missingPaths":source_status(ROOT)["missingPaths"],"finalHashesSealed":FINAL_HASHES_SEALED},sort_keys=True))
