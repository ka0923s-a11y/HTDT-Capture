import XCTest
@testable import HTDTCaptureCore

/// Temporary adversarial coverage for PR #293 (not for commit):
/// the re-End candidate-preservation chain exercised end-to-end
/// through the real store — a committed entity's
/// `derived_candidate:` link must stay resolvable after the
/// candidates document is rebuilt, or the NEXT annotation commit
/// throws `unresolvableSpatialEvidenceLink`.
final class PR293ReEndPreservationTests: XCTestCase {
    private let spaceID = CoordinateSpaceID()
    private let sessionID = CaptureSessionID()

    private func provenance() -> DerivedShapeProvenance {
        DerivedShapeProvenance(
            sourceEvidenceRefs: ["path:mesh/anchors.json"],
            sourceCoordinateSpaceID: spaceID,
            derivationAlgorithm: "alg",
            derivationVersion: "1",
            fitScore: nil,
            normalizedResidual: nil,
            observationStartSeconds: nil,
            observationEndSeconds: nil
        )
    }

    /// A resolved object proxy — each call produces a fresh record id
    /// at build time, mimicking how re-derivation re-mints ids.
    private func proxy(x: Double, y: Double) -> DerivedShapeProxy {
        DerivedShapeProxy(
            resolution: .resolved,
            selected: DerivedShapeCandidate(
                geometry: .orientedRectangle(
                    DerivedOrientedRectangle(
                        center: DerivedPoint2D(x: x, y: y),
                        width: 3,
                        depth: 4,
                        headingRadians: 0.5
                    )
                ),
                metrics: DerivedShapeFitMetrics(
                    normalizedResidual: 0.1,
                    supportScore: 0.8,
                    fitScore: 0.9
                )
            ),
            candidates: [],
            provenance: provenance(),
            observationSample: [
                DerivedObservationPoint(
                    position: DerivedPoint2D(x: 0, y: 0),
                    evidenceRef: "mesh_anchor:a",
                    evidenceKind: .mesh
                ),
            ]
        )
    }

    /// Builds + wraps a candidates document exactly as the app's
    /// `persistDerivedGeometryCandidates` does.
    private func candidatesDocument(
        snapshot: DerivedShapePreviewSnapshot,
        preserved: [DerivedGeometryCandidateRecord] = []
    ) throws -> (
        doc: WorkingSetSupplementalDocument,
        recordIDs: [DerivedGeometryCandidateID]
    ) {
        let built = try DerivedGeometryCandidatePackageBuilder.build(
            snapshot: snapshot,
            captureRevisionID: CaptureRevisionID(),
            captureSessionID: sessionID,
            sourcePayloadRefs: ["capture_session:\(sessionID)"],
            preservedCandidates: preserved
        )
        let doc = try WorkingSetSupplementalDocument(
            path: DerivedGeometryCandidatePackage.path,
            data: built.package.data,
            declaration: built.declaration,
            coordinateSpaceIDs: [spaceID],
            captureSessionIDs: [sessionID]
        )
        return (doc, built.package.document.candidates.map(\.candidateID))
    }

    /// Same entity shape the app promotes (see DerivedCandidatePromotionTests).
    private func entity(
        candidateID: DerivedGeometryCandidateID,
        extraRefs: [String] = []
    ) throws -> CaptureAnnotationEntity {
        try CaptureAnnotationEntity(
            type: .custom,
            coordinateSpaceID: spaceID,
            worldFromAnnotation: .identity,
            referencePointSemantics: .userReferencePoint,
            label: "promoted",
            provenanceClass: .userAnnotation,
            placement: PlacementProvenance(
                method: .other,
                sourceEvidenceRefs: [
                    "derived_candidate:\(candidateID.description)",
                ]
            ),
            evidenceRefs:
                ["derived_candidate:\(candidateID.description)"]
                    + extraRefs
        )
    }

