"""Deterministic, non-shipping static-preparation artifacts for V23-P06-C08."""
from __future__ import annotations
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
COORD=ROOT.parent/'AssetRounds-v23-coordination'
CARD='V23-P06-C08'; BASE='dda503c61cb64d9ed476c12dddbde79895605437'; TREE='504d97c23639b370f992ad98d878cce1ed40676b'
CH='a20ae353a722b7670c06cca8ef4b6db018d2103f'; CTREE='c7a7877a8eedba93817cf5b9df995d1daf0734b0'; SEQ=619
SPEC='44d21d9c8ba767488f24a25203517508bc054119cd112bd31c2ddd073953009a'; FENCE='a234a11adcc14f4c1033c01c39b621fa6a78c4fc2c356bfce0f2b738e8c42da1'; PREREQ='f7932fac90c94bc40799c39e53f89325dc83ed5302abfa2e7a983dbd1627efec'; TRANSITION='79fa0b63209eedcd4effc0cdc8aceb1ea58a0fb8e6a52b4323acc7f7f70af594'; LEDGER='370352ec3514d70072defb31e062c9d0599c3ead74fb29215fb8d749b3865458'; PROJECTION='33112381a7ee5b1d6616a459bd70d5126c5f6012caf70de4bbcb229a6889f6fb'
OWNED=('Scripts/v23/p06_c08_contracts.py','Scripts/v23/generate_p06_c08_contracts.py','Scripts/v23/verify_p06_c08_contracts.py','Scripts/v23/temporal-media-static-protocol.schema.json','FieldEvidenceAppTests/Fixtures/V23/P06/TemporalMedia/V23P06C08TemporalMediaStaticCorpusV1.json','docs/design/v23/tooling/V23P06C08TemporalMediaStaticPreparationContractV1.json','docs/design/v23/tooling/V23P06C08TemporalMediaStaticPreparationEvidenceReceiptV1.json','docs/design/v23/tooling/V23P06C08BrandImpactManifestV1.json','docs/design/v23/tooling/V23-P06-C08-tooling-manifest.json')
SC,CP,CON,EVI,BRAND,MAN=OWNED[3:]; IDS=tuple(f'{CARD}-{x}' for x in ('G01','A01','H01-CODEC','H01-DURATION','H01-REDACTION-MARKER','I01','R01'))
FLAGS={x:False for x in ('nativeCIClaim','hostedCIClaim','physicalCIClaim','adoptionCredit','acceptanceCredit','selectorCredit','implementationCredit','releaseCredit','phaseCredit','mainCredit','mergeCredit')}
NO={'capturedMedia':False,'transcription':False,'redaction':False,'modelOutput':False,'background':False,'network':False,'canonicalWrites':0,'customerData':False,'uploadInvoked':False,'transformInvoked':False,'externalActions':'NONE'}
def pretty(v): return (json.dumps(v,sort_keys=True,indent=2)+'\n').encode()
def sha(v): return hashlib.sha256(v).hexdigest()
def compact(v,newline=False): return (json.dumps(v,sort_keys=True,separators=(',',':'))+('\n' if newline else '')).encode()
def read(p): return json.loads(Path(p).read_text(encoding='utf-8'))
def git(root,*args): return subprocess.check_output(['git','-C',str(root),*args],text=True).strip()
def protocol(): return {'schema':'V23P06C08TemporalMediaStaticProtocolV1','cardID':CARD,'disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','syntheticRepositoryOnly':True,'declarativeDescriptorsOnly':True,**NO,'manualOfflineFallback':True,'expiryDays':30,'reconciliationRequired':True,'evidenceIDs':list(IDS),'flags':FLAGS}
def corpus(): return {'schema':'V23P06C08TemporalMediaStaticCorpusV1','cardID':CARD,'disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','syntheticRepositoryOnly':True,'realTerminalValidationResult':False,'noCapturedMediaOrCustomerData':True,'cases':[{'id':IDS[0],'kind':'golden','descriptor':'synthetic temporal descriptor','expectedDisposition':'STATIC_DESCRIPTOR_ONLY'},{'id':IDS[1],'kind':'accessibility','descriptor':'manual offline text alternative','expectedDisposition':'STATIC_DESCRIPTOR_ONLY'},{'id':IDS[2],'kind':'hostile','input':'malformed or unsupported codec','expectedDisposition':'REJECT_DESCRIPTOR','expectedSemantics':'NO_CAPTURE_OR_TRANSCODE'},{'id':IDS[3],'kind':'hostile','input':'duration outside bounded descriptor range','expectedDisposition':'REJECT_DESCRIPTOR','expectedSemantics':'NO_CAPTURE_OR_BACKGROUND_WORK'},{'id':IDS[4],'kind':'hostile','input':'redaction marker requests transformation','expectedDisposition':'REJECT_NO_TRANSFORM','expectedSemantics':'NO_REDACTION_MODEL_OR_UPLOAD'},{'id':IDS[5],'kind':'interruption','expectedDisposition':'NO_RUNTIME_CLAIM','expectedSemantics':'DISCARD_SYNTHETIC_DESCRIPTOR'},{'id':IDS[6],'kind':'recovery','expectedDisposition':'RECONCILE_OR_DISCARD','expectedSemantics':'EXPIRY_RECONCILIATION_REQUIRED'}]}
def schema(): return {'$schema':'https://json-schema.org/draft/2020-12/schema','type':'object','additionalProperties':False,'required':['schema','cardID','disposition','syntheticRepositoryOnly','declarativeDescriptorsOnly','capturedMedia','transcription','redaction','modelOutput','background','network','canonicalWrites','customerData','uploadInvoked','transformInvoked','externalActions','expiryDays','reconciliationRequired','evidenceIDs','flags'],'properties':{'schema':{'const':'V23P06C08TemporalMediaStaticProtocolV1'},'cardID':{'const':CARD},'disposition':{'const':'PROVISIONAL_STATIC_PREPARATION_ONLY'},'syntheticRepositoryOnly':{'const':True},'declarativeDescriptorsOnly':{'const':True},**{k:{'const':v} for k,v in NO.items()},'expiryDays':{'const':30},'reconciliationRequired':{'const':True}}}
def changed():
 s=set(git(ROOT,'diff','--name-only',BASE,'HEAD').splitlines())
 for line in git(ROOT,'status','--porcelain=v1').splitlines():
  p=line[3:]; f=ROOT/p
  if f.is_dir(): s.update(x.relative_to(ROOT).as_posix() for x in f.rglob('*') if x.is_file())
  elif p:s.add(p)
 return s
