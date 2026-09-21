import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum BundleFilesystemError: Error, Sendable, Equatable {
    case invalidRoot
    case invalidPath(String)
    case symlinkForbidden(String)
    case hardLinkForbidden(String)
    case duplicatePath(String)
    case caseCollision(String, String)
    case fileCountLimitExceeded
    case fileSizeLimitExceeded(String)
    case totalSizeLimitExceeded
    case fileOpenFailed(String)
}

public struct BundleFilesystemLimits: Sendable, Equatable {
    public let maxEntries: Int
    public let maxFileBytes: Int64
    public let maxTotalBytes: Int64
    public let maxManifestBytes: Int64

    public init(
        maxEntries: Int = 10_000,
        maxFileBytes: Int64 = 512 * 1024 * 1024,
        maxTotalBytes: Int64 = 4 * 1024 * 1024 * 1024,
        maxManifestBytes: Int64 = BundlePayloadLimits.maxManifestBytes
    ) {
        self.maxEntries = maxEntries
        self.maxFileBytes = maxFileBytes
        self.maxTotalBytes = maxTotalBytes
        self.maxManifestBytes = maxManifestBytes
    }
}

public struct ScannedBundleFile: Sendable, Equatable {
    public let path: String
    public let url: URL
    public let bytes: Int64
}

public enum BundleLogicalPath {
    public static func validate(_ path: String) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0")
        else {
            throw BundleFilesystemError.invalidPath(path)
        }

        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty else {
            throw BundleFilesystemError.invalidPath(path)
        }
        for component in components {
            guard !component.isEmpty,
                  component != ".",
                  component != ".."
            else {
                throw BundleFilesystemError.invalidPath(path)
            }
        }

        guard path.precomposedStringWithCanonicalMapping == path else {
            throw BundleFilesystemError.invalidPath(path)
        }
    }

    public static func collisionKey(_ path: String) -> String {
        // Match the reference Python validator's NFC + Unicode case-fold
        // collision semantics rather than simple lowercasing. Simple
        // lowercasing misses multi-scalar case folds such as ß -> ss and can
        // make Swift accept a bundle the reference validator rejects.
        path.precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    public static func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
        Array(lhs.utf8).lexicographicallyPrecedes(Array(rhs.utf8))
    }
}

public enum BundleDirectoryScanner {
    public static func scan(
        root: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> [ScannedBundleFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue
        else {
            throw BundleFilesystemError.invalidRoot
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .linkCountKey,
            ],
            options: []
        ) else {
            throw BundleFilesystemError.invalidRoot
        }

        var files: [ScannedBundleFile] = []
        var totalBytes: Int64 = 0
        var collisionMap: [String: String] = [:]

        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .linkCountKey,
                ]
            )

            let rootComponents = root.standardizedFileURL.pathComponents
            let fileComponents = url.standardizedFileURL.pathComponents
            guard fileComponents.starts(with: rootComponents) else {
                throw BundleFilesystemError.invalidPath(url.path)
            }
            let relativeComponents = fileComponents.dropFirst(
                rootComponents.count
            )
            if relativeComponents.isEmpty {
                continue
            }
            let normalized = relativeComponents.joined(separator: "/")
            try BundleLogicalPath.validate(normalized)

            if values.isSymbolicLink == true {
                throw BundleFilesystemError.symlinkForbidden(normalized)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw BundleFilesystemError.invalidPath(normalized)
            }

            guard let linkCount = values.linkCount else {
                // Link count is an integrity boundary. A regular file
                // reachable through a second directory entry can be
                // mutated through that external alias after the bundle
                // has been finalized and hashed. Fail closed when the
                // filesystem cannot report the count.
                throw BundleFilesystemError.invalidPath(normalized)
            }
            guard linkCount <= 1 else {
                throw BundleFilesystemError.hardLinkForbidden(normalized)
            }

            guard let fileSize = values.fileSize else {
                // Size accounting is a security/resource boundary. If the
                // provider cannot report a regular file's size, do not treat
                // it as an empty file and bypass expanded-byte limits.
                throw BundleFilesystemError.invalidPath(normalized)
            }
            let bytes = Int64(fileSize)
            if bytes > limits.maxFileBytes {
                throw BundleFilesystemError.fileSizeLimitExceeded(
                    normalized
                )
            }
            totalBytes += bytes
            if totalBytes > limits.maxTotalBytes {
                throw BundleFilesystemError.totalSizeLimitExceeded
            }

            let key = BundleLogicalPath.collisionKey(normalized)
            if let prior = collisionMap[key] {
                throw BundleFilesystemError.caseCollision(
                    prior,
                    normalized
                )
            }
            collisionMap[key] = normalized

            files.append(
                ScannedBundleFile(
                    path: normalized,
                    url: url,
                    bytes: bytes
                )
            )
            if files.count > limits.maxEntries {
                throw BundleFilesystemError.fileCountLimitExceeded
            }
        }

        return files.sorted {
            BundleLogicalPath.utf8Less($0.path, $1.path)
        }
    }
}

public struct BundleOpenedFile: Sendable, Equatable {
    public let data: Data
    public let sha256: EvidenceSHA256
    public let byteCount: Int64
}

