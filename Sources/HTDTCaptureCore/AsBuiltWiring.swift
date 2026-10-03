import Foundation

public struct WiringRouteID: CaptureIdentifier {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
}

/// The physical endpoint kind a wiring route terminates at (issue
/// legacy bolph71656-ai/HTDT-Capture#324). Enumerated machine semantics — speaker/subwoofer, the
/// electronics chain, rack/wall-plate termination hardware, or a
/// user-defined service point — never a display label.
public enum WiringTerminationKind: String, Codable, Sendable,
    CaseIterable
{
    case speaker
    case subwoofer
    case avReceiver = "av_receiver"
    case processor
    case amplifier
    case projector
    case display
    case rack
    case wallPlate = "wall_plate"
    case servicePoint = "service_point"
    case other
}

/// One exact physical termination endpoint of a cable route (issue
/// legacy bolph71656-ai/HTDT-Capture#324). An endpoint is identified by at least one of: an exact
/// `binding_ref` to a committed authority (`entity:<uuid>`,
/// `inventory_item:<uuid>`, `equipment:<id>`), a captured world-space
/// position (`world_from_endpoint` + `coordinate_space_id`), or an
/// operator label for a user-defined service point. `connector_label`
/// names the physical connector/port on the endpoint distinctly from
/// the endpoint itself.
public struct WiringTermination: Codable, Sendable, Equatable {
    public let kind: WiringTerminationKind
    /// Human label for the endpoint ("rack panel A", "wall plate 3").
    public let label: String?
    /// Binding ref to the authority this endpoint is part of.
    public let bindingRef: String?
    /// The connector/port on the endpoint the cable actually
    /// terminates at ("speaker L +", "AVR pre-out 2").
    public let connectorLabel: String?
    /// Captured world-space transform of the termination point —
    /// distinct from any bound entity's center. Requires
    /// `coordinate_space_id`.
    public let coordinateSpaceID: CoordinateSpaceID?
    public let worldFromEndpoint: Matrix4x4F?

    public init(
        kind: WiringTerminationKind,
        label: String? = nil,
        bindingRef: String? = nil,
        connectorLabel: String? = nil,
        coordinateSpaceID: CoordinateSpaceID? = nil,
        worldFromEndpoint: Matrix4x4F? = nil
    ) throws {
        let normalizedLabel = SchemaOwnedText.nfc(label)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBinding = SchemaOwnedText.nfc(bindingRef)
        if let binding = normalizedBinding {
            guard FieldAuthorityGrammar.isBindingRef(binding) else {
                throw FieldAuthorityModelError
                    .unboundReference(binding)
            }
        }
        // A captured position requires its coordinate space; the pair
        // is always present or both absent.
        guard (coordinateSpaceID != nil) == (worldFromEndpoint != nil)
        else {
            throw FieldAuthorityModelError.endpointConflict
        }
        // An endpoint must be identifiable: bound to an authority, a
        // captured position, or an explicit operator label.
        guard normalizedBinding != nil
                || worldFromEndpoint != nil
                || normalizedLabel?.isEmpty == false
        else {
            throw FieldAuthorityModelError.endpointConflict
        }
        self.kind = kind
        self.label = normalizedLabel?.isEmpty == true
            ? nil : normalizedLabel
        self.bindingRef = normalizedBinding
        self.connectorLabel = SchemaOwnedText.nfc(connectorLabel)
        self.coordinateSpaceID = coordinateSpaceID
        self.worldFromEndpoint = worldFromEndpoint
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case label
        case bindingRef = "binding_ref"
        case connectorLabel = "connector_label"
        case coordinateSpaceID = "coordinate_space_id"
        case worldFromEndpoint = "T_world_from_endpoint"
    }
}

