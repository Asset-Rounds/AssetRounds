from __future__ import annotations

import copy
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
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
# Current projection batch retains the predecessor nine and adds only eight
# exact C26/C27 generated outputs. No historical allocation or credit is widened.
# Release, schema, corpus and the original G01/A01/H01/I01/R01 suites stay frozen.
CURRENT_SOURCE_PREDECESSOR_MUTATION_PATHS = (*SOURCE_PATHS[:2],*SCRIPTS,CONTRACT,EVIDENCE,BRAND,MANIFEST)
CURRENT_SOURCE_MUTATION_PATHS = (
    *CURRENT_SOURCE_PREDECESSOR_MUTATION_PATHS,
    'docs/design/v23/tooling/V23P04C26OrganicFindabilityContractV1.json',
    'docs/design/v23/tooling/V23P04C26OrganicFindabilityEvidenceReceiptV1.json',
    'docs/design/v23/tooling/V23P04C26BrandImpactManifestV1.json',
    'docs/design/v23/tooling/V23-P04-C26-tooling-manifest.json',
    'docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryContractV1.json',
    'docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryEvidenceReceiptV1.json',
    'docs/design/v23/tooling/V23P04C27BrandImpactManifestV1.json',
    'docs/design/v23/tooling/V23-P04-C27-tooling-manifest.json',
)
CURRENT_SOURCE_SCOPE = 'CURRENT_SOURCE_WITH_AUTHENTICATED_HISTORICAL_ALLOCATION'
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

# Explicit historical-input mode; the default live-checkout admission is unchanged.
# Pins come from the authenticated coordination commit/tree/blob responses retained
# on 2026-10-13, and the existing owner-approved V9_93 card-time copies.
HISTORICAL_COORDINATION_ENV = 'V23_P05_C01_HISTORICAL_COORDINATION'
COORDINATION_REMOTE = 'https://github.com/Asset-Rounds/AssetRounds-v23-coordination.git'
HISTORICAL_COORDINATION_FILES = (
    ('commit-30a5be02.api.json', 1274, 'd04c20c55e95bd45a6cfd7815fbf304c960438b845981eed152b22c69d44c233'),
    ('tree-fd478fc2.api.json', 2282, 'aaac0c16b6fcaf16cb90ebf007caa5ed12d98a78b0265f66f1f4b02fb2ccca02'),
    ('tree-f176a142.api.json', 142508, 'e1b8134f604312c6ec471ec663ae2d4d917c331d82b8c4dea622b066a11a30ee'),
    ('V23-P04-to-V23-P05-C01-static-preparation-boundary-v1.json', 63695, '73b6688e918cde7e9d7bfd334cf30d9ecea6d5cfabd20076b71732c90726ef14'),
    ('V23-P05-C01-owner-authorized-path-allocation-v1.json', 9184, '927ce4c7219550377dd2a7cd7787a761eb6b35cdf6144ce8629fd06823898a9e'),
)
HISTORICAL_RECEIPTS_TREE = 'f176a142d93be6f69c3bd4054ad8f0a1d2fa2622'
HISTORICAL_RECEIPT_BLOB = 'd9f03103d493b5d4364173bf3c67ea9cd3614dad'
HISTORICAL_ALLOCATION_BLOB = '420826d4016eb9441ce0750a91fc6f71bc9aa1cf'
CARD_HISTORY_DIRECTORY = 'docs/design/v23/integration/v23-card-history'
CARD_HISTORY_COMMIT = '5f17cdcd63a4ee7cbdfe50c73c0b0265bdbc1ef3'
CARD_HISTORY_MANIFEST_BYTES = 4675
CARD_HISTORY_MANIFEST_SHA256 = '09757e0727bf62917d1b25b0558fcbb2ef2c33dfcd4cbb66a3878ec40b4a07e3'
# path, byte count, SHA256, Git blob OID, exact copy (same pins as V9_93).
CARD_HISTORY = (
    ('Scripts/ci-selection.json', 340, '03c23506919733dde0174448e446d26df4753c505be242587886f142d281314f', '2e8d194fbb52f0bdcc1bd420af4c254638eb9a49', 'blobs/03C23506919733DD.json'),
    ('.github/workflows/ios-ci.yml', 23068, 'bcd64e2a42752d28844435241b5abfca911d04190375cbbdbfc10b45acba97d7', 'bade6a6442bd77a6c15eaefa70726b1efc1b3c73', 'blobs/BCD64E2A42752D28.yml'),
    ('.github/workflows/v23-controller.yml', 1009, '9191e22ef1485af2dc3dd6a1f0201fe16fe2e6f884bed89fc701f1b4eb4b817b', '41ddf4caef03d8ac0041eb2d7a9da96266dfa19d', 'blobs/9191E22EF1485AF2.yml'),
    ('.github/workflows/v23-worker.yml', 5758, 'ee00dd9c894cfdc353b53e52813498c81a7a6d5486920931eec2cbe1caca2f51', 'd0a1b108b9b11e7c3d31cb65ff9a718587e7dc33', 'blobs/EE00DD9C894CFDC3.yml'),
    ('Scripts/v23/controller.py', 3060, 'f5634cf788afe80911db6dbedff53464b23556eff5eef4037a7f625343738b35', 'b5b49853485fbbfc35878f926db5d7eb499a965c', 'blobs/F5634CF788AFE809.py'),
    ('Scripts/v23/controller_contracts.py', 47899, '64f2a2d6975ae17cdab96ca1ddaa78feb5eeb8990325ee632c01f1cd79ccb977', 'd24d453bb0c4460ad2090b73157e673486d83659', 'blobs/64F2A2D6975AE17C.py'),
    ('TestPlans/V23-ReleaseCandidate.xctestplan', 781, '0539566b34917618f575650d256a2ae125fea6e8c31365c07871c52556f4b606', '213268188de10f7e5b919272410c9cb501f09e09', 'blobs/0539566B34917618.xctestplan'),
)

