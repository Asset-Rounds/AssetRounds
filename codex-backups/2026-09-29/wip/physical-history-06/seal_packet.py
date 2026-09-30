from pathlib import Path
import hashlib,json,subprocess,difflib,datetime,shutil
w=Path.cwd(); p=w/'.codex-temp/cold-physical-continuation-successor-v5'; v4=w/'.codex-temp/cold-physical-continuation-successor-v4'; base=w/'.codex-temp/cold-physical-author-baseline-v1'
sha=lambda b:hashlib.sha256(b).hexdigest()
jdump=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
paths=['FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift','FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift']
inputs={
'RouterGenericV9.swift.fragment':Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/issuer-core-successor-v9/SEALED_GENERIC_OBSERVATION_V2.swift.fragment'),
'RouterV9_BINDING.json':Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/issuer-core-successor-v9/BINDING.json'),
'ProtectedFilePolicy.swift':Path('/Users/rentamac/.codex/worktrees/cold-pair-policy/AssetRounds/.codex-temp/cold-pair-policy-sealed-generic-successor-v1/candidate/ProtectedFilePolicy.swift'),
'PFP_V9_BINDING.json':Path('/Users/rentamac/.codex/worktrees/cold-pair-policy/AssetRounds/.codex-temp/cold-pair-policy-sealed-generic-v9-binding-successor-v1/BINDING.json'),
'ROOT_DECISION.md':Path('/Users/rentamac/Developer/AssetRounds/.codex-temp/cold-firstcapture-root-decision-v1/DECISION.md'),
'OriginalPairRowData.swift.fragment':Path('/Users/rentamac/.codex/worktrees/live-notification-absence/AssetRounds/.codex-temp/live-notification-completed-retry-successor-v1/ORIGINAL_PAIR_ACCOUNTING_DATA_V1.swift.fragment')}
(p/'inputs').mkdir(exist_ok=True)
for name,src in inputs.items():shutil.copyfile(src,p/'inputs'/name)
inputs_map={name:{'source':str(src),'sha256':sha(src.read_bytes())} for name,src in inputs.items()}
assert inputs_map['RouterGenericV9.swift.fragment']['sha256']=='16941bbbe09b68b008a2fad54783f4a7f0dc4fb1aa0194650ee3a3e219ecdc5f'
assert inputs_map['ProtectedFilePolicy.swift']['sha256']=='fb3020533cfe03022e9d590984f7ae19a386debc95f4ecb1777fc538b5b2daeb'
assert inputs_map['ROOT_DECISION.md']['sha256']=='7cb3225bcfa525663c127757f6c2f4f1a91a818e9e836b6937ce69c1f036b141'
(p/'INPUT_BINDING.json').write_bytes(jdump(inputs_map))
interfaces='''# Physical generic successor v5 interfaces

GPT-6.1 Sol xhigh; candidate-only source, no installation or authority claim. V4 is immutable and superseded for two concrete coupling refusals: capturedScope.operationID compares to actual operation.operationID (Router ticket), and generic metadata parent is ScratchDataV1/ plus its actual relativeDirectory. Intent.eraseID remains separately bound by genuine publication lineage.

Factory's EraseSchema2ColdOriginalPairAccountingRosterV1.Pair now contains PURE immutable member paths/full11/observed9/SHA/count/device/inode/generic metadata. No restarted DATA reconstructs prior runtime policy objects. The live makeOriginalPairAccountingRoster(originalP:capturedOperationsTree:capturedScope:publication:store:operation:) retains complete real typed scanner observations and actual original Store publication checks. A cold source mint still needs the actual authenticated Store source observation/header/complete row iterator/current token.

schema2ColdCurrentOwnedTree gains genericScope: OriginalEraseSealedGenericObservationScopeV1? alongside the exact canonical Current/Initial or separate FirstCapture routes. It consumes sealed PFP fb302 with Router V9 scope16941. Generic scope roles must be positive intact pair or genuine strict single survivor; C16 role must be ordinary for a generic role, FirstCapture and sealed generic cannot overlap. Old strict default and ordinary postRetiredTree onward bytes are unchanged. Both pair names/current11/9/SHA/policies count and are independently checked; unique physical payload charge uses only privately proved typed membership.

Observer gains lexical withSealedGenericScope and captureFirstWithSealedGenericScope. Original Initial capture can receive actual genericScope too. Neither wrapper keeps a G scope across await nor rebases its immutable first snapshot.

Physical observeInitialComplete / observeComplete / requireComplete / visitCompleteProjection accept the actual lexical genericScope. performOneTarget(...genericScopeProvider:) obtains genuine current scope before and AFTER its ONE assigned unlink; the central provider revokes the preimage and reissues an actual PREPARING loss observation before postimage IO. Nil preserves strict ordinary predicates. Physical code constructs no scope, record token, source permission or nlink2 effect authority.

GenericPairLoss distinguishes actual ownedUnlink from preparingAbsenceReadback and records immutable original Row/accountingSHA, exact consumed original/actual path, survivor actual path, actual before/after full11 and SHA. GenericPairFinalLoss distinguishes the actual last unlink from positive last-name absence replay. Replay actualBeforeFullFact is nil; no invented pre-loss observation is supplied. The required private V9 requireOwnedGenericEvolutionForOriginalPath(path:) begins from the immutable fixed path and proves complete authenticated source-table membership/absence, including when both names are gone. A first-loss replay with genuine surviving Single keeps GenericPairLoss and does not incorrectly enter last-loss replay.

visitFixedNonC16Targets(originalP:c16Plan:targetGenerationID:originalPairAccounting:body:) emits immutable source-derived unique qualified postorder targets. fixedNonC16Targets is compatibility array collection. All original generation-leases descendants NOW remain in fixed postorder; actual drain consumed subset/replacement/new guard births require real external receipts and a genuine prefix owner. No current scan removes a target. visitCompleteProjection emits actual checked complete projection rows with fresh binding per callback. Logical Store stream hashes remain a distinct pending actual codec interface; existing canonical JSON commitments are not renamed as logical hashes.

Full11: dev|ino|mode|uid|gid|nlink|size|mtime_s|mtime_ns|ctime_s|ctime_ns. Persisted9: indices0,1,2,5,6,7,8,9,10. Nine root keys and three parents are unchanged; no global mixed100k ceiling is invented. Typed current-overlay capacity is awaiting root's frozen versioned recipe decision, and old bounds remain exact.
'''
(p/'INTERFACES.md').write_text(interfaces)
(p/'READ_WORK_PROOF.md').write_text((v4/'READ_WORK_PROOF.md').read_text()+'''\n## V5 sealed generic integration\n\nThe sealed-P generic PFP overload uses the same exact4 payload streams as pre-P observed generic aliases. The scanner still invokes PFP separately for each actual alias and makes its own two SHA streams, so successful full pair payload work is10B. Current canonical pair remains18B. No proof or fresh source check is cached. Single-survivor observation uses ordinary strict one-link policy and one scanner SHA stream. Before/after physical executor images include four actual complete scans (two preimage, two postimage); each scan carries its own checked work envelope. With nine registered roots, per complete scanner invocation each actual root keeps1GiB physical/100000 nodes/64 directory depth; the derived worst payload reservation for four nine-root images is4*9*18GiB, checked per pass rather than silently pooled. EOF/cursor/count/metadata proofs remain independently finite. This maximum does not count nonrecursive issuer/raw census/control/OS work: each actual owner must budget those independently. No valid population enlargement is implemented from a guessed +N.\n\nEffect unlink/fstat/fsync and checked-close calls are finite: one assigned target, one guarded descendant chain of at most67 qualified components, no syscall retry loop, fresh permit at each boundary. The real provider before/after is part of central source work and must have its own closed complete source lookup/census bound; its cost is not covered by PFP's4 constant.\n''')
(p/'CASE_MATRIX.md').write_text('''# V5 source case matrix — no runtime result

| Cut | Source behavior / required proof |
|---|---|
| strict ordinary nlink1 | unchanged strict walker and path charge |
| intact authenticated generic pair | two current nodes/SHA/private policy, PFP4 passes per invocation, exact original Row/metadata/mapping; one physical charge |
| originally validated lease present | canonical original metadata remains validated; actual current relation must be unchanged |
| validated lease actually consumed | real mixed/C16 consumed relation, never rewritten as orphan |
| originally owned orphan | positive original absent metadata DATA only |
| ambiguous partial-looking alias names | exact ordered owned generic pair membership; no historical final guess |
| first actual alias unlink | assigned physical permit plus intact preimage; fresh postimage Single nlink2→1/real ctime and exact absence; typed GenericPairLoss |
| first unlink PREPARING replay | positive source/record Single, exact current path absence and before/after survivor equality; preparingAbsenceReadback, no extra unlink |
| last actual alias unlink | strict Single preimage plus genuine both-consumed postimage and exact active target; typed GenericPairFinalLoss |
| last alias PREPARING replay | exact original-path complete-table lookup, both real absences and authenticated active consumed target; no fabricated before fact |
| third alias/unowned/role overlap | refuses under closed typed role/member/namespace proof |
| metadata corrupt/substituted | no orphan fallback |
| source/record stage changes | actual fresh scope/control token fails and permanent poison applies |
| short pread/extra EOF byte/cursor overflow | finite reservation precedes IO and refuses |
| close uncertainty | owned numeric FD/DIR remains permanently retained, no retry/deinit reopen |
| Registry original descendants | all fixed immutable postorder targets retained; no blanket drain omission |
| Registry consumed subset/new guard/replacement | genuine external projected owner and exact receipt/birth recipe still required; no G after hard loss claim |
| original/canonical current image at limit | old bounds exact; actual current birth overlay/versioned representation unresolved |
| 1GiB payload plus metadata / SOURCE4GiB | complete-scope versioned representation obligations remain, not corruption or permanent exclusion |
| cold source accounting | actual Store positive source observation/header/iterator/token prerequisite, no caller alias map |
| compact first-held target | separate next packet, no synthetic Intent or ready receipt in v5 |
''')
(p/'HANDOFF.md').write_text('''# Cold physical successor v5 handoff

GPT-6.1 Sol xhigh. Preserve sealed v1–v4, published93159755395d697a5a9da02f41374120433c50f9/full1206b24e and live functional Observerad95 source succession. Only ignored Factory/FirstObserver candidates changed. Root alone composes/builds/native/reviews/commits/pushes.

V5 corrects operation-vs-erase identity and ScratchDataV1 metadata parent refusals, separates immutable pure accounting DATA from runtime policy, consumes genuine sealed generic intact/single/both evolutions and precise path mapping, mints actual first/last alias one-effect/replay receipts, obtains fresh actual pre/post provider scopes, and adds pure target/projection visitors. Every original Registry descendant now remains immutable fixed postorder, closing the v3 blanket omission direction; actual consumed subset, replacement/control births and finite G-exhaustion projected owner remain REQUIRED and unimplemented by this packet.

PARTIAL/NONINSTALLABLE. Store bounded logical commitment/data source interfaces, authentic FirstCapture/current/raw census issuers and complete budgets, original accounting cold positive source mint, typed current capacity overlay/versioned producer/old plan representation, Registry prefix/new guard/birth recipe, and full central source/phase/record/OS/drain/retirement/terminal composition remain due. V5 does not declare legitimate1GiB+metadata/4GiB/mixed capacity states corruption or exclude them permanently. Separate compact inspector addition is not folded into this packet; real borrowed readonly SQL/Journal origin remains missing.

Actual DEBUG/nonDEBUG syntax parse only and unchanged full tracked1206 map checks are recorded. They do not prove semantic compilation, runtime, independent approval or gates. Root requires actual coupled compiler/fullbuild/native and independent GPT-6.1 Sol xhigh review/all same-head gates before restricted merge. No tracked/Git/Products/tests/CI/S10/Release/settings/signing effects.
''')
(p/'WORKING_HANDOFF.md').write_text('Superseded by sealed HANDOFF.md. V1–V4 retained immutable; further edits require a distinct successor.\n')
parse={}
for label,defs in [('DEBUG',['-D','DEBUG']),('nonDEBUG',[])]:
 cmd=['swiftc','-frontend','-parse',*defs,*[str(p/'candidate'/x) for x in paths]]
 r=subprocess.run(cmd,capture_output=True,text=True)
 parse[label]={'command':cmd,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'scope':'syntax_only_not_semantic_compilation_or_runtime'}
 assert r.returncode==0,r.stderr
