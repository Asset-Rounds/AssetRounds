from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CARD = 'V23-P04-C27'
BASE = '4c29f9781856526e6eb94a6cf357911497bb4c1f'
BTREE = 'ed081e7349e1577546c68b7bd7414d39a454df5f'
HEAD = 'e0b470a3ca730b288695553ff7a2d2f129de7e63'
CTREE = '63f250f0b243db30c45120fe45b9283404e6b1ae'
SEQ = 502
CONTEXT = '053ccf31cd3829f448228cad922cef94264a6443a487c2a3521e6cf667f6e12c'
FENCE = 'beae3b22cda76516c6a32e18186c11e442cde537e6d013e746ebe476fc3e5a32'
ALLOCATION = '1b92d727c0ba3272f0a992330c9b2d814aa43e94eca2034a6c58794de0aadefa'
PREREQ = '3d6cbf499a9f0b4aeb6d26ac349a35f80cbfb9f49435196d3db266eb0e3ba8e4'
FINAL_HASHES_SEALED = False

SCHEMA = 'Scripts/v23/brand-hig-state-inventory.schema.json'
PRODUCT = 'docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json'
TEST = 'FieldEvidenceAppTests/V9_90BrandHIGStateInventoryTests.swift'
FIXTURE = 'FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C27BrandHIGStateInventoryCorpusV1.json'
UI = 'FieldEvidenceAppUITests/V23_P04_C27BrandHIGStateInventoryUITests.swift'
CONTRACT = 'docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryContractV1.json'
EVIDENCE = 'docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryEvidenceReceiptV1.json'
BRAND = 'docs/design/v23/tooling/V23P04C27BrandImpactManifestV1.json'
MANIFEST = 'docs/design/v23/tooling/V23-P04-C27-tooling-manifest.json'
SCRIPTS = ('Scripts/v23/p04_c27_contracts.py', 'Scripts/v23/generate_p04_c27_contracts.py', 'Scripts/v23/verify_p04_c27_contracts.py')
OWNED = set((*SCRIPTS, CONTRACT, EVIDENCE, BRAND, MANIFEST))
PATH_FENCE = ('Scripts/release-preflight.sh', 'FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift', PRODUCT, TEST, FIXTURE, UI, *SCRIPTS, SCHEMA, CONTRACT, EVIDENCE, BRAND, MANIFEST)
SELECTORS = ('testV23P04C27G01CompleteBrandHIGStateInventoryAndFreeze', 'testV23P04C27A01GovernedReuseAndDualRuntimeSemanticParity', 'testV23P04C27H01HostileIdentityVocabularyStateAndIconDriftFailClosed', 'testV23P04C27I01ManifestLastInterruptionAndDeterministicRetry', 'testV23P04C27R01PreflightRemainsProvisionalUntilLaterAuthorities')
FLAGS = {key: False for key in ('physicalDevice', 'native', 'hosted', 'activation', 'adoption', 'acceptance', 'publication', 'release')}
PINS = {'V23-P04-C27': (7628, 'c1d3be2ba63fdfd75c060598ea2e1ea668d8cf31e912b2a4c3d08df7bfda9124'), 'V21-P04-C27': (14096, '307cb4650e59603d1e5849f65cadb43269f9faa1e4e53f2fe4c0af8e286c3b4c'), 'V23-P04-C27-register': (295, 'b47faab3abc1e20b5d89acd976585a1928098d02acd5d7226be445021e1dd283')}
CORRECTION_TRANSITION = '5515b4a81134bd09672bd0019021679a1f21266e0efbc2573ced73476fa7bdfc'
PRIOR_ALLOCATION = 'b4c132b0bce6358965c245b18309cf52222972b4bc7b1ef9e470dffbca5de8d3'
FROZEN_S10_DIGEST = '274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a'
FROZEN_S10 = tuple('''
.github/workflows/ios-ci-worker.yml
.github/workflows/ios-ci.yml
AGENTS.md
FieldEvidenceApp.xcodeproj/project.pbxproj
FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme
FieldEvidenceApp/App/FieldEvidenceAppApp.swift
FieldEvidenceApp/App/LaunchView.swift
FieldEvidenceApp/DesignSystem/DesignTokens.swift
FieldEvidenceApp/DesignSystem/WorklightComponents.swift
FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift
FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift
FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift
FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift
FieldEvidenceApp/Features/CheckRunner/PreflightView.swift
FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift
FieldEvidenceApp/Features/Issues/IssueDetailView.swift
FieldEvidenceApp/Features/Issues/RecordWorkView.swift
FieldEvidenceApp/Features/Issues/WorkCoordinator.swift
FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift
FieldEvidenceApp/Features/Reports/ReportDetailView.swift
FieldEvidenceApp/Features/Reports/ReportFailureView.swift
FieldEvidenceApp/Features/Reports/ReportsRootView.swift
FieldEvidenceApp/Features/Sample/PackSampleView.swift
FieldEvidenceApp/Features/Settings/BackupExportView.swift
FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift
FieldEvidenceApp/Features/Settings/EraseAllView.swift
FieldEvidenceApp/Features/Settings/FeedbackView.swift
FieldEvidenceApp/Features/Shell/AppShellView.swift
FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift
FieldEvidenceApp/Features/Signs/NewSignView.swift
FieldEvidenceApp/Features/Signs/SignDetailView.swift
FieldEvidenceApp/Features/Signs/SignsRootView.swift
FieldEvidenceApp/Features/Subscription/PaywallView.swift
FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift
FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift
FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift
FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift
FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png
FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Default-1024.png
FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted-1024.png
FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsAccentTeal.colorset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandCanvas.colorset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-1x.png
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-2x.png
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-3x.png
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-1x.png
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-2x.png
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-3x.png
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsCheckpointGreen.colorset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsDeepTeal.colorset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsInk.colorset/Contents.json
FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsSlate.colorset/Contents.json
FieldEvidenceAppTests/S10_1BrandInventoryTests.swift
FieldEvidenceAppTests/S10_2BrandComponentTests.swift
FieldEvidenceAppTests/S10_3BrandMigrationTests.swift
FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift
FieldEvidenceAppUITests/S10_1BrandInventoryUITests.swift
FieldEvidenceAppUITests/S10_2BrandComponentUITests.swift
FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift
Scripts/ci-selection.json
Scripts/s10-4-segment-assembler.sh
Scripts/s10-4-segment-plan.json
Scripts/s10-4-shards.json
Scripts/ui-smoke.sh
docs/design/s10/authority/asset-manifest.json
docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip
docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json
docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json
docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json
docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1
docs/design/s10/s10-accessibility-common-tasks.json
docs/design/s10/s10-activation.json
docs/design/s10/s10-experience-validation.json
docs/design/s10/s10-screen-state-inventory.json
docs/design/s10/s10-stage-checkpoints.json
docs/design/s10/s10-store-readiness.json
docs/design/s10/s10-token-coverage.json
docs/design/s10/s10-visual-regression.json
docs/execution/CODEX_EXECUTION_CONTRACT_V4.md
docs/execution/CURRENT_TASK.md
docs/execution/HANDOFF.md
docs/execution/V4_IMPLEMENTATION_RUNBOOK.md
docs/product/BUILD_PLAN_V4.md
'''.splitlines()[1:])

