import XCTest
@testable import HTDTCaptureCore

final class DerivedSupportPreviewTests: XCTestCase {
    func testTabletopWithFourVisibleLegsSeparatesSupports() {
        let analysis = analyze(
            body: bodyGrid(
                xValues: strideValues(-0.8, 0.8, 0.2),
                zValues: strideValues(-0.5, 0.5, 0.2),
                yValues: [0.74]
            ),
            supports: legs(
                centers: [
                    (-0.68, -0.38),
                    (-0.68, 0.38),
                    (0.68, -0.38),
                    (0.68, 0.38),
                ],
                yValues: strideValues(0.02, 0.68, 0.08)
            )
        )

        XCTAssertEqual(analysis.resolution, .separatedSupports)
        XCTAssertEqual(analysis.supports.count, 4)
        XCTAssertTrue(analysis.supports.allSatisfy { $0.kind == .leg })
        XCTAssertTrue(analysis.preservesOpenLowerVolume)
    }

    func testTabletopWithThreeVisibleLegsDoesNotInventFourth() {
        let analysis = analyze(
            body: bodyGrid(
                xValues: strideValues(-0.8, 0.8, 0.2),
                zValues: strideValues(-0.5, 0.5, 0.2),
                yValues: [0.74]
            ),
            supports: legs(
                centers: [
                    (-0.68, -0.38),
                    (-0.68, 0.38),
                    (0.68, -0.38),
                ],
                yValues: strideValues(0.02, 0.68, 0.08)
            )
        )

        XCTAssertEqual(analysis.supports.count, 3)
        XCTAssertFalse(
            analysis.supports.contains {
                abs($0.center.x - 0.68) < 0.05
                    && abs($0.center.y - 0.38) < 0.05
            }
        )
    }

    func testPedestalTableProducesSinglePedestalSupport() {
        var pedestal: [(Double, Double, Double)] = []
        let ys = strideValues(0.02, 0.66, 0.08)
        for y in ys {
            for angleIndex in 0..<8 {
                let angle =
                    2 * Double.pi * Double(angleIndex) / 8
                pedestal.append(
                    (
                        0.17 * cos(angle),
                        y,
                        0.17 * sin(angle)
                    )
                )
            }
        }

        let analysis = analyze(
            body: bodyGrid(
                xValues: strideValues(-0.7, 0.7, 0.2),
                zValues: strideValues(-0.7, 0.7, 0.2),
                yValues: [0.72]
            ),
            supports: pedestal
        )

        XCTAssertEqual(analysis.supports.count, 1)
        XCTAssertEqual(analysis.supports.first?.kind, .pedestal)
        XCTAssertEqual(analysis.resolution, .separatedSupports)
    }

    func testSolidCabinetReachingFloorCanRemainSolid() {
        let cabinet = bodyGrid(
            xValues: strideValues(-0.5, 0.5, 0.2),
            zValues: strideValues(-0.35, 0.35, 0.2),
            yValues: strideValues(0.02, 0.98, 0.08)
        )

        let analysis = analyze(body: cabinet, supports: [])

        XCTAssertEqual(analysis.resolution, .solidToFloor)
        XCTAssertEqual(analysis.lowerVolumeState, .solidToFloor)
        XCTAssertTrue(analysis.supports.isEmpty)
    }

    func testSofaBodyWithShortSupportsPreservesGap() {
        let body = bodyGrid(
            xValues: strideValues(-0.9, 0.9, 0.2),
            zValues: strideValues(-0.4, 0.4, 0.2),
            yValues: strideValues(0.18, 0.66, 0.08)
        )
        let support = legs(
            centers: [
                (-0.75, -0.3),
                (-0.75, 0.3),
                (0.75, -0.3),
                (0.75, 0.3),
            ],
            yValues: [0.02, 0.06, 0.10, 0.14]
        )

        let analysis = analyze(body: body, supports: support)

        XCTAssertEqual(analysis.resolution, .separatedSupports)
        XCTAssertEqual(analysis.supports.count, 4)
        XCTAssertTrue(analysis.preservesOpenLowerVolume)
        XCTAssertGreaterThan(analysis.bodyMinY ?? 0, 0.14)
    }

