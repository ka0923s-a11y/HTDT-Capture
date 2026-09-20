import CryptoKit
import Foundation

public enum BundleFilesystemError: Error, Sendable, Equatable {
    case invalidRoot
    case invalidPath(String)
    case symlinkForbidden(String)
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

    public init(
        maxEntries: Int = 10_000,
        maxFileBytes: Int64 = 512 * 1024 * 1024,
        maxTotalBytes: Int64 = 4 * 1024 * 1024 * 1024
    ) {
        self.maxEntries = maxEntries
        self.maxFileBytes = maxFileBytes
        self.maxTotalBytes = maxTotalBytes
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

            let bytes = Int64(values.fileSize ?? 0)
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

public enum BundleFileHasher {
    public static func sha256(
        url: URL,
        chunkBytes: Int = 1024 * 1024
    ) throws -> EvidenceSHA256 {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw BundleFilesystemError.fileOpenFailed(url.path)
        }
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: chunkBytes) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        let hex = digest.map {
            String(format: "%02x", $0)
        }.joined()
        return try EvidenceSHA256(hex)
    }
}
