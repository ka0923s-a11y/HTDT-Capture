import Foundation
import SwiftUI
import HTDTCaptureCore

/// Localized presentation helpers for the annotation workspace (#220).
/// Canonical tokens never reach the operator: every schema enum and
/// authority error maps to a task-level label in the current locale.
enum AnnotationPresentation {
    // MARK: Entity types

    static func entityTypeName(
        _ type: AnnotationEntityType
    ) -> String {
        switch type {
        case .speaker:
            return String(localized: "Speaker")
        case .subwoofer:
            return String(localized: "Subwoofer")
        case .display:
            return String(localized: "Display")
        case .projectionScreen:
            return String(localized: "Projection screen")
        case .projector:
            return String(localized: "Projector")
        case .listeningPosition:
            return String(localized: "Listening position")
        case .seat:
            return String(localized: "Seat")
        case .acousticTreatment:
            return String(localized: "Acoustic treatment")
        case .equipmentRack:
            return String(localized: "Equipment rack")
        case .referencePoint:
            return String(localized: "Reference point")
        case .measurementPoint:
            return String(localized: "Measurement point")
        case .custom:
            return String(localized: "Custom")
        }
    }

    /// The annotation templates the primary picker offers (#220). A
    /// template is just a type + sensible label default; `.custom`
    /// stays the advanced escape hatch.
    static var entityTemplates: [AnnotationEntityType] {
        [
            .listeningPosition,
            .speaker,
            .subwoofer,
            .display,
            .projectionScreen,
            .projector,
            .seat,
            .equipmentRack,
            .acousticTreatment,
            .referencePoint,
            .measurementPoint,
            .custom,
        ]
    }

    static func defaultLabel(
        for type: AnnotationEntityType
    ) -> String {
        switch type {
        case .listeningPosition: return "MLP"
        case .speaker: return "Speaker"
        case .subwoofer: return "Sub"
        case .display: return "Display"
        case .projectionScreen: return "Screen"
        case .projector: return "Projector"
        case .seat: return "Seat"
        case .equipmentRack: return "Rack"
        case .acousticTreatment: return "Treatment"
        case .referencePoint: return "Reference"
        case .measurementPoint: return "Mic point"
        case .custom: return "Item"
        }
    }

    // MARK: Channel roles

    /// Human name for a standard channel role. The canonical token
    /// (`L`, `C`, …) is still shown in secondary position so exact
    /// semantics stay visible.
    static func channelRoleName(_ role: ChannelRole) -> String {
        switch role {
        case .left:
            return String(localized: "Front left")
        case .center:
            return String(localized: "Center")
        case .right:
            return String(localized: "Front right")
        case .surroundLeft:
            return String(localized: "Surround left")
        case .surroundRight:
            return String(localized: "Surround right")
        case .surroundBackLeft:
            return String(localized: "Surround back left")
        case .surroundBackRight:
            return String(localized: "Surround back right")
        case .topFrontLeft:
            return String(localized: "Top front left")
        case .topFrontRight:
            return String(localized: "Top front right")
        case .topMiddleLeft:
            return String(localized: "Top middle left")
        case .topMiddleRight:
            return String(localized: "Top middle right")
        case .topRearLeft:
            return String(localized: "Top rear left")
        case .topRearRight:
            return String(localized: "Top rear right")
        case .lfe:
            return String(localized: "Subwoofer (LFE)")
        case .lfe1:
            return String(localized: "Subwoofer 1 (LFE1)")
        case .lfe2:
            return String(localized: "Subwoofer 2 (LFE2)")
        case .lfe3:
            return String(localized: "Subwoofer 3 (LFE3)")
        case .lfe4:
            return String(localized: "Subwoofer 4 (LFE4)")
        default:
            return MissionPresentation.tokenText(role.rawValue)
        }
    }

    /// Localized name for a typed listening-position role (#243).
    static func listeningRoleName(
        _ role: ListeningPositionRole
    ) -> String {
        switch role {
        case .primary:
            return String(localized: "Primary (MLP)")
        case .secondary:
            return String(localized: "Secondary")
        case .measurementReference:
            return String(localized: "Measurement reference")
        }
    }

