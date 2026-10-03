import CryptoKit
import Foundation

/// `.htdtcapturelibrary` — the Capture Library portability container
/// (issue bolph71656-ai/HTDT-Capture#378). A stored-ZIP package carrying byte-exact
/// `.htdtcapture` archives plus filtered app-local metadata and the
/// handoff-receipt ledger entries for the included revisions. The
/// package schema version is independent of the capture-bundle schema
/// version: the owning validators stay authoritative for each level.
///
/// Layout (all entries sorted by `BundleLogicalPath.utf8Less`):
///   `library-package.json`            package manifest
///   `archives/<revision_id>.htdtcapture`
///   `library-metadata.json`           filtered metadata document
///   `handoff-receipts.json`           filtered receipt ledger
public enum CaptureLibraryPackageError:
    Error,
    Sendable,
    Equatable
{
    case invalidDestinationExtension
    case destinationAlreadyExists
    case archiveMalformed
    case archiveEntryMismatch
    case archiveEntryTypeForbidden(String)
    case manifestMissing
    case manifestDecodeFailed
    case manifestNotCanonical
    case unsupportedSchemaVersion(String)
    case unsupportedBundleSchema
    case archiveSHA256Mismatch(String)
    case archiveDigestMismatch(String)
    case archiveValidationFailed(String)
    case archiveTooLargeForClassicZIP
    case filenameTooLong(String)
    case fileOpenFailed(String)
    case atomicPublishFailed
    case emptyPackage
}

public struct CaptureLibraryPackageManifest:
    Codable,
    Sendable,
    Equatable
{
    public static let schema = "htdt.capture.library-package"
    public static let schemaVersion = "1.0.0"
    public static let supportedReadVersions = ["1.0.0"]

    /// One included revision: identity is fixed by the bundle's own
    /// manifest; the archive bytes are attested by `archive_sha256`
    /// and the logical bundle digest separately so neither can be
    /// forged by editing package fields alone.
    public struct RevisionEntry:
        Codable,
        Sendable,
        Equatable
    {
        public let captureRevisionID: String
        public let captureSeriesID: String
        public let bundleDigest: String
        public let archiveSHA256: String
        public let archiveByteCount: Int64
        /// Logical path inside the package, always
        /// `archives/<capture_revision_id>.htdtcapture`.
        public let archivePath: String
        public let finalizedAtUTC: String

        public init(
            captureRevisionID: String,
            captureSeriesID: String,
            bundleDigest: String,
            archiveSHA256: String,
            archiveByteCount: Int64,
            archivePath: String,
            finalizedAtUTC: String
        ) {
            self.captureRevisionID = captureRevisionID
            self.captureSeriesID = captureSeriesID
            self.bundleDigest = bundleDigest
            self.archiveSHA256 = archiveSHA256
            self.archiveByteCount = archiveByteCount
            self.archivePath = archivePath
            self.finalizedAtUTC = finalizedAtUTC
        }

        private enum CodingKeys: String, CodingKey {
            case captureRevisionID = "capture_revision_id"
            case captureSeriesID = "capture_series_id"
            case bundleDigest = "bundle_digest"
            case archiveSHA256 = "archive_sha256"
            case archiveByteCount = "archive_byte_count"
            case archivePath = "archive_path"
            case finalizedAtUTC = "finalized_at_utc"
        }
    }

    public let schema: String
    public let schemaVersion: String
    public let createdAtUTC: String
    public let app: BundleAppIdentity
    public let revisions: [RevisionEntry]
    /// Whether `library-metadata.json` rides along in the package.
    public let includesLibraryMetadata: Bool
    /// Whether `handoff-receipts.json` rides along in the package.
    public let includesHandoffReceipts: Bool

    public init(
        createdAtUTC: String,
        app: BundleAppIdentity,
        revisions: [RevisionEntry],
        includesLibraryMetadata: Bool,
        includesHandoffReceipts: Bool
    ) {
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.createdAtUTC = createdAtUTC
        self.app = app
        self.revisions = revisions
        self.includesLibraryMetadata = includesLibraryMetadata
        self.includesHandoffReceipts = includesHandoffReceipts
    }

    /// Deterministic encode: sorted keys, no escaping; the canonical
    /// form the package validator compares entry bytes against.
    public func canonicalBytes() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case createdAtUTC = "created_at_utc"
        case app
        case revisions
        case includesLibraryMetadata = "includes_library_metadata"
        case includesHandoffReceipts = "includes_handoff_receipts"
    }
}