    /// Verbatim replication of the app-side still-cited gather
    /// (HTDTCaptureApp.swift ~17705): cited ids come from
    /// `committedAnnotationEntities`, the prior document is decoded
    /// from `supplementalDocumentData(path:)`.
    private func stillCitedCandidates(
        store: CaptureWorkingSetStore
    ) async -> [DerivedGeometryCandidateRecord] {
        let citedCandidateIDs = Set(
            (await store.committedAnnotationEntities)
                .flatMap(\.evidenceRefs)
                .compactMap { ref -> DerivedGeometryCandidateID? in
                    guard ref.hasPrefix("derived_candidate:")
                    else { return nil }
                    return DerivedGeometryCandidateID(
                        canonicalString: String(
                            ref.dropFirst("derived_candidate:".count)
                        )
                    )
                }
        )
        guard !citedCandidateIDs.isEmpty,
              let priorData = await store.supplementalDocumentData(
                  path: DerivedGeometryCandidatePackage.path
              ),
              let priorDocument = try? JSONDecoder().decode(
                  DerivedGeometryCandidateDocument.self,
                  from: priorData
              )
        else { return [] }
        return priorDocument.candidates.filter {
            citedCandidateIDs.contains($0.candidateID)
        }
    }

    private func decodedCandidatesDoc(
        store: CaptureWorkingSetStore
    ) async -> DerivedGeometryCandidateDocument? {
        guard let data = await store.supplementalDocumentData(
            path: DerivedGeometryCandidatePackage.path
        ) else { return nil }
        return try? JSONDecoder().decode(
            DerivedGeometryCandidateDocument.self, from: data
        )
    }

    private func tempStore() throws -> (
        CaptureWorkingSetStore, URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (try CaptureWorkingSetStore(rootDirectory: root), root)
    }

    // MARK: - B1: preserved cited record keeps the next commit valid

    func testReEndPreservesCitedCandidateAndNextCommitResolves()
        async throws
    {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // First End: one fresh candidate record X committed.
        let (docV1, idsV1) = try candidatesDocument(
            snapshot: DerivedShapePreviewSnapshot(
                objectProxies: [proxy(x: 1, y: 2)]
            )
        )
        let xID = try XCTUnwrap(idsV1.first)
        try await store.persistSupplementalDocument(docV1)

        // Accessors report committed truth before any annotation.
        var committedDoc = await decodedCandidatesDoc(store: store)
        XCTAssertTrue(
            committedDoc?.candidates.contains {
                $0.candidateID == xID
            } ?? false,
            "supplementalDocumentData must decode to doc containing X"
        )
        let bogus = await store.supplementalDocumentData(
            path: "bogus/p.json"
        )
        XCTAssertNil(bogus)
        let initiallyCommitted = await store.committedAnnotationEntities
        XCTAssertTrue(initiallyCommitted.isEmpty)

        // Promotion: entity cites derived_candidate:X — commits.
        let appendedA = try await store.appendCommittedAnnotationEntity(
            entity(candidateID: xID)
        )
        XCTAssertTrue(appendedA)
        var committed = await store.committedAnnotationEntities
        XCTAssertEqual(committed.count, 1)
        XCTAssertTrue(
            committed[0].evidenceRefs.contains(
                "derived_candidate:\(xID.description)"
            )
        )

        // Re-End: the app-side gather must surface exactly record X.
        let preserved = await stillCitedCandidates(store: store)
        XCTAssertEqual(preserved.map(\.candidateID), [xID])

        // Rebuild: fresh proxy mints a different id Y; X carries over.
        let (docV2, idsV2) = try candidatesDocument(
            snapshot: DerivedShapePreviewSnapshot(
                objectProxies: [proxy(x: 9, y: 9)]
            ),
            preserved: preserved
        )
        XCTAssertTrue(idsV2.contains(xID), "cited record X must survive")
        let yID = try XCTUnwrap(idsV2.first { $0 != xID })
        XCTAssertNotEqual(yID, xID)
        try await store.replaceSupplementalDocument(docV2)

        committedDoc = await decodedCandidatesDoc(store: store)
        XCTAssertTrue(
            committedDoc?.candidates.contains {
                $0.candidateID == xID
            } ?? false
        )

        // CRITICAL: the next annotation commit re-validates entity A's
        // `derived_candidate:X` link — it must still resolve.
        let appendedB = try await store.appendCommittedAnnotationEntity(
            entity(
                candidateID: yID,
                extraRefs: ["path:mesh/anchors.json"]
            )
        )
        XCTAssertTrue(appendedB)
        committed = await store.committedAnnotationEntities
        XCTAssertEqual(committed.count, 2)
    }