    // MARK: Measurements

    /// Common measurement tasks offered as templates (#220); each maps
    /// to the canonical quantity token written into the record.
    struct MeasurementTemplate:
        Identifiable, Equatable, Sendable
    {
        let id: String
        let title: String
        let quantityType: String
        let unit: MeasurementUnit
    }

    static var measurementTemplates: [MeasurementTemplate] {
        [
            MeasurementTemplate(
                id: "room_width",
                title: String(localized: "Room width"),
                quantityType: "room_width",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "room_length",
                title: String(localized: "Room length"),
                quantityType: "room_length",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "room_height",
                title: String(localized: "Room height"),
                quantityType: "room_height",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "screen_width",
                title: String(localized: "Screen width"),
                quantityType: "screen_width",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "screen_height",
                title: String(localized: "Screen height"),
                quantityType: "screen_height",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "speaker_to_mlp",
                title: String(localized: "Speaker-to-seat distance"),
                quantityType: "speaker_to_mlp",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "speaker_spacing",
                title: String(localized: "Speaker spacing"),
                quantityType: "speaker_spacing",
                unit: .meter
            ),
            MeasurementTemplate(
                id: "custom",
                title: String(localized: "Custom measurement"),
                quantityType: "custom",
                unit: .meter
            ),
        ]
    }

    static func measurementTitle(
        forQuantityType quantityType: String
    ) -> String {
        measurementTemplates.first {
            $0.quantityType == quantityType
        }?.title ?? quantityType
    }

    static func unitName(_ unit: MeasurementUnit) -> String {
        switch unit {
        case .meter:
            return String(localized: "meters (m)")
        case .radian:
            return String(localized: "radians (rad)")
        case .dimensionless:
            return String(localized: "unitless")
        case .degreeCelsius:
            return String(localized: "degrees Celsius (°C)")
        case .percent:
            return String(localized: "percent (%)")
        case .second:
            return String(localized: "seconds (s)")
        }
    }

    static func acquisitionMethodName(
        _ method: MeasurementAcquisitionMethod
    ) -> String {
        switch method {
        case .tapeMeasure:
            return String(localized: "Tape measure")
        case .laserDistanceMeter:
            return String(localized: "Laser distance meter")
        case .manufacturerSpecification:
            return String(localized: "Manufacturer specification")
        case .lidarDerived:
            return String(localized: "LiDAR derived")
        case .roomPlanDerived:
            return String(localized: "RoomPlan derived")
        case .externalInstrument:
            return String(localized: "External instrument")
        case .other:
            return String(localized: "Other")
        }
    }

    // MARK: Placement

    static func placementMethodName(
        _ method: PlacementMethod
    ) -> String {
        switch method {
        case .manualNumeric:
            return String(localized: "Manual numeric")
        case .raycast:
            return String(localized: "Camera raycast")
        case .meshHitTest:
            return String(localized: "Scanned surface (mesh)")
        case .roomPlanBinding:
            return String(localized: "RoomPlan object")
        case .importedReference:
            return String(localized: "Imported reference")
        case .other:
            return String(localized: "Other")
        }
    }

    /// Localized name for a measurement's provenance class — never
    /// the raw `user_annotation`/`capture_app_derived` token.
    static func provenanceClassName(
        _ value: AnnotationProvenanceClass
    ) -> String {
        switch value {
        case .userAnnotation:
            return String(localized: "User recorded")
        case .importedReference:
            return String(localized: "Imported reference")
        case .captureAppDerived:
            return String(localized: "App derived")
        }
    }

    /// Localized name for a measurement record's provenance class —
    /// distinct enum from the annotation one, same rule (no raw
    /// `user_attested_measurement`/… tokens).
    static func provenanceClassName(
        _ value: MeasurementProvenanceClass
    ) -> String {
        switch value {
        case .userAttestedMeasurement:
            return String(localized: "User measured")
        case .appleRoomPlanInference:
            return String(localized: "RoomPlan inferred")
        case .arkitMeshReconstruction:
            return String(localized: "ARKit reconstructed")
        case .importedReference:
            return String(localized: "Imported reference")
        case .captureAppDerived:
            return String(localized: "App derived")
        }
    }

