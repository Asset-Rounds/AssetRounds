"""Synthetic V2 byte/behavior fixtures, never an authentic hosted original.

Root runs this Source only after composing the four executable literal pins.
Real Gate/Native/kernel APIs parse, seal, safely restore and join finite products.
Synthetic command/compiler lines are disclosed inputs; no native command runs.
Emitted transport, provider authentication, human review and all gates stay due.
"""
import copy
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import stat
import struct
import tarfile
import tempfile
from types import ModuleType
import unittest
from unittest import mock
import zipfile


def source_root():
    explicit = os.environ.get("V23_RETAINED_PAYLOAD_SOURCE_ROOT")
    if explicit:
        return Path(explicit).resolve()
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/v23-native-ci.py").is_file():
            return parent
    raise RuntimeError("Set V23_RETAINED_PAYLOAD_SOURCE_ROOT to the exact composed Source checkout")


def source_frame(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns, getattr(info, "st_flags", 0))


def source_raw(path):
    """Fixture loader FULL10 is separate from the reader's inherited nine fields."""
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or getattr(before, "st_flags", 0) & 0x40000000:
        raise RuntimeError("fixture Source must be a materialized regular singleton")
    descriptor, primary, raw = None, None, bytearray()
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        if source_frame(os.fstat(descriptor)) != source_frame(before):
            raise RuntimeError("fixture Source held endpoint changed")
        while True:
            block = os.read(descriptor, 1024 * 1024)
            if not block:
                break
            raw.extend(block)
            if len(raw) > 4 * 1024 * 1024:
                raise RuntimeError("fixture Source first-excess bound")
        if len(raw) != before.st_size or os.lseek(descriptor, 0, os.SEEK_CUR) != before.st_size:
            raise RuntimeError("fixture Source size/cursor differs")
    except BaseException as error:
        primary = error
    secondary = []
    try:
        if source_frame(path.lstat()) != source_frame(before) or (descriptor is not None
                and source_frame(os.fstat(descriptor)) != source_frame(before)):
            raise RuntimeError("fixture Source final endpoint changed")
    except BaseException as error:
        secondary.append(error)
    if descriptor is not None:
        try:
            if os.close(descriptor) is not None:
                raise RuntimeError("fixture Source close must return None")
        except BaseException as error:
            secondary.append(error)
    if primary is None and secondary:
        primary = secondary.pop(0)
    if primary is not None:
        for error in secondary:
            primary.add_note("secondary fixture Source endpoint/close: " + repr(error))
        raise primary
    return bytes(raw), source_frame(before)


def load_target():
    path = Path(os.environ.get("V23_PHASE1_RETAINED_READER_SOURCE",
                               str(source_root() / "Scripts/dev/v23-retained-payload.py"))).resolve()
    raw, frame = source_raw(path)
    expected = os.environ.get("V23_PHASE1_RETAINED_READER_SHA256")
    if expected is not None and (re.fullmatch(r"[0-9a-f]{64}", expected) is None
                                 or hashlib.sha256(raw).hexdigest() != expected):
        raise RuntimeError("fixture Reader raw pin differs from Root-selected Source")
    module = ModuleType("phase1_retained_reader_v2_candidate")
    module.__file__ = str(path)
    primary = None
    try:
        exec(compile(raw, str(path), "exec"), module.__dict__)
    except BaseException as error:
        primary = error
    try:
        after, current = source_raw(path)
        if after != raw or current != frame:
            raise RuntimeError("fixture Reader Source changed after definition load")
    except BaseException as error:
        if primary is None:
            primary = error
        else:
            primary.add_note("secondary fixture Reader after-definition Source: " + repr(error))
    if primary is not None:
        raise primary
    return module


M = load_target()


def macho(filetype, *, cpu=0x0100000C, sdk=(26 << 16) | (5 << 8)):
    """Finite mechanically valid arm64 Simulator header; no compiled app claim."""
    return (b"\xcf\xfa\xed\xfe" + struct.pack("<7I", cpu, 0, filetype, 1, 24, 0, 0)
            + struct.pack("<6I", 0x32, 24, 7, 18 << 16, sdk, 0))