def pretty(value): return (json.dumps(value, sort_keys=True, indent=2) + '\n').encode()
def sha(value): return hashlib.sha256(value).hexdigest()
def git(*args, cwd=ROOT): return subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()
def coord_root():
    override = os.environ.get('V23_P04_C27_COORDINATION_ROOT')
    if override == 'NONE': return None
    candidate = Path(override).expanduser() if override else ROOT.parent / 'AssetRounds-v23-coordination'
    return candidate.resolve() if candidate.is_dir() else None
def coord_json(coord, path): return json.loads(subprocess.run(['git', 'show', HEAD + ':' + path], cwd=coord, check=True, capture_output=True).stdout)

def source_pins():
    blueprint = subprocess.run(['git', 'show', BASE + ':docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md'], cwd=ROOT, check=True, capture_output=True).stdout
    foundation = subprocess.run(['git', 'show', BASE + ':docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md'], cwd=ROOT, check=True, capture_output=True).stdout
    if git('rev-parse', BASE + '^{tree}') != BTREE: raise ValueError('C27 app base tree differs')
    def block(anchor, indent):
        hit = re.search(rf'(?ms)^{indent}### {re.escape(anchor)} —.*?(?=^{indent}### |\Z)', blueprint.decode())
        if not hit: raise ValueError('C27 source heading missing: ' + anchor)
        return hit.group(0).encode()
    index = foundation.index(b'P04-C27'); row = foundation[foundation.rfind(b'\n', 0, index) + 1:foundation.index(b'\n', index) + 1]
    values = {'V23-P04-C27': block('V23-P04-C27', ''), 'V21-P04-C27': block('V21-P04-C27', '    '), 'V23-P04-C27-register': row}
    for name, value in values.items():
        if (len(value), sha(value)) != PINS[name]: raise ValueError('C27 source pin differs: ' + name)
    return [{'anchor': name, 'utf8Length': len(value), 'sha256': sha(value)} for name, value in values.items()]
