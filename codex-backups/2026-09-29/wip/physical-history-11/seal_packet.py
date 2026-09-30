from pathlib import Path
import hashlib,json,difflib,subprocess,os
workspace=Path(__file__).resolve().parents[2]
packet=Path(__file__).resolve().parent
owned='FieldEvidenceApp/Infrastructure/Persistence/EraseSchema2ColdAuxiliaryFirstObservationV1.swift'
def sha(b): return hashlib.sha256(b).hexdigest()
def dump(path,obj): path.write_text(json.dumps(obj,indent=2,sort_keys=True)+'\n')
base=json.loads((packet/'SOURCE_MAP.json').read_text())
assert len(base)==1206
tracked={name:sha((workspace/name).read_bytes()) for name in base}
assert tracked==base
head=subprocess.run(['git','rev-parse','HEAD'],cwd=workspace,text=True,capture_output=True,check=True).stdout.strip()
assert head=='bcc9844fa5715ac8e3cbc4a7f47c122c07d1adb3'
status=subprocess.run(['git','status','--porcelain'],cwd=workspace,text=True,capture_output=True,check=True).stdout
assert not status.strip()
before=(packet/'before'/owned).read_bytes(); candidate=(packet/'candidate'/owned).read_bytes()
assert sha(before)==base[owned] and candidate.startswith(before)
diff=''.join(difflib.unified_diff(before.decode().splitlines(True),candidate.decode().splitlines(True),fromfile='a/'+owned,tofile='b/'+owned))
(packet/'CANDIDATE.diff').write_text(diff)
after=dict(base); after[owned]=sha(candidate); dump(packet/'AFTER_SOURCE_MAP.json',after)
parse=[]
for mode,flag in [('DEBUG',['-D','DEBUG']),('nonDEBUG',[])]:
 command=['xcrun','swiftc','-frontend','-parse',*flag,str(packet/'candidate'/owned)]
 r=subprocess.run(command,cwd=workspace,text=True,capture_output=True)
 (packet/('PARSE-'+mode+'.log')).write_text(r.stdout+r.stderr)
 parse.append({'mode':mode,'command':command,'exitCode':r.returncode,'stdoutBytes':len(r.stdout),'stderrBytes':len(r.stderr),'evidenceKind':'syntax parse only, not typecheck/compilation/link/runtime'})
 assert r.returncode==0
dump(packet/'PARSE.json',{'candidateSHA256':sha(candidate),'results':parse,'semanticCompilerRun':False,'buildRun':False,'nativeRun':False})
dump(packet/'TRACKED_UNCHANGED_AUDIT.json',{'head':head,'count':len(base),'inputMapSHA256':sha((packet/'SOURCE_MAP.json').read_bytes()),'all1206InputBytesUnchanged':tracked==base,'gitStatusPorcelain':status,'trackedSourceChanged':False,'candidateOverlayOnly':[owned],'unchangedBaselineBytePrefix':True,'afterMapIsUninstalledSingleFileOverlay':True})
# Inventory all owned packet directories. This does not modify or delete any
# historical cold packet. Live self-index/binding are excluded to avoid cycles.
broad=Path('/Users/rentamac/.codex/worktrees/cold-physical-continuation/AssetRounds/.codex-temp')
roots=[x for x in sorted(broad.iterdir()) if x.is_dir() and (x.name.startswith('cold-physical-') or x.name.startswith('cold-target-semantic-context-'))]+[packet]
ignore={'OWNED_PACKET_INVENTORY.json','BINDING.json'}
inv=[]
for root in roots:
 files=[]
 for file in sorted(root.rglob('*')):
  if not file.is_file() or (root==packet and file.name in ignore): continue
  b=file.read_bytes(); files.append({'path':str(file),'relativePath':str(file.relative_to(root)),'sha256':sha(b),'bytes':len(b),'modeBeforeThisSeal':oct(file.stat().st_mode & 0o777)})
 inv.append({'packetPath':str(root),'status':'preserved unpublished WIP; see own immutable handoff for exact scope; no full runtime acceptance','fileCount':len(files),'bytes':sum(x['bytes'] for x in files),'files':files})
dump(packet/'OWNED_PACKET_INVENTORY.json',{'author':'GPT-6.1 Sol xhigh','preservation':'No prior packet bytes removed or changed; no Git mutation','inventoryDoesNotSelfHash':True,'packetCount':len(inv),'fileCount':sum(x['fileCount'] for x in inv),'packets':inv})
files={str(x.relative_to(packet)):sha(x.read_bytes()) for x in sorted(packet.rglob('*')) if x.is_file() and x.name!='BINDING.json'}
dump(packet/'BINDING.json',{'status':'NONINSTALLABLE WIP checkpoint, syntax parse only','model':'gpt-6.1-sol','reasoningEffort':'xhigh','baseHead':head,'baseSourceMapSHA256':sha((packet/'SOURCE_MAP.json').read_bytes()),'candidateSHA256':sha(candidate),'candidatePath':owned,'afterSingleFileOverlayMapSHA256':sha((packet/'AFTER_SOURCE_MAP.json').read_bytes()),'changedFileCount':1,'beforeSHA256':sha(before),'completeBaselinePreservedAsBytePrefix':True,'parseOnly':True,'rootRequired':['complete coupled actual engine/issuer/role implementation','independent Sol6.1 xhigh source review','semantic compiler/full build','affected native verification','all required gates'],'files':files})
for x in packet.rglob('*'):
 if x.is_file(): x.chmod(0o444)
print(json.dumps({'candidateSHA256':sha(candidate),'bindingSHA256':sha((packet/'BINDING.json').read_bytes()),'inventorySHA256':sha((packet/'OWNED_PACKET_INVENTORY.json').read_bytes()),'handoffSHA256':sha((packet/'HANDOFF.md').read_bytes()),'afterMapSHA256':sha((packet/'AFTER_SOURCE_MAP.json').read_bytes()),'packetCount':len(inv),'fileCount':sum(x['fileCount'] for x in inv),'parseExitCodes':[x['exitCode'] for x in parse],'trackedUnchanged':True},indent=2))
