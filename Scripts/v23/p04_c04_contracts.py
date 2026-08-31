#!/usr/bin/env python3
"""Fail-closed static tooling contracts for V23-P04-C04."""
from __future__ import annotations
import ast, hashlib, json, os, re, subprocess, sys
from pathlib import Path
from typing import Any
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]; CARD="V23-P04-C04"; TITLE="Shop profile and branded open evidence handoff"; ORDINAL=92
BASE_HEAD="f3cb7ef2c1cc55e6306bb8073aebdf7d243dfa21"; BASE_TREE="26684b3fe7ee2e1a6af5c472dd13c1b2ffcae9de"
COORD_HEAD="c38ed75094359ec7911819c9a7f70c3bb7d93a1f"; COORD_TREE="9c3756d7b017e25d06f901749526b128ce34ab24"; SEQUENCE=402
CONTEXT="09d54679c2fe07482b840e273578c4dca61baf6a712fac9eeb188c1194fa2ba4"; FENCE="010964bbec129d28573349d4631f5b54caa4b8b4f1e7b239763e532da612bf42"; PREREQUISITE="bd4a15519b591cd3d1d60ef44e70323deab2c3d433342eda9da9d31da8af7836"; TRANSITION="cf496c588c0a043446fe31a92822436a1f2dcf8397807c637f40e9138f5107d7"; LEDGER="2ad178fb846cefbd6f68b2d355ffc9e6713389d047dfdd16f866701098e0c01a"; PROJECTION="9e43772eb70bb16ade49b97b86be757323eb5e1b6341124049f99cb81eda4afd"
SOURCE_PINS={"dossierUTF8Length":7457,"dossierSHA256":"5253a8ff89b283378208887d1110bdd5edb94c2634a4ab2122d0f6c016a6efc3","inheritedV21BlockUTF8Length":9340,"inheritedV21BlockSHA256":"ef4f0f9c22be6821a85a21dbcf10c62d5c185ba31fffc9178ad083d8f8ddac12","registerRowUTF8Length":243,"registerRowSHA256":"7d3d6d52a321934e3cc492201cd422374ba5b18b89540b743ead160f11021672","registerSectionUTF8Length":44217,"registerSectionSHA256":"3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"}
IMPLEMENTATION_PATHS=("FieldEvidenceApp/Domain/Reporting/ShopReportProfileContractsV1.swift","FieldEvidenceApp/Domain/Models/ShopReportProfilePersistenceModelsV1.swift","FieldEvidenceApp/Application/Reporting/ShopReportProfileCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Reporting/ShopReportProfileLifecycleAdapterV1.swift","FieldEvidenceApp/Features/Reporting/ShopProfileOpenEvidenceHandoffView.swift","FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests.swift","FieldEvidenceAppTests/Fixtures/V22/Reporting/V22P04C04ShopProfileOpenHandoffCorpusV1.json")
SCHEMA_PATH="Scripts/v23/shop-report-profile.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P04C04ShopReportProfileContractV1.json"; EVIDENCE_PATH="docs/design/v23/tooling/V23P04C04ShopProfileOpenHandoffEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P04C04BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P04-C04-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p04_c04_contracts.py","Scripts/v23/generate_p04_c04_contracts.py","Scripts/v23/verify_p04_c04_contracts.py"); GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH); TOOLING_EDIT_PATHS=(*SCRIPT_PATHS,*GENERATED_PATHS); NEW_PATHS=(*IMPLEMENTATION_PATHS,*TOOLING_EDIT_PATHS); OUTPUT_PATHS=GENERATED_PATHS
EVIDENCE_SUFFIXES=("G01","A01","H01","I01","R01"); EVIDENCE_IDS=tuple(f"{CARD}-{x}" for x in EVIDENCE_SUFFIXES); FINAL_HASHES_SEALED=True
FLAGS={x:False for x in ("activation","native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}; _TEXT={".json",".py",".swift",".md",".xcstrings",".plist",".schema"}; _BASE=None
def strict(pairs):
 d={}
 for k,v in pairs:
  if k in d:raise ValueError("duplicate JSON key:"+k)
  d[k]=v
 return d
def canonical(v):return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def pretty(v):return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def sha(b):return hashlib.sha256(b).hexdigest()
def file_bytes(p):
 b=p.read_bytes();return b.replace(b"\r\n",b"\n").replace(b"\r",b"\n") if p.suffix.lower() in _TEXT else b
def git(root,*a):return subprocess.run(["git",*a],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
def coord():
 for p in (Path(r"C:\AssetRounds-v23-coordination"),ROOT.parent/"AssetRounds-v23-coordination"):
  if (p/"contexts/V23-P04-C04-attempt-1/BootstrapCardContextV1.json").is_file():return p
 raise ValueError("C04 coordination unavailable")
def cjson(rel):return json.loads((coord()/rel).read_text(encoding="utf-8"),object_pairs_hook=strict)
def hydrate():
 c=cjson("contexts/V23-P04-C04-attempt-1/BootstrapCardContextV1.json");f=cjson("contexts/V23-P04-C04-attempt-1/BootstrapPathFenceV1.json")
 if (c.get("contextDigest"),f.get("fenceDigest"),c.get("provisionalPrerequisiteDigest"))!=(CONTEXT,FENCE,PREREQUISITE):raise ValueError("C04 coordination digest differs")
 e=tuple(c.get("existingPaths",()));n=tuple(c.get("newPaths",()));a=tuple(f.get("allowedCreateOrReplacePaths",()))
 if n!=NEW_PATHS or a!=e+n or len(e)!=318 or len(n)!=15 or len(a)!=333 or len(set(a))!=333:raise ValueError("C04 hydrated path fence differs")
 if f.get("priorFenceProof",{}).get("authorizedOverlapCount")!=6224 or f.get("priorFenceProof",{}).get("unauthorizedOverlapCount")!=0 or set(a)&set(f.get("activeS10ReservedPaths",())):raise ValueError("C04 overlap/S10 differs")
 return e,n
EXISTING_PATHS,_HYDRATED_NEW=hydrate(); PATH_FENCE=EXISTING_PATHS+_HYDRATED_NEW; MANIFEST_INPUT_PATHS=tuple(x for x in PATH_FENCE if x!=MANIFEST_PATH)
def source_status(root):
 missing=[x for x in IMPLEMENTATION_PATHS if not (root/x).is_file()];return {"hydrated":not missing,"missingPaths":missing,"presentPaths":[x for x in IMPLEMENTATION_PATHS if x not in missing]}
def selectors(root):
 p=root/IMPLEMENTATION_PATHS[5]
 return tuple(re.findall(r"(?m)^\s*func\s+(testV23P04C04(?:G|A|H|I|R)01[A-Za-z0-9_]*)\s*\(",p.read_text(encoding="utf-8"))) if p.is_file() else ()
def assert_scaffold(root):
 if git(root,"show","-s","--format=%T",BASE_HEAD)!=BASE_TREE:raise ValueError("C04 app base differs")
 q=coord()
 if (git(q,"rev-parse","HEAD"),git(q,"show","-s","--format=%T","HEAD"),git(q,"rev-parse","origin/main"))!=(COORD_HEAD,COORD_TREE,COORD_HEAD):raise ValueError("C04 coordination identity differs")
 if len(PATH_FENCE)!=333 or PATH_FENCE!=EXISTING_PATHS+_HYDRATED_NEW:raise ValueError("C04 exact path ordering differs")
def assert_source_contracts(root):
 s=source_status(root)
 if s["missingPaths"]:raise ValueError("C04 source missing:"+",".join(s["missingPaths"]))
 text="\n".join((root/x).read_text(encoding="utf-8") for x in IMPLEMENTATION_PATHS[:5]); tests=(root/IMPLEMENTATION_PATHS[5]).read_text(encoding="utf-8"); fixture=json.loads((root/IMPLEMENTATION_PATHS[6]).read_text(encoding="utf-8"),object_pairs_hook=strict)
 for token in ("SHOP_REPORT_PROFILE_V1","backup","restore","delete","erase","clone","fork","journal","replay","exact","privacy","confirmation","renderer","PDF","JSON","CSV","media","manifest","remote"):
  if token.lower() not in (text+json.dumps(fixture)).lower():raise ValueError("C04 semantic source proof missing:"+token)
 recovery=fixture.get("recoveryCases");hostile=fixture.get("hostileCases");delivery=fixture.get("delivery")
 if not isinstance(recovery,list) or "migration" not in recovery or not all(token in text for token in ("ShopReportProfileV1","schemaVersion","persistentKind")):raise ValueError("C04 typed persistent migration proof missing")
 if not isinstance(hostile,list) or "active-content" not in hostile or not all(token in text+tests for token in ("ClosedContractDecodingV1.rejectUnknownKeys","secondRenderer")):raise ValueError("C04 closed active-content rejection proof missing")
 if not isinstance(delivery,dict) or delivery.get("boundedBulkJobOnly") is not True or not all(token in text+tests for token in ("ShopReportProfileLimitsV1","maximumBulkHandoffs","maximumHistoryRevisions","prepareBulk")):raise ValueError("C04 bounded lifecycle proof missing")
 found=selectors(root)
 prefix="testV23P04C04"
 if len(found)!=5 or tuple(name[len(prefix):len(prefix)+3] for name in found)!=EVIDENCE_SUFFIXES:raise ValueError("C04 exact five selectors differ")
 return found
def authority():return {"cardID":CARD,"registerOrdinal":ORDINAL,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORD_HEAD,"coordinationTree":COORD_TREE,"coordinationSequence":SEQUENCE,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"prerequisiteDigest":PREREQUISITE,"hydrationTransitionDigest":TRANSITION,"coordinationLedgerDigest":LEDGER,"coordinationProjectionDigest":PROJECTION,"sourcePins":SOURCE_PINS,"existingPathCount":318,"newPathCount":15,"fencePathCount":333,"authorizedOverlapCount":6224,"unauthorizedOverlapCount":0,"s10ReservationOverlapCount":0,"finalHashesSealed":FINAL_HASHES_SEALED}
def common():return {"cardID":CARD,"title":TITLE,"authority":authority(),"evidenceIDs":list(EVIDENCE_IDS),"statusFlags":FLAGS,"nativeCompileRan":False,"hostedDispatchEnabled":False,"adoptionEnabled":False,"acceptanceEnabled":False,"releaseCredit":False,"physicalEvidenceComplete":False,"requiresAcceptedS10_6Reconciliation":True,"finalHashesSealed":FINAL_HASHES_SEALED,"provisional":not FINAL_HASHES_SEALED}
def source_rows(root):return [{"path":x,"byteCount":len(file_bytes(root/x)) if (root/x).is_file() else None,"sha256":sha(file_bytes(root/x)) if (root/x).is_file() else None,"status":"SEALED_SOURCE" if (root/x).is_file() else "PENDING_SOURCE"} for x in IMPLEMENTATION_PATHS]
def sealed(v):return {**v,"artifactDigest":sha(pretty(v)) if FINAL_HASHES_SEALED else None}
def outputs(root):
 assert_scaffold(root);s=source_status(root);sel=assert_source_contracts(root) if s["hydrated"] else selectors(root); semantics={"persistentFamily":"SHOP_REPORT_PROFILE_V1","schemaVersion":44,"selectors":list(sel),"evidenceIDs":list(EVIDENCE_IDS),"oneIncumbentRenderer":True,"formats":["PDF","OPEN_JSON","TEXT","FORMULA_SAFE_CSV","MEDIA","HASH_MANIFEST"],"confirmation":"IMMUTABLE_ORIGINAL_PRIVACY_DERIVATIVE_REVIEWED_MARKUP_DETAILS_EXACT_BYTES","lifecycle":["FIRST_WRITE","MIGRATION","JOURNAL","BACKUP","RESTORE","DELETE","ERASE","CLONE","FORK","CONFIGURATION","EXPORT","REPORT","REPLAY"],"rejects":["ACTIVE_CONTENT","UNBOUNDED","REMOTE"],"allExistingProfilesRemainOff":True,"ui":"STANDALONE_VIEW_ONLY_POST_S10_SETTINGS_AND_FINALIZATION_UNTOUCHED"}
 schema={"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/shop-report-profile.schema.json","type":"object","additionalProperties":False,"properties":{"schema":{"const":"SHOP_REPORT_PROFILE_V1"},"schemaVersion":{"const":44},"cardID":{"const":CARD},"selectors":{"const":list(sel)},"statusFlags":{"const":FLAGS},"semantics":{"const":semantics}},"required":["schema","schemaVersion","cardID","selectors","statusFlags","semantics"]}
 contract=sealed({"schema":"V23P04C04ShopReportProfileContractV1","schemaVersion":1,**common(),"semantics":semantics,"sourceRows":source_rows(root)})
 evidence=sealed({"schema":"V23P04C04ShopProfileOpenHandoffEvidenceReceiptV1","schemaVersion":1,**common(),"testSelectors":list(sel),"cases":[{"evidenceID":x,"selectorSuffix":y} for x,y in zip(EVIDENCE_IDS,EVIDENCE_SUFFIXES)],"semantics":semantics})
 brand=sealed({"schema":"V23P04C04BrandImpactManifestV1","schemaVersion":1,**common(),"iPhoneNativeOnly":True,"nativeIPadSurface":False,"uiAdoptionSkipped":True,"networkOrTelemetryFlow":False,"semantics":semantics})
 rendered={SCHEMA_PATH:pretty(schema),CONTRACT_PATH:pretty(contract),EVIDENCE_PATH:pretty(evidence),BRAND_PATH:pretty(brand)};rows=[]
 for x in MANIFEST_INPUT_PATHS:
  b=rendered.get(x) if x in rendered else (file_bytes(root/x) if (root/x).is_file() else None);rows.append({"path":x,"byteCount":len(b) if b is not None else None,"sha256":sha(b) if b is not None else None,"status":"SEALED_TOOLING" if x in rendered or x in TOOLING_EDIT_PATHS and b is not None else ("SEALED_SOURCE" if b is not None else "PENDING_SOURCE")})
 manifest=sealed({"schema":"V23-P04-C04-tooling-manifest","schemaVersion":1,**common(),"pathFence":list(PATH_FENCE),"existingPaths":list(EXISTING_PATHS),"newPaths":list(NEW_PATHS),"toolingEditPaths":list(TOOLING_EDIT_PATHS),"files":rows,"manifestInputCount":len(rows),"hashDisposition":"SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED"})
 rendered[MANIFEST_PATH]=pretty(manifest);return rendered
if __name__=="__main__":
 assert_scaffold(ROOT);print(json.dumps({"cardID":CARD,"fencePathCount":len(PATH_FENCE),"sourceReady":source_status(ROOT)["hydrated"],"finalHashesSealed":FINAL_HASHES_SEALED},sort_keys=True))
