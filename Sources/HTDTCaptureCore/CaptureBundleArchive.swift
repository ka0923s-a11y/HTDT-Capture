import CryptoKit
import Foundation

public enum CaptureBundleArchiveError:
    Error,
    Sendable,
    Equatable
{
    case invalidDestinationExtension
    case destinationAlreadyExists
    case archiveTooLargeForClassicZIP
    case filenameTooLong(String)
    case fileOpenFailed(String)
    case archiveMalformed
    case archiveEntryMismatch
    case archiveLogicalDigestMismatch
    case atomicPublishFailed
}

public struct CaptureBundleArchiveResult:
    Sendable,
    Equatable
{
    public let archiveURL: URL
    public let bundleDigest: EvidenceSHA256
    public let payloadCount: Int
    public let entryCount: Int

    public init(
        archiveURL: URL,
        bundleDigest: EvidenceSHA256,
        payloadCount: Int,
        entryCount: Int
    ) {
        self.archiveURL = archiveURL
        self.bundleDigest = bundleDigest
        self.payloadCount = payloadCount
        self.entryCount = entryCount
    }
}

private struct StoredZIPSourceEntry {
    let path: String
    let url: URL
    let size: UInt32
    let crc32: UInt32
    let localOffset: UInt32
}

private struct StoredZIPLocalEntry {
    let path: String
    let crc32: UInt32
    let size: UInt32
    let localOffset: UInt32
    let dataOffset: UInt64
}

public enum CaptureBundleArchiveExporter {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50
    private static let utf8Flag: UInt16 = 0x0800
    private static let storeMethod: UInt16 = 0
    private static let version20: UInt16 = 20
    private static let fixedDOSTime: UInt16 = 0
    private static let fixedDOSDate: UInt16 = 33
    private static let chunkBytes = 1024 * 1024

