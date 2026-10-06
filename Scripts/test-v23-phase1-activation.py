#!/usr/bin/env python3
"""Synthetic behavior checks. These fixtures never qualify an actual original."""
import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch


ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = load("phase1_activation_gate_fixture", ROOT / "Scripts/v23-phase1-gates.py")
D = load("phase1_activation_dispatch_fixture", ROOT / "Scripts/dev/v23-original.py")
HEAD, TREE, HASH = "a" * 40, "b" * 40, "A" * 64
STAMP = "2026-10-06T00:00:00Z"


def reference(name, raw=b"fixture\n"):
    return {"path": "/SYNTHETIC_ONLY/" + name, "bytes": len(raw), "SHA256": G.sha(raw)}


def inputs(selection=G.SHARED, purpose=G.CANDIDATE):
    resolved = {"unitTestSelectors": ["FieldEvidenceAppTests/Fixture/test_one"],
                "uiTestSelectors": ["FieldEvidenceAppUITests/Fixture/test_ui"] if selection == G.RUI1 else [],
                "sharedCoverage": {"partitionIDs": ["S01"]}}
    sources = {name: HASH for name in G.SOURCES}
    sources.update(G.POLICIES)
    controls = {key: reference(key) for key in ("assessment", "manifest", "review")}
    descriptor = {"runID": 101, **{key + "SHA256": value["SHA256"] for key, value in controls.items()}}
    plan = G.make_plan_v2(purpose=purpose, head=HEAD, tree=TREE, selection=selection,
        resolved_bytes=G.canonical(resolved), sources=sources, requested_at=STAMP, cold_prerequisite=descriptor)
    return plan, resolved, controls


def synthetic_phase1_event_v2(selection=G.SHARED, purpose=G.CANDIDATE, run_id=202):
    """Reusable UNIT fixture; only the external cold prerequisite is synthetic.

    The actual versioned plan, event parser and original binding run normally.
    This constructor creates no runtime original or independent review.
    """
    if type(run_id) is not int or run_id <= 0:
        raise ValueError("synthetic positive run ID")
    plan, resolved, controls = inputs(selection, purpose)
    event = {"inputs": G.dispatch_inputs_v2(plan), "repository": {"full_name": G.REPOSITORY}, "ref": plan["ref"]}
    raw = json.dumps(event, indent=2).encode("utf-8")
    environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": G.REPOSITORY,
        "GITHUB_REF": plan["ref"], "GITHUB_SHA": plan["head"], "GITHUB_RUN_ID": str(run_id), "GITHUB_RUN_ATTEMPT": "1",
        "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + plan["ref"],
        "GITHUB_WORKFLOW_SHA": plan["head"]}
    binding = G.bind_original_event_v2(raw, environment, head=plan["head"], tree=plan["tree"],
        resolved_bytes=G.canonical(resolved), sources=plan["sources"])
    return {"plan": plan, "resolved": resolved, "controls": controls, "event": event,
            "eventRaw": raw, "environment": environment, "binding": binding}


def phase():
    return {"contextSHA256": HASH, "forwardingReceiptSHA256": HASH, "durableProofSHA256": HASH,
        "bindingSHA256": HASH, "raw": {"path": "phase1-emitted-durable-original-unit/EMITTED.jsonl", "bytes": 0, "sha256": G.sha(b"")},
        "streams": [], "transportStatusSHA256": HASH, "emittedBoundary": "SEALED_COMPLETE_EMITTED_TRANSPORT"}


def chain(plan, resolved):
    labels = ["producer", *resolved["sharedCoverage"]["partitionIDs"]] if plan["selection"] == G.SHARED else ["rui1"]
    transport = {}
    for name in labels:
        phases = {} if name == "producer" else {"unit": phase()}
        if name == "rui1":
            phases["ui"] = phase()
            phases["ui"]["raw"]["path"] = "phase1-emitted-durable-original-ui/EMITTED.jsonl"
        transport[name] = {"role": "producer" if name == "producer" else ("rui1" if name == "rui1" else "consumer"),
                           "partitionID": name if name in resolved["sharedCoverage"]["partitionIDs"] else None, "phases": phases}
    return {"schema": G.CHAIN_SCHEMA_V2, "status": "RECOMPUTED_PHASE1_FUNCTIONAL_FACTS_DATA_ONLY",
        "runID": 202, "planSHA256": G.sha(G.canonical(plan)),
        "workers": {name: {"executedUnitMethods": [] if name == "producer" else resolved["unitTestSelectors"]} for name in labels},
        "executionProof": {"status": "RETAINED_EXECUTION_FACTS_VERIFIED", "problems": [],
            "jobs": {name: {} for name in labels}, "workers": {name: {} for name in labels}, "payload": {}},
        "emittedTransportV2": transport, "strongerClaims": dict(G.STRONGER_CLAIMS_V2),
        "functionalQualification": G.PENDING, "acceptance": False, "providerQualification": False,
        "releaseReady": False, "executionAuthority": False}


def pending_and_review(selection=G.SHARED):
    plan, _, controls = inputs(selection)
    gallery = {key: HASH for key in ("catalogueSHA256", "proofSHA256", "presentationSHA256", "checklistSHA256", "attachmentsSHA256")}
    pending = G.make_functional_assessment_v2(plan, run_id=202, manifest=reference("manifest"),
        chain=reference("chain"), cold_binding=controls, gallery=gallery if selection == G.RUI1 else None)
    pending_ref = reference("pending", G.canonical(pending))
    message, context = b"SYNTHETIC NONAUTHOR REVIEW MESSAGE\n", b"SYNTHETIC CONTEXT\n"
    review = {"schema": "root.faithful.received.phase1-functional-original-review.v2",
        "subject": "shared-cold-original" if selection == G.SHARED else "rui1-cold-original",
        "verdict": "PASS_BOUNDED_ACTUAL_PHASE1_SIMULATOR_FUNCTIONAL_ORIGINAL_V2",
        "reviewer": "/root/synthetic_review", "actualModel": "gpt-6.1-sol", "actualReasoningEffort": "xhigh",
        "independentNonauthor": True, "readOnly": True, "assessment": pending_ref,
        **{key: pending[key] for key in ("manifest", "chain", "head", "tree", "runID", "runAttempt", "purpose", "selection", "planSHA256", "sourceSHA256")},
        "message": reference("message", message), "context": reference("context", context),
        "executionAuthority": False, "acceptance": False, "releaseReady": False, "providerQualification": False}
    return plan, pending, pending_ref, review, message, context


