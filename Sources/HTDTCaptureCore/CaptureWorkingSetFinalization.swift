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
}
