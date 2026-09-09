#!/usr/bin/env python3
"""Hostile protocol tests. No hosted dispatch, native execution or evidence minting.

Optional read-only real originals: S10_4_FIXTURE_ROOT=C:/AssetRounds.
All mutations are disposable fixtures beneath this script's project Temp.
"""
import copy
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch
import zipfile

sys_path = Path(__file__).with_name('s10-4-ci.py')
spec = importlib.util.spec_from_file_location('tested_s10_4_ci', sys_path)
ci = importlib.util.module_from_spec(spec); spec.loader.exec_module(ci)
H = '1' * 40
P = '2' * 40
SHARD = 's10.4.minimum.minimum-os'


def row(kind='consumer', segment='minimum-segment-1'):
    return {'kind': kind, 'shardID': SHARD if kind != 'producer' else 'none',
            'segmentID': segment if kind != 'producer' else 'none',
            'provider': 'bitrise' if kind == 'producer' else 'github', 'dependencies': [], 'owned': 22, 'replay': 0}


def intent(rid=3, kind='consumer', segment='minimum-segment-1'):
    value = row(kind, segment)
    value.update(contractID=ci.CONTRACT, requestID='a' * 32, repository=ci.REPO, ref=ci.REF,
                 head=H, mainSHA=P, recordedAt='2026-09-01T00:00:00Z', sourceIdentitySHA256='A' * 64,
                 inputs=ci.inputs(value, None if kind == 'producer' else 2, {}))
    return value


def run(rid=3, value=None, status='completed', conclusion='failure'):
    value = value or intent(rid)
    return {'id': rid, 'head_sha': value['head'], 'head_branch': ci.REF, 'path': '.github/workflows/ios-ci.yml',
            'event': 'workflow_dispatch', 'run_attempt': 1, 'created_at': value['recordedAt'],
            'html_url': 'https://github.com/' + ci.REPO + '/actions/runs/' + str(rid),
            'repository': {'id': 77, 'full_name': ci.REPO}, 'head_repository': {'id': 77, 'full_name': ci.REPO},
            'display_title': 'iOS CI · lane=' + value['inputs']['execution_lane'] + ' · shard=' + value['shardID'] + ' · head=' + value['head'],
            'status': status, 'conclusion': conclusion}


def registered(rid, value):
    return {'intent': value, 'resolution': {'runID': rid}}


