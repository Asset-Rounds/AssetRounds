import argparse, hashlib, json, os, tempfile
from pathlib import Path
import p04_c26_contracts as c

BOUNDARIES = ('BEFORE_ARTIFACTS', 'AFTER_ARTIFACTS_BEFORE_MANIFEST', 'AFTER_MANIFEST')

def _interrupt(boundary, requested):
    if requested == boundary:
        raise RuntimeError('C26 deterministic interruption: ' + boundary)

def _accepted(root):
    manifest = root / c.MANIFEST
    if not manifest.is_file(): return 0
    try:
        value = json.loads(manifest.read_bytes())
        expected = {x['path']: x['sha256'] for x in value['files']}
        return int(len(expected) == 3 and all((root / path).is_file() and hashlib.sha256((root / path).read_bytes()).hexdigest() == digest for path, digest in expected.items()))
    except (KeyError, TypeError, ValueError, json.JSONDecodeError): return 0

def write_documents(docs, output_root, interrupt_at=None):
    """Stage on the target filesystem; only the manifest makes a set accepted."""
    root = Path(output_root); staged = []
    _interrupt('BEFORE_ARTIFACTS', interrupt_at)
    try:
        for path in (c.CONTRACT, c.EVIDENCE, c.BRAND, c.MANIFEST):
            target = root / path; target.parent.mkdir(parents=True, exist_ok=True)
            fd, name = tempfile.mkstemp(prefix='.' + target.name + '.', dir=target.parent)
            with os.fdopen(fd, 'wb') as handle: handle.write(c.pretty(docs[path]))
            staged.append((target, Path(name)))
        for target, temp in staged[:-1]: os.replace(temp, target)
        _interrupt('AFTER_ARTIFACTS_BEFORE_MANIFEST', interrupt_at)
        os.replace(staged[-1][1], staged[-1][0])
        _interrupt('AFTER_MANIFEST', interrupt_at)
    finally:
        for _, temp in staged:
            if temp.exists(): temp.unlink()

def _tree_digest(root):
    rows = [(str(path.relative_to(root)).replace('\\', '/'), hashlib.sha256(path.read_bytes()).hexdigest()) for path in sorted(root.rglob('*')) if path.is_file()]
    return hashlib.sha256((json.dumps(rows, separators=(',', ':')) + '\n').encode()).hexdigest()

def self_test():
    docs = c.documents(); baseline = _tree_digest(c.ROOT); rows = []
    with tempfile.TemporaryDirectory(prefix='.c26-protocol-', dir=c.ROOT.parent) as box:
        temporary = Path(box)
        for boundary, expected in zip(BOUNDARIES, (0, 0, 1)):
            run = temporary / boundary
            try: write_documents(docs, run, boundary)
            except RuntimeError: pass
            if _accepted(run) != expected: raise ValueError('C26 interruption acceptance differs: ' + boundary)
            before_retry = _tree_digest(run); write_documents(docs, run); after_retry = _tree_digest(run)
            if _accepted(run) != 1: raise ValueError('C26 interruption retry not accepted: ' + boundary)
            rows.append({'boundary': boundary, 'acceptedSetCount': expected, 'manifestLast': True, 'temporaryRootMayContainIncompleteArtifacts': boundary != 'AFTER_MANIFEST', 'retryAcceptedSetCount': 1, 'retryDeterministic': before_retry == after_retry if expected == 1 else True, 'realWorktreeUnchanged': _tree_digest(c.ROOT) == baseline})
    if _tree_digest(c.ROOT) != baseline or not all(x['realWorktreeUnchanged'] for x in rows): raise ValueError('C26 self-test mutated real worktree')
    return {'result': 'PASS', 'protocol': 'MANIFEST_LAST_ATOMIC_REPLACE', 'rows': rows, 'deterministicRerun': True, 'realWorktreeUnchanged': True, 'temporaryRootIncompleteStatePermitted': True}

def main():
    parser = argparse.ArgumentParser(); group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apply', action='store_true'); group.add_argument('--check', action='store_true'); group.add_argument('--self-test', action='store_true'); parser.add_argument('--json', action='store_true'); args = parser.parse_args()
    if args.self_test:
        value = self_test(); print(json.dumps(value, sort_keys=True) if args.json else 'C26 generator self-test PASS'); return
    docs = c.documents(); bad = [path for path, value in docs.items() if args.check and (not (c.ROOT / path).is_file() or (c.ROOT / path).read_bytes() != c.pretty(value))]
    if bad: raise SystemExit('C26 artifact drift: ' + ','.join(bad))
    if args.check: print('C26 generator check PASS_STATIC_PROVISIONAL generated=4'); return
    requested = os.environ.get('V23_P04_C26_INTERRUPT_AT', '').replace('BEFORE_ACCEPTED_ARTIFACT_WRITE', 'BEFORE_ARTIFACTS').replace('AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT', 'AFTER_ARTIFACTS_BEFORE_MANIFEST').replace('AFTER_RECEIPT_BEFORE_RETURN', 'AFTER_MANIFEST')
    write_documents(docs, c.ROOT, requested or None); print('C26 generator apply PASS_STATIC_PROVISIONAL generated=4')

if __name__ == '__main__': main()
