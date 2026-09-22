import Foundation

/// Floor-plan reference mode (issue #322): an imported, operator-scaled
/// drawing or HTDT coordinate reference that guides capture. The
/// underlay is `.importedReference` provenance — authoritative as a
/// *reference* only, never as observed truth: no plan geometry is ever
/// copied into observed payloads, disagreement between plan and
/// observation is preserved rather than averaged away, and the
/// alignment residual stays visible on the document itself.
public enum PlanUnderlaySourceKind: String, Codable, Sendable {
    /// Raster drawing file the operator imported (PNG/PDF page).
    case imageFile = "image_file"
    /// Vector drawing file (SVG/DWG export already converted to a
    /// drawable form).
    case vectorFile = "vector_file"
    /// An HTDT coordinate-space reference the operator selected —
    /// no file content, the identity is the authority.
    case htdtReference = "htdt_reference"
}

/// How the plan underlay's scale/alignment into the capture's
/// `coordinate_space_id` was established (issue #322). The method is
/// always explicit and operator- or authority-supplied — scale is
/// never inferred from pixel density, image DPI, bounding-box
/// similarity, or any other implicit cue.
public enum PlanUnderlayAlignmentMethod: String, Codable, Sendable {
    /// The operator bound the underlay through the capture's HTDT
    /// datum authority (the room reference frame, issue #232). No
    /// local points are needed — the datum is the scale authority.
    case htdtDatum = "htdt_datum"
    /// ≥2 operator-marked reference points on the drawing paired with
    /// measured capture-space positions; scale follows from the
    /// declared known distance between them.
    case referencePointPair = "reference_point_pair"
    /// A single operator-declared known distance + axis on the plan
    /// fixes scale and orientation.
    case knownDistanceAxis = "known_distance_axis"
    /// Alignment through registered fiducials/registration targets
    /// (issue #227) observed in capture space.
    case fiducialAlignment = "fiducial_alignment"
}

public enum PlanUnderlayError: Error, Sendable, Equatable {
    case invalidTimestamp
    case invalidSHA256
    case emptyField
    case missingReferencePoints
    case missingKnownDistance
    case nonFiniteValue
    case duplicatePointLabel
    case encodedDocumentMismatch
}

/// One operator-marked reference point (issue #322): a labeled point
/// on the drawing plane plus the capture-space position the operator
/// associated with it. `planXMeters`/`planYMeters` live in the plan's
/// own coordinate frame (meters at the declared scale), while
/// `capturePoint` is the observed capture-space position.
public struct PlanUnderlayReferencePoint:
    Codable,
    Sendable,
    Equatable
{
    public let label: String
    public let planXMeters: Double
    public let planYMeters: Double
    public let capturePoint: WorldPoint3D

    public init(
        label: String,
        planXMeters: Double,
        planYMeters: Double,
        capturePoint: WorldPoint3D
    ) throws {
        let normalized = SchemaOwnedText.nfc(label)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw PlanUnderlayError.emptyField
        }
        guard planXMeters.isFinite,
              planYMeters.isFinite,
              capturePoint.isFinite
        else {
            throw PlanUnderlayError.nonFiniteValue
        }
        self.label = normalized
        self.planXMeters = planXMeters
        self.planYMeters = planYMeters
        self.capturePoint = capturePoint
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case planXMeters = "plan_x_m"
        case planYMeters = "plan_y_m"
        case capturePoint = "capture_point"
    }
}