def pretty(value): return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode('utf-8')
def sha(value): return hashlib.sha256(value).hexdigest()
def load(path): return json.loads((ROOT / path).read_bytes())
def git(*args): return subprocess.run(['git',*args], cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()
def source_rows():
    return [{'path':p,'status':'SOURCE_PRESENT' if (ROOT/p).is_file() else 'SOURCE_MISSING','sha256':sha((ROOT/p).read_bytes()) if (ROOT/p).is_file() else None} for p in SOURCE_PATHS]
def source_ready(): return all(r['status'] == 'SOURCE_PRESENT' for r in source_rows())
def historical_coordination_root():
    value = os.environ.get(HISTORICAL_COORDINATION_ENV)
    if value is None: return None
    path = Path(value)
    if not value or not path.is_absolute() or not path.is_dir():
        raise ValueError('C01 explicit historical coordination directory missing or relative')
    return path

def _pinned_bytes(path, byte_count, digest):
    data = path.read_bytes()
    if len(data) != byte_count or sha(data) != digest:
        raise ValueError('C01 historical input bytes differ: ' + path.name)
    return data

def _git_object_id(kind, data):
    return hashlib.sha1(kind.encode('ascii') + b' ' + str(len(data)).encode('ascii') + b'\0' + data).hexdigest()

def _historical_tree(data, expected_oid, expected_count):
    tree = json.loads(data)
    rows = tree.get('tree', [])
    if tree.get('sha') != expected_oid or tree.get('truncated') is not False or len(rows) != expected_count:
        raise ValueError('C01 historical tree identity or completeness differs')
    if len({row['path'] for row in rows}) != len(rows):
        raise ValueError('C01 historical tree duplicate path')
    raw = b''.join((row['mode'].lstrip('0') + ' ' + row['path']).encode('utf-8') + b'\0' + bytes.fromhex(row['sha']) for row in rows)
    if _git_object_id('tree', raw) != expected_oid:
        raise ValueError('C01 historical tree object differs')
    return rows

def historical_coordination_receipt(root):
    # Re-read and authenticate every use; this is not an admission-decision cache.
    inputs = [_pinned_bytes(root / name, size, digest) for name, size, digest in HISTORICAL_COORDINATION_FILES]
    commit = json.loads(inputs[0])
    if commit.get('sha') != COORDINATION_HEAD or commit.get('tree', {}).get('sha') != COORDINATION_TREE:
        raise ValueError('C01 historical coordination commit differs')
    top = _historical_tree(inputs[1], COORDINATION_TREE, 9)
    receipts = _historical_tree(inputs[2], HISTORICAL_RECEIPTS_TREE, 508)
    directory = [row for row in top if row['path'] == 'receipts']
    if len(directory) != 1 or (directory[0]['mode'], directory[0]['type'], directory[0]['sha']) != ('040000', 'tree', HISTORICAL_RECEIPTS_TREE):
        raise ValueError('C01 historical receipts directory differs')
    receipt = [row for row in receipts if row['path'] == Path(BOUNDARY_RECEIPT).name]
    if len(receipt) != 1 or (receipt[0]['mode'], receipt[0]['type'], receipt[0]['sha'], receipt[0]['size']) != ('100644', 'blob', HISTORICAL_RECEIPT_BLOB, len(inputs[3])):
        raise ValueError('C01 historical receipt tree binding differs')
    if _git_object_id('blob', inputs[3]) != HISTORICAL_RECEIPT_BLOB:
        raise ValueError('C01 historical receipt blob differs')
    allocation = [row for row in receipts if row['path'] == HISTORICAL_COORDINATION_FILES[4][0]]
    if len(allocation) != 1 or (allocation[0]['mode'], allocation[0]['type'], allocation[0]['sha'], allocation[0]['size']) != ('100644', 'blob', HISTORICAL_ALLOCATION_BLOB, len(inputs[4])):
        raise ValueError('C01 historical allocation tree binding differs')
    if _git_object_id('blob', inputs[4]) != HISTORICAL_ALLOCATION_BLOB:
        raise ValueError('C01 historical allocation blob differs')
    require_historical_allocation(json.loads(inputs[4]))
    return inputs[3]

def require_historical_allocation(value):
    # Blueprint 8832 fences this card's mutation. This preparation-only receipt
    # authenticates its original allocation; it is not a terminal execution result.
    if (value.get('schema'), value.get('schemaVersion'), value.get('cardID'), value.get('attemptID'), value.get('allocationDigest')) != ('OwnerAuthorizedPathAllocationReceiptV1', 1, CARD, 1, ALLOCATION):
        raise ValueError('C01 historical allocation identity differs')
    if value.get('appCandidateAuthority') != {'baseHead': BASE, 'baseTree': BTREE, 'evidenceAuthority': 'OWNER_AUTHORIZED_PREPARATION_ONLY_ALLOCATION_WITHOUT_APP_WORKTREE_ACCESS'}:
        raise ValueError('C01 historical allocation base authority differs')
    if value.get('exactOrderedPaths') != list(PATH_FENCE) or len(PATH_FENCE) != 14 or len(set(PATH_FENCE)) != 14:
        raise ValueError('C01 historical ordered fourteen-path allocation differs')
    if (value.get('existingPathCount'), value.get('existingPaths'), value.get('newPathCount'), value.get('newPaths')) != (2, list(PATH_FENCE[:2]), 12, list(PATH_FENCE[2:])):
        raise ValueError('C01 historical allocation existing/new partition differs')
    proof = value.get('priorFenceProof', {})
    if (proof.get('authorizationBasis'), proof.get('authorizedOverlapEdgeCount'), proof.get('authorizedOverlapPaths'), proof.get('priorFenceCount'), proof.get('priorFenceSetDigest'), proof.get('s10ReservedOverlapCount'), proof.get('unauthorizedOverlapCount')) != ('OWNER_AUTHORIZED_AGGREGATE_RELEASE_PREFLIGHT_CONSUMERS_ONLY', 13, list(PATH_FENCE[:2]), 137, '54e7079707c1438cdbcc90450c8886655241009f23683999042c8fb928ea712b', 0, 0):
        raise ValueError('C01 historical allocation prior-fence scope differs')
    records = proof.get('authorizedOverlapRecords', [])
    if len(records) != 7 or sum(len(row.get('overlapPaths', [])) for row in records) != 13 or any(set(row.get('overlapPaths', [])) - set(PATH_FENCE[:2]) for row in records):
        raise ValueError('C01 historical allocation overlap records differ')
    if tuple((row.get('selectorID'), row.get('memberCount'), row.get('selectorRowSHA256')) for row in value.get('sourceProjection', {}).get('selectorRows', [])) != SELECTOR_ROWS:
        raise ValueError('C01 historical allocation selector rows differ')
    false_flags = ('acceptanceCredit', 'acceptanceEnabled', 'adoptionEnabled', 'hostedDispatchEnabled', 'hostedDispatchRan', 'nativeCompileRan', 'newMigration', 'newModel', 'newRoot', 'newSchema', 'newStore', 'newWriter', 'phase10PollingDuringParallelExecution', 'phaseIntegrationCredit', 'phaseIntegrationEnabled', 'physicalDeviceEnabled', 'publicationEnabled', 'releaseCredit', 'releaseReady')
    if any(value.get(flag) is not False for flag in false_flags) or value.get('requiresAcceptedS10_6Reconciliation') is not True:
        raise ValueError('C01 historical allocation preparation-only flags differ')

def historical_allocation_provenance():
    historical = historical_coordination_root()
    if historical is None: raise ValueError('C01 current-source mode requires explicit historical inputs')
    historical_coordination_receipt(historical)
    name, size, digest = HISTORICAL_COORDINATION_FILES[4]
    return {'result': 'AUTHENTICATED_ALLOCATION_ONLY', 'file': name, 'byteCount': size, 'sha256': digest, 'gitBlobOID': HISTORICAL_ALLOCATION_BLOB, 'cardID': CARD, 'attemptID': 1, 'appBaseHead': BASE, 'appBaseTree': BTREE, 'allocationDigest': ALLOCATION, 'orderedPathFence': list(PATH_FENCE), 'existingPathCount': 2, 'newPathCount': 12, 'historicalExecutionReplayed': False, 'mutationAuthorizationGranted': False}

def read_only_binding_bytes(path):
    entry = next((row for row in CARD_HISTORY if row[0] == path), None)
    if historical_coordination_root() is None or entry is None:
        return (ROOT / path).read_bytes()
    history = ROOT / CARD_HISTORY_DIRECTORY
    manifest = json.loads(_pinned_bytes(history / 'manifest.json', CARD_HISTORY_MANIFEST_BYTES, CARD_HISTORY_MANIFEST_SHA256))
    if manifest.get('document_id') != 'v23-card-history-v1' or len(manifest.get('entries', [])) != len(CARD_HISTORY):
        raise ValueError('C01 card-time manifest identity or count differs')
    rows = [row for row in manifest['entries'] if row.get('path') == path]
    if len(rows) != 1: raise ValueError('C01 card-time manifest path is missing or duplicated')
    _, size, digest, blob, copy_path = entry
    row = rows[0]
    if (row.get('card_id'), row.get('commit'), row.get('byte_count'), row.get('sha256', '').lower(), row.get('git_blob_oid'), row.get('copy')) != (CARD, CARD_HISTORY_COMMIT, size, digest, blob, copy_path):
        raise ValueError('C01 card-time manifest row differs')
    data = _pinned_bytes(history / copy_path, size, digest)
    if _git_object_id('blob', data) != blob: raise ValueError('C01 card-time Git blob differs')
    return data

def observe_current_coordination_remote():
    if historical_coordination_root() is None: return None
    # A fresh remote read is recorded in command output only. It grants no
    # current coordination authority and is never substituted for origin/main.
    environment = dict(os.environ, GIT_TERMINAL_PROMPT='0', GIT_OPTIONAL_LOCKS='0')
    result = subprocess.run(['git', 'ls-remote', '--exit-code', COORDINATION_REMOTE, 'refs/heads/main'], cwd=ROOT, check=True, capture_output=True, text=True, timeout=30, env=environment)
    rows = [line.split() for line in result.stdout.splitlines() if line.strip()]
    if len(rows) != 1 or len(rows[0]) != 2 or rows[0][1] != 'refs/heads/main' or len(rows[0][0]) != 40 or any(c not in '0123456789abcdef' for c in rows[0][0]):
        raise ValueError('C01 current remote main observation malformed')
    observation = {'repository': COORDINATION_REMOTE, 'ref': 'refs/heads/main', 'sha': rows[0][0], 'observedAtUTC': datetime.now(timezone.utc).isoformat(), 'historicalAuthorityHead': COORDINATION_HEAD, 'grantsCurrentAuthority': False}
    print('C01 current-remote-observation ' + json.dumps(observation, sort_keys=True), file=sys.stderr)
    return observation

def coordination_root():
    root = ROOT.parent / 'AssetRounds-v23-coordination'
    return root if root.is_dir() else None
def authority():
    return {'cardID':CARD,'ordinal':134,'attemptID':1,'appBaseHead':BASE,'appBaseTree':BTREE,'coordinationHead':COORDINATION_HEAD,'coordinationTree':COORDINATION_TREE,'allocationDigest':ALLOCATION,'prerequisiteDigest':PREREQUISITE,'contextDigest':CONTEXT,'pathFenceDigest':FENCE,'sequence':SEQUENCE,'transitionDigest':TRANSITION,'ledgerDigest':LEDGER,'projectionDigest':PROJECTION,'fencePathCount':14,'existingPathCount':2,'newPathCount':12,'priorOverlapCount':13,'priorOverlapAuthorizedPaths':['Scripts/release-preflight.sh','FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift'],'unauthorizedOverlapCount':0,'s10OverlapCount':0,'orderedPathFence':list(PATH_FENCE),'finalHashesSealed':False}
def require_authority(value):
    if value != authority(): raise ValueError('C01 sealed authority differs')
def verify_coordination_identity():
    historical = historical_coordination_root()
    if historical is not None: return historical_coordination_receipt(historical)
    coordination = coordination_root()
    if coordination is None: raise ValueError('C01 coordination root missing')
    def coord_git(*args): return subprocess.run(['git',*args],cwd=coordination,check=True,capture_output=True,text=True).stdout.strip()
    head, origin, tree = (coord_git('rev-parse','HEAD'),coord_git('rev-parse','origin/main'),coord_git('rev-parse','HEAD^{tree}'))
    if (head,origin,tree) != (COORDINATION_HEAD,COORDINATION_HEAD,COORDINATION_TREE): raise ValueError('C01 coordination identity differs')
def boundary_receipt():
    historical_bytes = verify_coordination_identity()
    if historical_bytes is None:
        path = coordination_root() / BOUNDARY_RECEIPT
        if not path.is_file(): raise ValueError('C01 boundary receipt missing')
        historical_bytes = path.read_bytes()
    receipt=json.loads(historical_bytes)
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

def current_worktree_counts():
    # Separate observation: no BASE-to-HEAD comparison or historical zero/PASS.
    # Committed modern changes remain subject to Root's exact candidate review.
    # Suppress optional index refresh writes for every probe in this observation.
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS='0')
    def read_git(*args): return subprocess.run(['git', '-c', 'diff.autoRefreshIndex=false', *args], cwd=ROOT, env=environment, check=True, capture_output=True, text=True).stdout
    head = read_git('rev-parse', 'HEAD').strip()
    tree = read_git('rev-parse', head + '^{tree}').strip()
    changed = set()
    binary_candidates = set()
    # Name-only can report stat-dirty but byte-identical paths when optional
    # refresh is disabled. Numstat reads content without refreshing the index.
    raw = read_git('diff', '--numstat', '--no-ext-diff', '--no-textconv', '--no-renames', '-z', head)
    if raw and not raw.endswith('\0'):
        raise ValueError('C01 current worktree numstat is not NUL terminated')
    for row in raw.split('\0')[:-1] if raw else ():
        fields = row.split('\t', 2)
        if len(fields) != 3 or not fields[2]:
            raise ValueError('C01 current worktree numstat record differs')
        counts = fields[:2]
        if counts != ['-', '-'] and not all(token and all('0' <= char <= '9' for char in token) for token in counts):
            raise ValueError('C01 current worktree numstat counts differ')
        # Keep 0/0 mode-only records and lossless path characters. Binary -/-
        # can also be a stat-only report, so compare its actual raw blob and mode.
        if counts == ['-', '-']: binary_candidates.add(fields[2])
        else: changed.add(fields[2])
    for args in (('diff', '--cached', '--name-only', '--no-renames', '-z', head), ('ls-files', '--others', '--exclude-standard', '-z')):
        raw = read_git(*args)
        changed.update(path for path in raw.split('\0') if path)
    if binary_candidates:
        raw = read_git('ls-tree', '-r', '-z', '--full-tree', head)
        if raw and not raw.endswith('\0'):
            raise ValueError('C01 current HEAD tree is not NUL terminated')
        entries = {}
        for row in raw.split('\0')[:-1] if raw else ():
            metadata, separator, path = row.partition('\t')
            fields = metadata.split(' ')
            if (not separator or not path or path in entries or len(fields) != 3 or
                fields[0] not in ('100644', '100755', '120000', '160000') or
                fields[1] not in ('blob', 'commit') or len(fields[2]) != 40 or
                any(char not in '0123456789abcdef' for char in fields[2])):
                raise ValueError('C01 current HEAD tree record differs')
            entries[path] = tuple(fields)
        def identity(value):
            return tuple(getattr(value, key, 0) for key in
                         ('st_dev', 'st_ino', 'st_mode', 'st_nlink', 'st_uid', 'st_gid',
                          'st_size', 'st_mtime_ns', 'st_ctime_ns', 'st_flags'))
        for path in binary_candidates:
            entry = entries.get(path)
            if entry is None or entry[0] not in ('100644', '100755') or entry[1] != 'blob':
                changed.add(path); continue
            target = ROOT / path
            try: observed = target.lstat()
            except FileNotFoundError:
                changed.add(path); continue
            mode = '100755' if observed.st_mode & 0o111 else '100644'
            if observed.st_mode & 0o170000 != 0o100000 or mode != entry[0]:
                changed.add(path); continue
            descriptor = os.open(target, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                opened = os.fstat(descriptor)
                if identity(opened) != identity(observed):
                    raise ValueError('C01 current binary identity changed before read')
                digest = hashlib.sha1(b'blob ' + str(opened.st_size).encode('ascii') + b'\0')
                length = 0
                while length < opened.st_size:
                    chunk = os.read(descriptor, min(1024 * 1024, opened.st_size - length))
                    if not chunk:
                        raise ValueError('C01 current binary premature EOF')
                    digest.update(chunk); length += len(chunk)
                    if length > opened.st_size:
                        raise ValueError('C01 current binary exceeds captured size')
                if os.read(descriptor, 1):
                    raise ValueError('C01 current binary exceeds captured size')
                if (identity(os.fstat(descriptor)) != identity(opened) or
                    identity(target.lstat()) != identity(opened)):
                    raise ValueError('C01 current binary changed during read')
            finally:
                os.close(descriptor)
            if digest.hexdigest() != entry[2]:
                changed.add(path)
    changed = {path for path in changed if not path.startswith('Scripts/v23/__pycache__/')}
    if read_git('rev-parse', 'HEAD').strip() != head: raise ValueError('C01 current worktree HEAD moved')
    predecessor = (*SOURCE_PATHS[:2],*SCRIPTS,CONTRACT,EVIDENCE,BRAND,MANIFEST)
    family_projections = (
        'docs/design/v23/tooling/V23P04C26OrganicFindabilityContractV1.json',
        'docs/design/v23/tooling/V23P04C26OrganicFindabilityEvidenceReceiptV1.json',
        'docs/design/v23/tooling/V23P04C26BrandImpactManifestV1.json',
        'docs/design/v23/tooling/V23-P04-C26-tooling-manifest.json',
        'docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryContractV1.json',
        'docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryEvidenceReceiptV1.json',
        'docs/design/v23/tooling/V23P04C27BrandImpactManifestV1.json',
        'docs/design/v23/tooling/V23-P04-C27-tooling-manifest.json',
    )
    allowed = set(CURRENT_SOURCE_MUTATION_PATHS)
    frozen_allocation = set(PATH_FENCE) - set(predecessor)
    read_only = {path for _, path in READ_ONLY_BINDINGS}
    if (CURRENT_SOURCE_PREDECESSOR_MUTATION_PATHS != predecessor or
        len(predecessor) != 9 or len(set(predecessor)) != 9 or
        not set(predecessor) <= set(PATH_FENCE) or
        len(family_projections) != 8 or len(set(family_projections)) != 8 or
        not set(predecessor).isdisjoint(family_projections) or
        CURRENT_SOURCE_MUTATION_PATHS != (*predecessor,*family_projections) or
        len(CURRENT_SOURCE_MUTATION_PATHS) != 17 or len(allowed) != 17 or
        not allowed.isdisjoint(frozen_allocation | read_only) or
        any(path.startswith(('Release/', 'docs/design/s10/')) for path in allowed)):
        raise ValueError('C01 current reader mutation fence differs')
    unowned = sorted(changed - allowed)
    frozen = sorted(path for path in changed if path.startswith(('Release/', 'docs/design/s10/')))
    missing = [path for path in PATH_FENCE if not (ROOT / path).is_file()]
    missing.extend(path for path in family_projections
                   if (ROOT / path).is_symlink() or not (ROOT / path).is_file())
    return {'comparison': 'OBSERVED_HEAD_TO_INDEX_WORKTREE_AND_UNTRACKED', 'observedHead': head, 'observedTree': tree, 'allowedMutationPaths': list(CURRENT_SOURCE_MUTATION_PATHS), 'changedPaths': sorted(changed), 'changedPathCount': len(changed), 'unownedChangedPaths': unowned, 'unownedChangedPathCount': len(unowned), 'frozenChangedPaths': frozen, 'frozenChangedPathCount': len(frozen), 'missingFencedPaths': missing, 'missingFencedPathCount': len(missing), 'committedMutationAuthorizationChecked': False}

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
    if tuple((x.get('role'),x.get('path')) for x in bindings) != READ_ONLY_BINDINGS or len({x.get('path') for x in bindings}) != 17 or any(not (ROOT/x['path']).is_file() or x.get('sha256') != sha(read_only_binding_bytes(x['path'])) for x in bindings): raise ValueError('C01 read-only bindings differ')
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
    historical = historical_coordination_root()
    if historical is not None:
        historical_coordination_receipt(historical)
        history_rows = []
        for path, _, _, blob, copy_path in CARD_HISTORY:
            data = read_only_binding_bytes(path)
            history_rows.append({'path': path, 'byteCount': len(data), 'sha256': sha(data), 'gitBlobOID': blob, 'copy': copy_path})
        scripts['contractsSHA256'] = sha((ROOT/SCRIPTS[0]).read_bytes())
        base['commands'][1] = {'command': 'python -B Scripts/v23/verify_p05_c01_contracts.py --current-source --json', 'mode': CURRENT_SOURCE_SCOPE}
        base['verificationScope'] = CURRENT_SOURCE_SCOPE
        base['candidateAndAuthorityRole'] = 'HISTORICAL_INPUT_IDENTITY_ONLY'
        base['sourceRowsRole'] = 'CURRENT_SOURCE_BYTES_NOT_HISTORICAL_EXECUTION'
        base['inputProvenance'] = {'mode': 'AUTHENTICATED_HISTORICAL_INPUTS', 'historicalExecutionReplayed': False, 'currentRemoteObservationIsAuthority': False, 'historicalAllocation': historical_allocation_provenance(), 'coordinationInputFiles': [{'name': name, 'byteCount': size, 'sha256': digest} for name, size, digest in HISTORICAL_COORDINATION_FILES], 'cardHistoryCommit': CARD_HISTORY_COMMIT, 'cardHistoryManifestSHA256': CARD_HISTORY_MANIFEST_SHA256, 'cardHistorySourceRows': history_rows}
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