    // MARK: - B2: negative control — dropping the cited record orphans

    func testReEndWithoutPreservationOrphansCitedLink() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let (docV1, idsV1) = try candidatesDocument(
            snapshot: DerivedShapePreviewSnapshot(
                objectProxies: [proxy(x: 1, y: 2)]
            )
        )
        let xID = try XCTUnwrap(idsV1.first)
        try await store.persistSupplementalDocument(docV1)
        let appendedA = try await store.appendCommittedAnnotationEntity(
            entity(candidateID: xID)
        )
        XCTAssertTrue(appendedA)

        // Re-End withOUT preservation: cited record X is dropped.
        let (docV2, idsV2) = try candidatesDocument(
            snapshot: DerivedShapePreviewSnapshot(
                objectProxies: [proxy(x: 9, y: 9)]
            ),
            preserved: []
        )
        XCTAssertFalse(idsV2.contains(xID))
        let yID = try XCTUnwrap(idsV2.first)

        // The doc replace itself succeeds — the orphan window is real.
        try await store.replaceSupplementalDocument(docV2)

        // The NEXT commit must fail closed on entity A's orphaned ref.
        do {
            _ = try await store.appendCommittedAnnotationEntity(
                entity(
                    candidateID: yID,
                    extraRefs: ["path:mesh/anchors.json"]
                )
            )
            XCTFail(
                "orphaned derived_candidate link must fail the commit"
            )
        } catch CaptureWorkingSetError
            .unresolvableSpatialEvidenceLink(let ref)
        {
            XCTAssertTrue(
                ref.contains(xID.description),
                "error should name the orphaned ref, got \(ref)"
            )
        }
    }

    // MARK: - B3: dedup treats a strict subset as already committed

    func testAppendDedupSubsetBoundary() async throws {
        let (store, root) = try tempStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let (docV1, idsV1) = try candidatesDocument(
            snapshot: DerivedShapePreviewSnapshot(
                objectProxies: [proxy(x: 1, y: 2)]
            )
        )
        let xID = try XCTUnwrap(idsV1.first)
        try await store.persistSupplementalDocument(docV1)

        // Entity A committed citing {X, path:mesh/anchors.json}.
        let appendedA = try await store.appendCommittedAnnotationEntity(
            entity(
                candidateID: xID,
                extraRefs: ["path:mesh/anchors.json"]
            )
        )
        XCTAssertTrue(appendedA)

        // A strict-subset re-delivery {X} must be deduped — an
        // equality-only check would wrongly commit a second entity.
        let subset = try await store.appendCommittedAnnotationEntity(
            entity(candidateID: xID)
        )
        XCTAssertFalse(subset)
        var count = await store.committedAnnotationEntities.count
        XCTAssertEqual(count, 1)

        // A superset {X, p1, p2} carries new evidence — commits.
        let superset = try await store.appendCommittedAnnotationEntity(
            entity(
                candidateID: xID,
                extraRefs: [
                    "path:mesh/anchors.json",
                    "path:mesh/anchors2.json",
                ]
            )
        )
        XCTAssertTrue(superset)
        count = await store.committedAnnotationEntities.count
        XCTAssertEqual(count, 2)
    }
}
