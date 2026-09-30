"""Deterministic V23-P06-C09 spatial-registration static-preparation tooling."""
from __future__ import annotations
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; COORD=ROOT.parent/'AssetRounds-v23-coordination'
CARD='V23-P06-C09'; BASE='24a86948fd0f213630a7066568fedec8e83cbc4d'; TREE='bf9600d75be3a72a4ca07d4b0ed3efb43c63679b'; CH='77dc97e3ccda2d59dd5772e64d3800373a51f00c'; CTREE='a185c448224e4d4f433ef0bda9de4700b86c62b0'; SEQ=623
SPEC='cf935ffaf7bb82fa82ca7105b9c689867f56e318cb72f32f392eca9a6149dc43'; FENCE='20ffc25342ea3647e350e576cf46f02cdcd47fa1e292e6e8e509dc2c6c423ff5'; PREREQ='073bea207827e7462e7925c0505bdf32a6d14c06e09c09eb4a8b29ab73d460c5'; TRANS='139f4f532e67af150ea71f1c766d9cbcab4bb4e697248fdd6f6ea33958b157b2'; LEDGER='2906900d441086153636a90a0d4cf63b14ea4e15dacd84c1208ddd183b6f2f9b'; PROJ='00313e24295dec3fc5bd6e7ca5aa37c044cc3f3631badfad54ea7fe52f0b2b88'
OWNED=('Scripts/v23/p06_c09_contracts.py','Scripts/v23/generate_p06_c09_contracts.py','Scripts/v23/verify_p06_c09_contracts.py','Scripts/v23/spatial-registration-static-protocol.schema.json','FieldEvidenceAppTests/Fixtures/V23/P06/SpatialRegistration/V23P06C09SpatialRegistrationStaticCorpusV1.json','docs/design/v23/tooling/V23P06C09SpatialRegistrationStaticPreparationContractV1.json','docs/design/v23/tooling/V23P06C09SpatialRegistrationStaticPreparationEvidenceReceiptV1.json','docs/design/v23/tooling/V23P06C09BrandImpactManifestV1.json','docs/design/v23/tooling/V23-P06-C09-tooling-manifest.json')
SC,CP,CON,EVI,BRAND,MAN=OWNED[3:]; IDS=tuple(f'{CARD}-{x}' for x in ('G01','A01','H01-NONINVERTIBLE','H01-ACCURACY','H01-SILENT-TRANSFORM','I01','R01'))
FLAGS={x:False for x in ('nativeCIClaim','hostedCIClaim','physicalCIClaim','adoptionCredit','acceptanceCredit','selectorCredit','implementationCredit','releaseCredit','phaseCredit','mainCredit','mergeCredit')}
NO={'mapKitCoreLocationARKitLiDARBIMImportLocationSensorNetworkEnabled':False,'transformExecuted':False,'calibrationClaim':False,'canonicalWrites':0,'accuracyClaim':False,'silentTransformEnabled':False,'geometryForkEnabled':False,'customerData':False,'externalActions':'NONE','actualPlans':False}
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+'\n').encode()
def sha(b):return hashlib.sha256(b).hexdigest()
def compact(v,n=False):return(json.dumps(v,sort_keys=True,separators=(',',':'))+('\n'if n else '')).encode()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def git(root,*a):return subprocess.check_output(['git','-C',str(root),*a],text=True).strip()
def protocol():return {'schema':'V23P06C09SpatialRegistrationStaticProtocolV1','cardID':CARD,'disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','syntheticRepositoryOnly':True,'declarativeSpatialDescriptorsOnly':True,**NO,'manualOfflineFallback':True,'expiryDays':30,'reconciliationRequired':True,'evidenceIDs':list(IDS),'flags':FLAGS}
def corpus():return {'schema':'V23P06C09SpatialRegistrationStaticCorpusV1','cardID':CARD,'disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','syntheticRepositoryOnly':True,'realTerminalValidationResult':False,'cases':[{'id':IDS[0],'kind':'golden','input':'synthetic spatial descriptor','expectedDisposition':'STATIC_DESCRIPTOR_ONLY'},{'id':IDS[1],'kind':'accessibility','input':'manual offline coordinate terminology','expectedDisposition':'STATIC_DESCRIPTOR_ONLY'},{'id':IDS[2],'kind':'hostile','input':'non-invertible transform descriptor','expectedDisposition':'REJECT_DESCRIPTOR','expectedSemantics':'NO_TRANSFORM_EXECUTION_OR_GEOMETRY_FORK'},{'id':IDS[3],'kind':'hostile','input':'calibration or accuracy claim','expectedDisposition':'REJECT_CLAIM','expectedSemantics':'NO_CALIBRATION_OR_ACCURACY_CLAIM'},{'id':IDS[4],'kind':'hostile','input':'silent transform or actual-plan request','expectedDisposition':'REJECT_NO_SILENT_TRANSFORM','expectedSemantics':'NO_PLAN_LOCATION_SENSOR_OR_NETWORK'},{'id':IDS[5],'kind':'interruption','expectedDisposition':'NO_RUNTIME_CLAIM','expectedSemantics':'DISCARD_SYNTHETIC_DESCRIPTOR'},{'id':IDS[6],'kind':'recovery','expectedDisposition':'RECONCILE_OR_DISCARD','expectedSemantics':'EXPIRY_RECONCILIATION_REQUIRED'}]}
def schema():return {'$schema':'https://json-schema.org/draft/2020-12/schema','type':'object','additionalProperties':False,'required':['schema','cardID','disposition','syntheticRepositoryOnly','declarativeSpatialDescriptorsOnly',*NO.keys(),'expiryDays','reconciliationRequired','evidenceIDs','flags'],'properties':{'schema':{'const':'V23P06C09SpatialRegistrationStaticProtocolV1'},'cardID':{'const':CARD},'disposition':{'const':'PROVISIONAL_STATIC_PREPARATION_ONLY'},'syntheticRepositoryOnly':{'const':True},'declarativeSpatialDescriptorsOnly':{'const':True},**{k:{'const':v}for k,v in NO.items()},'expiryDays':{'const':30},'reconciliationRequired':{'const':True}}}
def changed():
 s=set(git(ROOT,'diff','--name-only',BASE,'HEAD').splitlines())
 for r in git(ROOT,'status','--porcelain=v1').splitlines():
  p=r[3:]; x=ROOT/p
  if x.is_dir():s.update(v.relative_to(ROOT).as_posix()for v in x.rglob('*')if v.is_file())
  elif p:s.add(p)
 return s