class Protocol(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[1] / 'Temp/S10_4_ci_protocol_tests'
        root.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=root)
        self.path = Path(self.temp.name).resolve()
        self.assertTrue(self.path.is_relative_to(root.resolve()))
        self.addCleanup(self.temp.cleanup)

    def unavailable_export_fixture(self):
        root = self.path / ('native-' + str(len(list(self.path.iterdir()))))
        diagnostic = root / 'ui-failure-diagnostics'; diagnostic.mkdir(parents=True)
        native = diagnostic / 'xcresult-test-results.json'; native.write_bytes(b'')
        (diagnostic / 'status.txt').write_text('xcresult_test_results=64\nprocess_snapshot=0\n')
        (diagnostic / 'xcresult-test-results.stderr.txt').write_text(
            'Error: Failed to create a new result bundle reader, underlying error: Info.plist at '
            '/runner/UISmoke.xcresult/Info.plist does not exist, the result bundle might be corrupted or the provided path is not a result bundle\n'
            "Usage: xcresulttool <subcommand>\n  See 'xcresulttool --help' for more information.\n")
        for name in ('Data', 'Staging'): (root / 'UISmoke.xcresult' / name).mkdir(parents=True)
        return {'root': root, 'native_path': native, 'log': '** TEST EXECUTE FAILED **\n', 'events': {},
                'command': ['xcodebuild', '-resultBundlePath', '/runner/UISmoke.xcresult'],
                'job': {'conclusion': 'failure'}, 'run_conclusion': 'failure'}

    def test_unavailable_native_export_preserves_unknown_counts(self):
        args = self.unavailable_export_fixture(); result = ci.unavailable_native_export(**args)
        for key in ('nativeUIExecuted', 'nativeTests', 'nativeFailures', 'strictOwnedCount', 'replayCount',
                    'ownedJourneyCount', 'candidatePNGCount', 'nativeAttachmentRows'):
            self.assertIsNone(result[key])
        self.assertTrue(result['nativeResultUnavailable']); self.assertTrue(result['nativeDatabaseMissing'])
        self.assertEqual(result['observedTestBodyMarkerCount'], 0)
        self.assertEqual(result['nativeExportFailure']['sha256'], ci.digest(b''))
        self.assertEqual(result['nativeExportFailure']['status'], 64)

    def test_unavailable_native_export_rejects_contradictory_evidence(self):
        mutations = {
            'successful run': lambda a: a.update(run_conclusion='success'),
            'unknown run': lambda a: a.update(run_conclusion=None),
            'canceled run': lambda a: a.update(run_conclusion='cancelled'),
            'successful worker': lambda a: a['job'].update(conclusion='success'),
            'nonempty malformed export': lambda a: a['native_path'].write_text('{'),
            'competing export': lambda a: (a['root'] / 'ui-test-results.json').write_text('{}'),
            'missing export status': lambda a: (a['native_path'].parent / 'status.txt').write_text('process_snapshot=0\n'),
            'duplicate export status': lambda a: (a['native_path'].parent / 'status.txt').write_text('xcresult_test_results=64\nxcresult_test_results=64\n'),
            'successful export status': lambda a: (a['native_path'].parent / 'status.txt').write_text('xcresult_test_results=0\n'),
            'conflicting export status': lambda a: (a['native_path'].parent / 'status.txt').write_text('xcresult_test_results=64\nxcresult_test_results=0\n'),
            'malformed status': lambda a: (a['native_path'].parent / 'status.txt').write_text(' xcresult_test_results=64\n'),
            'foreign result path': lambda a: a.update(command=['xcodebuild', '-resultBundlePath', '/foreign/UISmoke.xcresult']),
            'different export error': lambda a: (a['native_path'].parent / 'xcresult-test-results.stderr.txt').write_text('other failure'),
            'present plist': lambda a: (a['root'] / 'UISmoke.xcresult/Info.plist').write_text('present'),
            'present database': lambda a: (a['root'] / 'UISmoke.xcresult/database.sqlite3').write_bytes(b'present'),
            'state event': lambda a: a.update(events={'S10_4_AX_STATE': [{}]}),
            'test body': lambda a: a.update(log="Test Case 'selected' started.\n** TEST EXECUTE FAILED **\n"),
            'migration state': lambda a: a.update(log='S10_MIGRATION_STATE state=state.a\n** TEST EXECUTE FAILED **\n'),
            'malformed native marker': lambda a: a.update(log='S10_4_AX_STATE {broken\n** TEST EXECUTE FAILED **\n'),
            'missing failure outcome': lambda a: a.update(log='incomplete log'),
            'receipt directory': lambda a: (a['root'] / 's10-4').mkdir(),
            'raw attachment directory': lambda a: (a['root'] / 's10-4-shared-raw-attachments').mkdir(),
            'attachment directory': lambda a: (a['root'] / 'ui-failure-attachments').mkdir(),
            'candidate image': lambda a: (a['root'] / 'ui-final.png').write_bytes(b'candidate'),
        }
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                args = self.unavailable_export_fixture(); mutate(args)
                with self.assertRaises(ci.Rejected): ci.unavailable_native_export(**args)

    def test_audit_keeps_unknown_native_execution_and_nonaccepting_gap(self):
        selected = intent(); folder = self.path / 'registry/requests' / selected['requestID']; folder.mkdir(parents=True)
        record = {'path': folder, 'intent': selected, 'resolution': {'runID': 3}}
        originals = folder / 'originals'; originals.mkdir()
        job = {'id': 4, 'name': 'worker', 'conclusion': 'failure', 'started_at': '2026-09-01T00:00:00Z',
               'completed_at': '2026-09-01T00:00:01Z', 'steps': []}
        ci.save(originals / 'jobs.json', {'jobs': [job]})
        ci.save(originals / 'artifacts.json', {'artifacts': [{'id': 5,
            'name': 'ios-ci-shared-3-1-' + SHARD + '-minimum-segment-1'}]})
        (originals / 'job-4.log').write_text('original failed worker log')
        source = types.SimpleNamespace(identity={'files': []}, payload=types.SimpleNamespace(PayloadError=RuntimeError),
                                       assembler=types.SimpleNamespace(Rejected=RuntimeError))
        matrix = types.SimpleNamespace(root=self.path, registry=self.path / 'registry', source=lambda head: source)
        original = {'runID': 3, 'head': H, 'conclusion': 'failure', 'originalFilesSHA256': 'A' * 64, 'gaps': []}
        native = ci.unavailable_native_export(**self.unavailable_export_fixture())
        native.update(gaps=['Native result unavailable.'], fullSegmentComplete=False, fullShardComplete=False)
        with patch.object(ci, 'records', return_value=[record]), patch.object(ci, 'collection_proof', return_value=original), \
             patch.object(ci, 'Transport'), patch.object(ci, 'consumer_facts', return_value=native) as consumer:
            result = ci.audit(matrix, selected['requestID'])
        self.assertEqual(consumer.call_args.args[-1], 'failure')
        self.assertTrue(result['completeOriginalAudit']); self.assertIsNone(result['nativeUIExecuted'])
        self.assertEqual(result['gaps'], ['Native result unavailable.'])
        for key in ('fullSegmentComplete', 'fullShardComplete', 'formalAcceptance', 'humanReviewGranted'):
            self.assertIs(result[key], False)

    def test_history_git_offset_and_checkout_instant_boundaries(self):
        ci.git(self.path, 'init')
        with patch.dict(os.environ, {'GIT_AUTHOR_DATE': '2026-09-08T22:44:26-04:00',
                                    'GIT_COMMITTER_DATE': '2026-09-08T22:44:26-04:00'}):
            ci.git(self.path, '-c', 'user.name=Protocol Test', '-c', 'user.email=protocol@example.invalid',
                   '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-m', 'Timezone fixture')
        head = ci.git(self.path, 'rev-parse', 'HEAD').decode().strip()
        self.assertEqual(ci.git(self.path, 'show', '-s', '--format=%cI', head).decode().strip(),
                         '2026-09-08T22:44:26-04:00')
        matrix = types.SimpleNamespace(root=self.path, head=head)
        proposed = intent(kind='producer'); proposed['head'] = head
        empty = types.SimpleNamespace(pages=lambda *args: [])
        self.assertEqual(ci.check_history(matrix, empty, proposed, [])[1]['oldCheckoutRunIDs'], [])
        previous = intent(); previous['head'] = H
        active = run(value=previous, status='in_progress', conclusion=None)
        for when, allowed in [('2026-09-09T02:44:25Z', True), ('2026-09-09T02:44:26Z', True),
                              ('2026-09-09T02:44:27Z', False), ('2026-09-08T22:44:26-04:00', False)]:
            def pages(endpoint, key):
                if endpoint.startswith('actions/runs?status=in_progress&'): return [active]
                if endpoint.startswith('actions/runs/3/jobs?'):
                    return [{'name': 'acceptance · fixture', 'conclusion': None, 'head_sha': H,
                             'steps': [{'name': 'Check out the exact revision', 'conclusion': 'success',
                                        'completed_at': when}]}]
                return []
            with self.subTest(when=when):
                transport = types.SimpleNamespace(pages=pages)
                if allowed:
                    self.assertEqual(ci.check_history(matrix, transport, proposed, [registered(3, previous)])[1]['oldCheckoutRunIDs'], [3])
                else:
                    with self.assertRaises(ci.Rejected): ci.check_history(matrix, transport, proposed, [registered(3, previous)])

    def test_history_rejects_malformed_git_epoch(self):
        matrix = types.SimpleNamespace(root=self.path, head=H)
        transport = types.SimpleNamespace(pages=lambda *args: [])
        for raw in (b'', b'2026-09-08T22:44:26-04:00', b'-1', b'+1', b'01', b'1.0',
                    b'1\n2', b'253402300800', b'999999999999999999999'):
            with self.subTest(raw=raw), patch.object(ci, 'git', return_value=raw), self.assertRaises(ci.Rejected):
                ci.check_history(matrix, transport, intent(kind='producer'), [])

    def test_candidate_native_name_decorations_and_hostiles(self):
        prefix = 'S10.4 candidate s10.4.current.default-light '
        state = 'state.subscription.no-entitlement'
        uuid = 'B5ADB6F6-8CF8-48AC-A80E-AB2BCB28707B'
        for name in (state, state + '.png', state + '_0_' + uuid + '.png',
                     'state.subscription_0_' + uuid + '.no-entitlement'):
            with self.subTest(name=name):
                self.assertEqual(ci.candidate_state(prefix + name, prefix, [state], []), state)
                with self.assertRaises(ci.Rejected): ci.candidate_state(prefix + name, prefix, [state], [state])
        for name in ('state.foreign', state + '_0_' + uuid, state + '_1_' + uuid + '.png',
                     state + '_0_' + '-' * 36 + '.png', state + '_0_' + uuid[:-1] + '.png',
                     state + '_0_' + uuid.replace('B', 'G') + '.png',
                     'state.subscription_0_' + uuid + '.no-entitlement_0_' + uuid + '.png',
                     'state_0_' + uuid + '.subscription.no-entitlement', state + '.png.png'):
            with self.subTest(name=name), self.assertRaises(ci.Rejected):
                ci.candidate_state(prefix + name, prefix, [state], [])
        with self.assertRaises(ci.Rejected):
            ci.candidate_state(prefix.replace('default-light', 'default-dark') + state, prefix, [state], [])

    def test_replay_source_families_and_hostiles(self):
        source = types.SimpleNamespace(head=H)
        for minimum in (False, True):
            shard = SHARD if minimum else 's10.4.current.ax-text'
            segment = 'minimum-segment-2' if minimum else 'segment-2'
            ctx = {'minimum': minimum, 'segments': [{'segmentID': segment, 'replayStateIDs': ['state.a', 'state.b']}]}
            selected = {'shardID': shard, 'segmentID': segment}
            prefix = 'S10_4_MINIMUM_SEGMENT_' if minimum else 'S10_4_SEGMENT_'
            foreign = 'S10_4_SEGMENT_' if minimum else 'S10_4_MINIMUM_SEGMENT_'
            rows = [{'ordinal': i, 'stateID': state, 'segmentID': segment, 'shardID': shard}
                    for i, state in enumerate(['state.a', 'state.b'], 1)]
            if minimum:
                for value in rows: value.update(setupOnly=True, acceptanceEligible=False, head=H)
            self.assertEqual(ci.replay_rows(source, ctx, selected, {prefix + 'REPLAY': rows}), rows)
            self.assertEqual(ci.replay_rows(source, ctx, selected, {prefix + 'REPLAY': rows[:1]}), rows[:1])
            hostile = [list(reversed(rows)), rows + [rows[0]], [rows[0], rows[0]], ['invalid'], None]
            for key, value in [('ordinal', True), ('ordinal', 2), ('stateID', 'state.foreign'),
                               ('segmentID', 'segment-3'), ('shardID', 's10.4.current.default-light')]:
                changed = copy.deepcopy(rows); changed[0][key] = value; hostile.append(changed)
            changed = copy.deepcopy(rows); del changed[0]['ordinal']; hostile.append(changed)
            if minimum:
                for key, value in [('setupOnly', False), ('acceptanceEligible', True), ('head', '3' * 40)]:
                    changed = copy.deepcopy(rows); changed[0][key] = value; hostile.append(changed)
                    changed = copy.deepcopy(rows); del changed[0][key]; hostile.append(changed)
            else:
                changed = copy.deepcopy(rows); changed[0]['head'] = H; hostile.append(changed)
            for changed in hostile:
                with self.subTest(minimum=minimum, rows=changed), self.assertRaises(ci.Rejected):
                    ci.replay_rows(source, ctx, selected, {prefix + 'REPLAY': changed})
            for events in ({foreign + 'REPLAY': rows}, {prefix + 'REPLAY': rows, foreign + 'REPLAY': rows},
                           {foreign + 'JOURNEY': []}):
                with self.subTest(events=events), self.assertRaises(ci.Rejected):
                    ci.replay_rows(source, ctx, selected, events)
            with self.assertRaises(ci.Rejected):
                ci.replay_rows(source, ctx, dict(selected, segmentID='none'), {prefix + 'REPLAY': rows})

    def test_malformed_segment_lines_reject_before_missing_reference(self):
        ctx = {'minimum': False, 'segments': []}
        source = types.SimpleNamespace(head=H, assembler=object(), payload=object(), context=lambda _: ctx)
        selected = {'shardID': 's10.4.current.ax-text', 'segmentID': 'segment-2'}
        for suffix in ('[]', 'null', '1', '"text"', '{', '{} trailing', ''):
            for prefix in ('S10_4_SEGMENT_REPLAY', 'S10_4_MINIMUM_SEGMENT_REPLAY'):
                with self.subTest(prefix=prefix, suffix=suffix):
                    (self.path / 'ui-smoke.log').write_text(prefix + ' ' + suffix + '\n', encoding='utf-8')
                    with self.assertRaises(ci.Rejected): ci.consumer_facts(source, self.path, selected, 3, [])
        (self.path / 'ui-smoke.log').write_text('S10_4_SEGMENT_REPLAY\n', encoding='utf-8')
        with self.assertRaises(ci.Rejected): ci.consumer_facts(source, self.path, selected, 3, [])

    def test_segment_kind_inventory_and_unsegmented_rejection(self):
        source = types.SimpleNamespace(head=H)
        for minimum in (False, True):
            prefix = 'S10_4_MINIMUM_SEGMENT_' if minimum else 'S10_4_SEGMENT_'
            kinds = ['START', 'REPLAY', 'JOURNEY', 'SETUP_WITNESS', 'RESUME_SETUP', 'RESULT',
                     'PURCHASE_PROOF', 'PENDING_RECEIPT_PROOF'] if minimum else ['REPLAY', 'RESUME_SETUP']
            shard = SHARD if minimum else 's10.4.current.ax-text'
            segment = 'minimum-segment-2' if minimum else 'segment-2'
            selected = {'shardID': shard, 'segmentID': segment}
            ctx = {'minimum': minimum, 'segments': [{'segmentID': segment, 'replayStateIDs': ['state.a']}]}
            replay = {'ordinal': 1, 'stateID': 'state.a', 'segmentID': segment, 'shardID': shard}
            if minimum: replay.update(head=H, setupOnly=True, acceptanceEligible=False)
            for kind in kinds:
                value = replay if kind == 'REPLAY' else {}
                events = ci.native_events(prefix + kind + ' ' + json.dumps(value))
                self.assertEqual(ci.replay_rows(source, ctx, selected, events), [replay] if kind == 'REPLAY' else [])
                with self.subTest(minimum=minimum, kind=kind), self.assertRaises(ci.Rejected):
                    ci.replay_rows(source, ctx, dict(selected, segmentID='none'), events)
            events = ci.native_events(prefix + 'REPLAY ' + json.dumps(replay) + '\n' + prefix + 'FOREIGN {}')
            with self.assertRaises(ci.Rejected): ci.replay_rows(source, ctx, selected, events)
        with self.assertRaises(ci.Rejected):
            ci.replay_rows(source, {'minimum': False}, {'shardID': 's10.4.current.default-light', 'segmentID': 'segment-2'},
                           ci.native_events('S10_4_SEGMENT_RESUME_SETUP {}'))

    def test_nonsegment_native_event_parser_is_unchanged(self):
        self.assertEqual(ci.native_events('noise\nS10_4_AX_STATE {"stateID":"state.a"}\nS10_4_OTHER []'),
                         {'S10_4_AX_STATE': [{'stateID': 'state.a'}]})

    def test_duplicate_nonfinite_json_rejected(self):
        for raw in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}'):
            with self.subTest(raw=raw), self.assertRaises(ci.Rejected): ci.decode(raw)

    def test_bool_not_run_id(self):
        for value in (True, False, 0, -2, '3', 3.0):
            with self.subTest(value=value), self.assertRaises(ci.Rejected): ci.positive(value)

    def test_relative_path_hostiles(self):
        for name in ('../a', '/a', 'C:/a', 'a\\b', 'a//b', 'a/./b', 'a/../b', 'a\x00b'):
            with self.subTest(name=name), self.assertRaises(ci.Rejected): ci.relative(name)

    def test_direct_return_must_be_unique_exact(self):
        url = b'https://github.com/Asset-Rounds/AssetRounds/actions/runs/123'
        self.assertEqual(ci.returned_id(url + b'\n'), 123)
        for raw in (b'', url + b'\n' + url, b'created ' + url, url.replace(b'Asset-Rounds', b'foreign'), url + b'?x=1'):
            with self.subTest(raw=raw), self.assertRaises(ci.Rejected): ci.returned_id(raw)

    def test_run_identity_rejects_wrong_provenance(self):
        original = intent(); raw = run(value=original)
        ci.run_identity(raw, original, 3)
        for key, value in [('head_sha', '3' * 40), ('head_branch', 'main'), ('run_attempt', 2),
                           ('event', 'push'), ('display_title', 'iOS CI'), ('created_at', '2026-08-31T23:59:59Z')]:
            altered = dict(raw, **{key: value})
            with self.subTest(key=key), self.assertRaises(ci.Rejected): ci.run_identity(altered, original, 3)
        foreign = copy.deepcopy(raw); foreign['head_repository']['id'] = 99
        with self.assertRaises(ci.Rejected): ci.run_identity(foreign, original, 3)

    def test_source_dependency_input_closure(self):
        selected = dict(row(segment='minimum-segment-3'), dependencies=['minimum-segment-1', 'minimum-segment-2'])
        actual = ci.inputs(selected, 9, {'minimum-segment-2': 12, 'minimum-segment-1': 11})
        self.assertEqual(actual['s10_4_segment_source_run_ids'], '{"minimum-segment-1":"11","minimum-segment-2":"12"}')
        for mapping in ({}, {'minimum-segment-1': 11}, {'minimum-segment-1': 11, 'minimum-segment-2': 11}):
            with self.subTest(mapping=mapping), self.assertRaises(ci.Rejected): ci.inputs(selected, 9, mapping)

    def test_no_silent_producer_replacement(self):
        with self.assertRaises(ci.Rejected): ci.inputs(row('producer'), 9, {})

    def test_hostile_dependency_cli(self):
        self.assertEqual(ci.parse_dependencies(['segment-1=11']), {'segment-1': 11})
        for entries in (['segment-1=0'], ['segment-1=01'], ['segment-1=11', 'segment-1=12'], ['unknown=11']):
            with self.subTest(entries=entries), self.assertRaises(ci.Rejected): ci.parse_dependencies(entries)

    def test_unknown_missing_duplicate_history_rejected(self):
        value = intent(); original = run(value=value); registry = [registered(3, value)]
        proposed = dict(row(segment='minimum-segment-2'), head=H)
        ci.capacity([original], [], registry, proposed)
        for history in ([], [original, original], [original, run(4)]):
            with self.subTest(history=history), self.assertRaises(ci.Rejected): ci.capacity(history, [], registry, proposed)

    def test_active_and_passed_tuple_never_duplicated(self):
        value = intent(); proposed = dict(row(), head=H)
        registry = [registered(3, value)]
        for status, conclusion in [('in_progress', None), ('completed', 'success')]:
            original = run(value=value, status=status, conclusion=conclusion)
            with self.subTest(status=status), self.assertRaises(ci.Rejected): ci.capacity([original], [original] if conclusion is None else [], registry, proposed)

    def test_five_github_boundary(self):
        records = []; active = []
        for index in range(5):
            value = intent(index + 10); value['shardID'] = 'synthetic-distinct-' + str(index)
            value['inputs']['s10_4_shard_id'] = value['shardID']
            records.append(registered(index + 10, value)); active.append(run(index + 10, value, 'in_progress', None))
        proposed = dict(row(segment='minimum-segment-2'), head=H)
        self.assertEqual(ci.capacity(active[:4], active[:4], records[:4], proposed)['proposedCounts']['github'], 5)
        with self.assertRaises(ci.Rejected): ci.capacity(active, active, records, proposed)

    def test_unknown_active_provider_rejected(self):
        with self.assertRaises(ci.Rejected): ci.capacity([], [run(99, status='in_progress', conclusion=None)], [], dict(row(), head=H))

    def make_zip(self, members):
        archive = self.path / ('archive-' + str(len(list(self.path.glob('*.zip')))) + '.zip')
        with zipfile.ZipFile(archive, 'w') as output:
            for name, content in members: output.writestr(name, content)
        return archive

    def test_zip_traversal_and_case_collision(self):
        for members in ([('../escape', b'a')], [('a', b'a'), ('A', b'b')], [('C:/escape', b'a')]):
            archive = self.make_zip(members)
            with self.subTest(members=members), self.assertRaises(ci.Rejected): ci.extract_checked(archive, self.path / 'out')
        self.assertFalse((self.path.parent / 'escape').exists())

    def test_zip_symlink_rejected(self):
        archive = self.path / 'symlink.zip'
        with zipfile.ZipFile(archive, 'w') as output:
            item = zipfile.ZipInfo('link'); item.create_system = 3; item.external_attr = 0o120777 << 16
            output.writestr(item, b'target')
        with self.assertRaises(ci.Rejected): ci.check_archive_bytes(archive)

    def test_idempotent_extraction_never_overwrites(self):
        archive = self.make_zip([('a.txt', b'original')]); output = self.path / 'out'
        ci.extract_checked(archive, output); ci.extract_checked(archive, output)
        (output / 'a.txt').write_bytes(b'changed')
        with self.assertRaises(ci.Rejected): ci.extract_checked(archive, output)
        self.assertEqual((output / 'a.txt').read_bytes(), b'changed')

    def test_manifest_partial_duplicate_and_wrong_digest(self):
        root = self.path / 'manifest'; root.mkdir(); (root / 'a').write_bytes(b'a'); (root / 'b').write_bytes(b'b')
        correct = ci.sha(root / 'a') + '  a\n' + ci.sha(root / 'b') + '  b\n'
        (root / 'SHA256SUMS.txt').write_text(correct); self.assertEqual(ci.manifests(root)[0]['rows'], 2)
        for text in (correct.splitlines()[0] + '\n', correct + correct.splitlines()[0] + '\n', '0' * 64 + '  a\n'):
            (root / 'SHA256SUMS.txt').write_text(text)
            with self.subTest(text=text), self.assertRaises(ci.Rejected): ci.manifests(root)

    def test_cache_detects_same_size_rewrite_with_restored_mtime(self):
        root = self.path / 'evidence'; root.mkdir(); path = root / 'original'; path.write_bytes(b'abc')
        cache = self.path / 'cache'; binding = {'head': H}; facts = {'verified': True}
        ci.remember_verified(root, cache, binding, facts)
        self.assertEqual(ci.reuse_verified(root, cache, binding), facts)
        stat_before = path.stat(); path.write_bytes(b'xyz'); os.utime(path, ns=(stat_before.st_atime_ns, stat_before.st_mtime_ns))
        with self.assertRaises(ci.Rejected): ci.reuse_verified(root, cache, binding)

    def test_cache_unchanged_files_not_rehashed(self):
        root = self.path / 'evidence'; root.mkdir(); path = root / 'original'; path.write_bytes(b'abc')
        cache = self.path / 'cache'; ci.remember_verified(root, cache, {}, {'verified': True})
        actual = ci.sha; called = []
        def observed(path):
            called.append(str(path)); return actual(path)
        with patch.object(ci, 'sha', side_effect=observed): self.assertEqual(ci.reuse_verified(root, cache, {}), {'verified': True})
        self.assertFalse(any(p.endswith('original') for p in called), called)

    def test_cache_source_change_requires_full_validation(self):
        root = self.path / 'evidence'; root.mkdir(); (root / 'original').write_bytes(b'abc')
        cache = self.path / 'cache'; ci.remember_verified(root, cache, {'head': H}, {'verified': True})
        self.assertIsNone(ci.reuse_verified(root, cache, {'head': P}))

    def test_cache_missing_or_extra_evidence_rejected(self):
        root = self.path / 'evidence'; root.mkdir(); (root / 'a').write_bytes(b'a')
        cache = self.path / 'cache'; ci.remember_verified(root, cache, {}, {})
        (root / 'b').write_bytes(b'b')
        with self.assertRaises(ci.Rejected): ci.reuse_verified(root, cache, {})

    def fake_matrix(self):
        source = types.SimpleNamespace(identity={'head': H}, tuple=lambda *args: row('producer'))
        matrix = types.SimpleNamespace(registry=self.path / 'registry', root=self.path, head=H, main=P,
                                       producer=None, identity='A' * 64, fresh=lambda: (source, {'reviewed': True}))
        return matrix

    def test_ambiguous_dispatch_persists_and_cannot_repeat(self):
        matrix = self.fake_matrix()
        args = types.SimpleNamespace(kind='producer', shard='none', segment='none', dependency=[],
                                     question='Does this exact candidate qualify its native producer?', retry=None, retry_kind=None, reason=None)
        with patch.object(ci, 'check_history', return_value=([], {})), patch.object(ci.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0, stdout=b'', stderr=b'')) as process:
            with self.assertRaises(ci.Rejected): ci.dispatch(matrix, args)
            self.assertEqual(process.call_count, 1)
            self.assertTrue((matrix.registry / 'dispatch.gate').exists())
            requests = list((matrix.registry / 'requests').iterdir()); self.assertEqual(len(requests), 1)
            self.assertTrue((requests[0] / 'intent.json').exists())
            self.assertTrue((requests[0] / 'returned.stdout').exists())
            with self.assertRaises(FileExistsError): ci.dispatch(matrix, args)
            self.assertEqual(process.call_count, 1)

    def test_direct_id_reconciliation_is_not_dispatch(self):
        matrix = self.fake_matrix(); folder = ci.request_path(matrix, 'a' * 32); value = intent(kind='producer')
        ci.save(folder / 'intent.json', value); ci.exclusive(folder / 'returned.stdout', run(value=value)['html_url'].encode())
        ci.exclusive(matrix.registry / 'dispatch.gate', b'a' * 32)
        with patch.object(ci.Transport, 'api', return_value=run(value=value)), patch.object(ci.subprocess, 'run') as process:
            resolved = ci.resolve(matrix, 'a' * 32)
            self.assertEqual(resolved['runID'], 3); process.assert_not_called()
            self.assertFalse((matrix.registry / 'dispatch.gate').exists())

    def test_terminal_only_collection(self):
        matrix = self.fake_matrix(); value = intent(); record = {'intent': value, 'resolution': {'runID': 3}, 'path': self.path / 'request'}
        transport = types.SimpleNamespace(api=lambda endpoint: run(value=value, status='in_progress', conclusion=None))
        with self.assertRaises(ci.Rejected): ci.terminal_collection(matrix, record, transport)
        self.assertFalse((record['path'] / 'originals').exists())

    def test_partial_download_never_reissued(self):
        target = self.path / 'original.zip'; target.with_suffix('.download-incomplete').write_bytes(b'partial')
        transport = ci.Transport(self.path, self.path / 'api')
        with patch.object(ci.subprocess, 'run') as process, self.assertRaises(ci.Rejected):
            transport.artifact({'id': 5, 'bytes': 3, 'sha256': 'A' * 64}, target)
        process.assert_not_called()

    def test_wrong_matrix_and_drift_rejected(self):
        path = self.path / 'matrix.json'; ci.save(path, {'schemaVersion': 1, 'contractID': ci.CONTRACT})
        with self.assertRaises(ci.Rejected): ci.Matrix(path)

    def test_deterministic_finding_sticky_across_same_second_audits(self):
        selected = intent(); record = registered(3, selected); record['path'] = self.path / 'record'
        audit_root = record['path'] / 'audits'; audit_root.mkdir(parents=True)
        base = {'runID': 3, 'head': H, 'completeOriginalAudit': True, 'originalFilesSHA256': 'F' * 64}
        for label, flag in [('20260909T000001-a', True), ('20260909T000001-z', None)]:
            ci.save(audit_root / (label + '.json'), dict(base, knownDeterministicFailure=flag))
        with patch.object(ci, 'verify_collection', return_value={'originalFilesSHA256': 'F' * 64}):
            with self.assertRaisesRegex(ci.Rejected, 'known deterministic'):
                ci.validate_retry([run(value=selected)], [record], selected, 3, 'unknown-native-cause',
                                  'A routine audit refresh must not erase an earlier deterministic finding.')

    def test_unknown_native_cause_is_explicit_not_inferred(self):
        selected = intent(); record = registered(3, selected); record['path'] = self.path / 'record'
        ci.save(record['path'] / 'audits/20260909T000001-a.json',
                {'runID': 3, 'head': H, 'completeOriginalAudit': True, 'originalFilesSHA256': 'F' * 64,
                 'knownDeterministicFailure': None})
        with patch.object(ci, 'verify_collection', return_value={'originalFilesSHA256': 'F' * 64}):
            result = ci.validate_retry([run(value=selected)], [record], selected, 3, 'unknown-native-cause',
                                       'Complete original forensic audit leaves cause unresolved; fresh runner is authorized.')
            self.assertFalse(result['nondeterminismProvedByController'])
            with self.assertRaises(ci.Rejected): ci.validate_retry([run(value=selected)], [record], selected, 3, None, None)