def base_blob(path):
    if path.startswith('/') or '..' in Path(path).parts: raise ValueError('C27 invalid immutable path')
    try:
        return subprocess.run(['git', 'show', BASE + ':' + path], cwd=ROOT, check=True, capture_output=True).stdout.decode('utf-8', errors='strict')
    except subprocess.CalledProcessError as error:
        raise ValueError('C27 immutable source missing: ' + path) from error

def sealed_authority(pins=None):
    if pins is None: pins = [{'anchor': name, 'utf8Length': length, 'sha256': digest} for name,(length,digest) in PINS.items()]
    return {'cardID': CARD, 'appBaseHead': BASE, 'appBaseTree': BTREE, 'coordinationHead': HEAD, 'coordinationTree': CTREE, 'sequence': SEQ, 'contextDigest': CONTEXT, 'pathFenceDigest': FENCE, 'allocationDigest': ALLOCATION, 'prerequisiteDigest': PREREQ, 'allocationCorrectionTransitionDigest': CORRECTION_TRANSITION, 'allocationCorrectionSupersedesDigest': PRIOR_ALLOCATION, 'fencePathCount': 14, 'existingPathCount': 2, 'newPathCount': 12, 'priorFenceProof': {'fenceCount': 1, 'priorOwnedPathCount': 16, 'authorizedOverlapCount': 2, 'unauthorizedOverlapCount': 0, 's10ReservedOverlapCount': 0, 'authorizedOverlapPaths': ['Scripts/release-preflight.sh', 'FieldEvidenceAppTests/S9_1ReleasePreflightTests.swift']}, 's10OverlapCount': 0, 'sourcePins': pins, 'finalHashesSealed': False, 'activeS10ReservedPaths': list(FROZEN_S10), 'frozenS10ReservationDigest': FROZEN_S10_DIGEST, 'orderedPathFence': list(PATH_FENCE)}

def require_sealed_authority(value):
    if not isinstance(value, dict) or value != sealed_authority(): raise ValueError('C27 portable sealed authority differs')

def authority():
    coord = coord_root()
    if coord is None:
        manifest = json.loads((ROOT / MANIFEST).read_bytes())
        authority = manifest.get('authority', {})
        require_sealed_authority(authority)
        if tuple(manifest.get('pathFence', ())) != PATH_FENCE: raise ValueError('C27 portable manifest fence differs')
        return authority
    if (git('rev-parse', 'HEAD', cwd=coord), git('rev-parse', 'HEAD^{tree}', cwd=coord)) != (HEAD, CTREE): raise ValueError('C27 coordination identity differs')
    context = coord_json(coord, f'contexts/{CARD}-attempt-1/BootstrapCardContextV1.json')
    fence = coord_json(coord, f'contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json')
    allocation = coord_json(coord, f'receipts/{CARD}-owner-authorized-path-allocation-v2.json')
    if (context.get('contextDigest'), fence.get('fenceDigest'), context.get('ownerAuthorizedPathAllocationDigest'), context.get('provisionalPrerequisiteDigest')) != (CONTEXT, FENCE, ALLOCATION, PREREQ): raise ValueError('C27 coordination digests differ')
    proof = fence.get('priorFenceProof', {})
    if tuple(fence.get('allowedCreateOrReplacePaths', ())) != PATH_FENCE or (len(context.get('existingPaths', ())), len(context.get('newPaths', ())), proof.get('fenceCount'), proof.get('priorOwnedPathCount'), proof.get('authorizedOverlapCount'), proof.get('unauthorizedOverlapCount'), proof.get('s10ReservedOverlapCount')) != (2, 12, 1, 16, 2, 0, 0): raise ValueError('C27 fence/proof differs')
    if allocation.get('allocationDigest') != ALLOCATION or allocation.get('schema') != 'OwnerAuthorizedPathAllocationReceiptV2' or allocation.get('canonicalRegistryOwner') != 'ContractFacetRegistryV1' or tuple(allocation.get('primaryRegistryFamilies', ())) != ('BrandHIGStateInventoryContractV1', 'ApplicationStateInventoryV1', 'BrandVocabularyMapV1', 'TechnicalIdentityFreezeV1') or allocation.get('supersedesAllocationDigest') != PRIOR_ALLOCATION: raise ValueError('C27 allocation correction differs')
    transition = coord_json(coord, f'transitions/000502-{CARD}-attempt-1-HYDRATING-allocation-name-correction.json')
    if transition.get('transitionDigest') != CORRECTION_TRANSITION or tuple(fence.get('activeS10ReservedPaths', ())) != FROZEN_S10 or fence.get('frozenS10ReservationDigest') != FROZEN_S10_DIGEST or set(PATH_FENCE) & set(FROZEN_S10): raise ValueError('C27 correction/S10 authority differs')
    result = sealed_authority(source_pins())
    require_sealed_authority(result)
    return result

