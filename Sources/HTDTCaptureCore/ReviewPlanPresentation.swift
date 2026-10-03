import Foundation

/// Review/task state a plan marker carries (issue bolph71656-ai/HTDT-Capture#367): separate from
/// the marker's geometric category so color can support — never
/// replace — the shape grammar. Maps onto the frozen
/// `CaptureSemanticStatus` vocabulary for rendering.
public enum PlanMarkerReviewStatus: String, Sendable, Equatable,
    CaseIterable
{
    /// Ordinary geometry — no review badge.
    case nominal
    /// Enumerated but not yet reviewed (e.g. an unreviewed opening
    /// candidate).
    case pending
    /// Operator-confirmed.
    case confirmed
    /// Needs follow-up (needs more scanning, a blocking issue ref, or
    /// an outstanding required task target).
    case needsAttention
    /// Reviewed and intentionally excluded.
    case intentionallySkipped

    public var semanticStatus: CaptureSemanticStatus {
        switch self {
        case .nominal: return .ready
        case .pending: return .pending
        case .confirmed: return .verified
        case .needsAttention: return .needsReview
        case .intentionallySkipped: return .skipped
        }
    }
}

/// Composition rules that turn the committed review workspace into
/// plan markers (issue bolph71656-ai/HTDT-Capture#367): annotations, opening candidates, and the
/// room reference frame overlay the RoomPlan-derived base plan. Pure
/// geometry — no SwiftUI — so selection hit-testing and the
/// accessibility summary stay unit-testable.
public enum ReviewPlanPresentation {

    /// Marker kind for a committed annotation entity. Unknown/custom
    /// types collapse to the generic entity square — never to a fake
    /// semantic glyph.
    public static func markerKind(
        for type: AnnotationEntityType
    ) -> RoomPlanPreviewModel.PlanMarker.Kind {
        switch type {
        case .speaker, .subwoofer:
            return .speaker
        case .seat:
            return .seat
        case .projectionScreen:
            return .screen
        case .projector:
            return .projector
        case .display:
            return .display
        case .listeningPosition, .measurementPoint:
            return .measurement
        case .referencePoint:
            return .referencePoint
        case .acousticTreatment, .equipmentRack, .custom:
            return .genericEntity
        }
    }

    /// Marker review status for an opening candidate's disposition.
    public static func reviewStatus(
        for disposition: RoomOpeningDisposition
    ) -> PlanMarkerReviewStatus {
        switch disposition {
        case .unreviewed:
            return .pending
        case .confirmed:
            return .confirmed
        case .needsMoreScanning:
            return .needsAttention
        case .intentionallyIgnored:
            return .intentionallySkipped
        }
    }

    /// Marker kind for an opening candidate's declared kind — hvac
    /// grilles, undercuts, penetrations and `other` all draw as the
    /// generic opening bracket rather than fake a door/window.
    public static func markerKind(
        for kind: RoomOpeningKind
    ) -> RoomPlanPreviewModel.PlanMarker.Kind {
        switch kind {
        case .door: return .door
        case .window: return .window
        case .opening, .hvacGrille, .transferGrille, .doorUndercut,
             .servicePenetration, .other:
            return .opening
        }
    }

