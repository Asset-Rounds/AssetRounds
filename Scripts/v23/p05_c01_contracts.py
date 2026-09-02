from __future__ import annotations

import copy
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = 'V23-P05-C01'
BASE = '2952775307a182d183461f81157af6cb3819be69'
BTREE = '36b3c5f0993519aa703a341f6e650989dc5f1102'
COORDINATION_HEAD = '30a5be02d3c6b00c084392a9901ebf3915a3ea1c'
COORDINATION_TREE = 'fd478fc211271f83fee7e74b5426001763e21c45'
ALLOCATION = 'd05fdbb6e8e06bf65087749d40e8d544ea9cc9e83528935cfbf4705bfb97c18d'
PREREQUISITE = '9914b355d2371cea8e831299c65ecf3947e695933dce05a165c08bc296c09f93'
CONTEXT = '454fb36d385cc9935bb76b596ae7d5e26d3ba89a68cf9d19209e8a71a158e286'
FENCE = '1f9286e373c2ddbb2e18b1e61a7226c560842dada45f719bc3a6653449099b45'
SEQUENCE = 590
TRANSITION = 'eb3e196f825b30250da007bec328c66754b1be0969431e884cbec9a89502ddbb'
LEDGER = '42e12627b00f7c1d23bdb0977a2a16aa078ced888ad611df6542d87d8dd5a379'
PROJECTION = 'aad3b7c187217d3e35eb68274a46080d57c1ccf74788a922cdf578398936bbc4'
BOUNDARY_RECEIPT = 'receipts/V23-P04-to-V23-P05-C01-static-preparation-boundary-v1.json'
PRODUCT = 'Release/V23P05C01ExactCodeCandidateGateV1.json'
TEST = 'FieldEvidenceAppTests/V9_93ExactCodeCandidateGateTests.swift'
FIXTURE = 'FieldEvidenceAppTests/Fixtures/V23/Release/V23P05C01ExactCodeCandidateGateCorpusV1.json'
UI = 'FieldEvidenceAppUITests/V23_P05_C01ExactCodeCandidateGateUITests.swift'
SCHEMA = 'Scripts/v23/exact-code-candidate-gate.schema.json'
CONTRACT = 'docs/design/v23/tooling/V23P05C01ExactCodeCandidateGateContractV1.json'
EVIDENCE = 'docs/design/v23/tooling/V23P05C01ExactCodeCandidateGateEvidenceReceiptV1.json'
BRAND = 'docs/design/v23/tooling/V23P05C01BrandImpactManifestV1.json'
MANIFEST = 'docs/design/v23/tooling/V23-P05-C01-tooling-manifest.json'
SCRIPTS = ('Scripts/v23/p05_c01_contracts.py','Scripts/v23/generate_p05_c01_contracts.py','Scripts/v23/verify_p05_c01_contracts.py')
OWNED = set((*SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST))
SOURCE_PATHS = ('Scripts/release-preflight.sh','FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift',PRODUCT,TEST,FIXTURE,UI)
PATH_FENCE = (*SOURCE_PATHS,*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTOR_ROWS = (
    ('P03ShippingSurfaceSetV1',19,'abcd7c41f9e2493840d2132f8fe6dd519eb6618e2074361e204a72d9516041c7'),
    ('P04ShippingSurfaceSetV1',40,'8398caa9f991c98d3eecc5d9568379b787c286c6b03b1148556d3aa512b18bec'),
    ('P04BrandClosureSetV1',65,'823914bb28232f22138f8e8ccd78cd730977d0f37fd09b06c57e3d4d6a194186'),
    ('PublicCapabilityTruthSetV1',15,'6556f62fd77179354579fe129dd0341b9ae1f4f075befe9ed4d6e57a4766cdc0'),
    ('AutonomousRequiredAcceptedSetV1',132,'31356cbabc5e576be8b9eae25a9102060ebf0109da666fbcece94765777bf5c8'),
    ('ContactPurposeSeparationSetV1',11,'de91c7b97c537b3233789eb1133d6e7c395715392c2411b91dfe438fb5d228fc'),
    ('KernelConformanceSubjectSetV1',72,'5235cb5f53c2130502a7b4e7fc26b534e8749bde0fe283edf5fae5b69832dff9'),
)
FLAGS = {'native':False,'hosted':False,'physical':False,'adoption':False,'acceptance':False,'publication':False,'release':False,'phaseIntegration':False,'requiresAcceptedS10_6':True}
PREREQUISITE_DICT = {'cardID':'V23-P04-C29','acceptance':False,'checkpointDigest':'b5a01f55325d5bbebc8e5744d4ddcf926936f73ed9c42b36a1f64e59d7bc2b89','verificationDigest':'45cb4f66f35ea76c024526a0d5a1cac4d4b642b6797b4565b40eb1646d224f38','boundaryDigest':'a4669291ed3722c46c30067066367d669ac00a850fda9e673fc147354ad1719f'}
COMMON_JOURNEYS = ('J01_FIRST_ENTRY','J02_REAL_WORKSPACE_CREATE_IMPORT_SELECT','J03_SITE_LOCATION_ASSET_CREATE_FIND_SCAN','J04_OFFLINE_PREPARE','J05_ROUND_START_RESUME','J06_EVIDENCE_CAPTURE_CURATE','J07_VALIDATION_INCOMPLETE_RESOLUTION','J08_COMPLETE_NEXT_CLOSE','J09_REPORT_PREVIEW_SHARE_EXPORT','J10_BACKUP_RESTORE_RECOVERY','J11_SETTINGS_ACCESSIBILITY_HELP','J12_PURCHASE_RESTORE','J13_DELETE_ERASE','J14_PRACTICE_START_SWITCH_LEAVE')
FEATURE_JOURNEYS = tuple(f'FJ{i:02d}' for i in range(1,18))
LOGICAL_LANES = (('COMPILE_STATIC_ARCHITECTURE_CLAIMS_LOCALIZATION','NOT_RUN'),('UNIT_CONTRACT_LIFECYCLE_HOSTILE_PARSER','NOT_RUN'),('INTEGRATION_INTERRUPTION_RECOVERY_COMPATIBILITY','NOT_RUN'),('UI_JOURNEY_ACCESSIBILITY_VISUAL_AFFECTED_HIG','BLOCKED'),('COVERAGE_UNINSTRUMENTED_PERFORMANCE_ARCHIVE_RELEASE_EVIDENCE','BLOCKED'))
SCENARIO_ROWS = (('G01','NOT_RUN'),('A01','NOT_RUN'),('H01','BLOCKED'),('I01','NOT_RUN'),('R01','NOT_RUN'))
CORPUS_CASE_IDS = ('G01','A01','H01_MALFORMED','H01_DUPLICATE','H01_STALE_IDENTITY','H01_FALSE_READY','H01_FALSE_RELEASE','I01','R01')
FORBIDDEN_OUTCOMES = ('READY','ACCEPTED','RELEASE_READY','RELEASED','PHASE_INTEGRATED','P05_C02','P05_C03','P06')
READ_ONLY_BINDINGS = (('ciSelector','Scripts/ci-selection.json'),('ciWorkflow','.github/workflows/ios-ci.yml'),('controllerWorkflow','.github/workflows/v23-controller.yml'),('workerWorkflow','.github/workflows/v23-worker.yml'),('controller','Scripts/v23/controller.py'),('capacityContracts','Scripts/v23/controller_contracts.py'),('releasePlan','TestPlans/V23-ReleaseCandidate.xctestplan'),('capacityPolicy','docs/design/v23/tooling/RepositoryHostedCapacityPolicyV1.json'),('controllerEnrollment','docs/design/v23/tooling/ControllerWorkflowEnrollmentV1.json'),('commonJourneys','docs/design/v23/tooling/CommonTaskJourneyReleaseV2.json'),('featureJourneys','docs/design/v23/tooling/FeatureEndToEndJourneyReleaseV1.json'),('privacyInventory','docs/privacy/V23P01C02OwnedFilePrivacyInventoryV1.json'),('higEvidence','docs/product/brand/V23P04C29ExactCandidateRegressionFreezeV1.json'),('persistenceRegistry','docs/design/v23/tooling/PersistentSchemaReleaseRegistryV1.json'),('archiveContract','docs/design/v23/tooling/V23P01C04StreamingArchiveContractV1.json'),('packageRegistry','docs/design/v23/tooling/V23P03C01PackageRegistryContractV2.json'),('releaseManifest','Release/ReleaseInputManifestV1.json'))

def pretty(value): return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode('utf-8')
def sha(value): return hashlib.sha256(value).hexdigest()
def load(path): return json.loads((ROOT / path).read_bytes())
def git(*args): return subprocess.run(['git',*args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
def source_rows():
    return [{'path':p,'status':'SOURCE_PRESENT' if (ROOT/p).is_file() else 'SOURCE_MISSING','sha256':sha((ROOT/p).read_bytes()) if (ROOT/p).is_file() else None} for p in SOURCE_PATHS]
def source_ready(): return all(r['status'] == 'SOURCE_PRESENT' for r in source_rows())
def coordination_root():
    root = ROOT.parent / 'AssetRounds-v23-coordination'
    return root if root.is_dir() else None
def authority():
    return {'cardID':CARD,'ordinal':134,'attemptID':1,'appBaseHead':BASE,'appBaseTree':BTREE,'coordinationHead':COORDINATION_HEAD,'coordinationTree':COORDINATION_TREE,'allocationDigest':ALLOCATION,'prerequisiteDigest':PREREQUISITE,'contextDigest':CONTEXT,'pathFenceDigest':FENCE,'sequence':SEQUENCE,'transitionDigest':TRANSITION,'ledgerDigest':LEDGER,'projectionDigest':PROJECTION,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'priorOverlapCount':13,'priorOverlapAuthorizedPaths':['Scripts/release-preflight.sh','FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift'],'unauthorizedOverlapCount':0,'s10OverlapCount':0,'orderedPathFence':list(PATH_FENCE),'finalHashesSealed':False}
def require_authority(value):
    if value != authority(): raise ValueError('C01 sealed authority differs')
def verify_coordination_identity():
    coordination = coordination_root()
    if coordination is None: raise ValueError('C01 coordination root missing')
    def coord_git(*args): return subprocess.run(['git',*args],cwd=coordination,check=True,capture_output=True,text=True).stdout.strip()
    head, origin, tree = (coord_git('rev-parse','HEAD'),coord_git('rev-parse','origin/main'),coord_git('rev-parse','HEAD^{tree}'))
    if (head,origin,tree) != (COORDINATION_HEAD,COORDINATION_HEAD,COORDINATION_TREE): raise ValueError('C01 coordination identity differs')
def boundary_receipt():
    verify_coordination_identity()
    path = coordination_root() / BOUNDARY_RECEIPT
    if not path.is_file(): raise ValueError('C01 boundary receipt missing')
    receipt=json.loads(path.read_bytes())
    if receipt.get('boundaryReceiptDigest') != PREREQUISITE_DICT['boundaryDigest']: raise ValueError('C01 boundary digest differs')
    authority=receipt.get('authority',{})
    if (authority.get('candidateHead'),authority.get('candidateTree'),authority.get('c29CheckpointDigest'),authority.get('c29VerificationDigest')) != (BASE,BTREE,PREREQUISITE_DICT['checkpointDigest'],PREREQUISITE_DICT['verificationDigest']): raise ValueError('C01 boundary authority differs')
    return receipt
def counts():
    changed={p.replace('\\','/') for p in git('diff','--name-only',BASE,'HEAD').splitlines() if p}
    changed|={p.replace('\\','/') for p in git('diff','--name-only','HEAD').splitlines() if p}
    changed|={p.replace('\\','/') for p in git('diff','--cached','--name-only').splitlines() if p}
    changed|={p.replace('\\','/') for p in git('ls-files','--others','--exclude-standard').splitlines() if p}
    changed={p for p in changed if not p.startswith('Scripts/v23/__pycache__/')}
    allowed=set(PATH_FENCE)
    return {'changedPathCount':len(changed&allowed),'missingOwnedPathCount':sum(not (ROOT/p).is_file() for p in OWNED),'unownedChangedPathCount':len(changed-allowed),'s10ReservationOverlapCount':0}

def _validate(value,node,root,trail='$'):
    if node is True: return
    if node is False: raise ValueError(trail+' forbidden')
    if '$ref' in node: return _validate(value,root['$defs'][node['$ref'].rsplit('/',1)[1]],root,trail)
    if 'const' in node and value != node['const']: raise ValueError(trail+' const')
    if 'enum' in node and value not in node['enum']: raise ValueError(trail+' enum')
    kind=node.get('type')
    if isinstance(kind,list):
        if not any(_valid_type(value,k) for k in kind): raise ValueError(trail+' type')
    elif kind and not _valid_type(value,kind): raise ValueError(trail+' '+kind)
    if kind == 'object':
        required=set(node.get('required',())); props=node.get('properties',{})
        if required-set(value): raise ValueError(trail+' required')
        if node.get('additionalProperties') is False and set(value)-set(props): raise ValueError(trail+' additional')
        for key,child in props.items():
            if key in value: _validate(value[key],child,root,trail+'.'+key)
    elif kind == 'array':
        if 'minItems' in node and len(value)<node['minItems']: raise ValueError(trail+' minItems')
        if 'maxItems' in node and len(value)>node['maxItems']: raise ValueError(trail+' maxItems')
        if node.get('uniqueItems') and len({json.dumps(x,sort_keys=True) for x in value}) != len(value): raise ValueError(trail+' unique')
        prefix=node.get('prefixItems',())
        for i,item in enumerate(value): _validate(item,prefix[i] if i < len(prefix) else node.get('items',{}),root,f'{trail}[{i}]')
def _valid_type(value,kind):
    return {'object':isinstance(value,dict),'array':isinstance(value,list),'string':isinstance(value,str),'boolean':isinstance(value,bool),'integer':isinstance(value,int) and not isinstance(value,bool),'null':value is None}.get(kind,True)
def validate_schema(value):
    schema=load(SCHEMA)
    if schema.get('$schema') != 'https://json-schema.org/draft/2020-12/schema': raise ValueError('C01 schema draft differs')
    _validate(value,schema,schema)
    try:
        from jsonschema import Draft202012Validator
        Draft202012Validator.check_schema(schema)
        if list(Draft202012Validator(schema).iter_errors(value)): raise ValueError('C01 formal schema differs')
    except ImportError: pass

def semantics(ready):
    if not ready: return
    receipt=boundary_receipt()
    gate=load(PRODUCT); validate_schema(gate)
    if gate.get('prerequisite') != PREREQUISITE_DICT: raise ValueError('C01 prerequisite differs')
    if tuple((x.get('id'),x.get('memberCount'),x.get('digest')) for x in gate['selectorRows']) != SELECTOR_ROWS: raise ValueError('C01 selector rows differ')
    evidence=gate['provisionalEvidence']
    if len(evidence['orderedMemberIDs']) != 132 or len(set(evidence['orderedMemberIDs'])) != 132 or evidence['stateCountVector'] != [112,14,5,1] or any(evidence[k] for k in ('acceptedCount','predicateSatisfied','creditGranted')): raise ValueError('C01 provisional evidence differs')
    required=receipt.get('autonomousRequiredSet',{})
    member_ids=[row.get('cardID') for row in required.get('currentProvisionalEvidence',())]
    if evidence['orderedMemberIDs'] != member_ids or required.get('currentStateCounts') != {'CHECKPOINTED':112,'TARGETED_GREEN':14,'VERIFIED_PROVISIONAL':5,'IMPLEMENTING':1}: raise ValueError('C01 boundary member or state vector differs')
    journeys=gate['journeyGates']
    if tuple(journeys['commonJourneyIDs']) != COMMON_JOURNEYS or tuple(journeys['featureJourneyIDs']) != FEATURE_JOURNEYS or journeys['status'] != 'NOT_RUN': raise ValueError('C01 journey gates differ')
    if tuple((x.get('id'),x.get('status')) for x in gate['logicalAcceptanceLanes']) != LOGICAL_LANES or tuple((x.get('id'),x.get('status')) for x in gate['scenarioRows']) != SCENARIO_ROWS: raise ValueError('C01 lane or scenario rows differ')
    bindings=gate['readOnlyBindings']
    if tuple((x.get('role'),x.get('path')) for x in bindings) != READ_ONLY_BINDINGS or len({x.get('path') for x in bindings}) != 17 or any(not (ROOT/x['path']).is_file() or x.get('sha256') != sha((ROOT/x['path']).read_bytes()) for x in bindings): raise ValueError('C01 read-only bindings differ')
    if any(v for k,v in gate['flags'].items() if k != 'requiresAcceptedS10_6') or gate['flags'].get('requiresAcceptedS10_6') is not True or any(gate['lifecycle'].values()): raise ValueError('C01 flags differ')
    corpus=load(FIXTURE)
    if tuple(row.get('id') for row in corpus.get('cases',())) != CORPUS_CASE_IDS or tuple(corpus.get('forbiddenOutcomes',())) != FORBIDDEN_OUTCOMES or corpus.get('requiredCounts',{}).get('logicalLanes',corpus.get('requiredCounts',{}).get('logicalAcceptanceLanes')) != 5: raise ValueError('C01 corpus differs')
    for path in (TEST,UI):
        text=(ROOT/path).read_text(encoding='utf-8')
        for token in ('V23P05C01G01','V23P05C01A01','V23P05C01H01','V23P05C01I01','V23P05C01R01'):
            if token not in text: raise ValueError('C01 test binding differs')
    ui=(ROOT/UI).read_text(encoding='utf-8')
    if ui.count('XCTSkip(') != 5 or ui.count('has not run') != 5 or any(token in ui for token in ('XCTAssertNoThrow','PASS_NATIVE','NATIVE_PASS','RELEASE_READY')): raise ValueError('C01 UI provisional disposition differs')

def schema_self_test(value):
    rejected=[]
    for label,mutate in (
        ('extra-root',lambda x:x.__setitem__('extra',True)),('duplicate-selector',lambda x:x['selectorRows'].append(copy.deepcopy(x['selectorRows'][0]))),('duplicate-member',lambda x:x['provisionalEvidence']['orderedMemberIDs'].append(x['provisionalEvidence']['orderedMemberIDs'][0])),('stale-candidate',lambda x:x['candidate'].__setitem__('baseHead','0'*40)),('wrong-prerequisite',lambda x:x['prerequisite'].__setitem__('boundaryDigest','0'*64)),('wrong-lane',lambda x:x['logicalAcceptanceLanes'].__setitem__(0,{'id':'WRONG','status':'NOT_RUN'})),('false-ready',lambda x:x['provisionalEvidence'].__setitem__('acceptedCount',1)),('release-flag',lambda x:x['flags'].__setitem__('release',True)),('missing-binding',lambda x:x.pop('readOnlyBindings'))):
        item=copy.deepcopy(value); mutate(item)
        try: validate_schema(item)
        except ValueError: rejected.append(label)
    if len(rejected) != 9: raise ValueError('C01 schema hostile acceptance')
    return {'result':'PASS','rejected':rejected,'count':len(rejected)}
def observation():
    scripts={'generatorSHA256':sha((ROOT/SCRIPTS[1]).read_bytes()),'verifierSHA256':sha((ROOT/SCRIPTS[2]).read_bytes())}
    base={'schema':'V23P05C01ObservedSelfTestV1','cardID':CARD,'candidate':{'head':BASE,'tree':BTREE},'authority':authority(),'commands':[{'command':'python -B Scripts/v23/generate_p05_c01_contracts.py --self-test --json','mode':'GENERATOR_MANIFEST_LAST_RECOVERY'},{'command':'python -B Scripts/v23/verify_p05_c01_contracts.py --complete --json','mode':'COMPLETE_STATIC_PROVISIONAL'}],'scripts':scripts,'sourceRows':source_rows()}
    return {**base,'canonicalResultSHA256':sha(json.dumps(base,sort_keys=True,separators=(',',':')).encode())}
def documents():
    ready=source_ready(); verify_coordination_identity(); observed=observation()
    base={'schema':'V23P05C01ToolingV1','cardID':CARD,'attemptID':1,'authority':authority(),'sourceRows':source_rows(),'sourceReady':ready,'observedSelfTest':observed,'finalHashesSealed':False,'flags':FLAGS,'productSHA256':sha((ROOT/PRODUCT).read_bytes()) if (ROOT/PRODUCT).is_file() else None}
    contract={**base,'contract':'ExactCodeCandidateGateContractV1','requirements':{'sevenSelectorRowsBound':True,'provisionalStateIsUncredited':True,'logicalAcceptanceLanesAreNotScenarios':True,'noAcceptanceOrReleaseClaim':True,'requiresAcceptedS10_6Reconciliation':True}}
    evidence={**base,'receipt':'ExactCodeCandidateGateEvidenceReceiptV1','schemaHostile':schema_self_test(load(PRODUCT)) if ready else {'result':'PENDING'},'provisionalDisposition':'PASS_STATIC_PROVISIONAL'}
    brand={'schema':'V23P05C01BrandImpactManifestV1','cardID':CARD,'flags':FLAGS,'finalHashesSealed':False,'candidatePromotion':False,'requiresAcceptedS10_6Reconciliation':True,'observedSelfTest':observed}
    files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))}
    manifest={'schema':'V23P05C01ToolingManifestV1','cardID':CARD,'authority':authority(),'pathFence':list(PATH_FENCE),'files':[{'path':p,'sha256':d} for p,d in files.items()],'sourceRows':source_rows(),'observedSelfTest':observed,'generatorProtocol':{'protocol':'MANIFEST_LAST_ATOMIC_REPLACE','boundaries':['BEFORE_ARTIFACTS','AFTER_ARTIFACTS_BEFORE_MANIFEST','AFTER_MANIFEST']},'finalHashesSealed':False,'flags':FLAGS}
    return {CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
