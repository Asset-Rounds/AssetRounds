from pathlib import Path
import hashlib,json,difflib,subprocess
root=Path.cwd();p=root/'.codex-temp/cold-physical-continuation-successor-v3';prior=root/'.codex-temp/cold-physical-continuation-successor-v2'
paths=['FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift','FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift']
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def writejson(path,data):path.write_text(json.dumps(data,sort_keys=True,indent=2)+'\n')
basePath=root/'.codex-temp/cold-physical-author-baseline-v1/SOURCE_MAP.json';base=json.loads(basePath.read_text());drift={path:sha(root/path) for path,h in base.items() if sha(root/path)!=h}
assert not drift and len(base)==1206
candidates={path:{'publishedBeforeSHA256':base[path],'immediateBeforeSHA256':sha(prior/'candidate'/path),'candidateSHA256':sha(p/'candidate'/path),'bytes':(p/'candidate'/path).stat().st_size} for path in paths}
after={**base,**{path:candidates[path]['candidateSHA256'] for path in paths}}
writejson(p/'AFTER_SOURCE_MAP.json',after)
for diffName,beforeRoot in [('CANDIDATE.diff',root),('SUCCESSOR.diff',prior/'candidate')]:
 text=''.join(''.join(difflib.unified_diff((beforeRoot/path).read_text().splitlines(keepends=True),(p/'candidate'/path).read_text().splitlines(keepends=True),fromfile='a/'+path,tofile='b/'+path)) for path in paths)
 (p/diffName).write_text(text)
external={
 'firstCaptureScope':('/Users/rentamac/.codex/worktrees/live-notification-absence/AssetRounds/.codex-temp/live-notification-completed-retry-successor-v1/FIRST_CAPTURE_SCOPE_INTERFACE_V1.swift.fragment','0d161f89031b17c3e87940126ba6f889a6f1da4d2533d05e3529d507b800ab8c'),
 'fourthPFP':('/Users/rentamac/.codex/worktrees/cold-pair-policy/AssetRounds/.codex-temp/cold-pair-policy-firstcapture-successor-v1/candidate/ProtectedFilePolicy.swift','330938cb61f5c5e1c3c7b8655f7603af31e8f15e1ff890542940a802678aa6bd'),
 'borrowedManifestSource':('/Users/rentamac/.codex/worktrees/live-notification-absence/AssetRounds/.codex-temp/live-notification-completed-retry-successor-v1/owner-stop-handoff-v1/candidate/FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift','2f04739ec4da6b2085f207ca6be181f24ab0842dfb2a326376e5c06ccb1ae2a9'),
 'liveFunctionalObserverBefore':('/Users/rentamac/.codex/worktrees/live-notification-absence/AssetRounds/.codex-temp/live-notification-absence-successor-v2/candidate/FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift','ad95d26b481a864a3f5f6b45a5f2917d790f703af59cbb0f742e85c0d6d40d1b')}
for name,(path,expected) in external.items():assert sha(Path(path))==expected,(name,path)
writejson(p/'SOURCE_SUCCESSION.json',{'sourceOnly':True,'publishedHead':'93159755395d697a5a9da02f41374120433c50f9','immediateParentBindingSHA256':sha(prior/'BINDING.json'),'physicalFrozenInputBindingSHA256':'eaa6b26f558bdff78085658b78643f6c22965eab097d554b4411041cab846be6','candidates':candidates,'externalDependencies':{k:{'path':path,'sha256':h,'authenticIssuerOrRuntimeClaim':False} for k,(path,h) in external.items()}})
(p/'WORKING_HANDOFF.md').write_text('V3 is now sealed. See HANDOFF.md and BINDING.json. This is source-only NONINSTALLABLE companion work, not runtime or approval evidence. Further corrections use a unique successor.\n')
artifactNames=['AFTER_SOURCE_MAP.json','CANDIDATE.diff','SUCCESSOR.diff','PARSE.json','SOURCE_SUCCESSION.json','INTERFACES.md','CASE_MATRIX.md','RECORDED_ROOT_CENSUS_V3.md','HANDOFF.md']
writejson(p/'BINDING.json',{'schemaVersion':3,'status':'sealed_source_only_NONINSTALLABLE_authentic_companion_prerequisites_due','authorModel':'gpt-6.1-sol','reasoningEffort':'xhigh','head':'93159755395d697a5a9da02f41374120433c50f9','sourceInputs':len(base),'parentBindingSHA256':sha(prior/'BINDING.json'),'beforeFullSourceMapSHA256':sha(basePath),'afterFullSourceMapSHA256':sha(p/'AFTER_SOURCE_MAP.json'),'candidates':candidates,'artifacts':{name:sha(p/name) for name in artifactNames},'trackedSourceDrift':drift,'openObligations':['Root/reviewer frozen physical budget interpretation for exact typed sameinode aliases, including payload plus metadata; current code charges each namespace entry.','Store lossless segmented controls implementation and bounded authenticated logical commitment helper.','Real Migration private FirstCapture owner and complete finite producer premises/pair decoder; fresh original and cold G/exclusion scope.','Real Router initial/bootstrap/current source/phase/progress/plan and birth role/version permit bindings, complete actual external Notification/OS/Registry/reader/drain/Manifest receipts and populated original/cold/terminal tail.','Root coupled semantic compilation/fullbuild, affected native development, independent GPT-6.1 Sol xhigh review and all five same-head gates.']})
for name in artifactNames+['BINDING.json','WORKING_HANDOFF.md']:
 (p/name).chmod(0o444)
for path in paths:(p/'candidate'/path).chmod(0o444)
print(json.dumps({'bindingSHA256':sha(p/'BINDING.json'),'candidates':{path:candidates[path]['candidateSHA256'] for path in paths},'beforeMapSHA256':sha(basePath),'afterMapSHA256':sha(p/'AFTER_SOURCE_MAP.json'),'trackedSourceDrift':drift,'parseSHA256':sha(p/'PARSE.json')},sort_keys=True))