def portable_authority_self_test():
    import copy
    samples = []
    for label, mutate in (
        ('coordination', lambda x: x.__setitem__('coordinationHead', '0' * 40)),
        ('correction', lambda x: x.__setitem__('allocationCorrectionTransitionDigest', '0' * 64)),
        ('source-pins', lambda x: x['sourcePins'][0].__setitem__('sha256', '0' * 64)),
        ('prior-proof', lambda x: x['priorFenceProof'].__setitem__('authorizedOverlapCount', 0)),
        ('s10', lambda x: x['activeS10ReservedPaths'].__setitem__(0, 'changed')),
        ('fence', lambda x: x['orderedPathFence'].__setitem__(0, 'changed')),
    ):
        candidate = copy.deepcopy(sealed_authority()); mutate(candidate)
        try: require_sealed_authority(candidate)
        except ValueError: samples.append(label); continue
        raise ValueError('C27 portable hostile accepted: ' + label)
    return {'result': 'PASS', 'rejected': samples, 'count': len(samples)}

def sources(): return tuple(path for path in PATH_FENCE if path not in OWNED)
def rows():
    result = [{'path': path, 'status': 'SOURCE_PRESENT' if (ROOT / path).is_file() else 'SOURCE_MISSING', 'sha256': sha((ROOT / path).read_bytes()) if (ROOT / path).is_file() else None} for path in sources()]
    return result, all(row['status'] == 'SOURCE_PRESENT' for row in result)
def counts():
    allowed = set(PATH_FENCE)
    def names(*args): return {line.replace('\\', '/') for line in git(*args).splitlines() if line}
    changed = names('diff', '--name-only', BASE, 'HEAD') | names('diff', '--name-only', 'HEAD') | names('diff', '--cached', '--name-only') | names('ls-files', '--others', '--exclude-standard') | OWNED
    reservation = set(authority().get('activeS10ReservedPaths', ()))
    return {'changedPathCount': len(changed & allowed), 'missingPathCount': sum(not (ROOT / path).is_file() for path in allowed - OWNED), 'unownedChangedPathCount': len(changed - allowed), 's10ReservationOverlapCount': len(allowed & reservation)}

def _same(left, right): return json.dumps(left, sort_keys=True, separators=(',', ':')) == json.dumps(right, sort_keys=True, separators=(',', ':'))
def _schema_errors(value, node, root, trail='$'):
    if '$ref' in node:
        ref = node['$ref']
        if not isinstance(ref, str) or not ref.startswith('#/$defs/') or ref.count('/') != 2 or ref.rsplit('/', 1)[1] not in root.get('$defs', {}): return [trail + ': invalid local ref']
        return _schema_errors(value, root['$defs'][ref.rsplit('/', 1)[1]], root, trail)
    errors=[]; expected=node.get('type')
    kinds={'object': isinstance(value, dict), 'array': isinstance(value, list), 'string': isinstance(value, str), 'integer': isinstance(value, int) and not isinstance(value, bool), 'boolean': isinstance(value, bool), 'null': value is None}
    if expected is not None:
        allowed=expected if isinstance(expected, list) else [expected]
        if not all(isinstance(kind, str) and kind in kinds for kind in allowed): return [trail + ': invalid type declaration']
        if not any(kinds[kind] for kind in allowed): return [trail + ': type differs']
    if 'const' in node and not _same(value, node['const']): errors.append(trail + ': const differs')
    if 'enum' in node and not any(_same(value, item) for item in node['enum']): errors.append(trail + ': enum differs')
    if isinstance(value, dict):
        props=node.get('properties', {})
        if not isinstance(props, dict): return [trail + ': invalid properties']
        errors.extend(trail+'.'+key+': required' for key in node.get('required', ()) if key not in value)
        if node.get('additionalProperties') is False: errors.extend(trail+'.'+key+': additional property' for key in value if key not in props)
        for key, child in props.items():
            if key in value: errors.extend(_schema_errors(value[key], child, root, trail+'.'+key))
    if isinstance(value, list):
        if 'minItems' in node and len(value) < node['minItems']: errors.append(trail + ': too few items')
        if 'maxItems' in node and len(value) > node['maxItems']: errors.append(trail + ': too many items')
        if node.get('uniqueItems') and len({json.dumps(item, sort_keys=True, separators=(',', ':')) for item in value}) != len(value): errors.append(trail + ': duplicate item')
        if 'items' in node:
            for index, item in enumerate(value): errors.extend(_schema_errors(item, node['items'], root, trail+'['+str(index)+']'))
    if isinstance(value, str):
        if 'minLength' in node and len(value) < node['minLength']: errors.append(trail + ': too short')
        if 'pattern' in node and re.search(node['pattern'], value) is None: errors.append(trail + ': pattern differs')
    return errors