/// One member of a `.htdtcapturelibrary` package while it is being
/// written: either inline bytes (manifest, metadata, receipts) or a
/// file-backed stream (`.htdtcapture` archives, which can be large).
public struct CaptureLibraryPackageEntry {
    public enum Source {
        case data(Data)
        case file(URL)
    }

    public let path: String
    public let source: Source

    public init(path: String, source: Source) {
        self.path = path
        self.source = source
    }
}

private struct CaptureLibraryPackageLocalEntry {
    let path: String
    let crc32: UInt32
    let size: UInt32
    let dataOffset: UInt64
}

/// Writes a `.htdtcapturelibrary` container: the same stored-ZIP
/// profile `.htdtcapture` uses (method 0, UTF-8 flag, version 20, no
/// extra fields, fixed DOS date, sorted entries) so the two container
/// levels stay byte-compatible in policy while keeping independent
/// schemas and validators.
public enum CaptureLibraryPackageWriter {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50
    private static let utf8Flag: UInt16 = 0x0800
    private static let storeMethod: UInt16 = 0
    private static let version20: UInt16 = 20
    private static let fixedDOSTime: UInt16 = 0
    private static let fixedDOSDate: UInt16 = 33
    private static let chunkBytes = 1024 * 1024

    public static func write(
        entries: [CaptureLibraryPackageEntry],
        destination: URL
    ) throws {
        guard destination.pathExtension == "htdtcapturelibrary"
        else {
            throw CaptureLibraryPackageError
                .invalidDestinationExtension
        }
        guard !FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            throw CaptureLibraryPackageError
                .destinationAlreadyExists
        }
        guard !entries.isEmpty else {
            throw CaptureLibraryPackageError.emptyPackage
        }

        let sorted = entries.sorted {
            BundleLogicalPath.utf8Less($0.path, $1.path)
        }
        guard sorted.count <= Int(UInt16.max) else {
            throw CaptureLibraryPackageError
                .archiveTooLargeForClassicZIP
        }
        var collisionMap: [String: String] = [:]
        for entry in sorted {
            do {
                try BundleLogicalPath.validate(entry.path)
            } catch {
                throw CaptureLibraryPackageError.archiveMalformed
            }
            let key = BundleLogicalPath.collisionKey(entry.path)
            guard collisionMap[key] == nil else {
                throw CaptureLibraryPackageError.archiveMalformed
            }
            collisionMap[key] = entry.path
        }

        // Compute per-entry size + CRC32 and the byte layout up front
        // so the container is written in one deterministic pass.
        struct Staged {
            let entry: CaptureLibraryPackageEntry
            let size: UInt32
            let crc32: UInt32
            let localOffset: UInt32
        }
        var staged: [Staged] = []
        staged.reserveCapacity(sorted.count)
        var nextOffset: UInt64 = 0
        for entry in sorted {
            let nameBytes = Data(entry.path.utf8)
            guard nameBytes.count <= Int(UInt16.max) else {
                throw CaptureLibraryPackageError.filenameTooLong(
                    entry.path
                )
            }
            let size: UInt64
            let crc32: UInt32
            switch entry.source {
            case .data(let data):
                size = UInt64(data.count)
                crc32 = ZIPCRC32Library.data(data)
            case .file(let url):
                let attributes = try FileManager.default
                    .attributesOfItem(atPath: url.path)
                guard let fileSize = attributes[.size]
                        as? NSNumber
                else {
                    throw CaptureLibraryPackageError
                        .fileOpenFailed(url.path)
                }
                size = fileSize.uint64Value
                crc32 = try ZIPCRC32Library.file(url: url)
            }
            guard size <= UInt64(UInt32.max) else {
                throw CaptureLibraryPackageError
                    .archiveTooLargeForClassicZIP
            }
            let required =
                nextOffset + 30 + UInt64(nameBytes.count) + size
            guard nextOffset <= UInt64(UInt32.max),
                  required <= UInt64(UInt32.max)
            else {
                throw CaptureLibraryPackageError
                    .archiveTooLargeForClassicZIP
            }
            staged.append(
                Staged(
                    entry: entry,
                    size: UInt32(size),
                    crc32: crc32,
                    localOffset: UInt32(nextOffset)
                )
            )
            nextOffset = required
        }