(p/'PARSE.json').write_bytes(jdump(parse))
before=json.loads((base/'SOURCE_MAP.json').read_text()); assert len(before)==1206
tracked={x:sha((w/x).read_bytes()) for x in before}
drift={x:{'baseline':before[x],'actual':tracked[x]} for x in before if tracked[x]!=before[x]};assert not drift,drift
candidate={x:sha((p/'candidate'/x).read_bytes()) for x in paths};after=dict(before);after.update(candidate)
(p/'AFTER_SOURCE_MAP.json').write_bytes(jdump(after))
factory=paths[1];marker=b'    func postRetiredTree(parent: Int32, name: String,'
old=(v4/'candidate'/factory).read_bytes();new=(p/'candidate'/factory).read_bytes();assert old[old.index(marker):]==new[new.index(marker):]
(p/'SOURCE_ONLY_CHECKS.json').write_bytes(jdump({'trackedSourceInputs':1206,'trackedSourceDrift':drift,'ordinaryPostRetiredTreeAndFollowingFactoryBytesUnchangedFromV4':True,'ordinaryRegionSHA256':sha(new[new.index(marker):]),'notSwiftBehaviorOrRuntimeVerification':True}))
for name,src in [('CANDIDATE.diff',w),('SUCCESSOR.diff',v4/'candidate')]:
 chunks=[]
 for x in paths:chunks.extend(difflib.unified_diff((src/x).read_text().splitlines(True),(p/'candidate'/x).read_text().splitlines(True),fromfile=str(src/x),tofile=str(p/'candidate'/x)))
 (p/name).write_text(''.join(chunks))
