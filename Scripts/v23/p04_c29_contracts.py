from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = 'V23-P04-C29'
BASE = '6bb5875d09e8d17076e269781ccb064451941895'
BTREE = 'ed62c3eaf2765c1dee04f33fdd09d4688ce73753'
HEAD = '24ae47fe78941c090e003b70487f2a9242bcf14f'
CTREE = 'fc7610930dcaadb95924633c81e8c66ed399238f'
SEQ = 585
CONTEXT = '73384822786179b49326ed94c51d0e4962aa555571655b2922e1c9d49a116688'
FENCE = 'da4ba32f2bacaf3d61032ea16bfdfe3cd12914b185070ba767eac791a4f53a5e'
ALLOCATION = '730f558b13aa9f41e8e2b26d32b33f7af49d7948eca235663bf6281fea3e788c'
PREREQ = 'a06b26120667c7d72be454289cc1b966ce5b770f50cf994fe962e52bfae9324e'
CORRECTION = 'ba8ef3800ce0f502ce08300c6dfee9c9b0d1f6a02f9b670881bacd663e4f9a53'
S10 = '274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a'
FINAL_HASHES_SEALED = False
PRODUCT='docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json'
TEST='FieldEvidenceAppTests/V9_92ExactCandidateRegressionFreezeTests.swift'
FIXTURE='FieldEvidenceAppTests/Fixtures/V23/Brand/V23P04C29ExactCandidateRegressionFreezeCorpusV1.json'
UI='FieldEvidenceAppUITests/V23_P04_C29ExactCandidateRegressionFreezeUITests.swift'
SCHEMA='Scripts/v23/exact-candidate-regression-freeze.schema.json'
CONTRACT='docs/design/v23/tooling/V23P04C29ExactCandidateRegressionFreezeContractV1.json'
EVIDENCE='docs/design/v23/tooling/V23P04C29ExactCandidateRegressionFreezeEvidenceReceiptV1.json'
BRAND='docs/design/v23/tooling/V23P04C29BrandImpactManifestV1.json'
MANIFEST='docs/design/v23/tooling/V23-P04-C29-tooling-manifest.json'
SCRIPTS=('Scripts/v23/p04_c29_contracts.py','Scripts/v23/generate_p04_c29_contracts.py','Scripts/v23/verify_p04_c29_contracts.py')
OWNED=set((*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST))
PATH_FENCE=('Scripts/release-preflight.sh','FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift',PRODUCT,TEST,FIXTURE,UI,*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=('testV23P04C29G01ExactCandidateFreezeBindsBrandHIGAccessibilityLocalizationJourneyAndReleaseState','testV23P04C29A01MinimumIOS18AndLatestStableResolveSeparatelyWithSemanticParity','testV23P04C29H01UnknownStaleCorruptCoverageContrastAccessibilityLocalizationJourneyAndReleaseDriftFailClosed','testV23P04C29I01ManifestLastInterruptionPreservesCandidateAndNoPartialReceipt','testV23P04C29R01DeterministicRetryPreservesFrozenCandidateWithoutPromotion')
FLAGS={k:False for k in ('physicalDevice','native','hosted','activation','adoption','acceptance','publication','release')}
CLOSURE=tuple(f'V23-P04-C{i:02d}' for i in range(27,46) if i != 29)

def pretty(value): return (json.dumps(value,sort_keys=True,indent=2)+'\n').encode()
def sha(value): return hashlib.sha256(value).hexdigest()
def git(*args,cwd=ROOT): return subprocess.run(['git',*args],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def load(path): return json.loads((ROOT/path).read_bytes())
def coordination_root():
    raw=os.environ.get('V23_P04_C29_COORDINATION_ROOT')
    if raw == 'NONE': return None
    path=Path(raw) if raw else ROOT.parent/'AssetRounds-v23-coordination'
    return path.resolve() if path.is_dir() else None

def sealed_authority():
    return {'cardID':CARD,'attemptID':2,'appBaseHead':BASE,'appBaseTree':BTREE,'coordinationHead':HEAD,'coordinationTree':CTREE,'sequence':SEQ,'contextDigest':CONTEXT,'pathFenceDigest':FENCE,'allocationDigest':ALLOCATION,'prerequisiteDigest':PREREQ,'correctionReceiptDigest':CORRECTION,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'frozenS10ReservationDigest':S10,'orderedPathFence':list(PATH_FENCE),'finalHashesSealed':False}
def require_sealed_authority(value):
    if value != sealed_authority(): raise ValueError('C29 sealed authority differs')
def authority():
    result=sealed_authority(); coord=coordination_root()
    if not coord:
        if (ROOT/MANIFEST).is_file(): require_sealed_authority(load(MANIFEST).get('authority'))
        return result
    def read(path): return json.loads((coord/path).read_bytes())
    if (git('rev-parse','HEAD',cwd=coord),git('rev-parse','HEAD^{tree}',cwd=coord)) != (HEAD,CTREE): raise ValueError('C29 coordination identity differs')
    context=read(f'contexts/{CARD}-attempt-2/BootstrapCardContextV1.json'); fence=read(f'contexts/{CARD}-attempt-2/BootstrapPathFenceV1.json')
    if (context.get('contextDigest'),fence.get('fenceDigest'),context.get('ownerAuthorizedPathAllocationDigest'),context.get('provisionalPrerequisiteDigest'),context.get('repository',{}).get('appBaseHead'),context.get('repository',{}).get('appBaseTree')) != (CONTEXT,FENCE,ALLOCATION,PREREQ,BASE,BTREE): raise ValueError('C29 attempt2 context differs')
    if tuple(fence.get('allowedCreateOrReplacePaths',())) != PATH_FENCE or set(PATH_FENCE)&set(fence.get('activeS10ReservedPaths',())) or fence.get('frozenS10ReservationDigest') != S10: raise ValueError('C29 attempt2 fence differs')
    return result

def rows():
    rows=[]
    for path in PATH_FENCE:
        if path not in OWNED and path != FIXTURE:
            item=ROOT/path; rows.append({'path':path,'status':'SOURCE_PRESENT' if item.is_file() else 'SOURCE_MISSING','sha256':sha(item.read_bytes()) if item.is_file() else None})
    return rows, all(row['status']=='SOURCE_PRESENT' for row in rows)
def closure_rows():
    result=[]
    for card in CLOSURE:
        choices=list((ROOT/'docs/design/v23/tooling').glob(card+'-tooling-manifest.json'))
        if len(choices)!=1: raise ValueError('C29 closure manifest missing or ambiguous '+card)
        data=json.loads(choices[0].read_bytes()); result.append({'cardID':card,'path':str(choices[0].relative_to(ROOT)).replace('\\','/'),'sha256':sha(choices[0].read_bytes()),'schema':data.get('schema'),'flagsAllFalse':all(value is False for value in data.get('flags',data.get('statusFlags',{})).values())})
    if not all(row['flagsAllFalse'] for row in result): raise ValueError('C29 closure flag claim differs')
    return result
def counts():
    changed={x.replace('\\','/') for x in git('diff','--name-only',BASE,'HEAD').splitlines() if x}
    changed|={x.replace('\\','/') for x in git('diff','--name-only','HEAD').splitlines() if x}
    changed|={x.replace('\\','/') for x in git('diff','--cached','--name-only').splitlines() if x}
    changed|={x.replace('\\','/') for x in git('ls-files','--others','--exclude-standard').splitlines() if x}
    allowed=set(PATH_FENCE)
    return {'changedPathCount':len(changed&allowed),'missingPathCount':sum(not(ROOT/path).is_file() for path in allowed-OWNED),'unownedChangedPathCount':len(changed-allowed),'s10ReservationOverlapCount':0}

def _validate(value,node,root,trail='$'):
    if '$ref' in node: return _validate(value,root['$defs'][node['$ref'].rsplit('/',1)[1]],root,trail)
    if 'const' in node and value != node['const']: raise ValueError(trail+' const')
    kind=node.get('type')
    if kind=='object':
        if not isinstance(value,dict): raise ValueError(trail+' object')
        required=set(node.get('required',())); props=node.get('properties',{})
        if required-set(value): raise ValueError(trail+' required')
        if node.get('additionalProperties') is False and set(value)-set(props): raise ValueError(trail+' additional')
        for key,child in props.items():
            if key in value: _validate(value[key],child,root,trail+'.'+key)
    elif kind=='array':
        if not isinstance(value,list): raise ValueError(trail+' array')
        if 'minItems' in node and len(value)<node['minItems']: raise ValueError(trail+' minItems')
        if node.get('uniqueItems') and len({json.dumps(x,sort_keys=True) for x in value})!=len(value): raise ValueError(trail+' unique')
        for index,item in enumerate(value): _validate(item,node.get('items',{}),root,f'{trail}[{index}]')
    elif kind=='string' and not isinstance(value,str): raise ValueError(trail+' string')
    elif kind=='boolean' and not isinstance(value,bool): raise ValueError(trail+' boolean')
def validate_schema(value):
    schema=load(SCHEMA)
    if schema.get('$schema')!='https://json-schema.org/draft/2020-12/schema': raise ValueError('C29 schema draft differs')
    _validate(value,schema,schema)
    try:
        from jsonschema import Draft202012Validator
        Draft202012Validator.check_schema(schema)
        if list(Draft202012Validator(schema).iter_errors(value)): raise ValueError('C29 formal schema differs')
    except ImportError: pass
def portable_authority_self_test():
    rejected=[]
    for label,key in (('tree','appBaseTree'),('fence','orderedPathFence'),('context','contextDigest'),('allocation','allocationDigest'),('prerequisite','prerequisiteDigest')):
        value=copy.deepcopy(sealed_authority()); value[key]='tampered'
        try: require_sealed_authority(value)
        except ValueError: rejected.append(label)
    if len(rejected)!=5: raise ValueError('C29 authority hostile test differs')
    return {'result':'PASS','rejected':rejected,'count':len(rejected)}

def observation():
    source,_=rows(); scripts={'generatorSHA256':sha((ROOT/SCRIPTS[1]).read_bytes()),'verifierSHA256':sha((ROOT/SCRIPTS[2]).read_bytes())}
    protocol_rows=[{'boundary':'BEFORE_ARTIFACTS','acceptedSetCount':0,'recoveryAcceptedSetCount':1,'secondRetryAcceptedSetCount':1,'manifestLast':True,'retryDeterministic':True},{'boundary':'AFTER_ARTIFACTS_BEFORE_MANIFEST','acceptedSetCount':0,'recoveryAcceptedSetCount':1,'secondRetryAcceptedSetCount':1,'manifestLast':True,'retryDeterministic':True},{'boundary':'AFTER_MANIFEST','acceptedSetCount':1,'recoveryAcceptedSetCount':1,'secondRetryAcceptedSetCount':1,'manifestLast':True,'retryDeterministic':True}]
    base={'schema':'V23P04C29ObservedSelfTestV1','cardID':CARD,'candidate':{'head':BASE,'tree':BTREE},'authority':{key:sealed_authority()[key] for key in ('coordinationHead','coordinationTree','sequence','contextDigest','pathFenceDigest','allocationDigest','prerequisiteDigest','correctionReceiptDigest')},'commands':[{'command':'python -B Scripts/v23/generate_p04_c29_contracts.py --self-test --json','mode':'GENERATOR_MANIFEST_LAST_RECOVERY'},{'command':'python -B Scripts/v23/verify_p04_c29_contracts.py --complete --json','mode':'COMPLETE_STATIC_PROVISIONAL'}],'scripts':scripts,'sourceRows':source,'manifestLastRows':protocol_rows}
    canonical=json.dumps(base,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')
    return {**base,'canonicalResultSHA256':sha(canonical)}

def semantics(ready):
    if not ready: return
    ledger=load(PRODUCT); validate_schema(ledger)
    if tuple(ledger.get('selectors',()))!=SELECTORS or not all(value is False for value in ledger.get('statusFlags',{}).values()): raise ValueError('C29 product selectors or flags differ')
    for path in (TEST,UI):
        text=(ROOT/path).read_text(encoding='utf-8')
        if not all(selector in text for selector in SELECTORS): raise ValueError('C29 test selectors differ')
    closure=closure_rows()
    if len(closure)!=18: raise ValueError('C29 closure set differs')
    matrix=ledger.get('matrix')
    expected={'candidateRuntimeRows','scenarioRows','commonJourneyRows','featureJourneyRows','accessibilityLabelRows','closureRows','c28S10ReservationRows','unresolvedEvidenceRows','semanticParityDimensions','commonJourneyRelease','featureJourneyRelease','shardPlan'}
    if not isinstance(matrix,dict) or set(matrix)!=expected: raise ValueError('C29 matrix shape differs')
    if (len(matrix['candidateRuntimeRows']),len(matrix['scenarioRows']),len(matrix['commonJourneyRows']),len(matrix['featureJourneyRows']),len(matrix['accessibilityLabelRows']),len(matrix['closureRows']),len(matrix['c28S10ReservationRows']),len(matrix['unresolvedEvidenceRows'])) != (2,5,14,17,9,16,4,7): raise ValueError('C29 matrix cardinality differs')
    if matrix['shardPlan'] != {'maximumShardCount':5,'status':'NOT_RUN'} or any(row.get('status')!='NOT_RUN' for group in ('candidateRuntimeRows','scenarioRows','accessibilityLabelRows') for row in matrix[group]): raise ValueError('C29 matrix provisional state differs')
    corpus=load(FIXTURE); binding=corpus.get('matrixBinding',{})
    exact={'candidateRuntimeCount':2,'commonJourneyCount':14,'featureJourneyCount':17,'accessibilityLabelCount':9,'closureCount':16,'c28S10ReservationCount':4,'unresolvedEvidenceCount':7,'maximumShardCount':5}
    if any(binding.get(key)!=value for key,value in exact.items()) or binding.get('matrixPath')!=PRODUCT: raise ValueError('C29 matrix corpus binding differs')
def documents():
    auth=authority(); source,ready=rows(); observed=observation(); closure=closure_rows() if ready else []
    base={'schema':'V23P04C29ToolingV2','cardID':CARD,'attemptID':2,'authority':auth,'sourceRows':source,'sourceReady':ready,'closureManifests':closure,'observedSelfTest':observed,'finalHashesSealed':False,'flags':FLAGS,'selectors':list(SELECTORS),'productSHA256':sha((ROOT/PRODUCT).read_bytes()) if (ROOT/PRODUCT).is_file() else None}
    contract={**base,'contract':'ExactCandidateRegressionFreezeContractV1','requirements':{'candidateFrozen':True,'closureC27ThroughC45Bound':True,'coverageAndJourneyRemainProvisional':True,'noCanonicalProductWrite':True,'s10ReconciliationRequired':True}}
    evidence={**base,'receipt':'ExactCandidateRegressionFreezeEvidenceReceiptV1','portableAuthorityHostile':portable_authority_self_test(),'schemaHostile':schema_self_test(load(PRODUCT)) if ready else {'result':'PENDING'}}
    brand={'schema':'BrandImpactManifestV1','cardID':CARD,'attemptID':2,'flags':FLAGS,'finalHashesSealed':False,'requiresAcceptedS10_6Reconciliation':True,'candidatePromotion':False,'observedSelfTest':observed}
    files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))}
    manifest={'schema':'V23P04C29ToolingManifestV2','cardID':CARD,'attemptID':2,'authority':auth,'pathFence':list(PATH_FENCE),'files':[{'path':path,'sha256':digest} for path,digest in files.items()],'sourceRows':source,'closureManifests':closure,'observedSelfTest':observed,'generatorProtocol':{'protocol':'MANIFEST_LAST_ATOMIC_REPLACE','boundaries':['BEFORE_ARTIFACTS','AFTER_ARTIFACTS_BEFORE_MANIFEST','AFTER_MANIFEST']},'finalHashesSealed':False,'flags':FLAGS}
    return {CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
def schema_self_test(value):
    rejected=[]
    for label,mutate in (('extra-root',lambda x:x.__setitem__('extra',True)),('deep-authority',lambda x:x['authority'].__setitem__('extra',True)),('deep-candidate',lambda x:x['candidate'].__setitem__('head','wrong')),('flags',lambda x:x['statusFlags'].__setitem__('native',True)),('matrix-extra',lambda x:x['matrix'].__setitem__('extra',True)),('matrix-missing',lambda x:x['matrix'].pop('shardPlan')),('matrix-row-type',lambda x:x['matrix']['candidateRuntimeRows'][0].__setitem__('status',True))):
        item=copy.deepcopy(value); mutate(item)
        try: validate_schema(item)
        except ValueError: rejected.append(label)
    if len(rejected)!=7: raise ValueError('C29 schema hostile accepted')
    return {'result':'PASS','rejected':rejected,'count':len(rejected)}
