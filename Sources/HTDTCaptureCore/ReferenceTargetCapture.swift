import Foundation

public struct ReferenceTargetID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

public struct ReferenceTargetObservationID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// Where the known physical dimensions of a declared reference target
/// come from. Dimensions are only trustworthy with an explicit
/// authority — never inferred from the scan.
public enum ReferenceTargetDimensionAuthority: String, Codable,
    Sendable, Equatable
{
    case userSupplied = "user_supplied"
    case manufacturerSpecification = "manufacturer_specification"
    case calibrationAuthority = "calibration_authority"
}

public enum ReferenceTargetError: Error, Sendable, Equatable {
    case emptyField
    case invalidDimension
    case invalidResidualValue
    case invalidObservationIndex
    case undeclaredTarget
    case duplicateTargetID
    case duplicateObservationID
    case duplicateEvidenceReference
    case encodedDocumentMismatch
}

/// A fiducial/reference target declared for this capture with its known
/// physical dimensions and the authority those dimensions come from
/// (issue #227).
public struct ReferenceTargetDeclaration: Codable, Sendable, Equatable {
    public let targetID: ReferenceTargetID
    /// Operator-facing target type token (e.g. "checkerboard_6x8",
    /// "apriltag_36h11_100mm") documented by the capture runbook.
    public let targetType: String
    /// Known physical dimension used for scale residuals, meters.
    public let knownDimensionMeters: Double
    public let dimensionAuthority: ReferenceTargetDimensionAuthority
    /// Free-text citation of the authority (datasheet, calibration
    /// certificate id, or note that the user measured it).
    public let authorityRef: String

    public init(
        targetID: ReferenceTargetID = ReferenceTargetID(),
        targetType: String,
        knownDimensionMeters: Double,
        dimensionAuthority: ReferenceTargetDimensionAuthority,
        authorityRef: String
    ) throws {
        let normalizedType = SchemaOwnedText.nfc(targetType)
        let normalizedAuthorityRef = SchemaOwnedText.nfc(authorityRef)
        guard !normalizedType.isEmpty, !normalizedAuthorityRef.isEmpty
        else {
            throw ReferenceTargetError.emptyField
        }
        guard knownDimensionMeters.isFinite,
              knownDimensionMeters > 0
        else {
            throw ReferenceTargetError.invalidDimension
        }
        self.targetID = targetID
        self.targetType = normalizedType
        self.knownDimensionMeters = knownDimensionMeters
        self.dimensionAuthority = dimensionAuthority
        self.authorityRef = normalizedAuthorityRef
    }

    private enum CodingKeys: String, CodingKey {
        case targetID = "target_id"
        case targetType = "target_type"
        case knownDimensionMeters = "known_dimension_m"
        case dimensionAuthority = "dimension_authority"
        case authorityRef = "authority_ref"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            targetID: container.decode(
                ReferenceTargetID.self,
                forKey: .targetID
            ),
            targetType: container.decode(
                String.self,
                forKey: .targetType
            ),
            knownDimensionMeters: container.decode(
                Double.self,
                forKey: .knownDimensionMeters
            ),
            dimensionAuthority: container.decode(
                ReferenceTargetDimensionAuthority.self,
                forKey: .dimensionAuthority
            ),
            authorityRef: container.decode(
                String.self,
                forKey: .authorityRef
            )
        )
    }
}

/// One evidence-linked sighting of a declared reference target. The
/// first observation is typically captured early; later observations
/// near End are revisits and feed revisit-displacement diagnostics.
public struct ReferenceTargetObservation: Codable, Sendable, Equatable {
    public let observationID: ReferenceTargetObservationID
    public let targetID: ReferenceTargetID
    public let coordinateSpaceID: CoordinateSpaceID
    /// 0 is the initial observation; >= 1 are revisits.
    public let observationIndex: Int
    /// Observed world-space center of the target, when the platform
    /// can place it.
    public let positionWorld: SpatialVector3F?
    /// Observed on-target dimension (e.g. measured edge length), meters.
    public let measuredDimensionMeters: Double?
    public let sessionTimestampSeconds: Double?
    public let evidenceRefs: [String]