/// An operator-declared known distance on the plan (issue #322): the
/// only legitimate non-authority scale source. The distance is a real-
/// world measurement (e.g. "this wall is 8.4 m") the operator attests,
/// attached to two plan-frame endpoints that also fix orientation.
public struct PlanUnderlayKnownDistance:
    Codable,
    Sendable,
    Equatable
{
    public let fromX: Double
    public let fromY: Double
    public let toX: Double
    public let toY: Double
    /// The attested real-world length of the segment, meters.
    public let meters: Double
    /// Axis the segment defines: `"x"` or `"y"` of the plan frame.
    public let axis: String

    public init(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        meters: Double,
        axis: String
    ) throws {
        guard fromX.isFinite, fromY.isFinite,
              toX.isFinite, toY.isFinite,
              meters.isFinite, meters > 0
        else {
            throw PlanUnderlayError.nonFiniteValue
        }
        let normalizedAxis = SchemaOwnedText.nfc(axis)
            .lowercased()
        guard normalizedAxis == "x" || normalizedAxis == "y" else {
            throw PlanUnderlayError.emptyField
        }
        self.fromX = fromX
        self.fromY = fromY
        self.toX = toX
        self.toY = toY
        self.meters = meters
        self.axis = normalizedAxis
    }

    private enum CodingKeys: String, CodingKey {
        case fromX = "from_x_m"
        case fromY = "from_y_m"
        case toX = "to_x_m"
        case toY = "to_y_m"
        case meters
        case axis
    }
}

/// The declared alignment of an underlay into capture space
/// (issue #322). `residualMeters` is the RMS alignment error the
/// operator measured — always surfaced, never folded into observed
/// geometry; a plan with a large residual is visibly less aligned.
public struct PlanUnderlayAlignment: Codable, Sendable, Equatable {
    public let method: PlanUnderlayAlignmentMethod
    /// Reference points the method uses (`reference_point_pair` and
    /// `fiducial_alignment` require ≥2; other methods may add context).
    public let referencePoints: [PlanUnderlayReferencePoint]
    /// Required for `known_distance_axis`.
    public let knownDistance: PlanUnderlayKnownDistance?
    /// Measured RMS residual of the fit, meters; nil when the method
    /// yields no measurable error (e.g. datum authority).
    public let residualMeters: Double?
    /// UTC the alignment was established on this device.
    public let alignedAtUTC: String

    public init(
        method: PlanUnderlayAlignmentMethod,
        referencePoints: [PlanUnderlayReferencePoint] = [],
        knownDistance: PlanUnderlayKnownDistance? = nil,
        residualMeters: Double? = nil,
        alignedAtUTC: String
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(alignedAtUTC) else {
            throw PlanUnderlayError.invalidTimestamp
        }
        switch method {
        case .referencePointPair, .fiducialAlignment:
            guard referencePoints.count >= 2 else {
                throw PlanUnderlayError.missingReferencePoints
            }
        case .knownDistanceAxis:
            guard knownDistance != nil else {
                throw PlanUnderlayError.missingKnownDistance
            }
        case .htdtDatum:
            break
        }
        var seen = Set<String>()
        for point in referencePoints {
            guard seen.insert(point.label).inserted else {
                throw PlanUnderlayError.duplicatePointLabel
            }
        }
        if let residualMeters {
            guard residualMeters.isFinite, residualMeters >= 0 else {
                throw PlanUnderlayError.nonFiniteValue
            }
        }
        self.method = method
        self.referencePoints = referencePoints
        self.knownDistance = knownDistance
        self.residualMeters = residualMeters
        self.alignedAtUTC = alignedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case referencePoints = "reference_points"
        case knownDistance = "known_distance"
        case residualMeters = "residual_m"
        case alignedAtUTC = "aligned_at"
    }
}

