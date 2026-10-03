import Foundation

public struct DerivedGeometryCandidateID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public enum DerivedGeometrySourceMode: String, Codable, Sendable, Equatable {
    case sceneDepth = "scene_depth"
    case classifiedMesh = "classified_mesh"
    case fused
}

public enum DerivedGeometryRecordKind: String, Codable, Sendable,
    Equatable
{
    case object
    case wallChain = "wall_chain"
}

public enum DerivedGeometryPersistenceError: Error, Sendable, Equatable {
    case emptySourceEvidenceReference
    case emptyDerivationField
    case invalidFitMetric
    case invalidObservationWindow
    case contourPointLimitExceeded
    case resolvedCandidateMissingGeometry
    case unresolvedCandidateCarriesGeometry
    case missingSourcePayloadReference
    case encodedDocumentMismatch
}

/// One persisted derived-geometry candidate (issue bolph71656-ai/HTDT-Capture#249). Each record
/// carries its derivation algorithm/version, source coordinate space,
/// source evidence references, source mode, a bounded point/contour
/// representation, the selected shape candidate when resolved, and
/// confidence/ambiguity diagnostics. Unresolved proxies persist with
/// `resolution != .resolved` and no selected geometry so downstream
/// review can enumerate them as explicitly unresolved.
public struct DerivedGeometryCandidateRecord: Codable, Sendable,
    Equatable
{
    /// Bound on the persisted point/contour representation so the
    /// payload stays bounded independently of the observation stream.
    public static let maxContourPoints = 256

    public let candidateID: DerivedGeometryCandidateID
    public let recordKind: DerivedGeometryRecordKind
    public let resolution: DerivedShapeResolution
    public let shapeKind: DerivedShapeKind?
    public let geometry: DerivedFootprintGeometry?
    /// Shape kinds seen across every competing candidate, sorted for
    /// deterministic output. Empty unless `resolution` is ambiguous.
    public let ambiguityShapeKinds: [DerivedShapeKind]
    public let coordinateSpaceID: CoordinateSpaceID
    public let sourceMode: DerivedGeometrySourceMode
    public let sourceEvidenceRefs: [String]
    public let derivationAlgorithm: String
    public let derivationVersion: String
    public let fitScore: Double?
    public let normalizedResidual: Double?
    public let supportScore: Double?
    public let observationStartSeconds: Double?
    public let observationEndSeconds: Double?
    public let contourPoints: [DerivedObservationPoint]

    public init(
        candidateID: DerivedGeometryCandidateID =
            DerivedGeometryCandidateID(),
        recordKind: DerivedGeometryRecordKind = .object,
        resolution: DerivedShapeResolution,
        shapeKind: DerivedShapeKind? = nil,
        geometry: DerivedFootprintGeometry? = nil,
        ambiguityShapeKinds: [DerivedShapeKind] = [],
        coordinateSpaceID: CoordinateSpaceID,
        sourceMode: DerivedGeometrySourceMode,
        sourceEvidenceRefs: [String],
        derivationAlgorithm: String,
        derivationVersion: String,
        fitScore: Double? = nil,
        normalizedResidual: Double? = nil,
        supportScore: Double? = nil,
        observationStartSeconds: Double? = nil,
        observationEndSeconds: Double? = nil,
        contourPoints: [DerivedObservationPoint] = []
    ) throws {
        let normalizedEvidence = SchemaOwnedText.nfc(sourceEvidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw DerivedGeometryPersistenceError
                .emptySourceEvidenceReference
        }
        let normalizedAlgorithm = SchemaOwnedText.nfc(
            derivationAlgorithm
        )
        let normalizedVersion = SchemaOwnedText.nfc(derivationVersion)
        guard !normalizedAlgorithm.isEmpty,
              !normalizedVersion.isEmpty
        else {
            throw DerivedGeometryPersistenceError.emptyDerivationField
        }
        for metric in [fitScore, normalizedResidual, supportScore] {
            if let metric {
                guard metric.isFinite else {
                    throw DerivedGeometryPersistenceError
                        .invalidFitMetric
                }
            }
        }
        for bound in [
            observationStartSeconds, observationEndSeconds,
        ] {
            if let bound {
                guard bound.isFinite, bound >= 0 else {
                    throw DerivedGeometryPersistenceError
                        .invalidObservationWindow
                }
            }
        }
        if let start = observationStartSeconds,
           let end = observationEndSeconds
        {
            guard start <= end else {
                throw DerivedGeometryPersistenceError
                    .invalidObservationWindow
            }
        }
        guard contourPoints.count <= Self.maxContourPoints else {
            throw DerivedGeometryPersistenceError
                .contourPointLimitExceeded
        }
        if resolution == .resolved {
            guard geometry != nil, shapeKind != nil else {
                throw DerivedGeometryPersistenceError
                    .resolvedCandidateMissingGeometry
            }
        } else {
            guard geometry == nil, shapeKind == nil else {
                throw DerivedGeometryPersistenceError
                    .unresolvedCandidateCarriesGeometry
            }
        }

        self.candidateID = candidateID
        self.recordKind = recordKind
        self.resolution = resolution
        self.shapeKind = shapeKind
        self.geometry = geometry
        self.ambiguityShapeKinds = ambiguityShapeKinds
        self.coordinateSpaceID = coordinateSpaceID
        self.sourceMode = sourceMode
        self.sourceEvidenceRefs = normalizedEvidence
        self.derivationAlgorithm = normalizedAlgorithm
        self.derivationVersion = normalizedVersion
        self.fitScore = fitScore
        self.normalizedResidual = normalizedResidual
        self.supportScore = supportScore
        self.observationStartSeconds = observationStartSeconds
        self.observationEndSeconds = observationEndSeconds
        self.contourPoints = contourPoints
    }

    private enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case recordKind = "record_kind"
        case resolution
        case shapeKind = "shape_kind"
        case geometry
        case ambiguityShapeKinds = "ambiguity_shape_kinds"
        case coordinateSpaceID = "coordinate_space_id"
        case sourceMode = "source_mode"
        case sourceEvidenceRefs = "source_evidence_refs"
        case derivationAlgorithm = "derivation_algorithm"
        case derivationVersion = "derivation_version"
        case fitScore = "fit_score"
        case normalizedResidual = "normalized_residual"
        case supportScore = "support_score"
        case observationStartSeconds = "observation_start_seconds"
        case observationEndSeconds = "observation_end_seconds"
        case contourPoints = "contour_points"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            candidateID: container.decode(
                DerivedGeometryCandidateID.self,
                forKey: .candidateID
            ),
            recordKind: container.decode(
                DerivedGeometryRecordKind.self,
                forKey: .recordKind
            ),
            resolution: container.decode(
                DerivedShapeResolution.self,
                forKey: .resolution
            ),
            shapeKind: container.decodeIfPresent(
                DerivedShapeKind.self,
                forKey: .shapeKind
            ),
            geometry: container.decodeIfPresent(
                DerivedFootprintGeometry.self,
                forKey: .geometry
            ),
            ambiguityShapeKinds: container.decode(
                [DerivedShapeKind].self,
                forKey: .ambiguityShapeKinds
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            sourceMode: container.decode(
                DerivedGeometrySourceMode.self,
                forKey: .sourceMode
            ),
            sourceEvidenceRefs: container.decode(
                [String].self,
                forKey: .sourceEvidenceRefs
            ),
            derivationAlgorithm: container.decode(
                String.self,
                forKey: .derivationAlgorithm
            ),
            derivationVersion: container.decode(
                String.self,
                forKey: .derivationVersion
            ),
            fitScore: container.decodeIfPresent(
                Double.self,
                forKey: .fitScore
            ),
            normalizedResidual: container.decodeIfPresent(
                Double.self,
                forKey: .normalizedResidual
            ),
            supportScore: container.decodeIfPresent(
                Double.self,
                forKey: .supportScore
            ),
            observationStartSeconds: container.decodeIfPresent(
                Double.self,
                forKey: .observationStartSeconds
            ),
            observationEndSeconds: container.decodeIfPresent(
                Double.self,
                forKey: .observationEndSeconds
            ),
            contourPoints: container.decode(
                [DerivedObservationPoint].self,
                forKey: .contourPoints
            )
        )
    }
}

