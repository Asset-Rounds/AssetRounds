#!/usr/bin/env bash
set -euo pipefail
# H411 shared modes preserve the legacy independent AX assembler below.
case "${1:-}" in
  --collect-shared-segment|--admit-shared-selection|--assemble-shared)
    shared_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
    python3 - "$shared_repo_root" "$@" <<'S10_4_SHARED_SEGMENT_PY'
"""Embedded H411 segment implementation; this file is development-only.

The shipping source is embedded verbatim in s10-4-segment-assembler.sh.
No test fixture is a native result or acceptance artifact.
"""
import datetime as dt
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import unicodedata
import zipfile
import zlib

REPOSITORY = 'Asset-Rounds/AssetRounds'
REF = 'refs/heads/phase/s10-brand-refresh'
UI_ID = 'S10_4AutomatedBrandLabUITests/testAutomatedBrandLabShard'
TOOLCHAIN = {'xcodeVersion':'Xcode 26.6','xcodeBuild':'17F113','sdkName':'iphonesimulator26.5','sdkBuild':'23F81a','architecture':'arm64','project':'FieldEvidenceApp.xcodeproj','scheme':'FieldEvidenceApp','configuration':'Debug'}
MAX_JSON = 64 * 1024 * 1024
MAX_ZIP = 2 * 1024 * 1024 * 1024
MAX_EXPANDED = 8 * 1024 * 1024 * 1024
MAX_MEMBERS = 50000
CONTRACT = 's10.4-shared-segment-matrix-v1'

class Rejected(ValueError): pass
def require(ok, message):
    if not ok: raise Rejected(message)
def digest(raw): return hashlib.sha256(raw).hexdigest().upper()
def canonical(value): return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('utf-8')
def identity(value): return digest(canonical(value))
def strict_pairs(pairs):
    result={}
    for k,v in pairs:
        require(k not in result, 'duplicate JSON key')
        result[k]=v
    return result
def decode(raw):
    require(len(raw)<=MAX_JSON,'oversized JSON')
    return json.loads(raw,object_pairs_hook=strict_pairs,parse_constant=lambda x: (_ for _ in ()).throw(Rejected('nonfinite JSON')))
def load(path):
    require(path.is_file() and not path.is_symlink(),'missing/unsafe JSON: '+path.name)
    return decode(path.read_bytes())
def save(path,value):
    require(not path.exists() and not path.is_symlink(),'refuse evidence overwrite: '+path.name)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(canonical(value)+b'\n')
def sha(path):
    require(path.is_file() and not path.is_symlink(),'missing/unsafe file: '+path.name)
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024),b''): h.update(chunk)
    return h.hexdigest().upper()
def positive(value):
    require(type(value) is str and re.fullmatch(r'[1-9][0-9]{0,19}',value) and int(value)<2**64,'noncanonical positive ID')
    return value
def hash_value(value):
    require(type(value) is str and re.fullmatch('[0-9A-F]{64}',value),'invalid uppercase SHA256')
    return value
def safe_relative(value):
    require(type(value) is str and value and '\\' not in value and ':' not in value and '\x00' not in value,'unsafe relative path')
    path=PurePosixPath(value)
    require(not path.is_absolute() and value==path.as_posix() and all(p not in ('','..','.') for p in value.split('/')),'unsafe relative path')
    return value
def files(root):
    require(root.is_dir() and not root.is_symlink(),'missing/unsafe directory')
    output={}; folded=set()
    for directory,dirs,names in os.walk(root,followlinks=False):
        for name in dirs+names:
            path=Path(directory)/name
            rel=path.relative_to(root).as_posix(); safe_relative(rel)
            require(rel.casefold() not in folded,'case-colliding tree path'); folded.add(rel.casefold())
            mode=path.lstat().st_mode
            require(stat.S_ISREG(mode) or stat.S_ISDIR(mode),'nonregular tree member')
            if stat.S_ISREG(mode): output[rel]=path
    return output
def checksum_rows(root):
    return {name:sha(path) for name,path in files(root).items() if name!='SHA256SUMS.txt'}
