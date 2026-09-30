from pathlib import Path
import hashlib,json,difflib,subprocess,shutil
w=Path.cwd();p=w/'.codex-temp/cold-physical-pending-producer-successor-v1';old=w/'.codex-temp/cold-physical-continuation-successor-v6';base=w/'.codex-temp/cold-physical-author-baseline-v1'
sha=lambda b:hashlib.sha256(b).hexdigest();jdump=lambda x:(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
paths=['FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift','FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift']
inputs={
'LedgerPendingRequestV10.swift.fragment':Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/pending-producer-interface-v10/LEDGER_PENDING_REQUEST_SHAPE_V10.swift.fragment'),
'PhysicalPendingRequestBindingV10.swift.fragment':Path('/Users/rentamac/.codex/worktrees/cold-erase-continuation/AssetRounds/.codex-temp/cold-schema2-continuation-successor-v1/terminal-authority-interface-v10/PHYSICAL_PENDING_REQUEST_BINDING_V10.swift.fragment'),
'StoreReadInterfaceV4.swift':Path('/Users/rentamac/.codex/worktrees/cold-control-continuation/AssetRounds/.codex-temp/cold-control-contract-v4-v1/READ_INTERFACE_V4_V1.swift')}
im={}
for k,v in inputs.items():
 shutil.copyfile(v,p/'inputs'/k);im[k]={'source':str(v),'sha256':sha(v.read_bytes())}
assert im['PhysicalPendingRequestBindingV10.swift.fragment']['sha256']=='c2d14f08a5fcf0edc82e447d852ee7098f33b7d1d751ffe6367a3b180caf2f6f'
assert im['LedgerPendingRequestV10.swift.fragment']['sha256']=='be527834e2ff704575672a61006ab37f46babe0ec577359d8970283f8cce4617'
assert im['StoreReadInterfaceV4.swift']['sha256']=='7028aba3b6e7f2c3013dd1d35747c73d27d2238bec3e07a94ad1d4ae94518669'
(p/'INPUT_BINDING.json').write_bytes(jdump(im))
(p/'INTERFACES.md').write_text('''# Physical pending producer boundary adapter V1

Exact Ledgerbe527 and actual central required positive methodc2d14. requireComplete/visitCompleteProjection signatures remain, while BoundaryObservation's private producerRequest is now consumed explicitly. Internal scan takes optional OriginalEraseC16ProducerRequestV4; nil preserves the actual ordinary no-request PREPARING preimage, never demands a future pending receipt. Non-nil performs actual permit.requireProducerRequestBinding at entry, before/after every scanner primitive through its real bound function, at output edge and before/after each streamed callback. Slot/source/temp/mode equality belongs to genuine private Ledger session and durable canonical Store pending readback; physical code never constructs a request, future fullFact or authority.

Boundary finite proof additionally requires mutually exclusive bornSource/request, purpose.producerRequest, exact plan/step/active C16 ordinal, exact private slot producer ordinal/final allowed path and actual supplied payload SHA. Full complete expected-tree proof remains the Ledger's authenticated current finite projection, including exact already durable zero/prefix/link cut and retained born tuple rules. This packet does not allow caller request DATA to add a path or admit partial bytes. Actual controller ordering remains: ordinary both-names-absent PREPARING preproof; Store pending CAS/readback; positive request proof; first publisher effect. Interrupted partial replay requires existing actual canonical pending input before observation.

StoreREAD7028 is pinned as future direct bounded adapter input only, not consumed or implemented here. Legacy Progress full JSON commitments remain exact; new recordBinding/logicalProgress/target rowstream VALUE adapter is separate forthcoming source. No synthetic old Progress/birth array is created.
''')
(p/'CASE_MATRIX.md').write_text('''# Pending boundary source cases, no runtime claims

| Cut | Actual source rule |
|---|---|
| pre-pending ordinary PREPARING | request nil, unchanged complete finite absence proof; no future request readback demanded |
| durable pending bound request | exact private plan/step/slot/path/temp/mode/payload under real current Store token at every raw scanner boundary |
| matching bytes without durable pending | required private permit getter refuses; DATA/shape cannot authorize |
| zero/prefix/link replay | complete actual finite Ledger projection + already durable pending readback; no role from current survivor |
| request and bornSource both supplied | rejects; private Ledger constructor also mutually excludes |
| finalized Hygiene prepare | genuine rename-born receipt only; no fictitious request temporary |
| changed Store stage/ordinal/input | positive bindings fail and real permanent poison fence applies |
| request-bound projection callback | positive before/after binding; no publisher syscall is performed here |
| full V4 segmented Store adapter | distinct pending implementation; old JSON hash not relabeled |
''')
(p/'READ_WORK_PROOF.md').write_text('''# Pending adapter read-work scope

All complete scanner pass counters, PFP8/4 coefficients, EOF/cursor/tree/per-file/unique pair bounds remain exact V6/V5. This adapter adds no scanner, syscall retry, effect or database open. Finite boundary validation computes one actual request SHA over request.bytes per requireFinite call; no opaque tree Data is newly materialized. Actual request role bytes and durable pending readback must be separately role-bounded by the private Ledger/Store source contract. Every real requireProducerRequestBinding callback has independently bounded actual source/control work; its work is not counted in the PFP or scanner envelope and cannot recurse into this full observer. No authorization cache/window is implemented. The actual provider-work K*N and current-capacity/full producer representation obligations remain open.
''')
(p/'HANDOFF.md').write_text('''# Physical pending request successor handoff

GPT-6.1 Sol xhigh. Unique ignored successor over immutable V6BINDING539f. Factory exactV6; Observer additive actual pending-boundary consumer only. Full tracked1206 baseline, prior sealed packets and functional Notification/Search succession remain untouched.

Actual requireComplete now consumes the genuine private Ledger ProducerRequest, positively reproofing its actual durable canonical pending Store binding at each scanner/raw-IO/output/callback edge. Initial no-request PREPARING is preserved; no future authority is required before pending publication. Finite plan/step/ordinal/slot/path/payload checks supplement existing full namespace/current tuple/partial-cut proof. No new partial path, publisher syscall, source/OS/close success or request is manufactured.

PARTIAL/NONINSTALLABLE. Real central pending issuer/Store readback implementation and Ledger publisher/controller exact ordering, fresh current scope and work budgets remain coupled prerequisites. StoreREAD7028 direct bounded Progress/target/projection commitment adapter is pinned but still separately unimplemented. Every V6/V5 generic/Registry/firstcapture/capacity/compact primitive/semantic/final-origin/full B/runtime obligation remains due. Root alone performs semantic compiler/build/native/independent review/gates/integration/Git; actual DEBUG/nonDEBUG syntax only is recorded. No compiler/native/Products/test/CI/settings/S10/Release/signing effect.
''')
parse={}
for label,defs in [('DEBUG',['-D','DEBUG']),('nonDEBUG',[])]:
 cmd=['swiftc','-frontend','-parse',*defs,*[str(p/'candidate'/x) for x in paths]];r=subprocess.run(cmd,capture_output=True,text=True)
 parse[label]={'command':cmd,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'scope':'syntax_only_not_semantic_compilation_or_runtime'};assert r.returncode==0,r.stderr
(p/'PARSE.json').write_bytes(jdump(parse))
before=json.loads((base/'SOURCE_MAP.json').read_text());assert len(before)==1206;actual={x:sha((w/x).read_bytes()) for x in before};drift={x:actual[x] for x in before if before[x]!=actual[x]};assert not drift,drift
c={x:sha((p/'candidate'/x).read_bytes()) for x in paths};after=dict(before);after.update(c);(p/'AFTER_SOURCE_MAP.json').write_bytes(jdump(after))
assert c[paths[1]]==sha((old/'candidate'/paths[1]).read_bytes())
(p/'SOURCE_ONLY_CHECKS.json').write_bytes(jdump({'trackedSourceInputs':1206,'trackedSourceDrift':drift,'factoryExactlyV6':True,'noBehaviorOrRuntimeVerification':True}))
for name,src in [('CANDIDATE.diff',w),('SUCCESSOR.diff',old/'candidate')]:
 chunks=[]
 for x in paths:chunks.extend(difflib.unified_diff((src/x).read_text().splitlines(True),(p/'candidate'/x).read_text().splitlines(True),fromfile=str(src/x),tofile=str(p/'candidate'/x)))
 (p/name).write_text(''.join(chunks))
(p/'SOURCE_SUCCESSION.json').write_bytes(jdump({'parentBindingSHA256':sha((old/'BINDING.json').read_bytes()),'sourceInputs':1206,'onlyCandidatePaths':paths,'requestConsumer':'authentic already-durable pending private getter; no pre-pending future authority','liveFunctionalFirstObserverSHA256':'ad95d26b481a864a3f5f6b45a5f2917d790f703af59cbb0f742e85c0d6d40d1b'}))
a={str(x.relative_to(p)):sha(x.read_bytes()) for x in sorted(p.rglob('*')) if x.is_file() and 'candidate' not in x.parts and x.name!='BINDING.json'}
b={'schemaVersion':1,'packet':'physical_pending_producer_boundary','status':'sealed_source_only_PARTIAL_NONINSTALLABLE_companion_issuers_due','model':'gpt-6.1-sol','reasoningEffort':'xhigh','head':'93159755395d697a5a9da02f41374120433c50f9','sourceInputs':1206,'beforeFullSourceMapSHA256':sha((base/'SOURCE_MAP.json').read_bytes()),'afterFullSourceMapSHA256':sha((p/'AFTER_SOURCE_MAP.json').read_bytes()),'parentBindingSHA256':sha((old/'BINDING.json').read_bytes()),'candidates':{x:{'publishedBeforeSHA256':before[x],'immediateBeforeSHA256':sha((old/'candidate'/x).read_bytes()),'candidateSHA256':c[x]} for x in paths},'inputs':im,'artifacts':a,'openObligations':['actual private pending Store issuer/getter/controller readback/order/current scopes','direct bounded V4 logical vs physical progress adapter','all V6/V5 actual full-family source/resource/capacity/Registry/semantic/runtime obligations','root semantic compiler/native independent source review/gates']}
(p/'BINDING.json').write_bytes(jdump(b))
for f in p.rglob('*'):
 if f.is_file():f.chmod(0o444)
print(json.dumps({'binding':sha((p/'BINDING.json').read_bytes()),'candidates':c,'afterMap':b['afterFullSourceMapSHA256'],'parse':{k:v['exitCode'] for k,v in parse.items()},'trackedDrift':drift},indent=2))