def validate_schema(value):
    schema = json.loads((ROOT / SCHEMA).read_bytes())
    if schema.get('$schema') != 'https://json-schema.org/draft/2020-12/schema' or not isinstance(schema.get('$defs'), dict): raise ValueError('C27 schema draft differs')
    errors = _schema_errors(value, schema, schema)
    if errors: raise ValueError('C27 schema validation: ' + errors[0])
    try:
        from jsonschema import Draft202012Validator
    except ImportError:
        return
    Draft202012Validator.check_schema(schema)
    if list(Draft202012Validator(schema).iter_errors(value)): raise ValueError('C27 formal Draft2020 validation differs')

def schema_self_test(value):
    import copy
    candidates=[]
    extra=copy.deepcopy(value); extra['contracts']['technicalIdentityFreeze']['unexpected']=True; candidates.append(('nested-extra-key',extra))
    missing=copy.deepcopy(value); del missing['discovery']['criticalInputs']; candidates.append(('missing-critical-inputs',missing))
    malformed=copy.deepcopy(value); malformed['contracts']['applicationStateInventory']['rendererOwners'][0]['renderers']=['1Bad']; candidates.append(('malformed-renderer',malformed))
    for label,candidate in candidates:
        try: validate_schema(candidate)
        except ValueError: continue
        raise ValueError('C27 schema hostile accepted: '+label)
    return {'result':'PASS','rejected':[label for label,_ in candidates],'count':len(candidates)}

def _token_present(text, token): return re.search(r'(?<![A-Za-z0-9_])' + re.escape(token) + r'(?![A-Za-z0-9_])', text) is not None
def _bind_renderer_and_graph(inventory):
    contracts = inventory['contracts']; owners = contracts['applicationStateInventory']['rendererOwners']
    if len(owners) != 41 or len({row['path'] for row in owners}) != 41: raise ValueError('C27 renderer owner path uniqueness differs')
    renderers = [renderer for row in owners for renderer in row['renderers']]
    if len(renderers) != 54 or len(set(renderers)) != 54: raise ValueError('C27 renderer inventory uniqueness differs')
    for row in owners:
        blob = base_blob(row['path'])
        if any(not _token_present(blob, renderer) for renderer in row['renderers']): raise ValueError('C27 immutable renderer symbol binding differs: ' + row['path'])
    edges = contracts['affectedConsumerGraph']['edges']
    expected = (('DESIGN_TOKENS', ('ALL_RENDERERS',)), ('SHARED_COMPONENTS', ('ALL_RENDERERS',)), ('BRAND_VOCABULARY', ('ALL_PUBLIC_COPY', 'REPORTS', 'SUPPORT_EXPORT')), ('ROUTE_REGISTRY', ('NAVIGATION', 'RESTORATION', 'PRIVATE_DISCOVERY')), ('SEMANTIC_IDENTITIES', ('VOICEOVER', 'VOICE_CONTROL', 'UI_TESTS')), ('TECHNICAL_IDENTITIES', ('BACKUP', 'RESTORE', 'DELETE', 'REPORT', 'SEARCH')))
    actual = tuple((edge.get('source'), tuple(edge.get('consumers', ()))) for edge in edges)
    if actual != expected or len(edges) != 6: raise ValueError('C27 affected consumer graph differs')
    expanded = {source: tuple(sorted(renderers)) if consumers == ('ALL_RENDERERS',) else consumers for source, consumers in actual}
    if tuple(expanded['DESIGN_TOKENS']) != tuple(sorted(renderers)) or tuple(expanded['SHARED_COMPONENTS']) != tuple(sorted(renderers)) or len(expanded['DESIGN_TOKENS']) != 54 or set(expanded['DESIGN_TOKENS']) != set(renderers) or set(expanded['SHARED_COMPONENTS']) != set(renderers): raise ValueError('C27 ALL_RENDERERS expansion differs')
    if len(renderers) != len(set(renderers)) or any(source not in {item[0] for item in expected} for source,_ in actual): raise ValueError('C27 graph consumer coverage differs')
