import Foundation

public enum CaptureWorkingSetFinalizationError:
    Error,
    Sendable,
    Equatable
{
    case qualityNotReady
    case integrityAssertionMissing
    case missingCaptureSessionAuthority
    case missingCoordinateSpaceAuthority
    case qualityPayloadMissing
}

public enum CaptureWorkingSetFinalizationRequestBuilder {
    public static func build(
        snapshot: CaptureWorkingSetSnapshot,
        qualityReport: CaptureQualityReport,
        app: BundleAppIdentity,
        finalizedAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) throws -> BundleFinalizationRequest {
        guard qualityReport.readyForHTDTIngestion else {
            throw CaptureWorkingSetFinalizationError
                .qualityNotReady
        }
        guard qualityReport.integrityStatus == .pass else {
            throw CaptureWorkingSetFinalizationError
                .integrityAssertionMissing
        }
        guard !snapshot.captureSessionIDs.isEmpty else {
            throw CaptureWorkingSetFinalizationError
                .missingCaptureSessionAuthority
        }
        guard !snapshot.coordinateSpaceIDs.isEmpty else {
            throw CaptureWorkingSetFinalizationError
                .missingCoordinateSpaceAuthority
        }
        guard snapshot.payloadDeclarations.contains(where: {
            $0.path == "quality/capture-quality.json"
        }) else {
            throw CaptureWorkingSetFinalizationError
                .qualityPayloadMissing
        }

        return BundleFinalizationRequest(
            captureSeriesID: snapshot.identity.captureSeriesID,
            captureRevisionID: snapshot.identity.captureRevisionID,
            parentRevisionID: snapshot.identity.parentRevisionID,
            captureSessionIDs: snapshot.captureSessionIDs,
            coordinateSpaceIDs: snapshot.coordinateSpaceIDs,
            createdAtUTC: snapshot.identity.createdAtUTC,
            finalizedAtUTC: finalizedAtUTC,
            app: app,
            payloads: snapshot.payloadDeclarations,
            qualityReport: qualityReport
        )
    }

    /// Builds a promotion request directly from a sealed working set
    /// (issue bolph71656-ai/HTDT-Capture#180). The sealed snapshot and quality report are the
    /// exact state `sealForFinalization` verified after draining
    /// in-flight writes, so the request can never describe a different
    /// working set than the one the seal froze.
    public static func build(
        sealed: SealedWorkingSet,
        app: BundleAppIdentity,
        finalizedAtUTC: String = BundleTimestamp.utcString(
            from: Date()
        )
    ) throws -> BundleFinalizationRequest {
        try build(
            snapshot: sealed.snapshot,
            qualityReport: sealed.qualityReport,
            app: app,
            finalizedAtUTC: finalizedAtUTC
        )
    }
}
