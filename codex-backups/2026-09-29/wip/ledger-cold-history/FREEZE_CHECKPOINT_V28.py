from pathlib import Path
import difflib, hashlib, json, shutil, subprocess

q = Path('.codex-temp/cold-ledger-continuation-successor-v1')
rel = Path('FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift')
before = q / 'before' / rel
candidate = q / 'candidate' / rel
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(before) == '3224bc14fe17d8a684e8d09d5e5acac875e1629b50d301d18aefd73e09c0204e'
assert sha(candidate) == '3e3edbcebddb4a27eb6184e7d65d834d1d2b14ed036db317ed9f4995b58e995a'
assert sha(rel) == sha(before), 'tracked Ledger changed'
c = q / 'checkpoint-v28'
assert not c.exists(), 'preserve immutable checkpoint'
c.mkdir()
for folder, source in [('before', before), ('candidate', candidate)]:
    dest = c / folder / rel
    dest.parent.mkdir(parents=True)
    shutil.copy2(source, dest)
diff = ''.join(difflib.unified_diff(before.read_text().splitlines(True), candidate.read_text().splitlines(True),
    fromfile='a/' + str(rel), tofile='b/' + str(rel)))
(c / 'DIFF.patch').write_text(diff)
proof = []
for direction, source, expected in [('forward', before, sha(candidate)), ('reverse', candidate, sha(before))]:
    directory = c / 'patch-proof' / direction
    dest = directory / rel
    dest.parent.mkdir(parents=True)
    shutil.copy2(source, dest)
    result = subprocess.run(['patch', '-p1', '--batch'] + (['-R'] if direction == 'reverse' else []),
        input=diff, text=True, cwd=directory, capture_output=True)
    (c / ('PATCH_' + direction + '.log')).write_text(result.stdout + result.stderr)
    item = {'direction': direction, 'exitCode': result.returncode, 'actualSHA256': sha(dest),
        'expectedSHA256': expected, 'exact': sha(dest) == expected}
    assert result.returncode == 0 and item['exact'], item
    proof.append(item)
parse = {'model': 'gpt-6.1-sol', 'reasoningEffort': 'xhigh', 'sourceSHA256': sha(candidate),
    'kind': 'syntax parse only; no module/typecheck/runtime', 'commands': [
        'xcrun swiftc -frontend -parse -D DEBUG <isolated-candidate>',
        'xcrun swiftc -frontend -parse <isolated-candidate>'],
    'DEBUG': {'exitCode': 0, 'log': 'PARSE_WORKING_V28_DEBUG.log', 'logSHA256': sha(q/'PARSE_WORKING_V28_DEBUG.log')},
    'nonDEBUG': {'exitCode': 0, 'log': 'PARSE_WORKING_V28_nonDEBUG.log', 'logSHA256': sha(q/'PARSE_WORKING_V28_nonDEBUG.log')}}
(q / 'PARSE_WORKING_V28.json').write_text(json.dumps(parse, indent=2) + '\n')
for name in ['PARSE_WORKING_V28.json', 'PARSE_WORKING_V28_DEBUG.log', 'PARSE_WORKING_V28_nonDEBUG.log',
             'LEGACY_FD_PATH_CENSUS_WORKING_V28.json', 'NESTED_PUBLICATION_IO_V22.json', 'ERRNO_PRESERVATION_V21.json', 'PENDING_PRODUCER_GATE_V24.json', 'PENDING_PRODUCER_RECIPE_V25.json', 'BOUNDARY_EXCLUSION_V26.json', 'INITIAL_DERIVED_SLOT_BOOTSTRAP_V27.json', 'DISTINCT_INITIAL_SLOT_ENUMERATOR_V28.json', 'V27_PREPARATION_ASSERTION_FAILURE.json', 'PENDING_PRODUCER_AND_INITIAL_SLOTS_INTERFACE_V28.swift.fragment']:
    shutil.copy2(q/name, c/name)
