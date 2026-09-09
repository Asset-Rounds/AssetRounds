#!/usr/bin/env python3
"""Finite S10.4 hosted-CI controller. No native execution or formal acceptance.

The matrix and registry are runtime data. A protocol review is reusable across
heads while these tool bytes remain unchanged; every payload still qualifies at
its own exact head. Run --help for the deliberately closed command surface.
"""
from __future__ import annotations

import argparse
import contextlib
import ctypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import tarfile
import types
import uuid
import zipfile

CONTRACT = 's10.4.ci.v1'
REPO = 'Asset-Rounds/AssetRounds'
REF = 'phase/s10-brand-refresh'
WORKFLOW = 'ios-ci.yml'
PRODUCER = 's10-4-shared-build-producer'
CONSUMER = 'github-xcode-26.6-shared-build-acceptance'
ASSEMBLY = 's10-4-shared-segment-assembly'
LANES = {'producer': PRODUCER, 'consumer': CONSUMER, 'assembly': ASSEMBLY}
ACTIVE = ('queued', 'in_progress', 'requested', 'waiting', 'pending')
TOOL_PATHS = ('Scripts/s10-4-ci.py', 'Scripts/test-s10-4-ci.py')
EXTRA_SOURCE = ('docs/design/s10/s10-screen-state-inventory.json',
                'docs/design/s10/s10-accessibility-common-tasks.json')
MAX_ARCHIVE = 2 * 1024**3
MAX_EXPANDED = 8 * 1024**3
MAX_MEMBERS = 100000


class Rejected(Exception):
    pass


def require(ok, reason):
    if not ok:
        raise Rejected(reason)


def pairs(rows):
    value = {}
    for key, item in rows:
        require(key not in value, 'duplicate JSON key')
        value[key] = item
    return value


def decode(raw):
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(Rejected('nonfinite JSON')))


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True,
                      allow_nan=False).encode()


def digest(raw):
    return hashlib.sha256(raw).hexdigest().upper()


def sha(path):
    path = wide(path)
    regular(path)
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def positive(value):
    require(type(value) is int and value > 0, 'positive integer required')
    return value


def head(value):
    require(type(value) is str and re.fullmatch('[0-9a-f]{40}', value), 'invalid exact head')
    return value


def hash_value(value):
    require(type(value) is str and re.fullmatch('[0-9A-F]{64}', value), 'invalid SHA256')
    return value


def utc(value):
    require(type(value) is str, 'timestamp required')
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.utcoffset() == dt.timedelta(0), 'UTC timestamp required')
    return parsed


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')


def regular(path):
    path = wide(path)
    mode = path.lstat()
    require(stat.S_ISREG(mode.st_mode) and not stat.S_ISLNK(mode.st_mode)
            and not getattr(mode, 'st_file_attributes', 0) & 0x400, 'unsafe regular file')


def absolute(value):
    require(type(value) is str and value and not any(ord(c) < 32 for c in value), 'unsafe path')
    path = Path(value)
    require(path.is_absolute(), 'absolute path required')
    # Existing parent symlinks/junctions cannot redirect retained evidence.
    for ancestor in [path, *path.parents]:
        if ancestor.exists():
            info = ancestor.lstat()
            require(not stat.S_ISLNK(info.st_mode)
                    and not getattr(info, 'st_file_attributes', 0) & 0x400, 'linked path rejected')
    return path.resolve()


def wide(path):
    path = Path(path)
    if os.name == 'nt' and not str(path).startswith('\\\\?\\'):
        return Path('\\\\?\\' + str(path.resolve()))
    return path


def relative(value):
    require(type(value) is str and value and '\\' not in value and ':' not in value
            and not any(ord(c) < 32 for c in value), 'unsafe relative path')
    parts = value.split('/')
    require(not PurePosixPath(value).is_absolute() and all(p not in ('', '.', '..') for p in parts),
            'unsafe relative path')
    return value


def load(path):
    path = wide(path)
    regular(path)
    require(path.stat().st_size <= 64 * 1024**2, 'oversized JSON')
    return decode(path.read_bytes())


