import XCTest
@testable import HTDTCaptureCore

final class DerivedShapeProxyTests: XCTestCase {
    func testPerfectCircleSelectsCircle() {
        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(
                circlePoints(
                    center: DerivedPoint2D(x: 0.2, y: -0.3),
                    radius: 1.0,
                    count: 72
                )
            )
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .circle)
        XCTAssertLessThan(
            proxy.selected?.metrics.normalizedResidual ?? 1,
            0.01
        )
        XCTAssertGreaterThan(
            proxy.selected?.metrics.angularSupport ?? 0,
            0.90
        )
    }

    func testPartialCircleArcRemainsUnresolved() {
        let points = (0..<72).map { index -> DerivedPoint2D in
            let t =
                -Double.pi / 3
                + (2 * Double.pi / 3)
                    * Double(index) / 71
            return DerivedPoint2D(
                x: cos(t),
                y: sin(t)
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertEqual(
            proxy.resolution,
            .insufficientEvidence
        )
        XCTAssertNil(proxy.selected)
        XCTAssertTrue(
            proxy.candidates.contains {
                $0.kind == .circle
                    && ($0.metrics.angularSupport ?? 1) < 0.70
            }
        )
    }

    func testEllipseSelectsEllipse() {
        let points = (0..<80).map { index -> DerivedPoint2D in
            let t = 2 * Double.pi * Double(index) / 80
            let u = 1.4 * cos(t)
            let v = 0.65 * sin(t)
            return rotate(
                DerivedPoint2D(x: u, y: v),
                radians: 0.48
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .ellipse)
        XCTAssertLessThan(
            proxy.selected?.metrics.normalizedResidual ?? 1,
            0.02
        )
        XCTAssertGreaterThan(
            proxy.selected?.metrics.angularSupport ?? 0,
            0.90
        )
    }

    func testNearSquareRoundedShapeDoesNotResolveAsCircle() {
        let points = (0..<96).map { index -> DerivedPoint2D in
            let t = 2 * Double.pi * Double(index) / 96
            let c = cos(t)
            let s = sin(t)
            let exponent = 4.0
            return DerivedPoint2D(
                x: c >= 0
                    ? pow(abs(c), 2 / exponent)
                    : -pow(abs(c), 2 / exponent),
                y: s >= 0
                    ? pow(abs(s), 2 / exponent)
                    : -pow(abs(s), 2 / exponent)
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertNotEqual(proxy.selected?.kind, .circle)
        XCTAssertNotEqual(proxy.selected?.kind, .ellipse)
    }

    func testRotatedRectangleSelectsOrientedRectangle() {
        let base = [
            DerivedPoint2D(x: -1.1, y: -0.55),
            DerivedPoint2D(x: 1.1, y: -0.55),
            DerivedPoint2D(x: 1.1, y: 0.55),
            DerivedPoint2D(x: -1.1, y: 0.55),
        ]
        let points = samplePolygon(
            base.map { rotate($0, radians: 0.61) },
            samplesPerEdge: 14
        )

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(
            proxy.selected?.kind,
            .orientedRectangle
        )
        XCTAssertLessThan(
            proxy.selected?.metrics.normalizedResidual ?? 1,
            0.01
        )
    }

    func testPentagonSelectsPolygon() {
        let vertices = (0..<5).map { index -> DerivedPoint2D in
            let angle =
                -Double.pi / 2
                + 2 * Double.pi * Double(index) / 5
            return DerivedPoint2D(
                x: cos(angle),
                y: sin(angle)
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(
                samplePolygon(vertices, samplesPerEdge: 12)
            )
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .polygon)
        guard case let .polygon(polygon)? =
            proxy.selected?.geometry
        else {
            return XCTFail("Expected polygon geometry")
        }
        XCTAssertGreaterThanOrEqual(polygon.vertices.count, 5)
        XCTAssertTrue(
            polygon.vertices.allSatisfy {
                !$0.supportEvidenceRefs.isEmpty
            }
        )
    }

    func testLShapeRemainsConcavePolygon() {
        let vertices = [
            DerivedPoint2D(x: 0, y: 0),
            DerivedPoint2D(x: 2, y: 0),
            DerivedPoint2D(x: 2, y: 0.8),
            DerivedPoint2D(x: 0.8, y: 0.8),
            DerivedPoint2D(x: 0.8, y: 2),
            DerivedPoint2D(x: 0, y: 2),
        ]

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(
                samplePolygon(vertices, samplesPerEdge: 12)
            )
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .polygon)
        guard case let .polygon(polygon)? =
            proxy.selected?.geometry
        else {
            return XCTFail("Expected polygon geometry")
        }
        XCTAssertTrue(polygon.isConcave)
        XCTAssertEqual(
            polygon.concavityResolution,
            .resolvedConcave
        )
    }

    func testSparseConcavityFallsBackToConvexAndMarksUnresolved() {
        let sparse = [
            DerivedPoint2D(x: 0, y: 0),
            DerivedPoint2D(x: 2, y: 0),
            DerivedPoint2D(x: 2, y: 0.8),
            DerivedPoint2D(x: 0.8, y: 0.8),
            DerivedPoint2D(x: 0.8, y: 2),
            DerivedPoint2D(x: 0, y: 2),
            DerivedPoint2D(x: 0.02, y: 0.02),
            DerivedPoint2D(x: 1.98, y: 0.02),
        ]
        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(sparse)
        )

        guard let polygonCandidate =
            proxy.candidates.first(where: {
                $0.kind == .polygon
            }),
            case let .polygon(polygon) =
                polygonCandidate.geometry
        else {
            return XCTFail("Expected polygon candidate")
        }

        XCTAssertFalse(polygon.isConcave)
        XCTAssertEqual(
            polygon.concavityResolution,
            .unresolved
        )
    }

    func testNoisyCircleStillSelectsCircleWithBoundedResidual() {
        let points = (0..<96).map { index -> DerivedPoint2D in
            let angle =
                2 * Double.pi * Double(index) / 96
            let deterministicNoise =
                0.018 * sin(Double(index) * 7.0)
            let radius = 1.0 + deterministicNoise
            return DerivedPoint2D(
                x: radius * cos(angle),
                y: radius * sin(angle)
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertEqual(proxy.selected?.kind, .circle)
        XCTAssertLessThan(
            proxy.selected?.metrics.normalizedResidual ?? 1,
            0.03
        )
        XCTAssertGreaterThan(
            proxy.selected?.metrics.angularSupport ?? 0,
            0.90
        )
        XCTAssertTrue(
            proxy.candidates.allSatisfy {
                $0.metrics.normalizedResidual.isFinite
                    && $0.metrics.supportScore.isFinite
                    && $0.metrics.fitScore.isFinite
            }
        )
    }

    func testInsufficientPointsDoNotForceRectangle() {
        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation([
                DerivedPoint2D(x: 0, y: 0),
                DerivedPoint2D(x: 1, y: 0),
                DerivedPoint2D(x: 1, y: 1),
                DerivedPoint2D(x: 0, y: 1),
                DerivedPoint2D(x: 0.5, y: 0.5),
            ])
        )

        XCTAssertEqual(
            proxy.resolution,
            .insufficientEvidence
        )
        XCTAssertNil(proxy.selected)
    }

    func testCircleSquareMixtureIsAmbiguousInsteadOfRectangleFallback() {
        var points = circlePoints(
            center: DerivedPoint2D(x: 0, y: 0),
            radius: 1,
            count: 48
        )
        points.append(
            contentsOf: samplePolygon(
                [
                    DerivedPoint2D(x: -0.92, y: -0.92),
                    DerivedPoint2D(x: 0.92, y: -0.92),
                    DerivedPoint2D(x: 0.92, y: 0.92),
                    DerivedPoint2D(x: -0.92, y: 0.92),
                ],
                samplesPerEdge: 12
            )
        )

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertNil(proxy.selected)
        XCTAssertEqual(
            proxy.resolution,
            .ambiguousEvidence
        )
    }

    func testNonOrthogonalWallChainPreservesArbitraryHeading() {
        let vertices = [
            DerivedPoint2D(x: 0, y: 0),
            DerivedPoint2D(x: 2.2, y: 0),
            DerivedPoint2D(x: 3.2, y: 1.7),
            DerivedPoint2D(x: 0.6, y: 2.2),
        ]
        let observation = observation(
            samplePolygon(vertices, samplesPerEdge: 10)
        )

        guard let wall =
            DerivedShapeProxyFitter.wallChain(
                observation: observation
            )
        else {
            return XCTFail("Expected wall chain")
        }

        let snapshot = DerivedShapePreviewSnapshot(
            wallChain: wall,
            disagreements:
                DerivedShapeDisagreementEvaluator.evaluate(
                    objectProxies: [],
                    wallChain: wall
                )
        )

        XCTAssertGreaterThanOrEqual(wall.vertices.count, 4)
        XCTAssertTrue(
            wall.vertices.allSatisfy {
                !$0.supportEvidenceRefs.isEmpty
            }
        )
        XCTAssertTrue(
            snapshot.disagreements.contains(.wallHeading)
        )
    }

    func testOutputIsDeterministic() {
        let points = (0..<72).map { index -> DerivedPoint2D in
            let t = 2 * Double.pi * Double(index) / 72
            return DerivedPoint2D(
                x: 1.25 * cos(t),
                y: 0.75 * sin(t)
            )
        }
        let input = observation(points)

        XCTAssertEqual(
            DerivedShapeProxyFitter.fit(observation: input),
            DerivedShapeProxyFitter.fit(observation: input)
        )
    }

    func testMeshExtractionUsesBoundaryEdgesAndBoundsPointCount()
        throws
    {
        let coordinateSpaceID = testCoordinateSpaceID
        let geometry = try MeshGeometryPayload(
            vertices: [
                Float3(-1, 0, -1),
                Float3(1, 0, -1),
                Float3(1, 0, 1),
                Float3(-1, 0, 1),
                Float3(0, 0, 0),
            ],
            triangleIndices: [
                0, 1, 4,
                1, 2, 4,
                2, 3, 4,
                3, 0, 4,
            ],
            faceClassifications: [4, 4, 4, 4]
        )
        let snapshot = MeshAnchorSnapshot(
            anchorID: UUID(
                uuidString:
                    "00000000-0000-4000-8000-000000000222"
            )!,
            captureSessionID: CaptureSessionID(
                rawValue: UUID(
                    uuidString:
                        "00000000-0000-4000-8000-000000000333"
                )!
            ),
            coordinateSpaceID: coordinateSpaceID,
            worldFromAnchor: .identity,
            sessionTimestampSeconds: 4.5,
            geometry: geometry
        )

        let extracted =
            try MeshDerivedShapeObservationBuilder.build(
                snapshots: [snapshot],
                allowedFaceClassifications: [4],
                voxelSizeMeters: 0.01,
                maxPoints: 16
            )

        XCTAssertEqual(extracted?.points.count, 4)
        XCTAssertFalse(
            extracted?.points.contains {
                abs($0.position.x) < 0.001
                    && abs($0.position.y) < 0.001
            } ?? true
        )
        XCTAssertEqual(
            extracted?.observationStartSeconds,
            4.5
        )
        XCTAssertEqual(
            extracted?.coordinateSpaceID,
            coordinateSpaceID
        )
    }

    private var testCoordinateSpaceID: CoordinateSpaceID {
        CoordinateSpaceID(
            rawValue: UUID(
                uuidString:
                    "00000000-0000-4000-8000-000000000111"
            )!
        )
    }

    private func observation(
        _ points: [DerivedPoint2D]
    ) -> DerivedShapeObservation {
        DerivedShapeObservation(
            coordinateSpaceID: testCoordinateSpaceID,
            points: points.enumerated().map { index, point in
                DerivedObservationPoint(
                    position: point,
                    evidenceRef: "synthetic:" + String(index),
                    evidenceKind: .spatialObservation
                )
            },
            observationStartSeconds: 1.0,
            observationEndSeconds: 2.0
        )
    }

    private func circlePoints(
        center: DerivedPoint2D,
        radius: Double,
        count: Int
    ) -> [DerivedPoint2D] {
        (0..<count).map { index in
            let angle =
                2 * Double.pi * Double(index)
                / Double(count)
            return DerivedPoint2D(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }
    }

    private func samplePolygon(
        _ vertices: [DerivedPoint2D],
        samplesPerEdge: Int
    ) -> [DerivedPoint2D] {
        var points: [DerivedPoint2D] = []
        for index in vertices.indices {
            let a = vertices[index]
            let b = vertices[(index + 1) % vertices.count]
            for sample in 0..<samplesPerEdge {
                let t =
                    Double(sample) / Double(samplesPerEdge)
                points.append(
                    DerivedPoint2D(
                        x: a.x + (b.x - a.x) * t,
                        y: a.y + (b.y - a.y) * t
                    )
                )
            }
        }
        return points
    }

    private func rotate(
        _ point: DerivedPoint2D,
        radians: Double
    ) -> DerivedPoint2D {
        let c = cos(radians)
        let s = sin(radians)
        return DerivedPoint2D(
            x: c * point.x - s * point.y,
            y: s * point.x + c * point.y
        )
    }
}
