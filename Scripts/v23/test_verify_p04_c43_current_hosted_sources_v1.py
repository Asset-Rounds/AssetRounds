#!/usr/bin/env python3
"""Current C43 source-contract controls using real inputs and in-memory mutations.

These tests verify the source reader's refusals, not UIKit/native behavior.
Every hostile control first requires the unmodified current bundle to pass, so
an unrelated pre-existing refusal cannot satisfy a negative test.
"""
from __future__ import annotations

import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

import p04_c41_contracts as source_reader
import verify_p04_c43_contracts as verifier

JOURNEY = "FieldEvidenceAppTests/V23ProductionSignoffResponseJourneyTests.swift"


class CurrentC43HostedSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.inputs = verifier.c.current_hosted_unit_sources()
        cls.original = cls.inputs["sources"][JOURNEY]["source"]
        cls.observer = source_reader.current_source_block(
            cls.inputs, JOURNEY, r"func\s+waitForCompletedWorkMoreMenu", "More observer")

    def inputs_for(self, source: str | None = None):
        inputs = dict(self.inputs)
        inputs["sources"] = dict(inputs["sources"])
        if source is not None:
            parser = inputs["generator"]
            inputs["sources"][JOURNEY] = {
                "source": source,
                "code": parser._active_swift(parser._mask_swift_noncode(source)),
            }
        return inputs

    def result(self, source: str | None = None):
        with patch.object(verifier.c, "current_hosted_unit_sources", return_value=self.inputs_for(source)):
            return verifier._current_hosted_unit_fixture_result()

    def structural_failures(self, source: str):
        # Exercise semantic guards separately, so their refusal is not supplied
        # solely by the complete body pin used to close equivalent early returns.
        failures = []
        try:
            verifier._current_more_menu_observer_contract(
                self.inputs_for(source), source_reader, failures)
        except ValueError as error:
            failures.append(str(error))
        return failures

    def assert_current_passes(self) -> None:
        result = self.result()
        self.assertEqual(result["failures"], [])
        self.assertEqual(result["result"], "PASS_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE_ONLY")

    def observer_rejects(self, old: str, new: str, *, all_occurrences: bool = False) -> None:
        self.assert_current_passes()
        body = self.observer["source"]
        self.assertIn(old, body, "mutation must target actual observer code")
        if not all_occurrences:
            self.assertEqual(body.count(old), 1, "mutation must be unambiguous")
        changed_body = body.replace(old, new) if all_occurrences else body.replace(old, new, 1)
        self.assertNotEqual(body, changed_body)
        self.assertEqual(self.original.count(body), 1)
        changed = self.original.replace(body, changed_body, 1)
        result = self.result(changed)
        self.assertEqual(result["result"], "FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE")
        self.assertTrue(result["failures"])
        self.assertTrue(self.structural_failures(changed),
                        "semantic guard must reject without relying on the body pin")

    def test_real_current_bundle_passes_without_readiness_claim(self) -> None:
        self.assert_current_passes()
        result = self.result()
        for field in ("SourceReady", "nativeExecution", "acceptanceCredit", "gateCredit",
                      "releaseReady", "historicalArtifactsRegenerated",
                      "physicalMenuOrAccessibilityQualification"):
            with self.subTest(field=field):
                self.assertIs(result[field], False)

    def test_a_helper_name_alone_cannot_supply_menu_observation(self) -> None:
        self.assert_current_passes()
        body = self.observer["source"]
        replacement = "func waitForCompletedWorkMoreMenu(from host: UIViewController) async -> Bool { return true }"
        result = self.result(self.original.replace(body, replacement, 1))
        self.assertEqual(result["result"], "FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE")
        self.assertTrue(result["failures"])

    def test_equivalent_early_success_cannot_bypass_observation(self) -> None:
        self.assert_current_passes()
        body = self.observer["source"]
        opening = body.index("{") + 1
        for statement in ("return true", "return 1 == 1", "return !false"):
            with self.subTest(statement=statement):
                changed_body = body[:opening] + "\n        " + statement + "\n" + body[opening:]
                result = self.result(self.original.replace(body, changed_body, 1))
                self.assertEqual(result["result"], "FAIL_CURRENT_HOSTED_UNIT_SOURCE_STRUCTURE")
                self.assertIn("complete More observer source frame differs", result["failures"])

    def test_ambiguous_or_truncated_control_discovery_is_rejected(self) -> None:
        for old, new in (
            ("!controls.truncated, controls.buttons.count <= 1", "controls.buttons.count <= 2"),
            ("depth <= 32, seenViews.count < 256", "depth <= 33, seenViews.count < 257"),
            ("if view.subviews.count > 64 { truncated = true }", ""),
            ("!finalControls.truncated && finalControls.buttons.count == 1", "true"),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)

    def test_control_must_be_attached_enabled_visible_and_clipped(self) -> None:
        for old, new in (
            ("button.window === window, button.isDescendant(of: root)", "true"),
            ("button.isEnabled, !button.bounds.isEmpty", "true"),
            ("!current.isHidden, current.alpha > 0,", ""),
            ("current.isUserInteractionEnabled", "true"),
            ("if current.clipsToBounds || current === window {", "if false {"),
            ("visible = visible.intersection(current.convert(current.bounds, to: window))", ""),
            ("finalControls.buttons.first === button", "true"),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)

    def test_expected_single_enabled_visible_action_is_required(self) -> None:
        for old, new in (
            ("menu.children.count == 1", "menu.children.count >= 1"),
            ("let action = menu.children.first as? UIAction", "let action = UIAction(title: \"Record approval response\") { _ in } as UIAction?"),
            ("&& !action.attributes.contains(.disabled)", ""),
            ("&& !action.attributes.contains(.hidden)", ""),
            ("callbacks == 1 && expectedActionVisible", "callbacks >= 0"),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)
        self.observer_rejects(
            "action.title == SignoffEnrollmentManifestV1.actionTitle", "true", all_occurrences=True)

    def test_action_activation_and_dismissal_cannot_be_removed_or_retried(self) -> None:
        for statement in ("button.performPrimaryAction()", "interaction.dismissMenu()"):
            for replacement in ("", statement + "\n" + statement):
                with self.subTest(statement=statement, replacement=replacement):
                    self.observer_rejects(statement, replacement)

    def test_shared_wait_budget_cannot_expand_or_stop_decrementing(self) -> None:
        for old, new in (
            ("var remainingWaits = 200", "var remainingWaits = 201"),
            ("remainingWaits -= 1", ""),
            ("remainingWaits > 0, !Task.isCancelled", "!Task.isCancelled"),
            ("Task.sleep(nanoseconds: 25_000_000)", "Task.sleep(nanoseconds: 50_000_000)"),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)

    def test_returning_success_cannot_bypass_observed_menu_and_dismissal(self) -> None:
        for old, new in (
            ("return observed", "return true"),
            ("&& expectedActionVisible && dismissed", "&& expectedActionVisible"),
            ("&& sameMountedControl && !Task.isCancelled", ""),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)

    def test_existing_menu_cannot_be_mistaken_for_new_activation(self) -> None:
        for old, new in (
            ("initiallyVisible = true", "initiallyVisible = false"),
            ("guard !initiallyVisible else { return false }", ""),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)

    def test_dismissal_needs_two_consecutive_absences_with_shared_yield(self) -> None:
        for old, new in (
            ("consecutiveAbsentSamples = stillVisible ? 0 : consecutiveAbsentSamples + 1",
             "consecutiveAbsentSamples += 1"),
            ("if consecutiveAbsentSamples == 2", "if consecutiveAbsentSamples == 1"),
            ("var dismissed = false", "var dismissed = true"),
            ("stillVisible = true", "stillVisible = false"),
        ):
            with self.subTest(old=old):
                self.observer_rejects(old, new)
        self.observer_rejects("while await nextSample()", "while false", all_occurrences=True)

    def test_unsupported_held_fallback_or_synthetic_action_dispatch_is_rejected(self) -> None:
        for extra in (
            "if button.isHeld { return true }\n",
            "if interaction.menuAppearance == .compact { return true }\n",
            "button.sendActions(for: .touchUpInside)\n",
        ):
            with self.subTest(extra=extra):
                self.observer_rejects("return observed", extra + "return observed")

    def test_guard_text_in_comments_cannot_replace_executed_checks(self) -> None:
        old = "if view.subviews.count > 64 { truncated = true }"
        self.observer_rejects(old, "// " + old)


if __name__ == "__main__":
    unittest.main()
