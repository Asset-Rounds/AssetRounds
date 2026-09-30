"""Synthetic contract tests only. No genuine approval, native result or dispatch."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


def load():
    path = Path(__file__).with_name("v23-phase1-gates.py")
    spec = importlib.util.spec_from_file_location("phase1_contract_test_target", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = load()
HEAD, TREE = "1" * 40, "2" * 40
STAMP = "2026-09-26T12:00:00Z"


def fixture(purpose=G.CANDIDATE, selection=G.SHARED):
    """Invented identities for tests, never approval or evidence records."""
    sources = {path: "A" * 64 for path in G.SOURCES}
    sources.update(G.POLICIES)
    selected = G.canonical({"unitTestSelectors": ["Tests/Example/testOne"], "uiTestSelectors": []})
    plan = G.make_plan(purpose=purpose, head=HEAD, tree=TREE, selection=selection,
                       resolved_bytes=selected, sources=sources, requested_at=STAMP)
    return plan, selected, sources


class PlanContractTests(unittest.TestCase):
    def test_closed_questions_differ_on_same_sha(self):
        candidate, _, _ = fixture()
        main, _, _ = fixture(G.EXACT_MAIN)
        self.assertNotEqual(G.original_key(candidate), G.original_key(main))
        self.assertEqual(candidate["head"], main["head"])
        for plan in (candidate, main):
            self.assertEqual(G.parse_plan(G.canonical(plan)), plan)
            self.assertEqual(plan["classification"], G.CLASSIFICATION)

    def test_plan_is_small_even_for_full_coverage(self):
        plan, _, sources = fixture()
        selected = G.canonical({"unitTestSelectors": [f"Tests/Class/test{x}" for x in range(4000)],
                                "uiTestSelectors": []})
        full = G.make_plan(purpose=G.CANDIDATE, head=HEAD, tree=TREE, selection=G.SHARED,
                           resolved_bytes=selected, sources=sources, requested_at=STAMP)
        self.assertLess(len(G.canonical(full)), G.MAX_PLAN_BYTES)
        self.assertNotEqual(plan["orderedUnitMethodsSHA256"], full["orderedUnitMethodsSHA256"])

    def test_refuses_arbitrary_purpose_ref_selection_and_head(self):
        plan, _, _ = fixture()
        for field, values in {"purpose": ["retry", "phase2", [], None],
                              "ref": ["main", "refs/heads/main", "refs/tags/x"],
                              "selection": ["v23-dev-batch-no-index-d50", "smoke", {}],
                              "head": [G.BASE_MAIN, "A" * 40, "abc", 12],
                              "baseMain": ["0" * 40], "tree": ["abc"]}.items():
            for value in values:
                with self.subTest(field=field, value=value):
                    changed = copy.deepcopy(plan)
                    changed[field] = value
                    with self.assertRaises(G.Refused):
                        G.validate_plan(changed)

    def test_unknown_missing_fields_and_json_forms_fail_closed(self):
        plan, _, _ = fixture()
        for key in plan:
            changed = copy.deepcopy(plan)
            del changed[key]
            with self.subTest(missing=key), self.assertRaises(G.Refused):
                G.validate_plan(changed)
        for raw in (G.canonical(plan).replace(b'"schema":', b'"schema":"duplicate","schema":'),
                    b" " + G.canonical(plan), G.canonical(plan).rstrip(), b"{}\n",
                    b'{"nan":NaN}\n', b"\xff", b"x" * (G.MAX_PLAN_BYTES + 1)):
            with self.assertRaises(G.Refused):
                G.parse_plan(raw)
        plan["approved"] = True
        with self.assertRaises(G.Refused):
            G.validate_plan(plan)

    def test_false_success_and_bool_integer_alias_are_rejected(self):
        plan, _, _ = fixture()
        for section, key, value in (("classification", "functionalQualification", "QUALIFIED"),
                ("classification", "releaseReady", True), ("classification", "acceptance", 0),
                ("classification", "physicalProtectionReleaseBlocker", 1),
                ("classification", "simulatorProtection", "PROVEN"),
                ("route", "runAttempt", True), ("route", "runtimeBuild", "23F77"),
                ("route", "configuration", "Release"), ("route", "provider", "bitrise")):
            with self.subTest(section=section, key=key):
                changed = copy.deepcopy(plan)
                changed[section][key] = value
                with self.assertRaises(G.Refused):
                    G.validate_plan(changed)

    def test_policy_source_collector_budget_and_time_tampering(self):
        plan, _, _ = fixture()
        variants = []
        for field in ("sources", "policies"):
            changed = copy.deepcopy(plan)
            changed[field][G.DECISION] = "B" * 64
            variants.append(changed)
        changed = copy.deepcopy(plan)
        changed["sources"]["../../other.py"] = "A" * 64
        variants.append(changed)
        changed = copy.deepcopy(plan)
        changed["collector"]["sha256"] = "B" * 64
        variants.append(changed)
        changed = copy.deepcopy(plan)
        changed["route"]["budgets"]["RUI1"][0] += 1
        variants.append(changed)
        for timestamp in ("2026-09-31T12:00:00Z", "2026-09-26T12:00:00-07:00", "yesterday"):
            changed = copy.deepcopy(plan)
            changed["requestedAtUTC"] = timestamp
            variants.append(changed)
        for changed in variants:
            with self.assertRaises(G.Refused):
                G.validate_plan(changed)

    def test_facts_recomputed_from_source_and_ref(self):
        plan, selected, sources = fixture()
        facts = dict(head=HEAD, tree=TREE, integration_head=HEAD, main_head=G.BASE_MAIN,
                     resolved_bytes=selected, sources=sources)
        G.bind_facts(plan, **facts)
        for key in ("head", "tree", "integration_head", "main_head"):
            changed = dict(facts, **{key: "9" * 40})
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.bind_facts(plan, **changed)
        changed = dict(facts, sources=dict(sources, **{G.COLLECTOR: "B" * 64}))
        with self.assertRaises(G.Refused):
            G.bind_facts(plan, **changed)
        changed = dict(facts, resolved_bytes=G.canonical({"unitTestSelectors": [], "uiTestSelectors": []}))
        with self.assertRaises(G.Refused):
            G.bind_facts(plan, **changed)


class OriginalAndRegistrationTests(unittest.TestCase):
    def test_legacy_unmarked_development_retry_and_free_purpose_block(self):
        candidate, _, _ = fixture()
        main, _, _ = fixture(G.EXACT_MAIN)
        for requested in (candidate, main):
            for extras in ({}, {"kind": "development"}, {"kind": "gate"},
                           {"kind": "development", "infraRetryOf": 12},
                           {"kind": "gate", "phase1Purpose": "another-purpose"},
                           {"kind": "gate", "phase1Purpose": G.CANDIDATE}):
                record = {"head": HEAD, "selection": G.SHARED, "runID": 123, **extras}
                with self.subTest(requested=requested["purpose"], extras=extras):
                    self.assertTrue(G.conflicting_originals(requested, [record], []))

    def test_distinct_keys_require_bound_candidate_and_never_authorize_dispatch(self):
        candidate, _, _ = fixture()
        main, _, _ = fixture(G.EXACT_MAIN)
        record = {"head": HEAD, "selection": G.SHARED, "runID": 123, "kind": "gate",
                  "phase1Purpose": G.CANDIDATE, "phase1PlanBytes": G.canonical(candidate).decode(),
                  "phase1PlanSHA256": G.sha(G.canonical(candidate)),
                  "phase1RegistrationSchema": G.REGISTRATION_SCHEMA}
        attempt = G.original_stem(candidate) + ".json"
        self.assertEqual(G.conflicting_originals(main, [record], [attempt]), [])
        self.assertTrue(G.conflicting_originals(candidate, [record], [attempt]))
        self.assertTrue(G.conflicting_originals(main, [record, record], [attempt]))
        self.assertTrue(G.conflicting_originals(main, [], [attempt]))
        record["phase1PlanSHA256"] = "F" * 64
        self.assertTrue(G.conflicting_originals(main, [record], [attempt]))
        with self.assertRaisesRegex(G.Refused, "dispatch disabled"):
            G.refuse_dispatch()

    def test_ambiguous_attempts_are_not_retryable(self):
        plan, _, _ = fixture()
        for name in (HEAD + "-" + G.SHARED + ".json",
                     HEAD + "-" + G.SHARED + ".infra-retry.json",
                     G.original_stem(plan) + ".json", G.original_stem(plan) + ".partial",
                     HEAD + "-unknown-" + G.SHARED + ".json"):
            with self.subTest(name=name):
                self.assertTrue(G.conflicting_originals(plan, [], [name]))
        self.assertEqual(G.conflicting_originals(plan, [{"event": "cancel-intent"}], []), [])

    def test_registration_is_exclusive_pending_only_and_exact_main_closed(self):
        plan, _, _ = fixture()
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "plans"
            target, record = G.register_candidate(plan, directory)
            self.assertEqual(target.read_bytes(), G.canonical(record))
            self.assertFalse(record["dispatchEnabled"])
            self.assertEqual(record["functionalQualification"], G.PENDING)
            before = target.read_bytes()
            with self.assertRaisesRegex(G.Refused, "already exists"):
                G.register_candidate(plan, directory)
            self.assertEqual(target.read_bytes(), before)
            main, _, _ = fixture(G.EXACT_MAIN)
            with self.assertRaisesRegex(G.Refused, "prerequisites"):
                G.register_candidate(main, directory)

    def test_unsafe_and_oversized_files_refused(self):
        plan, _, _ = fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            file = root / "plan.json"
            file.write_bytes(G.canonical(plan))
            link = root / "link"
            link.symlink_to(file)
            with self.assertRaisesRegex(G.Refused, "symlink"):
                G.regular_bytes(link)
            with self.assertRaisesRegex(G.Refused, "bounded"):
                G.regular_bytes(file, limit=5)
            directory_link = root / "directory-link"
            directory_link.symlink_to(root, target_is_directory=True)
            with self.assertRaisesRegex(G.Refused, "symlink"):
                G.register_candidate(plan, directory_link)


class OriginalEventBindingTests(unittest.TestCase):
    def event_fixture(self, purpose=G.CANDIDATE, selection=G.SHARED):
        plan, selected, sources = fixture(purpose, selection)
        event = {"repository": {"full_name": G.REPOSITORY}, "ref": plan["ref"],
                 "inputs": {G.PLAN_INPUT: G.canonical(plan).decode(), "v23_run_kind": "gate",
                            "native_selection_id": selection, "execution_lane": G.ROUTE["executionLane"],
                            "run_ui_smoke": "true" if selection == G.RUI1 else "false"}}
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": G.REPOSITORY,
                       "GITHUB_REF": plan["ref"], "GITHUB_SHA": HEAD, "GITHUB_RUN_ID": "123",
                       "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKFLOW_SHA": HEAD,
                       "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + plan["ref"]}
        facts = dict(head=HEAD, tree=TREE, resolved_bytes=selected, sources=sources)
        api = {"id": 123, "head_sha": HEAD, "head_branch": plan["ref"].removeprefix("refs/heads/"),
               "event": "workflow_dispatch", "path": G.ROUTE["workflow"], "run_attempt": 1}
        return plan, event, environment, facts, api

    def test_candidate_main_and_both_selections_bind_authentic_context_pending_only(self):
        for purpose in (G.CANDIDATE, G.EXACT_MAIN):
            for selection in G.SELECTIONS:
                with self.subTest(purpose=purpose, selection=selection):
                    plan, event, e, facts, api = self.event_fixture(purpose, selection)
                    raw = json.dumps(event, indent=2).encode()
                    binding = G.bind_original_event(raw, e, **facts)
                    result = G.verify_collected_event(binding, registered_plan_bytes=G.canonical(plan),
                        original_event_bytes=raw, api_run=api, **{k: v for k, v in facts.items() if k != "head"})
                    self.assertEqual(result["functionalQualification"], G.PENDING)
                    self.assertEqual(result["originalEventSHA256"], G.sha(raw))

    def test_absent_empty_plan_keeps_legacy_route_but_malformed_input_does_not(self):
        for event in ({}, {"inputs": {}}, {"inputs": {G.PLAN_INPUT: "", "v23_run_kind": "development"}}):
            self.assertIsNone(G.bind_original_event(G.canonical(event), {}, head="", tree="",
                                                    resolved_bytes=b"", sources={}))
        for raw in (b'{"inputs":{},"inputs":{}}', b"[]", b"null", b"x" * (G.MAX_EVENT_BYTES + 1),
                    G.canonical({"inputs": None}), G.canonical({"inputs": {G.PLAN_INPUT: None}}),
                    G.canonical({"inputs": {G.PLAN_INPUT: "{}"}})):
            with self.subTest(raw=raw[:80]), self.assertRaises(G.Refused):
                G.plan_from_event(raw)

    def test_wrong_authenticated_identity_and_input_cannot_bind(self):
        plan, event, e, facts, _ = self.event_fixture()
        for key in e:
            changed = dict(e, **{key: "foreign"})
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.bind_original_event(G.canonical(event), changed, **facts)
        for key, value in (("v23_run_kind", "development"), ("native_selection_id", G.RUI1),
                           ("run_ui_smoke", "true"), ("execution_lane", "bitrise")):
            changed = copy.deepcopy(event)
            changed["inputs"][key] = value
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.bind_original_event(G.canonical(changed), e, **facts)
        for key, value in (("repository", {"full_name": "foreign/repo"}), ("ref", "refs/heads/main")):
            changed = dict(event, **{key: value})
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.bind_original_event(G.canonical(changed), e, **facts)

    def test_original_event_source_selection_policy_and_order_are_bound(self):
        _, event, e, facts, _ = self.event_fixture()
        raw = G.canonical(event)
        for key, value in (("head", "9" * 40), ("tree", "9" * 40),
                           ("resolved_bytes", G.canonical({"unitTestSelectors": [], "uiTestSelectors": []})),
                           ("sources", dict(facts["sources"], **{"Scripts/s10-4-build-payload.py": "B" * 64}))):
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.bind_original_event(raw, e, **dict(facts, **{key: value}))

    def test_collector_requires_registered_plan_original_bytes_api_and_complete_binding(self):
        plan, event, e, facts, api = self.event_fixture()
        raw = G.canonical(event)
        binding = G.bind_original_event(raw, e, **facts)
        arguments = dict(registered_plan_bytes=G.canonical(plan), original_event_bytes=raw, api_run=api,
                         **{k: v for k, v in facts.items() if k != "head"})
        for key, value in (("id", 124), ("id", True), ("run_attempt", 2), ("run_attempt", True),
                           ("head_sha", "9" * 40), ("head_branch", "main"), ("event", "push"),
                           ("path", "different.yml")):
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.verify_collected_event(binding, **dict(arguments, api_run=dict(api, **{key: value})))
        for key, value in (("tree", "9" * 40), ("kind", "development"), ("repository", "foreign"),
                           ("selection", G.RUI1), ("functionalQualification", "QUALIFIED"),
                           ("unknown", "field"), ("workflowSHA", "9" * 40)):
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.verify_collected_event(dict(binding, **{key: value}), **arguments)
        for key in ("registered_plan_bytes", "original_event_bytes"):
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.verify_collected_event(binding, **dict(arguments, **{key: arguments[key] + b" "}))

    def test_valid_plan_for_another_head_is_not_a_registered_plan(self):
        plan, event, e, facts, api = self.event_fixture()
        raw = G.canonical(event)
        binding = G.bind_original_event(raw, e, **facts)
        other = dict(plan, head="9" * 40)
        with self.assertRaisesRegex(G.Refused, "registered plan"):
            G.verify_collected_event(binding, registered_plan_bytes=G.canonical(other),
                original_event_bytes=raw, api_run=api, **{k: v for k, v in facts.items() if k != "head"})


class AttemptContractTests(unittest.TestCase):
    """Invented protocol identities only; no real human or request authority."""

    def fixture(self):
        plan, _, _ = fixture()
        registration = G.canonical({"schema": G.REGISTRATION_SCHEMA, "plan": plan,
            "planSHA256": G.sha(G.canonical(plan)), "dispatchEnabled": False, "functionalQualification": G.PENDING})
        observations = {"repository": {"id": 7, "full_name": G.REPOSITORY},
            "workflow": {"id": 9, "path": G.ROUTE["workflow"], "state": "active"},
            "refs": {"integration": {"ref": G.INTEGRATION_REF, "object": {"type": "commit", "sha": HEAD}},
                     "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": G.BASE_MAIN}}},
            "headRuns": {"total_count": 0, "workflow_runs": []},
            "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in G.ACTIVE_RUN_STATUSES}}
        attempt = G.make_attempt(plan, registration, collector_id="a"*32, requested_at=STAMP,
            observations=observations, ledger_bytes="", attempt_names=[])
        return plan, registration, attempt

    def test_attempt_v2_binds_exact_input_command_and_every_closed_fact(self):
        plan, raw, attempt = self.fixture()
        self.assertEqual(G.validate_attempt(G.decode(G.canonical(attempt), limit=G.MAX_ATTEMPT_BYTES), plan, raw), attempt)
        self.assertEqual(json.loads(attempt["inputBytes"])[G.PLAN_INPUT], G.canonical(plan).decode())
        self.assertEqual(attempt["argv"], ["gh", "workflow", "run", "9", "--repo", G.REPOSITORY,
            "--ref", G.INTEGRATION_REF.removeprefix("refs/heads/"), "--json"])
        for key in attempt:
            with self.subTest(key=key):
                value = copy.deepcopy(attempt); del value[key]
                with self.assertRaises(G.Refused): G.validate_attempt(value, plan, raw)
        for key, value in (("schema", "v23-phase1-original-attempt.v1"), ("collectorID", "invented"),
                           ("workflowID", True), ("repositoryID", True), ("inputBytes", "{}\n"),
                           ("argv", ["gh", "run", "rerun", "9"]), ("collectorSHA256", "B"*64),
                           ("registrationSHA256", "B"*64), ("knownRunIDs", [1]),
                           ("planBytes", G.canonical(dict(plan, tree="3"*40)).decode())):
            with self.subTest(key=key, value=value):
                changed = copy.deepcopy(attempt); changed[key] = value
                with self.assertRaises(G.Refused): G.validate_attempt(changed, plan, raw)

    def test_attempt_refuses_legacy_collisions_unknown_runs_and_moved_or_active_observations(self):
        plan, raw, attempt = self.fixture()
        for variant in ("legacy", "attempt", "unknown", "wrong-ledger-head", "duplicate-ids", "main", "active", "repository", "workflow"):
            with self.subTest(variant=variant):
                changed = copy.deepcopy(attempt); observations = changed["observations"]
                if variant == "legacy": changed["ledgerBytes"] = G.canonical({"runID": 1, "head": HEAD, "selection": plan["selection"], "kind": "development"}).decode()
                if variant == "attempt": changed["attemptNames"] = [HEAD + "-" + plan["selection"] + ".json"]
                if variant in ("unknown", "wrong-ledger-head", "duplicate-ids"):
                    rows = [{"id": 1, "head_sha": HEAD}]
                    if variant == "duplicate-ids": rows *= 2
                    observations["headRuns"] = {"total_count": len(rows), "workflow_runs": rows}
                    changed["knownRunIDs"] = [1]
                    if variant == "wrong-ledger-head": changed["ledgerBytes"] = G.canonical({"runID": 1, "head": "f"*40}).decode()
                if variant == "main": observations["refs"]["main"]["object"]["sha"] = HEAD
                if variant == "active": observations["activeRuns"]["queued"] = {"total_count": 1, "workflow_runs": [{"id": 1}]}
                if variant == "repository": observations["repository"]["full_name"] = "other/repo"
                if variant == "workflow": observations["workflow"]["state"] = "disabled_manually"
                with self.assertRaises(G.Refused): G.validate_attempt(changed, plan, raw)

    def test_every_original_event_input_must_equal_exact_consumed_request(self):
        plan, _, attempt = self.fixture()
        event = {"inputs": G.dispatch_inputs(plan), "ref": plan["ref"], "repository": {"full_name": G.REPOSITORY}}
        raw = json.dumps(event, indent=2).encode()
        self.assertEqual(G.verify_attempt_inputs(attempt, raw)["inputSHA256"], G.sha(attempt["inputBytes"].encode()))
        for key in event["inputs"]:
            with self.subTest(key=key):
                altered = copy.deepcopy(event); altered["inputs"][key] = "substituted"
                with self.assertRaises(G.Refused): G.verify_attempt_inputs(attempt, json.dumps(altered).encode())
        altered = copy.deepcopy(event); altered["inputs"]["unrequested"] = "true"
        with self.assertRaises(G.Refused): G.verify_attempt_inputs(attempt, json.dumps(altered).encode())
        altered = copy.deepcopy(event); del altered["inputs"]["s10_4_shared_payload_run_id"]
        with self.assertRaises(G.Refused): G.verify_attempt_inputs(attempt, json.dumps(altered).encode())

    def test_exclusive_durable_writer_preserves_consumption_and_refuses_links(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); target = root / "consumed.json"
            original_fsync = G.os.fsync
            calls = []
            def fsync(fd):
                calls.append(fd); return original_fsync(fd)
            with mock.patch.object(G.os, "fsync", side_effect=fsync): G.write_immutable(target, b"synthetic consumed\n")
            self.assertGreaterEqual(len(calls), 1)
            with self.assertRaises(FileExistsError): G.write_immutable(target, b"replacement\n")
            self.assertEqual(target.read_bytes(), b"synthetic consumed\n")
            linked = root / "linked.json"; linked.symlink_to(target)
            with self.assertRaises(FileExistsError): G.write_immutable(linked, b"replacement\n")
            partial = root / "partial.json"
            with mock.patch.object(G.os, "fsync", side_effect=OSError("synthetic persistence failure")):
                with self.assertRaises(OSError): G.write_immutable(partial, b"consumed despite uncertainty\n")
            self.assertTrue(partial.exists())
            with self.assertRaises(FileExistsError): G.write_immutable(partial, b"retry forbidden\n")



def synthetic_review_request():
    return {"schema": G.REVIEW_REQUEST_SCHEMA, "testOnly": True, "subject": "shared-cold-original",
            "reportedDisposition": "approve", "head": HEAD, "tree": TREE,
            "originals": [{"runID": 10, "manifestSHA256": "A" * 64}], "gallery": None,
            "messageSHA256": G.sha(b"SYNTHETIC TEST ONLY: approve these fixture bytes.\r\n"),
            "contextSHA256": G.sha(b"SYNTHETIC TEST ONLY context.\n"),
            "messageReference": "test-only:message", "conversationReference": "test-only:task",
            "messageTimestampUTC": STAMP, "speakerReference": "test-only:reviewer",
            "reviewer": {"model": "test-only:model", "effort": "test-only:effort",
                "authorReference": "test-only:author", "independenceReference": "test-only:separate-task"}}


class ReviewProvenanceContractTests(unittest.TestCase):
    def record(self, request=None, **kwargs):
        return G.make_review_record(request or synthetic_review_request(),
            b"SYNTHETIC TEST ONLY: approve these fixture bytes.\r\n", b"SYNTHETIC TEST ONLY context.\n",
            {"originals": []}, index=0, previous=None, captured_at=STAMP, test_only=True, **kwargs)

    def test_verbatim_bytes_and_no_approval_from_reported_disposition(self):
        value = self.record()
        self.assertEqual(value["messageUTF8"].encode(), b"SYNTHETIC TEST ONLY: approve these fixture bytes.\r\n")
        self.assertEqual(value["status"], G.REVIEW_PENDING)
        assessment = G.review_pending_assessment(HEAD, [value])
        self.assertEqual(assessment["functionalQualification"], G.PENDING)
        self.assertFalse(assessment["acceptance"])
        self.assertFalse(assessment["releaseReady"])
        self.assertEqual(assessment["physicalProtection"], "UNVERIFIED/DEFERRED")
        self.assertEqual(len(assessment["missingSubjects"]), 3)

    def test_real_mode_rejects_test_only_and_closed_fields(self):
        request = synthetic_review_request()
        with self.assertRaisesRegex(G.Refused, "test-only"):
            G.validate_review_request(request)
        for key in request:
            bad = copy.deepcopy(request); del bad[key]
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.validate_review_request(bad, test_only=True)
        for key, value in (("approved", True), ("humanAuthenticated", True), ("signature", "invented")):
            bad = dict(request, **{key: value})
            with self.assertRaises(G.Refused): G.validate_review_request(bad, test_only=True)

    def test_reference_calendar_identity_and_subject_hostiles(self):
        request = synthetic_review_request()
        for key, value in (("messageReference", ""), ("conversationReference", " "), ("speakerReference", None),
                ("head", "main"), ("tree", "short"), ("messageTimestampUTC", "2026-02-30T01:01:01Z"),
                ("subject", "exact-main-approval"), ("reportedDisposition", "qualified"),
                ("originals", [{"runID": True, "manifestSHA256": "A" * 64}]), ("reviewer", {"model": "GPT-6 Astra"})):
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.validate_review_request(dict(request, **{key: value}), test_only=True)
        with self.assertRaisesRegex(G.Refused, "bytes"):
            self.record(dict(request, messageSHA256="0" * 64))
        bad = dict(request, messageSHA256=G.sha(b"\xff"))
        with self.assertRaisesRegex(G.Refused, "UTF8"):
            G.make_review_record(bad, b"\xff", b"SYNTHETIC TEST ONLY context.\n", {},
                index=0, previous=None, captured_at=STAMP, test_only=True)

    def test_history_reports_conflicts_and_self_review_without_resolving(self):
        value = self.record()
        other = copy.deepcopy(value)
        other["request"]["reportedDisposition"] = "changes-requested"
        other["request"]["speakerReference"] = other["request"]["reviewer"]["authorReference"]
        result = G.review_pending_assessment(HEAD, [value, other])
        self.assertEqual(len(result["subjects"]["shared-cold-original"]), 2)
        self.assertIn("shared-cold-original", result["unresolvedSubjects"])
        self.assertEqual(len(result["declaredIndependenceGaps"]), 1)
        self.assertEqual(result["functionalQualification"], G.PENDING)

    def test_owner_requires_exact_bundle_and_no_model_reviewer(self):
        request = synthetic_review_request()
        request.update(subject="owner-critical-states", reviewer=None,
            gallery={k: "A" * 64 for k in ("catalogueSHA256", "proofSHA256", "presentationSHA256",
                                        "checklistSHA256", "attachmentsSHA256")})
        G.validate_review_request(request, test_only=True)
        for key in request["gallery"]:
            bad = copy.deepcopy(request); del bad["gallery"][key]
            with self.assertRaises(G.Refused): G.validate_review_request(bad, test_only=True)
        request["reviewer"] = synthetic_review_request()["reviewer"]
        with self.assertRaises(G.Refused): G.validate_review_request(request, test_only=True)


if __name__ == "__main__":
    unittest.main()
