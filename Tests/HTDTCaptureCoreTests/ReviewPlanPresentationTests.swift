import Foundation
import Testing
@testable import HTDTCaptureCore

/// Issue #367: the review-plan overlay maps committed workspace
/// records onto plan markers with stable dedup identifiers, nearest-
/// first hit-testing, and a VoiceOver summary.
struct ReviewPlanPresentationTests {

    private let spaceID = CoordinateSpaceID()

    private func marker(
        kind: RoomPlanPreviewModel.PlanMarker.Kind = .object,
        x: Double = 0,
        z: Double = 0,
        identifier: String? = nil,
        selectable: Bool = true,
        reviewStatus: PlanMarkerReviewStatus = .nominal
    ) -> RoomPlanPreviewModel.PlanMarker {
        .init(
            kind: kind,
            x: x,
            z: z,
            identifier: identifier,
            selectable: selectable,
            reviewStatus: reviewStatus
        )
    }

    private func makeEntity(
        type: AnnotationEntityType = .speaker,
        label: String = "Left main",
        x: Float = 1,
        z: Float = 2
    ) throws -> CaptureAnnotationEntity {
        let orientation: OrientationAxes? =
            type == .speaker
                ? try OrientationAxes(
                    frontAxisLocal: .unit(0, 0, -1),
                    upAxisLocal: .unit(0, 1, 0)
                )
                : nil
        return try CaptureAnnotationEntity(
            type: type,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: try Matrix4x4F(values: [
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                x, 0, z, 1,
            ]),
            referencePointSemantics:
                ReferencePointSemanticsCatalog.forType(type),
            label: label,
            verificationState: .userAttested,
            placement: PlacementProvenance(method: .manualNumeric),
            orientation: orientation,
            channelRole: type == .speaker
                ? ChannelRole(rawValue: "L") : nil
        )
    }

    private func workspace(
        annotations: [CaptureAnnotationEntity] = [],
        roomReferenceFrame: RoomReferenceFrameDocument? = nil
    ) -> CaptureReviewWorkspaceModel {
        CaptureReviewWorkspaceModel(
            captureRevisionID: CaptureRevisionID(),
            coordinateSpaceID: spaceID,
            roomMetadata: nil,
            planPreview: nil,
            evidenceItems: [],
            annotations: annotations,
            measurements: [],
            openingReview: nil,
            roomReferenceFrame: roomReferenceFrame,
            qualityReport: nil,
            readOnly: false,
            spatialCaptureSealed: false,
            issues: []
        )
    }

    // MARK: - Shape grammar

