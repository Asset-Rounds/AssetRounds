from pathlib import Path
import hashlib,json,subprocess,difflib,shutil
w=Path.cwd();p=w/'.codex-temp/cold-physical-continuation-successor-v6';prev=w/'.codex-temp/cold-physical-continuation-successor-v5';base=w/'.codex-temp/cold-physical-author-baseline-v1'
sha=lambda b:hashlib.sha256(b).hexdigest()
jdump=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
paths=['FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift','FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift']
inputs={
 'CompactTargetReadPermitV4.swift.fragment':Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/issuer-core-successor-v9/TERMINAL_REAL_OS_SCOPE_V4.swift.fragment'),
 'ConsumerCompleteSubjectV4.swift.fragment':Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/issuer-core-successor-v9/CONSUMER_COMPLETE_SUBJECT_V4.swift.fragment'),
 'ROOT_A_DECISION.md':Path('/Users/rentamac/Developer/AssetRounds/.codex-temp/compact-target-semantic-root-direction-v1/DECISION.md'),
 'SEMANTIC_PREREQUISITE_REVIEW.md':Path('/Users/rentamac/Developer/AssetRounds/.codex-temp/compact-target-semantic-prerequisite-review-sol61-xhigh-v1/REVIEW.md'),
 'MINIMUM_TUPLE_AND_PRODUCER_CUTS.md':Path('/Users/rentamac/Developer/AssetRounds/.codex-temp/compact-target-semantic-prerequisite-review-sol61-xhigh-v1/MINIMUM_TUPLE_AND_PRODUCER_CUTS.md')}
for k,v in list(inputs.items()):
 if not v.exists() and k=='ConsumerCompleteSubjectV4.swift.fragment':
  matches=list(v.parent.glob('*SUBJECT*fragment'));assert len(matches)==1,matches;inputs[k]=matches[0]
inputmap={}
for k,v in inputs.items():
 b=v.read_bytes();shutil.copyfile(v,p/'inputs'/k);inputmap[k]={'source':str(v),'sha256':sha(b)}