    func testFloatingBodyWithoutResolvedLegEvidenceRemainsUnresolved() {
        let body = bodyGrid(
            xValues: strideValues(-0.7, 0.7, 0.2),
            zValues: strideValues(-0.4, 0.4, 0.2),
            yValues: strideValues(0.32, 0.72, 0.08)
        )

        let analysis = analyze(body: body, supports: [])

        XCTAssertEqual(analysis.resolution, .floatingBodyUnresolved)
        XCTAssertEqual(analysis.lowerVolumeState, .unresolved)
        XCTAssertTrue(analysis.supports.isEmpty)
        XCTAssertEqual(
            analysis.advisories.first?.kind,
            .observeLowerFurniture
        )
    }

    func testIsolatedNoiseDoesNotBecomeInvisibleLegs() {
        var support = legs(
            centers: [
                (-0.68, -0.38),
                (0.68, 0.38),
            ],
            yValues: strideValues(0.02, 0.68, 0.08)
        )
        support.append(contentsOf: [
            (1.8, 0.19, 1.7),
            (-1.6, 0.27, 1.3),
            (1.4, 0.41, -1.5),
            (-1.7, 0.53, -1.6),
        ])

        let analysis = analyze(
            body: bodyGrid(
                xValues: strideValues(-0.8, 0.8, 0.2),
                zValues: strideValues(-0.5, 0.5, 0.2),
                yValues: [0.74]
            ),
            supports: support
        )

        XCTAssertEqual(analysis.supports.count, 2)
    }

    func testInsufficientHeightEvidenceFailsClosed() {
        let coordinateSpaceID = testCoordinateSpaceID
        let points = (0..<16).map { index in
            DerivedObservationPoint(
                position: DerivedPoint2D(
                    x: Double(index % 4) * 0.1,
                    y: Double(index / 4) * 0.1
                ),
                evidenceRef: "flat:" + String(index),
                evidenceKind: .spatialObservation
            )
        }
        let observation = DerivedShapeObservation(
            coordinateSpaceID: coordinateSpaceID,
            points: points
        )

        let analysis = DerivedSupportAnalyzer.analyze(
            observation: observation,
            floorY: 0
        )

        XCTAssertEqual(
            analysis.resolution,
            .insufficientHeightEvidence
        )
        XCTAssertTrue(analysis.supports.isEmpty)
    }

    private func analyze(
        body: [(Double, Double, Double)],
        supports: [(Double, Double, Double)]
    ) -> DerivedSupportAnalysis {
        let samples = body + supports
        let points = samples.enumerated().map { index, sample in
            DerivedObservationPoint(
                position: DerivedPoint2D(
                    x: sample.0,
                    y: sample.2
                ),
                evidenceRef: "fixture:" + String(index),
                evidenceKind: .spatialObservation,
                verticalPositionMeters: sample.1
            )
        }
        let observation = DerivedShapeObservation(
            coordinateSpaceID: testCoordinateSpaceID,
            points: points,
            observationStartSeconds: 1,
            observationEndSeconds: 2
        )
        return DerivedSupportAnalyzer.analyze(
            observation: observation,
            floorY: 0
        )
    }

    private func bodyGrid(
        xValues: [Double],
        zValues: [Double],
        yValues: [Double]
    ) -> [(Double, Double, Double)] {
        var result: [(Double, Double, Double)] = []
        for y in yValues {
            for x in xValues {
                for z in zValues {
                    result.append((x, y, z))
                }
            }
        }
        return result
    }

    private func legs(
        centers: [(Double, Double)],
        yValues: [Double]
    ) -> [(Double, Double, Double)] {
        centers.flatMap { center in
            yValues.map { y in
                (center.0, y, center.1)
            }
        }
    }

    private func strideValues(
        _ start: Double,
        _ end: Double,
        _ step: Double
    ) -> [Double] {
        var values: [Double] = []
        var value = start
        while value <= end + 0.000_001 {
            values.append(value)
            value += step
        }
        return values
    }

    private var testCoordinateSpaceID: CoordinateSpaceID {
        CoordinateSpaceID(
            rawValue: UUID(
                uuidString:
                    "00000000-0000-4000-8000-000000000777"
            )!
        )
    }
}
