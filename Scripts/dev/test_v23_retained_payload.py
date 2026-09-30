"""Synthetic offline byte/behavior fixtures, never native builds or gate proof.

Root runs this candidate explicitly after freeze. Actual source/kernel contracts
create finite synthetic Mach-O/products/TARs; no embedded verifier literal.
"""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import stat
import struct
import tarfile
import tempfile
import tracemalloc
import unittest
from unittest import mock
import zipfile
import zlib


def load_target():
    path = Path(__file__).with_name("v23-retained-payload.py")
    spec = importlib.util.spec_from_file_location("retained_payload_candidate", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


M = load_target()


def source_root():
    explicit = os.environ.get("V23_RETAINED_PAYLOAD_SOURCE_ROOT")
    if explicit:
        return Path(explicit).resolve()
    for parent in Path(__file__).resolve().parents:
        if (parent / "Scripts/v23-native-ci.py").is_file():
            return parent
    raise RuntimeError("Set V23_RETAINED_PAYLOAD_SOURCE_ROOT to the exact source checkout")


def macho(filetype, *, cpu=0x0100000C, sdk=(26 << 16) | (5 << 8)):
    """Finite mechanically valid arm64 simulator header; not a built executable."""
    return (b"\xcf\xfa\xed\xfe" + struct.pack("<7I", cpu, 0, filetype, 1, 24, 0, 0)
            + struct.pack("<6I", 0x32, 24, 7, 18 << 16, sdk, 0))


class RetainedPayloadBehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = source_root()
        cls.ci, cls.gate, cls.kernel = M.source_modules(cls.root)
        cls.sources = M.source_closure(cls.root, cls.gate)
        cls.resolved = cls.ci["shared_selection"](cls.root)
        cls.plan = cls.gate["make_plan"](purpose=cls.gate["CANDIDATE"], head="1" * 40, tree="2" * 40,
            selection=cls.ci["SHARED_SELECTION_ID"], resolved_bytes=cls.ci["canonical"](cls.resolved),
            sources=cls.sources, requested_at="2026-09-29T12:00:00Z")

    def setUp(self):
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
            "runID": "123", "runAttempt": "1", "payloadArtifactName": "v23-shared-payload-123-1-" + self.plan["head"],
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
        self.envelope = {"schema": M.INPUT_SCHEMA, "plan": copy.deepcopy(self.plan), "runID": 123, "runAttempt": 1,
                         "payloadArtifact": {"id": 456, "name": self.metadata["payloadArtifactName"],
                             "digest": "sha256:" + "0" * 64, "size_in_bytes": 987654, "expired": False,
                             "workflow_run": {"id": 123, "head_sha": self.plan["head"],
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
        return M.recompute_retained_payload(self.zip, self.envelope_path, self.root, self.destination, **kwargs)

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

    def test_success_recomputes_real_kernel_facts_but_original_proof_stays_pending(self):
        result = self.run_helper()
        self.assertEqual(result["status"], "RECOMPUTED_RETAINED_PAYLOAD_DATA")
        self.assertEqual(result["products"], self.products)
        self.assertEqual(len(result["products"]["compatibility"]), 3)
        self.assertEqual(result["archive"], self.archive)
        self.assertEqual(result["sourceSHA256"], self.sources)
        self.assertEqual(result["outerZIP"]["sha256"], self.envelope["payloadArtifact"]["digest"][7:])
        self.assertNotEqual(result["outerZIP"]["sha256"].upper(), result["archive"]["sha256"])
        self.assertNotEqual(result["outerZIP"]["bytes"], result["outerZIP"]["declaredAPIArtifact"]["size_in_bytes"])
        self.assertEqual(result["workerJoins"]["status"], "PENDING_MISSING_RETAINED_WORKERS")
        self.assertEqual(result["workerJoins"]["requiredLabels"], ["producer"] + self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"])
        self.assertEqual(result["originalPayloadClassification"], {"developmentOnly": True, "acceptance": False})
        self.assertTrue(result["pendingProof"])
        self.assertNotIn("qualified", result)
        self.assertNotIn("authorized", result)
        self.assertEqual((self.destination / "payload.zip").read_bytes(), self.zip.read_bytes())
        self.assertEqual((self.destination / "transport" / M.TAR_NAME).read_bytes(), self.tar.read_bytes())
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o700)
        self.assertEqual(M.decode((self.destination / "FACTS.json").read_bytes()), result)

    def test_valid_stored_per_member_zip64_and_streaming_descriptors(self):
        class StreamingBuffer(io.BytesIO):
            def seek(self, *args):
                raise io.UnsupportedOperation("synthetic streaming writer")
        for streaming, zip64 in ((False, True), (True, False), (True, True)):
            with self.subTest(streaming=streaming, zip64=zip64):
                buffer = StreamingBuffer() if streaming else io.BytesIO()
                with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
                    with archive.open(M.TAR_NAME, "w", force_zip64=zip64) as member:
                        member.write(self.tar.read_bytes())
                    archive.writestr(M.DIGEST_NAME, ("%s %d %s\n" %
                        (self.archive["sha256"], self.archive["bytes"], M.TAR_NAME)).encode("ascii"))
                self.zip.write_bytes(buffer.getvalue())
                self.bind_outer()
                result = M.recompute_retained_payload(self.zip, self.envelope_path, self.root,
                    self.base / ("valid-zip-%s-%s" % (streaming, zip64)))
                self.assertEqual(result["products"], self.products)
                self.assertEqual(result["archive"], self.archive)

    def test_interruption_preserves_raw_bytes_and_partial_owned_receipt(self):
        with mock.patch.object(M, "zip_preflight", side_effect=KeyboardInterrupt("synthetic interruption")):
            with self.assertRaises(KeyboardInterrupt):
                self.run_helper()
        failure = M.decode((self.destination / "FAILURE.json").read_bytes())
        self.assertEqual(failure["errorType"], "KeyboardInterrupt")
        self.assertEqual(failure["stage"], "zip-transport")
        self.assertEqual((self.destination / "payload.zip").read_bytes(), self.zip.read_bytes())
        self.assertFalse((self.destination / "FACTS.json").exists())

    def test_preexisting_destination_is_untouched(self):
        self.destination.mkdir()
        sentinel = self.destination / "owner-file"
        sentinel.write_bytes(b"preserve")
        with self.assertRaises(FileExistsError):
            self.run_helper()
        self.assertEqual(list(self.destination.iterdir()), [sentinel])
        self.assertEqual(sentinel.read_bytes(), b"preserve")

    def test_symlink_destination_or_parent_is_refused_without_target_effect(self):
        target = self.base / "owner-directory"
        target.mkdir()
        self.destination.symlink_to(target, target_is_directory=True)
        with self.assertRaises(FileExistsError):
            self.run_helper()
        self.assertEqual(list(target.iterdir()), [])
        with self.assertRaises(OSError):
            M.recompute_retained_payload(self.zip, self.envelope_path, self.root, self.destination / "child")
        self.assertEqual(list(target.iterdir()), [])

    def test_symlink_and_hardlinked_raw_input_refused_with_owned_failure(self):
        before = self.zip.read_bytes()
        for kind in ("symlink", "hardlink"):
            with self.subTest(kind=kind):
                alternate = self.base / (kind + ".zip")
                if kind == "symlink":
                    alternate.symlink_to(self.zip)
                else:
                    os.link(self.zip, alternate)
                destination = self.base / (kind + "-destination")
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(alternate, self.envelope_path, self.root, destination)
                self.assertTrue((destination / "FAILURE.json").exists())
                self.assertEqual(self.zip.read_bytes(), before)

    def test_declared_outer_digest_case_mismatch_is_refused_after_raw_retention(self):
        self.envelope["payloadArtifact"]["digest"] = self.envelope["payloadArtifact"]["digest"].upper()
        self.envelope_path.write_bytes(M.canonical(self.envelope))
        self.refused("outer API artifact grammar")

    def test_outer_digest_is_checked_against_raw_zip_not_inner_tar(self):
        self.envelope["payloadArtifact"]["digest"] = "sha256:" + self.archive["sha256"].lower()
        self.envelope_path.write_bytes(M.canonical(self.envelope))
        self.refused("outer ZIP digest differs")

    def test_duplicate_json_nonfinite_and_noncanonical_envelopes_refused(self):
        for raw in (b'{"schema":"x","schema":"y"}\n', b'{"value":NaN}\n', b'{ "schema": "x" }\n'):
            with self.subTest(raw=raw):
                destination = self.base / ("bad-json-%d" % len(list(self.base.glob("bad-json-*"))))
                self.envelope_path.write_bytes(raw)
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(self.zip, self.envelope_path, self.root, destination)
                self.assertEqual((destination / "input-envelope.json").read_bytes(), raw)

    def test_missing_facts_and_bool_aliases_are_not_defaulted_to_original_ids(self):
        for key, value in (("runID", True), ("runAttempt", True), ("payloadArtifact", {})):
            with self.subTest(key=key):
                envelope = copy.deepcopy(self.envelope)
                envelope[key] = value
                path = self.base / (key + ".json")
                path.write_bytes(M.canonical(envelope))
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(self.zip, path, self.root, self.base / (key + "-destination"))

    def test_changed_source_or_closed_source_set_is_refused(self):
        self.envelope["plan"]["sources"]["Scripts/v23-native-ci.py"] = "C" * 64
        self.envelope_path.write_bytes(M.canonical(self.envelope))
        self.refused("source closure differs")

    def test_wrong_executable_version_is_not_executed(self):
        wrong_root = self.base / "untrusted-source"
        (wrong_root / "Scripts").mkdir(parents=True)
        sentinel = self.base / "must-not-execute"
        (wrong_root / "Scripts/v23-native-ci.py").write_text("open(%r, 'w').write('unsafe')\n" % str(sentinel))
        with self.assertRaisesRegex(M.Refused, "unsupported executable source"):
            M.recompute_retained_payload(self.zip, self.envelope_path, wrong_root, self.destination)
        self.assertFalse(sentinel.exists())
        self.assertTrue((self.destination / "FAILURE.json").exists())

    def test_selection_generator_dependency_cannot_execute_self_declared_source(self):
        wrong_root = self.base / "untrusted-generator-source"
        (wrong_root / "Scripts").mkdir(parents=True)
        for relative in M.EXECUTABLE_SOURCES:
            if relative != "Scripts/v23-selection-generator.py":
                (wrong_root / relative).write_bytes((self.root / relative).read_bytes())
        sentinel = self.base / "generator-must-not-execute"
        (wrong_root / "Scripts/v23-selection-generator.py").write_text("open(%r, 'w').write('unsafe')\n" % str(sentinel))
        with self.assertRaisesRegex(M.Refused, "unsupported executable source: Scripts/v23-selection-generator.py"):
            M.recompute_retained_payload(self.zip, self.envelope_path, wrong_root, self.destination)
        self.assertFalse(sentinel.exists())
        self.assertTrue((self.destination / "FAILURE.json").exists())

    def test_eager_zip_directory_count_and_size_refused_before_constructor(self):
        for offset, fmt, value in ((10, "H", 65535), (12, "I", 4 * 1024**2)):
            with self.subTest(offset=offset):
                raw = bytearray(self.zip.read_bytes())
                end = raw.rfind(b"PK\x05\x06")
                struct.pack_into("<" + fmt, raw, end + offset, value)
                bad = self.base / ("central-%d.zip" % offset)
                bad.write_bytes(raw)
                with mock.patch.object(M.zipfile, "ZipFile", side_effect=AssertionError("eager parser must not run")):
                    with self.assertRaises(M.Refused):
                        M.zip_preflight(bad)

    def test_transport_extra_duplicate_path_and_case_names_refused(self):
        for names in ((M.TAR_NAME, M.DIGEST_NAME, "extra"), (M.TAR_NAME, M.TAR_NAME),
                      ("../" + M.TAR_NAME, M.DIGEST_NAME), (M.TAR_NAME.lower(), M.DIGEST_NAME)):
            with self.subTest(names=names):
                self.write_zip([(name, b"synthetic") for name in names])
                destination = self.base / ("transport-case-%d" % len(list(self.base.glob("transport-case-*"))))
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(self.zip, self.envelope_path, self.root, destination)
                self.assertFalse((destination / "extracted").exists())

    def test_zip_symlink_special_mode_and_encryption_refused(self):
        for mode in ((stat.S_IFLNK | 0o777), (stat.S_IFREG | 0o4644), (stat.S_IFIFO | 0o600)):
            with self.subTest(mode=mode):
                info = zipfile.ZipInfo(M.TAR_NAME)
                info.create_system = 3
                info.external_attr = mode << 16
                self.write_zip([(info, b"synthetic"), (M.DIGEST_NAME, b"digest")])
                destination = self.base / ("mode-%d" % mode)
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(self.zip, self.envelope_path, self.root, destination)
        self.rebuild_archive()
        raw = bytearray(self.zip.read_bytes())
        struct.pack_into("<H", raw, raw.index(b"PK\x01\x02") + 8, 1)
        self.zip.write_bytes(raw)
        self.bind_outer()
        self.refused("encryption refusal")

    def test_local_header_name_mismatch_and_crc_corruption_refused(self):
        raw = bytearray(self.zip.read_bytes())
        raw[30] = ord("X")
        self.zip.write_bytes(raw)
        self.bind_outer()
        self.refused("local/central name mismatch")
        self.rebuild_archive()
        raw = bytearray(self.zip.read_bytes())
        local, central = raw.index(b"PK\x03\x04"), raw.index(b"PK\x01\x02")
        wrong = (struct.unpack_from("<I", raw, local + 14)[0] + 1) & 0xFFFFFFFF
        struct.pack_into("<I", raw, local + 14, wrong)
        struct.pack_into("<I", raw, central + 16, wrong)
        self.zip.write_bytes(raw)
        self.bind_outer()
        with self.assertRaisesRegex(M.Refused, "bytes/CRC"):
            M.recompute_retained_payload(self.zip, self.envelope_path, self.root, self.base / "bad-crc")

    def test_inner_digest_strict_case_name_length_newline_and_bytes(self):
        valid = "%s %d %s\n" % (self.archive["sha256"], self.archive["bytes"], M.TAR_NAME)
        for text in (valid.lower(), valid.rstrip("\n"), valid.replace(M.TAR_NAME, "other.tar"),
                     valid.replace(str(self.archive["bytes"]), "9" * 21),
                     valid.replace(str(self.archive["bytes"]), str(self.archive["bytes"] + 1))):
            with self.subTest(text=text):
                self.write_zip(digest=text.encode("ascii"))
                destination = self.base / ("inner-%d" % len(list(self.base.glob("inner-*"))))
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(self.zip, self.envelope_path, self.root, destination)
                self.assertFalse((destination / "extracted").exists())

    def test_first_excess_zip_expansion_and_raw_bounds_retain_owned_partials(self):
        with mock.patch.object(M, "ZIP_EXPANDED_BYTES", self.archive["bytes"] - 1):
            self.refused("ZIP declared expansion bound")
        second = self.base / "raw-limit-destination"
        with mock.patch.object(M, "ZIP_BYTES", self.zip.stat().st_size - 1):
            with self.assertRaisesRegex(M.Refused, "raw input declared byte bound"):
                M.recompute_retained_payload(self.zip, self.envelope_path, self.root, second)
        failure = json.loads((second / "FAILURE.json").read_bytes())
        self.assertEqual(failure["ownedCopies"]["payload.zip"]["state"], "PARTIAL_OWNED_COPY")
        self.assertEqual((second / "payload.zip").stat().st_size, 0)

    def test_deflate_underreported_size_is_refused_before_any_excess_output_write(self):
        raw = bytearray(self.zip.read_bytes())
        local, central = raw.index(b"PK\x03\x04"), raw.index(b"PK\x01\x02")
        fake_crc = zlib.crc32(self.tar.read_bytes()[:1])
        struct.pack_into("<I", raw, local + 14, fake_crc)
        struct.pack_into("<I", raw, local + 22, 1)
        struct.pack_into("<I", raw, central + 16, fake_crc)
        struct.pack_into("<I", raw, central + 24, 1)
        self.zip.write_bytes(raw)
        self.bind_outer()
        self.refused("ZIP first-excess expansion bytes")
        self.assertEqual((self.destination / "transport" / M.TAR_NAME).stat().st_size, 0)

    def hostile_tar(self, infos):
        self.tar.unlink()
        with tarfile.open(self.tar, "x", format=tarfile.PAX_FORMAT) as archive:
            for info, raw in infos:
                archive.addfile(info, io.BytesIO(raw) if info.isreg() else None)
        self.archive = {"name": M.TAR_NAME, "bytes": self.tar.stat().st_size, "sha256": self.kernel["sha256_file"](self.tar)}
        self.write_zip()

    def test_tar_path_link_sparse_type_permissions_and_duplicates_refused(self):
        cases = []
        for name, kind in (("FieldEvidencePayload/../escape", tarfile.REGTYPE),
                           ("FieldEvidencePayload/link", tarfile.SYMTYPE),
                           ("FieldEvidencePayload/hard", tarfile.LNKTYPE),
                           ("FieldEvidencePayload/fifo", tarfile.FIFOTYPE)):
            info = tarfile.TarInfo(name)
            info.type, info.linkname = kind, "target" if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE) else ""
            cases.append([(info, b"")])
        sparse = tarfile.TarInfo("FieldEvidencePayload/sparse")
        sparse.pax_headers = {"GNU.sparse.name": "hidden"}
        cases.append([(sparse, b"")])
        special = tarfile.TarInfo("FieldEvidencePayload/special")
        special.mode = 0o4644
        cases.append([(special, b"")])
        repeated = tarfile.TarInfo("FieldEvidencePayload/repeated")
        cases.append([(repeated, b""), (copy.copy(repeated), b"")])
        for index, infos in enumerate(cases):
            with self.subTest(index=index):
                self.hostile_tar(infos)
                destination = self.base / ("tar-hostile-%d" % index)
                with self.assertRaises(M.Refused):
                    M.recompute_retained_payload(self.zip, self.envelope_path, self.root, destination)
                self.assertFalse((destination / "extracted").exists())

    def test_tar_implicit_parent_case_conflict_and_file_parent_refused(self):
        for names in (("FieldEvidencePayload/A/one", "FieldEvidencePayload/a/two"),
                      ("FieldEvidencePayload/a", "FieldEvidencePayload/a/child")):
            with self.subTest(names=names):
                self.hostile_tar([(tarfile.TarInfo(name), b"") for name in names])
                with self.assertRaises(M.Refused):
                    M.tar_preflight(self.tar, self.kernel)

    def test_deep_admitted_pax_path_uses_linear_component_storage(self):
        # 4KiB/2048 components exposes the former ~8MiB retained prefixes.
        # Do not run the reviewer's multiGiB 64KiB-name exhaustion scenario.
        depth = 2048
        relative = "/".join(["x"] * depth)
        self.hostile_tar([(tarfile.TarInfo("FieldEvidencePayload/" + relative), b"")])
        tracemalloc.start()
        try:
            work = M.tar_preflight(self.tar, self.kernel)
            unused, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertEqual(work["componentVisits"], depth)
        self.assertEqual(work["componentNodes"], depth)
        self.assertEqual(work["componentCharactersVisited"], depth)
        self.assertEqual(work["casefoldCharactersVisited"], depth)
        self.assertEqual(work["storedComponentCharacters"], 2 * depth)
        self.assertLessEqual(work["storedComponentCharacters"], 2 * work["encodedCensusBytes"])
        # A regression measurement for this small fixture, not a new product
        # path/depth/heap admission cap. The old full-prefix table exceeds it.
        self.assertLess(peak, 512 * work["encodedCensusBytes"])
        self.assertGreater(2 * depth * depth, 512 * work["encodedCensusBytes"])

    def test_deep_path_never_reformats_each_full_parent(self):
        relative = "/".join(["part"] * 256)
        self.hostile_tar([(tarfile.TarInfo("FieldEvidencePayload/" + relative), b"")])
        emitted = [0]
        original = M.Path.as_posix
        def measured_as_posix(path):
            text = original(path)
            emitted[0] += len(text)
            return text
        with mock.patch.object(M.Path, "as_posix", measured_as_posix):
            work = M.tar_preflight(self.tar, self.kernel)
        # Permit a linear spelling pass; repeated full parents cost ~160KiB
        # for this ~1KiB name and fail this actual formatted-character count.
        self.assertLessEqual(emitted[0], work["encodedCensusBytes"])
        self.assertEqual(work["componentVisits"], 256)

    def test_component_roles_preserve_implicit_directory_file_order_and_case_refusals(self):
        valid = [("Dir/branch/leaf", tarfile.REGTYPE), ("Dir/branch", tarfile.DIRTYPE), ("Dir", tarfile.DIRTYPE)]
        for order in (valid, list(reversed(valid))):
            infos = []
            for name, kind in order:
                info = tarfile.TarInfo("FieldEvidencePayload/" + name)
                info.type = kind
                infos.append((info, b""))
            self.hostile_tar(infos)
            work = M.tar_preflight(self.tar, self.kernel)
            self.assertEqual(work["members"], 3)
            self.assertEqual(work["componentNodes"], 3)
        cases = [
            [("Foo/a", tarfile.REGTYPE), ("foo/b", tarfile.REGTYPE)],
            [("parent/Leaf", tarfile.REGTYPE), ("parent/leaf", tarfile.REGTYPE)],
            [("Straße/a", tarfile.REGTYPE), ("STRASSE/b", tarfile.REGTYPE)],
            [("same", tarfile.REGTYPE), ("same", tarfile.REGTYPE)],
            [("Dir", tarfile.DIRTYPE), ("Dir", tarfile.DIRTYPE)],
            [("node", tarfile.REGTYPE), ("node/child", tarfile.REGTYPE)],
            [("node/child", tarfile.REGTYPE), ("node", tarfile.REGTYPE)],
        ]
        for index, case in enumerate(cases):
            with self.subTest(index=index):
                infos = []
                for name, kind in case:
                    info = tarfile.TarInfo("FieldEvidencePayload/" + name)
                    info.type = kind
                    infos.append((info, b""))
                self.hostile_tar(infos)
                with self.assertRaises(M.Refused):
                    M.tar_preflight(self.tar, self.kernel)

    def test_shared_deep_component_work_is_charged_to_existing_census_bytes(self):
        shared = "/".join(["x"] * 256)
        names = [shared + "/leaf%d" % index for index in range(8)]
        names.append("Straße/leaf")  # Lawful Unicode expansion is preserved.
        self.hostile_tar([(tarfile.TarInfo("FieldEvidencePayload/" + name), b"") for name in names])
        work = M.tar_preflight(self.tar, self.kernel)
        self.assertEqual(work["members"], len(names))
        self.assertEqual(work["componentNodes"], 256 + 8 + 2)
        self.assertEqual(work["componentVisits"], 8 * 257 + 2)
        self.assertLessEqual(work["componentCharactersVisited"], work["encodedCensusBytes"])
        self.assertLessEqual(work["casefoldCharactersVisited"], work["encodedCensusBytes"])
        self.assertLessEqual(work["storedComponentCharacters"], 2 * work["encodedCensusBytes"])

    def test_tar_member_extension_census_and_truncated_terminal_bounds(self):
        infos = [(tarfile.TarInfo("FieldEvidencePayload/one"), b""),
                 (tarfile.TarInfo("FieldEvidencePayload/two"), b"")]
        self.hostile_tar(infos)
        with mock.patch.object(M, "TAR_MEMBERS", 1):
            with self.assertRaisesRegex(M.Refused, "first-excess member"):
                M.tar_preflight(self.tar, self.kernel)
        with mock.patch.object(M, "JSON_BYTES", 10):
            with self.assertRaisesRegex(M.Refused, "first-excess census"):
                M.tar_preflight(self.tar, self.kernel)
        long_name = tarfile.TarInfo("FieldEvidencePayload/" + "a" * 120)
        self.hostile_tar([(long_name, b"")])
        with mock.patch.object(M, "TAR_EXTENSION_BYTES", 8):
            with self.assertRaisesRegex(M.Refused, "extension allocation bound"):
                M.tar_preflight(self.tar, self.kernel)
        self.tar.write_bytes(self.tar.read_bytes()[:512])
        with self.assertRaises(M.Refused):
            M.tar_preflight(self.tar, self.kernel)

    def test_tar_negative_and_overflowing_declared_sizes_refuse_before_body_or_destination_allocation(self):
        for size in (-1, 1 << 63):
            with self.subTest(size=size):
                info = tarfile.TarInfo("FieldEvidencePayload/oversize")
                info.size = size
                self.tar.write_bytes(info.tobuf(format=tarfile.GNU_FORMAT) + bytes(1024))
                self.archive = {"name": M.TAR_NAME, "bytes": self.tar.stat().st_size,
                                "sha256": self.kernel["sha256_file"](self.tar)}
                self.write_zip()
                destination = self.base / ("declared-size-%s" % size)
                with self.assertRaisesRegex(M.Refused, "size/overflow refusal"):
                    M.recompute_retained_payload(self.zip, self.envelope_path, self.root, destination)
                self.assertFalse((destination / "extracted").exists())

    def test_unbound_extra_payload_files_and_forged_products_refused(self):
        extra = self.payload / "FieldEvidenceDerivedData/extra"
        extra.write_bytes(b"not part of products")
        self.rebuild_archive()
        self.refused("closed payload member closure")
        extra.unlink()
        self.metadata["products"] = dict(self.products, fileBytes=self.products["fileBytes"] + 1)
        (self.payload / M.METADATA).write_bytes(M.canonical(self.metadata))
        self.rebuild_archive()
        with self.assertRaisesRegex(M.Refused, "recomputed product"):
            M.recompute_retained_payload(self.zip, self.envelope_path, self.root, self.base / "forged-products")

    def test_real_kernel_rejects_unrelocatable_xctestrun_and_wrong_architecture(self):
        products = self.payload / self.kernel["ROOT_LABEL"]
        settings_path = products / "Synthetic.xctestrun"
        settings = plistlib.loads(settings_path.read_bytes())
        settings["FieldEvidenceAppTests"]["TestBundlePath"] = "/synthetic/original/absolute.xctest"
        settings_path.write_bytes(plistlib.dumps(settings))
        self.rebuild_archive()
        self.refused("xctestrun")
        settings["FieldEvidenceAppTests"]["TestBundlePath"] = "__TESTROOT__/FieldEvidenceAppTests.xctest"
        settings_path.write_bytes(plistlib.dumps(settings))
        (products / "FieldEvidenceApp.app/FieldEvidenceApp").write_bytes(macho(2, cpu=7))
        self.rebuild_archive()
        with self.assertRaisesRegex(M.Refused, "architecture"):
            M.recompute_retained_payload(self.zip, self.envelope_path, self.root, self.base / "wrong-architecture")

    def worker_fixture(self):
        directory = self.base / "synthetic-retained-workers"
        directory.mkdir()
        entries = self.kernel["inventory"](self.payload / self.kernel["ROOT_LABEL"])
        census = self.ci["phase1_tar_census"](self.tar, self.kernel)
        binding = {"schema": self.gate["EVENT_SCHEMA"], "plan": self.plan,
                   "planSHA256": M.sha(M.canonical(self.plan)), "runID": "123", "runAttempt": "1",
                   "functionalQualification": self.gate["PENDING"]}
        labels = ["producer"] + self.resolved[self.ci["SHARED_KEY"]]["partitionIDs"]
        for label in labels:
            artifact = directory / label
            artifact.mkdir()
            producer = label == "producer"
            role = "producer" if producer else "consumer"
            selected = self.resolved if producer else self.ci["shared_selection"](self.root, label)
            record = {**self.ci["source_binding"](self.root),
                      "repository": self.plan["route"]["repository"], "ref": self.plan["ref"],
                      "head": self.plan["head"], "gitTree": self.plan["tree"], "runID": "123", "runAttempt": "1",
                      "selectionID": self.ci["SHARED_SELECTION_ID"], "phase1Gate": binding,
                      "selectionSHA256": M.sha(self.ci["canonical"](selected)),
                      self.ci["SHARED_KEY"]: {"role": role, "partitionID": None if producer else label,
                          "payloadArtifactName": self.metadata["payloadArtifactName"],
                          "planSHA256": self.metadata["planSHA256"], "partitionsSHA256": self.metadata["partitionsSHA256"]}}
            for name, value in (("native-admission.json", record), ("phase1-event-binding.json", binding),
                                (M.METADATA, self.metadata), ("ci-selection.selected.json", selected)):
                (artifact / name).write_bytes(M.canonical(value))
            identity = self.ci["phase1_observation_identity"](self.root, artifact, record)
            receipt = {"schema": "v23-shared-payload-receipt.v1" if producer else "v23-shared-restore.v1",
                       "role": role, "archive": self.archive, "metadataSHA256": M.sha(M.canonical(self.metadata)),
                       "productsTreeSHA256": self.products["treeSHA256"], "xctestrunSHA256": self.products["xctestrunSHA256"]}
            receipt_name = self.ci["SHARED_PAYLOAD_RECEIPT"] if producer else self.ci["SHARED_RESTORE_RECEIPT"]
            (artifact / receipt_name).write_bytes(M.canonical(receipt))
            delta = dict(self.ci["shared_derived_delta"]({}, {}), beforeEntryCount=0, afterEntryCount=0, compileEvidence=[])
            if not producer:
                (artifact / self.ci["SHARED_DERIVED_DATA_DELTA"]).write_bytes(M.canonical(delta))
                (artifact / "phase1-activity-logs").mkdir()
                (artifact / "test-smoke.log").write_bytes(b"Synthetic offline fixture, no native execution.\n")
            for stage in (("seal",) if producer else ("restore", "before", "after")):
                observation = {"schema": self.ci["PHASE1_WITNESS_SCHEMA"], **identity,
                    "stage": stage, "role": role, "partitionID": None if producer else label,
                    "workspace": self.metadata["workspace"], "runnerTemp": "/synthetic/original/temp/" + label,
                    "artifactDirectory": "/synthetic/original/artifacts/" + label,
                    "payloadArtifactName": self.metadata["payloadArtifactName"],
                    "metadataSHA256": M.sha(M.canonical(self.metadata)), "products": self.products, "productInventory": entries}
                if stage in ("seal", "restore"):
                    observation.update(archive=self.archive, archiveMemberCensus=census, receiptSHA256=M.sha(M.canonical(receipt)))
                    if producer:
                        observation.update(sourceProductInventory=entries, sourceUnchangedDuringSeal=True,
                                           testsExecuted=0, diagnostics="NOT_APPLICABLE_BUILD_ONLY")
                    else:
                        observation.update(safeExtractionObserved=True,
                                           extractionKernelSHA256=self.sources[self.ci["SHARED_PAYLOAD_KERNEL"]])
                else:
                    fingerprint = {"phase": stage, "matchesProducer": True, "buildEvidence": [], "error": None,
                        "productsTreeSHA256": self.products["treeSHA256"], "xctestrunSHA256": self.products["xctestrunSHA256"],
                        "entryCount": self.products["entryCount"]}
                    if stage == "before":
                        fingerprint["derivedDataEntries"] = []
                    else:
                        fingerprint.update(matchesBefore=True, derivedDataDelta={"sha256": M.sha(M.canonical(delta))})
                    (artifact / ("v23-shared-fingerprint-" + stage + ".json")).write_bytes(M.canonical(fingerprint))
                    observation.update(derivedDataInventory=[], fingerprintSHA256=M.sha(M.canonical(fingerprint)), activityLogs=[])
                (artifact / ("phase1-shared-live-" + stage + ".json")).write_bytes(M.canonical(observation))
        return directory, labels

    def test_complete_synthetic_producer_every_consumer_joins_still_have_no_auth_or_runtime_credit(self):
        directory, labels = self.worker_fixture()
        result = self.run_helper(retained_workers=directory)
        self.assertEqual(result["workerJoins"]["status"], "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA")
        self.assertEqual(set(result["workerJoins"]["workers"]), set(labels))
        for facts in result["workerJoins"]["workers"].values():
            self.assertEqual(facts["retainedFacts"]["functionalQualification"], self.gate["PENDING"])
            self.assertIs(facts["retainedFacts"]["liveChecksIndependentlyReexecuted"], False)
            self.assertIs(facts["retainedFacts"]["acceptance"], False)
        self.assertTrue(result["pendingProof"])

    def test_supplied_partial_worker_set_is_refused_instead_of_default_complete(self):
        directory = self.base / "partial-workers"
        directory.mkdir()
        (directory / "producer").mkdir()
        self.refused("complete producer/every-consumer", retained_workers=directory)

    def test_last_consumer_self_consistent_false_archive_join_is_recomputed_and_refused(self):
        directory, labels = self.worker_fixture()
        last = directory / labels[-1]
        receipt_path = last / self.ci["SHARED_RESTORE_RECEIPT"]
        receipt = M.decode(receipt_path.read_bytes())
        receipt["archive"] = dict(receipt["archive"], sha256="F" * 64)
        receipt_path.write_bytes(M.canonical(receipt))
        observation_path = last / "phase1-shared-live-restore.json"
        observation = M.decode(observation_path.read_bytes())
        observation.update(archive=receipt["archive"], receiptSHA256=M.sha(M.canonical(receipt)))
        observation_path.write_bytes(M.canonical(observation))
        self.refused("recomputed TAR join", retained_workers=directory)

    def test_last_consumer_compile_log_is_refused_by_actual_source_checker(self):
        directory, labels = self.worker_fixture()
        (directory / labels[-1] / "test-smoke.log").write_text("SwiftCompile normal arm64\n")
        self.refused("no-rebuild log", retained_workers=directory)


if __name__ == "__main__":
    unittest.main()
