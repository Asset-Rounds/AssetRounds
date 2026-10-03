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
    def test_retained_reader_is_one_of_exactly_26_frozen_sources(self):
        self.assertEqual(len(G.SOURCES), 26)
        self.assertEqual(len(set(G.SOURCES)), 26)
        self.assertIn("Scripts/dev/v23-retained-payload.py", G.SOURCES)
        plan, _, _ = fixture()
        for change in ("missing", "extra", "alternate-reader"):
            with self.subTest(change=change):
                changed = copy.deepcopy(plan)
                if change != "extra":
                    changed["sources"].pop("Scripts/dev/v23-retained-payload.py")
                if change != "missing":
                    changed["sources"]["Scripts/dev/caller-chosen-reader.py"] = "A" * 64
                with self.assertRaises(G.Refused):
                    G.validate_plan(changed)

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


def cold_fixture():
    """Synthetic cold DEVELOPMENT intent; these bytes grant no qualification."""
    sources = {path: "A" * 64 for path in G.SOURCES}
    sources.update(G.POLICIES)
    selected = G.canonical({"tier": "D40P", "runUISmoke": False,
        "unitTestSelectors": ["Tests/Example/testOne", "Tests/Example/testTwo"], "uiTestSelectors": [],
        "sharedCoverage": {"partitionsPath": G.PARTITIONS, "partitionsSHA256": sources[G.PARTITIONS],
                           "partitionIDs": ["S01", "S02"], "partitionID": None,
                           "developmentOnly": True, "acceptance": False}})
    value = G.make_cold_plan(head=HEAD, tree=TREE, resolved_bytes=selected,
                             sources=sources, requested_at=STAMP)
    return value, selected, sources


class ColdDevelopmentPlanContractTests(unittest.TestCase):
    """Paired cold/gate admission, with no genuine run or review fixtures."""

    def test_cold_identity_is_closed_development_and_never_a_gate_projection(self):
        cold, _, _ = cold_fixture()
        candidate, _, _ = fixture()
        exact_main, _, _ = fixture(G.EXACT_MAIN)
        self.assertEqual((cold["schema"], cold["purpose"], cold["selection"], cold["kind"]),
                         (G.COLD_SCHEMA, G.COLD_PURPOSE, G.COLD_SELECTION, "development"))
        self.assertEqual(cold["classification"]["functionalQualification"], "PENDING")
        self.assertEqual(cold["classification"]["status"], "INCOMPLETE")
        self.assertIs(cold["classification"]["developmentOnly"], True)
        for key in ("acceptance", "providerQualification", "releaseReady",
                    "countsAsPerKindProtectionSuccess"):
            self.assertIs(cold["classification"][key], False)
        self.assertEqual(G.parse_cold_plan(G.canonical(cold)), cold)
        for value in (candidate, exact_main):
            with self.subTest(schema=value["schema"]), self.assertRaises(G.Refused):
                G.validate_cold_plan(value)
        with self.assertRaises(G.Refused):
            G.validate_plan(cold)
        for gate_plan in (candidate, exact_main):
            self.assertEqual(G.parse_plan(G.canonical(gate_plan)), gate_plan)
            with self.assertRaisesRegex(G.Refused, "dispatch disabled"):
                G.refuse_dispatch()

    def test_every_cold_field_is_required_and_arbitrary_authority_is_refused(self):
        cold, _, _ = cold_fixture()
        for key in cold:
            changed = copy.deepcopy(cold)
            del changed[key]
            with self.subTest(missing=key), self.assertRaises(G.Refused):
                G.validate_cold_plan(changed)
        variants = {"schema": G.SCHEMA, "purpose": G.CANDIDATE, "selection": G.SHARED,
                    "kind": "gate", "ref": "refs/heads/main", "approved": True,
                    "dispatchEnabled": True, "head": G.BASE_MAIN}
        for key, value in variants.items():
            with self.subTest(key=key), self.assertRaises(G.Refused):
                G.validate_cold_plan(dict(cold, **{key: value}))
        for key, value in (("functionalQualification", "QUALIFIED"), ("status", "COMPLETE"),
                           ("developmentOnly", 1), ("providerQualification", 0),
                           ("acceptance", True), ("releaseReady", True)):
            changed = copy.deepcopy(cold)
            changed["classification"][key] = value
            with self.subTest(classification=key), self.assertRaises(G.Refused):
                G.validate_cold_plan(changed)
        for raw in (G.canonical(cold).replace(b'"kind":', b'"kind":"gate","kind":'),
                    b" " + G.canonical(cold), G.canonical(cold).rstrip(), b"[]\n", b"\xff",
                    b"x" * (G.MAX_PLAN_BYTES + 1)):
            with self.subTest(raw=raw[:80]), self.assertRaises(G.Refused):
                G.parse_cold_plan(raw)

    def test_cold_builder_does_not_accept_a_gate_or_free_question(self):
        _, selected, sources = cold_fixture()
        kwargs = dict(head=HEAD, tree=TREE, resolved_bytes=selected, sources=sources, requested_at=STAMP)
        for changed in ({"purpose": G.CANDIDATE}, {"purpose": G.EXACT_MAIN},
                        {"purpose": "retry"}, {"selection": G.SHARED}, {"selection": G.RUI1}):
            with self.subTest(changed=changed), self.assertRaises(G.Refused):
                G.make_cold_plan(**dict(kwargs, **changed))


