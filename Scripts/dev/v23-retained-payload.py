"""Dormant offline retained-payload facts; no collector, CLI or gate activation.

All envelope/API/original identifiers are supplied DATA, not authentication.
This module performs no network, native replay, qualification or state rewrite.
Only the literal reviewed executable CI/kernel versions below may be loaded.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import struct
import tarfile
from types import SimpleNamespace
import zipfile
import zlib


INPUT_SCHEMA = "v23-retained-payload-input.v1"
FACT_SCHEMA = "v23-retained-payload-facts.v1"
COLD_INPUT_SCHEMA_V2 = "v23-cold-retained-payload-input.v2"
COLD_FACT_SCHEMA_V2 = "v23-cold-retained-payload-facts.v2"
COLD_PENDING_V2 = (
    "authenticated original API census, attempt/discovery and sole-collector authority",
    "frozen Git head/tree and archived-source provenance authentication",
    "complete authentic original-bound emitted diagnostic transport",
    "actual live safe-extraction, no-rebuild and every-method execution proof",
    "complete job/download/command/runtime facts and genuine independent review",
    "versioned cold qualification, candidate gates, owner review and exact-main lifecycle",
)
COLD_SCOPE_V2 = {
    "developmentOnly": True, "authentication": False, "qualification": False,
    "providerQualification": False, "acceptance": False, "releaseReady": False,
    "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED",
    "physicalProtectionReleaseBlocker": True, "emittedTransport": "PENDING",
    "totalPolicyCallCountProven": False, "exhaustiveKernelProcessCohortProven": False,
    "perPIDDescriptorRetirementProven": False, "exactCheckpointRepeatProven": False,
}
COLD_UNPROVEN_V2 = (
    "total policy-call counts", "exhaustive kernel process cohorts",
    "per-PID descriptor retirement", "exact checkpoint repeat",
)
ZIP_BYTES = 4 * 1024**3
ZIP_EXPANDED_BYTES = 4 * 1024**3
ZIP_MEMBERS = 100000
TAR_BYTES = 2 * 1024**3
TAR_MEMBERS = 100000
JSON_BYTES = 32 * 1024**2
TAR_EXTENSION_BYTES = 64 * 1024
CHUNK = 1024 * 1024
TAR_NAME = "FieldEvidencePayload.tar"
DIGEST_NAME = TAR_NAME + ".sha256"
METADATA = "v23-shared-payload.json"
EXECUTABLE_SOURCES = {
    "Scripts/v23-native-ci.py": "7cdc2c72c2bef8eb911e2ac433a5b4f4b38b66621e0e6b43435d9d0162f2ff57",
    "Scripts/v23-phase1-gates.py": "d97b166eaf2bdeabb7929503014ca4237dac570561b198ee25cf178db4ab4b8e",
    "Scripts/s10-4-build-payload.py": "ea731fd64278d3ab242956bf2f36d486254903a10f5f8bc17c65de3d10397521",
    "Scripts/v23-selection-generator.py": "c9cca4ff93227290f9d867e9ab19e574dca26ce4cdbf6b12e748bf63325452e1",
}
PENDING = (
    "authenticated original API census, attempt/discovery and sole-collector authority",
    "frozen Git head/tree and archived-source provenance authentication",
    "complete original diagnostic process lifetimes and emitted-stream continuity",
    "actual live safe-extraction, no-rebuild and every-method execution proof",
    "complete job/download/command/runtime facts and genuine independent review",
    "closed cold qualification, candidate gates, owner review and exact-main lifecycle",
)


class Refused(ValueError):
    """Refusal preserves inputs and any exclusively owned partial destination."""


def require(value, message):
    if not value:
        raise Refused(message)


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"),
                       ensure_ascii=True, allow_nan=False) + "\n").encode("ascii")


def sha(raw):
    return hashlib.sha256(raw).hexdigest().upper()


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def decode(raw):
    require(0 < len(raw) <= JSON_BYTES, "bounded JSON bytes")
    value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                       parse_constant=lambda _: (_ for _ in ()).throw(Refused("nonfinite JSON")))
    require(canonical(value) == raw, "canonical factual JSON bytes")
    return value


def snapshot(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
            info.st_nlink, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def durable_fsync(descriptor):
    """No unsupported-platform fallback: a failed sync cannot publish success."""
    os.fsync(descriptor)


def clean_absolute(path):
    path = Path(path)
    require(path.is_absolute() and str(path) == os.path.normpath(str(path)), "absolute canonical path spelling")
    return path


def directory_chain(path):
    """Held no-follow descriptors for every ancestor; caller closes every FD."""
    path = clean_absolute(path)
    handles = []
    try:
        handles.append(os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW))
        for part in path.parts[1:]:
            handles.append(os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                                   dir_fd=handles[-1]))
        return handles
    except BaseException:
        for handle in reversed(handles):
            os.close(handle)
        raise


def regular_open(path):
    path = clean_absolute(path)
    handles = directory_chain(path.parent)
    try:
        descriptor = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK,
                             dir_fd=handles[-1])
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, "single-link regular input")
        require(snapshot(info) == snapshot(os.stat(path.name, dir_fd=handles[-1], follow_symlinks=False)),
                "named input differs from held input")
        return descriptor, info, handles
    except BaseException:
        if "descriptor" in locals():
            os.close(descriptor)
        for handle in reversed(handles):
            os.close(handle)
        raise


def regular_finish(path, descriptor, before, handles):
    try:
        require(snapshot(os.fstat(descriptor)) == snapshot(before)
                == snapshot(os.stat(Path(path).name, dir_fd=handles[-1], follow_symlinks=False)),
                "input changed during read")
        # Reopen the spelling, rejecting ancestor replacement/aliases as well.
        fresh = directory_chain(Path(path).parent)
        try:
            require([(os.fstat(h).st_dev, os.fstat(h).st_ino) for h in handles]
                    == [(os.fstat(h).st_dev, os.fstat(h).st_ino) for h in fresh], "input ancestor changed")
        finally:
            for handle in reversed(fresh):
                os.close(handle)
    finally:
        os.close(descriptor)
        for handle in reversed(handles):
            os.close(handle)


def regular_bytes(path, limit=JSON_BYTES):
    descriptor, before, handles = regular_open(path)
    try:
        require(0 <= before.st_size <= limit, "regular input byte bound")
        result = bytearray()
        while True:
            chunk = os.read(descriptor, min(CHUNK, limit - len(result) + 1))
            if not chunk:
                break
            require(len(result) + len(chunk) <= limit, "regular input first-excess bytes")
            result.extend(chunk)
        require(len(result) == before.st_size, "regular input size changed")
        return bytes(result)
    finally:
        regular_finish(path, descriptor, before, handles)


class Owned:
    def __init__(self, path):
        self.path = clean_absolute(path)
        self.parents = directory_chain(self.path.parent)
        self.fd = None
        try:
            os.mkdir(self.path.name, 0o700, dir_fd=self.parents[-1])
            self.fd = os.open(self.path.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                              dir_fd=self.parents[-1])
            self.identity = os.fstat(self.fd)
            require(self.identity.st_uid == os.getuid() and stat.S_IMODE(self.identity.st_mode) == 0o700,
                    "exclusive private owned destination")
            durable_fsync(self.fd)
            durable_fsync(self.parents[-1])
            self.check()
        except BaseException:
            self.close()
            raise

    def check(self):
        fresh = directory_chain(self.path)
        try:
            require([(os.fstat(h).st_dev, os.fstat(h).st_ino) for h in self.parents]
                    == [(os.fstat(h).st_dev, os.fstat(h).st_ino) for h in fresh[:-1]],
                    "destination ancestor changed")
            current = os.fstat(fresh[-1])
            require((current.st_dev, current.st_ino, current.st_uid, stat.S_IMODE(current.st_mode))
                    == (self.identity.st_dev, self.identity.st_ino, os.getuid(), 0o700),
                    "owned destination identity changed")
        finally:
            for handle in reversed(fresh):
                os.close(handle)

    def write(self, name, raw):
        self.check()
        require("/" not in name and name not in (".", ".."), "fixed receipt filename")
        require(type(raw) is bytes and 0 < len(raw) <= JSON_BYTES, "bounded owned receipt bytes")
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.fd)
        try:
            with os.fdopen(descriptor, "wb", closefd=False) as stream:
                require(stream.write(raw) == len(raw), "complete owned receipt write")
                stream.flush()
                durable_fsync(descriptor)
            durable_fsync(self.fd)
        finally:
            os.close(descriptor)
        self.check()

    def copy(self, source, name, limit, receipts):
        self.check()
        descriptor, before, handles = regular_open(source)
        target = None
        count, digest = 0, hashlib.sha256()
        receipts[name] = {"source": str(source), "state": "PARTIAL_OWNED_COPY", "bytes": 0}
        try:
            target = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.fd)
            require(before.st_size <= limit, "raw input declared byte bound")
            while True:
                chunk = os.read(descriptor, min(CHUNK, limit - count + 1))
                if not chunk:
                    break
                require(count + len(chunk) <= limit, "raw input first-excess bytes")
                view = memoryview(chunk)
                while view:
                    written = os.write(target, view)
                    require(written > 0, "raw copy made no progress")
                    digest.update(view[:written])
                    count += written
                    view = view[written:]
            require(count == before.st_size, "raw input size changed")
        finally:
            receipts[name].update(bytes=count, sha256=digest.hexdigest().upper(),
                                  sourceStat=list(snapshot(before)))
            try:
                if target is not None:
                    try:
                        durable_fsync(target)
                        durable_fsync(self.fd)
                    finally:
                        os.close(target)
            finally:
                regular_finish(source, descriptor, before, handles)
        receipts[name]["state"] = "COMPLETE_OWNED_COPY"
        receipts[name]["ownedStat"] = list(snapshot((self.path / name).lstat()))
        self.check()
        return receipts[name]

    def sync_tree(self):
        """Fsync the bounded owned projection, with held no-follow identities.

        Files precede containing directories; the original parent follows the
        root. No cleanup or link traversal is permitted, including on failure.
        """
        self.check()
        pending = [(self.path, snapshot(os.fstat(self.fd)), False)]
        files = directories = total = census_bytes = 0
        states = hashlib.sha256()
        while pending:
            path, expected, finishing = pending.pop()
            handles = directory_chain(path)
            try:
                descriptor = handles[-1]
                require(snapshot(os.fstat(descriptor)) == expected, "durable directory changed")
                if finishing:
                    durable_fsync(descriptor)
                    require(snapshot(os.fstat(descriptor)) == expected, "directory changed during fsync")
                    continue
                directories += 1
                require(files + directories <= TAR_MEMBERS + 16, "durable projection member bound")
                pending.append((path, expected, True))
                with os.scandir(descriptor) as scan:
                    for entry in scan:
                        child = path / entry.name
                        relative = child.relative_to(self.path).as_posix()
                        info = os.stat(entry.name, dir_fd=descriptor, follow_symlinks=False)
                        state = snapshot(info)
                        encoded = canonical({"path": relative, "identity": list(state)})
                        census_bytes += len(encoded)
                        require(census_bytes <= JSON_BYTES, "durable projection census byte bound")
                        states.update(encoded)
                        if stat.S_ISDIR(info.st_mode):
                            pending.append((child, state, False))
                            continue
                        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, "durable single-link regular file")
                        files += 1
                        total += info.st_size
                        require(files + directories <= TAR_MEMBERS + 16 and
                                total <= ZIP_BYTES + 2 * TAR_BYTES + 3 * JSON_BYTES + 256,
                                "durable projection byte/member bound")
                        fd = os.open(entry.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=descriptor)
                        try:
                            require(snapshot(os.fstat(fd)) == state, "durable file changed before fsync")
                            durable_fsync(fd)
                            require(snapshot(os.fstat(fd)) == state ==
                                    snapshot(os.stat(entry.name, dir_fd=descriptor, follow_symlinks=False)),
                                    "durable file changed during fsync")
                        finally:
                            os.close(fd)
            finally:
                for handle in reversed(handles):
                    os.close(handle)
        durable_fsync(self.parents[-1])
        self.check()
        return {"schema": "v23-retained-payload-durable-tree.v1", "status": "FSYNCED_OWNED_DATA_PROJECTION",
                "files": files, "directories": directories, "bytes": total,
                "visitedIdentitySHA256": states.hexdigest().upper()}

    def close(self):
        try:
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None
        finally:
            for handle in reversed(self.parents):
                os.close(handle)
            self.parents = []


def source_modules(root):
    """Execute actual bounded pinned source bytes, never a caller-selected verifier."""
    root = clean_absolute(root)
    result = {}
    for relative, expected in EXECUTABLE_SOURCES.items():
        raw = regular_bytes(root / relative)
        require(hashlib.sha256(raw).hexdigest() == expected, "unsupported executable source: " + relative)
        namespace = {"__name__": "v23_retained_source", "__file__": str(root / relative)}
        exec(compile(raw, str(root / relative), "exec"), namespace)
        result[relative] = namespace
    ci = result["Scripts/v23-native-ci.py"]
    gate = result["Scripts/v23-phase1-gates.py"]
    kernel = result["Scripts/s10-4-build-payload.py"]
    generator = result["Scripts/v23-selection-generator.py"]
    # The unchanged CI checker normally loads these paths again. Keep its loader
    # dependency on the exact already verified executable bytes, closing that
    # additional caller-path execution race without embedding verifier text.
    def pinned_kernel(requested_root):
        require(Path(requested_root) == root, "source kernel root changed")
        return kernel
    def pinned_gate(requested_root):
        require(Path(requested_root) == root, "source gate root changed")
        return SimpleNamespace(**gate)
    def pinned_generator(requested_root):
        require(Path(requested_root) == root, "source generator root changed")
        return SimpleNamespace(**generator)
    ci["load_payload_kernel"] = pinned_kernel
    ci["load_phase1_gates"] = pinned_gate
    ci["load_selection_generator"] = pinned_generator
    return ci, gate, kernel


def source_closure(root, gate):
    return {relative: sha(regular_bytes(root / relative)) for relative in gate["SOURCES"]}


def envelope_facts(value, root, ci, gate, *, cold=False):
    keys = {"schema", "plan", "runID", "runAttempt", "payloadArtifact"}
    if cold:
        keys.add("originalEventSHA256")
    require(type(value) is dict and set(value) == keys
            and value["schema"] == (COLD_INPUT_SCHEMA_V2 if cold else INPUT_SCHEMA), "closed factual envelope")
    if cold:
        require(type(value["originalEventSHA256"]) is str
                and re.fullmatch(r"[0-9A-F]{64}", value["originalEventSHA256"]), "cold original event digest DATA")
    plan = gate["validate_cold_plan" if cold else "validate_plan"](value["plan"])
    require(plan["selection"] == ci["COLD_SELECTION_ID" if cold else "SHARED_SELECTION_ID"], "shared payload plan only")
    require(type(value["runID"]) is int and value["runID"] > 0
            and type(value["runAttempt"]) is int and value["runAttempt"] == 1, "declared frozen original IDs")
    sources = source_closure(root, gate)
    require(sources == plan["sources"], "source closure differs from frozen plan DATA")
    resolved = ci["shared_selection"](root)
    rebuilt = gate["make_cold_plan" if cold else "make_plan"](purpose=plan["purpose"], head=plan["head"], tree=plan["tree"],
        selection=plan["selection"], resolved_bytes=ci["canonical"](resolved), sources=sources,
        requested_at=plan["requestedAtUTC"])
    require(canonical(rebuilt) == canonical(plan), "source-resolved ordered selection differs")
    artifact = value["payloadArtifact"]
    require(type(artifact) is dict, "raw API artifact DATA object")
    origin = artifact.get("workflow_run")
    name = "v23-shared-payload-%d-1-%s" % (value["runID"], plan["head"])
    require(type(artifact.get("id")) is int and artifact["id"] > 0 and artifact.get("expired") is False
            and artifact.get("name") == name and type(artifact.get("size_in_bytes")) is int
            and artifact["size_in_bytes"] > 0 and type(artifact.get("digest")) is str
            and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"]), "declared outer API artifact grammar")
    require(type(origin) is dict and type(origin.get("id")) is int and origin["id"] == value["runID"]
            and origin.get("head_sha") == plan["head"]
            and origin.get("head_branch") == plan["ref"].removeprefix("refs/heads/"), "declared API original join")
    return plan, resolved, sources


def zip_preflight(path):
    """Bound central-directory allocation BEFORE ZipFile's eager constructor.

    Exactly two ordinary EOCD entries; per-member ZIP64 sizes are supported by
    ZipFile. ZIP64 EOCD/multidisk/ambiguous trailing records are refused: no
    permitted inner TAR can need an archive-level 4GiB offset/count extension.
    """
    size = path.stat().st_size
    require(22 <= size <= ZIP_BYTES, "outer ZIP byte bound")
    with path.open("rb") as stream:
        stream.seek(max(0, size - (65535 + 22)))
        tail = stream.read(65535 + 22)
        hits = []
        for offset in range(len(tail) - 21):
            if tail[offset:offset + 4] != b"PK\x05\x06":
                continue
            fields = struct.unpack_from("<4s4H2IH", tail, offset)
            if offset + 22 + fields[-1] == len(tail):
                hits.append((offset, fields))
        require(len(hits) == 1, "single closed ZIP end record")
        offset, (_, disk, start_disk, on_disk, count, cd_size, cd_offset, _) = hits[0]
        require(disk == start_disk == 0 and on_disk == count == 2 and count <= ZIP_MEMBERS,
                "closed two-member ZIP directory count before allocation")
        require(92 <= cd_size <= 2 * (46 + 3 * 65535) and cd_offset + cd_size == size - len(tail) + offset,
                "bounded exact ZIP central directory before allocation")
        stream.seek(cd_offset)
        directory = stream.read(cd_size)
        cursor = 0
        for unused in range(2):
            require(cursor + 46 <= len(directory) and directory[cursor:cursor + 4] == b"PK\x01\x02",
                    "ZIP central header")
            name, extra, comment, member_disk = struct.unpack_from("<4H", directory, cursor + 28)
            require(member_disk == 0, "ZIP member disk")
            cursor += 46 + name + extra + comment
            require(cursor <= len(directory), "ZIP central lengths")
        require(cursor == len(directory), "exact bounded ZIP central records")
        return cd_offset


def zip_extensions(extra):
    cursor, zip64, seen = 0, None, set()
    while cursor < len(extra):
        require(cursor + 4 <= len(extra), "ZIP extension header")
        kind, size = struct.unpack_from("<2H", extra, cursor)
        cursor += 4
        require(cursor + size <= len(extra) and kind not in seen, "ZIP extension length/duplicate")
        seen.add(kind)
        # These do not declare link/sparse/file roles; all others refuse.
        require(kind in (0x0001, 0x000A, 0x5455, 0x7875), "ZIP unsupported/link extension")
        if kind == 0x0001:
            zip64 = extra[cursor:cursor + size]
        cursor += size
    return zip64


def zip_local_member(stream, member, next_offset):
    """Close local/central header, ZIP64-size and data-descriptor ambiguity."""
    stream.seek(member.header_offset)
    raw = stream.read(30)
    require(len(raw) == 30 and raw[:4] == b"PK\x03\x04", "ZIP local header")
    _, version, flags, method, _, _, crc, compressed, expanded, name_size, extra_size = struct.unpack("<4s5H3I2H", raw)
    require(version <= 45 and flags == member.flag_bits and not flags & ~(0x800 | 8 | 6)
            and method == member.compress_type and method in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED),
            "ZIP local method/flags")
    require(stream.read(name_size) == member.filename.encode("ascii"), "ZIP local/central name mismatch")
    extra = stream.read(extra_size)
    require(len(extra) == extra_size, "ZIP local extension bytes")
    zip64 = zip_extensions(extra)
    cursor = 0
    for name, local in (("expanded", expanded), ("compressed", compressed)):
        if local == 0xFFFFFFFF:
            require(zip64 is not None and cursor + 8 <= len(zip64), "ZIP64 local size")
            local = struct.unpack_from("<Q", zip64, cursor)[0]
            cursor += 8
        expected = member.file_size if name == "expanded" else member.compress_size
        require(local == expected or (flags & 8 and local == 0), "ZIP local/central size mismatch")
    require(crc == member.CRC or (flags & 8 and crc == 0), "ZIP local/central CRC mismatch")
    start = stream.tell()
    end = start + member.compress_size
    require(start <= end <= next_offset, "ZIP compressed body overlap/overflow")
    stream.seek(end)
    require(next_offset - end <= 24, "ZIP unexpected local gap/extra member")
    descriptor = stream.read(next_offset - end)
    if flags & 8:
        if descriptor.startswith(b"PK\x07\x08"):
            descriptor = descriptor[4:]
        require(len(descriptor) in (12, 20), "ZIP data descriptor bytes")
        values = struct.unpack("<III" if len(descriptor) == 12 else "<IQQ", descriptor)
        require(values == (member.CRC, member.compress_size, member.file_size), "ZIP data descriptor identity")
    else:
        require(not descriptor, "ZIP unreported trailing member bytes")
    return start


def extract_transport(path, destination):
    central_offset = zip_preflight(path)
    destination.mkdir(mode=0o700)
    total = 0
    with zipfile.ZipFile(path) as archive:
        members = archive.infolist()
        require(len(members) == 2 and {m.filename for m in members} == {TAR_NAME, DIGEST_NAME},
                "exact two transport files")
        seen = set()
        members.sort(key=lambda m: m.header_offset)
        require(members[0].header_offset == 0, "ZIP unexpected prefix")
        for index, member in enumerate(members):
            mode = member.external_attr >> 16
            kind = stat.S_IFMT(mode)
            require(member.orig_filename == member.filename and member.filename.casefold() not in seen
                    and not member.is_dir() and kind in (0, stat.S_IFREG) and not mode & 0o7000
                    and not member.flag_bits & 1 and not member.external_attr & 0x10,
                    "ZIP name/type/link/encryption refusal")
            seen.add(member.filename.casefold())
            zip_extensions(member.extra)
            cap = TAR_BYTES if member.filename == TAR_NAME else 256
            require(0 <= member.file_size <= cap and 0 <= member.compress_size <= ZIP_BYTES,
                    "transport declared member byte bound")
            require(total + member.file_size <= ZIP_EXPANDED_BYTES, "ZIP declared expansion bound")
            count, crc = 0, 0
            with path.open("rb") as source, (destination / member.filename).open("xb") as target:
                next_offset = members[index + 1].header_offset if index + 1 < len(members) else central_offset
                start = zip_local_member(source, member, next_offset)
                source.seek(start)
                remaining = member.compress_size
                decoder = zlib.decompressobj(-15) if member.compress_type == zipfile.ZIP_DEFLATED else None
                while remaining:
                    compressed = source.read(min(CHUNK, remaining))
                    require(compressed, "ZIP truncated compressed body")
                    remaining -= len(compressed)
                    pending = compressed
                    while pending:
                        previous = pending
                        limit = min(CHUNK, cap - count + 1, ZIP_EXPANDED_BYTES - total + 1)
                        chunk = decoder.decompress(pending, limit) if decoder else pending
                        pending = decoder.unconsumed_tail if decoder else b""
                        require(chunk or pending != previous, "ZIP decoder made no progress")
                        require(count + len(chunk) <= cap and total + len(chunk) <= ZIP_EXPANDED_BYTES
                                and count + len(chunk) <= member.file_size, "ZIP first-excess expansion bytes")
                        require(not decoder or not decoder.unused_data, "ZIP trailing compressed stream bytes")
                        target.write(chunk)
                        crc = zlib.crc32(chunk, crc)
                        count += len(chunk)
                        total += len(chunk)
                require(not decoder or decoder.eof, "ZIP incomplete deflate stream")
            require(count == member.file_size and crc == member.CRC, "ZIP complete member bytes/CRC")
    return total


class _TarPathComponents:
    """Flat component trie: IDs, component edges and terminal roles only.

    No full joined prefix, parent Path object, recursion or depth limit. The
    caller supplies its already charged, bounded canonical census byte count.
    Counters cover actual visits/folds and retained component characters/nodes.
    """
    def __init__(self):
        self.edges = {}
        self.kinds = [None]
        self.children = [0]
        self.visits = self.characters = self.fold_characters = self.stored_characters = 0

    def add(self, relative, kind, encoded_census_bytes):
        node = 0
        for component in relative.split("/"):
            self.visits += 1
            self.characters += len(component)
            folded = component.casefold()
            self.fold_characters += len(folded)
            # Nonempty safe components consume encoded census characters.
            # ASCII folding preserves length; escaped Unicode leaves ample
            # space for Unicode case expansions. These are derived accounting
            # bounds on actual work, not a new lawful path/depth restriction.
            require(self.visits <= self.characters <= encoded_census_bytes
                    and self.fold_characters <= encoded_census_bytes,
                    "TAR component work exceeds encoded census bytes")
            require(self.kinds[node] != "file", "TAR file/parent conflict")
            key = (node, folded)
            edge = self.edges.get(key)
            if edge is None:
                stored = self.stored_characters + len(component) + len(folded)
                require(stored <= 2 * encoded_census_bytes
                        and len(self.kinds) <= self.visits,
                        "TAR component storage exceeds encoded census bytes")
                child = len(self.kinds)
                self.edges[key] = (component, child)
                self.kinds.append(None)
                self.children.append(0)
                self.children[node] += 1
                self.stored_characters = stored
                node = child
            else:
                require(edge[0] == component, "TAR case-colliding parent")
                node = edge[1]
        require(self.kinds[node] is None, "TAR duplicate member")
        require(kind != "file" or self.children[node] == 0, "TAR file/parent conflict")
        self.kinds[node] = kind

    def work(self, members, encoded_census_bytes):
        return {"members": members, "encodedCensusBytes": encoded_census_bytes,
                "componentVisits": self.visits, "componentCharactersVisited": self.characters,
                "casefoldCharactersVisited": self.fold_characters,
                "storedComponentCharacters": self.stored_characters,
                "componentNodes": len(self.kinds) - 1}


def tar_preflight(path, kernel):
    """Bound extension allocation, then reject logical unsafe/overflow members."""
    size = path.stat().st_size
    require(0 < size <= min(TAR_BYTES, kernel["MAX_ARCHIVE_BYTES"]), "inner TAR byte bound")
    with path.open("rb") as stream:
        physical, pending_extension = 0, False
        while True:
            header = stream.read(512)
            require(len(header) == 512, "TAR complete header")
            if header == bytes(512):
                require(not pending_extension, "TAR orphan extension")
                require(stream.read(512) == bytes(512), "TAR complete terminal blocks")
                while True:
                    chunk = stream.read(CHUNK)
                    if not chunk:
                        break
                    require(not any(chunk), "TAR trailing nonzero bytes")
                break
            physical += 1
            require(physical <= 2 * min(TAR_MEMBERS, kernel["MAX_MEMBERS"]), "TAR physical header bound")
            info = tarfile.TarInfo.frombuf(header, "utf-8", "strict")
            require(0 <= info.size <= TAR_BYTES, "TAR header size/overflow refusal")
            require(info.type in (tarfile.REGTYPE, tarfile.AREGTYPE, tarfile.DIRTYPE, tarfile.XHDTYPE),
                    "TAR physical type/link/sparse refusal")
            if info.type == tarfile.XHDTYPE:
                require(not pending_extension, "TAR chained extension refusal")
                require(info.size <= TAR_EXTENSION_BYTES, "TAR extension allocation bound")
                pending_extension = True
            else:
                pending_extension = False
            padded = ((info.size + 511) // 512) * 512
            require(stream.tell() + padded <= size, "TAR physical body bounds")
            stream.seek(padded, os.SEEK_CUR)
    components, members, total, census_bytes = _TarPathComponents(), 0, 0, 2
    with tarfile.open(path, "r:") as archive:
        for member in archive:
            require(members < min(TAR_MEMBERS, kernel["MAX_MEMBERS"]), "TAR first-excess member bound")
            require(member.name.startswith("FieldEvidencePayload/"), "TAR payload prefix")
            relative = member.name.removeprefix("FieldEvidencePayload/")
            kernel["safe_relative"](relative)
            require((member.isreg() or member.isdir())
                    and not member.linkname and member.sparse is None
                    and 0 <= member.mode <= 0o777 and 0 <= member.size <= TAR_BYTES
                    and (not member.isdir() or member.size == 0), "TAR logical name/type/link/sparse/size refusal")
            require(not any(key == "linkpath" or "sparse" in key.casefold()
                            for key in member.pax_headers), "TAR sparse/link extension refusal")
            total += member.size
            require(total <= min(TAR_BYTES, kernel["MAX_ARCHIVE_BYTES"]), "TAR first-excess expansion bytes")
            census_bytes += len(canonical({"path": relative, "type": "directory" if member.isdir() else "file",
                                          "size": member.size, "mode": member.mode}))
            require(census_bytes <= JSON_BYTES, "TAR first-excess census bytes")
            components.add(relative, "directory" if member.isdir() else "file", census_bytes)
            members += 1
    require(members, "nonempty TAR")
    return components.work(members, census_bytes)


def metadata_facts(extracted, value, plan, resolved, ci, kernel, *, cold=False):
    raw = regular_bytes(extracted / METADATA)
    metadata = decode(raw)
    workspace = metadata.get("workspace") if type(metadata) is dict else None
    require(type(workspace) is str and workspace.startswith("/") and "\x00" not in workspace
            and all(p not in (".", "..") for p in workspace.split("/")), "original workspace spelling DATA")
    expected = {
        "schema": ci["SHARED_PAYLOAD_SCHEMA"], "routeID": ci["COLD_SELECTION_ID" if cold else "SHARED_SELECTION_ID"],
        "repository": plan["route"]["repository"], "ref": plan["ref"], "head": plan["head"],
        "gitTree": plan["tree"], "workspace": workspace, "runID": str(value["runID"]), "runAttempt": "1",
        "payloadArtifactName": value["payloadArtifact"]["name"],
        "planSHA256": sha(ci["canonical"](resolved)),
        "partitionsSHA256": resolved[ci["SHARED_KEY"]]["partitionsSHA256"],
        "toolchain": {"xcodeVersion": "Xcode 26.6", "xcodeBuild": "17F113", "sdkName": "iphonesimulator26.5",
                      "sdkBuild": "23F81a", "architecture": "arm64", "configuration": "Debug"},
        "developmentOnly": True, "acceptance": False,
    }
    require(type(metadata) is dict and set(metadata) == set(expected) | {"products", "buildCommandReceiptSHA256", "buildLogSHA256"},
            "closed payload metadata")
    require(canonical({key: metadata[key] for key in expected}) == canonical(expected), "payload metadata original/selection join")
    for key in ("buildCommandReceiptSHA256", "buildLogSHA256"):
        require(type(metadata[key]) is str and re.fullmatch(r"[0-9A-F]{64}", metadata[key]), "declared build digest grammar")
    products = ci["shared_products_binding"](kernel, extracted)
    require(canonical(products) == canonical(metadata["products"]), "recomputed product/xctestrun/compatibility differs")
    return raw, metadata, products


def bounded_names(directory, count):
    names = []
    with os.scandir(directory) as scan:
        for entry in scan:
            require(len(names) < count, "retained directory first-excess members")
            names.append(entry.name)
    return sorted(names)


def worker_states(artifact, producer, ci):
    names = ["native-admission.json", "phase1-event-binding.json", METADATA, "ci-selection.selected.json"]
    names += ([ci["SHARED_PAYLOAD_RECEIPT"], "phase1-shared-live-seal.json"] if producer else
              [ci["SHARED_RESTORE_RECEIPT"], "phase1-shared-live-restore.json", "phase1-shared-live-before.json",
               "phase1-shared-live-after.json", "v23-shared-fingerprint-before.json", "v23-shared-fingerprint-after.json",
               ci["SHARED_DERIVED_DATA_DELTA"], "test-smoke.log"])
    paths = [(artifact / name, ci["SHARED_MAX_TEST_LOG_BYTES"] if name == "test-smoke.log" else JSON_BYTES) for name in names]
    if not producer:
        log_directory = artifact / "phase1-activity-logs"
        handles = directory_chain(log_directory)
        try:
            names = bounded_names(handles[-1], TAR_MEMBERS)
            paths += [(log_directory / name, ci["PHASE1_ACTIVITY_TOTAL_BYTES"]) for name in names]
        finally:
            for handle in reversed(handles):
                os.close(handle)
    states, activity_bytes = {}, 0
    for path, limit in paths:
        descriptor, info, handles = regular_open(path)
        try:
            require(info.st_size <= limit, "retained worker regular byte bound")
            if path.parent.name == "phase1-activity-logs":
                activity_bytes += info.st_size
                require(activity_bytes <= ci["PHASE1_ACTIVITY_TOTAL_BYTES"], "retained worker activity byte bound")
            states[str(path)] = snapshot(info)
        finally:
            regular_finish(path, descriptor, info, handles)
    return states


def worker_joins(root, directory, value, plan, resolved, raw, products, archive, census, ci, gate, kernel):
    """Optional complete retained observations, still unauthenticated DATA only."""
    labels = ["producer"] + resolved[ci["SHARED_KEY"]]["partitionIDs"]
    if directory is None:
        return {"status": "PENDING_MISSING_RETAINED_WORKERS", "requiredLabels": labels}
    directory = clean_absolute(directory)
    handles = directory_chain(directory)
    try:
        require(bounded_names(handles[-1], len(labels)) == sorted(labels), "complete producer/every-consumer directory census")
        facts = {}
        protocol = ci["source_binding"](root)
        entries = kernel["inventory"](Path(archive["extractedRoot"]) / kernel["ROOT_LABEL"])
        for label in labels:
            artifact = directory / label
            worker_handles = directory_chain(artifact)
            try:
                before = worker_states(artifact, label == "producer", ci)
                record = decode(regular_bytes(artifact / "native-admission.json"))
                binding = decode(regular_bytes(artifact / "phase1-event-binding.json"))
                require(binding.get("plan") == plan and binding.get("runID") == str(value["runID"])
                        and binding.get("runAttempt") == "1", "worker frozen original/plan DATA join")
                require(record.get("repository") == plan["route"]["repository"]
                        and record.get("runID") == str(value["runID"]) and record.get("runAttempt") == "1"
                        and record.get("selectionID") == ci["SHARED_SELECTION_ID"], "worker original DATA join")
                require(all(record.get(key) == fact for key, fact in protocol.items()), "worker source protocol DATA join")
                selected = resolved if label == "producer" else ci["shared_selection"](root, label)
                selected_raw = ci["canonical"](selected)
                require(regular_bytes(artifact / "ci-selection.selected.json") == selected_raw
                        and record.get("selectionSHA256") == sha(selected_raw), "worker actual ordered selection DATA join")
                shared = record.get(ci["SHARED_KEY"], {})
                require(shared.get("role") == ("producer" if label == "producer" else "consumer")
                        and shared.get("partitionID") == (None if label == "producer" else label), "worker role/partition DATA join")
                require(regular_bytes(artifact / METADATA) == raw, "worker exact retained metadata bytes")
                computed = ci["phase1_retained_shared_facts"](root, artifact, record, binding)
                for stage in (("seal",) if label == "producer" else ("restore", "before", "after")):
                    observation = decode(regular_bytes(artifact / ("phase1-shared-live-" + stage + ".json")))
                    require(observation["products"] == products and observation["productInventory"] == entries,
                            "worker observation/recomputed product join")
                    if stage in ("seal", "restore"):
                        require(observation["archive"] == {k: archive[k] for k in ("name", "bytes", "sha256")}
                                and observation["archiveMemberCensus"] == census, "worker observation/recomputed TAR join")
                facts[label] = {"retainedFacts": computed, "admissionSHA256": sha(canonical(record)),
                                "bindingSHA256": sha(canonical(binding))}
                require(worker_states(artifact, label == "producer", ci) == before, "retained worker inputs changed during recomputation")
            finally:
                for handle in reversed(worker_handles):
                    os.close(handle)
        return {"status": "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA", "workers": facts}
    finally:
        for handle in reversed(handles):
            os.close(handle)


def _recompute_retained_payload(zip_path, envelope_path, source_root, destination, *, retained_workers=None, cold=False):
    """Materialize in a NEW private destination; retain failures, never clean up.

    Caller must exclude concurrent writers to input/source/destination/retained
    worker trees. No current runner paths named inside metadata are opened.
    Return factual output, never authentication/authorization/qualification.
    """
    owned = Owned(destination)
    receipts, stage = {}, "raw-retention"
    try:
        owned.copy(clean_absolute(envelope_path), "input-envelope.json", JSON_BYTES, receipts)
        owned.copy(clean_absolute(zip_path), "payload.zip", ZIP_BYTES, receipts)
        stage = "source-and-envelope"
        root = clean_absolute(source_root)
        ci, gate, kernel = source_modules(root)
        value = decode(regular_bytes(owned.path / "input-envelope.json"))
        plan, resolved, sources = envelope_facts(value, root, ci, gate, cold=cold)
        require(receipts["payload.zip"]["sha256"].lower() == value["payloadArtifact"]["digest"].removeprefix("sha256:"),
                "outer ZIP digest differs from declared API DATA")
        # API size remains a distinct reported fact, never equated to ZIP bytes.
        stage = "zip-transport"
        owned.check()
        extract_transport(owned.path / "payload.zip", owned.path / "transport")
        stage = "inner-digest"
        tar = owned.path / "transport" / TAR_NAME
        digest_raw = regular_bytes(owned.path / "transport" / DIGEST_NAME, 256)
        match = re.fullmatch(rb"([0-9A-F]{64}) ([0-9]{1,20}) FieldEvidencePayload\.tar\n", digest_raw)
        require(match is not None, "distinct uppercase inner TAR digest grammar")
        require(int(match[2]) == tar.stat().st_size and 0 < int(match[2]) <= TAR_BYTES
                and kernel["sha256_file"](tar) == match[1].decode("ascii"), "inner TAR digest or bytes differ")
        archive = {"name": TAR_NAME, "bytes": int(match[2]), "sha256": match[1].decode("ascii")}
        stage = "tar-preflight"
        tar_preflight(tar, kernel)
        census = ci["phase1_tar_census"](tar, kernel)
        stage = "kernel-extraction"
        owned.check()
        extracted = owned.path / "extracted"
        kernel["extract_tar"](tar, extracted)
        require(sorted(p.name for p in extracted.iterdir()) == sorted(["FieldEvidenceDerivedData", METADATA]), "exact extracted root")
        stage = "metadata-products"
        raw, metadata, products = metadata_facts(extracted, value, plan, resolved, ci, kernel, cold=cold)
        # Exact archive census must equal the actual safely materialized view.
        expected_census = [{"path": e["path"], "type": e["type"], "size": e.get("size", 0), "mode": e["mode"]}
                           for e in kernel["inventory"](extracted)]
        require(census == expected_census, "actual extracted/census join")
        product_entries = kernel["inventory"](extracted / kernel["ROOT_LABEL"])
        allowed = {"FieldEvidenceDerivedData", "FieldEvidenceDerivedData/Build", kernel["ROOT_LABEL"], METADATA}
        allowed.update(kernel["ROOT_LABEL"] + "/" + entry["path"] for entry in product_entries)
        require({entry["path"] for entry in census} == allowed, "closed payload member closure")
        stage = "retained-worker-joins"
        join_reader = cold_worker_joins_v2 if cold else worker_joins
        joins = join_reader(root, retained_workers, value, plan, resolved, raw, products,
                            dict(archive, extractedRoot=str(extracted)), census, ci, gate, kernel)
        stage = "final-invariance"
        require(source_closure(root, gate) == sources, "source closure changed during recomputation")
        require(all(list(snapshot((owned.path / name).lstat())) == receipt["ownedStat"]
                    for name, receipt in receipts.items()), "retained raw input copy changed")
        require(ci["shared_selection"](root) == resolved, "ordered selection changed during recomputation")
        require(kernel["sha256_file"](tar) == archive["sha256"]
                and ci["shared_products_binding"](kernel, extracted) == products
                and regular_bytes(extracted / METADATA) == raw, "owned TAR/metadata/products changed")
        owned.check()
        stage = "durable-publication"
        durability = owned.sync_tree()
        result = {"schema": COLD_FACT_SCHEMA_V2 if cold else FACT_SCHEMA,
                  "status": "RECOMPUTED_COLD_RETAINED_PAYLOAD_DATA_ONLY_UNQUALIFIED" if cold else "RECOMPUTED_RETAINED_PAYLOAD_DATA",
                  "envelopeSHA256": receipts["input-envelope.json"]["sha256"],
                  "outerZIP": {"bytes": receipts["payload.zip"]["bytes"], "sha256": receipts["payload.zip"]["sha256"].lower(),
                               "declaredAPIArtifact": value["payloadArtifact"]},
                  "archive": archive, "digestFileSHA256": sha(digest_raw), "metadataSHA256": sha(raw),
                  "originalDATA": {"repository": plan["route"]["repository"], "ref": plan["ref"], "head": plan["head"],
                                   "tree": plan["tree"], "runID": value["runID"], "runAttempt": value["runAttempt"],
                                   "planSHA256": sha(canonical(plan))},
                  "sourceSHA256": sources, "executableSourceSHA256": EXECUTABLE_SOURCES,
                  "products": products, "archiveMemberCensus": census, "workerJoins": joins,
                  "originalPayloadClassification": {"developmentOnly": metadata["developmentOnly"], "acceptance": metadata["acceptance"]},
                  "declaredBuildDigests": {key: metadata[key] for key in ("buildCommandReceiptSHA256", "buildLogSHA256")},
                  "pendingProof": list(COLD_PENDING_V2 if cold else PENDING), "ownedCopies": receipts,
                  "durability": durability}
        if cold:
            result["originalDATA"]["originalEventSHA256"] = value["originalEventSHA256"]
            result["originalEventSHA256"] = value["originalEventSHA256"]
            result["scope"] = dict(COLD_SCOPE_V2)
            result["unprovenClaims"] = list(COLD_UNPROVEN_V2)
        owned.write("FACTS.json", canonical(result))
        return result
    except BaseException as error:
        try:
            durability = owned.sync_tree()
        except Exception as sync_error:
            durability = {"status": "UNPROVEN", "errorType": type(sync_error).__name__}
        failure = {"schema": "v23-cold-retained-payload-failure.v2" if cold else "v23-retained-payload-failure.v1",
                   "status": "REFUSED_PARTIAL_OWNED_DATA_RETAINED",
                   "stage": stage, "errorType": type(error).__name__, "reason": str(error)[:1000],
                   "ownedCopies": receipts, "pendingProof": list(COLD_PENDING_V2 if cold else PENDING), "durability": durability}
        try:
            owned.write("FAILURE.json", canonical(failure))
        except Exception as receipt_error:
            raise Refused("%s; failure receipt unavailable: %s; owned destination retained at %s"
                          % (error, receipt_error, owned.path)) from error
        if not isinstance(error, Exception):
            raise
        raise Refused("%s; failure receipt: %s" % (error, owned.path / "FAILURE.json")) from error
    finally:
        owned.close()


def recompute_retained_payload(zip_path, envelope_path, source_root, destination, *, retained_workers=None):
    """Unchanged v1 factual interface and ordinary/Phase1 retained artifact ABI."""
    return _recompute_retained_payload(zip_path, envelope_path, source_root, destination,
                                       retained_workers=retained_workers, cold=False)


def recompute_cold_retained_payload_v2(zip_path, envelope_path, source_root, destination, *, retained_workers=None):
    """Explicit v2 cold DATA adapter; never authentication or qualification.

    The six-key input envelope includes the actual retained original event digest.
    Worker inputs are original cold records and additive V2 payload witnesses.
    A caller authenticates originals/jobs/downloads/budgets before using facts.
    No original runner path is opened and no live extraction is replayed.
    """
    return _recompute_retained_payload(zip_path, envelope_path, source_root, destination,
                                       retained_workers=retained_workers, cold=True)


def cold_close_handles_v2(handles, primary):
    """Attempt each acquired handle's close once; preserve the first failure."""
    errors = []
    for handle in reversed(handles):
        try:
            os.close(handle)
        except BaseException as error:
            errors.append(error)
    if primary is not None:
        for error in errors:
            primary.add_note("secondary cold directory close: " + repr(error))
    elif errors:
        for error in errors[1:]:
            errors[0].add_note("secondary cold directory close: " + repr(error))
        raise errors[0]


