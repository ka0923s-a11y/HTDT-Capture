import Foundation
import XCTest
@testable import HTDTCaptureCore

/// Tests for the spatial lineage cluster: revision fork graph (#396),
/// cross-revision spatial registration (#395), and the mission
/// aggregate fulfillment ledger (#397).
final class SpatialLineageTests: XCTestCase {

    private func makeRoot() throws -> URL {
        try BundleValidationFixture.makeDirectory()
    }

    private func record(
        revisionID: CaptureRevisionID = CaptureRevisionID(),
        seriesID: CaptureSeriesID,
        parentID: CaptureRevisionID? = nil,
        finalizedAtUTC: String
    ) -> PersistedCaptureRecord {
        PersistedCaptureRecord(
            captureRevisionID: revisionID,
            captureSeriesID: seriesID,
            finalizedAtUTC: finalizedAtUTC,
            finalizedDirectory: nil,
            finalizedValidation: nil,
            exportArchive: nil,
            exportValidation: nil,
            parentRevisionID: parentID
        )
    }

    // MARK: - #396 revision fork graph

    func testLinearSeriesResolvesSingleHead() {
        let series = CaptureSeriesID()
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let records = [
            record(
                revisionID: a, seriesID: series,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
            record(
                revisionID: b, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let graph = CaptureSeriesRevisionGraph(
            allRecords: records,
            captureSeriesID: series
        )
        XCTAssertTrue(graph.hasSingleHead)
        XCTAssertFalse(graph.isBranched)
        XCTAssertEqual(graph.roots, [a])
        XCTAssertEqual(graph.heads, [b])
        XCTAssertTrue(graph.diagnostics.isEmpty)
        XCTAssertEqual(graph.ancestors(of: b).chain, [a])
        XCTAssertFalse(graph.ancestors(of: b).truncated)
        XCTAssertEqual(graph.descendants(of: a), [b])
    }

    func testForkedSeriesReportsTwoHeadsAndNoImplicitLatest() {
        let series = CaptureSeriesID()
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let c = CaptureRevisionID()
        let records = [
            record(
                revisionID: a, seriesID: series,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
            // b is the newer head by timestamp — timestamps must not
            // decide Latest on a branched series.
            record(
                revisionID: b, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T03:00:00Z"
            ),
            record(
                revisionID: c, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let group = CaptureSeriesGrouper.group(
            records: records,
            metadata: CaptureLibraryMetadataDocument()
        ).first!
        XCTAssertTrue(group.isBranched)
        XCTAssertEqual(
            Set(group.headRevisions.map(\.captureRevisionID)),
            [b, c]
        )
        // No accepted pick → the series presents no Latest at all;
        // the newest revision is never silently substituted.
        XCTAssertNil(group.preferredRevision)
        XCTAssertEqual(group.latestRevision?.captureRevisionID, b)
    }

    func testMissingAndCrossSeriesParentsAreDiagnostics() {
        let series = CaptureSeriesID()
        let other = CaptureSeriesID()
        let absent = CaptureRevisionID()
        let inOther = CaptureRevisionID()
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let records = [
            record(
                revisionID: inOther, seriesID: other,
                finalizedAtUTC: "2026-09-20T00:00:00Z"
            ),
            record(
                revisionID: a, seriesID: series, parentID: absent,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
            record(
                revisionID: b, seriesID: series, parentID: inOther,
                finalizedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let graph = CaptureSeriesRevisionGraph(
            allRecords: records,
            captureSeriesID: series
        )
        XCTAssertEqual(
            graph.diagnostics,
            [
                .missingPredecessor(revision: a, parent: absent),
                .crossSeriesParent(
                    revision: b,
                    parent: inOther,
                    parentSeries: other
                ),
            ]
        )
        // A revision declaring an unresolved parent is not a root —
        // its declared lineage is unproven, not absent.
        XCTAssertTrue(graph.roots.isEmpty)
        XCTAssertTrue(graph.ancestors(of: a).truncated)
        XCTAssertFalse(
            graph.nodes[b]!.parentResolvedInSeries
        )
    }

    func testCycleIsDiagnosedNotLooped() {
        let series = CaptureSeriesID()
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let records = [
            record(
                revisionID: a, seriesID: series, parentID: b,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
            record(
                revisionID: b, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let graph = CaptureSeriesRevisionGraph(
            allRecords: records,
            captureSeriesID: series
        )
        XCTAssertTrue(
            graph.diagnostics.contains {
                if case .cyclicTopology = $0 { return true }
                return false
            }
        )
        // Cycle members count as heads (nothing resolves below them)
        // but ancestry walk terminates instead of looping forever.
        XCTAssertTrue(graph.ancestors(of: a).truncated)
    }

    func testImportClassification() {
        let series = CaptureSeriesID()
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let records = [
            record(
                revisionID: a, seriesID: series,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
            record(
                revisionID: b, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let incoming = CaptureRevisionID()
        // Extending the single head extends the line.
        XCTAssertEqual(
            CaptureSeriesRevisionGraph.classifyImport(
                captureSeriesID: series,
                captureRevisionID: incoming,
                parentRevisionID: b,
                allRecords: records
            ),
            .extendsHead
        )
        // A sibling of b under a creates a parallel head.
        XCTAssertEqual(
            CaptureSeriesRevisionGraph.classifyImport(
                captureSeriesID: series,
                captureRevisionID: incoming,
                parentRevisionID: a,
                allRecords: records
            ),
            .newParallelHead
        )
        // A revision id already present is an exact duplicate.
        XCTAssertEqual(
            CaptureSeriesRevisionGraph.classifyImport(
                captureSeriesID: series,
                captureRevisionID: a,
                parentRevisionID: nil,
                allRecords: records
            ),
            .exactDuplicate
        )
        // A revision id present under a different parent conflicts.
        XCTAssertEqual(
            CaptureSeriesRevisionGraph.classifyImport(
                captureSeriesID: series,
                captureRevisionID: b,
                parentRevisionID: CaptureRevisionID(),
                allRecords: records
            ),
            .identityConflict
        )
        // A declared parent unknown locally stays unresolved — never
        // treated as a fresh root.
        XCTAssertEqual(
            CaptureSeriesRevisionGraph.classifyImport(
                captureSeriesID: series,
                captureRevisionID: incoming,
                parentRevisionID: CaptureRevisionID(),
                allRecords: records
            ),
            .unresolvedPredecessor
        )
    }

    func testImportFillsMissingPredecessor() {
        let series = CaptureSeriesID()
        let absent = CaptureRevisionID()
        let a = CaptureRevisionID()
        let records = [
            record(
                revisionID: a, seriesID: series, parentID: absent,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
        ]
        XCTAssertEqual(
            CaptureSeriesRevisionGraph.classifyImport(
                captureSeriesID: series,
                captureRevisionID: absent,
                parentRevisionID: nil,
                allRecords: records
            ),
            .fillsMissingPredecessor
        )
    }

    func testPreferredHeadPersistedAndValidated() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let series = CaptureSeriesID()
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let c = CaptureRevisionID()
        let records = [
            record(
                revisionID: a, seriesID: series,
                finalizedAtUTC: "2026-09-20T01:00:00Z"
            ),
            record(
                revisionID: b, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T03:00:00Z"
            ),
            record(
                revisionID: c, seriesID: series, parentID: a,
                finalizedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let store = CaptureLibraryMetadataStore(captureRoot: root)
        try store.updatePreferredHead(
            series,
            revisionID: c,
            note: "retake superseded"
        )
        let document = try store.load()
        XCTAssertEqual(
            document.preferredHeads[series.description]?
                .preferredHeadRevisionID,
            c.description
        )
        let group = CaptureSeriesGrouper.group(
            records: records,
            metadata: document
        ).first!
        XCTAssertEqual(group.effectivePreferredHeadID, c)
        XCTAssertEqual(group.preferredRevision?.captureRevisionID, c)
        // A stored pick naming a non-head never redirects Latest.
        let staleHead = CaptureRevisionID()
        try store.updatePreferredHead(series, revisionID: staleHead)
        let stale = CaptureSeriesGrouper.group(
            records: records,
            metadata: try store.load()
        ).first!
        XCTAssertNil(stale.effectivePreferredHeadID)
        XCTAssertNil(stale.preferredRevision)
        // Clearing restores the branched-but-unresolved presentation.
        try store.clearPreferredHead(series)
        XCTAssertTrue(
            try store.load().preferredHeads.isEmpty
        )
    }

    // MARK: - #395 cross-revision spatial registration

    private func correspondence(
        _ ref: String,
        _ source: WorldPoint3D,
        _ target: WorldPoint3D
    ) throws -> CrossRevisionCorrespondence {
        try CrossRevisionCorrespondence(
            kind: .manualPoint,
            ref: ref,
            sourcePosition: source,
            targetPosition: target
        )
    }

    /// A 90° rotation about +z followed by translation (1, 2, 3).
    private let knownRotation: [[Double]] = [
        [0, -1, 0],
        [1, 0, 0],
        [0, 0, 1],
    ]
    private let knownTranslation = WorldPoint3D(x: 1, y: 2, z: 3)

    private func knownTarget(
        _ p: WorldPoint3D,
        scale: Double = 1
    ) -> WorldPoint3D {
        let s = WorldPoint3D(
            x: p.x * scale, y: p.y * scale, z: p.z * scale
        )
        return WorldPoint3D(
            x: knownRotation[0][0] * s.x + knownRotation[0][1] * s.y
                + knownRotation[0][2] * s.z + knownTranslation.x,
            y: knownRotation[1][0] * s.x + knownRotation[1][1] * s.y
                + knownRotation[1][2] * s.z + knownTranslation.y,
            z: knownRotation[2][0] * s.x + knownRotation[2][1] * s.y
                + knownRotation[2][2] * s.z + knownTranslation.z
        )
    }

    private func knownPairCorrespondences(
        scale: Double = 1
    ) throws -> [CrossRevisionCorrespondence] {
        let sources = [
            WorldPoint3D(x: 0, y: 0, z: 0),
            WorldPoint3D(x: 1, y: 0, z: 0),
            WorldPoint3D(x: 0, y: 1, z: 0),
            WorldPoint3D(x: 0, y: 0, z: 1),
        ]
        return try sources.enumerated().map { index, source in
            try correspondence(
                "p\(index)", source, knownTarget(source, scale: scale)
            )
        }
    }

    func testRigidSolveRecoversKnownTransform() throws {
        let solve = try CrossRevisionRegistrationSolver.solve(
            correspondences: knownPairCorrespondences(),
            scalePolicy: .rigidOnly
        )
        XCTAssertEqual(solve.uniformScale, 1, accuracy: 1e-6)
        XCTAssertEqual(solve.rmsMeters, 0, accuracy: 1e-4)
        XCTAssertEqual(solve.maxResidualMeters, 0, accuracy: 1e-4)
        let mapped = solve.targetFromSource.applying(
            to: Float3(1, 0, 0)
        )
        let expected = knownTarget(WorldPoint3D(x: 1, y: 0, z: 0))
        XCTAssertEqual(Double(mapped.x), expected.x, accuracy: 1e-4)
        XCTAssertEqual(Double(mapped.y), expected.y, accuracy: 1e-4)
        XCTAssertEqual(Double(mapped.z), expected.z, accuracy: 1e-4)
        XCTAssertEqual(solve.residuals.count, 4)
    }

    func testSolveFailsClosedOnDegenerateGeometry() throws {
        // Fewer than three correspondences.
        XCTAssertThrowsError(
            try CrossRevisionRegistrationSolver.solve(
                correspondences: [
                    correspondence(
                        "a",
                        WorldPoint3D(x: 0, y: 0, z: 0),
                        WorldPoint3D(x: 1, y: 2, z: 3)
                    ),
                    correspondence(
                        "b",
                        WorldPoint3D(x: 1, y: 0, z: 0),
                        WorldPoint3D(x: 0, y: 2, z: 3)
                    ),
                ],
                scalePolicy: .rigidOnly
            )
        ) { error in
            XCTAssertEqual(
                error as? CrossRevisionRegistrationError,
                .insufficientCorrespondences(found: 2)
            )
        }
        // Collinear geometry can never orient a rigid fit.
        XCTAssertThrowsError(
            try CrossRevisionRegistrationSolver.solve(
                correspondences: [
                    correspondence(
                        "a",
                        WorldPoint3D(x: 0, y: 0, z: 0),
                        knownTarget(WorldPoint3D(x: 0, y: 0, z: 0))
                    ),
                    correspondence(
                        "b",
                        WorldPoint3D(x: 1, y: 0, z: 0),
                        knownTarget(WorldPoint3D(x: 1, y: 0, z: 0))
                    ),
                    correspondence(
                        "c",
                        WorldPoint3D(x: 2, y: 0, z: 0),
                        knownTarget(WorldPoint3D(x: 2, y: 0, z: 0))
                    ),
                ],
                scalePolicy: .rigidOnly
            )
        ) { error in
            XCTAssertEqual(
                error as? CrossRevisionRegistrationError,
                .degenerateCorrespondences
            )
        }
        // Duplicate referents are refused — every pairing is named.
        XCTAssertThrowsError(
            try CrossRevisionRegistrationSolver.solve(
                correspondences: [
                    correspondence(
                        "a",
                        WorldPoint3D(x: 0, y: 0, z: 0),
                        knownTarget(WorldPoint3D(x: 0, y: 0, z: 0))
                    ),
                    correspondence(
                        "a",
                        WorldPoint3D(x: 1, y: 0, z: 0),
                        knownTarget(WorldPoint3D(x: 1, y: 0, z: 0))
                    ),
                    correspondence(
                        "c",
                        WorldPoint3D(x: 0, y: 0, z: 1),
                        knownTarget(WorldPoint3D(x: 0, y: 0, z: 1))
                    ),
                ],
                scalePolicy: .rigidOnly
            )
        ) { error in
            XCTAssertEqual(
                error as? CrossRevisionRegistrationError,
                .duplicateCorrespondenceRef("a")
            )
        }
    }

    func testScaleOnlyFitsUnderExplicitPolicy() throws {
        let scaled = try knownPairCorrespondences(scale: 2)
        // Rigid policy on scaled data still solves but never reports
        // a fitted scale.
        let rigid = try CrossRevisionRegistrationSolver.solve(
            correspondences: scaled,
            scalePolicy: .rigidOnly
        )
        XCTAssertEqual(rigid.uniformScale, 1)
        XCTAssertGreaterThan(rigid.rmsMeters, 0)
        // Opt-in policy fits the declared scale correction.
        let fitted = try CrossRevisionRegistrationSolver.solve(
            correspondences: scaled,
            scalePolicy: .uniformScalePermitted
        )
        XCTAssertEqual(fitted.uniformScale, 2, accuracy: 1e-4)
        XCTAssertEqual(fitted.rmsMeters, 0, accuracy: 1e-4)
    }

    func testRegistrationStoreAcceptPersistsAndRefusesConflict() throws
    {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let store = CrossRevisionRegistrationStore(captureRoot: root)
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let spaceA = CoordinateSpaceID()
        let spaceB = CoordinateSpaceID()
        let correspondences = try knownPairCorrespondences()
        // propose persists nothing.
        let solve = try store.propose(correspondences: correspondences)
        XCTAssertEqual(solve.residuals.count, 4)
        XCTAssertTrue(try store.load().registrations.isEmpty)
        let accepted = try store.accept(
            sourceRevisionID: a,
            sourceCoordinateSpaceID: spaceA,
            targetRevisionID: b,
            targetCoordinateSpaceID: spaceB,
            mechanism: .manualPoint,
            correspondences: correspondences
        )
        XCTAssertEqual(accepted.uncertaintyMeters, accepted.maxResidualMeters)
        XCTAssertEqual(try store.load().registrations.count, 1)
        // Same directed pair — refused, never overwritten.
        XCTAssertThrowsError(
            try store.accept(
                sourceRevisionID: a,
                sourceCoordinateSpaceID: spaceA,
                targetRevisionID: b,
                targetCoordinateSpaceID: spaceB,
                mechanism: .manualPoint,
                correspondences: correspondences
            )
        ) { error in
            XCTAssertEqual(
                error as? CrossRevisionRegistrationError,
                .conflictingRegistration
            )
        }
    }

    func testRegistrationStoreFailsClosedOnUnreadableFile() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        try Data("not-json".utf8).write(
            to: root.appendingPathComponent(
                "spatial-registrations.json",
                isDirectory: false
            )
        )
        XCTAssertThrowsError(
            try CrossRevisionRegistrationStore(captureRoot: root).load()
        ) { error in
            XCTAssertEqual(
                error as? CrossRevisionRegistrationError,
                .unreadableDocument
            )
        }
    }

    func testSharedFieldDatumGatherProducesFourCorrespondences() throws
    {
        let datumA = try RoomFieldDatumDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            origin: RoomFieldDatumOrigin(
                kind: .roomCorner,
                ref: "corner",
                pointMeters: WorldPoint3D(x: 0, y: 0, z: 0)
            ),
            axis: RoomFieldDatumAxis(
                kind: .twoSurveyedPoints,
                refs: ["corner", "edge"],
                directionMeters: WorldPoint3D(x: 0, y: 1, z: 0)
            ),
            verticalDatum: RoomFieldDatumVertical(
                kind: .finishedFloor,
                ref: "floor",
                zeroElevationMeters: 0
            ),
            fieldFromCaptureWorld: RoomFieldDatumTransform(
                originMeters: WorldPoint3D(x: 0, y: 0, z: 0),
                xAxis: WorldPoint3D(x: 1, y: 0, z: 0),
                yAxis: WorldPoint3D(x: 0, y: 1, z: 0),
                zAxis: WorldPoint3D(x: 0, y: 0, z: 1)
            ),
            confirmedAtUTC: "2026-09-20T01:00:00Z"
        )
        let datumB = try RoomFieldDatumDocument(
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: CaptureSessionID(),
            coordinateSpaceID: CoordinateSpaceID(),
            origin: RoomFieldDatumOrigin(
                kind: .roomCorner,
                ref: "corner",
                pointMeters: WorldPoint3D(x: 2, y: 0.5, z: 0)
            ),
            axis: RoomFieldDatumAxis(
                kind: .twoSurveyedPoints,
                refs: ["corner", "edge"],
                directionMeters: WorldPoint3D(x: 1, y: 0, z: 0)
            ),
            verticalDatum: RoomFieldDatumVertical(
                kind: .finishedFloor,
                ref: "floor",
                zeroElevationMeters: 0.5
            ),
            fieldFromCaptureWorld: RoomFieldDatumTransform(
                originMeters: WorldPoint3D(x: 2, y: 0.5, z: 0),
                xAxis: WorldPoint3D(x: 0, y: -1, z: 0),
                yAxis: WorldPoint3D(x: 1, y: 0, z: 0),
                zAxis: WorldPoint3D(x: 0, y: 0, z: 1)
            ),
            confirmedAtUTC: "2026-09-20T02:00:00Z"
        )
        let correspondences =
            try CrossRevisionCorrespondenceGather.fromSharedFieldDatums(
                source: datumA,
                target: datumB
            )
        XCTAssertEqual(correspondences.count, 4)
        XCTAssertTrue(correspondences.allSatisfy {
            $0.kind == .sharedFieldDatum
        })
        // The field datum origin maps between the two spaces.
        let solve = try CrossRevisionRegistrationSolver.solve(
            correspondences: correspondences,
            scalePolicy: .rigidOnly
        )
        XCTAssertEqual(solve.maxResidualMeters, 0, accuracy: 1e-4)
    }

    func testRegistrationGraphDirectChainedAndUnresolved() throws {
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let c = CaptureRevisionID()
        let d = CaptureRevisionID()
        func registration(
            _ source: CaptureRevisionID,
            _ target: CaptureRevisionID,
            translation: WorldPoint3D,
            maxResidual: Double
        ) throws -> CrossRevisionRegistration {
            let solve = CrossRevisionRegistrationSolve(
                targetFromSource: try Matrix4x4F(values: [
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    Float(translation.x), Float(translation.y),
                    Float(translation.z), 1,
                ]),
                uniformScale: 1,
                residuals: [],
                rmsMeters: maxResidual,
                maxResidualMeters: maxResidual
            )
            return try CrossRevisionRegistration(
                sourceRevisionID: source,
                sourceCoordinateSpaceID: CoordinateSpaceID(),
                targetRevisionID: target,
                targetCoordinateSpaceID: CoordinateSpaceID(),
                mechanism: .manualPoint,
                correspondences: [],
                residuals: [],
                rmsMeters: solve.rmsMeters,
                maxResidualMeters: solve.maxResidualMeters,
                scalePolicy: .rigidOnly,
                uniformScale: 1,
                targetFromSource: solve.targetFromSource,
                acceptedAtUTC: "2026-09-20T01:00:00Z"
            )
        }
        let ab = try registration(
            a, b,
            translation: WorldPoint3D(x: 1, y: 0, z: 0),
            maxResidual: 0.03
        )
        let bc = try registration(
            b, c,
            translation: WorldPoint3D(x: 0, y: 2, z: 0),
            maxResidual: 0.04
        )
        let graph = CrossRevisionRegistrationGraph(
            registrations: [ab, bc]
        )
        // Direct edge.
        guard case .direct(let edge) = graph.resolve(from: a, to: b)
        else {
            XCTFail("a→b must resolve direct")
            return
        }
        XCTAssertEqual(edge.registrationID, ab.registrationID)
        // Chained path composes transforms and accumulates
        // uncertainty in quadrature.
        guard case .chained(
            let hops, let transform, let uncertainty
        ) = graph.resolve(from: a, to: c)
        else {
            XCTFail("a→c must resolve chained")
            return
        }
        XCTAssertEqual(hops.count, 2)
        XCTAssertEqual(
            uncertainty,
            (0.03 * 0.03 + 0.04 * 0.04).squareRoot(),
            accuracy: 1e-9
        )
        let mapped = transform.applying(
            to: WorldPoint3D(x: 0, y: 0, z: 0)
        )
        XCTAssertEqual(mapped.x, 1, accuracy: 1e-4)
        XCTAssertEqual(mapped.y, 2, accuracy: 1e-4)
        // Reverse traversal inverts each edge.
        guard case .chained(
            _, let inverse, _
        ) = graph.resolve(from: c, to: a)
        else {
            XCTFail("c→a must resolve chained via inverses")
            return
        }
        let roundTrip = inverse.applying(
            to: mapped
        )
        XCTAssertEqual(roundTrip.x, 0, accuracy: 1e-4)
        XCTAssertEqual(roundTrip.y, 0, accuracy: 1e-4)
        XCTAssertEqual(roundTrip.z, 0, accuracy: 1e-4)
        // No registered path is honestly reported.
        XCTAssertEqual(
            graph.resolve(from: a, to: d),
            .unresolved
        )
        XCTAssertEqual(
            graph.resolve(from: a, to: a),
            .identity
        )
    }

    func testRegistrationBundlePackageRoundTrips() throws {
        let a = CaptureRevisionID()
        let b = CaptureRevisionID()
        let registration = try CrossRevisionRegistration(
            sourceRevisionID: a,
            sourceCoordinateSpaceID: CoordinateSpaceID(),
            targetRevisionID: b,
            targetCoordinateSpaceID: CoordinateSpaceID(),
            mechanism: .sharedFieldDatum,
            correspondences: [],
            residuals: [],
            rmsMeters: 0.02,
            maxResidualMeters: 0.03,
            scalePolicy: .rigidOnly,
            uniformScale: 1,
            targetFromSource: try Matrix4x4F(values: [
                1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 2, 3, 1,
            ]),
            acceptedAtUTC: "2026-09-20T01:00:00Z",
            evidenceRefs: ["path:session/room-field-datum.json"]
        )
        // A document that fails to name its owning revision refuses.
        XCTAssertThrowsError(
            try CrossRevisionRegistrationBundleDocument(
                captureRevisionID: CaptureRevisionID(),
                registrations: [registration]
            )
        ) { error in
            XCTAssertEqual(
                error as? CrossRevisionRegistrationError,
                .mismatchedCorrespondenceIdentity
            )
        }
        let document = try CrossRevisionRegistrationBundleDocument(
            captureRevisionID: a,
            registrations: [registration]
        )
        let package = try CrossRevisionRegistrationPackageBuilder.build(
            document: document
        )
        XCTAssertEqual(
            CrossRevisionRegistrationPackage.path,
            "revision/registrations.json"
        )
        XCTAssertEqual(
            package.payloadDeclaration.provenanceClass,
            .captureAppDerived
        )
        // The v1 source_refs grammar cannot name an external
        // revision, so the manifest entry declares no refs — the
        // endpoint IDs live only in the document body.
        XCTAssertNil(package.payloadDeclaration.sourceRefs)
        let decoded = try JSONDecoder().decode(
            CrossRevisionRegistrationBundleDocument.self,
            from: package.data
        )
        XCTAssertEqual(decoded, document)
        // The schema registry resolves the path.
        XCTAssertEqual(
            CaptureBundleSchemaRegistry.schemaName(
                forPath: "revision/registrations.json"
            ),
            "cross-revision-registration"
        )
    }

    // MARK: - #397 mission aggregate fulfillment ledger

    private func makeLedgerMission(
        planID: String = "plan-1",
        planSHA256: String
    ) -> HTDTMissionRecord {
        HTDTMissionRecord(
            recordID: UUID().uuidString.lowercased(),
            missionID: "mission-1",
            missionKind: .initialSurvey,
            purpose: nil,
            payloadRelativePath: "missions/payload.json",
            payloadSHA256: String(repeating: "0", count: 64),
            planID: planID,
            planVersion: "1",
            planSHA256: planSHA256,
            projectRef: "proj",
            roomName: "room",
            issuedAtUTC: nil,
            importedAtUTC: "2026-09-20T00:00:00Z",
            lifecycle: .inProgress
        )
    }

    private func makeLedgerPlan() throws -> HTDTCaptureTaskPlan {
        try HTDTCaptureTaskPlan(
            planID: "plan-1",
            planVersion: "1",
            projectRef: "proj",
            roomName: "room",
            entityChecklist: [
                HTDTTaskPlanEntityItem(
                    itemID: "e-1",
                    entityType: .speaker,
                    requirement: .required
                ),
                HTDTTaskPlanEntityItem(
                    itemID: "e-2",
                    entityType: .speaker,
                    requirement: .optional
                ),
            ],
            measurementRequests: [
                HTDTTaskPlanMeasurementItem(
                    itemID: "m-1",
                    quantityType: "room_width",
                    requirement: .required
                ),
            ]
        )
    }

    private func statusDocument(
        revisionID: CaptureRevisionID,
        planID: String,
        planSHA256: EvidenceSHA256,
        items: [CaptureTaskPlanStatusDocument.ItemOutcome]
    ) throws -> CaptureTaskPlanStatusDocument {
        try CaptureTaskPlanStatusDocument(
            captureRevisionID: revisionID,
            captureSessionID: CaptureSessionID(),
            planID: planID,
            planVersion: "1",
            planSHA256: planSHA256,
            items: items
        )
    }

    func testLedgerIngestAggregatesAcrossRevisions() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let ledger = MissionProgressLedgerStore(captureRoot: root)
        let plan = try makeLedgerPlan()
        let sha = EvidenceIntegrity.sha256(of: Data("plan".utf8))
        let mission = makeLedgerMission(
            planSHA256: sha.description
        )
        let revA = CaptureRevisionID()
        let revB = CaptureRevisionID()
        // Revision A completes one required entity item.
        let docA = try statusDocument(
            revisionID: revA,
            planID: "plan-1",
            planSHA256: sha,
            items: [
                .init(itemID: "e-1", outcome: .completed),
                .init(itemID: "e-2", outcome: .pending),
                .init(itemID: "m-1", outcome: .skipped),
            ]
        )
        let first = try ledger.ingestStatusDocument(
            docA,
            for: mission,
            plan: plan,
            sourceStatusSHA256: sha
        )
        XCTAssertEqual(first.count, 3)
        // Re-ingest of the identical document appends nothing.
        XCTAssertTrue(
            try ledger.ingestStatusDocument(
                docA, for: mission, plan: plan,
                sourceStatusSHA256: sha
            ).isEmpty
        )
        // Revision B retakes m-1 — the replacement supersedes revA's
        // skipped outcome; both stay in history.
        let docB = try statusDocument(
            revisionID: revB,
            planID: "plan-1",
            planSHA256: sha,
            items: [
                .init(
                    itemID: "m-1",
                    outcome: .completed,
                    fulfillmentRef: "measurement:\(UUID().uuidString.lowercased())"
                ),
            ]
        )
        let second = try ledger.ingestStatusDocument(
            docB,
            for: mission,
            plan: plan,
            sourceStatusSHA256: sha
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertNotNil(second.first?.supersedes)
        let evaluation = try ledger.evaluate(
            record: mission,
            plan: plan
        )
        let m1 = evaluation.items.first { $0.taskItemID == "m-1" }!
        XCTAssertEqual(m1.outcome, .completed)
        XCTAssertEqual(m1.history.count, 2)
        // e-1 completed + m-1 completed → all required done;
        // optional e-2 still open keeps field-complete true (required
        // items only) — it is not outstanding-required.
        XCTAssertTrue(evaluation.fieldComplete)
        XCTAssertTrue(evaluation.requiredItemsResolved)
        XCTAssertEqual(
            Set(evaluation.completedItemIDs),
            ["e-1", "m-1"]
        )
        XCTAssertEqual(
            Set(evaluation.outstandingItemIDs),
            ["e-2"]
        )
        XCTAssertEqual(
            Set(try ledger.completedItemIDs(for: mission.recordID)),
            ["e-1", "m-1"]
        )
    }

    func testLedgerRejectsIncompatibleDocuments() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let ledger = MissionProgressLedgerStore(captureRoot: root)
        let plan = try makeLedgerPlan()
        let sha = EvidenceIntegrity.sha256(of: Data("plan".utf8))
        let mission = makeLedgerMission(
            planSHA256: sha.description
        )
        // Wrong plan id.
        XCTAssertThrowsError(
            try ledger.ingestStatusDocument(
                statusDocument(
                    revisionID: CaptureRevisionID(),
                    planID: "plan-2",
                    planSHA256: sha,
                    items: [.init(itemID: "e-1", outcome: .completed)]
                ),
                for: mission,
                plan: plan,
                sourceStatusSHA256: sha
            )
        ) { error in
            XCTAssertEqual(
                error as? MissionProgressLedgerError,
                .incompatibleSourceDocument
            )
        }
        // Wrong plan bytes digest — a revised plan is a different
        // contract.
        XCTAssertThrowsError(
            try ledger.ingestStatusDocument(
                statusDocument(
                    revisionID: CaptureRevisionID(),
                    planID: "plan-1",
                    planSHA256: EvidenceIntegrity.sha256(
                        of: Data("other".utf8)
                    ),
                    items: [.init(itemID: "e-1", outcome: .completed)]
                ),
                for: mission,
                plan: plan,
                sourceStatusSHA256: sha
            )
        ) { error in
            XCTAssertEqual(
                error as? MissionProgressLedgerError,
                .incompatibleSourceDocument
            )
        }
        // An item the plan never declared is not absorbed.
        XCTAssertThrowsError(
            try ledger.ingestStatusDocument(
                statusDocument(
                    revisionID: CaptureRevisionID(),
                    planID: "plan-1",
                    planSHA256: sha,
                    items: [
                        .init(itemID: "nope", outcome: .completed),
                    ]
                ),
                for: mission,
                plan: plan,
                sourceStatusSHA256: sha
            )
        ) { error in
            XCTAssertEqual(
                error as? MissionProgressLedgerError,
                .unknownItemID
            )
        }
    }

    func testLedgerWaiverResolvesButDoesNotFalsifyCompletion() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let ledger = MissionProgressLedgerStore(captureRoot: root)
        let plan = try makeLedgerPlan()
        let sha = EvidenceIntegrity.sha256(of: Data("plan".utf8))
        let mission = makeLedgerMission(
            planSHA256: sha.description
        )
        // Waiving an item the plan does not declare refuses.
        XCTAssertThrowsError(
            try ledger.waive(
                itemID: "nope",
                for: mission,
                plan: plan
            )
        ) { error in
            XCTAssertEqual(
                error as? MissionProgressLedgerError,
                .unknownItemID
            )
        }
        try ledger.waive(
            itemID: "m-1",
            for: mission,
            plan: plan,
            note: "site access denied"
        )
        let evaluation = try ledger.evaluate(
            record: mission,
            plan: plan
        )
        // m-1 waived → resolved but NOT completed: field-complete is
        // evidence-only; required-items-resolved still fails on the
        // untouched required e-1 — a waiver never silently completes
        // sibling work.
        XCTAssertFalse(evaluation.fieldComplete)
        XCTAssertFalse(evaluation.requiredItemsResolved)
        XCTAssertEqual(evaluation.waivedItemIDs, ["m-1"])
        XCTAssertEqual(evaluation.outstandingItemIDs, ["e-1", "e-2"])
        let m1 = evaluation.items.first { $0.taskItemID == "m-1" }!
        XCTAssertTrue(m1.waived)
        XCTAssertTrue(m1.resolved)
        XCTAssertFalse(m1.outcome == .completed)
    }

    func testLedgerContestedItemsSurface() throws {
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        let store = MissionProgressLedgerStore(captureRoot: root)
        let plan = try makeLedgerPlan()
        let sha = EvidenceIntegrity.sha256(of: Data("plan".utf8))
        let mission = makeLedgerMission(
            planSHA256: sha.description
        )
        // Two live entries for one item — what a cross-device fork
        // merged into one ledger looks like. Neither supersedes the
        // other, so the contest is surfaced instead of hidden.
        let entries = try [
            MissionProgressLedgerEntry(
                entryID: UUID().uuidString.lowercased(),
                taskItemID: "e-1",
                taskKind: .entityChecklist,
                requirement: .required,
                outcome: .completed,
                captureRevisionID: CaptureRevisionID(),
                sourceStatusSHA256: sha,
                acceptedAtUTC: "2026-09-20T01:00:00Z"
            ),
            MissionProgressLedgerEntry(
                entryID: UUID().uuidString.lowercased(),
                taskItemID: "e-1",
                taskKind: .entityChecklist,
                requirement: .required,
                outcome: .completed,
                captureRevisionID: CaptureRevisionID(),
                sourceStatusSHA256: sha,
                acceptedAtUTC: "2026-09-20T02:00:00Z"
            ),
        ]
        let document = MissionProgressLedgerStore.Document(
            records: [
                try MissionProgressLedgerRecord(
                    missionRecordID: mission.recordID,
                    planID: "plan-1",
                    planSHA256: sha.description,
                    entries: entries,
                    waivers: []
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(document).write(to: store.fileURL)
        let evaluation = try store.evaluate(
            record: mission,
            plan: plan
        )
        XCTAssertEqual(evaluation.contestedItemIDs, ["e-1"])
        // Deterministic winner: latest accepted entry.
        XCTAssertEqual(
            evaluation.items.first { $0.taskItemID == "e-1" }?
                .acceptedEntry?.entryID,
            entries.last?.entryID
        )
    }

    func testLedgerEntryValidationIsStrict() throws {
        let sha = EvidenceIntegrity.sha256(of: Data("x".utf8))
        // Non-canonical entry id.
        XCTAssertThrowsError(
            try MissionProgressLedgerEntry(
                entryID: "not-a-uuid",
                taskItemID: "e-1",
                taskKind: .entityChecklist,
                requirement: .required,
                outcome: .completed,
                captureRevisionID: CaptureRevisionID(),
                sourceStatusSHA256: sha,
                acceptedAtUTC: "2026-09-20T01:00:00Z"
            )
        )
        // Non-UTC acceptance timestamp.
        XCTAssertThrowsError(
            try MissionProgressLedgerEntry(
                entryID: UUID().uuidString.lowercased(),
                taskItemID: "e-1",
                taskKind: .entityChecklist,
                requirement: .required,
                outcome: .completed,
                captureRevisionID: CaptureRevisionID(),
                sourceStatusSHA256: sha,
                acceptedAtUTC: "2026-09-20 01:00:00"
            )
        ) { error in
            XCTAssertEqual(
                error as? MissionProgressLedgerError,
                .invalidTimestamp
            )
        }
        // Corrupt ledger file fails closed.
        let root = try makeRoot()
        defer { BundleValidationFixture.remove(root) }
        try Data("junk".utf8).write(
            to: root.appendingPathComponent(
                "mission-progress-ledger.json",
                isDirectory: false
            )
        )
        XCTAssertThrowsError(
            try MissionProgressLedgerStore(captureRoot: root).load()
        ) { error in
            XCTAssertEqual(
                error as? MissionProgressLedgerError,
                .schemaMismatch
            )
        }
    }
}
