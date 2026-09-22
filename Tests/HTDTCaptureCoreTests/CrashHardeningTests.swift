import XCTest
@testable import HTDTCaptureCore

/// Regression coverage for the crash-hardening pass: `.isFinite`
/// filters only reject NaN/±inf, so finite-but-extreme decoded values
/// (e.g. `1e300`) still reached `Int(floor(...))` conversions and
/// `try!` transform compositions and trapped there.
final class CrashHardeningTests: XCTestCase {

    // MARK: floorToIntClamped

    func testFloorToIntClampedMapsNonFiniteToZero() {
        XCTAssertEqual(floorToIntClamped(.nan), 0)
        XCTAssertEqual(floorToIntClamped(.infinity), 0)
        XCTAssertEqual(floorToIntClamped(-.infinity), 0)
    }

    func testFloorToIntClampedSaturatesOutOfRange() {
        XCTAssertEqual(floorToIntClamped(1e300), Int.max)
        XCTAssertEqual(floorToIntClamped(-1e300), Int.min)
        XCTAssertEqual(
            floorToIntClamped(Double(Int.max)),
            Int.max
        )
    }

    func testFloorToIntClampedFloorsOrdinaryValues() {
        XCTAssertEqual(floorToIntClamped(2.9), 2)
        XCTAssertEqual(floorToIntClamped(-2.1), -3)
        XCTAssertEqual(floorToIntClamped(0), 0)
    }

    // MARK: SpatialScanCoverageTracker — extreme decoded coordinates