/// How a route segment's geometry was obtained (issue bolph71656-ai/HTDT-Capture#324). The
/// observed/estimated/hidden-unknown split is explicit:
/// `hidden_unknown` sections are *known to be unknown* — concealed
/// in-wall paths the operator cannot see — and never carry waypoints.
public enum WiringSegmentObservation: String, Codable, Sendable {
    /// The operator physically saw this segment's course.
    case observed
    /// A best-estimate path between observed points (visible ends,
    /// inferred run) recorded as estimate — never as observation.
    case estimated
    /// Concealed path (in-wall, behind ceiling) the operator did not
    /// see. Must not carry waypoints or a surface binding: recording
    /// geometry here would fabricate the hidden course.
    case hiddenUnknown = "hidden_unknown"
}

/// One ordered segment of a wiring route (issue bolph71656-ai/HTDT-Capture#324). `waypoints` is
/// the operator-authored polyline in the capture coordinate space
/// (captured per point with the reticle or entered as a top-down X/Z
/// course); a `surface_ref` may associate the segment with a surface
/// authority it runs along.
public struct WiringSegment: Codable, Sendable, Equatable {
    /// Position of this segment in the route order (0-based).
    public let order: Int
    public let observation: WiringSegmentObservation
    /// Operator-authored polyline vertices in capture space.
    public let waypoints: [SpatialVector3F]
    /// Optional binding ref (`surface:`/`mesh_anchor:`/`entity:`) of
    /// the surface authority this segment runs along.
    public let surfaceRef: String?
    public let evidenceRefs: [String]

    public init(
        order: Int,
        observation: WiringSegmentObservation,
        waypoints: [SpatialVector3F] = [],
        surfaceRef: String? = nil,
        evidenceRefs: [String] = []
    ) throws {
        guard order >= 0 else {
            throw FieldAuthorityModelError.hiddenPathGuess
        }
        let normalizedSurface = SchemaOwnedText.nfc(surfaceRef)
        if let surface = normalizedSurface {
            guard FieldAuthorityGrammar.isBindingRef(surface) else {
                throw FieldAuthorityModelError
                    .unboundReference(surface)
            }
        }
        // Hidden sections are declared unknown, not guessed: they must
        // not carry operator geometry or a claimed surface course.
        if observation == .hiddenUnknown {
            guard waypoints.isEmpty, normalizedSurface == nil else {
                throw FieldAuthorityModelError.hiddenPathGuess
            }
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy(
            FieldAuthorityGrammar.isEvidenceRef
        ) else {
            throw FieldAuthorityModelError
                .unboundReference("evidence_refs")
        }
        self.order = order
        self.observation = observation
        self.waypoints = waypoints
        self.surfaceRef = normalizedSurface
        self.evidenceRefs = normalizedEvidence.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case order
        case observation
        case waypoints
        case surfaceRef = "surface_ref"
        case evidenceRefs = "evidence_refs"
    }
}

/// Recording state of a route (issue bolph71656-ai/HTDT-Capture#324): `planned` intent,
/// `estimated` from partial observation, or `observed_as_built` for
/// the physically verified install. A planned route and its as-built
/// counterpart are separate records sharing endpoints — both histories
/// are preserved rather than overwriting one another.
public enum WiringRouteState: String, Codable, Sendable, CaseIterable {
    case planned
    case estimated
    case observedAsBuilt = "observed_as_built"
}

/// One cable/termination route between two exact endpoints (issue
/// legacy bolph71656-ai/HTDT-Capture#324). Wire centerline is the ordered `segments` polyline between
/// `endpoint_a` and `endpoint_b`; lengths distinguish measured
/// (observed) from estimated slack/service-loop values so they are
/// never conflated. This record never claims knowledge of concealed
/// runs: hidden sections stay `hidden_unknown`, and planned paths are
/// never copied into `observed` segments.
public struct AsBuiltWiringRoute: Codable, Sendable, Equatable {
    public let routeID: WiringRouteID
    public let captureRevisionID: CaptureRevisionID
    /// Cable type token (`speaker_wire`, `hdmi`, `rca`, `xlr`, ...).
    public let cableType: String
    /// Optional service/use token (`front_l`, `sub_1`, `projector`).
    public let serviceType: String?
    public let state: WiringRouteState
    public let endpointA: WiringTermination
    public let endpointB: WiringTermination
    public let segments: [WiringSegment]
    /// Physically measured route length, when measured.
    public let observedLengthM: Double?
    /// Estimated route length, when only estimated.
    public let estimatedLengthM: Double?
    /// Slack/service-loop allowance recorded separately.
    public let serviceLoopLengthM: Double?
    public let evidenceRefs: [String]
    public let notes: String?
    public let operatorID: OperatorProfileID?
    public let recordedAtUTC: String

