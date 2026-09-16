#!/usr/bin/env python3

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True


HERE = Path(__file__).resolve().parent
REPO = HERE.parent
GENERATOR = HERE / "v23-selection-generator.py"
MANIFEST = HERE / "v23-selection-manifest.json"
COMMIT = "67ccbaba65330d4d60fb1aab21cf6cc244c2b257"
SELECTION_SHA = "91E6F41D81E982D116611FF4A96219FE3631020B5CB264F76A8BDA1E4E27408E"
MAP_SHA = "CD41DF01E106199B7CAE86CEDEB4BAA93F812C76D7B510BA6DC941DFCDDF7129"
NEW_SELECTOR = ("FieldEvidenceAppTests/V23MutationReceiptSafetyTests/"
                "testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority")

spec = importlib.util.spec_from_file_location("v23_selection_generator", GENERATOR)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def git_bytes(path):
    return subprocess.check_output(["git", "show", COMMIT + ":" + path], cwd=REPO)


class GeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = generator.load_json(MANIFEST)
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.checkout = Path(cls.temp.name).resolve() / "checkout"
        sources = cls.checkout / "FieldEvidenceAppTests"
        sources.mkdir(parents=True)
        classes = sorted({name for group in cls.manifest["groups"] for name in group["classes"]})
        for class_name in classes:
            (sources / (class_name + ".swift")).write_bytes(
                git_bytes("FieldEvidenceAppTests/" + class_name + ".swift")
            )
        cls.incumbent_selection = git_bytes("Scripts/ci-selection.json")
        cls.incumbent_map = git_bytes("Scripts/ci-selection-map.json")

    def generate(self, profile="prospective-v1", manifest=None, checkout=None):
        return generator.generate(manifest or copy.deepcopy(self.manifest), profile,
                                  checkout or self.checkout)

    def test_exact_incumbent_reconstruction_and_prospective_delta(self):
        selection, selection_map, report = self.generate("incumbent-v1")
        self.assertEqual(generator.canonical(selection), self.incumbent_selection)
        self.assertEqual(generator.canonical(selection_map), self.incumbent_map)
        self.assertEqual((report["selectorCount"], report["groupCount"]), (692, 37))
        self.assertEqual((report["selectionSHA256"], report["selectionMapSHA256"]),
                         (SELECTION_SHA, MAP_SHA))

        future, future_map, future_report = self.generate()
        self.assertEqual((future_report["selectorCount"], future_report["groupCount"]),
                         (693, 38))
        self.assertEqual(future["unitTestSelectors"][:-1], selection["unitTestSelectors"])
        self.assertEqual(future["unitTestSelectors"][-1], NEW_SELECTOR)
        self.assertEqual(future_map["groups"][:-1], selection_map["groups"])
        self.assertEqual(future_map["groups"][-1], {
            "id": "mutation-receipt-safety",
            "classes": ["V23MutationReceiptSafetyTests"],
            "methodCount": 1,
        })
        self.assertFalse(future_report["nativeReady"])
        self.assertFalse(future_report["acceptance"])

    def test_raw_photo_profile_retains_both_historical_profiles_and_enrolls_exact_four(self):
        prior, prior_map, _ = self.generate('prospective-v1')
        current, current_map, report = self.generate('raw-photo-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (697, 39))
        self.assertEqual(current['unitTestSelectors'][:-4], prior['unitTestSelectors'])
        self.assertEqual(current_map['groups'][:-1], prior_map['groups'])
        self.assertEqual(current_map['groups'][-1], {'id': 'c36-raw-staging',
            'classes': ['V9_30FieldDraftResilienceTests'], 'methodCount': 4})
        self.assertEqual(current['unitTestSelectors'][-4:], [
            'FieldEvidenceAppTests/V9_30FieldDraftResilienceTests/' + method for method in (
                'testV9_30A01AlternatePerItemStagingAndExactRetryRemainIndependent',
                'testV9_30R01RecoveryReservationRetentionBackupRestoreAndOneAuthority',
                'testRestoreInitializationMatchesActorPublicationAndReopensExactBytes',
                'testRestoreInitializationRejectsHostileInputsWithoutPublishingEntries')])
        self.assertEqual(report['selectionSHA256'],
            '62673E1257EE72462439FA8770F3D3CFB50ED2FB06F0674C7C9E8D5FE2FDBEBB')
        self.assertEqual(report['selectionMapSHA256'],
            '77E605D5BE168687CC9EB81C4F695806C6A6E2FCD619411C64AA7E251676CEAC')

    def test_legacy_consumer_shape_disjoint_exhaustive_and_deterministic(self):
        selection, selection_map, report = self.generate()
        self.assertEqual(set(selection), generator.COMMON_KEYS | {"unitTestSelectors"})
        self.assertEqual(set(selection_map), {"schemaVersion", "taskID", "defaultSelectionID", "groups"})
        expected = set(selection["unitTestSelectors"])
        covered = set()
        for group in selection_map["groups"]:
            self.assertEqual(set(group), {"id", "classes", "methodCount"})
            members = [item for item in selection["unitTestSelectors"]
                       if generator.parse_selector(item)[0] in group["classes"]]
            self.assertEqual(len(members), group["methodCount"])
            self.assertFalse(covered & set(members))
            covered.update(members)
        self.assertEqual(covered, expected)
        again = self.generate()
        self.assertEqual(generator.canonical(selection), generator.canonical(again[0]))
        self.assertEqual(generator.canonical(selection_map), generator.canonical(again[1]))
        self.assertEqual(report, again[2])

    def test_manifest_shape_membership_environment_and_path_hostiles(self):
        mutations = []
        value = copy.deepcopy(self.manifest); value["unknown"] = 1; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["selectorPool"].append(value["selectorPool"][0]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["selectorPool"][0] = "FieldEvidenceAppTests/../testEscape"; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["commonSelection"]["buildTimeoutSeconds"] = 1201; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["commonSelection"]["runUISmoke"] = 0; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][1]["classes"].append(value["groups"][0]["classes"][0]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][0]["classes"][0] = "UnknownTests"; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][1]["id"] = value["groups"][0]["id"]; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedGroupIDs"] = ["unknown"]; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["defaultSelectionID"] = "unadmitted-default"; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["selectorPool"].append({}); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][0]["classes"].append([]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedGroupIDs"].append({}); mutations.append(value)
        for index, hostile in enumerate(mutations):
            with self.subTest(index=index), self.assertRaises(generator.ManifestError):
                generator.validate_manifest(hostile)

        duplicate = Path(self.temp.name) / "duplicate-keys.json"
        duplicate.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8")
        with self.assertRaises(generator.ManifestError):
            generator.load_json(duplicate)
        with self.assertRaisesRegex(generator.ManifestError, "unknown profile"):
            self.generate("unknown-profile")

    def test_missing_unknown_and_duplicate_source_declarations_fail(self):
        target = self.checkout / "FieldEvidenceAppTests/V23MutationReceiptSafetyTests.swift"
        original = target.read_text(encoding="utf-8")
        token = "func testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority("
        self.assertEqual(original.count(token), 1)
        try:
            target.write_text(original.replace(token, "func renamedDayAndNightWorkflow("), encoding="utf-8")
            with self.assertRaisesRegex(generator.ManifestError, "missing or duplicate source method"):
                self.generate()
            target.write_text(original + "\nextension V23MutationReceiptSafetyTests {\n    " + token + ") {}\n}\n",
                              encoding="utf-8")
            with self.assertRaisesRegex(generator.ManifestError, "missing or duplicate source method"):
                self.generate()
        finally:
            target.write_text(original, encoding="utf-8")

        hostile = copy.deepcopy(self.manifest)
        receipt_index = hostile["selectorPool"].index(NEW_SELECTOR)
        hostile["selectorPool"][receipt_index] = hostile["selectorPool"][receipt_index].replace(
            "testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority",
            "testUnknownReceiptSafetyMethod")
        with self.assertRaisesRegex(generator.ManifestError, "missing or duplicate source method"):
            self.generate(manifest=hostile)

    def test_cli_outputs_are_canonical_and_refuse_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            command = [sys.executable, str(GENERATOR), "generate", "--manifest", str(MANIFEST),
                       "--checkout-root", str(self.checkout), "--profile", "prospective-v1",
                       "--selection-output", str(output / "ci-selection.json"),
                       "--map-output", str(output / "ci-selection-map.json"),
                       "--report-output", str(output / "report.json")]
            first = subprocess.run(command, check=True, capture_output=True)
            selection, selection_map, report = self.generate()
            self.assertEqual((output / "ci-selection.json").read_bytes(), generator.canonical(selection))
            self.assertEqual((output / "ci-selection-map.json").read_bytes(), generator.canonical(selection_map))
            self.assertEqual((output / "report.json").read_bytes(), generator.canonical(report))
            self.assertEqual(first.stdout, generator.canonical(report))
            second = subprocess.run(command, capture_output=True)
            self.assertEqual(second.returncode, 65)
            self.assertIn(b"output already exists", second.stderr)

            partial = output / "partial"
            partial.mkdir()
            (partial / "ci-selection-map.json").write_text("occupied", encoding="utf-8")
            hostile = command.copy()
            hostile[hostile.index(str(output / "ci-selection.json"))] = str(partial / "ci-selection.json")
            hostile[hostile.index(str(output / "ci-selection-map.json"))] = str(partial / "ci-selection-map.json")
            hostile[hostile.index(str(output / "report.json"))] = str(partial / "report.json")
            failed = subprocess.run(hostile, capture_output=True)
            self.assertEqual(failed.returncode, 65)
            self.assertFalse((partial / "ci-selection.json").exists())
            self.assertFalse((partial / "report.json").exists())

    def generate_source_case(self, source):
        manifest = copy.deepcopy(self.manifest)
        manifest["selectorPool"] = ["FieldEvidenceAppTests/FixtureTests/testSelected"]
        manifest["groups"] = [{"id": "fixture", "classes": ["FixtureTests"]}]
        manifest["profiles"] = [{"id": "fixture-v1", "excludedGroupIDs": []}]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            directory = root / "FieldEvidenceAppTests"
            directory.mkdir()
            (directory / "FixtureTests.swift").write_text(source, encoding="utf-8")
            return generator.generate(manifest, "fixture-v1", root)

    def test_only_direct_runnable_xctest_methods_are_members(self):
        invalid = {
            "nested function": "class FixtureTests: XCTestCase { func helper() { func testSelected() {} } }",
            "nested type": "class FixtureTests: XCTestCase { struct Helper { func testSelected() {} } }",
            "parameter": "class FixtureTests: XCTestCase { func testSelected(value: Int) {} }",
            "static": "class FixtureTests: XCTestCase { static func testSelected() {} }",
            "multiline static": "class FixtureTests: XCTestCase {\n static\n\n func testSelected() {} }",
            "class method": "class FixtureTests: XCTestCase { class func testSelected() {} }",
            "private": "class FixtureTests: XCTestCase { private func testSelected() {} }",
            "return value": "class FixtureTests: XCTestCase { func testSelected() -> Int { 1 } }",
            "generic": "class FixtureTests: XCTestCase { func testSelected<T>() {} }",
            "not XCTest": "class FixtureTests { func testSelected() {} }",
            "unknown base": "class FixtureTests: MissingBase { func testSelected() {} }",
            "shadowed XCTest class": "class XCTestCase {}\nclass FixtureTests: XCTestCase { func testSelected() {} }",
            "shadowed XCTest alias": "typealias XCTestCase = Fake\nclass FixtureTests: XCTestCase { func testSelected() {} }",
            "shadowed XCTest module": "struct XCTest {}\nclass FixtureTests: XCTest.XCTestCase { func testSelected() {} }",
            "non XCTest base": "class Base {}\nclass FixtureTests: Base { func testSelected() {} }",
            "inheritance cycle": "class Base: FixtureTests {}\nclass FixtureTests: Base { func testSelected() {} }",
            "nested class": "struct Owner { class FixtureTests: XCTestCase { func testSelected() {} } }",
            "private extension": "class FixtureTests: XCTestCase {}\nprivate extension FixtureTests { func testSelected() {} }",
            "conditional extension": "class FixtureTests: XCTestCase {}\nextension FixtureTests where Element: Equatable { func testSelected() {} }",
            "availability": "class FixtureTests: XCTestCase {\n @available(iOS 99, *)\n func testSelected() {} }",
        }
        for label, source in invalid.items():
            with self.subTest(label=label), self.assertRaises(generator.ManifestError):
                self.generate_source_case(source)
        valid = [
            "class FixtureTests: XCTestCase { func testSelected() {} }",
            "final class FixtureTests: XCTestCase {\n @MainActor\n func testSelected() async throws {} }",
            "class FixtureTests: XCTestCase {}\nextension FixtureTests { func testSelected() throws {} }",
            "class Base: XCTestCase {}\nclass FixtureTests: Base { func testSelected() {} }",
            "class FixtureTests: XCTest.XCTestCase { func testSelected()\n async throws {} }",
        ]
        for source in valid:
            with self.subTest(source=source):
                self.assertEqual(self.generate_source_case(source)[2]["selectorCount"], 1)

    def test_closed_debug_simulator_conditions_and_masked_noncode(self):
        method = "func testSelected() {}"
        for condition in ("false", "SWIFT_PACKAGE"):
            source = "class FixtureTests: XCTestCase {\n#if " + condition + "\n" + method + "\n#endif\n}"
            with self.subTest(condition=condition), self.assertRaises(generator.ManifestError):
                self.generate_source_case(source)
        for directives in (
            "#if UNKNOWN\n" + method + "\n#endif",
            "#if DEBUG\n" + method,
            "#else\n" + method,
            "#if DEBUG\n#else\n#else\n" + method + "\n#endif",
            "#if false\n#if UNKNOWN\n#endif\n#else\n" + method + "\n#endif",
        ):
            with self.subTest(directives=directives), self.assertRaises(generator.ManifestError):
                self.generate_source_case("class FixtureTests: XCTestCase {\n" + directives + "\n}")
        for directives in (
            "#if DEBUG\n" + method + "\n#endif",
            "#if DEBUG && os(iOS) && targetEnvironment(simulator)\n" + method + "\n#endif",
            "#if SWIFT_PACKAGE\nfunc helper() {}\n#else\n" + method + "\n#endif",
            "#if SWIFT_PACKAGE\nfunc helper() {}\n#elseif DEBUG\n" + method + "\n#else\nfunc other() {}\n#endif",
            "#if DEBUG\n#if SWIFT_PACKAGE\nfunc helper() {}\n#else\n" + method + "\n#endif\n#endif",
        ):
            with self.subTest(directives=directives):
                self.assertEqual(self.generate_source_case("class FixtureTests: XCTestCase {\n" + directives + "\n}")[2]["selectorCount"], 1)
        fake = 'func testSelected() {}'
        noncode = [
            '// ' + fake,
            '/* outer /* nested */ ' + fake + ' */',
            'let value = "' + fake + '"',
            'let value = #"escaped \\#" ' + fake + '"#',
            'let value = """\n' + fake + '\n"""',
            'let value = ##"""\n' + fake + '\n"""##',
        ]
        for hidden in noncode:
            with self.subTest(hidden=hidden):
                with self.assertRaises(generator.ManifestError):
                    self.generate_source_case("class FixtureTests: XCTestCase {\n" + hidden + "\n}")
                self.assertEqual(self.generate_source_case("class FixtureTests: XCTestCase {\n" + hidden + "\n" + method + "\n}")[2]["selectorCount"], 1)


if __name__ == "__main__":
    unittest.main()
