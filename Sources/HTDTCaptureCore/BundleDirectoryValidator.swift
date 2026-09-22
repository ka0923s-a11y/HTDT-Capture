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
    case manifestTooLarge
    case payloadNotCanonicalJSON(path: String, detail: String)
    case schemaValidationFailed(path: String, detail: String)
    case binaryPayloadInvalid(path: String, detail: String)
    case payloadCrossCheckFailed(path: String, detail: String)
}

public struct BundleValidationReport: Sendable, Equatable {
    public let valid: Bool
    public let manifest: BundleManifest
    public let bundleDigest: EvidenceSHA256
    public let payloadCount: Int
    /// Schema family -> `schema_version` the bundle declared at
    /// validation time (#332). Lets the library surface each payload's
    /// source version and its compatibility status under this build.
    public let payloadVersions: [String: String]

    public init(
        manifest: BundleManifest,
        bundleDigest: EvidenceSHA256,
        payloadCount: Int,
        payloadVersions: [String: String] = [:]
    ) {
        self.valid = true
        self.manifest = manifest
        self.bundleDigest = bundleDigest
        self.payloadCount = payloadCount
        self.payloadVersions = payloadVersions
    }

    /// Per-family compatibility of the validated payload versions
    /// under the published support matrix (#332).
    public var payloadCompatibility:
        [String: CapturePayloadCompatibility]
    {
        let matrix = CaptureBundleSchemaRegistry.supportMatrix
        var result: [String: CapturePayloadCompatibility] = [:]
        for (family, version) in payloadVersions {
            result[family] = matrix.compatibility(
                family: family,
                version: version
            )
        }
        return result
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

        let manifestSnapshot: BundleOpenedFile
        do {
            manifestSnapshot = try BundleFileReader.read(
                manifestFile.url,
                maxBytes: limits.maxManifestBytes
            )
        } catch BundleFilesystemError.fileSizeLimitExceeded {
            // dedicated manifest bound: rejected before bytes are read
            throw BundleDirectoryValidationError.manifestTooLarge
        } catch {
            throw BundleDirectoryValidationError.manifestUnreadable
        }
        let manifestData = manifestSnapshot.data

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

        var crossCheck = BundlePayloadCrossCheck()
        if let manifestValue = try CanonicalPayloadValidator
            .validateSchemaOwnedJSON(
                path: "manifest.json",
                data: manifestData
            )
        {
            crossCheck.recordJSON(path: "manifest.json",
                                  value: manifestValue)
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

        // Minimum foundation payload set (#194): a manifest whose
        // identity arrays have no grounding documents is not a
        // finalized v1 bundle. Same rule as the Python validator.
        let missingFoundation = BundlePayloadCrossCheck
            .foundationRequiredPaths
            .subtracting(declaredSet)
        guard missingFoundation.isEmpty else {
            throw BundleDirectoryValidationError
                .declaredPayloadSetMismatch(
                    missing: missingFoundation
                        .sorted(by: BundleLogicalPath.utf8Less),
                    undeclared: []
                )
        }

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

            let schemaFamily = CaptureBundleSchemaRegistry
                .schemaName(forPath: path)
            // #332: a manifest-declared .json payload must be owned by
            // a published schema or be a declared external authority
            // payload (RoomPlan). Any other .json is a generic
            // supplemental persistence bypass and fails validation —
            // except legacy bundles that carry RoomPlan payloads at
            // non-reserved paths, which the ingestor resolves by
            // provenance class.
            if path.hasSuffix(".json"),
               schemaFamily == nil,
               !CaptureBundleSchemaRegistry.supportMatrix
                   .isExternalAuthorityPath(path),
               entry.provenanceClass != .appleRoomPlanRawScan,
               entry.provenanceClass != .appleRoomPlanInference
            {
                throw BundleDirectoryValidationError
                    .schemaValidationFailed(
                        path: path,
                        detail: "JSON payload is not owned by a "
                            + "published schema or external authority"
                    )
            }

            let needsBytes = schemaFamily != nil
                || CanonicalPayloadValidator.isCanonicalBinaryMediaType(
                    entry.mediaType
                )

            if needsBytes {
                let snapshot = try BundleFileReader.read(
                    actual.url,
                    maxBytes: limits.maxFileBytes
                )
                guard snapshot.byteCount == Int64(entry.bytes) else {
                    throw BundleDirectoryValidationError
                        .byteLengthMismatch(
                            path: path,
                            expected: entry.bytes,
                            actual: snapshot.byteCount
                        )
                }
                guard snapshot.sha256 == entry.sha256 else {
                    throw BundleDirectoryValidationError.hashMismatch(
                        path: path,
                        expected: entry.sha256.description,
                        actual: snapshot.sha256.description
                    )
                }
                try CanonicalPayloadValidator.validateDeclaredPayload(
                    path: path,
                    mediaType: entry.mediaType,
                    data: snapshot.data,
                    crossCheck: &crossCheck
                )
            } else {
                let streamed = try BundleFileReader.sha256(
                    actual.url,
                    maxBytes: limits.maxFileBytes
                )
                guard streamed.byteCount == Int64(entry.bytes) else {
                    throw BundleDirectoryValidationError
                        .byteLengthMismatch(
                            path: path,
                            expected: entry.bytes,
                            actual: streamed.byteCount
                        )
                }
                guard streamed.digest == entry.sha256 else {
                    throw BundleDirectoryValidationError.hashMismatch(
                        path: path,
                        expected: entry.sha256.description,
                        actual: streamed.digest.description
                    )
                }
            }
        }
        try crossCheck.finish(
            declaredByPath: declaredByPath,
            manifest: manifest
        )

        let bundleDigest = EvidenceIntegrity.sha256(
            of: manifestData
        )
        return BundleValidationReport(
            manifest: manifest,
            bundleDigest: bundleDigest,
            payloadCount: manifest.files.count,
            payloadVersions: crossCheck.payloadVersions
        )
    }
}