def digest_self(v,key):
 w=dict(v); actual=w.pop(key,None)
 return actual==sha(compact(w,True)) or actual==sha(compact(w,False))
def authority():
 if subprocess.run(['git','-C',str(ROOT),'merge-base','--is-ancestor',BASE,'HEAD']).returncode: raise ValueError('APP_BASE_NOT_ANCESTOR')
 if git(ROOT,'rev-parse',BASE+'^{tree}')!=TREE: raise ValueError('APP_BASE_TREE_MISMATCH')
 v5=ROOT/'docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json'; raw=v5.read_bytes(); v=read(v5); sem=dict(v); sem.pop('contentDigest',None)
 if sha(raw)!='33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5' or sha(compact(sem))!='57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38': raise ValueError('V5_DIGEST_MISMATCH')
 reservation=read(ROOT/'docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json'); rr=dict(reservation); rr.pop('contentDigest',None)
 if reservation.get('contentDigest')!=sha(compact(rr,True)) or set(OWNED)&set(reservation['reservedPaths']): raise ValueError('S10_RESERVATION_MISMATCH')
 if (git(COORD,'rev-parse','HEAD'),git(COORD,'rev-parse','origin/main'),git(COORD,'show','-s','--format=%T','HEAD'))!=(CH,CH,CTREE): raise ValueError('COORD_IDENTITY_MISMATCH')
 paths=[COORD/f'contexts/{CARD}-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json',COORD/f'contexts/{CARD}-attempt-1/ProvisionalStaticPreparationPathFenceV1.json',COORD/f'receipts/{CARD}-provisional-static-prerequisite-set-v1.json',COORD/f'transitions/{SEQ:06d}-{CARD}-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json',COORD/'state/BootstrapExecutionLedgerEnvelopeV1.json',COORD/'projections/ActiveWorkSetProjectionV1.json']
 vals=[read(p) for p in paths]; keys=('executionSpecDigest','pathFenceDigest','prerequisiteSetDigest','transitionDigest','ledgerDigest','projectionDigest')
 if not all(digest_self(x,k) for x,k in zip(vals,keys)): raise ValueError('COORD_SELF_DIGEST_MISMATCH')
 sp,fn,pr,tr,le,po=vals
 if [sp[key] for key in ('executionSpecDigest',)]!=[SPEC] or fn['pathFenceDigest']!=FENCE or pr['prerequisiteSetDigest']!=PREREQ or tr['transitionDigest']!=TRANSITION or le['ledgerDigest']!=LEDGER or po['projectionDigest']!=PROJECTION: raise ValueError('HYDRATION_PIN_MISMATCH')
 if fn['allowedCreateOrReplacePaths']!=list(OWNED) or fn['s10ReservedOverlapCount']!=0 or sp['canonicalWrites']!=0 or any(sp[k] for k in ('capturedMediaEnabled','transcriptionEnabled','redactionEnabled','modelOutputEnabled','backgroundEnabled','networkEnabled')): raise ValueError('STATIC_FENCE_MISMATCH')
 src=pr['sources'][1]
 if src['cardID']!='V23-P04-C25' or src['candidateHead']!='2df711cb2e0eb7dedfe11618fc82641e760b8be7' or src['candidateTree']!='dcac37cb39b42902713f15d3aff34ac93f333298': raise ValueError('C25_PREREQUISITE_MISMATCH')
 if le['casSequence']!=SEQ or po['ledgerDigest']!=LEDGER: raise ValueError('LEDGER_PROJECTION_MISMATCH')
