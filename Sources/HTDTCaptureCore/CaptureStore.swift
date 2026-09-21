import Foundation

public enum CaptureStoreAdmissionError: Error, Sendable, Equatable {
    case invalidByteCount(Int)
    case itemLimitExceeded(maxItems: Int)
    case byteLimitExceeded(requested: Int, reserved: Int, maxBytes: Int)
    case unknownReservation
}

public struct CaptureStoreReservation: Hashable, Sendable {
    public let id: UUID
    public let bytes: Int

    public init(id: UUID = UUID(), bytes: Int) {
        self.id = id
        self.bytes = bytes
    }
}

public struct CaptureStoreBudgetSnapshot: Sendable, Equatable {
    public let reservedBytes: Int
    public let reservedItems: Int
    public let maxBytes: Int
    public let maxItems: Int
}

/// Bounded pending-write admission ledger (issue #147). Serialized by
/// a lock rather than the actor runtime so `release` can run
/// synchronously inside `defer` at every persistence entry point —
/// reservation release must be deterministic on success, failure, and
/// cancellation exits without an extra suspension.
public final class CaptureStoreAdmissionController: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private let maxItems: Int
    private var reservations: [UUID: Int] = [:]
    private var reservedBytes = 0

    public init(maxBytes: Int, maxItems: Int) {
        precondition(maxBytes > 0)
        precondition(maxItems > 0)
        self.maxBytes = maxBytes
        self.maxItems = maxItems
    }

    public func reserve(bytes: Int) throws -> CaptureStoreReservation {
        lock.lock()
        defer { lock.unlock() }
        guard bytes > 0 else {
            throw CaptureStoreAdmissionError.invalidByteCount(bytes)
        }
        guard reservations.count < maxItems else {
            throw CaptureStoreAdmissionError.itemLimitExceeded(maxItems: maxItems)
        }
        guard reservedBytes + bytes <= maxBytes else {
            throw CaptureStoreAdmissionError.byteLimitExceeded(
                requested: bytes,
                reserved: reservedBytes,
                maxBytes: maxBytes
            )
        }

        let reservation = CaptureStoreReservation(bytes: bytes)
        reservations[reservation.id] = bytes
        reservedBytes += bytes
        return reservation
    }

    public func release(_ reservation: CaptureStoreReservation) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let bytes = reservations.removeValue(forKey: reservation.id) else {
            throw CaptureStoreAdmissionError.unknownReservation
        }
        reservedBytes -= bytes
    }

    public func snapshot() -> CaptureStoreBudgetSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return CaptureStoreBudgetSnapshot(
            reservedBytes: reservedBytes,
            reservedItems: reservations.count,
            maxBytes: maxBytes,
            maxItems: maxItems
        )
    }
}

public enum CaptureStorePathError: Error, Sendable, Equatable {
    case empty
    case absolute
    case unsafeSegment(String)
    case backslash
}

public struct CaptureStorePath: Hashable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty else {
            throw CaptureStorePathError.empty
        }
        guard !rawValue.hasPrefix("/") else {
            throw CaptureStorePathError.absolute
        }
        guard !rawValue.contains("\\") else {
            throw CaptureStorePathError.backslash
        }

        let segments = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard !segments.isEmpty else {
            throw CaptureStorePathError.empty
        }
        for segment in segments {
            let value = String(segment)
            guard !value.isEmpty, value != ".", value != ".." else {
                throw CaptureStorePathError.unsafeSegment(value)
            }
        }
        description = rawValue
    }
}

public enum CaptureFileWriterError: Error, Sendable, Equatable {
    case alreadyExists(String)
    case batchRollbackFailed(String)
}

public struct CaptureFileWriteRequest: Sendable, Equatable {
    public let data: Data
    public let path: CaptureStorePath

    public init(data: Data, path: CaptureStorePath) {
        self.data = data
        self.path = path
    }
}