enum BundleFileDescriptor {
    /// Opens `url` with O_NOFOLLOW and verifies, on the opened descriptor,
    /// that it is a single-linked regular file of at most `maxBytes` that
    /// still resolves to `url`. The caller owns the returned handle and
    /// must close it.
    static func open(
        url: URL,
        maxBytes: Int64
    ) throws -> (handle: FileHandle, byteCount: Int64) {
        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
        let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC
        #if canImport(Darwin)
        let descriptor = url.path.withCString { pointer in
            Darwin.open(pointer, flags)
        }
        #elseif canImport(Glibc)
        let descriptor = url.path.withCString { pointer in
            Glibc.open(pointer, flags)
        }
        #else
        let descriptor = url.path.withCString { pointer in
            Musl.open(pointer, flags)
        }
        #endif
        guard descriptor >= 0 else {
            throw BundleFilesystemError.fileOpenFailed(url.path)
        }
        let handle = FileHandle(
            fileDescriptor: descriptor,
            closeOnDealloc: true
        )
        do {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else {
                throw BundleFilesystemError.fileOpenFailed(url.path)
            }
            let fileType = UInt32(info.st_mode) & 0o170000
            guard fileType == 0o100000 else {
                throw BundleFilesystemError.invalidPath(url.path)
            }
            guard info.st_nlink <= 1 else {
                throw BundleFilesystemError.hardLinkForbidden(url.path)
            }
            let size = Int64(info.st_size)
            guard size >= 0, size <= maxBytes else {
                throw BundleFilesystemError.fileSizeLimitExceeded(url.path)
            }
            // Verify the opened descriptor is still the file `url`
            // names by comparing filesystem identity rather than path
            // strings: a descriptor path (F_GETPATH / procfs) and the
            // URL's spelling can disagree on symlink resolution
            // (`/var` vs `/private/var`, firmlinks), which would
            // falsely reject a legitimate open. If the file at `url`
            // was swapped after open(), the path now resolves to a
            // different (dev, ino) pair and the read is refused.
            var reopened = stat()
            let statStatus = url.path.withCString { pointer in
                stat(pointer, &reopened)
            }
            guard statStatus == 0,
                  reopened.st_ino == info.st_ino,
                  reopened.st_dev == info.st_dev
            else {
                throw BundleFilesystemError.invalidPath(url.path)
            }
            return (handle, size)
        } catch {
            try? handle.close()
            throw error
        }
        #else
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw BundleFilesystemError.fileOpenFailed(url.path)
        }
        do {
            let end = try handle.seekToEnd()
            guard let size = Int64(exactly: end), size <= maxBytes else {
                throw BundleFilesystemError.fileSizeLimitExceeded(url.path)
            }
            try handle.seek(toOffset: 0)
            return (handle, size)
        } catch {
            try? handle.close()
            throw error
        }
        #endif
    }

    static func readFully(
        handle: FileHandle,
        byteCount: Int64,
        maxBytes: Int64,
        path: String
    ) throws -> Data {
        var data = Data()
        if byteCount > 0, byteCount <= maxBytes {
            data.reserveCapacity(Int(byteCount))
        }
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            data.append(chunk)
            if Int64(data.count) > maxBytes {
                throw BundleFilesystemError.fileSizeLimitExceeded(path)
            }
        }
        guard Int64(data.count) == byteCount else {
            throw BundleFilesystemError.invalidPath(path)
        }
        return data
    }
}

public enum BundleFileReader {
    /// Reads a bundle payload through a single verified descriptor so that
    /// the type, size, bytes, and digest are bound to the same opened file.
    public static func read(
        _ url: URL,
        maxBytes: Int64
    ) throws -> BundleOpenedFile {
        let verified = try BundleFileDescriptor.open(
            url: url,
            maxBytes: maxBytes
        )
        defer {
            try? verified.handle.close()
        }
        let data = try BundleFileDescriptor.readFully(
            handle: verified.handle,
            byteCount: verified.byteCount,
            maxBytes: maxBytes,
            path: url.path
        )
        return BundleOpenedFile(
            data: data,
            sha256: EvidenceIntegrity.sha256(of: data),
            byteCount: verified.byteCount
        )
    }

    /// Streams a bundle payload's digest through a single verified
    /// descriptor without materializing the file.
    public static func sha256(
        _ url: URL,
        maxBytes: Int64
    ) throws -> (digest: EvidenceSHA256, byteCount: Int64) {
        let verified = try BundleFileDescriptor.open(
            url: url,
            maxBytes: maxBytes
        )
        defer {
            try? verified.handle.close()
        }
        var hasher = SHA256()
        var consumed: Int64 = 0
        while true {
            let chunk = try verified.handle.read(upToCount: 1024 * 1024)
                ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
            consumed += Int64(chunk.count)
        }
        guard consumed == verified.byteCount else {
            throw BundleFilesystemError.invalidPath(url.path)
        }
        let digest = hasher.finalize()
        let hex = digest.map {
            String(format: "%02x", $0)
        }.joined()
        return (try EvidenceSHA256(hex), verified.byteCount)
    }
}

public enum BundleFileHasher {
    public static func sha256(
        url: URL,
        chunkBytes: Int = 1024 * 1024
    ) throws -> EvidenceSHA256 {
        let chunkBytes = max(chunkBytes, 1)
        let verified = try BundleFileDescriptor.open(
            url: url,
            maxBytes: Int64.max
        )
        defer {
            try? verified.handle.close()
        }

        var hasher = SHA256()
        var consumed: Int64 = 0
        while true {
            let data = try verified.handle.read(upToCount: chunkBytes)
                ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
            consumed += Int64(data.count)
        }
        guard consumed == verified.byteCount else {
            throw BundleFilesystemError.invalidPath(url.path)
        }

        let digest = hasher.finalize()
        let hex = digest.map {
            String(format: "%02x", $0)
        }.joined()
        return try EvidenceSHA256(hex)
    }
}