assert inputmap['CompactTargetReadPermitV4.swift.fragment']['sha256']=='86825adf3c60794f2e16693552c35bb54c7359ec3fb37c32ed4ca5e10d5ca6d3'
assert inputmap['ConsumerCompleteSubjectV4.swift.fragment']['sha256']=='600f50f9639f479e8b20144f112da4acdcc77bf55f62e529179bc5288f6d2dfc'
assert inputmap['ROOT_A_DECISION.md']['sha256']=='349fbc7147135ee00e9ce63264c1705e9baf68b2c6e43ea8567b9d6ac62af9b7'
(p/'INPUT_BINDING.json').write_bytes(jdump(inputmap))
factory=(p/'candidate'/paths[1]).read_text();start=factory.index('    /// Physical DATA only. The private initializer follows actual complete');end=factory.index('    func postRetiredTree(parent: Int32, name: String,',start)
(p/'COMPACT_PHYSICAL_DATA_V4.swift.fragment').write_text(factory[start:end])
(p/'CASE_MATRIX.md').write_text('''# V6 compact physical source case matrix — no runtime evidence

| Actual cut | Source disposition / missing dependency |
|---|---|
| actual first-held compact Support EX | borrowed exact parent FD, retained observation IO, genuine86825 current binding before/after raw IO; no EX minted |
| exact singleton target | full Data-before/target/Data-after physical scans, canonical UUID name and target original D/F digest |
| pointer and preserved Manifest | actual complete bytes/SHA/full11/strict link1, source1MiB/4MiB bounds and canonical codec equality |
| optional retired list present | complete canonical actual bytes, real empty list predicate; no nil-to-empty conversion |
| retired absent | actual complete Data names establish absence |
| SQL/WAL/SHM/supported generation paths | all byte-bearing entries scanned through existing GenerationOwnedPathV1 classifier; no main-SQL-only commitment |
| actual private policy | durable/db/media/journal/pointer genuine profile; ordinary nlink1 strict; primitive compact PFP origin API remains missing |
| named-held replacement / byte or directory change | actual complete facts/digest/SHA/members equality fails; sticky poison, no rebase |
| foreign or nonempty semantic graph/Journal | physical observation never implies semantic success; actual complete A producer/compatibility needed |
| source image changed after graph/alias/checkpoint/close | genuine semantic validation must repeat before final seal; no hash adoption or permanent lawful-state exclusion |
| lawful legacy/missing semantic DATA | full genuine B producer remains required; observer permit cannot authorize private copy/sidecars |
| short pread/extra EOF/cursor overflow | per-call checked finite reservation, no retry loops |
| uncertain close | actual numeric FD/DIR permanently retained; no second close, retry, destructor cleanup or success |
| present fresh pointer/target image | DATA only, no Context/Journal/drain/OS/namespace/ready permission |
| unsupported complete population at current old caps | root versioned capacity/order representation obligation remains; no inferred +N widening or corruption declaration |
''')
(p/'HANDOFF.md').write_text('''# Cold physical successor V6 handoff

GPT-6.1 Sol xhigh. Separate compact physical-only successor over immutable V5d84d; V1–V5 remain immutable. Observer bytes stay exactly V5f20c. Only ignored owned candidates/artifacts changed; all tracked1206/published931597/b24e baseline unchanged. Root alone integrates/compiler/build/native/review/commits/pushes.

Actual new Factory method inspectSchema2CompactFirstHeldTarget borrows first-held Support EX under real86825 permit. It performs complete genuine-policy Data preimage, independent singleton target original walker digest and Data postimage, exact canonical current pointer/preserved Manifest/optional retired bytes and all current11/9/UID/GID/device/link/namespace/SHA checks, finite64KiB reads/cursors, retained uncertainty fences and checked transient closes. Private result is physical DATA only. It exposes THREE actual scanner work records, actual control counters and overflow-checked total payload/reservations; no read pass completion is inferred. See exact interface/work proof and full immediate/published diffs/map.

PARTIAL/NONINSTALLABLE. Typed compact PFP per-internal-primitive origin binding is not yet authored; current ordinary helper is only externally bracketed and cannot be advertised as satisfying the full fresh-origin condition. Genuine86825 private first-held issuer, complete source/current-cut callback and its independently bounded primitive/census window remain missing. Root A direction349fbc now authorizes prospective complete semantic DATA route, but this packet contains NO graph producer/tuple/context bridge/current semantic compatibility/Store canonical transfer. No fresh SwiftData/context/Journal loan exists, and allowsSave:false does not prove no-effects: existing private-copy routes create WAL/SHM. Missing/changed/lawful legacy origins require actual full B validation under distinct authentic effect resources, not observation86825, old Intent/Preparation/session or blanket refusal.

Existing complete physical/generic/C16 author prerequisites from V5 remain due: actual firstcapture/raw source issuers, cold positive accounting mint, lossless logical control/birth current-overlay/producer/old-plan representation, exact Registry consumed subset/newguard/replacement/prefix owner, central source/record/OS/drain/retirement/final terminal composition. This compact packet does not resolve them or silently clobber functional live Notification/Search Observerad95 succession.

Actual DEBUG/nonDEBUG syntax parse only; no semantic compiler/build/native/Git/Products/test/CI/settings/S10/Release/signing effects. Independent GPT-6.1 Sol xhigh consequential source review and coupled root compilers/native/fault/capacity/full same-head gates remain required. Physical protection stays UNVERIFIED/DEFERRED and releaseReady=false.
''')
(p/'WORKING_HANDOFF.md').write_text('Superseded by immutable V6 HANDOFF.md; any further source edits require a distinct successor.\n')
parse={}
for label,defs in [('DEBUG',['-D','DEBUG']),('nonDEBUG',[])]:
 cmd=['swiftc','-frontend','-parse',*defs,*[str(p/'candidate'/x) for x in paths]];r=subprocess.run(cmd,capture_output=True,text=True)
 parse[label]={'command':cmd,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'scope':'syntax_only_not_semantic_compilation_or_runtime'};assert r.returncode==0,r.stderr