def cold_worker_states_v2(artifact, producer, ci):
    """Guard every retained byte input used by the versioned native validator."""
    names = ["native-admission.json", "cold-event-binding.json", "cold-original-plan.json", "cold-original-event.json",
             "native-checkpoint.json", METADATA, "ci-selection.selected.json", "runner-provider.txt",
             "native-sdk.txt", "xcode-version.txt", "simulator-selection.txt"]
    stages = ("seal",) if producer else ("restore", "before", "after")
    names += ["cold-shared-observation-" + stage + ".json" for stage in stages]
    names += ["cold-shared-payload-witness-" + stage + "-v2.json" for stage in stages]
    names += ([ci["SHARED_PAYLOAD_RECEIPT"]] if producer else
              [ci["SHARED_RESTORE_RECEIPT"], "v23-shared-fingerprint-before.json", "v23-shared-fingerprint-after.json",
               ci["SHARED_DERIVED_DATA_DELTA"], "test-smoke.log", "unit-test-results.json"])
    paths = [(artifact / name, ci["SHARED_MAX_TEST_LOG_BYTES"] if name == "test-smoke.log" else JSON_BYTES) for name in names]
    if not producer:
        directory = artifact / "cold-activity-logs-v2"
        handles, primary = directory_chain(directory), None
        try:
            names = bounded_names(handles[-1], TAR_MEMBERS)
            paths += [(directory / name, ci["PHASE1_ACTIVITY_TOTAL_BYTES"]) for name in names]
        except BaseException as error:
            primary = error
            raise
        finally:
            cold_close_handles_v2(handles, primary)
    states, total = {}, 0
    for path, limit in paths:
        # The existing bounded full read proves regular singleton/no-alias inputs
        # and held/name nine-field endpoint equality (without st_flags) before retaining each state.
        raw = regular_bytes(path, limit)
        if path.parent.name == "cold-activity-logs-v2":
            total += len(raw)
            require(total <= ci["PHASE1_ACTIVITY_TOTAL_BYTES"], "cold retained activity byte bound")
        states[str(path)] = {"stat": snapshot(path.lstat()), "bytes": len(raw), "sha256": sha(raw)}
    return states