cases = (q/'CASE_MATRIX_WORKING_V13.md').read_text()
cases = cases.replace('# Ledger checkpoint v13 cases', '# Ledger checkpoint v28 cases')
cases = cases.replace('9e103f62be4aeb15d72c7e822c2c89eb17853c5aa2c9f837fdb2abcac1977723', sha(candidate))
cases += '''

V14–V28 additive source cases (all are static direction only):

| Cut | Candidate behavior | Remaining coupled proof |
|---|---|---|
| borrowed raw observation/effect | permanent active/closed/uncertain memory latch first; required fresh provider before/after main instance and nested publication metadata/sync I/O | actual nonrecursive provider must match the permitted physical cut; semantic compile/runtime due |
| escaped body after close/uncertain | latch survives provider/permit/field clearing; descriptor-bearing instance entry refuses before old numeric FD use | independent final source and runtime close fault review due |
| provider throws | borrowed owner becomes permanently uncertain; real permit poison invoked on actor branch | actual outer owner retention/revocation due |
| syscall returns failure | incoming errno restored before syscall, actual errno restored after fresh proof | runtime errno/fault cuts due |
| directory enumeration | rewinddir and each readdir are freshly bracketed; errno0 input cannot be polluted by before-proof callbacks | old100k current-image limit remains unresolved; no cap widening |
| new descriptor open/dup | ownership installed immediately before any post-open proof; open/close are not naively wrapped across retention/receipt | static factory and nested terminal owner audit plus runtime due |
| generic intact alias pair | distinct real sealed-generic scope, immutable accounting row/metadata provenance/path mapping, PFP dual policy and streamed SHA; no fake C16 settle | actual complete source table/Store record/provider and full physical proof due |
| generic single survivor | actual retained evolution proves exact original member consumption before strict ordinary nlink1 policy | actual one-child physical target/prefix receipt due |
| generic both members consumed | original-path lookup proves actual immutable row and checked evolution without selecting a current survivor; same C16 ordinal allowed only by external per-member ordered proof | exact full-table absence/provenance callbacks due |
| initial generic partial classification | only positively proved generic pair members are excluded from canonical C16 partial steps | complete metadata for empty/single/unpaired orphan directories and combined-role bound remain gaps |
| pre-final publication crash | actual retained PublicationSession issues exact payload/temp/mode request before create or replay temp settlement; dynamic recipe consumes retained bytes | required actual Store/Router pending CAS/readback and physical whole-image binding remain due |
| finalized H rename | no fictitious publication temporary; actual retained staged finalizing tuple is distinct from final prepare birth | exact producer request/captured source lineage and actual Store readback due |
| new generic scope after CAS | required provider freshly issues against actual current cut; prior scope cannot serve as authority | actual Router revocation/record token/metadata-directory source still due |
| separate live root-marker fix | exact reviewed live cd2bfb delta absorbed using fuzz0 forward/reverse proof | future composition semantic compilation/runtime remain due; live evidence remains separately bound |
'''
cases += '''

V23–V28 source cuts:

| Cut | Candidate behavior | Remaining coupled proof |
|---|---|---|
| final absent / temp absent | Actual retained publisher first evaluates both names read-only, then privately emits fixed slot/payload/SHA/exact temporary path/mode request; no first create without receipt | Actual Store pending CAS/readback + complete physical request projection due |
| zero/prefix/full existing temp | Dynamic producer is reconstructed from positively retained pending bytes; exact actual session requests receipt before temp open/unlink/recreate | Actual pending table provenance, full projection and fault runtime due |
| final-only identical | Session finishes without new producer request; genuine original/captured final lineage remains independently required | Actual capture/getter/source owner due |
| canonical link pair | Request precedes physical birth; actual pair policy/expected whole-tree proof remains strict; final capture follows one-link readback | Actual Store request-to-birth tuple CAS due |
| request received before any syscall | Receipt exact observation identity/readback and getter byte/temp/SHA equality are consumed before authorizing this retained session only | Actual current Store record/token invalidation due |
| different request same slot | Fixed role bytes and actual pending getter must match; no added version ordinal or replacement payload | Actual Store one-slot strict idempotence implementation due |
| finalized hygiene rename | No partial producer request; actual captured finalizing source tuple is consumed then separate real finalized birth is captured | Actual staged source + rename provenance due |
| producer request plus birth | Private throwing boundary constructor rejects simultaneous fields | Semantic compile/runtime due |
| sealed-P / no sources | Planner retains only exact genuine first-P output as private initialDerivedPlan DATA; distinct initial slot API has no effect referencePlan/ordinal/Progress | Actual initial source/census token due |
| Sources/Plan / no Progress | Same separate read-only API accepts only freshly reissued actual noProgress scope and exact derived plan; one shared streaming iterator | Actual Store publication ordering; read-only visitor or coherent phase reissue/page protocol due |
| true runtime replay | Existing slot iterator requires effect referencePlan and real Lifecycle permit; Bootstrap cannot use it | Actual Source/Progress plan/slot record readback due |
| live marker source delta | Root-pinned reviewed cd2bfb delta applied with no fuzz; reverse returns exact V22 source | All future semantic compile/native/review/gates remain due |
'''
(c/'CASE_MATRIX.md').write_text(cases)
limitations = [
    'NONINSTALLABLE intermediate source packet. Actual central private source/progress/slot/current-state/generic provider callbacks and Store V4 are not complete.',
    'Ledger pre-publication request/gate/retained-byte recipe is implemented against V10; actual Store/Router pending publisher/readback is not complete.',
    'Complete generic-directory DATA must survive metadata loss for empty/single/unpaired orphan cuts; pair-only scope is insufficient.',
    'Combined Initial partial classification/index/materialization and typed current image node/byte capacity require coherent root decision/source review; no bounds changed here.',
    'Registry critical prefix authority and consumer-complete terminal controls/checked release are external actual-issuer obligations.',
    'Static census111 is lexical main-class inventory only, masks interpolation and excludes separate nested/extension owner semantics; zero unclassified is not whole-program proof.',
    'PFP plain/MainActor callback conversion and MainActor bridges require root semantic DEBUG/nonDEBUG compilation. No module build, runtime, independent review, acceptance or gate credit.',
    'Exact reviewed live marker delta is absorbed with forward/reverse proof; its compile/native evidence does not transfer to this future source.'
]
binding = {'model':'gpt-6.1-sol','reasoningEffort':'xhigh','status':'immutable intermediate checkpoint; NOT INSTALLABLE/approval',
    'ownedWorkspace':'/Users/rentamac/.codex/worktrees/cold-ledger-continuation/AssetRounds',
    'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'baselineJSONSHA256':'cd0447e9c71b7b9bfae4e334fa42ccbd3cde51797ca9c0d2c947865ec7a1a595',
    'beforeSHA256':sha(before),'candidateSHA256':sha(candidate),'diffSHA256':sha(c/'DIFF.patch'),
    'trackedLedgerSHA256':sha(rel),'patchProof':proof,'parseOnly':parse,
    'mainClassFDCensusSHA256':sha(c/'LEGACY_FD_PATH_CENSUS_WORKING_V28.json'),
    'caseMatrixSHA256':sha(c/'CASE_MATRIX.md'),
    'dependencies':{'capturedSlotGetter':'7da5496de5321bf772b7cac989df424d24fd584edbb343278899f0d254e95c37',
        'freshCurrentRecordGetter':'e2f4dc2b3267ba1b84733c309cb6cd0552aa1e8ce9a46b836844ba7b11a6a3c1',
        'sealedGenericV9Scope':'16941bbbe09b68b008a2fad54783f4a7f0dc4fb1aa0194650ee3a3e219ecdc5f',
        'PFPSealedGenericSource':'fb3020533cfe03022e9d590984f7ae19a386debc95f4ecb1777fc538b5b2daeb',
        'PFPV9DependencyBinding':'cf6c0899acdba2e58bb26f1f8c0f078374c4fdab3a75bafd686e0ee56608a1ac',
        'pendingRequestShape':'be527834e2ff704575672a61006ab37f46babe0ec577359d8970283f8cce4617',
        'pendingGetterReceipt':'9ecad48670b7ffcd038642f5d7575d3129bd33e747926be5ea28389faa667a03',
        'liveReviewedDiff':'cd2bfb12188ac98151d420bd15b82e89a4cf281344de54eaac7cd1b29ea68d0d',
        'actualLedgerInterface':'7a9992908692767c85d2f237e0e496837f8a68e4ff336eb77e3a6f19c03857bc'},
    'limitations':limitations}