def docs():
 authority(); p=protocol(); c=corpus(); common={'schema':'V23P06C08StaticPreparationToolingV1','cardID':CARD,'disposition':'PROVISIONAL_STATIC_PREPARATION_ONLY','appBaseAuthority':{'head':BASE,'tree':TREE},'observedCandidateIdentityPolicy':'RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN','noProductionPath':True,'noRealStudy':True,'expiryDays':30,'reconciliationRequired':True,'flags':FLAGS,**NO}
 out={SC:schema(),CP:c,CON:{**common,'contract':'TemporalMediaStaticPreparationContractV1','protocol':p,'corpusPath':CP},EVI:{**common,'receipt':'TemporalMediaStaticPreparationEvidenceReceiptV1','result':'PASS_STATIC_PROVISIONAL','protocolSHA256':sha(pretty(p))},BRAND:{**common,'manifest':'TemporalMediaBrandImpactManifestV1','impact':'NONE_SHIPPING'}}
 out[MAN]={**common,'manifest':'V23P06C08ToolingManifestV1','pathFence':list(OWNED),'generatedFiles':[{'path':k,'sha256':sha(pretty(v))} for k,v in out.items()]}; return out
def metrics():
 s=changed(); return {'fencePathCount':9,'changedPathCount':len(s&set(OWNED)),'missingOwnedPathCount':sum(not(ROOT/x).is_file() for x in OWNED),'unownedChangedPathCount':len(s-set(OWNED)),'s10ReservationOverlapCount':0}
def verify_complete():
 authority(); p=protocol(); c=corpus();
 if set(x['id'] for x in c['cases'])!=set(IDS) or any(not x['id'].startswith(CARD+'-') for x in c['cases']): raise ValueError('QUALIFIED_CASE_IDS')
 hostile={x['id']:(x['expectedDisposition'],x['expectedSemantics']) for x in c['cases'] if x['kind']=='hostile'}
 expected={IDS[2]:('REJECT_DESCRIPTOR','NO_CAPTURE_OR_TRANSCODE'),IDS[3]:('REJECT_DESCRIPTOR','NO_CAPTURE_OR_BACKGROUND_WORK'),IDS[4]:('REJECT_NO_TRANSFORM','NO_REDACTION_MODEL_OR_UPLOAD')}
 if hostile!=expected or any(v is not False for k,v in p.items() if k in NO and isinstance(NO[k],bool)): raise ValueError('HOSTILE_OR_STATIC_SEMANTICS')
 m=metrics()
 if m['changedPathCount']!=9 or m['missingOwnedPathCount'] or m['unownedChangedPathCount']: raise ValueError('CUMULATIVE_FENCE_MISMATCH')
 return {'result':'PASS_STATIC_PROVISIONAL','cardID':CARD,**m,'appBaseHead':BASE,'observedCandidateHead':git(ROOT,'rev-parse','HEAD'),'coordinationHead':CH,'executionSpecDigest':SPEC,'pathFenceDigest':FENCE,'staticPrerequisiteSetDigest':PREREQ}