public struct DerivedGeometryCandidateDocument: Codable, Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let candidates: [DerivedGeometryCandidateRecord]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        candidates: [DerivedGeometryCandidateRecord]
    ) {
        self.schema = DerivedGeometryCandidatePackage.schema
        self.schemaVersion =
            DerivedGeometryCandidatePackage.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.candidates = candidates
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case candidates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == DerivedGeometryCandidatePackage.schema,
              schemaVersion
                == DerivedGeometryCandidatePackage.schemaVersion
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription:
                        "Unsupported derived geometry candidate schema"
                )
            )
        }
        try self.init(
            captureRevisionID: container.decode(
                CaptureRevisionID.self,
                forKey: .captureRevisionID
            ),
            captureSessionID: container.decode(
                CaptureSessionID.self,
                forKey: .captureSessionID
            ),
            candidates: container.decode(
                [DerivedGeometryCandidateRecord].self,
                forKey: .candidates
            )
        )
    }
}

public struct DerivedGeometryCandidatePackage: Sendable, Equatable {
    public static let schema = "htdt.capture.derived-geometry-candidates"
    public static let schemaVersion = "1.0.0"
    public static let path = "derived/geometry-candidates.json"

    public let document: DerivedGeometryCandidateDocument
    public let data: Data

    public init(
        document: DerivedGeometryCandidateDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }
}