def check_checksums(root):
    rows={}
    for line in (root/'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        match=re.fullmatch(r'([0-9A-Fa-f]{64})  (.+)',line)
        require(match is not None,'malformed checksum row')
        name=safe_relative(match[2]); require(name not in rows,'duplicate checksum member')
        rows[name]=match[1].upper()
    require(rows==checksum_rows(root),'incomplete original checksum closure')
def write_checksums(root):
    require(not (root/'SHA256SUMS.txt').exists(),'checksum overwrite')
    rows=checksum_rows(root)
    (root/'SHA256SUMS.txt').write_text(''.join(rows[n]+'  '+n+'\n' for n in sorted(rows)),encoding='utf-8',newline='\n')
def directory_digest(root):
    rows=files(root); require(rows,'empty native result bundle')
    return digest(''.join(sha(rows[n])+'  '+n+'\n' for n in sorted(rows)).encode())
def utc(value):
    require(type(value) is str and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z',value),'invalid UTC metadata')
    return dt.datetime.strptime(value,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=dt.timezone.utc)
def fresh_output(path):
    require(path.is_absolute() and not path.exists() and path.parent.is_dir() and path.parent.resolve()==path.parent,'output must be new, absolute and canonical')
    return Path(tempfile.mkdtemp(prefix=path.name+'.pending-',dir=path.parent))
def publish(stage,destination):
    require(not destination.exists(),'destination appeared during assembly')
    os.replace(stage,destination)

def plan_context(root,shard_id,allow_full=False):
    plan=load(root/'Scripts/s10-4-segment-plan.json')
    shards=load(root/'Scripts/s10-4-shards.json')
    shared=plan['sharedVerification']; minimum=plan['minimumVerification']
    require(shared['contractID']==CONTRACT and shared['schemaVersion']==1,'wrong shared plan')
    require(allow_full or shard_id in shared['allowedShardIDs'],'unapproved segmented shard')
    matching=[s for s in shards['shards'] if s['shardID']==shard_id]
    require(len(matching)==1,'ambiguous shard'); shard=matching[0]
    is_min=shard['ordinal']>=8
    require(allow_full or is_min or shard_id=='s10.4.current.ax-text','current segment scope')
    require(minimum['profiles']==shards['shards'][7:] and len(minimum['profiles'])==7,'minimum tuple drift')
    device=[d for d in shards['deviceProfiles'] if d['deviceProfileID']==shard['deviceProfileID']]
    require(len(device)==1,'ambiguous device'); device=device[0]
    segments=minimum['segments'] if is_min else plan['segments']
    states=plan['orderedStateIDs']
    require(len(states)==67 and len(set(states))==67,'frozen state identity count')
    require([s['ordinal'] for s in segments]==[1,2,3] and [s['stateCount'] for s in segments]==[22,28,17] and [s['replayCount'] for s in segments]==[0,22,22],'segment partition drift')
    require([x for s in segments for x in s['ownedStateIDs']]==states,'missing/duplicate/reordered owned state')
    for s in segments:
        require(s['ownedStateIDs']==states[s['startOrdinal']-1:s['endOrdinal']] and len(s['ownedStateIDs'])==s['stateCount'],'owned slice mismatch')
        require(s['replayStateIDs']==states[:s['replayCount']],'replay slice mismatch')
        for key in ['owned','replay']:
            require(s[key+'StateSHA256']==digest('\n'.join(s[key+'StateIDs']).encode()),'state hash mismatch')
    require(segments[2]['dependencySegmentIDs']==[s['segmentID'] for s in segments[:2]] and segments[2]['dependencyOwnedStateIDs']==states[:50],'dependency contract mismatch')
    require(minimum['exceptionAuthorities']==[],'minimum exception spread')
    return {'plan':plan,'shard':shard,'device':device,'segments':segments,'minimum':is_min,'root':root}

def physical_source(root):
    require(os.environ.get('GITHUB_REPOSITORY')==REPOSITORY and os.environ.get('GITHUB_REF')==REF,'repository/ref environment mismatch')
    head=os.environ.get('GITHUB_SHA',''); require(re.fullmatch('[0-9a-f]{40}',head),'invalid source head')
    actual=subprocess.run(['git','rev-parse','HEAD'],cwd=root,text=True,capture_output=True,check=True).stdout.strip()
    require(actual==head,'physical checkout head mismatch')
    require(subprocess.run(['git','diff','--quiet',head,'--'],cwd=root).returncode==0,'tracked source differs from head')
    return head
def producer_binding(admission_root):
    admission=load(admission_root/'admission.json')
    seal=load(admission_root/'shared-build-seal.json')
    # Both hashes are content identities, never caller-selected substitutions.
    shared=hash_value(admission['sharedBuildIdentitySHA256'])
    qualification=hash_value(admission['producerQualificationSHA256'])
    require(identity(seal['sharedBuildIdentity'])==shared,'producer seal content identity mismatch')
    require(seal['producerQualificationSHA256']==qualification,'producer qualification binding mismatch')
    return shared,qualification
def new_matrix(ctx,head,admission_root):
    shared,qualification=producer_binding(admission_root)
    root=ctx['root']; plan=ctx['plan']; shard=ctx['shard']
    fields={'schemaVersion':1,'contractID':CONTRACT,'repository':REPOSITORY,'ref':REF,'productHead':head,
      'shardID':shard['shardID'],'requirementID':shard['requirementID'],'deviceProfileID':shard['deviceProfileID'],
      'environment':shard['environment'],'device':ctx['device'],'toolchain':TOOLCHAIN,
      'segmentPlanSHA256':sha(root/'Scripts/s10-4-segment-plan.json'),
      'selectorSHA256':sha(root/'Scripts/ci-selection.json'),'shardContractSHA256':sha(root/'Scripts/s10-4-shards.json'),
      'inventorySHA256':sha(root/'docs/design/s10/s10-screen-state-inventory.json'),
      'commonTaskSchemaSHA256':sha(root/'docs/design/s10/s10-accessibility-common-tasks.json'),
      'uiSourceSHA256':sha(root/'FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift'),
      'unitSourceSHA256':sha(root/'FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift'),
      'sharedBuildIdentitySHA256':shared,'producerQualificationSHA256':qualification}
    fields['evidenceKernelSHA256']=identity({k:v for k,v in fields.items() if k not in ['schemaVersion','contractID']})
    fields['matrixID']=identity(fields); fields['selectedConsumers']=[]
    return fields
def verify_matrix(matrix,ctx):
    require(type(matrix) is dict and matrix.get('schemaVersion')==1 and matrix.get('contractID')==CONTRACT,'wrong matrix schema')
    immutable={k:v for k,v in matrix.items() if k not in ['matrixID','selectedConsumers']}
    require(identity(immutable)==matrix.get('matrixID'),'matrix identity mismatch')
    shard=ctx['shard']; root=ctx['root']
    for k in ['shardID','requirementID','deviceProfileID','environment']: require(matrix.get(k)==shard[k],'matrix profile mismatch: '+k)
    require(matrix.get('repository')==REPOSITORY and matrix.get('ref')==REF and matrix.get('toolchain')==TOOLCHAIN and matrix.get('device')==ctx['device'],'matrix route/environment mismatch')
    for k,p in [('segmentPlanSHA256','Scripts/s10-4-segment-plan.json'),('selectorSHA256','Scripts/ci-selection.json'),('shardContractSHA256','Scripts/s10-4-shards.json'),('inventorySHA256','docs/design/s10/s10-screen-state-inventory.json'),('commonTaskSchemaSHA256','docs/design/s10/s10-accessibility-common-tasks.json'),('uiSourceSHA256','FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift'),('unitSourceSHA256','FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift')]:
        require(matrix.get(k)==sha(root/p),'matrix source mismatch: '+k)
    require(re.fullmatch('[0-9a-f]{40}',matrix.get('productHead','')),'matrix head invalid')
    for k in ['sharedBuildIdentitySHA256','producerQualificationSHA256','evidenceKernelSHA256']: hash_value(matrix[k])
    expected_kernel={k:v for k,v in immutable.items() if k not in ['schemaVersion','contractID','evidenceKernelSHA256']}
    require(identity(expected_kernel)==matrix['evidenceKernelSHA256'],'matrix kernel mismatch')
    require(type(matrix.get('selectedConsumers')) is list,'matrix source selection invalid')
    return matrix

def json_lines(lines,prefix): return [decode(line[len(prefix)+1:].encode()) for line in lines if line.startswith(prefix+' ')]

def minimum_semantic_label(observed,release,ctx):
    """The finite minimumSemanticLabel predicate in the bound UI source.

    Accent canonical decomposition removes Unicode mark categories, matching
    CharacterSet.nonBaseCharacters for the release ASCII strings used here.
    No case folding, whitespace repair, punctuation or non-mark removal occurs.
    """
    require(type(observed) is str and type(release) is str,'proof label must be text')
    locale=ctx['shard']['environment']['locale']
    if locale in ['en-US-release','ar-RTL']: return observed==release
    if locale=='en-US-double-length': return observed==release+' '+release
    if locale=='ar-RTL-string': return observed=='\u202e'+release+'\u202c'
    if locale=='en-US-bounded': return observed=='[# '+release+' #]'
    if locale=='en-US-tall':
        marker='\u0921\u094d\u0921\u0942\u0e01\u0e36\u0e4a'
        return observed==marker+(' '+marker+' ').join(release.split(' '))+marker
    if locale=='en-US-accented':
        return ''.join(c for c in unicodedata.normalize('NFD',observed) if not unicodedata.category(c).startswith('M'))==release
    raise Rejected('unknown minimum proof locale')

def minimum_proofs(events,ctx,segment):
    purchases=[r for kind,r in events if kind=='PURCHASE_PROOF']
    receipts=[r for kind,r in events if kind=='PENDING_RECEIPT_PROOF']
    expected=segment['nativeProofs']; ordinal=segment['ordinal']
    # Segment3 calls the same returned purchase guard inside the no-baseline
    # purchase and again in its caller. Two observations are not two purchases.
    require(expected=={'purchaseProofCount':[0,1,2][ordinal-1],
                       'pendingReceiptProofCount':[0,1,1][ordinal-1],
                       'setupOnly':ordinal==3},'minimum proof plan drift')
    require(len(purchases)==expected['purchaseProofCount'] and len(receipts)==expected['pendingReceiptProofCount'],'missing/duplicate native purchase or pending-receipt proof')
    purchase_release='Complete: Purchase verified. Subscription access is ready.'
    for row in purchases:
        require(row.get('completed') is True and row.get('setupOnly') is expected['setupOnly'],'purchase proof ownership/completion mismatch')
        require(row.get('identifier')=='s7.2.paywall.purchase-state' and row.get('semanticReleaseLabel')==purchase_release,'purchase proof source identity mismatch')
        require(minimum_semantic_label(row.get('actualLabel'),purchase_release,ctx),'purchase proof localized semantic label mismatch')
    for row in receipts:
        require(row.get('completed') is True and row.get('setupOnly') is expected['setupOnly'],'pending receipt proof ownership/completion mismatch')
        for key,value in [('savedCount',1),('preparingCount',1),('viewReportCount',0)]: require(type(row.get(key)) is int and row[key]==value,'pending receipt count mismatch: '+key)
        require(minimum_semantic_label(row.get('actualLabel'),'Report saved on this device.',ctx),'pending receipt localized semantic label mismatch')
    def positions(kind,key=None,value=None):
        return [i for i,(k,r) in enumerate(events) if k==kind and (key is None or r.get(key)==value)]
    def one(kind,key,value):
        found=positions(kind,key,value); require(len(found)==1,'native proof witness missing/duplicated'); return found[0]
    if ordinal==2:
        require(one('JOURNEY','journeyID','work-confirmed-recheck-saved')
                <positions('PURCHASE_PROOF')[0]
                <one('JOURNEY','journeyID','evaluation-blocked-purchase-close-continuation')
                <positions('PENDING_RECEIPT_PROOF')[0]
                <one('JOURNEY','journeyID','alternative-recheck-issue-relationships'),
                'owned purchase/receipt proofs are outside their native journeys')
    elif ordinal==3:
        p=positions('PURCHASE_PROOF')
        require(one('SETUP_WITNESS','witnessID','work-recheck-due')<p[0]<p[1]
                <one('SETUP_WITNESS','witnessID','settings-purchase-entitlement')
                <positions('PENDING_RECEIPT_PROOF')[0]
                <one('SETUP_WITNESS','witnessID','confirmed-different-recheck-pending-receipt')
                <one('SETUP_WITNESS','witnessID','persisted-pdf-failure')
                <one('RESUME_SETUP','setupID','minimum-report-pdf-failed-v1'),
                'setup purchase/receipt proofs are outside their native prerequisite sequence')
    return purchases,receipts

def ui_rows(log,ctx,segment,matrix):
    require(log.stat().st_size<128*1024*1024,'oversized UI log')
    lines=log.read_text(encoding='utf-8',errors='strict').splitlines()
    require(lines.count('** TEST EXECUTE SUCCEEDED **')==1,'native UI log lacks unique success')
    require(not any(re.search(r'^S10_4_[A-Z0-9_]*DIAGNOSTIC|^S10_4_AX |^S10_4_FRONTIER_REPLAY ',l) or re.search(r'Lost connection to testmanagerd|XCTHTestOperationCoordinatorErrorDomain',l,re.I) for l in lines),'diagnostic/partial/transport evidence cannot accept')
    require(not any(l.startswith('S10_4_SHARD ') for l in lines),'partial segment emitted full-shard result')
    owned=segment['ownedStateIDs']; replay=segment['replayStateIDs']; shard=ctx['shard']
    markers=[l.removeprefix('S10_MIGRATION_STATE state=') for l in lines if l.startswith('S10_MIGRATION_STATE state=')]
    require(markers==owned,'owned marker order mismatch')
    ax=json_lines(lines,'S10_4_AX_STATE'); contrast=json_lines(lines,'S10_4_CONTRAST')
    require([r.get('stateID') for r in ax]==owned and [r.get('stateID') for r in contrast]==owned,'owned AX/contrast closure mismatch')
    prefix='S10_4_MINIMUM_SEGMENT_' if ctx['minimum'] else 'S10_4_SEGMENT_'
    replays=json_lines(lines,prefix+'REPLAY'); resumes=json_lines(lines,prefix+'RESUME_SETUP')
    require([r.get('stateID') for r in replays]==replay and [r.get('ordinal') for r in replays]==list(range(1,len(replay)+1)),'replay evidence mismatch')
    for r in replays: require(r.get('shardID')==shard['shardID'] and r.get('segmentID')==segment['segmentID'],'replay profile mismatch')
    require(len(resumes)==(1 if segment['ordinal']==3 else 0),'resume cardinality mismatch')
    journeys=[]; witnesses=[]; starts=[]; results=[]; purchases=[]; pending_receipts=[]
    if ctx['minimum']:
        require(not any(l.startswith('S10_4_SEGMENT_') for l in lines),'mixed AX/minimum mode')
        minimum_kinds=[l.split(' ',1)[0][len(prefix):] for l in lines if l.startswith(prefix)]
        require(minimum_kinds and minimum_kinds[0]=='START' and minimum_kinds[-1]=='RESULT' and set(minimum_kinds)<= {'START','REPLAY','JOURNEY','SETUP_WITNESS','RESUME_SETUP','RESULT','PURCHASE_PROOF','PENDING_RECEIPT_PROOF'},'unknown/out-of-order minimum row kind')
        events=[(l.split(' ',1)[0][len(prefix):],decode(l.split(' ',1)[1].encode())) for l in lines if l.startswith(prefix)]
        starts=json_lines(lines,prefix+'START'); results=json_lines(lines,prefix+'RESULT')
        journeys=json_lines(lines,prefix+'JOURNEY'); witnesses=json_lines(lines,prefix+'SETUP_WITNESS')
        require(len(starts)==len(results)==1,'minimum missing/duplicate start/result')
        allrows=[r for kind,r in events if kind!='RESUME_SETUP']
        times=[]
        for row in allrows:
            for key in ['shardID','requirementID','deviceProfileID']: require(row.get(key)==shard[key],'minimum row profile mismatch')
            require(row.get('schemaVersion')==1 and row.get('acceptanceEligible') is False and row.get('segmentID')==segment['segmentID'] and row.get('head')==matrix['productHead'] and row.get('ref')==REF,'minimum row provenance mismatch')
            for key,value in [('ownedStartOrdinal',segment['startOrdinal']),('ownedCount',segment['stateCount']),('finalOrdinal',segment['endOrdinal']),('replayCount',segment['replayCount'])]: require(row.get(key)==value,'minimum row partition mismatch')
            t=row.get('elapsedSeconds'); require(type(t) in (float,int) and math.isfinite(t) and t>=0,'invalid native elapsed time'); times.append(t)
        require(times==sorted(times),'native segment elapsed order mismatch')
        require(all(r.get('setupOnly') is True for r in replays),'replay not marked setup')
        owned_journeys=[r for r in journeys if r.get('setupOnly') is False]
        setup_journeys=[r for r in journeys if r.get('setupOnly') is True]
        require(len(owned_journeys)+len(setup_journeys)==len(journeys),'journey setup classification missing')
        expected_setup=ctx['plan']['minimumVerification']['segments'][0]['journeyIDs'] if segment['ordinal']>1 else []
        require([r.get('journeyID') for r in owned_journeys]==segment['journeyIDs'] and [r.get('journeyID') for r in setup_journeys]==expected_setup,'native journey ownership/order mismatch')
        contracts={x['journeyID']:x for x in ctx['plan']['minimumVerification']['journeys']}
        for rows in [owned_journeys,setup_journeys]:
            for i,row in enumerate(rows,1):
                contract=contracts[row['journeyID']]
                require(row.get('completed') is True and row.get('sequence')==i,'native journey did not complete')
                for k in ['entryStateID','exitStateID','assertionIDs']: require(row.get(k)==contract[k],'native journey assertion contract mismatch')
        expected_witness=ctx['plan']['minimumVerification']['setupWitnessIDs'] if segment['ordinal']==3 else []
        require([r.get('witnessID') for r in witnesses]==expected_witness,'resume witness sequence mismatch')
        for i,row in enumerate(witnesses,1): require(row.get('sequence')==i and row.get('setupOnly') is True and row.get('completed') is True,'resume witness incomplete')
        result=results[0]
        omitted=ctx['plan']['orderedStateIDs'][22:50] if segment['ordinal']==3 else []
        require(result.get('result')=='PASS' and result.get('ownedStateIDs')==owned and result.get('replayedStateIDs')==replay and result.get('omittedHistoricalStateIDs')==omitted and result.get('completedJourneyWitnessIDs')==segment['journeyIDs'] and result.get('completedSetupWitnessIDs')==expected_witness,'minimum result closure mismatch')
        if resumes:
            row=resumes[0]
            expected=dict(segment['resumeSetup']); expected.pop('rowCount'); expected['localReplayCount']=22
            for k,value in expected.items(): require(row.get(k)==value,'minimum resume frontier/precondition mismatch: '+k)
            for k in ['shardID','requirementID','deviceProfileID']: require(row.get(k)==shard[k],'minimum resume profile mismatch')
            require(row.get('setupOnly') is True and row.get('acceptanceEligible') is False and row.get('head')==matrix['productHead'] and row.get('ref')==REF and row.get('segmentID')==segment['segmentID'],'minimum resume binding mismatch')
            for k in ['resolvedActionActualLabel','reportFailureHeadlineActualLabel','reportFailureRetryActualLabel']: require(type(row.get(k)) is str and row[k],'missing actual semantic label')
        purchases,pending_receipts=minimum_proofs(events,ctx,segment)
    else:
        require(not any(l.startswith('S10_4_MINIMUM_SEGMENT_') for l in lines),'mixed minimum/AX mode')
        if resumes:
            s=segment['resumeSetup']
            expected={'schemaVersion':1,'acceptanceEligible':False,'shardID':shard['shardID'],'segmentID':segment['segmentID'],**{k:v for k,v in s.items() if k!='rowCount'}}
            require(resumes[0]==expected,'AX resume exact contract mismatch')
    return {'ax':ax,'contrast':contrast,'replay':replays,'resume':resumes,'journeys':journeys,'witnesses':witnesses,'start':starts,'result':results,'purchaseProofs':purchases,'pendingReceiptProofs':pending_receipts}

def verify_state_rows(rows,ctx):
    shard=ctx['shard']; signatures=ctx['plan']['sharedVerification']['axExceptionSignatures']
    authorities=ctx['plan']['exceptionAuthorities'] if not ctx['minimum'] else []
    for ax,contrast in zip(rows['ax'],rows['contrast']):
        state=ax['stateID']
        for row in [ax,contrast]:
            for key in ['shardID','requirementID','deviceProfileID']: require(row.get(key)==shard[key],'state profile mismatch')
            hash_value(row.get('axTreeSHA256'))
        require(ax.get('result')=='PASS' and ax.get('capture')=='XCUIApplication.debugDescription' and ax.get('evidenceID')=='s10.4-ax-'+shard['shardID']+'-'+state,'AX row invalid')
        require(contrast.get('axTreeSHA256')==ax['axTreeSHA256'] and contrast.get('audit')=='XCUIAccessibilityAuditType.contrast' and contrast.get('evidenceID')=='s10.4-contrast-'+shard['shardID']+'-'+state,'contrast binding mismatch')
        if contrast.get('result')=='PASS':
            require(all(contrast.get(k)=='' for k in ['exceptionIssueID','exceptionOwner','exceptionExpiresAt','exceptionRationale']) and contrast.get('ignoredAuditIssues')==[],'PASS carries hidden exception')
        else:
            require(not ctx['minimum'] and contrast.get('result')=='EXCEPTION','unapproved contrast exception')
            eligible=sorted([a for a in signatures if a['stateID']==state],key=lambda a:a['exceptionIssueID'])
            require(eligible and contrast.get('ignoredAuditIssues')==[a['ignoredAuditIssues'][0] for a in eligible],'AX exact public exception signature mismatch')
            require(contrast.get('exceptionIssueID')==' | '.join(a['exceptionIssueID'] for a in eligible) and contrast.get('exceptionOwner')=='palatis3' and contrast.get('exceptionExpiresAt')==eligible[0]['exceptionExpiresAt'] and dt.datetime.now(dt.timezone.utc).date().isoformat()<=eligible[0]['exceptionExpiresAt'],'AX exception authority/expiry mismatch')
            require(contrast.get('exceptionRationale')==' | '.join(a['exceptionRationale'] for a in eligible),'AX exception rationale mismatch')
            require({a['exceptionIssueID'] for a in eligible}=={a['exceptionIssueID'] for a in authorities if a['stateID']==state},'AX exception plan identity mismatch')

def native_ui(root,consumer,ctx):
    tree=load(root/'ui-test-results.json'); executed=load(root/'ui-executed-tests.json'); cases=[]
    def walk(node):
        require(type(node) is dict,'native tree malformed')
        if node.get('nodeType')=='Test Case': cases.append(node)
        for child in node.get('children',[]): walk(child)
    for node in tree.get('testNodes',[]): walk(node)
    require(len(cases)==1 and cases[0].get('nodeIdentifier','').removesuffix('()')==UI_ID and cases[0].get('result')=='Passed','native UI missing/duplicate/failed/unexpected method')
    require(type(executed) is list and len(executed)==1 and executed[0].get('identifier','').removesuffix('()') in [UI_ID,'FieldEvidenceAppUITests/'+UI_ID] and executed[0].get('result')=='Passed','native executed UI mismatch')
    devices=tree.get('devices'); require(type(devices) is list and len(devices)==1,'native device cardinality')
    expected={'deviceId':consumer['simulatorUDID'],'deviceName':ctx['device']['simulatorName'],'osVersion':ctx['device']['simulatorRuntime'].removeprefix('iOS '),'osBuildNumber':ctx['device']['simulatorRuntimeBuild'],'architecture':'arm64','platform':'iOS Simulator'}
    require(all(devices[0].get(k)==v for k,v in expected.items()),'native consumer runtime/device mismatch')
    return directory_digest(root/'UISmoke.xcresult')

def png(path,minimum):
    raw=path.read_bytes(); require(raw.startswith(b'\x89PNG\r\n\x1a\n'),'not PNG')
    offset=8; kinds=[]; dimensions=None; compressed=[]; header=None
    while offset<len(raw):
        require(offset+12<=len(raw),'truncated PNG')
        size=struct.unpack('>I',raw[offset:offset+4])[0]; kind=raw[offset+4:offset+8]
        require(offset+12+size<=len(raw),'truncated PNG chunk')
        value=raw[offset+8:offset+8+size]; crc=struct.unpack('>I',raw[offset+8+size:offset+12+size])[0]
        require(zlib.crc32(kind+value)&0xffffffff==crc,'PNG CRC failure'); kinds.append(kind)
        if kind==b'IHDR':
            require(dimensions is None and len(value)==13,'PNG IHDR invalid'); header=struct.unpack('>IIBBBBB',value); dimensions=header[:2]
        if kind==b'IDAT': compressed.append(value)
        offset+=12+size
        if kind==b'IEND': break
    require(kinds and kinds[0]==b'IHDR' and kinds[-1]==b'IEND' and kinds.count(b'IEND')==1 and b'IDAT' in kinds and offset==len(raw),'PNG incomplete or trailing data')
    require(dimensions==((750,1334) if minimum else (1206,2622)),'PNG device dimensions mismatch')
    width,height,depth,colour,compression,filter_method,interlace=header
    allowed={0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]}
    require(colour in allowed and depth in allowed[colour] and compression==filter_method==0 and interlace in [0,1],'PNG encoding invalid')
    channels={0:1,2:3,3:1,4:2,6:4}[colour]
    passes=[(0,0,1,1)] if interlace==0 else [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
    scanlines=[]
    for x,y,dx,dy in passes:
        w=max(0,(width-x+dx-1)//dx); h=max(0,(height-y+dy-1)//dy)
        if w and h: scanlines.extend([1+(w*channels*depth+7)//8]*h)
    expected=sum(scanlines); require(expected<=64*1024*1024,'PNG decoded byte bound')
    decoder=zlib.decompressobj(); pixels=decoder.decompress(b''.join(compressed),expected+1)
    require(len(pixels)==expected and decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,'PNG pixel stream truncated/oversized/trailing')
    cursor=0
    for size in scanlines: require(pixels[cursor]<=4,'PNG filter invalid'); cursor+=size
    return {'sha256':digest(raw),'bytes':len(raw),'width':dimensions[0],'height':dimensions[1]}

def attachment_rows(attachment_root,ctx,segment):
    manifest=load(attachment_root/'manifest.json'); allrows=[]
    require(type(manifest) is list and manifest,'missing attachment manifest')
    for test in manifest:
        require(type(test) is dict and test.get('testIdentifier','').removesuffix('()')==UI_ID and type(test.get('attachments')) is list,'foreign attachment test')
        allrows+=test['attachments']
    require(len(allrows)==segment['stateCount']+1,'attachment cardinality mismatch')
    prefix='S10.4 candidate '+ctx['shard']['shardID']+' '
    terminal=('S10.4 minimum segment terminal '+segment['segmentID']) if ctx['minimum'] else ('S10.4 segment terminal '+segment['segmentID']+' s10.4.current.ax-text')
    candidates=[]; terminal_rows=[]; seen=set()
    for row in allrows:
        require(row.get('isAssociatedWithFailure') is False,'failure attachment in accepting segment')
        name=row.get('suggestedHumanReadableName','')
        name=re.sub(r'_0_[0-9A-Fa-f-]{36}\.', '.',name)
        filename=row.get('exportedFileName','')
        require(re.fullmatch('[A-Za-z0-9._-]+',filename) and filename not in seen,'unsafe/duplicate attachment file'); seen.add(filename)
        path=attachment_root/filename; require(path.is_file() and not path.is_symlink(),'missing/unsafe original attachment')
        info=png(path,ctx['minimum'])
        if name.startswith(prefix):
            state=name[len(prefix):]; require(state in segment['ownedStateIDs'],'foreign candidate state')
            candidates.append({'stateID':state,'exportedFileName':filename,'artifactPath':'candidates/'+state+'.png',**info})
        else:
            require(name==terminal,'unexpected diagnostic/terminal attachment'); terminal_rows.append(row)
    require(len(terminal_rows)==1 and len({r['stateID'] for r in candidates})==segment['stateCount'],'duplicate/missing candidate or terminal')
    candidates.sort(key=lambda r:segment['ownedStateIDs'].index(r['stateID']))
    return manifest,candidates

def build_reference(path,matrix,ctx,segment):
    reference=load(path)
    for k in ['sharedBuildIdentitySHA256','producerQualificationSHA256']: require(reference.get(k)==matrix[k],'consumer producer identity mismatch')
    require(reference.get('unitTestCount')==0 and reference.get('producerUnitTestCount')==5,'consumer falsely claims local units')
    consumer=reference['consumer']
    for key in ['runID','runAttempt','jobID']: require(type(consumer.get(key)) is int and 0<consumer[key]<2**64,'invalid consumer numeric API ID')
    require(consumer.get('purpose')=='acceptance' and consumer.get('runnerProvider')=='github' and consumer.get('toolchain')==TOOLCHAIN and consumer.get('shardID')==ctx['shard']['shardID'] and consumer.get('segmentID')==segment['segmentID'],'consumer tuple invalid')
    for k in ['simulatorName','simulatorRuntime','simulatorRuntimeBuild']: require(consumer.get(k)==ctx['device'][k],'consumer device mismatch')
    for k in ['simulatorUDID','isolationID']: require(re.fullmatch('[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}',consumer.get(k,'')),'invalid consumer isolation')
    require(reference.get('schemaVersion')==1 and reference.get('contractID')=='s10.4.shared-build.v1' and reference.get('recordType')=='consumer-build-reference' and reference.get('source',{}).get('head')==matrix['productHead'] and reference.get('diagnosticOnly') is False and reference.get('productsUnchanged') is True,'consumer source/execution contract mismatch')
    source_files=reference['source'].get('files',{})
    require(source_files.get('FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift')==matrix['uiSourceSHA256'] and source_files.get('FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift')==matrix['unitSourceSHA256'],'consumer UI/unit source mismatch')
    command=reference.get('uiCommand',[])
    require(type(command) is list and command.count('test-without-building')==1 and not any(x in command for x in ['build','build-for-testing','test']) and command.count('-xctestrun')==1 and reference.get('xctestrunPath')==command[command.index('-xctestrun')+1] and command.count('-only-testing:FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests')==1 and sum(x.startswith('-only-testing:') for x in command)==1 and not any(x.startswith('-skip-testing') for x in command),'consumer native command mismatch')
    require(command.count('-destination')==1 and command[command.index('-destination')+1]=='platform=iOS Simulator,id='+consumer['simulatorUDID'],'consumer command changed native destination')
    if 'producerQualification' in ctx:
        require(reference.get('products')==ctx['producerQualification']['products'] and reference.get('source')==ctx['producerQualification']['source'],'consumer reference differs from original producer qualification')
    if 'producerSeal' in ctx:
        require(reference.get('originalUnitArtifact')==ctx['producerSeal']['unitArtifact'],'consumer original unit artifact differs from authenticated producer')
    return reference,consumer

def collect(root,artifact_root,attachment_root,shard_id,segment_id,matrix_path):
    ctx=plan_context(root,shard_id); matrix=verify_matrix(load(matrix_path),ctx)
    require(physical_source(root)==matrix['productHead'],'collector head mismatch')
    found=[s for s in ctx['segments'] if s['segmentID']==segment_id]; require(len(found)==1,'invalid segment'); segment=found[0]
    module=payload_module(root)
    proof=module.qualification(Path(os.environ['CI_S10_4_PRODUCER_PROOF_ROOT']),module.source_identity(root,matrix['productHead']))
    require(identity(proof)==matrix['producerQualificationSHA256'],'collector original producer qualification differs from selected matrix')
    ctx['producerQualification']=proof
    reference,consumer=build_reference(Path(os.environ['CI_S10_4_CONSUMER_BUILD_REFERENCE']),matrix,ctx,segment)
    require(str(consumer['runID'])==os.environ.get('GITHUB_RUN_ID') and str(consumer['runAttempt'])==os.environ.get('GITHUB_RUN_ATTEMPT'),'collector native run environment mismatch')
    require(not (artifact_root/'Build.xcresult').exists() and not (artifact_root/'UnitTests.xcresult').exists(),'shared consumer has falsely local build/unit bundle')
    ui_identity=native_ui(artifact_root,consumer,ctx)
    rows=ui_rows(artifact_root/'ui-smoke.log',ctx,segment,matrix); verify_state_rows(rows,ctx)
    manifest,candidates=attachment_rows(attachment_root,ctx,segment)
    if segment['ordinal']==3:
        require([x.get('segmentID') for x in matrix['selectedConsumers']]==segment['dependencySegmentIDs'],'segment3 missing admitted predecessor selection')
    else: require(matrix['selectedConsumers']==[],'unexpected consumer dependency')
    shard_root=artifact_root/'s10-4'/shard_id
    require(not shard_root.exists(),'collector would overwrite existing evidence')
    staged=Path(tempfile.mkdtemp(prefix='shared-collect-',dir=artifact_root.parent))
    published=[]
    try:
        dst=staged/'s10-4'/shard_id
        save(dst/'xcresult-attachment-manifest.json',manifest)
        save(dst/'candidate-files.json',candidates)
        save(dst/'candidate-exports.json',[{'stateID':r['stateID'],'exportedFileName':r['exportedFileName']} for r in candidates])
        save(dst/'original-attachments/manifest.json',manifest)
        for test in manifest:
            for attachment in test['attachments']:
                filename=attachment['exportedFileName']
                shutil.copyfile(attachment_root/filename,dst/'original-attachments'/filename)
        for name,key in [('state-ax.json','ax'),('contrast.json','contrast'),('replay-rows.json','replay'),('resume-setup-rows.json','resume'),('journey-rows.json','journeys'),('setup-witness-rows.json','witnesses'),('ui-start-rows.json','start'),('ui-result-rows.json','result'),('purchase-proof-rows.json','purchaseProofs'),('pending-receipt-proof-rows.json','pendingReceiptProofs')]: save(dst/name,rows[key])
        for r in candidates:
            target=dst/r['artifactPath']; target.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(attachment_root/r['exportedFileName'],target)
        for key,path in [('ax','ax'),('contrast','contrast')]:
            for row in rows[key]: save(staged/path/shard_id/(row['stateID']+'.json'),dict(row,sourceProductHead=matrix['productHead']))
        save(dst/'consumer-build-reference.json',reference); save(dst/'matrix-binding.json',matrix)
        session=digest((consumer['runnerName']+'\n'+consumer['simulatorUDID']+'\n'+str(consumer['jobID'])+'\n'+ui_identity+'\n').encode())
        receipt={'schemaVersion':2,'receiptKind':'s10.4-shared-segment-pending','complete':False,'nativeEvidenceComplete':True,'terminalAPIRequired':True,'finalAcceptanceEligible':False,
          'taskID':'S10.4','shardID':shard_id,'requirementID':ctx['shard']['requirementID'],'deviceProfileID':ctx['shard']['deviceProfileID'],
          'productHead':matrix['productHead'],'ref':REF,'matrixID':matrix['matrixID'],'segmentPlanSHA256':matrix['segmentPlanSHA256'],'evidenceKernelSHA256':matrix['evidenceKernelSHA256'],
          'sharedBuildIdentitySHA256':matrix['sharedBuildIdentitySHA256'],'producerQualificationSHA256':matrix['producerQualificationSHA256'],
          'consumer':consumer,'segment':segment,'uiIdentitySHA256':ui_identity,'sessionIdentitySHA256':session,
          'buildMode':'shared-test-without-building','crossSessionBuildReuse':True,'crossSessionTestWithoutBuilding':True,
          'localUnitExecutedTestCount':0,'producerUnitExecutedTestCount':5,'unitEvidenceOrigin':'shared-producer','uiExecutedTestCount':1,'uiTestSelectors':[UI_ID+'()'],
          'candidateCount':segment['stateCount'],'stateAXRowCount':segment['stateCount'],'contrastRowCount':segment['stateCount'],'accessibilityRowCount':0,
          'sourceDependencySelections':matrix['selectedConsumers'],'sourceDependencySelectionsSHA256':identity(matrix['selectedConsumers']),
          'consumerBuildReferenceSHA256':identity(reference),'attachmentCount':segment['stateCount']+1,'journeyCount':len([r for r in rows['journeys'] if r['setupOnly'] is False])}
        save(dst/'segment-receipt.pending.json',receipt)
        save(staged/'s10-4-shared-segment-validation.json',{'schemaVersion':1,'validated':True,'nativeUIResult':'Passed','segmentID':segment_id,'matrixID':matrix['matrixID'],'terminalAPIRequired':True})
        # Stage all new paths; no receipt is published if validation above failed.
        for name in ['s10-4','ax','contrast']:
            destination=artifact_root/name/shard_id; require(not destination.exists(),'collector target collision'); destination.parent.mkdir(parents=True,exist_ok=True)
        validation=artifact_root/'s10-4-shared-segment-validation.json'; require(not validation.exists(),'segment validation collision')
        for name in ['ax','contrast','s10-4']:
            destination=artifact_root/name/shard_id
            os.replace(staged/name/shard_id,destination); published.append(destination)
        os.replace(staged/'s10-4-shared-segment-validation.json',validation); published.append(validation)
    except BaseException:
        for path in reversed(published):
            if path.is_dir(): shutil.rmtree(path)
            elif path.is_file(): path.unlink()
        raise
    finally: shutil.rmtree(staged)
    return receipt

def payload_module(root):
    # Named H411 sibling owns authenticated API transport, safe ZIP and producer
    # qualification. No generated/untracked module is consulted by this script.
    path=root/'Scripts/s10-4-build-payload.py'
    spec=importlib.util.spec_from_file_location('s10_4_shared_payload',path)
    require(spec is not None and spec.loader is not None,'payload module unavailable')
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module

def original_producer(root,admission_root,selection,stage,head):
    module=payload_module(root)
    old=load(admission_root/'admission.json')
    require(old.get('diagnosticOnly') is False and old.get('source',{}).get('head')==head,'producer admission is diagnostic or wrong head')
    source=module.source_identity(root,head)
    directory=stage/'shared-producer'; directory.mkdir()
    request={'sourceRunID':str(old['producerRunID'])}
    seal,admission=module.admit_source(request,directory,source,selection)
    require(admission['sharedBuildIdentitySHA256']==old['sharedBuildIdentitySHA256'] and admission['producerQualificationSHA256']==old['producerQualificationSHA256'],'producer identity changed since admission')
    # One original qualification retrieval per operation, shared by all segments.
    module.download(admission['artifacts']['unit'],directory/'original-unit-evidence.zip')
    module.extract_zip(directory/'original-unit-evidence.zip',directory/'unit-proof')
    qualification=module.qualification(directory/'unit-proof',source)
    require(identity(qualification)==seal['producerQualificationSHA256'],'original five-unit qualification mismatch')
    require(qualification['products']==seal['sharedBuildIdentity']['products'] and qualification['producer']==seal['sharedBuildIdentity']['producer'] and qualification['archive']==seal['sharedBuildIdentity']['archive'],'qualification payload identity mismatch')
    return module,directory

def source_map(path,ctx,segment_id,assembly=False):
    mapping=load(path); require(type(mapping) is dict,'source map must be object')
    if assembly: expected=[s['segmentID'] for s in ctx['segments']]
    elif segment_id=='none': expected=[]
    else:
        found=[s for s in ctx['segments'] if s['segmentID']==segment_id]; require(len(found)==1,'invalid target segment')
        expected=found[0]['dependencySegmentIDs']
    require(set(mapping)==set(expected),'missing/extra source dependency key')
    for value in mapping.values(): positive(value)
    require(len(set(mapping.values()))==len(mapping),'duplicate source run selected')
    return [(key,mapping[key]) for key in expected]

def metadata_contract(run,jobs,artifact,rid,ctx,segment,matrix):
    head=matrix['productHead']; shard_id=ctx['shard']['shardID']
    require(run.get('id')==int(rid) and run.get('status')=='completed' and run.get('conclusion')=='success' and run.get('event')=='workflow_dispatch' and run.get('head_sha')==head and run.get('head_branch')==REF.removeprefix('refs/heads/') and run.get('path')=='.github/workflows/ios-ci.yml','source run not successful exact workflow/head/ref')
    require(run.get('repository',{}).get('full_name')==REPOSITORY and run.get('head_repository',{}).get('full_name')==REPOSITORY and run['repository']['id']==run['head_repository']['id'],'source repository mismatch')
    require(run.get('display_title')=='iOS CI · lane=github-xcode-26.6-shared-build-acceptance · shard='+shard_id+' · head='+head,'source run lane/profile mismatch')
    attempt=run.get('run_attempt'); require(type(attempt) is int and attempt>0,'source attempt missing')
    expected='ios-ci-shared-'+rid+'-'+str(attempt)+'-'+shard_id+'-'+segment['segmentID']
    require(artifact.get('name')==expected and artifact.get('expired') is False,'source artifact wrong/expired')
    size=artifact.get('size_in_bytes'); aid=artifact.get('id')
    require(type(size) is int and 0<size<=MAX_ZIP and type(aid) is int and aid>0,'source artifact size/ID invalid')
    require(re.fullmatch('sha256:[0-9a-fA-F]{64}',artifact.get('digest','')),'source artifact digest missing')
    now=dt.datetime.now(dt.timezone.utc); created=utc(artifact['created_at']); expires=utc(artifact['expires_at'])
    require(utc(run['created_at'])<=created<=now<expires and dt.timedelta(0)<expires-created<=dt.timedelta(days=14),'source artifact retention/expiry mismatch')
    owner=artifact.get('workflow_run',{})
    require(owner.get('id')==int(rid) and owner.get('head_sha')==head and owner.get('head_branch')==run['head_branch'] and owner.get('repository_id')==owner.get('head_repository_id')==run['repository']['id'],'source artifact API ownership mismatch')
    return {'id':aid,'name':expected,'bytes':size,'sha256':artifact['digest'][7:].upper(),'createdAtUTC':artifact['created_at'],'expiresAtUTC':artifact['expires_at']}

def revalidate_original(root,artifact_root,ctx,segment,matrix):
    check_checksums(artifact_root)
    shard_root=artifact_root/'s10-4'/ctx['shard']['shardID']
    receipt=load(shard_root/'segment-receipt.pending.json')
    require(receipt.get('schemaVersion')==2 and receipt.get('receiptKind')=='s10.4-shared-segment-pending' and receipt.get('nativeEvidenceComplete') is True and receipt.get('complete') is False and receipt.get('terminalAPIRequired') is True and receipt.get('finalAcceptanceEligible') is False,'source receipt not pending typed native segment')
    require(not (shard_root/'shard-receipt.json').exists() and not (shard_root/'segment-receipt.json').exists(),'ambiguous source acceptance claim')
    for k in ['matrixID','productHead','ref','segmentPlanSHA256','evidenceKernelSHA256','sharedBuildIdentitySHA256','producerQualificationSHA256']: require(receipt.get(k)==matrix[k],'source matrix identity mismatch: '+k)
    require(receipt.get('segment')==segment,'source segment plan mismatch')
    source_matrix=verify_matrix(load(shard_root/'matrix-binding.json'),ctx)
    require(source_matrix['matrixID']==matrix['matrixID'] and source_matrix['selectedConsumers']==receipt.get('sourceDependencySelections') and identity(source_matrix['selectedConsumers'])==receipt.get('sourceDependencySelectionsSHA256'),'source dependency selection changed')
    require(receipt.get('localUnitExecutedTestCount')==0 and receipt.get('producerUnitExecutedTestCount')==5 and receipt.get('unitEvidenceOrigin')=='shared-producer' and receipt.get('uiExecutedTestCount')==1 and receipt.get('uiTestSelectors')==[UI_ID+'()'],'source native unit/UI accounting mismatch')
    require(receipt.get('buildMode')=='shared-test-without-building' and receipt.get('crossSessionBuildReuse') is True and receipt.get('crossSessionTestWithoutBuilding') is True,'source build mode mismatch')
    reference,consumer=build_reference(shard_root/'consumer-build-reference.json',matrix,ctx,segment)
    require(receipt.get('consumer')==consumer and receipt.get('consumerBuildReferenceSHA256')==identity(reference),'source consumer reference mismatch')
    require(not (artifact_root/'Build.xcresult').exists() and not (artifact_root/'UnitTests.xcresult').exists(),'source carries falsely local build/units')
    ui_identity=native_ui(artifact_root,consumer,ctx)
    require(receipt.get('uiIdentitySHA256')==ui_identity,'native UI bundle changed')
    session=digest((consumer['runnerName']+'\n'+consumer['simulatorUDID']+'\n'+str(consumer['jobID'])+'\n'+ui_identity+'\n').encode())
    require(receipt.get('sessionIdentitySHA256')==session,'source session identity mismatch')
    rows=ui_rows(artifact_root/'ui-smoke.log',ctx,segment,matrix); verify_state_rows(rows,ctx)
    for name,key in [('state-ax.json','ax'),('contrast.json','contrast'),('replay-rows.json','replay'),('resume-setup-rows.json','resume'),('journey-rows.json','journeys'),('setup-witness-rows.json','witnesses'),('ui-start-rows.json','start'),('ui-result-rows.json','result'),('purchase-proof-rows.json','purchaseProofs'),('pending-receipt-proof-rows.json','pendingReceiptProofs')]: require(load(shard_root/name)==rows[key],'retained rows differ from original UI stdout')
    candidates=load(shard_root/'candidate-files.json'); require([r.get('stateID') for r in candidates]==segment['ownedStateIDs'],'original candidate closure mismatch')
    require(set(files(shard_root/'candidates'))=={s+'.png' for s in segment['ownedStateIDs']},'extra/missing candidate file')
    for row in candidates:
        require(row.get('artifactPath')=='candidates/'+row['stateID']+'.png','candidate path mismatch')
        info=png(shard_root/row['artifactPath'],ctx['minimum'])
        require(all(row.get(k)==v for k,v in info.items()),'original candidate PNG size/digest/dimensions mismatch')
    manifest,original_candidates=attachment_rows(shard_root/'original-attachments',ctx,segment)
    require(load(shard_root/'xcresult-attachment-manifest.json')==manifest and original_candidates==candidates,'original native attachment/candidate binding mismatch')
    original_names={'manifest.json'}|{r['exportedFileName'] for t in manifest for r in t['attachments']}
    require(set(files(shard_root/'original-attachments'))==original_names,'original attachment closure mismatch')
    flattened=[r for t in manifest for r in t.get('attachments',[])]
    require(len(flattened)==segment['stateCount']+1 and all(r.get('isAssociatedWithFailure') is False for r in flattened),'original attachment closure/failure mismatch')
    require(receipt.get('attachmentCount')==len(flattened),'original attachment receipt mismatch')
    require(all(receipt.get(k)==segment['stateCount'] for k in ['candidateCount','stateAXRowCount','contrastRowCount']) and receipt.get('accessibilityRowCount')==0,'segment fabricated full-shard counts')
    for category,key in [('ax','ax'),('contrast','contrast')]:
        target=artifact_root/category/ctx['shard']['shardID']
        require(set(files(target))=={s+'.json' for s in segment['ownedStateIDs']},'raw state artifact closure mismatch')
        for row in rows[key]: require(load(target/(row['stateID']+'.json'))==dict(row,sourceProductHead=matrix['productHead']),'raw state source binding mismatch')
    return receipt,rows,candidates

def retrieve_source(module,root,stage,ctx,segment,rid,matrix):
    run=module.api('actions/runs/'+rid)
    jobs=module.list_api('actions/runs/'+rid+'/jobs','jobs')
    artifacts=module.list_api('actions/runs/'+rid+'/artifacts','artifacts')
    expected='ios-ci-shared-'+rid+'-'+str(run.get('run_attempt'))+'-'+ctx['shard']['shardID']+'-'+segment['segmentID']
    found=[a for a in artifacts if a.get('name')==expected]; require(len(found)==1,'missing/ambiguous original segment artifact')
    artifact=found[0]; binding=metadata_contract(run,jobs,artifact,rid,ctx,segment,matrix)
    directory=stage/'segment-sources'/segment['segmentID']; directory.mkdir(parents=True)
    save(directory/'run.json',run); save(directory/'jobs.json',jobs); save(directory/'artifact-metadata.json',artifact)
    module.download(binding,directory/'original.zip')
    module.extract_zip(directory/'original.zip',directory/'artifact')
    receipt,rows,candidates=revalidate_original(root,directory/'artifact',ctx,segment,matrix)
    consumer=receipt['consumer']; found=[j for j in jobs if j.get('id')==consumer['jobID']]
    require(len(found)==1,'native consumer job missing/ambiguous'); job=found[0]
    require(consumer['runID']==int(rid) and consumer['runAttempt']==run['run_attempt'] and job.get('run_id')==int(rid) and job.get('run_attempt')==run['run_attempt'] and job.get('head_sha')==matrix['productHead'] and job.get('head_branch')==run['head_branch'] and job.get('status')=='completed' and job.get('conclusion')=='success','native consumer API job not successful exact source')
    # API terminal success is mandatory even when all stdout rows look complete.
    require(job.get('runner_name')==consumer['runnerName'],'native/API runner identity mismatch')
    selection={'segmentID':segment['segmentID'],'runID':rid,'runAttempt':str(run['run_attempt']),'jobID':str(job['id']),
      'artifactID':str(binding['id']),'artifactName':binding['name'],'artifactSHA256':binding['sha256'],'artifactBytes':binding['bytes'],
      'artifactCreatedAt':binding['createdAtUTC'],'artifactExpiresAt':binding['expiresAtUTC'],
      'receiptSHA256':sha(directory/'artifact/s10-4'/ctx['shard']['shardID']/'segment-receipt.pending.json'),
      'sessionIdentitySHA256':receipt['sessionIdentitySHA256'],'matrixID':matrix['matrixID']}
    save(directory/'selected-source.json',selection)
    return {'selection':selection,'receipt':receipt,'rows':rows,'candidates':candidates,'directory':directory}

def task_artifacts(stage,ctx,rows,head):
    contract=load(ctx['root']/'docs/design/s10/s10-accessibility-common-tasks.json')
    tasks=contract['tasks']; require(len(tasks)==6 and len({t['task_id'] for t in tasks})==6,'six common tasks changed')
    shard=ctx['shard']; ax={r['stateID']:r for r in rows['ax']}; contrasts={r['stateID']:r for r in rows['contrast']}; output=[]
    require(len(shard['accessibilityFeatures'])==1,'ambiguous task feature')
    for task in tasks:
        ids=sorted(task['screen_state_ids']); require(ids and len(set(ids))==len(ids) and all(s in ax for s in ids),'missing common task native states')
        evidence=[{'stateID':s,'axTreeSHA256':ax[s]['axTreeSHA256']} for s in ids]
        exceptional=[contrasts[s] for s in ids if contrasts[s]['result']=='EXCEPTION']
        taskid=task['task_id']; prefix='s10.4-'; sid=shard['shardID']
        record={'taskID':taskid,'shardID':sid,'deviceProfileID':shard['deviceProfileID'],'feature':shard['accessibilityFeatures'][0],
          'automatedStatus':'EXCEPTION' if exceptional else 'PASS','automatedReviewer':'FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests',
          'exceptionIssueID':' | '.join(r['exceptionIssueID'] for r in exceptional),'exceptionOwner':'palatis3' if exceptional else '',
          'exceptionExpiresAt':exceptional[0]['exceptionExpiresAt'] if exceptional else '',
          'exceptionRationale':' | '.join(r['exceptionRationale'] for r in exceptional),'exceptionStateIDs':sorted(r['stateID'] for r in exceptional),
          'rationale':'Exact native task-state AX, focus-order, target-size and strict contrast evidence; source journeys remain bound to their complete native segments.',
          'evidenceID':prefix+'ax-'+sid+'-'+taskid,'focusOrderEvidenceID':prefix+'focus-order-'+sid+'-'+taskid,
          'targetSizeEvidenceID':prefix+'target-size-'+sid+'-'+taskid,'contrastEvidenceID':prefix+'contrast-'+sid+'-'+taskid,
          'stateCount':len(ids),'stateSetSHA256':digest('\n'.join(ids).encode()),
          'aggregateAXTreeSHA256':digest('\n'.join(s+'|'+ax[s]['axTreeSHA256'] for s in ids).encode()),'stateAXTreeDigests':evidence}
        record['automatedEvidenceIDs']=[record[k] for k in ['evidenceID','focusOrderEvidenceID','targetSizeEvidenceID','contrastEvidenceID']]+[prefix+'contrast-'+sid+'-'+s for s in record['exceptionStateIDs']]
        output.append(record); save(stage/'accessibility'/sid/(taskid+'.json'),dict(record,sourceProductHead=head))
    return output

def assemble_output(stage,ctx,matrix,sources):
    require(len(sources)==3,'complete three-member assembly required')
    selections=[s['selection'] for s in sources]
    require(len({s['sessionIdentitySHA256'] for s in selections})==3,'duplicate native session')
    require(sources[2]['receipt']['sourceDependencySelections']==selections[:2],'segment3 predecessor selections changed; reselect original predecessors or reexecute dependent segment')
    require(all(s['receipt']['sourceDependencySelections']==[] for s in sources[:2]),'unexpected earlier dependencies')
    rows={key:[r for source in sources for r in source['rows'][key]] for key in ['ax','contrast','journeys','purchaseProofs','pendingReceiptProofs']}
    require([r['stateID'] for r in rows['ax']]==ctx['plan']['orderedStateIDs'] and [r['stateID'] for r in rows['contrast']]==ctx['plan']['orderedStateIDs'],'assembled native ordered67 closure mismatch')
    if not ctx['minimum']:
        actual={r['stateID'] for r in rows['contrast'] if r['result']=='EXCEPTION'}
        require(actual=={a['stateID'] for a in ctx['plan']['exceptionAuthorities']},'shared AX lost exact existing exception closure')
    dst=stage/'s10-4'/ctx['shard']['shardID']; candidates=[]; cell_sources=[]
    for source in sources:
        origin=source['directory']/'artifact'; segment=source['receipt']['segment']; sid=ctx['shard']['shardID']
        for row in source['candidates']:
            target=dst/row['artifactPath']; require(not target.exists(),'duplicate owned PNG'); target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(origin/'s10-4'/sid/row['artifactPath'],target); candidates.append(row)
            cell_sources.append({'stateID':row['stateID'],'segmentID':segment['segmentID'],**{k:source['selection'][k] for k in ['runID','runAttempt','jobID','artifactID','artifactSHA256','receiptSHA256']}})
        for category in ['ax','contrast']:
            for state in segment['ownedStateIDs']:
                target=stage/category/sid/(state+'.json'); require(not target.exists(),'duplicate owned native row'); target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(origin/category/sid/(state+'.json'),target)
    tasks=task_artifacts(stage,ctx,rows,matrix['productHead'])
    for name,value in [('state-ax.json',rows['ax']),('contrast.json',rows['contrast']),('accessibility.json',tasks),('candidate-files.json',candidates),('source-segment-receipts.json',[s['receipt'] for s in sources]),('cell-source-map.json',cell_sources),('journey-rows.json',rows['journeys']),('purchase-proof-rows.json',rows['purchaseProofs']),('pending-receipt-proof-rows.json',rows['pendingReceiptProofs'])]: save(dst/name,value)
    save(dst/'shard-receipt.json',{'schemaVersion':2,'receiptKind':'s10.4-shared-logical-shard','taskID':'S10.4',
      'shardID':ctx['shard']['shardID'],'requirementID':ctx['shard']['requirementID'],'deviceProfileID':ctx['shard']['deviceProfileID'],
      'runtime':ctx['device']['simulatorRuntime'],'runtimeBuild':ctx['device']['simulatorRuntimeBuild'],'simulatorName':ctx['device']['simulatorName'],
      'productHead':matrix['productHead'],'matrixID':matrix['matrixID'],'candidateCount':67,'stateAXRowCount':67,'contrastRowCount':67,'accessibilityRowCount':6,
      'sharedBuildIdentitySHA256':matrix['sharedBuildIdentitySHA256'],'producerQualificationSHA256':matrix['producerQualificationSHA256'],'localUnitExecutedTestCount':0,'producerUnitExecutedTestCount':5,
      'nativeExecutionKind':'three-distinct-consumer-sessions','complete':True,'humanVisualReviewStatus':'NOT_RUN'})
    save(dst/'segment-aggregation.json',{'schemaVersion':2,'receiptKind':'s10.4-shared-segment-aggregation','complete':True,'finalAcceptanceEligible':True,
      'matrixID':matrix['matrixID'],'productHead':matrix['productHead'],'shardID':ctx['shard']['shardID'],
      'assemblyRunID':os.environ.get('GITHUB_RUN_ID'),'assemblyRunAttempt':os.environ.get('GITHUB_RUN_ATTEMPT'),
      'assemblyIsNativeExecution':False,'distinctSessionCount':3,'selectedConsumers':selections,
      'dependencyResolution':{'segmentID':ctx['segments'][2]['segmentID'],'selectedPredecessors':selections[:2],'immutableSelectionsVerified':True},
      'sourceSegmentReceiptSHA256s':[s['selection']['receiptSHA256'] for s in sources],
      'journeyResolution':{'minimumJourneyIDs':[r['journeyID'] for r in rows['journeys'] if r.get('setupOnly') is False],'sourceNativeSuccessRequired':True},
      'sharedBuildIdentitySHA256':matrix['sharedBuildIdentitySHA256'],'producerQualificationSHA256':matrix['producerQualificationSHA256'],'humanVisualReviewStatus':'NOT_RUN'})

def admission_or_assembly(root,admission_root,shard_id,segment_id,map_path,destination,assembly=False):
    head=physical_source(root); ctx=plan_context(root,shard_id,allow_full=(segment_id=='none' and not assembly))
    mapping=source_map(map_path,ctx,segment_id,assembly)
    stage=fresh_output(destination)
    try:
        # Assembly authenticates producer for this exact shard; there is no UI job
        # pretending to be segmentnone. This is a read-only producer selection.
        selection={'shardID':shard_id,'segmentID':'none' if assembly else segment_id,'purpose':'acceptance'}
        module,producer=original_producer(root,admission_root,selection,stage,head)
        ctx['producerSeal']=load(producer/'shared-build-seal.json')
        ctx['producerQualification']=load(producer/'unit-proof/producer-qualification.json')
        matrix=new_matrix(ctx,head,producer); verify_matrix(matrix,ctx)
        sources=[]
        for key,rid in mapping:
            segment=next(s for s in ctx['segments'] if s['segmentID']==key)
            sources.append(retrieve_source(module,root,stage,ctx,segment,rid,matrix))
        matrix['selectedConsumers']=[s['selection'] for s in sources]
        if assembly: assemble_output(stage,ctx,matrix,sources)
        save(stage/'matrix-binding.json',matrix)
        save(stage/'admission.json',{'schemaVersion':1,'contractID':CONTRACT,'admitted':True,'selection':selection,'matrixID':matrix['matrixID'],
          'sourceRunMap':dict(mapping),'producerQualificationSHA256':matrix['producerQualificationSHA256'],'sharedBuildIdentitySHA256':matrix['sharedBuildIdentitySHA256'],
          'dependencyCount':len(sources),'isAssembly':assembly,'nativeExecutionClaim':False})
        write_checksums(stage); check_checksums(stage); publish(stage,destination)
    except BaseException:
        shutil.rmtree(stage,ignore_errors=True)
        raise

def main(root,args):
    require(args,'mode required')
    if args[0]=='--collect-shared-segment':
        require(len(args)==6,'collect requires artifactRoot attachmentRoot shard segment matrix')
        collect(root,Path(args[1]),Path(args[2]),args[3],args[4],Path(args[5]))
    elif args[0]=='--admit-shared-selection':
        require(len(args)==6,'admit requires producerAdmission shard segment sourceMap newOutput')
        admission_or_assembly(root,Path(args[1]),args[2],args[3],Path(args[4]),Path(args[5]))
    elif args[0]=='--assemble-shared':
        require(len(args)==5,'assembly requires producerAdmission shard sourceMap newOutput')
        admission_or_assembly(root,Path(args[1]),args[2],'none',Path(args[3]),Path(args[4]),True)
    else: raise Rejected('unknown shared mode')

if __name__=='__main__':
    try: main(Path(sys.argv[1]).resolve(),sys.argv[2:])
    except (Rejected,KeyError,TypeError,ValueError,OSError,subprocess.CalledProcessError,zipfile.BadZipFile,zlib.error) as error:
        print('shared segment validation failed: '+str(error),file=sys.stderr)
        sys.exit(1)
S10_4_SHARED_SEGMENT_PY
    exit $?
    ;;
esac
# H411_LEGACY_AX_BODY_BEGIN
#!/usr/bin/env bash
set -euo pipefail

source_root="${1:?segment source root required}"
output_root="${2:?assembled output root required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
plan_path="$repo_root/Scripts/s10-4-segment-plan.json"
task_contract_path="$repo_root/docs/design/s10/s10-accessibility-common-tasks.json"
shard_id="s10.4.current.ax-text"
requirement_id="ax_text"
profile_id="iphone-17-ios-26.2-current"

test "${S10_4_SEGMENT_MATRIX_RESULT:-}" = "success"
test -f "$plan_path"
test -f "$task_contract_path"
test -d "$source_root"
test -d "$output_root"
test -z "$(find "$output_root" -mindepth 1 -print -quit)"

staging_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test -d "$staging_parent"
staging_root="$(mktemp -d "$staging_parent/s10-4-assembled.XXXXXX")"
cleanup_on_error() {
  status=$?
  rm -rf "$staging_root"
  rm -f \
    "$output_root/s10-4/$shard_id/shard-receipt.json" \
    "$output_root/s10-4/$shard_id/segment-aggregation.json" \
    "$output_root/SHA256SUMS.txt" 2>/dev/null || true
  exit "$status"
}
trap cleanup_on_error ERR INT TERM

sha256_file() {
  shasum -a 256 "$1" | awk '{print toupper($1)}'
}

sha256_text() {
  printf '%s' "$1" | shasum -a 256 | awk '{print toupper($1)}'
}

directory_digest() {
  local source_dir="$1"
  local rows
  rows="$(mktemp)"
  : > "$rows"
  while IFS= read -r file_path; do
    printf '%s  %s\n' "$(sha256_file "$file_path")" "${file_path#"$source_dir/"}" >> "$rows"
  done < <(find "$source_dir" -type f | LC_ALL=C sort)
  sha256_file "$rows"
  rm -f "$rows"
}

plan_sha256="$(sha256_file "$plan_path")"
test "$(sha256_file "$repo_root/Scripts/ci-selection.json")" = "$(jq -r '.selectorSHA256' "$plan_path")"
test "$(sha256_file "$repo_root/Scripts/s10-4-shards.json")" = "$(jq -r '.shardContractSHA256' "$plan_path")"
test "$(sha256_file "$repo_root/docs/design/s10/s10-screen-state-inventory.json")" = "$(jq -r '.inventorySHA256' "$plan_path")"
test "$(sha256_file "$task_contract_path")" = "$(jq -r '.commonTaskSchemaSHA256' "$plan_path")"
kernel_json="$(jq -cS '{
  productHead,
  selectorSHA256,
  shardContractSHA256,
  inventorySHA256,
  commonTaskSchemaSHA256,
  orderedStateSHA256,
  stateSetSHA256,
  captureBaselineSHA256,
  state27CallerSHA256,
  preflightHelperSHA256,
  issueRecheckHelperSHA256,
  exceptionAuthorities
}' "$plan_path")"
evidence_kernel_sha256="$(sha256_text "$kernel_json")"
jq -e --arg kernel "$evidence_kernel_sha256" '
  .schemaVersion == 1
  and .shardID == "s10.4.current.ax-text"
  and .requirementID == "ax_text"
  and .deviceProfileID == "iphone-17-ios-26.2-current"
  and .runnerProvider == "github"
  and .runnerLabel == "macos-26"
  and .xcodeVersion == "Xcode 26.6"
  and .xcodeBuild == "17F113"
  and .sdkName == "iphonesimulator26.5"
  and .sdkBuild == "23F81a"
  and .simulatorName == "iPhone 17"
  and .simulatorRuntime == "iOS 26.2"
  and .simulatorRuntimeBuild == "23C54"
  and .crossSessionBuildReuse == false
  and .crossSessionTestWithoutBuilding == false
  and .evidenceKernelSHA256 == $kernel
  and (.orderedStateIDs | length) == 67
  and (.orderedStateIDs | unique | length) == 67
  and [.segments[].segmentID] == ["segment-1", "segment-2", "segment-3"]
  and [.segments[].stateCount] == [22, 28, 17]
  and [.segments[].replayCount] == [0, 22, 22]
  and [.segments[].resumeMode] == ["none", "route-replay", "local-replay-plus-ui-prerequisite"]
  and [.segments[].dependencySegmentIDs] == [[], [], ["segment-1", "segment-2"]]
  and [.segments[].dependencyOwnedStateCount] == [0, 0, 50]
  and [.segments[].dependencyOwnedStateSHA256] == [
    "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
    "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
    "80397ABF11A3622661E301900B7A23D0398FBF292CEEE29E1E9FA1E7A8EDA0A4"
  ]
  and .segments[0].ownedStateIDs == .orderedStateIDs[0:22]
  and .segments[1].ownedStateIDs == .orderedStateIDs[22:50]
  and .segments[2].ownedStateIDs == .orderedStateIDs[50:67]
  and .segments[0].replayStateIDs == []
  and .segments[1].replayStateIDs == .orderedStateIDs[0:22]
  and .segments[2].replayStateIDs == .orderedStateIDs[0:22]
  and .segments[0].dependencyOwnedStateIDs == []
  and .segments[1].dependencyOwnedStateIDs == []
  and .segments[2].dependencyOwnedStateIDs == .orderedStateIDs[0:50]
  and .segments[0].resumeSetup == null
  and .segments[1].resumeSetup == null
  and .segments[2].resumeSetup == {
    setupID: "segment-3-report-pdf-failed-v1",
    rowCount: 1,
    localReplayCount: 22,
    sourceOrdinal: 22,
    sourceStateID: "state.sign-detail.open-issue",
    skippedStartOrdinal: 23,
    skippedEndOrdinal: 50,
    targetOrdinal: 51,
    targetStateID: "state.report-pdf.failed",
    cursorBeforeResume: 22,
    cursorAfterResume: 50,
    dependencyOwnedStateSHA256:
      "80397ABF11A3622661E301900B7A23D0398FBF292CEEE29E1E9FA1E7A8EDA0A4",
    applicationForeground: true,
    purchaseVerified: true,
    pendingDifferentIssueReceiptVerified: true,
    reportFailureRouteVerified: true,
    renderFailureArgumentCount: 1
  }
  and (.exceptionAuthorities | length) == 15
  and ([.exceptionAuthorities[].exceptionIssueID] | unique | length) == 15
  and all(.exceptionAuthorities[];
    .shardID == "s10.4.current.ax-text"
    and (.stateID | startswith("state."))
    and (.taskID | type == "string" and length > 0)
    and .exceptionOwner == "palatis3"
    and (.exceptionExpiresAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))
' "$plan_path" > /dev/null

mapfile -t source_dirs < <(find "$source_root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
test "${#source_dirs[@]}" -eq 3
test -z "$(find "$source_root" -mindepth 1 -maxdepth 1 ! -type d -print -quit)"

mkdir -p \
  "$staging_root/segment-sources" \
  "$staging_root/s10-4/$shard_id/candidates" \
  "$staging_root/ax/$shard_id" \
  "$staging_root/contrast/$shard_id" \
  "$staging_root/accessibility/$shard_id"
combined_shard="$staging_root/s10-4/$shard_id"
: > "$combined_shard/state-ax.ndjson"
: > "$combined_shard/contrast.ndjson"
: > "$combined_shard/accessibility.ndjson"
printf '[]\n' > "$combined_shard/candidate-files.json"
printf '[]\n' > "$combined_shard/source-segment-receipts.json"

declare -A seen_segments=()
declare -A seen_sessions=()
common_head=""
common_ref=""
common_run=""
common_attempt=""

for source_dir in "${source_dirs[@]}"; do
  test -f "$source_dir/SHA256SUMS.txt"
  test -z "$(find "$source_dir" -type l -print -quit)"
  (cd "$source_dir" && shasum -a 256 -c SHA256SUMS.txt)
  receipt="$source_dir/s10-4/$shard_id/segment-receipt.json"
  test -s "$receipt"
  segment_id="$(jq -er '.segmentID' "$receipt")"
  case "$segment_id" in segment-1|segment-2|segment-3) ;; *) exit 1 ;; esac
  test -z "${seen_segments[$segment_id]+x}"
  seen_segments[$segment_id]=1
  segment_json="$(jq -cer --arg id "$segment_id" '.segments[] | select(.segmentID == $id)' "$plan_path")"
  state_count="$(jq -r '.stateCount' <<< "$segment_json")"
  replay_count="$(jq -r '.replayCount' <<< "$segment_json")"
  resume_setup_count="$(jq -r '.resumeSetup.rowCount // 0' <<< "$segment_json")"

  jq -e \
    --arg segment "$segment_id" \
    --arg plan "$plan_sha256" \
    --arg kernel "$evidence_kernel_sha256" \
    --arg shard "$shard_id" \
    --arg requirement "$requirement_id" \
    --arg profile "$profile_id" \
    --argjson expected "$segment_json" '
      .schemaVersion == 1
      and .receiptKind == "s10.4-segment"
      and .complete == true
      and .finalAcceptanceEligible == false
      and .segmentID == $segment
      and .shardID == $shard
      and .requirementID == $requirement
      and .deviceProfileID == $profile
      and .segmentPlanSHA256 == $plan
      and .evidenceKernelSHA256 == $kernel
      and .selectorSHA256 == "692DD6F7DBCF771170191E7839C6B6281FB0A72603475FF2D0D81E35078330E2"
      and .shardContractSHA256 == "C023ADE99CAB0F9ED2984C90BCC0E03B0D05A05643DF7185201CC00772E3C8E4"
      and .inventorySHA256 == "6C820E8A1160297F561EABF1873BE82403589B408E4A8FA3318269293242F507"
      and .commonTaskSchemaSHA256 == "B7EDB1DD18BAB6DEE1884DA52C15F63AD5AD06045F58444C61442957558999F0"
      and .runnerProvider == "github"
      and .runnerLabel == "macos-26"
      and .xcodeVersion == "Xcode 26.6"
      and .xcodeBuild == "17F113"
      and .sdkName == "iphonesimulator26.5"
      and .sdkBuild == "23F81a"
      and .simulatorRuntime == "iOS 26.2"
      and .simulatorRuntimeBuild == "23C54"
      and .simulatorName == "iPhone 17"
      and .buildMode == "independent-build-for-testing"
      and .crossSessionBuildReuse == false
      and .crossSessionTestWithoutBuilding == false
      and .ordinal == $expected.ordinal
      and .startOrdinal == $expected.startOrdinal
      and .endOrdinal == $expected.endOrdinal
      and .stateCount == $expected.stateCount
      and .replayCount == $expected.replayCount
      and .resumeMode == $expected.resumeMode
      and .dependencySegmentIDs == $expected.dependencySegmentIDs
      and .dependencyOwnedStateCount == $expected.dependencyOwnedStateCount
      and .dependencyOwnedStateIDs == $expected.dependencyOwnedStateIDs
      and .dependencyOwnedStateSHA256 == $expected.dependencyOwnedStateSHA256
      and .resumeSetup == $expected.resumeSetup
      and .ownedStateIDs == $expected.ownedStateIDs
      and .replayStateIDs == $expected.replayStateIDs
      and .ownedStateSHA256 == $expected.ownedStateSHA256
      and .replayStateSHA256 == $expected.replayStateSHA256
      and .markerCount == $expected.stateCount
      and .replayRowCount == $expected.replayCount
      and .resumeSetupRowCount == ($expected.resumeSetup.rowCount // 0)
      and .diagnosticCount == 0
      and .attachmentCount == ($expected.stateCount + 1)
      and .segmentTerminalAttachmentCount == 1
      and .candidateCount == $expected.stateCount
      and .stateAXRowCount == $expected.stateCount
      and .contrastRowCount == $expected.stateCount
      and .accessibilityRowCount == 0
      and ((.unitTestSelectors | type) == "array")
      and ((.unitTestSelectors | length) == 5)
      and ((.unitTestSelectors | unique | length) == 5)
      and .unitTestSelectors == [
        "S10_4AutomatedBrandLabTests/testFrozenBrandPaletteProvidesExactOpaqueNormalAndIncreasedContrastTruth()",
        "S10_4AutomatedBrandLabTests/testFrozenInventoryDerivesExactUnpromotedVisualAndAccessibilityMatrices()",
        "S10_4AutomatedBrandLabTests/testMigratedProductAndTokenCoverageRemainBoundToFrozenInventory()",
        "S10_4AutomatedBrandLabTests/testMinimumOSCameraDeniedLegacyTabCorrectionIsNarrowAndDiagnosticFree()",
        "S10_4AutomatedBrandLabTests/testPinnedOverlaySelectorAndExactSevenPlusSevenShardContract()"
      ]
      and ((.uiTestSelectors | type) == "array")
      and ((.uiTestSelectors | length) == 1)
      and .uiTestSelectors == [
        "S10_4AutomatedBrandLabUITests/testAutomatedBrandLabShard()"
      ]
      and .unitExecutedTestCount == 5
      and .uiExecutedTestCount == 1
      and (.buildIdentitySHA256 | test("^[0-9A-F]{64}$"))
      and (.unitIdentitySHA256 | test("^[0-9A-F]{64}$"))
      and (.uiIdentitySHA256 | test("^[0-9A-F]{64}$"))
      and (.sessionIdentitySHA256 | test("^[0-9A-F]{64}$"))
    ' "$receipt" > /dev/null

  for bundle in Build.xcresult UnitTests.xcresult UISmoke.xcresult; do
    test -d "$source_dir/$bundle"
    test -n "$(find "$source_dir/$bundle" -mindepth 1 -print -quit)"
  done
  test -s "$source_dir/build-smoke.log"
  test -s "$source_dir/test-smoke.log"
  test -s "$source_dir/ui-smoke.log"
  test "$(grep -Fxc '** TEST BUILD SUCCEEDED **' "$source_dir/build-smoke.log" || true)" -eq 1
  test "$(grep -Fxc '** TEST EXECUTE SUCCEEDED **' "$source_dir/test-smoke.log" || true)" -eq 1
  test "$(grep -Fxc '** TEST EXECUTE SUCCEEDED **' "$source_dir/ui-smoke.log" || true)" -eq 1
  test "$(directory_digest "$source_dir/Build.xcresult")" = "$(jq -r '.buildIdentitySHA256' "$receipt")"
  test "$(directory_digest "$source_dir/UnitTests.xcresult")" = "$(jq -r '.unitIdentitySHA256' "$receipt")"
  test "$(directory_digest "$source_dir/UISmoke.xcresult")" = "$(jq -r '.uiIdentitySHA256' "$receipt")"

  head="$(jq -er '.productHead' "$receipt")"
  ref="$(jq -er '.ref' "$receipt")"
  run="$(jq -er '.runID' "$receipt")"
  attempt="$(jq -er '.runAttempt' "$receipt")"
  test "$(jq -er '.artifactName' "$receipt")" = \
    "ios-ci-$run-$attempt-$shard_id-$segment_id"
  test "$(basename "$source_dir")" = "$(jq -er '.artifactName' "$receipt")"
  runner_name="$(jq -er '.runnerName' "$receipt")"
  simulator_udid="$(jq -er '.simulatorUDID' "$receipt")"
  job_id="$(jq -er '.jobID' "$receipt")"
  test -n "$runner_name"
  test -n "$job_id"
  test "$(tr '[:lower:]' '[:upper:]' <<< "$simulator_udid")" = "$simulator_udid"
  test "$(grep -Ec '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' \
    <<< "$simulator_udid")" -eq 1
  if test -z "$common_head"; then
    common_head="$head"; common_ref="$ref"; common_run="$run"; common_attempt="$attempt"
  else
    test "$head" = "$common_head"
    test "$ref" = "$common_ref"
    test "$run" = "$common_run"
    test "$attempt" = "$common_attempt"
  fi
  test "$head" = "${GITHUB_SHA:?}"
  test "$ref" = "${GITHUB_REF:?}"
  test "$run" = "${GITHUB_RUN_ID:?}"
  test "$attempt" = "${GITHUB_RUN_ATTEMPT:?}"
  session="$(jq -er '.sessionIdentitySHA256' "$receipt")"
  expected_session="$(printf '%s\n%s\n%s\n%s\n' \
    "$runner_name" "$simulator_udid" "$job_id" "$(jq -er '.uiIdentitySHA256' "$receipt")" \
    | shasum -a 256 | awk '{print toupper($1)}')"
  test "$session" = "$expected_session"
  test -z "${seen_sessions[$session]+x}"
  seen_sessions[$session]=1

  shard_source="$source_dir/s10-4/$shard_id"
  test ! -e "$shard_source/shard-receipt.json"
  test ! -e "$source_dir/accessibility/$shard_id"
  test "$(jq 'length' "$shard_source/state-ax.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/contrast.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/candidate-exports.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/candidate-files.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/replay-rows.json")" -eq "$replay_count"
  test "$(jq 'length' "$shard_source/resume-setup-rows.json")" -eq "$resume_setup_count"
  jq -e --arg shard "$shard_id" --arg segment "$segment_id" --argjson expected "$segment_json" '
    [.[].stateID] == $expected.replayStateIDs
    and [.[].ordinal] == (if $expected.replayCount == 0 then [] else [range(1; $expected.replayCount + 1)] end)
    and all(.[]; .shardID == $shard and .segmentID == $segment)
  ' "$shard_source/replay-rows.json" > /dev/null
  jq -e --arg shard "$shard_id" --arg segment "$segment_id" \
    --argjson expected "$segment_json" --argjson replayCount "$replay_count" \
    --argjson setupCount "$resume_setup_count" '
      length == $setupCount
      and if $setupCount == 0 then
        . == [] and $expected.resumeSetup == null
      else
        $setupCount == 1
        and .[0] == {
          schemaVersion: 1,
          acceptanceEligible: false,
          shardID: $shard,
          segmentID: $segment,
          setupID: $expected.resumeSetup.setupID,
          sourceOrdinal: $expected.resumeSetup.sourceOrdinal,
          sourceStateID: $expected.resumeSetup.sourceStateID,
          skippedStartOrdinal: $expected.resumeSetup.skippedStartOrdinal,
          skippedEndOrdinal: $expected.resumeSetup.skippedEndOrdinal,
          targetOrdinal: $expected.resumeSetup.targetOrdinal,
          targetStateID: $expected.resumeSetup.targetStateID,
          cursorBeforeResume: $expected.resumeSetup.cursorBeforeResume,
          cursorAfterResume: $expected.resumeSetup.cursorAfterResume,
          localReplayCount: $replayCount,
          dependencyOwnedStateSHA256:
            $expected.resumeSetup.dependencyOwnedStateSHA256,
          applicationForeground:
            $expected.resumeSetup.applicationForeground,
          purchaseVerified: $expected.resumeSetup.purchaseVerified,
          pendingDifferentIssueReceiptVerified:
            $expected.resumeSetup.pendingDifferentIssueReceiptVerified,
          reportFailureRouteVerified:
            $expected.resumeSetup.reportFailureRouteVerified,
          renderFailureArgumentCount:
            $expected.resumeSetup.renderFailureArgumentCount
        }
      end
    ' "$shard_source/resume-setup-rows.json" > /dev/null
  jq -e --argjson expected "$segment_json" '[.[].stateID] == $expected.ownedStateIDs' "$shard_source/state-ax.json" > /dev/null
  jq -e --argjson expected "$segment_json" '[.[].stateID] == $expected.ownedStateIDs' "$shard_source/contrast.json" > /dev/null
  jq -e --argjson expected "$segment_json" '
    [.[].stateID] == $expected.ownedStateIDs
    and all(.[];
      (.exportedFileName | type == "string")
      and (.exportedFileName | test("^[A-Za-z0-9._-]+$")))
  ' "$shard_source/candidate-exports.json" > /dev/null
  jq -e --argjson expected "$segment_json" '
    . as $candidateRows
    | ([$candidateRows[].stateID] == $expected.ownedStateIDs)
      and all(range(0; ($candidateRows | length));
        . as $index
        | $candidateRows[$index].artifactPath
            == ("candidates/" + $expected.ownedStateIDs[$index] + ".png")
          and ($candidateRows[$index].sha256 | test("^[0-9A-F]{64}$"))
          and ($candidateRows[$index].bytes | type == "number" and . > 0))
  ' "$shard_source/candidate-files.json" > /dev/null
  test "$(find "$shard_source/candidates" -type f -name 'state.*.png' | wc -l | tr -d ' ')" -eq "$state_count"
  mapfile -t observed_markers < <(sed -n 's/^S10_MIGRATION_STATE state=//p' "$source_dir/ui-smoke.log")
  test "${#observed_markers[@]}" -eq "$state_count"
  test "$(printf '%s\n' "${observed_markers[@]}" | jq -Rsc 'split("\n") | map(select(length>0))')" = \
    "$(jq -c '.ownedStateIDs' <<< "$segment_json")"
  mapfile -t observed_replays < <(sed -n 's/^S10_4_SEGMENT_REPLAY //p' "$source_dir/ui-smoke.log")
  test "${#observed_replays[@]}" -eq "$replay_count"
  test "$(grep -Ec '^S10_4_AX ' "$source_dir/ui-smoke.log" || true)" -eq 0
  test "$(grep -Ec '^S10_4_FRONTIER_REPLAY ' "$source_dir/ui-smoke.log" || true)" -eq 0
  test "$(grep -Ec '^S10_4_.*DIAGNOSTIC' "$source_dir/ui-smoke.log" || true)" -eq 0
  test "$(grep -Eic 'Lost connection to testmanagerd|XCTHTestOperationCoordinatorErrorDomain' "$source_dir/ui-smoke.log" || true)" -eq 0
  jq -e '[.[]?.attachments[]? | select(
    .suggestedHumanReadableName == "UI Snapshot"
    or .suggestedHumanReadableName == "Synthesized Event"
    or .suggestedHumanReadableName == "Screen Recording"
    or (
      (.suggestedHumanReadableName // "") as $name
      | (($name | startswith("S10.4 candidate ")) | not)
        and ($name | test("diagnostic"; "i"))
    )
    or .isAssociatedWithFailure == true)] | length == 0' \
    "$shard_source/xcresult-attachment-manifest.json" > /dev/null
  jq -e --arg name "S10.4 segment terminal $segment_id $shard_id" \
    --argjson stateCount "$state_count" '
      ([.[]?.attachments[]?] | length) == ($stateCount + 1)
      and ([.[]?.attachments[]? | select(
        .isAssociatedWithFailure == false
        and (.suggestedHumanReadableName | type == "string")
        and ((.suggestedHumanReadableName
          | sub("_0_[0-9A-Fa-f-]{36}\\."; ".")) == $name)
        and (.exportedFileName | type == "string")
        and (.exportedFileName | test("^[A-Za-z0-9._-]+$"))
      )] | length) == 1
    ' "$shard_source/xcresult-attachment-manifest.json" > /dev/null

  while IFS= read -r candidate_row; do
    state_id="$(jq -er '.stateID' <<< "$candidate_row")"
    candidate_file="$shard_source/candidates/$state_id.png"
    test -f "$candidate_file"
    test "$(sha256_file "$candidate_file")" = "$(jq -er '.sha256' <<< "$candidate_row")"
    test "$(wc -c < "$candidate_file" | tr -d ' ')" = "$(jq -er '.bytes' <<< "$candidate_row")"
  done < <(jq -c '.[]' "$shard_source/candidate-files.json")

  cp -a "$source_dir" "$staging_root/segment-sources/$segment_id"
  while IFS= read -r state_id; do
    test ! -e "$combined_shard/candidates/$state_id.png"
    test ! -e "$staging_root/ax/$shard_id/$state_id.json"
    test ! -e "$staging_root/contrast/$shard_id/$state_id.json"
    cp "$shard_source/candidates/$state_id.png" "$combined_shard/candidates/$state_id.png"
    cp "$source_dir/ax/$shard_id/$state_id.json" "$staging_root/ax/$shard_id/$state_id.json"
    cp "$source_dir/contrast/$shard_id/$state_id.json" "$staging_root/contrast/$shard_id/$state_id.json"
  done < <(jq -r '.ownedStateIDs[]' <<< "$segment_json")
  jq -c '.[]' "$shard_source/state-ax.json" >> "$combined_shard/state-ax.ndjson"
  jq -c '.[]' "$shard_source/contrast.json" >> "$combined_shard/contrast.ndjson"
  jq -s '.[0] + .[1]' "$combined_shard/candidate-files.json" "$shard_source/candidate-files.json" \
    > "$combined_shard/candidate-files.next.json"
  mv "$combined_shard/candidate-files.next.json" "$combined_shard/candidate-files.json"
  jq -s '.[0] + [.[1]]' "$combined_shard/source-segment-receipts.json" "$receipt" \
    > "$combined_shard/source-segment-receipts.next.json"
  mv "$combined_shard/source-segment-receipts.next.json" "$combined_shard/source-segment-receipts.json"
done

test "${#seen_segments[@]}" -eq 3
test "${#seen_sessions[@]}" -eq 3
jq -e --slurpfile plan "$plan_path" '
  . as $receipts
  | ($plan[0].segments[] | select(.segmentID == "segment-3")) as $segment3
  | ([
      $segment3.dependencySegmentIDs[] as $dependencyID
      | $receipts[]
      | select(.segmentID == $dependencyID)
    ]) as $dependencies
  | ($receipts | length) == 3
    and ([$receipts[].segmentID] | unique | length) == 3
    and ([$dependencies[].segmentID] == $segment3.dependencySegmentIDs)
    and ($dependencies | length) == 2
    and all($dependencies[];
      .receiptKind == "s10.4-segment"
      and .complete == true
      and .finalAcceptanceEligible == false
      and .productHead == $receipts[0].productHead
      and .ref == $receipts[0].ref
      and .runID == $receipts[0].runID
      and .runAttempt == $receipts[0].runAttempt
      and .segmentPlanSHA256 == $receipts[0].segmentPlanSHA256
      and .evidenceKernelSHA256 == $receipts[0].evidenceKernelSHA256
      and .xcodeVersion == $receipts[0].xcodeVersion
      and .xcodeBuild == $receipts[0].xcodeBuild
      and .sdkName == $receipts[0].sdkName
      and .sdkBuild == $receipts[0].sdkBuild)
    and ([$dependencies[].ownedStateIDs[]] == $segment3.dependencyOwnedStateIDs)
    and (([$dependencies[].ownedStateIDs[]] | length) == $segment3.dependencyOwnedStateCount)
    and ([$receipts[].ownedStateIDs[]] == $plan[0].orderedStateIDs)
    and (([$receipts[].ownedStateIDs[]] | unique | length) == 67)
' "$combined_shard/source-segment-receipts.json" > /dev/null
dependency_state_text="$(jq -r --slurpfile plan "$plan_path" '
  ($plan[0].segments[] | select(.segmentID == "segment-3")) as $segment3
  | . as $receipts
  | $segment3.dependencySegmentIDs[] as $dependencyID
  | $receipts[]
  | select(.segmentID == $dependencyID)
  | .ownedStateIDs[]
' "$combined_shard/source-segment-receipts.json")"
test "$(sha256_text "$dependency_state_text")" = \
  "$(jq -r '.segments[] | select(.segmentID == "segment-3") | .dependencyOwnedStateSHA256' "$plan_path")"
jq -n --slurpfile plan "$plan_path" \
  --slurpfile receipts "$combined_shard/source-segment-receipts.json" '
    ($plan[0].segments[] | select(.segmentID == "segment-3")) as $segment3
    | ($receipts[0]) as $sourceReceipts
    | ([
        $segment3.dependencySegmentIDs[] as $dependencyID
        | $sourceReceipts[]
        | select(.segmentID == $dependencyID)
      ]) as $dependencies
    | {
        requiredSegmentIDs: $segment3.dependencySegmentIDs,
        resolvedSegmentIDs: [$dependencies[].segmentID],
        resolvedStateCount: ([$dependencies[].ownedStateIDs[]] | length),
        resolvedStateSHA256: $segment3.dependencyOwnedStateSHA256,
        sourceSegmentReceiptKinds: [$dependencies[].receiptKind],
        complete: true
      }
' > "$combined_shard/segment-dependency-resolution.json"
jq -s '.' "$combined_shard/state-ax.ndjson" > "$combined_shard/state-ax.json"
jq -s '.' "$combined_shard/contrast.ndjson" > "$combined_shard/contrast.json"
jq -e --slurpfile plan "$plan_path" '[.[].stateID] == $plan[0].orderedStateIDs and length == 67' "$combined_shard/state-ax.json" > /dev/null
jq -e --slurpfile plan "$plan_path" '[.[].stateID] == $plan[0].orderedStateIDs and length == 67' "$combined_shard/contrast.json" > /dev/null
jq -e --slurpfile plan "$plan_path" '[.[].stateID] == $plan[0].orderedStateIDs and length == 67' "$combined_shard/candidate-files.json" > /dev/null
jq -e --arg shard "$shard_id" --arg requirement "$requirement_id" --arg profile "$profile_id" '
  all(.[];
    .shardID == $shard
    and .requirementID == $requirement
    and .deviceProfileID == $profile
    and .result == "PASS"
    and .evidenceID == ("s10.4-ax-" + $shard + "-" + .stateID)
    and .capture == "XCUIApplication.debugDescription"
    and (.axTreeSHA256 | test("^[0-9A-F]{64}$")))
' "$combined_shard/state-ax.json" > /dev/null
jq -e --arg shard "$shard_id" --arg requirement "$requirement_id" --arg profile "$profile_id" '
  all(.[];
    .shardID == $shard
    and .requirementID == $requirement
    and .deviceProfileID == $profile
    and (.result == "PASS" or .result == "EXCEPTION")
    and .evidenceID == ("s10.4-contrast-" + $shard + "-" + .stateID)
    and .audit == "XCUIAccessibilityAuditType.contrast"
    and (.axTreeSHA256 | test("^[0-9A-F]{64}$")))
' "$combined_shard/contrast.json" > /dev/null
test "$(find "$combined_shard/candidates" -type f -name 'state.*.png' | wc -l | tr -d ' ')" -eq 67
test "$(find "$staging_root/ax/$shard_id" -type f -name 'state.*.json' | wc -l | tr -d ' ')" -eq 67
test "$(find "$staging_root/contrast/$shard_id" -type f -name 'state.*.json' | wc -l | tr -d ' ')" -eq 67

# Every planned AX-text exception must be observed once under its exact state,
# owner, expiry, issue ID order, and public callback cardinality.
jq -e --arg today "$(date -u +%F)" --slurpfile plan "$plan_path" '
  def groups($authorities):
    $authorities | sort_by(.stateID, .exceptionIssueID) | group_by(.stateID)
    | map({
        stateID: .[0].stateID,
        issueIDs: map(.exceptionIssueID),
        owner: .[0].exceptionOwner,
        expiry: .[0].exceptionExpiresAt
      });
  ($plan[0].exceptionAuthorities) as $authorities
  | groups($authorities) as $expected
  | ([.[] | select(.result == "EXCEPTION")] | sort_by(.stateID)) as $actual
  | all(.[];
      if .result == "PASS" then
        .exceptionIssueID == ""
        and .exceptionOwner == ""
        and .exceptionExpiresAt == ""
        and .exceptionRationale == ""
        and .ignoredAuditIssues == []
      else .result == "EXCEPTION" end)
  and [$actual[].stateID] == [$expected[].stateID]
  and ($authorities | length) == 15
  and ($expected | length) == 13
  and all($actual[]; . as $row |
    ($expected[] | select(.stateID == $row.stateID)) as $group
    | $row.exceptionIssueID == ($group.issueIDs | join(" | "))
    and $row.exceptionOwner == $group.owner
    and $row.exceptionExpiresAt == $group.expiry
    and $today <= $row.exceptionExpiresAt
    and ($row.exceptionRationale | type == "string" and length > 0)
    and ($row.ignoredAuditIssues | type == "array" and length == ($group.issueIDs | length))
    and all($row.ignoredAuditIssues[];
      .auditTypeRawValue == "1"
      and .compactDescription == "Contrast failed"
      and .detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      and .elementType == (if $row.stateID == "state.recheck-capture.wide-ready" then "XCUIElementType(rawValue: 9)" else "XCUIElementType(rawValue: 48)" end)
      and (.elementFrame | type == "object")
      and .applicationFrame == {x:0,y:0,width:402,height:874}))
' "$combined_shard/contrast.json" > /dev/null

# Derive the same six canonical common-task rows from the verified state union.
mapfile -t task_ids < <(jq -r '.tasks[].task_id' "$task_contract_path")
test "${#task_ids[@]}" -eq 6
for task_id in "${task_ids[@]}"; do
  mapfile -t task_states < <(jq -r --arg task "$task_id" '.tasks[] | select(.task_id == $task) | .screen_state_ids | sort[]' "$task_contract_path")
  test "${#task_states[@]}" -gt 0
  state_evidence="[]"
  canonical_lines=()
  for state_id in "${task_states[@]}"; do
    digest="$(jq -er --arg state "$state_id" '.[] | select(.stateID == $state) | .axTreeSHA256' "$combined_shard/state-ax.json")"
    [[ "$digest" =~ ^[0-9A-F]{64}$ ]]
    state_evidence="$(jq -c --arg state "$state_id" --arg digest "$digest" '. + [{stateID:$state,axTreeSHA256:$digest}]' <<< "$state_evidence")"
    canonical_lines+=("$state_id|$digest")
  done
  canonical_evidence="$(IFS=$'\n'; printf '%s' "${canonical_lines[*]}")"
  state_set_text="$(IFS=$'\n'; printf '%s' "${task_states[*]}")"
  aggregate_digest="$(sha256_text "$canonical_evidence")"
  state_set_digest="$(sha256_text "$state_set_text")"
  task_authorities="$(jq -c --arg task "$task_id" '[.exceptionAuthorities[] | select(.taskID == $task)] | sort_by(.stateID,.exceptionIssueID)' "$plan_path")"
  exception_state_ids="$(jq -c '[.[].stateID] | unique | sort' <<< "$task_authorities")"
  issue_ids="$(jq -r '[.[].exceptionIssueID] | join(" | ")' <<< "$task_authorities")"
  owner="$(jq -r 'if length == 0 then "" else .[0].exceptionOwner end' <<< "$task_authorities")"
  expiry="$(jq -r 'if length == 0 then "" else .[0].exceptionExpiresAt end' <<< "$task_authorities")"
  exception_rationale=""
  if test "$(jq 'length' <<< "$task_authorities")" -gt 0; then
    exception_rationale="$(jq -r --argjson states "$exception_state_ids" \
      '[.[] | select(.stateID | IN($states[]))] | sort_by(.stateID) | map(.exceptionRationale) | join(" | ")' \
      "$combined_shard/contrast.json")"
    test -n "$exception_rationale"
  fi
  status="PASS"
  rationale="All task states produced AX-tree, focus-order, target-size, and strict Apple contrast evidence."
  if test -n "$issue_ids"; then
    status="EXCEPTION"
    if test "$(jq 'length' <<< "$task_authorities")" -eq 1; then
      rationale="All task states produced AX-tree, focus-order, and target-size evidence; the sole Apple contrast issue is bound to the named, expiring exception."
    else
      rationale="All task states produced AX-tree, focus-order, and target-size evidence; the exact Apple contrast issues are bound to the named, expiring exceptions."
    fi
  fi
  automated_ids="$(jq -cn --arg shard "$shard_id" --arg task "$task_id" --argjson states "$exception_state_ids" '[
      "s10.4-ax-"+$shard+"-"+$task,
      "s10.4-focus-order-"+$shard+"-"+$task,
      "s10.4-target-size-"+$shard+"-"+$task,
      "s10.4-contrast-"+$shard+"-"+$task
    ] + [$states[] | "s10.4-contrast-"+$shard+"-"+.]')"
  raw_task_file="$staging_root/.s10-4-$task_id.raw.json"
  jq -cnS \
    --arg taskID "$task_id" --arg shardID "$shard_id" --arg profile "$profile_id" \
    --arg status "$status" --arg issueIDs "$issue_ids" --arg owner "$owner" --arg expiry "$expiry" \
    --arg exceptionRationale "$exception_rationale" --arg rationale "$rationale" \
    --arg aggregate "$aggregate_digest" --arg stateSet "$state_set_digest" \
    --argjson evidence "$state_evidence" --argjson stateIDs "$exception_state_ids" \
    --argjson automatedIDs "$automated_ids" '
      {
        taskID:$taskID, shardID:$shardID, deviceProfileID:$profile, feature:"larger_text",
        automatedStatus:$status,
        automatedReviewer:"FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests",
        exceptionIssueID:$issueIDs, exceptionOwner:$owner, exceptionExpiresAt:$expiry,
        exceptionRationale:$exceptionRationale, exceptionStateIDs:$stateIDs,
        rationale:$rationale,
        evidenceID:("s10.4-ax-"+$shardID+"-"+$taskID),
        focusOrderEvidenceID:("s10.4-focus-order-"+$shardID+"-"+$taskID),
        targetSizeEvidenceID:("s10.4-target-size-"+$shardID+"-"+$taskID),
        contrastEvidenceID:("s10.4-contrast-"+$shardID+"-"+$taskID),
        automatedEvidenceIDs:$automatedIDs,
        stateCount:($evidence|length), stateSetSHA256:$stateSet,
        aggregateAXTreeSHA256:$aggregate, stateAXTreeDigests:$evidence
      }' > "$raw_task_file"
  jq -c '.' "$raw_task_file" >> "$combined_shard/accessibility.ndjson"
  jq -cS --arg productHead "$common_head" '. + {sourceProductHead:$productHead}' \
    "$raw_task_file" > "$staging_root/accessibility/$shard_id/$task_id.json"
  rm -f "$raw_task_file"
done
jq -s '.' "$combined_shard/accessibility.ndjson" > "$combined_shard/accessibility.json"
test "$(jq 'length' "$combined_shard/accessibility.json")" -eq 6
test "$(find "$staging_root/accessibility/$shard_id" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 6
for task_file in "$staging_root/accessibility/$shard_id"/*.json; do
  jq -e --arg shard "$shard_id" --arg head "$common_head" '
    .shardID == $shard
    and .sourceProductHead == $head
    and .evidenceID == ("s10.4-ax-" + $shard + "-" + .taskID)
    and .focusOrderEvidenceID == ("s10.4-focus-order-" + $shard + "-" + .taskID)
    and .targetSizeEvidenceID == ("s10.4-target-size-" + $shard + "-" + .taskID)
    and .contrastEvidenceID == ("s10.4-contrast-" + $shard + "-" + .taskID)
  ' "$task_file" > /dev/null
done

jq -n \
  --arg taskID "S10.4" --arg shardID "$shard_id" --arg requirementID "$requirement_id" \
  --arg deviceProfileID "$profile_id" --arg runtime "iOS 26.2" --arg runtimeBuild "23C54" \
  --arg simulatorName "iPhone 17" --arg productHead "$common_head" \
  '{schemaVersion:1,taskID:$taskID,shardID:$shardID,requirementID:$requirementID,
    deviceProfileID:$deviceProfileID,runtime:$runtime,runtimeBuild:$runtimeBuild,
    simulatorName:$simulatorName,productHead:$productHead,candidateCount:67,
    stateAXRowCount:67,accessibilityRowCount:6,contrastRowCount:67}' \
  > "$combined_shard/shard-receipt.json"

jq -n \
  --arg shardID "$shard_id" --arg requirementID "$requirement_id" --arg profile "$profile_id" \
  --arg head "$common_head" --arg ref "$common_ref" --arg run "$common_run" --arg attempt "$common_attempt" \
  --arg planSHA256 "$plan_sha256" --arg evidenceKernelSHA256 "$evidence_kernel_sha256" \
  --slurpfile receipts "$combined_shard/source-segment-receipts.json" \
  --slurpfile dependency "$combined_shard/segment-dependency-resolution.json" '
    {schemaVersion:1,receiptKind:"s10.4-segment-aggregation",complete:true,
      finalAcceptanceEligible:true,shardID:$shardID,requirementID:$requirementID,
      deviceProfileID:$profile,productHead:$head,ref:$ref,runID:$run,runAttempt:$attempt,
      segmentPlanSHA256:$planSHA256,evidenceKernelSHA256:$evidenceKernelSHA256,
      segmentIDs:["segment-1","segment-2","segment-3"],segmentCount:3,
      distinctSessionCount:3,candidateCount:67,stateAXRowCount:67,
      contrastRowCount:67,accessibilityRowCount:6,
      dependencyResolution:$dependency[0],sourceSegmentReceipts:$receipts[0]}' \
  > "$combined_shard/segment-aggregation.json"

cp "$plan_path" "$combined_shard/s10-4-segment-plan.json"
checksum_file="$staging_root/SHA256SUMS.txt.pending"
(
  cd "$staging_root"
  find . -type f ! -name 'SHA256SUMS.txt*' -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' file_path; do
        printf '%s  %s\n' "$(shasum -a 256 "$file_path" | awk '{print toupper($1)}')" "${file_path#./}"
      done
) > "$checksum_file"
mv "$checksum_file" "$staging_root/SHA256SUMS.txt"
(cd "$staging_root" && shasum -a 256 -c SHA256SUMS.txt)

cp -a "$staging_root/." "$output_root/"
rm -rf "$staging_root"
test -s "$output_root/SHA256SUMS.txt"
test -s "$output_root/s10-4/$shard_id/shard-receipt.json"
test -s "$output_root/s10-4/$shard_id/segment-aggregation.json"
trap - ERR INT TERM