def cold_event_data_join_v2(artifact, value, plan, binding, gate):
    """Check actual event bytes and closed retained identity, never forge context."""
    event_raw = regular_bytes(artifact / "cold-original-event.json", gate["MAX_EVENT_BYTES"])
    require(sha(event_raw) == value["originalEventSHA256"], "cold retained original event digest DATA join")
    event_plan, event = gate["cold_plan_from_event"](event_raw)
    require(event_plan == plan and event.get("inputs") == gate["cold_dispatch_inputs"](plan)
            and event.get("ref") in (plan["ref"], plan["ref"].removeprefix("refs/heads/"))
            and type(event.get("repository")) is dict
            and event["repository"].get("full_name") == plan["route"]["repository"], "cold retained original event DATA join")
    expected = {
        "schema": gate["COLD_EVENT_SCHEMA"], "plan": plan, "planSHA256": sha(canonical(plan)),
        "originalEventSHA256": sha(event_raw), "repository": plan["route"]["repository"], "ref": plan["ref"],
        "head": plan["head"], "tree": plan["tree"],
        "workflowRef": plan["route"]["repository"] + "/" + plan["route"]["workflow"] + "@" + plan["ref"],
        "workflowSHA": plan["head"], "runID": str(value["runID"]), "runAttempt": "1", "kind": "development",
        "selection": plan["selection"], "functionalQualification": "PENDING", "status": "INCOMPLETE",
        "developmentOnly": True, "providerQualification": False, "acceptance": False, "releaseReady": False,
    }
    require(canonical(binding) == canonical(expected), "closed cold retained binding DATA join")
    require(regular_bytes(artifact / "cold-original-plan.json") == canonical(plan), "cold retained intent exact bytes")


