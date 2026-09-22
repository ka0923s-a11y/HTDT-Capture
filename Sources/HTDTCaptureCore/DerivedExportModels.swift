import Foundation

/// Convenience 3D formats the app can emit from a finalized capture
/// (issue #306). These are DERIVED artifacts: they are not canonical
/// capture evidence, are never written inside the inventoried
/// `finalized/`/`exports/`/`working/` roots, and never include camera
/// imagery or depth.
public enum DerivedExportFormat:
    String,
    Codable,
    Sendable,
    CaseIterable,
    Identifiable
{
    case usdz
    case glb
    case obj
    case ply

    public var id: String { rawValue }

    public var filenameExtension: String { rawValue }

    public var mediaType: String {
        switch self {
        case .usdz: "model/vnd.usdz+zip"
        case .glb: "model/gltf-binary"
        case .obj: "model/obj"
        case .ply: "application/x-ply"
        }
    }
}

/// Which captured geometry source a derived 3D export is built from.
public enum DerivedExportSourceKind:
    String,
    Codable,
    Sendable,
    CaseIterable,
    Identifiable
{
    /// RoomPlan's processed `CapturedRoom` (`roomplan/captured-room.json`)
    /// — parametric surfaces and objects.
    case roomPlanProcessed = "roomplan_processed"
    /// The recorded ARKit mesh anchors (`mesh/anchors.json` +
    /// `mesh/geometry/*.meshbin`) merged into capture world space.
    case arMeshAnchors = "arkit_mesh_anchors"

    public var id: String { rawValue }

    /// Formats this source can produce. USDZ is RoomPlan-native only.
    public var supportedFormats: [DerivedExportFormat] {
        switch self {
        case .roomPlanProcessed:
            [.usdz, .glb, .obj, .ply]
        case .arMeshAnchors:
            [.glb, .obj, .ply]
        }
    }
}

/// What the exported geometry represents — recorded so a downstream
/// consumer cannot mistake a box model for measured mesh.
public enum DerivedExportRepresentation: String, Codable, Sendable {
    /// USDZ produced by RoomPlan's own `CapturedRoom.export` —
    /// parametric surfaces/objects as authored by RoomPlan.
    case roomPlanNativeParametric = "roomplan_native_parametric"
    /// Axis-aligned bounding boxes synthesized from RoomPlan surface
    /// and object extents — NOT measured surface geometry.
    case roomPlanBoundingBoxes = "roomplan_bounding_boxes"
    /// The recorded ARKit scene mesh merged into capture world space.
    case arMeshWorldGeometry = "arkit_mesh_world_geometry"
}

/// One canonical payload consumed by a derived export, with the digest
/// of the exact bytes read.
public struct DerivedExportSourcePayload: Codable, Sendable, Equatable {
    public let path: String
    public let sha256: EvidenceSHA256
    public let byteCount: Int