def exclusive(path, raw):
    absolute(str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def retain(path, raw):
    if path.exists():
        regular(path)
        require(path.read_bytes() == raw, 'immutable evidence collision: ' + path.name)
    else:
        exclusive(path, raw)


def save(path, value):
    retain(path, canonical(value) + b'\n')


def command(root, args):
    result = subprocess.run(args, cwd=root, capture_output=True, shell=False)
    require(result.returncode == 0, 'command failed: ' + args[0])
    return result.stdout


def gh_environment():
    # gh authenticates internally; inherited credentials never become data.
    return {k: v for k, v in os.environ.items() if k not in ('GH_DEBUG', 'DEBUG', 'GH_TRACE') and not k.startswith('GIT_TRACE')}


def git(root, *args):
    return command(root, ['git', *args])


class Source:
    """Load unchanged tracked kernels, never generated helpers or native tools."""
    def __init__(self, root, expected, snapshot=None):
        self.checkout = absolute(str(root))
        self.head = head(expected)
        self.payload = self.module('payload', self.read('Scripts/s10-4-build-payload.py'))
        shell = self.read('Scripts/s10-4-segment-assembler.sh').decode('utf-8')
        marker = "<<'S10_4_SHARED_SEGMENT_PY'\n"
        require(shell.count(marker) == 1, 'unknown source assembler interface')
        body = shell.split(marker, 1)[1].split('\nS10_4_SHARED_SEGMENT_PY', 1)[0]
        self.assembler = self.module('assembler', body.encode())
        paths = set(self.payload.SOURCE_PATHS) | set(EXTRA_SOURCE)
        self.bytes = {p: self.read(p) for p in sorted(paths)}
        self.identity = {'head': expected,
                         'gitTree': git(self.checkout, 'rev-parse', expected + '^{tree}').decode().strip(),
                         'files': {p: digest(self.bytes[p]) for p in self.payload.SOURCE_PATHS}}
        if snapshot is None:
            require(git(self.checkout, 'rev-parse', 'HEAD').decode().strip() == expected,
                    'historical read requires an immutable source snapshot directory')
            self.root = self.checkout
            for p, raw in self.bytes.items():
                require((self.root / p).read_bytes() == raw, 'working source differs from Git object')
        else:
            self.root = absolute(str(snapshot))
            for p, raw in self.bytes.items():
                retain(self.root / p, raw)  # Exact Git bytes, not generated executable logic.
        self.shards = self.payload.shard_contract(self.root)
        self.plan = load(self.root / 'Scripts/s10-4-segment-plan.json')
        selector = load(self.root / 'Scripts/ci-selection.json')
        require(selector['taskID'] == 'S10.4' and selector['tier'] == 'F25', 'selected card/tier mismatch')
        task = self.bytes['docs/execution/CURRENT_TASK.md'].decode('utf-8')
        require(task.startswith('# CURRENT TASK — S10.4 ') and
                'S10 / phase/s10-brand-refresh / S10.4 /' in task, 'S10.4 not selected')
        found = re.findall(r'Immutable S10 phase-main base: `P=([0-9a-f]{40})`', task)
        require(len(found) == 1, 'main/P authority missing or ambiguous')
        self.main = found[0]
        manifest = load(self.root / 'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json')
        shared = manifest['shared_execution_contract']
        require(shared['shard_ids'] == [s['shardID'] for s in self.shards['shards']] and
                shared['producer_unit_test_selectors'] == list(self.payload.UNIT_IDS) and
                shared['local_unit_test_count'] == 0 and shared['producer_unit_test_count'] == 5 and
                shared['one_exact_head_and_payload'] is True and shared['human_visual_review_required'] is True,
                'manifest shared contract differs from source')
        runtime = manifest['runtime_contract']
        for stem in ('shard_contract', 'screen_state_inventory'):
            require(digest(self.read(runtime[stem + '_path'])) == runtime[stem + '_sha256'], 'manifest source pin mismatch')
        base = manifest['base_authority']
        for stem in ('activation', 'runbook'):
            require(digest(self.read(base[stem + '_path'])) == base[stem + '_sha256'], 'manifest authority pin mismatch')
        self.tuples = self.inventory()

    def read(self, path):
        relative(path)
        return git(self.checkout, 'show', self.head + ':' + path)

    @staticmethod
    def module(label, raw):
        module = types.ModuleType('s10_4_ci_' + label)
        module.__file__ = '<exact Git source ' + label + '>'
        exec(compile(raw, module.__file__, 'exec'), module.__dict__)
        return module

    def context(self, shard):
        return self.assembler.plan_context(self.root, shard, allow_full=True)

    def inventory(self):
        shared = self.plan['sharedVerification']
        require(shared['executionLane'] == CONSUMER and shared['assemblyLane'] == ASSEMBLY,
                'unknown shared lanes')
        rows = [{'kind': 'producer', 'shardID': 'none', 'segmentID': 'none',
                 'provider': 'bitrise', 'dependencies': [], 'owned': 0, 'replay': 0}]
        for shard in self.shards['shards']:
            sid = shard['shardID']
            ctx = self.context(sid)
            if sid in shared['allowedShardIDs']:
                for seg in ctx['segments']:
                    rows.append({'kind': 'consumer', 'shardID': sid, 'segmentID': seg['segmentID'],
                                 'provider': 'github', 'dependencies': seg['dependencySegmentIDs'],
                                 'owned': len(seg['ownedStateIDs']), 'replay': len(seg['replayStateIDs'])})
                rows.append({'kind': 'assembly', 'shardID': sid, 'segmentID': 'none',
                             'provider': 'github', 'dependencies': [s['segmentID'] for s in ctx['segments']],
                             'owned': 67, 'replay': 0})
            else:
                self.payload.selection_contract({'shardID': sid, 'segmentID': 'none', 'purpose': 'acceptance'}, self.root)
                rows.append({'kind': 'consumer', 'shardID': sid, 'segmentID': 'none',
                             'provider': 'github', 'dependencies': [], 'owned': 67, 'replay': 0})
        require(sum(r['kind'] == 'consumer' for r in rows) == 30 and
                sum(r['kind'] == 'assembly' for r in rows) == 8, 'closed source tuple count changed')
        return rows

    def tuple(self, kind, shard, segment):
        found = [r for r in self.tuples if (r['kind'], r['shardID'], r['segmentID']) == (kind, shard, segment)]
        require(len(found) == 1, 'tuple outside finite source contract')
        return found[0]


def inputs(row, producer, dependencies):
    require(set(dependencies) == set(row['dependencies']), 'missing or extra dependency segment')
    ids = [positive(v) for v in dependencies.values()]
    require(len(ids) == len(set(ids)), 'duplicate dependency run')
    if row['kind'] == 'producer':
        require(producer is None, 'producer cannot silently replace selected payload')
    else:
        positive(producer)
    return {'execution_lane': LANES[row['kind']], 'run_ui_smoke': str(row['kind'] == 'consumer').lower(),
            's10_4_shard_id': row['shardID'], 's10_4_shared_payload_run_id': '' if producer is None else str(producer),
            's10_4_shared_segment_id': row['segmentID'],
            's10_4_segment_source_run_ids': canonical({k: str(v) for k, v in dependencies.items()}).decode() if dependencies else ''}


def returned_id(raw):
    text = raw.decode('utf-8').strip()
    match = re.fullmatch(r'https://github[.]com/Asset-Rounds/AssetRounds/actions/runs/([1-9][0-9]*)', text)
    require(match is not None, 'ambiguous/missing direct run URL; reconcile only, never redispatch')
    return int(match[1])


def run_identity(value, intent, rid):
    positive(rid)
    expected_title = 'iOS CI · lane=' + intent['inputs']['execution_lane'] + ' · shard=' + intent['shardID'] + ' · head=' + intent['head']
    require(value.get('id') == rid and value.get('head_sha') == intent['head'] and
            value.get('head_branch') == REF and value.get('path') == '.github/workflows/' + WORKFLOW and
            value.get('event') == 'workflow_dispatch' and type(value.get('run_attempt')) is int and value['run_attempt'] == 1,
            'direct run workflow/head/ref/attempt mismatch')
    require(value.get('repository', {}).get('full_name') == value.get('head_repository', {}).get('full_name') == REPO and
            value['repository']['id'] == value['head_repository']['id'], 'direct run repository mismatch')
    require(value.get('html_url') == 'https://github.com/' + REPO + '/actions/runs/' + str(rid), 'direct run URL mismatch')
    require(value.get('display_title') == expected_title, 'direct run title not yet exact or foreign')
    require(utc(value['created_at']) >= utc(intent['recordedAt']), 'returned run predates durable request')
    return value


class Transport:
    """gh owns credentials. Only workflow/API outputs are retained, never auth."""
    def __init__(self, root, output):
        self.root, self.output = root, output
        output.mkdir(parents=True, exist_ok=True)

    def execute(self, args, name):
        prefix = self.output / (name + '-' + uuid.uuid4().hex)
        try:
            result = subprocess.run(['gh', *args], cwd=self.root, capture_output=True, shell=False, env=gh_environment())
        except OSError:
            exclusive(prefix.with_suffix('.exception.txt'), b'gh process could not start\n')
            raise Rejected('gh transport failed; retained failure record') from None
        exclusive(prefix.with_suffix('.stdout'), result.stdout)
        exclusive(prefix.with_suffix('.stderr'), result.stderr)
        exclusive(prefix.with_suffix('.exit'), str(result.returncode).encode())
        require(result.returncode == 0, 'gh transport failed; retained raw response')
        return result.stdout

    def api(self, endpoint):
        require(re.fullmatch(r'[A-Za-z0-9/?=&._-]+', endpoint) and '..' not in endpoint, 'unsafe endpoint')
        return decode(self.execute(['api', 'repos/' + REPO + '/' + endpoint], 'api'))

    def pages(self, endpoint, field):
        require(re.fullmatch(r'[A-Za-z0-9/?=&._-]+', endpoint) and '..' not in endpoint, 'unsafe endpoint')
        pages = decode(self.execute(['api', '--paginate', '--slurp', 'repos/' + REPO + '/' + endpoint], 'pages'))
        require(type(pages) is list and pages, 'missing API pages')
        rows = [r for p in pages for r in p[field]]
        require(all(type(p.get('total_count')) is int and p['total_count'] == pages[0]['total_count'] for p in pages)
                and len(rows) == pages[0]['total_count'], 'incomplete/changed paginated inventory')
        require(len({positive(r['id']) for r in rows}) == len(rows), 'duplicate API identity')
        return rows

    def artifact(self, meta, destination):
        positive(meta['id'])
        expected = meta.get('sha256', meta.get('digest', '').removeprefix('sha256:')).upper()
        hash_value(expected)
        size = meta.get('bytes', meta.get('size_in_bytes'))
        require(type(size) is int and 0 < size <= MAX_ARCHIVE, 'artifact size out of bounds')
        if destination.exists():
            require(destination.stat().st_size == size and sha(destination) == expected, 'cached archive identity changed')
            return
        partial = destination.with_suffix('.download-incomplete')
        require(not partial.exists(), 'incomplete original transport retained; do not redownload automatically')
        destination.parent.mkdir(parents=True, exist_ok=True)
        with partial.open('xb') as stream:
            result = subprocess.run(['gh', 'api', 'repos/' + REPO + '/actions/artifacts/' + str(meta['id']) + '/zip'],
                                    cwd=self.root, stdout=stream, stderr=subprocess.PIPE, shell=False, env=gh_environment())
            stream.flush(); os.fsync(stream.fileno())
        exclusive(destination.with_suffix('.transport-stderr'), result.stderr)
        exclusive(destination.with_suffix('.transport-exit'), str(result.returncode).encode())
        require(result.returncode == 0 and partial.stat().st_size == size and sha(partial) == expected,
                'artifact transport/digest failed; original partial retained')
        os.rename(partial, destination)


def extract_checked(path, output):
    """Idempotent extraction; existing bytes are compared, never overwritten."""
    output = wide(output)
    absolute(str(output))
    with zipfile.ZipFile(path) as archive:
        members = archive.infolist()
        require(len(members) <= MAX_MEMBERS and sum(i.file_size for i in members) <= MAX_EXPANDED, 'ZIP expansion limit')
        seen = set()
        for item in members:
            name = item.filename.rstrip('/') if item.is_dir() else item.filename
            relative(name)
            require(item.orig_filename == item.filename and name.casefold() not in seen and not item.flag_bits & 1,
                    'unsafe/duplicate/encrypted ZIP member')
            require((item.external_attr >> 16) & 0o170000 not in (0o120000, 0o060000, 0o020000, 0o010000, 0o140000),
                    'ZIP special file rejected')
            seen.add(name.casefold())
        require(archive.testzip() is None, 'ZIP CRC mismatch')
        output.mkdir(parents=True, exist_ok=True)
        for item in members:
            target = output.joinpath(*PurePosixPath(item.filename).parts)
            absolute(str(target))
            require(target.resolve().is_relative_to(output.resolve()), 'ZIP extraction escape')
            if item.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif target.exists():
                with archive.open(item) as stream:
                    expected = hashlib.file_digest(stream, 'sha256').hexdigest().upper()
                require(target.stat().st_size == item.file_size and sha(target) == expected, 'extracted original changed')
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(item) as source, target.open('xb') as stream:
                    shutil.copyfileobj(source, stream)
        expected_files = {i.filename for i in members if not i.is_dir()}
        require({p.relative_to(output).as_posix() for p in output.rglob('*') if p.is_file()} == expected_files,
                'extra extracted original file')
    return len(members)


def manifests(root):
    root = wide(root)
    results = []
    for path in root.rglob('SHA256SUMS.txt'):
        seen = set()
        for line in path.read_text(encoding='utf-8').splitlines():
            match = re.fullmatch(r'([0-9A-Fa-f]{64})  (?:\./)?(.+)', line)
            require(match is not None, 'malformed checksum row')
            name = relative(match[2])
            require(name.casefold() not in seen, 'duplicate checksum path')
            seen.add(name.casefold())
            require(sha(path.parent / name) == match[1].upper(), 'checksum mismatch')
        expected = {p.relative_to(path.parent).as_posix().casefold() for p in path.parent.rglob('*') if p.is_file()}
        require(seen == expected - {'sha256sums.txt'}, 'partial checksum closure')
        results.append({'path': path.relative_to(root).as_posix(), 'rows': len(seen), 'sha256': sha(path)})
    return results


class Matrix:
    def __init__(self, path):
        self.path = absolute(str(path))
        self.value = load(self.path)
        required = {'schemaVersion', 'contractID', 'repository', 'ref', 'head', 'mainSHA',
                    'checkoutRoot', 'registryRoot', 'protocolReview', 'producer'}
        require(type(self.value) is dict and set(self.value) == required, 'matrix fields differ from closed schema')
        value = self.value
        require(type(value['schemaVersion']) is int and value['schemaVersion'] == 1 and value['contractID'] == CONTRACT
                and value['repository'] == REPO and value['ref'] == REF, 'matrix contract mismatch')
        self.head = head(value['head']); self.main = head(value['mainSHA'])
        self.root = absolute(value['checkoutRoot']); self.registry = absolute(value['registryRoot'])
        require(self.registry.is_relative_to(self.root / 'Temp'), 'registry must be inside checkout Temp')
        self.identity = digest(canonical(value))
        self.producer = value['producer']
        if self.producer is not None:
            require(type(self.producer) is dict and set(self.producer) ==
                    {'runID', 'sharedBuildIdentitySHA256', 'producerQualificationSHA256'}, 'producer selection schema mismatch')
            positive(self.producer['runID'])
            for key in ('sharedBuildIdentitySHA256', 'producerQualificationSHA256'):
                hash_value(self.producer[key])

    def source(self, expected=None):
        selected = expected or self.head
        return Source(self.root, selected, self.registry / 'source' / selected)

    def review(self):
        binding = self.value['protocolReview']
        require(type(binding) is dict and set(binding) == {'path', 'sha256'}, 'review binding schema mismatch')
        path = absolute(binding['path'])
        require(sha(path) == hash_value(binding['sha256']), 'protocol review bytes changed')
        review = load(path)
        require(review.get('contractID') == CONTRACT and review.get('decision') == 'GO' and
                type(review.get('reviewer')) is str and review['reviewer'].strip() not in ('', 'author') and
                review.get('unresolvedFindings') == [] and set(review.get('files', {})) == set(TOOL_PATHS),
                'missing independent unchanged-protocol review')
        for name in TOOL_PATHS:
            actual = sha(self.root / name)
            require(actual == review['files'][name] == digest(git(self.root, 'show', self.head + ':' + name)),
                    'tool/test bytes do not match reviewed exact source')
        require(sha(Path(__file__).resolve()) == review['files'][TOOL_PATHS[0]], 'executed controller is not reviewed controller')
        return {'sha256': sha(path), 'files': review['files'], 'reviewer': review['reviewer']}

    def fresh(self):
        remote = git(self.root, 'remote', 'get-url', 'origin').decode().strip()
        require(remote in ('https://github.com/' + REPO + '.git', 'https://github.com/' + REPO,
                           'git@github.com:' + REPO + '.git'), 'origin repository differs')
        git(self.root, 'fetch', 'origin')
        observed = [git(self.root, 'rev-parse', ref).decode().strip() for ref in ('HEAD', 'origin/' + REF, 'origin/main')]
        require(observed == [self.head, self.head, self.main], 'HEAD/remote branch/mainP drift')
        require(git(self.root, 'symbolic-ref', '--short', 'HEAD').decode().strip() == REF, 'wrong checkout branch')
        require(not git(self.root, 'diff', '--name-only') and not git(self.root, 'diff', '--cached', '--name-only'),
                'tracked checkout dirty')
        remote_refs = dict(line.split('\t')[::-1] for line in git(self.root, 'ls-remote', 'origin',
                           'refs/heads/' + REF, 'refs/heads/main').decode().splitlines())
        require(remote_refs == {'refs/heads/' + REF: self.head, 'refs/heads/main': self.main}, 'live ref drift')
        source = Source(self.root, self.head)
        require(source.main == self.main and source.payload.source_identity(self.root, self.head, False) == source.identity,
                'physical source/authority binding mismatch')
        review = self.review()
        require(digest(canonical(load(self.path))) == self.identity, 'matrix changed during operation')
        return source, review


def request_path(matrix, request_id):
    require(type(request_id) is str and re.fullmatch(r'(?:[0-9a-f]{32}|import-[1-9][0-9]*)', request_id), 'invalid request ID')
    return matrix.registry / 'requests' / request_id


def records(matrix, allow_uncertain=False):
    result = []
    base = matrix.registry / 'requests'
    if not base.exists():
        return result
    for path in sorted(base.iterdir()):
        require(path.is_dir() and path == request_path(matrix, path.name), 'foreign registry member')
        intent = load(path / 'intent.json')
        require(intent.get('contractID') == CONTRACT and intent.get('requestID') == path.name and
                intent.get('repository') == REPO and intent.get('ref') == REF, 'registry intent identity mismatch')
        head(intent['head']); hash_value(intent['sourceIdentitySHA256'])
        resolution = load(path / 'resolution.json') if (path / 'resolution.json').exists() else None
        require(allow_uncertain or resolution is not None, 'unresolved durable request blocks dispatch; reconcile it')
        if resolution is not None:
            require(resolution['intentSHA256'] == sha(path / 'intent.json'), 'resolution not bound to original intent')
            positive(resolution['runID'])
        result.append({'path': path, 'intent': intent, 'resolution': resolution})
    ids = [r['resolution']['runID'] for r in result if r['resolution']]
    require(len(ids) == len(set(ids)), 'duplicate registered run ID')
    return result


def find_record(matrix, rid):
    found = [r for r in records(matrix, True) if r['resolution'] and r['resolution']['runID'] == rid]
    require(len(found) == 1, 'run absent or ambiguous in append-only registry')
    return found[0]


def original_root(record):
    imported = record['intent'].get('originals')
    return wide(absolute(imported['path']) if imported else record['path'] / 'originals')


def capacity(history, active, registry, proposal):
    known = {r['resolution']['runID']: r for r in registry}
    require(len(known) == len(registry), 'duplicate registered ID')
    require(len({r['id'] for r in history}) == len(history), 'duplicate history ID')
    expected = {rid for rid, row in known.items() if row['intent']['head'] == proposal['head']}
    require({r['id'] for r in history} == expected, 'unknown/missing current-head history; import original records first')
    for raw in history:
        run_identity(raw, known[raw['id']]['intent'], raw['id'])
    live = {}
    for raw in active + [r for r in history if r['status'] != 'completed']:
        require(raw['id'] in known, 'unknown repository-active run; no inferred route or capacity')
        row = known[raw['id']]
        run_identity(raw, row['intent'], raw['id'])
        require(raw['status'] in ACTIVE, 'active/history terminal-status race; refresh')
        if raw['id'] in live:
            require(live[raw['id']]['status'] == raw['status'], 'active-status race; refresh')
        live[raw['id']] = raw
    tuple_of = lambda i: (i['kind'], i['shardID'], i['segmentID'])
    active_tuples = [tuple_of(known[rid]['intent']) for rid in live]
    require(len(active_tuples) == len(set(active_tuples)), 'active logical tuple duplicate')
    require(tuple_of(proposal) not in active_tuples, 'proposed tuple already active')
    for raw in history:
        if tuple_of(known[raw['id']]['intent']) == tuple_of(proposal):
            require(not (raw['status'] == 'completed' and raw['conclusion'] == 'success'), 'tuple already passed at exact head')
    counts = {'github': 0, 'bitrise': 0}
    for rid in live:
        counts[known[rid]['intent']['provider']] += 1
    counts[proposal['provider']] += 1
    require(counts['github'] <= 5 and counts['bitrise'] <= 3, 'provider capacity exceeded')
    return {'proposedCounts': counts, 'activeRunIDs': sorted(live), 'repositoryWideActiveMeasured': True,
            'accountWideBitriseMeasured': False, 'newBitriseConsumer': False}


def check_history(matrix, transport, proposed, registry):
    history = transport.pages('actions/workflows/' + WORKFLOW + '/runs?branch=' + REF +
                              '&head_sha=' + matrix.head + '&per_page=100', 'workflow_runs')
    active = []
    for status in ACTIVE:
        active.extend(transport.pages('actions/runs?status=' + status + '&per_page=100', 'workflow_runs'))
    result = capacity(history, active, registry, proposed)
    old_ids = {r['id'] for r in active if r['head_sha'] != matrix.head}
    commit_epoch = git(matrix.root, 'show', '-s', '--format=%ct', matrix.head).decode().strip()
    require(re.fullmatch(r'0|[1-9][0-9]{0,11}', commit_epoch) is not None and
            int(commit_epoch) <= 253402300799, 'valid Git commit epoch required')
    commit_time = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(seconds=int(commit_epoch))
    for rid in old_ids:
        record = next(r for r in registry if r['resolution']['runID'] == rid)
        require(record['intent']['provider'] == 'github', 'old Bitrise checkout not independently established')
        jobs = transport.pages('actions/runs/' + str(rid) + '/jobs?per_page=100', 'jobs')
        workers = [j for j in jobs if j.get('conclusion') != 'skipped' and 'acceptance · ' in j['name']]
        require(len(workers) == 1, 'old worker checkout ambiguous')
        checks = [s for s in workers[0]['steps'] if s['name'] == 'Check out the exact revision']
        require(len(checks) == 1 and checks[0]['conclusion'] == 'success' and
                utc(checks[0]['completed_at']) <= commit_time and workers[0]['head_sha'] == record['intent']['head'],
                'old active run did not complete exact checkout before new commit')
    result['oldCheckoutRunIDs'] = sorted(old_ids)
    return history, result


def filesystem_stamp(path):
    """Include change time/file identity, not merely caller-restorable mtime."""
    path = wide(path); info = path.lstat()
    require(not stat.S_ISLNK(info.st_mode) and not getattr(info, 'st_file_attributes', 0) & 0x400,
            'linked evidence cannot use verified cache')
    stamp = {'size': info.st_size, 'mtimeNS': info.st_mtime_ns, 'changeNS': info.st_ctime_ns,
             'inode': info.st_ino, 'device': info.st_dev, 'mode': info.st_mode}
    if os.name == 'nt':
        from ctypes import wintypes
        class Basic(ctypes.Structure):
            _fields_ = [('creation', ctypes.c_longlong), ('access', ctypes.c_longlong),
                        ('write', ctypes.c_longlong), ('change', ctypes.c_longlong), ('attributes', wintypes.DWORD)]
        class Identity(ctypes.Structure):
            _fields_ = [('volume', ctypes.c_ulonglong), ('identifier', ctypes.c_ubyte * 16)]
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                      wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.GetFileInformationByHandleEx.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        kernel.GetFileInformationByHandleEx.restype = wintypes.BOOL
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        handle = kernel.CreateFileW(str(path), 0x80, 7, None, 3, 0x02000000, None)
        require(handle != ctypes.c_void_p(-1).value, 'cannot read filesystem evidence identity')
        try:
            basic = Basic(); identity = Identity()
            require(kernel.GetFileInformationByHandleEx(handle, 0, ctypes.byref(basic), ctypes.sizeof(basic)) and
                    kernel.GetFileInformationByHandleEx(handle, 18, ctypes.byref(identity), ctypes.sizeof(identity)),
                    'filesystem lacks stable change-time/identity proof; full inspection required')
            stamp.update(changeNS=basic.change * 100, nativeFileID=bytes(identity.identifier).hex(), nativeVolume=identity.volume)
        finally:
            kernel.CloseHandle(handle)
    return stamp


def cache_inventory(root, exclude_audits=False):
    root = wide(root); rows = {}
    for path in sorted(root.rglob('*')):
        name = path.relative_to(root).as_posix()
        if exclude_audits and (name.split('/')[0].startswith('AUDIT') or name == 'integrity.json'):
            continue
        rows[name] = {'stamp': filesystem_stamp(path), 'type': 'file' if path.is_file() else 'directory'}
        require(path.is_file() or path.is_dir(), 'nonregular evidence tree')
    return rows


def remember_verified(root, cache, binding, facts, exclude_audits=False):
    before = cache_inventory(root, exclude_audits)
    for name, row in before.items():
        if row['type'] == 'file': row['sha256'] = sha(wide(root) / name)
    after = cache_inventory(root, exclude_audits)
    require({n: {k: v for k, v in r.items() if k != 'sha256'} for n, r in before.items()} == after,
            'evidence changed during verified cache creation')
    value = {'binding': binding, 'toolSHA256': sha(Path(__file__).resolve()), 'root': str(wide(root)),
             'excludeAudits': exclude_audits, 'files': before, 'facts': facts}
    raw = canonical(value)
    path = cache / (dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%f') + '-' + digest(raw) + '.json')
    exclusive(path, raw)


def reuse_verified(root, cache, binding, exclude_audits=False):
    snapshots = sorted(cache.glob('*.json')) if cache.exists() else []
    if not snapshots:
        return None
    path = snapshots[-1]; raw = path.read_bytes()
    require(path.stem.split('-')[-1] == digest(raw), 'verified cache index corrupted')
    value = decode(raw)
    if value['toolSHA256'] != sha(Path(__file__).resolve()) or value['binding'] != binding:
        return None  # Changed controller/source receives full validation, not cached qualification.
    require(value['root'] == str(wide(root)) and value['excludeAudits'] == exclude_audits, 'cache root/scope mismatch')
    observed = cache_inventory(root, exclude_audits)
    require(set(observed) == set(value['files']), 'verified evidence file/directory closure changed')
    changed = []
    for name, row in observed.items():
        expected = value['files'][name]
        require(row['type'] == expected['type'], 'verified evidence type changed')
        if row['stamp'] != expected['stamp']:
            if row['type'] == 'file':
                require(sha(wide(root) / name) == expected['sha256'], 'changed original no longer matches verified digest')
            changed.append(name)
    if changed:
        # Exact changed bytes were checked; append refreshed metadata without
        # replacing the prior audit or regenerating native/product proof.
        for name in changed: value['files'][name]['stamp'] = observed[name]['stamp']
        require(cache_inventory(root, exclude_audits) == observed, 'evidence changed during incremental recheck')
        raw = canonical(value)
        exclusive(cache / (dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%f') + '-' + digest(raw) + '.json'), raw)
    return value['facts']


def collection_proof(matrix, root, intent, rid):
    cache = matrix.registry / 'verified-originals' / str(rid)
    binding = {'runID': rid, 'head': intent['head'], 'sourceIdentitySHA256': intent['sourceIdentitySHA256']}
    previous = reuse_verified(root, cache, binding, True)
    if previous is not None:
        return previous
    before = cache_inventory(root, True)
    facts = verify_collection(root, intent, rid)
    require(cache_inventory(root, True) == before, 'originals changed during full collection verification')
    remember_verified(root, cache, binding, facts, True)
    return facts


def terminal_collection(matrix, record, transport):
    rid = record['resolution']['runID']; intent = record['intent']; root = original_root(record)
    live = run_identity(transport.api('actions/runs/' + str(rid)), intent, rid)
    require(live['status'] == 'completed', 'not terminal; no original download or frozen terminal API')
    if intent.get('originals'):
        require(root.exists(), 'imported originals unavailable; never create another collector copy')
        return collection_proof(matrix, root, intent, rid)
    root.mkdir(parents=True, exist_ok=True)
    if not (root / 'run.json').exists():
        save(root / 'run.json', live)
    original_run = load(root / 'run.json'); run_identity(original_run, intent, rid)
    require(original_run['status'] == 'completed' and original_run['conclusion'] == live['conclusion'], 'terminal original changed status')
    if not (root / 'jobs.json').exists():
        jobs = transport.pages('actions/runs/' + str(rid) + '/jobs?per_page=100', 'jobs')
        save(root / 'jobs.json', {'total_count': len(jobs), 'jobs': jobs})
    jobs = load(root / 'jobs.json')['jobs']
    for job in jobs:
        require(job['status'] == 'completed' and job['head_sha'] == intent['head'], 'job not terminal exact head')
        if job['conclusion'] != 'skipped':
            path = root / ('job-' + str(positive(job['id'])) + '.log')
            if not path.exists():
                retain(path, transport.execute(['api', 'repos/' + REPO + '/actions/jobs/' + str(job['id']) + '/logs'], 'job-log'))
    if not (root / 'artifacts.json').exists():
        artifacts = transport.pages('actions/runs/' + str(rid) + '/artifacts?per_page=100', 'artifacts')
        save(root / 'artifacts.json', {'total_count': len(artifacts), 'artifacts': artifacts})
    for meta in load(root / 'artifacts.json')['artifacts']:
        destination = root / str(positive(meta['id']))
        save(destination / 'metadata.json', meta)
        transport.artifact(meta, destination / 'original.zip')
        extract_checked(destination / 'original.zip', destination / 'artifact')
    facts = collection_proof(matrix, root, intent, rid)
    save(record['path'] / 'collection.json', facts)
    return facts


def verify_collection(root, intent, rid):
    root = wide(root)
    run = run_identity(load(root / 'run.json'), intent, rid)
    require(run['status'] == 'completed', 'original run is not terminal')
    jobs = load(root / 'jobs.json'); arts = load(root / 'artifacts.json')
    require(jobs['total_count'] == len(jobs['jobs']) and arts['total_count'] == len(arts['artifacts']), 'incomplete original API inventory')
    require(len({j['id'] for j in jobs['jobs']}) == len(jobs['jobs']) and
            len({a['id'] for a in arts['artifacts']}) == len(arts['artifacts']), 'duplicate original API identity')
    gaps = []; entries = []
    for job in jobs['jobs']:
        require(job['status'] == 'completed' and job['head_sha'] == intent['head'], 'original job identity mismatch')
        if job['conclusion'] != 'skipped':
            regular(root / ('job-' + str(positive(job['id'])) + '.log'))
    for meta in arts['artifacts']:
        aid = positive(meta['id']); folder = root / str(aid); archive = folder / 'original.zip'
        require(load(folder / 'metadata.json') == meta, 'artifact metadata copy changed')
        require(archive.stat().st_size == meta['size_in_bytes'] and sha(archive) == meta['digest'].removeprefix('sha256:').upper(),
                'original artifact size/digest mismatch')
        owner = meta['workflow_run']
        require(owner['id'] == rid and owner['head_sha'] == intent['head'] and owner['head_branch'] == REF and
                owner['repository_id'] == owner['head_repository_id'] == run['repository']['id'], 'original artifact ownership mismatch')
        target = folder / 'artifact'
        # All files already exist here: equality verification cannot mutate an original.
        require(target.is_dir(), 'original extraction absent; use collect')
        count = check_archive_bytes(archive, target)
        nested = manifests(target)
        transport = meta['name'].startswith('s10-4-shared-payload-')
        if not (target / 'SHA256SUMS.txt').is_file():
            if transport:
                require({p.name for p in target.iterdir()} == {'FieldEvidencePayload.tar', 'FieldEvidencePayload.tar.sha256'}, 'payload transport closure')
                require((target / 'FieldEvidencePayload.tar.sha256').read_text().split()[0].upper() == sha(target / 'FieldEvidencePayload.tar'), 'payload TAR checksum')
            else:
                gaps.append('missing original outer checksum manifest: ' + meta['name'])
        zips = []
        for path in target.rglob('*.zip'):
            zips.append({'path': path.relative_to(target).as_posix(), 'members': check_archive_bytes(path), 'sha256': sha(path)})
        entries.append({'id': aid, 'name': meta['name'], 'bytes': meta['size_in_bytes'], 'sha256': sha(archive),
                        'members': count, 'manifests': nested, 'nestedArchives': zips})
    require(bool(entries) or run['conclusion'] != 'success', 'successful candidate has no artifacts')
    identity_files = {p.relative_to(root).as_posix(): sha(p) for p in root.rglob('*') if p.is_file()
                      and not p.relative_to(root).parts[0].startswith('AUDIT') and p.name != 'integrity.json'}
    return {'runID': rid, 'head': intent['head'], 'conclusion': run['conclusion'],
            'artifacts': entries, 'gaps': gaps, 'originalFilesSHA256': digest(canonical(identity_files)),
            'originalFileCount': len(identity_files), 'allAvailableOriginalsVerified': True}


def check_archive_bytes(path, root=None):
    path = wide(path)
    root = wide(root) if root is not None else None
    with zipfile.ZipFile(path) as archive:
        items = archive.infolist(); seen = set(); names = set()
        require(len(items) <= MAX_MEMBERS and sum(i.file_size for i in items) <= MAX_EXPANDED, 'ZIP bounds exceeded')
        for item in items:
            name = item.filename.rstrip('/') if item.is_dir() else item.filename
            relative(name)
            require(item.orig_filename == item.filename and name.casefold() not in seen and not item.flag_bits & 1 and
                    (item.external_attr >> 16) & 0o170000 not in (0o120000, 0o060000, 0o020000, 0o010000, 0o140000),
                    'unsafe ZIP entry')
            seen.add(name.casefold())
            if not item.is_dir():
                names.add(item.filename)
                if root is not None:
                    with archive.open(item) as stream:
                        value = hashlib.file_digest(stream, 'sha256').hexdigest().upper()
                    require(sha(root / item.filename) == value and (root / item.filename).stat().st_size == item.file_size,
                            'extracted original differs from archive')
        require(archive.testzip() is None, 'ZIP CRC failed')
        if root is not None:
            require(names == {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}, 'original extracted closure differs')
        return len(items)


def artifact_root(originals, name):
    found = [a for a in load(originals / 'artifacts.json')['artifacts'] if a['name'] == name]
    require(len(found) == 1, 'missing or duplicate named original artifact')
    return originals / str(found[0]['id']) / 'artifact'


def attach_transport(module, transport, originals):
    module.api = transport.api
    module.list_api = lambda endpoint, field: transport.pages(endpoint + ('&' if '?' in endpoint else '?') + 'per_page=100', field)
    def cached_download(meta, destination):
        archive = originals / str(meta['id']) / 'original.zip'
        require(archive.stat().st_size == meta['bytes'] and sha(archive) == meta['sha256'], 'qualified cached original changed')
        # A derived verifier copy is not another network download or new original.
        exclusive(destination, archive.read_bytes())
    module.download = cached_download


def hosted_command(module, *args):
    # Recorded macOS argument paths must be parsed as POSIX on a Windows author
    # host. The exact source function and all its assertions remain unchanged.
    original = module.ensure_command
    check = types.FunctionType(original.__code__, dict(original.__globals__, Path=PurePosixPath),
                               original.__name__, original.__defaults__)
    return check(*args)


def verify_tar_products(module, tar, extracted, source, seal):
    """POSIX mode proof comes from original TAR, never Windows stat emulation."""
    require(tar.stat().st_size == seal['sharedBuildIdentity']['archive']['bytes'] and
            sha(tar) == seal['sharedBuildIdentity']['archive']['sha256'], 'immutable TAR binding mismatch')
    if not extracted.exists():
        module.extract_tar(tar, extracted)
    entries = []; all_files = {}; seen = set()
    prefix = 'FieldEvidencePayload/'
    product_prefix = prefix + module.ROOT_LABEL + '/'
    with tarfile.open(tar, 'r:') as archive:
        members = archive.getmembers()
        require(len(members) <= MAX_MEMBERS and sum(m.size for m in members) <= MAX_ARCHIVE, 'TAR bounds')
        for member in members:
            require(member.name.startswith(prefix), 'foreign TAR root')
            name = relative(member.name[len(prefix):].rstrip('/'))
            require(name.casefold() not in seen and (member.isfile() or member.isdir()) and not member.linkname and
                    not member.mode & 0o7000 and not member.sparse and
                    not any(k in member.pax_headers for k in ('linkpath', 'GNU.sparse.name', 'GNU.sparse.map')), 'unsafe TAR member')
            seen.add(name.casefold())
            item = {'path': name, 'mode': member.mode, 'type': 'directory' if member.isdir() else 'file'}
            if member.isfile():
                with archive.extractfile(member) as stream:
                    item.update(size=member.size, sha256=hashlib.file_digest(stream, 'sha256').hexdigest().upper())
                require(sha(extracted / name) == item['sha256'], 'extracted TAR byte mismatch')
                all_files[name] = item['sha256']
            if member.name.startswith(product_prefix):
                item['path'] = member.name[len(product_prefix):].rstrip('/')
                entries.append(item)
    require(set(all_files) == {p.relative_to(extracted).as_posix() for p in extracted.rglob('*') if p.is_file()}, 'TAR extracted closure mismatch')
    module.verify_checksums(extracted)
    prepared = module.typed(load(extracted / 'prepared-build.json'), 'prepared-build',
                            'source producer toolchain products buildEvidence')
    require(prepared['source'] == source and prepared['toolchain'] == module.TOOLCHAIN,
            'prepared source/toolchain mismatch')
    module.producer_identity(prepared['producer'])
    products = seal['sharedBuildIdentity']['products']
    require(sorted(entries, key=lambda e: e['path']) == products['tree'] and prepared['products'] == products and
            module.object_sha(products['tree']) == products['treeSHA256'], 'original TAR product tree/modes mismatch')
    require(prepared['producer'] == seal['sharedBuildIdentity']['producer'] and
            load(extracted / 'products-before-units.json') == products, 'prepared producer or pre-unit products changed')
    product_root = extracted / module.ROOT_LABEL
    xctestrun = extracted / products['xctestrunPath']
    require(sha(xctestrun) == products['xctestrunSHA256'] and
            module.product_compatibility(product_root, xctestrun) == products['compatibility'], 'native product compatibility mismatch')
    module.validate_xctestrun(xctestrun, str(product_root))
    return products


def producer_proof(matrix, source, transport, rid, select=None):
    record = find_record(matrix, rid)
    require(record['intent']['kind'] == 'producer' and record['intent']['head'] == source.head, 'producer not exact-head source producer')
    originals = original_root(record)
    facts = collection_proof(matrix, originals, record['intent'], rid)
    require(facts['conclusion'] == 'success' and not facts['gaps'], 'producer originals not complete successful evidence')
    module = source.payload; attach_transport(module, transport, originals)
    run = module.run_contract(module.api('actions/runs/' + str(rid)), rid, source.head)
    require(run['status'] == 'completed' and run['conclusion'] == 'success' and run['run_attempt'] == 1, 'producer live API not successful')
    jobs = module.list_api('actions/runs/' + str(rid) + '/jobs', 'jobs'); module.job_contract(jobs, run)
    metas = module.list_api('actions/runs/' + str(rid) + '/artifacts', 'artifacts')
    normalized = {}
    for kind in ('payload', 'unit', 'seal'):
        found = [a for a in metas if a['name'] == module.artifact_name(kind, run)]
        require(len(found) == 1, 'producer live artifact missing or duplicate')
        normalized[kind] = module.artifact_contract(found[0], run, kind, module.now_epoch())
    cache = wide(matrix.registry / 'producer-proof' / str(rid))
    cache_binding = {'source': source.identity, 'runID': rid, 'artifacts': normalized}
    prior_proof = reuse_verified(cache, matrix.registry / 'verified-producers' / str(rid), cache_binding) if cache.exists() else None
    if prior_proof is not None:
        if select is not None:
            require(all(select[k] == prior_proof[k] for k in ('runID', 'sharedBuildIdentitySHA256', 'producerQualificationSHA256')),
                    'selected immutable payload differs')
        return cache, prior_proof
    if not (cache / 'admission.json').exists():
        require(not cache.exists(), 'incomplete producer proof retained; inspect before reuse')
        cache.mkdir(parents=True)
        module.admit_source({'sourceRunID': str(rid)}, cache, source.identity,
                            {'shardID': source.shards['shards'][0]['shardID'], 'segmentID': 'none', 'purpose': 'acceptance'})
    admission = load(cache / 'admission.json'); seal = load(cache / 'shared-build-seal.json')
    require(admission['source'] == source.identity and admission['artifacts'] == normalized and
            seal['sharedBuildIdentity']['payloadArtifact'] == normalized['payload'] and seal['unitArtifact'] == normalized['unit'],
            'live producer metadata changed from original selection')
    require(module.object_sha(seal['sharedBuildIdentity']) == admission['sharedBuildIdentitySHA256'] == seal['sharedBuildIdentitySHA256'],
            'producer identity mismatch')
    for kind, target in (('payload', 'payload-transport'), ('unit', 'unit-proof')):
        artifact = normalized[kind]; original = originals / str(artifact['id']) / 'original.zip'
        extract_checked(original, cache / target)
    tar = cache / 'payload-transport/FieldEvidencePayload.tar'
    products = verify_tar_products(module, tar, cache / 'payload', source.identity, seal)
    qualification = module.qualification(cache / 'unit-proof', source.identity)
    require(module.object_sha(qualification) == admission['producerQualificationSHA256'] == seal['producerQualificationSHA256'] and
            qualification['products'] == products and qualification['producer'] == seal['sharedBuildIdentity']['producer'] and
            qualification['archive'] == seal['sharedBuildIdentity']['archive'], 'producer native-five/payload closure mismatch')
    if select is not None:
        require(select['runID'] == rid and all(select[k] == admission[k] for k in
                ('sharedBuildIdentitySHA256', 'producerQualificationSHA256')), 'selected immutable payload differs')
    proof = {'runID': rid, 'sharedBuildIdentitySHA256': admission['sharedBuildIdentitySHA256'],
                   'producerQualificationSHA256': admission['producerQualificationSHA256'], 'producerUnitCount': 5,
                   'sourceIdentitySHA256': digest(canonical(source.identity)), 'productsPOSIXModesVerifiedFromOriginalTAR': True}
    remember_verified(cache, matrix.registry / 'verified-producers' / str(rid), cache_binding, proof)
    return cache, proof


def segment_proof(matrix, source, transport, producer_root, shard, segment_id, rid):
    record = find_record(matrix, rid); intent = record['intent']; originals = original_root(record)
    require((intent['kind'], intent['head'], intent['shardID'], intent['segmentID']) ==
            ('consumer', source.head, shard, segment_id), 'dependency tuple/head mismatch')
    facts = collection_proof(matrix, originals, intent, rid)
    require(facts['conclusion'] == 'success' and not facts['gaps'], 'dependency original run not complete successful')
    kernel = source.assembler; ctx = source.context(shard)
    ctx['producerSeal'] = load(producer_root / 'shared-build-seal.json')
    ctx['producerQualification'] = load(producer_root / 'unit-proof/producer-qualification.json')
    binding = kernel.new_matrix(ctx, source.head, producer_root); kernel.verify_matrix(binding, ctx)
    segment = next(s for s in ctx['segments'] if s['segmentID'] == segment_id)
    run = run_identity(transport.api('actions/runs/' + str(rid)), intent, rid)
    jobs = transport.pages('actions/runs/' + str(rid) + '/jobs?per_page=100', 'jobs')
    artifacts = transport.pages('actions/runs/' + str(rid) + '/artifacts?per_page=100', 'artifacts')
    name = 'ios-ci-shared-' + str(rid) + '-1-' + shard + '-' + segment_id
    found = [a for a in artifacts if a['name'] == name]
    require(len(found) == 1, 'dependency live artifact missing or duplicate')
    metadata = kernel.metadata_contract(run, jobs, found[0], str(rid), ctx, segment, binding)
    original_meta = next(a for a in load(originals / 'artifacts.json')['artifacts'] if a['name'] == name)
    require(original_meta['id'] == metadata['id'] and original_meta['digest'][7:].upper() == metadata['sha256'] and
            original_meta['size_in_bytes'] == metadata['bytes'], 'dependency live metadata differs from original')
    root = originals / str(metadata['id']) / 'artifact'
    proof_key = digest(canonical({'originalFilesSHA256': facts['originalFilesSHA256'], 'source': source.identity,
                                  'matrix': binding, 'segment': segment, 'toolSHA256': sha(Path(__file__).resolve())}))
    proof_dir = matrix.registry / 'segment-proofs' / str(rid)
    previous = list(proof_dir.glob(proof_key + '-*.json')) if proof_dir.exists() else []
    require(len(previous) <= 1, 'ambiguous cached native segment proof')
    if previous:
        raw = previous[0].read_bytes()
        require(previous[0].stem.split('-')[-1] == digest(raw), 'cached native proof corrupted')
        saved = decode(raw); receipt, rows, candidates = saved['receipt'], saved['rows'], saved['candidates']
    else:
        receipt, rows, candidates = kernel.revalidate_original(source.root, root, ctx, segment, binding)
        saved = {'receipt': receipt, 'rows': rows, 'candidates': candidates}
        raw = canonical(saved)
        exclusive(proof_dir / (proof_key + '-' + digest(raw) + '.json'), raw)
    consumer = receipt['consumer']; matched = [j for j in jobs if j['id'] == consumer['jobID']]
    require(len(matched) == 1, 'dependency native worker missing')
    job = matched[0]
    require(consumer['runID'] == rid and consumer['runAttempt'] == 1 and job['run_id'] == rid and job['run_attempt'] == 1 and
            job['head_sha'] == source.head and job['head_branch'] == REF and job['status'] == 'completed' and
            job['conclusion'] == 'success' and job['runner_name'] == consumer['runnerName'], 'dependency native/API worker mismatch')
    selected = {'segmentID': segment_id, 'runID': str(rid), 'runAttempt': '1', 'jobID': str(job['id']),
                'artifactID': str(metadata['id']), 'artifactName': metadata['name'], 'artifactSHA256': metadata['sha256'],
                'artifactBytes': metadata['bytes'], 'artifactCreatedAt': metadata['createdAtUTC'],
                'artifactExpiresAt': metadata['expiresAtUTC'],
                'receiptSHA256': sha(root / 's10-4' / shard / 'segment-receipt.pending.json'),
                'sessionIdentitySHA256': receipt['sessionIdentitySHA256'], 'matrixID': binding['matrixID']}
    return {'selection': selected, 'receipt': receipt, 'rows': rows, 'candidates': candidates,
            'artifactRoot': str(root), 'matrix': binding}


def validate_retry(history, registry, proposal, retry_id, retry_kind, reason):
    matches = [r for r in registry if r['intent']['head'] == proposal['head'] and
               (r['intent']['kind'], r['intent']['shardID'], r['intent']['segmentID']) ==
               (proposal['kind'], proposal['shardID'], proposal['segmentID'])]
    if not matches:
        require(retry_id is None and retry_kind is None and reason is None, 'retry lacks a predecessor tuple')
        return None
    require(retry_id is not None and retry_kind in ('hosted-infrastructure', 'runtime-crash', 'unknown-native-cause') and
            type(reason) is str and len(reason.strip()) >= 20, 'explicit audited retry classification and reason required')
    selected = [r for r in matches if r['resolution']['runID'] == retry_id]
    require(len(selected) == 1, 'retry predecessor not registered exact tuple')
    latest = max(matches, key=lambda r: utc(r['intent']['recordedAt']))
    require(latest['resolution']['runID'] == retry_id, 'retry must name latest same-head tuple, not an older failure')
    native = next(r for r in history if r['id'] == retry_id)
    require(native['status'] == 'completed' and native['conclusion'] == 'failure', 'retry predecessor not terminal failed')
    audits = sorted((selected[0]['path'] / 'audits').glob('*.json'))
    require(audits, 'full original predecessor audit missing')
    original = verify_collection(original_root(selected[0]), selected[0]['intent'], retry_id)
    history_audits = [load(path) for path in audits]
    require(all(a['runID'] == retry_id and a['head'] == proposal['head'] and
                a['originalFilesSHA256'] == original['originalFilesSHA256'] for a in history_audits),
            'predecessor audit/original binding changed')
    require(not any(a.get('knownDeterministicFailure') is True for a in history_audits),
            'append-only audit history records known deterministic same-head failure')
    complete = [index for index, a in enumerate(history_audits) if a.get('completeOriginalAudit') is True]
    require(complete, 'complete original predecessor audit missing')
    audit_index = complete[-1]
    return {'runID': retry_id, 'auditSHA256': sha(audits[audit_index]), 'classification': retry_kind, 'reason': reason,
            'classificationBy': 'explicit root dispatch invocation', 'nondeterminismProvedByController': False}


def dispatch(matrix, args):
    # This is the ONLY function that invokes gh workflow run.
    source, review = matrix.fresh()
    row = source.tuple(args.kind, args.shard, args.segment)
    dependencies = parse_dependencies(args.dependency)
    producer_id = matrix.producer['runID'] if matrix.producer else None
    selected_inputs = inputs(row, producer_id, dependencies)
    require(type(args.question) is str and len(args.question.strip()) >= 20, 'record a concrete unanswered question')
    request_id = uuid.uuid4().hex
    gate = matrix.registry / 'dispatch.gate'
    exclusive(gate, request_id.encode())
    attempted = False
    try:
        registry = records(matrix)
        proposed = dict(row, head=matrix.head)
        transport = Transport(matrix.root, matrix.registry / 'preflight' / request_id)
        history, capacity_fact = check_history(matrix, transport, proposed, registry)
        retry = validate_retry(history, registry, proposed, args.retry, args.retry_kind, args.reason)
        proof = None; dependency_proofs = []
        if row['kind'] != 'producer':
            producer_root, proof = producer_proof(matrix, source, transport, producer_id, matrix.producer)
            for sid in row['dependencies']:
                dependency_proofs.append(segment_proof(matrix, source, transport, producer_root, row['shardID'], sid, dependencies[sid])['selection'])
        final_source, final_review = matrix.fresh()
        require(source.identity == final_source.identity and review == final_review and
                [(r['intent'], r['resolution']) for r in registry] == [(r['intent'], r['resolution']) for r in records(matrix)],
                'source/review/registry changed during preflight')
        # Recheck active status at the last safe point; proof gathering may take time.
        history, capacity_fact = check_history(matrix, transport, proposed, registry)
        intent = dict(proposed, contractID=CONTRACT, requestID=request_id, repository=REPO, ref=REF,
                      mainSHA=matrix.main, matrixSHA256=matrix.identity, inputs=selected_inputs,
                      recordedAt=now(), question=args.question, owner='root', retry=retry,
                      sourceIdentitySHA256=digest(canonical(source.identity)), protocolReview=review,
                      producerProof=proof, dependencySelections=dependency_proofs, capacity=capacity_fact)
        folder = request_path(matrix, request_id)
        exclusive(folder / 'intent.json', canonical(intent) + b'\n')
        attempted = True  # Any exception from here is an uncertain durable request.
        cmd = ['gh', 'workflow', 'run', WORKFLOW, '--repo', REPO, '--ref', REF]
        for key, value in selected_inputs.items():
            cmd += ['-f', key + '=' + value]
        save(folder / 'command.json', cmd)
        result = subprocess.run(cmd, cwd=matrix.root, capture_output=True, shell=False, env=gh_environment())
        exclusive(folder / 'returned.stdout', result.stdout)
        exclusive(folder / 'returned.stderr', result.stderr)
        exclusive(folder / 'returned.exit', str(result.returncode).encode())
        require(result.returncode == 0, 'uncertain dispatch transport; reconcile same request only')
        resolve(matrix, request_id)
        return {'requestID': request_id, 'runID': load(folder / 'resolution.json')['runID']}
    finally:
        if not attempted:
            require(gate.read_bytes() == request_id.encode(), 'dispatch gate identity changed')
            gate.unlink()


def resolve(matrix, request_id):
    folder = request_path(matrix, request_id); intent = load(folder / 'intent.json')
    if (folder / 'resolution.json').exists():
        result = load(folder / 'resolution.json')
        require(result['intentSHA256'] == sha(folder / 'intent.json'), 'resolution intent mismatch')
        return result
    require((folder / 'returned.stdout').exists(), 'no returned direct identity; retain uncertain intent, never redispatch')
    rid = returned_id((folder / 'returned.stdout').read_bytes())
    known = [r['resolution']['runID'] for r in records(matrix, True) if r['resolution']]
    require(rid not in known, 'returned already registered run ID')
    transport = Transport(matrix.root, folder / 'reconciliation')
    # One explicit invocation, one same-ID read. A transitional title is retained
    # and another reconcile call may read that same ID, never dispatch again.
    raw = run_identity(transport.api('actions/runs/' + str(rid)), intent, rid)
    result = {'runID': rid, 'intentSHA256': sha(folder / 'intent.json'), 'directAPISHA256': digest(canonical(raw)),
              'resolvedAt': now(), 'url': raw['html_url']}
    save(folder / 'resolution.json', result)
    gate = matrix.registry / 'dispatch.gate'
    if gate.exists():
        require(gate.read_bytes() == request_id.encode(), 'dispatch gate belongs to another intent')
        gate.unlink()
    return result


def parse_dependencies(values):
    result = {}
    for value in values or []:
        match = re.fullmatch(r'((?:minimum-)?segment-[123])=([1-9][0-9]*)', value)
        require(match is not None and match[1] not in result, 'malformed/duplicate dependency')
        result[match[1]] = int(match[2])
    return result


def import_record(matrix, args):
    """Explicitly adopt original dispatch data; no inferred workflow inputs."""
    path = absolute(args.record); returned = absolute(args.returned)
    original = load(path); rid = returned_id(returned.read_bytes())
    require(original['run']['databaseId'] == rid and original['head'] == original['run']['headSha'] and
            original['repository'] == REPO and original['ref'] == REF and original['workflow'] == WORKFLOW,
            'import original dispatch provenance mismatch')
    source = matrix.source(original['head'])
    kind = next((k for k, lane in LANES.items() if lane == original['inputs']['execution_lane']), None)
    require(kind is not None, 'import route outside finite implemented controller')
    row = source.tuple(kind, original['inputs']['s10_4_shard_id'], original['inputs']['s10_4_shared_segment_id'])
    mapping = decode(original['inputs']['s10_4_segment_source_run_ids']) if original['inputs']['s10_4_segment_source_run_ids'] else {}
    require(all(type(v) is str and re.fullmatch('[1-9][0-9]*', v) for v in mapping.values()), 'import dependency IDs malformed')
    selected = original['inputs']['s10_4_shared_payload_run_id']
    expected = inputs(row, int(selected) if selected else None, {k: int(v) for k, v in mapping.items()})
    require(original['inputs'] == expected, 'import original closed inputs differ')
    request_id = 'import-' + str(rid)
    intent = dict(row, contractID=CONTRACT, requestID=request_id, repository=REPO, ref=REF, head=source.head,
                  mainSHA=source.main, recordedAt=original['recordedAt'], inputs=expected,
                  sourceIdentitySHA256=digest(canonical(source.identity)), owner='root',
                  question=original.get('question', 'Original imported dispatch; no new execution'),
                  importedDispatch={'path': str(path), 'sha256': sha(path), 'returnedPath': str(returned), 'returnedSHA256': sha(returned)})
    if args.originals:
        originals = absolute(args.originals)
        verify_collection(originals, intent, rid)
        intent['originals'] = {'path': str(originals)}
    transport = Transport(matrix.root, matrix.registry / 'imports' / str(rid))
    raw = run_identity(transport.api('actions/runs/' + str(rid)), intent, rid)
    jobs = transport.pages('actions/runs/' + str(rid) + '/jobs?per_page=100', 'jobs')
    if row['kind'] == 'consumer':
        # Unlike display_title, the existing worker name identifies the segment.
        expected_name = 'GitHub Xcode 26.6 acceptance · ' + row['shardID'] + ' · ' + row['segmentID'] + ' / verify'
        require(len([j for j in jobs if j['name'] == expected_name]) == 1, 'import has no actual segment worker identity')
    for record in records(matrix, True):
        require(not record['resolution'] or record['resolution']['runID'] != rid, 'run already registered')
    folder = request_path(matrix, request_id)
    exclusive(folder / 'intent.json', canonical(intent) + b'\n')
    save(folder / 'resolution.json', {'runID': rid, 'intentSHA256': sha(folder / 'intent.json'),
                                     'directAPISHA256': digest(canonical(raw)), 'resolvedAt': now(), 'url': raw['html_url']})
    return {'requestID': request_id, 'runID': rid, 'importedOriginalsOnly': True}


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def native_database_facts(root):
    db = wide(root) / 'UISmoke.xcresult/database.sqlite3'
    if not db.exists():
        return {'nativeDatabaseMissing': True}
    before = sha(db)
    uri = Path(str(db).removeprefix('\\\\?\\')).resolve().as_uri()
    connection = sqlite3.connect(uri + '?mode=ro&immutable=1', uri=True)
    connection.row_factory = sqlite3.Row
    try:
        tables = {r[0] for r in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        result = {}
        for table in ('TestCases', 'TestCaseRuns', 'TestIssues', 'SourceCodeLocations'):
            result['native' + table] = [dict(r) for r in connection.execute('SELECT rowid,* FROM ' + table)] if table in tables else None
        result['nativeAttachmentRows'] = connection.execute('SELECT count(*) FROM Attachments').fetchone()[0] if 'Attachments' in tables else None
    finally:
        connection.close()
    require(sha(db) == before, 'native database changed during read')
    result['nativeDatabaseSHA256'] = before
    result['compressedNativePayloadScan'] = 'Not decoded by this standard-library controller; original payloads remain preserved.'
    return result


def literal_full_catalog(source, shard):
    """Read the worker's literal jq catalog without executing shell or jq code."""
    text = source.bytes['.github/workflows/ios-ci-worker.yml'].decode()
    start = text.index('contrast_exception_authority_path=')
    end = text.index("' > \"$contrast_exception_authority_path\"", start)
    block = text[start:end]
    variables = {k: decode(v) for k, v in re.findall(r'--arg ([A-Za-z]\w*) ("(?:\\.|[^"\\])*")', block)}
    data = block[block.index('[\n'):].rstrip()
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|\$[A-Za-z]\w*|[A-Za-z_]\w*|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[\[\]{},:]|\s+|.', data)
    rendered = []
    for index, token in enumerate(tokens):
        if token.startswith('"') or token.isspace() or re.fullmatch(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?', token) or token in '[]{},:':
            rendered.append(token)
        elif token.startswith('$'):
            require(token[1:] in variables, 'unknown variable in static exception catalog')
            rendered.append(canonical(variables[token[1:]]).decode())
        elif re.fullmatch(r'[A-Za-z_]\w*', token):
            following = next((t for t in tokens[index + 1:] if not t.isspace()), '')
            require(following == ':' or token in ('true', 'false', 'null'), 'nonliteral exception catalog expression')
            rendered.append(json.dumps(token) if following == ':' else token)
        else:
            raise Rejected('unsupported source exception catalog syntax')
    catalog = decode(''.join(rendered))
    require(type(catalog) is list and all(type(r) is dict and 'shardID' in r for r in catalog), 'source exception catalog malformed')
    return [r for r in catalog if r['shardID'] == shard]


def verify_state_pairs(source, ctx, ax, contrast):
    require(len(ax) == len(contrast) and [r['stateID'] for r in ax] == [r['stateID'] for r in contrast] and
            len({r['stateID'] for r in ax}) == len(ax), 'missing/duplicate/reordered strict state rows')
    kernel = source.assembler
    if ctx['shard']['shardID'] in source.plan['sharedVerification']['allowedShardIDs']:
        kernel.verify_state_rows({'ax': ax, 'contrast': contrast}, ctx)
    else:
        # The same assertions with the full-route worker's exact literal catalog.
        # No min/AX catalog or native exception policy is modified.
        original = kernel.exception_catalog
        catalog = literal_full_catalog(source, ctx['shard']['shardID'])
        try:
            kernel.exception_catalog = lambda _: catalog
            kernel.verify_state_rows({'ax': ax, 'contrast': contrast}, ctx)
        finally:
            kernel.exception_catalog = original


def candidate_state(name, prefix, owned, seen):
    require(name.startswith(prefix), 'candidate profile prefix mismatch')
    state = re.sub(r'_0_[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}(?=\.[^.]+$)',
                   '', name[len(prefix):], count=1).removesuffix('.png')
    require(state in owned and state not in seen, 'candidate state foreign or duplicate')
    return state


def native_events(log):
    events = {}
    for line in log.splitlines():
        if line.startswith(('S10_4_SEGMENT_', 'S10_4_MINIMUM_SEGMENT_')):
            match = re.fullmatch(r'(S10_4_[A-Z_]+) (.*)', line)
            require(match is not None, 'malformed segmented marker line')
            try:
                value = decode(match[2])
            except ValueError as error:
                raise Rejected('malformed segmented marker JSON') from error
            require(type(value) is dict, 'segmented marker must be an object')
            events.setdefault(match[1], []).append(value)
        else:
            match = re.fullmatch(r'(S10_4_[A-Z_]+) (\{.*\})', line)
            if match:
                events.setdefault(match[1], []).append(decode(match[2]))
    return events


def replay_rows(source, ctx, row, events):
    prefix = 'S10_4_MINIMUM_SEGMENT_' if ctx['minimum'] else 'S10_4_SEGMENT_'
    foreign = 'S10_4_SEGMENT_' if ctx['minimum'] else 'S10_4_MINIMUM_SEGMENT_'
    require(not any(key.startswith(foreign) for key in events), 'foreign replay marker family')
    kinds = {'START', 'REPLAY', 'JOURNEY', 'SETUP_WITNESS', 'RESUME_SETUP', 'RESULT',
             'PURCHASE_PROOF', 'PENDING_RECEIPT_PROOF'} if ctx['minimum'] else {'REPLAY', 'RESUME_SETUP'}
    names = [key for key in events if key.startswith(prefix)]
    if names:
        require(row['segmentID'] != 'none' and (ctx['minimum'] or row['shardID'] == 's10.4.current.ax-text'),
                'segmented markers outside source segmented profile')
        require(all(key in {prefix + kind for kind in kinds} for key in names), 'unknown segmented marker kind')
    replay = events.get(prefix + 'REPLAY', [])
    require(type(replay) is list and all(type(r) is dict for r in replay), 'malformed replay rows')
    if not replay:
        return replay
    require(row['segmentID'] != 'none' and (ctx['minimum'] or row['shardID'] == 's10.4.current.ax-text'),
            'replay markers outside source segmented profile')
    selected = next(s for s in ctx['segments'] if s['segmentID'] == row['segmentID'])
    require([r.get('stateID') for r in replay] == selected['replayStateIDs'][:len(replay)] and
            all(type(r.get('ordinal')) is int and r['ordinal'] == index and
                r.get('segmentID') == row['segmentID'] and r.get('shardID') == row['shardID']
                for index, r in enumerate(replay, 1)), 'replay state/order/profile differs')
    if ctx['minimum']:
        require(all(r.get('setupOnly') is True and r.get('acceptanceEligible') is False and
                    r.get('head') == source.head for r in replay), 'minimum replay provenance differs')
    else:
        require(all(set(r) == {'ordinal', 'segmentID', 'shardID', 'stateID'} for r in replay),
                'current AX replay schema differs')
    return replay


def consumer_facts(source, root, intent, rid, jobs):
    root = wide(root)
    result = {'localUnitCount': 0, 'producerUnitCount': 0, 'consumerReferenceVerified': False,
              'nativeTests': [], 'nativeFailures': [], 'strictOwnedCount': 0, 'replayCount': 0,
              'ownedJourneyCount': 0, 'candidatePNGCount': 0, 'fullSegmentComplete': False,
              'fullShardComplete': False, 'gaps': []}
    ctx = source.context(intent['shardID']); kernel = source.assembler; payload = source.payload
    reference_path = root / 'shared-consumer/consumer-build-reference.json'
    log = (root / 'ui-smoke.log').read_text(encoding='utf-8') if (root / 'ui-smoke.log').exists() else ''
    events = native_events(log)
    replay = replay_rows(source, ctx, intent, events)
    result['nativeEvents'] = events
    result['Code56Observed'] = 'Code=56' in log
    if not reference_path.exists():
        result['gaps'].append('Consumer restore/reference absent; native source/environment binding not established.')
        return result
    ref = load(reference_path); consumer = ref['consumer']
    payload.consumer_identity(consumer, source.root)
    require(consumer['runID'] == rid and consumer['runAttempt'] == 1 and consumer['shardID'] == intent['shardID'] and
            consumer['segmentID'] == intent['segmentID'] and ref['source'] == source.identity and ref['diagnosticOnly'] is False and
            type(ref['unitTestCount']) is int and ref['unitTestCount'] == 0 and ref['producerUnitTestCount'] == 5 and
            ref['productsUnchanged'] is True, 'consumer source/tuple/local-unit reference mismatch')
    job = next(j for j in jobs if j['id'] == consumer['jobID'])
    require(job['head_sha'] == source.head and job['run_id'] == rid and job['runner_name'] == consumer['runnerName'], 'consumer native/API job binding')
    isolation = load(root / 's10-4-shared-isolation.json')
    require(isolation['createdByThisJob'] is True and isolation['preexistingDevice'] is False and
            all(isolation[k] == consumer[k] for k in ('runID', 'jobID', 'simulatorUDID', 'isolationID')) and
            digest(canonical(isolation)) == ref['isolationReceiptSHA256'], 'fresh consumer Simulator binding missing')
    qualification = payload.qualification(root / 'shared-producer/unit-proof', source.identity)
    require(payload.object_sha(qualification) == ref['producerQualificationSHA256'], 'consumer producer-five reference changed')
    seal = load(root / 'shared-producer/shared-build-seal.json')
    require(payload.object_sha(seal['sharedBuildIdentity']) == ref['sharedBuildIdentitySHA256'] and
            seal['sharedBuildIdentity']['source'] == source.identity and seal['sharedBuildIdentity']['products'] == ref['products'] and
            seal['producerQualificationSHA256'] == ref['producerQualificationSHA256'], 'consumer shared payload identity changed')
    if intent.get('producerProof'):
        require(all(ref[k] == intent['producerProof'][k] for k in ('sharedBuildIdentitySHA256', 'producerQualificationSHA256')),
                'consumer differs from selected dispatch payload')
    command_value = load(root / 's10-4-shared-ui-command.json')
    require(command_value == ref['uiCommand'] and log.count('Command line invocation:') == 1, 'consumer native command record mismatch')
    import shlex
    actual = shlex.split(log.split('Command line invocation:\n', 1)[1].splitlines()[0]); actual[0] = 'xcodebuild'
    require(actual == command_value, 'actual native command differs')
    hosted_command(payload, command_value, 'test-without-building', ref['xctestrunPath'], consumer['simulatorUDID'])
    require(not (root / 'UnitTests.xcresult').exists() and not (root / 'Build.xcresult').exists(), 'falsely local build/units')
    result.update(consumerReferenceVerified=True, consumer=consumer, producerUnitCount=5, uiCommand=command_value,
                  sharedBuildIdentitySHA256=ref['sharedBuildIdentitySHA256'], producerQualificationSHA256=ref['producerQualificationSHA256'])
    native_path = root / 'ui-test-results.json'
    if not native_path.exists():
        native_path = root / 'ui-failure-diagnostics/xcresult-test-results.json'
    if not native_path.exists():
        result['gaps'].append('Native UI result export missing.')
        return result
    native = load(native_path)
    cases = [r for r in nodes(native) if r.get('nodeType') == 'Test Case']
    failures = [r.get('name') for r in nodes(native) if r.get('nodeType') == 'Failure Message']
    system_cases = [r for r in cases if re.fullmatch(r'FieldEvidenceAppUITests-Runner \(\d+\) encountered an error', r.get('nodeIdentifier', '')) and r.get('result') == 'Failed']
    if not cases or len(system_cases) == len(cases):
        require(not events and job['conclusion'] == 'failure', 'zero-test result carries native state evidence or successful worker')
        result.update(nativeTests=[], nativeSystemFailureCases=system_cases, nativeFailures=failures, nativeUIExecuted=False,
                      nativeBootstrapFailure=True, nativeDevices=native.get('devices', []),
                      nativeRuntimeWarnings=[r.get('name') for r in nodes(native) if r.get('nodeType') == 'Runtime Warning'])
        result.update(native_database_facts(root))
        result['gaps'].append('Native bootstrap produced zero selected tests; no test body, states or journeys executed.')
        return result
    require(len(cases) == 1 and cases[0]['nodeIdentifier'].removesuffix('()') == kernel.UI_ID, 'native UI method cardinality/identity')
    devices = native.get('devices', [])
    expected = {'deviceId': consumer['simulatorUDID'], 'deviceName': ctx['device']['simulatorName'],
                'osVersion': ctx['device']['simulatorRuntime'].removeprefix('iOS '), 'osBuildNumber': ctx['device']['simulatorRuntimeBuild'],
                'architecture': 'arm64', 'platform': 'iOS Simulator'}
    require(len(devices) == 1 and all(devices[0].get(k) == v for k, v in expected.items()), 'native exact consumer device mismatch')
    result.update(nativeTests=cases, nativeFailures=failures, nativeDevices=devices,
                  nativeRuntimeWarnings=[r.get('name') for r in nodes(native) if r.get('nodeType') == 'Runtime Warning'])
    ax = events.get('S10_4_AX_STATE', []); contrast = events.get('S10_4_CONTRAST', [])
    verify_state_pairs(source, ctx, ax, contrast)
    row = source.tuple('consumer', intent['shardID'], intent['segmentID'])
    owned = source.plan['orderedStateIDs'] if row['segmentID'] == 'none' else next(s['ownedStateIDs'] for s in ctx['segments'] if s['segmentID'] == row['segmentID'])
    require([r['stateID'] for r in ax] == owned[:len(ax)], 'strict owned states not source prefix')
    journeys = events.get('S10_4_MINIMUM_SEGMENT_JOURNEY', [])
    result.update(strictStateRowCount=len(ax), replayCount=len(replay),
                  ownedJourneyCount=sum(r.get('setupOnly') is False for r in journeys),
                  requiredOwnedStates=row['owned'], requiredReplayStates=row['replay'])
    attachment_dir = root / 'ui-failure-attachments'
    if not attachment_dir.exists():
        attachment_dir = root / 's10-4-shared-raw-attachments'
    if not attachment_dir.exists():
        attachment_dir = root / 's10-4' / row['shardID'] / 'original-attachments'
    manifest_path = attachment_dir / 'manifest.json'
    full_exports = None
    shard_root = root / 's10-4' / row['shardID']
    if not manifest_path.exists() and row['segmentID'] == 'none' and (shard_root / 'xcresult-attachment-manifest.json').exists():
        manifest_path = shard_root / 'xcresult-attachment-manifest.json'
        full_exports = load(shard_root / 'candidate-exports.json')
    candidates = []
    if manifest_path.exists():
        exports = [e for t in load(manifest_path) for e in t['attachments']]
        if full_exports is None:
            require({p.name for p in attachment_dir.iterdir()} == {'manifest.json'} | {e['exportedFileName'] for e in exports}, 'exported attachment closure differs')
        db = root / 'UISmoke.xcresult/database.sqlite3'; original_db = sha(db)
        db_uri = Path(str(db).removeprefix('\\\\?\\')).resolve().as_uri()
        connection = sqlite3.connect(db_uri + '?mode=ro&immutable=1', uri=True); connection.row_factory = sqlite3.Row
        try:
            attachments = [dict(r) for r in connection.execute('SELECT rowid,* FROM Attachments')]
            result['nativeIssueRows'] = [dict(r) for r in connection.execute('SELECT rowid,* FROM TestIssues')]
            result['nativeSourceLocations'] = [dict(r) for r in connection.execute('SELECT rowid,* FROM SourceCodeLocations')]
        finally:
            connection.close()
        require(sha(db) == original_db, 'native database mutated')
        result['nativeAttachmentRows'] = len(attachments)
        prefix = 'S10.4 candidate ' + row['shardID'] + ' '
        for export in exports:
            name = export['suggestedHumanReadableName']
            if not name.startswith(prefix):
                continue
            matches = [a for a in attachments if a.get('filenameOverride') == name and
                       export['exportedFileName'] in (a['uuid'], a['uuid'] + '.png')]
            require(len(matches) == 1 and matches[0]['testIssue_fk'] is None and export['isAssociatedWithFailure'] is False and
                    export['deviceId'] == consumer['simulatorUDID'], 'candidate native attachment identity/failure mismatch')
            state = candidate_state(name, prefix, owned, [p['stateID'] for p in candidates])
            candidate_path = attachment_dir / relative(export['exportedFileName'])
            if full_exports is not None:
                require({'stateID': state, 'exportedFileName': export['exportedFileName']} in full_exports, 'full candidate export mapping mismatch')
                candidate_path = shard_root / 'candidates' / (state + '.png')
            info = kernel.png(candidate_path, ctx['minimum'])
            candidates.append({'stateID': state, **info})
        require({r['stateID'] for r in candidates} == {r['stateID'] for r in ax}, 'strict rows lack matching native candidate PNGs')
        result.update(candidatePNGCount=len(candidates), strictOwnedCount=len(candidates), candidatePNGs=candidates)
        if not exports:
            result['gaps'].append('Original attachment export manifest empty; no failure screenshot or hierarchy.')
    elif ax:
        result['gaps'].append('Strict state markers have no exported candidate PNG/native binding; count not accepted.')
    if cases[0]['result'] != 'Passed':
        result['gaps'].append('Native UI failed; no complete segment or full shard.')
    return result


def full_shard_proof(source, root, intent, facts):
    root = wide(root); shard = intent['shardID']; ctx = source.context(shard)
    stored = root / 's10-4' / shard; receipt = load(stored / 'shard-receipt.json')
    require(facts['consumerReferenceVerified'] and len(facts['nativeTests']) == 1 and facts['nativeTests'][0]['result'] == 'Passed' and
            facts['strictOwnedCount'] == facts['candidatePNGCount'] == 67, 'full native state/PNG closure missing')
    source.assembler.native_ui(root, facts['consumer'], ctx)
    for key, expected in {'taskID': 'S10.4', 'productHead': source.head, 'shardID': shard,
                          'requirementID': ctx['shard']['requirementID'], 'deviceProfileID': ctx['shard']['deviceProfileID'],
                          'runtime': ctx['device']['simulatorRuntime'], 'runtimeBuild': ctx['device']['simulatorRuntimeBuild'],
                          'simulatorName': ctx['device']['simulatorName'], 'candidateCount': 67, 'stateAXRowCount': 67,
                          'contrastRowCount': 67, 'accessibilityRowCount': 6, 'localUnitExecutedTestCount': 0,
                          'producerUnitExecutedTestCount': 5, 'executionModel': 'shared-native-v1',
                          'unitEvidenceOrigin': 'shared-producer'}.items():
        require(receipt.get(key) == expected, 'full shard receipt field mismatch: ' + key)
    require(receipt['sharedExecution'] == load(root / 'shared-consumer/consumer-build-reference.json') and
            all(receipt[k] == facts[k] for k in ('sharedBuildIdentitySHA256', 'producerQualificationSHA256')), 'full shard payload binding')
    manifest = load(source.root / 'docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json')
    require(receipt['github_environment'] == manifest['github_environment_contract'], 'full shard pinned GitHub environment mismatch')
    ax = facts['nativeEvents']['S10_4_AX_STATE']; contrast = facts['nativeEvents']['S10_4_CONTRAST']
    require(load(stored / 'state-ax.json') == ax and load(stored / 'contrast.json') == contrast, 'full retained rows differ from native stdout')
    require({r['stateID'] for r in ax} == set(source.plan['orderedStateIDs']), 'full67state identity mismatch')
    candidates = load(stored / 'candidate-files.json')
    require(len(candidates) == 67 and {r['stateID'] for r in candidates} == set(source.plan['orderedStateIDs']), 'full candidate list closure')
    for row in candidates:
        require(row['artifactPath'] == 'candidates/' + row['stateID'] + '.png', 'full candidate path substitution')
        info = source.assembler.png(stored / row['artifactPath'], ctx['minimum'])
        require(row['sha256'] == info['sha256'] and row['bytes'] == info['bytes'], 'full candidate digest/size mismatch')
    tasks = load(stored / 'accessibility.json'); contract = load(source.root / 'docs/design/s10/s10-accessibility-common-tasks.json')['tasks']
    require(len(tasks) == 6 and {t['taskID'] for t in tasks} == {t['task_id'] for t in contract}, 'full six-task identity mismatch')
    by_state = {r['stateID']: r for r in ax}
    for task in tasks:
        expected = next(t for t in contract if t['task_id'] == task['taskID']); states = sorted(expected['screen_state_ids'])
        require(task['shardID'] == shard and task['deviceProfileID'] == ctx['shard']['deviceProfileID'] and
                task['stateCount'] == len(states) and task['stateSetSHA256'] == digest('\n'.join(states).encode()) and
                task['stateAXTreeDigests'] == [{'stateID': s, 'axTreeSHA256': by_state[s]['axTreeSHA256']} for s in states] and
                task['aggregateAXTreeSHA256'] == digest('\n'.join(s + '|' + by_state[s]['axTreeSHA256'] for s in states).encode()),
                'full task native state digest binding mismatch')
        require(load(root / 'accessibility' / shard / (task['taskID'] + '.json')) == dict(task, sourceProductHead=source.head), 'full raw task differs')
    for category, rows in [('ax', ax), ('contrast', contrast)]:
        target = root / category / shard
        require({p.name for p in target.iterdir()} == {r['stateID'] + '.json' for r in rows}, 'full raw state closure')
        for row in rows:
            require(load(target / (row['stateID'] + '.json')) == dict(row, sourceProductHead=source.head), 'full raw state differs')
    return {'fullShardComplete': True, 'fullShardReceiptSHA256': sha(stored / 'shard-receipt.json'),
            'commonTaskCount': 6, 'formalAcceptance': False, 'humanReviewGranted': False,
            'nativePayloadDecompressionEqualityVerified': False,
            'nativeBindingScope': 'Original exported names/native SQLite identities and source-collected PNG digests; no compressed-payload decoding.'}


def audit(matrix, request_id, known_deterministic=False):
    folder = request_path(matrix, request_id)
    record = next(r for r in records(matrix, True) if r['path'] == folder)
    require(record['resolution'] is not None, 'cannot audit unresolved request')
    intent = record['intent']; rid = record['resolution']['runID']; originals = original_root(record)
    source = matrix.source(intent['head']); original = collection_proof(matrix, originals, intent, rid)
    prior_audits = [load(path) for path in (folder / 'audits').glob('*.json')]
    require(all(a['runID'] == rid and a['head'] == intent['head'] and
                a['originalFilesSHA256'] == original['originalFilesSHA256'] for a in prior_audits), 'prior audit provenance changed')
    inherited_deterministic = any(a.get('knownDeterministicFailure') is True for a in prior_audits)
    jobs = load(originals / 'jobs.json')['jobs']; artifacts = load(originals / 'artifacts.json')['artifacts']
    log_rows = []
    for job in jobs:
        if job['conclusion'] == 'skipped':
            continue
        text = (originals / ('job-' + str(job['id']) + '.log')).read_text(encoding='utf-8')
        log_rows.append({'jobID': job['id'], 'name': job['name'], 'conclusion': job['conclusion'],
                         'startedAt': job['started_at'], 'completedAt': job['completed_at'],
                         'elapsedSeconds': (utc(job['completed_at']) - utc(job['started_at'])).total_seconds(),
                         'steps': job['steps'], 'logBytes': len(text.encode()),
                         'budgetLines': [line for line in text.splitlines() if re.search(r'Z (?:elapsed_seconds|total_budget_seconds)=', line)],
                         'failureAndWarningLines': [line for line in text.splitlines() if re.search(r'error:|warning:|Code=56|Test Case.*failed|\*\* TEST .*FAILED', line)]})
    result = dict(original, contractID=CONTRACT, auditedAt=now(), completeOriginalAudit=True,
                  knownDeterministicFailure=True if known_deterministic or inherited_deterministic else None,
                  deterministicClassificationBy='explicit root audit invocation' if known_deterministic else
                      ('preserved append-only prior finding' if inherited_deterministic else 'not classified'),
                  sourceFilesVerified=len(source.identity['files']), jobs=log_rows,
                  compilationPassed=False, producerUnitCount=0, localUnitCount=0, nativeUIExecuted=False,
                  fullSegmentComplete=False, fullShardComplete=False, formalAcceptance=False, humanReviewGranted=False)
    transport = Transport(matrix.root, folder / 'audit-api' / uuid.uuid4().hex)
    try:
        if intent['kind'] == 'producer':
            if original['conclusion'] == 'success' and not original['gaps']:
                _, proof = producer_proof(matrix, source, transport, rid)
                result.update(producerQualified=True, compilationPassed=True, producerUnitCount=5, producerProof=proof)
            else:
                result['producerQualified'] = False
        elif intent['kind'] == 'consumer':
            name = 'ios-ci-shared-' + str(rid) + '-1-' + intent['shardID'] + '-' + intent['segmentID']
            found = [a for a in artifacts if a['name'] == name]
            if found:
                require(len(found) == 1, 'ambiguous consumer original artifact')
                root = originals / str(found[0]['id']) / 'artifact'
                native = consumer_facts(source, root, intent, rid, jobs)
                gaps = result['gaps'] + native.pop('gaps'); result.update(native); result['gaps'] = gaps
                result['nativeUIExecuted'] = bool(result.get('nativeTests'))
                if original['conclusion'] == 'success' and not original['gaps']:
                    if intent['segmentID'] != 'none':
                        producer_id = int(intent['inputs']['s10_4_shared_payload_run_id'])
                        proof_root, proof = producer_proof(matrix, source, transport, producer_id)
                        native_proof = segment_proof(matrix, source, transport, proof_root, intent['shardID'], intent['segmentID'], rid)
                        result.update(fullSegmentComplete=True, segmentSelection=native_proof['selection'], producerProof=proof)
                    else:
                        result.update(full_shard_proof(source, root, intent, result))
            else:
                result['gaps'].append('Worker artifact absent; setup/admission failure remains explicit.')
        else:
            producer_id = int(intent['inputs']['s10_4_shared_payload_run_id'])
            proof_root, proof = producer_proof(matrix, source, transport, producer_id)
            mapping = decode(intent['inputs']['s10_4_segment_source_run_ids'])
            selected = [segment_proof(matrix, source, transport, proof_root, intent['shardID'], key, int(value))
                        for key, value in sorted(mapping.items())]
            require(len(selected) == 3 and selected[2]['receipt']['sourceDependencySelections'] == [r['selection'] for r in selected[:2]],
                    'assembly continuity changed')
            roots = [originals / str(a['id']) / 'artifact' for a in artifacts]
            receipts = [p for root in roots for p in root.rglob('shard-receipt.json')
                        if '/segment-sources/' not in p.as_posix()]
            require(len(receipts) == 1, 'assembly full shard receipt absent/ambiguous')
            receipt = load(receipts[0])
            require(original['conclusion'] == 'success' and not original['gaps'] and receipt['complete'] is True and
                    receipt['productHead'] == source.head and receipt['shardID'] == intent['shardID'] and
                    receipt['candidateCount'] == receipt['stateAXRowCount'] == receipt['contrastRowCount'] == 67 and
                    receipt['accessibilityRowCount'] == 6 and receipt['sharedBuildIdentitySHA256'] == proof['sharedBuildIdentitySHA256'],
                    'assembly original receipt not complete exact proof')
            require(load(receipts[0].parent / 'source-segment-receipts.json') == [s['receipt'] for s in selected], 'assembly source receipt copies changed')
            require(load(receipts[0].parent / 'state-ax.json') == [r for s in selected for r in s['rows']['ax']] and
                    load(receipts[0].parent / 'contrast.json') == [r for s in selected for r in s['rows']['contrast']], 'assembly original row union changed')
            for segment in selected:
                for candidate in segment['candidates']:
                    require(sha(receipts[0].parent / candidate['artifactPath']) == candidate['sha256'], 'assembly PNG union differs')
            result.update(fullShardComplete=True, strictOwnedCount=67, commonTaskCount=6,
                          producerUnitCount=5, producerProof=proof, distinctNativeSessions=3,
                          nativeUIExecuted=False, assemblyIsNativeExecution=False)
    except (Rejected, OSError, ValueError, KeyError, TypeError, RuntimeError, source.payload.PayloadError, source.assembler.Rejected) as error:
        result['gaps'].append(type(error).__name__ + ': ' + str(error))
        result['completeOriginalAudit'] = False
    after = collection_proof(matrix, originals, intent, rid)
    require(after['originalFilesSHA256'] == original['originalFilesSHA256'], 'original files changed while auditing')
    result['formalAcceptance'] = False; result['humanReviewGranted'] = False
    output = folder / 'audits' / (dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex + '.json')
    save(output, result)
    return result


def summary(matrix):
    rows = []
    for record in records(matrix, True):
        intent = record['intent']; resolution = record['resolution']
        audits = sorted((record['path'] / 'audits').glob('*.json'))
        latest = load(audits[-1]) if audits else {}
        rows.append({'requestID': intent['requestID'], 'head': intent['head'], 'kind': intent['kind'],
                     'shardID': intent['shardID'], 'segmentID': intent['segmentID'],
                     'runID': resolution['runID'] if resolution else None, 'conclusion': latest.get('conclusion'),
                     'compilationPassed': latest.get('compilationPassed'), 'producerUnitCount': latest.get('producerUnitCount'),
                     'localUnitCount': latest.get('localUnitCount'), 'nativeUIExecuted': latest.get('nativeUIExecuted'),
                     'strictOwnedCount': latest.get('strictOwnedCount'), 'fullSegmentComplete': latest.get('fullSegmentComplete', False),
                     'fullShardComplete': latest.get('fullShardComplete', False), 'gaps': latest.get('gaps', ['Not terminal-audited.']),
                     'formalAcceptance': False, 'humanReviewGranted': False})
    return {'observedAt': now(), 'liveStatusQueried': False, 'rows': rows,
            'scope': 'Recorded original facts only; dispatch independently refreshes live history/capacity.'}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    inv = sub.add_parser('inventory'); inv.add_argument('--root', required=True); inv.add_argument('--head', required=True)
    for name in ('dispatch', 'reconcile', 'import', 'collect', 'audit', 'summary'):
        command_parser = sub.add_parser(name); command_parser.add_argument('--matrix', required=True)
        if name in ('reconcile', 'collect', 'audit'):
            command_parser.add_argument('--request', required=True)
        if name == 'audit':
            command_parser.add_argument('--known-deterministic', action='store_true', help='Explicit root forensic classification from originals; blocks same-head retries')
        if name == 'dispatch':
            command_parser.add_argument('--kind', choices=tuple(LANES), required=True)
            command_parser.add_argument('--shard', default='none'); command_parser.add_argument('--segment', default='none')
            command_parser.add_argument('--question', required=True); command_parser.add_argument('--dependency', action='append', default=[])
            command_parser.add_argument('--retry', type=int); command_parser.add_argument('--retry-kind', choices=('hosted-infrastructure', 'runtime-crash', 'unknown-native-cause'))
            command_parser.add_argument('--reason')
        if name == 'import':
            command_parser.add_argument('--record', required=True); command_parser.add_argument('--returned', required=True)
            command_parser.add_argument('--originals')
    args = parser.parse_args(argv)
    if args.command == 'inventory':
        source = Source(absolute(args.root), args.head)
        result = {'head': source.head, 'mainSHA': source.main, 'source': source.identity, 'tuples': source.tuples,
                  'formalAcceptance': False}
    else:
        matrix = Matrix(args.matrix)
        if args.command == 'dispatch': result = dispatch(matrix, args)
        elif args.command == 'reconcile': result = resolve(matrix, args.request)
        elif args.command == 'import': result = import_record(matrix, args)
        elif args.command == 'audit': result = audit(matrix, args.request, args.known_deterministic)
        elif args.command == 'summary': result = summary(matrix)
        else:
            record = next(r for r in records(matrix, True) if r['path'] == request_path(matrix, args.request))
            require(record['resolution'] is not None, 'cannot collect unresolved request')
            result = terminal_collection(matrix, record, Transport(matrix.root, record['path'] / 'collection-api'))
    print(json.dumps(result, indent=2, ensure_ascii=True, allow_nan=False))
    return result


if __name__ == '__main__':
    try:
        main()
    except (Rejected, OSError, ValueError, KeyError, TypeError, StopIteration, RuntimeError) as error:
        print('S10.4 controller rejected: ' + str(error), file=sys.stderr)
        sys.exit(1)
