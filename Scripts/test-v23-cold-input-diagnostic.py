"""Synthetic refusal diagnostics only; no authentic event, dispatch or gate credit.

Reason: hosted original 37379483873 refused the exact cold input equality, but
its log retained no differing key/type/value fingerprint. These checks preserve
that refusal and its first exception while exercising prospective diagnostic
detail. A fingerprint is never an accepted replacement for the original input.
"""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest import mock


def load():
    path = Path(__file__).with_name("v23-phase1-gates.py")
    spec = importlib.util.spec_from_file_location("cold_input_diagnostic_test_target", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


G = load()
HEAD, TREE = "1" * 40, "2" * 40
PREFIX = "cold dispatch input difference: "
REFUSAL = "Phase1 gate: closed cold original dispatch inputs"


class ColdInputDifferenceDiagnosticTests(unittest.TestCase):
    def fixture(self):
        """Invented Source/run identities, using the real closed cold builder."""
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
        return plan, event, environment, facts

    def refusal(self, event, environment, facts):
        raw = json.dumps(event, ensure_ascii=True, indent=2).encode("utf-8")
        with self.assertRaises(G.Refused) as caught:
            G.bind_cold_original_event(raw, environment, **facts)
        self.assertEqual(str(caught.exception), REFUSAL)
        notes = caught.exception.__notes__
        self.assertEqual(len(notes), 1)
        self.assertTrue(notes[0].startswith(PREFIX))
        self.assertNotIn("\n", notes[0])
        self.assertLessEqual(len(notes[0].removeprefix(PREFIX).encode("ascii")) + 1, 16 * 1024)
        detail = json.loads(notes[0].removeprefix(PREFIX))
        self.assertEqual(detail["schema"], "v23-cold-dispatch-input-difference-diagnostic.v1")
        self.assertEqual(detail["originalEvent"], {"bytes": len(raw), "SHA256": G.sha(raw)})
        return detail, notes[0]

    def test_exact_valid_event_keeps_original_binding_and_never_calls_diagnostic(self):
        plan, event, environment, facts = self.fixture()
        for raw in (G.canonical(event), json.dumps(event, indent=2).encode()):
            with self.subTest(serialization=G.sha(raw)), mock.patch.object(
                    G, "cold_dispatch_input_difference", side_effect=AssertionError("valid diagnostic call")):
                binding = G.bind_cold_original_event(raw, environment, **facts)
            self.assertEqual(binding, {"schema": G.COLD_EVENT_SCHEMA, "plan": plan,
                "planSHA256": G.sha(G.canonical(plan)), "originalEventSHA256": G.sha(raw),
                "repository": G.REPOSITORY, "ref": plan["ref"], "head": HEAD, "tree": TREE,
                "workflowRef": environment["GITHUB_WORKFLOW_REF"], "workflowSHA": HEAD,
                "runID": "123", "runAttempt": "1", "kind": "development",
                "selection": G.COLD_SELECTION, "functionalQualification": "PENDING", "status": "INCOMPLETE",
                "developmentOnly": True, "providerQualification": False,
                "acceptance": False, "releaseReady": False})

    def test_missing_and_substituted_remaining_keys_still_refuse_with_exact_digests(self):
        _, event, environment, facts = self.fixture()
        keys = ("s10_4_shard_id", "s10_4_minimum_core_smoke_id", "s10_4_shared_segment_id",
                "s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids",
                "v23_d50_compiler_observation", "v23_d50_swift_driver_jobs_two", G.PLAN_INPUT)
        for key in keys:
            for mutation in ("missing", "substituted"):
                # Nonempty gate intent is intentionally rejected by the earlier guard.
                if key == G.PLAN_INPUT and mutation == "substituted":
                    continue
                altered = copy.deepcopy(event)
                if mutation == "missing":
                    del altered["inputs"][key]
                else:
                    altered["inputs"][key] = "private-value-sentinel"
                with self.subTest(key=key, mutation=mutation):
                    detail, note = self.refusal(altered, environment, facts)
                    self.assertEqual(detail["extraKeyCount"], 0)
                    if mutation == "missing":
                        self.assertEqual(detail["missingKeys"], [key])
                        self.assertEqual(detail["changedValues"], [])
                    else:
                        self.assertEqual(detail["missingKeys"], [])
                        self.assertEqual(detail["changedValues"], [{"key": key,
                            "actual": {"type": "str", "canonicalBytes": len(G.canonical(altered["inputs"][key])),
                                       "canonicalSHA256": G.sha(G.canonical(altered["inputs"][key]))},
                            "expected": {"type": "str", "canonicalBytes": len(G.canonical(event["inputs"][key])),
                                         "canonicalSHA256": G.sha(G.canonical(event["inputs"][key]))}}])
                    self.assertNotIn("private-value-sentinel", note)

    def test_wrong_types_and_values_are_reported_without_acceptance_or_raw_values(self):
        _, event, environment, facts = self.fixture()
        key = "v23_d50_compiler_observation"
        values = (False, None, 0, ["private-value-sentinel"], {"private": "private-value-sentinel"},
                  "private-value-sentinel\n\t\u2603", "")
        for value in values:
            altered = copy.deepcopy(event)
            altered["inputs"][key] = value
            with self.subTest(type=type(value).__name__, digest=G.sha(G.canonical(value))):
                detail, note = self.refusal(altered, environment, facts)
                self.assertEqual(detail["changedValues"], [{"key": key,
                    "actual": {"type": type(value).__name__, "canonicalBytes": len(G.canonical(value)),
                               "canonicalSHA256": G.sha(G.canonical(value))},
                    "expected": {"type": "str", "canonicalBytes": len(G.canonical("false")),
                                 "canonicalSHA256": G.sha(G.canonical("false"))}}])
                self.assertNotIn("private-value-sentinel", note)
        altered = copy.deepcopy(event)
        altered["inputs"][key] = float("nan")
        detail, _ = self.refusal(altered, environment, facts)
        self.assertEqual(detail["changedValues"][0]["actual"],
                         {"type": "float", "canonicalEncodingError": "ValueError"})

    def test_extra_hostile_keys_are_escaped_bounded_and_fingerprinted_without_values(self):
        _, event, environment, facts = self.fixture()
        keys = ["\n::error::\t\u2603\x00-" + str(index).zfill(2) + "x" * 1000 for index in range(20)]
        altered = copy.deepcopy(event)
        altered["inputs"].update({key: "private-value-sentinel" for key in keys})
        detail, note = self.refusal(altered, environment, facts)
        self.assertEqual(detail["missingKeys"], [])
        self.assertEqual(detail["changedValues"], [])
        self.assertEqual(detail["extraKeyCount"], 20)
        self.assertIs(detail["extraKeyDetailsComplete"], False)
        self.assertEqual(detail["extraKeyFacts"], [{"keyPrefix": key[:64],
            "canonicalBytes": len(G.canonical(key)), "canonicalSHA256": G.sha(G.canonical(key))}
            for key in sorted(keys)[:16]])
        self.assertNotIn("private-value-sentinel", note)
        self.assertNotIn("\t", note)
        self.assertNotIn("\x00", note)
        small = copy.deepcopy(event)
        small["inputs"]["unknown"] = "private-value-sentinel"
        detail, note = self.refusal(small, environment, facts)
        self.assertEqual(detail["extraKeyCount"], 1)
        self.assertIs(detail["extraKeyDetailsComplete"], True)
        self.assertNotIn("private-value-sentinel", note)

    def test_earlier_guards_and_empty_ordinary_route_never_call_diagnostic(self):
        _, event, environment, facts = self.fixture()
        variants = []
        variants.append((event, dict(environment, GITHUB_RUN_ATTEMPT="2"), "original event attempt/run"))
        for key, value, message in (("v23_run_kind", "gate", "original event kind/selection/lane"),
                ("run_ui_smoke", False, "original event UI intent"),
                (G.PLAN_INPUT, "not-a-gate-plan", "simultaneous cold and gate plans")):
            altered = copy.deepcopy(event)
            altered["inputs"][key] = value
            variants.append((altered, environment, message))
        with mock.patch.object(G, "cold_dispatch_input_difference", side_effect=AssertionError("early diagnostic call")):
            for altered, changed_environment, message in variants:
                with self.subTest(message=message), self.assertRaisesRegex(G.Refused, message) as caught:
                    G.bind_cold_original_event(G.canonical(altered), changed_environment, **facts)
                self.assertFalse(hasattr(caught.exception, "__notes__"))
            self.assertIsNone(G.bind_cold_original_event(G.canonical({"inputs": {}}), {}, **facts))

    def test_diagnostic_first_excess_bound_cannot_replace_or_enlarge_the_refusal(self):
        _, event, environment, facts = self.fixture()
        altered = copy.deepcopy(event)
        altered["inputs"]["s10_4_shard_id"] = "foreign"
        raw = G.canonical(altered)
        original_canonical = G.canonical
        def oversized_diagnostic(value):
            if type(value) is dict and value.get("schema") == "v23-cold-dispatch-input-difference-diagnostic.v1":
                return b"x" * (16 * 1024 + 1)
            return original_canonical(value)
        with mock.patch.object(G, "canonical", side_effect=oversized_diagnostic), \
                self.assertRaises(G.Refused) as caught:
            G.bind_cold_original_event(raw, environment, **facts)
        self.assertEqual(str(caught.exception), REFUSAL)
        self.assertEqual(caught.exception.__notes__, ["cold input diagnostic failed: Refused"])

    def test_diagnostic_and_note_failures_preserve_the_first_actual_refusal_object(self):
        _, event, environment, facts = self.fixture()
        altered = copy.deepcopy(event)
        altered["inputs"]["s10_4_shard_id"] = "foreign"
        raw = G.canonical(altered)
        original_require = G.require
        for secondary in (RuntimeError("private-value-sentinel"), MemoryError("private-value-sentinel"), KeyboardInterrupt()):
            for failing_note in (False, True):
                primary = G.Refused(REFUSAL)
                def retain_refusal(value, message):
                    if message == "closed cold original dispatch inputs":
                        self.assertIs(value, False)
                        raise primary
                    return original_require(value, message)
                def note(value):
                    if failing_note:
                        raise OSError("private-value-sentinel")
                    return BaseException.add_note(primary, value)
                with self.subTest(secondary=type(secondary).__name__, failing_note=failing_note), \
                        mock.patch.object(G, "require", side_effect=retain_refusal), \
                        mock.patch.object(G, "cold_dispatch_input_difference", side_effect=secondary), \
                        mock.patch.object(primary, "add_note", side_effect=note), \
                        self.assertRaises(G.Refused) as caught:
                    G.bind_cold_original_event(raw, environment, **facts)
                self.assertIs(caught.exception, primary)
                self.assertEqual(str(caught.exception), REFUSAL)
                if not failing_note:
                    self.assertEqual(primary.__notes__, ["cold input diagnostic failed: " + type(secondary).__name__])
                else:
                    self.assertFalse(hasattr(primary, "__notes__"))


if __name__ == "__main__":
    unittest.main()