def make_phase1_payload_workers_v2(base, *, root, ci, gate, kernel, plan, resolved, run_id=123, received_inputs=None,
                                  before_consumer_tests=None, after_consumer_tests=None):
    """Synthetic all-worker payload fixture through the real V2 stage producers.

    No Gate/Native/kernel/source/selection parser is mocked. These synthetic
    command/compiler lines satisfy real finite receipt guards as unit inputs,
    and do not claim actual compilation, hosted API origin or emitted transport.
    Optional UNIT callbacks run once per consumer after real before
    fingerprint, then after synthetic test log birth and before real after
    fingerprint. Default None preserves all incumbent setup ordering.
    Return the actual producer transport and retained worker directories.
    """
    base, root = Path(base).resolve(), Path(root).resolve()
    base.mkdir(mode=0o700)
    workers = base / "retained-workers"
    workers.mkdir(mode=0o700)
    runtime = base / "synthetic-worker-runtimes"
    runtime.mkdir(mode=0o700)
    event = {"inputs": gate["dispatch_inputs_v2"](plan), "ref": plan["ref"],
             "repository": {"full_name": plan["route"]["repository"]}}
    if received_inputs is not None:
        event["inputs"] = copy.deepcopy(received_inputs)  # Synthetic received bytes, before actual binding/admission/stages.
    event_raw = M.canonical(event)
    environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": plan["route"]["repository"],
        "GITHUB_REF": plan["ref"], "GITHUB_SHA": plan["head"], "GITHUB_RUN_ID": str(run_id), "GITHUB_RUN_ATTEMPT": "1",
        "GITHUB_WORKFLOW_REF": plan["route"]["repository"] + "/" + plan["route"]["workflow"] + "@" + plan["ref"],
        "GITHUB_WORKFLOW_SHA": plan["head"]}
    binding = gate["bind_original_event_v2"](event_raw, environment, head=plan["head"], tree=plan["tree"],
        resolved_bytes=ci["canonical"](resolved), sources=plan["sources"])
    protocol = ci["source_binding"](root)
    udid = "11111111-2222-3333-4444-555555555555"
    records, members = {}, {}
    def worker(label):
        temp, artifact = runtime / label, workers / label
        temp.mkdir(mode=0o700); artifact.mkdir(mode=0o700)
        selected = resolved if label == "producer" else ci["shared_selection"](root, label)
        record = {"repository": plan["route"]["repository"], "head": plan["head"], "gitTree": plan["tree"],
            "ref": plan["ref"], "runID": str(run_id), "runAttempt": "1", "selectionID": ci["SHARED_SELECTION_ID"],
            "selectionSHA256": M.sha(ci["canonical"](selected)), "phase1Gate": copy.deepcopy(binding),
            "diagnosticOnly": True, "providerQualification": False, "acceptance": False, "releaseReady": False,
            ci["SHARED_KEY"]: {"role": "producer" if label == "producer" else "consumer",
                "partitionID": None if label == "producer" else label,
                "payloadArtifactName": "v23-shared-payload-%d-1-%s" % (run_id, plan["head"]),
                "planSHA256": plan["selectionSHA256"],
                "partitionsSHA256": resolved[ci["SHARED_KEY"]]["partitionsSHA256"]}}
        record.update(protocol)  # Same actual main source-binding augmentation before admission serialization.
        for name, raw in (("native-admission.json", ci["canonical"](record)),
                          ("ci-selection.selected.json", ci["canonical"](selected)),
                          ("phase1-event-binding.json", gate["canonical"](binding)),
                          ("phase1-original-event.json", event_raw), ("phase1-gate-plan.json", gate["canonical"](plan))):
            (artifact / name).write_bytes(raw)
        (artifact / "xcode-version.txt").write_text("Xcode 26.6\nBuild version 17F113\n")
        (artifact / "native-sdk.txt").write_text("sdk=iphonesimulator\nversion=26.5\nbuild=23F81a\n")
        e = {"PROJECT_PATH": "FieldEvidenceApp.xcodeproj", "SCHEME": "FieldEvidenceApp", "CONFIGURATION": "Debug",
             "CODE_SIGNING_ALLOWED": "NO", "CI_SIMULATOR_UDID": udid, "CI_DESTINATION": "platform=iOS Simulator,id=" + udid,
             "CI_ARTIFACT_DIR": str(artifact), "RUNNER_TEMP": str(temp)}
        records[label] = record
        members[label] = {"artifact": artifact, "record": record, "environment": e,
                          "selected": selected, "runnerTemp": temp}
        return temp, artifact, record, e
    temp, artifact, record, e = worker("producer")
    products = temp / kernel["ROOT_LABEL"]
    products.mkdir(parents=True)
    for relative, filetype in (("FieldEvidenceApp.app/FieldEvidenceApp", 2),
                               ("FieldEvidenceAppTests.xctest/FieldEvidenceAppTests", 8),
                               ("FieldEvidenceAppUITests.xctest/FieldEvidenceAppUITests", 8)):
        path = products / relative
        path.parent.mkdir()
        path.write_bytes(macho(filetype)); path.chmod(0o755)
    settings = {target: {"TestHostPath": str(products / "FieldEvidenceApp.app/FieldEvidenceApp"),
                         "TestBundlePath": str(products / (target + ".xctest"))}
                for target in ("FieldEvidenceAppTests", "FieldEvidenceAppUITests")}
    (products / "Synthetic.xctestrun").write_bytes(plistlib.dumps(settings, sort_keys=True))
    receipt = ci["no_index_build_receipt"](root, artifact, record, e)
    (artifact / ci["NO_INDEX_RECEIPT"]).write_bytes(ci["canonical"](receipt))
    argv = ["/Applications/Xcode_26.6.app/Contents/Developer/usr/bin/xcodebuild", *receipt["argv"][1:]]
    (artifact / "build-smoke.log").write_text("Command line invocation:\n    " + shlex.join(argv)
        + "\nbuiltin-SwiftDriver -- /synthetic/swiftc -D" + ci["PHASE1_EMITTED_CONTEXT_DEFINE"]
        + "\n** TEST BUILD SUCCEEDED **\n")
    ci["shared_seal"](root, artifact, record, e, kernel)
    transport = temp / ci["SHARED_TRANSPORT_DIRECTORY"]
    for label in resolved[ci["SHARED_KEY"]]["partitionIDs"]:
        temp, artifact, record, e = worker(label)
        download = temp / ci["SHARED_DOWNLOAD_DIRECTORY"]
        download.mkdir(mode=0o700)
        for name in (ci["SHARED_TAR"], ci["SHARED_TAR_DIGEST"]):
            shutil.copyfile(transport / name, download / name)
        ci["shared_restore"](root, artifact, record, e, kernel)
        ci["shared_fingerprint"](root, artifact, record, e, "before", kernel)
        if before_consumer_tests is not None:
            before_consumer_tests(members[label])
        log = temp / "FieldEvidenceDerivedData/Logs/Build/bookkeeping.xcactivitylog"
        log.parent.mkdir(parents=True)
        log.write_bytes(gzip.compress(b"synthetic test session bookkeeping only", mtime=0))
        (artifact / "test-smoke.log").write_text("** TEST EXECUTE SUCCEEDED **\n")
        if after_consumer_tests is not None:
            after_consumer_tests(members[label])
        ci["shared_fingerprint"](root, artifact, record, e, "after", kernel)
    return {"workers": workers, "transport": transport, "binding": binding, "records": records, "members": members,
            "runtime": runtime, "root": root, "plan": plan, "resolved": resolved, "eventRaw": event_raw,
            "synthetic": True, "qualification": False, "emittedTransport": "PENDING"}