def _bind_technical_identity(inventory):
    identity = inventory['contracts']['technicalIdentityFreeze']
    expected = {'bundleIDs': ['com.palatis3.fieldrecord', 'com.palatis3.fieldrecord.tests', 'com.palatis3.fieldrecord.uitests'], 'targetNames': ['FieldEvidenceApp', 'FieldEvidenceAppTests', 'FieldEvidenceAppUITests'], 'moduleNames': ['FieldEvidenceApp', 'FieldEvidenceAppTests', 'FieldEvidenceAppUITests'], 'entryPointIdentity': 'FieldEvidenceAppApp', 'backupUTI': 'com.palatis3.fieldrecordbackup', 'backupExtension': 'fieldrecordbackup', 'storageRoots': ['FieldEvidenceData', 'FieldEvidenceOperations', 'FieldEvidenceRestore'], 'storeKitProductIDs': ['com.palatis3.fieldrecord.sub.solo.monthly.v1'], 'schemaIdentitySource': 'FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift', 'wireIdentitySource': 'FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift', 'backupIdentitySources': ['FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift', 'FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift']}
    if any(identity.get(key) != value for key,value in expected.items()) or identity.get('contract') != 'TechnicalIdentityFreezeV1': raise ValueError('C27 technical identity values differ')
    project = base_blob('FieldEvidenceApp.xcodeproj/project.pbxproj'); plist = base_blob('FieldEvidenceApp/Info.plist'); app = base_blob('FieldEvidenceApp/App/FieldEvidenceAppApp.swift'); backup = base_blob('FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift'); schema = base_blob(expected['schemaIdentitySource']); wire = base_blob(expected['wireIdentitySource']); backup_contract = base_blob(expected['backupIdentitySources'][0]); compatibility = base_blob(expected['backupIdentitySources'][1]); storekit = base_blob('TestFixtures/StoreKit/FieldEvidence.storekit')
    if any(item not in project for item in expected['bundleIDs'] + expected['targetNames'] + expected['moduleNames']) or 'FieldEvidence.storekit' not in project: raise ValueError('C27 project target/module identity binding differs')
    if expected['backupUTI'] not in plist or expected['backupExtension'] not in plist: raise ValueError('C27 UTI/extension binding differs')
    if any(item not in app for item in expected['storageRoots']) or any(item not in backup for item in ('FieldEvidenceData', 'FieldEvidenceRestore')) or expected['backupExtension'] not in app or expected['backupExtension'] not in backup: raise ValueError('C27 storage/backup binding differs')
    if expected['storeKitProductIDs'][0] not in storekit or ('struct ' + expected['entryPointIdentity'] + ': App') not in app or 'PersistentSchemaV53.models.count == 168' not in schema: raise ValueError('C27 entry/schema/storekit binding differs')
    if not all(token in wire for token in ('WorkspaceMutationCanonicalV1', 'WorkspaceEntityIdentityV1')): raise ValueError('C27 wire identity binding differs')
    if not all(token in backup_contract for token in ('V4Backup', 'schemaVersion')) or not all(token in compatibility for token in ('currentWriterVersion', 'unknownFileVersionFailsClosed', 'persistentSchemaVersion')): raise ValueError('C27 backup identity binding differs')