    public init(
        observationID: ReferenceTargetObservationID =
            ReferenceTargetObservationID(),
        targetID: ReferenceTargetID,
        coordinateSpaceID: CoordinateSpaceID,
        observationIndex: Int,
        positionWorld: SpatialVector3F? = nil,
        measuredDimensionMeters: Double? = nil,
        sessionTimestampSeconds: Double? = nil,
        evidenceRefs: [String] = []
    ) throws {
        guard observationIndex >= 0 else {
            throw ReferenceTargetError.invalidObservationIndex
        }
        if let measuredDimensionMeters {
            guard measuredDimensionMeters.isFinite,
                  measuredDimensionMeters > 0
            else {
                throw ReferenceTargetError.invalidDimension
            }
        }
        if let sessionTimestampSeconds {
            guard sessionTimestampSeconds.isFinite,
                  sessionTimestampSeconds >= 0
            else {
                throw ReferenceTargetError.invalidObservationIndex
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy({ !$0.isEmpty }) else {
            throw ReferenceTargetError.emptyField
        }
        guard Set(normalizedEvidence).count == normalizedEvidence.count
        else {
            throw ReferenceTargetError.duplicateEvidenceReference
        }
        self.observationID = observationID
        self.targetID = targetID
        self.coordinateSpaceID = coordinateSpaceID
        self.observationIndex = observationIndex
        self.positionWorld = positionWorld
        self.measuredDimensionMeters = measuredDimensionMeters
        self.sessionTimestampSeconds = sessionTimestampSeconds
        self.evidenceRefs = normalizedEvidence
    }

    private enum CodingKeys: String, CodingKey {
        case observationID = "observation_id"
        case targetID = "target_id"
        case coordinateSpaceID = "coordinate_space_id"
        case observationIndex = "observation_index"
        case positionWorld = "position_world"
        case measuredDimensionMeters = "measured_dimension_m"
        case sessionTimestampSeconds = "session_timestamp_seconds"
        case evidenceRefs = "evidence_refs"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            observationID: container.decode(
                ReferenceTargetObservationID.self,
                forKey: .observationID
            ),
            targetID: container.decode(
                ReferenceTargetID.self,
                forKey: .targetID
            ),
            coordinateSpaceID: container.decode(
                CoordinateSpaceID.self,
                forKey: .coordinateSpaceID
            ),
            observationIndex: container.decode(
                Int.self,
                forKey: .observationIndex
            ),
            positionWorld: container.decodeIfPresent(
                SpatialVector3F.self,
                forKey: .positionWorld
            ),
            measuredDimensionMeters: container.decodeIfPresent(
                Double.self,
                forKey: .measuredDimensionMeters
            ),
            sessionTimestampSeconds: container.decodeIfPresent(
                Double.self,
                forKey: .sessionTimestampSeconds
            ),
            evidenceRefs: container.decode(
                [String].self,
                forKey: .evidenceRefs
            )
        )
    }
}

/// Advisory per-target diagnostics (issue #227): residuals between
/// observed and known dimensions plus revisit displacement. These are
/// diagnostics surfaced to review — they never feed back as silent
/// corrections.
public struct ReferenceTargetDiagnostics: Codable, Sendable, Equatable {
    public let targetID: ReferenceTargetID
    /// (observed - known) / known; nil when no observation carries a
    /// measured dimension.
    public let scaleResidualFraction: Double?
    /// Greatest distance between the earliest observation's position
    /// and any later revisit position, meters.
    public let revisitDisplacementMeters: Double?

    public init(
        targetID: ReferenceTargetID,
        scaleResidualFraction: Double?,
        revisitDisplacementMeters: Double?
    ) throws {
        for value in [scaleResidualFraction, revisitDisplacementMeters] {
            if let value {
                guard value.isFinite else {
                    throw ReferenceTargetError.invalidResidualValue
                }
            }
        }
        self.targetID = targetID
        self.scaleResidualFraction = scaleResidualFraction
        self.revisitDisplacementMeters = revisitDisplacementMeters
    }

    private enum CodingKeys: String, CodingKey {
        case targetID = "target_id"
        case scaleResidualFraction = "scale_residual_fraction"
        case revisitDisplacementMeters = "revisit_displacement_m"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            targetID: container.decode(
                ReferenceTargetID.self,
                forKey: .targetID
            ),
            scaleResidualFraction: container.decodeIfPresent(
                Double.self,
                forKey: .scaleResidualFraction
            ),
            revisitDisplacementMeters: container.decodeIfPresent(
                Double.self,
                forKey: .revisitDisplacementMeters
            )
        )
    }
}

public struct ReferenceTargetCaptureDocument: Codable, Sendable,
    Equatable
{
    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    public let captureSessionID: CaptureSessionID
    public let targets: [ReferenceTargetDeclaration]
    public let observations: [ReferenceTargetObservation]
    public let diagnostics: [ReferenceTargetDiagnostics]

    public init(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        targets: [ReferenceTargetDeclaration],
        observations: [ReferenceTargetObservation],
        diagnostics: [ReferenceTargetDiagnostics]
    ) throws {
        guard Set(targets.map(\.targetID)).count == targets.count
        else {
            throw ReferenceTargetError.duplicateTargetID
        }
        guard Set(observations.map(\.observationID)).count
                == observations.count
        else {
            throw ReferenceTargetError.duplicateObservationID
        }
        let declaredIDs = Set(targets.map(\.targetID))
        guard observations.allSatisfy({
            declaredIDs.contains($0.targetID)
        }) else {
            throw ReferenceTargetError.undeclaredTarget
        }
        guard diagnostics.allSatisfy({
            declaredIDs.contains($0.targetID)
        }) else {
            throw ReferenceTargetError.undeclaredTarget
        }
        self.schema = ReferenceTargetCapturePackage.schema
        self.schemaVersion =
            ReferenceTargetCapturePackage.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.captureSessionID = captureSessionID
        self.targets = targets
        self.observations = observations
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case captureSessionID = "capture_session_id"
        case targets
        case observations
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try container.decode(String.self, forKey: .schema)
        let schemaVersion = try container.decode(
            String.self,
            forKey: .schemaVersion
        )
        guard schema == ReferenceTargetCapturePackage.schema,
              schemaVersion
                == ReferenceTargetCapturePackage.schemaVersion
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription:
                        "Unsupported reference target schema"
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
            targets: container.decode(
                [ReferenceTargetDeclaration].self,
                forKey: .targets
            ),
            observations: container.decode(
                [ReferenceTargetObservation].self,
                forKey: .observations
            ),
            diagnostics: container.decode(
                [ReferenceTargetDiagnostics].self,
                forKey: .diagnostics
            )
        )
    }
}