    func testCoverageTrackerSurvivesExtremeSurfacePoint() {
        var tracker = SpatialScanCoverageTracker()
        let summary = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [
                    SpatialCoveragePoint3D(x: 1e300, y: 0, z: 1e300)
                ]
            )
        )
        XCTAssertEqual(summary.regions.count, 1)
    }

    func testCoverageTrackerSurvivesCameraBeyondIntRange() {
        var tracker = SpatialScanCoverageTracker()
        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: 0,
                cameraZ: 0,
                points: [point(1, -1)]
            )
        )
        // The camera position is finite-checked but not magnitude-
        // checked: 1e300 passes `.isFinite`, then the start-relative
        // difference still fits a Double and used to trap `Int(floor())`
        // in the accessibility summary's camera cell key.
        let summary = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 1e300,
                cameraZ: 1e300,
                points: [point(1, -1)]
            )
        )
        let accessibility = SpatialCoverageAccessibilitySummary(
            coverage: summary
        )
        XCTAssertNotNil(accessibility.cameraRegion)
    }

    func testCoverageTrackerSurvivesNonFiniteFreeExtremes() {
        var tracker = SpatialScanCoverageTracker()
        _ = tracker.record(
            sample(
                timestamp: 1,
                cameraX: -1e300,
                cameraZ: -1e300,
                points: [point(0, 0)]
            )
        )
        // `1e300 - (-1e300)` overflows to +inf inside `relativePoint`;
        // the point itself passes the `.isFinite` filter.
        let summary = tracker.record(
            sample(
                timestamp: 2,
                cameraX: 0,
                cameraZ: 0,
                points: [
                    SpatialCoveragePoint3D(x: 1e300, y: 0, z: 1e300)
                ]
            )
        )
        XCTAssertFalse(summary.regions.isEmpty)
    }

    // MARK: ScanDirectionOctant — non-finite azimuth

    func testOctantDefaultsFrontOnNonFiniteAzimuth() {
        XCTAssertEqual(
            ScanDirectionOctant(azimuthRadians: .nan),
            .front
        )
        XCTAssertEqual(
            ScanDirectionOctant(azimuthRadians: .infinity),
            .front
        )
        XCTAssertEqual(
            ScanDirectionOctant(azimuthRadians: -.infinity),
            .front
        )
    }

    func testOctantBucketsFiniteAzimuthUnchanged() {
        XCTAssertEqual(ScanDirectionOctant(azimuthRadians: 0), .front)
        XCTAssertEqual(
            ScanDirectionOctant(azimuthRadians: .pi / 2),
            .right
        )
        XCTAssertEqual(
            ScanDirectionOctant(azimuthRadians: -.pi / 2),
            .left
        )
        // Finite-but-huge still wraps deterministically.
        _ = ScanDirectionOctant(azimuthRadians: 1e300)
    }

    // MARK: TargetedObjectScanTracker — non-finite camera delta

    func testTargetedScanTreatsNonFiniteCameraAsOutOfRange() {
        var tracker = TargetedObjectScanTracker(
            target: ScanTargetAnchor(x: 0, y: 0, z: 0, radiusMeters: 1)
        )
        let status = tracker.record(
            cameraX: .nan,
            cameraZ: 0,
            timestampSeconds: 1,
            trackingState: .normal
        )
        XCTAssertTrue(status.outOfRange)
        XCTAssertEqual(status.observedBucketCount, 0)
    }

    func testTargetedScanStillAccumulatesFiniteSamples() {
        var tracker = TargetedObjectScanTracker(
            target: ScanTargetAnchor(x: 0, y: 0, z: 0, radiusMeters: 1)
        )
        _ = tracker.record(
            cameraX: 2,
            cameraZ: 0,
            timestampSeconds: 1,
            trackingState: .normal
        )
        let status = tracker.record(
            cameraX: 2,
            cameraZ: 0,
            timestampSeconds: 2,
            trackingState: .normal
        )
        XCTAssertFalse(status.outOfRange)
        XCTAssertEqual(status.observedBucketCount, 1)
    }

    // MARK: CrossRevisionScaledTransform — extreme decoded scales

    func testScaledTransformInverseThrowsOnDenormalScale() throws {
        let transform = try CrossRevisionScaledTransform(
            rigid: .identity,
            uniformScale: 1e-300
        )
        // `1/s` overflows Double → used to trap under `try!`.
        XCTAssertThrowsError(try transform.inverted())
    }

    func testScaledTransformCompositionThrowsOnOverflow() throws {
        let a = try CrossRevisionScaledTransform(
            rigid: .identity,
            uniformScale: 1e300
        )
        let b = try CrossRevisionScaledTransform(
            rigid: .identity,
            uniformScale: 1e300
        )
        // `s1·s2 = 1e600 → inf` → used to trap under `try!`.
        XCTAssertThrowsError(try a.concatenated(then: b))
    }

    func testScaledTransformRoundTripsOrdinaryScale() throws {
        let transform = try CrossRevisionScaledTransform(
            rigid: .identity,
            uniformScale: 2
        )
        let inverted = try transform.inverted()
        XCTAssertEqual(inverted.uniformScale, 0.5, accuracy: 1e-9)
        let roundTrip = try transform.concatenated(then: inverted)
        XCTAssertEqual(
            roundTrip.uniformScale,
            1,
            accuracy: 1e-9
        )
    }

    func testRegistrationGraphSkipsUninvertibleEdge() throws {
        let source = CaptureRevisionID()
        let target = CaptureRevisionID()
        let registration = try CrossRevisionRegistration(
            sourceRevisionID: source,
            sourceCoordinateSpaceID: CoordinateSpaceID(),
            targetRevisionID: target,
            targetCoordinateSpaceID: CoordinateSpaceID(),
            mechanism: .sharedFieldDatum,
            correspondences: [],
            residuals: [],
            rmsMeters: 0,
            maxResidualMeters: 0,
            scalePolicy: .uniformScalePermitted,
            uniformScale: 1e-300,
            targetFromSource: .identity,
            acceptedAtUTC: "2026-01-01T00:00:00Z"
        )
        let graph = CrossRevisionRegistrationGraph(
            registrations: [registration]
        )
        // Backward traversal must invert `1e-300` → overflows → the
        // edge is unusable, so resolution fails closed as `.unresolved`
        // instead of trapping.
        XCTAssertEqual(
            graph.resolve(from: target, to: source),
            .unresolved
        )
        // Forward still resolves — the stored transform itself is valid.
        if case .direct = graph.resolve(from: source, to: target) {
        } else {
            XCTFail("expected a direct path forward")
        }
    }

    func testRegistrationGraphSkipsOverflowingComposition() throws {
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let c = CaptureRevisionID()
        func edge(
            from source: CaptureRevisionID,
            to target: CaptureRevisionID
        ) throws -> CrossRevisionRegistration {
            try CrossRevisionRegistration(
                sourceRevisionID: source,
                sourceCoordinateSpaceID: CoordinateSpaceID(),
                targetRevisionID: target,
                targetCoordinateSpaceID: CoordinateSpaceID(),
                mechanism: .sharedFieldDatum,
                correspondences: [],
                residuals: [],
                rmsMeters: 0,
                maxResidualMeters: 0,
                scalePolicy: .uniformScalePermitted,
                uniformScale: 1e300,
                targetFromSource: .identity,
                acceptedAtUTC: "2026-01-01T00:00:00Z"
            )
        }
        let graph = CrossRevisionRegistrationGraph(
            registrations: [try edge(from: a, to: b), try edge(from: b, to: c)]
        )
        // a→b is fine (1e300); composing it with b→c overflows → the
        // chain is unusable → `.unresolved`, never a trap.
        XCTAssertEqual(graph.resolve(from: a, to: c), .unresolved)
    }

    // MARK: Matrix4x4F.invertedRigid — overflowed rotation of translation

    func testInvertedRigidThrowsOnOverflowedTranslation() throws {
        // 45° rotation about z: the rotated translation column is
        // 0.707·(tx + ty) — with max-Float translations that sum
        // overflows to inf and used to trap under `try!`.
        let s = Float(1 / 2.squareRoot())
        let m = Float.greatestFiniteMagnitude
        let matrix = try Matrix4x4F(values: [
            s, s, 0, 0,
            -s, s, 0, 0,
            0, 0, 1, 0,
            m, m, m, 1,
        ])
        XCTAssertThrowsError(try matrix.invertedRigid())
    }

    func testInvertedRigidStillInvertsOrdinaryTransform() throws {
        let matrix = try Matrix4x4F(values: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            3, -2, 5, 1,
        ])
        let inverted = try matrix.invertedRigid()
        XCTAssertEqual(inverted.values[12], -3, accuracy: 0.0001)
        XCTAssertEqual(inverted.values[13], 2, accuracy: 0.0001)
        XCTAssertEqual(inverted.values[14], -5, accuracy: 0.0001)
    }

    // MARK: helpers

    private func point(
        _ x: Double,
        _ z: Double
    ) -> SpatialCoveragePoint3D {
        SpatialCoveragePoint3D(x: x, y: 0, z: z)
    }

    private func sample(
        timestamp: Double,
        cameraX: Double,
        cameraZ: Double,
        tracking: TrackingQualityState = .normal,
        points: [SpatialCoveragePoint3D]
    ) -> SpatialCoverageSample {
        SpatialCoverageSample(
            sessionTimestampSeconds: timestamp,
            cameraPositionWorld: SpatialCoveragePoint3D(
                x: cameraX,
                y: 1.5,
                z: cameraZ
            ),
            cameraYawRadians: 0,
            trackingState: tracking,
            hasSceneDepth: true,
            meshAvailability: MeshAvailabilityDiagnostic(
                sceneReconstructionSupported: true,
                sceneReconstructionEnabled: true,
                activeMeshAnchorCount: 1
            ),
            surfaceEvidenceSource: .mesh,
            surfacePointsWorld: points
        )
    }
}