def semantics_self_test(inventory):
    import copy
    hostile=[]
    def rejected(label, mutate):
        candidate=copy.deepcopy(inventory); mutate(candidate)
        try: _bind_renderer_and_graph(candidate); _bind_technical_identity(candidate)
        except ValueError: hostile.append(label); return
        raise ValueError('C27 semantic hostile accepted: '+label)
    rejected('nonexistent-renderer-path', lambda x: x['contracts']['applicationStateInventory']['rendererOwners'][0].__setitem__('path','FieldEvidenceApp/Missing.swift'))
    rejected('nonexistent-renderer-symbol', lambda x: x['contracts']['applicationStateInventory']['rendererOwners'][0]['renderers'].__setitem__(0,'NoSuchRenderer'))
    rejected('partial-consumer-graph', lambda x: x['contracts']['affectedConsumerGraph']['edges'].__delitem__(0))
    rejected('bundle-rename', lambda x: x['contracts']['technicalIdentityFreeze']['bundleIDs'].__setitem__(0,'com.example.changed'))
    rejected('uti-rename', lambda x: x['contracts']['technicalIdentityFreeze'].__setitem__('backupUTI','com.example.changed'))
    rejected('storage-rename', lambda x: x['contracts']['technicalIdentityFreeze']['storageRoots'].__setitem__(0,'Changed'))
    rejected('product-id-rename', lambda x: x['contracts']['technicalIdentityFreeze']['storeKitProductIDs'].__setitem__(0,'com.example.changed'))
    rejected('backup-extension-rename', lambda x: x['contracts']['technicalIdentityFreeze'].__setitem__('backupExtension','changed'))
    rejected('entry-point-rename', lambda x: x['contracts']['technicalIdentityFreeze'].__setitem__('entryPointIdentity','ChangedApp'))
    rejected('target-rename', lambda x: x['contracts']['technicalIdentityFreeze']['targetNames'].__setitem__(0,'Changed'))
    rejected('module-rename', lambda x: x['contracts']['technicalIdentityFreeze']['moduleNames'].__setitem__(0,'Changed'))
    rejected('wire-source-rename', lambda x: x['contracts']['technicalIdentityFreeze'].__setitem__('wireIdentitySource','FieldEvidenceApp/Missing.swift'))
    rejected('backup-source-rename', lambda x: x['contracts']['technicalIdentityFreeze']['backupIdentitySources'].__setitem__(0,'FieldEvidenceApp/Missing.swift'))
    rejected('schema-source-rename', lambda x: x['contracts']['technicalIdentityFreeze'].__setitem__('schemaIdentitySource','FieldEvidenceApp/Missing.swift'))
    return {'result':'PASS','rejected':hostile,'count':len(hostile)}

def semantics(ready):
    if not ready: return
    inventory = json.loads((ROOT / PRODUCT).read_bytes())
    corpus = json.loads((ROOT / FIXTURE).read_bytes())
    validate_schema(inventory)
    schema_self_test(inventory)
    portable_authority_self_test()
    text = {path: (ROOT / path).read_text(encoding='utf-8', errors='replace') for path in sources()}
    test, ui, product, fixture = text[TEST], text[UI], text[PRODUCT], text[FIXTURE]
    if any(selector not in test for selector in SELECTORS) or len(re.findall(r'XCTSkip', ui)) != 5: raise ValueError('C27 selector/UI skip mismatch')
    required = ('BrandHIGStateInventoryContractV1', 'ApplicationStateInventoryV1', 'BrandVocabularyMapV1', 'TechnicalIdentityFreezeV1', 'NONPERSISTENT', 'Practice', 'accessibility', 'recipe', 'owner', 'icon', '1024', 'appearance', 'syntheticOnly')
    if any(token not in product + fixture + test for token in required): raise ValueError('C27 inventory semantics missing')
    contracts = inventory.get('contracts', {})
    if set(contracts) != {'affectedConsumerGraph', 'appIconReleaseManifest', 'applicationStateInventory', 'brandHIGStateInventory', 'brandPrePolishFreezeReceipt', 'brandVocabularyMap', 'technicalIdentityFreeze'}: raise ValueError('C27 seven-contract inventory differs')
    if contracts['brandHIGStateInventory'].get('lifecycle') != 'NONPERSISTENT' or inventory.get('syntheticOnly') is not True: raise ValueError('C27 nonpersistent/synthetic contract differs')
    identity = contracts['technicalIdentityFreeze']; vocabulary = contracts['brandVocabularyMap']; states = contracts['applicationStateInventory']; icon = contracts['appIconReleaseManifest']
    if identity.get('renameAllowed') is not False or identity.get('historicDisplayMutationAllowed') is not False or vocabulary.get('practice') != 'Practice' or vocabulary.get('residuePolicy') != 'ZERO_UNALLOWLISTED_VISIBLE_FIELD_EVIDENCE': raise ValueError('C27 technical identity/vocabulary freeze differs')
    if set(states.get('roots', ())) != {'ASSETS', 'REPORTS', 'TODAY', 'WORK'} or len(states.get('rendererOwners', ())) != 41 or sum(len(row.get('renderers', ())) for row in states.get('rendererOwners', ())) != 54 or len(states.get('commonStates', ())) != 18 or len(states.get('accessibilityVariants', ())) != 12 or states.get('unknownOwnerDisposition') != 'FAIL_CLOSED': raise ValueError('C27 state owner/identity inventory differs')
    taxonomy = contracts['brandHIGStateInventory'].get('higTaxonomy', {})
    if (taxonomy.get('leafCount'), taxonomy.get('applicable'), taxonomy.get('platformHandled'), taxonomy.get('notApplicableWithRationale'), taxonomy.get('deferredOutsideV21')) != (157, 65, 10, 76, 6): raise ValueError('C27 HIG taxonomy disposition differs')
    if len(icon.get('appearances', ())) != 6 or icon.get('appStoreArtwork1024') != 'NOT_PRODUCED' or icon.get('selectedSourcePath') is not None or icon.get('selectedBuildSetting') is not None: raise ValueError('C27 icon source/build truth differs')
    drafts = inventory.get('discovery', {}).get('c26Drafts', ())
    if len(drafts) != 4 or any(row.get('adopted') is not False for row in drafts): raise ValueError('C27 C26 external-draft exclusion differs')
    cases = corpus.get('cases', [])
    if corpus.get('schema') != 'V23P04C27BrandHIGStateInventoryCorpusV1' or len(cases) != 22 or not any(case.get('expected') == 'REJECT_EXTERNAL_DRAFT_ADOPTION' for case in cases): raise ValueError('C27 hostile corpus differs')
    _bind_renderer_and_graph(inventory)
    _bind_technical_identity(inventory)
    semantics_self_test(inventory)

