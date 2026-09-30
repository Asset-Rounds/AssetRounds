from pathlib import Path
import hashlib,json,os,stat
from datetime import datetime,timezone

base=Path('/Users/rentamac/.codex/worktrees/cold-control-continuation/AssetRounds/.codex-temp')
out=base/'cold-control-backup-handoff-v1'
packets=[
 ('cold-control-author-baseline-v1','Historical author baseline and exact source maps; no acceptance.'),
 ('cold-control-continuation-successor-v1','Frozen V3 plus preserved earlier source versions. Independent V3 review BLOCK: compile-risk, descriptor fences and lawful-population capacity.'),
 ('cold-control-continuation-successor-v4','Frozen narrow V4 source draft b3a2; incomplete/noninstallable; not a reviewed execution candidate.'),
 ('cold-control-contract-v4-v1','Working V4 segmented contract, capacity arithmetic, schemas and API prototypes, with immutable READ7028 and exact counterpart inputs. No concrete V4 Store codec/publisher/private issuers; not a final agreed/reviewed contract.')
]
objects=out/'objects'
objects.mkdir()
rows=[]
by_sha={}
packet_rows=[]
sha=lambda b:hashlib.sha256(b).hexdigest()
for name,status in packets:
 root=base/name
 count=total=0
 for p in sorted(root.rglob('*')):
  if p.is_dir():continue
  before=p.lstat()
  if not stat.S_ISREG(before.st_mode):raise RuntimeError('Nonregular entry: '+str(p))
  b=p.read_bytes()
  after=p.lstat()
  if (before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns,before.st_ctime_ns)!=(after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns,after.st_ctime_ns):
   raise RuntimeError('Changed during capture: '+str(p))
  h=sha(b)
  dest=objects/h
  if not dest.exists():
   with dest.open('xb') as f:f.write(b)
   os.chmod(dest,0o444)
  if sha(dest.read_bytes())!=h:raise RuntimeError('Object readback mismatch')
  if sha(p.read_bytes())!=h:raise RuntimeError('Source changed after capture')
  relative=str(p.relative_to(root))
  row={'packet':name,'relativePath':relative,'sourcePath':str(p),'restorePath':str(p),'snapshotObjectPath':str(dest),'archiveObjectRelativePath':'objects/'+h,'sha256':h,'byteCount':len(b),'originalMode':oct(stat.S_IMODE(before.st_mode)),'originalModifiedNanoseconds':before.st_mtime_ns}
  rows.append(row);by_sha.setdefault(h,[]).append(row)
  count+=1;total+=len(b)
 packet_rows.append({'name':name,'sourceRoot':str(root),'status':status,'fileCount':count,'logicalByteCount':total})
# Fresh full source equality check before sealing the mapping.
for r in rows:
 if sha(Path(r['sourcePath']).read_bytes())!=r['sha256']:raise RuntimeError('Final source mismatch: '+r['sourcePath'])