def cold_execution_data_v2(artifact, record, checkpoint, selected, label, observations, ci):
    """Retained pinned execution facts, without executing a command or granting it."""
    provider = ci["key_values"](artifact / "runner-provider.txt")
    sdk = ci["key_values"](artifact / "native-sdk.txt")
    simulator = ci["key_values"](artifact / "simulator-selection.txt")
    require(provider.get("provider") == record.get("runnerProvider") == "github"
            and provider.get("label") == record.get("runnerLabel") == "macos-26"
            and provider.get("runner_architecture") == "ARM64" and provider.get("uname_architecture") == "arm64"
            and provider.get("developer_dir") == "/Applications/Xcode_26.6.app/Contents/Developer"
            and regular_bytes(artifact / "xcode-version.txt").decode("utf-8").splitlines()
                == ["Xcode 26.6", "Build version 17F113"], "cold retained pinned provider/compiler DATA")
    require(sdk == {"sdk": "iphonesimulator", "version": "26.5", "build": "23F81a"}, "cold retained pinned SDK DATA")
    require((simulator.get("runtime"), simulator.get("runtime_build"), simulator.get("name"), simulator.get("initial_state"))
            == ("iOS 26.2", "23C54", "iPhone 17", "Shutdown")
            and type(simulator.get("udid")) is str
            and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", simulator["udid"]),
            "cold retained pinned runtime/owned Simulator DATA")
    require(type(checkpoint) is dict and checkpoint.get("recordType") == "validated-native-checkpoint"
            and all(checkpoint.get(key) == fact for key, fact in record.items())
            and checkpoint.get("provider") == provider and checkpoint.get("sdk") == sdk
            and checkpoint.get("simulator") == simulator
            and all(checkpoint.get(key) is False for key in ("providerQualification", "acceptance", "releaseReady")),
            "cold retained checkpoint identity/runtime DATA")
    producer = label == "producer"
    forbidden = (("test-smoke.log", "UnitTests.xcresult", "unit-test-results.json") if producer else
                 ("build-smoke.log", "Build.xcresult", ci["NO_INDEX_RECEIPT"]))
    require(not any((artifact / name).exists() or (artifact / name).is_symlink() for name in forbidden),
            "cold retained role/rebuild evidence refusal")
    methods, command = [], None
    if not producer:
        result_raw = regular_bytes(artifact / "unit-test-results.json")
        methods = ci["executed_methods"](decode(result_raw), selected["unitTestSelectors"],
                                          "FieldEvidenceAppTests", "Unit test bundle")
        witness = observations["restore"]
        expected = [provider["developer_dir"] + "/usr/bin/xcodebuild", "-project", "FieldEvidenceApp.xcodeproj",
                    "-scheme", "FieldEvidenceApp", "-configuration", "Debug", "-destination",
                    "platform=iOS Simulator,id=" + simulator["udid"], "-derivedDataPath",
                    str(Path(witness["runnerTemp"]) / "FieldEvidenceDerivedData"), "-resultBundlePath",
                    str(Path(witness["artifactDirectory"]) / "UnitTests.xcresult"),
                    *["-only-testing:" + method for method in selected["unitTestSelectors"]],
                    "CODE_SIGNING_ALLOWED=NO", "test-without-building"]
        log_raw = regular_bytes(artifact / "test-smoke.log", ci["SHARED_MAX_TEST_LOG_BYTES"])
        lines = log_raw.decode("utf-8").splitlines()
        invocations = [i for i, line in enumerate(lines) if line.strip() == "Command line invocation:"]
        require(len(invocations) == 1 and invocations[0] + 1 < len(lines)
                and shlex.split(lines[invocations[0] + 1].strip()) == expected
                and sum(line.strip() == "** TEST EXECUTE SUCCEEDED **" for line in lines) == 1
                and ci["shared_test_log_compile_lines"](artifact / "test-smoke.log") == [],
                "cold exact successful no-rebuild unit invocation DATA")
        require(b"V23_PROTECTED_FILE_DIAGNOSTIC_JOURNAL_FAILURE" not in log_raw,
                "cold diagnostic journal failure")
        command = {"argv": expected, "logSHA256": sha(log_raw), "structuredResultSHA256": sha(result_raw)}
    require(checkpoint.get("executedUnitMethods") == methods
            and checkpoint.get("executedUIMethods") == []
            and methods == ([] if producer else sorted(selected["unitTestSelectors"])),
            "cold retained every selected method DATA join")
    return {"executedUnitMethods": methods, "unitCommand": command, "provider": provider, "sdk": sdk,
            "simulator": simulator, "checkpointSHA256": sha(canonical(checkpoint)), "offlineNativeExecution": False}


