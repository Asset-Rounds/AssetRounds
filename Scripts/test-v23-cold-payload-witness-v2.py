#!/usr/bin/env python3
"""Synthetic cold payload behavior tests; no native, original, or qualification credit.

Root may select a private candidate with V23_COLD_PAYLOAD_NATIVE_SOURCE and its
exact Source root with V23_COLD_PAYLOAD_TEST_SOURCE_ROOT. The finite fixture is
also reusable by the retained-reader behavior tests; it never mocks the witness
producer or retained validator. The only producer-build mock names synthetic
compiler facts, and the compatibility stub names synthetic product bytes.
"""
import copy
import gzip
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest import mock


ROOT = Path(os.environ.get("V23_COLD_PAYLOAD_TEST_SOURCE_ROOT", Path(__file__).resolve().parents[1])).resolve()
NATIVE = Path(os.environ.get("V23_COLD_PAYLOAD_NATIVE_SOURCE", ROOT / "Scripts/v23-native-ci.py"))
SPEC = importlib.util.spec_from_file_location("cold_payload_native_ci", NATIVE)
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)
HEAD, TREE = "1" * 40, "2" * 40
UDID = "00000000-0000-0000-0000-000000000001"


def make_cold_payload_fixture(base, ci=CI, source_root=ROOT, *, finish=True, product_writer=None):
    """Real archive, restore and witness pipeline with explicitly synthetic build facts.

    Returns {producer, consumer, binding, kernel}; each worker contains its
    environment/record/artifact/selection. With finish=False the consumer has
    restore/before witnesses only, allowing a hostile live after observation.
    Test-only API event/Git facts are supplied at the real context admission.
    Optional product_writer(products, xctestrun) writes finite synthetic valid
    product bytes and mutates the original xctestrun dictionary before sealing;
    with that seam supplied, actual kernel compatibility is never substituted.
    """
    source_root, base = Path(source_root).resolve(), Path(base).resolve()
    baseline_spec = importlib.util.spec_from_file_location("cold_payload_test_baseline",
                                                          source_root / "Scripts/test-v23-native-ci.py")
    baseline = importlib.util.module_from_spec(baseline_spec)
    baseline_spec.loader.exec_module(baseline)
    gate = ci.load_phase1_gates(source_root)
    plan = ci.shared_selection(source_root)
    intent = gate.make_cold_plan(head=HEAD, tree=TREE, resolved_bytes=ci.canonical(plan),
        sources={path: gate.sha((source_root / path).read_bytes()) for path in gate.SOURCES},
        requested_at="2026-09-26T12:00:00Z")
    event = base / "original-event.json"
    event.write_bytes(ci.canonical({"repository": {"full_name": ci.REPOSITORY}, "ref": intent["ref"],
                                   "inputs": gate.cold_dispatch_inputs(intent)}))

    def git_facts(argv, **kwargs):
        if argv not in (["git", "rev-parse", "HEAD"], ["git", "rev-parse", "HEAD^{tree}"]):
            raise AssertionError("unexpected synthetic Git question")
        if kwargs.get("cwd") != source_root or kwargs.get("text") is not True:
            raise AssertionError("synthetic Git Source binding")
        return (HEAD if argv[-1] == "HEAD" else TREE) + "\n"

    def worker(label, role, partition=""):
        temp = base / label
        temp.mkdir()
        artifact = temp / "FieldEvidenceCI"
        artifact.mkdir()
        e = dict(baseline.environment(), NATIVE_SELECTION_ID=gate.COLD_SELECTION,
            DISPATCH_NATIVE_SELECTION_ID=gate.COLD_SELECTION, GITHUB_REF=gate.INTEGRATION_REF,
            GITHUB_WORKFLOW_SHA=HEAD, GITHUB_EVENT_PATH=str(event),
            GITHUB_WORKFLOW_REF=ci.REPOSITORY + "/" + gate.ROUTE["workflow"] + "@" + gate.INTEGRATION_REF,
            V23_SHARED_ROLE=role, V23_PARTITION_ID=partition,
            V23_PAYLOAD_ARTIFACT_NAME="v23-shared-payload-123-1-" + HEAD,
            SHARED_UI="false", DISPATCH_RUN_UI_SMOKE="false", RUNNER_TEMP=str(temp),
            CI_ARTIFACT_DIR=str(artifact), PROJECT_PATH="FieldEvidenceApp.xcodeproj", SCHEME="FieldEvidenceApp",
            CONFIGURATION="Debug", CODE_SIGNING_ALLOWED="NO", CI_SIMULATOR_UDID=UDID,
            CI_DESTINATION="platform=iOS Simulator,id=" + UDID)
        selected, selection_record = ci.selected_input(source_root, e)
        e.update(DISPATCH_NATIVE_SELECTION_SHA256=selection_record[ci.SHARED_KEY]["planSHA256"],
                 DISPATCH_NATIVE_SELECTION_MAP_SHA256=selection_record["selectionMapSHA256"])
        with mock.patch.object(ci.subprocess, "check_output", side_effect=git_facts):
            record = ci.admission(selected, e, HEAD, "worker", selection_record, source_root)
        record.update(ci.source_binding(source_root))
        record["gitTree"] = TREE
        (artifact / "native-admission.json").write_bytes(ci.canonical(record))
        (artifact / "xcode-version.txt").write_text("Xcode 26.6\nBuild version 17F113\n")
        (artifact / "native-sdk.txt").write_text("sdk=iphonesimulator\nversion=26.5\nbuild=23F81a\n")
        return {"environment": e, "record": record, "artifact": artifact, "selection": selected}

    kernel = dict(ci.load_payload_kernel(source_root))
    if product_writer is None:
        kernel["product_compatibility"] = lambda products, xctestrun: [
            {"path": "Debug-iphonesimulator/FieldEvidenceApp.app/FieldEvidenceApp", "fixture": True}]
    producer = worker("producer", "producer")
    temp = Path(producer["environment"]["RUNNER_TEMP"])
    products = temp / "FieldEvidenceDerivedData/Build/Products"
    app = products / "Debug-iphonesimulator/FieldEvidenceApp.app"
    (app / "PlugIns/FieldEvidenceAppTests.xctest").mkdir(parents=True)
    (app / "FieldEvidenceApp").write_bytes(b"test-only synthetic executable; not native")
    (app / "Info.plist").write_bytes(b"test-only synthetic plist")
    (app / "PlugIns/FieldEvidenceAppTests.xctest/FieldEvidenceAppTests").write_bytes(b"synthetic test bundle")
    xctestrun = copy.deepcopy(baseline.SHARED_XCTESTRUN)
    # Exercise the real normalization, not an identity stub.
    xctestrun["FieldEvidenceAppTests"]["TestHostPath"] = str(app)
    if product_writer is not None:
        product_writer(products, xctestrun)
    with (products / "FieldEvidenceApp_iphonesimulator26.5-arm64.xctestrun").open("wb") as stream:
        plistlib.dump(xctestrun, stream)
    (producer["artifact"] / "build-smoke.log").write_text("test-only synthetic build log\n")
    with mock.patch.object(ci.subprocess, "check_output", side_effect=git_facts), \
            mock.patch.object(ci.platform, "machine", return_value="arm64"), \
            mock.patch.object(ci, "verify_no_index_build", return_value={
                "commandReceiptSHA256": ci.sha256(ci.canonical({"fixture": "not a native build"}))}):
        ci.shared_seal(source_root, producer["artifact"], producer["record"], producer["environment"], kernel)
    consumer = worker("consumer", "consumer", plan[ci.SHARED_KEY]["partitionIDs"][0])
    consumer_temp = Path(consumer["environment"]["RUNNER_TEMP"])
    download = consumer_temp / ci.SHARED_DOWNLOAD_DIRECTORY
    download.mkdir()
    for name in (ci.SHARED_TAR, ci.SHARED_TAR_DIGEST):
        shutil.copyfile(temp / ci.SHARED_TRANSPORT_DIRECTORY / name, download / name)
    with mock.patch.object(ci.subprocess, "check_output", side_effect=git_facts), \
            mock.patch.object(ci.platform, "machine", return_value="arm64"):
        ci.shared_restore(source_root, consumer["artifact"], consumer["record"], consumer["environment"], kernel)
        ci.shared_fingerprint(source_root, consumer["artifact"], consumer["record"], consumer["environment"], "before", kernel)
        if finish:
            log = consumer_temp / "FieldEvidenceDerivedData/Logs/Build/bookkeeping.xcactivitylog"
            log.parent.mkdir(parents=True)
            log.write_bytes(gzip.compress(b"test session bookkeeping only"))
            (consumer["artifact"] / "test-smoke.log").write_text("** TEST EXECUTE SUCCEEDED **\n")
            ci.shared_fingerprint(source_root, consumer["artifact"], consumer["record"], consumer["environment"], "after", kernel)
    return {"producer": producer, "consumer": consumer, "binding": producer["record"]["coldOriginal"],
            "kernel": kernel, "git_facts": git_facts}


