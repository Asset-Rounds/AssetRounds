#!/usr/bin/env python3
"""Finite synthetic Phase 1 transport behavior; no native/gate qualification.

The test runner, not the Source author, imports the actual candidate modules.
No app process, Simulator, Git, provider API, or native command is executed here.
"""
import base64
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load(relative, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CI = load("Scripts/v23-native-ci.py", "phase1_emitted_native_tests")
UI = load("Scripts/v23-ui-evidence.py", "phase1_emitted_ui_tests")
G = load("Scripts/v23-phase1-gates.py", "phase1_emitted_gate_tests")
STREAM_A = "00000000-0000-0000-0000-000000000001"
STREAM_B = "00000000-0000-0000-0000-000000000002"
EMITTER = "00000000-0000-0000-0000-000000000003"
UDID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"


def finite_context(artifact, *, role="consumer", phase="unit", exact_main=False):
    return {"schema": CI.PHASE1_EMITTED_CONTEXT_SCHEMA,
        **{key: "A" * 64 for key in ("originalEventSHA256", "eventBindingSHA256", "admissionSHA256",
            "planSHA256", "selectionSHA256", "writerSourceSHA256", "durableSinkBindingSHA256")},
        "head": "a" * 40, "tree": "b" * 40,
        "ref": "refs/heads/main" if exact_main else "refs/heads/codex/v23-s10-integration-20260910",
        "runID": "123", "runAttempt": "1",
        "purpose": "phase1-exact-main-functional-v1" if exact_main else "phase1-candidate-functional-v1",
        "selectionID": CI.SHARED_SELECTION_ID if role == "consumer" else CI.UI_BATCH_SELECTION_ID,
        "role": role, "partitionID": "S01" if role == "consumer" else "", "phase": phase,
        "simulatorUDID": UDID, "executionScope": "phase1-simulator-functional-gate-v1",
        "durableSinkPath": str(artifact / CI.phase1_emitted_names(phase)["sink"])}


def finite_frame(stream, sequence=1):
    payload = ("V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_V2"
        " policyID=V23-SIMULATOR-FILE-PROTECTION-DIAGNOSTIC-20260915"
        " disposition=SIMULATOR_FILE_PROTECTION_UNSUPPORTED kind=database request=complete"
        " capabilityBefore=false capabilityAfter=false urlProtection=completeUntilFirstUserAuthentication"
        " backupExcluded=false expectsDirectory=false identityUnchanged=true\n").encode()
    return CI.canonical({"schema": CI.SIMULATOR_DIAGNOSTIC_FRAME_SCHEMA,
        "streamID": stream, "sequence": sequence, "payloadBase64": base64.b64encode(payload).decode("ascii"),
        "payloadByteCount": len(payload), "payloadSHA256": CI.sha256(payload)})


def finite_stream(context, stream=STREAM_A, *, binding_hash=None):
    frame = finite_frame(stream)
    common = {"schema": CI.PHASE1_DURABLE_RECORD_SCHEMA, "streamID": stream, "emitterID": EMITTER,
        "contextSHA256": CI.sha256(CI.canonical(context)),
        "bindingSHA256": context["durableSinkBindingSHA256"] if binding_hash is None else binding_hash}
    start = {**common, "kind": "STREAM_START", "actualPID": 123,
        "actualHome": "/finite-synthetic-app-container", "actualBundleID": CI.SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID,
        "actualExecutable": "/finite-synthetic-app-container/FieldEvidenceApp"}
    prepare = {**common, "kind": "FRAME_PREPARE", "sequence": 1,
               "frameBytes": len(frame), "frameSHA256": CI.sha256(frame)}
    return [CI.canonical(start), CI.canonical(prepare), frame, CI.canonical({**prepare, "kind": "FRAME_COMMIT"})]


def finite_event_plan(*, version=2, purpose=None, selection=None):
    """Synthetic declared identities; actual plan constructors, no worker authority."""
    purpose = G.CANDIDATE if purpose is None else purpose
    selection = G.SHARED if selection is None else selection
    resolved = G.canonical({"unitTestSelectors": ["FieldEvidenceAppTests/Fixture/test_one"],
        "uiTestSelectors": ["FieldEvidenceAppUITests/Fixture/test_ui"] if selection == G.RUI1 else []})
    sources = {path: "A" * 64 for path in G.SOURCES}
    sources.update(G.POLICIES)
    arguments = {"purpose": purpose, "head": "a" * 40, "tree": "b" * 40, "selection": selection,
        "resolved_bytes": resolved, "sources": sources, "requested_at": "2026-10-06T00:00:00Z"}
    if version == 2:
        plan = G.make_plan_v2(**arguments, cold_prerequisite={"runID": 101,
            "assessmentSHA256": "A" * 64, "manifestSHA256": "B" * 64, "reviewSHA256": "C" * 64})
    elif version == 1:
        plan = G.make_plan(**arguments)
    else:
        raise ValueError("finite event fixture version")
    return plan, resolved, sources



class Phase1EmittedContextTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="phase1-emitted-finite-")
        self.addCleanup(temporary.cleanup)
        self.artifact = Path(temporary.name).resolve()
        self.context = finite_context(self.artifact)

    def parse(self, raw, context=None, fence=None):
        path = self.artifact / "finite-raw.jsonl"
        path.write_bytes(raw)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
        consumed = []
        try:
            observed = CI._phase1_durable_parse(descriptor, context or self.context,
                (context or self.context)["durableSinkBindingSHA256"], fence or (lambda: None),
                lambda stream, line: consumed.append((stream, line)))
            self.assertEqual(os.lseek(descriptor, 0, os.SEEK_CUR), len(raw))
            return observed, consumed
        finally:
            os.close(descriptor)


    def test_original_event_format_routes_actual_v2_and_preserves_original_digest(self):
        for purpose in (G.CANDIDATE, G.EXACT_MAIN):
            for selection in (G.SHARED, G.RUI1):
                plan, resolved, sources = finite_event_plan(purpose=purpose, selection=selection)
                event = {"inputs": G.dispatch_inputs_v2(plan), "repository": {"full_name": G.REPOSITORY},
                    "ref": plan["ref"], "fixtureLabel": "noncanonical original"}
                pretty = json.dumps(event, indent=2).encode("utf-8")
                for raw in (pretty, pretty + b"\n", b" " + json.dumps(event).encode("utf-8")):
                    with self.subTest(purpose=purpose, selection=selection, rawSHA256=G.sha(raw)):
                        self.assertNotEqual(raw, G.canonical(event))
                        self.assertEqual(CI.phase1_plan_from_event(ROOT, raw), G.plan_from_event_v2(raw))
                        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": G.REPOSITORY,
                            "GITHUB_REF": plan["ref"], "GITHUB_SHA": plan["head"], "GITHUB_RUN_ID": "202",
                            "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKFLOW_SHA": plan["head"],
                            "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + plan["ref"]}
                        binding = G.bind_original_event_v2(raw, environment, head=plan["head"], tree=plan["tree"],
                            resolved_bytes=resolved, sources=sources)
                        self.assertEqual(binding["originalEventSHA256"], G.sha(raw))
                        self.assertNotEqual(binding["originalEventSHA256"], G.sha(G.canonical(event)))
                        self.assertEqual(binding["plan"], plan)
                        self.assertEqual(binding["functionalQualification"], G.PENDING)

    def test_original_event_legacy_empty_and_cold_routes_remain_distinct(self):
        for event in ({"eventName": "ordinary"}, {"inputs": {}},
            {"inputs": {G.PLAN_INPUT: "", G.COLD_PLAN_INPUT: ""}}):
            raw = json.dumps(event, indent=2).encode("utf-8")
            self.assertEqual(CI.phase1_plan_from_event(ROOT, raw), G.plan_from_event(raw))
            self.assertIsNone(CI.phase1_plan_from_event(ROOT, raw)[0])
        plan, _, sources = finite_event_plan(version=1)
        legacy = {"inputs": G.dispatch_inputs(plan)}
        raw = json.dumps(legacy, indent=2).encode("utf-8")
        self.assertEqual(CI.phase1_plan_from_event(ROOT, raw), (plan, legacy))
        self.assertEqual(CI.phase1_plan_from_event(ROOT, raw), G.plan_from_event(raw))
        cold_resolved = G.canonical({"tier": "D40P", "runUISmoke": False,
            "unitTestSelectors": ["FieldEvidenceAppTests/Fixture/test_one"], "uiTestSelectors": [],
            "sharedCoverage": {"partitionID": None, "partitionsPath": G.PARTITIONS,
                "partitionsSHA256": sources[G.PARTITIONS], "developmentOnly": True, "acceptance": False}})
        cold = G.make_cold_plan(head=plan["head"], tree=plan["tree"], resolved_bytes=cold_resolved,
            sources=sources, requested_at=plan["requestedAtUTC"])
        event = {"inputs": G.cold_dispatch_inputs(cold)}
        raw = json.dumps(event, indent=2).encode("utf-8")
        self.assertEqual(CI.phase1_plan_from_event(ROOT, raw), (None, event))
        self.assertEqual(G.cold_plan_from_event(raw), (cold, event))
        self.assertEqual(cold["kind"], "development")
        self.assertEqual(cold["classification"]["functionalQualification"], G.COLD_PENDING)

    def test_original_event_malformed_duplicate_nonfinite_input_and_simultaneous_intent_refuse(self):
        plan, _, _ = finite_event_plan()
        canonical_plan = G.canonical(plan).decode("utf-8")
        hostile = [None, bytearray(b"{}"), b"", b" " * (G.MAX_EVENT_BYTES + 1), b"\xff", b"[1]", b"null", b"{",
            b'{"inputs":{},"inputs":{}}', b'{"inputs":{"v23_phase1_gate_plan":"","v23_phase1_gate_plan":""}}',
            b'{"inputs":{},"repository":{"full_name":"one","full_name":"two"}}',
            b'{"inputs":{},"extra":NaN}', b'{"inputs":{},"extra":Infinity}', b'{"inputs":{},"extra":-Infinity}']
        hostile.extend(json.dumps({"inputs": value}).encode() for value in (None, [], True, "wrong"))
        for key in (G.PLAN_INPUT, G.COLD_PLAN_INPUT):
            hostile.extend(json.dumps({"inputs": {key: value}}).encode() for value in (None, True, 7, {}))
        for version in (1, 2):
            current, _, _ = finite_event_plan(version=version)
            hostile.append(json.dumps({"inputs": {G.PLAN_INPUT: G.canonical(current).decode(),
                G.COLD_PLAN_INPUT: "simultaneous dedicated cold intent"}}, indent=2).encode())
        for index, raw in enumerate(hostile):
            with self.subTest(index=index), self.assertRaises(ValueError):
                CI.phase1_plan_from_event(ROOT, raw)
        self.assertEqual(CI.phase1_plan_from_event(ROOT,
            json.dumps({"inputs": {G.PLAN_INPUT: canonical_plan}}, indent=2).encode())[0], plan)

    def test_original_event_format_does_not_normalize_or_accept_noncanonical_embedded_plans(self):
        for version in (1, 2):
            plan, _, _ = finite_event_plan(version=version)
            canonical_plan = G.canonical(plan).decode("utf-8")
            hostile = [json.dumps(plan, indent=2), canonical_plan.rstrip("\n"), " " + canonical_plan,
                canonical_plan.replace('"schema":', '"schema":"duplicate","schema":', 1)]
            for key, value in (("schema", "foreign"), ("head", "A" * 40), ("acceptance", True)):
                bad = copy.deepcopy(plan); bad[key] = value
                hostile.append(G.canonical(bad).decode("utf-8"))
            for encoded in hostile:
                with self.subTest(version=version, encodedSHA256=G.sha(encoded.encode())), self.assertRaises(ValueError):
                    CI.phase1_plan_from_event(ROOT, json.dumps({"inputs": {G.PLAN_INPUT: encoded}}, indent=2).encode())
            self.assertEqual(CI.phase1_plan_from_event(ROOT,
                json.dumps({"inputs": {G.PLAN_INPUT: canonical_plan}}, indent=2).encode())[0], plan)

    def test_candidate_and_exact_main_shared_and_rui1_contexts_are_closed(self):
        for exact_main in (False, True):
            for role, phase in (("consumer", "unit"), ("rui1", "unit"), ("rui1", "ui")):
                with self.subTest(exact_main=exact_main, role=role, phase=phase):
                    value = finite_context(self.artifact, role=role, phase=phase, exact_main=exact_main)
                    self.assertIs(CI.phase1_emitted_validate_context(value), value)

    def test_context_rejects_development_role_ref_phase_selection_unknown_and_wrong_types(self):
        mutations = [("schema", CI.COLD_EMITTED_CONTEXT_SCHEMA), ("role", "producer"),
            ("executionScope", "cold-shared-route-development-v1"), ("ref", "refs/heads/main"),
            ("purpose", "phase1-unreviewed"), ("phase", "ui"), ("selectionID", CI.COLD_SELECTION_ID),
            ("runAttempt", "2"), ("runID", "0"), ("head", "A" * 40), ("writerSourceSHA256", "a" * 64),
            ("partitionID", "S99/alias"), ("simulatorUDID", UDID.lower()), ("acceptance", "true"),
            ("admissionSHA256", 7), ("durableSinkPath", "/tmp/../phase1-emitted-durable-original-unit")]
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                bad = {**self.context, key: value}
                with self.assertRaises(ValueError):
                    CI.phase1_emitted_validate_context(bad)
        missing = dict(self.context); missing.pop("phase")
        with self.assertRaises(ValueError):
            CI.phase1_emitted_validate_context(missing)

    def test_forwarding_is_exact_canonical_three_value_map(self):
        forwarded = CI.phase1_emitted_forward_environment(self.context)
        self.assertEqual(set(forwarded), {"TEST_RUNNER_V23_PHASE1_EMITTED_MODE",
            "TEST_RUNNER_V23_PHASE1_EMITTED_CONTEXT", "TEST_RUNNER_V23_PHASE1_EMITTED_CONTEXT_SHA256"})
        self.assertEqual(forwarded["TEST_RUNNER_V23_PHASE1_EMITTED_MODE"], CI.PHASE1_EMITTED_MODE)
        raw = base64.b64decode(forwarded["TEST_RUNNER_V23_PHASE1_EMITTED_CONTEXT"], validate=True)
        self.assertEqual(raw, CI.canonical(self.context))
        self.assertEqual(forwarded["TEST_RUNNER_V23_PHASE1_EMITTED_CONTEXT_SHA256"], CI.sha256(raw))

    def test_inherited_phase1_or_cold_context_refuses_before_effects(self):
        for prefix in ("V23_PHASE1_EMITTED_", "TEST_RUNNER_V23_PHASE1_EMITTED_",
                       "V23_COLD_EMITTED_", "TEST_RUNNER_V23_COLD_EMITTED_"):
            with self.subTest(prefix=prefix), mock.patch.object(CI, "phase1_worker_context") as context:
                with self.assertRaises(ValueError):
                    CI.phase1_emitted_context_forwarding(ROOT, self.artifact, {}, {prefix + "MODE": "forged"}, "unit")
                context.assert_not_called()
                self.assertEqual(list(self.artifact.iterdir()), [])

    def test_compiler_guard_requires_actual_gate_define_and_refuses_cold_dual_or_missing(self):
        CI.phase1_emitted_compiler_context_guard(["builtin-SwiftDriver -- -D" + CI.PHASE1_EMITTED_CONTEXT_DEFINE])
        CI.phase1_emitted_compiler_context_guard(["builtin-SwiftDriver -- -D " + CI.PHASE1_EMITTED_CONTEXT_DEFINE])
        for lines in ([], ["builtin-SwiftDriver -- -DDEBUG"],
            ["builtin-SwiftDriver -- -D" + CI.PHASE1_EMITTED_CONTEXT_DEFINE, "builtin-SwiftDriver -- -DDEBUG"],
            ["builtin-SwiftDriver -- -D" + CI.PHASE1_EMITTED_CONTEXT_DEFINE + " -D" + CI.COLD_EMITTED_CONTEXT_DEFINE]):
            with self.subTest(lines=lines), self.assertRaises(ValueError):
                CI.phase1_emitted_compiler_context_guard(lines)

    def test_complete_raw_two_vanished_stream_union_preserves_actual_framed_bytes(self):
        raw = b"".join(finite_stream(self.context, STREAM_A) + finite_stream(self.context, STREAM_B))
        observed, consumed = self.parse(raw)
        self.assertEqual(observed["rawBytes"], len(raw))
        self.assertEqual(observed["rawSHA256"], CI.sha256(raw))
        self.assertEqual(consumed, [(STREAM_A, finite_frame(STREAM_A)), (STREAM_B, finite_frame(STREAM_B))])
        self.assertEqual(observed["streams"], [{"streamID": stream, "lastCommittedSequence": 1,
            "bytes": len(finite_frame(stream)), "sha256": CI.sha256(finite_frame(stream))} for stream in (STREAM_A, STREAM_B)])
        self.assertEqual(set(observed["streamStarts"]), {STREAM_A, STREAM_B})

    def test_raw_missing_truncated_duplicate_wrong_context_binding_and_host_refuse(self):
        pieces = finite_stream(self.context)
        raw = b"".join(pieces)
        hostile = [b"".join(pieces[:-1]), raw[:-1], pieces[0], pieces[0] + raw,
            raw.replace(CI.sha256(CI.canonical(self.context)).encode(), b"B" * 64),
            b"".join(finite_stream(self.context, binding_hash="B" * 64)),
            raw.replace(b'"actualPID":123', b'"actualPID":0'),
            raw.replace(b'"actualBundleID":"com.palatis3.fieldrecord"', b'"actualBundleID":"foreign"'),
            raw + b"unfinished-tail"]
        for index, bad in enumerate(hostile):
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.parse(bad)

    def test_raw_cold_controls_and_foreign_phase_never_relabel_to_gate(self):
        raw = b"".join(finite_stream(self.context))
        with self.assertRaises(ValueError):
            self.parse(raw.replace(CI.PHASE1_DURABLE_RECORD_SCHEMA.encode(), CI.COLD_DURABLE_RECORD_SCHEMA.encode()))
        other = finite_context(self.artifact, role="rui1", phase="ui")
        with self.assertRaises(ValueError):
            self.parse(raw, context=other)

    def test_raw_changed_during_full_read_refuses_actual_eof_endpoint(self):
        raw = b"".join(finite_stream(self.context))
        changed = False
        def mutate():
            nonlocal changed
            if not changed:
                changed = True
                with (self.artifact / "finite-raw.jsonl").open("ab") as stream:
                    stream.write(b"late-append\n")
        with self.assertRaises(ValueError):
            self.parse(raw, fence=mutate)
        self.assertTrue(changed)

    def test_raw_empty_is_an_observation_with_no_implicit_seal_or_qualification(self):
        observed, consumed = self.parse(b"")
        self.assertEqual(observed, {"rawBytes": 0, "rawSHA256": CI.sha256(b""), "streamStarts": {}, "streams": []})
        self.assertEqual(consumed, [])
        self.assertNotIn("emittedBoundary", observed)
        self.assertNotIn("functionalQualification", observed)

    def test_prepare_uses_gate_binding_actual_owners_and_refuses_exclusive_reuse(self):
        base = {k: v for k, v in self.context.items() if k not in ("durableSinkPath", "durableSinkBindingSHA256")}
        retained = {}
        prepared = CI.phase1_durable_prepare(self.artifact, base, retained)
        sink = self.artifact / CI.phase1_emitted_names("unit")["sink"]
        self.assertEqual(sorted(p.name for p in sink.iterdir()), ["BINDING.json", "EMITTED.jsonl", "STATE"])
        header_raw = (sink / "BINDING.json").read_bytes()
        self.assertEqual(prepared["bindingSHA256"], CI.sha256(header_raw))
        self.assertEqual(prepared["binding"]["schema"], CI.PHASE1_DURABLE_SCHEMA)
        self.assertEqual(prepared["binding"]["originalContext"], base)
        self.assertEqual((sink / "STATE").read_bytes(), b"OPEN\n")
        self.assertEqual((sink / "EMITTED.jsonl").read_bytes(), b"")
        self.assertTrue(prepared["actualAppReadWriteSyncStillRequired"])
        self.assertFalse(prepared["qualification"])
        close_rows = [row for row in retained["io"] if row.get("closeEntered")]
        self.assertTrue(close_rows)
        self.assertTrue(all(row["closeReturned"] and not row["closeUncertain"] for row in close_rows))
        with self.assertRaises(ValueError):
            CI.phase1_durable_prepare(self.artifact, base, {})
        self.assertEqual((sink / "BINDING.json").read_bytes(), header_raw)

    def test_raw_leaf_symlink_and_hardlink_refuse_before_acquired_reader(self):
        target = self.artifact / "finite-target"
        target.write_bytes(b"finite synthetic")
        for variant in ("symlink", "hardlink"):
            with self.subTest(variant=variant):
                directory = self.artifact / variant; directory.mkdir()
                leaf = directory / "EMITTED.jsonl"
                if variant == "symlink": leaf.symlink_to(target)
                else: os.link(target, leaf)
                descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
                owners = []
                try:
                    with self.assertRaises(ValueError):
                        CI._cold_durable_leaf(descriptor, "EMITTED.jsonl", os.O_RDONLY, owners, "reader")
                    self.assertEqual(owners, [])
                finally:
                    os.close(descriptor)
                    leaf.unlink()

    def test_first_body_error_survives_secondary_close_and_each_owner_is_attempted_once(self):
        first = OSError("finite primary write")
        second = OSError("finite secondary close")
        rows = []
        with mock.patch.object(CI.os, "close", side_effect=[second, None]) as close:
            returned = CI._phase1_durable_close([("parent", 101), ("writer", 102)], rows, first)
        self.assertIs(returned, first)
        self.assertEqual(close.call_args_list, [mock.call(102), mock.call(101)])
        self.assertEqual(rows[0]["error"], repr(second))
        self.assertTrue(rows[0]["closeUncertain"])
        self.assertFalse(rows[0]["closeReturned"])
        self.assertTrue(rows[1]["closeReturned"])

    def test_success_path_failed_or_non_none_close_refuses_without_retry(self):
        failure = OSError("finite positive write then close failure")
        with mock.patch.object(CI.os, "close", side_effect=failure) as close:
            returned = CI._phase1_durable_close([("writer", 101)], [], None)
        self.assertIs(returned, failure)
        close.assert_called_once_with(101)
        with mock.patch.object(CI.os, "close", return_value=0) as close:
            returned = CI._phase1_durable_close([("writer", 101)], [], None)
        self.assertIsInstance(returned, ValueError)
        close.assert_called_once_with(101)

    def test_exclusive_partial_write_preserves_first_object_secondary_close_and_original_bytes(self):
        path = self.artifact / "failed-original.json"
        raw = b"finite-original-byte-body\n"
        first, second = OSError("finite actual partial body"), OSError("finite secondary close")
        actual_write, actual_close = os.write, os.close
        writer, closed = [], []
        def fail_write(descriptor, value):
            writer.append(descriptor)
            self.assertEqual(actual_write(descriptor, value[:3]), 3)
            raise first
        def fail_secondary_close(descriptor):
            closed.append(descriptor)
            actual_close(descriptor)
            if descriptor == writer[0]: raise second
        with mock.patch.object(CI.os, "write", side_effect=fail_write), \
             mock.patch.object(CI.os, "close", side_effect=fail_secondary_close):
            with self.assertRaises(OSError) as raised:
                CI._phase1_durable_emit(path, raw)
        self.assertIs(raised.exception, first)
        self.assertEqual(len(closed), 2)
        self.assertEqual(len(closed), len(set(closed)))
        self.assertEqual(closed[0], writer[0])
        self.assertEqual(path.read_bytes(), raw[:3])
        with self.assertRaises(ValueError):
            CI._phase1_durable_emit(path, raw)
        self.assertEqual(path.read_bytes(), raw[:3])

    def test_exclusive_complete_write_close_failure_refuses_and_retains_exact_original(self):
        path = self.artifact / "complete-but-close-failed.json"
        raw = b"finite-complete-original\n"
        failure = OSError("finite successful body failed close")
        actual_write, actual_close = os.write, os.close
        writer, closed = [], []
        def record_write(descriptor, value):
            writer.append(descriptor)
            return actual_write(descriptor, value)
        def fail_close(descriptor):
            closed.append(descriptor)
            actual_close(descriptor)
            if descriptor == writer[0]: raise failure
        with mock.patch.object(CI.os, "write", side_effect=record_write), \
             mock.patch.object(CI.os, "close", side_effect=fail_close):
            with self.assertRaises(OSError) as raised:
                CI._phase1_durable_emit(path, raw)
        self.assertIs(raised.exception, failure)
        self.assertEqual(len(closed), 2)
        self.assertEqual(len(closed), len(set(closed)))
        self.assertEqual(path.read_bytes(), raw)

    def test_ui_retained_runner_map_joins_actual_admission_and_refuses_foreign_phase(self):
        context = finite_context(self.artifact, role="rui1", phase="ui")
        record = {"head": context["head"], "gitTree": context["tree"], "ref": context["ref"], "runID": "123",
            "runAttempt": "1", "selectionSHA256": context["selectionSHA256"],
            "phase1Gate": {"schema": "v23-phase1-original-event-binding.v2", "planSHA256": context["planSHA256"],
                           "plan": {"purpose": context["purpose"]}}}
        context["admissionSHA256"] = CI.sha256(CI.canonical(record))
        receipt = {"schema": CI.PHASE1_EMITTED_FORWARD_SCHEMA, "context": context,
            "contextSHA256": CI.sha256(CI.canonical(context)), "forwardedEnvironment": CI.phase1_emitted_forward_environment(context)}
        path = self.artifact / "phase1-emitted-context-forwarding-ui.json"
        path.write_bytes(CI.canonical(receipt))
        self.assertEqual(UI.phase1_emitted_runner_environment_v2(self.artifact, record),
            {"TEST_RUNNER_V23_P1_AX_AUDIT_STRICT": "1", **receipt["forwardedEnvironment"]})
        for key, value in (("phase", "unit"), ("role", "consumer"), ("purpose", "foreign"),
                           ("admissionSHA256", "B" * 64), ("extraAuthority", "true")):
            with self.subTest(key=key):
                bad = copy.deepcopy(receipt); bad["context"][key] = value
                path.write_bytes(CI.canonical(bad))
                with self.assertRaises(ValueError):
                    UI.phase1_emitted_runner_environment_v2(self.artifact, record)


if __name__ == "__main__":
    unittest.main()