class ColdOriginalEventContractTests(unittest.TestCase):
    """Real event input is necessary; environment labels never create intent."""

    def fixture(self):
        cold, selected, sources = cold_fixture()
        event = {"repository": {"full_name": G.REPOSITORY}, "ref": cold["ref"],
                 "inputs": G.cold_dispatch_inputs(cold)}
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": G.REPOSITORY,
                       "GITHUB_REF": cold["ref"], "GITHUB_SHA": HEAD, "GITHUB_RUN_ID": "123",
                       "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKFLOW_SHA": HEAD,
                       "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + cold["ref"]}
        facts = dict(head=HEAD, tree=TREE, resolved_bytes=selected, sources=sources)
        api = {"id": 123, "head_sha": HEAD, "head_branch": cold["ref"].removeprefix("refs/heads/"),
               "event": "workflow_dispatch", "path": G.ROUTE["workflow"], "run_attempt": 1}
        return cold, event, environment, facts, api

    def test_authentic_cold_event_binds_original_bytes_pending_only(self):
        cold, event, environment, facts, api = self.fixture()
        raw = json.dumps(event, indent=2).encode()
        binding = G.bind_cold_original_event(raw, environment, **facts)
        self.assertEqual(binding["schema"], G.COLD_EVENT_SCHEMA)
        result = G.verify_cold_collected_event(binding, registered_plan_bytes=G.canonical(cold),
            original_event_bytes=raw, api_run=api, **{key: value for key, value in facts.items() if key != "head"})
        self.assertEqual(result["originalEventSHA256"], G.sha(raw))
        self.assertEqual(result["kind"], "development")
        self.assertEqual(result["functionalQualification"], "PENDING")
        for key in ("acceptance", "providerQualification", "releaseReady"):
            self.assertIs(result[key], False)

    def test_simultaneous_gate_intent_and_cold_gate_masquerade_refuse(self):
        cold, event, environment, facts, _ = self.fixture()
        gate_plan, _, _ = fixture()
        simultaneous = copy.deepcopy(event)
        simultaneous["inputs"][G.PLAN_INPUT] = G.canonical(gate_plan).decode()
        for changed in (simultaneous,
                        dict(event, inputs=dict(event["inputs"], v23_run_kind="gate")),
                        dict(event, inputs=dict(event["inputs"], native_selection_id=G.SHARED)),
                        dict(event, inputs=dict(event["inputs"], run_ui_smoke="true")),
                        dict(event, inputs=dict(event["inputs"], **{G.COLD_PLAN_INPUT: G.canonical(gate_plan).decode()}))):
            with self.subTest(inputs=changed["inputs"].keys()), self.assertRaises(G.Refused):
                G.bind_cold_original_event(G.canonical(changed), environment, **facts)
        self.assertEqual(G.parse_cold_plan(G.canonical(cold)), cold)

    def test_authenticated_run_workflow_tree_source_and_order_cannot_be_substituted(self):
        _, event, environment, facts, _ = self.fixture()
        raw = G.canonical(event)
        reordered = json.loads(facts["resolved_bytes"])
        reordered["unitTestSelectors"].reverse()
        for key in environment:
            with self.subTest(environment=key), self.assertRaises(G.Refused):
                G.bind_cold_original_event(raw, dict(environment, **{key: "foreign"}), **facts)
        for key, value in (("head", "9" * 40), ("tree", "9" * 40),
                ("sources", dict(facts["sources"], **{G.COLLECTOR: "B" * 64})),
                ("resolved_bytes", G.canonical(reordered))):
            with self.subTest(fact=key), self.assertRaises(G.Refused):
                G.bind_cold_original_event(raw, environment, **dict(facts, **{key: value}))

    def test_collector_rechecks_api_attempt_original_bytes_and_closed_binding(self):
        cold, event, environment, facts, api = self.fixture()
        raw = G.canonical(event)
        binding = G.bind_cold_original_event(raw, environment, **facts)
        arguments = dict(registered_plan_bytes=G.canonical(cold), original_event_bytes=raw,
                         api_run=api, **{key: value for key, value in facts.items() if key != "head"})
        for key, value in (("id", 124), ("id", True), ("run_attempt", 2), ("run_attempt", True),
                           ("head_sha", "9" * 40), ("head_branch", "main"),
                           ("event", "push"), ("path", "different.yml")):
            with self.subTest(api=key), self.assertRaises(G.Refused):
                G.verify_cold_collected_event(binding, **dict(arguments, api_run=dict(api, **{key: value})))
        for key, value in (("kind", "gate"), ("purpose", G.CANDIDATE), ("selection", G.SHARED),
                           ("functionalQualification", "QUALIFIED"), ("unknown", "field")):
            with self.subTest(binding=key), self.assertRaises(G.Refused):
                G.verify_cold_collected_event(dict(binding, **{key: value}), **arguments)
        for key in ("registered_plan_bytes", "original_event_bytes"):
            with self.subTest(bytes=key), self.assertRaises(G.Refused):
                G.verify_cold_collected_event(binding, **dict(arguments, **{key: arguments[key] + b" "}))