    public init(path: String, sha256: EvidenceSHA256, byteCount: Int) {
        self.path = path
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

/// The provenance record written next to every derived artifact
/// (`<name>.provenance.json`). It names the exact capture revision and
/// bundle digest the output was derived from, the coordinate space the
/// geometry lives in, and the conversion the exporter applied — so a
/// shared USDZ/OBJ can always be traced back to its evidence (issue
/// #306).
public struct DerivedExportProvenance: Codable, Sendable, Equatable {
    public static let expectedSchema = "htdt.derived-export"
    public static let expectedSchemaVersion = "1.0.0"

    public let schema: String
    public let schemaVersion: String
    /// Always true: every artifact carrying this record is a derived
    /// convenience output, never canonical capture evidence.
    public let derivedArtifact: Bool
    public let captureSeriesID: CaptureSeriesID
    public let captureRevisionID: CaptureRevisionID
    /// Digest of the finalized bundle this artifact was derived from.
    public let bundleDigest: EvidenceSHA256
    /// Coordinate spaces the exported geometry is expressed in.
    public let sourceCoordinateSpaceIDs: [CoordinateSpaceID]
    public let format: DerivedExportFormat
    public let sourceKind: DerivedExportSourceKind
    public let representation: DerivedExportRepresentation
    public let sourcePayloads: [DerivedExportSourcePayload]
    /// Explicit transform statement, e.g. per-anchor
    /// `T_world_from_anchor` application or "identity".
    public let conversionTransform: String
    /// The coordinate convention the file carries.
    public let coordinateConvention: String
    /// The unit the file expresses — always meters; no rescaling is
    /// applied, which this field records explicitly.
    public let unitConversion: String
    public let exporterName: String
    public let exporterVersion: String
    /// App identity recorded on the source bundle's manifest.
    public let producerApp: BundleAppIdentity?
    public let generatedAtUTC: String

    public init(
        captureSeriesID: CaptureSeriesID,
        captureRevisionID: CaptureRevisionID,
        bundleDigest: EvidenceSHA256,
        sourceCoordinateSpaceIDs: [CoordinateSpaceID],
        format: DerivedExportFormat,
        sourceKind: DerivedExportSourceKind,
        representation: DerivedExportRepresentation,
        sourcePayloads: [DerivedExportSourcePayload],
        conversionTransform: String,
        coordinateConvention: String,
        unitConversion: String,
        exporterName: String = "HTDTCapture derived-export",
        exporterVersion: String = "1.0.0",
        producerApp: BundleAppIdentity? = nil,
        generatedAtUTC: String
    ) {
        self.schema = Self.expectedSchema
        self.schemaVersion = Self.expectedSchemaVersion
        self.derivedArtifact = true
        self.captureSeriesID = captureSeriesID
        self.captureRevisionID = captureRevisionID
        self.bundleDigest = bundleDigest
        self.sourceCoordinateSpaceIDs = sourceCoordinateSpaceIDs
        self.format = format
        self.sourceKind = sourceKind
        self.representation = representation
        self.sourcePayloads = sourcePayloads
        self.conversionTransform = conversionTransform
        self.coordinateConvention = coordinateConvention
        self.unitConversion = unitConversion
        self.exporterName = exporterName
        self.exporterVersion = exporterVersion
        self.producerApp = producerApp
        self.generatedAtUTC = generatedAtUTC
    }

    /// Short single-line summaries used inside the artifact's own
    /// comment/extras block.
    public var commentLines: [String] {
        var lines = [
            "HTDTCapture derived export — not canonical capture evidence",
            "capture_revision_id: \(captureRevisionID)",
            "bundle_digest: \(bundleDigest)",
            "source: \(sourceKind.rawValue) representation: \(representation.rawValue)",
            "coordinate_convention: \(coordinateConvention)",
            "conversion_transform: \(conversionTransform)",
            "unit_conversion: \(unitConversion)",
            "generated_at_utc: \(generatedAtUTC)",
        ]
        for payload in sourcePayloads {
            lines.append("source_payload: \(payload.path) sha256=\(payload.sha256)")
        }
        return lines
    }
}

/// A user-readable derived-export failure. Every case carries a reason
/// the UI can show verbatim.
public enum DerivedExportError: Error, Sendable, Equatable {
    /// The requested source payload is absent from the bundle.
    case sourceUnavailable(reason: String)
    /// The source exists but produced no usable geometry.
    case emptyGeometry(reason: String)
    /// A declared payload is unreadable or fails integrity checks.
    case malformedSource(reason: String)
    /// The format/source combination is not supported.
    case unsupportedCombination(reason: String)
    /// The destination could not be written.
    case writeFailed(reason: String)

    /// The user-facing explanation (English; the UI localizes the
    /// surrounding chrome).
    public var reason: String {
        switch self {
        case .sourceUnavailable(let reason),
             .emptyGeometry(let reason),
             .malformedSource(let reason),
             .unsupportedCombination(let reason),
             .writeFailed(let reason):
            reason
        }
    }
}

/// The files produced by one derived 3D export.
public struct Derived3DExportResult: Sendable, Equatable {
    public let primaryFileURL: URL
    public let provenanceFileURL: URL
    public let provenance: DerivedExportProvenance

    public init(
        primaryFileURL: URL,
        provenanceFileURL: URL,
        provenance: DerivedExportProvenance
    ) {
        self.primaryFileURL = primaryFileURL
        self.provenanceFileURL = provenanceFileURL
        self.provenance = provenance
    }
}
