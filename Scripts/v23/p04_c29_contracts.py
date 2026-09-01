from __future__ import annotations
import copy, hashlib, json, os, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; CARD='V23-P04-C29'; BASE='8b97b33a0c83d639349d9c28806092fdeb79b95f'; BTREE='0c804ceb7b50a5b804b1380762408aedac644d2d'; HEAD='3be7e1ac1cb8e8c046f4a02d8c6c450a14078c05'; CTREE='60748a754f7fb5e2ce12af18df1fe8414aa20ffb'; SEQ=512
CONTEXT='fb26f88b4599f31c2f7f47f9ec866651420ef3e612d0cdc80c8d745c84079dd6'; FENCE='ed507cde4b113ad321771f47f598b76c84f7f8d7ec147217bad819e6f46ffd25'; ALLOCATION='753e9ab7bf0c2a0f7c9bcabffb36b1d703073b9f88bf315dcd04a459ff5e60ab'; PREREQ='5e8367a8417e66691fa2a82723d5084e4734650e5e8921dd16175f36238c73aa'; FINAL_HASHES_SEALED=False
PRODUCT='docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json'; TEST='FieldEvidenceAppTests/V9_92ExactCandidateRegressionFreezeTests.swift'; FIXTURE='FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C29ExactCandidateRegressionFreezeCorpusV1.json'; UI='FieldEvidenceAppUITests/V23_P04_C29ExactCandidateRegressionFreezeUITests.swift'; SCHEMA='Scripts/v23/exact-candidate-regression-freeze.schema.json'; CONTRACT='docs/design/v23/tooling/V23P04C29ExactCandidateRegressionFreezeContractV1.json'; EVIDENCE='docs/design/v23/tooling/V23P04C29ExactCandidateRegressionFreezeEvidenceReceiptV1.json'; BRAND='docs/design/v23/tooling/V23P04C29BrandImpactManifestV1.json'; MANIFEST='docs/design/v23/tooling/V23-P04-C29-tooling-manifest.json'
SCRIPTS=('Scripts/v23/p04_c29_contracts.py','Scripts/v23/generate_p04_c29_contracts.py','Scripts/v23/verify_p04_c29_contracts.py'); OWNED=set((*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)); PATH_FENCE=('Scripts/release-preflight.sh','FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift',PRODUCT,TEST,FIXTURE,UI,*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=('testV23P04C29G01ExactCandidateFreezeBindsBrandHIGAccessibilityLocalizationJourneyAndReleaseState','testV23P04C29A01MinimumIOS18AndLatestStableResolveSeparatelyWithSemanticParity','testV23P04C29H01UnknownStaleCorruptCoverageContrastAccessibilityLocalizationJourneyAndReleaseDriftFailClosed','testV23P04C29I01ManifestLastInterruptionPreservesCandidateAndNoPartialReceipt','testV23P04C29R01DeterministicRetryPreservesFrozenCandidateWithoutPromotion')
PINS={'V23-P04-C29':(7185,'3e8b18ef2985c9083434a5f4abba86463c5bb5acc35b6ac8ea6a09e16421dcaa'),'V21-P04-C29':(16006,'3c985b54dc307b44551fa4146da28799bde8cd5b290a1506d1a1fc596f7208eb'),'V23-P04-C29-register':(304,'ce5978f7f73f1998ab3947483655a609654624bbdd659aabe781d9b06433b3b5')}
C28={'head':BASE,'tree':BTREE,'checkpointDigest':'61072c481d9c1acedf2e91bcc3759d161ad12fbfb67f2f1c8c35ea491d5769d6','verificationReceiptDigest':'b657cffb50c5989d7979e93d5e51b419dc4fc47b91c787b525850ff70cc53544','registerOrdinalCorrectionDigest':'46391ee5ee56b7f104b3173a9bc72eb9f7d17332b0f8b820a73ceba51dcae949'}; P00={'cardID':'V23-P00-C13','checkpointDigest':'8aa76625bee8c70277a41e2212f814604dac32f4600ab1954db4af4c90713b47','verificationReceiptDigest':'cba3785a50588c1bceddaaaabac2736b2256c3da017bd31eaef8f124342f4482'}; FLAGS={k:False for k in ('physicalDevice','native','hosted','activation','adoption','acceptance','publication','release')}; S10_DIGEST='274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a'
def pretty(x):return (json.dumps(x,sort_keys=True,indent=2)+'\n').encode()
def sha(x):return hashlib.sha256(x).hexdigest()
def git(*a,cwd=ROOT):return subprocess.run(['git',*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def coord_root():
 o=os.environ.get('V23_P04_C29_COORDINATION_ROOT'); p=None if o=='NONE' else Path(o) if o else ROOT.parent/'AssetRounds-v23-coordination'; return p.resolve() if p and p.is_dir() else None
def source_pins():
 if git('rev-parse',BASE+'^{tree}')!=BTREE:raise ValueError('C29 base tree differs')
 bp=subprocess.run(['git','show',BASE+':docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md'],cwd=ROOT,check=True,capture_output=True).stdout; fp=subprocess.run(['git','show',BASE+':docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md'],cwd=ROOT,check=True,capture_output=True).stdout
 def block(n,i):
  m=re.search(rf'(?ms)^{i}### {re.escape(n)} —.*?(?=^{i}### |\Z)',bp.decode());
  if not m:raise ValueError('C29 source missing '+n)
  return m.group(0).encode()
 at=fp.index(b'P04-C29'); row=fp[fp.rfind(b'\n',0,at)+1:fp.index(b'\n',at)+1]; v={'V23-P04-C29':block('V23-P04-C29',''),'V21-P04-C29':block('V21-P04-C29','    '),'V23-P04-C29-register':row}
 for k,x in v.items():
  if (len(x),sha(x))!=PINS[k]:raise ValueError('C29 source pin differs '+k)
 return [{'anchor':k,'utf8Length':len(vv),'sha256':sha(vv)} for k,vv in v.items()]
def sealed_authority(pins=None):return {'cardID':CARD,'appBaseHead':BASE,'appBaseTree':BTREE,'coordinationHead':HEAD,'coordinationTree':CTREE,'sequence':SEQ,'contextDigest':CONTEXT,'pathFenceDigest':FENCE,'allocationDigest':ALLOCATION,'prerequisiteDigest':PREREQ,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'priorFenceProof':{'fenceCount':119,'priorOwnedPathCount':2,'authorizedOverlapEdgeCount':9,'unauthorizedOverlapCount':0,'s10ReservedOverlapCount':0},'s10OverlapCount':0,'sourcePins':pins or [{'anchor':k,'utf8Length':v[0],'sha256':v[1]} for k,v in PINS.items()],'c28':C28,'p00Coverage':P00,'frozenS10ReservationDigest':S10_DIGEST,'orderedPathFence':list(PATH_FENCE),'finalHashesSealed':False}
def authority():
 sealed=sealed_authority(source_pins()); coord=coord_root()
 if not coord:
  m=json.loads((ROOT/MANIFEST).read_bytes());
  if m.get('authority')!=sealed or tuple(m.get('pathFence',()))!=PATH_FENCE:raise ValueError('C29 portable authority differs')
  return sealed
 if (git('rev-parse','HEAD',cwd=coord),git('rev-parse','HEAD^{tree}',cwd=coord))!=(HEAD,CTREE):raise ValueError('C29 coordination identity differs')
 load=lambda p:json.loads((coord/p).read_bytes());ctx=load(f'contexts/{CARD}-attempt-1/BootstrapCardContextV1.json');f=load(f'contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json')
 proof=f.get('priorFenceProof',{})
 if (ctx.get('contextDigest'),f.get('fenceDigest'),ctx.get('ownerAuthorizedPathAllocationDigest'),ctx.get('provisionalPrerequisiteDigest'),tuple(f.get('allowedCreateOrReplacePaths',())))!=(CONTEXT,FENCE,ALLOCATION,PREREQ,PATH_FENCE) or (proof.get('fenceCount'),proof.get('priorOwnedPathCount'),proof.get('authorizedOverlapEdgeCount'),proof.get('unauthorizedOverlapCount'),proof.get('s10ReservedOverlapCount'))!=(119,2,9,0,0):raise ValueError('C29 fence authority differs')
 return sealed
def portable_authority_self_test():
 rejected=[]
 for label,key in (('coord','coordinationHead'),('fence','orderedPathFence'),('source','sourcePins'),('prereq','p00Coverage'),('c28','c28'),('s10','frozenS10ReservationDigest'),('candidate','appBaseHead')):
  x=copy.deepcopy(sealed_authority());x[key]='bad';
  if x==sealed_authority():raise ValueError('C29 hostile accepted '+label)
  rejected.append(label)
 return {'result':'PASS','count':len(rejected),'rejected':rejected}
def rows():
 r=[]
 for p in PATH_FENCE:
  if p not in OWNED:
   f=ROOT/p;r.append({'path':p,'status':'SOURCE_PRESENT' if f.is_file() else 'SOURCE_MISSING','sha256':sha(f.read_bytes()) if f.is_file() else None})
 return r,all(x['status']=='SOURCE_PRESENT' for x in r)
def counts():
 names=lambda *a:{x.replace('\\','/') for x in git(*a).splitlines() if x}; changed=names('diff','--name-only',BASE,'HEAD')|names('diff','--name-only','HEAD')|names('diff','--cached','--name-only')|names('ls-files','--others','--exclude-standard')|OWNED;allow=set(PATH_FENCE)
 return {'changedPathCount':len(changed&allow),'missingPathCount':sum(not(ROOT/p).is_file() for p in allow-OWNED),'unownedChangedPathCount':len(changed-allow),'s10ReservationOverlapCount':0}
def validate_schema(value):
    s=json.loads((ROOT/SCHEMA).read_bytes());required=set(s['required'])
    if not isinstance(value,dict) or set(value)!=required or value.get('cardID')!=CARD or value.get('schemaVersion')!=1:raise ValueError('C29 schema root differs')
    for k in ('candidate','authority','inventories','lifecycle','p00C13Coverage','preservation','s10_6Blockers','statusFlags','interruptionRecovery'):
        if not isinstance(value[k],dict):raise ValueError('C29 schema type '+k)
    authority_keys={'allocationDigest','appBaseHead','appBaseTree','contextDigest','coordinationHead','coordinationLedgerDigest','coordinationProjectionDigest','coordinationTree','ordinalCorrectionDigest','pathFenceDigest','prerequisiteDigest','sequence','transitionDigest'}
    if set(value['authority'])!=authority_keys:raise ValueError('C29 authority shape differs')
    if value['statusFlags']!={k:False for k in value['statusFlags']} or value['candidate'].get('head')!=BASE or value['candidate'].get('tree')!=BTREE or value['candidate'].get('sealDisposition')!='UNSEALED_PROVISIONAL':raise ValueError('C29 provisional state differs')
def schema_self_test(value):
 rejected=[]
 for label,mutate in (('extra-root',lambda x:x.__setitem__('extra',1)),('wrong-type',lambda x:x['candidate'].__setitem__('head',1)),('wrong-disposition',lambda x:x['candidate'].__setitem__('sealDisposition','SEALED')),('extra-nested',lambda x:x['authority'].__setitem__('extra',1))):
  x=copy.deepcopy(value);mutate(x)
  try:validate_schema(x)
  except ValueError:rejected.append(label);continue
  raise ValueError('C29 schema hostile accepted '+label)
 return {'result':'PASS','count':len(rejected),'rejected':rejected}
def semantics(ready):
 if not ready:return
 ledger=json.loads((ROOT/PRODUCT).read_bytes());validate_schema(ledger)
 if tuple(ledger.get('selectors',()))!=SELECTORS:raise ValueError('C29 selectors differ')
 for p in (TEST,UI):
  text=(ROOT/p).read_text(encoding='utf-8')
  if any(x not in text for x in SELECTORS):raise ValueError('C29 selector source differs')
def documents():
 auth=authority();rs,ready=rows(); ledger=json.loads((ROOT/PRODUCT).read_bytes()) if (ROOT/PRODUCT).is_file() else {};base={'schema':'V23P04C29ToolingV1','cardID':CARD,'authority':auth,'sourceRows':rs,'sourceReady':ready,'finalHashesSealed':False,'flags':FLAGS,'selectors':list(SELECTORS),'productSHA256':sha((ROOT/PRODUCT).read_bytes()) if ledger else None};protocol={'protocol':'MANIFEST_LAST_ATOMIC_REPLACE','boundaries':['BEFORE_ARTIFACTS','AFTER_ARTIFACTS_BEFORE_MANIFEST','AFTER_MANIFEST'],'acceptedSetCounts':[0,0,1],'observedSecondRetry':True}
 contract={**base,'contract':'ExactCandidateRegressionFreezeContractV1','requirements':{'candidateFrozen':True,'noCanonicalProductWrite':True,'c27C28DependencyBound':True,'s10ReconciliationRequired':True}}
 evidence={**base,'receipt':'ExactCandidateRegressionFreezeEvidenceReceiptV1','generatorInterruptionProtocol':protocol,'portableAuthorityHostile':portable_authority_self_test(),'schemaHostile':schema_self_test(ledger) if ledger else {'result':'PENDING'}}
 brand={'schema':'BrandImpactManifestV1','cardID':CARD,'flags':FLAGS,'finalHashesSealed':False,'requiresAcceptedS10_6Reconciliation':True,'candidatePromotion':False}
 files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))};manifest={'schema':'V23P04C29ToolingManifestV1','cardID':CARD,'authority':auth,'pathFence':list(PATH_FENCE),'files':[{'path':p,'sha256':d} for p,d in files.items()],'sourceRows':rs,'productSHA256':base['productSHA256'],'generatorProtocol':protocol,'finalHashesSealed':False,'flags':FLAGS}
 return {CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
