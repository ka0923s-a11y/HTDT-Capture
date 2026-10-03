#if os(iOS) && canImport(ARKit)
import ARKit
import Foundation
import HTDTCaptureCore

/// Converts `ARObjectAnchor` delegate callbacks into
/// `ReferenceObjectPoseObservation` records (legacy bolph71656-ai/HTDT-Capture#268).
///
/// The adapter writes sensor truth only: the anchor's identifier,
/// its reported world-space pose, the matched object resolved by the
/// caller against the shipped manifest, and `ARTrackable.isTracked`
/// when the running OS exposes it (iOS 27+). `isTracked` is nil on
/// earlier releases — never a fabricated confidence scalar or a
/// guessed tracked state.
public enum ARReferenceObjectObservationAdapter {
    /// Builds the observation for one anchor. `role` is the session
    /// role the asset was configured with — it decides the persisted
    /// `observation_mode`; `kind` mirrors the delegate callback that
    /// delivered the anchor. Returns nil when ARKit's transform fails
    /// the rigid-pose invariant (`Matrix4x4F` rejects non-rigid
    /// values — an impossible pose is dropped loudly, never clamped
    /// into plausibility).
    public static func observation(
        for anchor: ARObjectAnchor,
        asset: ReferenceObjectAsset,
        role: ReferenceObjectAssetRole,
        kind: MeshAnchorLifecycleKind,
        captureSessionID: CaptureSessionID,
        coordinateSpaceID: CoordinateSpaceID,
        sessionTimestampSeconds: Double
    ) -> ReferenceObjectPoseObservation? {
        guard
            let matrix = try? matrix4x4F(anchor.transform)
        else {
            return nil
        }
        return try? ReferenceObjectPoseObservation(
            captureSessionID: captureSessionID,
            coordinateSpaceID: coordinateSpaceID,
            sessionTimestampSeconds: sessionTimestampSeconds,
            arAnchorID: anchor.identifier,
            referenceObjectID: asset.assetID.rawValue,
            referenceObjectRevision: asset.revision,
            referenceObjectDigestSHA256: asset.artifactSHA256,
            tWorldFromReferenceObject: matrix,
            observationMode: role == .tracking
                ? .tracking : .detection,
            lifecycleEvent: kind.lifecycleEvent,
            // `ARTrackable` exists in earlier SDKs but only iOS 27's
            // `ARObjectAnchor` conforms — the conditional cast keeps
            // the field nil on older systems rather than fabricating.
            isCurrentlyTracked:
                (anchor as AnyObject as? ARTrackable)?.isTracked,
            markerToEquipmentTransformID:
                asset.markerToEquipment?.transformID
        )
    }

    /// The matched manifest asset for an anchor, by ARKit's
    /// `referenceObject.name` ↔ `arkitObjectName` convention. Nil
    /// means the anchor did not come from the shipped catalog —
    /// impossible when only manifest assets were configured, so the
    /// caller drops it loudly rather than recording an unprovable
    /// match.
    public static func matchedAsset(
        for anchor: ARObjectAnchor,
        manifest: ReferenceObjectAssetManifest
    ) -> ReferenceObjectAsset? {
        guard let name = anchor.referenceObject.name else {
            return nil
        }
        return manifest.asset(arkitObjectName: name)
    }

    private static func matrix4x4F(
        _ value: simd_float4x4
    ) throws -> Matrix4x4F {
        try Matrix4x4F(values: [
            value.columns.0.x, value.columns.0.y,
            value.columns.0.z, value.columns.0.w,
            value.columns.1.x, value.columns.1.y,
            value.columns.1.z, value.columns.1.w,
            value.columns.2.x, value.columns.2.y,
            value.columns.2.z, value.columns.2.w,
            value.columns.3.x, value.columns.3.y,
            value.columns.3.z, value.columns.3.w,
        ])
    }
}

private extension MeshAnchorLifecycleKind {
    /// The observation lifecycle record a delegate callback kind maps
    /// onto; tracked-loss/resume flips are derived from `isTracked`
    /// changes inside the store's buffer, not here.
    var lifecycleEvent: ReferenceObjectLifecycleEvent {
        switch self {
        case .added: return .added
        case .updated: return .updated
        case .removed: return .removed
        }
    }
}
#endif