def cold_worker_joins_v2(root, directory, value, plan, resolved, raw, products, archive, census, ci, gate, kernel):
    """Join real cold V2 witnesses to recomputed payload; all inputs remain DATA."""
    labels = ["producer"] + resolved[ci["SHARED_KEY"]]["partitionIDs"]
    if directory is None:
        return {"status": "PENDING_MISSING_RETAINED_WORKERS", "requiredLabels": labels}
    require("cold_retained_shared_facts_v2" in ci, "unsupported cold retained native V2 ABI")
    directory = clean_absolute(directory)
    handles, primary = directory_chain(directory), None
    try:
        require(bounded_names(handles[-1], len(labels)) == sorted(labels), "complete cold producer/every-consumer directory census")
        facts = {}
        protocol = ci["source_binding"](root)
        entries = kernel["inventory"](Path(archive["extractedRoot"]) / kernel["ROOT_LABEL"])
        for label in labels:
            artifact = directory / label
            worker_handles, worker_error = directory_chain(artifact), None
            try:
                before = cold_worker_states_v2(artifact, label == "producer", ci)
                record = decode(regular_bytes(artifact / "native-admission.json"))
                binding = decode(regular_bytes(artifact / "cold-event-binding.json"))
                cold_event_data_join_v2(artifact, value, plan, binding, gate)
                require(type(record) is dict and record.get("coldOriginal") == binding and "phase1Gate" not in record
                        and (record.get("repository"), record.get("ref"), record.get("head"), record.get("gitTree"),
                             record.get("runID"), record.get("runAttempt"), record.get("selectionID"))
                        == (plan["route"]["repository"], plan["ref"], plan["head"], plan["tree"],
                            str(value["runID"]), "1", ci["COLD_SELECTION_ID"]), "cold worker original/source DATA join")
                require(all(record.get(key) == fact for key, fact in protocol.items()), "cold worker source protocol DATA join")
                selected = resolved if label == "producer" else ci["shared_selection"](root, label)
                selected_raw = ci["canonical"](selected)
                require(regular_bytes(artifact / "ci-selection.selected.json") == selected_raw
                        and record.get("selectionSHA256") == sha(selected_raw), "cold worker actual ordered selection DATA join")
                require(record.get(ci["SHARED_KEY"]) == {
                    "role": "producer" if label == "producer" else "consumer", "partitionID": None if label == "producer" else label,
                    "payloadArtifactName": value["payloadArtifact"]["name"], "planSHA256": plan["selectionSHA256"],
                    "partitionsSHA256": resolved[ci["SHARED_KEY"]]["partitionsSHA256"]}, "cold worker role/partition/payload DATA join")
                require(regular_bytes(artifact / METADATA) == raw, "cold worker exact retained metadata bytes")
                computed = ci["cold_retained_shared_facts_v2"](root, artifact, record, binding)
                observations = computed["observations"]
                for stage in (("seal",) if label == "producer" else ("restore", "before", "after")):
                    observation = observations[stage]
                    require(observation["products"] == products and observation["productInventory"] == entries,
                            "cold worker observation/recomputed normalized product join")
                    if stage in ("seal", "restore"):
                        require(observation["archive"] == {key: archive[key] for key in ("name", "bytes", "sha256")}
                                and observation["archiveMemberCensus"] == census, "cold worker observation/recomputed TAR join")
                checkpoint = decode(regular_bytes(artifact / "native-checkpoint.json"))
                execution = cold_execution_data_v2(artifact, record, checkpoint, selected, label, observations, ci)
                # Full observed inventories remain in the original retained
                # sidecars. Publish their raw pins and recomputed compact facts,
                # avoiding duplicate inventories for every partition/stage.
                compact = {key: fact for key, fact in computed.items() if key != "observations"}
                witness_sha = {stage: before[str(artifact / ("cold-shared-payload-witness-" + stage + "-v2.json"))]["sha256"]
                               for stage in observations}
                facts[label] = {"retainedFacts": compact, "retainedWitnessSHA256": witness_sha, "executionDATA": execution,
                                "admissionSHA256": sha(canonical(record)), "bindingSHA256": sha(canonical(binding))}
                require(cold_worker_states_v2(artifact, label == "producer", ci) == before,
                        "cold retained worker inputs changed during recomputation")
            except BaseException as error:
                worker_error = error
                raise
            finally:
                cold_close_handles_v2(worker_handles, worker_error)
        return {"status": "RECOMPUTED_ALL_RETAINED_COLD_WORKER_JOINS_DATA", "workers": facts}
    except BaseException as error:
        primary = error
        raise
    finally:
        cold_close_handles_v2(handles, primary)


def cold_job_names_v2(root, plan, resolved, ci):
    """Closed cold route uses the actual shared producer and every consumer name."""
    require(plan["selection"] == ci["COLD_SELECTION_ID"], "cold shared job naming only")
    source = regular_bytes(root / ".github/workflows/ios-ci.yml").decode("utf-8")
    def name(job):
        found = re.findall(r"(?m)^  " + re.escape(job) + r":\n    name: (.+)$", source)
        require(len(found) == 1, "cold source caller name")
        return found[0]
    names = {"selection": name("shared-selection"), "producer": name("v23-shared-producer") + " / verify"}
    for partition in resolved[ci["SHARED_KEY"]]["partitionIDs"]:
        names[partition] = name("v23-shared-consumer").replace("${{ matrix.partition_id }}", partition) + " / verify"
    require(all("${{" not in value for value in names.values()), "cold unresolved caller name")
    return names


