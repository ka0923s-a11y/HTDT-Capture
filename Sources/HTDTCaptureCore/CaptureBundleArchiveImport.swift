import Foundation

public struct CaptureBundleArchiveImportResult:
    Sendable,
    Equatable
{
    public let directoryURL: URL
    public let bundleDigest: EvidenceSHA256
    public let payloadCount: Int
    public let entryCount: Int

    public init(
        directoryURL: URL,
        bundleDigest: EvidenceSHA256,
        payloadCount: Int,
        entryCount: Int
    ) {
        self.directoryURL = directoryURL
        self.bundleDigest = bundleDigest
        self.payloadCount = payloadCount
        self.entryCount = entryCount
    }
}

private struct StoredZIPImportEntry {
    let path: String
    let size: UInt32
    let dataOffset: UInt64
}

public enum StoredCaptureBundleArchiveImporter {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let storeMethod: UInt16 = 0
    private static let chunkBytes = 1024 * 1024

    public static func importArchive(
        archive: URL,
        destination: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> CaptureBundleArchiveImportResult {
        guard archive.pathExtension == "htdtcapture" else {
            throw CaptureBundleArchiveError
                .invalidDestinationExtension
        }
        guard !FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            throw CaptureBundleArchiveError
                .destinationAlreadyExists
        }

        let archiveReport =
            try StoredCaptureBundleArchiveValidator.validate(
                archive: archive,
                limits: limits
            )
        let entries = try inspectLocalEntries(
            archive: archive,
            limits: limits
        )

        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let staging = parent.appendingPathComponent(
            "."
                + destination.lastPathComponent
                + ".import-"
                + UUID().uuidString.lowercased(),
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: false
        )
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }

