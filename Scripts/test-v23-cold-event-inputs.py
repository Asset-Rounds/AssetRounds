"""Synthetic received-representation v2 behavior; no genuine run or gate credit.

Reason: original 37387803052 reports exactly three omitted declared empty
defaults, extra0 and no changed shared values. Its raw event was not retained.
The real complete request producer and raw event attribution remain separate.
"""
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import unittest
from unittest import mock


def load():
    path = Path(__file__).with_name("v23-phase1-gates.py")
    spec = importlib.util.spec_from_file_location("cold_event_inputs_v2_test_target", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = load()
HEAD, TREE = "1" * 40, "2" * 40
OMITTED = ("s10_4_segment_source_run_ids", "s10_4_shared_payload_run_id", G.PLAN_INPUT)
REFUSAL = "Phase1 gate: closed cold original dispatch inputs"


class ColdEventInputRepresentationV2Tests(unittest.TestCase):
    def fixture(self):
        """The real builder/parser/binders receive explicit invented identities."""
        sources = {path: "A" * 64 for path in G.SOURCES}
        sources.update(G.POLICIES)
        selected = G.canonical({"tier": "D40P", "runUISmoke": False,
            "unitTestSelectors": ["Tests/Example/testOne"], "uiTestSelectors": [],
            "sharedCoverage": {"partitionsPath": G.PARTITIONS,
                "partitionsSHA256": sources[G.PARTITIONS], "partitionIDs": ["S01"],
                "partitionID": None, "developmentOnly": True, "acceptance": False}})
        plan = G.make_cold_plan(head=HEAD, tree=TREE, resolved_bytes=selected,
                               sources=sources, requested_at="2026-09-26T12:00:00Z")
        event = {"repository": {"full_name": G.REPOSITORY}, "ref": plan["ref"],
                 "inputs": G.cold_dispatch_inputs(plan)}
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": G.REPOSITORY,
            "GITHUB_REF": plan["ref"], "GITHUB_SHA": HEAD, "GITHUB_RUN_ID": "123",
            "GITHUB_RUN_ATTEMPT": "1", "GITHUB_WORKFLOW_SHA": HEAD,
            "GITHUB_WORKFLOW_REF": G.REPOSITORY + "/" + G.ROUTE["workflow"] + "@" + plan["ref"]}
        facts = dict(head=HEAD, tree=TREE, resolved_bytes=selected, sources=sources)
        attempt = {"planBytes": G.canonical(plan).decode("utf-8"),
                   "inputBytes": G.canonical(G.cold_dispatch_inputs(plan)).decode("utf-8")}
        api = {"id": 123, "head_sha": HEAD, "head_branch": plan["ref"].removeprefix("refs/heads/"),
               "event": "workflow_dispatch", "path": G.ROUTE["workflow"], "run_attempt": 1}
        return plan, event, environment, facts, attempt, api

    def received(self, event, omitted):
        value = copy.deepcopy(event)
        if omitted:
            for key in OMITTED:
                del value["inputs"][key]
        return value

    def refuse_both(self, event, environment, facts, attempt):
        raw = G.canonical(event)
        with self.assertRaises(G.Refused):
            G.bind_cold_original_event(raw, environment, **facts)
        with self.assertRaises(G.Refused):
            G.verify_cold_attempt_inputs(attempt, raw)

    def test_both_closed_shapes_preserve_complete_request_and_each_original_raw_digest(self):
        plan, event, environment, facts, attempt, api = self.fixture()
        full_request = copy.deepcopy(event["inputs"])
        complete_request_raw = G.canonical(full_request)
        expected_binding = {"schema": G.COLD_EVENT_SCHEMA, "plan": plan,
            "planSHA256": G.sha(G.canonical(plan)), "repository": G.REPOSITORY, "ref": plan["ref"],
            "head": HEAD, "tree": TREE, "workflowRef": environment["GITHUB_WORKFLOW_REF"],
            "workflowSHA": HEAD, "runID": "123", "runAttempt": "1", "kind": "development",
            "selection": G.COLD_SELECTION, "functionalQualification": "PENDING", "status": "INCOMPLETE",
            "developmentOnly": True, "providerQualification": False, "acceptance": False, "releaseReady": False}
        digests = set()
        for omitted in (False, True):
            received = self.received(event, omitted)
            original = copy.deepcopy(received)
            self.assertEqual(len(received["inputs"]), 10 if omitted else 13)
            for raw in (G.canonical(received), json.dumps(received, indent=2).encode("utf-8")):
                with self.subTest(omitted=omitted, digest=G.sha(raw)), mock.patch.object(
                        G, "cold_dispatch_input_difference", side_effect=AssertionError("valid diagnostic call")):
                    binding = G.bind_cold_original_event(raw, environment, **facts)
                    self.assertEqual(binding, dict(expected_binding, originalEventSHA256=G.sha(raw)))
                    self.assertEqual(G.verify_cold_attempt_inputs(attempt, raw),
                        {"originalEventSHA256": G.sha(raw), "inputSHA256": G.sha(complete_request_raw)})
                    collected = G.verify_cold_collected_event(binding, registered_plan_bytes=G.canonical(plan),
                        original_event_bytes=raw, api_run=api,
                        **{key: value for key, value in facts.items() if key != "head"})
                    self.assertEqual(collected["originalEventSHA256"], G.sha(raw))
                    self.assertEqual(collected["functionalQualification"], "PENDING")
                    for key in ("acceptance", "providerQualification", "releaseReady"):
                        self.assertIs(collected[key], False)
                digests.add(G.sha(raw))
                self.assertEqual(received, original)
                self.assertEqual(event["inputs"], full_request)
                self.assertEqual(G.canonical(G.cold_dispatch_inputs(plan)), complete_request_raw)
                self.assertEqual(attempt["inputBytes"].encode("utf-8"), complete_request_raw)
        self.assertEqual(len(digests), 4)

    def test_partial_empty_omission_and_every_further_required_omission_still_refuse(self):
        _, event, environment, facts, attempt, _ = self.fixture()
        cases = 0
        for count in (1, 2):
            for keys in itertools.combinations(OMITTED, count):
                altered = copy.deepcopy(event)
                for key in keys:
                    del altered["inputs"][key]
                with self.subTest(partial=keys):
                    self.refuse_both(altered, environment, facts, attempt)
                cases += 1
        received = self.received(event, True)
        for key in sorted(set(received["inputs"]) - {G.COLD_PLAN_INPUT}):
            altered = copy.deepcopy(received)
            del altered["inputs"][key]
            with self.subTest(required=key):
                self.refuse_both(altered, environment, facts, attempt)
            cases += 1
        self.assertEqual(cases, 15)
        ordinary = copy.deepcopy(received)
        del ordinary["inputs"][G.COLD_PLAN_INPUT]
        raw = G.canonical(ordinary)
        self.assertIsNone(G.bind_cold_original_event(raw, environment, **facts))
        with self.assertRaises(G.Refused):
            G.verify_cold_attempt_inputs(attempt, raw)

    def test_retained_types_values_and_reinserted_default_substitutions_cannot_downgrade(self):
        _, event, environment, facts, attempt, _ = self.fixture()
        cases = 0
        wrong_values = (False, None, 0, [], {}, "private-value-sentinel\n\t")
        for omitted in (False, True):
            received = self.received(event, omitted)
            for key in sorted(set(received["inputs"]) - set(OMITTED) - {G.COLD_PLAN_INPUT}):
                for value in wrong_values:
                    altered = copy.deepcopy(received)
                    altered["inputs"][key] = value
                    with self.subTest(omitted=omitted, key=key, type=type(value).__name__):
                        self.refuse_both(altered, environment, facts, attempt)
                    cases += 1
        for key in OMITTED:
            for value in wrong_values:
                altered = self.received(event, True)
                altered["inputs"][key] = value
                with self.subTest(reinserted=key, type=type(value).__name__):
                    self.refuse_both(altered, environment, facts, attempt)
                cases += 1
        self.assertEqual(cases, 126)

    def test_extra_aliases_and_caller_selected_profiles_are_never_accepted(self):
        _, event, environment, facts, attempt, _ = self.fixture()
        keys = ("unknown", "omittedKeys", "receivedInputSchema", "v23_phase1_gate_plan ",
                "\n::error::\t\u2603\x00", "V23_PHASE1_GATE_PLAN")
        for omitted in (False, True):
            for key in keys:
                altered = self.received(event, omitted)
                altered["inputs"][key] = ""
                with self.subTest(omitted=omitted, extra=key):
                    self.refuse_both(altered, environment, facts, attempt)

    def test_attempt_request_stays_complete_canonical_and_collector_keeps_raw_authentication(self):
        plan, event, environment, facts, attempt, api = self.fixture()
        for omitted in (False, True):
            received = self.received(event, omitted)
            raw = G.canonical(received)
            binding = G.bind_cold_original_event(raw, environment, **facts)
            for input_bytes in ("{}\n", G.canonical(self.received(event, True)["inputs"]).decode(),
                                json.dumps(event["inputs"], indent=2),
                                G.canonical(dict(event["inputs"], v23_d50_compiler_observation="true")).decode()):
                with self.subTest(omitted=omitted, request=G.sha(input_bytes.encode())), self.assertRaises(G.Refused):
                    G.verify_cold_attempt_inputs(dict(attempt, inputBytes=input_bytes), raw)
            with self.assertRaises(G.Refused):
                G.verify_cold_attempt_inputs(dict(attempt, planBytes=attempt["planBytes"] + " "), raw)
            arguments = dict(registered_plan_bytes=G.canonical(plan), original_event_bytes=raw, api_run=api,
                             **{key: value for key, value in facts.items() if key != "head"})
            for changes in ({"original_event_bytes": raw + b" "},
                            {"api_run": dict(api, run_attempt=2)}, {"tree": "9" * 40},
                            {"sources": dict(facts["sources"], **{G.COLLECTOR: "B" * 64})}):
                with self.subTest(omitted=omitted, changed=sorted(changes)), self.assertRaises(G.Refused):
                    G.verify_cold_collected_event(binding, **dict(arguments, **changes))
            for changes in ({"functionalQualification": "QUALIFIED"}, {"acceptance": True}, {"unknown": "field"}):
                with self.subTest(omitted=omitted, binding=sorted(changes)), self.assertRaises(G.Refused):
                    G.verify_cold_collected_event(dict(binding, **changes), **arguments)

    def test_received_parser_still_refuses_duplicates_bad_encoding_and_original_size_excess(self):
        _, event, environment, facts, attempt, _ = self.fixture()
        for omitted in (False, True):
            raw = G.canonical(self.received(event, omitted))
            hostile = (raw.replace(b'"inputs":', b'"inputs":{},"inputs":', 1),
                       raw.replace(b'"v23_run_kind":', b'"v23_run_kind":"development","v23_run_kind":', 1),
                       b"\xff", b"[]\n", b"x" * (G.MAX_EVENT_BYTES + 1))
            for altered in hostile:
                with self.subTest(omitted=omitted, bytes=len(altered), digest=G.sha(altered)):
                    with self.assertRaises(G.Refused):
                        G.bind_cold_original_event(altered, environment, **facts)
                    with self.assertRaises(G.Refused):
                        G.verify_cold_attempt_inputs(attempt, altered)

    def test_current_environment_plan_source_and_simultaneous_intent_guards_remain_strict(self):
        _, event, environment, facts, attempt, _ = self.fixture()
        for omitted in (False, True):
            received = self.received(event, omitted)
            raw = G.canonical(received)
            for key in environment:
                with self.subTest(omitted=omitted, environment=key), self.assertRaises(G.Refused):
                    G.bind_cold_original_event(raw, dict(environment, **{key: "foreign"}), **facts)
            for key, value in (("head", "9" * 40), ("tree", "9" * 40),
                               ("sources", dict(facts["sources"], **{G.COLLECTOR: "B" * 64}))):
                with self.subTest(omitted=omitted, fact=key), self.assertRaises(G.Refused):
                    G.bind_cold_original_event(raw, environment, **dict(facts, **{key: value}))
            simultaneous = copy.deepcopy(received)
            simultaneous["inputs"][G.PLAN_INPUT] = "not-a-gate-plan"
            self.refuse_both(simultaneous, environment, facts, attempt)

    def test_versioned_comparator_requires_closed_requested_shape_and_all_string_values(self):
        _, event, _, _, _, _ = self.fixture()
        requested = event["inputs"]
        received = self.received(event, True)["inputs"]
        self.assertIs(G.cold_received_inputs_match_v2(received, requested), True)
        variants = [dict(requested, **{key: None}) for key in OMITTED]
        variants += [dict(requested, v23_d50_compiler_observation=False), dict(requested, unknown=""),
                     {key: value for key, value in requested.items() if key != "s10_4_shard_id"}, None, []]
        for changed in variants:
            with self.subTest(requested_type=type(changed).__name__):
                self.assertIs(G.cold_received_inputs_match_v2(received, changed), False)
        for changed in (None, [], dict(received, v23_d50_compiler_observation=False), {}):
            with self.subTest(received_type=type(changed).__name__):
                self.assertIs(G.cold_received_inputs_match_v2(changed, requested), False)


if __name__ == "__main__":
    unittest.main()