(p/'SOURCE_SUCCESSION.json').write_bytes(jdump({'parentBindingSHA256':sha((v4/'BINDING.json').read_bytes()),'liveFunctionalFirstObserverSHA256':'ad95d26b481a864a3f5f6b45a5f2917d790f703af59cbb0f742e85c0d6d40d1b','inputBindingSHA256':sha((p/'INPUT_BINDING.json').read_bytes()),'sourceInputs':1206,'onlyCandidatePaths':paths,'operationIDCorrection':'actual Router operation.operationID, not intent.eraseID','metadataParentCorrection':'ScratchDataV1/ + actual relativeDirectory','RegistryTargetCorrection':'all original descendants retained; authentic projected owner/births still due'}))
artifacts={str(x.relative_to(p)):sha(x.read_bytes()) for x in sorted(p.rglob('*')) if x.is_file() and 'candidate' not in x.parts and x.name!='BINDING.json'}
binding={'schemaVersion':5,'status':'sealed_source_only_PARTIAL_NONINSTALLABLE_authentic_companion_consumers_due','authorModel':'gpt-6.1-sol','reasoningEffort':'xhigh','head':'93159755395d697a5a9da02f41374120433c50f9','sourceInputs':1206,'beforeFullSourceMapSHA256':sha((base/'SOURCE_MAP.json').read_bytes()),'afterFullSourceMapSHA256':sha((p/'AFTER_SOURCE_MAP.json').read_bytes()),'parentBindingSHA256':sha((v4/'BINDING.json').read_bytes()),'trackedSourceDrift':drift,'candidates':{x:{'publishedBeforeSHA256':before[x],'immediateBeforeSHA256':sha((v4/'candidate'/x).read_bytes()),'candidateSHA256':candidate[x],'bytes':(p/'candidate'/x).stat().st_size} for x in paths},'inputs':inputs_map,'artifacts':artifacts,'openObligations':['Actual complete FirstCapture/raw current/source issuer and per-owner IO work budget','Positive cold Store source observation and pure original accounting mint','Lossless logical commitments/current birth capacity overlay/full producer and old-plan representations','Actual Registry consumed subset/replacement/new guard births and finite prefix ownership after named G hard loss','Full central original/cold source/record/OS/drain/retirement/terminal composition','Root semantic compiler/fullbuild/native independent review and all required gates']}
(p/'BINDING.json').write_bytes(jdump(binding))
for f in p.rglob('*'):
 if f.is_file():f.chmod(0o444)
print(json.dumps({'binding':sha((p/'BINDING.json').read_bytes()),'candidate':candidate,'afterMap':binding['afterFullSourceMapSHA256'],'parse':{k:v['exitCode'] for k,v in parse.items()},'drift':drift},indent=2))
