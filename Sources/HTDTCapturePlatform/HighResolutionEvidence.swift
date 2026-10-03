import Foundation
import HTDTCaptureCore

#if os(iOS) && canImport(ARKit)
import ARKit
import AVFoundation

/// Typed outcomes for the bounded one-shot high-resolution request
/// (legacy bolph71656-ai/HTDT-Capture#275) — busy, unsupported and ARKit failure stay distinct so the
/// UI and diagnostics never conflate them.
public enum HighResolutionEvidenceError: Error, Sendable, Equatable {
    /// `recommendedVideoFormatForHighResolutionFrameCapturing` reports
    /// no usable high-resolution format for this device/configuration.
    case unsupported
    /// Another high-resolution request is already in flight; repeated
    /// taps reject rather than queue.
    case alreadyInFlight
    /// No active world-tracking configuration to request against.
    case noActiveConfiguration
    /// ARKit returned an error or no frame.
    case captureFailed(String)
}

/// The retained snapshot plus the bounded visual-profile provenance
/// that was effective when the high-resolution request was issued.
public struct HighResolutionEvidenceCapture: @unchecked Sendable {
    public let snapshot: CapturedFrameSnapshot
    /// `key=value` provenance detail recorded on the advisory note —
    /// bounded metadata only (no pixel data, no room imagery).
    public let profileDetail: String

    public init(
        snapshot: CapturedFrameSnapshot,
        profileDetail: String
    ) {
        self.snapshot = snapshot
        self.profileDetail = profileDetail
    }
}

/// legacy bolph71656-ai/HTDT-Capture#275: bounded one-shot high-resolution evidence on the shared
/// ARSession — never a second camera/AR session, at most one ARKit
/// high-resolution request in flight, encode/write deferred to the
/// caller's bounded persistence task.
@available(iOS 17.0, *)
extension SharedARSessionController {

    /// Request ONE high-resolution ARFrame and retain it as a snapshot.
    /// The returned frame's own intrinsics/resolution/exif are kept
    /// honest — nothing inherits ordinary-frame dimensions.
    ///
    /// `depthSelection` is forced to `.none`: the RGB↔depth mapping of
    /// an out-of-band high-resolution frame is not the documented
    /// ordinary `sceneDepth` mapping, so the still is visual/OCR
    /// evidence only and never becomes depth or geometry authority.
    ///
    /// - Parameter purpose: bounded request purpose recorded in
    ///   provenance (`HTDT.evidence.purpose`).
    public func captureHighResolutionEvidenceSnapshot(
        purpose: HighQualityEvidencePurpose
    ) async throws -> HighResolutionEvidenceCapture {
        guard !highResolutionRequestInFlight else {
            throw HighResolutionEvidenceError.alreadyInFlight
        }
        highResolutionRequestInFlight = true
        defer { highResolutionRequestInFlight = false }

        let worldConfiguration =
            arSession.configuration as? ARWorldTrackingConfiguration
        guard let videoFormat = worldConfiguration?.videoFormat else {
            throw HighResolutionEvidenceError.noActiveConfiguration
        }
        guard ARWorldTrackingConfiguration
            .recommendedVideoFormatForHighResolutionFrameCapturing
                != nil || videoFormat.isRecommendedForHighResolutionFrameCapturing
        else {
            throw HighResolutionEvidenceError.unsupported
        }

        // Photo settings: start from the active video format's
        // `defaultPhotoSettings` (iOS 26 photo-settings request) —
        // passed unmodified; a concrete benchmarked need is required
        // before any setting is mutated. Autofocus stays at ARKit's
        // world-tracking default; no manual tuning is introduced.
        var photoSettings: AVCapturePhotoSettings?
        if #available(iOS 26.0, *) {
            photoSettings = videoFormat.defaultPhotoSettings
        }

        let frame: ARFrame = try await withCheckedThrowingContinuation {
            continuation in
            let completion: (ARFrame?, Error?) -> Void = { frame, error in
                if let frame {
                    continuation.resume(returning: frame)
                } else {
                    continuation.resume(
                        throwing: HighResolutionEvidenceError
                            .captureFailed(
                                error?.localizedDescription
                                    ?? "no frame returned"
                            )
                    )
                }
            }
            if #available(iOS 26.0, *) {
                arSession.captureHighResolutionFrame(
                    using: photoSettings,
                    completion: completion
                )
            } else {
                arSession.captureHighResolutionFrame(
                    completion: completion
                )
            }
        }

        let resolution = videoFormat.imageResolution
        var provenance: [String: String] = [
            "HTDT.evidence.source": "high_resolution",
            "HTDT.evidence.purpose": purpose.rawValue,
            "HTDT.visual_profile.revision": "v1",
            "HTDT.visual_profile.video_format": String(
                format: "%dx%d@%dfps",
                Int(resolution.width),
                Int(resolution.height),
                Int(videoFormat.framesPerSecond)
            ),
            "HTDT.visual_profile.autofocus": "arkit_default",
            "HTDT.visual_profile.photo_settings":
                photoSettings != nil ? "default_photo_settings" : "none",
        ]
        if #available(iOS 16.0, *) {
            provenance["HTDT.visual_profile.hdr"] =
                worldConfiguration?.videoHDRAllowed == true
                ? "allowed" : "disallowed"
        }
        // The high-res frame's own dimensions land in the descriptor
        // via the snapshot — never inferred from the ordinary format.
        provenance["HTDT.visual_profile.hi_res_image_size"] = String(
            format: "%dx%d",
            CVPixelBufferGetWidth(frame.capturedImage),
            CVPixelBufferGetHeight(frame.capturedImage)
        )

        let snapshot = try ARFrameArtifactAdapter.snapshot(
            frame: frame,
            captureSessionID: context.captureSessionID,
            coordinateSpaceID: context.coordinateSpaceID,
            depthSelection: .none,
            provenanceExtras: provenance
        )

        let profileDetail = (
            provenance.map { "\($0.key)=\($0.value)" }
        ).sorted().joined(separator: " ")
        return HighResolutionEvidenceCapture(
            snapshot: snapshot,
            profileDetail: profileDetail
        )
    }
}
#endif