public actor AtomicCaptureFileWriter {
    public let rootDirectory: URL
    private let fileManager: FileManager

    /// Byte-exact comparison between a file on disk and `expected`,
    /// streamed through bounded chunks instead of materializing a
    /// second full-size copy of a large payload (issue #147).
    private func fileBytesEqual(
        _ url: URL,
        _ expected: Data
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        if let attributes = try? fileManager.attributesOfItem(
            atPath: url.path
        ),
            let size = (attributes[.size] as? NSNumber)?.intValue,
            size != expected.count
        {
            return false
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var offset = 0
        while offset < expected.count {
            let length = min(1 << 20, expected.count - offset)
            guard let chunk = try handle.read(upToCount: length),
                  chunk.count == length
            else {
                return false
            }
            guard
                chunk
                    == expected.subdata(
                        in: offset ..< (offset + length)
                    )
            else {
                return false
            }
            offset += length
        }
        // The file may be longer than `expected` even when the recorded
        // size attribute was unavailable; confirm end-of-file.
        guard (try handle.read(upToCount: 1))?.isEmpty ?? true else {
            return false
        }
        return true
    }

    public init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    public func write(_ data: Data, to path: CaptureStorePath) throws {
        let target = path.description
            .split(separator: "/")
            .reduce(rootDirectory) { url, component in
                url.appendingPathComponent(String(component), isDirectory: false)
            }

        if fileManager.fileExists(atPath: target.path) {
            throw CaptureFileWriterError.alreadyExists(path.description)
        }

        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let temporary = parent.appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            try data.write(to: temporary)
            try fileManager.moveItem(at: temporary, to: target)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
    public func writeBatchIfIdentical(
        _ requests: [CaptureFileWriteRequest]
    ) throws {
        var uniqueByPath: [String: Data] = [:]
        for request in requests {
            if let existing = uniqueByPath[request.path.description] {
                guard existing == request.data else {
                    throw CaptureFileWriterError.alreadyExists(
                        request.path.description
                    )
                }
                continue
            }
            uniqueByPath[request.path.description] = request.data
        }

        var created: [(url: URL, path: String)] = []
        do {
            for request in requests {
                let target = request.path.description
                    .split(separator: "/")
                    .reduce(rootDirectory) { url, component in
                        url.appendingPathComponent(
                            String(component),
                            isDirectory: false
                        )
                    }

                if fileManager.fileExists(atPath: target.path) {
                    guard try fileBytesEqual(target, request.data)
                    else {
                        throw CaptureFileWriterError.alreadyExists(
                            request.path.description
                        )
                    }
                    continue
                }

                let parent = target.deletingLastPathComponent()
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )

                let temporary = parent.appendingPathComponent(
                    ".tmp-\(UUID().uuidString)"
                )
                do {
                    try request.data.write(to: temporary)
                    try fileManager.moveItem(
                        at: temporary,
                        to: target
                    )
                } catch {
                    try? fileManager.removeItem(at: temporary)

                    // A writer outside this actor may have won the path race.
                    // Accept it only when it produced the exact same bytes.
                    if fileManager.fileExists(atPath: target.path),
                       (try? fileBytesEqual(target, request.data))
                        == true
                    {
                        continue
                    }
                    throw error
                }

                created.append(
                    (target, request.path.description)
                )
            }
        } catch {
            var rollbackFailure: String?
            for item in created.reversed() {
                guard fileManager.fileExists(atPath: item.url.path) else {
                    continue
                }
                do {
                    try fileManager.removeItem(at: item.url)
                } catch {
                    if rollbackFailure == nil {
                        rollbackFailure = item.path
                    }
                }
            }
            if let rollbackFailure {
                throw CaptureFileWriterError.batchRollbackFailed(
                    rollbackFailure
                )
            }
            throw error
        }
    }

    /// Atomically replaces the target bytes for every request, restoring
    /// the exact prior bytes if any replacement fails partway through
    /// (issue #163). Each file is staged through a same-directory
    /// temporary and swapped atomically, so a reader never observes a
    /// truncated payload; a failed later request restores each earlier
    /// target to its original bytes, or removes a path the batch created.
    public func writeBatchReplacing(
        _ requests: [CaptureFileWriteRequest]
    ) throws {
        var order: [String] = []
        var uniqueByPath: [String: Data] = [:]
        for request in requests {
            let key = request.path.description
            if let existing = uniqueByPath[key] {
                guard existing == request.data else {
                    throw CaptureFileWriterError.alreadyExists(key)
                }
                continue
            }
            uniqueByPath[key] = request.data
            order.append(key)
        }

        struct Applied {
            let target: URL
            let path: String
            /// Original bytes when the path existed before the batch;
            /// nil marks a path created by this batch whose rollback is
            /// removal.
            let originalData: Data?
        }
        var applied: [Applied] = []
        do {
            for key in order {
                guard let data = uniqueByPath[key] else { continue }
                let target = key
                    .split(separator: "/")
                    .reduce(rootDirectory) { url, component in
                        url.appendingPathComponent(
                            String(component),
                            isDirectory: false
                        )
                    }
                let parent = target.deletingLastPathComponent()
                try fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )
                let temporary = parent.appendingPathComponent(
                    ".tmp-\(UUID().uuidString)"
                )
                let originalData: Data?
                do {
                    try data.write(to: temporary)
                    if fileManager.fileExists(atPath: target.path) {
                        originalData = try Data(contentsOf: target)
                        _ = try fileManager.replaceItemAt(
                            target,
                            withItemAt: temporary
                        )
                    } else {
                        originalData = nil
                        try fileManager.moveItem(
                            at: temporary,
                            to: target
                        )
                    }
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    throw error
                }
                applied.append(
                    Applied(
                        target: target,
                        path: key,
                        originalData: originalData
                    )
                )
            }
        } catch {
            var rollbackFailure: String?
            for item in applied.reversed() {
                do {
                    if let original = item.originalData {
                        let restoreTemporary = item.target
                            .deletingLastPathComponent()
                            .appendingPathComponent(
                                ".tmp-\(UUID().uuidString)"
                            )
                        try original.write(to: restoreTemporary)
                        _ = try fileManager.replaceItemAt(
                            item.target,
                            withItemAt: restoreTemporary
                        )
                    } else if fileManager.fileExists(
                        atPath: item.target.path
                    ) {
                        try fileManager.removeItem(at: item.target)
                    }
                } catch {
                    if rollbackFailure == nil {
                        rollbackFailure = item.path
                    }
                }
            }
            if let rollbackFailure {
                throw CaptureFileWriterError.batchRollbackFailed(
                    rollbackFailure
                )
            }
            throw error
        }
    }

    public func writeIfIdentical(
        _ data: Data,
        to path: CaptureStorePath
    ) throws {
        let target = path.description
            .split(separator: "/")
            .reduce(rootDirectory) { url, component in
                url.appendingPathComponent(
                    String(component),
                    isDirectory: false
                )
            }

        if fileManager.fileExists(atPath: target.path) {
            guard try fileBytesEqual(target, data) else {
                throw CaptureFileWriterError
                    .alreadyExists(path.description)
            }
            return
        }

        let parent = target.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let temporary = parent.appendingPathComponent(
            ".tmp-\(UUID().uuidString)"
        )
        do {
            try data.write(to: temporary)
            try fileManager.moveItem(
                at: temporary,
                to: target
            )
        } catch {
            try? fileManager.removeItem(at: temporary)

            // A same-payload replay can reach this actor after another
            // caller won the atomic move. Accept only byte-identical
            // evidence; never overwrite or accept a conflicting payload.
            if fileManager.fileExists(atPath: target.path),
               (try? fileBytesEqual(target, data)) == true
            {
                return
            }
            throw error
        }
    }

    public func removeBatchIfIdentical(
        _ requests: [CaptureFileWriteRequest]
    ) throws {
        var ordered: [CaptureFileWriteRequest] = []
        var uniqueByPath: [String: Data] = [:]

        for request in requests {
            if let existing =
                uniqueByPath[request.path.description]
            {
                guard existing == request.data else {
                    throw CaptureFileWriterError.alreadyExists(
                        request.path.description
                    )
                }
                continue
            }
            uniqueByPath[request.path.description] =
                request.data
            ordered.append(request)
        }

        guard !ordered.isEmpty else {
            return
        }

        let targets = ordered.map { request in
            (
                request: request,
                url:
                    request.path.description
                        .split(separator: "/")
                        .reduce(rootDirectory) {
                            url,
                            component in
                            url.appendingPathComponent(
                                String(component),
                                isDirectory: false
                            )
                        }
            )
        }

        let present = targets.filter {
            fileManager.fileExists(atPath: $0.url.path)
        }

        // Exact concurrent replay after a prior successful rollback is
        // harmless. A partial set is not: it indicates an already-corrupt
        // transaction boundary and must fail closed.
        if present.isEmpty {
            return
        }
        guard present.count == targets.count else {
            let missing = targets.first {
                !fileManager.fileExists(
                    atPath: $0.url.path
                )
            }
            throw CaptureFileWriterError.batchRollbackFailed(
                missing?.request.path.description
                    ?? "unknown"
            )
        }

        for item in targets {
            guard try fileBytesEqual(
                item.url,
                item.request.data
            ) else {
                throw CaptureFileWriterError.alreadyExists(
                    item.request.path.description
                )
            }
        }

        let quarantineParent =
            rootDirectory.deletingLastPathComponent()
        let quarantine = quarantineParent
            .appendingPathComponent(
                ".rollback-"
                    + UUID().uuidString.lowercased(),
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: quarantine,
            withIntermediateDirectories: false
        )

        var moved: [
            (
                original: URL,
                quarantine: URL,
                path: String
            )
        ] = []

        do {
            for (index, item) in targets.enumerated() {
                let staged = quarantine
                    .appendingPathComponent(
                        String(index),
                        isDirectory: false
                    )
                try fileManager.moveItem(
                    at: item.url,
                    to: staged
                )
                moved.append(
                    (
                        original: item.url,
                        quarantine: staged,
                        path: item.request.path.description
                    )
                )
            }
        } catch {
            var restoreFailure: String?
            for item in moved.reversed() {
                do {
                    try fileManager.moveItem(
                        at: item.quarantine,
                        to: item.original
                    )
                } catch {
                    if restoreFailure == nil {
                        restoreFailure = item.path
                    }
                }
            }
            try? fileManager.removeItem(at: quarantine)

            if let restoreFailure {
                throw CaptureFileWriterError
                    .batchRollbackFailed(restoreFailure)
            }
            throw error
        }

        // The bundle root is already atomically clear of every owned path.
        // Quarantine cleanup is outside the bundle authority; a best-effort
        // delete avoids reintroducing any removed canonical file if cleanup
        // itself fails.
        try? fileManager.removeItem(at: quarantine)
    }

    public func removeIfIdentical(
        _ data: Data,
        at path: CaptureStorePath
    ) throws -> Bool {
        let target = path.description
            .split(separator: "/")
            .reduce(rootDirectory) { url, component in
                url.appendingPathComponent(
                    String(component),
                    isDirectory: false
                )
            }

        guard fileManager.fileExists(atPath: target.path) else {
            return true
        }

        guard try fileBytesEqual(target, data) else {
            return false
        }

        try fileManager.removeItem(at: target)
        return true
    }

    public func removeIfPresent(_ path: CaptureStorePath) throws {
        let target = path.description
            .split(separator: "/")
            .reduce(rootDirectory) { url, component in
                url.appendingPathComponent(
                    String(component),
                    isDirectory: false
                )
            }

        guard fileManager.fileExists(atPath: target.path) else {
            return
        }
        try fileManager.removeItem(at: target)
    }

    /// Actor fence used by the working-set finalization seal to drain
    /// previously enqueued write/remove work. Awaiting this function
    /// returns only after every request submitted to this actor before
    /// it has completed, giving the sealing caller a deterministic
    /// quiescence point without touching the filesystem itself
    /// (issue #180).
    public func barrier() async {}

    // NOTE: the finalization seal drains in-flight mutations through a
    // continuation resume on the store actor (`mutationDrainers`), not
    // through this fence — a fence-poll loop can starve queued writes
    // under the actor executor's non-FIFO job scheduling.

}