def self_digest(v,k):
 x=dict(v); actual=x.pop(k,None); return actual==sha(compact(x,True))or actual==sha(compact(x))
def authority():
 if subprocess.run(['git','-C',str(ROOT),'merge-base','--is-ancestor',BASE,'HEAD']).returncode:raise ValueError('APP_BASE_NOT_ANCESTOR')
 if git(ROOT,'rev-parse',BASE+'^{tree}')!=TREE:raise ValueError('APP_BASE_TREE_MISMATCH')
 v5p=ROOT/'docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json'; v5=read(v5p); vb=dict(v5);vb.pop('contentDigest',None)
 if sha(v5p.read_bytes())!='33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5'or sha(compact(vb))!='57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38':raise ValueError('V5_DIGEST_MISMATCH')
 res=read(ROOT/'docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json');rb=dict(res);rb.pop('contentDigest',None)
 if res.get('contentDigest')!=sha(compact(rb,True))or set(OWNED)&set(res['reservedPaths']):raise ValueError('S10_RESERVATION_MISMATCH')
 if(git(COORD,'rev-parse','HEAD'),git(COORD,'rev-parse','origin/main'),git(COORD,'show','-s','--format=%T','HEAD'))!=(CH,CH,CTREE):raise ValueError('COORD_IDENTITY_MISMATCH')
 ps=[COORD/f'contexts/{CARD}-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json',COORD/f'contexts/{CARD}-attempt-1/ProvisionalStaticPreparationPathFenceV1.json',COORD/f'receipts/{CARD}-provisional-static-prerequisite-set-v1.json',COORD/f'transitions/{SEQ:06d}-{CARD}-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json',COORD/'state/BootstrapExecutionLedgerEnvelopeV1.json',COORD/'projections/ActiveWorkSetProjectionV1.json'];vs=[read(x)for x in ps];ks=('executionSpecDigest','pathFenceDigest','prerequisiteSetDigest','transitionDigest','ledgerDigest','projectionDigest')
 if not all(self_digest(x,k)for x,k in zip(vs,ks)):raise ValueError('COORD_SELF_DIGEST_MISMATCH')
 sp,fn,pr,tr,le,po=vs
 if(sp['executionSpecDigest'],fn['pathFenceDigest'],pr['prerequisiteSetDigest'],tr['transitionDigest'],le['ledgerDigest'],po['projectionDigest'])!=(SPEC,FENCE,PREREQ,TRANS,LEDGER,PROJ):raise ValueError('HYDRATION_PIN_MISMATCH')
 if fn['allowedCreateOrReplacePaths']!=list(OWNED)or fn['s10ReservedOverlapCount']or any(sp[k]for k in('mapKitCoreLocationARKitLiDARBIMImportLocationSensorNetworkEnabled','transformExecuted','calibrationClaim','accuracyClaim','silentTransformEnabled','geometryForkEnabled'))or sp['canonicalWrites']!=0:raise ValueError('STATIC_FENCE_MISMATCH')
 src=pr['sources'][1]
 if src['cardID']!='V23-P04-C19'or src['candidateHead']!='1867095815c1b8b5f9fd2be0df884303fa5447e3'or src['candidateTree']!='ed68387293bd76ac892cd27c6c25a4f58ebdd050':raise ValueError('C19_PREREQUISITE_MISMATCH')
 if le['casSequence']!=SEQ or po['ledgerDigest']!=LEDGER:raise ValueError('LEDGER_PROJECTION_MISMATCH')
