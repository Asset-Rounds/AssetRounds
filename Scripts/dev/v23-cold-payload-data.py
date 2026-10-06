"""Dormant cold-original DATA reader; no extraction, collector or qualification.

This reads the existing cold development namespace. Retained API dictionaries,
manifests, checkpoints and reviews are DATA, never authentication or execution
proof. The public dispatcher and both Phase 1 gate purposes remain closed.
There is deliberately no CLI, output file, cached grant or qualified branch.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat


INPUT_SCHEMA = "v23-cold-payload-data-input.v1"
FACT_SCHEMA = "v23-cold-payload-data-facts.v1"
CONTRACT_PATH = "Scripts/v23-phase1-gates.py"
# Same actual executable contract pinned by the published Stage 2 reader.
CONTRACT_SHA256 = "D97B166EAF2BDEABB7929503014CA4237DAC570561B198EE25CF178DB4AB4B8E"
JSON_BYTES = 32 * 1024 ** 2
ZIP_BYTES = 4 * 1024 ** 3
MAX_FILES = 100000
CHUNK = 1024 * 1024
IDENTITY_KEYS = ("dev", "ino", "mode", "uid", "gid", "nlink", "size", "mtime_ns", "ctime_ns", "flags")
RECEIPTS = ("v23-shared-payload.json", "v23-shared-payload-receipt.json", "v23-shared-restore.json",
            "v23-shared-fingerprint-before.json", "v23-shared-fingerprint-after.json",
            "v23-shared-deriveddata-delta.json")
PENDING = (
    {"dependency": "AUTHENTICATED_ORIGINAL_AND_SOLE_COLLECTOR", "status": "PENDING",
     "reason": "Retained API/attempt/discovery bytes do not authenticate a live fixed-endpoint census or current authority."},
    {"dependency": "FROZEN_GIT_HEAD_TREE", "status": "PENDING",
     "reason": "Actual source bytes are compared; caller head/tree assertions are not independently authenticated Git facts."},
    {"dependency": "SAFE_EXTRACTION_AND_PAYLOAD_CONTENTS", "status": "PENDING",
     "reason": "Outer ZIP bytes are hashed without opening or extracting them; inner TAR, Products and extracted worker equivalence remain unproved."},
    {"dependency": "COMPLETE_LIFETIME_AND_EMITTED_STREAM", "status": "PENDING",
     "reason": "The current cold observation producer emits processLifetimes=PENDING and has no complete lifetime/stream producer."},
    {"dependency": "LIVE_NO_REBUILD_AND_EVERY_METHOD", "status": "PENDING",
     "reason": "Source-bound partition lists, checkpoints and receipt bytes are declarations, not every-method or full process execution proof."},
    {"dependency": "INDEPENDENT_COLD_QUALIFICATION_AND_GATES", "status": "PENDING",
     "reason": "No qualification/review authority, owner acceptance or Phase 1/exact-main lifecycle is granted by this reader."},
)


class Refused(ValueError):
    """A typed, side-effect-free DATA refusal."""
    def __init__(self, dependency, message):
        self.dependency = dependency
        super().__init__(dependency + ": " + message)


def require(condition, message, dependency="COLD_DATA_BINDING"):
    if not condition:
        raise Refused(dependency, message)


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=True, allow_nan=False) + "\n").encode("ascii")


def sha(raw):
    return hashlib.sha256(raw).hexdigest().upper()


def exact(value, expected, message):
    # bool/int aliasing must never turn a numeric assertion into a true flag.
    require(canonical(value) == canonical(expected), message)


def digest(value):
    return type(value) is str and re.fullmatch(r"[0-9A-F]{64}", value) is not None


def decode(raw, *, canonical_bytes=True):
    require(type(raw) is bytes and 0 < len(raw) <= JSON_BYTES, "bounded JSON", "COLD_DATA_SCHEMA")
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate JSON key", "COLD_DATA_SCHEMA")
            result[key] = value
        return result
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(Refused("COLD_DATA_SCHEMA", "nonfinite JSON")))
        encoded = canonical(value)
    except (ValueError, UnicodeError) as error:
        if isinstance(error, Refused):
            raise
        raise Refused("COLD_DATA_SCHEMA", "invalid JSON") from error
    if canonical_bytes:
        require(encoded == raw, "noncanonical JSON", "COLD_DATA_SCHEMA")
    return value


def identity(info):
    return {key: getattr(info, "st_" + key, 0) for key in IDENTITY_KEYS}


def absolute(path):
    value = os.fspath(path)
    require(type(value) is str and value.startswith("/") and "\x00" not in value
            and "\\" not in value and "//" not in value
            and all(part not in (".", "..") for part in value.split("/")),
            "absolute lexical path required", "READ_ONLY_FILESYSTEM")
    return Path(value)


def relative(name):
    require(type(name) is str and name and "\x00" not in name and "\\" not in name
            and all(part not in ("", ".", "..") for part in name.split("/")),
            "closed relative path", "COLD_DATA_SCHEMA")
    return name


class ReadFences:
    """Openat/no-follow reads with full TEN identities and bounded live handles.

    Every acquired descriptor receives one close attempt, including after an
    earlier close/read/fence failure. Cleanup never replaces the first error.
    No raw inode, mode, flag, timestamp or directory is normalized or written.
    """
    def __init__(self):
        self.identities = {}

    def note(self, path, info):
        current = identity(info)
        require(not current["flags"] & 0x40000000, "dataless input", "READ_ONLY_FILESYSTEM")
        previous = self.identities.get(str(path))
        if previous is not None:
            exact(current, previous, "full TEN filesystem identity changed")
        self.identities[str(path)] = current

    def access(self, path, operation, *, directory=False):
        path = absolute(path)
        descriptors, checks, result, error = [], [], None, None
        try:
            require(hasattr(os, "O_NOFOLLOW") and hasattr(os, "O_DIRECTORY"),
                    "no-follow directory support required", "READ_ONLY_FILESYSTEM")
            root_named = os.stat("/", follow_symlinks=False)
            require(stat.S_ISDIR(root_named.st_mode), "regular root directory required", "READ_ONLY_FILESYSTEM")
            self.note(Path("/"), root_named)
            descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            descriptors.append(descriptor)
            root_opened = os.fstat(descriptor)
            exact(identity(root_opened), identity(root_named), "root preopen/opened filesystem identity differs")
            self.note(Path("/"), root_opened)
            checks.append((Path("/"), descriptor, None, None))
            current = Path("/")
            for index, component in enumerate(path.parts[1:]):
                final = index == len(path.parts[1:]) - 1
                is_directory = not final or directory
                flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                if is_directory:
                    flags |= os.O_DIRECTORY
                candidate = current / component
                named = os.stat(component, dir_fd=descriptor, follow_symlinks=False)
                require(stat.S_ISDIR(named.st_mode) if is_directory else
                        stat.S_ISREG(named.st_mode) and named.st_nlink == 1,
                        "regular directory/single-link file required", "READ_ONLY_FILESYSTEM")
                # A no-follow open may materialize a dataless Dropbox leaf.
                # Reject the named type/link/flags/full TEN before that open.
                self.note(candidate, named)
                child = os.open(component, flags, dir_fd=descriptor)
                descriptors.append(child)
                current = candidate
                opened = os.fstat(child)
                exact(identity(opened), identity(named), "preopen/opened filesystem identity differs")
                exact(identity(opened), identity(os.stat(component, dir_fd=descriptor, follow_symlinks=False)),
                      "named/opened filesystem identity differs")
                self.note(current, opened)
                checks.append((current, child, descriptor, component))
                descriptor = child
            result = operation(descriptor)
            for checked, held, parent, component in checks:
                self.note(checked, os.fstat(held))
                if parent is not None:
                    self.note(checked, os.stat(component, dir_fd=parent, follow_symlinks=False))
            self.note(Path("/"), os.stat("/", follow_symlinks=False))
        except BaseException as caught:
            error = caught
        finally:
            for descriptor in reversed(descriptors):
                try:
                    os.close(descriptor)
                except BaseException as caught:
                    if error is None:
                        error = caught
                    elif hasattr(error, "add_note"):
                        error.add_note("additional descriptor close failure: " + type(caught).__name__)
        if error is not None:
            if isinstance(error, OSError):
                raise Refused("READ_ONLY_FILESYSTEM", "open/read/fence/close failed") from error
            raise error
        return result

    def read(self, path, *, limit=JSON_BYTES, capture=True):
        def consume(descriptor):
            before = os.fstat(descriptor)
            require(0 <= before.st_size <= limit, "regular input bound", "READ_ONLY_FILESYSTEM")
            count, checksum, blocks = 0, hashlib.sha256(), []
            while True:
                block = os.read(descriptor, min(CHUNK, limit + 1 - count))
                if not block:
                    break
                count += len(block)
                require(count <= limit, "stream input bound", "READ_ONLY_FILESYSTEM")
                checksum.update(block)
                if capture:
                    blocks.append(block)
            exact(identity(os.fstat(descriptor)), identity(before), "input changed while read")
            require(count == before.st_size, "complete disk read", "READ_ONLY_FILESYSTEM")
            return b"".join(blocks) if capture else {"bytes": count, "SHA256": checksum.hexdigest().upper()}
        return self.access(path, consume)

    def json(self, path):
        return decode(self.read(path))

    def census(self, root):
        root = absolute(root)
        files, pending, directories = set(), [root], 0
        while pending:
            directory = pending.pop()
            directories += 1
            require(directories <= MAX_FILES, "directory traversal bound", "READ_ONLY_FILESYSTEM")
            names = self.access(directory, lambda fd: sorted(os.listdir(fd)), directory=True)
            require(len(names) <= MAX_FILES, "directory census bound", "READ_ONLY_FILESYSTEM")
            for name in names:
                relative(name)
                child = directory / name
                mode = self.access(directory, lambda fd: os.stat(name, dir_fd=fd, follow_symlinks=False).st_mode,
                                   directory=True)
                if stat.S_ISDIR(mode):
                    pending.append(child)
                else:
                    require(stat.S_ISREG(mode), "nonregular census member", "READ_ONLY_FILESYSTEM")
                    files.add(child.relative_to(root).as_posix())
                require(len(files) + len(pending) <= MAX_FILES, "complete census bound", "READ_ONLY_FILESYSTEM")
        return files

    def finish(self):
        for name, before in list(self.identities.items()):
            self.access(Path(name), lambda _: None, directory=stat.S_ISDIR(before["mode"]))


def source_contract(root, fences):
    """Only the exact published pure cold contract is executable; no importer cache."""
    raw = fences.read(root / CONTRACT_PATH)
    require(sha(raw) == CONTRACT_SHA256, "published cold contract bytes differ", "SOURCE_CONTRACT")
    namespace = {"__file__": str(root / CONTRACT_PATH), "__name__": "_cold_data_contract"}
    exec(compile(raw, namespace["__file__"], "exec"), namespace)
    return namespace


def cold_call(contract, name, *args, **kwargs):
    require(name in ("validate_cold_plan", "validate_cold_attempt", "make_cold_plan",
                     "verify_cold_attempt_inputs", "verify_cold_collected_event"), "cold-only contract entry")
    try:
        return contract[name](*args, **kwargs)
    except contract["Refused"] as error:
        raise Refused("COLD_CONTRACT", str(error)) from error


def selection_data(raw, contract):
    """Reconstruct the producer selection from committed partition DATA.

    This does not discover Swift methods or prove any method executed. Its
    ordered declared census is bound to the same cold intent and checkpoints.
    """
    value = decode(raw, canonical_bytes=False)
    require(type(value) is dict and set(value) == {"schema", "sourceCensusHead", "generatedAtHead", "partitions", "sweepOrder"}
            and value["schema"] == "v23-coverage-partitions.v2", "partition source schema", "COLD_DATA_SCHEMA")
    for key in ("sourceCensusHead", "generatedAtHead"):
        require(type(value[key]) is str and re.fullmatch(r"[0-9a-f]{40}", value[key]), "partition provenance")
    partitions, order = value["partitions"], value["sweepOrder"]
    require(type(partitions) is list and 1 <= len(partitions) <= 60 and type(order) is list,
            "partition census bound")
    by_id = {}
    for partition in partitions:
        require(type(partition) is dict and set(partition) == {"id", "tier", "estimatedSeconds", "selectors"},
                "partition keys", "COLD_DATA_SCHEMA")
        identifier, tier, selectors = partition["id"], partition["tier"], partition["selectors"]
        require(type(identifier) is str and re.fullmatch(r"S[0-9]{2}", identifier) and identifier not in by_id,
                "unique partition ID")
        require(tier in ("D50C", "D90S") and type(partition["estimatedSeconds"]) in (int, float)
                and 0 < partition["estimatedSeconds"] <= contract["ROUTE"]["budgets"][tier][2], "partition budget")
        require(type(selectors) is list and 1 <= len(selectors) <= 500
                and all(type(item) is str and re.fullmatch(r"FieldEvidenceAppTests/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+", item)
                        for item in selectors) and (tier != "D90S" or len(selectors) == 1), "partition selector grammar/bound")
        by_id[identifier] = selectors
    require(all(type(item) is str for item in order) and len(order) == len(set(order))
            and set(order) == set(by_id), "exact partition sweep order")
    units = [item for identifier in order for item in by_id[identifier]]
    require(len(units) == len(set(units)), "disjoint declared method census")
    partitions_sha = sha(raw)
    selection = {"schemaVersion": 1, "taskID": "V23-INTEGRATION-20260910", "tier": "D40P", "runUISmoke": False,
        **dict(zip(("setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds", "uiTimeoutSeconds",
                    "totalBudgetSeconds"), contract["ROUTE"]["budgets"]["D40P"])),
        "unitTestSelectors": units, "uiTestSelectors": [], "sharedCoverage": {
            "partitionsPath": contract["PARTITIONS"], "partitionsSHA256": partitions_sha,
            "partitionIDs": order, "partitionID": None, "developmentOnly": True, "acceptance": False}}
    return selection, {"partitionsPath": contract["PARTITIONS"], "partitionsSHA256": partitions_sha,
                       "partitionIDs": order, "selectors": by_id}


def pending_flags(value, message):
    require(type(value) is dict and value.get("developmentOnly") is True and value.get("status") == "INCOMPLETE"
            and value.get("functionalQualification") == "PENDING"
            and all(value.get(key) is False for key in ("providerQualification", "acceptance", "releaseReady")), message)


def validate_transport(root, fences, summary, artifact, claim_sha, files, disk):
    require(type(summary) is dict and set(summary) == {"id", "digest", "downloaded", "transportStatus", "rawZIP", "transportReceipt"},
            "closed raw transport summary", "COLD_DATA_SCHEMA")
    require(type(summary["rawZIP"]) is dict and set(summary["rawZIP"]) == {"path", "bytes", "SHA256"}
            and type(summary["transportReceipt"]) is dict and set(summary["transportReceipt"]) == {"path", "SHA256"},
            "closed raw ZIP/receipt", "COLD_DATA_SCHEMA")
    require(summary["id"] == artifact["id"] and type(summary["id"]) is int
            and summary["digest"] == artifact["digest"] and summary["downloaded"] is True
            and summary["transportStatus"] == "COMPLETE", "complete declared cold transport")
    name = relative(summary["rawZIP"]["path"])
    require(re.fullmatch(r"cold-payload-transports/" + str(artifact["id"]) + r"/[0-9]{6}/raw\.zip", name),
            "cold raw ZIP namespace")
    receipt_name = str(Path(name).with_name("receipt.json"))
    request_name = str(Path(name).with_name("request.json"))
    require(summary["transportReceipt"]["path"] == receipt_name
            and all(item in files for item in (name, receipt_name, request_name)), "manifest-bound cold transport files")
    request, receipt = fences.json(root / request_name), fences.json(root / receipt_name)
    common = {"runID": artifact["workflow_run"]["id"], "runAttempt": 1, "claimSHA256": claim_sha,
        "artifactID": artifact["id"], "apiArtifactSHA256": sha(canonical(artifact)), "apiDigest": artifact["digest"],
        "declaredAPISizeBytes": artifact["size_in_bytes"], "streamLimitBytes": ZIP_BYTES,
        "index": int(Path(name).parent.name), "rawPath": name}
    request_keys = set(common) | {"schema", "atUTC", "ancestors", "initialRawIdentity"}
    require(type(request) is dict and set(request) == request_keys
            and request["schema"] == "v23-cold-payload-transport-request.v1", "cold request schema", "COLD_DATA_SCHEMA")
    exact({key: request[key] for key in common}, common, "cold transport original/API/sole-claim binding")
    receipt_keys = request_keys | {"status", "actualZIPBytes", "actualZIPSHA256", "rawIdentity",
                                  "responseComplete", "durableRaw", "digestVerified", "failureCategory"}
    require(type(receipt) is dict and set(receipt) == receipt_keys
            and receipt["schema"] == "v23-cold-payload-transport.v1", "cold receipt schema", "COLD_DATA_SCHEMA")
    exact({key: receipt[key] for key in request_keys - {"schema", "atUTC"}},
          {key: request[key] for key in request_keys - {"schema", "atUTC"}}, "cold receipt/request bytes")
    # Reuse the actual streamed manifest read, then recheck its full TEN at the
    # end of the entire join. Large raw originals are never needlessly reread.
    actual = disk[name]
    exact(summary["rawZIP"], {"path": name, **actual}, "actual outer ZIP bytes/hash")
    exact(receipt["rawIdentity"], fences.identities[str(root / name)], "retained raw full TEN identity")
    exact({"bytes": receipt["actualZIPBytes"], "SHA256": receipt["actualZIPSHA256"]}, actual, "receipt actual outer ZIP")
    require(actual["bytes"] > 0 and "sha256:" + actual["SHA256"].lower() == artifact["digest"]
            and summary["transportReceipt"]["SHA256"] == files[receipt_name]
            and receipt["status"] == "COMPLETE" and all(receipt[key] is True for key in
                ("responseComplete", "durableRaw", "digestVerified")), "cold complete transport digest/receipt")
    require(type(request["initialRawIdentity"]) is dict and set(request["initialRawIdentity"]) == set(IDENTITY_KEYS)
            and all(type(item) is int for item in request["initialRawIdentity"].values()), "initial raw identity schema")
    stable = ("dev", "ino", "mode", "uid", "gid", "nlink", "flags")
    exact({key: request["initialRawIdentity"][key] for key in stable},
          {key: receipt["rawIdentity"][key] for key in stable}, "raw owned inode/flags changed")
    require(type(request["ancestors"]) is dict, "transport ancestor schema")
    parent = (root / name).parent
    ancestors = {}
    for path in (parent, *parent.parents):
        actual_identity = fences.access(path, lambda fd: identity(os.fstat(fd)), directory=True)
        ancestors[str(path)] = {key: actual_identity[key] for key in ("dev", "ino", "mode", "uid", "gid")}
    exact(request["ancestors"], ancestors, "original transport ancestors changed")
    return {"artifactID": artifact["id"], "rawZIP": {"path": name, **actual},
            "transportReceiptSHA256": files[receipt_name]}


def worker_data(root, fences, label, plan, attempt, run, resolved, selectors, payload_name, contract):
    worker = root / "artifacts" / label
    event = fences.read(worker / "cold-original-event.json", limit=contract["MAX_EVENT_BYTES"])
    binding, admission = fences.json(worker / "cold-event-binding.json"), fences.json(worker / "native-admission.json")
    input_binding = cold_call(contract, "verify_cold_attempt_inputs", attempt, event)
    cold_call(contract, "verify_cold_collected_event", binding, registered_plan_bytes=canonical(plan), original_event_bytes=event,
        api_run=run, tree=plan["tree"], resolved_bytes=canonical(resolved), sources=plan["sources"])
    require(fences.read(worker / "cold-original-plan.json") == canonical(plan), "worker exact cold intent bytes")
    role, partition = ("producer", None) if label == "producer" else ("consumer", label)
    require(type(admission) is dict and "phase1Gate" not in admission, "cold admission namespace")
    exact(admission.get("coldOriginal"), binding, "cold admission event binding")
    exact({key: admission.get(key) for key in ("head", "gitTree", "ref", "runID", "runAttempt", "selectionID")},
          {"head": plan["head"], "gitTree": plan["tree"], "ref": plan["ref"], "runID": str(run["id"]),
           "runAttempt": "1", "selectionID": contract["COLD_SELECTION"]}, "cold worker original identity")
    exact(admission.get("sharedCoverage"), {"role": role, "partitionID": partition, "payloadArtifactName": payload_name,
        "planSHA256": plan["selectionSHA256"], "partitionsSHA256": plan["sources"][contract["PARTITIONS"]]},
        "cold worker role/partition/payload")
    checkpoint = fences.json(worker / "native-checkpoint.json")
    require(type(checkpoint) is dict and "phase1Gate" not in checkpoint, "cold checkpoint namespace")
    exact(checkpoint.get("coldOriginal"), binding, "cold checkpoint original binding")
    exact(checkpoint.get("executedUnitMethods"), [] if role == "producer" else sorted(selectors), "declared checkpoint methods")
    exact(checkpoint.get("executedUIMethods"), [], "cold checkpoint UI methods")
    require(all(checkpoint.get(key) is False for key in ("providerQualification", "acceptance", "releaseReady")),
            "unqualified cold checkpoint")
    stages = ("seal",) if role == "producer" else ("restore", "before", "after")
    observations = {}
    keys = {"schema", "stage", "eventBindingSHA256", "originalEventSHA256", "admissionSHA256", "planSHA256",
            "selectionSHA256", "head", "tree", "runID", "runAttempt", "role", "partitionID", "products", "receiptSHA256",
            "status", "functionalQualification", "processLifetimes", "executionScope", "developmentOnly",
            "providerQualification", "acceptance", "releaseReady"}
    for stage in stages:
        value = fences.json(worker / ("cold-shared-observation-" + stage + ".json"))
        require(type(value) is dict and set(value) == keys and value["schema"] == "v23-cold-shared-live-observation.v1",
                "closed cold observation schema", "COLD_DATA_SCHEMA")
        expected = {"stage": stage, "head": plan["head"], "tree": plan["tree"], "runID": str(run["id"]),
            "runAttempt": "1", "role": role, "partitionID": partition, "executionScope": contract["COLD_PURPOSE"],
            "eventBindingSHA256": sha(canonical(binding)), "originalEventSHA256": sha(event),
            "admissionSHA256": sha(canonical(admission)), "planSHA256": sha(canonical(plan)),
            "selectionSHA256": plan["selectionSHA256"], "processLifetimes": "PENDING"}
        exact({key: value[key] for key in expected}, expected, "cold observation original/role/source binding")
        pending_flags(value, "cold observation cannot grant qualification")
        require(type(value["products"]) is list and type(value["receiptSHA256"]) is dict,
                "observation Products/receipt DATA")
        for name, checksum in value["receiptSHA256"].items():
            require(name in RECEIPTS and digest(checksum) and sha(fences.read(worker / name)) == checksum,
                    "cold observation actual receipt bytes")
        observations[stage] = value
    exact(checkpoint.get("coldSharedObservations"), observations, "checkpoint exact retained observations")
    return {"eventBindingSHA256": sha(canonical(binding)), "admissionSHA256": sha(canonical(admission)),
            "dispatchInputBinding": input_binding,
            "checkpointSHA256": sha(canonical(checkpoint)), "declaredUnitMethods": [] if role == "producer" else sorted(selectors),
            "observations": observations}


def read_cold_payload_data(original_directory, source_root, expected):
    """Return joined, unqualified DATA from one immutable collected cold original.

    expected is a closed caller assertion, not authentication. This API never
    opens an archive, discovers/parses Swift, loads a review or writes evidence.
    Missing original files or unknown schemas refuse; missing genuine producers
    stay typed PENDING in every successful DATA result.
    """
    keys = {"schema", "head", "tree", "runID", "runAttempt", "manifestSHA256"}
    require(type(expected) is dict and set(expected) == keys and expected["schema"] == INPUT_SCHEMA,
            "closed cold DATA input", "COLD_DATA_SCHEMA")
    require(type(expected["runID"]) is int and expected["runID"] > 0 and type(expected["runAttempt"]) is int
            and expected["runAttempt"] == 1 and digest(expected["manifestSHA256"])
            and all(type(expected[key]) is str and re.fullmatch(r"[0-9a-f]{40}", expected[key]) for key in ("head", "tree")),
            "cold DATA caller original identity", "COLD_DATA_SCHEMA")
    root, source, fences = absolute(original_directory), absolute(source_root), ReadFences()
    contract = source_contract(source, fences)
    manifest_raw = fences.read(root / "manifest.json")
    require(sha(manifest_raw) == expected["manifestSHA256"], "caller manifest digest")
    manifest = decode(manifest_raw)
    require(type(manifest) is dict and set(manifest) == {"schema", "runID", "runAttempt", "files", "rawProofSHA256"}
            and manifest["schema"] == "v23-cold-original-manifest.v1", "cold manifest schema", "COLD_DATA_SCHEMA")
    exact({key: manifest[key] for key in ("runID", "runAttempt")},
          {key: expected[key] for key in ("runID", "runAttempt")}, "manifest original identity")
    files = manifest["files"]
    require(type(files) is dict and 0 < len(files) <= MAX_FILES and "manifest.json" not in files
            and all(digest(value) for value in files.values()), "closed manifest file hashes", "COLD_DATA_SCHEMA")
    disk = {}
    for name, checksum in files.items():
        relative(name)
        disk[name] = fences.read(root / name, limit=ZIP_BYTES, capture=False)
        require(disk[name]["SHA256"] == checksum, "retained manifest file digest: " + name)
    exact(sorted(fences.census(root)), sorted(["manifest.json", *files]), "complete original file census")
    registration_raw, attempt_raw = fences.read(root / "cold-registration.json"), fences.read(root / "cold-attempt.json")
    registration, attempt = decode(registration_raw), decode(attempt_raw)
    require(type(registration) is dict and set(registration) == {"schema", "plan", "planSHA256", "dispatchEnabled", "functionalQualification"}
            and registration["schema"] == contract["COLD_REGISTRATION_SCHEMA"], "cold registration schema", "COLD_DATA_SCHEMA")
    plan = cold_call(contract, "validate_cold_plan", registration["plan"])
    exact({key: plan[key] for key in ("head", "tree")}, {key: expected[key] for key in ("head", "tree")}, "caller frozen identity")
    cold_call(contract, "validate_cold_attempt", attempt, plan, registration_raw)
    sources = {name: sha(fences.read(source / name)) for name in contract["SOURCES"]}
    exact(plan["sources"], sources, "actual cold source closure")
    resolved, partitions = selection_data(fences.read(source / contract["PARTITIONS"]), contract)
    exact(cold_call(contract, "make_cold_plan", head=plan["head"], tree=plan["tree"], resolved_bytes=canonical(resolved),
        sources=sources, requested_at=plan["requestedAtUTC"]), plan, "recomputed cold intent/ordered DATA census")
    dispatch_raw = fences.read(root / "dispatch.json")
    dispatch = decode(dispatch_raw)
    pending_flags(dispatch, "cold dispatch pending classification")
    dispatch_bindings = {"coldDispatchSchema": "v23-cold-dispatch.v1", "head": plan["head"], "ref": plan["ref"],
        "runID": expected["runID"], "runAttempt": 1, "kind": "development", "selection": contract["COLD_SELECTION"],
        "lane": plan["route"]["executionLane"], "requestedAtUTC": attempt["requestedAtUTC"], "argv": attempt["argv"],
        "coldPurpose": contract["COLD_PURPOSE"], "coldPlanBytes": attempt["planBytes"], "coldPlanSHA256": attempt["planSHA256"],
        "coldRegistrationSHA256": sha(registration_raw), "coldRegistrationSchema": contract["COLD_REGISTRATION_SCHEMA"],
        "coldAttemptSHA256": sha(attempt_raw), "resolvedSelection": resolved,
        "resolvedSelectionSHA256": plan["selectionSHA256"], "sharedPartitions": partitions}
    require(set(dispatch) == set(dispatch_bindings) | {"url", "coldDiscoverySHA256", "functionalQualification", "status",
        "developmentOnly", "providerQualification", "acceptance", "releaseReady"}, "closed cold dispatch schema", "COLD_DATA_SCHEMA")
    require(dispatch["url"] == "https://github.com/%s/actions/runs/%d" % (plan["route"]["repository"], expected["runID"])
            and digest(dispatch["coldDiscoverySHA256"]), "cold dispatch URL/discovery DATA")
    exact({key: dispatch.get(key) for key in dispatch_bindings}, dispatch_bindings, "cold dispatch retained input bindings")
    claim_raw = fences.read(root / "collector.claim.json")
    exact(decode(claim_raw), {"schema": "v23-cold-sole-collector.v1", "runID": expected["runID"], "runAttempt": 1,
        "collectorID": attempt["collectorID"], "collectorSHA256": sources[contract["COLLECTOR"]],
        "planSHA256": sha(canonical(plan)), "attemptSHA256": sha(attempt_raw), "dispatchSHA256": sha(dispatch_raw),
        "registrationSHA256": sha(registration_raw)}, "retained sole cold claim bindings")
    run = fences.json(root / "run-after-collection.json")
    for name in ("run.json", "run-attempt-1.json", "run-after-collection.json"):
        value = fences.json(root / name)
        require(type(value) is dict and value.get("status") == "completed", "completed retained original DATA")
        origin = {"id": expected["runID"], "run_attempt": 1, "workflow_id": attempt["workflowID"], "head_sha": plan["head"],
            "head_branch": plan["ref"].removeprefix("refs/heads/"), "path": plan["route"]["workflow"], "event": "workflow_dispatch"}
        exact({key: value.get(key) for key in origin}, origin, "retained API original identity")
        for key in ("repository", "head_repository"):
            require(type(value.get(key)) is dict and value[key].get("full_name") == plan["route"]["repository"]
                    and type(value[key].get("id")) is int and value[key]["id"] == attempt["repositoryID"], "retained API repository identity")
        created = value.get("created_at")
        require(type(created) is str and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", created), "retained creation timestamp")
        require(datetime.datetime.fromisoformat(created.replace("Z", "+00:00")) >=
                datetime.datetime.fromisoformat(attempt["requestedAtUTC"].replace("Z", "+00:00")), "retained original predates attempt")
        require(value.get("conclusion") == run.get("conclusion"), "retained original conclusion changed")
    proof_raw = fences.read(root / "cold-raw-proof.json")
    proof = decode(proof_raw)
    pending_flags(proof, "raw proof cannot grant qualification")
    require(set(proof) == {"schema", "status", "runID", "runAttempt", "planSHA256", "head", "tree", "originalAttribution",
        "artifacts", "dispatchInputBindings", "problems", "functionalQualification", "developmentOnly", "providerQualification",
        "simulatorProtection", "physicalProtection", "physicalProtectionReleaseBlocker", "acceptance", "releaseReady", "pendingPredicates"}
        and proof["schema"] == "v23-cold-raw-proof.v1" and manifest["rawProofSHA256"] == sha(proof_raw),
        "closed cold raw proof schema/hash", "COLD_DATA_SCHEMA")
    exact({key: proof[key] for key in ("simulatorProtection", "physicalProtection", "physicalProtectionReleaseBlocker")},
        {"simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED", "physicalProtectionReleaseBlocker": True},
        "raw proof prospective protection split")
    exact(proof["pendingPredicates"], ["payload DATA reader", "cold/no-rebuild/lifetime proof", "independent qualification"],
          "raw proof remains incomplete")
    require(type(proof["problems"]) is list and all(type(value) is str for value in proof["problems"]), "raw proof problems DATA")
    exact({key: proof.get(key) for key in ("runID", "runAttempt", "head", "tree", "planSHA256")},
        {"runID": expected["runID"], "runAttempt": 1, "head": plan["head"], "tree": plan["tree"], "planSHA256": sha(canonical(plan))},
        "cold raw proof original binding")
    listing = fences.json(root / "artifacts.json")
    exact(fences.json(root / "artifacts-after-collection.json"), listing, "retained artifact census changed")
    require(type(listing) is dict and set(listing) == {"total_count", "artifacts"} and type(listing["artifacts"]) is list
            and type(listing["total_count"]) is int and listing["total_count"] == len(listing["artifacts"]), "closed complete artifact census")
    labels = ["producer", *partitions["partitionIDs"]]
    payload_name = "v23-shared-payload-%d-1-%s" % (expected["runID"], plan["head"])
    prefix = "ios-ci-native-github-" + contract["COLD_SELECTION"]
    names = {"producer": "%s-producer-%d-1" % (prefix, expected["runID"]), "payload": payload_name,
        **{label: "%s-consumer-%s-%d-1" % (prefix, label, expected["runID"]) for label in partitions["partitionIDs"]}}
    artifacts = listing["artifacts"]
    require(all(type(value) is dict and type(value.get("id")) is int and value["id"] > 0
                and type(value.get("name")) is str for value in artifacts), "artifact identity schema")
    require(len({value["id"] for value in artifacts}) == len(artifacts)
            and len({value["name"] for value in artifacts}) == len(artifacts)
            and set(value["name"] for value in artifacts) == set(names.values()), "unique complete cold artifact identities")
    require(type(proof.get("artifacts")) is dict and set(proof["artifacts"]) == set(names), "raw proof artifact census")
    transports = {}
    for label, name in names.items():
        artifact = next(value for value in artifacts if value["name"] == name)
        require(type(artifact.get("workflow_run")) is dict, "artifact origin DATA")
        origin = {"id": expected["runID"], "head_sha": plan["head"],
            "head_branch": plan["ref"].removeprefix("refs/heads/"), "repository_id": attempt["repositoryID"],
            "head_repository_id": attempt["repositoryID"]}
        exact({key: artifact["workflow_run"].get(key) for key in origin}, origin, "artifact original/head/repository binding")
        require(type(artifact.get("digest")) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"])
                and artifact.get("expired") is False and type(artifact.get("size_in_bytes")) is int
                and 0 < artifact["size_in_bytes"] <= ZIP_BYTES, "artifact digest/API-size schema")
        transports[label] = validate_transport(root, fences, proof["artifacts"][label], artifact, sha(claim_raw), files, disk)
    workers = {label: worker_data(root, fences, label, plan, attempt, run, resolved,
        [] if label == "producer" else partitions["selectors"][label], payload_name, contract) for label in labels}
    exact(proof["dispatchInputBindings"], {label: value["dispatchInputBinding"] for label, value in workers.items()},
          "raw proof exact worker original-input bindings")
    fences.finish()
    return {"schema": FACT_SCHEMA, "status": "DATA_ONLY_UNQUALIFIED", "kind": "development",
        "executionScope": contract["COLD_PURPOSE"], "selection": contract["COLD_SELECTION"],
        "head": plan["head"], "tree": plan["tree"], "runID": expected["runID"], "runAttempt": 1,
        "manifestSHA256": sha(manifest_raw), "planSHA256": sha(canonical(plan)), "sourceSHA256": sources,
        "executableSourceSHA256": {CONTRACT_PATH: CONTRACT_SHA256}, "rawTransports": transports,
        "workerJoins": workers, "declaredConclusion": run.get("conclusion"), "rawProofProblems": proof.get("problems"),
        "pendingProof": [dict(value) for value in PENDING], "functionalQualification": "PENDING", "developmentOnly": True,
        "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED",
        "physicalProtectionReleaseBlocker": True, "providerQualification": False, "acceptance": False,
        "gateQualification": False, "exactMainVerification": False, "releaseReady": False}


# V2 is additive. V1 schemas, bodies and six PENDING facts remain exact.
INPUT_SCHEMA_V2 = "v23-cold-payload-data-input.v2"
FACT_SCHEMA_V2 = "v23-cold-payload-data-facts.v2"
QUALIFICATION_CONTRACT_SCHEMA_V2 = "v23-cold-qualification-contract.v2"
EMITTED_NATIVE_SOURCE_PATH_V2 = "Scripts/v23-native-ci.py"
# Exact Native candidate Source dependency; independent review/current binding remain Root prerequisites.
EMITTED_NATIVE_SOURCE_SHA256_V2 = "82B9D320FF17048A6B58E6F9B127FC510D5C239687B5302DCFF2C95F3B58390A"
STRONGER_CLAIMS_V2 = ("totalPolicyCallCounts", "exhaustiveAppKernelLifetimeCohorts",
                      "perPIDDescriptorRetirement", "exactRepeatCounts")


def qualification_contract_v2():
    """Prospective requirements only. No supplied review or count grants a gate."""
    return {"schema": QUALIFICATION_CONTRACT_SCHEMA_V2, "status": "CONTRACT_ONLY_NO_AUTHORITY",
        "executionScope": "cold-shared-route-development-v1",
        "requiredEmittedTransport": ["AUTHENTIC_ORIGINAL_RUNTIME_AND_SOURCE_CONTEXT",
            "SOURCE_WIRED_AUTHORITATIVE_RAW_SINK", "ACTUAL_SHARED_LOCK_AND_SEALED_STATE",
            "POSITIVE_TERMINAL_SYNC_AND_ONCE_OWNER_CLOSES", "COMPLETE_COMMITTED_RAW_AND_DERIVED_STREAM_UNION",
            "REFUSAL_OF_INTERRUPTION_UNRESOLVED_WRITES_OR_ERRORS"],
        "remainingRequirements": ["AUTHENTICATED_ORIGINAL_AND_SOLE_COLLECTOR", "FROZEN_GIT_HEAD_TREE",
            "SAFE_EXTRACTION_AND_PAYLOAD_CONTENTS", "LIVE_NO_REBUILD_AND_EVERY_METHOD",
            "INDEPENDENT_COLD_QUALIFICATION_AND_GATES"],
        "strongerClaims": {name: "UNPROVEN" for name in STRONGER_CLAIMS_V2},
        "functionalQualification": "PENDING", "providerQualification": False, "acceptance": False,
        "gateQualification": False, "exactMainVerification": False, "releaseReady": False,
        "executionAuthority": False}


def _emitted_native_v2(source, fences, facts):
    """Only exact reviewed Source supplies the existing finite raw parser."""
    require(digest(EMITTED_NATIVE_SOURCE_SHA256_V2), "reviewed Native Source pin pending",
            "EMITTED_NATIVE_SOURCE_REVIEWED_PIN")
    raw = fences.read(source / EMITTED_NATIVE_SOURCE_PATH_V2)
    require(sha(raw) == EMITTED_NATIVE_SOURCE_SHA256_V2
            == facts["sourceSHA256"][EMITTED_NATIVE_SOURCE_PATH_V2],
            "exact reviewed/frozen Native parser Source", "SOURCE_CONTRACT")
    namespace = {"__file__": str(source / EMITTED_NATIVE_SOURCE_PATH_V2), "__name__": "_cold_data_native_v2"}
    exec(compile(raw, namespace["__file__"], "exec"), namespace)
    return namespace


def _emitted_close_rows_v2(rows, roles=None):
    require(type(rows) is list and 0 < len(rows) <= 100000 and all(type(row) is dict for row in rows),
            "emitted owner rows", "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT")
    closed = [row for row in rows if "closeEntered" in row]
    require(closed and all(set(row) == {"role", "descriptor", "closeEntered", "closeReturned", "closeUncertain", "error"}
            and type(row["role"]) is str and type(row["descriptor"]) is int and row["descriptor"] >= 0
            and row["closeEntered"] is True and row["closeReturned"] is True
            and row["closeUncertain"] is False and row["error"] is None for row in closed)
            and len({row["descriptor"] for row in closed}) == len(closed)
            and len({row["role"] for row in closed}) == len(closed)
            and all(row.get("error") is None and row.get("closeUncertain", False) is False for row in rows),
            "emitted positive distinct once owner closes", "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT")
    if roles is not None:
        exact(sorted(row["role"] for row in closed), sorted(roles), "emitted complete closed owner roster")


def _read_cold_payload_v1_with_fences_v2(root, source, expected, fences):
    """Reuse the exact V1 code with one call-local fence factory, no globals mutation."""
    import types
    original = read_cold_payload_data
    namespace = dict(original.__globals__)
    require(namespace["ReadFences"] is ReadFences, "V1 exact original fence constructor", "SOURCE_CONTRACT")
    namespace["ReadFences"] = lambda: fences
    bound = types.FunctionType(original.__code__, namespace, original.__name__,
                               original.__defaults__, original.__closure__)
    bound.__kwdefaults__ = original.__kwdefaults__
    return bound(root, source, expected)


def _manifest_read_v2(root, fences, files, path, *, limit=JSON_BYTES, capture=True):
    """Join these actual bytes to the seeded final manifest without a second ZIP pass."""
    try:
        name = absolute(path).relative_to(root).as_posix()
    except ValueError as error:
        raise Refused("COLD_DATA_BINDING", "V2 retained read outside original") from error
    require(name in files and digest(files[name]), "V2 retained manifest member")
    value = fences.read(path, limit=limit, capture=capture)
    checksum = sha(value) if capture else value["SHA256"]
    exact(checksum, files[name], "V2 actual retained raw manifest hash: " + name)
    return value


def _emitted_worker_v2(root, source, fences, label, plan, facts, native, manifest_files):
    """Recompute retained emitted DATA; never authenticate a live original."""
    worker = root / "artifacts" / label
    proof_raw = _manifest_read_v2(root, fences, manifest_files, worker / native["COLD_DURABLE_PROOF"])
    proof = decode(proof_raw)
    keys = {"schema", "status", "interrupted", "nativeExitStatus", "countsAreTotalInvocations",
        "trailingRepeatCountsMayBeUnobserved", "processLifetimesProven", "appDescriptorRetirementProven",
        "functionalQualification", "providerQualification", "acceptance", "releaseReady", "io", "firstError",
        "context", "bindingSHA256", "authoritativePath", "observed", "files", "emittedBoundary"}
    require(type(proof) is dict and set(proof) == keys and proof["schema"] == "v23-cold-emitted-durable-proof.v1",
            "closed emitted proof schema", "COLD_DATA_SCHEMA")
    require(proof["status"] == "SEALED_EMITTED_TRANSPORT_ONLY" and proof["interrupted"] is False
            and type(proof["nativeExitStatus"]) is int and proof["nativeExitStatus"] == 0 and proof["firstError"] is None
            and proof["countsAreTotalInvocations"] is False and proof["trailingRepeatCountsMayBeUnobserved"] is True
            and proof["processLifetimesProven"] is False and proof["appDescriptorRetirementProven"] is False
            and proof["functionalQualification"] == "PENDING"
            and all(proof[key] is False for key in ("providerQualification", "acceptance", "releaseReady"))
            and proof["emittedBoundary"] == "SOURCE_WIRED_APPEND_CLOSED_BY_ACTUAL_SHARED_LOCK_AND_SEALED_STATE",
            "emitted scoped terminal refuses stronger claims/errors/interruption", "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT")
    _emitted_close_rows_v2(proof["io"])
    require(any(row.get("role") == "authoritativeReader" and row.get("lockEntered") is True
                and row.get("lockReturned") is True and row.get("nonblocking") is True for row in proof["io"])
            and any(row.get("role") == "authoritativeReader" and row.get("unlockReturned") is True for row in proof["io"])
            and any(row.get("role") == "authoritativeReader" and row.get("terminalDataFsyncReturned") is True for row in proof["io"])
            and any(row.get("role") == "sealState" and row.get("writeReturned") is True
                and row.get("fsyncReturned") is True and row.get("readbackExact") is True for row in proof["io"]),
            "emitted actual lock/seal/terminal sync observations", "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT")
    context = proof["context"]
    context_keys = {"schema", "executionScope", "head", "tree", "runID", "runAttempt", "role", "partitionID",
        "originalEventSHA256", "eventBindingSHA256", "admissionSHA256", "planSHA256", "selectionSHA256",
        "writerSourceSHA256", "simulatorUDID", "durableSinkPath", "durableSinkBindingSHA256"}
    require(type(context) is dict and set(context) == context_keys, "closed emitted original context", "COLD_DATA_SCHEMA")
    joins = facts["workerJoins"][label]
    expected_context = {"schema": native["COLD_DURABLE_CONTEXT_SCHEMA"], "executionScope": facts["executionScope"],
        "head": facts["head"], "tree": facts["tree"], "runID": str(facts["runID"]), "runAttempt": "1",
        "role": "consumer", "partitionID": label, "originalEventSHA256": sha(_manifest_read_v2(root, fences, manifest_files, worker / "cold-original-event.json")),
        "eventBindingSHA256": joins["eventBindingSHA256"], "admissionSHA256": joins["admissionSHA256"],
        "planSHA256": facts["planSHA256"], "selectionSHA256": plan["selectionSHA256"]}
    exact({key: context[key] for key in expected_context}, expected_context, "emitted exact original/source/partition context")
    writer_path = native["SIMULATOR_DIAGNOSTIC_SOURCE_PATH"]
    writer_sha = sha(fences.read(source / writer_path))
    require(writer_sha == native["SIMULATOR_DIAGNOSTIC_SOURCE_SHA256"] == context["writerSourceSHA256"]
            and digest(proof["bindingSHA256"]) and proof["bindingSHA256"] == context["durableSinkBindingSHA256"]
            and type(context["simulatorUDID"]) is str
            and re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", context["simulatorUDID"]),
            "emitted current writer/binding/runtime context DATA", "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT")
    sink_path = absolute(context["durableSinkPath"])
    require(proof["authoritativePath"] == str(sink_path / "EMITTED.jsonl"), "emitted original authoritative path")
    sink = worker / native["COLD_DURABLE_ROOT"]
    exact(sorted(fences.access(sink, lambda fd: os.listdir(fd), directory=True)),
          ["BINDING.json", "EMITTED.jsonl", "STATE"], "emitted complete retained sink roster")
    header_raw = _manifest_read_v2(root, fences, manifest_files, sink / "BINDING.json")
    header = decode(header_raw)
    require(type(header) is dict and set(header) == {"schema", "originalContext", "directoryIdentity", "dataIdentity", "stateIdentity"}
            and header["schema"] == native["COLD_DURABLE_SCHEMA"] and sha(header_raw) == proof["bindingSHA256"],
            "emitted immutable retained header", "COLD_DATA_SCHEMA")
    exact(header["originalContext"], {key: value for key, value in context.items()
            if key not in ("durableSinkPath", "durableSinkBindingSHA256")}, "emitted exact original header context")
    for name in ("directoryIdentity", "dataIdentity", "stateIdentity"):
        value = header[name]
        require(type(value) is dict and set(value) == {"device", "inode", "mode", "uid", "gid", "links", "flags"}
                and all(type(item) is str and re.fullmatch(r"0|[1-9][0-9]*", item) for item in value.values()),
                "emitted original identity provenance", "COLD_DATA_SCHEMA")
    require(_manifest_read_v2(root, fences, manifest_files, sink / "STATE", limit=8) == b"SEALED\n", "emitted actual retained SEALED state",
            "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT")
    stream_hashes, stream_bytes = {}, {}
    def consume(stream, line):
        stream_hashes.setdefault(stream, hashlib.sha256()).update(line)
        stream_bytes[stream] = stream_bytes.get(stream, 0) + len(line)
    try:
        observed = fences.access(sink / "EMITTED.jsonl", lambda fd:
            native["_cold_durable_parse"](fd, context, proof["bindingSHA256"], lambda: None, consume))
    except ValueError as error:
        if isinstance(error, Refused):
            raise
        raise Refused("COMPLETE_AUTHENTIC_EMITTED_TRANSPORT", "Native durable raw parser refused") from error
    raw_name = (sink / "EMITTED.jsonl").relative_to(root).as_posix()
    require(raw_name in manifest_files and digest(manifest_files[raw_name]), "V2 emitted raw manifest member")
    exact(observed["rawSHA256"], manifest_files[raw_name], "V2 emitted parsed raw manifest hash")
    exact(proof["observed"], observed, "emitted independently recomputed complete raw/committed union")
    files = [{"name": row["streamID"] + ".jsonl", "bytes": row["bytes"], "sha256": row["sha256"]}
             for row in observed["streams"]]
    exact(proof["files"], files, "emitted exact derived stream union")
    _emitted_close_rows_v2(proof["io"], ["sinkDirectory", "bindingReader", "authoritativeReader", "sealState",
        "artifactOutputParent", "transportDirectory", *["derivedStream:" + row["streamID"] for row in observed["streams"]]])
    output = worker / native["SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY"]
    exact(sorted(fences.access(output, lambda fd: os.listdir(fd), directory=True)), sorted(row["name"] for row in files),
          "emitted exact derived directory membership")
    for row in files:
        relative(row["name"])
        actual = _manifest_read_v2(root, fences, manifest_files, output / row["name"],
            limit=native["SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES"], capture=False)
        exact(actual, {"bytes": row["bytes"], "SHA256": row["sha256"]}, "emitted derived actual raw bytes")
        require(stream_bytes[row["name"][:-6]] == row["bytes"]
                and stream_hashes[row["name"][:-6]].hexdigest().upper() == row["sha256"], "emitted consumed stream hash")
    transport = decode(_manifest_read_v2(root, fences, manifest_files, worker / native["SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS"]))
    require(type(transport) is dict and transport.get("status") == ("AVAILABLE" if files else "ZERO_USE")
            and "error" not in transport and transport.get("collectionMode") == "completed", "emitted same completed disposition")
    exact(transport.get("files"), files, "emitted status exact stream union")
    return {"schema": "v23-cold-retained-emitted-transport-facts.v1", "proofSHA256": sha(proof_raw),
        "observed": observed, "files": files, "committedEmittedBytesComplete": True,
        "countsAreTotalInvocations": False, "processLifetimesProven": False, "physicalRetirementProven": False,
        "functionalQualification": "PENDING", "providerQualification": False, "acceptance": False, "releaseReady": False}


def read_cold_payload_data_v2(original_directory, source_root, expected):
    """Read final retained DATA with a prospective scope split; no qualification."""
    require(type(expected) is dict and set(expected) == {"schema", "head", "tree", "runID", "runAttempt", "manifestSHA256"}
            and expected["schema"] == INPUT_SCHEMA_V2, "closed cold DATA v2 input", "COLD_DATA_SCHEMA")
    root, source, fences = absolute(original_directory), absolute(source_root), ReadFences()
    first, result = None, None
    try:
        manifest_raw = fences.read(root / "manifest.json")
        require(sha(manifest_raw) == expected["manifestSHA256"], "v2 caller manifest digest")
        manifest = decode(manifest_raw)
        require(type(manifest) is dict and type(manifest.get("files")) is dict
                and 0 < len(manifest["files"]) <= MAX_FILES
                and all(digest(value) for value in manifest["files"].values()),
                "V2 seeded complete manifest hashes", "COLD_DATA_SCHEMA")
        manifest_files = dict(manifest["files"])
        native_seed = fences.read(source / EMITTED_NATIVE_SOURCE_PATH_V2)
        facts = _read_cold_payload_v1_with_fences_v2(root, source, {**expected, "schema": INPUT_SCHEMA}, fences)
        require(sha(native_seed) == facts["sourceSHA256"][EMITTED_NATIVE_SOURCE_PATH_V2], "v2 seeded Native closure changed")
        registration = decode(_manifest_read_v2(root, fences, manifest_files, root / "cold-registration.json"))
        plan = registration["plan"]
        require(sha(canonical(plan)) == facts["planSHA256"], "v2 retained plan changed")
        native = _emitted_native_v2(source, fences, facts)
        consumers = sorted(set(facts["workerJoins"]) - {"producer"})
        emitted = {label: _emitted_worker_v2(root, source, fences, label, plan, facts, native, manifest_files)
                   for label in consumers}
        retained = decode(_manifest_read_v2(root, fences, manifest_files, root / "cold-emitted-retained-facts.json"))
        require(type(retained) is dict and set(retained) == {"schema", "runID", "runAttempt", "head", "tree", "planSHA256",
            "consumerFacts", "countsAreTotalInvocations", "functionalQualification", "providerQualification", "acceptance", "releaseReady"}
            and retained["schema"] == "v23-cold-emitted-retained-facts.v1" and retained["countsAreTotalInvocations"] is False
            and retained["functionalQualification"] == "PENDING"
            and all(retained[key] is False for key in ("providerQualification", "acceptance", "releaseReady")),
            "closed retained emitted facts cannot grant qualification", "COLD_DATA_SCHEMA")
        exact({key: retained[key] for key in ("runID", "runAttempt", "head", "tree", "planSHA256")},
              {key: facts[key] for key in ("runID", "runAttempt", "head", "tree", "planSHA256")}, "retained emitted original binding")
        require(type(retained["consumerFacts"]) is dict and set(retained["consumerFacts"]) == set(consumers),
                "retained exact consumer emitted census")
        for label, value in retained["consumerFacts"].items():
            require(type(value) is dict and set(value) == set(emitted[label]) | {"retainedReadCloseRows"},
                    "closed retained consumer emitted facts", "COLD_DATA_SCHEMA")
            _emitted_close_rows_v2(value["retainedReadCloseRows"], ["retainedSink", "retainedBinding",
                "retainedSealState", "retainedEmittedBytes", "retainedDerivedDirectory",
                *["retainedDerived:" + row["name"] for row in emitted[label]["files"]]])
            exact({key: value[key] for key in emitted[label]}, emitted[label], "retained emitted facts equal recomputed raw DATA")
        require(fences.read(root / "manifest.json") == manifest_raw, "v2 final manifest unchanged")
        result = {"schema": FACT_SCHEMA_V2, "status": "DATA_ONLY_UNQUALIFIED", "kind": "development",
            "executionScope": facts["executionScope"], "selection": facts["selection"], "head": facts["head"], "tree": facts["tree"],
            "runID": facts["runID"], "runAttempt": facts["runAttempt"], "manifestSHA256": facts["manifestSHA256"],
            "v1Data": facts, "qualificationContract": qualification_contract_v2(),
            "emittedTransport": {"status": "DATA_BOUND_RECOMPUTED", "consumerFacts": emitted},
            "strongerClaims": {name: "UNPROVEN" for name in STRONGER_CLAIMS_V2},
            "pendingProof": [dict(row) for row in PENDING if row["dependency"] != "COMPLETE_LIFETIME_AND_EMITTED_STREAM"] + [
                {"dependency": "COMPLETE_AUTHENTIC_EMITTED_TRANSPORT", "status": "PENDING",
                 "reason": "Retained raw/SEALED/union DATA is re-read; live authentic runtime/source accessibility and late-write exclusion require Root qualification."}],
            "functionalQualification": "PENDING", "developmentOnly": True, "simulatorProtection": "UNSUPPORTED",
            "physicalProtection": "UNVERIFIED/DEFERRED", "physicalProtectionReleaseBlocker": True,
            "providerQualification": False, "acceptance": False, "gateQualification": False,
            "exactMainVerification": False, "releaseReady": False, "executionAuthority": False}
    except BaseException as error:
        first = error
    try:
        fences.finish()
    except BaseException as error:
        if first is None:
            first = error
        elif hasattr(first, "add_note"):
            try:
                first.add_note("additional v2 final fence failure: " + type(error).__name__)
            except BaseException:
                # Diagnostic annotation cannot replace the already retained first object.
                pass
    if first is not None:
        raise first
    return result
