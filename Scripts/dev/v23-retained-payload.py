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
import stat
import struct
import tarfile
from types import SimpleNamespace
import zipfile
import zlib


INPUT_SCHEMA = "v23-retained-payload-input.v1"
FACT_SCHEMA = "v23-retained-payload-facts.v1"
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
    "Scripts/v23-native-ci.py": "87f6bd5d2ecaa1250deab0467ee6ddafeb67e6abc13f2ea11acdac3ca1f696c8",
    "Scripts/v23-phase1-gates.py": "d9fcbf89aebd0b97ed471b27b641eb3b97247c2c917d2bab6779269bdc2e9c92",
    "Scripts/s10-4-build-payload.py": "ea731fd64278d3ab242956bf2f36d486254903a10f5f8bc17c65de3d10397521",
    "Scripts/v23-selection-generator.py": "4a987864e3046e165c35bb8af1278a693c83a4bb90d2d398e81d528cff2c1c2a",
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


def envelope_facts(value, root, ci, gate):
    require(type(value) is dict and set(value) == {"schema", "plan", "runID", "runAttempt", "payloadArtifact"}
            and value["schema"] == INPUT_SCHEMA, "closed factual envelope")
    plan = gate["validate_plan"](value["plan"])
    require(plan["selection"] == ci["SHARED_SELECTION_ID"], "shared payload plan only")
    require(type(value["runID"]) is int and value["runID"] > 0
            and type(value["runAttempt"]) is int and value["runAttempt"] == 1, "declared frozen original IDs")
    sources = source_closure(root, gate)
    require(sources == plan["sources"], "source closure differs from frozen plan DATA")
    resolved = ci["shared_selection"](root)
    rebuilt = gate["make_plan"](purpose=plan["purpose"], head=plan["head"], tree=plan["tree"],
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


def metadata_facts(extracted, value, plan, resolved, ci, kernel):
    raw = regular_bytes(extracted / METADATA)
    metadata = decode(raw)
    workspace = metadata.get("workspace") if type(metadata) is dict else None
    require(type(workspace) is str and workspace.startswith("/") and "\x00" not in workspace
            and all(p not in (".", "..") for p in workspace.split("/")), "original workspace spelling DATA")
    expected = {
        "schema": ci["SHARED_PAYLOAD_SCHEMA"], "routeID": ci["SHARED_SELECTION_ID"],
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


def recompute_retained_payload(zip_path, envelope_path, source_root, destination, *, retained_workers=None):
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
        plan, resolved, sources = envelope_facts(value, root, ci, gate)
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
        joins = worker_joins(root, retained_workers, value, plan, resolved, raw, products,
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
        result = {"schema": FACT_SCHEMA, "status": "RECOMPUTED_RETAINED_PAYLOAD_DATA",
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
                  "pendingProof": list(PENDING), "ownedCopies": receipts,
                  "durability": durability}
        owned.write("FACTS.json", canonical(result))
        return result
    except BaseException as error:
        try:
            durability = owned.sync_tree()
        except Exception as sync_error:
            durability = {"status": "UNPROVEN", "errorType": type(sync_error).__name__}
        failure = {"schema": "v23-retained-payload-failure.v1", "status": "REFUSED_PARTIAL_OWNED_DATA_RETAINED",
                   "stage": stage, "errorType": type(error).__name__, "reason": str(error)[:1000],
                   "ownedCopies": receipts, "pendingProof": list(PENDING), "durability": durability}
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


if __name__ == "__main__":
    raise SystemExit("Dormant library only; no collector/qualification CLI activation.")