(c/'BINDING.json').write_text(json.dumps(binding,indent=2)+'\n')
(c/'HANDOFF.md').write_text('# Ledger checkpoint v28 handoff\n\nActual GPT-6.1 Sol xhigh; sole owned ignored Ledger candidate. Source '+sha(candidate)+'. Baseline '+sha(before)+'. Tracked Ledger remains exact baseline. All historical packets and parse failures are preserved.\n\nThis checkpoint adds required fresh generic providers, distinct sealed generic pair/single and consumed-original provenance, main/nested raw I/O brackets, deterministic errno preservation, and permanent lifetime fences. Forward/reverse unified patch proofs are exact; DEBUG/nonDEBUG isolated syntax parses pass. No semantic compilation/runtime or acceptance result is claimed.\n\nRemaining work:\n\n'+''.join('- '+item+'\n' for item in limitations)+'\nRoot alone composes/reviews/builds/tests/imports/commits/pushes/dispatches. Continue from the mutable candidate for complete generic-directory provenance/current capacity and actual callback composition; do not modify this checkpoint.\n')
manifest = {str(p.relative_to(c)):sha(p) for p in sorted(c.rglob('*')) if p.is_file()}
(c/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
for p in c.rglob('*'):
    if p.is_file(): p.chmod(0o444)
print(json.dumps({'candidateSHA256':sha(candidate),'bindingSHA256':sha(c/'BINDING.json'),
    'diffSHA256':sha(c/'DIFF.patch'),'handoffSHA256':sha(c/'HANDOFF.md'),'caseMatrixSHA256':sha(c/'CASE_MATRIX.md'),
    'manifestSHA256':sha(c/'MANIFEST.json'),'patchProof':proof},indent=2))