    static func probeTargetName(
        _ target: PlacementProbeTarget
    ) -> String {
        switch target {
        case .mesh:
            return String(localized: "scanned surface")
        case .roomPlanObject:
            return String(localized: "recognized object")
        case .existingPlaneGeometry:
            return String(localized: "scanned plane")
        case .estimatedPlane:
            return String(localized: "estimated plane")
        }
    }

    static func probeStatusText(
        _ probe: AnnotationPlacementProbe
    ) -> String {
        switch probe.status {
        case .hit:
            var text = probeTargetName(probe.target ?? .estimatedPlane)
            if let category = probe.roomPlanObjectCategory {
                text += " · " + category
            }
            if let distance = probe.distanceMeters {
                text += String(format:
                    String(localized: " · %.2f m"), Double(distance))
            }
            return text
        case .noHit:
            return String(localized:
                "Nothing under the reticle — aim at a surface")
        case .unavailable:
            return String(localized: "Camera unavailable")
        }
    }

    // MARK: Errors

    /// Maps authority/model errors to task-level guidance (#220) —
    /// what the operator should fix — rather than surfacing Swift type
    /// names. Unknown errors keep a bounded description.
    static func errorText(_ error: Error) -> String {
        if let error = error as? ManualAuthorityBuilderError {
            switch error {
            case .invalidPosition:
                return String(localized:
                    "Position must be three finite numbers in meters.")
            case .invalidSpeakerElevation:
                return String(localized:
                    "Speaker elevation must be a finite number of degrees.")
            case .acousticCenterRequiresLoudspeaker:
                return String(localized:
                    "An acoustic-center offset only applies to speakers and subwoofers.")
            case .invalidSpeakerYaw:
                return String(localized:
                    "Set the speaker facing direction: capture the heading or enter a yaw angle.")
            case .invalidSpeakerChannelRole:
                return String(localized:
                    "Choose a channel role (e.g. L, C, R, SL) for this speaker.")
            case .invalidSubwooferChannelRole:
                return String(localized:
                    "Choose a subwoofer role (e.g. LFE1, LFE2) for this subwoofer.")
            case .invalidOrientationYaw:
                return String(localized:
                    "Enter a finite yaw angle in degrees, or leave it empty.")
            case .orientationNotSupportedForType:
                return String(localized:
                    "This item type cannot carry a facing direction.")
            case .listeningRoleRequired:
                return String(localized:
                    "Choose a listening-position role (primary, secondary, or measurement reference).")
            case .referencePointConstructionRequired:
                return String(localized:
                    "Confirm how the captured point was constructed — pick a reference-point construction.")
            case .pointDirectionUnavailable:
                return String(localized:
                    "Point-direction capture is unavailable without a live camera session.")
            case .derivedAcquisitionNotUserAttestable:
                return String(localized:
                    "Derived acquisition methods are not allowed for manual entries.")
            case .authorityCoordinateSpaceMismatch:
                return String(localized:
                    "The captured evidence belongs to a different coordinate space; recapture it.")
            }
        }
        if let error = error as? AnnotationModelError {
            switch error {
            case .emptyLabel:
                return String(localized: "Enter a label.")
            case .speakerOrientationRequired:
                return String(localized:
                    "Speakers need a facing direction.")
            case .speakerChannelRoleRequired:
                return String(localized:
                    "Speakers need a channel role.")
            default:
                break
            }
        }
        if let error = error as? MeasurementModelError {
            switch error {
            case .emptyQuantityType:
                return String(localized:
                    "Choose a measurement task or enter a quantity type.")
            case .invalidScalar, .invalidVector:
                return String(localized:
                    "Enter a finite numeric value.")
            case .negativeUncertainty:
                return String(localized:
                    "Uncertainty must be a non-negative number.")
            case .userAttestationRequired:
                return String(localized:
                    "This measurement requires explicit attestation.")
            case .missingSpatialCoordinateAuthority:
                return String(localized:
                    "Spatial measurements require coordinate-space authority.")
            default:
                break
            }
        }
        if let error = error as? HTDTFieldReturnError {
            switch error {
            case .missingFulfillmentBasis(let ref):
                return String(localized:
                    "Task \(ref) needs at least one valid fulfilling record.")
            case .missingOutcomeReason(let ref):
                return String(localized:
                    "Task \(ref) needs a reason for that outcome.")
            case .unresolvedFulfillmentRef(let ref):
                return String(localized:
                    "Fulfillment ref \(ref) does not exist in this field return.")
            case .incompatibleFulfillmentRef(let ref):
                return String(localized:
                    "Ref \(ref) cannot fulfill this task — its record type does not match.")
            case .conflictingContributionRef(let ref):
                return String(localized:
                    "Record \(ref) belongs to a different contribution than its document.")
            case .dualOwnerRecord(let ref):
                return String(localized:
                    "Record \(ref) carries two contribution owners — it must carry exactly one.")
            case .incompatibleAuthoritySchema(let ref),
                 .unknownAuthoritySchema(let ref):
                return String(localized:
                    "Authority document \(ref) does not match the schema this contribution expects.")
            default:
                break
            }
        }
        return String(describing: error)
    }

