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
