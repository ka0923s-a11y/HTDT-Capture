import Foundation

public enum BundleFinalizationError: Error, Sendable, Equatable {
    case qualityNotReady
    case integrityAssertionMissing
    case manifestAlreadyPresent
    case destinationAlreadyExists
    case duplicateDeclaration(String)
    case invalidDeclaration(String)
    case stagedPayloadSetMismatch(
        missing: [String],
        undeclared: [String]
    )
    case qualityPayloadMissing
    case qualityPayloadUnreadable
    case qualityPayloadMismatch
    case crossVolumePromotionForbidden
    case promotionFailed
}

public struct BundleFinalizationRequest: Sendable, Equatable {
    public let captureSeriesID: CaptureSeriesID
    public let captureRevisionID: CaptureRevisionID
    public let parentRevisionID: CaptureRevisionID?
    public let captureSessionIDs: [CaptureSessionID]
    public let coordinateSpaceIDs: [CoordinateSpaceID]
    public let createdAtUTC: String
    public let finalizedAtUTC: String
    public let app: BundleAppIdentity
    public let payloads: [BundlePayloadDeclaration]
    public let qualityReport: CaptureQualityReport

    public init(
        captureSeriesID: CaptureSeriesID,
        captureRevisionID: CaptureRevisionID,
        parentRevisionID: CaptureRevisionID? = nil,
        captureSessionIDs: [CaptureSessionID],
        coordinateSpaceIDs: [CoordinateSpaceID],
        createdAtUTC: String,
        finalizedAtUTC: String,
        app: BundleAppIdentity,
        payloads: [BundlePayloadDeclaration],
        qualityReport: CaptureQualityReport
    ) {
        self.captureSeriesID = captureSeriesID
        self.captureRevisionID = captureRevisionID
        self.parentRevisionID = parentRevisionID
        self.captureSessionIDs = captureSessionIDs
        self.coordinateSpaceIDs = coordinateSpaceIDs
        self.createdAtUTC = createdAtUTC
        self.finalizedAtUTC = finalizedAtUTC
        self.app = app
        self.payloads = payloads
        self.qualityReport = qualityReport
    }
}

public struct FinalizedCaptureRevision: Sendable, Equatable {
    public let directory: URL
    public let captureRevisionID: CaptureRevisionID
    public let bundleDigest: EvidenceSHA256
    public let payloadCount: Int

    public init(
        directory: URL,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256,
        payloadCount: Int
    ) {
        self.directory = directory
        self.captureRevisionID = captureRevisionID
        self.bundleDigest = bundleDigest
        self.payloadCount = payloadCount
    }
}