    // MARK: Option descriptions
    //
    // One-line explanations rendered as the caption under each
    // selectable option — a picker never shows a bare label.

    static func entityTypeDescription(
        _ type: AnnotationEntityType
    ) -> String {
        switch type {
        case .listeningPosition:
            return String(localized:
                "Where a listener sits (MLP); the reference point for distances and angles.")
        case .speaker:
            return String(localized:
                "An individual loudspeaker; carries a channel role and facing direction.")
        case .subwoofer:
            return String(localized:
                "A low-frequency loudspeaker; assigned an LFE role.")
        case .display:
            return String(localized:
                "A TV or monitor — the watched video surface.")
        case .projectionScreen:
            return String(localized:
                "The projection surface a projector throws onto.")
        case .projector:
            return String(localized:
                "A video projection unit; mount and focus details matter.")
        case .seat:
            return String(localized:
                "A seat or furniture position other than the MLP.")
        case .acousticTreatment:
            return String(localized:
                "Absorptive or diffusive acoustic treatment on a surface.")
        case .equipmentRack:
            return String(localized:
                "A rack or shelf holding equipment.")
        case .referencePoint:
            return String(localized:
                "An arbitrary point used as a measurement/alignment reference.")
        case .measurementPoint:
            return String(localized:
                "A point where a microphone or instrument takes readings.")
        case .custom:
            return String(localized:
                "Anything not covered above; give it a free-form label.")
        }
    }

    static func channelRoleDescription(
        _ role: ChannelRole
    ) -> String {
        switch role {
        case .left:
            return String(localized:
                "Main front-left loudspeaker position.")
        case .center:
            return String(localized:
                "Center speaker anchored to the screen.")
        case .right:
            return String(localized:
                "Main front-right loudspeaker position.")
        case .surroundLeft:
            return String(localized:
                "Side/rear-left surround speaker position.")
        case .surroundRight:
            return String(localized:
                "Side/rear-right surround speaker position.")
        case .surroundBackLeft:
            return String(localized:
                "Rear-left surround-back speaker position.")
        case .surroundBackRight:
            return String(localized:
                "Rear-right surround-back speaker position.")
        case .topFrontLeft:
            return String(localized:
                "Height speaker, front-left (overhead layer).")
        case .topFrontRight:
            return String(localized:
                "Height speaker, front-right (overhead layer).")
        case .topMiddleLeft:
            return String(localized:
                "Height speaker, middle-left (overhead layer).")
        case .topMiddleRight:
            return String(localized:
                "Height speaker, middle-right (overhead layer).")
        case .topRearLeft:
            return String(localized:
                "Height speaker, rear-left (overhead layer).")
        case .topRearRight:
            return String(localized:
                "Height speaker, rear-right (overhead layer).")
        case .lfe:
            return String(localized:
                "Low-frequency effects channel — use when subs are not numbered.")
        case .lfe1, .lfe2, .lfe3, .lfe4:
            return String(localized:
                "Numbered subwoofer role — distinguishes each sub in a multi-sub layout.")
        default:
            return String(localized:
                "Custom channel token recorded verbatim for equipment-specific wiring.")
        }
    }