created=datetime.now(timezone.utc).isoformat()
inv={'schemaVersion':1,'createdUTC':created,'scope':'Owned broad Store controls only; root alone publishes the archival GitHub backup.','evidenceClass':'DEVELOPMENT / source inventory only','githubBackupVerified':False,'trackedFilesModified':False,'sourceRoots':packet_rows,'fileCount':len(rows),'logicalByteCount':sum(r['byteCount'] for r in rows),'distinctObjectCount':len(by_sha),'distinctObjectByteCount':sum(Path(objects/h).stat().st_size for h in by_sha),'files':rows,'restoreAlgorithm':'For each row, verify SHA-256 and byteCount of archiveObjectRelativePath, create the original restorePath parents, copy exact bytes, restore originalMode. OriginalModifiedNanoseconds is recorded for audit and is not product filesystem evidence. Never replace active work without root coordination.'}
(out/'INVENTORY.json').write_text(json.dumps(inv,indent=2)+'\n')
groups={'schemaVersion':1,'deduplication':'Content-addressed snapshot only. Original source packets and every logical restore path remain intact. No deletion or reclamation is authorized by this inventory.','groups':[{'sha256':h,'byteCount':Path(objects/h).stat().st_size,'objectRelativePath':'objects/'+h,'restorePaths':[r['restorePath'] for r in rs]} for h,rs in sorted(by_sha.items())]}
(out/'CONTENT_GROUPS.json').write_text(json.dumps(groups,indent=2)+'\n')
store_versions=[r for r in rows if r['relativePath'].endswith('EraseIntentStore.swift')]
versions={'schemaVersion':1,'versions':store_versions,'note':'These are exact source versions. None is inferred compiled, installed, runtime-qualified, approved or a gate result.'}
(out/'STORE_VERSIONS.json').write_text(json.dumps(versions,indent=2)+'\n')
text='''# Broad Store archival handoff

This sealed content-addressed snapshot preserves the owned broad Store baseline, frozen V3/V4 drafts, current V4 contract work, READ7028, wire schemas, capacity arithmetic, terminal/API prototypes and exact copied counterpart input fragments. It is incomplete and noninstallable. It conveys no semantic compilation, runtime, independent source approval or gate credit.

Root alone publishes and verifies the separate archival GitHub backup. `INVENTORY.json` records each absolute source/restore path, exact SHA-256, byte count, original mode and snapshot object. `CONTENT_GROUPS.json` records content equality without deleting or changing any original file. `STORE_VERSIONS.json` names every preserved Store source version. Snapshot objects are immutable; ongoing contract work may continue at the original paths after this boundary.

V3 remains frozen and BLOCKED by review728679: two compile-risk findings, permanent descriptor fencing and mixed lawful-population capacity. The narrow V4 draft remains frozen and uninstalled. The current V4 packet is a working segmented binary contract and pure API prototype packet. Its READ interface is immutable SHA7028aba3b6e7f2c3013dd1d35747c73d27d2238bec3e07a94ad1d4ae94518669. New effect framing is a pending agreement; its prototype is preserved rather than claimed approved.

Outstanding work includes actual bounded codec and checked publisher, authentic bootstrap/source/progress/pending-birth admissions, real private Router/Service/Registry/consumer-complete/semantic-target producers, complete fresh terminal OS and every deletion-prefix reproof, permanent Store/first-held observer close fences, genuine full legacy fallback and historical lost-source disposition, whole coupled heap/work proof, root-only coupled typecheck/build/runtime/fault/capacity verification and all unchanged gates. A decoded control or digest never issues OS, drain, retirement, alias-policy, ready or completion authority.

The capture performed only file reads, content copies to this ignored snapshot, hashes and immutable snapshot metadata. It did not modify tracked Store/source, original packets, Products, tests, CI, docs, Git refs/index, evidence or owner drafts. It performed no compiler, native test, Git publication or deletion. Local hash equality is not verified GitHub backup.

Restore using the inventory mapping after root coordinates with any active work: verify each archived object SHA/count, copy it to the recorded restore path and restore the recorded mode. Keep every distinct version and all logical paths. Do not reset Git, prune, reclaim originals or infer disposal eligibility from duplicate content.
'''
(out/'HANDOFF.md').write_text(text)
manifest_rows=[]
for p in sorted(out.rglob('*')):
 if p.is_file() and p.name not in ('MANIFEST.json','BINDING.json'):
  b=p.read_bytes();manifest_rows.append({'relativePath':str(p.relative_to(out)),'sha256':sha(b),'byteCount':len(b)})
manifest={'schemaVersion':1,'createdUTC':created,'files':manifest_rows}
(out/'MANIFEST.json').write_text(json.dumps(manifest,indent=2)+'\n')
binding={'schemaVersion':1,'createdUTC':created,'snapshotRoot':str(out),'sourceEvidence':'DEVELOPMENT / archival source inventory; incomplete/noninstallable; no semantic compile/runtime/gate approval','githubBackupVerified':False,'files':{name:{'sha256':sha((out/name).read_bytes()),'byteCount':(out/name).stat().st_size} for name in ('INVENTORY.json','CONTENT_GROUPS.json','STORE_VERSIONS.json','HANDOFF.md','MANIFEST.json','seal_backup.py')},'sourceFileCount':len(rows),'sourceLogicalByteCount':inv['logicalByteCount'],'distinctObjectCount':len(by_sha),'distinctObjectByteCount':inv['distinctObjectByteCount']}
(out/'BINDING.json').write_text(json.dumps(binding,indent=2)+'\n')
for p in out.rglob('*'):
 if p.is_file():os.chmod(p,0o444)
print(json.dumps({'snapshotRoot':str(out),'bindingSHA256':sha((out/'BINDING.json').read_bytes()),'inventorySHA256':sha((out/'INVENTORY.json').read_bytes()),'manifestSHA256':sha((out/'MANIFEST.json').read_bytes()),'sourceFileCount':len(rows),'sourceLogicalBytes':inv['logicalByteCount'],'distinctObjects':len(by_sha),'snapshotObjectBytes':inv['distinctObjectByteCount'],'storeVersions':[{k:r[k] for k in ('sourcePath','sha256','byteCount')} for r in store_versions]},indent=2))