def cold_job_execution_facts_v2(root, directory, plan, resolved, run_id):
    """Recompute execution facts from the sole collector's authenticated job logs.

    The dispatcher alone fetches these fixed repository/job endpoints. This local
    verifier checks retained facts; a dictionary/hash alone is not API authority.
    """
    root, directory = clean_absolute(root), clean_absolute(directory)
    ci, gate_dict, _ = source_modules(root)
    gate = SimpleNamespace(**gate_dict)
    sources = source_closure(root, gate_dict)
    require(gate.validate_cold_plan(plan) == plan and sources == plan["sources"]
            and type(run_id) is int and run_id > 0 and ci["shared_selection"](root) == resolved,
            "cold job exact source/selection/original DATA")
    names = cold_job_names_v2(root, plan, resolved, ci)
    phase1_workflow_steps = ci["phase1_workflow_steps"]
    unique_pairs = ci["unique_pairs"]
    sha256 = sha
    PHASE1_WITNESS_BYTES = ci["PHASE1_WITNESS_BYTES"]
    jobs = gate.decode(gate.regular_bytes(directory / "jobs.json", limit=PHASE1_WITNESS_BYTES),
                       limit=PHASE1_WITNESS_BYTES)["jobs"]
    require(type(jobs) is list and len(jobs) <= 500 and all(type(j) is dict for j in jobs)
            and len({j.get("id") for j in jobs}) == len(jobs)
            and len({j.get("name") for j in jobs}) == len(jobs), "Phase1 unique job census")
    by_name = {job["name"]: job for job in jobs}
    require(set(names.values()) <= set(by_name), "Phase1 complete source-derived active job census")
    for job in jobs:
        require(type(job.get("id")) is int and job["id"] > 0
                and type(job.get("run_id")) is int and job["run_id"] == run_id
                and type(job.get("run_attempt")) is int and job["run_attempt"] == 1
                and job.get("head_sha") == plan["head"] and job.get("status") == "completed",
                "Phase1 original job identity")
        if job["name"] not in names.values():
            require(job.get("conclusion") == "skipped" and not job.get("steps"),
                    "Phase1 unexpected executed job")
    rui_required = {"Prepare evidence directory", "Check out the exact revision", "Validate task selection and timeout tier",
        "Verify pinned toolchain, shared scheme, and simulator", "Verify setup budget before build",
        "Boot selected Simulator", "Await selected Simulator boot", "Build unsigned simulator app", "Run targeted tests",
        "Run task-authorized UI smoke", "Begin evidence-finalization budget", "Validate required build and test evidence",
        "Validate exact ordinary integration native checkpoint", "Remove owned isolated Simulator", "Hash collected evidence",
        "Recheck evidence-finalization budget", "Verify selected total budget before upload", "Upload build evidence"}
    facts = {}
    for label, name in names.items():
        job = by_name[name]
        require(job.get("conclusion") == "success", "Phase1 required job failed/interrupted")
        relative = (".github/workflows/ios-ci.yml" if label == "selection" else
                    ".github/workflows/ios-ci-worker.yml" if label == "rui1" else ".github/workflows/ios-ci-shared-worker.yml")
        source_steps = phase1_workflow_steps(root, relative, "shared-selection" if label == "selection" else "verify")
        required = set()
        for step in source_steps:
            if label == "selection":
                active = step["name"] in {"Check out the exact revision", "Validate ordinary V23 native acceptance selection",
                                          "Validate closed shared selection and original dependencies"}
            elif label == "rui1":
                active = step["name"] in rui_required
            else:
                condition = re.search(r"(?m)^        if: (.+)$", step["body"])
                active = (not condition or "inputs.v23_shared_role" not in condition[1]
                          or ("'producer'" if label == "producer" else "'consumer'") in condition[1])
            if active:
                required.add(step["name"])
        if label == "rui1":
            require(required == rui_required, "Phase1 RUI1 source step census changed")
        observed = job.get("steps")
        require(type(observed) is list and all(type(s) is dict for s in observed)
                and len({s.get("name") for s in observed}) == len(observed)
                and all(type(s.get("number")) is int and s["number"] > 0 for s in observed)
                and [s["number"] for s in observed] == sorted({s["number"] for s in observed}),
                "Phase1 unique ordered step census")
        by_step = {s["name"]: s for s in observed}
        source_names = [s["name"] for s in source_steps]
        require(set(source_names) <= set(by_step), "Phase1 missing source step outcome")
        require([s["name"] for s in observed if s["name"] in source_names] == source_names,
                "Phase1 source step order")
        framework = {"Set up job", "Complete job"} | {"Post " + s["name"] for s in source_steps if s["action"]}
        active_framework = {"Set up job", "Complete job"} | {
            "Post " + s["name"] for s in source_steps if s["action"] and s["name"] in required}
        require(set(by_step) <= set(source_names) | framework
                and {"Set up job", "Complete job"} <= set(by_step), "Phase1 unexpected/missing framework step")
        for step in observed:
            require(step.get("status") == "completed" and step.get("conclusion") ==
                    ("success" if step["name"] in required | active_framework else "skipped"),
                    "Phase1 failed/interrupted/bypassed/unexpected step " + step["name"])
        log = gate.regular_bytes(directory / "cold-job-logs" / (str(job["id"]) + ".log"), limit=256 * 1024 * 1024)
        text = log.decode("utf-8-sig")
        text = re.sub(r"(?m)^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ", "", text)
        text = re.sub(r"\x1b\[[0-9;]*m", "", text)
        commands, cursor = [], 0
        for step in source_steps:
            if step["name"] not in required:
                continue
            if step["script"]:
                require("${{" not in step["script"], "Phase1 active source command requires unsupported interpolation")
                pattern = "##[group]Run " + step["script"].splitlines()[0] + "\n" + step["script"] + "\n"
                require(text.count(pattern) == 1, "Phase1 exact executed source command " + step["name"])
                position = text.index(pattern)
                require(position >= cursor, "Phase1 executed command order")
                end = text.find("##[endgroup]", position + len(pattern))
                envelope = text[position + len(pattern):end]
                require(end >= 0 and "shell: /bin/bash --noprofile --norc -e -o pipefail {0}" in envelope
                        and "##[group]" not in envelope, "Phase1 incomplete command envelope")
                cursor = end
                wanted_env = {"CI_ARTIFACT_DIR", "CI_DESTINATION", "CI_SIMULATOR_UDID", "CI_SETUP_ARTIFACT_TIMEOUT_SECONDS",
                              "CI_BUILD_TIMEOUT_SECONDS", "CI_TEST_TIMEOUT_SECONDS", "CI_UI_TIMEOUT_SECONDS",
                              "CI_TOTAL_BUDGET_SECONDS", "NATIVE_SELECTION_ID", "CONFIGURATION", "DEVELOPER_DIR"}
                pairs = re.findall(r"(?m)^  ([A-Z_]+): (.*)$", text[position + len(pattern):end])
                env = unique_pairs([(key, value) for key, value in pairs if key in wanted_env])
                numeric = {}
                if step["name"] == "Verify selected total budget before upload":
                    output_end = text.find("##[group]Run ", end + 1)
                    output = text[end:output_end if output_end >= 0 else len(text)]
                    numeric = unique_pairs(re.findall(r"(?m)^(elapsed_seconds|total_budget_seconds)=([0-9]+)$", output))
                    require(set(numeric) == {"elapsed_seconds", "total_budget_seconds"}, "Phase1 complete total budget output")
                commands.append({"step": step["name"], "bodySHA256": step["bodySHA256"],
                                 "scriptSHA256": sha256(step["script"].encode()), "environment": env, "numericFacts": numeric})
            elif step["action"]:
                pattern = "##[group]Run " + step["action"] + "\n"
                count = sum(s["name"] in required and s["action"] == step["action"] for s in source_steps)
                position = text.find(pattern, cursor)
                end = text.find("##[endgroup]", position + len(pattern)) if position >= 0 else -1
                require(text.count(pattern) == count and position >= cursor and end >= 0
                        and "##[group]" not in text[position + len(pattern):end],
                        "Phase1 exact executed action " + step["name"])
                cursor = end
        facts[label] = {"jobID": job["id"], "name": name, "workflowSourceSHA256": sha256((root / relative).read_bytes()),
                        "jobLogSHA256": sha256(log), "commands": commands, "requiredSteps": sorted(required),
                        "finalizationBudgetPredicatePassed": label != "selection", "finalizationNumericElapsedAvailable": False}
    require(source_closure(root, gate_dict) == sources, "cold job source changed during recomputation")
    return facts


def cold_worker_execution_facts_v2(root, artifact, record, selected, label, job):
    """Retained execution/command facts, never a local native execution replay."""
    from pathlib import PurePosixPath
    root, artifact = clean_absolute(root), clean_absolute(artifact)
    ci, gate_dict, _ = source_modules(root)
    gate = SimpleNamespace(**gate_dict)
    sources = source_closure(root, gate_dict)
    binding = record.get("coldOriginal")
    require(type(binding) is dict and binding.get("schema") == gate.COLD_EVENT_SCHEMA and "phase1Gate" not in record,
            "cold worker execution original record")
    plan = gate.validate_cold_plan(binding["plan"])
    require(sources == plan["sources"] and record.get("selectionID") == ci["COLD_SELECTION_ID"],
            "cold worker execution frozen Source")
    resolved = ci["shared_selection"](root)
    require(label == "producer" or label in resolved[ci["SHARED_KEY"]]["partitionIDs"], "cold worker execution closed role")
    require(selected == (resolved if label == "producer" else ci["shared_selection"](root, label)),
            "cold worker execution exact ordered selectors")
    role = "producer" if label == "producer" else "consumer"
    require(record.get(ci["SHARED_KEY"], {}).get("role") == role
            and record[ci["SHARED_KEY"]].get("partitionID") == (None if label == "producer" else label)
            and all(record.get(key) == fact for key, fact in ci["source_binding"](root).items()),
            "cold worker execution role/source DATA")
    key_values = ci["key_values"]
    BUDGET_KEYS = ci["BUDGET_KEYS"]
    SHARED_MAX_TEST_LOG_BYTES = ci["SHARED_MAX_TEST_LOG_BYTES"]
    NO_INDEX_RECEIPT = ci["NO_INDEX_RECEIPT"]
    verify_no_index_build = ci["verify_no_index_build"]
    shared_test_log_compile_lines = ci["shared_test_log_compile_lines"]
    sha256 = sha
    def read_json(path):
        return decode(regular_bytes(path))
    for name in ("runner-provider.txt", "native-sdk.txt", "xcode-version.txt", "simulator-selection.txt"):
        gate.regular_bytes(artifact / name, limit=32768)
    provider = key_values(artifact / "runner-provider.txt")
    require(provider.get("provider") == record.get("runnerProvider") == "github"
            and provider.get("label") == record.get("runnerLabel") == "macos-26"
            and provider.get("runner_architecture") == "ARM64" and provider.get("uname_architecture") == "arm64"
            and provider.get("developer_dir") == "/Applications/Xcode_26.6.app/Contents/Developer",
            "Phase1 observed runner/toolchain")
    require((artifact / "xcode-version.txt").read_text().splitlines() == ["Xcode 26.6", "Build version 17F113"],
            "Phase1 observed Xcode")
    sdk = key_values(artifact / "native-sdk.txt")
    require(sdk == {"sdk": "iphonesimulator", "version": "26.5", "build": "23F81a"}, "Phase1 observed SDK")
    simulator = key_values(artifact / "simulator-selection.txt")
    require((simulator.get("runtime"), simulator.get("runtime_build"), simulator.get("name"), simulator.get("initial_state"))
            == ("iOS 26.2", "23C54", "iPhone 17", "Shutdown")
            and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", simulator.get("udid", "")),
            "Phase1 observed owned Simulator")
    if label == "rui1":
        environment, original_artifact = load_ui_evidence(root).retained_environment(read_json(artifact / "rui1-command.json")["argv"])
    else:
        witness = read_json(artifact / ("cold-shared-payload-witness-seal-v2.json" if label == "producer" else "cold-shared-payload-witness-restore-v2.json"))
        original_artifact = PurePosixPath(witness["artifactDirectory"])
        environment = {"PROJECT_PATH": "FieldEvidenceApp.xcodeproj", "SCHEME": "FieldEvidenceApp", "CONFIGURATION": "Debug",
                       "CODE_SIGNING_ALLOWED": "NO", "CI_SIMULATOR_UDID": simulator["udid"],
                       "CI_DESTINATION": "platform=iOS Simulator,id=" + simulator["udid"],
                       "CI_ARTIFACT_DIR": str(original_artifact), "RUNNER_TEMP": witness["runnerTemp"]}
    require(environment["CI_SIMULATOR_UDID"] == simulator["udid"], "Phase1 original command Simulator identity")
    timeout_env = dict(zip(("CI_SETUP_ARTIFACT_TIMEOUT_SECONDS", "CI_BUILD_TIMEOUT_SECONDS", "CI_TEST_TIMEOUT_SECONDS",
                           "CI_UI_TIMEOUT_SECONDS", "CI_TOTAL_BUDGET_SECONDS"),
                          (str(selected[key]) for key in BUDGET_KEYS)))
    commands = {item["step"]: item for item in job["commands"]}
    checked_steps = ["Recheck evidence-finalization budget", "Verify selected total budget before upload",
                     "Validate required build and test evidence", "Validate exact ordinary integration native checkpoint"]
    if label != "producer":
        checked_steps.append("Run targeted tests")
    if label in ("producer", "rui1"):
        checked_steps.append("Build unsigned simulator app")
    if label == "rui1":
        checked_steps.append("Run task-authorized UI smoke")
    for name in checked_steps:
        require(name in commands, "Phase1 source command proof missing " + name)
        observed = commands[name]["environment"]
        require(all(observed.get(k) == v for k, v in timeout_env.items())
                and observed.get("CI_ARTIFACT_DIR") == str(original_artifact)
                and observed.get("NATIVE_SELECTION_ID") == record["selectionID"]
                and observed.get("CONFIGURATION") == "Debug"
                and observed.get("DEVELOPER_DIR") == provider["developer_dir"], "Phase1 actual command budget/configuration inputs")
    def numbers(name, keys):
        gate.regular_bytes(artifact / name, limit=4096)
        value = key_values(artifact / name)
        require(set(value) == set(keys) and all(re.fullmatch(r"[0-9]+", v) for v in value.values()),
                "Phase1 complete numeric budget " + name)
        return {key: int(v) for key, v in value.items()}
    limit = selected["setupArtifactTimeoutSeconds"]
    setup = numbers("setup-budget.txt", ("setup_elapsed_seconds", "setup_budget_seconds"))
    require(setup["setup_elapsed_seconds"] <= setup["setup_budget_seconds"] == limit, "Phase1 setup budget")
    setup_elapsed = setup["setup_elapsed_seconds"]
    restore = None
    if label not in ("producer", "rui1"):
        restore = numbers("v23-shared-restore-budget.txt", ("shared_restore_setup_elapsed_seconds",))
        require(setup_elapsed <= restore["shared_restore_setup_elapsed_seconds"] <= limit, "Phase1 restore setup budget")
        setup_elapsed = restore["shared_restore_setup_elapsed_seconds"]
    artifact_budget = numbers("artifact-budget.txt", ("setup_elapsed_seconds", "artifact_elapsed_seconds",
                                                     "setup_artifact_elapsed_seconds", "setup_artifact_budget_seconds"))
    require(artifact_budget["setup_elapsed_seconds"] == setup_elapsed
            and artifact_budget["setup_artifact_budget_seconds"] == limit
            and setup_elapsed + artifact_budget["artifact_elapsed_seconds"] == artifact_budget["setup_artifact_elapsed_seconds"] <= limit,
            "Phase1 artifact finalization budget")
    total = {k: int(v) for k, v in commands["Verify selected total budget before upload"]["numericFacts"].items()}
    require(total.get("total_budget_seconds") == selected["totalBudgetSeconds"]
            and total.get("elapsed_seconds", -1) >= setup_elapsed
            and total["elapsed_seconds"] <= total["total_budget_seconds"], "Phase1 total budget")
    build = None
    if label in ("producer", "rui1"):
        build = verify_no_index_build(root, artifact, record, environment, command_artifact=original_artifact)
    unit_command = None
    if label != "producer":
        expected = [provider["developer_dir"] + "/usr/bin/xcodebuild", "-project", "FieldEvidenceApp.xcodeproj",
                    "-scheme", "FieldEvidenceApp", "-configuration", "Debug", "-destination", environment["CI_DESTINATION"],
                    "-derivedDataPath", str(PurePosixPath(environment["RUNNER_TEMP"]) / "FieldEvidenceDerivedData"),
                    "-resultBundlePath", str(original_artifact / "UnitTests.xcresult"),
                    *["-only-testing:" + value for value in selected["unitTestSelectors"]],
                    "CODE_SIGNING_ALLOWED=NO", "test-without-building"]
        raw_log = gate.regular_bytes(artifact / "test-smoke.log", limit=SHARED_MAX_TEST_LOG_BYTES)
        log = raw_log.decode("utf-8")
        lines = log.splitlines()
        invocations = [i for i, line in enumerate(lines) if line.strip() == "Command line invocation:"]
        require(len(invocations) == 1 and invocations[0] + 1 < len(lines)
                and shlex.split(lines[invocations[0] + 1].strip()) == expected
                and sum(line.strip() == "** TEST EXECUTE SUCCEEDED **" for line in lines) == 1
                and not shared_test_log_compile_lines(artifact / "test-smoke.log"),
                "Phase1 exact successful no-rebuild unit invocation")
        unit_command = {"argv": expected, "logSHA256": sha256(raw_log),
                        "exporterSourceSHA256": sha256((root / "Scripts/validate-required-evidence.sh").read_bytes()),
                        "structuredResultSHA256": sha256((artifact / "unit-test-results.json").read_bytes()),
                        "exportReexecutedOffline": False}
    checkpoint = read_json(artifact / "native-checkpoint.json")
    require(checkpoint.get("recordType") == "validated-native-checkpoint"
            and all(checkpoint.get(k) == v for k, v in record.items())
            and checkpoint.get("provider") == provider and checkpoint.get("simulator") == simulator and checkpoint.get("sdk") == sdk
            and checkpoint.get("releaseReady") is False and checkpoint.get("acceptance") is False,
            "Phase1 original live checkpoint binding")
    require(checkpoint.get("executedUnitMethods") == ([] if label == "producer" else sorted(selected["unitTestSelectors"]))
            and checkpoint.get("executedUIMethods") == sorted(selected["uiTestSelectors"]),
            "Phase1 live checkpoint complete method census")
    forbidden = (("test-smoke.log", "UnitTests.xcresult", "unit-test-results.json") if label == "producer" else
                 ("build-smoke.log", "Build.xcresult", NO_INDEX_RECEIPT) if label != "rui1" else ())
    require(not any((artifact / name).exists() or (artifact / name).is_symlink() for name in forbidden),
            "Phase1 unexpected role execution evidence")
    require(source_closure(root, gate_dict) == sources, "cold worker execution source changed during recomputation")
    return {"jobID": job["jobID"], "jobLogSHA256": job["jobLogSHA256"], "build": build, "unitCommand": unit_command,
            "budgets": {"setup": setup, "restore": restore, "artifact": artifact_budget, "total": total,
                        "finalizationPredicatePassed": True, "finalizationNumericElapsedAvailable": False},
            "simulator": simulator, "checkpointSHA256": sha256((artifact / "native-checkpoint.json").read_bytes()),
            "offlineNativeExecution": False}