    public init(
        routeID: WiringRouteID = WiringRouteID(),
        captureRevisionID: CaptureRevisionID,
        cableType: String,
        serviceType: String? = nil,
        state: WiringRouteState,
        endpointA: WiringTermination,
        endpointB: WiringTermination,
        segments: [WiringSegment] = [],
        observedLengthM: Double? = nil,
        estimatedLengthM: Double? = nil,
        serviceLoopLengthM: Double? = nil,
        evidenceRefs: [String] = [],
        notes: String? = nil,
        operatorID: OperatorProfileID? = nil,
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let normalizedCable = SchemaOwnedText.nfc(cableType)
        guard FieldAuthorityGrammar.isLowercaseToken(normalizedCable)
        else {
            throw FieldAuthorityModelError.invalidToken(cableType)
        }
        let normalizedService = SchemaOwnedText.nfc(serviceType)
        if let service = normalizedService {
            guard FieldAuthorityGrammar.isLowercaseToken(service) else {
                throw FieldAuthorityModelError.invalidToken(service)
            }
        }
        // Two distinct physical endpoints: identical endpoints carry no
        // route information and are a recording error.
        guard endpointA != endpointB else {
            throw FieldAuthorityModelError.endpointConflict
        }
        // Segment order must be a dense 0..n sequence so the polyline
        // is unambiguous.
        let orders = segments.map(\.order).sorted()
        guard orders == Array(0 ..< orders.count) else {
            throw FieldAuthorityModelError.hiddenPathGuess
        }
        if state == .observedAsBuilt {
            // As-built authority requires at least one physically
            // observed portion; an entirely estimated/hidden route is
            // recorded `estimated`, never `observed_as_built`.
            guard segments.contains(where: {
                $0.observation == .observed
            }) else {
                throw FieldAuthorityModelError.attestationRequired
            }
        }
        for length in [
            observedLengthM, estimatedLengthM, serviceLoopLengthM,
        ] {
            if let length {
                guard length.isFinite, length >= 0 else {
                    throw FieldAuthorityModelError.invalidObservedValue
                }
            }
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        let normalizedEvidence = SchemaOwnedText.nfc(evidenceRefs)
        guard normalizedEvidence.allSatisfy(
            FieldAuthorityGrammar.isEvidenceRef
        ) else {
            throw FieldAuthorityModelError
                .unboundReference("evidence_refs")
        }

        self.routeID = routeID
        self.captureRevisionID = captureRevisionID
        self.cableType = normalizedCable
        self.serviceType = normalizedService
        self.state = state
        self.endpointA = endpointA
        self.endpointB = endpointB
        self.segments = segments.sorted { $0.order < $1.order }
        self.observedLengthM = observedLengthM
        self.estimatedLengthM = estimatedLengthM
        self.serviceLoopLengthM = serviceLoopLengthM
        self.evidenceRefs = normalizedEvidence.sorted()
        self.notes = SchemaOwnedText.nfc(notes)
        self.operatorID = operatorID
        self.recordedAtUTC = recordedAtUTC
    }

    private enum CodingKeys: String, CodingKey {
        case routeID = "route_id"
        case captureRevisionID = "capture_revision_id"
        case cableType = "cable_type"
        case serviceType = "service_type"
        case state
        case endpointA = "endpoint_a"
        case endpointB = "endpoint_b"
        case segments
        case observedLengthM = "observed_length_m"
        case estimatedLengthM = "estimated_length_m"
        case serviceLoopLengthM = "service_loop_length_m"
        case evidenceRefs = "evidence_refs"
        case notes
        case operatorID = "operator_id"
        case recordedAtUTC = "recorded_at_utc"
    }
}

/// The derived `derived/wiring-routes.json` payload (issue bolph71656-ai/HTDT-Capture#324):
/// every recorded cable route for the revision. Logical HTDT routing
/// is a separate concern — this is the physical wiring record only.
public struct AsBuiltWiringDocument: Codable, Sendable, Equatable {
    public static let schema = "htdt.capture.wiring-routes"
    public static let schemaVersion = "1.0.0"

