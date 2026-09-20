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

public actor CaptureStoreAdmissionController {
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
        guard let bytes = reservations.removeValue(forKey: reservation.id) else {
            throw CaptureStoreAdmissionError.unknownReservation
        }
        reservedBytes -= bytes
    }

    public func snapshot() -> CaptureStoreBudgetSnapshot {
        CaptureStoreBudgetSnapshot(
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
                    let existing = try Data(contentsOf: target)
                    guard existing == request.data else {
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
                       let existing = try? Data(contentsOf: target),
                       existing == request.data
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
            let existing = try Data(contentsOf: target)
            guard existing == data else {
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
               let existing = try? Data(contentsOf: target),
               existing == data
            {
                return
            }
            throw error
        }
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

        let existing = try Data(contentsOf: target)
        guard existing == data else {
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

}