        guard let input = try? FileHandle(
            forReadingFrom: archive
        ) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(archive.path)
        }
        defer {
            try? input.close()
        }

        for entry in entries {
            let target = try extractionURL(
                root: staging,
                logicalPath: entry.path
            )
            let targetParent =
                target.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: targetParent,
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(
                atPath: target.path
            ) else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }
            guard fileManager.createFile(
                atPath: target.path,
                contents: nil
            ) else {
                throw CaptureBundleArchiveError
                    .fileOpenFailed(target.path)
            }

            guard let output = try? FileHandle(
                forWritingTo: target
            ) else {
                throw CaptureBundleArchiveError
                    .fileOpenFailed(target.path)
            }
            do {
                try copySegment(
                    input: input,
                    offset: entry.dataOffset,
                    count: UInt64(entry.size),
                    output: output
                )
                try output.synchronize()
                try output.close()
            } catch {
                try? output.close()
                throw error
            }
        }

        let extractedReport =
            try BundleDirectoryValidator.validate(
                root: staging,
                limits: limits
            )
        guard extractedReport.bundleDigest
                == archiveReport.bundleDigest
        else {
            throw CaptureBundleArchiveError
                .archiveLogicalDigestMismatch
        }

        do {
            try fileManager.moveItem(
                at: staging,
                to: destination
            )
        } catch {
            throw CaptureBundleArchiveError
                .atomicPublishFailed
        }

        return CaptureBundleArchiveImportResult(
            directoryURL: destination,
            bundleDigest: extractedReport.bundleDigest,
            payloadCount: extractedReport.payloadCount,
            entryCount: entries.count
        )
    }

    private static func inspectLocalEntries(
        archive: URL,
        limits: BundleFilesystemLimits
    ) throws -> [StoredZIPImportEntry] {
        guard let handle = try? FileHandle(
            forReadingFrom: archive
        ) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(archive.path)
        }
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        var cursor: UInt64 = 0
        var entries: [StoredZIPImportEntry] = []
        var collisionMap: [String: String] = [:]
        var totalBytes: Int64 = 0

        while cursor < fileSize {
            try handle.seek(toOffset: cursor)
            let signature: UInt32 = try handle.importReadLE()
            if signature == centralSignature {
                break
            }
            guard signature == localSignature else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }

            let version: UInt16 = try handle.importReadLE()
            let flags: UInt16 = try handle.importReadLE()
            let method: UInt16 = try handle.importReadLE()
            _ = try handle.importReadLE() as UInt16
            _ = try handle.importReadLE() as UInt16
            _ = try handle.importReadLE() as UInt32
            let compressedSize: UInt32 =
                try handle.importReadLE()
            let size: UInt32 = try handle.importReadLE()
            let nameLength: UInt16 =
                try handle.importReadLE()
            let extraLength: UInt16 =
                try handle.importReadLE()

            guard version == 20,
                  method == storeMethod,
                  compressedSize == size,
                  extraLength == 0
            else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }

            let nameData = try handle.importReadExact(
                count: Int(nameLength)
            )
            guard let path = String(
                data: nameData,
                encoding: .utf8
            ) else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }
            guard CaptureArchiveEntryFlags.isValid(
                flags,
                nameBytes: nameData
            ) else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }
            do {
                try BundleLogicalPath.validate(path)
            } catch {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }

            let collisionKey =
                BundleLogicalPath.collisionKey(path)
            guard collisionMap[collisionKey] == nil else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }
            collisionMap[collisionKey] = path

            if Int64(size) > limits.maxFileBytes {
                throw BundleFilesystemError
                    .fileSizeLimitExceeded(path)
            }
            totalBytes += Int64(size)
            if totalBytes > limits.maxTotalBytes {
                throw BundleFilesystemError
                    .totalSizeLimitExceeded
            }
            if entries.count + 1 > limits.maxEntries {
                throw BundleFilesystemError
                    .fileCountLimitExceeded
            }

            let dataOffset =
                cursor
                + 30
                + UInt64(nameLength)
                + UInt64(extraLength)
            guard dataOffset + UInt64(size) <= fileSize else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }

            entries.append(
                StoredZIPImportEntry(
                    path: path,
                    size: size,
                    dataOffset: dataOffset
                )
            )
            cursor = dataOffset + UInt64(size)
        }

        guard !entries.isEmpty,
              entries.map(\.path)
                == entries.map(\.path).sorted(
                    by: BundleLogicalPath.utf8Less
                )
        else {
            throw CaptureBundleArchiveError
                .archiveMalformed
        }
        return entries
    }

    private static func extractionURL(
        root: URL,
        logicalPath: String
    ) throws -> URL {
        do {
            try BundleLogicalPath.validate(logicalPath)
        } catch {
            throw CaptureBundleArchiveError
                .archiveMalformed
        }

        let rootComponents =
            root.standardizedFileURL.pathComponents
        let target = root.appendingPathComponent(
            logicalPath,
            isDirectory: false
        ).standardizedFileURL
        guard target.pathComponents.starts(
            with: rootComponents
        ) else {
            throw CaptureBundleArchiveError
                .archiveMalformed
        }
        return target
    }

    private static func copySegment(
        input: FileHandle,
        offset: UInt64,
        count: UInt64,
        output: FileHandle
    ) throws {
        try input.seek(toOffset: offset)
        var remaining = count
        while remaining > 0 {
            let request = Int(
                min(UInt64(chunkBytes), remaining)
            )
            let data = try input.importReadExact(
                count: request
            )
            try output.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
    }
}

private extension FileHandle {
    func importReadExact(count: Int) throws -> Data {
        guard count >= 0 else {
            throw CaptureBundleArchiveError
                .archiveMalformed
        }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let next = try read(
                upToCount: count - result.count
            ) ?? Data()
            guard !next.isEmpty else {
                throw CaptureBundleArchiveError
                    .archiveMalformed
            }
            result.append(next)
        }
        return result
    }

    func importReadLE<T: FixedWidthInteger>()
        throws -> T
    {
        let data = try importReadExact(
            count: MemoryLayout<T>.size
        )
        return data.withUnsafeBytes {
            T(littleEndian: $0.loadUnaligned(as: T.self))
        }
    }
}