    public let schemaName: String
    public let schemaVersionValue: String
    public let captureRevisionID: CaptureRevisionID
    public let recordedAtUTC: String
    public let routes: [AsBuiltWiringRoute]

    public init(
        captureRevisionID: CaptureRevisionID,
        routes: [AsBuiltWiringRoute],
        recordedAtUTC: String = BundleTimestamp.utcString(from: Date())
    ) throws {
        let ids = routes.map(\.routeID)
        guard Set(ids).count == ids.count else {
            throw FieldAuthorityModelError.duplicateRecord("route_id")
        }
        guard routes.allSatisfy({
            $0.captureRevisionID == captureRevisionID
        }) else {
            throw FieldAuthorityModelError
                .unboundReference("capture_revision_id")
        }
        guard SchemaTimestampText.isUTCTimestamp(recordedAtUTC) else {
            throw FieldAuthorityModelError
                .invalidTimestamp(recordedAtUTC)
        }
        self.schemaName = Self.schema
        self.schemaVersionValue = Self.schemaVersion
        self.captureRevisionID = captureRevisionID
        self.recordedAtUTC = recordedAtUTC
        self.routes = routes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaName = "schema"
        case schemaVersionValue = "schema_version"
        case captureRevisionID = "capture_revision_id"
        case recordedAtUTC = "recorded_at_utc"
        case routes
    }
}

/// Encoded `AsBuiltWiringDocument` ready for the working-set store.
public struct AsBuiltWiringPackage: Sendable, Equatable {
    public static let path = "derived/wiring-routes.json"
    public static let sourceRef = "path:" + path

    public let document: AsBuiltWiringDocument
    public let data: Data
    public let sourceRefs: [String]

    public init(document: AsBuiltWiringDocument) throws {
        var refs = Set<String>()
        for route in document.routes {
            for endpoint in [route.endpointA, route.endpointB] {
                if let binding = endpoint.bindingRef {
                    if binding.hasPrefix("entity:") {
                        refs.insert(
                            "path:" + AnnotationEvidencePackage.path
                        )
                    } else if binding.hasPrefix("inventory_item:") {
                        refs.insert(
                            "path:" + TheaterAuthorityPackage.path
                        )
                    }
                }
            }
            for ref in route.evidenceRefs
                + route.segments.flatMap(\.evidenceRefs)
            where ref.hasPrefix("path:") || ref.hasPrefix("frame:")
            {
                if ref.hasPrefix("frame:") {
                    refs.insert(
                        "path:evidence/frames/"
                            + ref.dropFirst("frame:".count) + ".json"
                    )
                } else {
                    refs.insert(ref)
                }
            }
            if route.operatorID != nil {
                refs.insert("path:" + OperatorProfilePackage.path)
            }
        }
        if refs.isEmpty {
            refs.insert("path:session/capture-session.json")
        }
        self.document = document
        self.sourceRefs = refs.sorted()
        self.data = try FieldAuthorityCoding.encoder()
            .encode(document)
    }
}