public actor BundleRevisionFinalizer {
    private let fileManager: FileManager
    private let limits: BundleFilesystemLimits
    private let volumeIdentity:
        @Sendable (URL) throws -> String?

    public init(
        fileManager: FileManager = .default,
        limits: BundleFilesystemLimits = .init()
    ) {
        self.fileManager = fileManager
        self.limits = limits
        self.volumeIdentity = { url in
            let values = try url.resourceValues(
                forKeys: [.volumeIdentifierKey]
            )
            return values.volumeIdentifier.map {
                String(describing: $0)
            }
        }
    }

    // Testing seam: the platform volume-identifier API cannot reliably
    // produce an "identity unknown" state in a normal temp directory,
    // so tests inject the probe directly.
    init(
        fileManager: FileManager = .default,
        limits: BundleFilesystemLimits = .init(),
        volumeIdentity:
            @escaping @Sendable (URL) throws -> String?
    ) {
        self.fileManager = fileManager
        self.limits = limits
        self.volumeIdentity = volumeIdentity
    }

    public func finalize(
        stagingDirectory: URL,
        destinationDirectory: URL,
        request: BundleFinalizationRequest
    ) throws -> FinalizedCaptureRevision {
        guard request.qualityReport.readyForHTDTIngestion else {
            throw BundleFinalizationError.qualityNotReady
        }
        guard request.qualityReport.integrityStatus == .pass else {
            throw BundleFinalizationError.integrityAssertionMissing
        }

        let manifestURL = stagingDirectory.appendingPathComponent(
            "manifest.json",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: manifestURL.path) {
            throw BundleFinalizationError.manifestAlreadyPresent
        }
        if fileManager.fileExists(atPath: destinationDirectory.path) {
            throw BundleFinalizationError.destinationAlreadyExists
        }

        var declarations: [String: BundlePayloadDeclaration] = [:]
        for declaration in request.payloads {
            do {
                try BundleLogicalPath.validate(declaration.path)
            } catch {
                throw BundleFinalizationError.invalidDeclaration(
                    declaration.path
                )
            }
            guard declaration.path != "manifest.json",
                  !declaration.mediaType.isEmpty,
                  !declaration.producer.isEmpty,
                  declaration.sourceRefs?.allSatisfy({
                      !$0.isEmpty
                  }) ?? true,
                  declaration.sourceRefs.map({
                      Set($0).count == $0.count
                  }) ?? true
            else {
                throw BundleFinalizationError.invalidDeclaration(
                    declaration.path
                )
            }
            if declarations[declaration.path] != nil {
                throw BundleFinalizationError.duplicateDeclaration(
                    declaration.path
                )
            }
            declarations[declaration.path] = declaration
        }

        let stagedFiles = try BundleDirectoryScanner.scan(
            root: stagingDirectory,
            limits: limits
        )
        let stagedByPath = Dictionary(
            uniqueKeysWithValues: stagedFiles.map {
                ($0.path, $0)
            }
        )
        let declaredSet = Set(declarations.keys)
        let stagedSet = Set(stagedByPath.keys)

        if declaredSet != stagedSet {
            throw BundleFinalizationError.stagedPayloadSetMismatch(
                missing: declaredSet
                    .subtracting(stagedSet)
                    .sorted(by: BundleLogicalPath.utf8Less),
                undeclared: stagedSet
                    .subtracting(declaredSet)
                    .sorted(by: BundleLogicalPath.utf8Less)
            )
        }

        // The quality report authorizes finalization, so the payload
        // sealed into the bundle must be that exact report: require the
        // canonical declaration, then prove the staged bytes decode to
        // a CaptureQualityReport equal to request.qualityReport.
        let qualityPath = "quality/capture-quality.json"
        guard declarations[qualityPath] != nil,
              let stagedQuality = stagedByPath[qualityPath]
        else {
            throw BundleFinalizationError.qualityPayloadMissing
        }
        let stagedQualityReport: CaptureQualityReport
        do {
            let stagedQualityData = try Data(
                contentsOf: stagedQuality.url
            )
            stagedQualityReport = try JSONDecoder().decode(
                CaptureQualityReport.self,
                from: stagedQualityData
            )
        } catch {
            throw BundleFinalizationError.qualityPayloadUnreadable
        }
        guard stagedQualityReport == request.qualityReport else {
            throw BundleFinalizationError.qualityPayloadMismatch
        }

        var entries: [BundleFileEntry] = []
        entries.reserveCapacity(stagedFiles.count)
        for file in stagedFiles {
            guard let declaration = declarations[file.path],
                  let byteCount = Int(exactly: file.bytes)
            else {
                throw BundleFinalizationError.invalidDeclaration(
                    file.path
                )
            }
            let digest = try BundleFileHasher.sha256(url: file.url)
            entries.append(
                BundleFileEntry(
                    path: file.path,
                    bytes: byteCount,
                    mediaType: declaration.mediaType,
                    sha256: digest,
                    producer: declaration.producer,
                    provenanceClass: declaration.provenanceClass,
                    role: declaration.role,
                    sourceRefs: declaration.sourceRefs
                )
            )
        }

        let manifest = try BundleManifest(
            captureSeriesID: request.captureSeriesID,
            captureRevisionID: request.captureRevisionID,
            parentRevisionID: request.parentRevisionID,
            captureSessionIDs: request.captureSessionIDs,
            coordinateSpaceIDs: request.coordinateSpaceIDs,
            createdAtUTC: request.createdAtUTC,
            finalizedAtUTC: request.finalizedAtUTC,
            app: request.app,
            files: entries
        )
        let manifestData = try manifest.canonicalBytes()

        do {
            try manifestData.write(
                to: manifestURL,
                options: .atomic
            )
            let report = try BundleDirectoryValidator.validate(
                root: stagingDirectory,
                limits: limits
            )

            let parent = destinationDirectory
                .deletingLastPathComponent()
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )

            guard sameVolume(
                lhs: stagingDirectory,
                rhs: parent
            ) else {
                throw BundleFinalizationError
                    .crossVolumePromotionForbidden
            }

            do {
                try fileManager.moveItem(
                    at: stagingDirectory,
                    to: destinationDirectory
                )
            } catch {
                throw BundleFinalizationError.promotionFailed
            }

            return FinalizedCaptureRevision(
                directory: destinationDirectory,
                captureRevisionID: request.captureRevisionID,
                bundleDigest: report.bundleDigest,
                payloadCount: report.payloadCount
            )
        } catch {
            if fileManager.fileExists(atPath: manifestURL.path) {
                try? fileManager.removeItem(at: manifestURL)
            }
            throw error
        }
    }

    private func sameVolume(
        lhs: URL,
        rhs: URL
    ) -> Bool {
        // Fail closed: atomic rename eligibility requires positively
        // proving both paths resolve to the same volume identity. An
        // unavailable or unreadable identity is not evidence of a
        // same-volume relationship.
        guard let left = try? volumeIdentity(lhs),
              let right = try? volumeIdentity(rhs)
        else {
            return false
        }
        return left == right
    }
}
