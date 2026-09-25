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


DUPLICATE_CLASS_WARNING = ('objc[35189]: Class UIAccessibilityLoaderWebShared is implemented in both '
    '/Runtime/WebCore.axbundle/WebCore (0x111) and /Runtime/WebKit.axbundle/WebKit (0x222). '
    'One of the two will be used. Which one is undefined.')


def interrupted_start(extra=''):
    return ('noise\nS10_4_MINIMUM_SEGMENT_START {"acceptanceEligible":false,"requirementID":"double_length"'
            + DUPLICATE_CLASS_WARNING + '\n,"schemaVersion":1,"segmentID":"minimum-segment-1"}\n' + extra)


class Protocol(unittest.TestCase):
    def setUp(self):
        root = Path(__file__).resolve().parents[1] / 'Temp/S10_4_ci_protocol_tests'
        root.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=root)
        self.path = Path(self.temp.name).resolve()
        self.assertTrue(self.path.is_relative_to(root.resolve()))
        self.addCleanup(self.temp.cleanup)

    def assembly_archive_fixture(self):
        selected = intent(kind='assembly', segment='none')
        source = object.__new__(ci.Source)
        source.head = H
        source.identity = {'head': H, 'gitTree': '3' * 40, 'files': {'source': 'A' * 64}}
        selected['sourceIdentitySHA256'] = ci.digest(ci.canonical(source.identity))
        source.tuples = [dict(row('assembly', 'none'), owned=67, replay=0,
                              dependencies=['minimum-segment-1', 'minimum-segment-2', 'minimum-segment-3'])]
        original = run(value=selected, conclusion='success')
        meta = {'id': 5, 'size_in_bytes': ci.MAX_ARCHIVE + 1, 'digest': 'sha256:' + 'a' * 64,
                'name': 'ios-ci-shared-admission-3-1-' + SHARD,
                'expired': False, 'expires_at': (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1)).isoformat(),
                'workflow_run': {'id': 3, 'head_sha': H, 'head_branch': ci.REF,
                                 'repository_id': 77, 'head_repository_id': 77}}
        return meta, (source, selected, original)

    def test_assembly_archive_limit_requires_original_source_identity(self):
        meta, context = self.assembly_archive_fixture()
        self.assertEqual(ci.artifact_byte_limit(meta), ci.MAX_ARCHIVE)
        self.assertEqual(ci.artifact_byte_limit(meta, context), ci.MAX_EXPANDED)
        self.assertEqual(ci.MAX_ARCHIVE, 2 * 1024**3)
        self.assertEqual(ci.MAX_EXPANDED, 8 * 1024**3)
        self.assertEqual(ci.MAX_MEMBERS, 100000)
        bad_cases = {
            'consumer admission': lambda m, c: c[1].update(kind='consumer'),
            'producer': lambda m, c: c[1].update(kind='producer'),
            'wrong lane': lambda m, c: c[1]['inputs'].update(execution_lane=ci.CONSUMER),
            'UI execution': lambda m, c: c[1]['inputs'].update(run_ui_smoke='true'),
            'segment': lambda m, c: c[1].update(segmentID='minimum-segment-1'),
            'source tuple missing': lambda m, c: setattr(c[0], 'tuples', []),
            'source state coverage': lambda m, c: c[0].tuples[0].update(owned=66),
            'source dependency count': lambda m, c: c[0].tuples[0].update(dependencies=[]),
            'source head': lambda m, c: setattr(c[0], 'head', P),
            'source digest': lambda m, c: c[1].update(sourceIdentitySHA256='B' * 64),
            'run active': lambda m, c: c[2].update(status='in_progress'),
            'run title': lambda m, c: c[2].update(display_title='other'),
            'artifact name': lambda m, c: m.update(name='ios-ci-shared-other'),
            'artifact run': lambda m, c: m['workflow_run'].update(id=4),
            'artifact head': lambda m, c: m['workflow_run'].update(head_sha=P),
            'artifact ref': lambda m, c: m['workflow_run'].update(head_branch='main'),
            'artifact repository': lambda m, c: m['workflow_run'].update(repository_id=78),
            'artifact fork': lambda m, c: m['workflow_run'].update(head_repository_id=78),
            'expired flag': lambda m, c: m.update(expired=True),
            'past expiry': lambda m, c: m.update(expires_at='2000-01-01T00:00:00Z'),
            'wrong attempt': lambda m, c: c[2].update(run_attempt=2),
        }
        for label, change in bad_cases.items():
            with self.subTest(label=label):
                altered_meta, altered_context = copy.deepcopy((meta, context))
                change(altered_meta, altered_context)
                with self.assertRaises(ci.Rejected): ci.artifact_byte_limit(altered_meta, altered_context)

    def test_assembly_archive_transport_preserves_size_and_no_partial_guards(self):
        meta, context = self.assembly_archive_fixture()
        transport = ci.Transport(self.path, self.path / 'assembly-api')
        target = self.path / 'original.zip'
        with patch.object(ci.subprocess, 'run') as process:
            with self.assertRaisesRegex(ci.Rejected, 'size out of bounds'): transport.artifact(meta, target)
            self.assertFalse(target.with_suffix('.download-incomplete').exists())
            too_big = dict(meta, size_in_bytes=ci.MAX_EXPANDED + 1)
            with self.assertRaisesRegex(ci.Rejected, 'size out of bounds'): transport.artifact(too_big, target, assembly=context)
            for invalid_size in (0, -1, True, '2303084578'):
                with self.assertRaisesRegex(ci.Rejected, 'size out of bounds'):
                    transport.artifact(dict(meta, size_in_bytes=invalid_size), target, assembly=context)
            target.with_suffix('.download-incomplete').write_bytes(b'original partial')
            with self.assertRaisesRegex(ci.Rejected, 'incomplete original transport retained'):
                transport.artifact(meta, target, assembly=context)
            process.assert_not_called()
        self.assertEqual(target.with_suffix('.download-incomplete').read_bytes(), b'original partial')

    def test_assembly_archive_transport_success_still_checks_exact_bytes_and_digest(self):
        meta, context = self.assembly_archive_fixture()
        data = b'finite assembly transport fixture'
        meta.update(size_in_bytes=len(data), digest='sha256:' + ci.digest(data).lower())
        transport = ci.Transport(self.path, self.path / 'assembly-success-api')
        target = self.path / 'assembly-original.zip'
        def write_original(*args, **kwargs):
            kwargs['stdout'].write(data)
            return types.SimpleNamespace(returncode=0, stderr=b'')
        with patch.object(ci.subprocess, 'run', side_effect=write_original) as process:
            transport.artifact(meta, target, assembly=context)
            process.assert_called_once()
        self.assertEqual(target.read_bytes(), data)
        with patch.object(ci.subprocess, 'run') as process:
            transport.artifact(meta, target, assembly=context)
            with self.assertRaisesRegex(ci.Rejected, 'cached archive identity changed'):
                transport.artifact(dict(meta, digest='sha256:' + 'b' * 64), target, assembly=context)
            process.assert_not_called()

    def test_assembly_archive_transport_failure_retains_original_partial(self):
        meta, context = self.assembly_archive_fixture()
        data = b'finite failed assembly transport fixture'
        meta.update(size_in_bytes=len(data), digest='sha256:' + ci.digest(data).lower())
        transport = ci.Transport(self.path, self.path / 'assembly-failure-api')
        for label, current in [('digest', dict(meta, digest='sha256:' + 'b' * 64)),
                               ('length', dict(meta, size_in_bytes=len(data) + 1))]:
            target = self.path / (label + '.zip')
            def write_original(*args, **kwargs):
                kwargs['stdout'].write(data)
                return types.SimpleNamespace(returncode=0, stderr=b'')
            with patch.object(ci.subprocess, 'run', side_effect=write_original):
                with self.assertRaisesRegex(ci.Rejected, 'artifact transport/digest failed'):
                    transport.artifact(current, target, assembly=context)
            self.assertFalse(target.exists())
            self.assertEqual(target.with_suffix('.download-incomplete').read_bytes(), data)

    def test_assembly_archive_cached_boundaries_and_owner_checks(self):
        meta, context = self.assembly_archive_fixture()
        transport = ci.Transport(self.path, self.path / 'assembly-cache-api')
        target = self.path / 'cached.zip'
        target.touch()
        for size in (ci.MAX_ARCHIVE + 1, ci.MAX_EXPANDED):
            with self.subTest(size=size), patch.object(Path, 'stat', return_value=types.SimpleNamespace(st_size=size)), \
                 patch.object(ci, 'sha', return_value='A' * 64) as hashing, patch.object(ci.subprocess, 'run') as process:
                transport.artifact(dict(meta, size_in_bytes=size), target, assembly=context)
                hashing.assert_called_once_with(target)
                process.assert_not_called()
        for key, value in [('name', 'foreign-admission'), ('expired', True),
                           ('expires_at', '2000-01-01T00:00:00Z')]:
            with self.subTest(key=key), patch.object(ci, 'sha') as hashing, patch.object(ci.subprocess, 'run') as process:
                with self.assertRaises(ci.Rejected):
                    transport.artifact(dict(meta, **{key: value}), target, assembly=context)
                hashing.assert_not_called()
                process.assert_not_called()

    def github_v3_fixture(self, image='20260831.0337.3'):
        contract = {'contract_version': 's10.4-github-image-adoption-v3', 'authority_head': 'a' * 40,
                    'worker_source_sha256': 'B' * 64, 'image_os': 'macos26', 'macos_product_name': 'macOS',
                    'macos_product_version': '26.6.2', 'macos_build_version': '25G83', 'architecture': 'arm64',
                    'image_versions': ['20260831.0337.3', '20260907.0351.1']}
        environment = {k: v for k, v in contract.items() if k != 'image_versions'}
        return {'environment': dict(environment, image_version=image), 'contract': contract,
                'worker_sha256': 'B' * 64, 'provider': 'github'}

    def test_github_v3_both_exact_actual_images(self):
        # Receipt projection only: these fixtures do not establish native/full-shard evidence.
        for image in ('20260831.0337.3', '20260907.0351.1'):
            with self.subTest(image=image):
                args = self.github_v3_fixture(image); before = copy.deepcopy(args)
                self.assertIsNone(ci.verify_github_environment(**args))
                self.assertEqual(args, before)
                self.assertNotIn('image_versions', args['environment'])

    def test_github_v3_rejects_malformed_config(self):
        mutations = {
            'missing image list': lambda a: a['contract'].pop('image_versions'),
            'scalar image list': lambda a: a['contract'].update(image_versions='20260831.0337.3'),
            'tuple image list': lambda a: a['contract'].update(image_versions=('20260831.0337.3', '20260907.0351.1')),
            'reversed image list': lambda a: a['contract']['image_versions'].reverse(),
            'duplicate image': lambda a: a['contract'].update(image_versions=['20260831.0337.3'] * 2),
            'third image': lambda a: a['contract']['image_versions'].append('20260728.0273.1'),
            'single image': lambda a: a['contract']['image_versions'].pop(),
            'nonstring image': lambda a: a['contract'].update(image_versions=[True, '20260907.0351.1']),
            'extra scalar': lambda a: a['contract'].update(image_version='20260831.0337.3'),
            'malformed anchor': lambda a: a['contract'].update(authority_head='A' * 40),
            'malformed worker': lambda a: a['contract'].update(worker_source_sha256='b' * 64),
        }
        for field in self.github_v3_fixture()['contract']:
            if field not in ('contract_version', 'image_versions'):
                mutations['missing ' + field] = lambda a, key=field: a['contract'].pop(key)
                mutations['wrong type ' + field] = lambda a, key=field: a['contract'].update({key: []})
        for field in ('image_os', 'macos_product_name', 'macos_product_version', 'macos_build_version', 'architecture'):
            mutations['crossed invariant ' + field] = lambda a, key=field: (
                a['contract'].update({key: 'unapproved'}), a['environment'].update({key: 'unapproved'}))
        for name, mutate in mutations.items():
            with self.subTest(name=name):
                args = self.github_v3_fixture(); mutate(args)
                with self.assertRaises(ci.Rejected): ci.verify_github_environment(**args)

    def test_github_v3_rejects_receipt_substitution_and_wrong_types(self):
        for field in self.github_v3_fixture()['environment']:
            for kind in ('missing', 'wrong', 'null', 'bool', 'list', 'object'):
                with self.subTest(field=field, kind=kind):
                    args = self.github_v3_fixture()
                    if kind == 'missing': args['environment'].pop(field)
                    else: args['environment'][field] = {'wrong': 'unapproved', 'null': None, 'bool': True,
                                                       'list': [args['environment'][field]], 'object': {}}[kind]
                    with self.assertRaises(ci.Rejected): ci.verify_github_environment(**args)
        for value in (None, [], 'receipt', True):
            args = self.github_v3_fixture(); args['environment'] = value
            with self.subTest(receipt=value), self.assertRaises(ci.Rejected): ci.verify_github_environment(**args)
        for key, value in (('image_versions', ['20260831.0337.3', '20260907.0351.1']), ('extra', 'value')):
            args = self.github_v3_fixture(); args['environment'][key] = value
            with self.subTest(extra=key), self.assertRaises(ci.Rejected): ci.verify_github_environment(**args)
        for image in ('20260728.0273.1', '20260907.0351.1 ', 'macos26-20260907.0351.1'):
            args = self.github_v3_fixture(image)
            with self.subTest(image=image), self.assertRaises(ci.Rejected): ci.verify_github_environment(**args)
        for field, values in {'provider': (None, True, 'bitrise', 'github_actions', 'getmac'),
                              'worker_sha256': ('C' * 64, 'b' * 64, None)}.items():
            for value in values:
                args = self.github_v3_fixture(); args[field] = value
                with self.subTest(field=field, value=value), self.assertRaises(ci.Rejected):
                    ci.verify_github_environment(**args)

    def test_github_historical_contract_equality_is_unchanged(self):
        for version in ('s10.4-github-image-adoption-v1', 's10.4-github-image-adoption-v2'):
            args = self.github_v3_fixture(); legacy = args['environment']
            legacy['contract_version'] = version
            args.update(contract=copy.deepcopy(legacy), worker_sha256=None, provider=None)
            self.assertIsNone(ci.verify_github_environment(**args))
            for field in legacy:
                changed = copy.deepcopy(args); changed['environment'][field] = 'different'
                with self.subTest(version=version, field=field), self.assertRaises(ci.Rejected):
                    ci.verify_github_environment(**changed)

    def test_github_rejects_unknown_or_malformed_contract_versions(self):
        for contract in (None, [], 'contract', True, {}, {'contract_version': None},
                         {'contract_version': True}, {'contract_version': []},
                         {'contract_version': 's10.4-github-image-adoption-v0'},
                         {'contract_version': 's10.4-github-image-adoption-v4'}):
            # Equality must never admit an unsupported or malformed source contract.
            args = self.github_v3_fixture()
            args.update(contract=contract, environment=copy.deepcopy(contract))
            with self.subTest(contract=contract), self.assertRaises(ci.Rejected):
                ci.verify_github_environment(**args)
        for source_version, receipt_version in (('v1', 'v2'), ('v2', 'v1'), ('v1', 'v3'), ('v2', 'v3')):
            args = self.github_v3_fixture(); legacy = args['environment']
            legacy['contract_version'] = 's10.4-github-image-adoption-' + source_version
            args.update(contract=copy.deepcopy(legacy), worker_sha256=None, provider=None)
            args['environment']['contract_version'] = 's10.4-github-image-adoption-' + receipt_version
            with self.subTest(source=source_version, receipt=receipt_version), self.assertRaises(ci.Rejected):
                ci.verify_github_environment(**args)

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
        prior = folder / 'audits/20260901T000000-rejected.json'
        ci.save(prior, {'runID': 3, 'head': H, 'completeOriginalAudit': False,
                        'originalFilesSHA256': 'A' * 64, 'gaps': ['Rejected: malformed segmented marker JSON']})
        native = ci.unavailable_native_export(**self.unavailable_export_fixture())
        native.update(gaps=['Native result unavailable.'], fullSegmentComplete=False, fullShardComplete=False)
        with patch.object(ci, 'records', return_value=[record]), patch.object(ci, 'collection_proof', return_value=original), \
             patch.object(ci, 'Transport'), patch.object(ci, 'consumer_facts', return_value=native) as consumer:
            result = ci.audit(matrix, selected['requestID'])
        self.assertEqual(consumer.call_args.args[-2], 'failure'); self.assertIs(consumer.call_args.args[-1], original)
        self.assertTrue(result['completeOriginalAudit']); self.assertIsNone(result['nativeUIExecuted'])
        self.assertEqual(result['gaps'], ['Native result unavailable.'])
        self.assertEqual(result['collectorRelease'], ci.COLLECTOR_RELEASE)
        self.assertEqual(result['collectorSHA256'], ci.sha(Path(ci.__file__).resolve()))
        self.assertEqual(result['priorAuditBindings'], [{'path': 'audits/' + prior.name, 'sha256': ci.sha(prior),
            'completeOriginalAudit': False, 'gaps': ['Rejected: malformed segmented marker JSON']}])
        for key in ('fullSegmentComplete', 'fullShardComplete', 'formalAcceptance', 'humanReviewGranted'):
            self.assertIs(result[key], False)

    def test_failed_start_audit_cannot_complete_across_deterministic_history(self):
        selected = intent(); folder = self.path / 'registry/requests' / selected['requestID']; folder.mkdir(parents=True)
        record = {'path': folder, 'intent': selected, 'resolution': {'runID': 3}}
        originals = folder / 'originals'; originals.mkdir()
        job = {'id': 4, 'name': 'worker', 'conclusion': 'failure', 'started_at': '2026-09-01T00:00:00Z',
               'completed_at': '2026-09-01T00:00:01Z', 'steps': []}
        ci.save(originals / 'jobs.json', {'jobs': [job]})
        ci.save(originals / 'artifacts.json', {'artifacts': [{'id': 5,
            'name': 'ios-ci-shared-3-1-' + SHARD + '-minimum-segment-1'}]})
        (originals / 'job-4.log').write_text('failed')
        ci.save(folder / 'audits/prior.json', {'runID': 3, 'head': H, 'completeOriginalAudit': True,
            'originalFilesSHA256': 'A' * 64, 'knownDeterministicFailure': True, 'gaps': []})
        source = types.SimpleNamespace(identity={'files': []}, payload=types.SimpleNamespace(PayloadError=RuntimeError),
                                       assembler=types.SimpleNamespace(Rejected=RuntimeError))
        matrix = types.SimpleNamespace(root=self.path, registry=self.path / 'registry', source=lambda head: source)
        original = {'runID': 3, 'head': H, 'conclusion': 'failure', 'originalFilesSHA256': 'A' * 64, 'gaps': []}
        native = {'malformedSegmentStartDiagnostics': [{}], 'gaps': [], 'fullSegmentComplete': False,
                  'fullShardComplete': False}
        with patch.object(ci, 'records', return_value=[record]), patch.object(ci, 'collection_proof', return_value=original), \
             patch.object(ci, 'Transport'), patch.object(ci, 'consumer_facts', return_value=native):
            result = ci.audit(matrix, selected['requestID'])
        self.assertFalse(result['completeOriginalAudit'])
        self.assertIn('Rejected: malformed START audit prohibited by known deterministic failure history', result['gaps'])
        self.assertTrue(result['knownDeterministicFailure'])

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

    def test_valid_marker_path_preserves_replay_validation_and_facts_before_missing_reference(self):
        segment = 'minimum-segment-1'
        ctx = {'minimum': True, 'segments': [{'segmentID': segment, 'replayStateIDs': ['state.a']}]}
        source = types.SimpleNamespace(head=H, assembler=object(), payload=object(), context=lambda _: ctx)
        selected = {'shardID': SHARD, 'segmentID': segment}
        replay = {'ordinal': 1, 'stateID': 'state.a', 'segmentID': segment, 'shardID': SHARD,
                  'setupOnly': True, 'acceptanceEligible': False, 'head': H}
        prefix = 'S10_4_MINIMUM_SEGMENT_REPLAY '
        (self.path / 'ui-smoke.log').write_text(prefix + json.dumps(replay) + '\nCode=56\n', encoding='utf-8')
        result = ci.consumer_facts(source, self.path, selected, 3, [])
        self.assertEqual(result['nativeEvents'], {'S10_4_MINIMUM_SEGMENT_REPLAY': [replay]})
        self.assertTrue(result['Code56Observed'])
        self.assertEqual(result['gaps'], ['Consumer restore/reference absent; native source/environment binding not established.'])

        invalid = copy.deepcopy(replay); invalid['stateID'] = 'state.foreign'
        for line in (prefix + json.dumps(invalid), 'S10_4_SEGMENT_REPLAY ' + json.dumps(replay)):
            (self.path / 'ui-smoke.log').write_text(line + '\n', encoding='utf-8')
            with self.subTest(line=line), self.assertRaises(ci.Rejected):
                ci.consumer_facts(source, self.path, selected, 3, [])

    def test_failed_start_diagnostic_retains_exact_lines_warning_and_locations_without_reconstruction(self):
        raw = interrupted_start().encode('utf-8')
        with self.assertRaises(ci.Rejected):
            ci.native_events(raw)
        diagnostics = []
        self.assertEqual(ci.native_events(raw, diagnostics), {})
        self.assertEqual(len(diagnostics), 1); diagnostic = diagnostics[0]
        self.assertFalse(diagnostic['originalMarkerValidJSON']); self.assertFalse(diagnostic['derivedMarkerCreated'])
        self.assertFalse(diagnostic['acceptanceClaimed']); self.assertEqual(diagnostic['strictParserResult'], 'REJECTED')
        self.assertEqual(diagnostic['nativeWarning'], DUPLICATE_CLASS_WARNING)
        self.assertEqual(diagnostic['logSHA256'], ci.digest(raw))
        lines = raw.splitlines(keepends=True)
        self.assertEqual(diagnostic['rawLineBase64'], __import__('base64').b64encode(lines[1]).decode('ascii'))
        self.assertEqual(diagnostic['followingRawLineBase64'], __import__('base64').b64encode(lines[2]).decode('ascii'))
        self.assertEqual(diagnostic['lineStartByteOffset'], len(lines[0]))
        self.assertEqual(diagnostic['nativeWarningStartByteOffset'], raw.index(DUPLICATE_CLASS_WARNING.encode()))
        self.assertEqual(diagnostic['followingLineStartByteOffset'], len(lines[0]) + len(lines[1]))

        hostiles = {
            'current segment start': interrupted_start().replace('MINIMUM_SEGMENT_START', 'SEGMENT_START'),
            'malformed state marker': interrupted_start().replace('MINIMUM_SEGMENT_START', 'MINIMUM_SEGMENT_REPLAY'),
            'warning absent': interrupted_start().replace(DUPLICATE_CLASS_WARNING, 'ordinary output'),
            'continuation absent': interrupted_start().split('\n,"schemaVersion"', 1)[0] + '\n',
            'continuation not suffix': interrupted_start().replace(',"schemaVersion":1', '{"schemaVersion":1'),
            'second malformed start': interrupted_start(interrupted_start()),
        }
        for name, value in hostiles.items():
            with self.subTest(name=name), self.assertRaises(ci.Rejected):
                ci.native_events(value, [])

    def test_failed_start_zero_evidence_proof_rejects_every_partial_or_missing_input(self):
        failure = self.path / 'ui-failure-attachments'; failure.mkdir()
        raw = interrupted_start().encode('utf-8'); diagnostics = []; events = ci.native_events(raw, diagnostics)
        result = {'nativeTests': [{'result': 'Failed'}], 'strictOwnedCount': 0, 'strictStateRowCount': 0,
                  'replayCount': 0, 'ownedJourneyCount': 0, 'candidatePNGCount': 0,
                  'nativeAttachmentRows': 1, 'nativeCandidateAttachmentRowCount': 0}
        selected = row()
        expected = ci.failed_start_zero_evidence(self.path, raw, diagnostics, events, result, [], selected)
        self.assertEqual(expected['candidatePNGs'], 0); self.assertEqual(expected['events'], 0)
        mutations = {
            'native success': lambda r, e, x: r['nativeTests'][0].update(result='Passed'),
            'selected native absent': lambda r, e, x: r.update(nativeTests=[]),
            'owned state count': lambda r, e, x: r.update(strictOwnedCount=1),
            'state row count': lambda r, e, x: r.update(strictStateRowCount=1),
            'replay count': lambda r, e, x: r.update(replayCount=1),
            'journey count': lambda r, e, x: r.update(ownedJourneyCount=1),
            'candidate count': lambda r, e, x: r.update(candidatePNGCount=1),
            'state event': lambda r, e, x: e.update(S10_4_AX_STATE=[{}]),
            'partial result event': lambda r, e, x: e.update(S10_4_MINIMUM_SEGMENT_RESULT=[{}]),
            'candidate export': lambda r, e, x: x.append({'suggestedHumanReadableName': 'S10.4 candidate ' + SHARD + ' state.a'}),
            'candidate SQLite row': lambda r, e, x: r.update(nativeCandidateAttachmentRowCount=1),
            'missing SQLite proof': lambda r, e, x: r.pop('nativeAttachmentRows'),
        }
        for name, mutate in mutations.items():
            actual = copy.deepcopy(result); events = {}; exports = []; mutate(actual, events, exports)
            with self.subTest(name=name), self.assertRaises(ci.Rejected):
                ci.failed_start_zero_evidence(self.path, raw, diagnostics, events, actual, exports, selected)
        for path in ('s10-4', 's10-4-shared-raw-attachments', 'ax', 'contrast', 'accessibility'):
            target = self.path / path; target.mkdir()
            with self.subTest(path=path), self.assertRaises(ci.Rejected):
                ci.failed_start_zero_evidence(self.path, raw, diagnostics, {}, result, [], selected)
            target.rmdir()
        candidate = failure / 'candidate.png'; candidate.write_bytes(b'not accepted')
        with self.assertRaises(ci.Rejected):
            ci.failed_start_zero_evidence(self.path, raw, diagnostics, {}, result, [], selected)
        candidate.unlink()
        for extra in ('S10_4_AX_STATE {broken\n', ' S10_4_CONTRAST {broken\n',
                      'S10_4_MINIMUM_SEGMENT_REPLAY {broken\n', 'S10_MIGRATION_STATE state.a\n'):
            hostile = raw + extra.encode()
            with self.subTest(raw_marker=extra), self.assertRaises(ci.Rejected):
                ci.failed_start_zero_evidence(self.path, hostile, diagnostics, {}, result, [], selected)

    def test_candidate_attachment_count_accepts_nullable_unrelated_rows(self):
        prefix = 'S10.4 candidate ' + SHARD + ' '
        rows = [{'filenameOverride': None}, {}, {'filenameOverride': 'failure hierarchy'},
                {'filenameOverride': prefix + 'state.a'}]
        self.assertEqual(ci.candidate_attachment_count(rows, prefix), 1)

    def test_failed_start_context_is_one_source_defined_minimum_segment_only(self):
        selected = {'segmentID': 'minimum-segment-1'}
        ci.require_failed_start_context({'minimum': True, 'segments': [{'segmentID': 'minimum-segment-1'}]}, selected)
        hostiles = [
            ({'minimum': False, 'segments': [{'segmentID': 'minimum-segment-1'}]}, selected),
            ({'minimum': True, 'segments': []}, selected),
            ({'minimum': True, 'segments': [{'segmentID': 'minimum-segment-2'}]}, selected),
            ({'minimum': True, 'segments': [{'segmentID': 'minimum-segment-1'}, {'segmentID': 'minimum-segment-1'}]}, selected),
            ({'minimum': True, 'segments': [{'segmentID': 'none'}]}, {'segmentID': 'none'}),
        ]
        for ctx, intent_value in hostiles:
            with self.subTest(ctx=ctx, intent=intent_value), self.assertRaises(ci.Rejected):
                ci.require_failed_start_context(ctx, intent_value)

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

    def test_real_minimum_core_smoke_unnumbered_bootstrap_and_hostile_controls(self):
        # Read-only original verification; this never invokes collect/audit or writes a receipt.
        original = self.root / 'Temp/S10_4_CI/registry/requests/4745eb04620e419b89047960c70f7a32/originals'
        run_value = ci.load(original / 'run.json')
        self.assertEqual(run_value['id'], 34472954538)
        self.assertEqual(run_value['head_sha'], '7d33a206bcf9ff4c5e767549f9db7632d15fbc4a')
        source = ci.Source(self.root, run_value['head_sha'], Path(self.snapshot.name) / 'minimum-core-smoke-bootstrap-source')
        selected = ci.load(original.parent / 'intent.json')
        inventory_before = ci.cache_inventory(original)
        verified = ci.verify_collection(original, selected, run_value['id'])
        self.assertTrue(verified['allAvailableOriginalsVerified'])
        self.assertEqual(verified['originalFileCount'], 2279)
        self.assertEqual(verified['originalFilesSHA256'], 'D91A83B554C9AD82D87CA16D75B152A903FB22D79B03878E94E23FC66DC270CD')
        self.assertEqual(len(source.identity['files']), 15)
        artifact = ci.wide(original / '10151258208/artifact')
        reference = ci.load(artifact / 'shared-consumer/consumer-build-reference.json')
        self.assertEqual(reference['source'], source.identity)
        jobs = ci.load(original / 'jobs.json')['jobs']
        native_path = artifact / 'ui-failure-diagnostics/xcresult-test-results.json'
        native = ci.load(native_path)
        native_before = native_path.read_bytes()
        database_hash = ci.sha(artifact / 'UISmoke.xcresult/database.sqlite3')
        log_path = artifact / 'ui-smoke.log'
        log = log_path.read_bytes()
        read_json = ci.load; read_bytes = Path.read_bytes
        bootstrap = 'FieldEvidenceAppUITests-Runner encountered an error'
        case = next(r for r in ci.nodes(native) if r.get('nodeType') == 'Test Case')
        self.assertEqual(case['nodeIdentifier'], bootstrap)
        self.assertEqual(case['result'], 'Failed')

        def inspect(native_value=native, job_values=jobs, log_value=log):
            # Only disposable input views change; every source/producer/command/isolation gate executes.
            with patch.object(ci, 'load', side_effect=lambda p: copy.deepcopy(native_value) if p == native_path else read_json(p)), \
                 patch.object(Path, 'read_bytes', lambda p: log_value if p == log_path else read_bytes(p)):
                return ci.consumer_facts(source, artifact, selected, run_value['id'], job_values, 'failure', verified)

        def assert_bootstrap(facts):
            self.assertTrue(facts['consumerReferenceVerified'])
            self.assertTrue(facts['nativeBootstrapFailure'])
            self.assertFalse(facts['nativeUIExecuted']); self.assertEqual(facts['nativeTests'], [])
            self.assertEqual(facts['nativeEvents'], {})
            self.assertEqual(facts['producerUnitCount'], 5); self.assertEqual(facts['localUnitCount'], 0)
            for key in ('strictOwnedCount', 'replayCount', 'ownedJourneyCount', 'candidatePNGCount', 'nativeAttachmentRows'):
                self.assertEqual(facts[key], 0, key)
            for key in ('smokeComplete', 'fullSegmentComplete', 'fullShardComplete', 'formalAcceptance', 'humanReviewGranted'):
                self.assertFalse(facts.get(key, False), key)
            self.assertEqual(facts['gaps'], ['Native bootstrap produced zero selected tests; no test body, states or journeys executed.'])
            self.assertTrue(any('unknown to FrontBoard' in value for value in facts['nativeFailures']))

        assert_bootstrap(inspect())
        numbered = copy.deepcopy(native)
        numbered_case = next(r for r in ci.nodes(numbered) if r.get('nodeType') == 'Test Case')
        numbered_case.update(name='FieldEvidenceAppUITests-Runner (1234) encountered an error',
                             nodeIdentifier='FieldEvidenceAppUITests-Runner (1234) encountered an error')
        assert_bootstrap(inspect(numbered))
        for label, identifier, status in (
            ('foreign runner', 'ForeignRunner encountered an error', 'Failed'),
            ('prefix', 'x' + bootstrap, 'Failed'), ('suffix', bootstrap + ' trailing', 'Failed'),
            ('empty PID', 'FieldEvidenceAppUITests-Runner () encountered an error', 'Failed'),
            ('nonnumeric PID', 'FieldEvidenceAppUITests-Runner (abc) encountered an error', 'Failed'),
            ('extra whitespace', 'FieldEvidenceAppUITests-Runner  encountered an error', 'Failed'),
            ('passed system case', bootstrap, 'Passed'), ('false result', bootstrap, False),
        ):
            with self.subTest(label=label):
                bad = copy.deepcopy(native)
                bad_case = next(r for r in ci.nodes(bad) if r.get('nodeType') == 'Test Case')
                bad_case.update(nodeIdentifier=identifier, name=identifier, result=status)
                with self.assertRaises(ci.Rejected): inspect(bad)
        for identifier in (source.assembler.UI_ID, 'ForeignSuite/foreignTest'):
            with self.subTest(mixedCase=identifier):
                bad = copy.deepcopy(native)
                bad['testNodes'].append(dict(nodeType='Test Case', nodeIdentifier=identifier, result='Failed'))
                with self.assertRaises(ci.Rejected): inspect(bad)
        successful_worker = copy.deepcopy(jobs)
        next(j for j in successful_worker if j['id'] == reference['consumer']['jobID'])['conclusion'] = 'success'
        with self.assertRaisesRegex(ci.Rejected, 'zero-test result carries native state evidence or successful worker'):
            inspect(job_values=successful_worker)
        for marker in ('S10_4_MINIMUM_CORE_SMOKE_CHECKPOINT', 'S10_4_MINIMUM_CORE_SMOKE_COMPLETE', 'S10_4_AX_STATE'):
            with self.subTest(contradictoryMarker=marker):
                with self.assertRaises(ci.Rejected): inspect(log_value=log + ('\n' + marker + ' {}\n').encode())
        # Read-only views and SQLite inspection must leave every retained original byte unchanged.
        self.assertEqual(native_path.read_bytes(), native_before)
        self.assertEqual(log_path.read_bytes(), log)
        self.assertEqual(ci.sha(artifact / 'UISmoke.xcresult/database.sqlite3'), database_hash)
        self.assertEqual(ci.cache_inventory(original), inventory_before)

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

    def test_real_failed_interleaved_start_is_complete_nonaccepting_factual_inspection(self):
        folder = self.root / 'Temp/S10_4_CI/registry/requests/25ca31a0246643f7b2b26d6391369f99'
        originals = folder / 'originals'; run_value = ci.load(originals / 'run.json')
        self.assertEqual((run_value['id'], run_value['head_sha'], run_value['conclusion']),
                         (34423087881, '2927b049bfdd8d5219a70e4d7e2f877ffb9b4000', 'failure'))
        source = ci.Source(self.root, run_value['head_sha'], Path(self.snapshot.name) / 'failed-start-source')
        artifact = ci.wide(originals / '10132599696/artifact')
        reference_path = artifact / 'shared-consumer/consumer-build-reference.json'
        consumer = ci.load(reference_path)['consumer']
        selected = {'kind': 'consumer', 'head': source.head, 'shardID': consumer['shardID'], 'segmentID': consumer['segmentID']}
        jobs = ci.load(originals / 'jobs.json')['jobs']
        request_intent = ci.load(folder / 'intent.json')
        original = ci.verify_collection(originals, request_intent, run_value['id'])
        observed = [reference_path, artifact / 's10-4-shared-ui-command.json', artifact / 'ui-smoke.log',
                    artifact / 'ui-failure-diagnostics/xcresult-test-results.json', artifact / 'UISmoke.xcresult/database.sqlite3',
                    artifact / 'ui-failure-attachments/manifest.json']
        before = {str(path): ci.sha(path) for path in observed}
        facts = ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, run_value['conclusion'], original)
        self.assertTrue(facts['consumerReferenceVerified']); self.assertEqual(facts['producerUnitCount'], 5)
        self.assertFalse(facts['markerProtocolValid']); self.assertEqual(len(facts['malformedSegmentStartDiagnostics']), 1)
        diagnostic = facts['malformedSegmentStartDiagnostics'][0]
        self.assertFalse(diagnostic['originalMarkerValidJSON']); self.assertFalse(diagnostic['derivedMarkerCreated'])
        self.assertIn('Class UIAccessibilityLoaderWebShared is implemented in both', diagnostic['nativeWarning'])
        self.assertEqual((diagnostic['lineNumber'], diagnostic['lineStartByteOffset'], diagnostic['nativeWarningStartByteOffset']),
                         (34, 4050, 4387))
        self.assertEqual(facts['nativeTests'][0]['result'], 'Failed')
        self.assertEqual((facts['strictOwnedCount'], facts['replayCount'], facts['ownedJourneyCount'], facts['candidatePNGCount']),
                         (0, 0, 0, 0))
        self.assertEqual(facts['nativeCandidateAttachmentRowCount'], 0)
        self.assertEqual(facts['failedMalformedStartZeroEvidence']['events'], 0)
        self.assertEqual(facts['failedMalformedStartNativeResult']['databaseSHA256'],
                         '980C2CD7A053C1BC4E497B72B4FC892B0493AA4918EF49C8C2963A127D7BBF7C')
        self.assertEqual(facts['frozenFailedOriginal']['originalFilesSHA256'], original['originalFilesSHA256'])
        self.assertFalse(facts['fullSegmentComplete']); self.assertFalse(facts['fullShardComplete'])
        self.assertIn('Malformed segmented START retained as a nonaccepting protocol defect; original marker remains invalid.', facts['gaps'])
        self.assertEqual(before, {str(path): ci.sha(path) for path in observed})

        # A failure string alone cannot opt into recovery; the verified terminal original is mandatory.
        with self.assertRaises(ci.Rejected):
            ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, 'failure')

        original_load = ci.load
        command_path = artifact / 's10-4-shared-ui-command.json'
        for changed in ('source', 'command'):
            def mutated_load(path):
                value = original_load(path)
                if str(path) == str(reference_path) and changed == 'source':
                    value = copy.deepcopy(value); value['source']['head'] = '0' * 40
                if str(path) == str(command_path) and changed == 'command':
                    value = value.copy(); value[-1] = 'build'
                return value
            with self.subTest(changed=changed), patch.object(ci, 'load', side_effect=mutated_load), \
                 patch.object(ci, 'failed_start_zero_evidence') as zero_proof, self.assertRaises(ci.Rejected):
                ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, 'failure', original)
            zero_proof.assert_not_called()

        native_path = artifact / 'ui-failure-diagnostics/xcresult-test-results.json'
        def native_success_load(path):
            value = original_load(path)
            if str(path) == str(native_path):
                value = copy.deepcopy(value)
                def rewrite(node):
                    if isinstance(node, dict):
                        if node.get('nodeType') == 'Test Case': node['result'] = 'Passed'
                        for child in node.values(): rewrite(child)
                    elif isinstance(node, list):
                        for child in node: rewrite(child)
                rewrite(value)
            return value
        with patch.object(ci, 'load', side_effect=native_success_load), self.assertRaises(ci.Rejected):
            ci.consumer_facts(source, artifact, selected, run_value['id'], jobs, 'failure', original)

        contradictory_jobs = copy.deepcopy(jobs)
        next(job for job in contradictory_jobs if job['id'] == consumer['jobID'])['conclusion'] = 'success'
        with self.assertRaises(ci.Rejected):
            ci.consumer_facts(source, artifact, selected, run_value['id'], contradictory_jobs, 'failure', original)