        let centralOffset = nextOffset
        var centralSize: UInt64 = 0
        for item in staged {
            centralSize += UInt64(
                46 + Data(item.entry.path.utf8).count
            )
        }
        guard centralOffset <= UInt64(UInt32.max),
              centralSize <= UInt64(UInt32.max),
              centralOffset + centralSize + 22
                <= UInt64(UInt32.max)
        else {
            throw CaptureLibraryPackageError
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
            throw CaptureLibraryPackageError.fileOpenFailed(temp.path)
        }
        guard let output = try? FileHandle(forWritingTo: temp) else {
            throw CaptureLibraryPackageError.fileOpenFailed(temp.path)
        }
        defer {
            try? output.close()
        }

        for item in staged {
            let name = Data(item.entry.path.utf8)
            var header = Data()
            header.appendLE(localSignature)
            header.appendLE(version20)
            header.appendLE(utf8Flag)
            header.appendLE(storeMethod)
            header.appendLE(fixedDOSTime)
            header.appendLE(fixedDOSDate)
            header.appendLE(item.crc32)
            header.appendLE(item.size)
            header.appendLE(item.size)
            header.appendLE(UInt16(name.count))
            header.appendLE(UInt16(0))
            header.append(name)
            try output.write(contentsOf: header)
            switch item.entry.source {
            case .data(let data):
                try output.write(contentsOf: data)
            case .file(let url):
                try copyFile(url, to: output)
            }
        }

        for item in staged {
            let name = Data(item.entry.path.utf8)
            var central = Data()
            central.appendLE(centralSignature)
            central.appendLE(version20)
            central.appendLE(version20)
            central.appendLE(utf8Flag)
            central.appendLE(storeMethod)
            central.appendLE(fixedDOSTime)
            central.appendLE(fixedDOSDate)
            central.appendLE(item.crc32)
            central.appendLE(item.size)
            central.appendLE(item.size)
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(item.localOffset)
            central.append(name)
            try output.write(contentsOf: central)
        }

        var end = Data()
        end.appendLE(endSignature)
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(staged.count))
        end.appendLE(UInt16(staged.count))
        end.appendLE(UInt32(centralSize))
        end.appendLE(UInt32(centralOffset))
        end.appendLE(UInt16(0))
        try output.write(contentsOf: end)
        try output.synchronize()

        do {
            try FileManager.default.moveItem(
                at: temp,
                to: destination
            )
        } catch {
            throw CaptureLibraryPackageError.atomicPublishFailed
        }
    }

    private static func copyFile(
        _ source: URL,
        to output: FileHandle
    ) throws {
        guard let input = try? FileHandle(forReadingFrom: source)
        else {
            throw CaptureLibraryPackageError
                .fileOpenFailed(source.path)
        }
        defer {
            try? input.close()
        }
        while true {
            let chunk =
                try input.read(upToCount: chunkBytes) ?? Data()
            if chunk.isEmpty {
                break
            }
            try output.write(contentsOf: chunk)
        }
    }
}

/// Validates and reads a `.htdtcapturelibrary` container (issue
/// legacy bolph71656-ai/HTDT-Capture#378). The container contract mirrors the `.htdtcapture` stored-ZIP
/// validator: locals then central then end, method 0, UTF-8 flag, no
/// extras, sorted names, no collisions, and CRC proven per entry. On
/// top of the container, `validate` decodes the manifest, enforces the
/// package schema + supported read versions, and requires the manifest
/// to be canonical bytes — so package structure and package semantics
/// are proven together before any archive is trusted.
public enum CaptureLibraryPackageReader {
    private static let localSignature: UInt32 = 0x04034b50
    private static let centralSignature: UInt32 = 0x02014b50
    private static let endSignature: UInt32 = 0x06054b50
    private static let utf8Flag: UInt16 = 0x0800
    private static let storeMethod: UInt16 = 0
    private static let chunkBytes = 1024 * 1024

    /// One validated local entry — the read-address index the
    /// importer uses to stream member bytes without re-parsing.
    public struct Entry {
        public let path: String
        public let size: UInt32
        public let crc32: UInt32
        public let dataOffset: UInt64
    }

    public struct ValidatedPackage {
        public let archive: URL
        public let manifest: CaptureLibraryPackageManifest
        /// Entries other than `library-package.json`, keyed by path.
        public let entries: [String: Entry]
    }