public enum DerivedGeometryCandidatePackageBuilder {
    /// Derives the persisted source mode from the evidence kinds that
    /// fed the candidate. Pure mesh input stays `classified_mesh`, pure
    /// scene-depth input stays `scene_depth`, and any mixture (or
    /// user-driven spatial observation input) is `fused`.
    public static func sourceMode(
        forEvidenceKinds kinds: Set<DerivedShapeEvidenceKind>
    ) -> DerivedGeometrySourceMode {
        if !kinds.isEmpty, kinds == [.mesh] {
            return .classifiedMesh
        }
        if !kinds.isEmpty, kinds == [.sceneDepth] {
            return .sceneDepth
        }
        return .fused
    }

    /// Live observation refs are stream-local; translate the
    /// derivable ones to committed manifest tokens so HTDT can
    /// attribute the record. `live-mesh:<anchor>:face:<n>` collapses
    /// to `mesh_anchor:<anchor>`; `live-scene-depth:*` stays in the
    /// `live:` namespace (its frames are transient samples, not
    /// committed payloads); the `wall_chain` support marker likewise
    /// stays.
    public static func committedEvidenceRef(_ ref: String) -> String {
        if ref.hasPrefix("live-mesh:") {
            let anchorToken = ref
                .dropFirst("live-mesh:".count)
                .split(separator: ":")
                .first
                .map(String.init)
            if let anchorToken, !anchorToken.isEmpty {
                return "mesh_anchor:" + anchorToken
            }
        }
        return ref
    }

    static func committedEvidenceRefs(
        _ refs: [String]
    ) -> [String] {
        var seen = Set<String>()
        return refs.map(committedEvidenceRef).filter {
            seen.insert($0).inserted
        }
    }

    static func committedGeometry(
        _ geometry: DerivedFootprintGeometry
    ) -> DerivedFootprintGeometry {
        if case .polygon(let polygon) = geometry {
            return .polygon(
                DerivedPolygon(
                    vertices: polygon.vertices.map {
                        SupportedPolygonVertex(
                            position: $0.position,
                            supportEvidenceRefs:
                                committedEvidenceRefs(
                                    $0.supportEvidenceRefs
                                )
                        )
                    },
                    isConcave: polygon.isConcave,
                    concavityResolution:
                        polygon.concavityResolution
                )
            )
        }
        return geometry
    }

    /// Maps a derived-shape proxy into a persisted candidate record.
    public static func record(
        from proxy: DerivedShapeProxy,
        recordKind: DerivedGeometryRecordKind = .object,
        candidateID: DerivedGeometryCandidateID =
            DerivedGeometryCandidateID()
    ) throws -> DerivedGeometryCandidateRecord {
        let kinds = Set(proxy.observationSample.map(\.evidenceKind))
        let ambiguityKinds: [DerivedShapeKind]
        if proxy.resolution == .ambiguousEvidence {
            ambiguityKinds = proxy.candidates.map(\.kind).sorted {
                $0.rawValue < $1.rawValue
            }
        } else {
            ambiguityKinds = []
        }
        let selected = proxy.resolution == .resolved
            ? proxy.selected
            : nil
        return try DerivedGeometryCandidateRecord(
            candidateID: candidateID,
            recordKind: recordKind,
            resolution: proxy.resolution,
            shapeKind: selected?.kind,
            geometry: selected.map {
                committedGeometry($0.geometry)
            },
            ambiguityShapeKinds: ambiguityKinds,
            coordinateSpaceID: proxy.provenance.sourceCoordinateSpaceID,
            sourceMode: sourceMode(forEvidenceKinds: kinds),
            sourceEvidenceRefs: committedEvidenceRefs(
                proxy.provenance.sourceEvidenceRefs
            ),
            derivationAlgorithm: proxy.provenance.derivationAlgorithm,
            derivationVersion: proxy.provenance.derivationVersion,
            fitScore: proxy.provenance.fitScore,
            normalizedResidual: proxy.provenance.normalizedResidual,
            supportScore: selected?.metrics.supportScore,
            observationStartSeconds:
                proxy.provenance.observationStartSeconds,
            observationEndSeconds:
                proxy.provenance.observationEndSeconds,
            contourPoints: Array(
                proxy.observationSample.prefix(
                    DerivedGeometryCandidateRecord.maxContourPoints
                )
            ).map {
                DerivedObservationPoint(
                    position: $0.position,
                    evidenceRef: committedEvidenceRef(
                        $0.evidenceRef
                    ),
                    evidenceKind: $0.evidenceKind,
                    verticalPositionMeters:
                        $0.verticalPositionMeters
                )
            }
        )
    }