    public static func export(
        finalizedDirectory: URL,
        destination: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> CaptureBundleArchiveResult {
        guard destination.pathExtension == "htdtcapture" else {
            throw CaptureBundleArchiveError
                .invalidDestinationExtension
        }
        guard !FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            throw CaptureBundleArchiveError
                .destinationAlreadyExists
        }

        let sourceReport = try BundleDirectoryValidator.validate(
            root: finalizedDirectory,
            limits: limits
        )
        let files = try BundleDirectoryScanner.scan(
            root: finalizedDirectory,
            limits: limits
        )

        guard files.count <= Int(UInt16.max) else {
            throw CaptureBundleArchiveError
                .archiveTooLargeForClassicZIP
        }

        var entries: [StoredZIPSourceEntry] = []
        entries.reserveCapacity(files.count)
        var nextOffset: UInt64 = 0

        for file in files {
            let nameBytes = Data(file.path.utf8)
            guard nameBytes.count <= Int(UInt16.max) else {
                throw CaptureBundleArchiveError
                    .filenameTooLong(file.path)
            }
            guard file.bytes >= 0,
                  UInt64(file.bytes) <= UInt64(UInt32.max)
            else {
                throw CaptureBundleArchiveError
                    .archiveTooLargeForClassicZIP
            }

            let headerBytes =
                UInt64(30 + nameBytes.count)
            let required =
                nextOffset
                + headerBytes
                + UInt64(file.bytes)
            guard nextOffset <= UInt64(UInt32.max),
                  required <= UInt64(UInt32.max)
            else {
                throw CaptureBundleArchiveError
                    .archiveTooLargeForClassicZIP
            }

            entries.append(
                StoredZIPSourceEntry(
                    path: file.path,
                    url: file.url,
                    size: UInt32(file.bytes),
                    crc32: try ZIPCRC32.file(url: file.url),
                    localOffset: UInt32(nextOffset)
                )
            )
            nextOffset = required
        }

        let centralOffset = nextOffset
        var centralSize: UInt64 = 0
        for entry in entries {
            let nameCount = Data(entry.path.utf8).count
            centralSize += UInt64(46 + nameCount)
        }
        guard centralOffset <= UInt64(UInt32.max),
              centralSize <= UInt64(UInt32.max),
              centralOffset + centralSize + 22
                <= UInt64(UInt32.max)
        else {
            throw CaptureBundleArchiveError
                .archiveTooLargeForClassicZIP
        }

        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        let temp = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).tmp-\(UUID().uuidString.lowercased())"
        )
        defer {
            if FileManager.default.fileExists(atPath: temp.path) {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        guard FileManager.default.createFile(
            atPath: temp.path,
            contents: nil
        ) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(temp.path)
        }

        guard let output = try? FileHandle(forWritingTo: temp) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(temp.path)
        }
        defer {
            try? output.close()
        }

        for entry in entries {
            let name = Data(entry.path.utf8)
            var header = Data()
            header.appendLE(localSignature)
            header.appendLE(version20)
            header.appendLE(utf8Flag)
            header.appendLE(storeMethod)
            header.appendLE(fixedDOSTime)
            header.appendLE(fixedDOSDate)
            header.appendLE(entry.crc32)
            header.appendLE(entry.size)
            header.appendLE(entry.size)
            header.appendLE(UInt16(name.count))
            header.appendLE(UInt16(0))
            header.append(name)
            try output.write(contentsOf: header)
            try copyFile(entry.url, to: output)
        }

        for entry in entries {
            let name = Data(entry.path.utf8)
            var central = Data()
            central.appendLE(centralSignature)
            central.appendLE(version20)
            central.appendLE(version20)
            central.appendLE(utf8Flag)
            central.appendLE(storeMethod)
            central.appendLE(fixedDOSTime)
            central.appendLE(fixedDOSDate)
            central.appendLE(entry.crc32)
            central.appendLE(entry.size)
            central.appendLE(entry.size)
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(entry.localOffset)
            central.append(name)
            try output.write(contentsOf: central)
        }

        var end = Data()
        end.appendLE(endSignature)
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt32(centralSize))
        end.appendLE(UInt32(centralOffset))
        end.appendLE(UInt16(0))
        try output.write(contentsOf: end)
        try output.synchronize()

        let archiveReport =
            try StoredCaptureBundleArchiveValidator.validate(
                archive: temp,
                limits: limits
            )
        guard archiveReport.bundleDigest
                == sourceReport.bundleDigest
        else {
            throw CaptureBundleArchiveError
                .archiveLogicalDigestMismatch
        }

        do {
            try FileManager.default.moveItem(
                at: temp,
                to: destination
            )
        } catch {
            throw CaptureBundleArchiveError
                .atomicPublishFailed
        }

        return CaptureBundleArchiveResult(
            archiveURL: destination,
            bundleDigest: archiveReport.bundleDigest,
            payloadCount: archiveReport.payloadCount,
            entryCount: files.count
        )
    }

    private static func copyFile(
        _ source: URL,
        to output: FileHandle
    ) throws {
        guard let input = try? FileHandle(forReadingFrom: source) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(source.path)
        }
        defer {
            try? input.close()
        }

        while true {
            let chunk =
                try input.read(upToCount: chunkBytes)
                ?? Data()
            if chunk.isEmpty {
                break
            }
            try output.write(contentsOf: chunk)
        }
    }
}

public enum StoredCaptureBundleArchiveValidator {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50
    private static let utf8Flag: UInt16 = 0x0800
    private static let storeMethod: UInt16 = 0
    private static let chunkBytes = 1024 * 1024