/// Persisted `reference/plan-underlay.json` (issue #322): the declared
/// underlay for one capture revision — where the source came from
/// (file hash or HTDT reference identity), how it was explicitly
/// scaled/aligned, and the visible residual. The document is the
/// *reference declaration*; plan geometry itself stays outside the
/// bundle or in `.importedReference` payloads and is never re-typed
/// as observation.
public struct PlanUnderlayDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.plan-underlay"
    public static let schemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    public let captureRevisionID: CaptureRevisionID
    /// Capture space the underlay is aligned into.
    public let coordinateSpaceID: CoordinateSpaceID
    public let sourceKind: PlanUnderlaySourceKind
    /// Original filename for file sources; nil for `htdt_reference`.
    public let sourceFilename: String?
    /// Declared media type of the source file (e.g. `image/png`).
    public let sourceMediaType: String?
    /// SHA-256 of the imported file bytes — binds the reference
    /// declaration to the exact drawing the operator scaled. Stored
    /// in the document (not a manifest `source_refs` edge) because the
    /// source file itself is not a bundle payload.
    public let sourceSHA256: String?
    /// Identity of the HTDT reference for `htdt_reference` sources.
    public let htdtReferenceID: String?
    public let alignment: PlanUnderlayAlignment
    /// UTC the underlay was registered on this device.
    public let importedAtUTC: String

    public init(
        captureRevisionID: CaptureRevisionID,
        coordinateSpaceID: CoordinateSpaceID,
        sourceKind: PlanUnderlaySourceKind,
        sourceFilename: String? = nil,
        sourceMediaType: String? = nil,
        sourceSHA256: String? = nil,
        htdtReferenceID: String? = nil,
        alignment: PlanUnderlayAlignment,
        importedAtUTC: String
    ) throws {
        guard SchemaTimestampText.isUTCTimestamp(importedAtUTC) else {
            throw PlanUnderlayError.invalidTimestamp
        }
        let normalizedFilename = SchemaOwnedText
            .nfc(sourceFilename)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMedia = SchemaOwnedText
            .nfc(sourceMediaType)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReference = SchemaOwnedText
            .nfc(htdtReferenceID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch sourceKind {
        case .imageFile, .vectorFile:
            guard normalizedFilename?.isEmpty == false,
                  normalizedMedia?.isEmpty == false
            else {
                throw PlanUnderlayError.emptyField
            }
            guard let digest = sourceSHA256,
                  (try? EvidenceSHA256(digest)) != nil
            else {
                throw PlanUnderlayError.invalidSHA256
            }
        case .htdtReference:
            guard normalizedReference?.isEmpty == false else {
                throw PlanUnderlayError.emptyField
            }
        }
        if let digest = sourceSHA256 {
            _ = try EvidenceSHA256(digest)
        }
        self.schema = Self.schema
        self.schemaVersion = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.coordinateSpaceID = coordinateSpaceID
        self.sourceKind = sourceKind
        self.sourceFilename =
            normalizedFilename?.isEmpty == true
                ? nil
                : normalizedFilename
        self.sourceMediaType =
            normalizedMedia?.isEmpty == true ? nil : normalizedMedia
        self.sourceSHA256 = sourceSHA256
        self.htdtReferenceID =
            normalizedReference?.isEmpty == true
                ? nil
                : normalizedReference
        self.alignment = alignment
        self.importedAtUTC = importedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case coordinateSpaceID = "coordinate_space_id"
        case sourceKind = "source_kind"
        case sourceFilename = "source_filename"
        case sourceMediaType = "source_media_type"
        case sourceSHA256 = "source_sha256"
        case htdtReferenceID = "htdt_reference_id"
        case alignment
        case importedAtUTC = "imported_at"
    }
}

/// Encoded `reference/plan-underlay.json` ready for the working set
/// (issue #322). `.importedReference` provenance marks the payload as
/// operator-supplied truth-by-declaration, distinct from every derived
/// or observed payload in the bundle.
public struct PlanUnderlayPackage: Sendable, Equatable {
    public static let path = "reference/plan-underlay.json"

    public let document: PlanUnderlayDocument
    public let data: Data

    public init(document: PlanUnderlayDocument, data: Data) {
        self.document = document
        self.data = data
    }

    public var payloadDeclaration: BundlePayloadDeclaration {
        BundlePayloadDeclaration(
            path: Self.path,
            mediaType: "application/json",
            producer: "capture_app",
            provenanceClass: .importedReference,
            role: .canonical
        )
    }
}

public enum PlanUnderlayPackageBuilder {
    public static func build(
        document: PlanUnderlayDocument
    ) throws -> PlanUnderlayPackage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let data = try encoder.encode(document)