    /// Fully validates the container and manifest; throws on any
    /// structural or semantic mismatch. Returns the read index needed
    /// for member extraction.
    public static func validate(
        archive: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> ValidatedPackage {
        let entries = try index(archive: archive, limits: limits)
        guard let manifestEntry = entries.first(where: {
            $0.path == "library-package.json"
        }) else {
            throw CaptureLibraryPackageError.manifestMissing
        }
        let manifestData = try readSegment(
            archive: archive,
            entry: manifestEntry
        )
        let manifest: CaptureLibraryPackageManifest
        do {
            manifest = try JSONDecoder().decode(
                CaptureLibraryPackageManifest.self,
                from: manifestData
            )
        } catch {
            throw CaptureLibraryPackageError.manifestDecodeFailed
        }
        guard manifest.schema
                == CaptureLibraryPackageManifest.schema else {
            throw CaptureLibraryPackageError.manifestDecodeFailed
        }
        guard CaptureLibraryPackageManifest.supportedReadVersions
            .contains(manifest.schemaVersion)
        else {
            throw CaptureLibraryPackageError
                .unsupportedSchemaVersion(manifest.schemaVersion)
        }
        let canonical = try manifest.canonicalBytes()
        guard canonical == manifestData else {
            throw CaptureLibraryPackageError.manifestNotCanonical
        }

        var byPath: [String: Entry] = [:]
        for entry in entries where entry.path
            != "library-package.json"
        {
            byPath[entry.path] = entry
        }
        return ValidatedPackage(
            archive: archive,
            manifest: manifest,
            entries: byPath
        )
    }

    /// Validates the ZIP container only — the structural layer —
    /// without requiring the package manifest to decode. Useful when
    /// the caller wants to distinguish a malformed package from a
    /// semantically unsupported one.
    public static func index(
        archive: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> [Entry] {
        guard let handle = try? FileHandle(
            forReadingFrom: archive
        ) else {
            throw CaptureLibraryPackageError
                .fileOpenFailed(archive.path)
        }
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        var locals: [CaptureLibraryPackageLocalEntry] = []
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
                throw CaptureLibraryPackageError.archiveMalformed
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
                throw CaptureLibraryPackageError.archiveMalformed
            }

            let nameData = try handle.readExact(
                count: Int(nameLength)
            )
            guard let path = String(
                data: nameData,
                encoding: .utf8
            ) else {
                throw CaptureLibraryPackageError.archiveMalformed
            }
            do {
                try BundleLogicalPath.validate(path)
            } catch {
                throw CaptureLibraryPackageError.archiveMalformed
            }
            let collisionKey =
                BundleLogicalPath.collisionKey(path)
            guard collisionMap[collisionKey] == nil else {
                throw CaptureLibraryPackageError.archiveMalformed
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
                throw CaptureLibraryPackageError.archiveMalformed
            }
            let actualCRC = try ZIPCRC32Library.segment(
                handle: handle,
                offset: dataOffset,
                count: UInt64(size)
            )
            guard actualCRC == crc else {
                throw CaptureLibraryPackageError
                    .archiveEntryMismatch
            }
            locals.append(
                CaptureLibraryPackageLocalEntry(
                    path: path,
                    crc32: crc,
                    size: size,
                    dataOffset: dataOffset
                )
            )
            cursor = dataOffset + UInt64(size)
        }

        guard let centralOffset else {
            throw CaptureLibraryPackageError.archiveMalformed
        }
        guard locals.map(\.path) == locals.map(\.path)
            .sorted(by: BundleLogicalPath.utf8Less)
        else {
            throw CaptureLibraryPackageError.archiveMalformed
        }

        var byOffset: [UInt64: CaptureLibraryPackageLocalEntry] = [:]
        for local in locals {
            let localOffset =
                local.dataOffset
                - 30
                - UInt64(Data(local.path.utf8).count)
            byOffset[localOffset] = local
        }

        var centralPaths: [String] = []
        try handle.seek(toOffset: centralOffset)
        for _ in locals.indices {
            let signature: UInt32 = try handle.readLE()
            guard signature == centralSignature else {
                throw CaptureLibraryPackageError.archiveMalformed
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
            let externalAttributes: UInt32 = try handle.readLE()
            let localOffset: UInt32 = try handle.readLE()

            guard version == 20,
                  flags == utf8Flag,
                  method == storeMethod,
                  compressedSize == size,
                  extraLength == 0,
                  commentLength == 0,
                  diskStart == 0
            else {
                throw CaptureLibraryPackageError.archiveMalformed
            }

            let nameData = try handle.readExact(
                count: Int(nameLength)
            )
            guard let path = String(
                data: nameData,
                encoding: .utf8
            ) else {
                throw CaptureLibraryPackageError.archiveMalformed
            }

            // Same entry-type policy as the bundle validator (legacy bolph71656-ai/HTDT-Capture#196):
            // only regular/directory/unspecified file types pass.
            let unixFileType =
                (externalAttributes >> 16) & 0o170000
            guard unixFileType == 0
                  || unixFileType == 0o100000
                  || unixFileType == 0o040000
            else {
                throw CaptureLibraryPackageError
                    .archiveEntryTypeForbidden(path)
            }

            guard let local = byOffset[UInt64(localOffset)],
                  local.path == path,
                  local.crc32 == crc,
                  local.size == size
            else {
                throw CaptureLibraryPackageError
                    .archiveEntryMismatch
            }
            centralPaths.append(path)
        }

        let endOffset = try handle.offset()
        let endSignature: UInt32 = try handle.readLE()
        guard endSignature == self.endSignature else {
            throw CaptureLibraryPackageError.archiveMalformed
        }
        let disk: UInt16 = try handle.readLE()
        let centralDisk: UInt16 = try handle.readLE()
        let entriesOnDisk: UInt16 = try handle.readLE()
        let entryCount: UInt16 = try handle.readLE()
        let centralSize: UInt32 = try handle.readLE()
        let declaredCentralOffset: UInt32 = try handle.readLE()
        let commentLength: UInt16 = try handle.readLE()

        guard centralOffset <= UInt64(UInt32.max),
              disk == 0,
              centralDisk == 0,
              entriesOnDisk == UInt16(locals.count),
              entryCount == UInt16(locals.count),
              declaredCentralOffset == UInt32(centralOffset),
              UInt64(centralSize) == endOffset - centralOffset,
              commentLength == 0,
              try handle.offset() == fileSize,
              Set(centralPaths) == Set(locals.map(\.path))
        else {
            throw CaptureLibraryPackageError.archiveMalformed
        }

        return locals.map {
            Entry(
                path: $0.path,
                size: $0.size,
                crc32: $0.crc32,
                dataOffset: $0.dataOffset
            )
        }
    }

    /// Streams one member's bytes to `destination`; the destination
    /// must not exist. Data is written to a sibling temp file first
    /// and moved over, so a partial extract never publishes.
    public static func extractEntry(
        archive: URL,
        entry: Entry,
        destination: URL
    ) throws {
        guard !FileManager.default.fileExists(
            atPath: destination.path
        ) else {
            throw CaptureLibraryPackageError
                .destinationAlreadyExists
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
            throw CaptureLibraryPackageError
                .fileOpenFailed(temp.path)
        }
        guard let input = try? FileHandle(
            forReadingFrom: archive
        ), let output = try? FileHandle(forWritingTo: temp)
        else {
            throw CaptureLibraryPackageError
                .fileOpenFailed(archive.path)
        }
        defer {
            try? input.close()
            try? output.close()
        }
        try input.seek(toOffset: entry.dataOffset)
        var remaining = UInt64(entry.size)
        while remaining > 0 {
            let request = Int(
                min(UInt64(chunkBytes), remaining)
            )
            let data = try input.readExact(count: request)
            try output.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
        try output.synchronize()
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    /// Reads a member's full bytes into memory — intended for the
    /// small package documents, never for `.htdtcapture` archives.
    public static func readSegment(
        archive: URL,
        entry: Entry
    ) throws -> Data {
        guard let handle = try? FileHandle(
            forReadingFrom: archive
        ) else {
            throw CaptureLibraryPackageError
                .fileOpenFailed(archive.path)
        }
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: entry.dataOffset)
        return try handle.readExact(count: Int(entry.size))
    }
}

private enum ZIPCRC32Library {
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

    static func data(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        crc = update(crc, data)
        return crc ^ UInt32.max
    }

    static func file(
        url: URL,
        chunkBytes: Int = 1024 * 1024
    ) throws -> UInt32 {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw CaptureLibraryPackageError
                .fileOpenFailed(url.path)
        }
        defer {
            try? handle.close()
        }
        var crc = UInt32.max
        while true {
            let data =
                try handle.read(upToCount: chunkBytes) ?? Data()
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

private extension FileHandle {
    func readExact(count: Int) throws -> Data {
        guard count >= 0 else {
            throw CaptureLibraryPackageError.archiveMalformed
        }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            let next = try read(
                upToCount: count - result.count
            ) ?? Data()
            guard !next.isEmpty else {
                throw CaptureLibraryPackageError.archiveMalformed
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