    /// Overlay markers derived from committed workspace state:
    /// annotation entities, opening-review candidates and the room
    /// reference frame. Everything is linked back to its record so
    /// selection syncs with the workspace lists both ways.
    public static func overlayMarkers(
        for model: CaptureReviewWorkspaceModel
    ) -> [RoomPlanPreviewModel.PlanMarker] {
        var markers: [RoomPlanPreviewModel.PlanMarker] = []

        for entity in model.annotations {
            let position = entity.worldFromAnnotation.translationWorld
            var dirX: Double? = nil
            var dirZ: Double? = nil
            if let orientation = entity.orientation {
                let front = entity.worldFromAnnotation.applying(
                    toDirection: Float3(
                        orientation.frontAxisLocal.x,
                        orientation.frontAxisLocal.y,
                        orientation.frontAxisLocal.z
                    )
                )
                let length = sqrt(
                    Double(front.x * front.x + front.z * front.z)
                )
                if length > 0.001 {
                    dirX = Double(front.x) / length
                    dirZ = Double(front.z) / length
                }
            }
            markers.append(
                .init(
                    kind: markerKind(for: entity.type),
                    x: Double(position.x),
                    z: Double(position.z),
                    dirX: dirX,
                    dirZ: dirZ,
                    label: entity.label,
                    identifier: "entity:\(entity.entityID)",
                    linkedItemID: entity.entityID.description,
                    selectable: true,
                    reviewStatus: .nominal
                )
            )
        }

        if let openings = model.openingReview?.openings {
            for opening in openings {
                guard let center = opening.centerMeters,
                      center.isFinite
                else { continue }
                markers.append(
                    .init(
                        kind: markerKind(for: opening.kind),
                        x: center.x,
                        z: center.z,
                        label: nil,
                        // `sourceRef` IS the dedup key: RoomPlan-derived
                        // candidates share it with the raw plan marker,
                        // so the reviewed candidate replaces the raw
                        // dot rather than double-drawing (legacy bolph71656-ai/HTDT-Capture#367).
                        identifier: opening.sourceRef,
                        linkedItemID: opening.openingID.description,
                        selectable: true,
                        reviewStatus: reviewStatus(
                            for: opening.disposition
                        )
                    )
                )
            }
        }

        // Subject-point field-note anchors (issue bolph71656-ai/HTDT-Capture#421): a
        // restrained marker per anchored note — viewpoint anchors
        // never render, and one note contributes exactly one pin.
        for note in model.fieldNotes {
            guard let position = note.spatialPosition,
                  position.anchorKind == .subjectPoint
            else { continue }
            markers.append(
                .init(
                    kind: .revisitFlag,
                    x: position.pointMeters.x,
                    z: position.pointMeters.z,
                    label: String(note.text.prefix(24)),
                    identifier: "field_note:\(note.noteID)",
                    linkedItemID: note.noteID.description,
                    selectable: true,
                    reviewStatus: note.needsAttention
                        ? .needsAttention : .nominal
                )
            )
        }

        if let frame = model.roomReferenceFrame {
            markers.append(
                .init(
                    kind: .roomFrameOrigin,
                    x: frame.originMeters.x,
                    z: frame.originMeters.z,
                    label: nil,
                    identifier: "roomframe:origin",
                    selectable: false,
                    reviewStatus: .confirmed
                )
            )
            let front = frame.frontDirection
            let length = sqrt(front.x * front.x + front.z * front.z)
            guard length > 0.001 else {
                return markers
            }
            markers.append(
                .init(
                    kind: .roomFrameFront,
                    x: frame.originMeters.x,
                    z: frame.originMeters.z,
                    dirX: front.x / length,
                    dirZ: front.z / length,
                    label: nil,
                    identifier: "roomframe:front",
                    selectable: false,
                    reviewStatus: .confirmed
                )
            )
        }

        return markers
    }

    /// Every marker — base plan plus overlays — the surface renders.
    /// Overlay markers win on identical identifiers so a RoomPlan
    /// candidate upgraded into a reviewed opening never double-draws:
    /// the reviewed opening replaces the raw candidate marker.
    public static func composedMarkers(
        base: [RoomPlanPreviewModel.PlanMarker],
        overlay: [RoomPlanPreviewModel.PlanMarker]
    ) -> [RoomPlanPreviewModel.PlanMarker] {
        let overlayIDs = Set(overlay.compactMap(\.identifier))
        return base.filter {
            guard let identifier = $0.identifier else { return true }
            return !overlayIDs.contains(identifier)
        } + overlay
    }

    /// Selectable markers within `tolerance` (meters, plan space) of a
    /// tap point, nearest first — the disambiguation ordering the
    /// surface presents when several markers overlap (issue bolph71656-ai/HTDT-Capture#367).
    public static func hitTest(
        markers: [RoomPlanPreviewModel.PlanMarker],
        at point: (x: Double, z: Double),
        tolerance: Double
    ) -> [RoomPlanPreviewModel.PlanMarker] {
        markers
            .filter { marker in
                guard marker.selectable else { return false }
                let dx = marker.x - point.x
                let dz = marker.z - point.z
                return dx * dx + dz * dz <= tolerance * tolerance
            }
            .sorted { a, b in
                let da = (a.x - point.x) * (a.x - point.x)
                    + (a.z - point.z) * (a.z - point.z)
                let db = (b.x - point.x) * (b.x - point.x)
                    + (b.z - point.z) * (b.z - point.z)
                return da < db
            }
    }

    /// The VoiceOver summary of the plan surface (issue bolph71656-ai/HTDT-Capture#367 RVIS-80):
    /// counts + front-direction confirmation, one sentence, never raw
    /// IDs. Returns nil when nothing is drawn.
    public static func accessibilitySummary(
        wallCount: Int,
        doorCount: Int,
        windowCount: Int,
        openingCount: Int,
        markerCount: Int,
        frontConfirmed: Bool
    ) -> String? {
        var parts: [String] = []
        if wallCount > 0 {
            parts.append(
                String(
                    format: String(localized: "%lld walls"),
                    wallCount
                )
            )
        }
        if doorCount > 0 {
            parts.append(
                String(
                    format: String(localized: "%lld doors"),
                    doorCount
                )
            )
        }
        if windowCount > 0 {
            parts.append(
                String(
                    format: String(localized: "%lld windows"),
                    windowCount
                )
            )
        }
        if openingCount > 0 {
            parts.append(
                String(
                    format: String(localized: "%lld openings"),
                    openingCount
                )
            )
        }
        if markerCount > 0 {
            parts.append(
                String(
                    format: String(localized: "%lld items"),
                    markerCount
                )
            )
        }
        guard !parts.isEmpty else { return nil }
        var summary = String(localized: "Room plan. ")
            + parts.joined(separator: ", ") + "."
        summary += frontConfirmed
            ? String(localized: " Front direction confirmed.")
            : String(localized: " Front direction not set.")
        return summary
    }

}