class MinimumCoreSmokeProtocol(unittest.TestCase):
    """Synthetic protocol fixtures; no native or hosted PASS is claimed."""
    def setUp(self):
        import runpy
        self.payload = types.SimpleNamespace(**runpy.run_path(str(Path(__file__).with_name('s10-4-build-payload.py'))))
        self.k = self.payload.smoke_proof.__globals__
        fixture_parent=Path(__file__).resolve().parent/'Temp'
        fixture_parent.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=fixture_parent)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.contract = dict(schemaVersion=1, contractID=self.payload.SMOKE_ID, shardID=SHARD, ordinal=8,
            segmentID='none', executionLane=self.payload.SMOKE_LANE, runnerProvider='github',
            proofKind='functional-smoke', checkpointCount=6, checkpointIDs=self.payload.SMOKE_CHECKPOINTS,
            nativeEnvironmentKeys=self.payload.SMOKE_KEYS, fullMatrixEligible=False, fullShardComplete=False, fullSegmentComplete=False)
        (self.root/'Scripts').mkdir()
        self.put('Scripts/s10-4-segment-plan.json', {'minimumCoreSmoke':self.contract})
        self.env=dict(CI_S10_4_SHARED_BUILD_MODE='consumer', CI_S10_4_EXECUTION_ROLE='payload-consumer',
            CI_RUNNER_PROVIDER='github', CI_RUNNER_LABEL='macos-26', CI_S10_4_SHARD_ID=SHARD,
            CI_S10_4_SEGMENT_ID='none', WORKER_S10_4_MINIMUM_SEGMENT_ID='none', CI_S10_4_DIAGNOSTIC_PROBE_ID='none',
            CI_S10_4_PILOT_MODE='false', GITHUB_REF=self.payload.SMOKE_REF, GITHUB_SHA=H)
        for key,value in zip(self.payload.SMOKE_KEYS,[self.payload.SMOKE_ID,H,self.payload.SMOKE_REF,self.payload.SMOKE_LANE]):
            self.env[key]=self.env['TEST_RUNNER_'+key]=value

    def put(self,path,value):
        p=self.root/path; p.parent.mkdir(parents=True,exist_ok=True)
        p.write_text(json.dumps(value),encoding='utf-8')

    def test_environment_complete_absent_and_every_partial(self):
        self.assertEqual(len(self.payload.smoke_environment(self.env,self.root,self.payload.SMOKE_ID)),4)
        empty={k:v for k,v in self.env.items() if 'MINIMUM_CORE_SMOKE_' not in k}
        self.assertEqual(self.payload.smoke_environment(empty,self.root,'none'),{})
        for key in [k for k in self.env if 'MINIMUM_CORE_SMOKE_' in k]:
            with self.subTest(key=key):
                bad=dict(self.env); del bad[key]
                with self.assertRaises(self.payload.PayloadError): self.payload.smoke_environment(bad,self.root,self.payload.SMOKE_ID)
        with self.assertRaises(self.payload.PayloadError): self.payload.smoke_environment(self.env,self.root,'none')

    def test_environment_foreign_conflicting_and_other_routes(self):
        for key,value in dict(CI_S10_4_SHARED_BUILD_MODE='producer',CI_S10_4_EXECUTION_ROLE='independent',
                CI_RUNNER_PROVIDER='bitrise',CI_S10_4_SHARD_ID='s10.4.minimum.double-length',CI_S10_4_SEGMENT_ID='segment-1',
                WORKER_S10_4_MINIMUM_SEGMENT_ID='minimum-segment-1',CI_S10_4_DIAGNOSTIC_PROBE_ID='minimum-preflight',
                GITHUB_SHA='2'*40,GITHUB_REF='refs/heads/main',TEST_RUNNER_CI_S10_4_MINIMUM_CORE_SMOKE_EXTRA='x',
                CI_S10_4_MINIMUM_CORE_SMOKE_ID='foreign',TEST_RUNNER_CI_S10_4_MINIMUM_CORE_SMOKE_HEAD='3'*40).items():
            with self.subTest(key=key):
                with self.assertRaises(self.payload.PayloadError): self.payload.smoke_environment(dict(self.env,**{key:value}),self.root,self.payload.SMOKE_ID)

    def test_explicit_dispatch_mode_and_legacy_input_identity(self):
        old=row(); self.assertNotIn('s10_4_minimum_core_smoke_id',ci.inputs(old,2,{}))
        smoke=dict(kind='consumer',shardID=SHARD,segmentID='none',provider='github',dependencies=[],owned=0,replay=0,
                   proofKind='functional-smoke',checkpointCount=6,nativeMode=self.payload.SMOKE_ID)
        source=ci.Source.__new__(ci.Source); source.tuples=[old,smoke]
        with self.assertRaises(ci.Rejected): source.tuple('consumer',SHARD,'none')
        self.assertEqual(source.tuple('consumer',SHARD,'none',self.payload.SMOKE_ID),smoke)
        selected=ci.inputs(smoke,2,{})
        self.assertEqual(selected['s10_4_minimum_core_smoke_id'],self.payload.SMOKE_ID)
        value=intent(); value.update(smoke,inputs=selected)
        original=run(value=value)
        with self.assertRaises(ci.Rejected): ci.run_identity(original,value,3)
        original['display_title']+=' · smoke='+self.payload.SMOKE_ID
        self.assertEqual(ci.run_identity(original,value,3),original)
        for changed in (dict(smoke,owned=67),dict(smoke,nativeMode='foreign'),dict(smoke,shardID='s10.4.current.default-light')):
            with self.assertRaises(ci.Rejected): ci.inputs(changed,2,{})
        with self.assertRaises(ci.Rejected): ci.full_shard_proof(None,None,smoke,{})
        with self.assertRaises(ci.Rejected): ci.full_shard_proof(None,None,{},dict(consumer={'nativeMode':self.payload.SMOKE_ID}))

    def test_source_inventory_preserves_every_legacy_tuple(self):
        import subprocess
        checkout=next(parent for parent in Path(__file__).resolve().parents if (parent/'.git').exists())
        def source(path): return subprocess.check_output(['git','show','bba048eb06ecd97945b7f8cd4bede55371c41257:'+path],cwd=checkout)
        old_ci=types.ModuleType('baseline_ci'); exec(compile(source('Scripts/s10-4-ci.py'),'<baseline>','exec'),old_ci.__dict__)
        plan=json.loads(source('Scripts/s10-4-segment-plan.json')); shards=json.loads(source('Scripts/s10-4-shards.json'))
        obj=ci.Source.__new__(ci.Source); obj.plan=plan; obj.shards=shards; obj.root=self.root
        obj.payload=types.SimpleNamespace(selection_contract=lambda *a:None,smoke_contract=lambda *a:self.contract)
        obj.context=lambda sid:dict(segments=plan['minimumVerification']['segments'] if sid.startswith('s10.4.minimum.') else plan['segments'])
        baseline=old_ci.Source.inventory(obj)
        obj.plan=dict(plan,minimumCoreSmoke=self.contract)
        current=ci.Source.inventory(obj)
        self.assertEqual(current[:-1],baseline)
        self.assertEqual(sum(r['kind']=='consumer' for r in current),sum(r['kind']=='consumer' for r in baseline)+1)
        self.assertEqual(sum(r['kind']=='assembly' for r in current),sum(r['kind']=='assembly' for r in baseline))
        self.assertEqual((current[-1]['owned'],current[-1]['checkpointCount']),(0,6))

    def fixture(self):
        import sqlite3, struct, zlib, subprocess
        p=self.payload
        artifact=self.root
        consumer=dict(nativeMode=p.SMOKE_ID,shardID=SHARD,segmentID='none',purpose='acceptance',simulatorUDID='F'*8+'-FFFF-FFFF-FFFF-'+'F'*12)
        reference=dict(consumer=consumer,source=dict(head=H),productsUnchanged=True,diagnosticOnly=False,
            unitTestCount=0,producerUnitTestCount=5,sharedBuildIdentitySHA256='A'*64,producerQualificationSHA256='B'*64)
        admission={k:reference[k] for k in ('source','sharedBuildIdentitySHA256','producerQualificationSHA256')}
        admission['selection']=dict(shardID=SHARD,segmentID='none',purpose='acceptance',nativeMode=p.SMOKE_ID)
        self.put('shared-producer/admission.json',admission)
        self.put('shared-consumer/consumer-build-reference.json',reference)
        self.put('ui-test-results.json',{'testNodes':[dict(nodeType='Test Case',result='Passed')]})
        self.put('s10-4-smoke-environment.json',{'fixture':True})
        identity=dict(schemaVersion=1,contractID=p.SMOKE_ID,shardID=SHARD,head=H,ref=p.SMOKE_REF,executionLane=p.SMOKE_LANE)
        events=['S10_4_MINIMUM_CORE_SMOKE_CHECKPOINT '+json.dumps(dict(identity,checkpointID=c,ordinal=i,
            attachmentName='S10.4 minimum core smoke '+c)) for i,c in enumerate(p.SMOKE_CHECKPOINTS,1)]
        events.append('S10_4_MINIMUM_CORE_SMOKE_COMPLETE '+json.dumps(dict(identity,checkpointIDs=p.SMOKE_CHECKPOINTS,functionalSmokeComplete=True,fullMatrixEligible=False)))
        (self.root/'ui-smoke.log').write_text('\n'.join(events+['** TEST EXECUTE SUCCEEDED **']),encoding='utf-8')
        dbpath=self.root/'UISmoke.xcresult/database.sqlite3'; dbpath.parent.mkdir()
        db=sqlite3.connect(dbpath)
        db.executescript('CREATE TABLE TestCases(identifier TEXT); CREATE TABLE TestCaseRuns(testCase_fk INTEGER,result TEXT);'
            'CREATE TABLE Activities(testCaseRun_fk INTEGER,parent_fk INTEGER,failureIDs TEXT,expectedFailureIDs TEXT);'
            'CREATE TABLE Attachments(uuid TEXT,filenameOverride TEXT,uniformTypeIdentifier TEXT,testIssue_fk INTEGER,activity_fk INTEGER,xcResultKitPayloadRefId TEXT);'
            'CREATE TABLE TestIssues(x TEXT); CREATE TABLE TestErrors(x TEXT); CREATE TABLE ExpectedFailures(x TEXT);')
        ui_id='S10_4AutomatedBrandLabUITests/testAutomatedBrandLabShard'
        db.execute('INSERT INTO TestCases VALUES(?)',(ui_id+'()',)); db.execute("INSERT INTO TestCaseRuns VALUES(1,'Success')")
        db.execute("INSERT INTO Activities VALUES(1,NULL,'','')")
        def chunk(kind,raw): return struct.pack('>I',len(raw))+kind+raw+struct.pack('>I',zlib.crc32(kind+raw)&0xffffffff)
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',750,1334,8,0,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(751*1334)))+chunk(b'IEND',b'')
        exports=[]; (self.root/'s10-4-smoke-attachments').mkdir(); (dbpath.parent/'Data').mkdir()
        for i,checkpoint in enumerate(p.SMOKE_CHECKPOINTS+['terminal'],1):
            uuid=f'{i:08X}-AAAA-AAAA-AAAA-AAAAAAAAAAAA'; name='S10.4 minimum core smoke '+checkpoint
            filename=uuid+'.png'; ref='payload'+str(i)
            db.execute('INSERT INTO Attachments VALUES(?,?,?,NULL,1,?)',(uuid,name,'public.png',ref))
            (self.root/'s10-4-smoke-attachments'/filename).write_bytes(png); (dbpath.parent/'Data'/('data.'+ref)).write_bytes(png)
            exports.append(dict(suggestedHumanReadableName=name,exportedFileName=filename,isAssociatedWithFailure=False,deviceId=consumer['simulatorUDID']))
        with (self.root/'ui-smoke.log').open('a',encoding='utf-8') as stream:
            for e in exports: stream.write('\nFile: '+e['exportedFileName']+', suggested name: "'+e['suggestedHumanReadableName']+'"')
        db.commit(); db.close()
        self.put('s10-4-smoke-attachments/manifest.json',[dict(testIdentifier=ui_id+'()',attachments=exports)])
        (self.root/'ui-final.png').write_bytes(png)
        # Native identity/source gates have their independent tests; this fixture focuses
        # on the new event, SQLite ownership and PNG proof, with real PNG validation.
        checkout=next(parent for parent in Path(__file__).resolve().parents if (parent/'.git').exists())
        raw=subprocess.check_output(['git','show','bba048eb06ecd97945b7f8cd4bede55371c41257:Scripts/s10-4-segment-assembler.sh'],cwd=checkout).decode()
        body=raw.split("<<'S10_4_SHARED_SEGMENT_PY'\n",1)[1].split('\nS10_4_SHARED_SEGMENT_PY',1)[0]
        assembler=types.ModuleType('fixture_assembler'); exec(body,assembler.__dict__)
        fake=types.SimpleNamespace(UI_ID=ui_id,png=assembler.png,plan_context=lambda *a,**kw:{},native_ui=lambda *a:'D'*64)
        return reference, fake

    def proof(self, reference, fake):
        with patch.dict(self.k,consumer_identity=lambda *a:None,smoke_kernel=lambda *a:fake):
            return self.payload.smoke_proof(self.root,self.root,reference)

    def test_original_checkpoint_sqlite_png_proof_is_not_full(self):
        reference,fake=self.fixture(); result=self.proof(reference,fake)
        self.assertTrue(result['smokeComplete']); self.assertEqual(result['checkpointCount'],6)
        self.assertEqual(len(result['attachments']),7)
        for key in ('fullMatrixEligible','fullShardComplete','fullSegmentComplete'): self.assertIs(result[key],False)

    def test_missing_duplicate_reordered_wrong_head_and_native_failure_reject(self):
        reference,fake=self.fixture(); path=self.root/'ui-smoke.log'; original=path.read_text(); lines=original.splitlines()
        mutations=['\n'.join(lines[1:]),'\n'.join([lines[0]]+lines), '\n'.join([lines[1],lines[0]]+lines[2:]),
                   original.replace(H,'2'*40),original.replace('capture-review','wrong'),original.replace('SUCCEEDED','FAILED'),
                   original+'\nS10_MIGRATION_STATE state.welcome.empty']
        for value in mutations:
            with self.subTest(value=value[:90]):
                path.write_text(value)
                with self.assertRaises(self.payload.PayloadError): self.proof(reference,fake)
        path.write_text(original)
        self.put('ui-test-results.json',{'testNodes':[dict(nodeType='Failure Message',name='original native failure')]})
        with self.assertRaises(self.payload.PayloadError): self.proof(reference,fake)

    def test_duplicate_foreign_missing_corrupt_native_png_reject(self):
        reference,fake=self.fixture(); path=self.root/'s10-4-smoke-attachments/manifest.json'; original=json.loads(path.read_text())
        for mutate in ('duplicate','foreign','failed','missing'):
            value=copy.deepcopy(original)
            if mutate=='duplicate': value[0]['attachments'][1]=value[0]['attachments'][0]
            elif mutate=='foreign': value[0]['attachments'][0]['deviceId']='foreign'
            elif mutate=='failed': value[0]['attachments'][0]['isAssociatedWithFailure']=True
            else: value[0]['attachments'].pop()
            path.write_text(json.dumps(value))
            with self.assertRaises(self.payload.PayloadError): self.proof(reference,fake)
        path.write_text(json.dumps(original))
        first=self.root/'s10-4-smoke-attachments'/original[0]['attachments'][0]['exportedFileName']
        first.write_bytes(b'not png')
        with self.assertRaises((self.payload.PayloadError,ValueError)): self.proof(reference,fake)

    def test_stale_selection_wrong_source_and_false_units_reject(self):
        reference,fake=self.fixture()
        for bad in (dict(reference,source=dict(head='2'*40)),dict(reference,producerUnitTestCount=4),dict(reference,unitTestCount=True),dict(reference,productsUnchanged=False)):
            with self.assertRaises(self.payload.PayloadError): self.proof(bad,fake)
        path=self.root/'shared-producer/admission.json'; value=json.loads(path.read_text()); value['selection'].pop('nativeMode'); path.write_text(json.dumps(value))
        with self.assertRaises(self.payload.PayloadError): self.proof(reference,fake)

    def test_foreign_native_activity_failed_database_and_payload_missing_reject(self):
        import sqlite3
        reference,fake=self.fixture(); path=self.root/'UISmoke.xcresult/database.sqlite3'
        for update,restore in [("UPDATE Activities SET testCaseRun_fk=99","UPDATE Activities SET testCaseRun_fk=1"),
                ("UPDATE TestCaseRuns SET result='Failure'","UPDATE TestCaseRuns SET result='Success'"),
                ("INSERT INTO ExpectedFailures VALUES('unexpected')","DELETE FROM ExpectedFailures")]:
            db=sqlite3.connect(path); db.execute(update); db.commit(); db.close()
            with self.assertRaises(self.payload.PayloadError): self.proof(reference,fake)
            db=sqlite3.connect(path); db.execute(restore); db.commit(); db.close()
        (self.root/'UISmoke.xcresult/Data/data.payload1').unlink()
        with self.assertRaises(self.payload.PayloadError): self.proof(reference,fake)

    def test_empty_referenced_native_payload_rejected(self):
        reference,fake=self.fixture()
        (self.root/'UISmoke.xcresult/Data/data.payload1').write_bytes(b'')
        with self.assertRaisesRegex(self.payload.PayloadError,'payload absent or empty'):
            self.proof(reference,fake)

    def test_consumer_facts_retains_smoke_events_and_never_promotes(self):
        # Exercise the actual factual-consumer/parser seam, not smoke_proof alone.
        # The independent producer/source admission boundary is synthetic here;
        # all command, hash, isolation, native identity and marker parsing below run.
        import shlex
        reference,fake=self.fixture(); c=reference['consumer']
        c.update(runID=3,runAttempt=1,jobID=4,runnerName='synthetic-runner',isolationID='E'*8+'-EEEE-EEEE-EEEE-'+'E'*12)
        products={'synthetic':True}; qualification={'syntheticFiveUnitBoundary':True}
        identity=dict(source=reference['source'],products=products)
        reference.update(products=products,sharedBuildIdentitySHA256=self.payload.object_sha(identity),
                         producerQualificationSHA256=self.payload.object_sha(qualification),xctestrunPath='/synthetic/Smoke.xctestrun')
        isolation=dict(createdByThisJob=True,preexistingDevice=False,**{key:c[key] for key in ('runID','jobID','simulatorUDID','isolationID')})
        reference['isolationReceiptSHA256']=ci.digest(ci.canonical(isolation))
        command=['xcodebuild','-xctestrun',reference['xctestrunPath'],'-destination','platform=iOS Simulator,id='+c['simulatorUDID'],
                 '-resultBundlePath','/synthetic/UISmoke.xcresult','CODE_SIGNING_ALLOWED=NO',
                 '-only-testing:FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests','test-without-building']
        reference['uiCommand']=command
        self.put('shared-consumer/consumer-build-reference.json',reference)
        self.put('s10-4-shared-isolation.json',isolation)
        self.put('s10-4-shared-ui-command.json',command)
        self.put('shared-producer/shared-build-seal.json',dict(sharedBuildIdentity=identity,producerQualificationSHA256=reference['producerQualificationSHA256']))
        path=self.root/'ui-smoke.log'; log='Command line invocation:\n'+shlex.join(command)+'\n'+path.read_text(encoding='utf-8'); path.write_text(log,encoding='utf-8',newline='\n')
        device=dict(simulatorName='iPhone SE (3rd generation)',simulatorRuntime='iOS 18.0',simulatorRuntimeBuild='22A3351')
        native=dict(testNodes=[dict(nodeType='Test Case',nodeIdentifier=fake.UI_ID+'()',result='Passed')],
                    devices=[dict(deviceId=c['simulatorUDID'],deviceName=device['simulatorName'],osVersion='18.0',osBuildNumber='22A3351',architecture='arm64',platform='iOS Simulator')])
        self.put('ui-test-results.json',native)
        source=types.SimpleNamespace(root=self.root,head=H,identity=reference['source'],payload=self.payload,assembler=fake,
                                     context=lambda sid:dict(minimum=True,device=device,segments=[]))
        selected=dict(shardID=SHARD,segmentID='none',nativeMode=self.payload.SMOKE_ID,
                      inputs=dict(s10_4_minimum_core_smoke_id=self.payload.SMOKE_ID))
        jobs=[dict(id=4,head_sha=H,run_id=3,runner_name=c['runnerName'],conclusion='success')]
        with patch.object(self.payload,'consumer_identity',return_value=None), patch.object(self.payload,'qualification',return_value=qualification):
            result=ci.consumer_facts(source,self.root,selected,3,jobs,'success')
            self.assertEqual(result['smokeCheckpointCount'],6)
            self.assertEqual(len(result['nativeEvents']['S10_4_MINIMUM_CORE_SMOKE_COMPLETE']),1)
            self.assertTrue(result['consumerReferenceVerified'])
            self.assertFalse(result['smokeComplete']); self.assertFalse(result['fullShardComplete']); self.assertFalse(result['fullSegmentComplete'])
            self.assertEqual(result['gaps'],[])
            path.write_text(log+'\nS10_4_AX_STATE {}',encoding='utf-8',newline='\n')
            with self.assertRaises(ci.Rejected): ci.consumer_facts(source,self.root,selected,3,jobs,'success')
            # Failed partial execution remains factual and never becomes a success.
            partial='\n'.join(line for line in log.splitlines() if not line.startswith('S10_4_MINIMUM_CORE_SMOKE_COMPLETE'))
            partial=partial.replace('** TEST EXECUTE SUCCEEDED **','** TEST EXECUTE FAILED **')
            path.write_text(partial,encoding='utf-8',newline='\n'); native['testNodes'][0]['result']='Failed'; self.put('ui-test-results.json',native)
            failed=ci.consumer_facts(source,self.root,selected,3,[dict(jobs[0],conclusion='failure')],'failure')
            self.assertFalse(failed['smokeComplete']); self.assertFalse(failed['fullShardComplete'])
            self.assertEqual(failed['smokeCheckpointCount'],6); self.assertTrue(failed['gaps'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
