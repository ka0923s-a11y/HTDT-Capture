import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit) && canImport(RoomPlan)
import RoomPlan

/// iOS-only RoomPlan support for derived 3D export (issue bolph71656-ai/HTDT-Capture#306):
/// decodes the bundle's processed `CapturedRoom` for the box-mesh
/// writers, and produces the USDZ convenience artifact through
/// RoomPlan's own `CapturedRoom.export(to:exportOptions:)`.
/// Everything reads from the finalized bundle — never the live session.
@available(iOS 17.0, *)
public enum DerivedRoomPlanExportSupport {
    /// Whether the bundle carries a processed RoomPlan payload (and
    /// thus supports USDZ and bounding-box exports).
    public static func isAvailable(
        manifest: BundleManifest,
        bundleDirectory: URL
    ) -> Bool {
        let path = RoomPlanEvidenceArtifactBuilder.processedPath
        guard manifest.files.contains(where: { $0.path == path })
        else { return false }
        return FileManager.default.fileExists(
            atPath: url(bundleDirectory, path).path
        )
    }

    /// Reads the declared processed payload bytes, integrity-checking
    /// them against the manifest's recorded digest.
    public static func processedRoomData(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) throws -> Data {
        let path = RoomPlanEvidenceArtifactBuilder.processedPath
        guard let entry = manifest.files.first(where: {
            $0.path == path
        }) else {
            throw DerivedExportError.sourceUnavailable(
                reason:
                    "The bundle declares no \(path) — RoomPlan-derived exports require a capture that ran RoomPlan to completion"
            )
        }
        let fileURL = url(bundleDirectory, path)
        guard let data = try? Data(contentsOf: fileURL) else {
            throw DerivedExportError.malformedSource(
                reason: "\(path) is declared but unreadable"
            )
        }
        let digest = EvidenceIntegrity.sha256(of: data)
        guard digest == entry.sha256 else {
            throw DerivedExportError.malformedSource(
                reason:
                    "\(path) digest mismatch — the recorded payload is not the finalized bytes"
            )
        }
        return data
    }

    /// Decodes `CapturedRoom` and flattens its objects + surfaces into
    /// bindable records for the box-mesh builders.
    public static func bindableObjects(
        bundleDirectory: URL,
        manifest: BundleManifest
    ) throws -> [RoomPlanBindableObject] {
        let data = try processedRoomData(
            bundleDirectory: bundleDirectory,
            manifest: manifest
        )
        let objects =
            SharedARSessionController
                .roomPlanBindableObjects(fromProcessedData: data)
        guard !objects.isEmpty else {
            throw DerivedExportError.malformedSource(
                reason:
                    "roomplan/captured-room.json could not be decoded into a CapturedRoom"
            )
        }
        return objects
    }

    /// RoomPlan's own USDZ emission (.parametric — the survey-friendly
    /// primitive representation) into `destination`.
    public static func writeUSDZ(
        bundleDirectory: URL,
        manifest: BundleManifest,
        to destination: URL
    ) throws {
        let data = try processedRoomData(
            bundleDirectory: bundleDirectory,
            manifest: manifest
        )
        guard let room = try? RoomPlanArtifactEncoder.makeJSONDecoder()
            .decode(
                CapturedRoom.self,
                from: data
            )
        else {
            throw DerivedExportError.malformedSource(
                reason:
                    "roomplan/captured-room.json could not be decoded into a CapturedRoom"
            )
        }
        do {
            try room.export(
                to: destination,
                exportOptions: .parametric
            )
        } catch {
            throw DerivedExportError.writeFailed(
                reason:
                    "RoomPlan USDZ export failed: \(error.localizedDescription)"
            )
        }
    }

    private static func url(
        _ directory: URL,
        _ path: String
    ) -> URL {
        path.split(separator: "/").reduce(directory) {
            $0.appendingPathComponent(
                String($1),
                isDirectory: false
            )
        }
    }
}
#endif