# Explicit Phase1 V2 DATA interfaces. The legacy V1 and cold bodies above are
# unchanged; a V2 plan is never converted to either predecessor's schema.
PHASE1_INPUT_SCHEMA_V2 = "v23-retained-payload-input.v2"
PHASE1_FACT_SCHEMA_V2 = "v23-retained-payload-facts.v2"
PHASE1_PENDING_V2 = (
    "authenticated original API census, attempt/discovery and sole-collector authority",
    "frozen Git head/tree and archived-source provenance authentication",
    "complete authentic original-bound emitted diagnostic transport",
    "actual live safe-extraction, no-rebuild and every-method execution proof",
    "complete job/download/command/runtime facts and genuine independent review",
    "versioned Phase1 candidate gates, owner review and exact-main lifecycle",
)
PHASE1_SCOPE_V2 = {
    "dataOnly": True, "executionAuthority": False, "authentication": False,
    "qualification": False, "functionalQualification": "PENDING_RAW_PROOF_AND_INDEPENDENT_REVIEW",
    "providerQualification": False, "acceptance": False, "releaseReady": False,
    "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED",
    "physicalProtectionReleaseBlocker": True, "emittedTransport": "PENDING",
    "totalPolicyCallCountProven": False, "exhaustiveKernelProcessCohortProven": False,
    "perPIDDescriptorRetirementProven": False, "exactCheckpointRepeatProven": False,
}
PHASE1_UNPROVEN_V2 = (
    "total policy-call counts", "exhaustive kernel process cohorts",
    "per-PID descriptor retirement", "exact checkpoint repeat",
)


def phase1_envelope_facts_v2(value, root, ci, gate):
    """Validate the actual closed V2 plan; supplied API facts remain DATA."""
    require(type(value) is dict and set(value) == {"schema", "plan", "runID", "runAttempt", "payloadArtifact"}
            and value["schema"] == PHASE1_INPUT_SCHEMA_V2, "closed Phase1 V2 factual envelope")
    require("validate_plan_v2" in gate and "make_plan_v2" in gate,
            "unsupported Phase1 retained gate V2 ABI")
    plan = gate["validate_plan_v2"](value["plan"])
    require(plan["selection"] == ci["SHARED_SELECTION_ID"], "shared Phase1 V2 payload plan only")
    require(type(value["runID"]) is int and value["runID"] > 0
            and type(value["runAttempt"]) is int and value["runAttempt"] == 1, "declared frozen original IDs")
    sources = source_closure(root, gate)
    require(sources == plan["sources"], "source closure differs from frozen plan DATA")
    resolved = ci["shared_selection"](root)
    rebuilt = gate["make_plan_v2"](purpose=plan["purpose"], head=plan["head"], tree=plan["tree"],
        selection=plan["selection"], resolved_bytes=ci["canonical"](resolved), sources=sources,
        requested_at=plan["requestedAtUTC"], cold_prerequisite=plan["coldPrerequisite"])
    require(canonical(rebuilt) == canonical(plan), "source-resolved ordered selection differs")
    artifact = value["payloadArtifact"]
    require(type(artifact) is dict, "raw API artifact DATA object")
    origin = artifact.get("workflow_run")
    name = "v23-shared-payload-%d-1-%s" % (value["runID"], plan["head"])
    require(type(artifact.get("id")) is int and artifact["id"] > 0 and artifact.get("expired") is False
            and artifact.get("name") == name and type(artifact.get("size_in_bytes")) is int
            and artifact["size_in_bytes"] > 0 and type(artifact.get("digest")) is str
            and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact["digest"]), "declared outer API artifact grammar")
    require(type(origin) is dict and type(origin.get("id")) is int and origin["id"] == value["runID"]
            and origin.get("head_sha") == plan["head"]
            and origin.get("head_branch") == plan["ref"].removeprefix("refs/heads/"), "declared API original join")
    return plan, resolved, sources


def phase1_close_handles_v2(handles, primary):
    """Attempt each owned close once; retain the genuine primary object."""
    errors = []
    for handle in reversed(handles):
        try:
            os.close(handle)
        except BaseException as error:
            errors.append(error)
    if primary is not None:
        for error in errors:
            primary.add_note("secondary Phase1 V2 directory close: " + repr(error))
    elif errors:
        for error in errors[1:]:
            errors[0].add_note("secondary Phase1 V2 directory close: " + repr(error))
        raise errors[0]


def phase1_worker_states_v2(artifact, producer, ci):
    """Fence the actual V2 payload validator's inputs, without replaying a job."""
    names = ["native-admission.json", "phase1-event-binding.json", "phase1-original-event.json",
             "phase1-gate-plan.json", METADATA, "ci-selection.selected.json"]
    stages = ("seal",) if producer else ("restore", "before", "after")
    names += ["phase1-shared-live-v2-" + stage + ".json" for stage in stages]
    names += ([ci["SHARED_PAYLOAD_RECEIPT"]] if producer else
              [ci["SHARED_RESTORE_RECEIPT"], "v23-shared-fingerprint-before.json", "v23-shared-fingerprint-after.json",
               ci["SHARED_DERIVED_DATA_DELTA"], "test-smoke.log"])
    paths = [(artifact / name, ci["SHARED_MAX_TEST_LOG_BYTES"] if name == "test-smoke.log" else JSON_BYTES) for name in names]
    if not producer:
        directory = artifact / "phase1-activity-logs-v2"
        handles, primary = directory_chain(directory), None
        try:
            names = bounded_names(handles[-1], TAR_MEMBERS)
            paths += [(directory / name, ci["PHASE1_ACTIVITY_TOTAL_BYTES"]) for name in names]
        except BaseException as error:
            primary = error
            raise
        finally:
            phase1_close_handles_v2(handles, primary)
    handles, primary = directory_chain(artifact), None
    try:
        states = {"directory": snapshot(os.fstat(handles[-1])),
                  "memberNames": bounded_names(handles[-1], TAR_MEMBERS)}
        require(states["directory"] == snapshot(artifact.lstat()), "Phase1 V2 worker held/name directory join")
        if not producer:
            forbidden = {}
            for name in ("Build.xcresult", "build-smoke.log", ci["NO_INDEX_RECEIPT"]):
                try:
                    info = os.stat(name, dir_fd=handles[-1], follow_symlinks=False)
                except FileNotFoundError:
                    forbidden[name] = {"absent": True}
                else:
                    forbidden[name] = {"absent": False, "stat": snapshot(info)}
            states["forbiddenConsumerLeaves"] = forbidden
    except BaseException as error:
        primary = error
        raise
    finally:
        phase1_close_handles_v2(handles, primary)
    total = 0
    for path, limit in paths:
        # Reuse the incumbent bounded read and its nine-field endpoint guard;
        # st_flags is not part of the inherited runtime snapshot.
        raw = regular_bytes(path, limit)
        if path.parent.name == "phase1-activity-logs-v2":
            total += len(raw)
            require(total <= ci["PHASE1_ACTIVITY_TOTAL_BYTES"], "Phase1 V2 retained activity byte bound")
        states[str(path)] = {"stat": snapshot(path.lstat()), "bytes": len(raw), "sha256": sha(raw)}
    return states


def phase1_workers_states_v2(directory, labels, ci):
    """Observe the complete retained worker interval, including named absences."""
    if directory is None:
        return None
    directory = clean_absolute(directory)
    handles, primary = directory_chain(directory), None
    try:
        state = {"directory": snapshot(os.fstat(handles[-1])), "labels": bounded_names(handles[-1], len(labels))}
        require(state["directory"] == snapshot(directory.lstat()), "Phase1 V2 retained workers held/name directory join")
        require(state["labels"] == sorted(labels), "complete producer/every-consumer directory census")
        state["workers"] = {label: phase1_worker_states_v2(directory / label, label == "producer", ci) for label in labels}
        return state
    except BaseException as error:
        primary = error
        raise
    finally:
        phase1_close_handles_v2(handles, primary)


def phase1_workers_unchanged_v2(directory, labels, ci, before):
    require(phase1_workers_states_v2(directory, labels, ci) == before,
            "Phase1 V2 retained workers changed during complete recomputation interval")


def phase1_event_data_join_v2(artifact, value, plan, binding, gate):
    """Join authentic retained bytes as DATA; enclosing collector authenticates API."""
    require("plan_from_event_v2" in gate and "validate_received_inputs_v2" in gate,
            "unsupported Phase1 retained event V2 ABI")
    event_raw = regular_bytes(artifact / "phase1-original-event.json", gate["MAX_EVENT_BYTES"])
    event_plan, event = gate["plan_from_event_v2"](event_raw)
    require(event_plan == plan, "Phase1 V2 retained original event DATA join")
    received_shape = gate["validate_received_inputs_v2"](event.get("inputs"), plan)
    require(type(received_shape) is str
            and received_shape in ("COMPLETE_13", "OMITTED_EMPTY_DEFAULTS_10"),
            "unsupported Phase1 received-input V2 result ABI")
    require(event.get("ref") in (plan["ref"], plan["ref"].removeprefix("refs/heads/"))
            and type(event.get("repository")) is dict
            and event["repository"].get("full_name") == plan["route"]["repository"],
            "Phase1 V2 retained original event DATA join")
    expected = {
        "schema": "v23-phase1-original-event-binding.v2", "plan": plan, "planSHA256": sha(canonical(plan)),
        "originalEventSHA256": sha(event_raw), "repository": plan["route"]["repository"], "ref": plan["ref"],
        "head": plan["head"], "tree": plan["tree"],
        "workflowRef": plan["route"]["repository"] + "/" + plan["route"]["workflow"] + "@" + plan["ref"],
        "workflowSHA": plan["head"], "runID": str(value["runID"]), "runAttempt": "1", "kind": "gate",
        "selection": plan["selection"], "functionalQualification": gate["PENDING"],
    }
    require(canonical(binding) == canonical(expected), "closed Phase1 V2 retained binding DATA join")
    require(regular_bytes(artifact / "phase1-gate-plan.json") == canonical(plan), "Phase1 V2 retained plan exact bytes")