    @Test func entityMarkerKinds() {
        #expect(
            ReviewPlanPresentation.markerKind(for: .speaker) == .speaker
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .subwoofer) == .speaker
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .seat) == .seat
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .projectionScreen)
                == .screen
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .projector)
                == .projector
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .display) == .display
        )
        #expect(
            ReviewPlanPresentation.markerKind(
                for: .measurementPoint
            ) == .measurement
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .referencePoint)
                == .referencePoint
        )
        // Custom/unknown collapse to the generic square — never a
        // fake semantic glyph.
        #expect(
            ReviewPlanPresentation.markerKind(for: .custom)
                == .genericEntity
        )
    }

    @Test func openingMarkerKinds() {
        #expect(
            ReviewPlanPresentation.markerKind(for: .door) == .door
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .window) == .window
        )
        // HVAC/undercut/penetration/other draw as the generic
        // opening bracket.
        #expect(
            ReviewPlanPresentation.markerKind(for: .hvacGrille)
                == .opening
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .doorUndercut)
                == .opening
        )
        #expect(
            ReviewPlanPresentation.markerKind(for: .other) == .opening
        )
    }

    @Test func openingReviewStatuses() {
        #expect(
            ReviewPlanPresentation.reviewStatus(for: .unreviewed)
                == .pending
        )
        #expect(
            ReviewPlanPresentation.reviewStatus(for: .confirmed)
                == .confirmed
        )
        #expect(
            ReviewPlanPresentation.reviewStatus(for: .needsMoreScanning)
                == .needsAttention
        )
        #expect(
            ReviewPlanPresentation.reviewStatus(
                for: .intentionallyIgnored
            ) == .intentionallySkipped
        )
        // The semantic vocabulary stays frozen — review state maps
        // onto it, never extends it.
        #expect(
            PlanMarkerReviewStatus.needsAttention.semanticStatus
                == .needsReview
        )
        #expect(
            PlanMarkerReviewStatus.confirmed.semanticStatus == .verified
        )
    }

    // MARK: - Overlay markers

    @Test func entityOverlaysLinkBackToRecord() throws {
        let entity = try makeEntity()
        let markers = ReviewPlanPresentation.overlayMarkers(
            for: workspace(annotations: [entity])
        )
        #expect(markers.count == 1)
        let marker = try #require(markers.first)
        #expect(marker.kind == .speaker)
        #expect(marker.identifier == "entity:\(entity.entityID)")
        #expect(
            marker.linkedItemID == entity.entityID.description
        )
        #expect(marker.label == "Left main")
        #expect(marker.selectable)
        #expect(marker.x == 1)
        #expect(marker.z == 2)
        // Speaker orientation projects onto the plan as a unit
        // facing vector.
        let dirX = try #require(marker.dirX)
        let dirZ = try #require(marker.dirZ)
        #expect(dirX == 0)
        #expect(dirZ == -1)
    }

    @Test func roomFrameOverlaysAreNotSelectable() throws {
        let frame = try RoomReferenceFrameDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: spaceID,
            originMeters: WorldPoint3D(x: 1, y: 0, z: 1),
            frontDirection: WorldPoint3D(x: 0, y: 0, z: -4),
            confirmedAtUTC: "2026-09-22T01:02:03Z"
        )
        let markers = ReviewPlanPresentation.overlayMarkers(
            for: workspace(roomReferenceFrame: frame)
        )
        #expect(markers.count == 2)
        let origin = markers[0]
        let front = markers[1]
        #expect(origin.kind == .roomFrameOrigin)
        #expect(origin.identifier == "roomframe:origin")
        #expect(front.kind == .roomFrameFront)
        #expect(front.identifier == "roomframe:front")
        #expect(!origin.selectable)
        #expect(!front.selectable)
        // The front arrow keeps the normalized direction.
        #expect(front.dirZ == -1)
    }

    // MARK: - Composition / dedup

    @Test func overlayReplacesBaseOnSharedIdentifier() {
        let base = [
            marker(
                x: 0, z: 0,
                identifier: "roomplan:door:aaaa"
            ),
            marker(x: 5, z: 5, identifier: "roomplan:door:bbbb"),
            marker(x: 9, z: 9, identifier: nil),
        ]
        let overlay = [
            marker(
                x: 0, z: 0,
                identifier: "roomplan:door:aaaa",
                reviewStatus: .confirmed
            ),
        ]
        let composed = ReviewPlanPresentation.composedMarkers(
            base: base,
            overlay: overlay
        )
        #expect(composed.count == 3)
        // The reviewed opening replaced the raw RoomPlan candidate —
        // it never double-draws.
        let kept = composed.filter {
            $0.identifier == "roomplan:door:aaaa"
        }
        #expect(kept.count == 1)
        #expect(kept.first?.reviewStatus == .confirmed)
        #expect(
            composed.contains { $0.identifier == "roomplan:door:bbbb" }
        )
    }

    // MARK: - Hit-testing

    @Test func hitTestOrdersNearestFirst() {
        let markers = [
            marker(x: 2.0, z: 0, identifier: "far"),
            marker(x: 0.5, z: 0, identifier: "near"),
            marker(x: 50, z: 50, identifier: "outside"),
        ]
        let hits = ReviewPlanPresentation.hitTest(
            markers: markers,
            at: (x: 0, z: 0),
            tolerance: 5
        )
        #expect(hits.count == 2)
        #expect(hits.first?.identifier == "near")
        #expect(hits.last?.identifier == "far")
    }

    @Test func hitTestSkipsNonSelectable() {
        let markers = [
            marker(
                x: 0, z: 0,
                identifier: "frame",
                selectable: false
            ),
            marker(x: 1, z: 0, identifier: "pickable"),
        ]
        let hits = ReviewPlanPresentation.hitTest(
            markers: markers,
            at: (x: 0, z: 0),
            tolerance: 5
        )
        #expect(hits.count == 1)
        #expect(hits.first?.identifier == "pickable")
    }

    // MARK: - Accessibility summary

    @Test func accessibilitySummaryCounts() {
        let summary = ReviewPlanPresentation.accessibilitySummary(
            wallCount: 4,
            doorCount: 1,
            windowCount: 2,
            openingCount: 1,
            markerCount: 6,
            frontConfirmed: true
        )
        #expect(summary != nil)
        #expect(summary?.contains("4 walls") == true)
        #expect(summary?.contains("1 door") == true)
        #expect(summary?.contains("2 windows") == true)
        #expect(summary?.contains("1 opening") == true)
        #expect(summary?.contains("6 items") == true)
    }

    @Test func accessibilitySummaryEmptyIsNil() {
        #expect(
            ReviewPlanPresentation.accessibilitySummary(
                wallCount: 0,
                doorCount: 0,
                windowCount: 0,
                openingCount: 0,
                markerCount: 0,
                frontConfirmed: false
            ) == nil
        )
    }
}