        guard let decoded = try? JSONDecoder().decode(
            PlanUnderlayDocument.self,
            from: data
        ), decoded == document else {
            throw PlanUnderlayError.encodedDocumentMismatch
        }
        return PlanUnderlayPackage(
            document: document,
            data: data
        )
    }
}

/// Per-reference-point support state for the #322 advisory: does the
/// observed coverage map near this plan anchor claim any observation?
/// `unsupported` means the plan region around the point has no
/// observed coverage within the search radius — the region stays
/// highlighted as plan-only so disagreement is never averaged away.
public enum PlanUnderlaySupportState: String, Sendable, Equatable {
    case observed
    case weaklySupported = "weakly_supported"
    case unsupported
}

/// Which declared plan reference points currently lack observed
/// support (issue #322). Purely diagnostic: the underlay's geometry is
/// never merged into observed coverage and an unsupported point is a
/// visible mismatch, not an error.
public struct PlanUnderlaySupportFinding:
    Sendable,
    Equatable
{
    public let pointLabel: String
    public let state: PlanUnderlaySupportState
    /// Distance in meters from the plan anchor to the nearest
    /// observed/weak coverage cell center; nil when no coverage exists.
    public let nearestCoverageDistanceMeters: Double?

    public init(
        pointLabel: String,
        state: PlanUnderlaySupportState,
        nearestCoverageDistanceMeters: Double? = nil
    ) {
        self.pointLabel = pointLabel
        self.state = state
        self.nearestCoverageDistanceMeters =
            nearestCoverageDistanceMeters
    }
}

/// Evaluates the committed underlay's reference points against the
/// live spatial-coverage summary (#322). A plan anchor maps onto the
/// coverage grid through its declared `capture_point` — plan-vs-
/// observed stays visually distinguishable because the advisory
/// reports per-point support rather than a merged score.
public enum PlanUnderlaySupportEvaluator {
    /// Horizontal distance within which a coverage cell center counts
    /// as supporting the plan anchor. One cell diagonal + slack keeps
    /// the check local without pretending sub-cell precision exists.
    public static func supportRadiusMeters(
        cellSizeMeters: Double
    ) -> Double {
        cellSizeMeters * 2.0
    }

    public static func evaluate(
        underlay: PlanUnderlayDocument,
        coverage: SpatialScanCoverageSummary
    ) -> [PlanUnderlaySupportFinding] {
        let cellSize = coverage.cellSizeMeters
        let radius = supportRadiusMeters(cellSizeMeters: cellSize)
        var findings: [PlanUnderlaySupportFinding] = []
        for point in underlay.alignment.referencePoints {
            let px = point.capturePoint.x
            let pz = point.capturePoint.z
            var nearestObserved: Double?
            var nearestWeak: Double?
            for region in coverage.regions {
                guard region.classification != .unknown else {
                    continue
                }
                // Cell center in the plan's capture coordinate axes:
                // the coverage grid is start-relative, which is the
                // same XZ world plane the alignment declared.
                let centerX = (Double(region.key.x) + 0.5) * cellSize
                let centerZ = (Double(region.key.z) + 0.5) * cellSize
                let dx = centerX - px
                let dz = centerZ - pz
                let distance = (dx * dx + dz * dz).squareRoot()
                if region.classification == .observed {
                    if distance <= radius {
                        nearestObserved = min(
                            nearestObserved ?? .greatestFiniteMagnitude,
                            distance
                        )
                    }
                } else if distance <= radius {
                    nearestWeak = min(
                        nearestWeak ?? .greatestFiniteMagnitude,
                        distance
                    )
                }
            }
            let state: PlanUnderlaySupportState
            let nearest: Double?
            if let nearestObserved {
                state = .observed
                nearest = nearestObserved
            } else if let nearestWeak {
                state = .weaklySupported
                nearest = nearestWeak
            } else {
                state = .unsupported
                nearest = nil
            }
            findings.append(
                PlanUnderlaySupportFinding(
                    pointLabel: point.label,
                    state: state,
                    nearestCoverageDistanceMeters: nearest
                )
            )
        }
        return findings
    }
}
