import Foundation
import Darwin

/// A one-shot physical observation, never an Erase or publication capability.
/// The genuine operation retains this owner before opening any descriptor and
/// keeps its access/epoch fence through observation and writer return. Its
/// expected identity must come from the original writer's retained registry,
/// not from a fresh stat of the returned path.
@MainActor
final class EraseUnadmittedControlObservationV1 {
    enum Status: Equatable {
        case unopened, observing, absentAndClosed, refused, refusedAndClosed, closeUncertain
    }
    enum Failure: Error, Equatable {
        case invalidIdentity, controlsPresent, invalidState, systemCall, closeUncertain
    }

    private let supportURL: URL
    private let expectedSupport: StoreApplicationSupportIdentity
    private var support: Int32?
    private var erase: Int32?
    private var directoryDuplicate: Int32?
    private var stream: UnsafeMutablePointer<DIR>?
    private struct EraseDirectorySnapshot: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ value: stat) {
            device = value.st_dev
            inode = value.st_ino
            size = value.st_size
            modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
            changedSeconds = Int64(value.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        }
    }
    private var eraseSnapshot: EraseDirectorySnapshot?
    private(set) var status: Status = .unopened
    private(set) var closeErrors: [Int32] = []
    private static let eraseName = "FieldEvidenceErase"

    // Deliberately no filesystem operation or validation in initialization.
    init(applicationSupportURL: URL,
         expectedSourceSupportIdentity: StoreApplicationSupportIdentity) {
        supportURL = applicationSupportURL
        expectedSupport = expectedSourceSupportIdentity
    }

    /// Accepts only an absent Erase root or a physically empty real directory.
    /// Any entry (including any canonical/pending/preparation control) refuses.
    /// Failures retain all successfully opened descriptors for checked disposal.
    func requireAbsent() throws {
        guard status == .unopened else { throw Failure.invalidState }
        status = .observing
        do {
            guard supportURL.isFileURL, supportURL.path.hasPrefix("/"),
                  expectedSupport.inode != 0 else { throw Failure.invalidIdentity }
            let fd = Darwin.open(supportURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw Failure.systemCall }
            support = fd // Retain before the first throwing verification.
            try requireSupport()
            var named = stat()
            let result = Darwin.fstatat(fd, Self.eraseName, &named, AT_SYMLINK_NOFOLLOW)
            let lookupError = errno
            if result == 0 {
                guard named.st_mode & S_IFMT == S_IFDIR else { throw Failure.controlsPresent }
                let child = Darwin.openat(fd, Self.eraseName,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard child >= 0 else { throw Failure.systemCall }
                erase = child
                eraseSnapshot = EraseDirectorySnapshot(named)
                try requireErase()
                let duplicate = Darwin.fcntl(child, F_DUPFD_CLOEXEC, 0)
                guard duplicate >= 0 else { throw Failure.systemCall }
                directoryDuplicate = duplicate
                guard let opened = Darwin.fdopendir(duplicate) else { throw Failure.systemCall }
                stream = opened
                directoryDuplicate = nil // fdopendir now owns this exact descriptor.
                try requireEmpty()
                try requireErase()
                Darwin.rewinddir(opened)
                try requireEmpty()
                try requireErase()
            } else {
                guard lookupError == ENOENT else { throw Failure.systemCall }
                try requireRootAbsent()
            }
            try requireSupport()
            if erase != nil { try requireErase() } else { try requireRootAbsent() }
            try closeOwnedResources()
            status = .absentAndClosed
        } catch {
            if status != .closeUncertain { status = .refused }
            throw error
        }
    }

    /// Disposal only. A refused observation can never become successful later.
    /// No descriptor integer is retried after any close attempt, even EINTR.
    func closeAfterRefusal() throws {
        guard status == .refused else { throw Failure.invalidState }
        try closeOwnedResources()
        status = .refusedAndClosed
    }

    private func requireSupport() throws {
        guard let support else { throw Failure.invalidState }
        var held = stat(), named = stat()
        guard Darwin.fstat(support, &held) == 0,
              Darwin.lstat(supportURL.path, &named) == 0,
              held.st_mode & S_IFMT == S_IFDIR, named.st_mode & S_IFMT == S_IFDIR,
              held.st_dev == expectedSupport.device,
              held.st_ino == expectedSupport.inode,
              named.st_dev == held.st_dev, named.st_ino == held.st_ino else { throw Failure.invalidIdentity }
    }

    private func requireRootAbsent() throws {
        try requireSupport()
        guard let support else { throw Failure.invalidState }
        var named = stat()
        let result = Darwin.fstatat(support, Self.eraseName, &named, AT_SYMLINK_NOFOLLOW)
        let saved = errno
        guard result == -1, saved == ENOENT else { throw Failure.controlsPresent }
    }

    private func requireErase() throws {
        try requireSupport()
        guard let support, let erase, let expected = eraseSnapshot else {
            throw Failure.invalidState
        }
        var held = stat(), named = stat()
        guard Darwin.fstat(erase, &held) == 0,
              Darwin.fstatat(support, Self.eraseName, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_mode & S_IFMT == S_IFDIR, named.st_mode & S_IFMT == S_IFDIR,
              EraseDirectorySnapshot(held) == expected,
              EraseDirectorySnapshot(named) == expected else {
            throw Failure.invalidIdentity
        }
    }

    private func requireEmpty() throws {
        guard let stream else { throw Failure.invalidState }
        // A real empty directory has only dot entries. Bound even malformed input.
        for _ in 0..<3 {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                guard errno == 0 else { throw Failure.systemCall }
                return
            }
            guard let name = OwnedStorageDirectoryEntryNameV1.decode(entry) else { throw Failure.invalidIdentity }
            guard name == "." || name == ".." else { throw Failure.controlsPresent }
        }
        throw Failure.controlsPresent
    }

    private func closeOwnedResources() throws {
        if let value = stream {
            stream = nil
            if Darwin.closedir(value) != 0 { closeErrors.append(errno) }
        }
        for value in [directoryDuplicate, erase, support].compactMap({ $0 }) {
            // Clear every owner slot before closing; no retry can see the integer.
            if directoryDuplicate == value { directoryDuplicate = nil }
            if erase == value { erase = nil }
            if support == value { support = nil }
            if Darwin.close(value) != 0 { closeErrors.append(errno) }
        }
        guard closeErrors.isEmpty else {
            status = .closeUncertain
            throw Failure.closeUncertain
        }
    }
    // No deinit close: failures belong to the retained operation until explicit
    // checked disposal. Silent destructor cleanup cannot prove writer-return safety.
}