public struct ReferenceTargetCapturePackage: Sendable, Equatable {
    public static let schema = "htdt.capture.reference-targets"
    public static let schemaVersion = "1.0.0"
    public static let path = "evidence/reference-targets.json"

    public let document: ReferenceTargetCaptureDocument
    public let data: Data

    public init(
        document: ReferenceTargetCaptureDocument,
        data: Data
    ) {
        self.document = document
        self.data = data
    }

    /// Lineage refs for the store's derived-payload declaration —
    /// the bound capture session.
    public var sourceRefs: [String] {
        ["capture_session:" + document.captureSessionID.description]
    }
}

public enum ReferenceTargetCaptureBuilder {
    /// Computes advisory residuals for one declared target.
    public static func diagnostics(
        for declaration: ReferenceTargetDeclaration,
        observations: [ReferenceTargetObservation]
    ) throws -> ReferenceTargetDiagnostics {
        let scoped = observations
            .filter { $0.targetID == declaration.targetID }
            .sorted { $0.observationIndex < $1.observationIndex }

        let measured = scoped.compactMap(\.measuredDimensionMeters)
        let scaleResidual: Double? = measured.isEmpty
            ? nil
            : (measured.reduce(0, +) / Double(measured.count)
                - declaration.knownDimensionMeters)
                / declaration.knownDimensionMeters

        var revisitDisplacement: Double? = nil
        if let origin = scoped.first?.positionWorld {
            let later = scoped.dropFirst().compactMap(\.positionWorld)
            if !later.isEmpty {
                let maxDistanceSquared = later.map { point -> Float in
                    let dx = point.x - origin.x
                    let dy = point.y - origin.y
                    let dz = point.z - origin.z
                    return dx * dx + dy * dy + dz * dz
                }.max() ?? 0
                revisitDisplacement = Double(
                    maxDistanceSquared.squareRoot()
                )
            }
        }
        return try ReferenceTargetDiagnostics(
            targetID: declaration.targetID,
            scaleResidualFraction: scaleResidual,
            revisitDisplacementMeters: revisitDisplacement
        )
    }

    /// Builds the reference-target payload. Capture without any targets
    /// is valid — the app simply never calls this builder.
    public static func build(
        captureRevisionID: CaptureRevisionID,
        captureSessionID: CaptureSessionID,
        targets: [ReferenceTargetDeclaration],
        observations: [ReferenceTargetObservation]
    ) throws -> ReferenceTargetCapturePackage {
        let computedDiagnostics = try targets.map {
            try Self.diagnostics(for: $0, observations: observations)
        }
        let document = try ReferenceTargetCaptureDocument(
            captureRevisionID: captureRevisionID,
            captureSessionID: captureSessionID,
            targets: targets,
            observations: observations,
            diagnostics: computedDiagnostics
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys, .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)
        guard
            let decoded = try? JSONDecoder().decode(
                ReferenceTargetCaptureDocument.self,
                from: data
            ),
            decoded == document
        else {
            throw ReferenceTargetError.encodedDocumentMismatch
        }
        return ReferenceTargetCapturePackage(
            document: document,
            data: data
        )
    }

    /// Review-surface diagnostics: one quality diagnostic per target
    /// that produced a residual, all advisory severity. These never
    /// gate finalization.
    public static func reviewDiagnostics(
        for document: ReferenceTargetCaptureDocument
    ) -> [QualityDiagnostic] {
        var diagnostics: [QualityDiagnostic] = []
        for diagnostic in document.diagnostics {
            if let scaleResidual = diagnostic.scaleResidualFraction {
                diagnostics.append(
                    QualityDiagnostic(
                        code: "reference_target_scale_residual",
                        severity: .info,
                        message:
                            "Reference target \(diagnostic.targetID) scale residual \(scaleResidual)",
                        evidenceRefs: [
                            "reference_target:\(diagnostic.targetID)"
                        ]
                    )
                )
            }
            if let displacement =
                diagnostic.revisitDisplacementMeters
            {
                diagnostics.append(
                    QualityDiagnostic(
                        code:
                            "reference_target_revisit_displacement",
                        severity: .info,
                        message:
                            "Reference target \(diagnostic.targetID) revisit displacement \(displacement) m",
                        evidenceRefs: [
                            "reference_target:\(diagnostic.targetID)"
                        ]
                    )
                )
            }
        }
        return diagnostics
    }
}