def docs():
 authority();p=protocol();c=corpus();common={'schema':'V23P06C09StaticPreparationToolingV1','cardID':CARD,'disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','appBaseAuthority':{'head':BASE,'tree':TREE},'observedCandidateIdentityPolicy':'RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN','noProductionPath':True,'noRealStudy':True,'expiryDays':30,'reconciliationRequired':True,'flags':FLAGS,**NO}
 d={SC:schema(),CP:c,CON:{**common,'contract':'SpatialRegistrationStaticPreparationContractV1','protocol':p,'corpusPath':CP},EVI:{**common,'receipt':'SpatialRegistrationStaticPreparationEvidenceReceiptV1','result':'PASS_STATIC_PROVISIONAL','protocolSHA256':sha(pretty(p))},BRAND:{**common,'manifest':'SpatialRegistrationBrandImpactManifestV1','impact':'NONE_SHIPPING'}};d[MAN]={**common,'manifest':'V23P06C09ToolingManifestV1','pathFence':list(OWNED),'generatedFiles':[{'path':k,'sha256':sha(pretty(v))}for k,v in d.items()]};return d
def metrics():
 s=changed();return {'fencePathCount':9,'changedPathCount':len(s&set(OWNED)),'missingOwnedPathCount':sum(not(ROOT/x).is_file()for x in OWNED),'unownedChangedPathCount':len(s-set(OWNED)),'s10ReservationOverlapCount':0}
def verify_complete():
 authority();p=protocol();c=corpus();h={x['id']:(x['expectedDisposition'],x['expectedSemantics'])for x in c['cases']if x['kind']=='hostile'};expected={IDS[2]:('REJECT_DESCRIPTOR','NO_TRANSFORM_EXECUTION_OR_GEOMETRY_FORK'),IDS[3]:('REJECT_CLAIM','NO_CALIBRATION_OR_ACCURACY_CLAIM'),IDS[4]:('REJECT_NO_SILENT_TRANSFORM','NO_PLAN_LOCATION_SENSOR_OR_NETWORK')}
 if set(x['id']for x in c['cases'])!=set(IDS)or h!=expected or any(p[k]is not False for k,v in NO.items()if isinstance(v,bool)):raise ValueError('CORPUS_OR_STATIC_SEMANTICS')
 m=metrics()
 if m['changedPathCount']!=9 or m['missingOwnedPathCount']or m['unownedChangedPathCount']:raise ValueError('CUMULATIVE_FENCE_MISMATCH')
 return {'result':'PASS_STATIC_PROVISIONAL','cardID':CARD,**m,'appBaseHead':BASE,'observedCandidateHead':git(ROOT,'rev-parse','HEAD'),'coordinationHead':CH,'executionSpecDigest':SPEC,'pathFenceDigest':FENCE,'staticPrerequisiteSetDigest':PREREQ}