class ColdAttemptContractTests(unittest.TestCase):
    """Synthetic reserved original, paired with the unchanged gate contract."""

    def fixture(self):
        cold, _, _ = cold_fixture()
        registration = G.canonical({"schema": G.COLD_REGISTRATION_SCHEMA, "plan": cold,
            "planSHA256": G.sha(G.canonical(cold)), "dispatchEnabled": False, "functionalQualification": "PENDING"})
        observations = {"repository": {"id": 7, "full_name": G.REPOSITORY},
            "workflow": {"id": 9, "path": G.ROUTE["workflow"], "state": "active"},
            "refs": {"integration": {"ref": G.INTEGRATION_REF, "object": {"type": "commit", "sha": HEAD}},
                     "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": G.BASE_MAIN}}},
            "headRuns": {"total_count": 0, "workflow_runs": []},
            "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in G.ACTIVE_RUN_STATUSES}}
        attempt = G.make_cold_attempt(cold, registration, collector_id="a" * 32, requested_at=STAMP,
            observations=observations, ledger_bytes="", attempt_names=[])
        return cold, registration, attempt

    def with_active(self, attempt, count=1):
        changed = copy.deepcopy(attempt)
        rows = [{"id": index + 20, "head_sha": "9" * 40, "status": "queued", "run_attempt": 1,
                 "path": G.ROUTE["workflow"], "event": "workflow_dispatch"} for index in range(count)]
        changed["observations"]["activeRuns"]["queued"] = {"total_count": count, "workflow_runs": rows}
        changed["ledgerBytes"] = "".join(G.canonical({"runID": row["id"], "head": row["head_sha"],
            "selection": G.SHARED, "kind": "development"}).decode() for row in rows)
        return changed

    def test_closed_cold_attempt_carries_exact_request_and_never_admits_gate_attempt(self):
        cold, registration, attempt = self.fixture()
        self.assertEqual(G.validate_cold_attempt(attempt, cold, registration), attempt)
        self.assertEqual(attempt["schema"], G.COLD_ATTEMPT_SCHEMA)
        self.assertEqual(json.loads(attempt["inputBytes"])[G.PLAN_INPUT], "")
        self.assertEqual(json.loads(attempt["inputBytes"])[G.COLD_PLAN_INPUT], G.canonical(cold).decode())
        for key in attempt:
            changed = copy.deepcopy(attempt); del changed[key]
            with self.subTest(missing=key), self.assertRaises(G.Refused):
                G.validate_cold_attempt(changed, cold, registration)
        for key, value in (("schema", G.ATTEMPT_SCHEMA), ("collectorID", "invented"),
                           ("workflowID", True), ("repositoryID", True), ("inputBytes", "{}\n"),
                           ("argv", ["gh", "run", "rerun", "9"]), ("collectorSHA256", "B" * 64),
                           ("registrationSHA256", "B" * 64), ("mainHead", HEAD),
                           ("planBytes", G.canonical(dict(cold, kind="gate")).decode())):
            with self.subTest(field=key), self.assertRaises(G.Refused):
                G.validate_cold_attempt(dict(attempt, **{key: value}), cold, registration)
        gate_plan, gate_registration, gate_attempt = AttemptContractTests.fixture(self)
        self.assertEqual(G.validate_attempt(gate_attempt, gate_plan, gate_registration), gate_attempt)
        with self.assertRaises(G.Refused):
            G.validate_cold_attempt(gate_attempt, cold, registration)

    def test_shared_capacity_allows_four_other_head_development_runs_and_refuses_five(self):
        cold, registration, attempt = self.fixture()
        four = self.with_active(attempt, 4)
        self.assertEqual(G.validate_cold_attempt(four, cold, registration), four)
        with self.assertRaises(G.Refused):
            G.validate_cold_attempt(self.with_active(attempt, 5), cold, registration)

    def test_active_gate_unmarked_unknown_same_head_second_attempt_and_duplicate_refuse(self):
        cold, registration, attempt = self.fixture()
        for variant in ("gate", "unmarked", "unknown", "same-head", "attempt", "phase1", "duplicate", "workflow"):
            changed = self.with_active(attempt)
            row = changed["observations"]["activeRuns"]["queued"]["workflow_runs"][0]
            record = json.loads(changed["ledgerBytes"])
            if variant == "gate": record["kind"] = "gate"
            if variant == "unmarked": del record["kind"]
            if variant == "unknown": record["runID"] += 1
            if variant == "same-head": row["head_sha"] = record["head"] = HEAD
            if variant == "attempt": row["run_attempt"] = 2
            if variant == "phase1": record["phase1Purpose"] = G.CANDIDATE
            if variant == "workflow": row["path"] = "foreign.yml"
            if variant == "duplicate":
                changed["observations"]["activeRuns"]["in_progress"] = {
                    "total_count": 1, "workflow_runs": [dict(row, status="in_progress")]}
            changed["ledgerBytes"] = G.canonical(record).decode()
            with self.subTest(variant=variant), self.assertRaises(G.Refused):
                G.validate_cold_attempt(changed, cold, registration)

    def test_consumed_and_partial_cold_attempt_names_never_create_another_original(self):
        cold, registration, attempt = self.fixture()
        for name in (G.cold_original_stem(cold) + ".json", G.cold_original_stem(cold) + ".partial",
                     HEAD + "-" + G.COLD_SELECTION + ".json", "../" + G.cold_original_stem(cold) + ".json"):
            with self.subTest(name=name), self.assertRaises(G.Refused):
                G.validate_cold_attempt(dict(attempt, attemptNames=[name]), cold, registration)
        for record in ({"runID": 123, "head": HEAD, "selection": G.COLD_SELECTION, "kind": "development"},
                       {"runID": 123, "head": HEAD, "selection": G.SHARED, "kind": "development", "coldPurpose": G.COLD_PURPOSE}):
            with self.subTest(record=record), self.assertRaises(G.Refused):
                G.validate_cold_attempt(dict(attempt, ledgerBytes=G.canonical(record).decode()), cold, registration)

    def test_every_cold_requested_input_is_bound_including_empty_gate_and_false_experiments(self):
        cold, _, attempt = self.fixture()
        event = {"inputs": G.cold_dispatch_inputs(cold), "ref": cold["ref"],
                 "repository": {"full_name": G.REPOSITORY}}
        raw = json.dumps(event, indent=2).encode()
        self.assertEqual(G.verify_cold_attempt_inputs(attempt, raw)["inputSHA256"], G.sha(attempt["inputBytes"].encode()))
        for key in event["inputs"]:
            for mode in ("replace", "remove"):
                altered = copy.deepcopy(event)
                if mode == "replace": altered["inputs"][key] = "substituted"
                else: del altered["inputs"][key]
                with self.subTest(key=key, mode=mode), self.assertRaises(G.Refused):
                    G.verify_cold_attempt_inputs(attempt, json.dumps(altered).encode())
        altered = copy.deepcopy(event); altered["inputs"]["unrequested"] = "true"
        with self.assertRaises(G.Refused):
            G.verify_cold_attempt_inputs(attempt, G.canonical(altered))

    def test_cold_registration_is_immutable_and_retains_pending_only(self):
        cold, _, _ = self.fixture()
        with tempfile.TemporaryDirectory() as temporary:
            target, record = G.register_cold(cold, Path(temporary).resolve())
            original = target.read_bytes()
            self.assertEqual(record["schema"], G.COLD_REGISTRATION_SCHEMA)
            self.assertIs(record["dispatchEnabled"], False)
            self.assertEqual(record["functionalQualification"], "PENDING")
            with self.assertRaises(FileExistsError):
                G.register_cold(cold, Path(temporary).resolve())
            self.assertEqual(target.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
