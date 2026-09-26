import Foundation

/// Plain-files salvage for maintenance (blueprint: post-activation failures
/// enter maintenance/export/support). When no backup can be produced, for
/// example with a corrupt receipt history, the user can still save their own
/// photos and report PDFs from the last accepted generation.
///
/// This is deliberately NOT a backup: no archive format, no manifest, not
/// restorable. It reads only the current pointer and the generation's
/// `evidence/<id>/original.jpg` and `pdfs/<id>.pdf` files, opens no store
/// session, writer or lease, never writes under Application Support, and skips
/// anything that does not validate instead of failing the whole save.
///
/// Every app-owned path component is opened with `O_NOFOLLOW` descriptors from
/// the OS-provided Application Support directory; each file is opened no-follow,
/// proved a regular file with `fstat` on that same descriptor, and read through
/// it, so there is no check-then-use gap. Photos are the canonical normalized
/// originals (MediaNormalizerV1 re-encodes and drops every APPn/COM segment,
/// including EXIF and GPS); a copy that still carries such a segment is skipped.
struct MaintenanceSalvageExportV1 {
    enum Kind: String, Equatable, Sendable { case photo, report }

    struct Item: Equatable, Sendable {
        let kind: Kind
        let id: UUID
        let sourceRelativePath: String
        let fileName: String
    }

    enum Failure: Error, Equatable {
        case noAcceptedGeneration
        case nothingToSave
        case unsafeDestination
    }

    static let folderName = "AssetRounds Photos and Reports"
    private static let maximumItemCount = 100_000
    private static let maximumFileByteCount = 512 * 1024 * 1024

    let applicationSupportURL: URL
    var fileManager: FileManager = .default

    /// Read-only inventory of the last accepted generation.
    func inventory() throws -> [Item] {
        try withGenerationRoot { generation in try inventory(in: generation) }
    }

    /// Copies the inventory into `parent/<folderName>` and returns that folder.
    /// `parent` must be a fresh, caller-owned temporary folder outside
    /// Application Support; the caller deletes it when sharing ends.
    /// Unreadable or non-canonical files are skipped.
    func materialize(into parent: URL) throws -> (folder: URL, saved: [Item]) {
        let support = applicationSupportURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let target = parent.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard !target.hasPrefix(support), !support.hasPrefix(target) else { throw Failure.unsafeDestination }
        return try withGenerationRoot { generation in
            let items = try inventory(in: generation)
            let folder = parent.appendingPathComponent(Self.folderName, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
            var saved: [Item] = []
            for item in items {
                guard let data = try? readRegular(generation, item.sourceRelativePath),
                      item.kind != .photo || Self.isMetadataFreeJPEG(data) else { continue }
                try data.write(to: folder.appendingPathComponent(item.fileName), options: .withoutOverwriting)
                saved.append(item)
            }
            guard !saved.isEmpty else {
                try? fileManager.removeItem(at: folder)
                throw Failure.nothingToSave
            }
            return (folder, saved)
        }
    }

    // MARK: - Anchored, read-only access

    private func inventory(in generation: Int32) throws -> [Item] {
        var photos: [(Date, UUID)] = []
        if let evidence = try? openDirectory(generation, "evidence") {
            defer { close(evidence) }
            for name in entries(evidence) {
                guard let id = canonicalID(name), let directory = try? openDirectory(evidence, name) else { continue }
                defer { close(directory) }
                guard let date = regularFileDate(directory, "original.jpg") else { continue }
                photos.append((date, id))
            }
        }
        var reports: [(Date, UUID)] = []
        if let pdfs = try? openDirectory(generation, "pdfs") {
            defer { close(pdfs) }
            for name in entries(pdfs) where (name as NSString).pathExtension == "pdf" {
                guard let id = canonicalID((name as NSString).deletingPathExtension),
                      let date = regularFileDate(pdfs, name) else { continue }
                reports.append((date, id))
            }
        }
        guard photos.count + reports.count <= Self.maximumItemCount else { throw Failure.nothingToSave }
        let order: ((Date, UUID), (Date, UUID)) -> Bool = { ($0.0, $0.1.uuidString) < ($1.0, $1.1.uuidString) }
        return photos.sorted(by: order).map {
            Item(kind: .photo, id: $0.1, sourceRelativePath: "evidence/\(Self.canonical($0.1))/original.jpg",
                 fileName: "Photo \(Self.stamp($0.0)) \(Self.shortID($0.1)).jpg")
        } + reports.sorted(by: order).map {
            Item(kind: .report, id: $0.1, sourceRelativePath: "pdfs/\(Self.canonical($0.1)).pdf",
                 fileName: "Report \(Self.stamp($0.0)) \(Self.shortID($0.1)).pdf")
        }
    }

    /// Trusts only the OS-provided Application Support ancestry, then opens
    /// FieldEvidenceData, generations and the accepted generation no-follow.
    private func withGenerationRoot<T>(_ body: (Int32) throws -> T) throws -> T {
        let support = open(applicationSupportURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard support >= 0 else { throw Failure.noAcceptedGeneration }
        defer { close(support) }
        guard let data = try? openDirectory(support, "FieldEvidenceData") else { throw Failure.noAcceptedGeneration }
        defer { close(data) }
        guard let pointer = try? readRegularFile(data, "current.json", maximum: 64 * 1024),
              let envelope = try? CurrentPointerCodecV1.decode(pointer),
              let id = canonicalID(envelope.generationID),
              let generations = try? openDirectory(data, "generations") else { throw Failure.noAcceptedGeneration }
        defer { close(generations) }
        guard let generation = try? openDirectory(generations, Self.canonical(id)) else {
            throw Failure.noAcceptedGeneration
        }
        defer { close(generation) }
        return try body(generation)
    }

    private func openDirectory(_ parent: Int32, _ name: String) throws -> Int32 {
        let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.noAcceptedGeneration }
        return descriptor
    }

    private func readRegular(_ generation: Int32, _ relativePath: String) throws -> Data {
        var components = relativePath.split(separator: "/").map(String.init)
        guard let leaf = components.popLast() else { throw Failure.nothingToSave }
        var directory = generation
        var owned: [Int32] = []
        defer { owned.forEach { close($0) } }
        for component in components {
            directory = try openDirectory(directory, component)
            owned.append(directory)
        }
        return try readRegularFile(directory, leaf, maximum: Self.maximumFileByteCount)
    }

    /// Opens no-follow, proves a regular file on the same descriptor, and
    /// reads through it.
    private func readRegularFile(_ parent: Int32, _ name: String, maximum: Int) throws -> Data {
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.nothingToSave }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var facts = stat()
        guard fstat(descriptor, &facts) == 0, facts.st_mode & S_IFMT == S_IFREG,
              facts.st_size >= 0, facts.st_size <= off_t(maximum) else { throw Failure.nothingToSave }
        let data = try handle.readToEnd() ?? Data()
        guard data.count == Int(facts.st_size) else { throw Failure.nothingToSave }
        return data
    }

