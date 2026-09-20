import XCTest
@testable import HTDTCaptureCore

final class DerivedObjectDecompositionTests: XCTestCase {
    func testVerticallyStackedBoxesWithGapRemainSeparate() {
        let lower = boxPoints(
            minX: -0.9, maxX: 0.9,
            minY: 0.40, maxY: 0.80,
            minZ: -0.7, maxZ: 0.7,
            prefix: "lower"
        )
        let upper = boxPoints(
            minX: -0.45, maxX: 0.45,
            minY: 0.86, maxY: 1.10,
            minZ: -0.35, maxZ: 0.35,
            prefix: "upper"
        )

        let result = decompose(lower + upper)

        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.components.count, 2)
        XCTAssertLessThan(
            result.components[0].verticalExtent?.maxY ?? .infinity,
            result.components[1].verticalExtent?.minY ?? -.infinity
        )
        XCTAssertEqual(result.supportRelations.count, 1)
        XCTAssertEqual(
            result.supportRelations.first?.lowerComponentID,
            result.components[0].id
        )
        XCTAssertEqual(
            result.supportRelations.first?.upperComponentID,
            result.components[1].id
        )
    }

    func testBroadTouchingSupportCanRemainOneContinuousComponent() {
        let lower = boxPoints(
            minX: -0.9, maxX: 0.9,
            minY: 0.20, maxY: 0.60,
            minZ: -0.7, maxZ: 0.7,
            prefix: "lower"
        )
        let upper = boxPoints(
            minX: -0.5, maxX: 0.5,
            minY: 0.60, maxY: 0.90,
            minZ: -0.4, maxZ: 0.4,
            prefix: "upper"
        )

        let result = decompose(lower + upper)

        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.components.count, 1)
    }

    func testContinuousSteppedObjectIsNotOverSplit() {
        let left = boxPoints(
            minX: -1.0, maxX: 0.0,
            minY: 0.0, maxY: 0.40,
            minZ: -0.5, maxZ: 0.5,
            prefix: "step-left"
        )
        let right = boxPoints(
            minX: 0.0, maxX: 0.9,
            minY: 0.0, maxY: 0.72,
            minZ: -0.5, maxZ: 0.5,
            prefix: "step-right"
        )

        let result = decompose(left + right)

        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.components.count, 1)
        XCTAssertGreaterThan(
            result.components[0].verticalExtent?.verticalExtent ?? 0,
            0.65
        )
    }

    func testNearbyBoxesAtSameHeightStaySeparate() {
        let first = boxPoints(
            minX: -1.0, maxX: -0.35,
            minY: 0.20, maxY: 0.70,
            minZ: -0.4, maxZ: 0.4,
            prefix: "first"
        )
        let second = boxPoints(
            minX: 0.05, maxX: 0.70,
            minY: 0.20, maxY: 0.70,
            minZ: -0.4, maxZ: 0.4,
            prefix: "second"
        )

        let result = decompose(first + second)

        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.components.count, 2)
    }

    func testThinSparseBridgeDoesNotForceMerge() {
        let first = boxPoints(
            minX: -1.0, maxX: -0.45,
            minY: 0.20, maxY: 0.65,
            minZ: -0.35, maxZ: 0.35,
            prefix: "first"
        )
        let second = boxPoints(
            minX: 0.25, maxX: 0.80,
            minY: 0.20, maxY: 0.65,
            minZ: -0.35, maxZ: 0.35,
            prefix: "second"
        )
        let bridge = [
            point(x: -0.23, y: 0.42, z: 0, ref: "noise-1"),
            point(x: -0.01, y: 0.42, z: 0, ref: "noise-2"),
        ]

        let result = decompose(first + bridge + second)

        XCTAssertEqual(result.components.count, 2)
        XCTAssertGreaterThanOrEqual(result.unassignedPointCount, 1)
        XCTAssertFalse(result.components.contains { component in
            let refs = component.observation.points.map(\.evidenceRef)
            return refs.contains { $0.hasPrefix("first-") }
                && refs.contains { $0.hasPrefix("second-") }
        })
    }

    func testTrueNarrowConnectorMergesDenseGeometry() {
        let first = boxPoints(
            minX: -1.0, maxX: -0.45,
            minY: 0.20, maxY: 0.65,
            minZ: -0.35, maxZ: 0.35,
            prefix: "first"
        )
        let second = boxPoints(
            minX: 0.25, maxX: 0.80,
            minY: 0.20, maxY: 0.65,
            minZ: -0.35, maxZ: 0.35,
            prefix: "second"
        )
        let connector = connectorPoints(
            fromX: -0.45,
            toX: 0.25,
            y: 0.42,
            prefix: "connector"
        )

        let result = decompose(first + connector + second)

        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.components.count, 1)
    }

    func testOverlappingXZWithVerticalSeparationDoesNotCollapseIdentity() {
        let lower = boxPoints(
            minX: -0.7, maxX: 0.7,
            minY: 0.10, maxY: 0.35,
            minZ: -0.6, maxZ: 0.6,
            prefix: "lower"
        )
        let upper = boxPoints(
            minX: -0.7, maxX: 0.7,
            minY: 0.55, maxY: 0.80,
            minZ: -0.6, maxZ: 0.6,
            prefix: "upper"
        )

        let result = decompose(lower + upper)

        XCTAssertEqual(result.state, .resolved)
        XCTAssertEqual(result.components.count, 2)
        XCTAssertEqual(
            result.components.map(\.heightOrder),
            [0, 1]
        )
    }

    func testInsufficientEvidenceRemainsUnresolvedAndRequestsReobservation() {
        let points = [
            point(x: 0, y: 0.5, z: 0, ref: "p0"),
            point(x: 0.1, y: 0.5, z: 0, ref: "p1"),
            point(x: 0, y: 0.5, z: 0.1, ref: "p2"),
            point(x: 0.1, y: 0.5, z: 0.1, ref: "p3"),
            point(x: 0.05, y: 0.52, z: 0.05, ref: "p4"),
        ]

        let result = decompose(points)

        XCTAssertEqual(result.state, .unresolvedDecomposition)
        XCTAssertEqual(
            result.reobservationAdvisory?.reason,
            .insufficientVerticalEvidence
        )
    }

    func testMissingVerticalEvidenceFailsClosed() {
        let points = (0..<20).map { index in
            DerivedObservationPoint(
                position: DerivedPoint2D(
                    x: Double(index % 5) * 0.05,
                    y: Double(index / 5) * 0.05
                ),
                evidenceRef: "legacy-" + String(index),
                evidenceKind: .spatialObservation
            )
        }

        let result = DerivedObjectDecomposer.decompose(
            observation: observation(points)
        )

        XCTAssertEqual(result.state, .unresolvedDecomposition)
        XCTAssertEqual(
            result.reobservationAdvisory?.reason,
            .insufficientVerticalEvidence
        )
    }

    func testDecompositionIsDeterministicAndComponentsRemainFittable() {
        let lower = boxPoints(
            minX: -0.8, maxX: 0.8,
            minY: 0.20, maxY: 0.55,
            minZ: -0.6, maxZ: 0.6,
            prefix: "lower"
        )
        let upper = boxPoints(
            minX: -0.4, maxX: 0.4,
            minY: 0.62, maxY: 0.86,
            minZ: -0.3, maxZ: 0.3,
            prefix: "upper"
        )
        let input = observation(lower + upper)

        let first = DerivedObjectDecomposer.decompose(
            observation: input
        )
        let second = DerivedObjectDecomposer.decompose(
            observation: input
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.components.count, 2)

        for component in first.components {
            let proxy = DerivedShapeProxyFitter.fit(
                observation: component.observation
            )
            XCTAssertFalse(proxy.observationSample.isEmpty)
            XCTAssertFalse(proxy.candidates.isEmpty)
        }
    }

    private func decompose(
        _ points: [DerivedObservationPoint]
    ) -> DerivedObjectDecomposition {
        DerivedObjectDecomposer.decompose(
            observation: observation(points)
        )
    }

    private func observation(
        _ points: [DerivedObservationPoint]
    ) -> DerivedShapeObservation {
        DerivedShapeObservation(
            coordinateSpaceID: testCoordinateSpaceID,
            points: points,
            observationStartSeconds: 1,
            observationEndSeconds: 2
        )
    }

    private func boxPoints(
        minX: Double,
        maxX: Double,
        minY: Double,
        maxY: Double,
        minZ: Double,
        maxZ: Double,
        prefix: String
    ) -> [DerivedObservationPoint] {
        var result: [DerivedObservationPoint] = []
        var counter = 0
        let horizontalSamples = 8
        let verticalStep = 0.035

        func append(_ x: Double, _ y: Double, _ z: Double) {
            result.append(
                point(
                    x: x,
                    y: y,
                    z: z,
                    ref: prefix + "-" + String(counter)
                )
            )
            counter += 1
        }

        for index in 0...horizontalSamples {
            let t = Double(index) / Double(horizontalSamples)
            let x = minX + (maxX - minX) * t
            let z = minZ + (maxZ - minZ) * t

            append(x, minY, minZ)
            append(x, minY, maxZ)
            append(minX, minY, z)
            append(maxX, minY, z)

            append(x, maxY, minZ)
            append(x, maxY, maxZ)
            append(minX, maxY, z)
            append(maxX, maxY, z)
        }

        let supportPatchX = min(0.06, (maxX - minX) / 6)
        let supportPatchZ = min(0.06, (maxZ - minZ) / 6)
        let centerX = (minX + maxX) / 2
        let centerZ = (minZ + maxZ) / 2
        for y in [minY, maxY] {
            for xOffset in [-supportPatchX, 0, supportPatchX] {
                for zOffset in [-supportPatchZ, 0, supportPatchZ] {
                    append(
                        centerX + xOffset,
                        y,
                        centerZ + zOffset
                    )
                }
            }
        }

        let verticalSamples =
            max(1, Int(ceil((maxY - minY) / verticalStep)))
        for index in 0...verticalSamples {
            let t = Double(index) / Double(verticalSamples)
            let y = minY + (maxY - minY) * t
            append(minX, y, minZ)
            append(minX, y, maxZ)
            append(maxX, y, minZ)
            append(maxX, y, maxZ)
        }

        return result
    }

    private func connectorPoints(
        fromX: Double,
        toX: Double,
        y: Double,
        prefix: String
    ) -> [DerivedObservationPoint] {
        var result: [DerivedObservationPoint] = []
        let longitudinalSamples = 10
        let zOffsets = [-0.35, -0.30, -0.25]

        for index in 0...longitudinalSamples {
            let t = Double(index) / Double(longitudinalSamples)
            let x = fromX + (toX - fromX) * t
            for (zIndex, z) in zOffsets.enumerated() {
                result.append(
                    point(
                        x: x,
                        y: y,
                        z: z,
                        ref:
                            prefix
                            + "-"
                            + String(index)
                            + "-"
                            + String(zIndex)
                    )
                )
            }
        }
        return result
    }

    private func point(
        x: Double,
        y: Double,
        z: Double,
        ref: String
    ) -> DerivedObservationPoint {
        DerivedObservationPoint(
            position: DerivedPoint2D(x: x, y: z),
            verticalY: y,
            evidenceRef: ref,
            evidenceKind: .spatialObservation
        )
    }

    private var testCoordinateSpaceID: CoordinateSpaceID {
        CoordinateSpaceID(
            rawValue: UUID(
                uuidString:
                    "10000000-0000-4000-8000-000000000001"
            )!
        )
    }
}
