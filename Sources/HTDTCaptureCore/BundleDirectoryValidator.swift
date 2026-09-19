import Foundation

public enum BundleDirectoryValidationError: Error, Sendable, Equatable {
    case manifestMissing
    case manifestUnreadable
    case manifestDecodeFailed
    case manifestNotCanonical
    case invalidManifestEntry(String)
    case declaredPayloadSetMismatch(
        missing: [String],
        undeclared: [String]
    )
    case byteLengthMismatch(
        path: String,
        expected: Int,
        actual: Int64
    )
    case hashMismatch(
        path: String,
        expected: String,
        actual: String
    )
}

public struct BundleValidationReport: Sendable, Equatable {
    public let valid: Bool
    public let manifest: BundleManifest
    public let bundleDigest: EvidenceSHA256
    public let payloadCount: Int

    public init(
        manifest: BundleManifest,
        bundleDigest: EvidenceSHA256,
        payloadCount: Int
    ) {
        self.valid = true
        self.manifest = manifest
        self.bundleDigest = bundleDigest
        self.payloadCount = payloadCount
    }
}

public enum BundleDirectoryValidator {
    public static func validate(
        root: URL,
        limits: BundleFilesystemLimits = .init()
    ) throws -> BundleValidationReport {
        let files = try BundleDirectoryScanner.scan(
            root: root,
            limits: limits
        )
        guard let manifestFile = files.first(where: {
            $0.path == "manifest.json"
        }) else {
            throw BundleDirectoryValidationError.manifestMissing
        }

        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestFile.url)
        } catch {
            throw BundleDirectoryValidationError.manifestUnreadable
        }

        let manifest: BundleManifest
        do {
            manifest = try JSONDecoder().decode(
                BundleManifest.self,
                from: manifestData
            )
        } catch {
            throw BundleDirectoryValidationError.manifestDecodeFailed
        }

        let canonical: Data
        do {
            canonical = try manifest.canonicalBytes()
        } catch {
            throw BundleDirectoryValidationError.manifestNotCanonical
        }
        guard canonical == manifestData else {
            throw BundleDirectoryValidationError.manifestNotCanonical
        }

        var declaredByPath: [String: BundleFileEntry] = [:]
        for entry in manifest.files {
            do {
                try BundleLogicalPath.validate(entry.path)
            } catch {
                throw BundleDirectoryValidationError.invalidManifestEntry(
                    entry.path
                )
            }
            guard entry.bytes >= 0,
                  !entry.mediaType.isEmpty,
                  !entry.producer.isEmpty
            else {
                throw BundleDirectoryValidationError.invalidManifestEntry(
                    entry.path
                )
            }
            if let sourceRefs = entry.sourceRefs {
                guard sourceRefs.allSatisfy({ !$0.isEmpty }),
                      Set(sourceRefs).count == sourceRefs.count
                else {
                    throw BundleDirectoryValidationError
                        .invalidManifestEntry(entry.path)
                }
            }
            if declaredByPath[entry.path] != nil {
                throw BundleDirectoryValidationError.invalidManifestEntry(
                    entry.path
                )
            }
            declaredByPath[entry.path] = entry
        }

        let actualPayloadFiles = files.filter {
            $0.path != "manifest.json"
        }
        let actualByPath = Dictionary(
            uniqueKeysWithValues: actualPayloadFiles.map {
                ($0.path, $0)
            }
        )
        let declaredSet = Set(declaredByPath.keys)
        let actualSet = Set(actualByPath.keys)

        if declaredSet != actualSet {
            throw BundleDirectoryValidationError
                .declaredPayloadSetMismatch(
                    missing: declaredSet
                        .subtracting(actualSet)
                        .sorted(by: BundleLogicalPath.utf8Less),
                    undeclared: actualSet
                        .subtracting(declaredSet)
                        .sorted(by: BundleLogicalPath.utf8Less)
                )
        }

        for path in declaredSet.sorted(
            by: BundleLogicalPath.utf8Less
        ) {
            guard let entry = declaredByPath[path],
                  let actual = actualByPath[path]
            else {
                continue
            }

            guard Int64(entry.bytes) == actual.bytes else {
                throw BundleDirectoryValidationError.byteLengthMismatch(
                    path: path,
                    expected: entry.bytes,
                    actual: actual.bytes
                )
            }

            let digest = try BundleFileHasher.sha256(
                url: actual.url
            )
            guard digest == entry.sha256 else {
                throw BundleDirectoryValidationError.hashMismatch(
                    path: path,
                    expected: entry.sha256.description,
                    actual: digest.description
                )
            }
        }

        let bundleDigest = EvidenceIntegrity.sha256(
            of: manifestData
        )
        return BundleValidationReport(
            manifest: manifest,
            bundleDigest: bundleDigest,
            payloadCount: manifest.files.count
        )
    }
}