def phase1_worker_joins_v2(root, directory, value, plan, resolved, raw, products, archive, census, ci, gate, kernel, *, input_states):
    """Join real V2 observations to independently extracted payload, DATA only."""
    labels = ["producer"] + resolved[ci["SHARED_KEY"]]["partitionIDs"]
    if directory is None:
        return {"status": "PENDING_MISSING_RETAINED_WORKERS", "requiredLabels": labels}
    require("phase1_retained_shared_facts_v2" in ci, "unsupported Phase1 retained native V2 ABI")
    directory = clean_absolute(directory)
    handles, primary = directory_chain(directory), None
    try:
        require(bounded_names(handles[-1], len(labels)) == sorted(labels), "complete producer/every-consumer directory census")
        facts = {}
        protocol = ci["source_binding"](root)
        entries = kernel["inventory"](Path(archive["extractedRoot"]) / kernel["ROOT_LABEL"])
        for label in labels:
            artifact = directory / label
            worker_handles, worker_error = directory_chain(artifact), None
            try:
                producer = label == "producer"
                before = input_states["workers"][label]
                require(phase1_worker_states_v2(artifact, producer, ci) == before,
                        "Phase1 V2 retained worker changed before Native computation")
                record = decode(regular_bytes(artifact / "native-admission.json"))
                binding = decode(regular_bytes(artifact / "phase1-event-binding.json"))
                phase1_event_data_join_v2(artifact, value, plan, binding, gate)
                require(record.get("phase1Gate") == binding, "Phase1 V2 worker actual original binding")
                require((record.get("repository"), record.get("head"), record.get("gitTree"), record.get("ref"),
                         record.get("runID"), record.get("runAttempt"), record.get("selectionID"))
                        == (plan["route"]["repository"], plan["head"], plan["tree"], plan["ref"],
                            str(value["runID"]), "1", ci["SHARED_SELECTION_ID"]), "worker original DATA join")
                require(all(record.get(key) == fact for key, fact in protocol.items()), "worker source protocol DATA join")
                selected = resolved if producer else ci["shared_selection"](root, label)
                selected_raw = ci["canonical"](selected)
                require(regular_bytes(artifact / "ci-selection.selected.json") == selected_raw
                        and record.get("selectionSHA256") == sha(selected_raw), "worker actual ordered selection DATA join")
                require(record.get(ci["SHARED_KEY"]) == {
                    "role": "producer" if producer else "consumer", "partitionID": None if producer else label,
                    "payloadArtifactName": value["payloadArtifact"]["name"], "planSHA256": plan["selectionSHA256"],
                    "partitionsSHA256": resolved[ci["SHARED_KEY"]]["partitionsSHA256"]},
                    "worker role/partition/payload DATA join")
                require(regular_bytes(artifact / METADATA) == raw, "worker exact retained metadata bytes")
                computed = ci["phase1_retained_shared_facts_v2"](root, artifact, record, binding)
                require(computed.get("schema") == "v23-phase1-retained-shared-facts.v2"
                        and computed.get("status") == "COMPLETE_RETAINED_SHARED_OBSERVATIONS"
                        and computed.get("functionalQualification") == gate["PENDING"]
                        and all(computed.get(key) is False for key in
                                ("acceptance", "providerQualification", "releaseReady", "payloadArchiveRetained",
                                 "liveChecksIndependentlyReexecuted")), "Phase1 V2 retained facts remain unqualified DATA")
                for stage in (("seal",) if producer else ("restore", "before", "after")):
                    witness_path = artifact / ("phase1-shared-live-v2-" + stage + ".json")
                    observation = decode(regular_bytes(witness_path))
                    require(computed["liveObservationSHA256"].get(stage) == before[str(witness_path)]["sha256"],
                            "Phase1 V2 actual retained witness digest join")
                    require(observation["products"] == products and observation["productInventory"] == entries,
                            "worker observation/recomputed product join")
                    if stage in ("seal", "restore"):
                        require(observation["archive"] == {key: archive[key] for key in ("name", "bytes", "sha256")}
                                and observation["archiveMemberCensus"] == census, "worker observation/recomputed TAR join")
                facts[label] = {"retainedFacts": computed, "admissionSHA256": sha(canonical(record)),
                                "bindingSHA256": sha(canonical(binding))}
                require(phase1_worker_states_v2(artifact, producer, ci) == before,
                        "retained worker inputs changed during recomputation")
            except BaseException as error:
                worker_error = error
                raise
            finally:
                phase1_close_handles_v2(worker_handles, worker_error)
        return {"status": "RECOMPUTED_ALL_RETAINED_WORKER_JOINS_DATA", "workers": facts}
    except BaseException as error:
        primary = error
        raise
    finally:
        phase1_close_handles_v2(handles, primary)

def recompute_phase1_retained_payload_v2(zip_path, envelope_path, source_root, destination, *, retained_workers=None):
    """Materialize in a NEW private destination; retain failures, never clean up.

    Caller must exclude concurrent writers to input/source/destination/retained
    worker trees. No current runner paths named inside metadata are opened.
    Return factual output, never authentication/authorization/qualification.
    """
    owned = Owned(destination)
    receipts, stage, primary = {}, "raw-retention", None
    try:
        owned.copy(clean_absolute(envelope_path), "input-envelope.json", JSON_BYTES, receipts)
        owned.copy(clean_absolute(zip_path), "payload.zip", ZIP_BYTES, receipts)
        stage = "source-and-envelope"
        root = clean_absolute(source_root)
        ci, gate, kernel = source_modules(root)
        value = decode(regular_bytes(owned.path / "input-envelope.json"))
        plan, resolved, sources = phase1_envelope_facts_v2(value, root, ci, gate)
        require(receipts["payload.zip"]["sha256"].lower() == value["payloadArtifact"]["digest"].removeprefix("sha256:"),
                "outer ZIP digest differs from declared API DATA")
        # API size remains a distinct reported fact, never equated to ZIP bytes.
        stage = "zip-transport"
        owned.check()
        extract_transport(owned.path / "payload.zip", owned.path / "transport")
        stage = "inner-digest"
        tar = owned.path / "transport" / TAR_NAME
        digest_raw = regular_bytes(owned.path / "transport" / DIGEST_NAME, 256)
        match = re.fullmatch(rb"([0-9A-F]{64}) ([0-9]{1,20}) FieldEvidencePayload\.tar\n", digest_raw)
        require(match is not None, "distinct uppercase inner TAR digest grammar")
        require(int(match[2]) == tar.stat().st_size and 0 < int(match[2]) <= TAR_BYTES
                and kernel["sha256_file"](tar) == match[1].decode("ascii"), "inner TAR digest or bytes differ")
        archive = {"name": TAR_NAME, "bytes": int(match[2]), "sha256": match[1].decode("ascii")}
        stage = "tar-preflight"
        tar_preflight(tar, kernel)
        census = ci["phase1_tar_census"](tar, kernel)
        stage = "kernel-extraction"
        owned.check()
        extracted = owned.path / "extracted"
        kernel["extract_tar"](tar, extracted)
        require(sorted(p.name for p in extracted.iterdir()) == sorted(["FieldEvidenceDerivedData", METADATA]), "exact extracted root")
        stage = "metadata-products"
        raw, metadata, products = metadata_facts(extracted, value, plan, resolved, ci, kernel)
        # Exact archive census must equal the actual safely materialized view.
        expected_census = [{"path": e["path"], "type": e["type"], "size": e.get("size", 0), "mode": e["mode"]}
                           for e in kernel["inventory"](extracted)]
        require(census == expected_census, "actual extracted/census join")
        product_entries = kernel["inventory"](extracted / kernel["ROOT_LABEL"])
        allowed = {"FieldEvidenceDerivedData", "FieldEvidenceDerivedData/Build", kernel["ROOT_LABEL"], METADATA}
        allowed.update(kernel["ROOT_LABEL"] + "/" + entry["path"] for entry in product_entries)
        require({entry["path"] for entry in census} == allowed, "closed payload member closure")
        stage = "retained-worker-joins"
        worker_labels = ["producer"] + resolved[ci["SHARED_KEY"]]["partitionIDs"]
        worker_inputs = phase1_workers_states_v2(retained_workers, worker_labels, ci)
        join_reader = phase1_worker_joins_v2
        joins = join_reader(root, retained_workers, value, plan, resolved, raw, products,
                            dict(archive, extractedRoot=str(extracted)), census, ci, gate, kernel,
                            input_states=worker_inputs)
        stage = "final-invariance"
        phase1_workers_unchanged_v2(retained_workers, worker_labels, ci, worker_inputs)
        require(source_closure(root, gate) == sources, "source closure changed during recomputation")
        require(all(list(snapshot((owned.path / name).lstat())) == receipt["ownedStat"]
                    for name, receipt in receipts.items()), "retained raw input copy changed")
        require(ci["shared_selection"](root) == resolved, "ordered selection changed during recomputation")
        require(kernel["sha256_file"](tar) == archive["sha256"]
                and ci["shared_products_binding"](kernel, extracted) == products
                and regular_bytes(extracted / METADATA) == raw, "owned TAR/metadata/products changed")
        owned.check()
        stage = "durable-publication"
        durability = owned.sync_tree()
        phase1_workers_unchanged_v2(retained_workers, worker_labels, ci, worker_inputs)
        result = {"schema": PHASE1_FACT_SCHEMA_V2,
                  "status": "RECOMPUTED_PHASE1_RETAINED_PAYLOAD_DATA_ONLY_UNQUALIFIED",
                  "envelopeSHA256": receipts["input-envelope.json"]["sha256"],
                  "outerZIP": {"bytes": receipts["payload.zip"]["bytes"], "sha256": receipts["payload.zip"]["sha256"].lower(),
                               "declaredAPIArtifact": value["payloadArtifact"]},
                  "archive": archive, "digestFileSHA256": sha(digest_raw), "metadataSHA256": sha(raw),
                  "originalDATA": {"repository": plan["route"]["repository"], "ref": plan["ref"], "head": plan["head"],
                                   "tree": plan["tree"], "runID": value["runID"], "runAttempt": value["runAttempt"],
                                   "planSHA256": sha(canonical(plan))},
                  "sourceSHA256": sources, "executableSourceSHA256": EXECUTABLE_SOURCES,
                  "products": products, "archiveMemberCensus": census, "workerJoins": joins,
                  "originalPayloadClassification": {"developmentOnly": metadata["developmentOnly"], "acceptance": metadata["acceptance"]},
                  "declaredBuildDigests": {key: metadata[key] for key in ("buildCommandReceiptSHA256", "buildLogSHA256")},
                  "pendingProof": list(PHASE1_PENDING_V2), "ownedCopies": receipts,
                  "durability": durability}
        result["scope"] = dict(PHASE1_SCOPE_V2)
        result["unprovenClaims"] = list(PHASE1_UNPROVEN_V2)
        owned.write("FACTS.json", canonical(result))
        stage = "final-worker-invariance"
        phase1_workers_unchanged_v2(retained_workers, worker_labels, ci, worker_inputs)
        return result
    except BaseException as error:
        primary = error
        try:
            durability = owned.sync_tree()
        except Exception as sync_error:
            durability = {"status": "UNPROVEN", "errorType": type(sync_error).__name__}
        failure = {"schema": "v23-phase1-retained-payload-failure.v2",
                   "status": "REFUSED_PARTIAL_OWNED_DATA_RETAINED",
                   "stage": stage, "errorType": type(error).__name__, "reason": str(error)[:1000],
                   "ownedCopies": receipts, "pendingProof": list(PHASE1_PENDING_V2), "durability": durability}
        try:
            owned.write("FAILURE.json", canonical(failure))
        except Exception as receipt_error:
            raise Refused("%s; failure receipt unavailable: %s; owned destination retained at %s"
                          % (error, receipt_error, owned.path)) from error
        if not isinstance(error, Exception):
            raise
        raise Refused("%s; failure receipt: %s" % (error, owned.path / "FAILURE.json")) from error
    finally:
        # Detach before once-closing every acquired owned endpoint; a cleanup
        # failure refuses success and cannot replace a genuine primary error.
        handles = owned.parents + ([] if owned.fd is None else [owned.fd])
        owned.parents, owned.fd = [], None
        phase1_close_handles_v2(handles, primary)



if __name__ == "__main__":
    raise SystemExit("Dormant library only; no collector/qualification CLI activation.")