class Phase1RetainedPayloadV2BehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = source_root()
        cls.ci, cls.gate, cls.kernel = M.source_modules(cls.root)
        cls.sources = M.source_closure(cls.root, cls.gate)
        cls.resolved = cls.ci["shared_selection"](cls.root)
        cls.plan = cls.gate["make_plan_v2"](purpose=cls.gate["CANDIDATE"], head="1" * 40, tree="2" * 40,
            selection=cls.ci["SHARED_SELECTION_ID"], resolved_bytes=cls.ci["canonical"](cls.resolved),
            sources=cls.sources, requested_at="2026-10-05T12:00:00Z",
            cold_prerequisite={"runID": 17, "assessmentSHA256": "A" * 64,
                               "manifestSHA256": "B" * 64, "reviewSHA256": "C" * 64})

    def setUp(self):
        # All IDs and products here are synthetic DATA; no authentic original
        # or native execution is claimed by these finite fixtures.
        self.run_id = getattr(self, "run_id", 123)
        self.temp = tempfile.TemporaryDirectory(prefix="synthetic-retained-payload-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.payload = self.base / "synthetic-producer-payload"
        products = self.payload / self.kernel["ROOT_LABEL"]
        products.mkdir(parents=True)
        names = [("FieldEvidenceApp.app/FieldEvidenceApp", 2),
                 ("FieldEvidenceAppTests.xctest/FieldEvidenceAppTests", 8),
                 ("FieldEvidenceAppUITests.xctest/FieldEvidenceAppUITests", 8)]
        for relative, filetype in names:
            path = products / relative
            path.parent.mkdir()
            path.write_bytes(macho(filetype))
            path.chmod(0o755)
        settings = {target: {"TestHostPath": "__TESTROOT__/FieldEvidenceApp.app/FieldEvidenceApp",
                            "TestBundlePath": "__TESTROOT__/" + target + ".xctest"}
                    for target in ("FieldEvidenceAppTests", "FieldEvidenceAppUITests")}
        (products / "Synthetic.xctestrun").write_bytes(plistlib.dumps(settings, sort_keys=True))
        self.products = self.ci["shared_products_binding"](self.kernel, self.payload)
        self.metadata = {
            "schema": self.ci["SHARED_PAYLOAD_SCHEMA"], "routeID": self.ci["SHARED_SELECTION_ID"],
            "repository": self.plan["route"]["repository"], "ref": self.plan["ref"], "head": self.plan["head"],
            "gitTree": self.plan["tree"], "workspace": "/synthetic/original/workspace",
            "runID": str(self.run_id), "runAttempt": "1", "payloadArtifactName": "v23-shared-payload-%d-1-%s" % (self.run_id, self.plan["head"]),
            "planSHA256": M.sha(self.ci["canonical"](self.resolved)),
            "partitionsSHA256": self.resolved[self.ci["SHARED_KEY"]]["partitionsSHA256"],
            "toolchain": {"xcodeVersion": "Xcode 26.6", "xcodeBuild": "17F113", "sdkName": "iphonesimulator26.5",
                          "sdkBuild": "23F81a", "architecture": "arm64", "configuration": "Debug"},
            "developmentOnly": True, "acceptance": False, "buildCommandReceiptSHA256": "A" * 64,
            "buildLogSHA256": "B" * 64, "products": self.products,
        }
        (self.payload / M.METADATA).write_bytes(M.canonical(self.metadata))
        self.tar = self.base / M.TAR_NAME
        self.zip = self.base / "retained-original.zip"
        self.envelope_path = self.base / "retained-envelope.json"
        self.destination = self.base / "owned-recomputation"
        self.envelope = {"schema": M.PHASE1_INPUT_SCHEMA_V2, "plan": copy.deepcopy(self.plan), "runID": self.run_id, "runAttempt": 1,
                         "payloadArtifact": {"id": 456, "name": self.metadata["payloadArtifactName"],
                             "digest": "sha256:" + "0" * 64, "size_in_bytes": 987654, "expired": False,
                             "workflow_run": {"id": self.run_id, "head_sha": self.plan["head"],
                                              "head_branch": self.plan["ref"].removeprefix("refs/heads/")}}}
        self.rebuild_archive()

    def bind_outer(self):
        self.envelope["payloadArtifact"]["digest"] = "sha256:" + hashlib.sha256(self.zip.read_bytes()).hexdigest()
        self.envelope_path.write_bytes(M.canonical(self.envelope))

    def write_zip(self, members=None, digest=None):
        if digest is None:
            digest = ("%s %d %s\n" % (self.archive["sha256"], self.archive["bytes"], M.TAR_NAME)).encode("ascii")
        with zipfile.ZipFile(self.zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            if members is None:
                archive.write(self.tar, M.TAR_NAME)
                archive.writestr(M.DIGEST_NAME, digest)
            else:
                for name, raw in members:
                    archive.writestr(name, raw)
        self.bind_outer()

    def rebuild_archive(self):
        if self.tar.exists():
            self.tar.unlink()  # Synthetic test fixture only, never original evidence.
        self.archive = self.ci["shared_payload_archive"](self.kernel, self.payload, self.tar)
        self.write_zip()

    def run_helper(self, **kwargs):
        return M.recompute_phase1_retained_payload_v2(self.zip, self.envelope_path, self.root, self.destination, **kwargs)

    def refused(self, phrase, **kwargs):
        zip_before = self.zip.read_bytes()
        envelope_before = self.envelope_path.read_bytes()
        with self.assertRaisesRegex(M.Refused, phrase):
            self.run_helper(**kwargs)
        self.assertEqual(self.zip.read_bytes(), zip_before)
        self.assertEqual(self.envelope_path.read_bytes(), envelope_before)
        failure = json.loads((self.destination / "FAILURE.json").read_bytes())
        self.assertEqual(failure["status"], "REFUSED_PARTIAL_OWNED_DATA_RETAINED")
        self.assertTrue(failure["pendingProof"])
        self.assertEqual((self.destination / "payload.zip").read_bytes(), zip_before)
        self.assertFalse((self.destination / "FACTS.json").exists())
        return failure

    def use_workers(self):
        fixture = make_phase1_payload_workers_v2(self.base / "full-workers", root=self.root, ci=self.ci,
            gate=self.gate, kernel=self.kernel, plan=self.plan, resolved=self.resolved, run_id=self.run_id)
        self.tar = fixture["transport"] / M.TAR_NAME
        self.archive = {"name": M.TAR_NAME, "bytes": self.tar.stat().st_size,
                        "sha256": self.kernel["sha256_file"](self.tar)}
        self.metadata = M.decode((fixture["workers"] / "producer" / M.METADATA).read_bytes())
        self.products = self.metadata["products"]
        self.write_zip()
        return fixture

    def fresh_destination(self, label):
        self.destination = self.base / ("owned-" + label)


    def _received_input_plan(self, purpose):
        return self.gate["make_plan_v2"](purpose=purpose, head=self.plan["head"], tree=self.plan["tree"],
            selection=self.gate["SHARED"], resolved_bytes=self.ci["canonical"](self.resolved),
            sources=self.sources, requested_at=self.plan["requestedAtUTC"],
            cold_prerequisite=copy.deepcopy(self.plan["coldPrerequisite"]))

    def _use_received_input_workers(self, plan, received_inputs, label):
        fixture = make_phase1_payload_workers_v2(self.base / ("received-workers-" + label), root=self.root,
            ci=self.ci, gate=self.gate, kernel=self.kernel, plan=plan, resolved=self.resolved,
            run_id=self.run_id, received_inputs=received_inputs)
        self.envelope["plan"] = copy.deepcopy(plan)
        self.envelope["payloadArtifact"]["workflow_run"]["head_branch"] = plan["ref"].removeprefix("refs/heads/")
        self.tar = fixture["transport"] / M.TAR_NAME
        self.archive = {"name": M.TAR_NAME, "bytes": self.tar.stat().st_size,
                        "sha256": self.kernel["sha256_file"](self.tar)}
        self.metadata = M.decode((fixture["workers"] / "producer" / M.METADATA).read_bytes())
        self.products = self.metadata["products"]
        self.write_zip()
        self.fresh_destination("received-" + label)
        return fixture

    def _assert_received_input_pipeline(self, purpose):
        plan = self._received_input_plan(purpose)
        requested = self.gate["dispatch_inputs_v2"](plan)
        requested_raw = M.canonical(requested)
        omitted = ("s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids", "v23_cold_original_plan")
        self.assertEqual(len(requested), 13)
        self.assertTrue(all(requested[key] == "" for key in omitted))
        event_hashes = []
        for shape in ("COMPLETE_13", "OMITTED_EMPTY_DEFAULTS_10"):
            with self.subTest(purpose=purpose, shape=shape):
                received = copy.deepcopy(requested)
                if shape == "OMITTED_EMPTY_DEFAULTS_10":
                    for key in omitted:
                        del received[key]
                fixture = self._use_received_input_workers(plan, received, shape)
                self.assertEqual(self.gate["validate_received_inputs_v2"](received, plan), shape)
                self.assertEqual(M.canonical(self.gate["dispatch_inputs_v2"](plan)), requested_raw)
                self.assertEqual(M.decode(fixture["eventRaw"])["inputs"], received)
                self.assertEqual(len(received), 13 if shape == "COMPLETE_13" else 10)
                event_hashes.append(M.sha(fixture["eventRaw"]))
                originals = {label: (member["artifact"] / "phase1-original-event.json").read_bytes()
                             for label, member in fixture["members"].items()}
                zip_raw, envelope_raw = self.zip.read_bytes(), self.envelope_path.read_bytes()
                result = self.run_helper(retained_workers=fixture["workers"])
                self.assertEqual(result["workerJoins"]["status"], "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA")
                self.assertEqual(set(result["workerJoins"]["workers"]),
                                 {"producer", *self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"]})
                self.assertEqual(result["originalDATA"]["planSHA256"], M.sha(M.canonical(plan)))
                self.assertEqual(result["originalDATA"]["ref"], plan["ref"])
                self.assertEqual(fixture["binding"]["originalEventSHA256"], M.sha(fixture["eventRaw"]))
                for label, joined in result["workerJoins"]["workers"].items():
                    facts = joined["retainedFacts"]
                    self.assertEqual(facts["role"], "producer" if label == "producer" else "consumer")
                    self.assertEqual(facts["eventBindingSHA256"], M.sha(M.canonical(fixture["binding"])))
                    self.assertEqual(facts["functionalQualification"], self.gate["PENDING"])
                    self.assertIs(facts["acceptance"], False)
                    self.assertEqual((fixture["members"][label]["artifact"] / "phase1-original-event.json").read_bytes(),
                                     originals[label])
                    self.assertEqual(originals[label], fixture["eventRaw"])
                for key in ("executionAuthority", "authentication", "qualification", "providerQualification",
                            "acceptance", "releaseReady"):
                    self.assertIs(result["scope"][key], False)
                self.assertEqual(result["scope"]["emittedTransport"], "PENDING")
                self.assertTrue(result["pendingProof"])
                self.assertEqual(self.zip.read_bytes(), zip_raw)
                self.assertEqual(self.envelope_path.read_bytes(), envelope_raw)
                self.assertEqual((self.destination / "payload.zip").read_bytes(), zip_raw)
                self.assertEqual((self.destination / "input-envelope.json").read_bytes(), envelope_raw)
                self.assertEqual(M.decode((self.destination / "FACTS.json").read_bytes()), result)
                self.assertFalse((self.destination / "FAILURE.json").exists())
        self.assertNotEqual(event_hashes[0], event_hashes[1])

    def test_complete_and_omitted_received_shapes_recompute_candidate_all_workers(self):
        self._assert_received_input_pipeline(self.gate["CANDIDATE"])

    def test_complete_and_omitted_received_shapes_recompute_exact_main_all_workers(self):
        self._assert_received_input_pipeline(self.gate["EXACT_MAIN"])

    def test_partial_omission_nonempty_wrong_and_unknown_received_fields_refuse_real_pipeline(self):
        fixture = self.use_workers()
        artifact = fixture["members"]["producer"]["artifact"]
        event_path = artifact / "phase1-original-event.json"
        original_raw = event_path.read_bytes()
        original = M.decode(original_raw)
        requested = self.gate["dispatch_inputs_v2"](self.plan)
        omitted = ("s10_4_shared_payload_run_id", "s10_4_segment_source_run_ids", "v23_cold_original_plan")
        cases = []
        for index, key in enumerate(omitted):
            one = copy.deepcopy(requested); del one[key]
            two = copy.deepcopy(requested)
            for other in omitted:
                if other != key:
                    del two[other]
            cases.extend([("one-omitted-" + str(index), one), ("two-omitted-" + str(index), two)])
        nonempty = copy.deepcopy(requested); nonempty[omitted[0]] = "77"
        wrong_value = copy.deepcopy(requested); wrong_value["v23_d50_compiler_observation"] = "true"
        wrong_type = copy.deepcopy(requested); wrong_type["run_ui_smoke"] = False
        extra = copy.deepcopy(requested); extra["unexpected_native_key"] = "untrusted"
        missing = copy.deepcopy(requested); del missing["native_selection_id"]
        cases.extend([("nonempty-unused", nonempty), ("wrong-value", wrong_value),
                      ("wrong-type", wrong_type), ("extra-key", extra), ("missing-required", missing)])
        zip_raw, envelope_raw = self.zip.read_bytes(), self.envelope_path.read_bytes()
        try:
            for label, received in cases:
                with self.subTest(shape=label):
                    with self.assertRaises(self.gate["Refused"]):
                        self.gate["validate_received_inputs_v2"](received, self.plan)
                    event = copy.deepcopy(original); event["inputs"] = received
                    rejected_raw = M.canonical(event)
                    event_path.write_bytes(rejected_raw)
                    self.fresh_destination("received-refused-" + label)
                    genuine_source_modules = M.source_modules
                    source_invocations = []
                    def observe_source_modules(root):
                        modules = genuine_source_modules(root)
                        source_invocations.append((root, modules))
                        return modules  # Observe the actual fresh namespace; never substitute Source or validators.
                    with mock.patch.object(M, "source_modules", side_effect=observe_source_modules):
                        with self.assertRaises(M.Refused) as caught:
                            self.run_helper(retained_workers=fixture["workers"])
                    self.assertEqual(len(source_invocations), 1)
                    self.assertEqual(source_invocations[0][0], self.root)
                    pipeline_gate = source_invocations[0][1][1]
                    cause = caught.exception.__cause__
                    self.assertIs(type(cause), pipeline_gate["Refused"])
                    self.assertEqual(type(cause).__name__, "Refused")
                    failure = M.decode((self.destination / "FAILURE.json").read_bytes())
                    self.assertEqual(failure["errorType"], type(cause).__name__)
                    self.assertEqual(failure["reason"], str(cause)[:1000])
                    self.assertEqual(failure["stage"], "retained-worker-joins")
                    self.assertEqual(failure["status"], "REFUSED_PARTIAL_OWNED_DATA_RETAINED")
                    self.assertTrue(failure["pendingProof"])
                    self.assertFalse((self.destination / "FACTS.json").exists())
                    self.assertEqual(event_path.read_bytes(), rejected_raw)
                    self.assertEqual(self.zip.read_bytes(), zip_raw)
                    self.assertEqual(self.envelope_path.read_bytes(), envelope_raw)
                    self.assertEqual((self.destination / "payload.zip").read_bytes(), zip_raw)
                    self.assertEqual((self.destination / "input-envelope.json").read_bytes(), envelope_raw)
        finally:
            event_path.write_bytes(original_raw)

    def test_valid_closed_v2_payload_recomputes_real_bytes_with_zero_authority(self):
        result = self.run_helper()
        self.assertEqual(result["schema"], M.PHASE1_FACT_SCHEMA_V2)
        self.assertEqual(result["status"], "RECOMPUTED_PHASE1_RETAINED_PAYLOAD_DATA_ONLY_UNQUALIFIED")
        self.assertEqual(result["durability"]["status"], "FSYNCED_OWNED_DATA_PROJECTION")
        self.assertEqual(result["products"], self.products)
        self.assertEqual(result["archive"], self.archive)
        self.assertEqual(result["sourceSHA256"], self.sources)
        self.assertEqual(set(result["originalDATA"]), {"repository", "ref", "head", "tree", "runID", "runAttempt", "planSHA256"})
        self.assertEqual(result["originalDATA"]["planSHA256"], M.sha(M.canonical(self.plan)))
        self.assertEqual(result["outerZIP"]["sha256"], self.envelope["payloadArtifact"]["digest"][7:])
        self.assertEqual(result["envelopeSHA256"], M.sha(self.envelope_path.read_bytes()))
        self.assertEqual(result["workerJoins"]["status"], "PENDING_MISSING_RETAINED_WORKERS")
        self.assertEqual(result["workerJoins"]["requiredLabels"], ["producer"] + self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"])
        for key in ("executionAuthority", "authentication", "qualification", "providerQualification", "acceptance", "releaseReady"):
            self.assertIs(result["scope"][key], False)
        self.assertEqual(result["scope"]["emittedTransport"], "PENDING")
        self.assertEqual(result["scope"]["physicalProtection"], "UNVERIFIED/DEFERRED")
        self.assertTrue(result["scope"]["physicalProtectionReleaseBlocker"])
        self.assertEqual(result["unprovenClaims"], list(M.PHASE1_UNPROVEN_V2))
        self.assertTrue(result["pendingProof"])
        self.assertEqual(M.decode((self.destination / "FACTS.json").read_bytes()), result)

    def test_real_v2_producer_and_every_partition_join_recomputed_payload(self):
        fixture = self.use_workers()
        result = self.run_helper(retained_workers=fixture["workers"])
        joins = result["workerJoins"]
        self.assertEqual(joins["status"], "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA")
        self.assertEqual(set(joins["workers"]), {"producer", *self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"]})
        for label, joined in joins["workers"].items():
            with self.subTest(worker=label):
                facts = joined["retainedFacts"]
                self.assertEqual(facts["schema"], "v23-phase1-retained-shared-facts.v2")
                self.assertEqual(facts["status"], "COMPLETE_RETAINED_SHARED_OBSERVATIONS")
                self.assertEqual(facts["sourceSHA256"], self.sources)
                self.assertEqual(facts["functionalQualification"], self.gate["PENDING"])
                self.assertEqual(facts["eventBindingSHA256"], M.sha(M.canonical(fixture["binding"])))
                self.assertEqual(facts["role"], "producer" if label == "producer" else "consumer")
                self.assertEqual(set(facts["liveObservationSHA256"]), {"seal"} if label == "producer" else {"restore", "before", "after"})
                for key in ("acceptance", "providerQualification", "releaseReady", "payloadArchiveRetained", "liveChecksIndependentlyReexecuted"):
                    self.assertIs(facts[key], False)
        self.assertIs(result["scope"]["qualification"], False)
        self.assertEqual(result["scope"]["emittedTransport"], "PENDING")
        self.assertTrue(result["pendingProof"])

    def test_missing_extra_and_foreign_envelope_fields_refuse(self):
        original = copy.deepcopy(self.envelope)
        mutations = [dict(original, schema=M.INPUT_SCHEMA), dict(original, schema=M.COLD_INPUT_SCHEMA_V2),
                     dict(original, originalEventSHA256="A" * 64)]
        missing = copy.deepcopy(original); del missing["runAttempt"]; mutations.append(missing)
        for index, value in enumerate(mutations):
            with self.subTest(index=index):
                self.envelope = value; self.bind_outer(); self.fresh_destination("envelope-%d" % index)
                failure = self.refused(r"closed Phase1 V2 factual envelope")
                self.assertEqual(failure["schema"], "v23-phase1-retained-payload-failure.v2")

    def test_closed_cold_prerequisite_missing_substituted_and_extra_fields_refuse(self):
        original = copy.deepcopy(self.envelope)
        mutations = []
        value = copy.deepcopy(original); del value["plan"]["coldPrerequisite"]; mutations.append(value)
        for key in ("runID", "assessmentSHA256", "manifestSHA256", "reviewSHA256"):
            value = copy.deepcopy(original); del value["plan"]["coldPrerequisite"][key]; mutations.append(value)
        for key, fact in (("runID", True), ("runID", 0), ("reviewSHA256", "c" * 64), ("reviewSHA256", "C" * 63), ("authority", True)):
            value = copy.deepcopy(original); value["plan"]["coldPrerequisite"][key] = fact; mutations.append(value)
        for index, value in enumerate(mutations):
            with self.subTest(index=index):
                self.envelope = value; self.bind_outer(); self.fresh_destination("prerequisite-%d" % index)
                self.refused("Phase1 gate:")

    def test_moved_candidate_purpose_without_matching_ref_refuses(self):
        self.envelope["plan"]["purpose"] = self.gate["EXACT_MAIN"]
        self.bind_outer()
        self.refused("purpose/ref")

    def test_actual_exact_main_v2_plan_recomputes_without_qualification(self):
        plan = self.gate["make_plan_v2"](purpose=self.gate["EXACT_MAIN"], head=self.plan["head"], tree=self.plan["tree"],
            selection=self.ci["SHARED_SELECTION_ID"], resolved_bytes=self.ci["canonical"](self.resolved),
            sources=self.sources, requested_at=self.plan["requestedAtUTC"], cold_prerequisite=self.plan["coldPrerequisite"])
        self.envelope["plan"] = plan
        self.envelope["payloadArtifact"]["workflow_run"]["head_branch"] = "main"
        self.metadata["ref"] = plan["ref"]
        (self.payload / M.METADATA).write_bytes(M.canonical(self.metadata)); self.rebuild_archive()
        result = self.run_helper()
        self.assertEqual(result["originalDATA"]["ref"], "refs/heads/main")
        self.assertEqual(result["originalDATA"]["planSHA256"], M.sha(M.canonical(plan)))
        self.assertIs(result["scope"]["qualification"], False)

    def test_original_ids_reject_bool_zero_and_nonoriginal_attempt(self):
        original = copy.deepcopy(self.envelope)
        for index, (key, fact) in enumerate((("runID", True), ("runID", 0), ("runAttempt", True), ("runAttempt", 2))):
            with self.subTest(key=key, value=fact):
                self.envelope = copy.deepcopy(original); self.envelope[key] = fact
                self.bind_outer(); self.fresh_destination("ids-%d" % index)
                self.refused("declared frozen original IDs")

    def test_raw_api_download_identity_substitution_and_expiry_refuse(self):
        original = copy.deepcopy(self.envelope)
        cases = (("name", "wrong-payload"), ("expired", True), ("id", True), ("size_in_bytes", 0))
        for index, (key, fact) in enumerate(cases):
            with self.subTest(key=key):
                self.envelope = copy.deepcopy(original); self.envelope["payloadArtifact"][key] = fact
                self.bind_outer(); self.fresh_destination("api-%d" % index)
                self.refused("declared outer API artifact grammar")
        self.envelope = copy.deepcopy(original)
        self.envelope["payloadArtifact"]["workflow_run"]["head_sha"] = "3" * 40
        self.bind_outer(); self.fresh_destination("api-original")
        self.refused("declared API original join")

    def test_wrong_outer_payload_digest_refuses_before_extraction(self):
        self.envelope["payloadArtifact"]["digest"] = "sha256:" + "0" * 64
        self.envelope_path.write_bytes(M.canonical(self.envelope))
        failure = self.refused("outer ZIP digest differs")
        self.assertEqual(failure["stage"], "source-and-envelope")
        self.assertFalse((self.destination / "transport").exists())

    def test_pinned_runtime_sdk_and_configuration_substitutions_refuse(self):
        original = copy.deepcopy(self.metadata)
        for index, (key, fact) in enumerate((("xcodeVersion", "Xcode 27.0"), ("sdkBuild", "27A266a"),
                                           ("architecture", "x86_64"), ("configuration", "Release"))):
            with self.subTest(key=key):
                self.metadata = copy.deepcopy(original); self.metadata["toolchain"][key] = fact
                (self.payload / M.METADATA).write_bytes(M.canonical(self.metadata))
                self.rebuild_archive(); self.fresh_destination("runtime-%d" % index)
                self.refused("payload metadata original/selection join")

    def test_current_source_substitution_refuses(self):
        path = "Scripts/dev/v23-retained-payload.py"
        self.envelope["plan"]["sources"][path] = "0" * 64
        self.bind_outer()
        self.refused("source closure differs from frozen plan DATA")

    def test_changed_ordered_unit_method_digest_refuses(self):
        self.envelope["plan"]["orderedUnitMethodsSHA256"] = "0" * 64
        self.bind_outer()
        self.refused("source-resolved ordered selection differs")

    def test_rui1_selection_cannot_be_moved_into_shared_payload_adapter(self):
        self.envelope["plan"]["selection"] = self.gate["RUI1"]
        self.bind_outer()
        self.refused("shared Phase1 V2 payload plan only")

    def test_zip_traversal_duplicate_and_link_inputs_refuse(self):
        raw = self.tar.read_bytes()
        digest = ("%s %d %s\n" % (self.archive["sha256"], self.archive["bytes"], M.TAR_NAME)).encode("ascii")
        for index, members in enumerate(([("../" + M.TAR_NAME, raw), (M.DIGEST_NAME, digest)],
                                         [(M.TAR_NAME, raw), (M.TAR_NAME, raw)])):
            with self.subTest(index=index):
                self.write_zip(members=members); self.fresh_destination("zip-%d" % index)
                self.refused("exact two transport files")
                self.assertFalse((self.base / M.TAR_NAME).is_symlink())
        with zipfile.ZipFile(self.zip, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            link = zipfile.ZipInfo(M.TAR_NAME); link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, b"/outside")
            archive.writestr(M.DIGEST_NAME, digest)
        self.bind_outer(); self.fresh_destination("zip-link")
        self.refused("ZIP name/type/link/encryption refusal")

    def test_tar_traversal_duplicate_and_link_inputs_refuse(self):
        cases = [("FieldEvidencePayload/../outside", tarfile.REGTYPE, b"x"),
                 ("FieldEvidencePayload/outside", tarfile.SYMTYPE, b""),
                 ("FieldEvidencePayload/duplicate", tarfile.REGTYPE, b"x")]
        for index, (name, kind, raw) in enumerate(cases):
            with self.subTest(index=index):
                candidate = self.base / ("unsafe-%d.tar" % index)
                with tarfile.open(candidate, "w", format=tarfile.USTAR_FORMAT) as archive:
                    member = tarfile.TarInfo(name); member.type = kind; member.mode = 0o600
                    member.size = len(raw)
                    if kind == tarfile.SYMTYPE: member.linkname = "/outside"
                    archive.addfile(member, io.BytesIO(raw) if raw else None)
                    if index == 2: archive.addfile(copy.copy(member), io.BytesIO(raw))
                self.tar = candidate
                self.archive = {"name": M.TAR_NAME, "bytes": candidate.stat().st_size,
                                "sha256": self.kernel["sha256_file"](candidate)}
                self.write_zip(); self.fresh_destination("tar-%d" % index)
                phrase = ("unsafe relative member component", "TAR physical type/link/sparse refusal", "TAR duplicate member")[index]
                failure = self.refused(phrase)
                self.assertEqual(failure["stage"], "tar-preflight")
                self.assertFalse((self.destination / "extracted").exists())

    def test_products_and_xctestrun_substitution_refuse(self):
        products = self.payload / self.kernel["ROOT_LABEL"]
        app = products / "FieldEvidenceApp.app/FieldEvidenceApp"
        before = app.read_bytes()
        app.write_bytes(macho(2, cpu=0x01000007))
        self.rebuild_archive()
        self.refused("wrong/truncated Mach-O architecture")
        app.write_bytes(before)
        xctestrun = products / "Synthetic.xctestrun"
        settings = plistlib.loads(xctestrun.read_bytes())
        settings["FieldEvidenceAppTests"]["TestBundlePath"] = "__TESTROOT__/Missing.xctest"
        xctestrun.write_bytes(plistlib.dumps(settings, sort_keys=True))
        self.rebuild_archive(); self.fresh_destination("missing-xctestrun-executable")
        self.refused("missing test executable closure")

    def test_missing_or_extra_partition_directory_refuses_complete_census(self):
        workers = self.base / "incomplete-workers"; workers.mkdir()
        (workers / "producer").mkdir()
        failure = self.refused("complete producer/every-consumer directory census", retained_workers=workers)
        self.assertEqual(failure["stage"], "retained-worker-joins")
        self.fresh_destination("extra-census")
        for label in self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"]:
            (workers / label).mkdir()
        (workers / "extra").mkdir()
        self.refused("retained directory first-excess members", retained_workers=workers)

    def test_v2_worker_binding_substitution_and_v1_projection_refuse(self):
        fixture = self.use_workers()
        artifact = fixture["workers"] / "producer"
        path = artifact / "phase1-event-binding.json"
        original = path.read_bytes()
        for index, (key, fact) in enumerate((("schema", self.gate["EVENT_SCHEMA"]),
                                           ("originalEventSHA256", "0" * 64), ("kind", "development"))):
            with self.subTest(key=key):
                binding = M.decode(original); binding[key] = fact; path.write_bytes(M.canonical(binding))
                self.fresh_destination("worker-binding-%d" % index)
                self.refused("closed Phase1 V2 retained binding DATA join", retained_workers=fixture["workers"])
                path.write_bytes(original)

    def test_worker_source_role_and_selected_method_substitution_refuse(self):
        fixture = self.use_workers()
        artifact = fixture["workers"] / "producer"
        path = artifact / "native-admission.json"
        original = path.read_bytes()
        cases = (("protocolSHA256", "0" * 64, "worker source protocol DATA join"),
                 ("selectionSHA256", "0" * 64, "worker actual ordered selection DATA join"))
        for index, (key, fact, phrase) in enumerate(cases):
            with self.subTest(key=key):
                record = M.decode(original); record[key] = fact; path.write_bytes(M.canonical(record))
                self.fresh_destination("worker-source-%d" % index)
                self.refused(phrase, retained_workers=fixture["workers"])
                path.write_bytes(original)
        record = M.decode(original); record[self.ci["SHARED_KEY"]]["role"] = "consumer"
        path.write_bytes(M.canonical(record)); self.fresh_destination("worker-role")
        self.refused("worker role/partition/payload DATA join", retained_workers=fixture["workers"])

    def test_real_native_v2_no_rebuild_guard_refuses_consumer_build_evidence(self):
        fixture = self.use_workers()
        label = self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"][0]
        artifact = fixture["workers"] / label
        (artifact / "build-smoke.log").write_text("synthetic forbidden consumer build evidence\n")
        self.refused("Phase1 retained no-rebuild log/artifact scan", retained_workers=fixture["workers"])

    def test_legacy_v1_interface_retains_v1_schema_and_status(self):
        plan = self.gate["make_plan"](purpose=self.gate["CANDIDATE"], head=self.plan["head"], tree=self.plan["tree"],
            selection=self.ci["SHARED_SELECTION_ID"], resolved_bytes=self.ci["canonical"](self.resolved),
            sources=self.sources, requested_at=self.plan["requestedAtUTC"])
        self.envelope["schema"] = M.INPUT_SCHEMA; self.envelope["plan"] = plan; self.bind_outer()
        result = M.recompute_retained_payload(self.zip, self.envelope_path, self.root, self.destination)
        self.assertEqual(result["schema"], M.FACT_SCHEMA)
        self.assertEqual(result["status"], "RECOMPUTED_RETAINED_PAYLOAD_DATA")
        self.assertNotIn("scope", result)
        self.assertNotIn("coldPrerequisite", plan)
        self.assertEqual(result["pendingProof"], list(M.PENDING))

    def test_legacy_cold_development_interface_retains_closed_cold_contract(self):
        plan = self.gate["make_cold_plan"](head=self.plan["head"], tree=self.plan["tree"],
            resolved_bytes=self.ci["canonical"](self.resolved), sources=self.sources, requested_at=self.plan["requestedAtUTC"])
        self.envelope["schema"] = M.COLD_INPUT_SCHEMA_V2; self.envelope["plan"] = plan
        self.envelope["originalEventSHA256"] = "A" * 64
        self.metadata["routeID"] = self.ci["COLD_SELECTION_ID"]
        (self.payload / M.METADATA).write_bytes(M.canonical(self.metadata)); self.rebuild_archive()
        result = M.recompute_cold_retained_payload_v2(self.zip, self.envelope_path, self.root, self.destination)
        self.assertEqual(result["schema"], M.COLD_FACT_SCHEMA_V2)
        self.assertEqual(result["status"], "RECOMPUTED_COLD_RETAINED_PAYLOAD_DATA_ONLY_UNQUALIFIED")
        self.assertEqual(result["scope"], M.COLD_SCOPE_V2)
        self.assertEqual(result["originalEventSHA256"], "A" * 64)
        self.assertEqual(result["pendingProof"], list(M.COLD_PENDING_V2))

    def test_new_once_close_helper_preserves_primary_and_attempts_every_handle(self):
        primary, close_error = RuntimeError("first synthetic body object"), OSError("synthetic close object")
        attempted = []
        def close(handle):
            attempted.append(handle)
            if handle == 22: raise close_error
            return None
        with mock.patch.object(M.os, "close", close):
            M.phase1_close_handles_v2([11, 22, 33], primary)
        self.assertEqual(attempted, [33, 22, 11])
        self.assertTrue(any(repr(close_error) in note for note in primary.__notes__))
        attempted.clear()
        with mock.patch.object(M.os, "close", close), self.assertRaises(OSError) as raised:
            M.phase1_close_handles_v2([11, 22, 33], None)
        self.assertIs(raised.exception, close_error)
        self.assertEqual(attempted, [33, 22, 11])

    def test_v2_durable_publication_failure_retains_raw_inputs_and_primary_cause(self):
        actual = M.Owned.sync_tree
        injected, calls = OSError("synthetic late V2 publication fsync"), []
        zip_before, envelope_before = self.zip.read_bytes(), self.envelope_path.read_bytes()
        def late(owned):
            calls.append(owned.path)
            if len(calls) == 1:
                self.assertEqual((owned.path / "payload.zip").read_bytes(), zip_before)
                self.assertEqual((owned.path / "input-envelope.json").read_bytes(), envelope_before)
                self.assertTrue((owned.path / "extracted" / M.METADATA).is_file())
                raise injected
            return actual(owned)
        with mock.patch.object(M.Owned, "sync_tree", late), self.assertRaises(M.Refused) as raised:
            self.run_helper()
        self.assertIs(raised.exception.__cause__, injected)
        self.assertEqual(len(calls), 2)
        failure = M.decode((self.destination / "FAILURE.json").read_bytes())
        self.assertEqual(failure["stage"], "durable-publication")
        self.assertEqual(failure["durability"]["status"], "FSYNCED_OWNED_DATA_PROJECTION")
        self.assertEqual((self.destination / "payload.zip").read_bytes(), zip_before)
        self.assertEqual((self.destination / "input-envelope.json").read_bytes(), envelope_before)
        self.assertEqual(self.zip.read_bytes(), zip_before)
        self.assertEqual(self.envelope_path.read_bytes(), envelope_before)
        self.assertFalse((self.destination / "FACTS.json").exists())

    def test_late_forbidden_consumer_leaves_after_all_native_joins_refuse(self):
        fixture = self.use_workers()
        label = self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"][0]
        artifact = fixture["workers"] / label
        actual = M.Owned.sync_tree
        for index, name in enumerate(("Build.xcresult", "build-smoke.log", self.ci["NO_INDEX_RECEIPT"])):
            with self.subTest(name=name):
                before = M.phase1_worker_states_v2(artifact, False, self.ci)
                self.assertEqual(before["forbiddenConsumerLeaves"][name], {"absent": True})
                leaf, injected = artifact / name, []
                def late(owned):
                    result = actual(owned)
                    if not injected:
                        injected.append(name)
                        if name == "Build.xcresult": leaf.mkdir()
                        else: leaf.write_bytes(b"synthetic late forbidden consumer input\n")
                    return result
                self.fresh_destination("late-forbidden-%d" % index)
                with mock.patch.object(M.Owned, "sync_tree", late):
                    failure = self.refused("Phase1 V2 retained workers changed during complete recomputation interval",
                                           retained_workers=fixture["workers"])
                self.assertEqual(injected, [name])
                self.assertEqual(failure["stage"], "durable-publication")
                if leaf.is_dir(): leaf.rmdir()
                else: leaf.unlink()

    def test_earlier_worker_witness_changed_during_later_native_computation_refuses(self):
        fixture = self.use_workers()
        last = fixture["workers"] / self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"][-1]
        witness = fixture["workers"] / "producer/phase1-shared-live-v2-seal.json"
        original = witness.read_bytes()
        actual, later_reads, injected = M.phase1_worker_states_v2, [], []
        def observed(artifact, producer, ci):
            state = actual(artifact, producer, ci)
            if artifact == last:
                later_reads.append(artifact)
                # First is complete initial capture; second precedes the final
                # worker's real Native call, after every earlier local check.
                if len(later_reads) == 2:
                    value = M.decode(original); value["testsExecuted"] = 1
                    witness.write_bytes(M.canonical(value)); injected.append(witness)
            return state
        with mock.patch.object(M, "phase1_worker_states_v2", observed):
            failure = self.refused("Phase1 V2 retained workers changed during complete recomputation interval",
                                   retained_workers=fixture["workers"])
        self.assertEqual(injected, [witness])
        self.assertEqual(failure["stage"], "final-invariance")
        self.assertNotEqual(witness.read_bytes(), original)

    def test_worker_drift_after_durable_facts_publication_refuses_preserving_both_receipts(self):
        fixture = self.use_workers()
        witness = fixture["workers"] / "producer/phase1-shared-live-v2-seal.json"
        original = witness.read_bytes()
        actual, injected = M.Owned.write, []
        def published(owned, name, raw):
            result = actual(owned, name, raw)
            if name == "FACTS.json":
                value = M.decode(original); value["testsExecuted"] = 1
                witness.write_bytes(M.canonical(value)); injected.append(witness)
            return result
        zip_before, envelope_before = self.zip.read_bytes(), self.envelope_path.read_bytes()
        with mock.patch.object(M.Owned, "write", published), self.assertRaisesRegex(M.Refused,
                "Phase1 V2 retained workers changed during complete recomputation interval"):
            self.run_helper(retained_workers=fixture["workers"])
        self.assertEqual(injected, [witness])
        failure = M.decode((self.destination / "FAILURE.json").read_bytes())
        self.assertEqual(failure["stage"], "final-worker-invariance")
        self.assertEqual(failure["status"], "REFUSED_PARTIAL_OWNED_DATA_RETAINED")
        # Preserve the already published DATA and explicit invalidating failure;
        # a failed child can never supply the collector's successful result.
        facts = M.decode((self.destination / "FACTS.json").read_bytes())
        self.assertIs(facts["scope"]["qualification"], False)
        self.assertEqual(self.zip.read_bytes(), zip_before)
        self.assertEqual(self.envelope_path.read_bytes(), envelope_before)
        self.assertEqual((self.destination / "payload.zip").read_bytes(), zip_before)
        self.assertEqual((self.destination / "input-envelope.json").read_bytes(), envelope_before)




if __name__ == "__main__":
    unittest.main()
