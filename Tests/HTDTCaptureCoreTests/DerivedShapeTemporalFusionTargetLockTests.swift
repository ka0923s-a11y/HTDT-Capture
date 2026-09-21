import XCTest
@testable import HTDTCaptureCore

final class DerivedShapeTemporalFusionTargetLockTests: XCTestCase {
    func testChainedSubThresholdShiftsCannotBridgeTableToChair() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: targetLockConfiguration(
                maximumFrameCount: 6
            )
        )

        // A slow pan moves the observed center 0.5 m per step — below
        // the 0.65 m step bound — while the table-to-chair drift totals
        // 1.5 m. The anchor lock must reject the chain instead of
        // letting the fused target walk onto the adjacent object.
        _ = tracker.record(
            observation(
                centerX: 0.0,
                refPrefix: "table",
                timestamp: 1
            ),
            timestampSeconds: 1
        )

        let withinAnchor = tracker.record(
            observation(
                centerX: 0.5,
                refPrefix: "edge",
                timestamp: 2
            ),
            timestampSeconds: 2
        )

        // A sub-threshold step still fuses while it remains inside the
        // anchor radius.
        XCTAssertTrue(
            withinAnchor?.points.contains {
                $0.evidenceRef == "table-a"
            } == true
        )
        XCTAssertTrue(
            withinAnchor?.points.contains {
                $0.evidenceRef == "edge-a"
            } == true
        )

        _ = tracker.record(
            observation(
                centerX: 1.0,
                refPrefix: "mid",
                timestamp: 3
            ),
            timestampSeconds: 3
        )
        let fused = tracker.record(
            observation(
                centerX: 1.5,
                refPrefix: "chair",
                timestamp: 4
            ),
            timestampSeconds: 4
        )

        let refs = Set(fused?.points.map(\.evidenceRef) ?? [])
        XCTAssertEqual(
            refs,
            Set(
                [
                    "mid-a", "mid-b", "mid-c", "mid-d",
                    "chair-a", "chair-b", "chair-c", "chair-d",
                ]
            )
        )
    }

    func testChainedSubThresholdShiftsCannotBridgeSofaToChair() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: targetLockConfiguration(
                maximumFrameCount: 6
            )
        )

        // Sofa-to-chair drift in 0.3 m steps: every adjacent shift is
        // below the bound, but the 0.9 m cumulative drift from the
        // anchored sofa center must split the fusion.
        _ = tracker.record(
            observation(
                centerX: 0.0,
                refPrefix: "sofa",
                timestamp: 1
            ),
            timestampSeconds: 1
        )
        _ = tracker.record(
            observation(
                centerX: 0.3,
                refPrefix: "near",
                timestamp: 2
            ),
            timestampSeconds: 2
        )
        let withinRadius = tracker.record(
            observation(
                centerX: 0.6,
                refPrefix: "far",
                timestamp: 3
            ),
            timestampSeconds: 3
        )

        // While the cumulative drift stays inside the anchor radius the
        // window still fuses the extended object's views.
        XCTAssertTrue(
            withinRadius?.points.contains {
                $0.evidenceRef == "sofa-a"
            } == true
        )
        XCTAssertTrue(
            withinRadius?.points.contains {
                $0.evidenceRef == "far-a"
            } == true
        )

        let fused = tracker.record(
            observation(
                centerX: 0.9,
                refPrefix: "chair",
                timestamp: 4
            ),
            timestampSeconds: 4
        )

        XCTAssertEqual(
            Set(fused?.points.map(\.evidenceRef) ?? []),
            Set(
                [
                    "chair-a", "chair-b",
                    "chair-c", "chair-d",
                ]
            )
        )
    }

    func testMultiViewObservationsAroundAnchorStillFuse() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: targetLockConfiguration(
                maximumFrameCount: 6
            )
        )

        // Views of one extended object can land on opposite sides of the
        // anchored center: consecutive centers here are 0.75 m apart
        // even though both stay inside the anchor radius, so the lock --
        // not step-to-step distance -- decides fusion.
        let centers: [(Double, String)] = [
            (0.0, "front"),
            (0.45, "right"),
            (-0.30, "left"),
            (0.20, "back"),
        ]

        var fused: DerivedShapeObservation?
        for (index, entry) in centers.enumerated() {
            fused = tracker.record(
                observation(
                    centerX: entry.0,
                    refPrefix: entry.1,
                    timestamp: Double(index) + 1
                ),
                timestampSeconds: Double(index) + 1
            )
        }

        let refs = Set(fused?.points.map(\.evidenceRef) ?? [])
        for prefix in ["front", "right", "left", "back"] {
            XCTAssertTrue(
                refs.contains(prefix + "-a"),
                "expected fused points for " + prefix
            )
        }
    }

    func testAnchorLockSurvivesWindowEviction() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: targetLockConfiguration(
                maximumFrameCount: 3
            )
        )

        // All centers stay inside the anchor radius, so the bounded
        // window evicts the oldest frame -- but not the anchor itself.
        let centers: [(Double, String)] = [
            (0.0, "first"),
            (0.4, "second"),
            (-0.4, "third"),
            (0.5, "fourth"),
        ]
        for (index, entry) in centers.enumerated() {
            _ = tracker.record(
                observation(
                    centerX: entry.0,
                    refPrefix: entry.1,
                    timestamp: Double(index) + 1
                ),
                timestampSeconds: Double(index) + 1
            )
        }

        // The anchor frame has been evicted from the window, yet the
        // lock still rejects a 0.7 m target even though it is only
        // 0.2 m from the previous frame.
        let fused = tracker.record(
            observation(
                centerX: 0.7,
                refPrefix: "drifted",
                timestamp: 5
            ),
            timestampSeconds: 5
        )

        XCTAssertEqual(
            Set(fused?.points.map(\.evidenceRef) ?? []),
            Set(
                [
                    "drifted-a", "drifted-b",
                    "drifted-c", "drifted-d",
                ]
            )
        )
    }

    func testAbruptTargetSwitchStillResets() {
        var tracker = DerivedShapeTemporalFusionTracker(
            configuration: targetLockConfiguration(
                maximumFrameCount: 6
            )
        )

        _ = tracker.record(
            observation(
                centerX: 0.0,
                refPrefix: "table",
                timestamp: 1
            ),
            timestampSeconds: 1
        )
        let fused = tracker.record(
            observation(
                centerX: 2.0,
                refPrefix: "chair",
                timestamp: 2
            ),
            timestampSeconds: 2
        )

        XCTAssertEqual(
            Set(fused?.points.map(\.evidenceRef) ?? []),
            Set(
                [
                    "chair-a", "chair-b",
                    "chair-c", "chair-d",
                ]
            )
        )
        XCTAssertEqual(fused?.observationStartSeconds, 2)
        XCTAssertEqual(fused?.observationEndSeconds, 2)
    }

    private func targetLockConfiguration(
        maximumFrameCount: Int
    ) -> DerivedShapeTemporalFusionConfiguration {
        DerivedShapeTemporalFusionConfiguration(
            maximumFrameCount: maximumFrameCount,
            maximumAgeSeconds: 24,
            voxelSizeMeters: 0.05,
            maximumPointCount: 128,
            maximumObservationCenterShiftMeters: 0.65
        )
    }

    // A four-point cross whose median ground-plane center is
    // (centerX, 0), matching the production furniture-cluster shape.
    private func observation(
        centerX: Double,
        refPrefix: String,
        timestamp: Double
    ) -> DerivedShapeObservation {
        DerivedShapeObservation(
            coordinateSpaceID: firstCoordinate,
            points: [
                point(
                    x: centerX - 0.20,
                    y: 0.7,
                    z: 0.00,
                    ref: refPrefix + "-a"
                ),
                point(
                    x: centerX,
                    y: 0.7,
                    z: 0.20,
                    ref: refPrefix + "-b"
                ),
                point(
                    x: centerX + 0.20,
                    y: 0.7,
                    z: 0.00,
                    ref: refPrefix + "-c"
                ),
                point(
                    x: centerX,
                    y: 0.7,
                    z: -0.20,
                    ref: refPrefix + "-d"
                ),
            ],
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
}