@unittest.skipUnless(os.environ.get('S10_4_FIXTURE_ROOT'), 'set S10_4_FIXTURE_ROOT for read-only source/original fixtures')
class OriginalFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(os.environ['S10_4_FIXTURE_ROOT']).resolve()
        work = Path(__file__).resolve().parents[1] / 'Temp/S10_4_ci_protocol_tests'
        work.mkdir(parents=True, exist_ok=True)
        cls.snapshot = tempfile.TemporaryDirectory(dir=work)
        cls.addClassCleanup(cls.snapshot.cleanup)
        snapshot = Path(cls.snapshot.name).resolve()
        ci.require(snapshot.is_relative_to(work.resolve()), 'fixture snapshot must stay inside test Temp')
        cls.source = ci.Source(cls.root, 'ca8f18bc2d1b0fdb796e405efb29e52fccae0258', snapshot / 'source')

    def test_current_light_original_midstate_candidate_names_and_full_closure(self):
        originals = self.root / 'Temp/S10_4_CI/registry/requests/fd56ec96ad88492e916f2b18935fbc06/originals'
        run_value = ci.load(originals / 'run.json')
        self.assertEqual(run_value['head_sha'], '4f41a4fcee5ebec5adb238f8a6ca80b8bb634dc8')
        source = ci.Source(self.root, run_value['head_sha'], Path(self.snapshot.name) / 'current-light-source')
        artifact = originals / '10087431839/artifact'
        consumer = ci.load(artifact / 'shared-consumer/consumer-build-reference.json')['consumer']
        selected = {'kind': 'consumer', 'head': source.head, 'shardID': consumer['shardID'], 'segmentID': consumer['segmentID']}
        facts = ci.consumer_facts(source, artifact, selected, run_value['id'], ci.load(originals / 'jobs.json')['jobs'])
        self.assertEqual(facts['strictOwnedCount'], 67)
        self.assertEqual(facts['candidatePNGCount'], 67)
        self.assertEqual(facts['nativeTests'][0]['result'], 'Passed')
        self.assertEqual(facts['gaps'], [])
        proof = ci.full_shard_proof(source, artifact, selected, facts)
        self.assertTrue(proof['fullShardComplete']); self.assertEqual(proof['commonTaskCount'], 6)
        self.assertFalse(proof['formalAcceptance']); self.assertFalse(proof['humanReviewGranted'])

    def test_current_ax_middle_and_final_original_replay_contracts(self):
        fixtures = [
            (34308325400, self.root / 'Temp/S10_4_CI/registry/requests/fbcf5c3f3e574d1a83e465109ca044b8/originals', 25),
            (34296504060, self.root / 'Temp/S10_4_K491_s10-4-current-ax-text_segment-2_34296504060', 28),
            (34300018458, self.root / 'Temp/S10_4_K491_s10-4-current-ax-text_segment-3_34300018458', 17),
        ]
        for rid, originals, owned in fixtures:
            with self.subTest(runID=rid):
                raw_run = ci.load(originals / 'run.json')
                self.assertEqual(raw_run['id'], rid)
                source = ci.Source(self.root, raw_run['head_sha'], Path(self.snapshot.name) / ('source-' + str(rid)))
                meta = next(a for a in ci.load(originals / 'artifacts.json')['artifacts'] if a['name'].startswith('ios-ci-shared-'))
                artifact = ci.wide(originals / str(meta['id']) / 'artifact')
                consumer = ci.load(artifact / 'shared-consumer/consumer-build-reference.json')['consumer']
                selected = {'kind': 'consumer', 'head': source.head, 'shardID': consumer['shardID'], 'segmentID': consumer['segmentID']}
                facts = ci.consumer_facts(source, artifact, selected, rid, ci.load(originals / 'jobs.json')['jobs'])
                self.assertEqual(facts['replayCount'], 22); self.assertEqual(facts['strictOwnedCount'], owned)
                self.assertEqual(facts['ownedJourneyCount'], 0)
                if rid == 34308325400:
                    self.assertEqual(raw_run['conclusion'], 'failure')
                    self.assertEqual(facts['nativeTests'][0]['result'], 'Failed')
                    self.assertEqual(facts['gaps'], ['Native UI failed; no complete segment or full shard.'])
                    self.assertFalse(facts['fullSegmentComplete'])
                    self.assertTrue(any('Audit failed to complete in time' in failure for failure in facts['nativeFailures']))
                    continue
                self.assertEqual(facts['nativeTests'][0]['result'], 'Passed'); self.assertEqual(facts['gaps'], [])
                producer = artifact / 'shared-producer'; ctx = source.context(consumer['shardID'])
                ctx['producerSeal'] = ci.load(producer / 'shared-build-seal.json')
                ctx['producerQualification'] = ci.load(producer / 'unit-proof/producer-qualification.json')
                binding = source.assembler.new_matrix(ctx, source.head, producer)
                source.assembler.verify_matrix(binding, ctx)
                segment = next(s for s in ctx['segments'] if s['segmentID'] == consumer['segmentID'])
                receipt, rows, candidates = source.assembler.revalidate_original(source.root, artifact, ctx, segment, binding)
                self.assertEqual(receipt['journeyCount'], 0); self.assertEqual(len(candidates), owned)
                self.assertTrue(receipt['nativeEvidenceComplete'])

    def test_exact_source_inventory_and_full_catalog(self):
        self.assertEqual(len(self.source.tuples), 39)
        self.assertEqual(sum(r['kind'] == 'consumer' for r in self.source.tuples), 30)
        self.assertEqual(sum(r['kind'] == 'assembly' for r in self.source.tuples), 8)
        self.assertEqual(len(ci.literal_full_catalog(self.source, 's10.4.current.default-light')), 1)
        with self.assertRaises(ci.Rejected): self.source.tuple('consumer', SHARD, 'none')

    def test_exact_minos_retry_native_failure_and_missing_proof(self):
        originals = self.root / 'Temp/S10_4_K491_s10-4-minimum-minimum-os_minimum-segment-2_retry1_34299031955'
        original = ci.load(self.root / 'Temp/S10_4_K491_minos_middle_retry_support/CONSUMER_DISPATCH_s10-4-minimum-minimum-os_minimum-segment-2_retry1.json')
        selected = {'kind': 'consumer', 'head': self.source.head, 'shardID': SHARD, 'segmentID': 'minimum-segment-2'}
        result = ci.consumer_facts(self.source, originals / '10084684269/artifact', selected, 34299031955, ci.load(originals / 'jobs.json')['jobs'])
        self.assertEqual(result['replayCount'], 4); self.assertEqual(result['strictOwnedCount'], 0)
        self.assertEqual(result['nativeFailures'], ['S10_3BrandMigrationUITests.swift:1525: XCTAssertTrue failed'])
        self.assertEqual(result['nativeAttachmentRows'], 0)
        self.assertFalse(result['fullSegmentComplete']); self.assertEqual(result['producerUnitCount'], 5)
        self.assertEqual(result['localUnitCount'], 0)
        self.assertFalse(result['Code56Observed'])

    def test_expired_actual_producer_artifact_rejected(self):
        root = self.root / 'Temp/S10_4_K491_producer_34295236272'
        run = ci.load(root / 'run.json'); artifacts = ci.load(root / 'artifacts.json')['artifacts']
        meta = next(a for a in artifacts if a['name'].startswith('s10-4-shared-payload-'))
        with self.assertRaises(self.source.payload.PayloadError):
            self.source.payload.artifact_contract(meta, run, 'payload', ci.utc(meta['expires_at']).timestamp())

    def test_hosted_posix_command_validation_on_windows(self):
        root = self.root / 'Temp/S10_4_K491_s10-4-minimum-minimum-os_minimum-segment-2_retry1_34299031955/10084684269/artifact'
        ref = ci.load(root / 'shared-consumer/consumer-build-reference.json')
        command = ref['uiCommand']
        self.assertEqual(ci.hosted_command(self.source.payload, command, 'test-without-building', ref['xctestrunPath'], ref['consumer']['simulatorUDID']), command)
        wrong = command.copy(); wrong[wrong.index('-resultBundlePath') + 1] = 'relative.xcresult'
        with self.assertRaises(self.source.payload.PayloadError): ci.hosted_command(self.source.payload, wrong, 'test-without-building', ref['xctestrunPath'], ref['consumer']['simulatorUDID'])

    def test_real_zero_test_bootstrap_remains_complete_factual_inspection(self):
        roots = list((self.root / 'Temp').glob('*34292785074'))
        self.assertEqual(len(roots), 1); original = roots[0]
        run_value = ci.load(original / 'run.json')
        work = Path(__file__).resolve().parents[1] / 'Temp/S10_4_ci_protocol_tests'; work.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=work) as temp:
            self.assertTrue(Path(temp).resolve().is_relative_to(work.resolve()))
            source = ci.Source(self.root, run_value['head_sha'], Path(temp) / 'source')
            metadata = ci.load(original / 'artifacts.json')['artifacts']
            worker = next(a for a in metadata if a['name'].startswith('ios-ci-shared-'))
            artifact = original / str(worker['id']) / 'artifact'
            consumer = ci.load(artifact / 'shared-consumer/consumer-build-reference.json')['consumer']
            selected = {'kind': 'consumer', 'head': source.head, 'shardID': consumer['shardID'], 'segmentID': consumer['segmentID']}
            result = ci.consumer_facts(source, artifact, selected, run_value['id'], ci.load(original / 'jobs.json')['jobs'])
            self.assertEqual(result['nativeTests'], []); self.assertFalse(result['nativeUIExecuted'])
            self.assertTrue(result['nativeBootstrapFailure']); self.assertEqual(result['strictOwnedCount'], 0)
            self.assertFalse(result['fullSegmentComplete']); self.assertEqual(result['producerUnitCount'], 5)

    def test_real_incomplete_native_export_keeps_source_gates_and_unknown_results(self):
        original = self.root / 'Temp/S10_4_CI/registry/requests/fedc0d09dcc1404dab66abb04d425472/originals'
        run_value = ci.load(original / 'run.json')
        self.assertEqual(run_value['id'], 34341891637)
        source = ci.Source(self.root, run_value['head_sha'], Path(self.snapshot.name) / 'incomplete-native-source')
        artifact = ci.wide(original / '10101221753/artifact')
        reference_path = artifact / 'shared-consumer/consumer-build-reference.json'
        reference = ci.load(reference_path); consumer = reference['consumer']
        selected = {'kind': 'consumer', 'head': source.head, 'shardID': consumer['shardID'], 'segmentID': consumer['segmentID']}
        jobs = ci.load(original / 'jobs.json')['jobs']
        observed = [reference_path, artifact / 's10-4-shared-ui-command.json', artifact / 'ui-smoke.log',
                    artifact / 'ui-failure-diagnostics/xcresult-test-results.json',
                    artifact / 'ui-failure-diagnostics/xcresult-test-results.stderr.txt']
        before = {str(p): ci.sha(p) for p in observed}
        facts = ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, run_value['conclusion'])
        self.assertTrue(facts['consumerReferenceVerified']); self.assertEqual(facts['producerUnitCount'], 5)
        self.assertEqual(facts['localUnitCount'], 0); self.assertTrue(facts['nativeResultUnavailable'])
        self.assertIsNone(facts['nativeUIExecuted']); self.assertIsNone(facts['nativeTests'])
        self.assertIsNone(facts['strictOwnedCount']); self.assertIsNone(facts['candidatePNGCount'])
        self.assertEqual(facts['observedTestBodyMarkerCount'], 0)
        self.assertFalse(facts['fullSegmentComplete']); self.assertFalse(facts['fullShardComplete'])
        self.assertEqual(facts['nativeExportFailure']['status'], 64); self.assertTrue(facts['gaps'])
        with self.assertRaises(ci.Rejected):
            ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, 'success')
        original_load = ci.load
        for changed in ('source', 'command'):
            def mutated_load(path):
                value = original_load(path)
                if changed == 'source' and str(path) == str(reference_path):
                    value = copy.deepcopy(value); value['source']['head'] = '0' * 40
                if changed == 'command' and str(path) == str(artifact / 's10-4-shared-ui-command.json'):
                    value = value.copy(); value[-1] = 'build'
                return value
            with self.subTest(changed=changed), patch.object(ci, 'load', side_effect=mutated_load), \
                 patch.object(ci, 'unavailable_native_export') as unavailable, self.assertRaises(ci.Rejected):
                ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, 'failure')
            unavailable.assert_not_called()
        self.assertEqual(before, {str(p): ci.sha(p) for p in observed})


if __name__ == '__main__':
    unittest.main(verbosity=2)