class ColdPayloadWitnessV2Tests(unittest.TestCase):
    def test_v2_writer_keeps_first_body_object_and_separate_secondary_close_once(self):
        for stage in ("write", "fsync"):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary).resolve() / "partial-original"
                raw, retained = b"complete intended witness", {}
                first = OSError("test-only first " + stage + " failure")
                secondary = OSError("test-only secondary close failure")
                actual_write, actual_fsync, actual_close = CI.os.write, CI.os.fsync, CI.os.close
                def write(descriptor, value):
                    if stage == "write":
                        actual_write(descriptor, value[:3])
                        raise first
                    return actual_write(descriptor, value)
                def sync(descriptor):
                    if stage == "fsync": raise first
                    return actual_fsync(descriptor)
                def close(descriptor):
                    actual_close(descriptor)
                    raise secondary
                with mock.patch.object(CI.os, "write", side_effect=write) as writes, \
                        mock.patch.object(CI.os, "fsync", side_effect=sync) as syncs, \
                        mock.patch.object(CI.os, "close", side_effect=close) as closes:
                    with self.assertRaises(OSError) as caught:
                        CI._cold_payload_write_v2(path, raw, retained)
                self.assertIs(caught.exception, first)
                self.assertIs(retained["firstError"], first)
                self.assertIs(retained["secondaryErrors"][0], secondary)
                self.assertIs(first.cold_payload_write_io_v2, retained)
                self.assertEqual(writes.call_count, 1)
                self.assertEqual(syncs.call_count, int(stage == "fsync"))
                self.assertEqual(closes.call_count, 1)
                self.assertTrue(retained["openReturned"] and retained["closeEntered"] and retained["closeUncertain"])
                self.assertFalse(retained["closeReturned"])
                self.assertEqual(path.read_bytes(), raw[:3] if stage == "write" else raw)
                with self.assertRaises(FileExistsError): CI._cold_payload_write_v2(path, raw)
                self.assertEqual(path.read_bytes(), raw[:3] if stage == "write" else raw)

    def test_v2_writer_success_and_successful_body_failed_close_never_claim_close(self):
        for close_result in ("success", "raises", "non-none"):
            with self.subTest(close_result=close_result), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary).resolve() / "original"
                raw, retained = b"complete intended witness", {}
                error = OSError("test-only close failure after successful body")
                actual_close = CI.os.close
                def close(descriptor):
                    result = actual_close(descriptor)
                    if close_result == "raises": raise error
                    return 0 if close_result == "non-none" else result
                with mock.patch.object(CI.os, "close", side_effect=close) as closes:
                    if close_result == "success":
                        result = CI._cold_payload_write_v2(path, raw, retained)
                        self.assertIs(result, retained)
                    else:
                        with self.assertRaises(OSError if close_result == "raises" else ValueError) as caught:
                            CI._cold_payload_write_v2(path, raw, retained)
                        self.assertIs(caught.exception, retained["firstError"])
                        if close_result == "raises": self.assertIs(caught.exception, error)
                self.assertEqual(closes.call_count, 1)
                self.assertTrue(retained["writeReturned"] and retained["fsyncReturned"] and retained["closeEntered"])
                self.assertEqual(retained["closeReturned"], close_result == "success")
                self.assertEqual(retained["closeUncertain"], close_result != "success")
                self.assertIs(retained["closeActualReturn"], None if close_result != "non-none" else 0)
                self.assertEqual(retained["secondaryErrors"], [])
                self.assertEqual(path.read_bytes(), raw)

    def facts(self, fixture, role="consumer"):
        worker = fixture[role]
        return CI.cold_retained_shared_facts_v2(ROOT, worker["artifact"], worker["record"], fixture["binding"])

    def witness_path(self, worker, stage):
        return worker["artifact"] / (CI.COLD_PAYLOAD_WITNESS_PREFIX_V2 + stage + "-v2.json")

    def rewrite(self, path, change):
        value = json.loads(path.read_bytes())
        change(value)
        path.write_bytes(CI.canonical(value))

    def test_valid_real_pipeline_retains_normalization_logs_and_v1_pending_scopes(self):
        with tempfile.TemporaryDirectory() as temporary:
            fixture = make_cold_payload_fixture(Path(temporary).resolve())
            protocol = CI.source_binding(ROOT)
            for role in ("producer", "consumer"):
                self.assertEqual({key: fixture[role]["record"].get(key) for key in protocol}, protocol)
            producer, consumer = self.facts(fixture, "producer"), self.facts(fixture)
            seal = producer["observations"]["seal"]
            self.assertEqual(seal["normalization"]["changedProductPaths"], [seal["products"]["xctestrunPath"]])
            self.assertNotEqual(seal["sourceProductInventory"], seal["productInventory"])
            self.assertEqual(seal["productInventory"], consumer["observations"]["restore"]["productInventory"])
            after = consumer["observations"]["after"]
            self.assertEqual(len(after["activityLogs"]), 1)
            retained = fixture["consumer"]["artifact"] / CI.COLD_ACTIVITY_DIRECTORY_V2 / "000000.xcactivitylog"
            self.assertEqual(CI.sha256(retained.read_bytes()), after["activityLogs"][0]["sha256"])
            for role, facts in (("producer", producer), ("consumer", consumer)):
                self.assertEqual(facts["status"], "COMPLETE_RETAINED_COLD_PAYLOAD_OBSERVATIONS")
                self.assertEqual((facts["functionalQualification"], facts["processLifetimes"], facts["emittedTransport"]),
                                 ("PENDING", "PENDING", "PENDING"))
                for key in ("providerQualification", "acceptance", "releaseReady"):
                    self.assertIs(facts[key], False)
                for stage in facts["observations"]:
                    v1 = CI.read_json(fixture[role]["artifact"] / ("cold-shared-observation-" + stage + ".json"))
                    self.assertEqual((v1["status"], v1["functionalQualification"], v1["processLifetimes"]),
                                     ("INCOMPLETE", "PENDING", "PENDING"))
                    self.assertEqual(v1["schema"], "v23-cold-shared-live-observation.v1")

    def test_relocated_retained_facts_need_no_live_source_products_or_payload(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary).resolve()
            fixture = make_cold_payload_fixture(base)
            expected = self.facts(fixture)
            retained = base / "retained"
            shutil.copytree(fixture["consumer"]["artifact"], retained)
            shutil.rmtree(Path(fixture["consumer"]["environment"]["RUNNER_TEMP"]))
            worker = fixture["consumer"]
            observed = CI.cold_retained_shared_facts_v2(ROOT, retained, worker["record"], fixture["binding"])
            self.assertEqual(observed, expected)
            self.assertIs(observed["payloadArchiveRetained"], False)
            self.assertIs(observed["liveChecksIndependentlyReexecuted"], False)

    def test_missing_truncated_and_extra_sidecar_keys_refuse(self):
        for variant in ("missing", "truncated", "extra", "products-truncated", "dd-truncated"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                fixture = make_cold_payload_fixture(Path(temporary).resolve())
                worker = fixture["consumer"]
                path = self.witness_path(worker, "after")
                if variant == "missing": path.unlink()
                elif variant == "truncated": path.write_bytes(path.read_bytes()[:-2])
                elif variant == "extra": self.rewrite(path, lambda value: value.update(extra=True))
                elif variant == "products-truncated": self.rewrite(path, lambda value: value["productInventory"].pop())
                else: self.rewrite(path, lambda value: value["derivedDataInventory"].pop())
                with self.assertRaises((OSError, ValueError)):
                    self.facts(fixture)

    def test_wrong_original_context_role_source_and_admission_refuse(self):
        for field, replacement in (("originalEventSHA256", "A" * 64), ("eventBindingSHA256", "B" * 64),
                                   ("admissionSHA256", "C" * 64), ("head", "3" * 40),
                                   ("partitionID", "S99"), ("role", "producer"), ("runAttempt", "2"),
                                   ("executionScope", "phase1-functional-gate"), ("sourceSHA256", {})):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary:
                fixture = make_cold_payload_fixture(Path(temporary).resolve())
                self.rewrite(self.witness_path(fixture["consumer"], "restore"),
                             lambda value: value.update({field: replacement}))
                with self.assertRaises(ValueError): self.facts(fixture)
        with tempfile.TemporaryDirectory() as temporary:
            fixture = make_cold_payload_fixture(Path(temporary).resolve())
            worker = fixture["consumer"]
            stale = copy.deepcopy(worker["record"])
            stale["protocolSHA256"] = "0" * 64
            (worker["artifact"] / "native-admission.json").write_bytes(CI.canonical(stale))
            with self.assertRaisesRegex(ValueError, "cold payload admitted protocol Source"):
                CI.cold_retained_shared_facts_v2(ROOT, worker["artifact"], stale, fixture["binding"])
            (worker["artifact"] / "native-admission.json").write_bytes(b"{}\n")
            with self.assertRaises(ValueError): self.facts(fixture)

    def test_raw_activity_missing_truncated_compile_corrupt_symlink_and_extra_refuse(self):
        for variant in ("missing", "truncated", "compile", "corrupt", "symlink", "extra"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                fixture = make_cold_payload_fixture(Path(temporary).resolve())
                worker = fixture["consumer"]
                directory = worker["artifact"] / CI.COLD_ACTIVITY_DIRECTORY_V2
                path = directory / "000000.xcactivitylog"
                if variant == "missing": path.unlink()
                elif variant == "truncated": path.write_bytes(path.read_bytes()[:-3])
                elif variant == "compile": path.write_bytes(gzip.compress(b"CompileSwiftSources compile task"))
                elif variant == "corrupt": path.write_bytes(b"not a gzip activity log")
                elif variant == "extra": (directory / "unlisted.xcactivitylog").write_bytes(b"extra")
                else:
                    raw = path.read_bytes(); path.unlink()
                    target = directory.parent / "alias.xcactivitylog"; target.write_bytes(raw); path.symlink_to(target)
                with self.assertRaises((OSError, ValueError)): self.facts(fixture)

    def test_coherent_retained_dd_compile_output_and_compile_log_refuse(self):
        for variant in ("dd-output", "test-log", "local-build"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                fixture = make_cold_payload_fixture(Path(temporary).resolve())
                worker = fixture["consumer"]
                if variant == "test-log":
                    (worker["artifact"] / "test-smoke.log").write_text("CompileSwiftSources actual rebuild\n")
                elif variant == "local-build":
                    (worker["artifact"] / "Build.xcresult").mkdir()
                else:
                    path = self.witness_path(worker, "after")
                    value = CI.read_json(path)
                    entry = {"path": "Build/Intermediates.noindex/rebuilt.o", "type": "file", "size": 1,
                             "sha256": CI.sha256(b"x")}
                    value["derivedDataInventory"].append(entry)
                    value["derivedDataInventory"].sort(key=lambda item: item["path"])
                    before = CI.read_json(self.witness_path(worker, "before"))["derivedDataInventory"]
                    old = {item["path"]: {k: v for k, v in item.items() if k != "path"} for item in before}
                    new = {item["path"]: {k: v for k, v in item.items() if k != "path"}
                           for item in value["derivedDataInventory"]}
                    delta_path = worker["artifact"] / CI.SHARED_DERIVED_DATA_DELTA
                    delta = CI.read_json(delta_path)
                    delta.update(CI.shared_derived_delta(old, new), afterEntryCount=len(new))
                    delta_path.write_bytes(CI.canonical(delta))
                    fingerprint_path = worker["artifact"] / "v23-shared-fingerprint-after.json"
                    fingerprint = CI.read_json(fingerprint_path)
                    fingerprint["derivedDataDelta"].update(sha256=CI.sha256(delta_path.read_bytes()),
                                                         addedCount=delta["addedCount"])
                    fingerprint_path.write_bytes(CI.canonical(fingerprint))
                    value["fingerprintSHA256"] = CI.sha256(fingerprint_path.read_bytes())
                    path.write_bytes(CI.canonical(value))
                with self.assertRaises(ValueError): self.facts(fixture)

    def test_changed_products_unsafe_alias_archive_census_and_normalization_refuse(self):
        for variant in ("changed-products", "unsafe-path", "case-alias", "missing-member", "source-product"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                fixture = make_cold_payload_fixture(Path(temporary).resolve())
                role = "producer" if variant == "source-product" else "consumer"
                stage = "seal" if role == "producer" else "restore"
                path = self.witness_path(fixture[role], stage)
                def change(value):
                    if variant == "changed-products": value["products"]["treeSHA256"] = "A" * 64
                    elif variant == "unsafe-path": value["archiveMemberCensus"][0]["path"] = "../escape"
                    elif variant == "case-alias":
                        item = copy.deepcopy(value["archiveMemberCensus"][0]); item["path"] = item["path"].upper()
                        value["archiveMemberCensus"].append(item)
                        value["archiveMemberCensus"].sort(key=lambda item: item["path"])
                    elif variant == "missing-member": value["archiveMemberCensus"].pop()
                    else:
                        entry = next(item for item in value["sourceProductInventory"]
                                     if item["type"] == "file" and not item["path"].endswith(".xctestrun"))
                        entry["sha256"] = "A" * 64
                        value["sourceBeforeProductInventorySHA256"] = CI.sha256(CI.canonical(value["sourceProductInventory"]))
                self.rewrite(path, change)
                with self.assertRaises(ValueError): self.facts(fixture, role)

    def test_live_products_change_compile_output_and_activity_compile_refuse(self):
        for variant in ("products", "dd-output", "activity"):
            with self.subTest(variant=variant), tempfile.TemporaryDirectory() as temporary:
                fixture = make_cold_payload_fixture(Path(temporary).resolve(), finish=False)
                worker = fixture["consumer"]
                derived = Path(worker["environment"]["RUNNER_TEMP"]) / "FieldEvidenceDerivedData"
                (worker["artifact"] / "test-smoke.log").write_text("** TEST EXECUTE SUCCEEDED **\n")
                if variant == "products":
                    (derived / "Build/Products/Debug-iphonesimulator/FieldEvidenceApp.app/FieldEvidenceApp").write_bytes(b"changed")
                elif variant == "dd-output":
                    path = derived / "Build/Intermediates.noindex/rebuilt.o"
                    path.parent.mkdir(parents=True); path.write_bytes(b"compiled")
                else:
                    path = derived / "Logs/Build/rebuild.xcactivitylog"
                    task = b"SwiftCompile normal arm64 /w/A.swift"
                    activity = b'SLF010#' + b'%d"%s' % (len(task), task)
                    path.parent.mkdir(parents=True)
                    path.write_bytes(gzip.compress(activity, mtime=0))
                    self.assertEqual(CI.shared_activity_log_compile_step(path), "SwiftCompile step")
                with mock.patch.object(CI.subprocess, "check_output", side_effect=fixture["git_facts"]), \
                        mock.patch.object(CI.platform, "machine", return_value="arm64"), self.assertRaises(ValueError):
                    CI.shared_fingerprint(ROOT, worker["artifact"], worker["record"], worker["environment"], "after", fixture["kernel"])
                self.assertFalse(self.witness_path(worker, "after").exists())


if __name__ == "__main__":
    unittest.main()