    public static func validate(
        archive: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> BundleValidationReport {
        guard let handle = try? FileHandle(forReadingFrom: archive) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(archive.path)
        }
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        var locals: [StoredZIPLocalEntry] = []
        var localByOffset: [UInt32: StoredZIPLocalEntry] = [:]
        var collisionMap: [String: String] = [:]
        var totalBytes: Int64 = 0
        var cursor: UInt64 = 0
        var centralOffset: UInt64?

        while cursor < fileSize {
            try handle.seek(toOffset: cursor)
            let signature: UInt32 = try handle.readLE()
            if signature == centralSignature {
                centralOffset = cursor
                break
            }
            guard signature == localSignature else {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            let version: UInt16 = try handle.readLE()
            let flags: UInt16 = try handle.readLE()
            let method: UInt16 = try handle.readLE()
            _ = try handle.readLE() as UInt16
            _ = try handle.readLE() as UInt16
            let crc: UInt32 = try handle.readLE()
            let compressedSize: UInt32 = try handle.readLE()
            let size: UInt32 = try handle.readLE()
            let nameLength: UInt16 = try handle.readLE()
            let extraLength: UInt16 = try handle.readLE()

            guard version == 20,
                  flags == utf8Flag,
                  method == storeMethod,
                  compressedSize == size,
                  extraLength == 0
            else {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            let nameData = try handle.readExact(
                count: Int(nameLength)
            )
            guard let path = String(
                data: nameData,
                encoding: .utf8
            ) else {
                throw CaptureBundleArchiveError.archiveMalformed
            }
            do {
                try BundleLogicalPath.validate(path)
            } catch {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            let collisionKey =
                BundleLogicalPath.collisionKey(path)
            if collisionMap[collisionKey] != nil {
                throw CaptureBundleArchiveError.archiveMalformed
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
            if locals.count + 1 > limits.maxEntries {
                throw BundleFilesystemError
                    .fileCountLimitExceeded
            }

            let dataOffset =
                cursor + 30 + UInt64(nameLength)
            guard dataOffset + UInt64(size) <= fileSize else {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            let actualCRC = try ZIPCRC32.segment(
                handle: handle,
                offset: dataOffset,
                count: UInt64(size)
            )
            guard actualCRC == crc else {
                throw CaptureBundleArchiveError.archiveEntryMismatch
            }

            guard cursor <= UInt64(UInt32.max) else {
                throw CaptureBundleArchiveError
                    .archiveTooLargeForClassicZIP
            }
            let localOffset = UInt32(cursor)
            let local = StoredZIPLocalEntry(
                path: path,
                crc32: crc,
                size: size,
                localOffset: localOffset,
                dataOffset: dataOffset
            )
            locals.append(local)
            if localByOffset.updateValue(local, forKey: localOffset)
                != nil
            {
                throw CaptureBundleArchiveError.archiveMalformed
            }
            cursor = dataOffset + UInt64(size)
        }

        guard let centralOffset else {
            throw CaptureBundleArchiveError.archiveMalformed
        }
        guard locals.map(\.path) == locals
            .map(\.path)
            .sorted(by: BundleLogicalPath.utf8Less)
        else {
            throw CaptureBundleArchiveError.archiveMalformed
        }
        let localByPath = Dictionary(
            uniqueKeysWithValues: locals.map {
                ($0.path, $0)
            }
        )

        var centralEntries: [StoredZIPLocalEntry] = []
        try handle.seek(toOffset: centralOffset)
        for _ in locals.indices {
            let signature: UInt32 = try handle.readLE()
            guard signature == centralSignature else {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            _ = try handle.readLE() as UInt16
            let version: UInt16 = try handle.readLE()
            let flags: UInt16 = try handle.readLE()
            let method: UInt16 = try handle.readLE()
            _ = try handle.readLE() as UInt16
            _ = try handle.readLE() as UInt16
            let crc: UInt32 = try handle.readLE()
            let compressedSize: UInt32 = try handle.readLE()
            let size: UInt32 = try handle.readLE()
            let nameLength: UInt16 = try handle.readLE()
            let extraLength: UInt16 = try handle.readLE()
            let commentLength: UInt16 = try handle.readLE()
            let diskStart: UInt16 = try handle.readLE()
            _ = try handle.readLE() as UInt16
            _ = try handle.readLE() as UInt32
            let localOffset: UInt32 = try handle.readLE()

            guard version == 20,
                  flags == utf8Flag,
                  method == storeMethod,
                  compressedSize == size,
                  extraLength == 0,
                  commentLength == 0,
                  diskStart == 0
            else {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            let nameData = try handle.readExact(
                count: Int(nameLength)
            )
            guard let path = String(
                data: nameData,
                encoding: .utf8
            ) else {
                throw CaptureBundleArchiveError.archiveMalformed
            }

            guard let local = localByOffset[localOffset],
                  local.path == path,
                  local.crc32 == crc,
                  local.size == size
            else {
                throw CaptureBundleArchiveError.archiveEntryMismatch
            }
            centralEntries.append(local)
        }

        let endOffset = try handle.offset()
        let endSignature: UInt32 = try handle.readLE()
        guard endSignature == self.endSignature else {
            throw CaptureBundleArchiveError.archiveMalformed
        }
        let disk: UInt16 = try handle.readLE()
        let centralDisk: UInt16 = try handle.readLE()
        let entriesOnDisk: UInt16 = try handle.readLE()
        let entryCount: UInt16 = try handle.readLE()
        let centralSize: UInt32 = try handle.readLE()
        let declaredCentralOffset: UInt32 = try handle.readLE()
        let commentLength: UInt16 = try handle.readLE()

        guard centralOffset <= UInt64(UInt32.max) else {
            throw CaptureBundleArchiveError
                .archiveTooLargeForClassicZIP
        }
        guard disk == 0,
              centralDisk == 0,
              entriesOnDisk == UInt16(locals.count),
              entryCount == UInt16(locals.count),
              declaredCentralOffset == UInt32(centralOffset),
              UInt64(centralSize) == endOffset - centralOffset,
              commentLength == 0,
              try handle.offset() == fileSize,
              Set(centralEntries.map(\.path))
                == Set(locals.map(\.path))
        else {
            throw CaptureBundleArchiveError.archiveMalformed
        }

        guard let manifestEntry = localByPath["manifest.json"]
        else {
            throw BundleDirectoryValidationError.manifestMissing
        }
        let manifestData = try readSegment(
            handle: handle,
            offset: manifestEntry.dataOffset,
            count: UInt64(manifestEntry.size)
        )
        let manifest: BundleManifest
        do {
            manifest = try JSONDecoder().decode(
                BundleManifest.self,
                from: manifestData
            )
        } catch {
            throw BundleDirectoryValidationError
                .manifestDecodeFailed
        }
        let canonical = try manifest.canonicalBytes()
        guard canonical == manifestData else {
            throw BundleDirectoryValidationError
                .manifestNotCanonical
        }

        var declaredByPath: [String: BundleFileEntry] = [:]
        for entry in manifest.files {
            do {
                try BundleLogicalPath.validate(entry.path)
            } catch {
                throw BundleDirectoryValidationError
                    .invalidManifestEntry(entry.path)
            }
            guard entry.bytes >= 0,
                  !entry.mediaType.isEmpty,
                  !entry.producer.isEmpty,
                  entry.sourceRefs?.allSatisfy({
                      !$0.isEmpty
                  }) ?? true,
                  entry.sourceRefs.map({
                      Set($0).count == $0.count
                  }) ?? true,
                  declaredByPath[entry.path] == nil
            else {
                throw BundleDirectoryValidationError
                    .invalidManifestEntry(entry.path)
            }
            declaredByPath[entry.path] = entry
        }
        let actualPayloadPaths =
            Set(localByPath.keys)
                .subtracting(["manifest.json"])
        let declaredPaths = Set(declaredByPath.keys)

        guard actualPayloadPaths == declaredPaths else {
            throw BundleDirectoryValidationError
                .declaredPayloadSetMismatch(
                    missing: declaredPaths
                        .subtracting(actualPayloadPaths)
                        .sorted(by: BundleLogicalPath.utf8Less),
                    undeclared: actualPayloadPaths
                        .subtracting(declaredPaths)
                        .sorted(by: BundleLogicalPath.utf8Less)
                )
        }

        for path in declaredPaths.sorted(
            by: BundleLogicalPath.utf8Less
        ) {
            guard let entry = declaredByPath[path],
                  let local = localByPath[path]
            else {
                throw CaptureBundleArchiveError
                    .archiveEntryMismatch
            }
            guard UInt64(entry.bytes) == UInt64(local.size) else {
                throw BundleDirectoryValidationError
                    .byteLengthMismatch(
                        path: path,
                        expected: entry.bytes,
                        actual: Int64(local.size)
                    )
            }

            let actualHash = try segmentSHA256(
                handle: handle,
                offset: local.dataOffset,
                count: UInt64(local.size)
            )
            guard actualHash == entry.sha256 else {
                throw BundleDirectoryValidationError.hashMismatch(
                    path: path,
                    expected: entry.sha256.description,
                    actual: actualHash.description
                )
            }
        }

        return BundleValidationReport(
            manifest: manifest,
            bundleDigest: EvidenceIntegrity.sha256(
                of: manifestData
            ),
            payloadCount: manifest.files.count
        )
    }

    private static func readSegment(
        handle: FileHandle,
        offset: UInt64,
        count: UInt64
    ) throws -> Data {
        guard count <= UInt64(Int.max) else {
            throw CaptureBundleArchiveError.archiveMalformed
        }
        try handle.seek(toOffset: offset)
        return try handle.readExact(count: Int(count))
    }

    private static func segmentSHA256(
        handle: FileHandle,
        offset: UInt64,
        count: UInt64
    ) throws -> EvidenceSHA256 {
        try handle.seek(toOffset: offset)
        var remaining = count
        var hasher = SHA256()

        while remaining > 0 {
            let request = Int(
                min(UInt64(chunkBytes), remaining)
            )
            let data = try handle.readExact(count: request)
            hasher.update(data: data)
            remaining -= UInt64(data.count)
        }

        let digest = hasher.finalize()
        let hex = digest.map {
            String(format: "%02x", $0)
        }.joined()
        return try EvidenceSHA256(hex)
    }
}

private enum ZIPCRC32 {
    private static let table: [UInt32] = (0..<256).map {
        index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0
                ? 0xedb88320 ^ (value >> 1)
                : value >> 1
        }
        return value
    }

    static func file(
        url: URL,
        chunkBytes: Int = 1024 * 1024
    ) throws -> UInt32 {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CaptureBundleArchiveError
                .fileOpenFailed(url.path)
        }
        defer {
            try? handle.close()
        }

        var crc = UInt32.max
        while true {
            let data =
                try handle.read(upToCount: chunkBytes)
                ?? Data()
            if data.isEmpty {
                break
            }
            crc = update(crc, data)
        }
        return crc ^ UInt32.max
    }

    static func segment(
        handle: FileHandle,
        offset: UInt64,
        count: UInt64
    ) throws -> UInt32 {
        try handle.seek(toOffset: offset)
        var remaining = count
        var crc = UInt32.max

        while remaining > 0 {
            let request = Int(
                min(UInt64(1024 * 1024), remaining)
            )
            let data = try handle.readExact(count: request)
            crc = update(crc, data)
            remaining -= UInt64(data.count)
        }

        return crc ^ UInt32.max
    }

    private static func update(
        _ initial: UInt32,
        _ data: Data
    ) -> UInt32 {
        var crc = initial
        for byte in data {
            let index = Int(
                (crc ^ UInt32(byte)) & 0xff
            )
            crc = table[index] ^ (crc >> 8)
        }
        return crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(
        _ value: T
    ) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) {
            append(contentsOf: $0)
        }
    }
}

/// Recovery disposition for a pre-existing artifact occupying the
/// deterministic app-owned export destination (#118). The `.htdtcapture`
/// archive at that path is a derived transport wrapper, never capture
/// authority: a validated archive whose logical bundle digest matches
/// the finalized revision is reused idempotently, while anything else
/// is removed so the archive can be rebuilt once from the immutable
/// finalized directory.
public enum ExistingExportArchiveDisposition:
    Sendable,
    Equatable
{
    /// The existing artifact is a validated `.htdtcapture` archive
    /// carrying the expected logical bundle digest.
    case recoverValidated
    /// The existing artifact is unreadable, malformed, fails archive
    /// validation, or carries a different digest. Only that derived
    /// wrapper may be removed; the finalized directory is never opened
    /// for mutation.
    case rebuild
}

public enum ExistingExportArchiveClassifier {
    /// Classify the artifact currently occupying `destination` ahead of
    /// an export retry. Anything that cannot be proven to hold the
    /// finalized revision's exact logical bytes — including unreadable
    /// or truncated files — returns `.rebuild` so a corrupt derived
    /// archive can never make retry permanently impossible. This never
    /// inspects or modifies the finalized directory itself.
    public static func disposition(
        at destination: URL,
        expectedBundleDigest: EvidenceSHA256,
        limits: BundleFilesystemLimits = .init()
    ) -> ExistingExportArchiveDisposition {
        guard let validation =
            try? StoredCaptureBundleArchiveValidator.validate(
                archive: destination,
                limits: limits
            ),
            validation.bundleDigest == expectedBundleDigest
        else {
            return .rebuild
        }
        return .recoverValidated
    }
}

private extension FileHandle {
    func readExact(count: Int) throws -> Data {
        guard count >= 0 else {
            throw CaptureBundleArchiveError.archiveMalformed
        }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let next = try read(
                upToCount: count - result.count
            ) ?? Data()
            guard !next.isEmpty else {
                throw CaptureBundleArchiveError.archiveMalformed
            }
            result.append(next)
        }
        return result
    }

    func readLE<T: FixedWidthInteger>() throws -> T {
        let data = try readExact(
            count: MemoryLayout<T>.size
        )
        return data.withUnsafeBytes {
            T(littleEndian: $0.loadUnaligned(as: T.self))
        }
    }
}
