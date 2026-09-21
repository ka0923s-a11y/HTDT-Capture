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
            return role.rawValue
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
        return String(describing: error)
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