    private func regularFileDate(_ parent: Int32, _ name: String) -> Date? {
        let descriptor = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var facts = stat()
        guard fstat(descriptor, &facts) == 0, facts.st_mode & S_IFMT == S_IFREG else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(facts.st_mtimespec.tv_sec))
    }

    private func entries(_ directory: Int32) -> [String] {
        let copy = dup(directory)
        guard copy >= 0, let stream = fdopendir(copy) else {
            if copy >= 0 { close(copy) }
            return []
        }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            var name = entry.pointee.d_name
            let value = withUnsafeBytes(of: &name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if value != "." && value != ".." { names.append(value) }
        }
        return names.sorted()
    }

    /// True for a JPEG whose header carries no APPn (other than JFIF APP0 and
    /// ICC APP2) or COM segment, i.e. no EXIF, GPS, XMP or comments.
    static func isMetadataFreeJPEG(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(1024 * 1024))
        guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { return false }
        var offset = 2
        while offset + 3 < bytes.count {
            guard bytes[offset] == 0xff else { return false }
            let marker = bytes[offset + 1]
            if marker == 0xda || marker == 0xd9 { return true }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2 else { return false }
            if marker == 0xfe || ((0xe1...0xef).contains(marker) && marker != 0xe2) { return false }
            if marker == 0xe2 {
                let tag = Array("ICC_PROFILE\0".utf8)
                guard offset + 4 + tag.count <= bytes.count,
                      Array(bytes[(offset + 4)..<(offset + 4 + tag.count)]) == tag else { return false }
            }
            offset += 2 + length
        }
        return false
    }

    private func canonicalID(_ name: String) -> UUID? {
        guard let id = UUID(uuidString: name), Self.canonical(id) == name else { return nil }
        return id
    }

    private static func canonical(_ id: UUID) -> String { id.uuidString.lowercased() }

    private static func shortID(_ id: UUID) -> String { String(canonical(id).prefix(8)) }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: date)
    }
}
