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

    func testDepthInteriorPointsReduceToOuterBoundaryForCircleFit() {
        var points: [DerivedObservationPoint] = []

        for ringIndex in 1...5 {
            let radius = Double(ringIndex) / 5
            for index in 0..<48 {
                let angle =
                    2 * Double.pi * Double(index) / 48
                points.append(
                    DerivedObservationPoint(
                        position: DerivedPoint2D(
                            x: radius * cos(angle),
                            y: radius * sin(angle)
                        ),
                        evidenceRef:
                            "depth:\(ringIndex):\(index)",
                        evidenceKind: .sceneDepth,
                        verticalPositionMeters: 0.72
                    )
                )
            }
        }

        let observation = DerivedShapeObservation(
            coordinateSpaceID: testCoordinateSpaceID,
            points: points
        )
        let boundary =
            DerivedShapeProxyFitter.boundaryObservation(
                from: observation
            )
        let proxy = DerivedShapeProxyFitter.fit(
            observation: boundary
        )

        XCTAssertLessThan(boundary.points.count, points.count)
        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .circle)
    }

    func testRepresentativeHorizontalSliceIgnoresLegsForRoundTableFootprint() {
        var points: [DerivedObservationPoint] = []

        for index in 0..<64 {
            let angle =
                2 * Double.pi * Double(index) / 64.0
            points.append(
                DerivedObservationPoint(
                    position: DerivedPoint2D(
                        x: cos(angle),
                        y: sin(angle)
                    ),
                    evidenceRef: "top-" + String(index),
                    evidenceKind: .sceneDepth,
                    verticalPositionMeters: 0.76
                )
            )
        }

        let legCenters = [
            DerivedPoint2D(x: -0.55, y: -0.55),
            DerivedPoint2D(x: 0.55, y: -0.55),
            DerivedPoint2D(x: -0.55, y: 0.55),
            DerivedPoint2D(x: 0.55, y: 0.55),
        ]
        var legIndex = 0
        for center in legCenters {
            for sample in 0..<10 {
                points.append(
                    DerivedObservationPoint(
                        position: center,
                        evidenceRef:
                            "leg-"
                            + String(legIndex)
                            + "-"
                            + String(sample),
                        evidenceKind: .sceneDepth,
                        verticalPositionMeters:
                            0.08 + 0.06 * Double(sample)
                    )
                )
            }
            legIndex += 1
        }

        let input = DerivedShapeObservation(
            coordinateSpaceID: testCoordinateSpaceID,
            points: points
        )
        let slice =
            DerivedShapeProxyFitter
                .representativeHorizontalSliceObservation(
                    from: input
                )
        let boundary =
            DerivedShapeProxyFitter.boundaryObservation(
                from: slice
            )
        let proxy = DerivedShapeProxyFitter.fit(
            observation: boundary
        )

        XCTAssertLessThan(slice.points.count, points.count)
        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .circle)
    }

    func testMultiLevelHorizontalProfilesPreserveStackedFootprints() {
        var points: [DerivedObservationPoint] = []

        func appendRectangle(
            halfWidth: Double,
            halfDepth: Double,
            y: Double,
            prefix: String
        ) {
            let samplesPerEdge = 20
            let corners = [
                DerivedPoint2D(x: -halfWidth, y: -halfDepth),
                DerivedPoint2D(x: halfWidth, y: -halfDepth),
                DerivedPoint2D(x: halfWidth, y: halfDepth),
                DerivedPoint2D(x: -halfWidth, y: halfDepth),
            ]
            for edge in corners.indices {
                let a = corners[edge]
                let b = corners[(edge + 1) % corners.count]
                for sample in 0..<samplesPerEdge {
                    let t =
                        Double(sample) / Double(samplesPerEdge)
                    points.append(
                        DerivedObservationPoint(
                            position: DerivedPoint2D(
                                x: a.x + (b.x - a.x) * t,
                                y: a.y + (b.y - a.y) * t
                            ),
                            evidenceRef:
                                prefix
                                + "-"
                                + String(edge)
                                + "-"
                                + String(sample),
                            evidenceKind: .sceneDepth,
                            verticalPositionMeters: y
                        )
                    )
                }
            }
        }

        appendRectangle(
            halfWidth: 1.0,
            halfDepth: 0.80,
            y: 0.40,
            prefix: "lower"
        )
        appendRectangle(
            halfWidth: 0.55,
            halfDepth: 0.42,
            y: 0.80,
            prefix: "upper"
        )

        let input = DerivedShapeObservation(
            coordinateSpaceID: testCoordinateSpaceID,
            points: points
        )
        let profiles =
            DerivedShapeProxyFitter.horizontalProfileObservations(
                from: input
            )

        XCTAssertEqual(profiles.count, 2)

        let widths = profiles.map { profile -> Double in
            let xs = profile.points.map(\.position.x)
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }.sorted()

        XCTAssertLessThan(widths[0], 1.20)
        XCTAssertGreaterThan(widths[1], 1.90)

        for profile in profiles {
            let proxy = DerivedShapeProxyFitter.fit(
                observation:
                    DerivedShapeProxyFitter.boundaryObservation(
                        from: profile
                    )
            )
            XCTAssertNotNil(proxy.selected)
        }
    }

    func testBroadMultiViewRoundEvidenceResolvesAsCircle() {
        let points = (0..<90).map { index -> DerivedPoint2D in
            let angle =
                -5 * Double.pi / 6
                + (5 * Double.pi / 3)
                    * Double(index) / 89.0
            let radius =
                1.0
                + 0.025 * sin(5 * angle)
                + 0.010 * cos(11 * angle)
            return DerivedPoint2D(
                x: radius * cos(angle),
                y: radius * sin(angle)
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .circle)
        XCTAssertGreaterThan(
            proxy.selected?.metrics.angularSupport ?? 0,
            0.78
        )
    }

    func testWellSupportedImperfectCircleCanBeatFlexiblePolygon() {
        let points = (0..<96).map { index -> DerivedPoint2D in
            let angle =
                2 * Double.pi * Double(index) / 96.0
            let radius =
                1.0
                + 0.035 * sin(3 * angle)
                + 0.012 * cos(7 * angle)
            return DerivedPoint2D(
                x: radius * cos(angle),
                y: radius * sin(angle)
            )
        }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(points)
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .circle)
        XCTAssertGreaterThan(
            proxy.selected?.metrics.angularSupport ?? 0,
            0.85
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

    func testNonOrthogonalQuadrilateralSelectsPolygon() {
        let vertices = [
            DerivedPoint2D(x: -1.20, y: -0.55),
            DerivedPoint2D(x: 1.05, y: -0.82),
            DerivedPoint2D(x: 0.72, y: 0.88),
            DerivedPoint2D(x: -0.82, y: 0.62),
        ]
        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(
                samplePolygon(vertices, samplesPerEdge: 18)
            )
        )

        XCTAssertEqual(proxy.resolution, .resolved)
        XCTAssertEqual(proxy.selected?.kind, .polygon)
        guard case let .polygon(polygon)? =
            proxy.selected?.geometry
        else {
            return XCTFail("Expected polygon geometry")
        }
        XCTAssertGreaterThanOrEqual(polygon.vertices.count, 4)
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

    func testAdversarialPointSetNeverEmitsSelfIntersectingPolygon() {
        // Review reproducer: greedy nearest-edge insertion used to
        // produce a ring with intersecting non-adjacent edges for this
        // point set.
        let adversarial = [
            DerivedPoint2D(x: 1.43, y: 1.94),
            DerivedPoint2D(x: 0.79, y: 3.72),
            DerivedPoint2D(x: 0.17, y: 2.01),
            DerivedPoint2D(x: 0.46, y: 2.77),
            DerivedPoint2D(x: 0.17, y: 0.83),
            DerivedPoint2D(x: 1.85, y: 1.18),
            DerivedPoint2D(x: 3.53, y: 2.27),
            DerivedPoint2D(x: 1.26, y: 0.13),
            DerivedPoint2D(x: 2.50, y: 0.46),
            DerivedPoint2D(x: 3.05, y: 0.46),
        ]

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(adversarial)
        )

        for candidate in proxy.candidates {
            guard case let .polygon(polygon) =
                candidate.geometry
            else {
                continue
            }
            XCTAssertTrue(
                ringIsSimple(
                    polygon.vertices.map(\.position)
                ),
                "candidate polygon ring must be simple"
            )
        }
        if case let .polygon(selected)? =
            proxy.selected?.geometry
        {
            XCTAssertTrue(
                ringIsSimple(
                    selected.vertices.map(\.position)
                ),
                "selected polygon ring must be simple"
            )
        }
    }

    func testRotatedAdversarialPointSetStaysSimple() {
        let adversarial = [
            DerivedPoint2D(x: 1.43, y: 1.94),
            DerivedPoint2D(x: 0.79, y: 3.72),
            DerivedPoint2D(x: 0.17, y: 2.01),
            DerivedPoint2D(x: 0.46, y: 2.77),
            DerivedPoint2D(x: 0.17, y: 0.83),
            DerivedPoint2D(x: 1.85, y: 1.18),
            DerivedPoint2D(x: 3.53, y: 2.27),
            DerivedPoint2D(x: 1.26, y: 0.13),
            DerivedPoint2D(x: 2.50, y: 0.46),
            DerivedPoint2D(x: 3.05, y: 0.46),
        ].map { rotate($0, radians: 0.9) }

        let proxy = DerivedShapeProxyFitter.fit(
            observation: observation(adversarial)
        )

        for candidate in proxy.candidates {
            guard case let .polygon(polygon) =
                candidate.geometry
            else {
                continue
            }
            XCTAssertTrue(
                ringIsSimple(
                    polygon.vertices.map(\.position)
                )
            )
        }
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

    /// Strict simple-ring check used to verify emitted polygons never
    /// self-intersect: no two non-adjacent edges may share any point.
    private func ringIsSimple(
        _ ring: [DerivedPoint2D]
    ) -> Bool {
        let count = ring.count
        guard count >= 3 else {
            return false
        }
        for i in 0..<count {
            let a1 = ring[i]
            let a2 = ring[(i + 1) % count]
            for j in (i + 1)..<count
            where (i + 1) % count != j
                && (j + 1) % count != i
            {
                let b1 = ring[j]
                let b2 = ring[(j + 1) % count]
                if testSegmentsShareAnyPoint(
                    a1, a2, b1, b2
                ) {
                    return false
                }
            }
        }
        return true
    }

    private func testSegmentsShareAnyPoint(
        _ p1: DerivedPoint2D,
        _ p2: DerivedPoint2D,
        _ q1: DerivedPoint2D,
        _ q2: DerivedPoint2D
    ) -> Bool {
        func cross3(
            _ a: DerivedPoint2D,
            _ b: DerivedPoint2D,
            _ c: DerivedPoint2D
        ) -> Double {
            (b.x - a.x) * (c.y - a.y)
                - (b.y - a.y) * (c.x - a.x)
        }
        func onSegment(
            _ p: DerivedPoint2D,
            _ a: DerivedPoint2D,
            _ b: DerivedPoint2D
        ) -> Bool {
            let eps = 0.000_000_001
            return abs(cross3(a, b, p)) <= 0.000_000_1
                && p.x >= min(a.x, b.x) - eps
                && p.x <= max(a.x, b.x) + eps
                && p.y >= min(a.y, b.y) - eps
                && p.y <= max(a.y, b.y) + eps
        }

        let d1 = cross3(q1, q2, p1)
        let d2 = cross3(q1, q2, p2)
        let d3 = cross3(p1, p2, q1)
        let d4 = cross3(p1, p2, q2)

        if (
            (d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)
        ) && (
            (d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)
        ) {
            return true
        }

        return onSegment(p1, q1, q2)
            || onSegment(p2, q1, q2)
            || onSegment(q1, p1, p2)
            || onSegment(q2, p1, p2)
    }
}