    static func listeningRoleDescription(
        _ role: ListeningPositionRole
    ) -> String {
        switch role {
        case .primary:
            return String(localized:
                "Main listening position (MLP) — one per layout; all references anchor here.")
        case .secondary:
            return String(localized:
                "Additional listener position (second row, alternate seat, …).")
        case .measurementReference:
            return String(localized:
                "Position used only as a measurement reference, not a seat.")
        }
    }

    static func verificationStateDescription(
        _ state: AnnotationVerificationState
    ) -> String {
        switch state {
        case .unverified:
            return String(localized:
                "Recorded but not yet backed by confirmation or evidence.")
        case .userAttested:
            return String(localized:
                "The operator confirms this correction is correct.")
        case .evidenceLinked:
            return String(localized:
                "Backed by linked evidence such as a photo or scan frame.")
        }
    }

    static func measurementUnitDescription(
        _ unit: MeasurementUnit
    ) -> String {
        switch unit {
        case .meter:
            return String(localized:
                "Lengths, distances, and coordinates.")
        case .radian:
            return String(localized:
                "Angles — headings, elevations, and subtends.")
        case .dimensionless:
            return String(localized:
                "Ratios and counts with no physical unit.")
        case .second:
            return String(localized:
                "Time values such as delay and decay time.")
        case .degreeCelsius:
            return String(localized: "Temperature.")
        case .percent:
            return String(localized:
                "Fractions such as gain and humidity.")
        }
    }

    static func acquisitionMethodDescription(
        _ method: MeasurementAcquisitionMethod
    ) -> String {
        switch method {
        case .tapeMeasure:
            return String(localized:
                "Read directly off a tape measure on site.")
        case .laserDistanceMeter:
            return String(localized:
                "Point-to-point distance from a laser rangefinder.")
        case .manufacturerSpecification:
            return String(localized:
                "Value taken from the manufacturer's published spec or drawing.")
        case .lidarDerived:
            return String(localized:
                "Computed from the LiDAR scan geometry.")
        case .roomPlanDerived:
            return String(localized:
                "Computed from RoomPlan's detected room structure.")
        case .externalInstrument:
            return String(localized:
                "Reading or file taken from a measurement instrument.")
        case .other:
            return String(localized:
                "Another method — describe it in the note field.")
        }
    }

    static func constructionDescription(
        _ construction: ReferencePointConstruction
    ) -> String {
        switch construction {
        case .surfaceHitConfirmed:
            return String(localized:
                "The camera surface hit itself is the semantic point.")
        case .offsetFromSurface:
            return String(localized:
                "The point is a fixed offset away from a captured surface hit (e.g. ear center above the seat).")
        case .directPlacement:
            return String(localized:
                "The point is placed directly by coordinates or object binding — no surface capture.")
        case .importedReference:
            return String(localized:
                "The point arrives from an imported reference authority.")
        }
    }

    /// Caption under each measurement-template option — what the
    /// template actually measures.
    static func measurementTemplateDescription(
        id: String
    ) -> String {
        switch id {
        case "room_width":
            return String(localized: "Width of the room.")
        case "room_length":
            return String(localized: "Depth (front-to-back) of the room.")
        case "room_height":
            return String(localized: "Floor-to-ceiling height.")
        case "screen_width":
            return String(localized: "Width of the screen or display surface.")
        case "screen_height":
            return String(localized: "Height of the screen or display surface.")
        case "speaker_to_mlp":
            return String(localized:
                "Distance from a speaker to the listening position.")
        case "speaker_spacing":
            return String(localized:
                "Distance between the left and right speakers.")
        default:
            return String(localized:
                "A measurement not covered by the templates; name it yourself.")
        }
    }
}

extension View {
    /// `.inline` navigation-bar title on iOS; a no-op on macOS where
    /// the modifier is unavailable.
    @ViewBuilder func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension View {
    /// Decimal-pad keyboard on iOS; a no-op on macOS where
    /// `keyboardType` is unavailable.
    @ViewBuilder func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
