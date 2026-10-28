#!/usr/bin/env python3
"""Current C08 source-proof controls; mutations are in memory only.

The real positive executes the complete current reader. Individual frame,
caller, field and raw-reference controls invoke the existing reader layers so
their expected rejection is not hidden by an earlier complete-body digest.
These are source/tooling tests, not Swift behavior or native evidence.
"""
from __future__ import annotations

import re
import sys
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

import verify_p02_c08_contracts as reader

ERASE = "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift"
ADAPTER = "eraseEmptyGenerationPhaseDiagnostic"
LABELS = "eraseFixedPhaseLabelsForTesting"


class CurrentC08HardeningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        paths = tuple(reader.EXISTING_PATHS + reader.NEW_SOURCE_PATHS)
        paths += reader.CURRENT_C08_HARDENING_SUPPORT_PATHS
        cls.texts = {p: (reader.ROOT / p).read_text(encoding="utf-8") for p in paths}
        cls.codes = {p: reader._current_c08_swift_views(s)[1]
                     for p, s in cls.texts.items() if p.endswith(".swift")}
        cls.frames = [reader._current_c08_hardening_frame(
            cls.texts[p[0]], cls.codes[p[0]], p, f"declaration {index}")
            for index, p in enumerate(reader.CURRENT_C08_HARDENING_DECLARATIONS)]
        cls.field_row = next(row for row in reader.CURRENT_C08_HARDENING_REFERENCES
                             if row[1] == LABELS and row[2] is None)
        cls.field_literal = cls.field_row[4][0]

    def frame_rejects(self, index: int, old: str, new: str, reason: str) -> None:
        policy = reader.CURRENT_C08_HARDENING_DECLARATIONS[index]
        source = self.texts[policy[0]]
        start, end = self.frames[index]
        body = source[start:end]
        self.assertEqual(body.count(old), 1, "mutation must identify one real operand")
        changed = source[:start] + body.replace(old, new, 1) + source[end:]
        self.assertNotEqual(changed, source)
        with self.assertRaisesRegex(reader.VerificationError, reason):
            reader._current_c08_hardening_frame(
                changed, reader._current_c08_swift_views(changed)[1], policy,
                f"declaration {index}")

    def callers_reject(self, reason: str, *, texts=None, codes=None, frames=None) -> None:
        with self.assertRaisesRegex(reader.VerificationError, reason):
            reader._current_c08_hardening_callers(
                self.texts if texts is None else texts,
                self.codes if codes is None else codes,
                self.frames if frames is None else frames)

    def field_inputs(self, replacement: str):
        """Translate unchanged frame positions after a test-only prefix edit.

        No body policy or adopted expectation is changed. This lets the field
        guard, rather than unrelated downstream positional drift, reject the
        hostile initializer. No registered body overlaps this literal field.
        """
        source = self.texts[ERASE]
        self.assertEqual(source.count(self.field_literal), 1)
        start = source.index(self.field_literal)
        end = start + len(self.field_literal)
        delta = len(replacement) - len(self.field_literal)
        changed = source[:start] + replacement + source[end:]
        texts = dict(self.texts, **{ERASE: changed})
        codes = dict(self.codes, **{ERASE: reader._current_c08_swift_views(changed)[1]})
        frames = list(self.frames)
        for i, policy in enumerate(reader.CURRENT_C08_HARDENING_DECLARATIONS):
            if policy[0] != ERASE:
                continue
            left, right = frames[i]
            self.assertTrue(right <= start or left >= end)
            if left >= end:
                frames[i] = (left + delta, right + delta)
        return texts, codes, frames

    def test_real_current_bindings_and_complete_hardening_pass(self) -> None:
        reader.verify_current_source_bindings()
        reader.verify_current_source_hardening()

    def test_new_typed_cases_cannot_be_replaced_by_payload_or_unknown_labels(self) -> None:
        for old, new in (
            ('"generation.data-pointer-invalid"', 'String(describing: error)'),
            ('"generation.data-generation-missing"', '"unknown-generation"'),
            ('default: return "other"', 'default: return String(describing: error)'),
        ):
            with self.subTest(old=old):
                self.frame_rejects(90, old, new,
                                   "checked failure/identity clauses differ|complete checked declaration differs")

    def test_erase_route_wiring_and_confirmation_are_bound(self) -> None:
        for old, new in (
            ('let emptyGenerationDiagnostic = eraseEmptyGenerationPhaseDiagnostic',
             'let emptyGenerationDiagnostic = eraseFactoryPhaseDiagnostic'),
            ('diagnosticPhase: emptyGenerationDiagnostic', 'diagnosticPhase: nil'),
            ('guard confirmation == Self.requiredConfirmation else {', 'if false {'),
        ):
            with self.subTest(old=old):
                self.frame_rejects(96, old, new, "checked failure/identity clauses differ")

    def test_erase_original_failure_rethrow_is_bound(self) -> None:
        old = '                throw originalFailure\n            }\n            throw error'
        new = '                throw error\n            }\n            throw error'
        self.frame_rejects(96, old, new, "complete checked declaration differs")

    def test_each_new_auxiliary_marker_is_required_and_fixed(self) -> None:
        for stage in ('namespace-enter', 'namespace-return', 'targets-enter', 'targets-return',
                      'diagnostics-enter', 'diagnostics-return', 'remove-enter', 'remove-return'):
            old = f'print("ORIGINAL_AUX_PROGRESS_V1 scope=phase-written stage={stage}")'
            for new in ('', old + '\n' + old,
                        'print("ORIGINAL_AUX_PROGRESS_V1 scope=phase-written stage=\\(error)")'):
                with self.subTest(stage=stage, mutation=new):
                    self.frame_rejects(101, old, new, "complete checked declaration differs")

    def test_auxiliary_guard_and_poison_clause_are_required(self) -> None:
        for old, new in (
            ('if closeStarted { phase = .closeUncertain }', ''),
            ('guard !running, let retirement else { throw EraseAllServiceError.invalidAuthority }',
             'guard let retirement else { throw EraseAllServiceError.invalidAuthority }'),
        ):
            with self.subTest(old=old):
                self.frame_rejects(101, old, new, "checked failure/identity clauses differ")

    def test_auxiliary_rethrow_is_bound(self) -> None:
        old = 'if closeStarted { phase = .closeUncertain }\n                        throw error'
        new = 'if closeStarted { phase = .closeUncertain }\n                        return false'
        self.frame_rejects(101, old, new, "complete checked declaration differs")

    def test_adapter_optin_errno_filter_and_release_nil_are_required(self) -> None:
        for old, new in (
            ('guard erasePhaseDiagnosticForTesting != nil else { return nil }', ''),
            ('let savedErrno = errno', 'let savedErrno = 0'),
            ('defer { errno = savedErrno }', ''),
            ('guard fixed.hasPrefix("prepare.empty-target."),', 'guard true,'),
            ('Self.eraseFixedPhaseLabelsForTesting.contains(fixed) else { return }',
             'true else { return }'),
            ('stage=\\(fixed)', 'stage=\\(phase)'),
            ('#else\n        return nil\n#endif', '#else\n        return { _ in }\n#endif'),
        ):
            with self.subTest(old=old):
                self.frame_rejects(169, old, new, "checked failure/identity clauses differ")

    def test_adapter_wrong_owner_or_comment_only_declaration_refuses(self) -> None:
        policy = reader.CURRENT_C08_HARDENING_DECLARATIONS[169]
        original = self.texts[ERASE]
        for changed in (
            original.replace(policy[2][0], '@MainActor\nfinal class WrongEraseOwner {', 1),
            original.replace(policy[1], '    // ' + policy[1].lstrip(), 1),
        ):
            with self.subTest(owner=changed == original):
                with self.assertRaisesRegex(reader.VerificationError, "declaration/owner identity differs"):
                    reader._current_c08_hardening_frame(
                        changed, reader._current_c08_swift_views(changed)[1], policy, "adapter")

    def test_allowlist_value_expression_and_boundary_mutations_reach_field_guard(self) -> None:
        literal = self.field_literal
        for changed in (
            literal.replace('"prepare.empty-target.route-retained"', '"prepare.empty-target.secret"', 1),
            literal.replace('        "prepare.empty-target.route-retained",\n', '', 1),
            literal.replace('"prepare.empty-target.route-retained"', 'externalPhase', 1),
            literal.replace('\n    ]\n', '\n    ] + externalLabels\n', 1),
            literal.replace('\n    ]\n', '\n    ]\n        .union(externalLabels)\n', 1),
        ):
            with self.subTest(mutation=changed[-100:]):
                self.assertNotEqual(literal, changed)
                texts, codes, frames = self.field_inputs(changed)
                self.callers_reject("protected field/comment literal role differs",
                                    texts=texts, codes=codes, frames=frames)

    def test_allowlist_comment_and_non_debug_roles_are_rejected_directly(self) -> None:
        for replacement, reason in (
            ('/*' + self.field_literal + '*/', 'protected field code/depth differs'),
            ('#endif\n' + self.field_literal + '\n#if DEBUG',
             'protected field conditional ownership differs'),
        ):
            with self.subTest(reason=reason):
                texts, codes, frames = self.field_inputs(replacement)
                self.callers_reject(reason, texts=texts, codes=codes, frames=frames)

    def test_allowlist_wrong_named_owner_is_rejected(self) -> None:
        rows = list(reader.CURRENT_C08_HARDENING_REFERENCES)
        i = rows.index(self.field_row)
        old = rows[i]
        rows[i] = old[:4] + ((old[4][0], ('@MainActor\nfinal class WrongEraseOwner {',)),)
        with patch.object(reader, 'CURRENT_C08_HARDENING_REFERENCES', tuple(rows)):
            self.callers_reject("protected field owner identity differs")

    def test_unchanged_trace_cannot_bypass_membership_or_history_bound(self) -> None:
        for old, new in (
            ('Self.eraseFixedPhaseLabelsForTesting.contains(phase)', 'true'),
            ('eraseFixedPhaseHistoryForTesting.count > 32', 'eraseFixedPhaseHistoryForTesting.count > 9999'),
        ):
            with self.subTest(old=old):
                self.frame_rejects(170, old, new, "checked failure/identity clauses differ")

    def test_stale_erase_caller_offset_reaches_caller_guard(self) -> None:
        rows = list(reader.CURRENT_C08_HARDENING_CALLERS)
        i = next(i for i, row in enumerate(rows) if row[2] == 96)
        row = rows[i]
        rows[i] = row[:3] + (row[3] - 308,) + row[4:]
        with patch.object(reader, 'CURRENT_C08_HARDENING_CALLERS', tuple(rows)):
            self.callers_reject("actual caller/DEBUG branch differs")

    def test_missing_or_wrong_adapter_caller_reaches_closed_caller_guard(self) -> None:
        rows = reader.CURRENT_C08_HARDENING_CALLERS
        for changed in (rows[:-1], rows[:-1] + (rows[-2],)):
            with self.subTest(length=len(changed)):
                with patch.object(reader, 'CURRENT_C08_HARDENING_CALLERS', changed):
                    self.callers_reject("complete caller census differs")

    def test_stale_erase_reference_offset_reaches_literal_position_guard(self) -> None:
        rows = list(reader.CURRENT_C08_HARDENING_REFERENCES)
        i = next(i for i, row in enumerate(rows) if row[2] == 96 and row[1] == 'print')
        row = rows[i]
        rows[i] = row[:3] + (row[3] - 308,) + row[4:]
        with patch.object(reader, 'CURRENT_C08_HARDENING_REFERENCES', tuple(rows)):
            self.callers_reject("protected reference literal position differs")

    def test_missing_reference_and_changed_vocabulary_refuse(self) -> None:
        with patch.object(reader, 'CURRENT_C08_HARDENING_REFERENCES',
                          reader.CURRENT_C08_HARDENING_REFERENCES[:-1]):
            self.callers_reject("protected reference policy census differs")
        with patch.object(reader, 'CURRENT_C08_HARDENING_PROTECTED_IDENTIFIERS',
                          reader.CURRENT_C08_HARDENING_PROTECTED_IDENTIFIERS[:-1]):
            self.callers_reject("protected reference policy census differs")

    def test_extra_aliases_member_values_comments_and_interpolation_refuse(self) -> None:
        for suffix, reason in (
            ('\nlet extra = self . eraseEmptyGenerationPhaseDiagnostic\n', 'complete caller census differs'),
            ('\nlet extra = eraseFixedPhaseLabelsForTesting\n', 'unregistered protected reference'),
            ('\n// eraseEmptyGenerationPhaseDiagnostic\n', 'unregistered protected reference'),
            ('\nlet text = "\\(eraseEmptyGenerationPhaseDiagnostic)"\n', 'unregistered protected reference'),
            ('\nlet alias = os_log\n', 'unregistered protected reference'),
            ('\nlet alias = Logger\n', 'unregistered protected reference'),
            ('\nlet alias = print\n', 'unregistered protected reference'),
        ):
            with self.subTest(suffix=suffix):
                text = self.texts[ERASE] + suffix
                self.callers_reject(reason, texts=dict(self.texts, **{ERASE: text}),
                                    codes=dict(self.codes, **{ERASE: reader._current_c08_swift_views(text)[1]}))

    def test_changed_event_condition_reaches_conditional_guard(self) -> None:
        rows = list(reader.CURRENT_C08_HARDENING_DECLARATIONS)
        row = list(rows[169])
        row[7] = (('print', 1538, ()),)
        rows[169] = tuple(row)
        with patch.object(reader, 'CURRENT_C08_HARDENING_DECLARATIONS', tuple(rows)):
            with self.assertRaisesRegex(reader.VerificationError, 'event scope/conditional differs'):
                reader.verify_current_source_hardening()

    def test_missing_or_duplicate_event_reaches_whole_primary_census(self) -> None:
        for events in ((), (('print', 1538, ('if DEBUG',)),) * 2):
            with self.subTest(events=events):
                rows = list(reader.CURRENT_C08_HARDENING_DECLARATIONS)
                row = list(rows[169])
                row[7] = events
                rows[169] = tuple(row)
                with patch.object(reader, 'CURRENT_C08_HARDENING_DECLARATIONS', tuple(rows)):
                    with self.assertRaisesRegex(reader.VerificationError, 'unregistered/moved print site'):
                        reader.verify_current_source_hardening()


if __name__ == '__main__':
    unittest.main()
