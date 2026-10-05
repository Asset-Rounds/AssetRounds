"""Finite synthetic cold DATA cases; never original, native or qualification proof.

Root runs this source after independent review. These fixtures use the actual
published cold-contract constructors, with one synthetic declared partition.
No existing predicate, census, workflow or test expectation is changed.
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock


PATH = Path(__file__).with_name("v23-cold-payload-data.py")
SPEC = importlib.util.spec_from_file_location("cold_payload_data_candidate", PATH)
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
SOURCE_ROOT = PATH.parents[2]


class ColdPayloadDataTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="synthetic-cold-data-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.source, self.original = self.base / "source", self.base / "original"
        self.source.mkdir()
        self.original.mkdir()
        self.contract = M.source_contract(SOURCE_ROOT, M.ReadFences())
        for name in self.contract["SOURCES"]:
            destination = self.source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((SOURCE_ROOT / name).read_bytes())
        coverage = {"schema": "v23-coverage-partitions.v2", "sourceCensusHead": "3" * 40,
            "generatedAtHead": "4" * 40, "sweepOrder": ["S01"], "partitions": [{"id": "S01", "tier": "D50C",
            "estimatedSeconds": 1, "selectors": ["FieldEvidenceAppTests/SyntheticColdTests/testOnly"]}]}
        raw = M.canonical(coverage)
        (self.source / self.contract["PARTITIONS"]).write_bytes(raw)
        self.selected, self.partitions = M.selection_data(raw, self.contract)
        sources = {name: M.sha((self.source / name).read_bytes()) for name in self.contract["SOURCES"]}
        self.plan = self.contract["make_cold_plan"](head="1" * 40, tree="2" * 40,
            resolved_bytes=M.canonical(self.selected), sources=sources, requested_at="2026-09-29T12:00:00Z")
        registration = {"schema": self.contract["COLD_REGISTRATION_SCHEMA"], "plan": self.plan,
            "planSHA256": M.sha(M.canonical(self.plan)), "dispatchEnabled": False, "functionalQualification": "PENDING"}
        registration_raw = M.canonical(registration)
        self.put("cold-registration.json", registration_raw)
        observations = {"repository": {"id": 77, "full_name": self.contract["REPOSITORY"]},
            "workflow": {"id": 7, "path": self.contract["ROUTE"]["workflow"], "state": "active"},
            "refs": {"integration": {"ref": self.plan["ref"], "object": {"type": "commit", "sha": self.plan["head"]}},
                     "main": {"ref": "refs/heads/main", "object": {"type": "commit", "sha": self.contract["BASE_MAIN"]}}},
            "headRuns": {"total_count": 0, "workflow_runs": []},
            "activeRuns": {status: {"total_count": 0, "workflow_runs": []} for status in self.contract["ACTIVE_RUN_STATUSES"]}}
        self.attempt = self.contract["make_cold_attempt"](self.plan, registration_raw, collector_id="a" * 32,
            requested_at="2026-09-29T12:01:00Z", observations=observations, ledger_bytes="", attempt_names=[])
        self.put_json("cold-attempt.json", self.attempt)
        self.dispatch = {"coldDispatchSchema": "v23-cold-dispatch.v1", "runID": 123, "runAttempt": 1,
            "head": self.plan["head"], "ref": self.plan["ref"], "selection": self.contract["COLD_SELECTION"],
            "kind": "development", "lane": self.contract["ROUTE"]["executionLane"], "requestedAtUTC": self.attempt["requestedAtUTC"],
            "url": "https://github.com/%s/actions/runs/123" % self.contract["REPOSITORY"], "argv": self.attempt["argv"],
            "resolvedSelection": self.selected, "resolvedSelectionSHA256": self.plan["selectionSHA256"],
            "coldPurpose": self.contract["COLD_PURPOSE"], "coldPlanBytes": self.attempt["planBytes"],
            "coldPlanSHA256": self.attempt["planSHA256"], "coldRegistrationSHA256": self.attempt["registrationSHA256"],
            "coldRegistrationSchema": self.contract["COLD_REGISTRATION_SCHEMA"], "coldAttemptSHA256": M.sha(M.canonical(self.attempt)),
            "coldDiscoverySHA256": "D" * 64, "sharedPartitions": self.partitions,
            "functionalQualification": "PENDING", "status": "INCOMPLETE", "developmentOnly": True,
            "providerQualification": False, "acceptance": False, "releaseReady": False}
        self.put_json("dispatch.json", self.dispatch)
        self.claim = {"schema": "v23-cold-sole-collector.v1", "runID": 123, "runAttempt": 1,
            "collectorID": self.attempt["collectorID"], "collectorSHA256": sources[self.contract["COLLECTOR"]],
            "planSHA256": self.attempt["planSHA256"], "attemptSHA256": M.sha(M.canonical(self.attempt)),
            "dispatchSHA256": M.sha(M.canonical(self.dispatch)), "registrationSHA256": M.sha(registration_raw)}
        self.put_json("collector.claim.json", self.claim)
        self.run = {"id": 123, "run_attempt": 1, "workflow_id": 7, "head_sha": self.plan["head"],
            "head_branch": self.plan["ref"].removeprefix("refs/heads/"), "path": self.contract["ROUTE"]["workflow"],
            "event": "workflow_dispatch", "repository": {"id": 77, "full_name": self.contract["REPOSITORY"]},
            "head_repository": {"id": 77, "full_name": self.contract["REPOSITORY"]},
            "created_at": "2026-09-29T12:01:01Z", "status": "completed", "conclusion": "success"}
        for name in ("run.json", "run-attempt-1.json", "run-after-collection.json"):
            self.put_json(name, self.run)
        self.event = M.canonical({"repository": {"full_name": self.contract["REPOSITORY"]}, "ref": self.plan["ref"],
                                 "inputs": self.contract["cold_dispatch_inputs"](self.plan)})
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": self.contract["REPOSITORY"],
            "GITHUB_REF": self.plan["ref"], "GITHUB_SHA": self.plan["head"], "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_WORKFLOW_SHA": self.plan["head"],
            "GITHUB_WORKFLOW_REF": self.contract["REPOSITORY"] + "/" + self.contract["ROUTE"]["workflow"] + "@" + self.plan["ref"]}
        self.binding = self.contract["bind_cold_original_event"](self.event, environment, head=self.plan["head"],
            tree=self.plan["tree"], resolved_bytes=M.canonical(self.selected), sources=sources)
        payload_name = "v23-shared-payload-123-1-" + self.plan["head"]
        prefix = "ios-ci-native-github-" + self.contract["COLD_SELECTION"]
        names = {"producer": prefix + "-producer-123-1", "S01": prefix + "-consumer-S01-123-1", "payload": payload_name}
        summaries, artifacts = {}, []
        for index, (label, name) in enumerate(names.items(), 20):
            # Deliberately opaque bytes: reader must not try to open an archive.
            raw = ("synthetic opaque raw " + label).encode("ascii")
            artifact = {"id": index, "name": name, "digest": "sha256:" + M.sha(raw).lower(),
                "size_in_bytes": len(raw) + 7, "expired": False, "workflow_run": {"id": 123,
                    "head_sha": self.plan["head"], "head_branch": self.run["head_branch"],
                    "repository_id": 77, "head_repository_id": 77}}
            artifacts.append(artifact)
            relative_raw = "cold-payload-transports/%d/000000/raw.zip" % index
            path = self.put(relative_raw, b"")
            initial = M.identity(path.stat())
            path.write_bytes(raw)
            final = M.identity(path.stat())
            ancestors = {str(parent): {key: getattr(parent.stat(), "st_" + key) for key in ("dev", "ino", "mode", "uid", "gid")}
                         for parent in (path.parent, *path.parent.parents)}
            request = {"schema": "v23-cold-payload-transport-request.v1", "atUTC": "2026-09-29T12:02:00Z",
                "runID": 123, "runAttempt": 1, "claimSHA256": M.sha(M.canonical(self.claim)), "artifactID": index,
                "apiArtifactSHA256": M.sha(M.canonical(artifact)), "apiDigest": artifact["digest"],
                "declaredAPISizeBytes": artifact["size_in_bytes"], "streamLimitBytes": M.ZIP_BYTES,
                "index": 0, "rawPath": relative_raw, "ancestors": ancestors, "initialRawIdentity": initial}
            receipt = {**request, "schema": "v23-cold-payload-transport.v1", "status": "COMPLETE",
                "actualZIPBytes": len(raw), "actualZIPSHA256": M.sha(raw), "rawIdentity": final,
                "responseComplete": True, "durableRaw": True, "digestVerified": True, "failureCategory": None}
            self.put_json(str(Path(relative_raw).with_name("request.json")), request)
            receipt_name = str(Path(relative_raw).with_name("receipt.json"))
            self.put_json(receipt_name, receipt)
            summaries[label] = {"id": index, "digest": artifact["digest"], "downloaded": True, "transportStatus": "COMPLETE",
                "rawZIP": {"path": relative_raw, "bytes": len(raw), "SHA256": M.sha(raw)},
                "transportReceipt": {"path": receipt_name, "SHA256": M.sha(M.canonical(receipt))}}
        for label in ("producer", "S01"):
            role, partition = ("producer", None) if label == "producer" else ("consumer", label)
            worker = "artifacts/" + label + "/"
            record = {"coldOriginal": self.binding, "head": self.plan["head"], "gitTree": self.plan["tree"],
                "ref": self.plan["ref"], "runID": "123", "runAttempt": "1", "selectionID": self.contract["COLD_SELECTION"],
                "sharedCoverage": {"role": role, "partitionID": partition, "payloadArtifactName": payload_name,
                    "planSHA256": self.plan["selectionSHA256"], "partitionsSHA256": sources[self.contract["PARTITIONS"]]}}
            self.put(worker + "cold-original-event.json", self.event)
            self.put_json(worker + "cold-original-plan.json", self.plan)
            self.put_json(worker + "cold-event-binding.json", self.binding)
            self.put_json(worker + "native-admission.json", record)
            receipt_name = "v23-shared-payload.json"
            self.put_json(worker + receipt_name, {"syntheticTestOnly": True, "acceptance": False})
            live = {}
            for stage in (("seal",) if role == "producer" else ("restore", "before", "after")):
                value = {"schema": "v23-cold-shared-live-observation.v1", "stage": stage,
                    "eventBindingSHA256": M.sha(M.canonical(self.binding)), "originalEventSHA256": M.sha(self.event),
                    "admissionSHA256": M.sha(M.canonical(record)), "planSHA256": self.attempt["planSHA256"],
                    "selectionSHA256": self.plan["selectionSHA256"], "head": self.plan["head"], "tree": self.plan["tree"],
                    "runID": "123", "runAttempt": "1", "role": role, "partitionID": partition,
                    "products": [{"path": "synthetic-product", "type": "file", "size": 4,
                                  "mode": 0o644, "sha256": M.sha(b"DATA")}],
                    "receiptSHA256": {receipt_name: M.sha((self.original / (worker + receipt_name)).read_bytes())},
                    "status": "INCOMPLETE", "functionalQualification": "PENDING", "processLifetimes": "PENDING",
                    "executionScope": self.contract["COLD_PURPOSE"], "developmentOnly": True,
                    "providerQualification": False, "acceptance": False, "releaseReady": False}
                live[stage] = value
                self.put_json(worker + "cold-shared-observation-" + stage + ".json", value)
            checkpoint = {"coldOriginal": self.binding,
                "executedUnitMethods": [] if role == "producer" else self.selected["unitTestSelectors"], "executedUIMethods": [],
                "coldSharedObservations": live, "providerQualification": False, "acceptance": False, "releaseReady": False}
            self.put_json(worker + "native-checkpoint.json", checkpoint)
        listing = {"total_count": len(artifacts), "artifacts": artifacts}
        self.put_json("artifacts.json", listing)
        self.put_json("artifacts-after-collection.json", listing)
        self.proof = {"schema": "v23-cold-raw-proof.v1", "status": "INCOMPLETE", "runID": 123, "runAttempt": 1,
            "planSHA256": self.attempt["planSHA256"], "head": self.plan["head"], "tree": self.plan["tree"],
            "originalAttribution": {"status": "DISCOVERED_PENDING_PROOF", "retentionOnly": True, "observations": []},
            "artifacts": summaries, "dispatchInputBindings": {label: self.contract["verify_cold_attempt_inputs"](self.attempt, self.event)
                for label in ("producer", "S01")}, "problems": ["synthetic DATA only"],
            "functionalQualification": "PENDING", "developmentOnly": True, "providerQualification": False,
            "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED", "physicalProtectionReleaseBlocker": True,
            "acceptance": False, "releaseReady": False,
            "pendingPredicates": ["payload DATA reader", "cold/no-rebuild/lifetime proof", "independent qualification"]}
        self.put_json("cold-raw-proof.json", self.proof)
        self.reseal()

    def put(self, name, raw):
        path = self.original / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        return path

    def put_json(self, name, value):
        return self.put(name, M.canonical(value))

    def change(self, name, transform):
        value = json.loads((self.original / name).read_bytes())
        transform(value)
        self.put_json(name, value)

    def reseal(self):
        files = {path.relative_to(self.original).as_posix(): M.sha(path.read_bytes())
                 for path in self.original.rglob("*") if path.is_file() and path.name != "manifest.json"}
        manifest = {"schema": "v23-cold-original-manifest.v1", "runID": 123, "runAttempt": 1, "files": files,
            "rawProofSHA256": M.sha((self.original / "cold-raw-proof.json").read_bytes())}
        raw = M.canonical(manifest)
        self.put("manifest.json", raw)
        self.expected = {"schema": M.INPUT_SCHEMA, "head": self.plan["head"], "tree": self.plan["tree"],
                         "runID": 123, "runAttempt": 1, "manifestSHA256": M.sha(raw)}

    def read(self):
        return M.read_cold_payload_data(self.original, self.source, self.expected)

    def refused(self, phrase):
        before = {str(path): (path.read_bytes(), M.identity(path.stat()))
                  for path in self.original.rglob("*") if path.is_file() and not path.is_symlink()}
        with self.assertRaisesRegex(M.Refused, phrase):
            self.read()
        after = {str(path): (path.read_bytes(), M.identity(path.stat()))
                 for path in self.original.rglob("*") if path.is_file() and not path.is_symlink()}
        self.assertEqual(before, after)

    def test_actual_cold_shapes_join_but_all_execution_and_gate_dependencies_stay_pending(self):
        result = self.read()
        self.assertEqual(result["status"], "DATA_ONLY_UNQUALIFIED")
        self.assertEqual(set(result["workerJoins"]), {"producer", "S01"})
        self.assertEqual(result["workerJoins"]["S01"]["declaredUnitMethods"], self.selected["unitTestSelectors"])
        self.assertEqual(result["rawTransports"]["payload"]["rawZIP"], self.proof["artifacts"]["payload"]["rawZIP"])
        self.assertEqual({row["dependency"] for row in result["pendingProof"]}, {row["dependency"] for row in M.PENDING})
        self.assertTrue(all(row["status"] == "PENDING" for row in result["pendingProof"]))
        self.assertTrue(result["physicalProtectionReleaseBlocker"])
        self.assertTrue(all(result[key] is False for key in ("providerQualification", "acceptance", "gateQualification",
                                                           "exactMainVerification", "releaseReady")))

    def test_success_preserves_every_original_byte_and_full_ten(self):
        before = {str(path): (path.read_bytes(), M.identity(path.stat())) for path in self.original.rglob("*") if path.is_file()}
        self.read()
        after = {str(path): (path.read_bytes(), M.identity(path.stat())) for path in self.original.rglob("*") if path.is_file()}
        self.assertEqual(before, after)

    def test_phase1_gate_namespace_cannot_be_relabelled_as_cold(self):
        self.change("cold-registration.json", lambda row: row["plan"].update(schema=self.contract["SCHEMA"], kind="gate"))
        self.reseal()
        self.refused("COLD_CONTRACT")

    def test_bool_run_attempt_and_unknown_input_fields_refuse(self):
        self.expected["runAttempt"] = True
        self.refused("caller original identity")
        self.expected["runAttempt"] = 1
        self.expected["qualificationApproved"] = True
        self.refused("closed cold DATA input")

    def test_wrong_caller_head_and_manifest_hash_refuse(self):
        self.expected["head"] = "f" * 40
        self.refused("caller frozen identity")
        self.expected["head"] = self.plan["head"]
        self.expected["manifestSHA256"] = "0" * 64
        self.refused("caller manifest digest")

    def test_changed_raw_bytes_fail_even_when_the_manifest_is_resealed(self):
        name = self.proof["artifacts"]["payload"]["rawZIP"]["path"]
        (self.original / name).write_bytes(b"changed original bytes")
        self.reseal()
        self.refused("actual outer ZIP bytes/hash")

    def test_artifact_from_foreign_original_refuses(self):
        for name in ("artifacts.json", "artifacts-after-collection.json"):
            self.change(name, lambda row: row["artifacts"][0]["workflow_run"].update(id=456))
        self.reseal()
        self.refused("artifact original/head/repository binding")

    def test_duplicate_artifact_ids_refuse_before_transport_join(self):
        for name in ("artifacts.json", "artifacts-after-collection.json"):
            self.change(name, lambda row: row["artifacts"][1].update(id=row["artifacts"][0]["id"]))
        self.reseal()
        self.refused("unique complete cold artifact identities")

    def test_claim_from_another_collector_refuses(self):
        self.change("collector.claim.json", lambda row: row.update(collectorID="b" * 32))
        self.reseal()
        self.refused("sole cold claim bindings")

    def test_observation_claimed_lifetime_or_qualification_cannot_become_proof(self):
        self.change("artifacts/S01/cold-shared-observation-after.json", lambda row: row.update(processLifetimes={"complete": True}))
        self.reseal()
        self.refused("observation original/role/source binding")

    def test_observation_extra_stream_or_review_pin_is_unknown_schema(self):
        self.change("artifacts/producer/cold-shared-observation-seal.json", lambda row: row.update(reviewApproved=True))
        self.reseal()
        self.refused("closed cold observation schema")

    def test_forged_qualification_flag_cannot_become_data_success(self):
        self.change("artifacts/producer/cold-shared-observation-seal.json", lambda row: row.update(providerQualification=True))
        self.reseal()
        self.refused("observation cannot grant qualification")

    def test_changed_receipt_bytes_refuse(self):
        self.put_json("artifacts/S01/v23-shared-payload.json", {"syntheticTestOnly": "changed"})
        self.reseal()
        self.refused("actual receipt bytes")

    def test_checkpoint_cannot_drop_a_declared_partition_method(self):
        self.change("artifacts/S01/native-checkpoint.json", lambda row: row.update(executedUnitMethods=[]))
        self.reseal()
        self.refused("declared checkpoint methods")

    def test_raw_proof_cannot_substitute_worker_input_bindings(self):
        self.change("cold-raw-proof.json", lambda row: row["dispatchInputBindings"]["S01"].update(inputSHA256="0" * 64))
        self.reseal()
        self.refused("raw proof exact worker original-input bindings")

    def test_unlisted_file_or_symlink_cannot_hide_outside_the_manifest(self):
        self.put("unlisted.txt", b"extra DATA")
        self.refused("complete original file census")
        (self.original / "unlisted.txt").unlink()
        (self.original / "unlisted-link").symlink_to(self.original / "dispatch.json")
        self.refused("nonregular census member")

    def test_hardlinked_input_refuses_without_rewriting_either_name(self):
        os.link(self.original / "dispatch.json", self.original / "dispatch-alias.json")
        self.refused("single-link file required")

    def test_unpinned_contract_refuses_before_source_execution(self):
        (self.source / M.CONTRACT_PATH).write_bytes(b"raise RuntimeError('never execute this')\n")
        self.refused("published cold contract bytes differ")

    def test_bound_source_change_refuses(self):
        path = self.source / "Scripts/build-smoke.sh"
        path.write_bytes(path.read_bytes() + b"\n# synthetic change\n")
        self.refused("actual cold source closure")

    def test_duplicate_json_keys_refuse(self):
        self.put("dispatch.json", b'{"kind":"development","kind":"gate"}\n')
        self.reseal()
        self.refused("duplicate JSON key")

    def test_nonfinite_json_cannot_hide_in_data_only_products(self):
        path = self.original / "artifacts/producer/cold-shared-observation-seal.json"
        path.write_bytes(path.read_bytes().replace(b'"size":4', b'"size":1e400'))
        self.reseal()
        self.refused("invalid JSON")

    def test_failed_declared_original_stays_failed_unqualified_data(self):
        for name in ("run.json", "run-attempt-1.json", "run-after-collection.json"):
            self.change(name, lambda row: row.update(conclusion="failure"))
        self.reseal()
        result = self.read()
        self.assertEqual(result["declaredConclusion"], "failure")
        self.assertEqual(result["status"], "DATA_ONLY_UNQUALIFIED")
        self.assertFalse(result["acceptance"])


class ReadFenceBehaviorTests(unittest.TestCase):
    def test_banned_named_component_is_refused_before_its_child_open(self):
        # Every actual filesystem input is an ordinary disposable local fixture.
        # Only one named stat is synthetic; no dataless inode is ever created.
        variants = (("dataless-leaf", False, {"st_flags": 0x40000000}, "dataless input"),
                    ("dataless-ancestor", True, {"st_flags": 0x40000000}, "dataless input"),
                    ("symlink-type", False, {"st_mode": 0o120600}, "single-link file required"),
                    ("multiple-links", False, {"st_nlink": 2}, "single-link file required"))
        for label, ancestor, changed, phrase in variants:
            with self.subTest(label=label), tempfile.TemporaryDirectory(prefix="synthetic-preopen-fence-") as temporary:
                base = Path(temporary).resolve()
                blocked = base / "blocked-component"
                if ancestor:
                    blocked.mkdir()
                    target = blocked / "leaf"
                else:
                    target = blocked
                target.write_bytes(b"DATA")
                fields = {"st_" + key: value for key, value in M.identity(blocked.stat()).items()}
                named = type("SyntheticNamedStat", (), {**fields, **changed})()
                actual_stat, actual_open = os.stat, os.open
                attempts = []
                def stat_record(name, *args, **kwargs):
                    if name == blocked.name and kwargs.get("dir_fd") is not None:
                        return named
                    return actual_stat(name, *args, **kwargs)
                def open_record(name, *args, **kwargs):
                    if name == blocked.name and kwargs.get("dir_fd") is not None:
                        attempts.append(name)
                        raise AssertionError("banned component reached child-open")
                    return actual_open(name, *args, **kwargs)
                operation = mock.Mock(side_effect=AssertionError("banned component reached reader"))
                with mock.patch.object(M.os, "stat", side_effect=stat_record), mock.patch.object(M.os, "open", side_effect=open_record):
                    with self.assertRaisesRegex(M.Refused, phrase):
                        M.ReadFences().access(target, operation)
                self.assertEqual(attempts, [])
                operation.assert_not_called()

    def test_changed_inode_after_read_refuses_at_the_final_join_fence(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-read-fence-") as temporary:
            path = Path(temporary).resolve() / "raw"
            path.write_bytes(b"DATA")
            fences = M.ReadFences()
            self.assertEqual(fences.read(path), b"DATA")
            replacement = path.with_name("replacement")
            replacement.write_bytes(b"DATA")
            os.replace(replacement, path)
            with self.assertRaisesRegex(M.Refused, "full TEN"):
                fences.finish()

    def test_first_read_error_survives_close_error_and_every_handle_is_attempted_once(self):
        with tempfile.TemporaryDirectory(prefix="synthetic-read-fence-") as temporary:
            path = Path(temporary).resolve() / "raw"
            path.write_bytes(b"DATA")
            actual_open, actual_close = os.open, os.close
            opened, closed = [], []
            def open_record(*args, **kwargs):
                descriptor = actual_open(*args, **kwargs)
                opened.append(descriptor)
                return descriptor
            def close_record(descriptor):
                closed.append(descriptor)
                actual_close(descriptor)
                if len(closed) == 1:
                    raise OSError("synthetic post-close failure")
            with mock.patch.object(M.os, "open", side_effect=open_record), mock.patch.object(M.os, "close", side_effect=close_record):
                first = M.Refused("SYNTHETIC_FIRST_ERROR", "read failed")
                with self.assertRaises(M.Refused) as captured:
                    M.ReadFences().access(path, lambda _: (_ for _ in ()).throw(first))
            self.assertIs(captured.exception, first)
            self.assertEqual(closed, list(reversed(opened)))
            self.assertEqual(len(closed), len(set(closed)))

    def test_flags_and_ctime_are_part_of_the_identity_fence(self):
        fields = {"st_" + key: 0 for key in M.IDENTITY_KEYS}
        fields["st_mode"] = 0o100600
        fields["st_nlink"] = 1
        first = type("SyntheticStat", (), fields)()
        fences = M.ReadFences()
        fences.note(Path("/synthetic-only"), first)
        for name, value in (("st_flags", 64), ("st_ctime_ns", 1)):
            changed = type("SyntheticStat", (), {**fields, name: value})()
            with self.assertRaisesRegex(M.Refused, "full TEN"):
                fences.note(Path("/synthetic-only"), changed)


if __name__ == "__main__":
    unittest.main()