def protocol():
    return {'protocol': 'MANIFEST_LAST_ATOMIC_REPLACE', 'rows': [{'boundary': 'BEFORE_ARTIFACTS', 'acceptedSetCount': 0, 'manifestLast': True, 'temporaryRootMayContainIncompleteArtifacts': True, 'retryAcceptedSetCount': 1, 'retryDeterministic': True, 'realWorktreeUnchanged': True}, {'boundary': 'AFTER_ARTIFACTS_BEFORE_MANIFEST', 'acceptedSetCount': 0, 'manifestLast': True, 'temporaryRootMayContainIncompleteArtifacts': True, 'retryAcceptedSetCount': 1, 'retryDeterministic': True, 'realWorktreeUnchanged': True}, {'boundary': 'AFTER_MANIFEST', 'acceptedSetCount': 1, 'manifestLast': True, 'temporaryRootMayContainIncompleteArtifacts': False, 'retryAcceptedSetCount': 1, 'retryDeterministic': True, 'realWorktreeUnchanged': True}], 'deterministicRerun': True, 'realWorktreeUnchanged': True}
def documents():
    a = authority(); source_rows, ready = rows(); c = counts(); p = {'sourceReady': ready, 'sourceRows': source_rows, 'counts': c, 'selectors': list(SELECTORS)}
    semantics = {'sevenContracts': 'NONPERSISTENT_INVENTORY_EVIDENCE', 'persistentSchema': 'V53', 'activeModelCount': 168, 'newDurableRecordCount': 0, 'newDurableFamilies': [], 'statusFlags': FLAGS}
    contract = {'schema': 'V23P04C27BrandHIGStateInventoryContractV1', 'schemaVersion': 1, 'cardID': CARD, 'provisional': True, 'authority': a, 'semantics': semantics, 'sourceProjection': p, 'testSelectors': list(SELECTORS), 'statusFlags': FLAGS}
    evidence = {'schema': 'V23P04C27BrandHIGStateInventoryEvidenceReceiptV1', 'schemaVersion': 1, 'cardID': CARD, 'provisional': True, 'authority': a, 'sourceProjection': p, 'contractDigest': sha(pretty(contract)), 'generatorInterruptionProtocol': protocol(), 'statusFlags': FLAGS}
    brand = {'schema': 'V23P04C27BrandImpactManifestV1', 'schemaVersion': 1, 'cardID': CARD, 'provisional': True, 'authority': a, 'semantics': semantics, 'sourceProjection': p, 'uiAdoptionSkipped': True, 'uiAcceptanceCredit': False, 'statusFlags': FLAGS}
    manifest = {'schema': 'V23P04C27ToolingManifestV1', 'schemaVersion': 1, 'cardID': CARD, 'provisional': True, 'finalHashesSealed': FINAL_HASHES_SEALED, 'authority': a, 'pathFence': list(PATH_FENCE), 'files': [{'path': path, 'sha256': sha(pretty(value))} for path, value in ((CONTRACT, contract), (EVIDENCE, evidence), (BRAND, brand))], 'sources': source_rows, 'counts': c, 'toolingPaths': [*SCRIPTS, CONTRACT, EVIDENCE, BRAND, MANIFEST], 'statusFlags': FLAGS}
    return {CONTRACT: contract, EVIDENCE: evidence, BRAND: brand, MANIFEST: manifest}
