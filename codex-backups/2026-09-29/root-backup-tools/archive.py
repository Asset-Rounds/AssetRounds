#!/usr/bin/env python3
"""Root-only archival source checkpoint; no app installation or cleanup effects."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import subprocess
import time

PACKET = Path(__file__).resolve().parent
REPO = PACKET.parent.parent
PLAN = PACKET / 'PLAN.json'

def sha(data):
    return hashlib.sha256(data).hexdigest()

def write_json(path, value):
    if path.exists():
        raise RuntimeError('refusing overwrite: ' + str(path))
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')

def git(*args, data=None, repo=REPO, index=None):
    env = os.environ.copy()
    if index:
        env['GIT_INDEX_FILE'] = str(index)
    return subprocess.run(['git', '-c', 'gc.auto=0', '-c', 'maintenance.auto=false',
        '-C', str(repo), *args], input=data, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=env, check=True).stdout

def clean_path(value):
    p = PurePosixPath(value)
    if p.is_absolute() or not p.parts or any(x in ('', '.', '..') for x in p.parts):
        raise RuntimeError('unsafe archive path: ' + value)
    if any(c in value for c in ('\n', '\r', '\0', '\t', '"', '\\')):
        raise RuntimeError('unsupported path: ' + value)
    return value

def facts(p):
    s = p.lstat()
    return dict(mode=stat.S_IMODE(s.st_mode), uid=s.st_uid, gid=s.st_gid,
                size=s.st_size, mtime_ns=s.st_mtime_ns, ctime_ns=s.st_ctime_ns,
                dev=s.st_dev, inode=s.st_ino, flags=s.st_flags,
                kind='file' if stat.S_ISREG(s.st_mode) else
                     'dir' if stat.S_ISDIR(s.st_mode) else 'unsupported')

def census(root):
    # Reject links at every level. Never follow symlinks or archive special files.
    root = Path(root)
    if facts(root)['kind'] != 'dir':
        raise RuntimeError('scope root not a real directory: ' + str(root))
    out = {'.': facts(root)}
    for d, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            p = Path(d) / name
            f = facts(p)
            if f['kind'] == 'unsupported':
                raise RuntimeError('special file or symlink: ' + str(p))
            out[clean_path(p.relative_to(root).as_posix())] = f
    return out

def read_file(path):
    before = facts(path)
    if before['kind'] != 'file' or before['size'] >= 100_000_000:
        raise RuntimeError('not a bounded source file: ' + str(path))
    # lstat/open/fstat guard prevents a changed or redirected source from entering the archive.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        s = os.fstat(fd)
        if (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns) != tuple(
                before[k] for k in ('dev', 'inode', 'size', 'mtime_ns', 'ctime_ns')):
            raise RuntimeError('changed source at open: ' + str(path))
        with os.fdopen(fd, 'rb', closefd=False) as f:
            data = f.read()
        if facts(path) != before or len(data) != before['size']:
            raise RuntimeError('changed source during read: ' + str(path))
    finally:
        os.close(fd)
    oid = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
    return before, sha(data), oid

def verify_blobs(entries, repo=REPO):
    wanted = {}
    for row in entries:
        pair = (row['size'], row['sha256'])
        if row['blob'] in wanted and wanted[row['blob']] != pair:
            raise RuntimeError('inconsistent blob identity')
        wanted[row['blob']] = pair
    proc = subprocess.Popen(['git', '-C', str(repo), 'cat-file', '--batch'],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for oid, (size, digest) in sorted(wanted.items()):
            proc.stdin.write((oid + '\n').encode()); proc.stdin.flush()
            header = proc.stdout.readline().decode().rstrip('\n').split()
            if header != [oid, 'blob', str(size)]:
                raise RuntimeError('blob unavailable: ' + oid)
            h = hashlib.sha256(); remaining = size
            while remaining:
                chunk = proc.stdout.read(min(remaining, 1024 * 1024))
                if not chunk:
                    raise RuntimeError('short blob: ' + oid)
                h.update(chunk); remaining -= len(chunk)
            if proc.stdout.read(1) != b'\n' or h.hexdigest() != digest:
                raise RuntimeError('blob content mismatch: ' + oid)
        proc.stdin.close()
        if proc.wait() != 0:
            raise RuntimeError('cat-file failed')
    finally:
        if proc.poll() is None:
            proc.kill(); proc.wait()
    return len(wanted)

def capture():
    plan_bytes = PLAN.read_bytes(); plan = json.loads(plan_bytes)
    base = plan['base']; prefix = clean_path(plan['prefix'])
    if git('rev-parse', 'HEAD').decode().strip() != base:
        raise RuntimeError('primary head moved')
    for name in ('MANIFEST.json', 'TREE.json', 'archive.index'):
        if (PACKET / name).exists():
            raise RuntimeError('capture already started: ' + name)
    rows = []; scopes = []; archived = set(); captured_dirs = {}

    def add_file(key, root, rel, expected=None):
        rel = clean_path(rel); target = clean_path(prefix + '/' + key + '/' + rel)
        if target in archived:
            raise RuntimeError('duplicate archive path')
        path = Path(root) / rel
        f, digest, oid = read_file(path)
        if expected and (digest != expected['sha256'] or f['size'] != expected['byteCount']):
            raise RuntimeError('author manifest mismatch: ' + str(path))
        rows.append(dict(scope=key, original=str(path), archive=target,
                         sha256=digest, blob=oid, gitMode='100755' if f['mode'] & 0o111 else '100644', **f))
        archived.add(target)

    for key, root, kind in plan['scopes']:
        clean_path(key); root = Path(root)
        before = census(root); captured_dirs[str(root)] = before
        expected = None; input_digest = None
        if kind == 'obsolete-materialized-source':
            input_path = root.parent / 'INPUTS.json'
            input_bytes = input_path.read_bytes(); input_digest = sha(input_bytes)
            expected = json.loads(input_bytes)
            if not isinstance(expected, dict) or len(expected) < 2500:
                raise RuntimeError('invalid historical source manifest')
            actual = {p for p, f in before.items() if f['kind'] == 'file'}
            missing = set(expected) - actual
            extras = actual - set(expected)
            if missing or any(not (p.startswith('Scripts/__pycache__/') and p.endswith('.pyc')) for p in extras):
                raise RuntimeError('historical census mismatch: ' + key)
            # The bound INPUTS bytes are stored separately without copying the source tree.
            f, digest, oid = read_file(input_path)
            target = prefix + '/historical-inputs/' + root.parent.name + '-INPUTS.json'
            rows.append(dict(scope='historical-inputs', original=str(input_path), archive=target,
                             sha256=digest, blob=oid, gitMode='100644', **f)); archived.add(target)
        for rel, f in sorted(before.items()):
            if f['kind'] == 'file':
                add_file(key, root, rel)
                if expected and rel in expected and rows[-1]['sha256'] != expected[rel]:
                    raise RuntimeError('historical source hash mismatch: ' + rel)
        if census(root) != before:
            raise RuntimeError('source changed while capturing: ' + str(root))
        scopes.append(dict(key=key, root=str(root), classification=kind, census=before,
                           inputSHA256=input_digest))

    for scope in plan.get('listedScopes', []):
        key = clean_path(scope['key']); root = Path(scope['root'])
        data = Path(scope['manifest']).read_bytes()
        if sha(data) != scope['manifestSHA256']:
            raise RuntimeError('author manifest changed')
        for row in json.loads(data)['files']:
            rel = clean_path(row['path'])
            if str(root / rel) != row['absolutePath'] or row['restoreAbsolutePath'] != row['absolutePath']:
                raise RuntimeError('author manifest restore mapping mismatch')
            add_file(key, root, rel, row)
        scopes.append(dict(key=key, root=str(root), classification='immutable-listed-WIP-no-cleanup',
                           authorManifest=scope['manifest'], authorManifestSHA256=sha(data)))

    for value in plan['currentRecords']:
        path = Path(value)
        add_file('current-records', path.parent, path.name)
    for filename in ('PLAN.json', 'archive.py', 'README.md'):
        add_file('root-backup-tools', PACKET, filename)

    # Author inventories bind all historical references, rather than archiving references alone.
    by_original = {r['original']: r for r in rows}
    for inventory in plan.get('authorInventories', []):
        raw = Path(inventory['path']).read_bytes()
        if sha(raw) != inventory['sha256']:
            raise RuntimeError('author inventory changed')
        for packet in json.loads(raw)['packets']:
            expected = packet['files']
            expected = expected.items() if isinstance(expected, dict) else (
                (r['path'], r['sha256']) for r in expected)
            for path, digest in expected:
                if path not in by_original or by_original[path]['sha256'] != digest:
                    raise RuntimeError('author historical bytes not archived: ' + path)

    manifest = dict(schema='v23-source-archival-checkpoint.v1', createdUnix=time.time(),
                    base=base, prefix=prefix, branch=plan['branch'], planSHA256=sha(plan_bytes),
                    acceptance=False, releaseReady=False,
                    scope='Immutable snapshots of source/WIP bytes and file modes; not all future edits; no binary build/evidence archive.',
                    restoreLimitations='Bytes and POSIX modes are restorable. Finder/xattrs/ACLs/ownership/document IDs are not restored by this tool. Flagged config remains local.',
                    files=rows, scopes=scopes)
    write_json(PACKET / 'MANIFEST.json', manifest)
    # Deduplicated Git objects: no second checkout; no filters or live index changes.
    paths = ''.join(r['original'] + '\n' for r in rows).encode()
    for row in rows:
        if any(c in row['original'] for c in ('\n', '\r', '"', '\\')):
            raise RuntimeError('unsupported Git stdin path')
    oids = git('hash-object', '-w', '--no-filters', '--stdin-paths', data=paths).decode().splitlines()
    if oids != [r['blob'] for r in rows]:
        raise RuntimeError('Git source bytes changed')
    unique = verify_blobs(rows)
    for root, before in captured_dirs.items():
        if census(root) != before:
            raise RuntimeError('snapshot changed before tree freeze: ' + root)
    mf = PACKET / 'MANIFEST.json'
    moid = git('hash-object', '-w', '--no-filters', str(mf)).decode().strip()
    index = PACKET / 'archive.index'
    git('read-tree', base, index=index)
    lines = [f"{r['gitMode']} {r['blob']}\t{r['archive']}\0".encode() for r in rows]
    lines.append(f'100644 {moid}\t{prefix}/MANIFEST.json\0'.encode())
    git('update-index', '-z', '--index-info', data=b''.join(lines), index=index)
    tree = git('write-tree', index=index).decode().strip()
    if git('rev-parse', 'HEAD').decode().strip() != base:
        raise RuntimeError('primary head changed before seal')
    write_json(PACKET / 'TREE.json', dict(base=base, tree=tree, branch=plan['branch'],
               manifestSHA256=sha(mf.read_bytes()), manifestBlob=moid, fileCount=len(rows),
               uniqueBlobs=unique, sourceOnly=True, acceptance=False, releaseReady=False))
    print(json.dumps(dict(tree=tree, fileCount=len(rows), uniqueBlobs=unique,
                         manifestSHA256=sha(mf.read_bytes()))))

def verify(repo, revision):
    manifest = json.loads((PACKET / 'MANIFEST.json').read_bytes())
    expected = {r['archive']:(r['gitMode'], r['blob']) for r in manifest['files']}
    prefix = manifest['prefix']
    raw_manifest = (PACKET / 'MANIFEST.json').read_bytes()
    moid = hashlib.sha1(b'blob ' + str(len(raw_manifest)).encode() + b'\0' + raw_manifest).hexdigest()
    expected[prefix + '/MANIFEST.json'] = ('100644', moid)
    actual = {}
    for entry in git('ls-tree', '-r', '-z', revision, '--', prefix, repo=repo).split(b'\0'):
        if not entry:
            continue
        head, name = entry.split(b'\t', 1); mode, kind, oid = head.decode().split()
        if kind != 'blob':
            raise RuntimeError('unexpected tree member')
        actual[name.decode()] = (mode, oid)
    if actual != expected:
        raise RuntimeError('archive tree mismatch')
    if git('show', revision + ':' + prefix + '/MANIFEST.json', repo=repo) != (PACKET / 'MANIFEST.json').read_bytes():
        raise RuntimeError('manifest bytes mismatch')
    changed = [p.decode() for p in git('diff-tree', '--no-commit-id', '--name-only', '-r', '-z',
               manifest['base'], revision).split(b'\0') if p]
    if sorted(changed) != sorted(expected):
        raise RuntimeError('tree contains changes outside archive prefix')
    unique = verify_blobs(manifest['files'], repo=repo)
    print(json.dumps(dict(revision=revision, files=len(expected), uniqueBlobs=unique, archiveClosureVerified=True)))

def restore(repo, revision, scope, destination):
    # Restore into a NEW directory only. Never overwrite working code or existing historical evidence.
    manifest = json.loads((PACKET / 'MANIFEST.json').read_bytes())
    if git('show', revision + ':' + manifest['prefix'] + '/MANIFEST.json', repo=repo) != (PACKET / 'MANIFEST.json').read_bytes():
        raise RuntimeError('restore revision does not bind this manifest')
    rows = [r for r in manifest['files'] if r['scope'] == scope]
    if not rows:
        raise RuntimeError('unknown scope')
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise RuntimeError('restore destination already exists')
    verify_blobs(rows, repo=repo)
    destination.mkdir(mode=0o700)
    prefix = manifest['prefix'] + '/' + scope + '/'
    for row in rows:
        if not row['archive'].startswith(prefix):
            raise RuntimeError('restore mapping mismatch')
        rel = clean_path(row['archive'][len(prefix):]); target = destination / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        data = git('cat-file', 'blob', row['blob'], repo=repo)
        if sha(data) != row['sha256'] or len(data) != row['size']:
            raise RuntimeError('restore content mismatch')
        with target.open('xb') as f:
            f.write(data)
        target.chmod(row['mode'])
        os.utime(target, ns=(row['mtime_ns'],row['mtime_ns']))
    selected = next((s for s in manifest['scopes'] if s['key'] == scope), None)
    if selected and 'census' in selected:
        for rel, f in sorted(selected['census'].items(), key=lambda x: len(PurePosixPath(x[0]).parts), reverse=True):
            if f['kind'] == 'dir':
                target = destination if rel == '.' else destination / rel
                target.mkdir(parents=True, exist_ok=True)
                target.chmod(f['mode']); os.utime(target, ns=(f['mtime_ns'],f['mtime_ns']))
    for row in rows:
        target = destination / row['archive'][len(prefix):]
        f, digest, oid = read_file(target)
        if (digest, oid, f['mode']) != (row['sha256'], row['blob'], row['mode']):
            raise RuntimeError('restored readback mismatch')
    print(json.dumps(dict(scope=scope, destination=str(destination), files=len(rows), bytesAndModesVerified=True,
                         noOwnershipXattrACLFlagRestoration=True)))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('capture')
    v = sub.add_parser('verify'); v.add_argument('--repo', type=Path, default=REPO); v.add_argument('--revision', required=True)
    r = sub.add_parser('restore'); r.add_argument('--repo', type=Path, default=REPO); r.add_argument('--revision', required=True)
    r.add_argument('--scope', required=True); r.add_argument('--destination', required=True)
    args = parser.parse_args()
    if args.command == 'capture': capture()
    elif args.command == 'verify': verify(args.repo, args.revision)
    else: restore(args.repo, args.revision, args.scope, args.destination)