(p/'PARSE.json').write_bytes(jdump(parse))
before=json.loads((base/'SOURCE_MAP.json').read_text());assert len(before)==1206
tracked={x:sha((w/x).read_bytes()) for x in before};drift={x:{'baseline':before[x],'actual':tracked[x]} for x in before if before[x]!=tracked[x]};assert not drift,drift
candidate={x:sha((p/'candidate'/x).read_bytes()) for x in paths};after=dict(before);after.update(candidate);(p/'AFTER_SOURCE_MAP.json').write_bytes(jdump(after))
marker=b'    func postRetiredTree(parent: Int32, name: String,';old=(prev/'candidate'/paths[1]).read_bytes();new=(p/'candidate'/paths[1]).read_bytes();assert old[old.index(marker):]==new[new.index(marker):]
assert candidate[paths[0]]==sha((prev/'candidate'/paths[0]).read_bytes())
(p/'SOURCE_ONLY_CHECKS.json').write_bytes(jdump({'trackedSourceInputs':1206,'trackedSourceDrift':drift,'observerExactlyV5':True,'ordinaryPostRetiredTreeAndFollowingFactoryBytesUnchangedFromV5':True,'ordinaryRegionSHA256':sha(new[new.index(marker):]),'noSemanticCompilationOrRuntime':True}))
for name,src in [('CANDIDATE.diff',w),('SUCCESSOR.diff',prev/'candidate')]:
 chunks=[]
 for x in paths:chunks.extend(difflib.unified_diff((src/x).read_text().splitlines(True),(p/'candidate'/x).read_text().splitlines(True),fromfile=str(src/x),tofile=str(p/'candidate'/x)))
 (p/name).write_text(''.join(chunks))
(p/'SOURCE_SUCCESSION.json').write_bytes(jdump({'parentBindingSHA256':sha((prev/'BINDING.json').read_bytes()),'sourceInputs':1206,'onlyCandidatePaths':paths,'liveFunctionalFirstObserverSHA256':'ad95d26b481a864a3f5f6b45a5f2917d790f703af59cbb0f742e85c0d6d40d1b','observerDelta':'none from V5','compactPhysicalResult':'genuine physical DATA only; missing private source/policy/semantic producer APIs'}))
(p/'WORKING_PINS.json').write_bytes(jdump({'status':'superseded_by_immutable_BINDING.json','sourceSHA256':candidate[paths[1]],'observerSHA256':candidate[paths[0]],'compactFragmentSHA256':sha((p/'COMPACT_PHYSICAL_DATA_V4.swift.fragment').read_bytes()),'parseScope':'syntax_only','missing':['genuine compact issuer','typed per-primitive compact PFP observer','actual A semantic/context-image/publication tuple or B genuine effect-authorized full inspection','independent source/provider primitive work bounds','root coupled compiler/native/source review/gates']}))
artifacts={str(x.relative_to(p)):sha(x.read_bytes()) for x in sorted(p.rglob('*')) if x.is_file() and 'candidate' not in x.parts and x.name!='BINDING.json'}
binding={'schemaVersion':6,'status':'sealed_source_only_PARTIAL_NONINSTALLABLE_compact_physical_DATA','authorModel':'gpt-6.1-sol','reasoningEffort':'xhigh','head':'93159755395d697a5a9da02f41374120433c50f9','sourceInputs':1206,'beforeFullSourceMapSHA256':sha((base/'SOURCE_MAP.json').read_bytes()),'afterFullSourceMapSHA256':sha((p/'AFTER_SOURCE_MAP.json').read_bytes()),'parentBindingSHA256':sha((prev/'BINDING.json').read_bytes()),'trackedSourceDrift':drift,'candidates':{x:{'publishedBeforeSHA256':before[x],'immediateBeforeSHA256':sha((prev/'candidate'/x).read_bytes()),'candidateSHA256':candidate[x],'bytes':(p/'candidate'/x).stat().st_size} for x in paths},'inputs':inputmap,'artifacts':artifacts,'openObligations':['Real private first-held compact EX/control/source origin issuer and per-provider complete work bounds','Compact PFP actual primitive kind/path/fact/close origin API','Actual compatible complete semantic graph/global Journal/context-to-image bridge, final-image seal and genuine Store transfer','Full genuine B effect resources/lifecycle for valid missing/changed/legacy semantic DATA','All V5 actual generic/C16/Registry/representation/central runtime obligations','Root semantic compiler/fullbuild/native independent review and required gates']}
(p/'BINDING.json').write_bytes(jdump(binding))
for f in p.rglob('*'):
 if f.is_file():f.chmod(0o444)
print(json.dumps({'binding':sha((p/'BINDING.json').read_bytes()),'candidates':candidate,'afterMap':binding['afterFullSourceMapSHA256'],'compactFragment':sha((p/'COMPACT_PHYSICAL_DATA_V4.swift.fragment').read_bytes()),'parse':{k:v['exitCode'] for k,v in parse.items()},'trackedDrift':drift},indent=2))