def synthetic_phase1_attempt_v2(value):
    """Synthetic external observations; real closed V3 attempt producer/checker."""
    plan = value["plan"]
    registration = G.canonical(G.registration_record_v2(plan, value["controls"]))
    observations = {"repository": {"full_name": G.REPOSITORY, "id": 11},
        "workflow": {"id": 12, "path": G.ROUTE["workflow"], "state": "active"},
        "refs": {"integration": {"ref": G.INTEGRATION_REF, "object": {"type": "commit", "sha": HEAD}},
            "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": G.BASE_MAIN if plan["purpose"] == G.CANDIDATE else HEAD}}},
        "headRuns": {"total_count": 0, "workflow_runs": []},
        "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in G.ACTIVE_RUN_STATUSES}}
    return G.make_attempt_v2(plan, registration, collector_id="0" * 32, requested_at=STAMP,
        observations=observations, ledger_bytes="", attempt_names=[])


class Phase1ActivationBehaviorTests(unittest.TestCase):
    def test_real_payload_context_durable_union_and_gate_binding_bridge_stays_unqualified(self):
        """Synthetic Products/app frames; real parsers, owners, lock/seal/union.

        Only the two external Git identity observations return declared fixture
        values. No native app/Simulator/provider original or review is claimed.
        The full Native job/command checker remains a separate original proof.
        Optional synthetic callbacks respect the actual before/test/after order.
        """
        reader = load("phase1_activation_payload_fixture", ROOT / "Scripts/test-v23-phase1-retained-reader-v2.py")
        emitted = load("phase1_activation_emitted_fixture", ROOT / "Scripts/test-v23-phase1-emitted-context.py")
        ci, gate, kernel = reader.M.source_modules(ROOT)
        resolved, sources = ci["shared_selection"](ROOT), reader.M.source_closure(ROOT, gate)
        plan = gate["make_plan_v2"](purpose=gate["CANDIDATE"], head=HEAD, tree=TREE, selection=gate["SHARED"],
            resolved_bytes=ci["canonical"](resolved), sources=sources, requested_at=STAMP,
            cold_prerequisite={"runID": 101, "assessmentSHA256": HASH, "manifestSHA256": HASH, "reviewSHA256": HASH})
        labels = resolved["sharedCoverage"]["partitionIDs"]
        forwarded, retained_by_label = {}, {}
        def observed_git(argv, **kwargs):
            self.assertEqual(kwargs.get("cwd"), ROOT)
            if argv == ["git", "rev-parse", "HEAD"]:
                return HEAD + "\n"
            if argv == ["git", "rev-parse", "HEAD^{tree}"]:
                return TREE + "\n"
            self.fail("unexpected external command in UNIT fixture: " + repr(argv))
        def before_consumer_tests(member):
            artifact, record = member["artifact"], member["record"]
            label = record[ci["SHARED_KEY"]]["partitionID"]
            self.assertIn(label, labels)
            self.assertNotIn(label, forwarded)
            environment = {**member["environment"], "GITHUB_EVENT_NAME": "workflow_dispatch",
                "GITHUB_REPOSITORY": G.REPOSITORY, "GITHUB_REF": plan["ref"], "GITHUB_SHA": HEAD,
                "GITHUB_RUN_ID": "202", "GITHUB_RUN_ATTEMPT": "1",
                "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + plan["ref"],
                "GITHUB_WORKFLOW_SHA": HEAD, "GITHUB_EVENT_PATH": str(artifact / "phase1-original-event.json"),
                "NATIVE_SELECTION_ID": ci["SHARED_SELECTION_ID"], "CI_NATIVE_ACCEPTANCE_CONTRACT": ci["CONTRACT"],
                "V23_SHARED_ROLE": "consumer", "V23_PARTITION_ID": label,
                "V23_PAYLOAD_ARTIFACT_NAME": record[ci["SHARED_KEY"]]["payloadArtifactName"],
                "CI_NATIVE_CREATED_SIMULATOR_UDID": member["environment"]["CI_SIMULATOR_UDID"]}
            (artifact / "simulator-selection.txt").write_text("runtime=iOS 26.2\nruntime_build=23C54\nname=iPhone 17\n"
                + "initial_state=Shutdown\nudid=" + environment["CI_SIMULATOR_UDID"] + "\n")
            # The constructor has restored/fingerprinted products but has not
            # yet created synthetic test bookkeeping or after observations.
            self.assertEqual(ci["shared_build_evidence"](artifact, member["runnerTemp"]), [])
            metadata = ci["read_json"](artifact / ci["SHARED_PAYLOAD_METADATA"])
            self.assertEqual(ci["shared_products_binding"](kernel, member["runnerTemp"]), metadata["products"])
            ci["phase1_emitted_retain_forwarding"](ROOT, artifact, record, environment, "unit")
            forwarding = ci["read_json"](artifact / ci["phase1_emitted_names"]("unit")["forwarding"])
            forwarded[label] = {"environment": environment, "context": forwarding["context"]}
        def after_consumer_tests(member):
            artifact, record = member["artifact"], member["record"]
            label = record[ci["SHARED_KEY"]]["partitionID"]
            self.assertIn(label, forwarded)
            self.assertNotIn(label, retained_by_label)
            index = labels.index(label)
            environment, context = forwarded[label]["environment"], forwarded[label]["context"]
            self.assertEqual((artifact / "test-smoke.log").read_bytes(), b"** TEST EXECUTE SUCCEEDED **\n")
            self.assertTrue((member["runnerTemp"] / "FieldEvidenceDerivedData/Logs/Build/bookkeeping.xcactivitylog").is_file())
            # Two streams vanish before collection; all other workers genuinely emit zero UNIT bytes.
            raw = b"" if index else b"".join(part for stream in (emitted.STREAM_A, emitted.STREAM_B)
                for part in emitted.finite_stream(context, stream))
            sink = artifact / ci["phase1_emitted_names"]("unit")["sink"]
            (sink / "EMITTED.jsonl").write_bytes(raw)
            console = io.StringIO()
            with contextlib.redirect_stdout(console):
                status = ci["phase1_durable_collect"](ROOT, artifact, environment, False, 0,
                    time.monotonic(), time.monotonic)
            with (artifact / "test-smoke.log").open("ab") as stream:
                stream.write(console.getvalue().encode("utf-8"))
            diagnostics, error = ci["simulator_diagnostic_observations"](ROOT, artifact, record)
            self.assertIsNone(error)
            ci["_phase1_durable_emit"](artifact / ci["SIMULATOR_DIAGNOSTIC_OUTPUT"], ci["canonical"](diagnostics))
            retained = ci["phase1_retained_emitted_facts_v2"](ROOT, artifact, record, record["phase1Gate"])
            self.assertEqual(status["status"], "AVAILABLE" if index == 0 else "ZERO_USE")
            self.assertEqual((sink / "STATE").read_bytes(), b"SEALED\n")
            self.assertEqual(retained["phases"]["unit"]["raw"]["bytes"], len(raw))
            self.assertEqual(len(retained["phases"]["unit"]["streams"]), 2 if index == 0 else 0)
            retained_by_label[label] = retained
        with tempfile.TemporaryDirectory(prefix="synthetic-phase1-emitted-bridge-") as temporary:
            with patch.object(ci["subprocess"], "check_output", side_effect=observed_git):
                fixture = reader.make_phase1_payload_workers_v2(Path(temporary) / "workers", root=ROOT,
                    ci=ci, gate=gate, kernel=kernel, plan=plan, resolved=resolved, run_id=202,
                    before_consumer_tests=before_consumer_tests, after_consumer_tests=after_consumer_tests)
            self.assertTrue(fixture["synthetic"])
            self.assertFalse(fixture["qualification"])
            self.assertEqual(set(forwarded), set(labels))
            self.assertEqual(set(retained_by_label), set(labels))
            value = chain(plan, resolved)
            value["workers"]["producer"]["executedUnitMethods"] = []
            value["emittedTransportV2"]["producer"] = ci["phase1_retained_emitted_facts_v2"](
                ROOT, fixture["members"]["producer"]["artifact"], fixture["records"]["producer"], fixture["binding"])
            for index, label in enumerate(labels):
                member = fixture["members"][label]
                artifact, record = member["artifact"], member["record"]
                environment = forwarded[label]["environment"]
                value["emittedTransportV2"][label] = retained_by_label[label]
                value["workers"][label]["executedUnitMethods"] = member["selected"]["unitTestSelectors"]
                if index == 0:
                    with patch.object(ci["subprocess"], "check_output", return_value="c" * 40 + "\n"), self.assertRaises(ValueError):
                        ci["phase1_worker_context"](ROOT, environment)
                    proof_path = artifact / ci["phase1_emitted_names"]("unit")["proof"]
                    proof_mode = ci["stat"].S_IMODE(proof_path.stat().st_mode)
                    self.assertEqual(proof_mode, 0o444)
                    proof_raw = proof_path.read_bytes()
                    bad = ci["read_json"](proof_path); bad["executionAuthority"] = True
                    proof_first = None
                    proof_restoration = []
                    try:
                        # Only this test-owned disposable leaf is writable while
                        # changing bytes; real Reader always receives sealed mode.
                        proof_path.chmod(proof_mode | 0o200)
                        proof_path.write_bytes(ci["canonical"](bad))
                        proof_path.chmod(proof_mode)
                        self.assertEqual(ci["stat"].S_IMODE(proof_path.stat().st_mode), proof_mode)
                        with self.assertRaisesRegex(ValueError, "Phase1 retained complete emitted-only proof"):
                            ci["phase1_retained_emitted_facts_v2"](ROOT, artifact, record, fixture["binding"])
                    except BaseException as error:
                        proof_first = error
                    finally:
                        # Attempt every restoration operation independently;
                        # a cleanup error cannot replace an earlier body error.
                        for operation, action in (("owner-write", lambda: proof_path.chmod(proof_mode | 0o200)),
                                ("original-bytes", lambda: proof_path.write_bytes(proof_raw)),
                                ("original-mode", lambda: proof_path.chmod(proof_mode))):
                            try:
                                returned = action()
                            except BaseException as error:
                                proof_restoration.append({"operation": operation, "returned": None, "error": error})
                                if proof_first is None:
                                    proof_first = error
                            else:
                                proof_restoration.append({"operation": operation, "returned": returned, "error": None})
                        self.phase1_fixture_proof_restoration = proof_restoration
                    if proof_first is not None:
                        raise proof_first
                    self.assertEqual(proof_path.read_bytes(), proof_raw)
                    self.assertEqual(ci["stat"].S_IMODE(proof_path.stat().st_mode), proof_mode)
            output = G.validate_chain_v2(value, plan, resolved)
            self.assertEqual(output["functionalQualification"], G.PENDING)
            self.assertFalse(output["gateQualification"])
            self.assertFalse(output["executionAuthority"])

    def test_reusable_constructor_reaches_actual_noncanonical_event_parser(self):
        value = synthetic_phase1_event_v2(run_id=202)
        self.assertNotEqual(value["eventRaw"], G.canonical(value["event"]))
        self.assertEqual(value["binding"]["plan"], value["plan"])
        self.assertEqual(value["binding"]["runID"], "202")
        self.assertEqual(value["event"]["inputs"], G.dispatch_inputs_v2(value["plan"]))
        self.assertEqual(value["binding"]["functionalQualification"], G.PENDING)

    def test_closed_v2_plan_and_legacy_pending_are_distinct(self):
        plan, resolved, _ = inputs()
        G.validate_plan_v2(plan)
        legacy = G.make_plan(purpose=G.CANDIDATE, head=HEAD, tree=TREE, selection=G.SHARED,
            resolved_bytes=G.canonical(resolved), sources=plan["sources"], requested_at=STAMP)
        self.assertEqual(legacy["schema"], G.SCHEMA)
        self.assertEqual(legacy["classification"], G.CLASSIFICATION)
        with self.assertRaises(G.Refused):
            G.validate_plan_v2(legacy)
        self.assertEqual(plan["classification"]["functionalQualification"], G.PENDING)
        for key, value in (("kind", "development"), ("head", G.BASE_MAIN), ("ref", "refs/heads/main")):
            bad = copy.deepcopy(plan)
            bad[key] = value
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.validate_plan_v2(bad)

    def test_no_extra_cold_descriptor_or_route_budget_authority(self):
        plan, _, _ = inputs()
        for mutation in (lambda p: p["coldPrerequisite"].update(qualified=True),
                lambda p: p["coldPrerequisite"].update(runID=True),
                lambda p: p["coldPrerequisite"].pop("reviewSHA256"),
                lambda p: p["route"]["budgets"]["D50C"].__setitem__(2, 3001),
                lambda p: p["classification"].update(acceptance=True),
                lambda p: p["sources"].pop(G.COLLECTOR)):
            bad = copy.deepcopy(plan)
            mutation(bad)
            with self.subTest(bad=bad), self.assertRaises(G.Refused):
                G.validate_plan_v2(bad)

    def test_original_event_uses_real_noncanonical_github_bytes(self):
        plan, resolved, _ = inputs()
        event = {"inputs": G.dispatch_inputs_v2(plan), "repository": {"full_name": G.REPOSITORY}, "ref": plan["ref"]}
        raw = json.dumps(event, indent=2).encode()
        env = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": G.REPOSITORY,
            "GITHUB_REF": plan["ref"], "GITHUB_SHA": HEAD, "GITHUB_RUN_ID": "202", "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + plan["ref"], "GITHUB_WORKFLOW_SHA": HEAD}
        binding = G.bind_original_event_v2(raw, env, head=HEAD, tree=TREE,
            resolved_bytes=G.canonical(resolved), sources=plan["sources"])
        self.assertEqual(binding["originalEventSHA256"], G.sha(raw))
        self.assertEqual(binding["schema"], G.EVENT_SCHEMA_V2)
        for key, value in (("GITHUB_RUN_ATTEMPT", "2"), ("GITHUB_SHA", "c" * 40), ("GITHUB_REF", "refs/heads/main")):
            bad = dict(env, **{key: value})
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.bind_original_event_v2(raw, bad, head=HEAD, tree=TREE, resolved_bytes=G.canonical(resolved), sources=plan["sources"])
        bad_event = copy.deepcopy(event)
        bad_event["inputs"]["v23_cold_original_plan"] = "not empty"
        with self.assertRaises(G.Refused):
            G.plan_from_event_v2(json.dumps(bad_event).encode())

    def test_attempt_cannot_retry_unknown_original_or_moved_main(self):
        plan, _, controls = inputs()
        registration = G.canonical(G.registration_record_v2(plan, controls))
        observations = {"repository": {"full_name": G.REPOSITORY, "id": 11},
            "workflow": {"id": 12, "path": G.ROUTE["workflow"], "state": "active"},
            "refs": {"integration": {"ref": G.INTEGRATION_REF, "object": {"type": "commit", "sha": HEAD}},
                     "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": G.BASE_MAIN}}},
            "headRuns": {"total_count": 0, "workflow_runs": []},
            "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in G.ACTIVE_RUN_STATUSES}}
        args = dict(collector_id="0" * 32, requested_at=STAMP, observations=observations, ledger_bytes="", attempt_names=[])
        actual = G.make_attempt_v2(plan, registration, **args)
        self.assertEqual(actual["schema"], G.ATTEMPT_SCHEMA_V3)
        for mutation in (lambda a: a["observations"]["refs"]["main"]["object"].update(sha=HEAD),
                lambda a: a["observations"].update(headRuns={"total_count": 1, "workflow_runs": [{"id": 303, "head_sha": HEAD}]}),
                lambda a: a.update(attempt_names=[G.original_stem(plan) + ".json"])):
            bad = copy.deepcopy(args)
            mutation(bad)
            with self.subTest(bad=bad), self.assertRaises(G.Refused):
                G.make_attempt_v2(plan, registration, **bad)

    def test_exact_main_purpose_cannot_use_baseline_or_untyped_candidate(self):
        plan, resolved, _ = inputs(purpose=G.EXACT_MAIN)
        G.bind_facts_v2(plan, head=HEAD, tree=TREE, integration_head=HEAD, main_head=HEAD,
            resolved_bytes=G.canonical(resolved), sources=plan["sources"])
        with self.assertRaises(G.Refused):
            G.bind_facts_v2(plan, head=HEAD, tree=TREE, integration_head=HEAD, main_head=G.BASE_MAIN,
                resolved_bytes=G.canonical(resolved), sources=plan["sources"])
        self.assertTrue(G.conflicting_originals_v2(plan, [{"head": HEAD, "selection": G.SHARED, "kind": "development", "runID": 99}], []))
        candidate, _, _ = inputs()
        row = {"head": HEAD, "selection": G.SHARED, "kind": "gate", "runID": 202,
            "phase1Purpose": G.CANDIDATE, "phase1PlanBytes": G.canonical(candidate).decode(),
            "phase1PlanSHA256": G.sha(G.canonical(candidate)), "phase1RegistrationSchema": G.REGISTRATION_SCHEMA_V2}
        stem = G.original_stem(candidate)
        self.assertEqual(G.conflicting_originals_v2(plan, [row], [stem + ".json", stem + ".discovery"]), [])
        bad = dict(row, phase1PlanSHA256="B" * 64)
        self.assertTrue(G.conflicting_originals_v2(plan, [bad], [stem + ".json"]))

    def test_complete_synthetic_chain_stays_data_only_even_with_zero_emission(self):
        for selection in G.SELECTIONS:
            plan, resolved, _ = inputs(selection)
            value = chain(plan, resolved)
            result = G.validate_chain_v2(value, plan, resolved)
            self.assertEqual(result["functionalQualification"], G.PENDING)
            self.assertFalse(result["gateQualification"])
            self.assertFalse(result["executionAuthority"])
            self.assertFalse(result["acceptance"])

    def test_missing_worker_method_phase_or_terminal_proof_refuses(self):
        plan, resolved, _ = inputs()
        for mutation in (lambda c: c["workers"].pop("S01"),
                lambda c: c["workers"]["S01"].update(executedUnitMethods=[]),
                lambda c: c["workers"]["producer"].update(executedUnitMethods=resolved["unitTestSelectors"]),
                lambda c: c["emittedTransportV2"]["S01"].update(phases={}),
                lambda c: c["emittedTransportV2"]["S01"]["phases"]["unit"].update(emittedBoundary="OPEN"),
                lambda c: c["executionProof"].update(problems=["unresolved close"]),
                lambda c: c.update(executionAuthority=True),
                lambda c: c["strongerClaims"].update(totalPolicyCallCountProven=True)):
            bad = chain(plan, resolved)
            mutation(bad)
            with self.subTest(bad=bad), self.assertRaises(G.Refused):
                G.validate_chain_v2(bad, plan, resolved)

    def test_actual_uuid_stream_domain_and_duplicate_or_zero_sequence_refusal(self):
        plan, resolved, _ = inputs()
        value = chain(plan, resolved)
        phase_value = value["emittedTransportV2"]["S01"]["phases"]["unit"]
        stream = {"streamID": "00000000-0000-0000-0000-000000000001", "bytes": 20, "sha256": HASH, "lastCommittedSequence": 1}
        phase_value.update(streams=[stream], raw={"path": phase_value["raw"]["path"], "bytes": 20, "sha256": HASH})
        G.validate_chain_v2(value, plan, resolved)
        for key, altered in (("streamID", "0" * 32), ("bytes", True), ("bytes", 0),
                ("lastCommittedSequence", 0), ("lastCommittedSequence", 100001), ("sha256", HASH.lower())):
            bad = copy.deepcopy(value)
            bad["emittedTransportV2"]["S01"]["phases"]["unit"]["streams"][0][key] = altered
            with self.subTest(key=key, altered=altered), self.assertRaises(G.Refused):
                G.validate_chain_v2(bad, plan, resolved)
        bad = copy.deepcopy(value)
        bad["emittedTransportV2"]["S01"]["phases"]["unit"]["streams"].append(copy.deepcopy(stream))
        with self.assertRaises(G.Refused):
            G.validate_chain_v2(bad, plan, resolved)

    def test_review_scope_and_raw_message_bindings_are_strict(self):
        _, pending, pending_ref, review, message, context = pending_and_review()
        G.validate_functional_review_v2(review, pending_reference=pending_ref, pending=pending, message=message, context=context)
        for mutation in (lambda r: r.update(actualModel="other-model"), lambda r: r.update(independentNonauthor=False),
                lambda r: r.update(runAttempt=True), lambda r: r["chain"].update(bytes=1),
                lambda r: r.update(executionAuthority=True), lambda r: r.update(extra=True),
                lambda r: r["message"].update(SHA256="B" * 64)):
            bad = copy.deepcopy(review)
            mutation(bad)
            with self.subTest(bad=bad), self.assertRaises(G.Refused):
                G.validate_functional_review_v2(bad, pending_reference=pending_ref, pending=pending, message=message, context=context)

    def test_offline_review_cannot_rescue_failed_actual_original(self):
        _, pending, pending_ref, review, _, _ = pending_and_review()
        request = {"schema": "v23-phase1-functional-assessment-request.v2", "stage": "RECORD_REVIEWED_FUNCTIONAL",
            "runID": 202, "manifest": pending["manifest"], "priorAssessment": pending_ref,
            "independentReview": reference("review", G.canonical(review))}
        with patch.object(D, "phase1_gates", return_value=G), patch.object(D, "cold_v2_regular_bytes", return_value=G.canonical(request)),\
                patch.object(D, "phase1_original_data_v2", side_effect=G.Refused("actual native transport unresolved")),\
                patch.object(D, "phase1_publish_v2") as publish:
            with self.assertRaisesRegex(G.Refused, "actual native transport unresolved"):
                D.qualify_phase1_v2(Path("/SYNTHETIC_ONLY/request"))
            publish.assert_not_called()

    def test_reader_projection_requires_actual_manifest_bound_versioned_facts(self):
        plan, _, _ = inputs()
        directory = Path("/SYNTHETIC_ONLY/202")
        facts = {"schema": "v23-retained-payload-facts.v2",
            "status": "RECOMPUTED_PHASE1_RETAINED_PAYLOAD_DATA_ONLY_UNQUALIFIED",
            "durability": {"status": "FSYNCED_OWNED_DATA_PROJECTION"}, "pendingProof": ["synthetic external authenticity pending"],
            "workerJoins": {"status": "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA"}, "sourceSHA256": plan["sources"],
            "scope": {"emittedTransport": "PENDING", **{key: False for key in ("executionAuthority", "authentication",
                "qualification", "providerQualification", "acceptance", "releaseReady")}},
            "originalDATA": {"repository": G.REPOSITORY, "ref": plan["ref"], "head": plan["head"], "tree": plan["tree"],
                "runID": 202, "runAttempt": 1, "planSHA256": G.sha(G.canonical(plan))}}
        prefix = "phase1-payload-recomputations/000000/"
        def evidence(value):
            raw = G.canonical(value)
            receipt = {"schema": "v23-phase1-payload-recomputation.v1", "status": "RECOMPUTED_DURABLE_PAYLOAD_DATA",
                "failureCategory": None, "inputInvariance": True, "continuationRequired": False, "proofStatus": "INCOMPLETE",
                "functionalQualification": G.PENDING, "acceptance": False, "providerQualification": False, "releaseReady": False,
                "results": {"FACTS.json": {"SHA256": G.sha(raw)}}}
            receipt_raw = G.canonical(receipt)
            summary = {key: receipt[key] for key in ("status", "functionalQualification", "acceptance", "providerQualification",
                "releaseReady", "continuationRequired")}
            summary["receipt"] = {"path": prefix + "receipt.json", "SHA256": G.sha(receipt_raw)}
            manifest = {"files": {prefix + "receipt.json": G.sha(receipt_raw), prefix + "reader-owned/FACTS.json": G.sha(raw)}}
            files = {directory / (prefix + "receipt.json"): receipt_raw, directory / (prefix + "reader-owned/FACTS.json"): raw}
            return summary, manifest, files
        summary, manifest, files = evidence(facts)
        with patch.object(D, "cold_v2_regular_bytes", side_effect=lambda gate, path, **kwargs: files[path]):
            D.phase1_payload_binding_v2(G, directory, plan, {"payloadRecomputation": summary}, manifest)
        for mutation in (lambda f: f.update(schema="v23-retained-payload-facts.v1"),
                lambda f: f.update(status="supplied-qualified"), lambda f: f["durability"].update(status="PENDING"),
                lambda f: f.update(pendingProof=[]), lambda f: f["workerJoins"].update(status="PENDING"),
                lambda f: f["scope"].update(qualification=True),
                lambda f: f["sourceSHA256"].update({G.COLLECTOR: "B" * 64}),
                lambda f: f["originalDATA"].update(runAttempt=True)):
            bad = copy.deepcopy(facts); mutation(bad)
            summary, manifest, files = evidence(bad)
            with self.subTest(mutation=mutation), patch.object(D, "cold_v2_regular_bytes", side_effect=lambda gate, path, **kwargs: files[path]),\
                    self.assertRaises(G.Refused):
                D.phase1_payload_binding_v2(G, directory, plan, {"payloadRecomputation": summary}, manifest)
        summary, manifest, files = evidence(facts)
        manifest["files"][prefix + "reader-owned/FACTS.json"] = "B" * 64
        with patch.object(D, "cold_v2_regular_bytes", side_effect=lambda gate, path, **kwargs: files[path]), self.assertRaises(G.Refused):
            D.phase1_payload_binding_v2(G, directory, plan, {"payloadRecomputation": summary}, manifest)
        rui, _, _ = inputs(G.RUI1)
        D.phase1_payload_binding_v2(G, directory, rui, {"payloadRecomputation": None}, {})
        with self.assertRaises(G.Refused):
            D.phase1_payload_binding_v2(G, directory, rui, {"payloadRecomputation": summary}, {})

    def test_genuine_review_intake_keeps_human_owner_and_independent_model_distinct(self):
        message, context = b"SYNTHETIC UNIT approval message\n", b"SYNTHETIC UNIT source context\n"
        for subject in ("candidate-integration", "owner-critical-states"):
            owner = subject == "owner-critical-states"
            request = {"schema": G.REVIEW_REQUEST_SCHEMA, "testOnly": False, "subject": subject,
                "reportedDisposition": "approve", "head": HEAD, "tree": TREE,
                "originals": [{"runID": 202, "manifestSHA256": HASH}] if owner else [
                    {"runID": 202, "manifestSHA256": HASH}, {"runID": 203, "manifestSHA256": HASH}],
                "gallery": {key: HASH for key in ("catalogueSHA256", "proofSHA256", "presentationSHA256",
                    "checklistSHA256", "attachmentsSHA256")} if owner else None,
                "messageSHA256": G.sha(message), "contextSHA256": G.sha(context),
                "messageReference": "synthetic://unit/message", "conversationReference": "synthetic://unit/conversation",
                "messageTimestampUTC": STAMP, "speakerReference": "synthetic://owner" if owner else "synthetic://independent",
                "reviewer": None if owner else {"model": "gpt-6.1-sol", "effort": "xhigh",
                    "authorReference": "synthetic://author", "independenceReference": "synthetic://separate"}}
            record = G.make_review_record(request, message, context, {}, index=0, previous=None, captured_at=STAMP)
            ref = reference("provenance", G.canonical(record))
            receipt = {"schema": "root.faithful.received.phase1-candidate-review.v2", "subject": subject,
                "verdict": "APPROVE_PHASE1_FROZEN_CANDIDATE_V2", "reviewRecord": ref,
                **{key: request[key] for key in ("head", "tree", "originals", "gallery")},
                "reviewer": None if owner else "/root/synthetic_review", "actualModel": None if owner else "gpt-6.1-sol",
                "actualReasoningEffort": None if owner else "xhigh", "independentNonauthor": None if owner else True,
                "readOnly": None if owner else True, "humanOwner": owner, "message": reference("message", message),
                "context": reference("context", context), "executionAuthority": False, "acceptance": False,
                "releaseReady": False, "providerQualification": False}
            G.validate_genuine_candidate_review_v2(receipt, record, ref, message=message, context=context)
            for mutation in (lambda r: r.update(humanOwner=not owner), lambda r: r.update(executionAuthority=True),
                    lambda r: r.update(extra=True), lambda r: r["reviewRecord"].update(bytes=1),
                    lambda r: r.update(actualModel="model-substitute")):
                bad = copy.deepcopy(receipt); mutation(bad)
                with self.subTest(subject=subject, mutation=mutation), self.assertRaises(G.Refused):
                    G.validate_genuine_candidate_review_v2(bad, record, ref, message=message, context=context)

    def test_v2_settlement_preserves_actual_first_and_each_secondary_once(self):
        primary = ValueError("actual body first")
        observer_error, authority_error, collection_error = OSError("observer"), RuntimeError("authority"), KeyError("collection")
        calls = []
        def operation(label, error=None):
            def call():
                calls.append(label)
                if error is not None:
                    raise error
                return None
            return call
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(ValueError) as caught:
            D.phase1_settle_v2(primary, observer=operation("observer", observer_error),
                removals=(("authority", operation("authority", authority_error)), ("collection", operation("collection", collection_error))))
        self.assertIs(caught.exception, primary)
        self.assertEqual(calls, ["observer", "authority", "collection"])
        state = primary.phase1SettlementV2
        self.assertIs(state["primary"], primary)
        self.assertIs(state["observer"]["error"], observer_error)
        self.assertEqual([row["error"] for row in state["removals"]], [authority_error, collection_error])
        self.assertTrue(state["report"]["returnedNone"])
        for first_label in ("observer", "authority", "collection"):
            calls.clear()
            errors = {first_label: OSError(first_label)}
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(OSError) as caught:
                D.phase1_settle_v2(None, observer=operation("observer", errors.get("observer")),
                    removals=(("authority", operation("authority", errors.get("authority"))),
                              ("collection", operation("collection", errors.get("collection")))))
            self.assertIs(caught.exception, errors[first_label])
            self.assertEqual(calls, ["observer", "authority", "collection"])
        calls.clear()
        with contextlib.redirect_stderr(io.StringIO()):
            state = D.phase1_settle_v2(None, removals=(("authority", operation("authority")), ("collection", operation("collection"))))
        self.assertIsNone(state["primary"])
        self.assertEqual(calls, ["authority", "collection"])
        self.assertTrue(all(row["returnedNone"] for row in state["removals"]))
        self.assertFalse(state["executionAuthority"])
        report_error, fallback_error = OSError("report"), RuntimeError("fallback")
        with patch.object(D, "print", side_effect=[report_error, fallback_error], create=True), self.assertRaises(ValueError) as caught:
            D.phase1_settle_v2(primary)
        self.assertIs(caught.exception, primary)
        self.assertIs(primary.phase1SettlementV2["report"]["error"], report_error)
        self.assertIs(primary.phase1SettlementV2["fallback"]["error"], fallback_error)
        report_after_success = OSError("success report refusal")
        with patch.object(D, "print", side_effect=[report_after_success, None], create=True), self.assertRaises(OSError) as caught:
            D.phase1_settle_v2(None)
        self.assertIs(caught.exception, report_after_success)
        self.assertTrue(caught.exception.phase1SettlementV2["fallback"]["returnedNone"])
        class Unprintable(ValueError):
            def __repr__(self):
                raise RuntimeError("repr observation failed")
        unprintable = Unprintable("body")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(Unprintable) as caught:
            D.phase1_settle_v2(unprintable)
        self.assertIs(caught.exception, unprintable)
        self.assertIsInstance(unprintable.phase1SettlementV2["report"]["error"], RuntimeError)
        self.assertTrue(unprintable.phase1SettlementV2["fallback"]["returnedNone"])

    def test_actual_v2_lifecycle_and_collection_cleanup_keep_body_identity(self):
        plan, resolved, _ = inputs()
        body, cleanup = ValueError("frozen current body"), OSError("dispatch cleanup")
        evidence, lock = MagicMock(), MagicMock()
        evidence.is_symlink.return_value = False
        evidence.__truediv__.return_value = lock
        lock.rmdir.side_effect = cleanup
        with patch.object(D, "phase1_gates", return_value=G), patch.object(D, "EVIDENCE", evidence),\
                patch.object(D, "cold_v2_regular_bytes", return_value=G.canonical(plan)),\
                patch.object(D, "phase1_frozen_candidate", side_effect=body), patch.object(D, "api") as remote,\
                patch.object(D.subprocess, "run") as child, contextlib.redirect_stderr(io.StringIO()), self.assertRaises(ValueError) as caught:
            D.phase1_candidate_lifecycle(Path("/SYNTHETIC_ONLY/plan"), activation_v2=True)
        self.assertIs(caught.exception, body)
        self.assertIs(body.phase1SettlementV2["removals"][0]["error"], cleanup)
        lock.mkdir.assert_called_once_with()
        lock.rmdir.assert_called_once_with()
        remote.assert_not_called()
        child.assert_not_called()
        # A successful synthetic discovery still refuses when its positively owned lock cannot settle.
        _, _, controls = inputs()
        registration = G.canonical(G.registration_record_v2(plan, controls))
        observations = {"repository": {"full_name": G.REPOSITORY, "id": 11},
            "workflow": {"id": 12, "path": G.ROUTE["workflow"], "state": "active"},
            "refs": {"integration": {"ref": G.INTEGRATION_REF, "object": {"type": "commit", "sha": HEAD}},
                     "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": G.BASE_MAIN}}},
            "headRuns": {"total_count": 0, "workflow_runs": []},
            "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in G.ACTIVE_RUN_STATUSES}}
        consumed = G.make_attempt_v2(plan, registration, collector_id="0" * 32, requested_at=STAMP,
            observations=observations, ledger_bytes="", attempt_names=[])
        clean_evidence, clean_lock = MagicMock(), MagicMock()
        clean_evidence.is_symlink.return_value = False
        clean_evidence.__truediv__.return_value = clean_lock
        success_cleanup = OSError("successful discovery cleanup")
        clean_lock.rmdir.side_effect = success_cleanup
        with patch.object(D, "phase1_gates", return_value=G), patch.object(D, "EVIDENCE", clean_evidence),\
                patch.object(D, "cold_v2_regular_bytes", return_value=G.canonical(plan)),\
                patch.object(D, "phase1_frozen_candidate", return_value=(resolved, registration)),\
                patch.object(G, "regular_bytes", return_value=G.canonical(consumed)), patch.object(G, "durable_directory"),\
                patch.object(D, "phase1_discover_original", return_value={"synthetic": True, "qualification": False}) as discovered,\
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(OSError) as caught:
            D.phase1_candidate_lifecycle(Path("/SYNTHETIC_ONLY/plan"), activation_v2=True, discover=True)
        self.assertIs(caught.exception, success_cleanup)
        clean_lock.rmdir.assert_called_once_with()
        discovered.assert_called_once_with(G, plan, consumed, resolved)
        class MemoryStream(io.BytesIO):
            def fileno(self):
                return 999
        directory, children = MagicMock(), {}
        def child_path(name):
            if name not in children:
                member = MagicMock()
                member.exists.return_value = False
                member.open.return_value = MemoryStream()
                children[name] = member
            return children[name]
        directory.__truediv__.side_effect = child_path
        authority = MagicMock()
        evidence.__truediv__.return_value = authority
        authority_error, collector_error, observer_error = OSError("authority removal"), RuntimeError("collector removal"), KeyError("end observer")
        authority.rmdir.side_effect = authority_error
        child_path("phase1-collector-active").rmdir.side_effect = collector_error
        entry = {"index": 0, "status": "DISCOVERED_PENDING_PROOF", "runID": 202, "problems": [], "snapshot": {"transportFailure": False}}
        attempt = {"collectorID": "0" * 32, "collectorSHA256": HASH, "planSHA256": G.sha(G.canonical(plan))}
        context = (G, directory, {}, plan, attempt, b"dispatch\n", b"registration\n", b"attempt\n", resolved)
        with patch.object(D, "phase1_original_context", return_value=context), patch.object(D, "EVIDENCE", evidence),\
                patch.object(G, "durable_directory"), patch.object(G, "write_immutable"),\
                patch.object(D.os, "fsync", return_value=None),\
                patch.object(D, "phase1_capture_original", return_value={}),\
                patch.object(D, "phase1_record_discovery", side_effect=[entry, observer_error]) as observations,\
                patch.object(D, "api", side_effect=body), patch.object(D.subprocess, "run") as child,\
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(ValueError) as caught:
            D.collect_phase1(202, False)
        self.assertIs(caught.exception, body)
        self.assertEqual(observations.call_count, 2)
        state = body.phase1SettlementV2
        self.assertIs(state["observer"]["error"], observer_error)
        self.assertEqual([row["operation"] for row in state["removals"]], ["dispatch-authority-lock", "collection-lock"])
        self.assertEqual([row["error"] for row in state["removals"]], [authority_error, collector_error])
        authority.rmdir.assert_called_once_with()
        child_path("phase1-collector-active").rmdir.assert_called_once_with()
        child.assert_not_called()

    def test_both_exact_received_shapes_bind_actual_v2_event_and_v3_attempt_for_all_profiles(self):
        omitted = {"s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids", "v23_cold_original_plan"}
        for purpose in (G.CANDIDATE, G.EXACT_MAIN):
            for selection in G.SELECTIONS:
                value = synthetic_phase1_event_v2(selection, purpose)
                plan, attempt = value["plan"], synthetic_phase1_attempt_v2(value)
                requested = G.dispatch_inputs_v2(plan)
                self.assertEqual(len(requested), 13)
                self.assertTrue(all(requested[key] == "" for key in omitted))
                original_requested_bytes = attempt["inputBytes"]
                for absent, shape in ((set(), "COMPLETE_13"), (omitted, "OMITTED_EMPTY_DEFAULTS_10")):
                    event = copy.deepcopy(value["event"])
                    for key in absent:
                        event["inputs"].pop(key)
                    before = G.canonical(event)
                    raw = json.dumps(event, indent=2).encode("utf-8")
                    with self.subTest(purpose=purpose, selection=selection, shape=shape):
                        self.assertEqual(G.validate_received_inputs_v2(event["inputs"], plan), shape)
                        binding = G.bind_original_event_v2(raw, value["environment"], head=HEAD, tree=TREE,
                            resolved_bytes=G.canonical(value["resolved"]), sources=plan["sources"])
                        joined = G.verify_attempt_inputs(attempt, raw)
                        self.assertEqual(binding["originalEventSHA256"], G.sha(raw))
                        self.assertEqual(joined["originalEventSHA256"], G.sha(raw))
                        self.assertEqual(joined["inputSHA256"], G.sha(original_requested_bytes.encode("utf-8")))
                        self.assertEqual(original_requested_bytes, G.canonical(requested).decode("utf-8"))
                        self.assertEqual(G.canonical(event), before)
                        self.assertEqual(binding["functionalQualification"], G.PENDING)
                self.assertEqual(attempt["inputBytes"], original_requested_bytes)

    def test_partial_omissions_extra_keys_wrong_types_values_or_profiles_refuse_real_paths(self):
        omitted = ("s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids", "v23_cold_original_plan")
        for purpose in (G.CANDIDATE, G.EXACT_MAIN):
            for selection in G.SELECTIONS:
                value = synthetic_phase1_event_v2(selection, purpose)
                plan, attempt = value["plan"], synthetic_phase1_attempt_v2(value)
                original = value["event"]["inputs"]
                variants = []
                for index, key in enumerate(omitted):
                    one = dict(original); one.pop(key); variants.append(("one-omitted-" + key, one))
                    two = dict(original); two.pop(key); two.pop(omitted[(index + 1) % 3]); variants.append(("two-omitted-" + key, two))
                variants.append(("unknown-empty-field", {**original, "not_a_requested_field": ""}))
                variants.extend(("nondict-inputs-" + type(bad).__name__, bad) for bad in (None, False, 0, []))
                for key in original:
                    missing = dict(original); missing.pop(key)
                    if key not in omitted:
                        variants.append(("nondefault-missing-" + key, missing))
                    variants.append(("wrong-string-" + key, {**original, key: "wrong"}))
                    for bad in (None, False, 0, []):
                        variants.append(("wrong-type-" + key + "-" + type(bad).__name__, {**original, key: bad}))
                other = synthetic_phase1_event_v2(selection, G.EXACT_MAIN if purpose == G.CANDIDATE else G.CANDIDATE)
                variants.append(("different-purpose-profile", other["event"]["inputs"]))
                other = synthetic_phase1_event_v2(G.RUI1 if selection == G.SHARED else G.SHARED, purpose)
                variants.append(("different-selection-profile", other["event"]["inputs"]))
                for label, received in variants:
                    event = copy.deepcopy(value["event"]); event["inputs"] = received
                    raw = json.dumps(event, indent=2).encode("utf-8")
                    before = G.canonical(event)
                    with self.subTest(purpose=purpose, selection=selection, mutation=label):
                        with self.assertRaises(G.Refused):
                            G.validate_received_inputs_v2(received, plan)
                        try:
                            binding = G.bind_original_event_v2(raw, value["environment"], head=HEAD, tree=TREE,
                                resolved_bytes=G.canonical(value["resolved"]), sources=plan["sources"])
                        except G.Refused:
                            pass
                        else:
                            # Missing/null plan is ordinary non-gate DATA, never a V2 binding.
                            self.assertIsNone(binding)
                        with self.assertRaises(G.Refused):
                            G.verify_attempt_inputs(attempt, raw)
                        self.assertEqual(G.canonical(event), before)
                        self.assertEqual(attempt["inputBytes"], G.canonical(original).decode("utf-8"))

    def test_v3_attempt_requires_complete_persisted_request_even_for_valid_received10(self):
        value = synthetic_phase1_event_v2()
        plan, attempt = value["plan"], synthetic_phase1_attempt_v2(value)
        event = copy.deepcopy(value["event"])
        for key in ("s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids", "v23_cold_original_plan"):
            event["inputs"].pop(key)
        raw = json.dumps(event, indent=2).encode("utf-8")
        variants = [G.canonical(event["inputs"]).decode("utf-8"), G.canonical({**value["event"]["inputs"], "extra": ""}).decode("utf-8"),
            G.canonical({**value["event"]["inputs"], "v23_run_kind": "development"}).decode("utf-8"),
            None, False, 0, []]
        for requested in variants:
            bad = copy.deepcopy(attempt); bad["inputBytes"] = requested
            with self.subTest(requested=requested), self.assertRaises(G.Refused):
                G.verify_attempt_inputs(bad, raw)
        self.assertEqual(G.verify_attempt_inputs(attempt, raw)["inputSHA256"], G.sha(attempt["inputBytes"].encode("utf-8")))

    def test_missing_genuine_reader_blocks_without_dispatch_or_publication(self):
        plan, _, _ = inputs()
        with patch.object(D, "cold_v2_archived_call", side_effect=lambda gate, plan, callback: callback(Path("/SYNTHETIC_ONLY/source"))),\
                patch.object(D, "cold_v2_source_module", return_value={}), patch.object(D.subprocess, "run") as child:
            with self.assertRaisesRegex(G.Refused, "reader prerequisite missing"):
                D.phase1_reader_ready_v2(G, plan)
            child.assert_not_called()

    def test_legacy_dispatch_remains_inactive_without_any_observation(self):
        with patch.object(D, "phase1_gates", return_value=G), patch.object(D, "api") as remote, patch.object(D, "run") as git,\
                patch.object(D, "cold_v2_regular_bytes") as reader:
            with self.assertRaises(G.Refused):
                D.phase1_candidate_lifecycle(Path("/SYNTHETIC_ONLY/legacy-plan"))
            remote.assert_not_called()
            git.assert_not_called()
            reader.assert_not_called()

    def test_invalid_v2_plan_refuses_before_any_reservation(self):
        plan, _, _ = inputs()
        plan["classification"]["acceptance"] = True
        with patch.object(D, "phase1_gates", return_value=G), patch.object(D, "cold_v2_regular_bytes", return_value=G.canonical(plan)),\
                patch.object(D, "phase1_frozen_candidate") as frozen, patch.object(D, "api") as remote:
            with self.assertRaises(G.Refused):
                D.phase1_candidate_lifecycle(Path("/SYNTHETIC_ONLY/plan"), activation_v2=True)
            frozen.assert_not_called()
            remote.assert_not_called()

    def test_exact_main_rechecks_qualified_candidate_and_genuine_owner(self):
        plan, _, controls = inputs(purpose=G.EXACT_MAIN)
        candidate, _, _ = inputs()
        qualified = {selection: {"runID": i + 202, "tree": TREE, "sourceSHA256": plan["sources"], "coldBinding": controls}
                     for i, selection in enumerate(G.SELECTIONS)}
        context = (None, None, None, candidate)
        with patch.object(D, "phase1_candidate_originals_v2", return_value=qualified) as originals,\
                patch.object(D, "phase1_original_context", return_value=context),\
                patch.object(D, "phase1_candidate_reviews_v2", side_effect=G.Refused("genuine owner review missing")) as reviews:
            with self.assertRaisesRegex(G.Refused, "genuine owner review missing"):
                D.phase1_exact_main_prerequisites_v2(G, plan)
            originals.assert_called_once_with(G, HEAD, purpose=G.CANDIDATE)
            reviews.assert_called_once_with(G, HEAD, qualified)

    def test_full_main_verification_never_moves_refs_or_grants_release(self):
        originals = {selection: {"runID": i + 202} for i, selection in enumerate(G.SELECTIONS)}
        def git(*args):
            if args[:2] == ("git", "fetch"):
                return ""
            if args[:2] == ("git", "rev-parse"):
                return HEAD if args[2] != "origin/main" else G.BASE_MAIN
            if args[:2] == ("git", "diff"):
                return ""
            self.fail("unexpected Git mutation: " + repr(args))
        with patch.object(D, "phase1_gates", return_value=G),\
                patch.object(D, "phase1_candidate_originals_v2", return_value=originals),\
                patch.object(D, "phase1_candidate_reviews_v2", return_value={}), patch.object(D, "run", side_effect=git):
            result = D.verify_phase1_main_v2(HEAD)
            self.assertEqual(result["status"], "CANDIDATE_READY_FOR_ROOT_NONFORCE_FAST_FORWARD_V2")
            for key in ("executionAuthority", "acceptance", "providerQualification", "releaseReady"):
                self.assertIs(result[key], False)


if __name__ == "__main__":
    unittest.main()
