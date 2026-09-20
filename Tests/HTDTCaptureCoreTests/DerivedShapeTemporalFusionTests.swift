import XCTest
@testable import HTDTCaptureCore

final class DerivedShapeTemporalFusionTests: XCTestCase {
    func testFusionAccumulatesRecentFramesAndVoxelDeduplicates() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: DerivedShapeTemporalFusionConfiguration(
                maximumFrameCount: 3,
                maximumAgeSeconds: 10,
                voxelSizeMeters: 0.10,
                maximumPointCount: 16
            )
        )

        _ = tracker.record(
            observation(
                coordinate: firstCoordinate,
                timestamp: 1,
                points: [
                    point(x: 0.02, y: 0.50, z: 0.02, ref: "old"),
                    point(x: 0.50, y: 0.50, z: 0.00, ref: "stable"),
                ]
            ),
            timestampSeconds: 1
        )

        let fused = tracker.record(
            observation(
                coordinate: firstCoordinate,
                timestamp: 2,
                points: [
                    point(x: 0.04, y: 0.52, z: 0.03, ref: "new"),
                    point(x: 1.00, y: 0.50, z: 0.00, ref: "added"),
                ]
            ),
            timestampSeconds: 2
        )

        XCTAssertEqual(fused?.points.count, 3)
        XCTAssertTrue(
            fused?.points.contains { $0.evidenceRef == "new" } == true
        )
        XCTAssertFalse(
            fused?.points.contains { $0.evidenceRef == "old" } == true
        )
        XCTAssertTrue(
            fused?.points.contains { $0.evidenceRef == "stable" } == true
        )
        XCTAssertTrue(
            fused?.points.contains { $0.evidenceRef == "added" } == true
        )
        XCTAssertEqual(fused?.observationStartSeconds, 1)
        XCTAssertEqual(fused?.observationEndSeconds, 2)
    }

    func testFusionIsBoundedByFrameCountAndAge() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: DerivedShapeTemporalFusionConfiguration(
                maximumFrameCount: 2,
                maximumAgeSeconds: 3,
                voxelSizeMeters: 0.01,
                maximumPointCount: 4
            )
        )

        for index in 0..<3 {
            _ = tracker.record(
                observation(
                    coordinate: firstCoordinate,
                    timestamp: Double(index),
                    points: [
                        point(
                            x: Double(index),
                            y: 0.5,
                            z: 0,
                            ref: "frame-" + String(index)
                        ),
                    ]
                ),
                timestampSeconds: Double(index)
            )
        }

        let bounded = tracker.fusedObservation()
        XCTAssertEqual(bounded?.points.count, 2)
        XCTAssertFalse(
            bounded?.points.contains {
                $0.evidenceRef == "frame-0"
            } == true
        )

        let expired = tracker.record(
            nil,
            timestampSeconds: 10
        )
        XCTAssertNil(expired)
    }

    func testFurnitureTargetShiftResetsInsteadOfFusingDifferentObjects() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: DerivedShapeTemporalFusionConfiguration(
                maximumFrameCount: 6,
                maximumAgeSeconds: 24,
                voxelSizeMeters: 0.05,
                maximumPointCount: 128,
                maximumObservationCenterShiftMeters: 0.65
            )
        )

        _ = tracker.record(
            observation(
                coordinate: firstCoordinate,
                timestamp: 1,
                points: [
                    point(x: -0.20, y: 0.7, z: 0.00, ref: "table-a"),
                    point(x: 0.00, y: 0.7, z: 0.20, ref: "table-b"),
                    point(x: 0.20, y: 0.7, z: 0.00, ref: "table-c"),
                    point(x: 0.00, y: 0.7, z: -0.20, ref: "table-d"),
                ]
            ),
            timestampSeconds: 1
        )

        let sameTarget = tracker.record(
            observation(
                coordinate: firstCoordinate,
                timestamp: 2,
                points: [
                    point(x: -0.14, y: 0.7, z: 0.03, ref: "table-e"),
                    point(x: 0.06, y: 0.7, z: 0.23, ref: "table-f"),
                    point(x: 0.26, y: 0.7, z: 0.03, ref: "table-g"),
                    point(x: 0.06, y: 0.7, z: -0.17, ref: "table-h"),
                ]
            ),
            timestampSeconds: 2
        )

        XCTAssertTrue(
            sameTarget?.points.contains {
                $0.evidenceRef == "table-a"
            } == true
        )
        XCTAssertTrue(
            sameTarget?.points.contains {
                $0.evidenceRef == "table-h"
            } == true
        )

        let changedTarget = tracker.record(
            observation(
                coordinate: firstCoordinate,
                timestamp: 3,
                points: [
                    point(x: 1.80, y: 0.6, z: 0.00, ref: "chair-a"),
                    point(x: 2.00, y: 0.6, z: 0.20, ref: "chair-b"),
                    point(x: 2.20, y: 0.6, z: 0.00, ref: "chair-c"),
                    point(x: 2.00, y: 0.6, z: -0.20, ref: "chair-d"),
                ]
            ),
            timestampSeconds: 3
        )

        XCTAssertEqual(
            Set(changedTarget?.points.map(\.evidenceRef) ?? []),
            Set(["chair-a", "chair-b", "chair-c", "chair-d"])
        )
        XCTAssertEqual(changedTarget?.observationStartSeconds, 3)
        XCTAssertEqual(changedTarget?.observationEndSeconds, 3)
    }

    func testCoordinateSpaceChangeResetsInsteadOfMixingAuthorities() {
        var tracker = DerivedShapeTemporalFusionTracker()

        _ = tracker.record(
            observation(
                coordinate: firstCoordinate,
                timestamp: 1,
                points: [
                    point(x: 0, y: 0.4, z: 0, ref: "first"),
                ]
            ),
            timestampSeconds: 1
        )

        let fused = tracker.record(
            observation(
                coordinate: secondCoordinate,
                timestamp: 2,
                points: [
                    point(x: 1, y: 0.4, z: 0, ref: "second"),
                ]
            ),
            timestampSeconds: 2
        )

        XCTAssertEqual(fused?.coordinateSpaceID, secondCoordinate)
        XCTAssertEqual(fused?.points.map(\.evidenceRef), ["second"])
    }

    private func observation(
        coordinate: CoordinateSpaceID,
        timestamp: Double,
        points: [DerivedObservationPoint]
    ) -> DerivedShapeObservation {
        DerivedShapeObservation(
            coordinateSpaceID: coordinate,
            points: points,
            observationStartSeconds: timestamp,
            observationEndSeconds: timestamp
        )
    }

    private func point(
        x: Double,
        y: Double,
        z: Double,
        ref: String
    ) -> DerivedObservationPoint {
        DerivedObservationPoint(
            position: DerivedPoint2D(x: x, y: z),
            evidenceRef: ref,
            evidenceKind: .sceneDepth,
            verticalPositionMeters: y
        )
    }

    private var firstCoordinate: CoordinateSpaceID {
        CoordinateSpaceID(
            rawValue: UUID(
                uuidString:
                    "10000000-0000-4000-8000-000000000101"
            )!
        )
    }

    private var secondCoordinate: CoordinateSpaceID {
        CoordinateSpaceID(
            rawValue: UUID(
                uuidString:
                    "10000000-0000-4000-8000-000000000102"
            )!
        )
    }
}
