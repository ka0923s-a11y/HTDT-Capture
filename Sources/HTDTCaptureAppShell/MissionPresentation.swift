import Foundation
import HTDTCaptureCore

/// Operator-facing presentation for the Mission/production surfaces
/// (issue #412): every persisted enum token maps to a localized task
/// label here so `rawValue`/`String(describing:)` never reach normal
/// UX. Technical identifiers (item ids, issue codes, plan refs) stay
/// in secondary Details-style captions. Enum switches carry
/// `@unknown default` so a future case degrades to an explicit
/// "Unknown" label rather than leaking its token.
///
/// Reuse, per the issue: entity/channel-role/quantity names delegate
/// to `AnnotationPresentation` (the #220 mapping the annotation
/// workspace already speaks) and as-built states delegate to
/// `TheaterAuthorityPresentation.asBuiltStateName` (#365), so one
/// operator-facing label exists everywhere.
public enum MissionPresentation {
    // MARK: Task-plan checklist

    public static func taskPlanItemOutcomeName(
        _ outcome: TaskPlanItemOutcome
    ) -> String {
        switch outcome {
        case .pending:
            return String(localized: "Pending")
        case .completed:
            return String(localized: "Completed")
        case .skipped:
            return String(localized: "Skipped")
        case .unavailable:
            return String(localized: "Unavailable")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    public static func taskPlanRequirementName(
        _ requirement: TaskPlanRequirement
    ) -> String {
        switch requirement {
        case .required:
            return String(localized: "Required")
        case .optional:
            return String(localized: "Optional")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    /// Entity checklist title: the plan's `label_hint` wins verbatim
    /// (it is the issuer's own operator text); otherwise compose
    /// "<channel role> <type>" — "Front left speaker" — or the bare
    /// type name when the item carries no role.
    public static func entityTaskTitle(
        _ item: HTDTTaskPlanEntityItem
    ) -> String {
        if let hint = item.labelHint?.trimmingCharacters(
            in: .whitespaces
        ), !hint.isEmpty {
            return hint
        }
        let typeName = AnnotationPresentation.entityTypeName(
            item.entityType
        )
        guard let role = item.channelRole else {
            return typeName
        }
        let roleName = AnnotationPresentation.channelRoleName(role)
        // Subwoofer role names already name the device
        // ("Subwoofer 1 (LFE1)") — composing "… subwoofer" repeats it.
        if item.entityType == .subwoofer {
            return roleName
        }
        return "\(roleName) \(typeName.localizedLowercase)"
    }

    public static func measurementTaskTitle(
        _ item: HTDTTaskPlanMeasurementItem
    ) -> String {
        String(
            format: String(localized: "Measure %@"),
            quantityTypeName(item.quantityType)
        )
    }

    public static func surfaceTaskTitle(
        _ item: HTDTTaskPlanSurfaceItem
    ) -> String {
        String(
            format: String(localized: "Review %@"),
            tokenText(item.surfaceKind)
        )
    }

    /// `quantity_type` is an open string in the schema: the standard
    /// `MeasurementQuantityRegistry` tokens get real names; anything
    /// else is humanized (`floor_to_ceiling` → "floor to ceiling")
    /// rather than shown as a raw token.
    public static func quantityTypeName(
        _ quantityType: String
    ) -> String {
        switch quantityType {
        case "room_width":
            return String(localized: "Room width")
        case "room_length":
            return String(localized: "Room length")
        case "room_height":
            return String(localized: "Room height")
        case "screen_width":
            return String(localized: "Screen width")
        case "screen_height":
            return String(localized: "Screen height")
        case "screen_diagonal":
            return String(localized: "Screen diagonal")
        case "speaker_distance":
            return String(localized: "Speaker distance")
        case "speaker_spacing":
            return String(localized: "Speaker spacing")
        case "speaker_to_mlp":
            return String(localized: "Speaker-to-seat distance")
        case "listener_distance":
            return String(localized: "Listener distance")
        case "endpoint_distance":
            return String(localized: "Endpoint distance")
        case "displacement":
            return String(localized: "Displacement")
        case "azimuth":
            return String(localized: "Azimuth")
        case "signal_delay":
            return String(localized: "Signal delay")
        case "air_temperature":
            return String(localized: "Air temperature")
        case "relative_humidity":
            return String(localized: "Relative humidity")
        case "spl":
            return String(localized: "Sound level")
        case "rt60":
            return String(localized: "Reverberation time (RT60)")
        default:
            return tokenText(quantityType)
        }
    }

    /// Humanize an open schema token (`snake_case` → words). Used for
    /// `surface_kind` and any unregistered `quantity_type`.
    public static func tokenText(_ token: String) -> String {
        token.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: Connected regions

    public static func regionKindName(
        _ kind: CaptureRegionKind
    ) -> String {
        switch kind {
        case .room:
            return String(localized: "Room")
        case .openPlanArea:
            return String(localized: "Open-plan area")
        case .hallway:
            return String(localized: "Hallway")
        case .stairwell:
            return String(localized: "Stairwell")
        case .alcove:
            return String(localized: "Alcove")
        case .other:
            return String(localized: "Other")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    public static func portalKindName(
        _ kind: CapturePortalKind
    ) -> String {
        switch kind {
        case .doorway:
            return String(localized: "Doorway")
        case .openPassage:
            return String(localized: "Open passage")
        case .stairOpening:
            return String(localized: "Stair opening")
        case .other:
            return String(localized: "Other")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    // MARK: Repair tasks

    /// Operator task title for an HTDT repair instruction: what to do,
    /// not the persisted `semantic_correction`-style token.
    public static func repairTaskKindName(
        _ kind: RepairTaskKind
    ) -> String {
        switch kind {
        case .semanticCorrection:
            return String(localized: "Correct details")
        case .sameCoordinateEvidence:
            return String(localized: "Add evidence in place")
        case .freshRescan:
            return String(localized: "Re-scan")
        case .externalMeasurement:
            return String(localized: "Instrument reading")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    // MARK: Mission inbox & deliveries

    public static func missionKindName(
        _ kind: HTDTMissionKind
    ) -> String {
        switch kind {
        case .initialSurvey:
            return String(localized: "Initial survey")
        case .followUp:
            return String(localized: "Follow-up")
        case .repair:
            return String(localized: "Repair")
        case .commissioning:
            return String(localized: "Commissioning")
        case .other:
            return String(localized: "Other")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    public static func missionLifecycleName(
        _ lifecycle: HTDTMissionLifecycle
    ) -> String {
        switch lifecycle {
        case .received:
            return String(localized: "Received")
        case .ready:
            return String(localized: "Ready")
        case .blockedDependency:
            return String(localized: "Blocked")
        case .inProgress:
            return String(localized: "In progress")
        case .fieldCaptureCompleted:
            return String(localized: "Field capture completed")
        case .finalized:
            return String(localized: "Finalized")
        case .delivered:
            return String(localized: "Delivered")
        case .needsFollowUp:
            return String(localized: "Needs follow-up")
        case .completed:
            return String(localized: "Completed")
        case .superseded:
            return String(localized: "Superseded")
        case .archived:
            return String(localized: "Archived")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    public static func deliveryJobStateName(
        _ state: HTDTDeliveryJobState
    ) -> String {
        switch state {
        case .queued:
            return String(localized: "Queued")
        case .sending:
            return String(localized: "Sending")
        case .retryWait:
            return String(localized: "Waiting to retry")
        case .paused:
            return String(localized: "Paused")
        case .blocked:
            return String(localized: "Blocked")
        case .deliveredStaged:
            return String(localized: "Delivered (staged)")
        case .rejected:
            return String(localized: "Rejected")
        case .cancelled:
            return String(localized: "Cancelled")
        case .failed:
            return String(localized: "Failed")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    public static func missionDependencyKindName(
        _ kind: HTDTMissionDependency.Kind
    ) -> String {
        switch kind {
        case .missionCompleted:
            return String(localized: "Mission completed")
        case .captureFinalized:
            return String(localized: "Capture finalized")
        case .captureDelivered:
            return String(localized: "Capture delivered")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    /// Human lead for a failed dependency evaluation — the raw error
    /// text stays visible as the section's small Details line.
    public static var dependencyCheckFailedText: String {
        String(
            localized:
                "Could not check this mission's requirements."
        )
    }

    /// Pairing-sheet errors in operator language; unknown errors keep
    /// a bounded technical description for support diagnosis.
    public static func pairingErrorText(_ error: Error) -> String {
        if let pairingError = error as? HTDTPairingError {
            switch pairingError {
            case .invalidPairingPayload(let detail):
                return String(
                    localized:
                        "That is not a receiver pairing payload this app accepts."
                ) + " — " + detail
            case .nonSecureEndpoint:
                return String(
                    localized:
                        "Pairing requires a secure https endpoint — plain http is refused."
                )
            case .invalidPinnedIdentity:
                return String(
                    localized:
                        "The payload's pinned identity is not a valid sha256 digest."
                )
            case .pairingPayloadExpired:
                return String(
                    localized:
                        "This pairing payload has expired — get a fresh code from the receiver."
                )
            case .unknownDestination(let detail):
                return String(
                    localized:
                        "No paired receiver matches that destination."
                ) + " — " + detail
            case .unreadableDocument:
                return String(
                    localized:
                        "The stored destination document could not be read."
                )
            @unknown default:
                return String(describing: error)
            }
        }
        return String(describing: error)
    }

    // MARK: Shared annotation identities + repair flags

    /// Entity-type names shared with the annotation workspace — the
    /// same vocabulary everywhere the operator sees an entity kind.
    public static func annotationEntityTypeName(
        _ type: AnnotationEntityType
    ) -> String {
        AnnotationPresentation.entityTypeName(type)
    }

    /// Channel-role names shared with the annotation workspace
    /// ("Front left", "Subwoofer 1 (LFE1)").
    public static func channelRoleName(_ role: ChannelRole) -> String {
        AnnotationPresentation.channelRoleName(role)
    }

    /// Canonical English display names the built-in layout profiles
    /// ship — kept for comparing a plan-supplied `displayName` against
    /// the role's own vocabulary.
    private static let canonicalRoleEnglishNames: [String: String] = [
        "L": "Front left", "C": "Center", "R": "Front right",
        "SL": "Surround left", "SR": "Surround right",
        "SBL": "Surround back left", "SBR": "Surround back right",
        "TFL": "Top front left", "TFR": "Top front right",
        "TML": "Top middle left", "TMR": "Top middle right",
        "TRL": "Top rear left", "TRR": "Top rear right",
        "LFE": "Subwoofer",
        "LFE1": "Subwoofer 1", "LFE2": "Subwoofer 2",
        "LFE3": "Subwoofer 3", "LFE4": "Subwoofer 4",
    ]

    /// Localized display name for a speaker-layout role: a genuinely
    /// custom plan-supplied name is honored, but a `displayName` that
    /// merely echoes the channel token ("SL") or the built-in English
    /// name swaps to the localized channel-role vocabulary — raw role
    /// IDs never surface as UI text.
    public static func layoutRoleDisplayName(
        _ role: SpeakerLayoutRole
    ) -> String {
        if role.displayName == role.channelRole.rawValue
            || canonicalRoleEnglishNames[role.channelRole.rawValue]
                == role.displayName {
            return channelRoleName(role.channelRole)
        }
        return role.displayName
    }

    public static func listeningPositionRoleName(
        _ role: ListeningPositionRole
    ) -> String {
        switch role {
        case .primary:
            return String(localized: "Primary (MLP)")
        case .secondary:
            return String(localized: "Secondary")
        case .measurementReference:
            return String(localized: "Measurement reference")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    /// `ReferencePointSemantics` is an open snake_case token — the
    /// catalog's well-known tokens get names, anything else degrades
    /// to humanized words rather than the raw token.
    public static func referencePointSemanticsName(
        _ semantics: ReferencePointSemantics
    ) -> String {
        switch semantics {
        case .cabinetReferencePoint:
            return String(localized: "Cabinet reference point")
        case .acousticCenter:
            return String(localized: "Acoustic center")
        case .earCenter:
            return String(localized: "Ear center")
        case .screenCenter:
            return String(localized: "Screen center")
        case .displayCenter:
            return String(localized: "Display center")
        case .seatReferencePoint:
            return String(localized: "Seat reference point")
        case .userReferencePoint:
            return String(localized: "User reference point")
        case .projectorBodyReference:
            return String(localized: "Projector body reference")
        case .projectorLensCenter:
            return String(localized: "Projector lens center")
        case .microphoneCapsule:
            return String(localized: "Microphone capsule")
        default:
            return tokenText(semantics.rawValue)
        }
    }

    /// Caption describing what each reference-point semantics choice
    /// anchors the item's semantic position to (#291).
    public static func referencePointSemanticsDescription(
        _ semantics: ReferencePointSemantics
    ) -> String {
        switch semantics {
        case .cabinetReferencePoint:
            return String(localized:
                "The reference point on the equipment's cabinet or body.")
        case .acousticCenter:
            return String(localized:
                "The driver's acoustic center — the point sound radiates from.")
        case .earCenter:
            return String(localized:
                "The listener's ear position.")
        case .screenCenter:
            return String(localized:
                "The center of the projection surface.")
        case .displayCenter:
            return String(localized:
                "The center of the display surface.")
        case .seatReferencePoint:
            return String(localized:
                "The reference point on the seat.")
        case .userReferencePoint:
            return String(localized:
                "A user-defined reference point on the item.")
        case .projectorBodyReference:
            return String(localized:
                "The projector cabinet's reference point — distinct from the lens center.")
        case .projectorLensCenter:
            return String(localized:
                "The center of the projection lens.")
        case .microphoneCapsule:
            return String(localized:
                "The microphone capsule's pickup position.")
        default:
            return String(localized:
                "A semantics token recorded verbatim.")
        }
    }

    /// Stored `MeasurementUnit` rawValues are canonical symbols
    /// ("m", "degC", "1") — the picker shows the conventional glyph
    /// instead (`°C`, `dimensionless`).
    public static func measurementUnitSymbol(
        _ unit: MeasurementUnit
    ) -> String {
        switch unit {
        case .meter:
            return String(localized: "m")
        case .radian:
            return String(localized: "rad")
        case .second:
            return String(localized: "s")
        case .degreeCelsius:
            return String(localized: "°C")
        case .percent:
            return String(localized: "%")
        case .dimensionless:
            return String(localized: "dimensionless")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    /// Localized name for an evidence frame's retention reason — the
    /// rawValue tokens ("end_boundary", "linked_to_authority", …) are
    /// storage identifiers and are never shown verbatim.
    public static func retentionReasonName(
        _ reason: EvidenceRetentionReason
    ) -> String {
        switch reason {
        case .endBoundary:
            return String(localized: "End boundary")
        case .linkedToAuthority:
            return String(localized: "Referenced")
        case .automaticKeyframe:
            return String(localized: "Auto keyframe")
        case .operatorSaved:
            return String(localized: "Operator saved")
        @unknown default:
            return String(localized: "Retained")
        }
    }

    public static func scanRevisitFlagStatusName(
        _ status: ScanRevisitFlagStatus
    ) -> String {
        switch status {
        case .unresolved:
            return String(localized: "Unresolved")
        case .resolved:
            return String(localized: "Resolved")
        case .skipped:
            return String(localized: "Skipped")
        case .unavailable:
            return String(localized: "Unavailable")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    /// Caption describing what each region kind means in the survey
    /// — the option detail under the region-kind picker.
    public static func regionKindDescription(
        _ kind: CaptureRegionKind
    ) -> String {
        switch kind {
        case .room:
            return String(localized:
                "A distinct enclosed room or compartment.")
        case .openPlanArea:
            return String(localized:
                "One zone of a continuous space not divided by walls.")
        case .hallway:
            return String(localized:
                "A connecting corridor or passage.")
        case .stairwell:
            return String(localized:
                "A stair run and its surrounding volume.")
        case .alcove:
            return String(localized:
                "A small recessed area off a larger space.")
        case .other:
            return String(localized:
                "A region kind not covered above.")
        @unknown default:
            return String(localized:
                "A region kind not covered above.")
        }
    }

    /// Localized name for a revisit-flag category — the shared label
    /// used by both the scanning HUD picker and the review list.
    public static func scanRevisitFlagCategoryName(
        _ category: ScanRevisitFlagCategory
    ) -> String {
        switch category {
        case .geometry:
            return String(localized: "Geometry")
        case .opening:
            return String(localized: "Opening")
        case .reflectiveTransparent:
            return String(localized: "Reflective / transparent")
        case .objectDetail:
            return String(localized: "Object detail")
        case .measurement:
            return String(localized: "Measurement")
        case .equipment:
            return String(localized: "Equipment")
        case .other:
            return String(localized: "Other")
        @unknown default:
            return String(localized: "Other")
        }
    }

    /// Caption describing which sites belong in each revisit-flag
    /// category — the option detail under the flag-category picker.
    public static func scanRevisitFlagCategoryDescription(
        _ category: ScanRevisitFlagCategory
    ) -> String {
        switch category {
        case .geometry:
            return String(localized:
                "A spot where walls or surfaces look wrong or uncertain.")
        case .opening:
            return String(localized:
                "A door, window, or opening whose detection is doubtful.")
        case .reflectiveTransparent:
            return String(localized:
                "Mirrors, glass, or glossy finishes the sensor struggles with.")
        case .objectDetail:
            return String(localized:
                "A spot where furniture or object detail is missing.")
        case .measurement:
            return String(localized:
                "A spot that still needs a manual measurement.")
        case .equipment:
            return String(localized:
                "A spot where equipment must be recorded later.")
        case .other:
            return String(localized:
                "Anything else worth revisiting.")
        @unknown default:
            return String(localized:
                "Anything else worth revisiting.")
        }
    }
}