    /// Builds the accepted-End derived-geometry candidate payload. Every
    /// record is bounded and carries its own derivation provenance so
    /// HTDT can enumerate candidates after ingestion without consulting
    /// the live pipeline.
    public static func build(
        snapshot: DerivedShapePreviewSnapshot,
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        sourcePayloadRefs: [String]
    ) throws -> (
        package: DerivedGeometryCandidatePackage,
        declaration: BundlePayloadDeclaration
    ) {
        var records: [DerivedGeometryCandidateRecord] = []
        for proxy in snapshot.objectProxies {
            records.append(
                try record(from: proxy, recordKind: .object)
            )
        }
        if let wallChain = snapshot.wallChain {
            let provenance = wallChain.provenance
            let contourPoints = wallChain.vertices.map {
                DerivedObservationPoint(
                    position: $0.position,
                    evidenceRef: committedEvidenceRef(
                        $0.supportEvidenceRefs.first
                            ?? "wall_chain"
                    ),
                    evidenceKind: .mesh
                )
            }
            if wallChain.isClosed, wallChain.vertices.count >= 3 {
                // A supported closed ring is genuinely a polygon.
                let wallChainIsConcave =
                    DerivedShapeProxyFitter.polygonIsConcave(
                        wallChain.vertices.map(\.position),
                        closed: wallChain.isClosed
                    )
                records.append(
                    try DerivedGeometryCandidateRecord(
                        recordKind: .wallChain,
                        resolution: .resolved,
                        shapeKind: .polygon,
                        geometry: .polygon(
                            DerivedPolygon(
                                vertices: wallChain.vertices.map {
                                    SupportedPolygonVertex(
                                        position: $0.position,
                                        supportEvidenceRefs:
                                            committedEvidenceRefs(
                                                $0.supportEvidenceRefs
                                            )
                                    )
                                },
                                isConcave: wallChainIsConcave,
                                concavityResolution: wallChainIsConcave
                                    ? .resolvedConcave
                                    : .resolvedConvex
                            )
                        ),
                        coordinateSpaceID:
                            provenance.sourceCoordinateSpaceID,
                        sourceMode: sourceMode(
                            forEvidenceKinds: [.mesh]
                        ),
                        sourceEvidenceRefs:
                            committedEvidenceRefs(
                                provenance.sourceEvidenceRefs
                            ),
                        derivationAlgorithm:
                            provenance.derivationAlgorithm,
                        derivationVersion:
                            provenance.derivationVersion,
                        fitScore: provenance.fitScore,
                        normalizedResidual:
                            provenance.normalizedResidual,
                        observationStartSeconds:
                            provenance.observationStartSeconds,
                        observationEndSeconds:
                            provenance.observationEndSeconds,
                        contourPoints: contourPoints
                    )
                )
            } else {
                // An open run is a polyline, not a polygon — persisting
                // it as resolved would invent a wall across the
                // unobserved gap. Emit it unresolved so HTDT sees the
                // honest partial observation; the contour still
                // carries every supported vertex.
                records.append(
                    try DerivedGeometryCandidateRecord(
                        recordKind: .wallChain,
                        resolution: .insufficientEvidence,
                        coordinateSpaceID:
                            provenance.sourceCoordinateSpaceID,
                        sourceMode: sourceMode(
                            forEvidenceKinds: [.mesh]
                        ),
                        sourceEvidenceRefs:
                            committedEvidenceRefs(
                                provenance.sourceEvidenceRefs
                            ),
                        derivationAlgorithm:
                            provenance.derivationAlgorithm,
                        derivationVersion:
                            provenance.derivationVersion,
                        observationStartSeconds:
                            provenance.observationStartSeconds,
                        observationEndSeconds:
                            provenance.observationEndSeconds,
                        contourPoints: contourPoints
                    )
                )
            }
        }

        let document = DerivedGeometryCandidateDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            candidates: records
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                DerivedGeometryCandidateDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw DerivedGeometryPersistenceError
                .encodedDocumentMismatch
        }

        let normalizedRefs = SchemaOwnedText.nfc(sourcePayloadRefs)
        guard !normalizedRefs.isEmpty else {
            throw DerivedGeometryPersistenceError
                .missingSourcePayloadReference
        }
        let declaration = BundlePayloadDeclaration(
            path: DerivedGeometryCandidatePackage.path,
            mediaType: "application/json",
            producer: "derived_geometry",
            provenanceClass: .captureAppDerived,
            role: .derived,
            sourceRefs: normalizedRefs
        )
        return (
            DerivedGeometryCandidatePackage(
                document: document,
                data: data
            ),
            declaration
        )
    }
}
